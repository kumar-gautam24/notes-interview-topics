# 13 · Final Sheet: Round 2 in One Page

Everything to prepare for the Headstart client round 2, in one file. The questions from round 1 and the ones you shared today are all here, each with a guided answer.

**How every answer is built (use the same 4 steps each time):**
1. **Say it simply** (1–3 sentences, the human way).
2. **Show the small code** if it's a coding question.
3. **Say what happens on failure.** Round 1 always asked this.
4. **Stop.** Go one level deeper ("If they push") only when they ask.

Simple wins: every extra tool you name (Kafka, Lua, Celery) is one more thing they can grill you on.

---

## The question list (tick them off)

**A. Asked in round 1 (expect them again, deeper)**
- [ ] Q1. 5 users upload CSVs of 10 lakh rows each. Design it so nobody waits. Why a queue? Why object storage? Show the chunk code.
- [ ] Q2. What is a job, a job id, a background job? How is a job created?
- [ ] Q3. Razorpay webhooks: same event twice, fake event, out of order, late, idempotency key, what's stored in the processed table.
- [ ] Q4. Razorpay basics: currency INR, amount, keys, checkout signature.

**B. Hands-on code you shared today**
- [ ] Q5. Rate limiter: input is tuples `(user_id, time)`, 3 requests per 10 s per user, block the 4th.
- [ ] Q6. Rate limiter in FastAPI / across many servers (Redis).
- [ ] Q7. Redis from zero: what it is, why it's fast, data types.
- [ ] Q8. Redis cache: store a user with TTL 5 s.
- [ ] Q9. Library code: `Depends(cache(...))`, `cache_evict`, `cache_put`, `rate_limit("100/minute")`, `eviction_group`.
- [ ] Q10. Redis as a queue. Worker crash?
- [ ] Q11. Redis queue vs RabbitMQ (and Kafka, Celery).

**C. Rapid-fire theory**
- [ ] Q12. MongoDB: what, when, when not.
- [ ] Q13. An API takes 5 seconds. What do you do?
- [ ] Q14. Indexes: why, and which types.
- [ ] Q15. Data integrity.
- [ ] Q16. Generators.
- [ ] Q17. FastAPI architecture and validation.
- [ ] Q18. async vs sync.

**D. Weak spots from the screening round**
- [ ] Q19. Fibonacci: optimise the recursive version.
- [ ] Q20. Threads vs processes vs asyncio (multiprocessing).
- [ ] Q21. Multi-tenant architecture.
- [ ] Q22. Sending 1K vs 10M emails (large-scale data).

**E. About you**
- [ ] Q23. Introduce yourself.
- [ ] Q24. Your billing / webhook story.

---

# A. Round 1 questions

## Q1. "5 users upload CSVs of 10 lakh rows. Nobody should wait."

**Say it simply:**
> "Processing 10 lakh rows takes minutes, so I don't do it inside the HTTP request. I do it in three steps.
> **One:** save the file to storage (like S3), create a job row, put the job id on a queue, and return the job id right away (202).
> **Two:** a separate worker takes the job id, reads the file **5,000 rows at a time**, inserts each batch in one query, and saves progress after each batch.
> **Three:** the user checks progress with the job id. If the worker crashes, the next one continues from the saved progress."

**The flow:**
```
User ──upload──> API ──save file──> S3
                 │──INSERT job row (status=queued)──> Postgres
                 │──LPUSH job_id──> Redis queue
                 └──202 {"job_id": ...}   (milliseconds)

Worker ──BRPOP job_id──> read file from S3 in chunks of 5,000
       ──for each chunk: validate → batch INSERT → save rows_done → commit
       ──status = done
User ──GET /imports/{job_id}──> {"status": "processing", "rows_done": 400000}
```

**The chunk code (they asked for this):**
```python
import csv
from itertools import islice

def read_chunks(path, size=5000, skip=0):          # generator: one chunk in memory at a time
    with open(path, newline="") as f:
        rows = islice(csv.DictReader(f), skip, None)  # skip = rows already done (resume)
        while chunk := list(islice(rows, size)):
            yield chunk

for chunk in read_chunks(job.file_path, skip=job.rows_done):
    good = [r for r in chunk if valid(r)]          # bad rows -> error report
    insert_many(good)                              # ONE batch insert, ON CONFLICT DO NOTHING
    rows_done += len(chunk)
    save_progress(job_id, rows_done)               # same transaction as the insert
    conn.commit()
```

