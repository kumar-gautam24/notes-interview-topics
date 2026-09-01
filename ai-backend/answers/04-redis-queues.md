# Document 04 — Redis / Queues (Questions 171–215)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 171. What is Redis?

**Definition.** An in-memory data structure server. Not just a key-value cache — it stores strings, hashes, lists, sets, sorted sets, streams, bitmaps, HyperLogLogs, and geospatial indexes, and exposes atomic operations on each.

**Why it exists.** A database round trip to disk costs milliseconds; a Redis round trip costs tens of microseconds. For data accessed thousands of times per second, that difference is the whole product.

**The architectural point:** Redis is not "a faster database." It's a different tool. It trades durability and query flexibility for latency and atomic data-structure operations. Its most valuable feature is often not caching at all — it's providing **atomic primitives shared across processes**, which is what makes distributed rate limiting, locking, and queueing possible.

**Persistence options** (worth knowing, since "is it durable?" is the follow-up):
- **RDB** — periodic point-in-time snapshots. Compact, fast restart, loses everything since the last snapshot.
- **AOF** — appends every write command to a log. `appendfsync everysec` is the default: at most one second of data loss.
- **Both** — the usual production choice; AOF for durability, RDB for fast restarts.

Even with AOF, Redis is *less* durable than PostgreSQL, and that's a deliberate design choice, not a defect.

**Failure.** Treating Redis as a source of truth (Q192). Redis can lose data on failover; if it holds the only copy of something that matters, you will eventually lose it.

---

## 172. Why is it fast?

Five reasons, and being able to give more than "it's in memory" is the point:

1. **In-memory.** No disk seek on the read path. RAM access is ~100 nanoseconds; an SSD read is ~100 microseconds — a 1,000× difference.

2. **Single-threaded command execution.** Counter-intuitive but crucial: no locks, no mutexes, no context switching, no race conditions between commands. Every command is atomic *for free*. The CPU is rarely the bottleneck for a memory-access workload, so giving up multi-core parallelism costs little and buys enormous simplicity. (Redis 6+ does use threads for I/O reads/writes and background tasks like `UNLINK`, but command *execution* remains single-threaded.)

3. **Optimised data structures with encoding switches.** A small hash is stored as a compact `listpack` (an array, cache-friendly); it converts to a real hash table only past a size threshold. Small integers are shared objects. These encodings save both memory and cache misses.

4. **An efficient protocol (RESP)** — simple to parse, and it supports **pipelining**: send 1,000 commands in one network round trip instead of 1,000 round trips. On a 1ms-RTT link that's 1 second versus 1 millisecond.

5. **An event loop with I/O multiplexing** — one thread handling tens of thousands of connections via epoll, no thread-per-connection overhead.

**The consequence of single-threading you must remember:** one slow command blocks everything. `KEYS *` on a 10-million-key database, a `SORT` on a huge list, a Lua script with a loop, or `FLUSHALL` synchronously — each freezes the entire server for every client. This is the #1 Redis production incident.

---

## 173. Redis data structures?

| Structure | Operations | Use for |
|---|---|---|
| **String** | `GET`/`SET`/`INCR`/`APPEND`/`SETEX` | Cache, counters, flags, serialised blobs |
| **Hash** | `HGET`/`HSET`/`HINCRBY`/`HGETALL` | Objects with fields; partial updates |
| **List** | `LPUSH`/`RPOP`/`BLPOP`/`LRANGE` | Simple queues, recent-items feeds |
| **Set** | `SADD`/`SISMEMBER`/`SINTER`/`SCARD` | Membership, dedup, tags, relationships |
| **Sorted set (ZSet)** | `ZADD`/`ZRANGE`/`ZRANGEBYSCORE`/`ZPOPMIN` | Leaderboards, priority queues, time-ordered indexes, rate limiting |
| **Stream** | `XADD`/`XREADGROUP`/`XACK`/`XCLAIM` | Durable event log with consumer groups |
| **Bitmap** | `SETBIT`/`BITCOUNT`/`BITOP` | Dense boolean data (daily active users) |
| **HyperLogLog** | `PFADD`/`PFCOUNT`/`PFMERGE` | Approximate cardinality in 12 KB |
| **Geospatial** | `GEOADD`/`GEOSEARCH` | Location queries (built on ZSets) |

**The two that carry the most weight in interviews:**

**Sorted sets** are the most versatile structure Redis has. Score-ordered members with O(log n) insert and O(log n + m) range queries. They give you leaderboards, delayed/priority queues (score = execution timestamp), sliding-window rate limiters (score = request timestamp), and time-ordered indexes — all from one structure.

**Streams** are the right answer for anything queue-shaped in modern Redis (Q205–214). Append-only log, consumer groups, explicit acknowledgement, and pending-entry tracking for crash recovery.

**HyperLogLog** is worth mentioning as a signal: counting 100 million unique visitors exactly needs gigabytes; HLL does it in 12 KB with ~0.81% error. Knowing when approximate is good enough is an engineering skill.

---

## 174. When use a hash?

**When you have an object with multiple fields and you want to read or update fields individually.**

```
HSET user:1234 name "Gautam" email "g@x.com" credits 500
HINCRBY user:1234 credits -50        -- atomic, single field
HGET user:1234 credits                -- fetch one field
```

**Versus a serialised JSON string:**

| | Hash | JSON string |
|---|---|---|
| Update one field | `HSET` — atomic, small | Read all, parse, modify, serialise, write |
| Read one field | `HGET` — small transfer | Transfer everything, parse |
| Atomic increment | `HINCRBY` | Impossible without a lock |
| Nested data | Not supported | Supported |
| Memory (small objects) | **Much smaller** | Larger |

**The memory point is significant.** Under `hash-max-listpack-entries` (default 128) and `hash-max-listpack-value` (default 64 bytes), a hash is stored as a compact listpack. Redis's own benchmarks put this at roughly 5× less memory than separate keys, and it's also more cache-friendly. Storing a million small objects as hashes rather than key-per-field is a real cost difference.

**Failure.** `HGETALL` on a hash with 100,000 fields — it blocks the server while serialising, and transfers megabytes. Use `HSCAN` for iteration, or restructure so hashes stay small.

**Don't use a hash when:** you need per-field TTL (Redis 7.4 added `HEXPIRE`, but support is still uneven across clients — verify before relying on it), or the value is deeply nested.

---

## 175. When use a set?

**When you need unordered unique membership, and especially when you need set algebra.**

```
SADD tags:post:1 python redis backend
SISMEMBER tags:post:1 python          -- O(1)
SINTER tags:post:1 tags:post:2        -- shared tags
SDIFF   users:active users:paid       -- active but unpaid
SCARD   online:users                  -- count
```

**Use for:**
- **Deduplication** — seen event IDs, processed webhook IDs
- **Membership checks** — is this user in this cohort?
- **Relationships** — followers, group members, permissions
- **Tags and categories**, with intersection for multi-tag filtering
- **Random sampling** — `SRANDMEMBER` / `SPOP`

**The distinguishing feature is set operations.** `SINTER`, `SUNION`, and `SDIFF` in one atomic O(n) server-side command replace fetching two lists and comparing them in application code. That's a real architectural difference, not a micro-optimisation.

**Set vs sorted set:** use a plain set unless you need ordering, ranking, or range-by-score. Sets are smaller and faster; sorted sets cost an extra score per member plus skip-list overhead.

**Failure.** `SMEMBERS` on a set with millions of members blocks the server. Use `SSCAN`. Also, `SINTER` across very large sets is O(n×m) in the worst case — Redis optimises by starting with the smallest set, but it can still be a slow command.

**Memory note.** A set of small integers uses an `intset` encoding — extremely compact. Mixing in one string value converts the whole thing to a hash table and multiplies memory use. Keep integer sets integer-only.

---

## 176. When use a sorted set?

**Whenever ordering, ranking, or range-by-value matters.** This is Redis's most powerful structure.

```
ZADD leaderboard 4500 "player:1"
ZREVRANGE leaderboard 0 9 WITHSCORES     -- top 10
ZRANK leaderboard "player:1"             -- this player's rank, O(log n)
ZRANGEBYSCORE jobs 0 <now>               -- due jobs
ZPOPMIN priority_queue                    -- highest priority, atomic
```

**The four patterns worth knowing by name:**

**1. Leaderboards.** The obvious one. `ZREVRANK` gives a player's rank in O(log n), which is genuinely hard to do efficiently in a relational database at scale.

**2. Delayed / scheduled jobs.** Score = the Unix timestamp when the job should run.
```
ZADD delayed_jobs 1735689600 "job:abc"
ZRANGEBYSCORE delayed_jobs 0 <now> LIMIT 0 10    -- what's due
```
A worker polls for due jobs, moves them to the ready queue atomically via Lua. That's a complete delayed-job system in two commands.

