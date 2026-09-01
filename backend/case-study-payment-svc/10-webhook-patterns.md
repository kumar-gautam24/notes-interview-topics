# 10 — Webhook Patterns (theory + what we actually do)

This doc explains the **correct** way to handle webhooks, the trade-offs, and then shows exactly what **this codebase** does — where it follows best practice and where it takes a shortcut.

---

## Part A — What is a webhook?

A webhook is a **server-to-server HTTP POST** that a third-party (Razorpay, Stripe, GitHub, etc.) sends to **your** URL when something happens on **their** side.

```
Normal API call (you → them):
  Your server  ──POST /create-order──▶  Razorpay
               ◀── 200 OK ──────────

Webhook (them → you):
  Razorpay     ──POST /payments/webhook──▶  Your server
               ◀── 200 OK ──────────────
```

You don't control **when** it arrives. You don't control **how many times** it arrives (retries). You don't control the **order** of events. Your job is to handle all of that gracefully.

---

## Part B — The golden rule: verify → ack → process

The industry-standard pattern has three steps:

```
┌──────────────────────────────────────────────────────────────────┐
│  1. VERIFY the signature (is this really from Razorpay?)        │
│  2. ACK immediately (return 200 so they stop retrying)          │
│  3. PROCESS at your own pace (queue, background worker, etc.)   │
└──────────────────────────────────────────────────────────────────┘
```

### Step 1 — Verify the signature

Every serious webhook provider signs the payload. Razorpay puts an HMAC-SHA256 hash in the `X-Razorpay-Signature` header. You recompute it with your webhook secret and compare:

```python
import hmac, hashlib

def verify_webhook_signature(raw_body: bytes, signature: str) -> bool:
    expected = hmac.new(
        WEBHOOK_SECRET.encode(),
        raw_body,           # the EXACT bytes Razorpay sent
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)
```

**Critical rules:**
- Use the **raw bytes** of the request body, not a re-serialized dict (JSON key order, whitespace, encoding can differ).
- Use `hmac.compare_digest()` — constant-time comparison prevents timing attacks.
- If the signature doesn't match → **reject immediately** (400 or 401). Don't touch your database.

### Step 2 — Ack immediately (return 200)

Once the signature is valid, you know the event is real. The ideal pattern:

```python
@router.post("/webhook")
async def webhook(request: Request):
    raw_body = await request.body()
    signature = request.headers.get("X-Razorpay-Signature", "")

    if not verify_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=400, detail="Bad signature")

    event = json.loads(raw_body)

    # ✅ Enqueue for background processing
    queue.enqueue(process_webhook_event, event)

    # ✅ Return 200 IMMEDIATELY — Razorpay is happy, no retry
    return {"status": "ok"}
```

**Why ack fast?**
- Razorpay (and most providers) have a **timeout** (typically 5–15 seconds). If your handler takes longer, they assume failure and **retry**.
- Retries mean **duplicate delivery**. You now have to handle the same event twice.
- If your downstream (DB, LiteLLM, external API) is slow or down, your webhook starts failing, retries pile up, and you get a thundering herd.

### Step 3 — Process at your own pace

A background worker picks up the event from the queue and does the real work:

```python
def process_webhook_event(event: dict):
    event_type = event["event"]

    if event_type == "payment.captured":
        process_payment_captured(...)
    elif event_type == "subscription.charged":
        handle_subscription_charged(...)
    # ...
```

**Benefits:**
- You control concurrency (one worker, ten workers, rate-limited).
- Retries are **yours** to manage (exponential backoff, dead-letter queue).
- A slow downstream doesn't block Razorpay's retry timer.

### The full ideal flow

```
Razorpay                          Your server                    Background worker
────────                          ───────────                    ─────────────────
POST /webhook ──────────────────▶ verify signature
                                  ✓ valid
                                  enqueue(event)
                                  return 200 ◀─────────────────
                                                                 dequeue(event)
                                                                 process_payment_captured()
                                                                 add_credits()
                                                                 update_litellm_budget()
                                                                 ✓ done
```

---

## Part C — What this codebase actually does

We follow **step 1** correctly. We skip step 2's "ack fast" and do **everything inline**.