**Their follow-ups:**
- **"Why a queue? Why not just a background task?"** A queue (1) **survives restarts**, because FastAPI `BackgroundTasks` dies with the pod, (2) **spreads work** across many workers on any machine, and (3) **controls the rate**: 50 uploads wait in line instead of hitting the DB together.
- **"Why object storage?"** The API server and the worker are **different machines**, so the file must be somewhere both can reach. A retry after a crash needs the file again. Big files shouldn't sit in API memory or in Redis.
- **"What goes in the queue?"** Only the **job id** (a few bytes). The file is in S3, and the details are in the job table.
- **"Why 5,000 per chunk?"** One row at a time means 10 lakh DB round trips (slow). All at once means huge memory and one giant transaction. A chunk in the middle gives few round trips and small memory, and a crash loses at most one chunk.
- **"Worker crashes at row 6 lakh?"** Progress (`rows_done`) is saved **in the same transaction** as each batch, so the next worker skips the done rows. A unique key `(tenant_id, email)` with `ON CONFLICT DO NOTHING` means re-running a chunk never duplicates.
- **"5 users at once?"** With 5 workers, all 5 run in parallel. With fewer, they wait in the queue but still get an instant response and live progress.
- **"One user uploads 20 files?"** Limit running jobs per tenant (for example 2), so others aren't starved.
- **"DB is the bottleneck?"** Batch inserts or `COPY`, a capped worker count (so DB connections stay limited), and running imports at lower priority than user traffic.
- **Numbers from our test:** 5 × 10 lakh rows with 3 workers took about 53 s. The uploads returned in 0.06 s.

**If they push:** use a signed URL so the phone uploads straight to S3, progress over SSE or WebSocket, and a downloadable error file of bad rows.

---

## Q2. "What is a job? Job id? Background job?"

> "A **job** is a to-do note for slow work, stored as **one row in a table**. The **job id** is its unique id, like a **courier tracking number**: you get it instantly and use it later to ask 'where's my parcel?'. A **background job** is work done **outside the HTTP request** by a separate worker process, so the user doesn't wait."

```sql
CREATE TABLE import_jobs (
    id         UUID PRIMARY KEY,           -- the job id
    user_id    UUID NOT NULL,
    file_path  TEXT NOT NULL,              -- S3 key
    status     TEXT NOT NULL,              -- queued -> processing -> done / failed
    rows_done  INT NOT NULL DEFAULT 0,     -- progress + resume point
    error      TEXT
);
```
```python
@app.post("/imports", status_code=202)              # 1) create the job
def create_import(file_key: str):
    job_id = str(uuid4())
    db.execute("INSERT INTO import_jobs (id, file_path, status) VALUES (%s, %s, 'queued')",
               (job_id, file_key))
    r.lpush("imports", job_id)                       # tell a worker
    return {"job_id": job_id}

while True:                                          # 2) worker, separate process
    _, job_id = r.brpop("imports")
    process(job_id)                                  # updates status + rows_done

@app.get("/imports/{job_id}")                        # 3) user checks progress
def get_import(job_id: str):
    return db.fetch_one("SELECT status, rows_done FROM import_jobs WHERE id = %s", (job_id,))
```

**"Why a table AND a queue?"** The table is the **record** (status, progress, errors), and it's what the user reads. The queue is just the **signal** to a free worker. If Redis loses the queue, the row is still `queued`, and a small sweeper re-queues it.

---

## Q3. Razorpay webhooks

**Say it simply (three checks):**
> "**One**, verify the signature, and reject with 400 if it's wrong. **Two**, save the event id in a table where it's unique, and if it's already there, return 200 and do nothing. **Three**, update the order only if the change is allowed, for example never from paid back to failed. Steps two and three happen in **one transaction**."

```python
@app.post("/webhooks/razorpay")
async def razorpay_webhook(request: Request,
                           x_razorpay_signature: str = Header(None),
                           x_razorpay_event_id: str = Header(None)):
    raw = await request.body()                                     # RAW bytes
    expected = hmac.new(WEBHOOK_SECRET.encode(), raw, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, x_razorpay_signature or ""):
        raise HTTPException(400, "bad signature")                  # fake: nothing saved

    event = json.loads(raw)
    with db.transaction():
        inserted = db.execute("INSERT INTO webhook_events (event_id, type) VALUES (%s, %s) "
                              "ON CONFLICT DO NOTHING", (x_razorpay_event_id, event["event"]))
        if inserted.rowcount == 0:
            return {"status": "duplicate"}                         # seen before -> 200, no-op
        apply_if_allowed(event)                                    # state machine + amount check
    return {"status": "ok"}
```