**3. Sliding-window rate limiting.** Score = request timestamp.
```
ZREMRANGEBYSCORE rl:user1 0 <now-60s>    -- drop old
ZCARD rl:user1                            -- count in window
ZADD rl:user1 <now> <unique-id>
```
Accurate sliding window, unlike a fixed window which permits a 2× burst at the boundary.

**4. Time-ordered indexes.** Score = timestamp, member = ID. Cheap "most recent N" queries.

**Implementation.** A skip list plus a hash table — the skip list gives O(log n) ordered access, the hash gives O(1) score lookup by member. Small zsets use a listpack instead.

**Cost.** More memory per element than a set, and `ZADD` is O(log n) rather than O(1). Worth it only when you need the ordering.

---

## 177. What is TTL?

**Definition.** Time To Live — an expiry set on a key, after which Redis removes it automatically.

```
SET session:abc "..." EX 3600          -- expire in 1 hour
EXPIRE key 60                           -- set expiry on existing key
TTL key                                 -- seconds remaining (-1 no expiry, -2 gone)
PERSIST key                             -- remove expiry
```

**How expiry actually works** — two mechanisms, and knowing both is the depth signal:
1. **Lazy** — when a key is accessed, Redis checks whether it's expired and deletes it then. Cheap, but an untouched expired key sits in memory indefinitely.
2. **Active** — a background cycle samples 20 random keys with expiries, deletes the expired ones, and repeats if more than 25% were expired. Probabilistic, so expired keys can linger briefly.

**The consequence:** `TTL` is not a precise delete-at guarantee, and `used_memory` may include expired-but-unreaped keys. Usually irrelevant, occasionally confusing during a memory investigation.

**The gotchas that cause bugs:**
- **Most write commands clear the TTL.** `SET key value` on a key with a TTL removes the expiry. `SET key value KEEPTTL` preserves it. `INCR`, `HSET`, `LPUSH` preserve it; plain `SET` does not. This silently creates immortal keys.
- **A key with no TTL lives forever.** Every cache key must have one, or you have an unbounded memory leak with extra steps.
- Replicas don't expire keys independently — the primary sends an explicit `DEL` on expiry, so replicas can briefly serve a logically-expired key.

**Design rule:** TTL is your primary defence against unbounded memory growth. Set it on *every* cache key, and set `maxmemory` plus an eviction policy as the backstop.

---

## 178. What is cache-aside?

**Definition.** The application manages the cache explicitly: check cache → on miss, read the database → write to cache → return.

```python
async def get_user(uid):
    key = f"user:{uid}"
    cached = await redis.get(key)
    if cached:
        return json.loads(cached)
    user = await db.fetch_user(uid)          # miss
    if user:
        await redis.setex(key, 300, json.dumps(user))
    return user
```

**Why it's the dominant pattern.** Only requested data is cached (no wasted memory), the cache can fail without breaking correctness (you just get slower), and it works with any data source.

**Compared to the alternatives:**
- **Read-through** — the cache itself loads on miss. Cleaner application code, but requires cache-layer support and couples the cache to the data source.
- **Write-through** — write to cache and database together. Cache is never stale; every write pays cache latency.
- **Write-behind** — write to cache, flush to database asynchronously. Fast writes, real risk of data loss.
- **Refresh-ahead** — proactively refresh before expiry. Avoids miss latency for hot keys; wastes work on cold ones.

**The failure modes of cache-aside specifically:**
1. **Stale data** between a database write and cache invalidation. Bounded by TTL.
2. **The invalidation race:** thread A reads the DB (old value), thread B writes the DB and deletes the cache, thread A writes its stale value to the cache. Now the cache holds old data with a fresh TTL. Mitigate with short TTLs, delayed double-delete, or versioned keys.
3. **Cache stampede** on expiry of a hot key (Q185).
4. **Cache penetration** — repeated requests for a nonexistent key always miss and always hit the database. Cache the negative result with a short TTL.

**Trade-off.** Cache-aside is the most flexible and most manual. You own invalidation, and invalidation is the hard part.

---

## 179. What is Pub/Sub?

**Definition.** Fire-and-forget message broadcasting. Publishers send to channels; every currently-subscribed client receives the message.

```
SUBSCRIBE notifications:user:123
PUBLISH notifications:user:123 '{"type":"run_complete"}'
PSUBSCRIBE notifications:*            -- pattern matching
```

**The defining property — and the one that decides whether you should use it: Pub/Sub has no persistence and no delivery guarantee.** If no subscriber is connected at the instant of publish, the message is gone. Forever. There is no replay, no acknowledgement, no backlog. It is **at-most-once** delivery.

**Where that's fine:**
- Cache invalidation broadcasts (a missed one just means a stale entry until TTL)
- Fanning an SSE/WebSocket message out to whichever API worker holds that client's connection (Q82)
- Live metrics and dashboards
- Config-change notifications where a periodic refresh is the backstop

**Where it's wrong:** job queues, order events, payment notifications, anything where losing a message matters. People reach for Pub/Sub because it's simple, then discover during their first deploy that every in-flight message vanished.

**Additional constraints:** a slow subscriber gets disconnected when its output buffer fills (`client-output-buffer-limit`), and in Redis Cluster, Pub/Sub messages are broadcast to all nodes, which doesn't scale — use `SSUBSCRIBE`/`SPUBLISH` (sharded Pub/Sub, Redis 7+) instead.

**When you need delivery guarantees, use Streams** (Q213). That's the whole reason Streams exist.

---

## 180. What is a Stream?

**Definition.** An append-only log of entries, each with an auto-generated monotonic ID (`<millisecond>-<sequence>`) and a set of field-value pairs. Entries persist until explicitly trimmed, and multiple independent consumers can read the same stream.

```
XADD runs * type start run_id abc tenant_id t1
XLEN runs
XRANGE runs - +                                 -- read all
XREAD COUNT 10 STREAMS runs 0                   -- read from the beginning
```

**What makes it different from a list-based queue:**

| | List (`LPUSH`/`BRPOP`) | Stream |
|---|---|---|
| Message removed on read | Yes — gone | No — persists in the log |
| Multiple consumer groups | No | Yes, independent positions |
| Acknowledgement | None | Explicit `XACK` |
| Crash recovery | Message lost | Pending entry, reclaimable |
| Replay history | Impossible | `XRANGE` any range |
| Delivery guarantee | At-most-once | **At-least-once** |

**Consumer groups** are the key feature (Q205). Each group has its own cursor into the stream; within a group, each entry goes to exactly one consumer; unacknowledged entries stay in a Pending Entries List where another consumer can claim them after a timeout. That is what makes crash recovery possible.

**Trimming is mandatory.** Streams grow forever otherwise:
```
XADD runs MAXLEN ~ 100000 * ...       -- approximate trim, much cheaper
XTRIM runs MINID <timestamp>           -- trim by age
```
The `~` makes trimming approximate (it trims whole macro-nodes), which is dramatically faster than exact trimming. Use it unless you need exactness.

**The honest positioning:** Streams give you most of Kafka's semantics at a fraction of the operational cost, bounded by memory rather than disk. For moderate volumes that's an excellent trade (Q214).

---

# L2 — Caching and coordination

## 181. Redis cache vs PostgreSQL?

They solve different problems; the question is testing whether you know which.

| | Redis | PostgreSQL |
|---|---|---|
| Latency | ~0.1–1 ms | ~1–50 ms |
| Storage | RAM (expensive, limited) | Disk (cheap, large) |
| Durability | Best-effort (AOF/RDB) | ACID guaranteed |
| Query model | Key lookup + structure ops | Full SQL, joins, aggregates |
| Transactions | `MULTI`/Lua, no rollback on logic errors | Full ACID with rollback |
| Data model | Key → structure | Relational, constrained |
| Consistency on failover | Can lose writes | Guaranteed durable |

**The rule:** PostgreSQL is the source of truth; Redis is a derived, disposable view of it. Everything in Redis must be reconstructible from PostgreSQL.

**Use Redis for:** hot reads, session state, rate limiting counters, distributed locks, queues, ephemeral computed results, leaderboards.

**Use PostgreSQL for:** anything you cannot afford to lose, anything requiring joins or aggregation, anything requiring transactional guarantees across records, anything with a compliance retention requirement.

**The nuance worth adding:** PostgreSQL is faster than people assume. A primary-key lookup on a cached page is often 0.2ms. If your database queries are slow, the first move is fixing the query, not adding Redis (Q167). Adding a cache to hide a missing index gives you two problems: a slow query and a cache invalidation bug.

---

## 182. Good cache-key design?

**A good key is namespaced, versioned, deterministic, and carries every input that affects the value.**

```
{app}:{version}:{entity}:{id}:{variant}

app:v2:user:1234:profile
app:v2:search:results:{sha256(normalized_query)}:page:2
app:v2:tenant:t1:orders:status=paid:cursor=abc
```

**The rules:**

1. **Namespace by application and environment.** Sharing a Redis instance between staging and production without namespacing is a real and common outage.

