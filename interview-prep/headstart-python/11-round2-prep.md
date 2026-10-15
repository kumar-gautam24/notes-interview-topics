# 11 · Round 2 Prep: Hands-On Answers

Round 1 showed what they want: **not tool names, but what the tool does, what data goes in, and what code runs.** "Use RabbitMQ" got the follow-up "why, and what exactly does the worker do?". Every answer below goes one level deeper than the tool name.

**The rule for every design answer:** *what goes in → what code runs → what happens when it fails → what I give up.*

## Part 0 · Simple first (learn this before anything else)

**The rule:** give the **simplest version that works**, in plain words. Stop. Let them ask for more. Only then go one level deeper. Each extra tool you name (RabbitMQ, Lua, Kafka) is a new thing they can grill you on, so don't bring it up unless they push.

But keep **one deeper layer ready** for each answer. In round 1 they pushed every time, and "simple" must still be **complete**: what goes in, what code runs, and what happens on failure.

### Rate limiter: 3 requests per 10 s per user
> "For each user I keep the times of their last requests. On a new request I drop times older than 10 seconds. If 3 are left, I block with 429. Otherwise I save this time and allow it."
```python
from collections import defaultdict, deque
import time

hits = defaultdict(deque)                      # user_id -> request times

def allow(user_id):
    now = time.time()
    q = hits[user_id]
    while q and q[0] <= now - 10:              # drop requests older than 10 s
        q.popleft()
    if len(q) >= 3:
        return False                           # 4th request -> block (429)
    q.append(now)
    return True
```
**If they hand you tuples** `(user_id, request_time_in_seconds)`: same logic, in a loop.
```python
from collections import deque

def rate_limit(requests, limit=3, window=10):
    hits = {}                                  # user_id -> deque of allowed request times
    result = []
    for user_id, t in requests:                # each request is a tuple (user_id, time_in_seconds)
        if user_id not in hits:                # (defaultdict(deque) does these 2 lines for you)
            hits[user_id] = deque()
        q = hits[user_id]
        while q and q[0] <= t - window:        # forget requests older than 10 s
            q.popleft()
        if len(q) < limit:
            q.append(t)
            result.append((user_id, t, "ALLOW"))
        else:
            result.append((user_id, t, "BLOCK"))
    return result

rate_limit([("u1",1), ("u1",2), ("u1",3), ("u1",4), ("u2",4), ("u1",11), ("u1",12)])
# u1@1 ALLOW, u1@2 ALLOW, u1@3 ALLOW, u1@4 BLOCK, u2@4 ALLOW, u1@11 ALLOW, u1@12 ALLOW
```
- **Logic:** for each request, (1) take this user's recent times, (2) drop the ones older than 10 s, (3) if 3 remain, block; otherwise record and allow. At t=11 the request from t=1 has left the window, so it's allowed.
- **deque:** a list that's fast at both ends. Times arrive in order, so the oldest is at the front and `popleft()` removes it in O(1). `list.pop(0)` is O(n) because it shifts everything.
- **defaultdict(deque):** a dict that creates an empty deque the first time a new user appears, instead of raising KeyError. It's the same as the two `if user_id not in hits` lines, just shorter.
- **One deque per user:** limits are per user, so u2 never counts against u1.
- **Complexity:** each time is added once and removed once, so O(n) total. At most 3 timestamps are stored per user.

*If they push ("many servers?"):* the same idea in Redis, with one sorted set per user, so all servers share it. See Part 3.

### Cache: user with 5 s TTL
> "First check Redis. If the user is there, return it. If not, read from the DB, save it in Redis for 5 seconds, and return it. When the user is updated, I delete the key."
```python
def get_user(uid):
    cached = r.get(f"user:{uid}")
    if cached:
        return json.loads(cached)              # hit
    user = db_get_user(uid)                    # miss -> DB
    r.set(f"user:{uid}", json.dumps(user), ex=5)
    return user
```
*If they push:* stampede, what not to cache. See Part 4.

### Redis as a queue
> "A Redis list is the queue. The API pushes a job id with LPUSH. A worker waits with BRPOP, takes the next job and processes it."
```python
r.lpush("jobs", job_id)                        # API side

while True:                                    # worker side
    _, job_id = r.brpop("jobs")                # waits until a job arrives
    process(job_id.decode())
```
*If they push ("worker crashes mid-job?"):* move the job to a `processing` list and remove it only after success, plus retries. See Part 5. Mention RabbitMQ only if asked.