**Their follow-ups:**
- **"What is idempotency?"** Doing the same thing twice gives the same result as doing it once. The webhook comes twice, but credits are added once.
- **"Same event id twice?"** The first insert wins and processes. The second hits the **unique constraint**, so it's a no-op returning 200. It's the DB constraint, not an `if exists` check, because two copies can arrive at the same moment on two servers.
- **"What's stored in the processed table?"** `event_id` (primary key), event type, order/payment id and received time, plus the raw payload for audit if you want it.
- **"Fake first, real second, same event id?"** The fake fails the signature check, so it's **rejected before saving anything**. The event id is saved **only after** the signature passes, so a fake can't "use up" the real id.
- **"Out of order (`failed` after `paid`)?"** A **state machine**: `created→paid`, `created→failed`, `failed→paid`. `paid` is final, so a late `failed` is ignored.
- **"Load balancer busy, the webhook comes late or never?"** Razorpay **retries** until it gets a 2xx. Keep the handler fast (verify, save, return 200, and push heavy work to a queue). A **reconciliation job** asks Razorpay's API about orders stuck in `created`, for the case where a webhook never arrives.
- **"Crash halfway?"** One transaction means both the event id and the order update roll back, and we return 500. Razorpay retries, and the retry works.
- **"Return 200 first, process later?"** Only if the event is **saved first** (a table row or queue). The order is save, acknowledge, process. Never acknowledge and hope.
- **"Idempotency key on your own API?"** The client sends an `Idempotency-Key` header (a UUID per action). We store it as unique along with the result. The same key again returns the **saved result** instead of creating a second order.
- **"Trust the amount?"** No. Compare the payment's amount and currency with **our** order row.

---

## Q4. Razorpay basics

- **Amount is in paise:** ₹500 is `50000`. **Currency** is `"INR"`. Never store money as a float.
  ```python
  client = razorpay.Client(auth=(KEY_ID, KEY_SECRET))
  order = client.order.create({"amount": 50000, "currency": "INR", "receipt": "rcpt_1"})
  ```
- **Keys:** `key_id` is public, and the app uses it to open checkout. `key_secret` is **server only** (env var). The **webhook secret** is separate and set in the dashboard. Test and live modes use different keys.
- **Checkout success:** the app gets `order_id`, `payment_id` and `signature`. The server checks HMAC-SHA256 of `"order_id|payment_id"` with `key_secret`.
- **Flow:** server creates the order → app opens checkout → user pays → server verifies the signature → the webhook confirms → reconciliation catches gaps.

---

# B. Hands-on code

## Q5. Rate limiter from tuples: 3 per 10 s per user

**Say it simply:**
> "For each user I keep the times of their recent allowed requests. For each new request I drop the times older than 10 seconds. If 3 are left, block. Otherwise save this time and allow."

```python
from collections import deque

def rate_limit(requests, limit=3, window=10):
    hits = {}                                  # user_id -> deque of allowed times
    result = []
    for user_id, t in requests:                # each item is a tuple (user_id, time_in_seconds)
        if user_id not in hits:
            hits[user_id] = deque()            # new user -> empty deque
        q = hits[user_id]
        while q and q[0] <= t - window:        # drop times older than 10 s
            q.popleft()
        if len(q) < limit:
            q.append(t)
            result.append((user_id, t, "ALLOW"))
        else:
            result.append((user_id, t, "BLOCK"))
    return result

print(rate_limit([("u1",1), ("u1",2), ("u1",3), ("u1",4), ("u2",4), ("u1",11)]))
# u1@1 ALLOW, u1@2 ALLOW, u1@3 ALLOW, u1@4 BLOCK, u2@4 ALLOW, u1@11 ALLOW
```

