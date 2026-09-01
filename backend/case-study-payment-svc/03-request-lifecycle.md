# 03 — Request Lifecycle

This doc traces **exactly what happens** when a real HTTP request arrives at this service. We'll walk through two flows: creating an order (simpler) and verifying a payment (more complex).

---

## Flow 1: POST `/payments/orders` (Create Order)

### What the user does

The frontend calls this API when a user clicks "Buy Pro Pack". The request looks like:

```
POST /payments/orders
Headers:
  Authorization: eyJhbG...  (user's JWT token)
  Content-Type: application/json
Body:
  {"package_id": "pro"}
```

### Step-by-step trace

**Step 1 — Uvicorn receives the request**

Uvicorn (the ASGI server) accepts the TCP connection and passes the HTTP request to FastAPI.

**Step 2 — CORS middleware runs**

```python
# app/main.py
app.add_middleware(CORSMiddleware, allow_origins=ALLOWED_ORIGINS, ...)
```

FastAPI checks if the request's `Origin` header is in the allowed list. If not, it blocks the request (this only matters for browser requests, not curl/Postman).

**Step 3 — FastAPI matches the route**

FastAPI looks at `POST /payments/orders` and finds:
```python
# app/routers/payment.py
@router.post("/orders", response_model=CreateOrderResponse)
async def create_order(request: Request, body: CreateOrderRequest):
```

The `prefix="/payments"` was added in `main.py`, so the router only sees `/orders`.

**Step 4 — Pydantic validates the request body**

Before your code runs, FastAPI/Pydantic automatically:
1. Parses the JSON body
2. Checks that `package_id` exists and is a string (as defined in `CreateOrderRequest`)
3. If validation fails, returns `422 Unprocessable Entity` with details — your code never executes

**Step 5 — Router extracts user_id**

```python
user_id = await get_user_id_from_request(request)
```

This function:
1. Checks for `userid` header (some internal services send it directly)
2. If not found, takes the `Authorization` header
3. Calls `common_utils.get_user_id_email_from_token(access_token)`
4. Which makes an **HTTP POST** to `ASTRA_AUTH_URL` (an external auth service)
5. The auth service decodes the JWT and returns `{"user_id": "123", "email": "..."}`

If no token is provided → `HTTPException(401, "Authorization token is required.")`

**Step 6 — Router calls service: get package**

```python
pkg = pay_svc.get_package(body.package_id)
if not pkg:
    raise HTTPException(status_code=404, detail="Package not found or inactive")
```

This is a **pure Python dict lookup** — no database call:
```python
# app/services/payment.py
DEFAULT_PACKAGES = {
    "pro": {"package_id": "pro", "name": "Pro Pack", "credits": 1200, "price_paise": 99900, ...}
}
def get_package(package_id):
    pkg = DEFAULT_PACKAGES.get(package_id)
    return pkg if pkg and pkg["is_active"] else None
```

**Step 7 — Router calls service: create Razorpay order**

```python
rz_order = pay_svc.create_razorpay_order(
    amount_paise=pkg["price_paise"],
    currency=pkg["currency"],
    receipt=f"usr_{user_id}_{body.package_id}",
)
```

This calls the **Razorpay API** via their SDK:
```python
order = rz_client.order.create(data={"amount": 99900, "currency": "INR", ...})
# Returns: {"id": "order_ABC123", "amount": 99900, "status": "created", ...}
```

This is an **HTTP call to Razorpay's servers**. If Razorpay is down, this throws an exception.

**Step 8 — Router calls service: save order to DB**

```python
pay_svc.save_order(
    user_id=user_id,
    razorpay_order_id=rz_order["id"],
    amount=pkg["price_paise"],
    ...
)
```

This runs SQL via `db_utils`:
```sql
INSERT INTO razorpay_orders
    (id, user_id, razorpay_order_id, amount, currency, package_id, credits, status, created_at, updated_at)
VALUES
    (:id, :user_id, :razorpay_order_id, :amount, :currency, :package_id, :credits, :status, :now, :now)
```

The `:id` is a new UUID generated in Python. The status is `"created"`.

**Step 9 — Router builds the response**

```python
return CreateOrderResponse(
    razorpay_order_id=rz_order["id"],
    amount=pkg["price_paise"],
    currency=pkg["currency"],
    ...
)
```

FastAPI serializes this Pydantic model to JSON and sends it back with HTTP 200.

**Step 10 — Frontend uses the response**

The frontend takes `razorpay_order_id` and opens the Razorpay checkout widget. The user enters card/UPI details and pays.

---

## Flow 2: POST `/payments/verify` (Verify Payment)