2. **Include a schema version.** When the cached object's shape changes, bump `v2` → `v3`. Every old key becomes unreachable and expires naturally. **This is the cleanest deploy strategy for cache format changes** — no mass deletion, no mixed-format reads, no `KEYS` scan.

3. **Include every input that affects the value.** Especially the **user or tenant** for anything authorisation-dependent. Omitting it is how user A's data gets served to user B — the classic and severe cache-poisoning leak.

4. **Normalise before hashing.** `?b=2&a=1` and `?a=1&b=2` must produce the same key. Sort parameters, lowercase where appropriate, strip defaults.

5. **Hash long or unbounded components.** Keys count against memory; a 2 KB key holding a 200-byte value is absurd. `sha256` the query, keep the prefix readable for debugging.

6. **Keep prefixes greppable** so `SCAN app:v2:user:*` is possible for debugging — but never run `KEYS` in production (Q172).

**Failure.** Keys that don't include the tenant, keys with unbounded cardinality (a key per unique query string with no TTL fills memory), and keys built from unsanitised input containing spaces or newlines.

---

## 183. How invalidate cache?

The genuinely hard problem. Four approaches, increasing in correctness and cost:

**1. TTL only.** Set an expiry, accept staleness up to that window. Simple, self-healing, no coordination. **This is the right default for most data** — decide what staleness the product tolerates and set the TTL to it. Be honest that it's a stale window, not a guarantee.

**2. Explicit deletion on write.**
```python
async def update_user(uid, data):
    await db.update(uid, data)
    await redis.delete(f"user:{uid}")
```
Correct in the common case, but has the race in Q178: a concurrent reader can repopulate with stale data after the delete. Mitigate with a short TTL as a backstop, or a delayed second delete.

**3. Event-driven invalidation.** Publish a change event; all consumers invalidate. Necessary when many services cache the same data, or when a write in one service must invalidate a cache in another. Requires infrastructure and is subject to Pub/Sub's at-most-once delivery — so it needs a TTL backstop anyway.

**4. Versioned keys — the most robust.** Never delete; bump a version.
```python
version = await redis.incr(f"user:{uid}:ver")
key = f"user:{uid}:v{version}:profile"
```
Old keys become unreachable and expire on their own. No delete race, no partial invalidation, no stampede on delete. Costs one extra read for the version (which is itself cacheable with a short TTL).

**The rules to state:**
- **Invalidate, don't update.** Writing the new value into the cache introduces ordering races between concurrent writers. Deleting is idempotent and safe.
- **Invalidate after the database commit**, not before — otherwise a concurrent reader repopulates from the pre-commit state.
- **Every cache key needs a TTL**, even with explicit invalidation. It's the backstop for every bug in your invalidation logic, and there will be bugs.

**The honest closing line:** perfect invalidation across a distributed system is not achievable. The engineering decision is *how much staleness is acceptable for this specific data*, and the answer is different for a user's display name than for their account balance.

---

## 184. What happens when TTL expires?

Covered mechanically at Q177 (lazy + active expiry). The **application-level** consequences are what matter here:

1. **The next read is a miss** and falls through to the database. Fine for one client.
2. **If the key is hot, every concurrent client misses simultaneously** — that's the stampede (Q185). A key served 5,000 times per second expiring means 5,000 concurrent database queries in the same millisecond.
3. **`GET` returns nil**, not an error. Your code must handle nil as a normal path, not an exception.
4. **Any `SET` without `KEEPTTL` resets the expiry**, which silently creates immortal keys (Q177).
5. **Memory isn't freed immediately** — active expiry is sampled and probabilistic, so `used_memory` lags.
6. **On a replica**, the key may still be readable for a moment until the primary propagates the `DEL`.

**The design consequence:** treat expiry as *probabilistic and simultaneous*. Add jitter to TTLs so a batch of keys written together doesn't expire together:
```python
ttl = 300 + random.randint(-30, 30)
```
Without jitter, a cache warmed at deploy time expires in one synchronised wave five minutes later, and you get a database load spike at a predictable interval that nobody can explain.

---

## 185. Cache stampede?

**Definition.** A popular key expires (or is evicted, or the cache restarts), and every concurrent request misses at once, all hitting the database simultaneously with the same query. Also called dog-piling or the thundering herd.

**Why it's dangerous.** The cache was absorbing 5,000 req/s. The instant it expires, all 5,000 go to the database, which is provisioned for 200 req/s. It saturates, queries slow, requests pile up, connection pool exhausts, and the API falls over — **caused by a cache key expiring on a perfectly healthy system.**

The secondary effect is worse: while the database is struggling, nobody manages to repopulate the cache, so the misses continue. The system cannot self-recover, which is the definition of a cascading failure.

**Three variants to distinguish:**
- **Stampede** — one hot key expires, many concurrent misses
- **Avalanche** — many keys expire simultaneously (no TTL jitter), or the whole cache restarts cold
- **Penetration** — requests for a key that *never* exists, so it can never be cached (often malicious)

**Real trigger to name:** a Redis failover or restart empties the cache entirely. Every key misses at once. Any system that cannot survive a cold cache will go down during a routine Redis maintenance window.

Fixes are Q186.

---

## 186. How prevent it?

**1. Per-key lock (mutex) — the standard fix.** Exactly one request recomputes; the rest wait briefly or serve stale.
```python
async def get_with_lock(key, loader, ttl=300):
    val = await redis.get(key)
    if val: return json.loads(val)

    lock = f"lock:{key}"
    if await redis.set(lock, "1", nx=True, ex=10):     # I won
        try:
            data = await loader()
            await redis.setex(key, ttl, json.dumps(data))
            return data
        finally:
            await redis.delete(lock)
    else:                                              # someone else is loading
        await asyncio.sleep(0.05)
        return await get_with_lock(key, loader, ttl)   # bounded retries
```
Reduces N concurrent database queries to exactly 1.

**2. Probabilistic early expiry (XFetch)** — elegant, no locks. Each reader independently decides, with rising probability as expiry approaches, to refresh early:
```python
if now - delta * beta * math.log(random.random()) >= expiry:
    refresh()
```
One request refreshes early while the key is still valid, so nobody ever experiences a miss. Recomputation is spread over time rather than synchronised.

**3. Serve stale while revalidating.** Store the value with a *logical* expiry inside it and a much longer physical TTL. Past the logical expiry, return the stale value immediately and trigger an async refresh. Users never wait; the database sees one query. This is the best user experience of the three.

**4. TTL jitter** (Q184) — prevents avalanche.

**5. Never let the cache be a hard dependency.** If Redis is down, the system must degrade (slower) rather than fail. Combine with a circuit breaker on the database so a stampede sheds load instead of collapsing.

**6. Cache negative results** with a short TTL to stop penetration.

**7. Warm the cache** after a deploy or failover, before taking traffic.

---

## 187. Distributed lock?

**Definition.** A mutual-exclusion primitive shared across processes and machines, so only one holder runs a critical section at a time.

**The correct single-instance implementation:**
```python
token = str(uuid4())
acquired = await redis.set(f"lock:{resource}", token, nx=True, ex=30)

if acquired:
    try:
        await do_work()
    finally:
        # release ONLY if we still hold it — must be atomic
        await redis.eval("""
            if redis.call('GET', KEYS[1]) == ARGV[1] then
                return redis.call('DEL', KEYS[1])
            else return 0 end
        """, 1, f"lock:{resource}", token)
```

**Every element is load-bearing:**
- **`NX`** — set only if absent. This is the atomic acquire.
- **`EX`** — a TTL, so a crashed holder's lock is eventually released. **Without this, one crash deadlocks the resource permanently.**
- **A unique token** — so you release only your own lock.
- **Lua for release** — a `GET` then `DEL` from the client is not atomic; between them, your lock could expire and be acquired by someone else, and your `DEL` would then release *their* lock.

**Redlock** is the multi-node algorithm (acquire on a majority of N independent masters). It's genuinely contested — Martin Kleppmann's critique argues it doesn't provide the safety it claims under clock skew and GC pauses, and Antirez responded. **The interview-safe position:** know both exist, and know that neither gives you a correctness guarantee strong enough to protect data integrity (Q188).

---

## 188. What can go wrong with a Redis lock?

This is the question that separates people who've used locks from people who understand them.

**1. TTL expires while the holder is still working.** Your process pauses for a GC, or the work takes longer than expected. The lock expires. Another process acquires it. **Now two processes are in the critical section simultaneously** — the exact thing the lock existed to prevent, and it fails silently. Mitigate with a watchdog that extends the TTL while working, but you can never fully close the gap.

**2. No TTL → permanent deadlock.** The holder crashes and the lock is never released. The resource is unusable until a human intervenes.

**3. Releasing someone else's lock.** Without the token check, a slow holder whose lock expired will happily delete the new holder's lock on completion.