### CSV: 5 users × 10 lakh rows
> "I don't process it inside the request. **One:** save the file to storage, create a job, put the job id on a queue, and return the job id right away. **Two:** a worker reads the file **5,000 rows at a time**, inserts each batch in one query, and saves progress. **Three:** the user checks progress with the job id. If the worker crashes, it continues from the saved progress."
```python
def read_chunks(path, size=5000):              # generator: one chunk in memory at a time
    with open(path) as f:
        reader = csv.DictReader(f)
        while chunk := list(islice(reader, size)):
            yield chunk

for chunk in read_chunks(path):
    insert_many(chunk)                         # one batch insert
    save_progress(job_id, rows_done)
```
*If they push:* what a job and job id are, why storage, why a queue, chunk size, duplicates. See Part 1.

### Razorpay webhook
> "Three checks: **one**, verify the signature, and reject it if it's wrong. **Two**, save the event id in a table where it's unique, and if it's already there, return 200 and do nothing. **Three**, update the order only if the change is allowed, for example never from paid back to failed. The event id and the order update are saved in one transaction."

*If they push:* fake-then-real, late events, a crash midway. See Part 2.

---

All code is in [code/round2/](code/round2/) and every file runs its own tests:

| File | What it shows | Run |
|---|---|---|
| [rate_limiter.py](code/round2/rate_limiter.py) | 3 requests / 10 s per user: deque, tuple list, Redis sorted set, Redis counter | `python3 rate_limiter.py` |
| [redis_cache.py](code/round2/redis_cache.py) | Get user with 5 s TTL: miss, hit, invalidate on update, expiry | `python3 redis_cache.py` |
| [redis_queue.py](code/round2/redis_queue.py) | Redis list as a queue: producer, workers, ack, retry, dead-letter, crash recovery. RabbitMQ version for comparison | `python3 redis_queue.py` |
| [csv_import.py](code/round2/csv_import.py) | 5 users × 10 lakh rows: upload → queue → worker reads chunks with a generator → batch insert → progress → resume after crash | `python3 csv_import.py 1000000` |
| [razorpay_webhook.py](code/round2/razorpay_webhook.py) | Signature check, duplicate event, fake-then-real, out-of-order, rollback, Idempotency-Key | `python3 razorpay_webhook.py` |

Setup once: `pip install redis fastapi httpx` and start Redis (`brew services start redis` on Mac, or `docker run -p 6379:6379 redis`).

---

## The 2-hour plan

| Time | Do | Done when |
|---|---|---|
| 0:00–0:30 | **Part 0 only.** Type every snippet from memory and say every answer out loud. | You can give each one in under 30 seconds, with code. |
| 0:30–0:50 | **Rate limiter + cache, one level deeper.** Run `rate_limiter.py` and `redis_cache.py`. Read the Redis sorted-set version once. | You can answer "many servers?" and "what if data changes?". |
| 0:50–1:15 | **Queue + CSV.** Run `redis_queue.py`, then `csv_import.py`. Read `read_chunks` (generator) and `process_import` (chunk → batch insert → checkpoint) until you could rewrite them. | You can draw the CSV flow and say what the worker does line by line. |
| 1:15–1:40 | **Say Part 1 and Part 2 out loud** (CSV design, Razorpay drill). Use a timer: 2 minutes each. | No "um, maybe RabbitMQ". Every box has a reason. |
| 1:40–2:00 | **Rapid-fire (Part 6).** Cover the answer, say yours, check. | One clear sentence each. |

---

# Part 1 · "5 users upload CSVs of 10 lakh rows each. Nobody should wait."

## Say this (about 2 minutes)

