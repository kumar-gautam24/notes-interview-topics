"""
Razorpay webhooks + idempotency, hands-on (FastAPI + SQLite, runs without Razorpay).

What the interviewer drilled, and where it is in this file:
  1. Fake / tampered event           -> verify_signature(): HMAC-SHA256 of the RAW body with the
                                        webhook secret; mismatch -> 400, nothing stored
  2. Same event delivered twice       -> webhook_events table, event_id UNIQUE; 2nd insert conflicts
     (same payload, same event id)       -> return 200 and do nothing
  3. Fake first, real one second      -> we record the event id only AFTER the signature passes,
                                        so the fake can't "use up" the real event's id
  4. Events out of order / late       -> order state machine: only allowed transitions are applied
     (load balancer busy, retry later)   (paid never goes back to failed)
  5. Processing crashes halfway       -> event row + order update in ONE transaction: on error both
                                        roll back, we return 500, Razorpay retries, it works then
  6. Idempotency key on OUR API       -> POST /orders with an Idempotency-Key header: same key
                                        returns the same order instead of creating a second one

Run:  python3 razorpay_webhook.py
"""
import hashlib
import hmac
import json
import sqlite3
import uuid

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.testclient import TestClient

WEBHOOK_SECRET = "whsec_test_only_change_me_in_env"     # Razorpay dashboard -> Webhooks -> secret
KEY_SECRET = "key_secret_test_only"                       # API key secret (server only, never in the app)

app = FastAPI()
conn = sqlite3.connect(":memory:", check_same_thread=False, isolation_level=None)
conn.executescript("""
CREATE TABLE orders (
    id          TEXT PRIMARY KEY,                -- Razorpay order id, e.g. order_ABC
    user_id     TEXT NOT NULL,
    amount      INTEGER NOT NULL,                -- in PAISE: 500.00 INR = 50000
    currency    TEXT NOT NULL DEFAULT 'INR',
    status      TEXT NOT NULL DEFAULT 'created', -- created -> paid | failed ; failed -> paid
    idempotency_key TEXT UNIQUE
);
CREATE TABLE webhook_events (
    event_id    TEXT PRIMARY KEY,                -- X-Razorpay-Event-Id header
    event_type  TEXT NOT NULL,
    received_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE wallet (user_id TEXT PRIMARY KEY, credits INTEGER NOT NULL DEFAULT 0);
""")

ALLOWED = {                                            # state machine
    ("created", "paid"), ("created", "failed"),
    ("failed", "paid"),                                # user retried and the 2nd attempt succeeded
}
EVENT_TO_STATUS = {"payment.captured": "paid", "order.paid": "paid", "payment.failed": "failed"}


# ---------------------------------------------------------------------------
# Signatures
# ---------------------------------------------------------------------------
def sign(body: bytes, secret: str = WEBHOOK_SECRET) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def verify_signature(raw_body: bytes, signature: str | None) -> bool:
    if not signature:
        return False
    return hmac.compare_digest(sign(raw_body), signature)      # constant-time compare


