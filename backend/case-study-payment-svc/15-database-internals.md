# 15 — Database Internals (what doc 04 skipped)

[Doc 04](./04-database-guide.md) covers *how* to connect and write queries. This doc covers *why* things work the way they do — connection pooling, ACID, transactions, and what happens when your service is under real load.

Grounded in our actual code: [`app/utils/db_utils.py`](../app/utils/db_utils.py) and [`app/services/payment.py`](../app/services/payment.py).

---

## Part A — What is a database connection?

A connection is a **live session** between your Python process and PostgreSQL. Creating one involves:

```
Python process                              PostgreSQL server
      │                                            │
      │── TCP handshake (SYN/ACK) ────────────────▶│  ~1-5ms (local)
      │                                            │  ~10-50ms (remote/Azure)
      │── TLS handshake (if enabled) ─────────────▶│  ~5-20ms
      │── Authentication (user/pass check) ───────▶│  ~5-10ms
      │── Session setup (timezone, encoding) ─────▶│  ~1-5ms
      │                                            │
      │◀═══ Connection ready ═════════════════════▶│
      │     (now you can run SQL)                  │
```

Total: **20-80ms** just to establish a connection. That's before you run a single query.

### Why this matters

If you open a new connection for every HTTP request:

- 10 requests/second = 10 connections/second = 200-800ms of overhead/second just connecting
- 100 requests/second = 100 simultaneous connections → PostgreSQL has a `max_connections` limit (typically 100-200). You'd exhaust it.
- Each PostgreSQL connection uses ~5-10MB of server memory. 200 connections = 1-2GB just for connection overhead.

### The solution: connection pooling

Instead of creating and destroying connections, keep a few alive and reuse them.

---

## Part B — Connection pooling: why and how

### How it works

```
HTTP Request 1 arrives
  → "I need a DB connection"
  → Pool: "Here, borrow connection #1"
  → Run SQL query (50ms)
  → "Done, returning connection #1 to pool"

HTTP Request 2 arrives (1ms later)
  → "I need a DB connection"
  → Pool: "Here, connection #1 is free — take it"
  → No TCP handshake, no auth, instant.
```

The pool manages a set of pre-established connections. Your code borrows one, uses it, and returns it. The connection stays open for the next request.

### Our pool config

From `app/utils/db_utils.py`:

```python
engine = create_engine(
    DATABASE_URL,
    pool_size=2,
    max_overflow=0,
    pool_pre_ping=True,
    pool_recycle=1800,
    pool_timeout=30,
    echo=False,
)
```

Every setting explained:

| Setting | Value | What it means |
|---------|-------|---------------|
| `pool_size` | **2** | Keep 2 connections alive at all times |
| `max_overflow` | **0** | Never create more than `pool_size` connections. Strict limit. |
| `pool_pre_ping` | **True** | Before handing out a connection, send a lightweight `SELECT 1` to check it's alive. If dead (DB restarted, network blip), discard it and create a fresh one. Costs ~1ms but prevents "connection reset" errors. |
| `pool_recycle` | **1800** | Replace connections older than 30 minutes. Firewalls and load balancers silently kill idle TCP connections. This prevents "stale connection" errors. |
| `pool_timeout` | **30** | If all connections are busy, wait up to 30 seconds for one to free up. After that → `TimeoutError` → your request fails with a 500. |
| `echo` | **False** | Don't log every SQL query (set to True for debugging). |

### Pool lifecycle

```
Startup:
  Pool creates 2 connections to PostgreSQL.
  Both are idle, waiting.

Request 1:
  → Borrow conn #1 → run query → return conn #1

Request 2 (concurrent with Request 1):
  → conn #1 is busy → Borrow conn #2 → run query → return conn #2

Request 3 (concurrent with 1 and 2):
  → Both busy → WAIT...
  → Request 1 finishes, returns conn #1
  → Request 3 borrows conn #1

Request 4 (concurrent with 2 and 3, arrives during wait):
  → Both busy → WAIT...
  → 30 seconds pass → nobody returned a connection
  → pool_timeout → TimeoutError → HTTP 500
```

---

## Part C — Our pool_size=2: is it enough?

### It depends on how you run the app

**Dockerfile (single uvicorn process):**
- 1 process × 2 connections = **2 total DB connections**
- uvicorn is async, so it can handle many concurrent HTTP requests, but DB queries are **sync** (SQLAlchemy sync engine). Each query blocks a connection until it completes.