**Explain the pieces:**
- `hits[user_id] = deque()` creates an empty "line" for a new user. `defaultdict(deque)` does the same automatically.
- **Why a deque?** Times arrive in order, so the oldest is at the front. `popleft()` removes it in O(1), while `list.pop(0)` is O(n) because it shifts everything.
- **Why `<=`?** A request exactly 10 s old has just left the window. Either choice is fine if you say which.
- **Per user:** each user has their own deque, so u2 never counts against u1.
- **Cost:** each time is added once and removed once, so O(n) total, with at most 3 times stored per user.

---

## Q6. Rate limiter in FastAPI / many servers

**Simplest: a Redis counter (fixed window).**
```python
def rate_limit(limit: int, window: int):
    async def check(request: Request):
        key = f"rate:{request.url.path}:{request.client.host}"
        count = await r.incr(key)               # 1, 2, 3 ... atomic across servers
        if count == 1:
            await r.expire(key, window)         # first request starts the window
        if count > limit:
            raise HTTPException(429, "Too Many Requests",
                                headers={"Retry-After": str(await r.ttl(key))})
    return check

@app.get("/api", dependencies=[Depends(rate_limit(3, 10))])
async def api():
    return {"ok": True}
```
- **Why Redis?** With 4 API servers, each server's Python dict would count separately. Redis is one shared counter.
- **Why does `rate_limit` return a function?** `rate_limit(3, 10)` runs once and returns `check`, which remembers 3 and 10 (a closure). FastAPI calls `check(request)` on every request. If it raises, the endpoint doesn't run.
- **Fixed window weakness:** 3 requests at 9.9 s plus 3 at 10.1 s means 6 in 0.2 s. **If they push:** a sliding window with a Redis **sorted set** per user (score = timestamp): `ZREMRANGEBYSCORE` drops old entries, `ZCARD` counts, `ZADD` adds, all run in one Lua script so it's atomic.
- **Redis down?** Choose: **fail open** (allow, keep the site up) or **fail closed** (block, for login/OTP abuse).
- **Per IP or per user?** Use the user id from the JWT when logged in, and the IP otherwise. One office Wi-Fi shares an IP.

---

## Q7. Redis from zero

> "Redis is an **in-memory key-value store**: like a Python dict on a separate server that every API server and worker shares. It's fast because data is in RAM and commands are simple. Commands run one at a time, so **each command is atomic**."

| Type | Think of it as | Commands | Used for |
|---|---|---|---|
| String | one value | `SET k v EX 5`, `GET`, `DEL`, `INCR`, `EXPIRE`, `TTL` | cache, counters |
| List | a line of items | `LPUSH`, `BRPOP`, `LLEN` | job queue |
| Hash | small dict | `HSET`, `HGET`, `HINCRBY` | job progress |
| Sorted set | sorted by a number | `ZADD`, `ZREMRANGEBYSCORE`, `ZCARD` | sliding-window rate limit, delayed jobs |

```python
import redis
r = redis.Redis(host="localhost", port=6379, decode_responses=True)   # create once, reuse
r.set("name", "Gautam", ex=5); r.get("name"); r.incr("count")
```
- **Not your main DB.** RAM is limited and data can be lost. Postgres stays the source of truth.
- **Can it lose data?** Yes, on restart. **RDB** snapshots lose minutes, and **AOF** (append-only file) loses about 1 s. That's fine for a cache. For a queue, turn on AOF and keep job status in Postgres too.
- **`KEYS *`?** Never in production, because it blocks Redis. Use `SCAN`.

---

## Q8. Redis cache: store a user with TTL 5 s

**Say it simply:**
> "Check Redis first. If the user is there, return it. If not, read the DB, save it in Redis with `EX 5`, and return it. Redis deletes it after 5 seconds, so it's never more than 5 seconds old. On update, I delete the key."

```python
def get_user(user_id):
    key = f"user:{user_id}"
    cached = r.get(key)                         # 1. look in Redis
    if cached is not None:
        return json.loads(cached)               # 2. HIT: no DB
    user = db_get_user(user_id)                 # 3. MISS: ask DB
    if user is not None:
        r.set(key, json.dumps(user), ex=5)      # 4. save a copy for 5 s
    return user

def update_user_age(user_id, age):
    db_update_age(user_id, age)                 # DB first (source of truth)
    r.delete(f"user:{user_id}")                 # then drop the old copy
```