> "Processing 10 lakh rows takes minutes, so it **can't happen inside the HTTP request**. The request would time out, and while a server worker is busy with one file it can't serve anyone else. So I split it into **accept now, process later**.
>
> **Step 1, upload.** The file goes to **object storage** like S3. Ideally the client uploads straight to S3 with a signed URL, so the big file never passes through our API servers. The API then creates an `import_jobs` row with status `queued` and pushes just the **job id** onto a **queue**, and returns **202 with the job id**. That takes milliseconds, so all 5 users get an instant response.
>
> **Step 2, workers.** A pool of worker processes, separate from the API, pull job ids from the queue. Each worker streams the file from S3 and reads it **in chunks of about 5,000 rows using a generator**, so memory stays flat whether the file has 10 thousand or 10 lakh rows. For each chunk it **validates** rows, **inserts the whole chunk in one batch** (`execute_values` or `COPY`), and **commits once per chunk**. In the same transaction it saves a **checkpoint**: rows done so far.
>
> **Step 3, progress.** After each chunk the worker updates progress in Redis or the job row. The app polls `GET /imports/{id}` or listens over SSE or WebSocket to show '4 lakh of 10 lakh done'. Bad rows are collected into an error report the user can download.
>
> **Failures.** If a worker crashes, the job goes back on the queue and the next worker **resumes from the checkpoint**. A **unique constraint** like `(tenant_id, email)` with `ON CONFLICT DO NOTHING` means re-running a chunk never creates duplicates.
>
> **Five users at once:** with 5 workers, all 5 files run in parallel. With fewer workers they queue but still get instant responses and live progress. **What I give up:** more moving parts (queue, workers, storage) and results that aren't instant. The user waits for the result, but nobody waits for the API."

## What is a "job"? (the basics, in case they start here)

**Job:** a to-do note for work too slow to do while the user waits. It's **one row in a table**:

```sql
CREATE TABLE import_jobs (
    id          UUID PRIMARY KEY,        -- the job id
    user_id     UUID NOT NULL,           -- who asked
    file_path   TEXT NOT NULL,           -- where the file is (S3 key)
    status      TEXT NOT NULL,           -- queued -> processing -> done / failed
    rows_done   INT  NOT NULL DEFAULT 0, -- progress + resume point
    rows_failed INT  NOT NULL DEFAULT 0,
    error       TEXT,
    created_at  TIMESTAMPTZ DEFAULT now()
);
```

**Job id:** the unique id of that row (a UUID). Like a **courier tracking number**: you get it instantly and use it later to ask "where's my parcel?".

**Background job:** work done **outside the HTTP request**, by a separate **worker** process. The user doesn't wait for it; they check on it with the job id.

**How a job is created and run, step by step:**
```python
# 1) API: create the job and return immediately
@app.post("/imports", status_code=202)
def create_import(file_key: str, user=Depends(current_user)):
    job_id = str(uuid4())                                   # new tracking number
    db.execute("INSERT INTO import_jobs (id, user_id, file_path, status) "
               "VALUES (%s, %s, %s, 'queued')", (job_id, user.id, file_key))
    redis.lpush("imports", job_id)                          # "wake up, there's work"
    return {"job_id": job_id}                               # takes milliseconds

# 2) WORKER: separate process, runs forever
while True:
    _, job_id = redis.brpop("imports")                      # wait for the next job id
    job = db.fetch_one("SELECT * FROM import_jobs WHERE id = %s", (job_id,))
    set_status(job_id, "processing")
    try:
        for chunk in read_chunks(job.file_path, skip=job.rows_done):
            insert_many(chunk)
            save_progress(job_id, ...)                      # rows_done += len(chunk)
        set_status(job_id, "done")
    except Exception as e:
        set_status(job_id, "failed", error=str(e))

# 3) API: user checks progress with the job id
@app.get("/imports/{job_id}")
def get_import(job_id: str):
    return db.fetch_one("SELECT status, rows_done, rows_failed FROM import_jobs WHERE id = %s", (job_id,))
```

**Why both a table AND a queue?**
- **Table** = the record: status, progress, errors, history. It's what the user's status API reads.
- **Queue** = the **signal** that tells a free worker "there's work". It holds only the id.
- If the queue loses a message (Redis restarts), the row is still `queued` in the table, so a small **sweeper** job re-pushes jobs stuck in `queued` for too long. The table is the source of truth.

**Say it in one line:** "A job is a row that tracks slow work; the job id is its tracking number; the API creates the row and queues the id; a worker does the work and updates the row; the user polls with the id."

## The follow-ups they asked, with answers

