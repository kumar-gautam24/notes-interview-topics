# 07 — Debugging Guide

## Local debugging setup

### Running the app for debugging

```bash
export ENVT=DEV
uvicorn app.main:app --reload --port 8002
```

`--reload` makes uvicorn restart automatically when you save a file. Watch the terminal — it shows every request and any errors.

### Using Cursor/VS Code debugger with breakpoints

Create `.vscode/launch.json` (already gitignored):

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "FastAPI Debug",
            "type": "debugpy",
            "request": "launch",
            "module": "uvicorn",
            "args": ["app.main:app", "--reload", "--port", "8002"],
            "env": {"ENVT": "DEV"},
            "jinja": true
        }
    ]
}
```

Now you can:
1. Set breakpoints by clicking in the gutter (left of line numbers)
2. Press F5 to start debugging
3. When a request hits the breakpoint, execution pauses and you can inspect variables

### Using print/logger for quick debugging

```python
from loguru import logger

# In any function:
logger.info(f"user_id = {user_id}")
logger.debug(f"SQL result: {rows}")
logger.error(f"Something failed: {exc}")
```

Output appears in the terminal where uvicorn is running.

---

## Reading logs

### What loguru output looks like

```
2026-04-10 14:23:15.432 | INFO     | app.services.payment:process_payment_captured:144 - Razorpay order created: order_ABC123
2026-04-10 14:23:15.534 | ERROR    | app.services.payment:update_litellm_budget:128 - Failed to update LiteLLM budget for team 123: ConnectionError
```

Format: `timestamp | level | module:function:line - message`

### Key things to watch for

- **INFO** messages — normal flow (order created, credits added, etc.)
- **ERROR** messages — something went wrong (DB connection failed, external API error)
- **WARNING** messages — non-fatal issues (rate limit Redis failed, retrying)
- `traceback.print_exc()` in `db_utils.py` — prints full stack traces for DB errors

---

## Common errors and how to fix them

### Error: App fails to start / connection refused

**Symptom:** App crashes immediately or first request hangs/times out.

**Cause:** Can't reach `DB_HOST`.

**Fix:**
1. Check VPN is connected
2. Test: `ping <DB_HOST>` (use your actual DB_HOST)
3. Test: `psql "postgresql://USER:PASS@HOST:5432/<DB_NAME>"` — does it connect?
4. If still failing, ask team about firewall rules

### Error: `relation "razorpay_orders" does not exist`

**Symptom:** First query to the orders table fails.

**Cause:** Migration hasn't been run on this database.

**Fix:**
```bash
psql "postgresql://USER:PASS@HOST:5432/<DB_NAME>" -f app/migrations/001_payment_tables.sql
```

### Error: `401 Unauthorized`

**Symptom:** Any authenticated endpoint returns 401.

**Cause:** Missing or invalid `Authorization` header, or Astra auth service is unreachable.

**Debug:**
1. Check if you're sending the header: `Authorization: <token>` (no "Bearer " prefix in this codebase)
2. Check if `ASTRA_AUTH_URL` is reachable from your machine
3. Try adding `userid: 123` header directly (bypasses token validation)

### Error: `422 Unprocessable Entity`

**Symptom:** POST request returns 422 with validation details.

**Cause:** Request body doesn't match the Pydantic model.

**Fix:** Read the error detail — it tells you exactly which field is wrong:
```json
{
    "detail": [
        {
            "loc": ["body", "package_id"],
            "msg": "field required",
            "type": "value_error.missing"
        }
    ]
}
```

### Error: `Invalid payment signature`

**Symptom:** `/payments/verify` returns 400.

**Cause:** HMAC signature doesn't match. Either:
- Wrong `RAZORPAY_KEY_SECRET` in config
- Data was tampered with
- Order ID / payment ID don't match what Razorpay sent

**Debug:**
```python
# Add logging in verify_razorpay_signature:
logger.debug(f"order_id={order_id}, payment_id={payment_id}")
logger.debug(f"received_signature={signature}")
logger.debug(f"expected_signature={expected}")
```

### Error: `502` on `/payments/verify`

**Symptom:** Payment seems to work on Razorpay's side but verify returns 502.

**Cause:** `update_litellm_budget()` failed → auto-refund triggered.

**Debug:**
1. Check logs for "LiteLLM budget update failed"
2. Is `LITELLM_BASE_URL` reachable?
3. Is `LITELLM_MASTER_KEY` correct?
4. Check if the auto-refund also failed (look for "Auto-refund also failed" in logs)

### Error: `500 Internal Server Error`

**Symptom:** Unhandled exception.

**Debug:**
1. Look at the terminal — the full traceback is printed
2. The traceback shows: file, line number, function name, and the exact error
3. Common causes:
   - DB query error (typo in SQL, wrong column name)
   - External API timeout
   - None/null where a value was expected

---

## Debugging specific scenarios

### "Why isn't the webhook processing?"

1. Check if Razorpay is actually sending webhooks — log into Razorpay Dashboard → Webhooks → check delivery status
2. Check if your endpoint is reachable from the internet (localhost is NOT — you need a tunnel like ngrok for local testing)
3. Add logging at the start of the webhook handler:
   ```python
   @router.post("/webhook")
   async def razorpay_webhook(request: Request):
       logger.info("Webhook received!")
       raw_body = await request.body()
       logger.info(f"Event: {json.loads(raw_body).get('event')}")
   ```

### "Credits weren't added after payment"

1. Check `razorpay_orders` — is the status `paid`?
   ```sql
   SELECT * FROM razorpay_orders WHERE razorpay_order_id = 'order_XXX';
   ```
2. Check `api_user_credits` — what's the balance?
   ```sql
   SELECT * FROM api_user_credits WHERE user_id = '123';
   ```
3. Check `razorpay_credit_transactions` — is there a credit entry?
   ```sql
   SELECT * FROM razorpay_credit_transactions WHERE user_id = '123' ORDER BY created_at DESC LIMIT 5;
   ```
4. Check logs for "already processed" — maybe both verify and webhook tried, and the second was a no-op

### "Refund didn't reverse credits"

1. Check order status: should be `refunded`
2. Check transaction ledger for a `refund` type entry
3. Check if LiteLLM budget was updated (look for "LiteLLM budget updated" in logs)

---

## Debugging with the database directly

### Useful queries

```sql
-- Recent orders for a user
SELECT id, razorpay_order_id, status, credits, created_at
FROM razorpay_orders
WHERE user_id = '123'
ORDER BY created_at DESC
LIMIT 10;