| Time | Call | In Redis? | Result |
|---|---|---|---|
| 0 s | `get_user(1)` | no | MISS → DB → `SET EX 5` |
| 1 s, 3 s | `get_user(1)` | yes | HIT, no DB |
| 5 s | Redis deletes the key | | |
| 6 s | `get_user(1)` | no | MISS → DB again |

In our test: a miss took about 100 ms and a hit about 0.2 ms. This pattern is called **cache-aside**.

**Follow-ups:**
- **"Why delete on update, not update the cache?"** Two updates at once could write the cache in the wrong order. Deleting is always safe, because the next read loads the truth.
- **"Why 5 s? How to pick a TTL?"** It's how stale the data may be. A profile can be minutes old. Money should never come from cache.
- **"Missing user id 999 asked again and again?"** Cache "not found" briefly too.
- **"Redis down?"** Catch the error and read from the DB. The cache only speeds things up.
- **"Cache stampede?"** A popular key expires and 1,000 requests hit the DB at once. Add a little random time to the TTL, or let only one request refill using a short lock (`SET lock:user:1 1 NX EX 2`).
- **"String or hash?"** A JSON string is simplest. A hash lets you read or change one field.

---

## Q9. The library snippets: `cache`, `cache_evict`, `cache_put`, `rate_limit`, `eviction_group`

They come from **fastapi-redis-sdk**, Redis's official FastAPI library. Underneath, it's **the same as Q8 and Q6**, wrapped in `Depends`.

| Library | What happens | Hand-written version |
|---|---|---|
| `Depends(cache(ttl=60))` on GET | Key built from the URL. **Hit:** returns the cached response, and your function never runs. **Miss:** your function runs and the response is saved for 60 s. | `r.get` → else DB + `r.set(key, json, ex=60)` |
| `Depends(cache_evict(key_builder=...))` on DELETE | Your function runs. **Only if it succeeded**, that one key is deleted. Without `key_builder`, the whole group is deleted. | DB delete, then `r.delete(key)` |
| `Depends(cache_put(ttl=300))` on PUT | Your function runs, then the **new** response is written to the cache (**write-through**), so the next GET is a hit. | DB update, then `r.set(key, new_json, ex=300)` |
| `Depends(rate_limit("100/minute"))` | A counter per route and client IP (INCR + EXPIRE). Request 101 gets **429** + `Retry-After`. | Q6 code |

- **`eviction_group="users"`** is a **tag inside every key** of that kind (`...:{users}:users:5`), so you can delete all of them together. By hand, that's a key prefix plus SCAN and delete:
  ```python
  for key in r.scan_iter(match="users:*"):
      r.delete(key)
  ```
- **In the interview:** write the hand-written version (every line can be explained), then say: *"In production I'd use a library like fastapi-redis-sdk, where `Depends(cache(ttl=60))` does exactly this."*
- **Watch out:** GET caches for 60 s but PUT writes for 300 s, so keep the TTLs consistent. If the response depends on who's asking (`/me`), the key must include the user, or one user sees another's data.

---

## Q10. Redis as a queue

**Say it simply:**
> "A queue separates **accepting** work from **doing** it. The API pushes a job id onto a Redis **list** with `LPUSH`. A worker waits with `BRPOP` and takes the next job. Push left, take right, so it's first in, first out."

```python
r.lpush("jobs", job_id)                     # API: add on the left, returns instantly

while True:                                 # worker: separate process
    _name, job_id = r.brpop("jobs")         # take from the right; WAITS if empty
    process(job_id)
```
- `brpop` returns a **tuple** `(list name, value)`, which is why it unpacks into two.
- **B = blocking:** it waits inside Redis, so there's no busy loop and no `sleep`.
- **Two workers never get the same job:** Redis runs commands one at a time.
- **More speed?** Start more workers.

**"Worker crashes mid-job?"** `BRPOP` already removed the job, so it's **lost**. Fix: **move** it to a processing list, and remove it only after success:
```python
job_id = r.blmove("jobs", "jobs:processing", 0, "RIGHT", "LEFT")   # atomic move
process(job_id)
r.lrem("jobs:processing", 1, job_id)                              # done = "ack"
```
After a crash, the job is still in `jobs:processing`, and a recovery step moves it back to `jobs`.

