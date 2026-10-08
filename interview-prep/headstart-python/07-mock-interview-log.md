# 07 · Mock Interview Log (2026-10-08)

Every question from the mock round, your score, and the model answer to rehearse. **[fill: …]** marks facts only you know. Check every "your story" line against what really happened before you use it.

| # | Topic | Score | Main fix |
|---|---|---|---|
| Q1 | Project pitch | 2/5 | Say what the product does and who uses it; group your work; "I built" |
| Q1b | Ownership follow-up | 3/5 | Name one concrete failure it caught; don't call Firebase "OpenTelemetry" |
| Q2 | Largest system / scale | — | Don't say "no scaling issues, we add pods"; use your performance stories |
| Q3 | Multithreading / multiprocessing | — | Honest "not in production" + GIL + I/O vs CPU decision |
| Q4 | Multi-tenant isolation | — | RBAC ≠ tenant isolation; tenant from JWT, every query scoped |
| Q5 | 2M-row CSV import | 2/5 | Queue one job, stream the file in chunks, bulk upsert, checkpoints |
| Q6 | Fibonacci | — | Naive → memo → tabulation → O(1) → O(log n), complexity each step |
| Q7 | Right-shift by 1 | 3.5/5 | Write the code and say the complexity of each approach |
| Q8 | 1K vs 10M emails | — | Time, limits, failures, duplicates → one fix each |
| Q9 | Blocking code in async | 3/5 | Say "the whole event loop stalls" and tell your production story |
| Q10 | N+1 queries | 2.5/5 | 1 + N queries from a loop, not "reading the whole table" |
| Q11 | Indexing | skipped | See [05-indexing-deep-dive.md](05-indexing-deep-dive.md) |
| Q12 | Pool sizing (3×4×20 vs 100) | 3/5 | Do the maths aloud, name the symptom, fixes in order |
| Q13 | API change without breaking clients | 3/5 | Additive first, version second, deprecation plan, nullable Flutter models |
| Q14 | Report 2s → 40s | — | change → measure → DB → app → contention → fix → prevent |
| Q15 | OOP real example | — | See answer below |

---

## Q1 · Project pitch
> "I work on two products for Fractal: Vaidya, a healthcare AI app, and Vaidya Insurance. On Vaidya I built the subscription billing on Razorpay and the ABDM integration, which links users' ABHA health IDs, and I own the auth service. On Vaidya Insurance I built the platform APIs, including auth, and the gateway between the UI and the AI services. The UI never calls the AI services directly. Every request goes through my layer, which handles auth, validation and errors. The piece I'm proudest of is billing: I made the credit wallet safe against concurrent spends and made subscription webhooks idempotent."

[fill: who the users are] · check the ABDM line matches what you did.

## Q1b · "What wouldn't exist without you?"
> "Early on, when a user reported a failure, we were guessing: no breadcrumbs, no idea how many users were affected. I proposed adding observability to the Vaidya app, took it to the PM and built it: Crashlytics for crashes and non-fatal errors, breadcrumbs and custom keys like user id and API endpoint, Analytics events for API failures, and Performance Monitoring for slow requests. After that we could see exactly which users hit a failure and what happened just before. For example, [fill: the specific bug it uncovered]. It turned bug reports from guesswork into data."

Never say "anyone could have done" any part of your work. Keep a backend ownership story ready too (wallet concurrency, sync driver fix).

## Q2 · Largest system and its scaling problems
> "The largest is Vaidya: roughly 1 million registered users, with [fill: daily active users or requests per day] active. It isn't a huge-traffic system, so we scale horizontally by adding pods. What I learned is that adding pods doesn't fix everything, and the problems I hit were about efficiency, not raw traffic.
> First, a synchronous DB driver called inside async FastAPI endpoints blocked the event loop, so one slow query stalled every request on that worker. We moved to an async driver and pushed blocking calls off the loop.
> Second, the connection pool was capped at 10 per service, so requests queued for a connection. Adding pods would have made it worse, because each pod opens its own pool and can exhaust Postgres's connection limit. You size the pool against the database's limit.
> Third, OTP delivery took 8 to 10 seconds because a third-party email call sat on the request path. Moving it to a background worker brought it to about 500 milliseconds.
> On Manpower, a multi-tenant system for six companies, documents stored as Postgres blobs made file reads compete with transactional queries. Moving them to object storage with signed URLs fixed that."

[fill: is 1M registered or monthly active?]

## Q3 · Multithreading / multiprocessing
> "I haven't written explicit multithreading or multiprocessing code in production, because my workloads are I/O-bound: database, Redis, LLM APIs, webhooks. For that, asyncio is the right tool. But I've worked with both models. Our Redis workers run as separate processes from the API, and we scale with multiple pods, which is process-level parallelism. When I fixed the sync DB driver, the options were an async driver or running the blocking call in a thread pool, which is the threading use case.
> The GIL lets only one thread run Python code at a time, but it's released while waiting on I/O. So threads help with blocking I/O libraries but not CPU work. For CPU-heavy work, like parsing a big CSV import or generating PDFs, I'd use a ProcessPoolExecutor, ideally in a background worker. Each process has its own GIL, at the cost of more memory and pickling data between processes."