-- Current credit balance
SELECT * FROM api_user_credits WHERE user_id = '123';

-- Recent credit movements
SELECT id, amount, transaction_type, reason, reference_id, created_at
FROM razorpay_credit_transactions
WHERE user_id = '123'
ORDER BY created_at DESC
LIMIT 20;

-- Find an order by Razorpay order ID
SELECT * FROM razorpay_orders WHERE razorpay_order_id = 'order_ABC123';

-- Count orders by status
SELECT status, COUNT(*) FROM razorpay_orders GROUP BY status;
```

---

## Testing endpoints manually

### Using Swagger UI

1. Go to http://localhost:8002/docs
2. Click on an endpoint → "Try it out"
3. For authenticated endpoints, you need to pass headers. In Swagger, look for the "Parameters" section and add:
   - `userid: 123` (if you know the user ID)
   - Or use the `Authorization` header with a valid token

### Using curl

```bash
# Health check
curl http://localhost:8002/health

# List packages (no auth needed)
curl http://localhost:8002/payments/packages

# Get credits (auth needed)
curl -H "userid: 123" http://localhost:8002/payments/credits

# Create order
curl -X POST http://localhost:8002/payments/orders \
  -H "userid: 123" \
  -H "Content-Type: application/json" \
  -d '{"package_id": "pro"}'
```

### Using the dummy request helper

For quick testing in a Python REPL:
```python
# In a Python shell from the project root
from app.utils.request_utils import create_dummy_request

# Create a fake request with a test token
req = create_dummy_request()

# Now call router functions directly
from app.routers.payment import get_user_id_from_request
import asyncio
user_id = asyncio.run(get_user_id_from_request(req))
print(user_id)
```

---

## Debugging Kubernetes (deployed service)

### View pod logs
```bash
# List pods in the namespace
kubectl get pods -n <app>-ns

# Stream logs from the payment service
kubectl logs -f deployment/<payment-svc> -n <app>-ns

# Get logs from a specific pod
kubectl logs <pod-name> -n <app>-ns
```

### Check pod status
```bash
# See if pod is running, restarting, or crashlooping
kubectl get pods -n <app>-ns

# Detailed info (events, restart reasons)
kubectl describe pod <pod-name> -n <app>-ns
```

### Open a shell inside the pod
```bash
kubectl exec -it <pod-name> -n <app>-ns -- /bin/bash

# Now you can:
# - Check environment: echo $ENVT
# - Test DB connectivity: python -c "from app.utils.db_utils import engine; print(engine.url)"
# - Run quick queries
```

---

## Next doc

→ [08 - Razorpay Subscriptions](./08-razorpay-subscriptions.md) — subscriptions from scratch