### ✅ Signature verification (correct)

`app/routers/payment.py` lines 147–151:

```python
raw_body = await request.body()
signature = request.headers.get("X-Razorpay-Signature", "")

if not pay_svc.verify_webhook_signature(raw_body, signature):
    raise HTTPException(status_code=400, detail="Invalid webhook signature")
```

This is textbook:
- Raw bytes (not re-parsed JSON).
- HMAC-SHA256 with `compare_digest`.
- Early reject on mismatch — no business logic runs.

### ⚠️ Synchronous processing (shortcut)

After signature check, the handler does **all** the work before returning:

```python
# One-time payments
if event_type == "payment.captured":
    order = pay_svc.process_payment_captured(rz_order_id, rz_payment_id)
    #       ↑ hits DB, adds credits, calls LiteLLM, maybe refunds
    #       ... all before we return {"status": "ok"}

# Subscriptions
elif event_type == "subscription.charged":
    sub_svc.handle_subscription_charged(rz_sub_id, payment_entity)
    #       ↑ DB lookup, invoice insert, add_credits, LiteLLM sync
    #       ... all inline
```

Only **after** all that work completes does the handler return `{"status": "ok"}`.

### Why this works (for now)

1. **Idempotent handlers** — `process_payment_captured` uses an atomic `UPDATE ... WHERE status IN ('created','failed') RETURNING *`. If called twice, the second call gets `None` and skips. `handle_subscription_charged` checks `_get_invoice_by_payment()` before inserting. So retries and duplicates are safe.

2. **Fast enough** — DB operations are local-network, Razorpay's timeout is generous (~15s), and LiteLLM calls are quick. We haven't hit the timeout in practice.

3. **No extra infrastructure** — No Redis queue, no Celery, no background workers to deploy and monitor.

### Where it could break

| Scenario | What happens |
|----------|-------------|
| LiteLLM is slow (>10s) | Razorpay times out → retries → duplicate delivery (idempotency saves us, but we waste work) |
| LiteLLM is **down** | `process_payment_captured` triggers auto-refund; subscription handler logs error but credits are still added without budget sync |
| DB is slow | Same timeout problem — Razorpay retries |
| Burst of webhooks | All processed serially in the web worker; if Gunicorn workers are busy, new webhooks queue at the TCP level |
| Razorpay changes timeout | If they shorten it, our inline approach breaks sooner |

---

## Part D — Idempotency: the safety net

Whether you process inline or via a queue, **idempotency** is non-negotiable. Webhooks are delivered **at least once**, not exactly once.

### How we handle it

**One-time payments** — `mark_order_paid()` in `app/services/payment.py`:

```python
sql = """
    UPDATE razorpay_orders
    SET status = 'paid', razorpay_payment_id = :payment_id, updated_at = :now
    WHERE razorpay_order_id = :order_id
      AND status IN ('created', 'failed')
    RETURNING *
"""
```

The `AND status IN ('created', 'failed')` clause means a second call for the same order returns zero rows → `None` → caller skips credit addition. This is **atomic** — no race condition even with concurrent webhook + `/verify` calls.

**Subscriptions** — `handle_subscription_charged()` in `app/services/subscription.py`:

```python
existing = _get_invoice_by_payment(rz_payment_id)
if existing:
    logger.info("payment {} already processed, skipping")
    return
```