Homework: benchmark a CPU-heavy function sequential vs `ThreadPoolExecutor` vs `ProcessPoolExecutor`.

## Q4 · Multi-tenant isolation
**RBAC decides what a user can do. Tenant isolation decides whose data they can see.** You need both.
> "Manpower uses a shared database with a `company_id` on every tenant-owned table. The tenant comes from the verified JWT, never the request body. Every repository method takes `company_id` and adds `WHERE company_id = $1`, including joins; another company's record returns 404, not 403. RBAC sits on top: the 4-level roles decide what each user can do within their company. To harden it I'd add Postgres row-level security, start every index with `company_id`, and make uniqueness per tenant.
> If one tenant grows 100 times larger: protect the others with per-tenant rate limits and per-tenant queues or concurrency caps; partition their big tables; and if needed move just that tenant to its own database behind the same routing layer."

[fill: confirm `company_id` columns and that it's in the JWT]

## Q5 · Importing a 2-million-row CSV
**Queue one job, not 2 million rows.**
1. Client uploads straight to S3/R2 with a presigned URL.
2. `POST /imports` creates a job row and enqueues the id; returns **202 + job id**.
3. Worker streams the file with a generator, ~5,000 rows per batch.
4. Validate each row with Pydantic; bad rows go to an error list with line numbers.
5. Bulk write (batch insert or `COPY`), `ON CONFLICT (tenant_id, email) DO UPDATE` so retries don't duplicate.
6. Update progress and a checkpoint after each batch; resume after a crash.
7. Finish with counts and a downloadable error CSV. Parallelise chunks across workers if needed.

Pattern for any big-data question: **don't block the request → stream → batch writes → idempotent → progress + resume → parallelise.**

## Q6 · Fibonacci
See [01-dsa-cpp.md §1](01-dsa-cpp.md). Say: naive O(2ⁿ) because of overlapping subproblems → memo O(n)/O(n) → tabulation O(n)/O(n), no recursion → two variables O(n)/O(1) (final answer) → mention O(log n) fast doubling. `long long` overflows after F(92).

## Q7 · Right-shift by 1
New array O(n)/O(n) → swap from the end O(n)/O(1) → cleanest: save last, shift right walking backwards, put last at index 0. Follow-up by k: `k %= n`, reverse all, reverse first k, reverse rest. See [01-dsa-cpp.md §2](01-dsa-cpp.md).

## Q8 · 1K vs 10M emails
**What breaks at scale: time, provider limits, failures, duplicates.**
- 1K: API returns immediately; one background job loops and sends with retries (like the OTP fix).
- 10M: 202 → planner job pages recipients → batches of ~1,000 ids on a queue → many workers using bulk send APIs → shared Redis rate limiter (10M at 1,000/s ≈ 3 hours) → `sent_emails` unique key for idempotency → retries with backoff + dead-letter queue → separate queue from OTPs + per-institution fairness → bounces/unsubscribes via webhooks → progress, pause, cancel.

**Follow-ups you asked:**
- *Duplicate webhooks:* unique `processed_events(event_id)` inserted in the same transaction as the state change; conflict = duplicate → 200, do nothing. Forward-only state machine.
- *Queue/partial failures:* ack only after work → redelivery; per-recipient idempotency; **outbox pattern** if Redis is down at enqueue; heartbeat + sweeper for stuck jobs.
- *3 hours too long for a sale:* raise quota or add providers, prioritise engaged users, pre-render emails and codes before launch, push/SMS for urgent; staggering also protects the site from a click spike.

## Q9 · Blocking code in async FastAPI
> "Blocking code in an `async def` endpoint blocks the event loop. There's one loop per worker process, so every request on that worker freezes, not just the slow one. I hit this in production: a sync DB driver inside async endpoints. Fixes: async driver like asyncpg; `await asyncio.to_thread(...)`; make the endpoint plain `def` so FastAPI runs it in its thread pool; or move heavy work to a background worker."

## Q10 · N+1 queries
**Simple version:** it's like going to the shop once for the shopping list, then making a separate trip for every item on it. 1 query for the list + N queries, one per item, usually because there's a query inside a loop. 100 leads → 101 queries.
> "To spot it: count queries per request in logs or APM; if the count grows with page size, it's N+1. `pg_stat_statements` shows the same small query thousands of times. In code review, any DB call inside a loop. To fix: one JOIN, or fetch all related rows at once with `WHERE id = ANY($1)` and match in Python. ORMs: `select_related`/`prefetch_related` in Django, `joinedload`/`selectinload` in SQLAlchemy. Prevent it with a test asserting query count."

```python
# N+1
leads = await conn.fetch("SELECT id, name, counsellor_id FROM leads WHERE tenant_id=$1", tid)
for l in leads:
    c = await conn.fetchrow("SELECT name FROM users WHERE id=$1", l["counsellor_id"])   # runs N times
# Fixed: 1 query
rows = await conn.fetch("""SELECT l.id, l.name, u.name AS counsellor
    FROM leads l LEFT JOIN users u ON u.id = l.counsellor_id WHERE l.tenant_id = $1""", tid)
```

## Q12 · Pool sizing: 3 pods × 4 workers × 20 vs limit 100
> "That's 240 possible connections against 100. Pools open lazily, so it works at low traffic and breaks under load: Postgres rejects new connections ('too many clients'), requests 500 or hang, and autoscaling makes it worse. Fixes: size pools from the DB limit (~90 usable ÷ 12 workers ≈ 7 each); PgBouncer in transaction mode (`statement_cache_size=0` for asyncpg); short transactions and never hold a connection during external calls; cap autoscaling and use read replicas; monitor pool wait time and `pg_stat_activity`."

Pattern: **numbers → symptom → fixes by effort → real story.**

## Q13 · Changing a response without breaking web and mobile
> "Mobile is the constraint: old app versions live for months. 1) Additive changes only: add fields, never rename, remove or retype. 2) Version only for real breaking changes: `/v2` router sharing the same service layer, keep v1. 3) Deprecate deliberately: OpenAPI deprecation, `Deprecation`/`Sunset` headers, log v1 usage by app version, minimum-supported-version check, remove at near-zero traffic. 4) Tolerant clients: in our Flutter apps every model field is nullable and unknown fields are ignored."

## Q14 · Report API went from 2s to 40s
**Your instinct, "log each step and see which takes the time", is the right one.** That's step 2. Make it precise:

1. **What changed?** Deploy, data growth, new filter, traffic, a batch job.
2. **Measure each step.** Time every stage with the request id in structured logs. Better still, use **tracing** (OpenTelemetry spans), which shows a timeline of every DB query and external call per request without hand-adding logs everywhere. Also log **query count per request**.
   ```python
   import time, logging
   from contextlib import contextmanager
   log = logging.getLogger("timing")

   @contextmanager
   def step(name, request_id):
       start = time.perf_counter()
       try:
           yield
       finally:
           log.info("step=%s ms=%.1f request_id=%s", name, (time.perf_counter() - start) * 1000, request_id)

   with step("fetch_leads", rid):     rows = await repo.fetch(...)
   with step("aggregate", rid):       report = build_report(rows)
   with step("serialize", rid):       body = ReportOut.model_validate(report)
   ```
3. **Then look at the slowest step by type:**
   - **DB query:** `EXPLAIN (ANALYZE, BUFFERS)`: seq scan on a big table, missing index, sort spilling to disk, stale stats (`ANALYZE`).
   - **Many small DB calls:** query count grows with data → N+1 → JOIN or batch.
   - **External API:** add a timeout, call concurrently with `asyncio.gather`, cache, or move off the request path.
   - **Python CPU** (aggregating in a loop): move the work into SQL `GROUP BY`, or profile with `cProfile`/`py-spy`.
   - **Waiting, not working** (time gaps between steps): pool exhaustion or locks → check pool wait time and `pg_stat_activity`.
4. **Fix the biggest cost first.** If the report is inherently heavy: summary table or materialized view, cache with TTL, read replica, or async export (202 → job → download link).
5. **Prevent:** slow-query log, latency alert on the endpoint, a load test in CI for critical reports.

Memory hook: **change → measure → DB → app → contention → fix → prevent.**

## Q15 · OOP: a real example
**Answer pattern:** name the problem → the classes → which pillar → why it helped.
> "Yes. My backends follow Clean Architecture with the repository pattern, so OOP is how the layers are separated. Three examples:
> **Abstraction and polymorphism for storage.** Document storage sits behind a storage interface (an abstract class with `upload`, `get_signed_url`, `delete`). When we moved documents in Manpower from Postgres blobs to Cloudflare R2, I wrote a new implementation of that interface, and the service layer didn't change. That's the point of depending on an abstraction: the business code doesn't care where files live.
> **Repositories and dependency injection.** Each aggregate has a repository class, like `LeadRepository`, that hides the SQL. Services receive repositories through their constructor, so in tests I pass a fake one. That's encapsulation plus dependency inversion from SOLID.
> **A common base for the AI tools.** The Vaidya pipeline's tools share one shape: a name, an input schema and an async `run` method. The turn manager calls any tool the same way without knowing which one it is. That's polymorphism.
> I also use composition over inheritance where it fits. The Manpower compliance engine is deliberately plain pure functions, not a class hierarchy, so the rules are testable without a database. And I use inheritance where it's natural: a custom exception hierarchy, `AppError` with `NotFoundError` and `ConflictError`, and Pydantic models like `UserBase` → `UserCreate` / `UserOut`."

**Before using it, confirm each example matches your code:** that storage is behind an interface or base class, that repositories are classes injected into services, and how the 29 tools are structured. Drop or rephrase any example that doesn't match. Better to give two true examples than three where one falls apart on a follow-up.

**Likely follow-ups:** abstract class vs interface (Python has `abc.ABC`, and `Protocol` for structural typing); `@classmethod` vs `@staticmethod`; MRO and `super()` in multiple inheritance; when inheritance is a bad idea (deep hierarchies, "is-a" that isn't really true). Cheatsheet: [02-python-cheatsheet.md §7](02-python-cheatsheet.md).