**"Why a queue? Why not just start a background task?"**
> "A queue does three things a background task doesn't:
> 1. **Survives restarts.** The job is stored outside the API process. FastAPI `BackgroundTasks` dies if the pod restarts.
> 2. **Spreads load.** Any number of workers on any machines can pull from it, and I scale workers separately from the API.
> 3. **Controls the rate.** If 50 users upload at once, jobs wait in line instead of 50 imports hammering the database together.
> It also gives retries and a dead-letter list for jobs that keep failing."

**"What exactly goes in the queue?"**
> "Only the **job id**, a few bytes. The file is in S3 and the job details are in the `import_jobs` table. Queues are for small messages, and storing a 100 MB file in Redis would eat memory and be lost if Redis restarts."

**"Why put the file in storage instead of sending it to the server that processes it?"**
> - **The API server and the worker are different machines.** The worker that picks up the job might be on another pod, so the file has to be somewhere both can reach.
> - **Retries and resume need the file again.** If the worker crashes at row 6 lakh, the next worker re-reads it from S3. If it lived only in one server's memory or disk, it'd be gone.
> - **API servers stay light.** Uploading straight to S3 with a signed URL means 5 × 100 MB never flows through our API.
> - **Audit.** We keep the original file to show what the user actually uploaded."

**"What exactly does the worker code do, chunk by chunk?"** (this is `process_import` in [csv_import.py](code/round2/csv_import.py))
```python
def read_chunks(path, chunk_size=5000, skip=0):          # generator: one chunk in memory at a time
    with open(path, newline="") as f:
        rows = islice(csv.DictReader(f), skip, None)      # skip = rows already done (resume)
        while chunk := list(islice(rows, chunk_size)):
            yield chunk

for chunk in read_chunks(path, skip=job.rows_done):
    good = [v for v in (validate(r) for r in chunk) if v]  # bad rows -> error report
    insert_chunk(conn, tenant_id, good)                    # ONE batch insert, ON CONFLICT DO NOTHING
    rows_done += len(chunk)
    update job set rows_done = ... ; conn.commit()        # data + checkpoint in ONE transaction
    redis.hset(f"import:{job_id}", "rows_done", rows_done) # progress for the UI
```
> "Read 5,000 rows, validate, insert them in one statement, commit together with the checkpoint, update progress, repeat. One commit per chunk instead of per row is the big speed win: 200 commits instead of 10 lakh."

**"Why chunks of 5,000? Why not all at once, or one by one?"**
> "One row at a time means 10 lakh round trips and commits: very slow. All at once means 10 lakh rows in memory and one giant transaction that locks for minutes and loses everything on failure. A chunk of a few thousand is the middle: few round trips, small memory, and a failure loses at most one chunk. I'd tune the size by measuring."

**"How fast is it?"** In the test run: **5 files × 10 lakh rows with 3 workers took about 53 seconds** (SQLite on one laptop-class machine), and the 5 uploads were accepted in **0.06 s**. Say it as: "uploads return in milliseconds; processing is bounded by workers and DB write speed, and I scale workers to go faster." Postgres with `COPY` is faster still.

**"One user uploads 20 files and blocks the other 4?"**
> "Fairness: limit concurrent jobs per tenant (for example, at most 2 running per tenant), or use a queue per tenant and have workers rotate across them. Same idea as noisy-neighbour control in multi-tenant systems."

**"The database becomes the bottleneck?"**
> "Batch inserts, fewer indexes during load (or a staging table, then one `INSERT ... SELECT`), cap the number of workers so connections stay under the pool limit, and run imports at a lower priority than user traffic."

**"Why not Kafka?"**
> "Kafka is for high-volume event streams with replay and many consumers. Here it's a few jobs per minute, so a simple job queue (Redis or RabbitMQ) is enough. Kafka adds operational cost we don't need."

---

# Part 2 · Razorpay webhooks: the full drill

Code for every case: [razorpay_webhook.py](code/round2/razorpay_webhook.py).

**"What is idempotency?"**
> "Doing the same operation twice gives the same result as doing it once. If Razorpay sends 'payment captured' twice, the user still gets credits **once**. It matters because networks retry: Razorpay retries webhooks, and mobile apps retry requests when the network drops."

**"How do you make the webhook idempotent? What's the key?"**
> "Razorpay sends an **event id** in the `X-Razorpay-Event-Id` header. I have a `webhook_events` table with `event_id` as the **primary key**. When an event arrives I `INSERT` its id. If it's new, the insert succeeds and I process it. If it's a repeat, the insert conflicts, and I return 200 and do nothing. The **database's unique constraint** is the guard, not an `if` in Python, because two copies can arrive at the same moment on two servers and both pass an `if exists` check."

