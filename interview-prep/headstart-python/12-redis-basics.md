# 12 · Redis from Zero

Read this **before** the rate limiter, cache and queue in [11-round2-prep.md](11-round2-prep.md). Everything there is built from the few commands on this page.

Hands-on: [redis_basics.py](code/round2/redis_basics.py) runs every command below and prints what happens. Run it with `python3 redis_basics.py`.

---

## 1. What is Redis?

**Redis is a server that keeps data in memory (RAM) as keys and values.**

Think of it as a Python `dict` that:
- lives in a **separate server**, so all your API servers and workers share the same one
- every program can read and write over the network
- can make keys **expire on their own** after N seconds

```
Your FastAPI server 1 ─┐
Your FastAPI server 2 ─┼──>  Redis (one shared "dict" in RAM)
Your worker process   ─┘
```

**Why it's fast:**
1. **Data is in RAM.** Reading RAM takes about 100 nanoseconds, while a disk read is thousands of times slower. Postgres also has to parse SQL, plan the query and read pages.
2. **Simple operations.** `GET key` is a hash lookup, so it's O(1).
3. **Single-threaded command execution.** Commands run one at a time, so there are no locks. As a side effect, **every command is atomic**: two clients can never half-run the same command. This is why `INCR` and `BRPOP` are safe with many servers.

Typical speed: a command takes well under a millisecond, and a single Redis can handle around 100k+ simple commands per second.

**Say it in one line:** "Redis is an in-memory key-value store. It's fast because data is in RAM and commands are simple, and since commands run one at a time, each one is atomic."

**Redis is NOT your main database.** RAM is limited and costly, and data can be lost (see section 6). Postgres stays the source of truth, and Redis holds **fast, temporary or shareable** data.

---

## 2. Run it and connect from Python

**Start Redis** (pick one):
```bash
docker run -d -p 6379:6379 redis      # any OS with Docker
brew install redis && brew services start redis   # Mac
sudo apt install redis-server         # Ubuntu
```
Redis listens on port **6379** by default.

**Try it by hand** with the built-in CLI:
```bash
redis-cli
127.0.0.1:6379> SET name Gautam
OK
127.0.0.1:6379> GET name
"Gautam"
```

**From Python** (`pip install redis`):
```python
import redis

r = redis.Redis(host="localhost", port=6379, decode_responses=True)
r.set("name", "Gautam")
print(r.get("name"))     # Gautam
```
- `decode_responses=True` gives you `str` back. Without it, you get bytes (`b"Gautam"`) and must `.decode()`.
- Create `r` **once** and reuse it. It keeps a connection pool inside. In FastAPI, create it at startup.
- Async FastAPI: `import redis.asyncio as redis`, then the same calls with `await r.get(...)`.

---

## 3. The 4 data types you need

A key is always a string, like `"user:1"`. The value can be one of several types. You need four.

### a) String: a single value (cache, counters)

```python
r.set("user:1", '{"name": "Asha", "age": 21}')   # store
r.get("user:1")                                  # read -> the JSON string
r.set("user:1", "...", ex=5)                     # store AND delete automatically after 5 s
r.ttl("user:1")                                  # seconds left (-1 = no expiry, -2 = key gone)
r.delete("user:1")                               # remove now

r.incr("count:u1")          # +1 and return the new value (creates it at 0 if missing) -> 1
r.incr("count:u1")          # -> 2
r.expire("count:u1", 10)    # add an expiry to an existing key
```
- `ex=5` (`SET key value EX 5`) is how **every cache with a TTL** works.
- `INCR` is atomic: 10 servers calling it at once still count correctly. That's the base of a **simple rate limiter**.
- Redis stores strings, not Python dicts. Use `json.dumps` to save and `json.loads` to read.

### b) List: an ordered list with two ends (queues)

```python
r.lpush("jobs", "job1")     # add on the LEFT     -> [job1]
r.lpush("jobs", "job2")     #                     -> [job2, job1]
r.rpop("jobs")              # take from the RIGHT -> "job1"  (oldest first = FIFO)
r.brpop("jobs", timeout=5)  # same, but if empty WAIT up to 5 s -> ("jobs", "job2") or None
r.llen("jobs")              # how many items
r.lrange("jobs", 0, -1)     # look at all items without removing them
```
- `LPUSH` + `BRPOP` = **a job queue**. The `B` means *blocking*: it waits for an item instead of you polling in a loop.

### c) Hash: a small dict under one key (objects, job progress)

```python
r.hset("import:abc", mapping={"status": "processing", "rows_done": 5000})
r.hget("import:abc", "status")      # "processing"
r.hgetall("import:abc")             # {"status": "processing", "rows_done": "5000"}
r.hincrby("import:abc", "rows_done", 5000)   # add to one field atomically
```
- Good when you update **one field** often, like CSV import progress, without rewriting the whole JSON.
- Values come back as strings, so `"5000"` needs `int()`.

### d) Sorted set: unique members, each with a number "score", kept sorted (time windows, leaderboards)

```python
r.zadd("hits:u1", {"req-1": 1001, "req-2": 1004})   # member -> score (here: timestamp)
r.zcard("hits:u1")                                   # how many members -> 2
r.zremrangebyscore("hits:u1", 0, 1002)               # remove members with score 0..1002
r.zrange("hits:u1", 0, -1, withscores=True)          # [("req-2", 1004.0)]
```
- Score = time, so you can say "remove everything older than 10 s" in one command. That's the **sliding-window rate limiter** across many servers.
- Also used for leaderboards (score = points) and delayed jobs (score = run-at time).