**Follow-ups:**
- **"Can a job run twice?"** Yes, if a crash happens after the work but before the ack. That's **at-least-once** delivery, so make jobs **idempotent** (`ON CONFLICT DO NOTHING`, or check `status = 'done'` first).
- **"Retries?"** Keep an `attempts` count. Retry up to 3 times, then move the job to a **dead-letter** list for a human to check.
- **"Redis restarts?"** Turn on AOF, and keep job status in Postgres so a sweeper re-queues anything still pending.
- **"Priority?"** Two lists: `r.brpop(["jobs:high", "jobs:low"])` checks high first.
- **"Run a job in 10 minutes?"** A sorted set with score = run time. A loop moves due jobs into the list.
- **"Backlog?"** `LLEN jobs`. Alert if it keeps growing, then add workers.

---

## Q11. Redis queue vs RabbitMQ (vs Kafka, Celery)

> "Redis was already in my stack and my jobs were simple, so a list was enough. If I needed delivery guarantees **built in** (ack, redelivery when a worker dies, dead-letter, routing), I'd use RabbitMQ instead of building them myself."

| | Redis list | RabbitMQ | Kafka | Celery |
|---|---|---|---|---|
| What | data structure used as a queue | a real message broker | an event **log** | Python task library |
| Ack / redelivery | you build it (BLMOVE + LREM) | built in (`basic_ack`) | consumer offsets | built in |
| Use when | simple jobs, Redis already there | many job types, strict delivery | huge event streams, replay, many readers | Python team wanting retries and schedules for free (runs on Redis or RabbitMQ) |

RabbitMQ worker, if they ask for code:
```python
ch.queue_declare(queue="jobs", durable=True)
ch.basic_qos(prefetch_count=1)                         # one job at a time per worker
def on_message(ch, method, props, body):
    handle(json.loads(body))
    ch.basic_ack(method.delivery_tag)                  # done -> broker deletes it
ch.basic_consume(queue="jobs", on_message_callback=on_message)
ch.start_consuming()
```

---

# C. Rapid-fire theory