Checks if we already recorded this `razorpay_payment_id` in `subscription_invoices`. If yes, skip. This is a read-then-write pattern (slightly weaker than the atomic UPDATE approach — a race is theoretically possible if two identical webhooks arrive at the exact same millisecond, though Razorpay doesn't do that in practice).

### Idempotency checklist for any webhook handler

- [ ] Can this handler be called twice with the same payload without double-crediting?
- [ ] Can it be called twice concurrently (two web workers)?
- [ ] Does it log clearly when it detects a duplicate?
- [ ] Does it still return 200 on duplicates (so the provider stops retrying)?

Our one-time payment handler passes all four. The subscription handler passes 1, 3, and 4; item 2 has a theoretical (but practically negligible) gap.

---

## Part E — The two paths: `/verify` vs webhook

For **one-time payments**, this codebase has **dual triggers** into the same idempotent function:

```
                    ┌─────────────────────┐
  User's browser    │  POST /verify       │──┐
  (after checkout)  │  (client-initiated) │  │
                    └─────────────────────┘  │
                                             ▼
                                   process_payment_captured()
                                   (idempotent — runs once)
                    ┌─────────────────────┐  ▲
  Razorpay server   │  POST /webhook      │──┘
  (server-to-server)│  payment.captured   │
                    └─────────────────────┘
```

**Why both?**
- `/verify` gives the user **instant** feedback ("payment successful, credits added").
- Webhook is the **safety net** — if the user closes the tab, loses network, or the browser never calls `/verify`, the webhook still fires and credits are added.

**Who wins?** Whichever arrives first does the work. The second one sees `status = 'paid'` and returns gracefully.

For **subscriptions**, there is **no** `/verify` equivalent. Recurring charges happen while the user is asleep — only the webhook path exists:

```
  Razorpay (monthly) ──webhook──▶ handle_subscription_charged() ──▶ add_credits()
                                        (single source of truth)
```

---

## Part F — If you wanted to add "ack fast + queue"

This is what the upgrade path looks like. You don't need to do this today, but when LiteLLM calls get slow or you add more downstream work, here's the plan:

### Option 1: FastAPI BackgroundTasks (simplest)

```python
from fastapi import BackgroundTasks

@router.post("/webhook")
async def razorpay_webhook(request: Request, bg: BackgroundTasks):
    raw_body = await request.body()
    signature = request.headers.get("X-Razorpay-Signature", "")

    if not pay_svc.verify_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=400, detail="Bad signature")

    event = json.loads(raw_body)
    bg.add_task(dispatch_webhook_event, event)
    return {"status": "ok"}     # ← returned BEFORE processing
```

**Pros:** Zero new infrastructure. **Cons:** If the process crashes mid-task, the event is lost (no persistence).

### Option 2: Database queue (durable, no new infra)

```python
@router.post("/webhook")
async def razorpay_webhook(request: Request):
    # ... verify signature ...
    event = json.loads(raw_body)

    # Persist the raw event
    sql = """INSERT INTO webhook_events (id, event_type, payload, status, created_at)
             VALUES (:id, :type, CAST(:payload AS jsonb), 'pending', :now)"""
    execute_query_with_params(sql, {
        "id": str(uuid.uuid4()),
        "type": event.get("event"),
        "payload": raw_body.decode(),
        "now": datetime.now(timezone.utc).isoformat(),
    })

    return {"status": "ok"}     # ← fast ack
```

Then a separate worker (cron, or a `/process-webhooks` admin endpoint) polls `webhook_events WHERE status = 'pending'` and processes them. Failed events get retried with backoff.

**Pros:** Durable — survives crashes. Uses your existing Postgres. **Cons:** Slight delay; need a polling mechanism.

### Option 3: Redis / Celery / SQS (production-grade)

Full async queue. Overkill for this service's current scale, but the standard at high volume.

---

## Part G — Summary: where we stand

| Best practice | Our status | Notes |
|---------------|------------|-------|
| Verify signature before trusting | ✅ Done | HMAC-SHA256, raw bytes, `compare_digest` |
| Reject bad signatures early | ✅ Done | 400 before any business logic |
| Ack fast, process later | ❌ Not done | We process inline (works because ops are fast) |
| Idempotent handlers | ✅ Done | Atomic SQL for payments; invoice check for subscriptions |
| Dual path (client + webhook) | ✅ Payments only | `/verify` + webhook both call `process_payment_captured` |
| Single source for subscriptions | ⚠️ Webhook only | If webhooks fail, no credits are added for renewals |
| Persistent event log | ❌ Not done | Raw webhook payloads are not stored for replay |

**The honest take:** For a service at this scale, the inline approach is fine. Idempotency is the hard part, and we have it. The "ack fast + queue" upgrade is worth doing when you start seeing webhook retries in Razorpay's dashboard or when downstream calls (LiteLLM) become unreliable.

---

## Next doc

→ [09 - Subscription Dev Guide](./09-subscription-dev-guide.md) — building the subscription feature step by step