**4. Failover loses the lock.** Redis replication is asynchronous. Primary accepts `SET NX`, acknowledges, and dies before replicating. The replica is promoted with no record of the lock. Two holders. This is unavoidable with async replication and is the core of the Redlock critique.

**5. Clock skew.** TTL expiry depends on wall-clock time across machines. Skew or NTP adjustment breaks the reasoning.

**6. Network partition.** The holder believes it holds the lock; Redis has expired it; the holder keeps working.

**The conclusion to state clearly, because it's the mature answer:**

> **A Redis lock is an efficiency optimisation, not a correctness guarantee.** It reduces duplicate work. It does not make duplicate work impossible. So never rely on it for data integrity.

**What to do instead for correctness:**
- **Idempotency** — make double execution harmless (Q42). This is the real answer almost every time.
- **Database-level guarantees** — unique constraints, conditional `UPDATE`s, `SELECT FOR UPDATE`. The database is the arbiter and it's authoritative.
- **Fencing tokens** — the lock service issues a monotonically increasing number; the protected resource rejects any write with a token lower than the highest it has seen. This is the only approach that survives the expired-lock scenario, and it requires cooperation from the resource.

**The one-line version:** *"I'd use a Redis lock to avoid doing work twice, and a unique constraint to guarantee it doesn't happen twice."*

---

## 189. How would you implement rate limiting?

**Sliding window with a sorted set** — accurate, and Redis's structures make it natural:
```lua
-- KEYS[1]=key, ARGV[1]=now_ms, ARGV[2]=window_ms, ARGV[3]=limit, ARGV[4]=member
redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, ARGV[1] - ARGV[2])
local count = redis.call('ZCARD', KEYS[1])
if count < tonumber(ARGV[3]) then
  redis.call('ZADD', KEYS[1], ARGV[1], ARGV[4])
  redis.call('PEXPIRE', KEYS[1], ARGV[2])
  return {1, ARGV[3] - count - 1}
end
return {0, 0}
```

**Why Lua.** The check-then-add must be atomic. Doing `ZCARD` then `ZADD` from the client leaves a window where concurrent requests both see `count < limit` and both add — the limit is exceeded. Redis executes a script atomically, closing that window. This is the same read-check-write problem as Q147, in a different system.

**Sliding window counter** — cheaper, nearly as accurate. Two fixed-window counters with a weighted blend of the previous window. O(1) memory instead of O(requests). This is what most production systems actually use.

**Token bucket** — allows controlled bursts, which is often what you want:
```
HSET bucket:user1 tokens 100 last_refill <ts>
-- Lua: refill by elapsed × rate, cap at capacity, decrement if available
```

**The essentials regardless of algorithm:**
1. **Atomic via Lua** (or `INCR`+`EXPIRE` for the simplest fixed window).
2. **Always set a TTL** on the key, or you accumulate a key per user forever.
3. **Return the standard headers** — `X-RateLimit-Limit`, `-Remaining`, `-Reset`, and `Retry-After` on 429. Well-behaved clients self-regulate; without headers they just hammer you.
4. **Layer the limits** — per user, per IP, per endpoint, and globally. Different attacks need different limits.
5. **Fail open or closed, deliberately.** If Redis is down, do you reject everything or allow everything? For a public API, fail open (availability matters more); for an expensive AI endpoint, fail closed (cost matters more). **Decide and document it** — the worst outcome is not having thought about it.

**The AI-specific point** (Q90): limit by **token spend**, not request count. A 200-token request and a 50,000-token request are not equivalent.

---

## 190. Token bucket vs fixed window?

**Fixed window.** Divide time into buckets; count requests per bucket.
```
INCR rl:user1:1735689600     -- key includes the minute
EXPIRE rl:user1:1735689600 120
```
- **Pros:** trivially simple, O(1) memory, one command.
- **The fatal flaw — boundary burst:** with a limit of 100/minute, a client sends 100 requests at 11:59:59 and 100 more at 12:00:01. That's **200 requests in 2 seconds**, all within the limit as configured. Your downstream sees a 2× spike exactly when you thought you were protected.

**Token bucket.** A bucket holds up to `capacity` tokens, refilled at `rate` per second. Each request consumes one; empty means rejected.
- **Pros:** allows *controlled* bursts (the bucket can be full), smooth long-run rate, no boundary problem, and it naturally matches how humans and clients actually behave — idle, then a flurry.
- **Cons:** more state (tokens + last-refill timestamp), needs Lua for atomicity.

**Sliding window log** (sorted set, Q189) — most accurate, most memory. **Sliding window counter** — the practical middle ground, and what most production limiters use.

| | Accuracy | Memory | Bursts | Complexity |
|---|---|---|---|---|
| Fixed window | Poor at boundaries | O(1) | 2× spike | Trivial |
| Sliding counter | Good | O(1) | Smooth | Low |
| Sliding log | Exact | O(n) | Smooth | Medium |
| Token bucket | Good | O(1) | Configurable | Medium |
| Leaky bucket | Good | O(1) | None — fully smoothed | Medium |

**Which to choose:** token bucket when you want to permit legitimate bursts (most user-facing APIs); leaky bucket when the downstream absolutely cannot take bursts (a strict third-party rate limit); sliding window counter as a good general default.

**Note the asymmetry:** token bucket permits bursts, leaky bucket eliminates them. Choosing between them is a statement about what your downstream can absorb, and that's worth saying explicitly.

---

## 191. What if Redis dies?

**The answer that scores is a per-use-case impact analysis, not a single sentence.**

| Redis is used for | Impact | Correct behaviour |
|---|---|---|
| **Cache** | Every read hits the database. Load spikes 5–50×. | Degrade — serve slower. Circuit-break to shed load if the DB saturates. |
| **Rate limiting** | No limits enforced | Decide: fail open (availability) or closed (protection) |
| **Session store** | All users logged out | Consider signed JWTs so sessions survive, or a DB fallback |
| **Distributed locks** | No mutual exclusion | Idempotency must carry it (Q188) |
| **Job queue** | **Jobs lost** if not persisted elsewhere | This is why the queue must be backed by durable state |
| **SSE fanout (Pub/Sub)** | Clients stop receiving updates | Clients reconnect; poll as fallback |

**The critical question for each: is this data reconstructible?** If yes, Redis dying is a performance event. If no, Redis dying is data loss — and that means you designed it wrong (Q192).

**The cache-death cascade is the one to describe.** Redis dies → 100% cache miss → database receives 20× its normal load → queries slow → connection pool exhausts → API times out → clients retry → more load → total outage. **Redis dying takes down the database, which takes down everything.** Guard against it with: a circuit breaker on the database, load shedding, a small in-process LRU as a second-tier cache, and — most importantly — capacity planning that asks "can the database survive a cold cache?" If the answer is no, you have a single point of failure you may not have counted.

**Operational mitigations:** Redis Sentinel or Cluster for automatic failover, replicas, AOF persistence for faster warm recovery, and a `redis_available` health signal so the application knows to change behaviour rather than throwing on every call.

**Code-level:** every Redis call wrapped with a timeout (100–200ms) and a try/except that falls through to the source of truth. **A cache that throws on failure is worse than no cache** — you've added a dependency without adding resilience.

---

## 192. Should Redis be source of truth?

**No — with a narrow and well-defined exception.**

**Why not:**

1. **Durability is best-effort.** Default `appendfsync everysec` means up to one second of acknowledged writes can be lost on a crash. `always` is durable but slow. RDB alone can lose minutes.

2. **Failover loses writes.** Replication is asynchronous. A primary can acknowledge a write, die before replicating, and a replica is promoted without it. Silent loss.

3. **Eviction deletes your data.** With `maxmemory-policy allkeys-lru`, Redis will delete keys under memory pressure — including data you consider permanent. It will not ask.

4. **No transactional integrity across records.** `MULTI` doesn't roll back on logical errors, and there are no foreign keys or constraints.

5. **No ad-hoc query capability.** Answering "which users spent more than X last month" requires a full keyspace scan or a purpose-built secondary index you maintain by hand.

6. **RAM is expensive and bounded.** 500 GB of data is routine on disk and prohibitive in memory.

7. **Weak audit and backup ergonomics** for compliance requirements.

**The exception.** Redis *can* be authoritative for data that is **intrinsically ephemeral and whose loss is acceptable by definition**: rate-limit counters (losing them means one lenient window), online-presence sets, short-lived idempotency locks, live leaderboards for a transient game. Even then, ask whether losing it on a Tuesday afternoon is genuinely fine.

**The design principle to state:** *everything in Redis must be reconstructible from PostgreSQL.* If you can't answer "how would I rebuild this key?", it doesn't belong in Redis alone.

**Common violations worth naming:** storing job state only in Redis (a failover loses in-flight jobs — Q203); storing session data with no fallback (a restart logs out every user); accumulating an event stream in Redis with no archival, then trimming it.

---

# L3 — Queue semantics

## 193. Producer?