### Cheat table

| Type | Think of it as | Key commands | Used for |
|---|---|---|---|
| String | one value | `SET` (with `EX`), `GET`, `DEL`, `INCR`, `EXPIRE`, `TTL` | cache, counters, simple rate limit |
| List | a line of items | `LPUSH`, `RPOP`, `BRPOP`, `LLEN` | job queue |
| Hash | a small dict | `HSET`, `HGET`, `HGETALL`, `HINCRBY` | objects, job progress |
| Sorted set | sorted by a number | `ZADD`, `ZREMRANGEBYSCORE`, `ZCARD`, `ZRANGE` | sliding-window rate limit, leaderboard, delayed jobs |

(There's also **Set** for unique members, with `SADD`/`SISMEMBER`, for example "has this event id been seen". You'll rarely need it today.)

---

## 4. Naming keys

Use `type:id` with colons: `user:1`, `import:abc123`, `rate:u1`, `jobs`. In a multi-tenant app, add the tenant: `tenant:42:user:1`. Colons are just a convention, but every tool groups keys by them, and it prevents two features from clashing on the same key.

---

## 5. The three uses you'll be asked about

These are just the commands above, put together. The full versions are in 11.

**Cache (string + EX):**
```python
cached = r.get(f"user:{uid}")
if cached:
    return json.loads(cached)                     # hit: no DB
user = db_get_user(uid)                           # miss: go to DB
r.set(f"user:{uid}", json.dumps(user), ex=5)      # keep for 5 s
return user
```

**Rate limit, simplest (string + INCR + EXPIRE): max 3 per 10 s window:**
```python
key = f"rate:{user_id}"
count = r.incr(key)            # 1, 2, 3, 4 ...
if count == 1:
    r.expire(key, 10)          # first request starts a 10 s window
if count > 3:
    raise HTTPException(429, "Too many requests")
```
This is a **fixed** window: the counter resets every 10 s. Its weakness is that 3 requests at second 9 and 3 at second 11 make 6 in 2 seconds. The sorted-set version fixes that (11, Part 3).

**Queue (list + LPUSH + BRPOP):**
```python
r.lpush("jobs", job_id)                 # API
_name, job_id = r.brpop("jobs")         # worker: waits for the next job
```

---

## 6. Can Redis lose data? (persistence)

Data is in RAM, so **if Redis stops, RAM is wiped**. Redis can save to disk in two ways:

| Option | What it does | Data you can lose on a crash |
|---|---|---|
| **None** | Pure cache, nothing saved | Everything (fine for a cache) |
| **RDB snapshot** | Every few minutes, writes the whole dataset to a file (`dump.rdb`) | Changes since the last snapshot (minutes) |
| **AOF (append-only file)** | Logs every write command; replays it on restart. Usually `appendfsync everysec` | About 1 second |

**What to say:**
> "For a cache I don't care. If Redis restarts, the next reads just go to the DB. For a queue I turn on AOF, and I still keep the job's status in Postgres. So if Redis ever loses the list, a sweeper re-queues anything still pending from the DB. Redis is never my only copy of important data."

**Full memory:** set `maxmemory` and an eviction policy. For a cache, `allkeys-lru` drops the least recently used keys. For a queue, use `noeviction`, because silently dropping jobs is worse than an error.

---

## 7. Common follow-ups

- **"Why Redis and not a Python dict?"** A dict lives inside one process. With 4 API servers, each has its own dict, so the cache and rate limit counts don't agree. Redis is one shared store, and it supports expiry and blocking pops.
- **"Is Redis single-threaded, so isn't it slow?"** Commands are tiny and in memory, so one thread handles 100k+ per second. Being single-threaded is what makes each command atomic. (Network I/O can use extra threads in newer versions.)
- **"Two commands together atomic?"** Each command is atomic, but two separate commands are not. For example, between `INCR` and `EXPIRE` the server could crash, leaving a counter without an expiry. Fixes: `MULTI`/`EXEC` (a pipeline transaction), or a small **Lua script**, which Redis runs as one step.
- **"Redis vs Memcached?"** Both cache in memory. Memcached only has strings. Redis has lists, hashes and sorted sets, plus persistence, which is why it can also do queues and rate limits.
- **"Redis vs Postgres?"** Postgres is the source of truth: durable, with SQL, joins and transactions. Redis is fast, temporary, shared state: cache, counters, queues, sessions.
- **"How do you scale Redis?"** Replicas for reads and failover (Sentinel), and **Redis Cluster** to split keys across nodes. I'd say I haven't run a cluster myself.

---

## 8. Self-check (say it out loud)

1. What is Redis, in one line, and why is it fast?
2. Which command stores a value for 5 seconds?
3. Which type is a queue, and which two commands?
4. Why is `INCR` safe with 10 API servers?
5. What happens to a cache and to a queue if Redis restarts?
6. Sorted set: what's the score in a rate limiter?

<details><summary>Answers</summary>

1. An in-memory key-value store shared by all servers. It's fast because data is in RAM, operations are simple, and commands run one at a time.
2. `SET key value EX 5` (`r.set(k, v, ex=5)`).
3. A list: `LPUSH` to add, `BRPOP` to take (waits if empty).
4. Redis runs commands one at a time, so each `INCR` is atomic.
5. Cache: just refills from the DB. Queue: AOF keeps most of it, and the job table in Postgres lets a sweeper re-queue the rest.
6. The request's timestamp, so old ones can be removed by score.
</details>