**"Then what's stored in that processed table?"**
> "Event id (primary key), event type, the payment or order id, and when it was received. Optionally the raw payload for debugging and audit."

**"Two events with the same payload and the same event id arrive. What happens?"**
> "The first inserts the event id and processes. The second hits the unique constraint, so it's a no-op returning 200. If they arrive at exactly the same time, the database lets only one insert win, and the other waits and then sees the conflict."

**"The first event is fake or tampered, the second is real. Then?"**
> "Every webhook is **signed**: Razorpay computes HMAC-SHA256 of the raw body with our webhook secret and sends it in `X-Razorpay-Signature`. I compute the same and compare with `hmac.compare_digest`. The fake one fails, so I return **400 and store nothing**. That order matters: I record the event id **only after** the signature passes. Otherwise a fake request with a real event id could 'use up' the id, and the genuine event would be ignored as a duplicate."

**"Our load balancer handles 1,000 requests. The webhook doesn't get through, or comes much later. Then?"**
> "Razorpay **retries** a webhook that doesn't get a quick 2xx, with backoff, for up to about a day. So:
> 1. **Make the handler fast:** verify signature, record the event, return 200. Heavy work goes to a queue. A slow handler times out and causes more retries.
> 2. **Late or retried events are safe** because of the event-id dedupe and the state machine.
> 3. **If it never arrives**, a **reconciliation job** periodically asks Razorpay's API for orders stuck in `created` and fixes them. Webhooks are the fast path, reconciliation is the safety net.
> 4. **Don't rate-limit the webhook route** like user traffic, and give it its own capacity if possible."

**"Events arrive out of order: `payment.failed` after `payment.captured`?"**
> "The order has a **state machine**: `created → paid`, `created → failed`, `failed → paid` (the user retried and the second attempt worked). `paid` is final. A late `failed` after `paid` is not an allowed transition, so it's ignored. The newest event doesn't automatically win; only valid transitions are applied."

**"Processing crashes halfway?"**
> "The event-id insert and the order update are in **one transaction**. If anything fails, both roll back and I return 500. Razorpay retries, and the retry processes cleanly because the event id was never saved. If I saved the event id first and crashed after, the retry would be skipped as a duplicate and the payment lost."

**"Return 200 first, then process. What if processing fails after the 200?"**
> "Then Razorpay won't retry, so the event must be **saved durably before** returning 200: in the `webhook_events` table with status `pending`, or on a queue. A worker processes it and retries on failure. 'Return 200 first' means 'save, then acknowledge, then process', never 'acknowledge and hope'."

**"Idempotency key on your own API?"**
> "For our create-order or payment API, the client sends an **`Idempotency-Key` header** (a UUID per user action). I store the key with a unique constraint and the result. If the same key comes again (double tap, network retry), I return the **saved result** instead of creating a second order. Same idea as the webhook event id, but the client generates the key."

**"Verify the amount?"**
> "Yes. Compare the payment's amount and currency with **our** order row, not just trust the payload."

**Razorpay specifics they may ask**
- **Amount is in paise** (the smallest unit): ₹500 → `amount: 50000`. **Currency** `"INR"`.
  ```python
  client = razorpay.Client(auth=(KEY_ID, KEY_SECRET))
  order = client.order.create({"amount": 50000, "currency": "INR", "receipt": "rcpt_123", "notes": {"user_id": "u1"}})
  ```
- **Keys:** `key_id` is public (the app uses it to open checkout). `key_secret` stays **server-only** (env var or secret manager). The **webhook secret** is a separate secret set in the dashboard. Test and live modes have different keys.
- **Checkout success:** the app gets `razorpay_order_id`, `razorpay_payment_id` and `razorpay_signature`. The server verifies HMAC-SHA256 of `order_id|payment_id` with `key_secret`. **Still trust the webhook / server state**, not the app's "success" screen.
- **Flow:** server creates order → app opens checkout with the order id → user pays → app sends ids to the server to verify → webhook confirms → reconciliation catches gaps.
- **Never store money as float.** Integer paise.

---

# Part 3 · Rate limiter (3 requests per 10 s per user)

