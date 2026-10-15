# 11 · Round 2 Prep: Hands-On Answers

Round 1 showed what they want: **not tool names, but what the tool does, what data goes in, and what code runs.** "Use RabbitMQ" got the follow-up "why, and what exactly does the worker do?". Every answer below goes one level deeper than the tool name.

**The rule for every design answer:** *what goes in → what code runs → what happens when it fails → what I give up.*

## Part 0 · Simple first (learn this before anything else)

**New to Redis?** Read [12-redis-basics.md](12-redis-basics.md) first (about 20 minutes). It explains every Redis command used below.

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

**Line by line: what does `hits[user_id] = deque()` do?**

It creates an **empty box for a new user** and stores it in the dict under that user's id.
- `hits` is a dict: user id → that user's request times.
- `deque()` makes a new, empty deque (think: an empty list).
- `hits[user_id] = deque()` means "this user has no requests yet".

It runs **only the first time** we see a user, because of the `if user_id not in hits:` line above it. Watch `hits` change:
```python
hits = {}
# ("u1", 1): u1 is new  -> hits["u1"] = deque()  -> {"u1": deque([])}
#            append 1                            -> {"u1": deque([1])}
# ("u1", 2): u1 exists, skip creating            -> {"u1": deque([1, 2])}
# ("u2", 4): u2 is new  -> hits["u2"] = deque()  -> {"u1": deque([1, 2]), "u2": deque([4])}
```
Without that line, `hits["u2"]` would crash with **KeyError** because u2 isn't in the dict yet. `defaultdict(deque)` does this automatically: the first time you touch a new key, it creates the empty deque for you.

**Full walk-through of the example** `[(u1,1), (u1,2), (u1,3), (u1,4), (u2,4), (u1,11), (u1,12)]`:

