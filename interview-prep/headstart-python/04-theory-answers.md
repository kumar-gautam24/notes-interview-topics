# Theory Round Prep: Headstart Python Backend

**Context.** Headstart builds a CRM for education institutions (enrolment, marketing automation, student communication). The JD stresses REST APIs, DB schema/indexing, JWT/OAuth, scalability, error handling/logging, code reviews, OOP, and lists Django/Flask/FastAPI and MySQL/MongoDB/PostgreSQL. Their real workload is **many institutions (tenants), lots of leads/students, bulk emails/SMS, reports**. That's exactly where your screening was weaker (large data, multiprocessing, multi-tenancy), so those sections below go deepest.

**Rules for every answer:**
- Lead with a one-line answer, then one real example from your work, then the trade-off.
- Where you haven't used something (Celery, MongoDB, Django, multiprocessing in prod), say so plainly and map it to what you *have* done. Interviewers punish bluffing far more than "I've used X instead, and here's how Y differs."
- Placeholders like **[fill: …]** are numbers only you know. Fill them before the interview; never invent.

Contents: [1 Project & ownership](#1-project--ownership) · [2 Python](#2-python) · [3 FastAPI / REST](#3-fastapi--rest-apis) · [4 Databases](#4-databases) · [5 Background jobs](#5-celery--redis--background-jobs) · [6 Weak areas deep dive](#6-weak-areas-deep-dive) · [7 Client question bank](#7-client-question-bank) · [8 Questions to ask them](#8-questions-to-ask-them)

---

## 1. Project & Ownership

### Q1. Tell me about your current backend project
**Spoken answer (~90s):**
> "I work at Ailoitte on Vaidya AI for Fractal Analytics, a medical AI app on the App Store. I own three backend services, auth, admin and billing, plus the agentic pre-authorization pipeline. Auth issues the JWT contract every other service validates against, with RBAC. Billing is a credit wallet with Razorpay subscriptions. The pipeline takes a medical case and runs 36 to 40 LLM turns across 6 phases using a 29-tool layer, and I built the turn manager that orchestrates it.
> Users are **[fill: doctors / hospital staff / patients]**. I started on the mobile client and took over backend ownership as the product grew."

**Follow-up: "What wouldn't exist without you?"** Pick one and go deep:
- **Pipeline request path:** API returns a run id immediately, Redis-queued workers do the multi-minute run, client gets progress over SSE. Before that, a long run could die on an HTTP timeout.
- **Billing safety:** concurrent spends can't overdraw because deduction is one atomic `UPDATE wallet SET balance = balance - $1 WHERE user_id = $2 AND balance >= $1` instead of read-modify-write; webhooks go through a Postgres state machine that only allows valid forward transitions, HMAC-SHA256 verified, plus a reconciliation job for missed webhooks.
- **Systemic fixes:** found a sync DB driver inside async endpoints blocking the event loop, and a pool capped at 10 connections per service.

### Q2. Largest system / dataset you've personally worked with
Be honest about scale and talk about *rate and shape* rather than inflating volume.
> "Vaidya AI: **[fill: users, cases/day, requests/day, rows in largest table]**. Each case is 36–40 model turns, so one user action fans out into dozens of LLM calls and DB writes. Manpower Management is in production for a UAE client: 178+ employees across 6+ companies, ~50 APIs, plus their document store."

**Follow-up: "What scaling problem did you hit?"** You have three real ones; tell one as a story (symptom → measurement → cause → fix → result):
1. **Event-loop blocking:** latency spiked for *all* requests under load, not just slow ones. Cause: synchronous psycopg2 calls inside `async def` endpoints froze the loop. Fix: asyncpg / `run_in_threadpool`. Plus pool capped at 10 per service, so requests queued for connections.
2. **OTP latency 8–10s → ~500ms:** the blocking third-party email call was on the request path; moved it to a background job.
3. **Blob contention:** documents stored as Postgres blobs made document reads contend with transactional queries; moved to Cloudflare R2 with signed URLs, so the DB only stores keys.

---

## 2. Python

### Q3. How much of your work is Python?
> "All my backend work since early 2025 is Python: FastAPI services, Pydantic models, asyncio, asyncpg/psycopg2, Redis workers. One feature end to end: the turn manager, which runs each model turn, validates the output against a Pydantic schema and appends it to the case record before the next turn runs, so a malformed generation fails where it was produced instead of corrupting later state."

### Q4. OOP in real projects
Use concrete examples; you already follow Clean Architecture + Repository pattern.
- **Abstraction + polymorphism:** a `PaymentGateway` / `Notifier` / `Storage` abstract base class (`abc.ABC`, `@abstractmethod`) with concrete `RazorpayGateway`, `EmailNotifier`, `R2Storage`. Business code depends on the interface, so swapping Postgres blobs for R2 didn't touch the service layer.
- **Repository pattern:** `UserRepository` hides SQL; services receive it via dependency injection (`Depends`). Tests can pass an in-memory fake.
- **Tool layer:** the 29 tools share a base `Tool` class (name, input schema, `async run()`); the turn manager calls them polymorphically.
- **Inheritance:** Pydantic models (`UserBase → UserCreate / UserOut`), custom exception hierarchy (`AppError → NotFoundError, ConflictError, PaymentError`).
- **Composition over inheritance:** compliance engine is pure functions composed together, deliberately not a class hierarchy, so the rules are testable without a DB.

Know the four pillars in one line each, plus `@classmethod` vs `@staticmethod`, `@property`, dunder methods (`__init__`, `__repr__`, `__eq__`), MRO for multiple inheritance, and that Python has no real private (`_x` convention, `__x` name-mangling).

### Q5. Exceptions in production
> "Three layers. Inside the code, catch only what I can handle, specific exceptions, never a bare `except:`. Domain errors are a custom hierarchy like `NotFoundError` or `InsufficientCreditsError`. At the API boundary, FastAPI exception handlers map those to proper status codes and a consistent JSON shape `{code, message, request_id}`. And a catch-all handler logs anything unexpected with the stack trace and request id as structured JSON, then returns a generic 500 without leaking internals."

**Follow-up: "Unexpected exception inside an API?"** FastAPI/Starlette's default turns it into a 500 and the worker survives; your global handler logs traceback + request context, the client gets a safe 500 with a request id, error monitoring (Sentry or CloudWatch alarms on error rate) alerts. If a DB transaction was open, it rolls back (`async with conn.transaction()`). Mention `try / except / else / finally`, `raise ... from e` to keep the cause, and retry with backoff only for transient errors (timeouts, 503s), never for 4xx.

### Q6. Decorators
A decorator is a function that takes a function and returns a wrapped one; `@d` is `f = d(f)`. Always use `functools.wraps` to keep name/docstring.
Your real uses: FastAPI route decorators (`@app.get`), `@lru_cache`, Pydantic `@field_validator`, `@property`. Ones worth saying you wrote or would write: **retry with backoff**, **timing/logging**, **rate limit**, **role check**.

```python
import asyncio, functools, time, logging

def timed(fn):
    @functools.wraps(fn)
    async def wrapper(*args, **kwargs):
        start = time.perf_counter()
        try:
            return await fn(*args, **kwargs)
        finally:
            logging.info("%s took %.1fms", fn.__name__, (time.perf_counter() - start) * 1000)
    return wrapper

def retry(times=3, delay=0.5):                 # decorator with arguments = one more level
    def deco(fn):
        @functools.wraps(fn)
        async def wrapper(*a, **kw):
            for attempt in range(times):
                try:
                    return await fn(*a, **kw)
                except TimeoutError:
                    if attempt == times - 1: raise
                    await asyncio.sleep(delay * 2 ** attempt)
        return wrapper
    return deco
```
Note: in FastAPI, RBAC is better as a dependency (`Depends(require_role("admin"))`) than a decorator because it plugs into DI and OpenAPI. Saying that shows judgement.

### Q7. Generators / millions of records
See the deep dive in [6.1](#61-large-scale-data-processing). Short answer:
> "Never load everything. Stream in chunks: a server-side cursor or keyset pagination from the DB, a generator that yields one batch at a time, process and write in batches with `executemany`/`COPY`, so memory stays flat regardless of total size. If it's CPU-heavy, fan the batches out to a process pool; if it's long-running, it goes to a background worker with checkpointing so it can resume."

Generator basics: a function with `yield` returns a lazy iterator; state is suspended between `next()` calls; memory O(1) per item. Generator expressions `(x for x in ...)` vs list comprehensions. An iterator implements `__iter__` + `__next__`; every generator is an iterator.

### Q8. Multithreading / multiprocessing
See [6.2](#62-concurrency-threads-vs-processes-vs-async). Honest framing:
> "Most of my concurrency is asyncio, because my workloads are I/O-bound: DB, Redis, LLM APIs, webhooks. I've used threads indirectly, `run_in_threadpool` for blocking libraries in FastAPI. For CPU-bound work like parsing a big CSV import or generating reports I'd use multiprocessing because the GIL stops threads running Python bytecode in parallel. Each process has its own interpreter and GIL."

### Q9. Async Python
Your strongest area; the screener already rated it well. Key line:
> "Yes, in production every service is async FastAPI with asyncpg and async Redis. If you put blocking code in an async app, it blocks the single event loop thread, so **every** concurrent request on that worker stalls, not just the slow one. I actually diagnosed this: a sync DB driver inside async endpoints. Fixes: use async drivers, offload with `run_in_threadpool` / `asyncio.to_thread`, push heavy work to a queue worker, or for CPU-bound work a process pool. Also, in FastAPI a plain `def` endpoint runs in a threadpool automatically, so a blocking call is safer in `def` than in `async def`."

---

## 3. FastAPI / REST APIs

### Q10. One API you built + auth, validation, errors
Use the **pipeline submit API** or **Recurring's sync API**.
- **Auth:** JWT access (short-lived) + refresh with rotation and revocation; change-password revokes all sessions; argon2 hashing; per-IP rate limit on auth routes. `Depends(get_current_user)` decodes and checks the token; RBAC via role dependency.
- **Validation:** Pydantic request/response models (types, constraints, enums); `response_model` stops leaking fields.
- **Errors:** custom exception hierarchy + global handlers, consistent error JSON, 409 with current row on stale updates, idempotent creates via client-generated UUID (retry returns 200, not a duplicate).

### Q11. Changing a response without breaking web + mobile
> "Mobile is the hard constraint because old app versions live for months. Rule one: **additive changes only** on the existing contract: add new fields, never rename, remove or change the type of existing ones. If the shape genuinely has to break, I version it: `/v2/...` or a version header, and keep v1 running. Then deprecate: mark it in OpenAPI docs, add a `Deprecation`/`Sunset` header, log which clients still hit v1, use a minimum-supported-app-version check to force upgrades, and only remove v1 when traffic is near zero."
Your experience: you've been the Flutter client *and* the backend, so you've felt this from both sides.

### Q12. 10-minute request: keep HTTP open?
No. This is literally your pipeline:
> "`POST /jobs` validates, writes a job row with status `queued`, enqueues it, returns **202** with a job id. Workers process it and update status/progress. Client either polls `GET /jobs/{id}`, subscribes over SSE/WebSocket, or gets a webhook on completion. Workers are idempotent and retry safely, and a stuck-job sweeper requeues jobs whose heartbeat stopped. In Vaidya AI it's run id → Redis workers → SSE progress."
Why not keep it open: proxies/load balancers time out (Nginx default 60s), a deploy kills it, mobile networks drop, and it ties up a worker slot.

---

## 4. Databases

### Q13. Which DBs?
> "PostgreSQL deeply: schema design, indexes, transactions, atomic updates, state machines in SQL, connection pooling, raw SQL with asyncpg and hand-written migrations, Neon. Redis for queues, caching, rate limits and blocklists. **MongoDB I haven't used in production**, but I know the model: documents, embedding vs referencing, indexes and the aggregation pipeline." Prepare the Mongo basics in Q15 so that "no" doesn't end the conversation.

### Q14. Report API went from 2s to 40s
Structured approach (say it as steps):
1. **What changed?** Recent deploy, data growth, new filter, traffic spike, other jobs running at the same time. "Suddenly" points to a deploy, a lost index, or plan flip.
2. **Measure where time goes:** request logs/APM by span: DB vs app vs external calls. Count queries per request.
3. **DB:** `EXPLAIN (ANALYZE, BUFFERS)` on the slow query. Look for seq scans on large tables, bad row estimates (stale stats, run `ANALYZE`), sorts spilling to disk, missing composite index on the filter + sort columns.
4. **App-side smells:** N+1 queries inside a loop, `SELECT *` pulling unused columns/blobs, no pagination, Python-side aggregation that should be SQL `GROUP BY`.
5. **Contention:** locks from long transactions, pool exhaustion (your "pool capped at 10" story), a heavy batch job on the same DB.
6. **Fix + prevent:** add index, rewrite query, paginate, pre-aggregate (materialized view refreshed periodically or a summary table), cache with TTL, move heavy reports to a read replica or async export job. Add a slow-query log/alert.

### Q15. MongoDB vs SQL, real trade-offs
- **Schema:** SQL enforces schema + constraints (FK, unique, check) in the DB; Mongo is flexible per document, so validation moves to the app (or JSON schema validators). Flexible is great for varying form data, e.g. lead custom fields per institution in a CRM.
- **Relations:** SQL joins across normalized tables; Mongo favours **embedding** data read together (lead + its notes) and `$lookup` is comparatively limited/expensive. Model around access patterns.
- **Transactions:** Postgres ACID across any rows by default. Mongo: single-document writes are atomic; multi-document transactions exist (replica sets, 4.0+) but cost more, so you design so one business operation touches one document. Your wallet deduction would be `findOneAndUpdate({_id, balance: {$gte: amt}}, {$inc: {balance: -amt}})`.
- **Scaling:** Mongo has built-in horizontal sharding; Postgres scales vertically + read replicas, with sharding via Citus/partitioning.
- **Querying/reporting:** SQL is better for ad-hoc analytics; Mongo uses the aggregation pipeline (`$match → $group → $sort`).
- Postgres `JSONB` + GIN index gives you document flexibility inside SQL, often the pragmatic middle ground.

---

## 5. Celery / Redis / Background Jobs

(The recruiter's list was cut off at Q16; this covers the usual set.)

### Q16. Have you used Celery?
> "I've built the same pattern with Redis queues and my own workers: the API enqueues, workers consume, results/progress go back through Redis and SSE. I haven't run Celery in production, but it's the same architecture packaged: **producer** (your app calls `task.delay()`), **broker** (Redis or RabbitMQ holds messages), **workers** (separate processes executing tasks), **result backend** (optional, stores return values), **Celery Beat** for scheduled tasks."

Celery details to know:
- `@app.task(bind=True, autoretry_for=(TimeoutError,), retry_backoff=True, max_retries=5)`
- `acks_late=True` + idempotent tasks = a crashed worker's task is redelivered instead of lost (at-least-once delivery → make tasks idempotent with a dedupe key, exactly your idempotency experience).
- `worker_prefetch_multiplier=1` for long tasks so one worker doesn't hoard work.
- Separate **queues** by priority (`otp` vs `bulk_email`) with dedicated workers so bulk jobs never delay OTPs.
- Canvas: `chain` (sequential), `group` (parallel), `chord` (parallel then callback).
- Pass IDs, not big objects, as task args. Don't wait on a task's result inside another task.
- Monitoring: Flower; dead-letter / failed-task table.
- Alternatives: RQ, Dramatiq, arq (asyncio-native), FastAPI `BackgroundTasks` (in-process, lost on restart, only for tiny fire-and-forget work).

### Redis roles
Broker/queue, cache (cache-aside with TTL, invalidate on write), rate limiting (`INCR` + `EXPIRE`, or sliding window with sorted sets), distributed locks (`SET key val NX PX 30000`), pub/sub for fan-out (SSE/WebSocket across instances), session/token blocklist (your Apple Sign-In story), idempotency keys.

---

## 6. Weak Areas Deep Dive

### 6.1 Large-scale data processing

**Mental model:** memory, throughput, failure. Bound memory by streaming; raise throughput by batching and parallelism; survive failure with checkpoints + idempotency.

**Reading millions of rows without loading them:**
```python
# Keyset pagination: stable and fast at any depth (OFFSET gets slower as it grows)
async def iter_leads(pool, tenant_id, batch=5000):
    last_id = 0
    while True:
        rows = await pool.fetch(
            "SELECT id, email, name FROM leads "
            "WHERE tenant_id = $1 AND id > $2 ORDER BY id LIMIT $3",
            tenant_id, last_id, batch)
        if not rows:
            return
        yield rows
        last_id = rows[-1]["id"]

async for batch in iter_leads(pool, tid):
    await process(batch)          # memory stays ~one batch
```
- Server-side cursors (`conn.cursor()` in asyncpg inside a transaction; named cursor in psycopg2) also stream.
- Files: iterate line by line (`for line in f`), `csv.reader`, `pandas.read_csv(chunksize=...)`, never `f.read()` on a 5GB file.
- **Why keyset > OFFSET:** `OFFSET 1_000_000` makes the DB scan and discard a million rows each page; `WHERE id > last_id` uses the index.

**Writing fast:** batch inserts (`executemany`, multi-row `INSERT`), `COPY` (asyncpg `copy_records_to_table`) for bulk loads, 10-100× faster than row-by-row. Upsert with `INSERT ... ON CONFLICT DO UPDATE` to make re-runs idempotent. Commit per batch, not per row and not one giant transaction.

**Parallelism:** I/O-bound batches → asyncio with a `Semaphore` to cap concurrency; CPU-bound → `ProcessPoolExecutor`; across machines → split into chunk jobs on a queue (each job = id range), many workers consume.

**Reliability:** checkpoint `last_id` per job so a crash resumes instead of restarting; idempotent writes; a dead-letter table for bad rows instead of failing the whole import; progress = processed/total in the job row.

**Example story for Headstart:** "An institution uploads a 2-million-row lead CSV." Upload to S3/R2 via signed URL (not through the API), API creates an import job and returns 202, worker streams the file in 10k-row chunks, validates each row with Pydantic, bad rows go to an error report, good rows `COPY` into a staging table then upsert into `leads` by `(tenant_id, email)`, progress over SSE, user downloads the error CSV at the end.

**Memory tools to name:** generators, `itertools.islice` for batching, `__slots__` for many small objects, `tracemalloc` to profile.

### 6.2 Concurrency: threads vs processes vs async

**The GIL:** CPython's Global Interpreter Lock lets only one thread execute Python bytecode at a time per process. It's released during blocking I/O (and inside many C extensions like NumPy), so threads still help for I/O, not for pure-Python CPU work. (Python 3.13 has an experimental free-threaded build; mention only if asked, it isn't the default yet.)

| | Threading | Multiprocessing | asyncio |
|---|---|---|---|
| Best for | I/O-bound with blocking libraries | **CPU-bound** | I/O-bound at high concurrency |
| Parallel CPU? | No (GIL) | Yes, one GIL per process | No, single thread |
| Memory | Shared, cheap | Separate per process, heavy | Shared, cheapest |
| Data sharing | Shared objects + locks | Must pickle across processes (Queue, Pipe, shared memory) | Shared, no locks needed between awaits |
| Startup cost | Low | High (spawn/fork) | Very low (coroutines) |
| Scale | Hundreds of threads | ~number of cores | Tens of thousands of tasks |
| Risks | Race conditions, deadlocks | Pickling overhead, high memory | One blocking call stalls everything |

```python
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

# I/O-bound: blocking HTTP library
with ThreadPoolExecutor(max_workers=20) as ex:
    results = list(ex.map(fetch_url, urls))

# CPU-bound: parse/score/resize
if __name__ == "__main__":                      # required on spawn (macOS/Windows)
    with ProcessPoolExecutor() as ex:           # defaults to CPU count
        results = list(ex.map(score_chunk, chunks, chunksize=10))

# Mixing with asyncio
loop = asyncio.get_running_loop()
await asyncio.to_thread(blocking_call)                        # threads
await loop.run_in_executor(process_pool, cpu_heavy, data)    # processes
```
**Decision line:** "Is the time spent waiting or computing? Waiting → async (or threads if the library is blocking). Computing → processes. Both → async front, process pool or a separate worker service behind it."
Also know: gunicorn/uvicorn **workers are processes**, so a FastAPI deployment already uses multiprocessing at the server level (e.g. `uvicorn --workers 4`, or `2×cores+1` gunicorn rule of thumb), and each worker runs its own event loop. Celery workers default to a **prefork process pool** for the same reason.
Race-condition example: two threads doing `counter += 1` lose updates because it's read-modify-write; fix with `threading.Lock`, or better, avoid shared state. Same bug class as your wallet fix, just in memory instead of the DB.

### 6.3 Multi-tenant architecture

You *have* built this (Manpower Management: 6+ companies, 4-level RBAC), so claim it and explain the trade-offs. For Headstart, each **institution is a tenant**.

**Three isolation models:**

| Model | How | Pros | Cons | When |
|---|---|---|---|---|
| Shared DB, shared schema | `tenant_id` column on every table | Cheapest, simplest ops, easy cross-tenant analytics | One missed `WHERE tenant_id` = data leak; noisy neighbours | Many small tenants (most SaaS, likely Headstart) |
| Shared DB, schema per tenant | Postgres schema per tenant, `SET search_path` | Better isolation, per-tenant restore | Migrations × N schemas, connection/catalog bloat at thousands of tenants | Tens–hundreds of mid-size tenants |
| DB per tenant | Separate database | Strongest isolation, per-tenant scaling/compliance | Expensive, complex routing and migrations | Few large/enterprise tenants with compliance needs |

Hybrid is common: shared for most, dedicated DB for a big university that pays for it.

**Making shared-schema safe (what to say you did / would do):**
1. **Tenant resolution** once per request: from JWT claim (`tenant_id` in token), subdomain (`abc-college.headstart.app`) or header; middleware puts it in a request context (`contextvars`).
2. **Enforce in one place:** repositories always take/inject `tenant_id`; never trust a tenant id from the request body.
3. **Defence in depth: Postgres Row-Level Security.**
   ```sql
   ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
   CREATE POLICY tenant_isolation ON leads
     USING (tenant_id = current_setting('app.tenant_id')::uuid);
   -- per request/transaction:
   SET LOCAL app.tenant_id = '...';
   ```
   Even a buggy query can't read another tenant's rows.
4. **Indexes lead with tenant_id:** `(tenant_id, created_at)`, `(tenant_id, email)` unique, because almost every query filters by tenant. Partition big tables by tenant or time when they get huge.
5. **Uniqueness is per tenant:** `UNIQUE (tenant_id, email)`, not global.
6. **Noisy neighbour control:** per-tenant rate limits and quotas; per-tenant queues or fair scheduling so one college's 1M-email campaign doesn't starve others; per-tenant job concurrency caps.
7. **Cache keys and storage paths namespaced:** `tenant:{id}:...` in Redis, `/{tenant_id}/docs/...` in R2/S3 with signed URLs.
8. **RBAC within a tenant:** roles are tenant-scoped (admin of college A is nobody in college B); super-admin is a separate platform role.
9. **Tests:** an automated test that user from tenant A gets 404 (not 403, don't confirm existence) on tenant B's resource for every endpoint.
10. **Per-tenant config/features:** settings table or feature flags, e.g. custom lead fields stored as JSONB.

**Spoken summary:**
> "In Manpower Management I used a shared schema with `tenant_id` on every table, resolved from the JWT, enforced in the repository layer, with 4-level RBAC scoped to the company. For a CRM at Headstart's scale I'd keep shared schema for most institutions, add Postgres RLS as a safety net, lead every index with tenant_id, and add per-tenant rate limits and queue fairness so one big campaign can't hurt other tenants. Very large or compliance-heavy institutions could move to a dedicated database behind the same routing layer."

---

## 7. Client Question Bank

### 7.1 WebSockets vs Django Channels
- **WebSocket** is the *protocol*: a persistent, full-duplex TCP connection upgraded from HTTP (`Upgrade: websocket`, 101 Switching Protocols). Both sides push any time. Alternatives: SSE (server → client only, plain HTTP, auto-reconnect, which is what you used for pipeline progress), long polling.
- **Django Channels** is a *library* that lets Django handle WebSockets (and other long-lived protocols). Django is WSGI (sync, one request → one response); Channels moves it to **ASGI** (run with Daphne/Uvicorn) and adds:
  - **Consumers** (like views for a connection): `connect`, `receive`, `disconnect`; `AsyncWebsocketConsumer`.
  - **Routing** (`URLRouter` for ws paths) + `AuthMiddlewareStack` for user auth on the socket.
  - **Channel layer** (backed by **Redis**, `channels_redis`): lets any process send to a socket held by *another* process, and **groups** for broadcast (e.g. `group_send("ticket_123", ...)`).
- So: "WebSocket is the transport; Channels is Django's way to speak it and to fan messages out across many server processes via Redis."
- Your parallel: in FastAPI you get WebSockets natively (`@app.websocket`), and for multi-instance broadcast you'd add Redis pub/sub yourself, the same job Channels' channel layer does.
- Scaling notes: sticky sessions not required if state lives in Redis; load balancer must support upgrade (Nginx `proxy_set_header Upgrade/Connection`); heartbeats/ping to detect dead connections.

```python
class TicketConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.group = f"event_{self.scope['url_route']['kwargs']['event_id']}"
        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()
    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.group, self.channel_name)
    async def seats_update(self, event):            # handler for group_send type "seats.update"
        await self.send(text_data=json.dumps(event["data"]))
```

### 7.2 Django signals, indexing, API response optimization
**Signals:** observer pattern; decoupled hooks fired on events. Built-ins: `pre_save`, `post_save`, `pre_delete`, `post_delete`, `m2m_changed`, `request_started/finished`; custom via `Signal()`. Receiver with `@receiver(post_save, sender=Lead)`; connect in `AppConfig.ready()`.
- Use for: cache invalidation, audit logs, creating a profile when a user is created.
- Caveats (interviewers love these): run **synchronously in the same transaction/request**, so a slow receiver slows the request; **not fired by `queryset.update()` or `bulk_create`**; hidden control flow makes debugging hard. For side effects like emails, use `transaction.on_commit(lambda: send_email.delay(id))` so the task only runs if the commit succeeds, and prefer explicit service calls for core business logic.

**Indexing in Django:** `db_index=True`, `unique=True`, `Meta.indexes = [models.Index(fields=["tenant", "-created_at"])]`, `UniqueConstraint`, partial indexes `Index(..., condition=Q(status="active"))`, `GinIndex` for JSON/full-text. FKs get an index automatically. Check with `queryset.explain()`.

**API response optimization:**
1. Kill N+1: `select_related` (FK/one-to-one, SQL JOIN) and `prefetch_related` (M2M/reverse FK, second query + Python join).
2. Fetch less: `only()/defer()`, `values()/values_list()`, serializer with only needed fields.
3. Paginate (cursor pagination for large/real-time lists).
4. DB-side work: `annotate`, `aggregate`, `Count`, `F` expressions instead of Python loops.
5. Indexes for filter/order columns.
6. Caching: per-view, low-level `cache.get/set` in Redis, cache invalidation via signals or on write; HTTP caching (ETag, Cache-Control).
7. Compression (GZip middleware), smaller payloads.
8. Move slow work to Celery; return 202.
9. Measure: Django Debug Toolbar / django-silk, query counts in tests (`assertNumQueries`).

Honest line: "My production work is FastAPI rather than Django, but these concepts are the same ones I apply with raw SQL; in Django they're ORM features."

### 7.3 Ticketing system: architecture + concurrency
Clarify first: event tickets (BookMyShow-style, seats are scarce) or support tickets? Default to booking. Core problem: **two users must never get the same seat, and the system must survive a spike when sales open.**

**Components:** API servers (stateless, behind LB) · Postgres (source of truth) · Redis (seat holds, cache, rate limits, waiting room) · queue + workers (payment confirmation, emails, PDF tickets) · payment gateway with webhooks · WebSocket/SSE for live seat map.

**Flow:**
1. User picks seats → **hold** for ~10 min (status `HELD`, `held_until`, `hold_id`).
2. Payment initiated with an **idempotency key**.
3. Payment webhook (HMAC-verified) → `HELD → BOOKED`. Expiry job releases `HELD` seats past `held_until`. State machine allows only `AVAILABLE → HELD → BOOKED` or `HELD → AVAILABLE`, same as your billing webhook state machine.

**Concurrency options (know all, pick one):**
- **Atomic conditional update (simplest, my default):**
  ```sql
  UPDATE seats SET status='HELD', hold_id=$1, held_until=now()+interval '10 min'
  WHERE event_id=$2 AND seat_id = ANY($3) AND status='AVAILABLE';
  -- if rowcount != requested count → roll back, seats taken
  ```
  Exactly your wallet trick: the check and the write are one statement.
- **Pessimistic lock:** `SELECT ... FOR UPDATE` in a transaction; add `SKIP LOCKED` for "give me any N free seats" (general admission) so buyers don't queue on the same rows; lock rows in a consistent order (sort seat ids) to avoid deadlocks.
- **Optimistic lock:** `version` column, `UPDATE ... WHERE version = $v`; retry on 0 rows. Good when conflicts are rare.
- **Unique constraint as the final guard:** `UNIQUE(event_id, seat_id)` on bookings, so even a bug can't double-book.
- **Redis hold:** `SET seat:{event}:{seat} {user} NX EX 600` for a fast hold layer; DB stays authoritative.
- For hot sales (100k users for 1k seats): **virtual waiting room / queue** admitting users at a fixed rate, per-user rate limits, cached seat map pushed over WebSocket, inventory counter in Redis (`DECR`) to reject quickly before touching Postgres.

### 7.4 Finding and fixing N+1 queries
**What:** 1 query for the list + N queries, one per row, for a related object. 100 leads → 101 queries.
**Spot it:** query count per request in logs/APM, Django Debug Toolbar / silk, SQLAlchemy `echo=True`, pg_stat_statements showing the same query run thousands of times, a test asserting query count.
**Fix:**
- ORM eager loading: Django `select_related` / `prefetch_related`; SQLAlchemy `joinedload` / `selectinload`.
- Raw SQL (what you do): one `JOIN`, or fetch children with `WHERE parent_id = ANY($1)` and group in Python; or `json_agg` to return nested data in one query.
- Batch loading (DataLoader pattern) for GraphQL-like resolvers.
- Prevent: `assertNumQueries` in tests; review loops containing DB calls in code review.

### 7.5 How indexing works and when to avoid it
- **B-tree** (default): balanced sorted tree, lookups/ranges/sorting in O(log n) instead of a full O(n) scan. Leaf entries point to heap rows.
- **Composite index** `(tenant_id, status, created_at)`: usable by left-most prefix; put equality columns first, range/sort column last.
- **Covering index** `INCLUDE (name)` → index-only scan, no heap visit.
- Other types: Hash (equality only), **GIN** (JSONB, arrays, full-text), GiST (geo/ranges), BRIN (huge append-only time-series, tiny index).
- **Partial index** `WHERE status = 'active'` / `WHERE deleted_at IS NULL`: smaller, and fits your soft-delete pattern.
- Index killers: function on column (`WHERE lower(email)=...` needs an expression index), leading wildcard `LIKE '%abc'`, implicit type casts, `OR` across columns.

**When to avoid / be careful:**
- Write-heavy tables: every insert/update must update every index (slower writes, more WAL).
- Low-cardinality columns alone (`is_active`, `gender`): planner will scan anyway; use a partial index instead.
- Small tables: seq scan is faster.
- Columns never filtered/sorted on; duplicate or overlapping indexes (`(a)` is redundant if `(a, b)` exists).
- Bulk loads: drop/disable, load, recreate.
- Verify with `EXPLAIN ANALYZE`; find unused ones via `pg_stat_user_indexes.idx_scan = 0`.

### 7.6 Multithreading vs multiprocessing
See [6.2](#62-concurrency-threads-vs-processes-vs-async) table and decision line.

### 7.7 Roles of async/await, Redis and Celery
> "They solve different layers. **async/await** makes one process handle thousands of concurrent *I/O waits* inside the request; it doesn't make anything run later or survive a crash. **Celery** moves work *out of* the request into separate worker processes, with retries, scheduling and scaling independently of the web tier. **Redis** is the glue: Celery's broker (and result backend), plus cache, rate limiter, locks and pub/sub."
Example: OTP request → async endpoint validates, writes OTP to Redis with TTL, enqueues `send_otp` task, returns in ~ms. Worker sends the email with retries. That is your 8–10s → 500ms fix.
When *not* to use Celery: tiny fire-and-forget work (FastAPI `BackgroundTasks` is fine), or when you need a response in the same request.

### 7.8 Sending 1K emails vs 10M emails
Frame it as: **what breaks as you scale?** (time, provider limits, failures, duplicates, reputation, cost).

**1K emails:**
- One Celery/worker task per campaign or per small batch; loop and send through a provider (SES/SendGrid). Takes a minute or two.
- Template rendering, retry on failure, log status. Done; don't over-engineer.

**10M emails:**
1. **API:** `POST /campaigns/{id}/send` → 202. Campaign row with status + counts.
2. **Fan-out in stages:** a *planner* task streams recipients by keyset pagination and enqueues **batch jobs of ~500–1000 recipient IDs** (not 10M individual tasks, not one giant task). Pass IDs, not payloads.
3. **Send via provider bulk APIs** (SES bulk templated send, up to 50 destinations per call; SendGrid personalizations, up to 1000 per call) over connection pools; async I/O inside workers for high throughput.
4. **Throttle to the provider's rate limit** with a Redis token bucket shared across workers (e.g. SES account limit N/sec); 10M at 1,000/s ≈ 2.8 hours, so state the arithmetic.
5. **Idempotency:** `email_sends(campaign_id, recipient_id)` with a unique constraint; a retried batch skips already-sent recipients. At-least-once queue + dedupe = effectively once (your resume phrase).
6. **Retries:** exponential backoff for 429/5xx; permanent failures (bad address) are never retried; dead-letter queue.
7. **Horizontal scaling:** add workers; dedicated `bulk` queue separate from transactional (`otp`, password reset) so campaigns never delay OTPs; **per-tenant fairness** so one institution's campaign doesn't monopolise workers.
8. **Deliverability:** SPF/DKIM/DMARC, warm-up dedicated IPs, honour unsubscribes and suppression lists (bounces/complaints via provider webhooks → mark contact).
9. **Tracking:** open/click via provider webhooks into a queue, aggregated into counts (don't update the campaign row 10M times; batch increments or Redis counters flushed periodically).
10. **Observability + control:** progress %, sent/failed/bounced, pause/resume/cancel (workers check campaign status per batch), alerts on bounce-rate spikes.
11. **Scheduling:** Celery Beat / scheduled jobs, send in recipient's timezone if needed.

One-liner close: "1K is a loop in a background task; 10M is a pipeline: chunked fan-out, rate-limited workers, idempotent sends, separate queues, and feedback via webhooks."

---

## 8. Questions to Ask Them
- What's the current stack: Django or FastAPI, Postgres or Mongo, and how is multi-tenancy handled today?
- What scale are you at: institutions, leads, emails/SMS per month?
- What's the biggest technical problem the backend team is facing right now?
- How do code reviews and deployments work; what does on-call look like?
- What would success look like in the first 90 days for this role?