**Say this:**
> "For each user I keep the timestamps of their recent requests. On each request I drop timestamps older than 10 seconds. If 3 are left, I block with **429** and a `Retry-After` header. Otherwise I record this one and allow it. In-memory works for one server. With many servers I keep the same data in **Redis**, a **sorted set per user** with the timestamp as the score, and run the steps in a **Lua script** so they're atomic."

| Algorithm | How | Good | Bad |
|---|---|---|---|
| **Fixed window** | `INCR ratelimit:{user}:{bucket}` + `EXPIRE` | Simplest, 1 key | Edge burst: 3 at 9.9s + 3 at 10.1s |
| **Sliding window log** | Store each timestamp (deque / sorted set) | Exact | Memory per request |
| **Token bucket** | Tokens refill at a steady rate; a request takes one | Allows short bursts, smooth | Slightly more logic |

**Follow-ups**
- **"Why atomic?"** Two servers both read count = 2, both allow → 4 requests got through. Lua (or `MULTI`) runs check-and-add as one step inside Redis.
- **"Where in FastAPI?"** A dependency on the routes (`Depends(rate_limit)`) or middleware for all routes. The key is the user id from the JWT, or the IP for logged-out routes.
- **"The tuple list `(user_id, time)`?"** Works, but each check scans every user's entries. A dict of deques per user only looks at that user's entries.
- **"Redis down?"** Decide: fail open (allow, keep the site up) or fail closed (block, for login and OTP abuse). Say which and why.

---

# Part 4 · Redis cache (user, TTL 5 s)

**Say this:**
> "Cache-aside: look in Redis for `user:{id}`. On a **hit**, return it. On a **miss**, read the database, store it with `SET user:{id} <json> EX 5`, and return it. After 5 seconds Redis deletes it automatically, so data is at most 5 seconds stale. On **update** I write the database first, then **delete** the cache key, so the next read loads fresh data."

```python
cached = r.get(f"user:{uid}")
if cached: return json.loads(cached)
user = db.get(uid)
r.set(f"user:{uid}", json.dumps(user), ex=5)
return user
```

**Follow-ups**
- **"Why delete on update instead of updating the cache?"** Simpler and safer: two concurrent updates could write the cache in the wrong order. A delete just forces a fresh read.
- **"What's a good TTL?"** Depends how stale the data can be. A profile can be minutes old. A balance should never come from cache.
- **"Cache stampede?"** A hot key expires and 1,000 requests hit the DB at once. Fixes: a lock so only one request refills, or slightly random TTLs.
- **"Missing user?"** Cache the "not found" briefly too, or repeated bad ids hammer the DB.
- **"What Redis type?"** A string with JSON for the whole object, or a **hash** (`HSET user:1 name Asha age 21`) to read or update single fields.
- **"Don't cache what?"** Money, permissions right after they change, and anything that must be exactly current.

---

# Part 5 · Redis as a queue vs RabbitMQ (hands-on)

**Say this:**
> "A Redis **list** is a queue. The producer `LPUSH`es a job, the worker `BRPOP`s it: that's first in, first out, and BRPOP blocks until a job arrives, so there's no busy polling. The catch: if the worker crashes after popping, the job is lost. So I use `BLMOVE` to atomically move the job to a `processing` list, and remove it only after success (that's my **ack**). Failed jobs are retried a few times, then moved to a **dead-letter** list. A reaper moves jobs stuck in `processing` back to the queue."

| | Redis list | RabbitMQ | Celery |
|---|---|---|---|
| What it is | Data structure you use as a queue | A real message broker | Python task library on top of Redis or RabbitMQ |
| Ack / redelivery | You build it (BLMOVE + LREM) | Built in (`basic_ack`; unacked messages are redelivered) | Built in (`acks_late`, retries) |
| Dead letters, routing | Build yourself | Built in | Via broker |
| When | Simple jobs, Redis already in the stack | Many job types, strict delivery, routing | Python team that wants retries, schedules, chains for free |

**Redis Streams** (`XADD`, `XREADGROUP`, `XACK`) give consumer groups and acks inside Redis, and are worth naming as the "proper" Redis queue.

---

# Part 6 · Rapid-fire (one clear answer each)