| Request | u1's deque before | Drop older than t−10 | Count | Result | Deque after |
|---|---|---|---|---|---|
| (u1, 1) | (new) [] | [] | 0 | ALLOW | [1] |
| (u1, 2) | [1] | [1] | 1 | ALLOW | [1, 2] |
| (u1, 3) | [1, 2] | [1, 2] | 2 | ALLOW | [1, 2, 3] |
| (u1, 4) | [1, 2, 3] | [1, 2, 3] | 3 | **BLOCK** | [1, 2, 3] (blocked requests aren't stored) |
| (u2, 4) | (new) [] | [] | 0 | ALLOW | u2: [4] |
| (u1, 11) | [1, 2, 3] | drop 1 (1 ≤ 11−10) → [2, 3] | 2 | ALLOW | [2, 3, 11] |
| (u1, 12) | [2, 3, 11] | drop 2 (2 ≤ 12−10) → [3, 11] | 2 | ALLOW | [3, 11, 12] |

**Why deque and not something else? Is deque Python's queue?**

`deque` (said "deck") means **double-ended queue**. It's Python's go-to queue: `from collections import deque`. Add at the back with `append`, remove from the front with `popleft`, and both are O(1).

| Option | Remove the oldest | Verdict |
|---|---|---|
| `list` | `pop(0)` is **O(n)**: every other item shifts left | Works. With a limit of 3 the list never holds more than 3 items, so it's honestly fine here. Deque is the right habit for "remove from the front". |
| `collections.deque` | `popleft()` is **O(1)** | Best fit: times arrive in order, so the oldest is always at the front. |
| `queue.Queue` | `get()` | A **thread-safe** queue for passing work between threads. It has locks and no peeking at the front. Overkill here. |
| `asyncio.Queue` | `await get()` | Same idea for async tasks. Not needed here. |
| `heapq` | `heappop` O(log n) | For items that arrive **out of order**. Ours arrive in time order, so no heap is needed. |

**Say it in one line:** "Requests come in time order, so the oldest is always at the front. A deque lets me drop from the front in O(1). A list would also work since it holds at most 3 items, but `pop(0)` is O(n) in general."

**Why `<=` in `q[0] <= t - window`?** A request exactly 10 s old has just left the window. Either `<` or `<=` is fine if you say which one you chose and why.

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
*If they push:* stampede, what not to cache. Part 4 explains it step by step.

### Redis as a queue
> "A Redis list is the queue. The API pushes a job id with LPUSH. A worker waits with BRPOP, takes the next job and processes it."
```python
r.lpush("jobs", job_id)                        # API side

while True:                                    # worker side
    _, job_id = r.brpop("jobs")                # waits until a job arrives
    process(job_id.decode())
```
*If they push ("worker crashes mid-job?"):* move the job to a `processing` list and remove it only after success, plus retries. Part 5 explains it step by step. Mention RabbitMQ only if asked.

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
| [redis_cache_simple.py](code/round2/redis_cache_simple.py) | The simple cache first: get_user with SET EX 5, update deletes the key, shows miss / hit / expiry | `python3 redis_cache_simple.py` |
| [redis_cache.py](code/round2/redis_cache.py) | Get user with 5 s TTL: miss, hit, invalidate on update, expiry | `python3 redis_cache.py` |
| [redis_basics.py](code/round2/redis_basics.py) | Redis from zero: every basic command (string, list, hash, sorted set) run and printed | `python3 redis_basics.py` |
| [fastapi_cache_ratelimit.py](code/round2/fastapi_cache_ratelimit.py) | Hand-written version of the fastapi-redis-sdk snippets: GET cache, DELETE evict, PUT write-through, `rate_limit` dependency returning 429 | `python3 fastapi_cache_ratelimit.py` |
| [redis_queue_simple.py](code/round2/redis_queue_simple.py) | The simple queue first: LPUSH + BRPOP (Level 1), then BLMOVE + LREM so a crash doesn't lose the job (Level 2) | `python3 redis_queue_simple.py` |
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

## Step by step (learn this part first)

Redis basics (what `SET`, `GET` and `EX` are): [12-redis-basics.md](12-redis-basics.md), section 3a.
Code: [redis_cache_simple.py](code/round2/redis_cache_simple.py). Run it with `python3 redis_cache_simple.py`, and it shows miss, hit, update and expiry.

### 1. What is the question really asking?

"Store a user in Redis with TTL 5 seconds" means:
- **Cache** = keep a copy of the user somewhere fast (Redis), so we don't ask the slow database every time.
- **TTL (time to live) = 5 s** = the copy **deletes itself after 5 seconds**. Redis does that for you.

Real-life example: you write a friend's phone number on a sticky note so you don't search your contacts every time, and the note dissolves after 5 seconds. Then you look it up again and write a new note.

**Why the TTL?** The database can change. With a 5 s TTL, the cached copy is **never more than 5 seconds old**, even if we forget to clean it up.

### 2. The two Redis commands you need

```python
r.set("user:1", '{"id": 1, "name": "Asha", "age": 21}', ex=5)   # save, auto-delete after 5 s
r.get("user:1")    # the JSON string, or None if missing / expired
```
- `ex=5` is the TTL in seconds (`SET key value EX 5`).
- Redis stores **strings**, so we turn the dict into JSON with `json.dumps` and back with `json.loads`.
- `r.ttl("user:1")` shows the seconds left. `-2` means the key is already gone.

### 3. The code (this is the whole answer)

```python
def get_user(user_id):
    key = f"user:{user_id}"
    cached = r.get(key)                         # 1. look in Redis
    if cached is not None:
        return json.loads(cached)               # 2. found -> HIT, no DB call
    user = db_get_user(user_id)                 # 3. not found -> MISS, ask the DB
    if user is not None:
        r.set(key, json.dumps(user), ex=5)      # 4. save a copy for 5 s
    return user
```

Line by line:
1. `key = f"user:{user_id}"`: one key per user, such as `user:1` and `user:2`.
2. `r.get(key)`: ask Redis. It returns the JSON string, or `None` if it was never stored or already expired.
3. `if cached is not None: return json.loads(cached)`: a **hit**. We answer from Redis in under a millisecond, with no DB involved.
4. `db_get_user(user_id)`: a **miss**. Read from Postgres the normal way.
5. `r.set(key, json.dumps(user), ex=5)`: put a copy in Redis so the next 5 seconds of requests are hits.
6. `if user is not None`: don't cache "nothing" here (see the follow-ups).

This pattern is called **cache-aside**: the app checks the cache first, and fills it itself on a miss.

### 4. Walk-through

| Time | Call | Redis has `user:1`? | Result | DB called? |
|---|---|---|---|---|
| 0.0 s | `get_user(1)` | no | MISS, read DB, `SET ... EX 5` | yes |
| 1.0 s | `get_user(1)` | yes (4 s left) | HIT | no |
| 3.0 s | `get_user(1)` | yes (2 s left) | HIT | no |
| 5.0 s | Redis deletes the key by itself | no | | |
| 6.0 s | `get_user(1)` | no | MISS, read DB, `SET ... EX 5` again | yes |

When I ran it locally, a miss took about 100 ms (the fake slow DB) and a hit took about 0.2 ms.

### 5. When the user is updated

```python
def update_user_age(user_id, age):
    db_update_age(user_id, age)          # 1. write the DB first (source of truth)
    r.delete(f"user:{user_id}")          # 2. delete the old copy
```
The next `get_user` is a miss and loads the new age. Without the delete, readers could see the old age for up to 5 s. Sometimes that's acceptable, and then the TTL alone is enough.

### 6. FastAPI endpoint (if they want it as an API)

```python
r = redis.Redis(decode_responses=True)       # created once at startup

@app.get("/users/{user_id}")
def read_user(user_id: int):
    user = get_user(user_id)
    if user is None:
        raise HTTPException(404, "User not found")
    return user
```
Async version: `import redis.asyncio as redis`, `async def`, and `await r.get(...)` / `await r.set(...)`.

**Say it in one line:** "I check Redis for `user:{id}`. If it's there, I return it. If not, I read the DB, store it with `SET ... EX 5` and return it. Redis deletes it after 5 seconds, so it's never more than 5 seconds stale, and on update I delete the key."

### 7. Follow-ups (simple answers)

- **"Why delete on update, not update the cache?"** Two updates at the same time could write the cache in the wrong order and leave old data. Deleting is always safe: the next read loads the truth.
- **"Why 5 seconds? How do you pick a TTL?"** It's how stale the data is allowed to be. A user's name can be minutes old. A wallet balance should never come from cache.
- **"User doesn't exist, and someone keeps asking for id 999?"** Every call is a miss and hits the DB. Fix: cache "not found" briefly too, for example store `"null"` with `ex=5`. That's in [redis_cache.py](code/round2/redis_cache.py).
- **"Redis is down?"** Wrap the Redis calls in `try/except` and fall back to the DB. The cache is a speed-up, so the app must still work without it.
- **"Cache stampede?"** A very popular key expires, and 1,000 requests miss at the same moment and all hit the DB. Fixes, simplest first: add a little random time to the TTL (`ex=5 + random.randint(0, 2)`) so keys don't all expire together, or let only one request refill using a short lock (`SET lock:user:1 1 NX EX 2`) while the others wait briefly or get the old value.
- **"String or hash?"** A string with JSON is simplest for reading the whole user. A hash (`HSET user:1 name Asha age 21`) lets you read or change one field. Note that `EXPIRE` works on the whole key either way.
- **"What should NOT be cached?"** Money, permissions right after they change, and anything that must be exactly current.

---

## Full version (one level deeper)

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

# Part 4b · The library version: `cache()`, `cache_evict()`, `cache_put()`, `rate_limit()`

Those snippets come from **fastapi-redis-sdk** (`pip install fastapi-redis-sdk`, `from redis_fastapi import ...`). It's Redis's official FastAPI SDK, announced in September 2026 ([blog](https://redis.io/blog/the-official-fastapi-redis-sdk-is-now-available/)). Everything below was checked against its source (v0.9.0), not guessed. Setup is one line:

```python
FastAPIRedis(app).lifespan().caching().rate_limiting()   # connect Redis on startup, close on shutdown
```

**Big idea:** it's the **same cache-aside and INCR counter as Part 4 and Part 3**. The library just runs it for you inside `Depends(...)`, so the endpoint body only talks to the DB.

### 1. `Depends(cache(ttl=60, eviction_group="users"))` on GET: what happens

1. **Builds a key from the URL.** `GET /users/5?x=1` becomes roughly `<prefix>:{users}:users:5:x=1`. The path's `/` turns into `:`, sorted query params are appended, and the group sits in `{}`.
2. **Looks in Redis.**
   - **HIT:** returns the cached response straight away. **Your endpoint function never runs.** It does this by raising an internal exception that a handler turns into the response.
   - **MISS:** marks the request as "store this", lets your endpoint run (`db.get_user`), and then a middleware saves the response in Redis with **TTL 60 s**.
3. It also adds HTTP headers: `X-Redis-Cache: HIT/MISS`, `ETag` and `Cache-Control`.

**Eviction group = a label for keys that belong together** ("all user entries"). Later you can wipe the whole group at once. The `{users}` braces keep all of them on the same Redis Cluster node, so a group delete can be atomic.

### 2. `Depends(cache_evict(eviction_group="users", key_builder=usr_key_builder))` on DELETE

1. Lets the endpoint run first (`db.delete_user`).
2. **Only if it succeeded**, it deletes the cache entry.
   - **With `key_builder`**, it deletes **just that one key**, here user 5. `usr_key_builder` is the app's own function and must build the **same key** the GET used.
   - **Without `key_builder`**, it deletes the **whole `users` group**: every cached user.
3. If the endpoint raised an error, nothing is deleted, because the DB didn't change.

### 3. `Depends(cache_put(eviction_group="users", ttl=300))` on PUT: write-through

1. The endpoint **always runs** (`db.update`).
2. Then its response is **written into the cache** under the same key, with **TTL 300 s**.
3. So the next GET is already a hit with the **new** data. This is **write-through**: write the DB, then write the cache. Compare **delete on update** in Part 4, where the next GET is a miss.

> Small thing to notice: GET caches for 60 s, but PUT writes with 300 s, so an entry written by PUT lives 5 minutes. Fine if you mean it. Keep the TTLs equal if you don't.

### 4. `Depends(rate_limit("100/minute"))`

1. `"100/minute"` means **limit 100, window 60 s**.
2. **Counter key** = `<prefix>:<scope>:<client IP>`. The scope defaults to the route, so each route and each IP gets its own counter.
3. **Algorithm:** a **fixed-window counter**, the same as `INCR` + `EXPIRE` in [12-redis-basics.md](12-redis-basics.md) section 5. The library does it atomically, with `INCREX` on Redis 8.8+ or a small Lua script on older versions.
4. Over the limit, it returns **429 Too Many Requests** with `Retry-After` plus `X-RateLimit-Limit`, `X-RateLimit-Remaining` and `X-RateLimit-Reset`. The endpoint doesn't run.
5. You can stack two limits (`"10/second"` for bursts and `"100/minute"` for sustained traffic) with different `scope=` values, or pass `identifier=` to count per user instead of per IP.

### The simple hand-written version (say and type this)

Runnable with tests: [fastapi_cache_ratelimit.py](code/round2/fastapi_cache_ratelimit.py) (`python3 fastapi_cache_ratelimit.py`).

```python
def user_key(user_id):
    return f"user:{user_id}"                       # ONE key format for GET, PUT, DELETE

@app.get("/users/{user_id}")                       # = cache(ttl=60)
async def get_user(user_id: int):
    cached = await r.get(user_key(user_id))
    if cached is not None:
        return json.loads(cached)                  # HIT
    user = await db.get_user(user_id)              # MISS
    await r.set(user_key(user_id), json.dumps(user), ex=60)
    return user

@app.delete("/users/{user_id}")                    # = cache_evict(key_builder=...)
async def delete_user(user_id: int):
    await db.delete_user(user_id)                  # DB first
    await r.delete(user_key(user_id))              # then drop the cached copy

@app.put("/users/{user_id}")                       # = cache_put(ttl=300)
async def replace_user(user_id: int, body: User):
    user = await db.update(user_id, body)          # DB first
    await r.set(user_key(user_id), json.dumps(user), ex=300)   # then write the new copy
    return user
```

```python
def rate_limit(limit: int, window: int):           # = rate_limit("100/minute")
    async def check(request: Request):
        key = f"rate:{request.url.path}:{request.client.host}"
        count = await r.incr(key)                  # 1, 2, 3 ...
        if count == 1:
            await r.expire(key, window)            # first request starts the window
        if count > limit:
            raise HTTPException(429, "Too Many Requests",
                                headers={"Retry-After": str(await r.ttl(key))})
    return check

@app.get("/api", dependencies=[Depends(rate_limit(100, 60))])
async def api():
    return {"ok": True}
```

**Why is `rate_limit` a function that returns a function?** `Depends()` needs a function FastAPI can call on every request. `rate_limit(100, 60)` runs **once** at startup and returns `check`, which "remembers" 100 and 60 (a closure). FastAPI then calls `check(request)` on every request. If `check` raises, the endpoint never runs. The library's `rate_limit("100/minute")` works the same way.

**Why is the cache inside the endpoint and not a `Depends` in the simple version?** A dependency can't simply return the response and skip the endpoint. The library needs an exception handler for hits and a middleware to capture the response on a miss. Writing it in the endpoint is the plain, readable version.

### Library or hand-written?

- **Use the library** in a real project. It covers the edge cases for you: atomic Lua, `Retry-After` and `X-RateLimit-*` headers, ETag and `Cache-Control`, per-user cache entries, Redis Cluster, and metrics.
- **Write it by hand** in an interview, or when you need custom logic (cache only some results, a TTL based on the data, a limit per tenant). The library offers a `CacheBackend` / `RateLimitBackend` for that too.

**Say it in one line:** "These are cache-aside, delete-on-delete, write-through-on-update and a fixed-window INCR counter, packaged as FastAPI dependencies. By hand, it's `GET`/`SET EX`/`DEL` and `INCR`+`EXPIRE` with a 429."

### Follow-ups

- **"Cache key per user? Two users see the same `/me`?"** The default key is the URL only. If the response depends on who's asking, the key must include the user, for example `user:{id}`. A shared key would leak one user's data to another. The library has `vary_on_session=True` for this.
- **"Rate limit by IP: what about users behind one office Wi-Fi?"** They share one counter. Limit by user id or API key instead, using an `identifier=` function.
- **"Fixed window weakness?"** It allows up to double the limit around the window edge, for example 100 at 0:59 and 100 at 1:01. For a strict limit, use the sliding window (sorted set) in Part 3.
- **"Redis down?"** For the cache, skip Redis and read the DB. For the rate limiter, decide between fail open (allow) and fail closed (block). Most APIs fail open.
- **"Write-through or delete on update?"** Write-through gives a hit right after an update, but two concurrent PUTs can leave the older one in the cache. Delete-on-update is always safe and just costs one miss.

---

# Part 5 · Redis as a queue vs RabbitMQ (hands-on)

## Step by step (learn this part first)

Need Redis basics first (what a list is, LPUSH, BRPOP)? See [12-redis-basics.md](12-redis-basics.md).

Code for this part: [redis_queue_simple.py](code/round2/redis_queue_simple.py) (Level 1 and Level 2, with tests). Run it with `python3 redis_queue_simple.py`.

### 1. Why a queue at all?

Think of a restaurant. The waiter takes your order, writes a ticket, puts it on the kitchen rail and comes back to you. The waiter does not stand in the kitchen cooking your food while other customers wait.

- **API = waiter.** It writes a ticket (the job id) and replies right away (`202 Accepted`).
- **Queue = the ticket rail.** Tickets wait there in order.
- **Worker = cook.** A separate process takes the next ticket and does the slow work.

What this gets you:
1. **The API stays fast.** A 10-lakh-row CSV doesn't hold the HTTP request open.
2. **Spikes are absorbed.** If 500 jobs arrive at once, they wait in the queue instead of crashing the server.
3. **You can scale the slow part alone.** Need more speed? Start more workers. The API doesn't change.
4. **Failures can be retried.** If the work fails, the job can go back on the queue.

**Say it in one line:** "A queue separates *accepting* work from *doing* work, so the API stays fast and workers do the slow part at their own pace."

### 2. A Redis list is the queue

A Redis list is just an ordered list with two ends. Two commands:
- `LPUSH jobs X` adds X to the **left** end.
- `RPOP jobs` takes from the **right** end.

Push on the left, take from the right, and the oldest item is always taken first. That's **first in, first out (FIFO)**.

| Step | Command | List `jobs` (left ... right) |
|---|---|---|
| 1 | `LPUSH jobs job1` | `[job1]` |
| 2 | `LPUSH jobs job2` | `[job2, job1]` |
| 3 | `LPUSH jobs job3` | `[job3, job2, job1]` |
| 4 | `RPOP jobs` → `job1` | `[job3, job2]` |
| 5 | `RPOP jobs` → `job2` | `[job3]` |

`RPUSH` + `LPOP` works the same way, just mirrored. Pick one pair and stick to it.

### 3. Producer (the API side): one line

```python
r = redis.Redis(decode_responses=True)   # get str back instead of bytes

def enqueue(job_id):
    r.lpush("jobs", job_id)
```

- `r.lpush("jobs", job_id)`: adds the job id to the left of the list named `jobs`. If the list doesn't exist, Redis creates it. It returns immediately.
- **What goes in the queue?** Only the **job id**, not the file or the 10 lakh rows. The details live in the `import_jobs` table (Part 1). The message stays tiny, and the database stays the source of truth.

### 4. Worker (the consumer side)

```python
while True:
    _queue_name, job_id = r.brpop("jobs")   # waits until a job arrives
    process(job_id)
```

Line by line:
- `while True:` A worker is a separate program that runs forever, one job after another.
- `r.brpop("jobs")`: **B**locking **R**ight **POP**. It takes from the right end. **If the list is empty, it waits** (the connection just sits there) until something is pushed, then returns at once.
- It returns a **tuple**: `("jobs", "job1")`, meaning which list it came from and the value. That's why we unpack two things. (`brpop` can watch several lists at once, so it tells you which one.)
- `process(job_id)`: do the real work, such as reading the CSV or sending the email.

**Why `BRPOP` and not `RPOP` in a loop?** `RPOP` on an empty list returns `None` immediately. You'd either spin in a loop hitting Redis thousands of times a second (wasted CPU), or add `sleep(1)`, and then a job waits up to 1 s for no reason. `BRPOP` waits *inside Redis* and wakes up the moment a job arrives.

**Timeout:** `r.brpop("jobs", timeout=5)` waits at most 5 s and returns `None` if nothing came. That's useful so the loop can check "should I shut down?" Timeout `0` means wait forever.

### 5. Walk-through: 3 jobs, 2 workers

| Time | What happens | `jobs` list |
|---|---|---|
| t0 | Worker A and Worker B both call `BRPOP` and wait | `[]` |
| t1 | API: `LPUSH jobs job1` | `[job1]` → A gets `job1` instantly → `[]` |
| t2 | API pushes `job2` and `job3` | `[job3, job2]` → B gets `job2` → `[job3]` |
| t3 | A finishes `job1`, calls `BRPOP` again, gets `job3` | `[]` |

**Can two workers get the same job?** No. Every Redis command runs one at a time (Redis is single-threaded), so a pop is atomic: one item goes to exactly one worker.

**Want more speed?** Start more workers. They all `BRPOP` the same list and share the work.

### 6. The problem: worker crashes mid-job

```
BRPOP -> job1 is REMOVED from Redis -> worker starts processing -> worker crashes
```
Now `job1` exists nowhere: not in the queue, not finished. **The job is lost.**

### 7. The fix: don't delete until it's done (Level 2)

Idea: instead of *taking the ticket off the rail*, **move it to a "being cooked" rail**. Remove it only when the dish is served.

```python
while True:
    job_id = r.blmove("jobs", "jobs:processing", 0, "RIGHT", "LEFT")
    process(job_id)
    r.lrem("jobs:processing", 1, job_id)    # done -> remove ("ack")
```

- `BLMOVE jobs jobs:processing RIGHT LEFT`: take from the right of `jobs` and push to the left of `jobs:processing`, **as one atomic step**. It also blocks while empty, like BRPOP. (Older Redis calls it `BRPOPLPUSH`.)
- `LREM jobs:processing 1 job_id`: remove one copy of `job_id` from the processing list. This is the **ack** ("acknowledged, done").
- **If the worker crashes** between those two lines, `job_id` is still in `jobs:processing`. A small recovery step (on worker startup, or every few minutes) moves stuck jobs back to `jobs`:

```python
while r.lmove("jobs:processing", "jobs", "RIGHT", "RIGHT"):
    pass
```

| Step | `jobs` | `jobs:processing` |
|---|---|---|
| `LPUSH jobs job1` | `[job1]` | `[]` |
| Worker `BLMOVE` | `[]` | `[job1]` |
| Worker crashes | `[]` | `[job1]` ← still safe |
| Recovery moves it back | `[job1]` | `[]` |
| New worker `BLMOVE`, processes, `LREM` | `[]` | `[]` ✓ |

**Say it in one line:** "BRPOP deletes the job before the work is done, so a crash loses it. I use BLMOVE to move it to a processing list and remove it only after success. Anything left in processing after a crash gets put back."

### 8. Retries and dead-letter (only if they push)

Some jobs fail even without a crash, for example when an email provider is down. Store an attempt count with the job:

```python
job = {"job_id": "abc", "attempts": 0}
try:
    process(job)
except Exception:
    job["attempts"] += 1
    if job["attempts"] < 3:
        r.lpush("jobs", json.dumps(job))        # try again later
    else:
        r.lpush("jobs:dead", json.dumps(job))   # give up, a human looks at it
```

- **Dead-letter list** = jobs that failed 3 times. You don't retry them forever (that blocks other work), and you don't throw them away. Someone checks them, fixes the cause, and re-queues them.
- Full version with backoff: [redis_queue.py](code/round2/redis_queue.py).

### 9. Follow-ups they may ask

- **"Can a job run twice?"** Yes. If the worker finishes the work but crashes just before `LREM`, recovery puts it back and it runs again. That's called **at-least-once** delivery. So the job must be **idempotent**, meaning running it twice gives the same result. Examples: `ON CONFLICT DO NOTHING` on inserts, or checking `status = 'done'` in the jobs table before starting.
- **"What if Redis itself restarts?"** Redis is in memory. Turn on persistence (AOF), and keep the **jobs table in Postgres as the source of truth**. A sweeper re-queues any job still `queued` or `processing` for too long. Even if Redis loses the list, nothing is lost for good.
- **"How do you see a backlog?"** `LLEN jobs` gives the queue length. Alert if it keeps growing, then add workers.
- **"Priority jobs?"** Use two lists: `r.brpop(["jobs:high", "jobs:low"])`. BRPOP checks the lists in the order given, so high always goes first.
- **"Run a job later (in 10 minutes)?"** A list can't do that. Use a **sorted set** with the run time as the score: `ZADD delayed <run_at> job_id`. A small loop moves due jobs (`ZRANGEBYSCORE delayed 0 now`) into `jobs`.
- **"Is order guaranteed?"** The queue hands jobs out in order. With 2+ workers they *finish* in any order, because a big job can take longer. If order matters per user, use one queue per user or one worker per key.
- **"Why not RabbitMQ?"** "Redis was already in my stack and my jobs were simple, so a list was enough. If I needed delivery guarantees built in (ack, redelivery on crash, dead-letter, routing to different consumers), I'd use RabbitMQ instead of building them myself."
- **"Why not Kafka?"** Kafka is a log for event *streams*, built for very high volume and for many consumers reading the same events. It's too much for a background job queue.
- **"Why not just Celery?"** Celery is a Python library that does all of this for you (retries, schedules) using Redis or RabbitMQ underneath. In a real project I'd likely use it, or RQ/ARQ. Writing it by hand here shows I understand what it does inside.

---

## Full version (one level deeper)

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