**run.sh (gunicorn with 4 workers):**
- 4 processes × 2 connections each = **8 total DB connections**
- Each worker is independent with its own pool.

**Kubernetes (2 pods, each single-process):**
- 2 pods × 1 process × 2 connections = **4 total DB connections**

### The math

If the average query takes **50ms** (fast, simple queries like ours):
- 1 connection handles: 1000ms / 50ms = **20 queries/second**
- 2 connections handle: **40 queries/second**

If a query takes **500ms** (slow query, complex join, DB under load):
- 1 connection handles: **2 queries/second**
- 2 connections handle: **4 queries/second**

Our payment endpoints typically do 1-3 queries per request. At 40 queries/second with 2 connections, we can handle roughly **13-40 requests/second** per process. For our current traffic, that's plenty.

### When to increase pool_size

Watch for these signs:
- `TimeoutError` or `QueuePool limit` in logs → pool is exhausted
- Response times spike during traffic bursts → requests waiting for connections
- `kubectl logs` shows slow responses that aren't slow queries

Increase to `pool_size=5` or `pool_size=10`. But also increase `max_overflow` if you want burst capacity:

```python
engine = create_engine(
    DATABASE_URL,
    pool_size=5,       # 5 steady connections
    max_overflow=5,    # up to 10 total during bursts
    # overflow connections are closed after use
)
```

### The other side: PostgreSQL limits

PostgreSQL's `max_connections` (default: 100) is shared across ALL clients. If you have:
- 4 gunicorn workers × pool_size=10 = 40 connections from this service
- Plus other services connecting to the same DB
- Plus admin connections (psql, DBeaver)

You can hit the limit. Then PostgreSQL refuses new connections for everyone.

---

## Part D — ACID: what the database guarantees

ACID is the set of properties that make databases reliable. Every property explained with our code:

### Atomicity — all or nothing

A transaction either **fully completes** or **fully rolls back**. No partial state.

Our example — `mark_order_paid()` in `app/services/payment.py`:

```sql
UPDATE razorpay_orders
SET status = 'paid',
    razorpay_payment_id = :payment_id,
    updated_at = :now
WHERE razorpay_order_id = :order_id
  AND status IN ('created', 'failed')
RETURNING *
```

If the server crashes mid-write (power failure, process killed), PostgreSQL rolls back the partial UPDATE. The order is never in a state where `status = 'paid'` but `razorpay_payment_id` is still NULL. It's all or nothing.

### Consistency — rules are always enforced

Database constraints hold true before and after every transaction.

Our example — `api_user_credits` table:

```sql
CREATE TABLE api_user_credits (
    ...
    balance INTEGER NOT NULL CHECK (balance >= 0)
);
```

Even if two requests try to deduct credits simultaneously, the `CHECK` constraint prevents the balance from going negative. If a deduction would result in `-50`, PostgreSQL rejects it — the transaction fails, the balance stays at the old value.

### Isolation — concurrent transactions don't interfere

Two transactions running at the same time don't see each other's uncommitted changes.

Our example — two webhooks for the same order arrive simultaneously:

```
Transaction A (webhook #1):              Transaction B (webhook #2):
                                         
SELECT ... WHERE status = 'created'      SELECT ... WHERE status = 'created'
→ finds the row                          → finds the row (A hasn't committed yet)
                                         
UPDATE SET status = 'paid'               UPDATE SET status = 'paid'
→ acquires row lock                      → BLOCKED (waiting for A's lock)
                                         
COMMIT                                   → lock released
                                         → re-checks: status is now 'paid'
                                         → WHERE status IN ('created','failed')
                                         → no match → 0 rows updated
                                         → returns None (idempotent!)
```

PostgreSQL's default isolation level (`READ COMMITTED`) handles this correctly for our use case.

### Durability — committed = permanent

Once PostgreSQL says "COMMIT successful", the data survives crashes. It uses a **Write-Ahead Log (WAL)**: changes are written to a sequential log file on disk *before* the actual table data is updated. If the server crashes, it replays the WAL on startup to recover committed transactions.

---

## Part E — Transactions: what we do and don't do

### What a transaction is

A transaction groups multiple SQL statements into one atomic unit:

```sql
BEGIN;
  INSERT INTO subscription_invoices (...) VALUES (...);
  UPDATE api_user_credits SET balance = balance + 1200 WHERE user_id = '123';
COMMIT;
-- Both happen, or neither happens.
```

If the process crashes between the INSERT and UPDATE, PostgreSQL rolls back both. The invoice is not saved and credits are not added. Clean state.