**Definition.** The component that creates and publishes messages to a queue or stream.

**Responsibilities that are easy to get wrong:**

1. **Publish durably.** The message must be persisted before the producer considers it sent. With Streams, `XADD` returns an ID once written; with `fsync` policy weaker than `always`, that's still not a hard durability guarantee.

2. **Publish atomically with the state change.** This is the important one. If you write to the database and then publish, a crash between them loses the event (Q41). Use the **transactional outbox**: write the business change and the outbox row in one transaction; a relay publishes afterwards. This converts the impossible problem (atomic across two systems) into a solvable one (at-least-once + idempotent consumers).

3. **Include everything a consumer needs**: a unique message/event ID (for dedup), a type and schema version, a timestamp, a correlation/trace ID (Q87), the tenant ID, and the payload.

4. **Keep payloads small.** Put a reference, not a 10 MB document — write the blob to S3 and send the key. Large messages inflate memory, slow every consumer, and are a common cause of Redis memory pressure.

5. **Handle backpressure.** If the queue is full or Redis is unavailable, the producer must block, buffer durably, or reject — not silently drop.

**Failure.** A producer that publishes before committing. The consumer processes an event for a row that doesn't exist yet, fails, retries, and eventually dead-letters — while the database transaction rolls back and the event describes something that never happened.

---

## 194. Consumer?

**Definition.** The component that reads messages from a queue and processes them.

**The correct processing loop, in order:**
```python
async def consume():
    while not shutdown.is_set():
        entries = await redis.xreadgroup(GROUP, CONSUMER,
                                         {STREAM: ">"}, count=10, block=5000)
        for entry_id, fields in entries:
            try:
                if await already_processed(fields["event_id"]):
                    await redis.xack(STREAM, GROUP, entry_id)   # dedupe
                    continue
                await process(fields)                            # do the work
                await mark_processed(fields["event_id"])         # same txn as work
                await redis.xack(STREAM, GROUP, entry_id)        # ACK LAST
            except RetryableError:
                pass                     # no ACK → stays pending → redelivered
            except PermanentError:
                await dead_letter(entry_id, fields)
                await redis.xack(STREAM, GROUP, entry_id)
```

**The five rules:**

1. **ACK after processing, never before.** ACK-then-process is at-most-once: a crash between them loses the message permanently, silently (Q196).
2. **Be idempotent.** At-least-once delivery means duplicates are guaranteed, not possible (Q200).
3. **Distinguish retryable from permanent errors.** Retrying a malformed payload forever is a poison message (Q199) that blocks progress and burns money.
4. **Bound concurrency.** Unbounded parallel processing exhausts database connections and downstream rate limits.
5. **Shut down gracefully** — stop reading, finish in-flight work, ACK, exit (Q44).

**Failure.** A consumer that catches all exceptions and ACKs anyway. Messages are silently discarded and the queue looks perfectly healthy. Every metric is green while data disappears.

---

## 195. Acknowledgement?

**Definition.** An explicit signal from the consumer to the broker that a message has been fully processed and may be removed from the pending set.