def verify_payment_signature(order_id: str, payment_id: str, signature: str) -> bool:
    """Checkout success callback: Razorpay signs 'order_id|payment_id' with the KEY secret."""
    expected = hmac.new(KEY_SECRET.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


# ---------------------------------------------------------------------------
# Our API: create order with an idempotency key
# ---------------------------------------------------------------------------
@app.post("/orders")
def create_order(body: dict, idempotency_key: str = Header(...)):
    existing = conn.execute("SELECT id, amount, status FROM orders WHERE idempotency_key=?",
                            (idempotency_key,)).fetchone()
    if existing:                                    # client retried (timeout, double tap): same answer
        return {"order_id": existing[0], "amount": existing[1], "status": existing[2], "replayed": True}
    # Real code: order = razorpay_client.order.create({"amount": 50000, "currency": "INR",
    #                                                  "receipt": idempotency_key, "notes": {...}})
    order_id = f"order_{uuid.uuid4().hex[:14]}"
    conn.execute("INSERT INTO orders (id, user_id, amount, idempotency_key) VALUES (?,?,?,?)",
                 (order_id, body["user_id"], body["amount"], idempotency_key))
    return {"order_id": order_id, "amount": body["amount"], "status": "created", "replayed": False}


# ---------------------------------------------------------------------------
# Webhook
# ---------------------------------------------------------------------------
@app.post("/webhooks/razorpay")
async def razorpay_webhook(
    request: Request,
    x_razorpay_signature: str | None = Header(None),
    x_razorpay_event_id: str | None = Header(None),
):
    raw = await request.body()                      # RAW bytes: re-serialised JSON would change the hash
    if not verify_signature(raw, x_razorpay_signature):
        raise HTTPException(400, "bad signature")   # fake event: rejected, NOT recorded

    event = json.loads(raw)
    event_id = x_razorpay_event_id or event.get("id")
    new_status = EVENT_TO_STATUS.get(event["event"])
    payment = event["payload"]["payment"]["entity"]

    try:
        conn.execute("BEGIN IMMEDIATE")
        cur = conn.execute("INSERT OR IGNORE INTO webhook_events (event_id, event_type) VALUES (?,?)",
                           (event_id, event["event"]))
        if cur.rowcount == 0:                       # already processed this exact event
            conn.execute("ROLLBACK")
            return {"status": "duplicate_ignored"}

        result = "ignored_event_type"
        if new_status:
            row = conn.execute("SELECT status, amount, currency, user_id FROM orders WHERE id=?",
                               (payment["order_id"],)).fetchone()
            if row is None:
                result = "unknown_order"
            else:
                status, amount, currency, user_id = row
                if (payment["amount"], payment["currency"]) != (amount, currency):
                    result = "amount_mismatch"      # never trust the payload blindly
                elif (status, new_status) not in ALLOWED:
                    result = f"ignored_transition_{status}_to_{new_status}"   # late / out of order
                else:
                    conn.execute("UPDATE orders SET status=? WHERE id=?", (new_status, payment["order_id"]))
                    if new_status == "paid":
                        conn.execute("INSERT INTO wallet (user_id, credits) VALUES (?, ?) "
                                     "ON CONFLICT(user_id) DO UPDATE SET credits = credits + excluded.credits",
                                     (user_id, amount // 100))
                    result = f"applied_{new_status}"
        conn.execute("COMMIT")                      # event id + state change saved together
        return {"status": result}
    except Exception:
        conn.execute("ROLLBACK")                    # nothing saved -> Razorpay's retry will work
        raise HTTPException(500, "processing failed, will be retried")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
def event_body(event_id, event, order_id, amount=50000, currency="INR"):
    return json.dumps({
        "id": event_id, "event": event,
        "payload": {"payment": {"entity": {"id": f"pay_{event_id}", "order_id": order_id,
                                           "amount": amount, "currency": currency}}},
    }).encode()


def send(client, body, event_id, signature=None):
    return client.post("/webhooks/razorpay", content=body, headers={
        "Content-Type": "application/json",
        "X-Razorpay-Signature": signature if signature is not None else sign(body),
        "X-Razorpay-Event-Id": event_id,
    })


def credits(user):
    row = conn.execute("SELECT credits FROM wallet WHERE user_id=?", (user,)).fetchone()
    return row[0] if row else 0


def test():
    c = TestClient(app)

    # idempotency key on our own API
    a = c.post("/orders", json={"user_id": "u1", "amount": 50000}, headers={"Idempotency-Key": "k1"}).json()
    b = c.post("/orders", json={"user_id": "u1", "amount": 50000}, headers={"Idempotency-Key": "k1"}).json()
    assert a["order_id"] == b["order_id"] and b["replayed"] is True
    print("same Idempotency-Key -> same order, no duplicate: OK")
    order = a["order_id"]

    # fake event first (bad signature), then the real one with the SAME event id
    real = event_body("evt_1", "payment.captured", order)
    assert send(c, real, "evt_1", signature="forged").status_code == 400
    assert credits("u1") == 0
    r = send(c, real, "evt_1")
    assert r.json()["status"] == "applied_paid" and credits("u1") == 500
    print("fake event rejected, real event with same id still processed: OK")

    # duplicate delivery of the real event
    assert send(c, real, "evt_1").json()["status"] == "duplicate_ignored" and credits("u1") == 500
    print("duplicate event ignored, credits added once: OK")

    # late 'payment.failed' arriving after 'paid' (out of order)
    late = event_body("evt_0", "payment.failed", order)
    assert send(c, late, "evt_0").json()["status"] == "ignored_transition_paid_to_failed"
    print("late failed event can't move paid -> failed: OK")

    # tampered amount: signature valid (it's our test secret) but amount doesn't match the order
    o2 = c.post("/orders", json={"user_id": "u2", "amount": 100000}, headers={"Idempotency-Key": "k2"}).json()
    assert send(c, event_body("evt_2", "payment.captured", o2["order_id"], amount=100), "evt_2").json()["status"] == "amount_mismatch"
    print("amount mismatch caught: OK")

    # checkout signature (order_id|payment_id)
    sig = hmac.new(KEY_SECRET.encode(), f"{order}|pay_x".encode(), hashlib.sha256).hexdigest()
    assert verify_payment_signature(order, "pay_x", sig) and not verify_payment_signature(order, "pay_y", sig)
    print("checkout payment signature check: OK")
    print("All webhook tests passed")


if __name__ == "__main__":
    test()