**MongoDB**
- **What:** a document database: stores JSON-like documents, with a flexible schema and no joins by default.
- **When:** data whose shape varies per record (form builders, event logs), or that you read as a whole document.
- **When not:** money and strongly related data needing transactions and joins → Postgres.
- **Indexes:** single, compound and text indexes exist there too; the same left-prefix rule as SQL.
- **Embed vs reference:** embed what you always read together (an order's items); reference what grows without limit or is shared.

**"An API takes 5 seconds. What do you do?"**
1. **Measure, don't guess.** Log timing per step (or use tracing). Is it the DB, an external call, or Python code?
2. **DB:** run `EXPLAIN ANALYZE` on the slow query. A "Seq Scan" on a big table means you need an index. Check for **N+1** (a query inside a loop → one JOIN or `IN (...)`).
3. **External call** (email, payment, AI): move it off the request path to a queue, set a timeout, or call in parallel with `asyncio.gather`.
4. **Repeated reads:** cache them in Redis with a TTL.
5. **Too much data:** paginate, select only the needed columns.
6. **Async mistakes:** a blocking call inside `async def` freezes everything (your Vaidya story).

**Index types and why**
- **Why:** without an index the DB reads every row; with a B-tree it jumps to the match (like a book's index). The cost is slower writes and more storage.
- **B-tree (default):** `=`, `<`, `>`, `BETWEEN`, `ORDER BY`, prefix `LIKE 'abc%'`.
- **Composite** `(tenant_id, created_at)`: the left-prefix rule. It helps `WHERE tenant_id = ?` and `WHERE tenant_id = ? AND created_at > ?`, not `created_at` alone.
- **Unique:** speed plus a guarantee (no duplicate emails, event ids).
- **Partial:** `WHERE status = 'pending'` indexes only the rows you query, so it's small.
- **Covering** (`INCLUDE`): the query is answered from the index alone.
- **GIN:** JSONB, arrays, full-text search. **Hash:** equality only, rarely needed.
- **Don't index:** small tables, columns with few distinct values alone (booleans), or write-heavy columns you never filter on.

**Data integrity**
- **Constraints in the DB:** `NOT NULL`, `UNIQUE`, `FOREIGN KEY`, `CHECK (amount > 0)`. The last line of defence even if the code has a bug.
- **Transactions:** all-or-nothing (event id + order update together).
- **Atomic updates:** `UPDATE ... SET balance = balance - 10 WHERE balance >= 10`, not read-then-write.
- **Validation:** Pydantic at the API edge, business rules in the service layer, constraints in the DB.
- **Isolation / locks:** `SELECT ... FOR UPDATE` when two requests change the same row.

**Generators**
- A function with `yield` returns values **one at a time, lazily**. It remembers where it stopped.
- **Why:** memory. Reading 10 lakh rows as a generator keeps one chunk in memory; a list keeps all of them.
- `(x*x for x in rows)` is a generator expression; `[...]` builds a list.
- A generator can be consumed **only once**.
- Real use: `read_chunks()` in the CSV worker, streaming responses, reading big files line by line.

**FastAPI architecture and validation**
- **Layers:** router (HTTP only) → service (business rules) → repository (SQL) → DB. Dependencies injected with `Depends` (DB session, current user).
- **Validation:** Pydantic models on request bodies give automatic **422** errors with field details. Use `Field(gt=0, max_length=100)` for limits and `field_validator` for custom rules. Use `response_model` to control what goes out (never leak password hashes).
- **Where each check goes:** shape and format → Pydantic; "is this email already taken?" → service + DB unique constraint; permissions → auth dependency.

**Async vs sync**
- `async def` + `await` for **I/O** (DB with asyncpg, HTTP with httpx, Redis): while one request waits, the event loop serves others.
- A **blocking** call (`requests`, `time.sleep`, psycopg2) inside `async def` freezes the loop for **everyone**.
- If a library is sync, write a plain `def` route; FastAPI runs it in a **threadpool**. Or call `await run_in_threadpool(fn)`.
- **CPU-heavy** work (big calculations): neither helps because of the GIL. Use a **process pool** or a separate worker.

---

## If they ask you to code live
1. **Say the plan first** in 2–3 lines ("dict of deques, drop old, count, allow").
2. Write the **simplest working version**, then improve it (in-memory → Redis → atomic).
3. **Test it out loud** with a tiny example: 4 calls → T, T, T, F.
4. **Name the trade-off:** memory, multi-server, edge cases.