**Why explicit ACK is essential.** Without it, the broker must assume delivery equals success. Any crash between delivery and completion loses the message with no record. ACK moves the completion decision from the broker (which can't know) to the consumer (which can).

**In Redis Streams:**
```
XREADGROUP GROUP g c COUNT 10 STREAMS mystream >   -- delivered → added to PEL
XACK mystream g <entry-id>                          -- removed from PEL
XPENDING mystream g                                 -- what's outstanding
```
Between read and ACK, the entry sits in the **Pending Entries List** with the consumer name and a delivery timestamp. That's what makes recovery possible (Q208).

**The three timing choices:**

| Strategy | Guarantee | Consequence |
|---|---|---|
| ACK before processing | At-most-once | Crash = message lost silently |
| ACK after processing | **At-least-once** | Crash = message redelivered (duplicate) |
| ACK in the same transaction as the work | Effectively-once | Only possible when broker and store are the same system |

**Always choose at-least-once and make consumers idempotent.** Losing messages is unrecoverable; duplicates are handled by a unique constraint. That asymmetry decides the design.

**Failure.** ACKing in a `finally` block. That ACKs on exceptions too, silently discarding every failed message. ACK belongs only on the success path.

---

## 196. At-most-once?

**Definition.** Every message is delivered zero or one times. Never duplicated, sometimes lost.

**Achieved by** ACKing before processing (or not tracking delivery at all, as in Pub/Sub).

**The failure:**
```
receive → ACK → [crash] → process never runs → message gone forever
```
No error, no retry, no record. The queue shows zero pending. Everything looks healthy.

**When it's acceptable:** metrics samples, non-critical telemetry, live dashboard updates, cache invalidation hints (a periodic refresh covers the gap), presence pings. In each case, losing one is genuinely harmless because another arrives shortly.

**When it's catastrophic:** payments, orders, emails, any state transition. "We lost the payment confirmation and nobody knows" is not recoverable by retry, because nothing knows to retry.

**The trap to name:** teams choose at-most-once implicitly, by ACKing early or by using Pub/Sub, without realising they've made a delivery-guarantee decision at all. It's almost never a deliberate choice — which is exactly why it causes incidents.

---

## 197. At-least-once?

**Definition.** Every message is delivered one or more times. Never lost, sometimes duplicated.

**Achieved by** ACKing after processing completes.

**The duplicate path:**
```
receive → process (succeeds) → [crash before ACK] → redelivered → processed again
```

**Why this is the right default.** The two failure modes are not symmetric:
- **Lost message** — unrecoverable. The information is gone; nothing knows to retry.
- **Duplicate message** — recoverable. A unique constraint, an idempotency key, or a conditional `UPDATE` absorbs it completely.

You choose the failure you can engineer around.

**The obligation it creates: every consumer must be idempotent** (Q42, Q200). This is not optional and it is not "nice to have." At-least-once delivery with a non-idempotent consumer means double charges, duplicate emails, and doubled counters — you've traded a rare loss for a frequent corruption.

**Where duplicates come from:** crash before ACK, ACK timeout with the message reclaimed by another consumer, network partition, consumer restart during a deploy, the reclaim mechanism firing on a slow-but-alive consumer.

**The correct architecture, stated as one sentence:** *at-least-once delivery plus idempotent consumers equals effectively-once processing* (Q234).

---

## 198. Dead-letter queue?

**Definition.** A separate destination for messages that have failed processing repeatedly, so they stop blocking the main queue while remaining available for inspection and replay.

**Why it's necessary.** Without one, a message that always fails is retried forever. It consumes worker capacity, fills logs, burns money (especially with LLM calls), and — with strict ordering — blocks every message behind it (Q199).

**Implementation:**
```python
delivery_count = await get_delivery_count(entry_id)
if delivery_count >= MAX_RETRIES:
    await redis.xadd(DLQ_STREAM, {
        "original_id": entry_id,
        "payload": json.dumps(fields),
        "error": str(exc),
        "traceback": traceback.format_exc(),
        "failed_at": now_iso(),
        "delivery_count": delivery_count,
    })
    await redis.xack(STREAM, GROUP, entry_id)     # remove from main queue
    return
```
In Redis Streams, `XPENDING` reports the delivery count, so you get the retry counter for free.

**What a DLQ record must contain:** the full original payload (so it can be replayed), the error and stack trace, the failure timestamp, the attempt count, and the correlation ID. A DLQ entry with only "processing failed" is useless.

**Operational requirements — the part people skip:**
1. **Alert on DLQ depth.** A DLQ nobody watches is a data-loss mechanism with extra steps. This is the single most important part.
2. **A replay mechanism** — after fixing the bug, move messages back to the main queue. Build it before you need it, at 3 a.m.
3. **Retention and its own monitoring.**
4. **Categorise failures** — a spike of one error type means a systemic bug; scattered types mean bad data.

**The framing:** a DLQ doesn't fix anything. It **contains** the failure so the rest of the system keeps working, and preserves the evidence. It's a quarantine, not a solution.

---

## 199. Poison message?

**Definition.** A message that always fails processing, no matter how many times it's retried. Malformed JSON, a reference to a deleted record, an unsupported schema version, or a payload that triggers a code bug.

**Why it's dangerous — three escalating harms:**

1. **Infinite retry loop.** Consumes worker capacity permanently.
2. **Head-of-line blocking.** With ordering guarantees, everything behind it stops. One bad message halts an entire partition.
3. **Cost.** If processing involves an LLM call, each retry is real money spent to fail identically. A poison message retried 10,000 times overnight is a genuine and avoidable bill.

**Detection and handling:**
1. **Track delivery count** — `XPENDING` gives it in Streams; store it explicitly elsewhere.
2. **Cap retries** (3–5), then dead-letter.
3. **Classify errors first.** `ValidationError` on a malformed payload → dead-letter *immediately*, don't retry at all. It will never succeed. Only retry genuinely transient failures — timeouts, 429s, 5xx, connection resets.
4. **Retry with backoff** so transient failures get a real chance to clear.
5. **Alert.** A poison message is a bug report with a payload attached.

```python
except (ValidationError, SchemaError, json.JSONDecodeError):
    await dead_letter(entry, "permanent: malformed")   # zero retries
    await ack(entry)
except (TimeoutError, ConnectionError, RateLimited):
    pass                                                # retry — no ACK
```

**The distinction that matters and is often missed:** *retryable vs permanent is a property of the error, not of the retry count.* Retrying a permanent error even once is wasted work; retrying it five times before dead-lettering is a design that hasn't thought about it.

---

## 200. Duplicate processing?

**Definition.** The same logical message processed more than once — the guaranteed consequence of at-least-once delivery.

**Every source:**
- Crash after processing, before ACK
- ACK lost in the network
- Message reclaimed from a slow-but-alive consumer (Q209)
- Producer retried after an ambiguous publish
- Consumer restarted mid-deploy
- Manual replay from a DLQ

**The defences, in order of strength:**

**1. Natural idempotency.** Design the operation so repetition has no effect. `SET status='processed'` is idempotent; `INCR counter` is not.

**2. A dedupe table with a unique constraint** — the workhorse:
```sql
CREATE TABLE processed_messages (
  message_id TEXT PRIMARY KEY,
  processed_at TIMESTAMPTZ DEFAULT now(),
  result JSONB
);
```
```python
async with conn.transaction():
    try:
        await conn.execute(
            "INSERT INTO processed_messages (message_id) VALUES ($1)", msg_id)
    except UniqueViolationError:
        return await fetch_result(msg_id)          # already done
    result = await do_work()
    await conn.execute("UPDATE processed_messages SET result=$1 WHERE message_id=$2",
                       result, msg_id)
```
**Both the marker and the work must commit in the same transaction.** Marking first in a separate transaction means a crash loses the work while claiming it's done.

**3. Conditional updates / state machines** (Q155). `WHERE status='pending'` makes a repeat a no-op.

**4. Upserts** — `ON CONFLICT DO UPDATE`.

**Why Redis `SETNX` is not sufficient for this:** it can lose the marker on failover (Q192), and the marker isn't atomic with the database write. Use it as a fast pre-filter if you like, but the database constraint is what makes it correct.

**Operationally:** retention on the dedupe table matters — partition by day and drop old partitions, or it becomes your largest table.

---

## 201. Dead worker recovery?

**The problem.** A worker reads a message, begins processing, and dies — OOM kill, node preemption, SIGKILL, network partition. The message is delivered but unacknowledged. Without recovery it sits pending forever and the work never completes.

**In Redis Streams, the mechanism is the Pending Entries List plus reclaim:**
```
XPENDING mystream mygroup - + 10                      -- what's outstanding, and for how long
XAUTOCLAIM mystream mygroup newconsumer 60000 0-0     -- reclaim entries idle > 60s
```
`XAUTOCLAIM` (Redis 6.2+) atomically transfers ownership of entries whose idle time exceeds a threshold. Run it periodically from every consumer, or from a dedicated reaper.

**The generic database version — leases:**
```sql
UPDATE jobs SET status='running', worker_id=$1,
       lease_expires_at = now() + interval '2 minutes'
WHERE id = (SELECT id FROM jobs
            WHERE status='queued'
               OR (status='running' AND lease_expires_at < now())   -- reclaim
            ORDER BY created_at
            FOR UPDATE SKIP LOCKED LIMIT 1)
RETURNING *;
```
The worker **heartbeats** the lease while working:
```sql
UPDATE jobs SET lease_expires_at = now() + interval '2 minutes' WHERE id=$1;
```
A dead worker stops heartbeating, the lease expires, and another worker claims it.

**The essential tuning trade-off to state:** the idle/lease threshold must exceed your longest legitimate processing time. Set it too short and you reclaim work from healthy-but-slow workers, producing duplicate execution. Set it too long and recovery from a real crash is slow. **Heartbeating is what lets you have both** — a short lease with periodic renewal means fast detection *and* no false reclaims. That's the answer that shows you've operated this.

**And the closing point:** reclaim guarantees duplicates when a slow worker is wrongly reclaimed, so idempotency is a prerequisite for this mechanism, not an optional extra.

---

## 202. Stuck-job detection?

**A job is stuck when it's in a non-terminal state longer than it should be.** You need to detect this actively — nothing will tell you.

**The signals, each catching a different failure:**

| Signal | Query | Catches |
|---|---|---|
| Lease expired | `status='running' AND lease_expires_at < now()` | Dead worker |
| No heartbeat | `last_heartbeat_at < now() - 5min` | Hung worker (deadlock, infinite wait) |
| Age in state | `status='queued' AND created_at < now() - 30min` | Nothing is consuming |
| Oldest pending | `XPENDING` idle time | Same, in Streams |
| Queue depth rising | Metric trend | Consumers can't keep up |
| No progress | `updated_at` unchanged despite `status='running'` | Silent hang |

**The reaper:**
```python
async def reap():
    while True:
        stuck = await conn.fetch("""
            UPDATE jobs SET status='queued', attempt=attempt+1, worker_id=NULL
            WHERE status='running' AND lease_expires_at < now()
              AND attempt < $1
            RETURNING id
        """, MAX_ATTEMPTS)
        for j in stuck:
            logger.warning("reclaimed stuck job", extra={"job_id": j["id"]})
        # exhausted attempts → dead letter
        await conn.execute("""
            UPDATE jobs SET status='failed', error='max attempts exceeded'
            WHERE status='running' AND lease_expires_at < now() AND attempt >= $1
        """, MAX_ATTEMPTS)
        await asyncio.sleep(30)
```

**The metric to alert on is `oldest_pending_age`, not queue depth.** Depth is ambiguous — 10,000 fast jobs is fine, 3 jobs stuck for an hour is not. Age directly expresses the SLO: "no job waits more than N minutes." This is also the right autoscaling signal for workers (Q100).

**Also worth building:** an admin view of jobs by state and age. During an incident, "show me everything stuck" is the first question, and grepping logs is a bad answer.

---

## 203. How does job state survive worker death?

**By living in durable storage outside the worker process, and being updated incrementally.**

**The layers:**

**1. The job record itself is a database row**, written before the job is ever enqueued. That's the anchor — the queue message is a pointer, not the data. If the queue loses the message, the row still exists and a reaper finds it (Q202). If the row doesn't exist, the message is meaningless.

**2. Progress is persisted incrementally, not at the end.** This is the design decision that matters most:
```sql
CREATE TABLE run_steps (
  run_id UUID, seq INT, type TEXT, payload JSONB, created_at TIMESTAMPTZ,
  PRIMARY KEY (run_id, seq)
);
```
Each completed step is committed before the next begins. A worker that dies at step 23 is replaced by one that reads steps 1–22 and resumes. **Without this, a 30-minute agent run dying at minute 29 restarts from zero — and costs you the LLM spend twice.**

**3. The lease and heartbeat** make the death detectable (Q201).

**4. Each step is idempotent**, so a step that completed but wasn't recorded before the crash can safely re-run.

**5. External side effects go through the outbox** (Q41), so a crash between "did the work" and "told the world" is recoverable.

**What must never hold state:** worker process memory, local disk in an ephemeral container, an in-process cache, or `asyncio` task state. All of it vanishes on SIGKILL, and SIGKILL is not an exceptional event — it's what happens on every node preemption, OOM, and hard deploy.

**The design principle to state:** *assume the worker can vanish between any two instructions.* Everything that must survive that must already be committed. This is the same principle as Q45, applied to jobs.

**The trade-off:** persisting every step costs a database write per step, which for a 40-turn agent run is 40 writes. That's real overhead and it's cheap insurance — one avoided re-run of an expensive LLM workflow pays for thousands of them.

---

## 204. How do workers scale?

**Horizontally, driven by queue metrics rather than CPU** — covered architecturally at Q100. The Redis/queue-specific mechanics:

**How work is distributed:**
- **Redis Streams consumer groups** — each entry goes to exactly one consumer in the group; add consumers and Redis distributes automatically. No coordination needed.
- **PostgreSQL `SKIP LOCKED`** (Q138) — each worker claims a different row with no blocking.
- **List-based (`BRPOP`)** — Redis serves waiting clients; simple but no ACK, so at-most-once.

**Scaling signal:** `oldest_pending_age`, secondarily queue depth. With KEDA in Kubernetes you can scale directly on Redis Stream pending count.

**The constraints that actually bound worker count — naming these is what shows experience:**
1. **Database connections.** `workers × pool_size ≤ max_connections`. This binds far sooner than people expect.
2. **Upstream rate limits.** 50 workers against a 20/sec API produces 429s, not throughput. The limiter must be shared (Redis), not per-worker (Q82).
3. **LLM provider quotas** — tokens per minute is usually the real ceiling for AI workloads.
4. **Cost.** Each worker calling an LLM burns money continuously.

**Separate pools by workload class.** One queue holding both 200ms jobs and 30-minute jobs means a burst of slow ones starves the fast ones — head-of-line blocking at the fleet level. Separate streams, separate consumer groups, separate deployments, separate scaling policies. Similarly, separate queues per tenant tier so one large customer can't starve everyone.

**Scaling down needs care.** A worker being terminated must stop reading, finish in-flight work, ACK, and exit within the grace period (Q44). Kubernetes will SIGKILL it otherwise — survivable because of leases and idempotency, but it produces duplicate work and wasted spend.

**The point to close on:** more workers is not monotonically better. Past the downstream bottleneck, you're just moving the queue from your system into someone else's, while paying for idle capacity.

---

# Redis Streams (205–215)

## 205. Consumer group?

**Definition.** A named set of consumers that cooperatively read one stream. The group maintains its own cursor (`last-delivered-id`), and each entry is delivered to exactly **one** consumer within that group.

```
XGROUP CREATE mystream workers $ MKSTREAM      -- $ = only new entries; 0 = from start
XREADGROUP GROUP workers worker-1 COUNT 10 BLOCK 5000 STREAMS mystream >
```

**The two independent axes — this is the design insight:**
- **Within a group**, entries are *distributed* — that's load balancing. Add consumers to go faster.
- **Across groups**, entries are *duplicated* — each group sees every entry. That's fan-out to independent subsystems.

So one stream can feed a billing group, an analytics group, and a notifications group, each processing every event at its own pace, while each group internally load-balances across its own workers. That combination is exactly what Pub/Sub cannot do and what Kafka is famous for.

**The `>` vs ID distinction, which trips people up:**
- `>` — deliver *new* entries never delivered to this group
- `0` (or any ID) — re-read *this consumer's own pending* entries, i.e. what it was delivered but never ACKed

On startup, a consumer should first read `0` to recover its own pending work, then switch to `>`.

**Consumer names must be stable and unique.** If every restart generates a new random name, the old consumer's PEL entries are orphaned under a name nobody will ever query, and only `XAUTOCLAIM` will recover them. Use the pod name or a persistent identifier.

**Cleanup:** `XGROUP DELCONSUMER` for consumers that are gone for good, or their PEL entries linger.

---

## 206. Pending entry?

**Definition.** An entry that has been delivered to a consumer in a group but not yet acknowledged. It lives in the group's **Pending Entries List (PEL)**.

```
XPENDING mystream workers                          -- summary: count, min/max ID, per-consumer
XPENDING mystream workers - + 10                   -- detail: ID, consumer, idle ms, delivery count
```
The detailed form returns, per entry: the entry ID, which consumer owns it, **how long since it was delivered or last claimed** (idle time), and **how many times it has been delivered**.

**Why the PEL exists.** It's the record of "delivered but not confirmed done." Without it, a crash between delivery and completion is indistinguishable from success, and the message is lost. The PEL makes the ambiguity visible and recoverable.

**The two fields that matter operationally:**
- **Idle time** → drives reclaim. Entries idle beyond a threshold are presumed abandoned (Q209).
- **Delivery count** → drives dead-lettering. A count of 5 means this entry has failed four times; it's a poison message (Q199).

**The PEL is your queue health dashboard.** Alert on:
- PEL size growing without bound → consumers are failing or too slow
- Max idle time rising → something is stuck
- High delivery counts → poison messages accumulating

**Failure to watch for:** a PEL that grows forever because a consumer processes successfully but never ACKs (a bug), or because consumers are named randomly on each restart so nobody reclaims their orphans. Both look like "the queue is fine, messages are being processed" while pending entries accumulate silently.

---

## 207. Why ACK?

Because **the broker cannot know whether processing succeeded**. Delivery is not completion, and only the consumer knows the difference.

`XACK` removes the entry from the PEL, meaning: this work is done, don't redeliver it.

```
XACK mystream workers 1526569495631-0
```

**Without ACK** (or with `NOACK`), Streams degrade to at-most-once — a crash mid-processing loses the message with no trace.

**The three consequences of ACKing at the wrong time:**

- **ACK before processing** → at-most-once → silent loss on crash.
- **ACK in a `finally` block** → failed messages ACKed and discarded. The queue looks healthy while data is dropped. This is a genuinely common bug because `finally` *feels* like the tidy place to put cleanup.
- **Never ACK** → the PEL grows without bound, memory rises, and reclaim logic keeps redelivering messages that were actually processed — producing endless duplicate work.

**The correct rule:** ACK exactly once, on the success path, after the work is durably committed.

**The subtlety worth raising:** even correct ACKing leaves a window. If you commit the work and crash before `XACK`, the entry is redelivered and processed again. **That window cannot be eliminated** — the database and Redis are separate systems and cannot commit atomically. Which is why the answer to "how do I avoid duplicates?" is never "ACK more carefully," it's "be idempotent" (Q234).

---

## 208. What if worker dies after receiving?

**The entry stays in the PEL, owned by the dead consumer, with a growing idle time.** It is not lost, and it is not redelivered automatically — Streams do not have a visibility timeout that fires on its own.

**This is the crucial difference from SQS-style queues.** SQS makes a message visible again automatically after the visibility timeout. Redis Streams require *you* to run reclaim. If nobody calls `XPENDING`/`XAUTOCLAIM`, the entry sits in the PEL forever, and the work never completes. **Silently.** Every metric looks healthy; the stream isn't backing up; the message just never gets done.

**So a Streams-based system without a reclaim loop has a permanent, invisible data-loss path.** That's the single most important operational fact about Redis Streams and the thing most teams discover the hard way.

**The recovery loop:**
```python
async def reclaim_loop():
    while not shutdown.is_set():
        # atomically claim entries idle longer than MIN_IDLE
        start = "0-0"
        while True:
            start, entries, _ = await redis.xautoclaim(
                STREAM, GROUP, MY_NAME, min_idle_time=60_000, start=start, count=50)
            for entry_id, fields in entries:
                await handle(entry_id, fields)
            if start == "0-0":
                break
        await asyncio.sleep(15)
```

**Also handle the consumer's own restart:** on startup, read with ID `0` rather than `>` to pick up entries this consumer was delivered before it died — provided the consumer name is stable (Q205).

**And guard against poison messages during reclaim:** check the delivery count from `XPENDING`; past the threshold, dead-letter rather than reclaim, or a permanently-failing entry cycles through your fleet forever.

---

## 209. How can another worker reclaim it?

**`XAUTOCLAIM`** (Redis 6.2+) — the modern, correct tool:
```
XAUTOCLAIM mystream workers worker-2 60000 0-0 COUNT 50
```
Atomically scans the PEL from the given start ID, finds entries idle longer than 60,000 ms, transfers ownership to `worker-2`, resets their idle time, increments the delivery count, and returns them plus a cursor for the next call. One command, no race.

**`XCLAIM`** — the older, more granular form. You must first find candidates with `XPENDING`, then claim specific IDs. Two steps means two workers can race to claim the same entry — though `XCLAIM` itself is atomic, so only one wins, and the loser gets an empty result. Useful options:
- `JUSTID` — claim without transferring the payload (cheaper when you'll re-read it anyway)
- `FORCE` — create a PEL entry even if one doesn't exist
- `RETRYCOUNT` — explicitly set the delivery counter

**The critical tuning parameter is `min-idle-time`**, and getting it wrong causes the two opposite failures:

- **Too short** → you reclaim work from a healthy consumer that's simply taking longer than expected. Now **two workers process the same entry concurrently**. The lock you thought you had doesn't exist. This is worse than the problem you were solving.
- **Too long** → recovery from a genuine crash is slow, and jobs sit idle.

**The resolution is the same as Q201:** set `min-idle-time` comfortably above your p99 processing time, and have long-running consumers **periodically touch their entries** (`XCLAIM ... JUSTID` on their own entries resets idle time) as a heartbeat. Then you get fast crash detection without false reclaims.

**Always remember:** reclaim is a duplicate-generating mechanism by design. Idempotency is the prerequisite, not a mitigation.

---

## 210. What does ordering mean?

**Streams guarantee that entries are *stored* in ID order, and that a single consumer reading with `>` receives them in that order.** That's the entirety of the guarantee, and being precise about its limits is the point of this question.

**What is guaranteed:**
- Entry IDs are monotonically increasing (`<ms>-<seq>`), so the log itself has a total order
- `XRANGE` returns entries in ID order
- One consumer reading `>` from one stream sees entries in order

**What is NOT guaranteed:**
- **Order of *completion*** across multiple consumers in a group. Entry 1 goes to consumer A, entry 2 to consumer B; B finishes first. Delivery was ordered; processing was not (Q212).
- **Order across streams.** Two streams have independent ID spaces.
- **Order after reclaim.** A reclaimed entry is reprocessed long after its successors completed.
- **Order relative to the real world.** IDs come from the Redis server clock, so `XADD` order reflects arrival at Redis, not the order events actually occurred at their sources.

**The practical implication:** if you need ordered processing of related events (all events for one order, one user, one run), you must **partition by key and process each partition with a single consumer**. Use one stream per key range, or hash the key to a stream — the same approach Kafka takes with partitions.

**The better approach where possible:** design so ordering doesn't matter. Commutative operations, state machines with guarded transitions (Q154), and version/timestamp checks all tolerate arbitrary order. **Ordering is expensive — it forces serialisation and creates head-of-line blocking.** Needing strict ordering is a real constraint that costs throughput, and it's worth checking whether you truly need it before designing around it.

---

## 211. Can consumers process concurrently?

**Yes, at two levels:**

**1. Across consumers in a group.** Each entry goes to exactly one consumer, so N consumers process N entries in parallel. This is the primary scaling mechanism (Q204).

**2. Within one consumer.** `XREADGROUP COUNT 10` returns a batch; the consumer can process all ten concurrently:
```python
entries = await redis.xreadgroup(GROUP, NAME, {STREAM: ">"}, count=10, block=5000)
async with asyncio.TaskGroup() as tg:
    for entry_id, fields in entries:
        tg.create_task(handle_and_ack(entry_id, fields))
```

**But bound it.** Unbounded concurrency exhausts database connections, blows through upstream rate limits, and consumes memory. Use a semaphore sized to the actual downstream constraint, not to your CPU count (Q30).

**What concurrency costs you:**
- **Ordering** (Q212). Concurrent processing means completion order is arbitrary.
- **Longer PEL residency** if some entries are slow — increasing false-reclaim risk if `min-idle-time` is tight.
- **Harder failure attribution** — which of the ten failed, and what do you ACK?

**Handle partial batch failure explicitly.** ACK the successes individually; leave the failures unACKed so they're redelivered. Do not ACK the batch as a unit — that either loses failures or reprocesses successes.

**The tuning knob:** batch size trades throughput against latency and blast radius. Larger batches amortise the round trip but mean more work lost and redelivered on a crash. 10–100 is the usual range; measure rather than guess.

---

## 212. Can processing become out of order?

**Yes — routinely, and by design.** Delivery order and completion order are different things, and conflating them causes real bugs.

**Every mechanism that reorders processing:**

1. **Multiple consumers.** Entry 1 → consumer A (slow), entry 2 → consumer B (fast). B commits first.
2. **Concurrency within a consumer** (Q211).
3. **Retries.** Entry 1 fails and is retried after 30 seconds; entries 2–50 completed in the meantime.
4. **Reclaim.** A crashed consumer's entry is reprocessed minutes later.
5. **Variable work.** One entry needs three LLM calls, another needs a cache hit.

**So you must design for out-of-order processing.** The mechanisms (all covered elsewhere, and worth linking explicitly in an interview):

- **State machines with guarded transitions** (Q154, Q155). A backwards transition doesn't match its `WHERE` clause and is ignored.
- **Version or timestamp guards** — `WHERE last_event_at < $new_event_time`. Last-write-wins by event time rather than arrival time.
- **Commutative operations.** `INCR`/`DECR` produce the same result in any order; `SET` does not.
- **Fetch current state instead of applying deltas.** Treat the message as a notification: "object X changed" → `GET /objects/X` → apply authoritative state. Order becomes irrelevant because you always converge on truth. Costs an API call; worth it for anything financial.

**If you genuinely need strict ordering:** partition by key and dedicate one consumer per partition. Accept that you've traded throughput for ordering, and that a slow message now blocks its whole partition. **Say this trade-off out loud** — it's the difference between someone who has read about ordering and someone who has paid for it.

---

## 213. Streams vs Pub/Sub?

| | Pub/Sub | Streams |
|---|---|---|
| Persistence | None | Persisted until trimmed |
| Delivery | At-most-once | At-least-once |
| Offline subscriber | **Message lost** | Received on reconnect |
| Acknowledgement | None | Explicit `XACK` |
| Consumer groups | No | Yes |
| Load balancing | No — all subscribers get everything | Yes, within a group |
| Replay | Impossible | `XRANGE` any range |
| Crash recovery | None | PEL + `XAUTOCLAIM` |
| Memory | Negligible | Grows — must trim |
| Latency | Marginally lower | Very low |

**The decision rule:** if losing a message is acceptable, Pub/Sub is simpler and lighter. If it isn't, use Streams. There is no middle ground — Pub/Sub cannot be made reliable by trying harder.

**Where Pub/Sub is genuinely correct:**
- Cache invalidation broadcasts (a missed one costs you staleness until TTL)
- Fanning a message to whichever API worker holds a given SSE/WebSocket connection (Q82) — the client reconnects if it misses one
- Live dashboards and presence

**Where Streams are required:** job queues, domain events, payment notifications, audit trails, anything a user will later ask about.

**The hybrid pattern worth naming, because it's what a real AI platform does:** the worker writes run progress to a **Stream** (durable, replayable, so a reconnecting client can catch up from `Last-Event-ID`) *and* publishes to **Pub/Sub** for instant fan-out to connected SSE clients. Streams provide correctness; Pub/Sub provides the low-latency push. Neither alone gives you both.

---

## 214. Streams vs Kafka?

| | Redis Streams | Kafka |
|---|---|---|
| Storage | Memory (+ AOF/RDB) | Disk, designed for it |
| Retention | Hours–days (memory-bound) | Days–forever (disk-bound) |
| Throughput | ~100k–1M msg/s (single node) | Millions/s, horizontally |
| Partitioning | Manual (one stream per partition) | Native, first-class |
| Ordering | Per stream | Per partition, guaranteed |
| Replication | Async — **can lose acknowledged writes on failover** | Synchronous with ISR + `acks=all` |
| Consumer groups | Yes | Yes, with rebalancing |
| Replay | Yes, while retained | Yes, by design |
| Exactly-once | No | Transactional producer support |
| Ops burden | Low — you probably already run Redis | High — brokers, ZK/KRaft, tuning |
| Ecosystem | Minimal | Connect, Streams, Schema Registry, ksqlDB |

**The two decisive differences:**

1. **Durability model.** Kafka is a disk-based log with synchronous replication and configurable acknowledgement (`acks=all` + `min.insync.replicas`). Redis is memory-first with asynchronous replication — an acknowledged `XADD` can be lost on failover. **For a financial event log, that distinction is disqualifying.**

2. **Retention economics.** Kafka retaining 30 days of events costs disk. Redis retaining 30 days costs RAM, at roughly 50–100× the price. This alone rules Redis out for high-volume, long-retention use cases.

**The honest positioning:** Redis Streams give you perhaps 80% of Kafka's semantics for ~5% of the operational cost, bounded by memory. For most applications that's an excellent trade, and reaching for Kafka prematurely is a real and common mistake — you take on a large operational commitment to solve a problem you don't have.

---

## 215. When choose Kafka?

**Choose Kafka when at least one of these is genuinely true:**

1. **Throughput exceeds a single Redis node**, sustained. Millions of messages per second, or terabytes per day.
2. **Long retention is required.** Weeks or months of replayable history — for reprocessing, for new consumers backfilling from the beginning, or for regulatory retention. Memory cannot economically hold this.
3. **Durability guarantees are non-negotiable.** `acks=all` with `min.insync.replicas=2` means no acknowledged message is lost even if a broker dies. Redis's async replication cannot promise this.
4. **Event sourcing** — the log *is* the source of truth, and state is derived by replay. This requires indefinite retention and strict ordering.
5. **Many independent consumer groups** reading the same data at very different rates — a real-time consumer and a nightly batch job on the same topic.
6. **Strict per-key ordering at scale**, via native partitioning.
7. **The ecosystem matters** — Kafka Connect for database CDC (Debezium), Schema Registry for contract enforcement, stream processing with Flink or Kafka Streams.

**Choose Redis Streams when:**
- You already run Redis and don't want another stateful system to operate
- Volume is moderate (thousands per second, not millions)
- Retention of hours or days suffices
- At-least-once with idempotent consumers is adequate
- The team is small and operational simplicity has real value

**The judgement to demonstrate — and this is what the question is actually testing:** Kafka is a significant operational commitment. Brokers, partition planning, consumer rebalancing, ZooKeeper or KRaft, monitoring, upgrades. Adopting it for 1,000 messages per second is a mistake that costs an engineer's ongoing attention forever.

**The pragmatic path:** start with Redis Streams or PostgreSQL `SKIP LOCKED`. Move to Kafka when you hit a *specific, measured* limit — not when you anticipate one. Migrating later is real work, but far less than operating infrastructure you don't need for two years. **Say this explicitly.** Interviewers are checking whether you choose technology by fashion or by constraint.

---

*End of Document 04. Next: Document 05 — Distributed systems (questions 216–262).*