### What happens

After the user pays in the Razorpay widget, the frontend receives a callback with three values: `razorpay_order_id`, `razorpay_payment_id`, `razorpay_signature`. It sends these to your backend.

### Step-by-step trace

**Step 1-4** — Same as above (uvicorn, CORS, route matching, Pydantic validation of `VerifyPaymentRequest`)

**Step 5 — Verify Razorpay signature (HMAC)**

```python
valid = pay_svc.verify_razorpay_signature(
    body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
)
```

How HMAC verification works:
1. Razorpay and you share a **secret key** (`RAZORPAY_KEY_SECRET`)
2. Razorpay creates: `HMAC-SHA256(order_id|payment_id, secret)` → sends as `signature`
3. Your code creates the same HMAC with the same secret
4. If they match → the data genuinely came from Razorpay (not tampered)

If invalid → `HTTPException(400, "Invalid payment signature")`

**Step 6 — Process payment (the critical function)**

```python
order = pay_svc.process_payment_captured(
    body.razorpay_order_id, body.razorpay_payment_id
)
```

This function does **4 things atomically**:

**6a. Mark order as paid (idempotent)**
```sql
UPDATE razorpay_orders
SET status = 'paid', razorpay_payment_id = :payment_id, updated_at = :now
WHERE razorpay_order_id = :order_id
  AND status IN ('created', 'failed')
RETURNING *
```

The `WHERE status IN ('created', 'failed')` is key — if the order is already `'paid'`, this returns nothing. This prevents double-processing if both `/verify` and the webhook fire.

**6b. Add credits**
```python
new_balance = add_credits(user_id, order["credits"], reason="purchase", reference_id=payment_id)
```

Updates `api_user_credits` table and writes to `razorpay_credit_transactions` ledger.

**6c. Sync LiteLLM budget**
```python
budget_ok = update_litellm_budget(user_id, max_budget=float(new_balance))
```

Makes an HTTP POST to the LiteLLM proxy so the user can actually use their credits for AI inference.

**6d. If LiteLLM fails → auto-refund**

If the budget sync fails, the service automatically:
1. Calls `process_refund()` to reverse the credits and refund via Razorpay
2. Raises `RuntimeError` so the router returns `502`

This is a safety net — the user is never charged without getting usable credits.

**Step 7 — Return response**

```python
return VerifyPaymentResponse(
    verified=True, order_id=order["id"], credits_added=order["credits"],
    new_balance=order["new_balance"], message="Payment verified and credits added"
)
```

---

## Flow 3: POST `/payments/webhook` (Razorpay Webhook)

### Why webhooks exist

What if the user pays but their browser crashes before calling `/verify`? The credits would never be added. Webhooks solve this:

- Razorpay **directly calls your server** when a payment event happens
- This is server-to-server — no browser involved
- Your server processes the event even if the user is offline

### What happens

Razorpay POSTs to your `/payments/webhook` endpoint with:
- Body: JSON event payload (contains payment details)
- Header: `X-Razorpay-Signature` (HMAC of the body)

### Step-by-step

1. **Verify webhook signature** — same HMAC pattern, but using `RAZORPAY_WEBHOOK_SECRET` (different from the client-side key)
2. **Parse the event** — extract `event` type and payment entity from the nested JSON
3. **Handle based on event type:**
   - `payment.captured` → call `process_payment_captured()` (same function as `/verify`)
   - `payment.failed` → mark order as failed in DB
   - `refund.created` → process credit reversal
4. **Return `{"status": "ok"}`** — Razorpay expects a 2xx response; if you return an error, it retries

The same `process_payment_captured()` function handles both `/verify` and webhook — and it's **idempotent** — so if both fire, credits are only added once.

---

## Summary: the mental model

```
Frontend                   Your Backend                 External
────────                   ────────────                 ────────
                           main.py (startup)
Buy click ──────────────→  router (parse, auth)
                           service (get package)
                           service (create order) ───→  Razorpay API
                           service (save to DB) ────→   PostgreSQL
                    ←────  router (respond)

User pays in Razorpay widget ─────────────────────────→ Razorpay

Checkout callback ───────→ router (parse)
                           service (verify HMAC)
                           service (mark paid) ─────→   PostgreSQL
                           service (add credits) ───→   PostgreSQL
                           service (sync budget) ───→   LiteLLM HTTP
                    ←────  router (respond)

(Meanwhile, independently)
Razorpay webhook ────────→ router (verify signature)
                           service (same idempotent flow)
                    ←────  {"status": "ok"}
```

---

## Next doc

→ [04 - Database Guide](./04-database-guide.md) — how data is stored and queried