### What our code does (auto-commit per statement)

Each `execute_query_with_params` call is its own transaction:

```python
# In handle_subscription_charged():

_save_invoice(sub["id"], payment_entity)    # Transaction 1: INSERT invoice → COMMIT
                                            # ← if crash here: invoice saved, no credits
add_credits(user_id, amount, ...)           # Transaction 2: UPDATE balance → COMMIT
```

These are **two separate transactions**. If the process crashes between them:
- Invoice is recorded (charge happened)
- Credits are NOT added (user doesn't get what they paid for)
- The webhook retries, `_get_invoice_by_payment` finds the existing invoice → **skips** (idempotency)
- Result: user paid but never got credits. This is a real bug.

### What we should do for critical paths

```python
# Hypothetical fix using explicit transactions:
with engine.begin() as conn:
    conn.execute(text(insert_invoice_sql), invoice_params)
    conn.execute(text(update_credits_sql), credit_params)
# COMMIT happens here — both or neither
```

### Why we get away with it (mostly)

1. Crashes between two statements are rare (milliseconds window)
2. The one-time payment path (`process_payment_captured`) does credits + LiteLLM sync, and if LiteLLM fails, it auto-refunds — so there's a recovery path
3. The subscription path has the gap described above, but webhook retries + manual monitoring catch it in practice

This is a conscious trade-off: simpler code (no transaction management) at the cost of a rare edge case. In a high-volume system, you'd fix it.

---

## Part F — The RETURNING pattern as atomic read-write

Our most elegant database pattern. Used in `mark_order_paid()`:

```sql
UPDATE razorpay_orders
SET status = 'paid', razorpay_payment_id = :payment_id, updated_at = :now
WHERE razorpay_order_id = :order_id
  AND status IN ('created', 'failed')
RETURNING *
```

This does **three things in one atomic operation**:

1. **Find** rows matching the WHERE clause
2. **Update** them
3. **Return** the updated rows

### Why this is better than read-then-write

The naive approach:

```python
# Step 1: Read
order = SELECT * FROM razorpay_orders WHERE id = :id
if order["status"] != "created":
    return None  # already processed

# ← DANGER ZONE: another request could change status here

# Step 2: Write
UPDATE razorpay_orders SET status = 'paid' WHERE id = :id
```

Between Step 1 and Step 2, another concurrent request could also read `status = 'created'` and both would proceed to update. Race condition → double credits.

With `UPDATE ... WHERE status = 'created' RETURNING *`, the check and update are **one atomic operation**. The database locks the row during the UPDATE. Only one concurrent caller can match `status = 'created'` — the other sees `status = 'paid'` and gets zero rows back.

### Compare with subscription invoices

Our subscription code uses the weaker read-then-write pattern:

```python
existing = _get_invoice_by_payment(rz_payment_id)   # SELECT
if existing:
    return                                            # skip

_save_invoice(sub["id"], payment_entity)              # INSERT
```

The unique index on `razorpay_payment_id` catches the race at the DB level (second INSERT fails), but it's less clean than the RETURNING approach. We catch the exception and handle it, but it's a workaround rather than a design.

### When to use RETURNING

Any time you need to:
- Conditionally update a row and know whether it worked
- Read the updated values without a second query
- Ensure exactly one concurrent caller succeeds

---

## Part G — What happens under real load

### Scenario: 200 users buy credits simultaneously

Each purchase = 1 `create_order` + 1 `verify_payment` (which calls `process_payment_captured` = 2-3 queries).

**With our current config (pool_size=2, single uvicorn):**

| Metric | Value |
|--------|-------|
| Concurrent DB queries | 2 at a time |
| Query time (avg) | ~50ms |
| Throughput | ~40 queries/sec = ~15 requests/sec |
| 200 users at once | Queued for ~13 seconds |
| Risk | `pool_timeout` (30s) if queries slow down |

**With pool_size=10, gunicorn -w 4:**

| Metric | Value |
|--------|-------|
| Concurrent DB queries | 40 at a time (4 workers × 10) |
| Throughput | ~800 queries/sec = ~300 requests/sec |
| 200 users at once | Handled in < 1 second |
| Risk | 40 connections × PostgreSQL memory |

### The real bottleneck

The pool is rarely the bottleneck. These are:

**1. Slow queries**

```bash
# Find slow queries in PostgreSQL
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

Or use `EXPLAIN ANALYZE` on a specific query:

```sql
EXPLAIN ANALYZE
SELECT * FROM subscription_plans WHERE is_active = true ORDER BY price_paise;
```

This shows the query plan (sequential scan vs index scan) and actual execution time.

**2. Missing indexes**

Without an index, PostgreSQL scans every row in the table. Our migration creates indexes:

```sql
-- From 002_subscription_tables.sql
CREATE INDEX idx_user_subs_user ON user_subscriptions (user_id, status);
CREATE INDEX idx_user_subs_rz ON user_subscriptions (razorpay_subscription_id);
CREATE UNIQUE INDEX idx_sub_invoices_payment ON subscription_invoices (razorpay_payment_id);
```

`idx_user_subs_user` exists because `get_active_subscription` queries `WHERE user_id = :uid AND status IN (...)`. Without this index, every subscription lookup scans the entire table.

**3. Lock contention**

Two transactions updating the same row → one waits for the other's lock. Our `mark_order_paid` is fine (each order is updated once). But `api_user_credits` has one row per user — if a user triggers two concurrent credit operations, one blocks the other.

**4. Connection limits on PostgreSQL**

```sql
-- Check current connections
SELECT count(*) FROM pg_stat_activity;

-- Check the limit
SHOW max_connections;
```

If you're near the limit, adding more app-side pool connections won't help — PostgreSQL will reject them.

### Monitoring

```bash
# From inside a pod or with psql access:

# Active connections by application
SELECT application_name, state, count(*)
FROM pg_stat_activity
GROUP BY application_name, state;

# Long-running queries (potential locks)
SELECT pid, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active' AND now() - query_start > interval '5 seconds';
```

---

## Part H — Scaling patterns (what comes after pool tuning)

When pool tuning isn't enough, here's the progression:

### 1. Read replicas

Route SELECT queries to a read-only copy of the database. Writes still go to the primary.

```
Writes (INSERT/UPDATE) → Primary DB
Reads (SELECT)         → Read Replica
```

Our `list_plans()` and `get_balance()` are read-only — they could use a replica. `mark_order_paid()` must use the primary (it writes).

### 2. PgBouncer (external connection pooler)

Sits between your app and PostgreSQL. Multiplexes many app connections into fewer DB connections.

```
App (40 connections) → PgBouncer (10 connections) → PostgreSQL
```

PgBouncer handles the connection reuse at the TCP level, more efficiently than SQLAlchemy's pool. Useful when you have many pods/workers but PostgreSQL's `max_connections` is limited.

### 3. Async DB access

Our repo has an unused `app/database.py` set up for async:

```python
from sqlalchemy.ext.asyncio import create_async_engine
engine = create_async_engine("postgresql+asyncpg://...")
```

With async, a single Python process can handle many concurrent DB queries without blocking. The connection pool is used more efficiently because connections are released during `await` points. We don't use this yet — all our DB access goes through the sync `db_utils.py`.

### 4. Redis caching

We already have Redis (used for rate limiting). Hot queries like `list_plans()` (called on every page load, rarely changes) could be cached:

```python
# Pseudocode
plans = redis.get("subscription_plans")
if not plans:
    plans = list_plans()  # DB query
    redis.set("subscription_plans", json.dumps(plans), ex=300)  # cache 5 min
return plans
```

### When to use each

| Pattern | When | Complexity |
|---------|------|-----------|
| Increase pool_size | First sign of pool exhaustion | Low |
| PgBouncer | Many pods, hitting max_connections | Medium |
| Read replicas | Read-heavy workload, primary DB is bottleneck | Medium |
| Async DB | Want more concurrency per process | High (rewrite queries) |
| Redis caching | Hot read-only queries | Low-Medium |

For our current scale, increasing `pool_size` to 5-10 and adding an index or two would handle 10x our traffic. The other patterns are for when you outgrow that.

---

## Next doc

This is the last doc in the series. For a refresher on any topic:

- [01 — Project Overview](./01-project-overview.md) — what this service does
- [04 — Database Guide](./04-database-guide.md) — how to connect and write queries
- [10 — Webhook Patterns](./10-webhook-patterns.md) — verify/ack/process and idempotency in practice
- [11 — Networking Foundations](./11-networking-foundations.md) — DNS, TLS, load balancers, ports
- [12 — Deployment Lifecycle](./12-deployment-lifecycle.md) — Docker to Kubernetes
- [13 — Kubernetes Guide](./13-kubernetes-guide.md) — K8s objects and concepts
- [14 — Ingress Guide](./14-ingress-guide.md) — external traffic routing