## Q12. MongoDB
- **What:** a document database. It stores JSON-like documents with a flexible schema and no joins by default.
- **When:** data whose shape changes per record (custom form fields, event logs), or data you always read as a whole document.
- **When not:** money and strongly related data that needs transactions and joins. Use Postgres.
- **Embed vs reference:** embed what you always read together (an order's items). Reference what grows without limit or is shared.
- **Indexes:** the same idea as SQL (single, compound, text), with the same left-prefix rule.

## Q13. "An API takes 5 seconds. What do you do?"
1. **Measure first.** Time each step (logs or tracing). Is it the DB, an external call, or Python?
2. **DB:** `EXPLAIN ANALYZE`. A "Seq Scan" on a big table needs an index. Watch for **N+1** (a query inside a loop), and replace it with one JOIN or `IN (...)`.
3. **External call** (email, payment): move it to a queue, add a timeout, or run calls in parallel with `asyncio.gather`.
4. **Same data read again and again:** cache it in Redis with a TTL (Q8).
5. **Too much data:** paginate and select only the needed columns.
6. **Blocking call inside `async def`:** it freezes every request. Use an async driver or a plain `def` route.

> One line: "Measure, find the slow part, then fix that part: an index, a JOIN, a cache, or move it to a background job."

## Q14. Indexes: why and which
- **Why:** without one, the DB reads every row. A B-tree index jumps straight to the match, like a book's index. **Cost:** slower writes and more storage.
- **B-tree (default):** `=`, `<`, `>`, `BETWEEN`, `ORDER BY`, `LIKE 'abc%'`.
- **Composite** `(tenant_id, created_at)`: the **left-prefix rule**. It helps `WHERE tenant_id=?` and `WHERE tenant_id=? AND created_at>?`, but not `created_at` alone.
- **Unique:** speed plus a guarantee (no duplicate emails or event ids).
- **Partial:** `WHERE status='pending'` indexes only the rows you query, so it's small.
- **Covering** (`INCLUDE`): the query is answered from the index alone.
- **GIN:** JSONB, arrays, full-text. **Hash:** equality only, rarely needed.
- **Don't index:** tiny tables, a boolean column on its own, or columns you never filter on.

## Q15. Data integrity
- **DB constraints:** `NOT NULL`, `UNIQUE`, `FOREIGN KEY`, `CHECK (amount > 0)`. The last guard even when the code has a bug.
- **Transactions:** all or nothing (webhook event id + order update together).
- **Atomic updates:** `UPDATE wallet SET credits = credits - 10 WHERE user_id = ? AND credits >= 10`, never read-then-write in Python.
- **Validation:** Pydantic at the API edge, business rules in the service, constraints in the DB.
- **Locks:** `SELECT ... FOR UPDATE` when two requests change the same row.

## Q16. Generators
- A function with `yield` gives values **one at a time, lazily**, and remembers where it stopped.
- **Why:** memory. 10 lakh rows as a generator keep **one chunk** in memory, while a list keeps all of them.
- `(x*x for x in rows)` is a generator. `[x*x for x in rows]` builds the whole list.
- It can be used **only once**.
- **Real use:** `read_chunks()` in Q1, streaming responses, reading big files.
```python
def numbers(n):
    for i in range(n):
        yield i            # pauses here, continues on next()
g = numbers(3); next(g), next(g), next(g)   # 0, 1, 2
```

## Q17. FastAPI architecture and validation
- **Layers:** router (HTTP only) → service (business rules) → repository (SQL) → DB. Shared things (DB session, current user) come in through `Depends`.
- **Validation:** Pydantic request models give an automatic **422** with field errors. Use `Field(gt=0, max_length=100)` and `field_validator` for custom rules, and `response_model` to control output (never return password hashes).
- **Where each check goes:** shape and format in Pydantic, "email already taken?" in the service plus a DB unique constraint, permissions in an auth dependency.
```python
class CreateLead(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    phone: str | None = None

@app.post("/leads", response_model=LeadOut, status_code=201)
def create_lead(body: CreateLead, user=Depends(current_user), svc=Depends(get_lead_service)):
    return svc.create(user.tenant_id, body)
```

## Q18. async vs sync
- `async def` + `await` is for **waiting work** (DB, HTTP, Redis). While one request waits, the event loop serves others.
- A **blocking** call (`requests`, `time.sleep`, psycopg2) inside `async def` freezes the loop **for everyone**.
- Library is sync? Write a plain `def` route, and FastAPI runs it in a **threadpool**. Or use `await run_in_threadpool(fn)`.
- **CPU-heavy** work: async doesn't help (the GIL). Use a **process pool** or a separate worker.

> One line: "async for waiting, processes for computing, and never block inside `async def`."

---

# D. Screening weak spots

## Q19. Fibonacci: optimise the recursive version
> "Naive recursion recomputes the same values, so it's **O(2ⁿ)**. I'd go: memoize (O(n)), then a bottom-up loop, then just **two variables**: O(n) time, O(1) space."

```cpp
// naive: O(2^n)
long long fibSlow(int n) { return n < 2 ? n : fibSlow(n - 1) + fibSlow(n - 2); }

// default answer: O(n) time, O(1) space
long long fib(int n) {
    long long a = 0, b = 1;
    for (int i = 0; i < n; ++i) { long long t = a + b; a = b; b = t; }
    return a;
}
```
| Version | Time | Space |
|---|---|---|
| Naive recursion | O(2ⁿ) | O(n) stack |
| Memoization | O(n) | O(n) |
| Bottom-up table | O(n) | O(n) |
| **Two variables** | **O(n)** | **O(1)** |
| Fast doubling / matrix (if they push) | O(log n) | O(log n) |

Python memo in one line, if asked: `@functools.lru_cache(maxsize=None)` on the recursive function.

## Q20. Threads vs processes vs asyncio
| | Threads | Processes | asyncio |
|---|---|---|---|
| Best for | waiting work with blocking libraries | **CPU-heavy** work | waiting work at high concurrency |
| Runs Python code in parallel? | No (GIL) | **Yes** (each has its own GIL) | No (one thread) |
| Cost | low | high (separate memory) | lowest |

```python
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
with ThreadPoolExecutor(20) as ex:  results = list(ex.map(fetch_url, urls))      # waiting
with ProcessPoolExecutor() as ex:   results = list(ex.map(score_chunk, chunks))  # computing
```
> "Is the time spent **waiting** or **computing**? Waiting: async, or threads for blocking libraries. Computing: processes."

Be honest: "My production work has been I/O-heavy with asyncio. I haven't needed multiprocessing in production, but I know when I'd use it."

## Q21. Multi-tenant architecture (each college = one tenant)
> "Shared database, with a `tenant_id` column on every table. The tenant comes from the JWT, never from the request body. Every query is filtered by tenant in the repository layer."

- **Three models:** shared schema + `tenant_id` (cheap, most SaaS); a schema per tenant (more isolation); a DB per tenant (strongest, expensive, for big or compliance-heavy clients).
- **Safety:** Postgres **Row-Level Security** as a safety net. Unique constraints per tenant `(tenant_id, email)`. Indexes **start with `tenant_id`**.
- **Noisy neighbour:** per-tenant rate limits and a cap on running jobs per tenant, so one college's big import or campaign doesn't slow the others.
- **Redis keys and file paths** carry the tenant: `tenant:42:user:1`, `/42/imports/...`.
- **Your experience:** you built a multi-tenant backend for a UAE client (6 companies, 4-level RBAC), with the tenant from the token and every query scoped.

## Q22. Sending 1K vs 10M emails
> "1K is a loop in a background job. 10M is a pipeline."
- **10M:** the API returns 202. A planner splits recipients into **batches of about 1,000 ids** on a queue. Workers send through the provider's bulk API, **throttled** to the provider's limit (a shared Redis counter).
- **Idempotent:** a unique `(campaign_id, recipient_id)` row means a retried batch skips people already sent to.
- **Separate queues:** bulk campaigns never delay OTP or password-reset emails. Keep fairness per tenant.
- **Retries** with backoff, a dead-letter queue, bounces and unsubscribes via provider webhooks, and progress plus pause/resume.

---

# E. About you

## Q23. Introduce yourself (30-second backend version)
> "Hi, I'm Gautam, a software engineer at Ailoitte Technologies with about two years of experience. I work on **Vaidya AI**, a healthcare platform we build for Fractal Analytics, where I own the **auth, admin and billing services** in **FastAPI, PostgreSQL and Redis**. I built the credit wallet and payment webhooks so money stays correct under concurrency and retries, and the job flow that runs multi-minute work on Redis workers and streams progress over SSE. I started on mobile and moved into backend ownership, and that's where I'm going deeper."

The 90-second and 2-minute versions are in [09-self-intro.md](09-self-intro.md).

## Q24. Your billing / webhook story
> "I listed what could go wrong with money and built a guard for each. **Two spends at once:** one atomic SQL update (`credits = credits - x WHERE credits >= x`). **Same webhook twice:** a unique event id table. **Fake webhook:** HMAC signature check. **Webhooks out of order:** a state machine that only moves forward. **A webhook that never arrives:** a reconciliation job. Prithvi, a senior engineer, owned the Razorpay dashboard config, checkout and the payment-flow endpoints. I owned the wallet, the deduction, the webhook handler and reconciliation."

---

## Runnable code (all self-testing)

All files live in [code/round2/](code/round2/). Start Redis first: `docker run -p 6379:6379 redis`, then `pip install redis fastapi httpx`.

| Question | File | Run |
|---|---|---|
| Q1, Q2 | [csv_import.py](code/round2/csv_import.py) | `python3 csv_import.py` |
| Q3, Q4 | [razorpay_webhook.py](code/round2/razorpay_webhook.py) | `python3 razorpay_webhook.py` |
| Q5, Q6 | [rate_limiter.py](code/round2/rate_limiter.py) | `python3 rate_limiter.py` |
| Q7 | [redis_basics.py](code/round2/redis_basics.py) | `python3 redis_basics.py` |
| Q8 | [redis_cache_simple.py](code/round2/redis_cache_simple.py) | `python3 redis_cache_simple.py` |
| Q9 | [fastapi_cache_ratelimit.py](code/round2/fastapi_cache_ratelimit.py) | `python3 fastapi_cache_ratelimit.py` |
| Q10, Q11 | [redis_queue_simple.py](code/round2/redis_queue_simple.py) | `python3 redis_queue_simple.py` |

Deeper versions of every answer: [11-round2-prep.md](11-round2-prep.md) and [12-redis-basics.md](12-redis-basics.md).

## Last 10 minutes before the call
1. Say Q1 out loud in 2 minutes, with the 3 steps.
2. Write Q5 from memory, and test it with the 6 tuples.
3. Write Q8 from memory (9 lines).
4. Say the 3 webhook checks (Q3).
5. One line each: queue (Q10), index (Q14), async (Q18).
6. When coding live: **say the plan first, write the simple version, test it out loud with a tiny example, name one trade-off.**
