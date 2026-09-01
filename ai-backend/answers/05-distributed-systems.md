# Document 05 — Distributed Systems (Questions 216–262)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 216. What is a distributed system?

**Definition.** A system whose components run on separate machines, communicate only by passing messages over a network, and fail independently.

**The definition that actually matters** is Leslie Lamport's: *"A distributed system is one in which the failure of a computer you didn't even know existed can render your own computer unusable."* That captures the essential property — you have dependencies you cannot see, cannot control, and cannot reason about locally.

**What makes it categorically different from a single machine:**
1. **No shared memory or shared clock.** State must be communicated, and communication takes time during which the state can change.
2. **Partial failure.** One component fails while others continue. A single process either runs or crashes; a distributed system exists in a superposition of both.
3. **Unbounded message delay.** You cannot distinguish "slow" from "dead" (Q219).

**You are already in one if you have:** an API and a database on separate hosts, a cache, a queue, a third-party payment provider, multiple replicas of anything, or a mobile client. **Two processes and a network is a distributed system** — the label isn't reserved for planet-scale infrastructure. That framing is worth having ready for question 596.

---

## 217. Why are they hard?

**Because every assumption that holds on one machine stops holding.**

The canonical framing is the **eight fallacies of distributed computing** — the false assumptions engineers make by default:
1. The network is reliable
2. Latency is zero
3. Bandwidth is infinite
4. The network is secure
5. Topology doesn't change
6. There is one administrator
7. Transport cost is zero
8. The network is homogeneous

**The three that cause the most production incidents:**

1. **Partial failure.** A local function call either returns or raises. A remote call has a third outcome: *no answer*. And that state is genuinely ambiguous — the request may not have arrived, may have arrived and failed, or may have succeeded with a lost response. **This ambiguity is the root of most distributed-systems complexity**, and it's why idempotency exists.

2. **No global state.** You cannot atomically observe two machines. By the time you read B, A has changed. Every consistency mechanism is machinery for coping with this.

3. **No reliable clocks.** Wall clocks drift, NTP jumps backwards, and "which event happened first" has no cheap answer. Use monotonic clocks for durations and logical clocks for ordering — never wall-clock comparison across machines for correctness.

**The consequence to state:** you can't eliminate these problems, only choose which failure mode you prefer. That framing — *choosing a failure rather than pretending to prevent one* — is the mark of an L3/L4 answer throughout this section.

---

## 218. What is network failure?

**Definition.** Any way the network fails to deliver a message as intended: packet loss, connection reset, DNS failure, routing change, congestion, or a full partition splitting the cluster.

**The taxonomy that matters practically:**

| Failure | Symptom | Response |
|---|---|---|
| Connection refused | Immediate error | Fail fast; the host is up but nothing is listening |
| Connection timeout | Hangs then errors | Host unreachable or overloaded |
| Read timeout | Connected, no response | **Ambiguous** — may have succeeded |
| Connection reset | Mid-request failure | **Ambiguous** |
| DNS failure | Cannot resolve | Usually configuration; cache TTLs matter |
| Partition | Some nodes unreachable from others | The hardest case (Q223) |
| Gray failure | High latency, not down | Worst — health checks pass, users suffer |

**Gray failure deserves emphasis.** A node that responds in 30 seconds instead of 30 milliseconds passes every liveness check while destroying user experience and consuming caller resources. It's harder to handle than a clean crash, because a crashed node is removed from the pool automatically and a slow one is not. This is what circuit breakers and outlier detection exist for.

**The critical property of every ambiguous failure:** *a timeout does not mean it didn't happen.* The remote side may have completed the work. Retrying without an idempotency key is how customers get charged twice.

---

## 219. Why timeout?

**Because without a timeout, a failed remote call is indistinguishable from a slow one, and your resources are held hostage indefinitely.**

**What happens with no timeout:** the caller blocks forever. A connection, a thread or coroutine, a database connection, and memory are all held. Under load, every worker ends up blocked on the same dead dependency, and your service is down — **caused entirely by someone else's outage**. This is the classic cascading failure, and the timeout is what breaks the chain.

**Timeouts also give you agency.** They convert "unknown" into a decision point: retry, fall back, degrade, or fail. Without one you never reach the decision.

**How to set them:**
1. **Measure, don't guess.** Base it on observed p99 plus headroom. A timeout below p99 causes spurious failures on legitimately slow requests.
2. **Separate connect and read timeouts.** A slow connect means the host is unreachable — fail fast (1–2s). A slow read means it's working but busy — be more patient.
3. **Budget downward.** Your timeout to a dependency must be *shorter* than your caller's timeout to you, with room for retries. Timeouts that grow as you go deeper guarantee the outer caller gives up while inner work continues, burning capacity on results nobody will read.
4. **Set a total deadline**, not just per-attempt — otherwise three retries at 10s each is a 30-second wait.
5. **Propagate the deadline.** If the remaining budget is already exhausted, don't start the work.

**The cost of aggressive timeouts:** spurious failures and retries, which means duplicate side effects. That's acceptable *only* if operations are idempotent. Timeouts and idempotency are a package — adopting one without the other trades an availability problem for a correctness problem.

---

## 220. Why retry?

**Because most distributed failures are transient**, and a retry costs almost nothing compared to surfacing an error to a user.

**What retries genuinely fix:** packet loss, a brief network blip, a node restarting during a rolling deploy, transient overload, a connection pool momentarily exhausted, a leader election in progress, a rate limit that will clear in a second.

**What retries never fix:** malformed input, missing authorisation, a nonexistent resource, a business rule violation, a permanently down service. Retrying a 400 or a 422 is pure waste — the response will be identical every time, and with LLM calls it costs real money to fail repeatedly.

**So classify before retrying:**
```python
RETRYABLE = {408, 425, 429, 500, 502, 503, 504}
# plus: ConnectionError, TimeoutError, connection reset
# never: 400, 401, 403, 404, 409, 422
```

**The requirements that make retries safe rather than harmful:**
1. **Idempotency** — otherwise a retry after an ambiguous timeout duplicates the effect (Q226).
2. **Exponential backoff with jitter** (Q227, Q228).
3. **A bounded attempt count and total deadline.**
4. **A circuit breaker above it** so you stop retrying against a dead service.
5. **Retry at one layer only** — layered retries multiply (Q96).

**The trade-off to name:** retries convert transient failures into latency. A request that succeeds on attempt three took three times as long. For a user-facing path, sometimes failing fast and letting the client retry is the better product decision.

---

## 221. Idempotency?

**Definition.** An operation is idempotent if performing it multiple times produces the same result as performing it once.

Mathematically: `f(f(x)) = f(x)`. `SET balance = 100` is idempotent; `balance = balance + 10` is not.

**Why it is the single most important property in distributed systems.** Every ambiguous failure (Q218) forces a choice: retry and risk duplication, or don't retry and risk loss. **Idempotency dissolves the dilemma** — if the operation is idempotent, you always retry, and duplication is harmless. It converts an unsolvable problem into a non-problem.

**Natural idempotency by HTTP method:** GET, PUT, DELETE, HEAD are idempotent by specification. POST is not — which is why POST endpoints need explicit idempotency keys.

**How to make things idempotent** (full treatment at Q42, Q160):
1. **Design it in.** Absolute assignment over relative increment; upsert over insert.
2. **Idempotency keys** + a unique constraint — the general-purpose mechanism.
3. **Conditional updates / state machines** — `WHERE status='pending'` makes a repeat a no-op.
4. **Natural keys** with `ON CONFLICT DO NOTHING`.
5. **Fencing tokens** for resources that can't dedupe themselves.

**What resists idempotency, and what to do:** sending an email (dedupe *before* sending; an email cannot be unsent), charging a card (use the provider's idempotency key — this is why every payment API has one), calling a non-idempotent third party (wrap it in your own dedupe table).

**The sentence to have ready for question 595 ("you say idempotency — show me exactly where"):** point at a specific unique constraint and the specific `ON CONFLICT` clause, in the same transaction as the business write. A general description will not survive that follow-up.

---

## 222. Eventual consistency?

**Definition.** Given no new updates, all replicas will *eventually* converge on the same value. There is no guarantee about *when*, and reads before convergence may return stale data.

**Contrast with strong consistency:** every read returns the most recent write, always. Strong consistency requires coordination — the read must confirm it isn't stale, which means talking to a quorum, which costs latency and availability.

**Why anyone accepts eventual consistency:** it buys availability during partitions (Q223), lower latency (read the nearest replica), and higher throughput (no coordination per operation).

**Where you already have it, whether you chose it or not:**
- PostgreSQL read replicas (Q170)
- Any cache with a TTL
- CDN edge caches
- DNS propagation
- Search indexes updated asynchronously
- Anything driven by a message queue

**The failure that matters: read-your-writes.** A user updates their profile, the page reloads from a replica, and the old value appears. To the user this is simply a broken product. Fix with session stickiness to the primary after a write, or LSN-based read routing (Q170).

**Stronger models worth naming, because they show precision:**
- **Read-your-writes** — you always see your own writes
- **Monotonic reads** — you never see time go backwards
- **Causal consistency** — causally related operations are seen in order

Most products need read-your-writes and monotonic reads, not full linearizability. Knowing that distinction lets you buy exactly the consistency you need instead of paying for the strongest option.

**The engineering task, stated plainly:** eventual consistency isn't a technical setting, it's a per-query product decision about how much staleness each piece of data tolerates. A stale recommendation list is fine; a stale account balance used for a spending decision is not.

---

## 223. CAP?

**The theorem.** In the presence of a network **P**artition, a distributed system must choose between **C**onsistency (every read sees the latest write) and **A**vailability (every request receives a non-error response).

**The framing that avoids the common mistake.** CAP is not "pick two of three." Partitions are not optional — they *will* happen, and you don't choose whether to have them. So the real statement is: **when a partition occurs, do you return an error (CP) or possibly stale data (AP)?**

- **CP** — refuse to serve rather than serve wrong. Examples: etcd, ZooKeeper, a PostgreSQL primary with synchronous replication. Correct for configuration, leader election, financial ledgers.
- **AP** — serve something rather than nothing. Examples: Cassandra, DynamoDB (tunable), DNS. Correct for shopping carts, feeds, recommendations, presence.

**PACELC is the more useful refinement**, and mentioning it signals depth: *if there's a Partition, choose A or C; Else (normal operation), choose Latency or Consistency.* This matters because the normal-operation trade-off dominates — partitions are rare, but you pay the latency-vs-consistency cost on every single request.

**The nuances that separate a good answer from a memorised one:**
1. **The choice is per-operation, not per-system.** The same database can serve strongly-consistent reads for balances and eventually-consistent reads for a feed.
2. **CAP's "consistency" is linearizability** — much stronger than ACID's "C". They're different words for different things.
3. **CAP says nothing about normal operation**, which is why PACELC exists.
4. **Availability in CAP is absolute** (every node responds), which is stricter than the operational "99.9% uptime" sense.

**Applied to a real design:** a payments system is CP for the ledger (refuse to write during a partition rather than risk divergence) and AP for the transaction history view (serve slightly stale data). Being able to place both in one system is the answer they want.

---

## 224. Queue?

**Definition.** A durable buffer between a producer and a consumer, decoupling them in time, rate, and availability.

**The four things it buys you** — this is the answer, not the data structure:

1. **Temporal decoupling.** The producer doesn't wait for the consumer. A 30-second job doesn't hold an HTTP connection (Q76).
2. **Rate decoupling / load levelling.** A traffic spike lengthens the queue instead of overwhelming the consumer. The queue absorbs burstiness and the consumer drains at a sustainable rate — this is backpressure at the architectural level.
3. **Availability decoupling.** The consumer can be down, deploying, or scaling; work accumulates rather than being lost.
4. **Independent scaling** (Q100).

**What it costs:**
- **Eventual consistency.** The effect happens later, so the client can't be told the outcome synchronously.
- **At-least-once delivery**, hence mandatory idempotency.
- **Out-of-order processing** (Q231).
- **A new failure mode** — an unbounded queue that never drains is an outage that looks like a working system.
- **Operational surface** — DLQs, stuck-job detection, replay tooling.

**When NOT to use one:** when the caller genuinely needs the result to proceed. Wrapping a synchronous need in a queue and then polling for the answer is a slower, more complex synchronous call.

**The decision rule:** if the work can exceed ~10 seconds, or if it must survive the caller disconnecting, or if its rate is bursty relative to the consumer's capacity — queue it.

---

## 225. Event?

**Definition.** An immutable record that something happened. Past tense, factual, with no expectation of a response: `order.created`, `payment.captured`, `user.deactivated`.

**Event vs command** — the distinction interviewers probe:
- **Command** — an instruction. `CreateOrder`. Imperative, addressed to one handler, can be rejected.
- **Event** — a fact. `OrderCreated`. Past tense, broadcast to any number of subscribers, cannot be rejected because it already happened.

Getting this backwards produces coupled systems. If your "event" is really a command (`SendEmail`), the publisher is implicitly directing the consumer, and adding a second consumer breaks the semantics.

**A well-formed event carries:**
```json
{
  "event_id": "uuid",              // for deduplication
  "event_type": "payment.captured",
  "event_version": 2,              // schema evolution
  "occurred_at": "2026-08-22T...", // when it happened, not when published
  "tenant_id": "...",
  "correlation_id": "...",         // trace linkage
  "aggregate_id": "payment_123",
  "data": { ... }
}
```

**Two design decisions worth defending:**

1. **Thin vs fat events.** A thin event carries only IDs, forcing consumers to fetch current state — resilient to ordering problems (Q231) and avoids stale duplication, at the cost of an API call per event. A fat event carries the full payload — fast, but consumers may act on data that's already outdated. **For anything financial, thin plus fetch-authoritative-state is the safer default.**

2. **Events are immutable.** You never edit or delete one. A correction is a new event. This is what makes replay, audit, and event sourcing possible.

---

# L2 — Delivery semantics and patterns

## 226. Why can retries be dangerous?

**Because of the ambiguity in Q218: a timeout does not mean the operation didn't happen.**

```
Client → POST /charge → Server processes → charges card → response lost
Client times out → retries → card charged twice
```
Nothing failed on the server. The work succeeded. Only the acknowledgement was lost — and the client cannot tell the difference.

**The three categories of danger:**

**1. Duplicate side effects.** Double charges, duplicate emails, doubled counters, two orders. These are user-visible, reputation-damaging, and sometimes legally significant.

**2. Amplification.** Retries multiply load exactly when the system is already struggling. A service degrades → clients retry → load triples → full collapse. The retries, not the original fault, cause the outage (Q229).

**3. Cost.** In an AI system this is concrete. A retried LLM call is a real charge. A poison message retried 10,000 times overnight is a bill you'll notice.

**Making retries safe:**
- **Idempotency keys** — the general fix (Q221)
- **Retry only retryable errors** — never a 4xx
- **Exponential backoff with jitter** (Q227, 228)
- **Bounded attempts and a total deadline**
- **Circuit breaker** above the retry logic
- **Retry budget** — cap retries at ~10% of traffic; beyond that, shed load
- **One retry layer only** (Q96)

**The sentence to have ready:** *"Retries without idempotency don't improve reliability — they trade a visible failure for an invisible corruption."*

---

## 227. Why exponential backoff?

**Because a failing system needs time to recover, and constant-interval retries deny it that time.**

Fixed 100ms retries against an overloaded service deliver *more* load than the original traffic — you've built a load generator pointed at a system that's already falling over. It cannot recover while being hammered, so the outage persists indefinitely.

**Exponential backoff** doubles the wait each attempt: 100ms → 200ms → 400ms → 800ms. Load from retries decays geometrically, giving the downstream room to drain its queues and recover.

```python
delay = min(base * (2 ** attempt), cap)
```

**The parameters and why each exists:**
- **`base`** — first delay. Roughly the expected recovery time for a trivial blip (100–500ms).
- **Multiplier 2** — standard. Higher backs off faster but wastes recovery opportunity.
- **`cap`** — prevents absurd waits. Without it, attempt 10 waits 100 seconds.
- **Max attempts / total deadline** — bounds the whole operation.

**The second reason, often missed:** backoff also *probes* for recovery at a sensible rate. Each retry is a test of whether the service is back. Exponential spacing means you check often when recovery is likely (just after failure) and rarely when it isn't.

**It is not sufficient on its own.** Backoff controls *how often one client retries*; it does nothing about *many clients retrying simultaneously*. That needs jitter (Q228).

---

## 228. Why jitter?

**Because exponential backoff alone keeps every client synchronised.**

If 10,000 clients all fail at time T, they all retry at T+100ms, then all at T+300ms, then all at T+700ms. You've converted continuous load into **synchronised spikes** — which is worse, because each spike can re-break a recovering service, resetting the cycle. This is the thundering herd, and backoff without jitter creates it rather than preventing it.

Worse: the failure *itself* synchronises the clients. Before the outage they were randomly distributed; the outage aligns them. Every subsequent retry wave is more synchronised than natural traffic ever was.

**Jitter re-randomises the distribution:**

```python
# Full jitter — the recommended default
delay = random.uniform(0, min(cap, base * 2**attempt))

# Equal jitter — keeps a minimum wait
temp = min(cap, base * 2**attempt)
delay = temp/2 + random.uniform(0, temp/2)

# Decorrelated jitter — good for long backoffs
delay = min(cap, random.uniform(base, prev_delay * 3))
```

**Full jitter is the standard recommendation** — AWS's analysis found it minimises both total work and completion time versus no jitter or partial jitter. It's counter-intuitive (a client might retry almost immediately) but the aggregate behaviour is what matters.

**Jitter belongs everywhere periodic things happen, not just retries:**
- **Cache TTLs** — otherwise keys warmed together expire together (Q184)
- **Cron schedules** — every pod running a job at exactly `:00` is a self-inflicted spike
- **Health check intervals**
- **Reconnection after a disconnect** — a service restart causes every client to reconnect simultaneously
- **Polling intervals**

**The one-line version:** *"Backoff controls one client's rate; jitter decorrelates all clients. You need both, and jitter is the one people forget."*

---

## 229. Retry storm?

**Definition.** A self-sustaining failure where retries generate load that causes further failures, which generate more retries. The retries — not the original fault — become the outage.

**The mechanism, step by step:**
1. A service degrades slightly (a slow query, a GC pause, a deploy).
2. Some requests time out. Clients retry.
3. Effective load is now 2–3× normal, against reduced capacity.
4. More requests fail. More retries.
5. Load multiplies through every layer that retries (Q96).
6. Total collapse.
7. **Recovery is impossible** — the instant the service comes back it's hit by the entire accumulated retry backlog and falls over again.

That last point is what makes it uniquely dangerous. Most outages end when the cause is fixed; a retry storm outlives its cause.

**Prevention, layered:**
1. **Jitter** (Q228) — desynchronise.
2. **Retry budgets** — cap retries at ~10% of total requests. When exceeded, stop retrying entirely. This bounds amplification regardless of how bad things get, and it's more robust than per-request attempt limits because it's a *system-level* constraint.
3. **Circuit breakers** (Q236) — the primary defence. While open, the struggling service receives almost no traffic and can actually recover.
4. **Retry at one layer only.** Audit the whole path; 3×3×3 is 27 requests from one user action.
5. **Load shedding** — a fast 503 costs almost nothing; a slow timeout holds a connection for 30 seconds.
6. **`Retry-After`** on 429/503, honoured by clients.
7. **Deadline propagation** — don't start work whose deadline has already passed.
8. **Queues instead of retries** where the work can be asynchronous.

**Detection:** alert on the *ratio* of retried to original requests, and on the divergence between rising request rate and falling success rate. That divergence is the signature.

---

## 230. Duplicate delivery?

**Definition.** The same logical message or request processed more than once — the guaranteed consequence of at-least-once delivery and ambiguous failures.

**Every source, so you can enumerate them:**
- Client retried after a timeout (the response was lost, not the work)
- Consumer crashed after processing, before acknowledging
- Message reclaimed from a slow-but-alive consumer (Q209)
- Producer republished after an ambiguous publish
- Consumer restarted mid-deploy
- Manual replay from a DLQ or a backfill
- A network partition healing and both sides having acted

**Why you don't try to prevent it.** Preventing duplicates requires exactly-once delivery, which is impossible across a network (Q233). So the design accepts duplicates and neutralises them.

**The defences** (mechanics at Q42, Q200):
1. **Natural idempotency** — design the operation so repetition is a no-op
2. **Dedupe table with a unique constraint** — the general mechanism, and it must commit in the same transaction as the work
3. **Conditional updates / state machines** — `WHERE status='pending'`
4. **Upserts** — `ON CONFLICT DO UPDATE`
5. **Fencing tokens** for external resources

**The one-line framing:** *duplicates are inevitable and cheap to handle; lost messages are avoidable-only-by-accepting-duplicates and impossible to recover. Choose duplicates.*

**What makes this concrete in an interview:** point at the actual unique constraint. "Deduplication happens on `UNIQUE (provider, event_id)` in `webhook_events`, inserted with `ON CONFLICT DO NOTHING` inside the same transaction as the state change." That's an answer; "we handle idempotency" is not.

---

## 231. Out-of-order delivery?

**Definition.** Messages arriving or being processed in a different order than they were produced.

**Why it's normal, not exceptional:**
- Multiple consumers process in parallel at different speeds (Q212)
- A failed message retries after its successors have completed
- A reclaimed message is reprocessed minutes later
- Different network paths, different latencies
- Multiple producers with unsynchronised clocks
- Partitioned queues have no cross-partition ordering

**The failures it causes:** applying `order.cancelled` before `order.created` (the row doesn't exist); applying `payment.authorized` after `payment.captured` (state goes backwards); a stale update overwriting a newer one.

**The four defences, best first:**

**1. State machines with guarded transitions** (Q154, Q155):
```sql
UPDATE payments SET status='captured'
WHERE id=$1 AND status IN ('authorized','pending');
```
A backwards transition matches nothing and is silently ignored. This is the primary mechanism and it costs nothing.

**2. Version or timestamp guards:**
```sql
UPDATE t SET data=$1, last_event_at=$2
WHERE id=$3 AND last_event_at < $2;
```
Last-write-wins by *event* time rather than arrival time.

**3. Commutative operations.** `INCR`/`DECR` produce the same result in any order; `SET` does not. Where you can express the operation as a delta rather than an assignment, ordering stops mattering.

**4. Thin events + fetch authoritative state.** Treat the message as "object X changed", then `GET /objects/X`. You always converge on truth regardless of order. Costs an API call per event; correct for anything financial.

**If you truly need ordering:** partition by key and process each partition with a single consumer. Accept the cost — head-of-line blocking within a partition, and throughput bounded by the slowest message. **Say that trade-off out loud.**

---

## 232. Exactly-once?

**Definition.** Every message is processed exactly one time — never lost, never duplicated.

**The honest answer: exactly-once *delivery* is impossible over an unreliable network.** Exactly-once *processing* is achievable, and the distinction is the entire point of the question.

**Why delivery can't be exactly-once** — the Two Generals Problem (Q233). The sender cannot know whether its message arrived. If it retries, it may duplicate. If it doesn't, it may lose. There is no protocol that resolves this, and no amount of engineering changes it.

**What is achievable — effectively-once processing:**
```
at-least-once delivery + idempotent processing = effectively-once effect
```
The message may be *delivered* five times, but the *effect* occurs once, because the second through fifth attempts are absorbed by a unique constraint or a conditional update.

**Where genuine exactly-once semantics exist, and why:**
- **Kafka transactions** — offset commits and output writes are in the same transactional scope, so consume-process-produce within Kafka is atomic. Note the boundary: it's exactly-once *within Kafka*, not to your database.
- **Broker and store in the same system** — PostgreSQL `SKIP LOCKED` with the work in the same transaction as the claim. Because it's one system with one transaction, there's no cross-system gap.

That second case is worth naming: **exactly-once is possible when there is only one system.** The moment you have two, you're back to at-least-once plus idempotency.

**The answer for question 602 ("you say exactly-once — prove it"):** don't claim exactly-once delivery. Say: *"At-least-once delivery, with idempotent consumers keyed on a unique constraint, giving effectively-once processing. Here's the constraint, and here's the transaction it commits in."* That is provable; the other claim is not.

---

## 233. Why is exactly-once hard?

**The Two Generals Problem.** Two generals must attack simultaneously and communicate only by messenger through hostile territory. General A sends "attack at dawn." Did it arrive? A needs an acknowledgement. But did the acknowledgement arrive? B needs an acknowledgement of the acknowledgement. **There is no finite exchange of messages that gives both sides certainty.** It's proven impossible, not merely difficult.

**Applied to your system:** the sender never knows whether the receiver got the message. So it either retries (risking duplicates) or doesn't (risking loss). Every messaging system in existence picks one.

**The related result worth knowing: the FLP impossibility theorem** — in an asynchronous system with even one faulty process, no deterministic consensus algorithm can guarantee termination. This is why real consensus protocols (Raft, Paxos) use timeouts and randomisation: they trade guaranteed termination for practical termination.

**The concrete gaps in any implementation:**
1. **The ACK gap.** Process → crash → ACK never sent → redelivered. Cannot be closed; the ACK and the work are separate operations.
2. **The dual-write gap.** Write to the database, then publish to the queue. No transaction spans both (Q41).
3. **The side-effect gap.** An external API call succeeded; your recording of it didn't.

**Why the outbox pattern is the standard answer:** it doesn't achieve exactly-once. It *relocates* the problem into a single system where one transaction covers both writes, then accepts at-least-once on the publish side and requires idempotent consumers. That's engineering — moving the unsolvable part to where it's cheapest to absorb.

**The framing that lands in an interview:** *"Exactly-once delivery is impossible, and any system claiming it is either lying or redefining the term. What's achievable is at-least-once delivery with idempotent effects, and that's what I build."*

---

## 234. Effectively-once?

**Definition.** The observable *effect* occurs exactly once, even though delivery may occur many times. The practical, achievable substitute for exactly-once.

**The formula:**
```
at-least-once delivery + idempotent processing = effectively-once
```

**How it works concretely:**
```python
async def handle(message):
    async with conn.transaction():
        try:
            await conn.execute(
                "INSERT INTO processed (message_id) VALUES ($1)", message.id)
        except UniqueViolationError:
            return await fetch_result(message.id)      # 2nd..Nth delivery: no-op
        result = await do_work(message)                 # 1st delivery: real work
        await conn.execute(
            "UPDATE processed SET result=$1 WHERE message_id=$2", result, message.id)
        return result
```
Delivered ten times, the work runs once. The other nine hit the unique constraint and return the stored result.

**The two properties that make it correct — and both are load-bearing:**
1. **The dedupe marker and the work commit in the same transaction.** Marking first in a separate transaction means a crash loses the work while claiming it's done. This is the single most common way people get this wrong.
2. **The uniqueness is enforced by the database**, not by application logic. A Python `if id in seen_set:` check is not atomic across processes and loses its state on restart.

**Where it doesn't fully hold, and you should say so:**
- **Non-idempotent side effects.** An email sent before the transaction commits is sent. Dedupe *before* the external call, and accept that a crash in the gap is a real (small) duplicate risk.
- **Cross-system effects** need the outbox plus idempotent downstream consumers.
- **The dedupe table needs retention** — partition by day and drop, or it becomes your largest table.

**The interview-safe phrasing:** *"I don't claim exactly-once. I claim at-least-once delivery with effectively-once processing, enforced by a unique constraint in the same transaction as the write."*

---

## 235. Distributed lock?

Mechanics are at Q187–188. The distributed-systems framing:

**Definition.** A mechanism for mutual exclusion across processes and machines, where no shared memory exists.

**Why it's fundamentally harder than a local mutex.** A local mutex is held by a thread the OS can see; if the thread dies, the OS knows. A distributed lock is held by a process the lock service cannot observe. So the lock service must *guess* liveness via a TTL — and a guess can be wrong.

**The two ways the guess fails:**
- **TTL too short** → a healthy-but-slow holder loses its lock while still working. Two holders. The mutual exclusion silently doesn't exist.
- **TTL too long / absent** → a crashed holder deadlocks the resource.

**And no TTL setting eliminates both**, because a process can pause arbitrarily (GC, CPU starvation, VM migration, container throttling) between checking that it holds the lock and acting on that belief.

**Therefore the conclusion that matters:**

> **A distributed lock is an efficiency optimisation, not a correctness guarantee.**

Use it to avoid doing expensive work twice. Never use it to guarantee work doesn't happen twice.

**For correctness, use instead:**
1. **Idempotency** — make double execution harmless. This is the answer almost always.
2. **Database-level guarantees** — unique constraints, `SELECT FOR UPDATE`, conditional `UPDATE`. The database is a single authoritative arbiter, which is exactly what a distributed lock is trying and failing to be.
3. **Fencing tokens** — a monotonically increasing number issued with the lock; the protected resource rejects writes carrying a stale token. This is the only technique that survives the expired-lock scenario, and it requires the resource to participate.
4. **Consensus systems** (etcd, ZooKeeper) with session-based ephemeral locks — stronger guarantees, real operational cost.

**Better still: design the lock away.** Partition work by key so only one worker ever handles a given key (`SKIP LOCKED`, consumer group partitioning). No contention means no lock needed. That's usually the right architecture.

---

## 236. Circuit breaker?

**Definition.** A wrapper around a remote call that tracks failures and, past a threshold, stops making calls entirely for a cooldown period — failing fast instead of waiting.

**Three states:**
- **Closed** — normal. Calls pass through; failures are counted.
- **Open** — the threshold was exceeded. Calls fail *immediately* without touching the network. After a cooldown, transition to half-open.
- **Half-open** — allow a limited number of trial calls. Success → closed. Failure → open again, with the cooldown often extended.

```python
class CircuitBreaker:
    def __init__(self, threshold=5, cooldown=30):
        self.failures = 0
        self.state = "closed"
        self.opened_at = None

    async def call(self, fn, *args):
        if self.state == "open":
            if time.monotonic() - self.opened_at > self.cooldown:
                self.state = "half_open"
            else:
                raise CircuitOpen()               # fail fast, no network call
        try:
            result = await fn(*args)
            self.failures = 0
            self.state = "closed"
            return result
        except Exception:
            self.failures += 1
            if self.failures >= self.threshold:
                self.state = "open"
                self.opened_at = time.monotonic()
            raise
```

**Why it matters more than retries.** Retries make a struggling dependency worse. A circuit breaker is the only mechanism that makes it *better* — while open, the dependency receives almost no traffic, which is precisely what it needs to recover. **It is what makes recovery possible** in a cascading failure.

**Secondary benefit:** it protects *you*. Without it, every worker sits in a 30-second timeout against a dead service, and your service goes down because of someone else's outage.

**Design details worth mentioning:**
- **Per-dependency**, never global. One breaker per downstream, ideally per endpoint.
- **Count only relevant failures.** Timeouts and 5xx open the breaker; a 404 does not — that's a working service giving a correct answer.
- **Use a rate, not a raw count**, at high volume — 50% failure over a rolling window is more meaningful than "5 failures."
- **Half-open must limit concurrency** to one or a few probes, or reopening floods the recovering service.
- **Pair it with a fallback** (Q88): cached data, a degraded response, or a secondary provider. A breaker without a fallback just fails faster.
- **Emit state transitions as events** — a breaker opening is a high-value alert.

---

## 237. Backpressure?

Covered at Q34; the distributed framing:

**Definition.** A signal propagated *upstream* telling producers to slow down because a downstream component cannot keep up.

**Why it's essential in distributed systems.** Without it, a slow consumer causes work to accumulate somewhere — a queue, a buffer, a connection pool — until memory is exhausted and the process dies. **An unbounded queue converts a throughput problem into an outage**, and it does so silently: everything looks fine until it doesn't.

**Where it lives at each layer:**
- **TCP** — the receive window is backpressure built into the protocol
- **HTTP** — 429 with `Retry-After`; load shedding
- **Queues** — bounded size, consumer prefetch limits, consumer lag as the signal
- **Databases** — a bounded connection pool where waiters block
- **In-process** — `asyncio.Queue(maxsize=N)`

**The three responses when you're at capacity, and you must choose one explicitly:**
1. **Block** the producer (backpressure proper)
2. **Drop** — shed load, reject with 429/503
3. **Buffer durably** — write to disk/queue and process later

Silence is not an option. A system with no explicit choice is choosing "buffer in memory until we crash."

**The subtlety that trips people:** backpressure often just *moves* the problem. Bounding your internal queue makes the producer block — but if the producer is an HTTP handler, requests now hang instead of the queue growing. You've relocated the failure, not removed it. **The correct answer is usually to shed load at the edge**, where rejection is cheap and visible, rather than blocking deep in the stack.

**In an AI system specifically:** an LLM provider's rate limit is backpressure. Honour it with a shared token bucket and queue depth, don't fight it with more workers (Q204).

---

## 238. Outbox pattern?

**The problem it solves: the dual-write problem.** You must update your database *and* publish an event. These are two systems. No transaction spans both. A crash between them leaves them inconsistent, permanently and silently (Q41).

**The pattern:**

**1. Write both changes in one local transaction:**
```sql
BEGIN;
  UPDATE orders SET status='paid' WHERE id=$1;
  INSERT INTO outbox (id, aggregate_id, topic, payload, created_at)
    VALUES (gen_random_uuid(), $1, 'order.paid', $2, now());
COMMIT;
```
Atomic. Both or neither. The problem is now inside one system, where transactions work.

**2. A relay publishes the outbox rows:**
- **Polling** — `SELECT ... WHERE published_at IS NULL ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 100`, publish, mark published. Simple, adds latency, adds database load.
- **CDC (Debezium)** — read the WAL directly. Lower latency, no polling load, more infrastructure.

**3. Consumers must be idempotent**, because the relay can crash after publishing but before marking — giving at-least-once (Q234).

**What the pattern actually achieves — state this precisely:** it does *not* give exactly-once. It converts an **unsolvable** cross-system atomicity problem into a **solvable** at-least-once-plus-idempotency problem. That relocation is the whole idea.

**Operational details that matter:**
- **Order by outbox ID** to preserve per-aggregate ordering where you need it.
- **Prune published rows** aggressively — this table has high churn and will bloat (Q139). Partition or delete on a schedule.
- **The outbox insert adds write load** to every business transaction. Real, usually acceptable.
- **Monitor unpublished age.** A stalled relay is invisible otherwise — the application keeps working perfectly while no events reach anyone.

**The inverse pattern is the inbox** — record received message IDs before processing, giving consumer-side dedup with the same transactional property.

---

## 239. When use a queue?

**Use one when any of these is true:**

1. **The work can take longer than a request should** (>10s). Holding HTTP open breaks at every layer (Q76).
2. **The work must survive the caller disconnecting** — mobile network changes, browser closed, deploy mid-request.
3. **Load is bursty relative to consumer capacity.** The queue absorbs the spike.
4. **The consumer has different scaling characteristics** — GPU-bound, rate-limited upstream, expensive (Q100).
5. **Multiple independent consumers** need the same event (fan-out).
6. **Reliability matters more than latency** — retries, DLQ, and durable state are worth the delay.
7. **You want deploy independence** between the producer and the consumer.

**Do NOT use one when:**
- **The caller needs the result to proceed.** Enqueue-then-poll is a slower, more complex synchronous call.
- **The operation is fast and reliable** — sub-100ms with a stable dependency. You're adding a failure domain for nothing.
- **Strict global ordering is required** and you can't partition. Queues fight you here.
- **The team can't operate it.** A queue means DLQs, stuck-job detection, replay tooling, and monitoring. Without those it's a data-loss mechanism.

**The trade-offs to name honestly:** you gain resilience and decoupling; you pay in eventual consistency (the client can't be told the outcome synchronously), mandatory idempotency, out-of-order processing, and a substantial new operational surface.

**The middle ground worth mentioning:** PostgreSQL `SKIP LOCKED` gives you a durable queue with transactional guarantees and zero new infrastructure. For thousands-per-hour workloads it's often the right answer, and it lets the job claim and the work commit in one transaction — which no separate broker can offer.

---

## 240. What guarantees does your queue actually provide?

**This is a trap question, and the trap is answering confidently.** The right response is to enumerate the specific guarantees rather than say "it's reliable."

**The dimensions to address, each explicitly:**

| Dimension | Question to answer |
|---|---|
| **Delivery** | At-most-once, at-least-once, or effectively-once? |
| **Durability** | Is a message persisted before the producer's `send` returns? Synchronously to disk, or buffered? |
| **Ordering** | Global, per-partition/key, or none? |
| **Acknowledgement** | Explicit ACK? Before or after processing? |
| **Failure recovery** | How is a dead consumer's in-flight message recovered? Automatically, or does it need a reclaim loop? |
| **Retry** | Bounded? Backoff? DLQ? |
| **Replication** | Sync or async? Can an acknowledged write be lost on failover? |
| **Retention** | How long? What happens when it's exceeded? |

**Concrete answers for the systems in your stack:**

- **Redis Streams** — at-least-once *if* you ACK after processing; ordered per stream; durable only to AOF policy; **async replication, so an acknowledged `XADD` can be lost on failover**; recovery requires *you* to run `XAUTOCLAIM` — nothing happens automatically (Q208).
- **Redis Pub/Sub** — at-most-once, no persistence, no recovery. Messages published while a subscriber is disconnected are gone.
- **PostgreSQL `SKIP LOCKED`** — at-least-once, fully durable, transactional with the work itself; recovery via lease expiry that you implement.
- **SQS standard** — at-least-once, durable, unordered, automatic visibility-timeout redelivery.
- **Kafka** — at-least-once by default; exactly-once *within Kafka* with transactions; ordered per partition; durable with `acks=all` + `min.insync.replicas`.

**The two answers that score highest:**
1. **"Redis Streams can lose acknowledged writes on failover, so for anything financial the durable record is a PostgreSQL row and the stream is just the notification."** That shows you know the limit of your own tooling.
2. **"And regardless of the broker's guarantees, my consumers are idempotent — because I'd rather not depend on the broker being right."**

---

# L3 — Failure scenarios

## 241. Worker writes DB then crashes. Message arrives again. What happens?

**Without idempotency:** the work is done twice. Credits deducted twice, an email sent twice, a counter doubled. The database has no idea anything is wrong — both writes were individually valid.

**With idempotency:** the second delivery is absorbed. Walk through it precisely:

```python
async def handle(msg):
    async with conn.transaction():
        try:
            await conn.execute(
                "INSERT INTO processed_messages (message_id) VALUES ($1)", msg.id)
        except UniqueViolationError:
            return await fetch_stored_result(msg.id)     # ← second delivery lands here
        result = await do_work(msg)
        await conn.execute(
            "UPDATE processed_messages SET result=$1 WHERE message_id=$2", result, msg.id)
    await ack(msg)
    return result
```

1. First delivery: insert succeeds, work runs, result stored, transaction commits.
2. Crash before ACK.
3. Reclaim/redelivery.
4. Second delivery: the insert violates the primary key. We catch it, fetch the stored result, ACK, and return. **No work is repeated.**

**The essential detail — and the one that fails in most naive implementations:** the marker and the work are in **one transaction**. If you insert the marker in transaction A and do the work in transaction B, a crash between them means the message is marked processed but the work never happened. The message is now permanently lost, and it looks like a success.

**Three cases to distinguish, because an interviewer will ask:**
- **Crash *before* the transaction commits** → everything rolls back, including the marker → redelivery does the work → correct.
- **Crash *after* commit, before ACK** → marker exists → redelivery is a no-op → correct.
- **Crash *during* commit** → PostgreSQL resolves it atomically; you land in one of the above.

There is no fourth case, and that's the point: atomicity collapses the ambiguity into two outcomes, both of which you handle.

---

## 242. Webhook arrives twice?

Full treatment at Q153. The distributed-systems summary:

**Assume it will happen.** Every provider documents at-least-once delivery. Duplicates come from their retry after a lost ACK, from a replay after an incident, or from their own internal redelivery.

**The mechanism:**
```sql
CREATE TABLE webhook_events (
  provider TEXT, event_id TEXT, payload JSONB,
  received_at TIMESTAMPTZ DEFAULT now(), processed_at TIMESTAMPTZ,
  PRIMARY KEY (provider, event_id)
);
```
```python
async with conn.transaction():
    inserted = await conn.execute(
        "INSERT INTO webhook_events (provider,event_id,payload) VALUES ($1,$2,$3) "
        "ON CONFLICT DO NOTHING", provider, event.id, raw)
    if inserted == "INSERT 0 0":
        return Response(200)                  # already handled — ACK, do nothing
    await apply_effect(event)                 # same transaction
```

**The three properties:**
1. **Insert and effect in one transaction** — otherwise you mark it seen and lose the effect on crash.
2. **`ON CONFLICT DO NOTHING` is atomic** — two simultaneous deliveries, exactly one proceeds.
3. **Always return 200 for a duplicate** — an error makes the provider retry harder and eventually disable your endpoint.

**And the belt-and-braces layer:** even with dedup, the *effect* should be idempotent (a guarded state transition, Q243). Then a bug in your dedup logic doesn't corrupt state — you have two independent defences.

---

## 243. Webhook arrives out of order?

Full treatment at Q154. The core mechanism:

**State machine with guarded transitions:**
```sql
UPDATE payments SET status='captured', captured_at=now()
WHERE id=$1 AND status IN ('authorized','pending');
```
An event that would move the state backwards matches nothing and updates zero rows. Ignore it and return 200 — it's stale, not an error.

**Timestamp guard for last-write-wins by event time:**
```sql
UPDATE payments SET status=$2, last_event_at=$3
WHERE id=$1 AND last_event_at < $3;
```
Arrival order becomes irrelevant; event order governs.

**The most robust approach — treat webhooks as notifications, not data.** The webhook says "payment X changed." You call `GET /payments/X` and apply the provider's authoritative current state. Order stops mattering entirely because you always converge on truth. Costs one API call per event; for anything financial, worth it unconditionally.

**When B arrives and A genuinely hasn't:** you have a gap, not just an ordering problem. Either park B in a pending table and apply it when A arrives, or — better — fetch current state and skip the gap entirely. Add a reconciliation sweep (Q156) so a permanently missing A is eventually detected.

---

## 244. DB succeeds but response is lost?

**The canonical ambiguous failure.** Full treatment at Q151.

**Server state:** committed, durable, done. **Client state:** unknown. The client saw a timeout or a connection reset and cannot distinguish "never arrived" from "succeeded, response lost."

**Why this cannot be fixed by trying harder.** It's the Two Generals Problem (Q233). No acknowledgement protocol resolves it.

**The resolution — make the ambiguity safe:**

1. **Idempotency keys.** The client retries with the same key; the server recognises it and returns the *stored original response*. Retry and original become indistinguishable to the client.

2. **The key record commits in the same transaction as the work** — otherwise you reintroduce the gap you're closing.

3. **Store and replay the response**, not just a "yes, done" flag. The client needs the payment ID, not merely confirmation that *a* payment happened.

4. **A status endpoint as a fallback.** `GET /payments?idempotency_key=X` lets a client that lost its key context resolve the ambiguity by asking.

**Client-side obligations, which are half the solution:**
- Generate the key at the moment of user intent, not per HTTP attempt
- Persist it locally so it survives an app restart
- Reuse it for every retry of that logical operation
- Bound retries and surface a clear terminal state

**The framing:** *"You can't eliminate the ambiguity. You make it resolvable — the client asks the same question twice and gets the same answer."*

---

## 245. Redis succeeds but DB fails?

**Now Redis holds state that the database doesn't.** The severity depends entirely on what Redis is holding.

**Case by case:**

| Redis holds | Impact | Fix |
|---|---|---|
| **Cache entry** | Cache is ahead of the DB — serves data that was never committed | Invalidate *after* DB commit, never before. TTL bounds the damage. |
| **Rate-limit counter** | User consumed a token for work that didn't happen | Usually acceptable — slight over-limiting |
| **Idempotency marker** | **Severe** — the operation is marked done but wasn't. Retry is rejected; work permanently lost | Never keep the authoritative marker in Redis. Use a DB unique constraint (Q200). |
| **Queue message enqueued** | A worker will pick up a job whose row doesn't exist | Enqueue via the outbox, after commit |
| **Lock acquired** | Held for work that didn't happen; TTL releases it | Acceptable |

**The general rule that resolves all of these: order the writes so the durable system commits first, and make the non-durable system's state disposable.**

```python
# Wrong
await redis.setex(key, 300, value)
await db.commit()                    # ← fails; Redis now holds phantom state

# Right
await db.commit()                    # source of truth first
await redis.delete(key)              # invalidate; a failure here is bounded by TTL
```

**And critically: invalidate rather than populate.** Writing the new value into the cache after a DB write introduces ordering races between concurrent writers. Deleting is idempotent and safe.

**The deeper answer:** this is the dual-write problem again (Q238). If the two writes must be atomic, the answer is the outbox — commit to the database, and let a relay update the derived system. If they don't need to be atomic, ensure the Redis side is reconstructible and TTL-bounded, so any inconsistency self-heals.

---

## 246. DB succeeds but event publish fails?

**This is Q41 exactly, and it's the most important scenario in this section.**

**What happens:** the database has the new state; nothing else in the system knows. No confirmation email, no downstream notification, no search index update, no analytics event. **And no error is logged**, because nothing failed — the publish simply never happened.

**Silent, permanent inconsistency.** These are the incidents discovered weeks later by a customer.

**Why the naive design cannot be fixed:**
```python
await db.commit()          # succeeded
# ← crash / OOM / SIGKILL / network partition here
await broker.publish(evt)  # never runs
```
Two systems, no shared transaction. Not solvable in this shape.

**The fix — transactional outbox** (Q238):
```sql
BEGIN;
  UPDATE orders SET status='paid' WHERE id=$1;
  INSERT INTO outbox (topic, payload) VALUES ('order.paid', $2);
COMMIT;
```
A relay publishes and marks the row. It can crash after publishing but before marking → at-least-once → consumers must be idempotent.

**Why the alternatives are worse:**
- **Publish first, then commit** — you can now emit an event for an order that never existed. Strictly worse: a phantom event is harder to detect than a missing one.
- **`asyncio.shield(publish)`** — protects against cancellation, not SIGKILL, OOM, or node loss. Narrows the window; doesn't close it.
- **Retry in `finally`** — the process may not survive to run it.
- **Two-phase commit** — technically closes it, at a cost in availability and operational complexity that is almost never worth paying.

**The framing that scores:** *"You cannot make this atomic across two systems. You choose which failure you prefer. The outbox chooses at-least-once delivery with idempotent consumers, because duplicate processing is recoverable and lost events are not."*

---

## 247. How do you make the workflow reliable?

**Reliability is not one mechanism — it's a stack, and being able to name the layers in order is the answer.**

**1. Durable state before anything else.** The job/run row is written to PostgreSQL *before* it's enqueued. The queue message is a pointer, not the data. If the queue loses it, a reaper finds the orphaned row.

**2. Atomic state + event via the outbox** (Q238). No dual writes.

**3. Idempotency at every step** (Q234). Each step can run twice harmlessly.

**4. Incremental persistence.** Each completed step commits before the next begins:
```sql
CREATE TABLE run_steps (run_id UUID, seq INT, payload JSONB, PRIMARY KEY (run_id, seq));
```
A worker dying at step 23 is replaced by one resuming from step 23 — not step 1. For a 30-minute LLM workflow, this is the difference between a retry and paying twice.

**5. Leases and heartbeats** for dead-worker detection (Q201).

**6. Bounded retries with backoff and jitter**, classified by error type, with a DLQ (Q198).

**7. Timeouts everywhere**, budgeted downward (Q219).

**8. Circuit breakers** on external dependencies (Q236).

**9. Reconciliation** — a sweep that finds work stuck in non-terminal states and resolves it (Q156). **This is the safety net that catches everything the other layers missed**, and it's the layer most often skipped.

**10. Observability** — state distribution, oldest-pending age, DLQ depth, outbox lag. Alert on the *age* of the oldest stuck item, not raw counts.

**The principle underneath all ten:** *assume the process can vanish between any two instructions.* Everything that must survive that must already be committed. Every mechanism above follows from that one assumption.

---

## 248. When use outbox?

**Use it whenever a database write and an external effect must both happen, and you cannot tolerate one without the other.**

**Concretely:**
- Order created → notify fulfilment
- Payment captured → send receipt, update accounting
- User deleted → propagate deletion to downstream services (a compliance requirement)
- Any state change other services subscribe to
- Any write that must trigger a search-index or cache update

**Do NOT use it when:**
- **The effect is genuinely optional.** An analytics ping that can be lost doesn't justify the machinery — fire and forget.
- **The consumer polls anyway.** If a downstream job scans for changed rows every minute, the outbox adds nothing.
- **A single system already covers it** — PostgreSQL `SKIP LOCKED` puts the claim and the work in one transaction, so there's no gap to bridge.
- **You can make the read-side pull instead of the write-side push.** Often the simplest correct design.

**The costs to state honestly:**
- An extra insert on every business transaction
- A relay process to build, deploy, and monitor
- Publish latency (polling interval, typically 100ms–1s)
- High-churn table needing aggressive pruning and vacuum attention (Q139)
- **A new invisible failure mode**: if the relay stalls, the application works perfectly while no events reach anyone. **Monitoring unpublished-row age is mandatory**, not optional.

**The alternatives and when they win:**
- **CDC (Debezium)** — reads the WAL, no outbox table, no polling load, lower latency. Better at scale; more infrastructure.
- **Listen/Notify** — PostgreSQL's `NOTIFY` fires on commit. Lightweight, but not durable — a disconnected listener misses it. Fine as a latency optimisation *on top of* a polling outbox, not as a replacement.

---

## 249. What changes when scaling horizontally?

**Everything that relied on there being one process stops being true.** That's the whole answer, and then you enumerate.

| Assumption that breaks | Consequence | Fix |
|---|---|---|
| In-memory state is shared | Each instance has its own view (Q82) | Redis or PostgreSQL |
| `asyncio.Lock` provides mutual exclusion | N instances, N independent locks, zero protection | Distributed lock or DB constraint |
| Rate limiter enforces the limit | Effective limit is N× configured | Redis-backed counters |
| Circuit breaker state is shared | Some instances hammer a dead service | Shared state, or accept per-instance |
| A scheduled job runs once | It runs N times | Leader election, or a DB lock, or a dedicated singleton |
| Connection pool size is what I configured | `N × pool_size` connections to PostgreSQL | PgBouncer; size pools as `max_conn / (pods × workers)` |
| Cache is warm | Each instance has a cold cache | Shared Redis, or accept lower hit rates |
| SSE/WebSocket clients are reachable | Only from the instance holding the connection | Redis Pub/Sub fanout |
| Ordering is preserved | Concurrent consumers reorder (Q231) | Partition by key |
| Logs are in one place | Scattered across instances | Centralised logging + request IDs (Q87) |

**The two that cause the most production damage:**

1. **Connection pool multiplication.** `pool_size=20` × 4 workers × 10 pods = 800 connections against PostgreSQL's default `max_connections=100`. **You take down the database by scaling the API.** This is the most common self-inflicted outage in this space.

2. **Scheduled jobs running N times.** A nightly billing job on 5 replicas bills everyone 5 times. Needs an explicit singleton mechanism — a distributed lock (as an optimisation) plus an idempotency key (for correctness).

**The governing principle:** *in a horizontally scaled system, process memory is a cache, never a source of truth.* Anything requiring a single consistent view must live in a system all instances share.

---

## 250. Where can duplicate work occur?

**Enumerate the boundaries — that's what the question is testing.**

| Boundary | Duplicate source |
|---|---|
| **Client → API** | Retry after an ambiguous timeout (Q244) |
| **API → API** | Service-to-service retry; layered retries multiplying (Q96) |
| **Producer → queue** | Publish retried after ambiguous ACK |
| **Queue → consumer** | At-least-once redelivery; crash before ACK (Q197) |
| **Reclaim mechanism** | Slow-but-alive worker wrongly reclaimed (Q209) |
| **Outbox relay** | Published, crashed before marking (Q238) |
| **Scheduled jobs** | N replicas each running it (Q249) |
| **Manual operations** | DLQ replay, backfill scripts, incident remediation |
| **Deploys** | Worker restarted mid-processing |
| **Provider webhooks** | Their at-least-once delivery (Q242) |

**The defence at each boundary is the same primitive:** a unique identifier plus a uniqueness constraint at the point of effect.

**The architectural insight worth stating:** you don't defend at *every* boundary independently — that's a lot of duplicated machinery. You defend at the **point where the effect becomes real**: the database write, the payment API call, the email send. One idempotency check at the effect covers duplicates arriving from every path above it.

**Which means the practical question is:** *what is the natural idempotency key for this effect?* For a payment it's the client's idempotency key. For a webhook it's `(provider, event_id)`. For a job step it's `(run_id, seq)`. Identifying that key is the design work; the constraint is trivial once you have it.

---

## 251. Where can data be lost?

| Point | Loss mechanism | Prevention |
|---|---|---|
| **Client → API** | Request never arrives; client gives up | Client-side retry with a persisted idempotency key |
| **API before commit** | Crash mid-request | Nothing lost — the client knows it failed and retries |
| **Fire-and-forget background task** | Process dies; client already got 200 (Q83) | Durable queue |
| **DB → event publish** | Crash in the gap (Q246) | Outbox |
| **Queue** | Redis async replication loses acknowledged writes on failover (Q240) | DB row as the durable record |
| **Consumer ACKs before processing** | Crash loses the message silently (Q196) | ACK after |
| **Consumer ACKs in `finally`** | Failed messages discarded | ACK only on success |
| **Pending entry never reclaimed** | No reclaim loop → entry sits forever (Q208) | `XAUTOCLAIM` loop + monitoring |
| **DLQ nobody watches** | Messages accumulate unnoticed | Alert on depth |
| **In-memory state on SIGKILL** | Anything not committed (Q45) | Persist incrementally |
| **Cache eviction of authoritative data** | `maxmemory-policy` deletes it (Q192) | Never make Redis authoritative |
| **Retention expiry** | Stream trimmed before consumption | Monitor consumer lag vs retention |

**The two most dangerous, because they're silent:**

1. **ACK-before-process.** Every metric is green. The queue is empty. The work never happened. There is no error anywhere.
2. **A DLQ or PEL nobody monitors.** The system is "working" — messages are being removed from the main queue — while data quietly accumulates in a corner.

**The general defence:** every message must have a durable home *before* it's acknowledged anywhere, and every terminal state must be either a success or an *alerted* failure. **A silent third state is where data goes to disappear.**

---

## 252. Where can ordering break?

| Point | Mechanism |
|---|---|
| **Multiple producers** | Unsynchronised clocks; no global order exists |
| **Network** | Different paths, different latencies |
| **Queue partitioning** | No cross-partition ordering guarantee |
| **Multiple consumers** | Parallel processing at different speeds (Q212) |
| **Concurrency within a consumer** | Batch processed in parallel (Q211) |
| **Retries** | A failed message completes after its successors |
| **Reclaim** | Reprocessed minutes later |
| **Variable work per message** | One needs 3 LLM calls, another hits cache |
| **Outbox relay batching** | Ordering preserved only if you order by outbox ID |
| **Replicas** | Different replicas at different points in the WAL stream |

**The conclusion:** ordering is preserved only within a single sequential path. Any parallelism, any retry, any failure breaks it.

**So design for arbitrary order** (Q231): guarded state transitions, version/timestamp checks, commutative operations, or fetch-authoritative-state.

**If you genuinely need ordering:** partition by key, one consumer per partition. Then say the cost out loud — throughput is bounded by the slowest message in each partition, and a single slow or poisoned message blocks everything behind it (head-of-line blocking). **Ordering is expensive**, and the mature answer checks whether it's actually required before designing around it. Most of the time a state machine removes the requirement entirely.

---

## 253. What cost did your design add?

**This question rewards honesty and punishes salesmanship.** Every reliability mechanism has a bill; naming them shows judgement.

**Latency.** Async processing means the user waits for a poll or an SSE event instead of a synchronous response. Outbox polling adds 100ms–1s. Retries with backoff turn a 200ms failure into a 3-second success.

**Complexity.** A synchronous handler becomes: API + queue + worker + outbox + relay + reaper + DLQ + replay tooling. More code, more deploys, more failure modes, more onboarding time for a new engineer.

**Operational surface.** DLQ depth, oldest-pending age, outbox lag, PEL size, stuck-job counts — each needs a dashboard, an alert, and a runbook. **Machinery without monitoring is worse than no machinery**, because it hides failures.

**Storage and write amplification.** Idempotency keys, dedupe tables, outbox rows, run-step records, audit trails. Each business transaction now writes 3–5 rows instead of 1. These tables have high churn and need partitioning and aggressive vacuum.

**Eventual consistency.** The client cannot be told the outcome synchronously. Read-your-writes needs explicit handling. Every "why doesn't it show up immediately?" support ticket traces here.

**Debugging difficulty.** A failure now spans five components. Without distributed tracing, "it didn't work" has no starting point.

**Money.** More database writes, more Redis memory, more worker instances, more observability data.

**And the meta-cost:** every mechanism is itself a thing that can break. The reaper can stall. The relay can fall behind silently. You've traded a small number of loud failures for a larger number of quiet ones.

**The closing line that lands:** *"This design is right for payments, where a lost event is unrecoverable. For a feature where the worst case is a missing analytics row, it would be over-engineering — I'd do the direct call and move on."* Q262 is the same test.

---

# L4 — System design

## 254. Design event-driven payments.

**Requirements:** never lose money, never double-charge, tolerate provider outages, full audit trail, handle out-of-order and duplicate webhooks, reconcilable.

**Flow:**
```
Client ──idempotency-key──▶ Payment API
                              │ (one txn)
                              ├─ INSERT idempotency_keys
                              ├─ INSERT payments (status='created')
                              ├─ INSERT ledger_entries
                              └─ INSERT outbox('payment.created')
                              COMMIT → 202 {payment_id}
                                 │
                          Outbox relay ──▶ Stream ──▶ Payment worker
                                                        │ call provider
                                                        │ (provider idempotency key)
                                                        ▼
                          Provider webhook ──▶ Webhook API (verify HMAC, dedupe,
                                                             guarded transition)
                                 │
                          Reconciliation sweep (polls stuck payments, daily settlement)
```

**The decisions to defend:**

1. **Idempotency key + payment + ledger + outbox in one transaction.** This is the crux — no dual writes anywhere on the critical path (Q160, Q238).

2. **The provider call happens in a worker, never in the request.** It's slow, it's unreliable, and calling it inside a transaction would hold locks across the network (Q145).

3. **Provider idempotency key derived from ours**, so even a worker retry can't double-charge at the provider.

4. **Webhooks: verify HMAC over the raw body → dedupe on `(provider, event_id)` → apply through a guarded state transition → ACK fast, process async** (Q242, Q243).

5. **Treat webhooks as notifications.** Fetch the authoritative payment object from the provider rather than trusting the payload's amount and status. Order and duplicates stop mattering.

6. **Reconciliation is not optional** (Q156, Q157): a sweep for payments stuck in non-terminal states with exponentially increasing poll intervals, plus daily settlement-file comparison. **This is the only mechanism that catches payments that succeeded at the provider and were never recorded by you.**

7. **Ledger is append-only, double-entry, `UPDATE`/`DELETE` revoked at the database level** (Q161).

**CAP position:** CP for the ledger — refuse to write during a partition rather than risk divergence. AP for the payment history view.

**What I'd say about the trade-off:** this is heavy machinery, justified because a lost payment event is unrecoverable and a double charge is a customer-trust event. I would not build this for a feature-flag service.

---

## 255. Design notifications.

**Requirements:** multi-channel (push, email, SMS, in-app), per-user preferences, no duplicates, no notification storms, respect quiet hours, handle provider outages, track delivery.

**Architecture:**
```
Domain events ──▶ Notification service
                    │ resolve recipients
                    │ apply preferences + quiet hours
                    │ dedupe + rate limit per user
                    │ render template
                    ▼
              Per-channel queues (push / email / SMS)
                    │ (separate — different rate limits, different failure modes)
                    ▼
              Channel workers ──▶ Providers (FCM/APNs, SES, Twilio)
                    │
              Delivery receipts ──▶ status tracking
```

**The decisions that matter:**

1. **Separate queue per channel.** Email has a 14/sec SES limit; push has different limits and much lower latency expectations. One queue means a slow channel blocks all channels (head-of-line blocking, Q252).

2. **Idempotency on `(user_id, event_id, channel)`.** An event delivered twice must not notify twice. Unique constraint at the send point (Q250).

3. **Rate limit per user, not just globally.** Twenty notifications in a minute is a bug from the user's perspective regardless of whether your infrastructure can handle it. Cap per user per hour, and **aggregate** — "5 new comments" rather than five notifications.

4. **Quiet hours require the user's timezone**, stored per user, and a scheduled-send mechanism (a sorted set with score = send time, Q176).

5. **Preferences checked at send time, not at enqueue time.** A user who unsubscribes between enqueue and send must not receive it.

6. **Templates versioned and rendered in the worker**, so a template fix doesn't require re-emitting events.

7. **Delivery receipts** — providers report bounces, invalid tokens, and unsubscribes. Feed these back: an invalid FCM token must be deleted, or you retry forever against a device that no longer exists.

8. **Circuit breaker per provider** with a fallback (SMS if push fails for a critical alert).

**The failure mode to name unprompted:** a bug that re-emits historical events, sending months of notifications at once. Guard with a per-user rate limit *and* a global sanity check that halts sending if volume exceeds a multiple of baseline. A kill switch is worth building before you need it.

---

## 256. Design a distributed job scheduler.

**Requirements:** run jobs on a schedule (cron and one-off), exactly-once *effect* per scheduled occurrence, survive node failure, scale to many jobs, no drift, handle missed windows.

**Architecture:**
```
job_definitions (cron expr, timezone, payload, enabled)
       │
Scheduler (N replicas, leader-elected or partitioned)
       │ computes next_run_at, claims due jobs
       ▼
job_runs (one row per scheduled occurrence)  ◀── the idempotency anchor
       │
    Outbox ──▶ Queue ──▶ Workers
```

**The design decisions:**

1. **The uniqueness anchor is `UNIQUE (job_id, scheduled_for)`.** This is the crux of the whole design. Even if three scheduler replicas all decide a job is due, only one `INSERT` into `job_runs` succeeds. **The database, not leader election, guarantees single execution.** Leader election is an optimisation to reduce contention, not the correctness mechanism (Q235).

2. **Claim with `SKIP LOCKED`** so schedulers don't block each other:
```sql
UPDATE job_definitions SET next_run_at = <computed>, last_claimed_at = now()
WHERE id = (SELECT id FROM job_definitions
            WHERE enabled AND next_run_at <= now()
            ORDER BY next_run_at FOR UPDATE SKIP LOCKED LIMIT 10)
RETURNING *;
```

3. **Store timezone with the cron expression.** "Daily at 9am" during a DST transition is ambiguous — decide and document whether it runs once, twice, or skips. This is a real source of production bugs.

4. **Handle missed windows explicitly.** If the scheduler was down for two hours, do you run the four missed occurrences, just the latest, or none? **This is a per-job policy** (`catchup: all | latest | skip`), not a global default. Airflow calls it backfill; getting it wrong means a billing job running 48 times after an outage.

5. **Overlap policy.** If the previous run is still going when the next is due: skip, queue, or run concurrently? Per job.

6. **Decouple scheduling from execution.** The scheduler only creates `job_runs` rows and enqueues; workers execute. A slow job must never delay the scheduler.

7. **Jitter the schedule.** A thousand jobs all at `:00` is a self-inflicted spike (Q228). Spread within the minute.

8. **Monitoring:** scheduler lag (`now() - next_run_at` for the oldest due job), runs stuck in `running`, and a per-job "expected N runs today, saw M" check that catches silent non-execution — the failure nobody notices.

---

## 257. Design file processing.

**Requirements:** upload up to 10 GB, process asynchronously (virus scan, extract text, generate thumbnails, index), survive worker failure, resumable, no duplicate processing, tenant-isolated.

**Flow:**
```
Client ──▶ POST /uploads → presigned multipart URLs + upload_id (row created)
Client ──▶ direct multipart upload to S3 (parallel parts, resumable)
Client ──▶ POST /uploads/{id}/complete
              │ (one txn) update status='uploaded' + outbox('file.uploaded')
              ▼
         Pipeline: scan → extract → derive → index
              each stage: own queue, own scaling, own retry policy
              each stage result persisted before the next begins
```

**The decisions:**

1. **Never proxy bytes through your API** (Q94). Presigned URLs; multipart for resumability and parallelism; short expiry; content-length-range constrained in the policy so a client can't upload 100 GB on your bill.

2. **A pipeline of stages, not one monolithic job.** Virus scanning is fast and CPU-light; text extraction from a 500-page PDF is heavy; embedding generation is rate-limited by an external provider. **Different resource profiles need different queues and different scaling** (Q100). One stage failing doesn't redo the others.

3. **Persist each stage's output** (`file_stages` table keyed on `(file_id, stage)`), so a crash resumes rather than restarts. For a 10 GB file this is the difference between minutes and hours (Q247).

4. **Idempotency on `(file_id, stage)`** — reprocessing a stage is a no-op.

5. **Validate after upload, never trust the client.** Sniff the content type from magic bytes, not the extension or the declared type. Mark the file `pending` and expose it only after validation passes.

6. **S3 lifecycle rule aborting incomplete multipart uploads after 7 days.** Otherwise abandoned parts consume storage and bill you silently, forever. Non-optional.

7. **Tenant isolation in the key prefix** (`{tenant_id}/{file_id}/...`) with the presign IAM policy scoped to that prefix.

8. **Dead-letter with the file reference**, so a failed extraction can be replayed after a parser fix without re-uploading.

**Failure to raise unprompted:** a poison file (a malformed PDF that crashes the parser) retried forever consumes a worker permanently. Classify parse errors as permanent, dead-letter immediately, and alert (Q199).

---

## 258. Design a multi-tenant backend.

**Requirements:** strict data isolation, per-tenant quotas and rate limits, noisy-neighbour protection, per-tenant configuration, and the ability to scale a large tenant independently.

**Isolation model.** Shared schema with `tenant_id` for most SaaS (lowest cost, lowest ops burden); schema-per-tenant or database-per-tenant when compliance demands it or when a single tenant is large enough to justify dedicated infrastructure. **State the trade-off and pick one** (Q93).

**The layered enforcement — the core of the answer:**
1. **Tenant identity from the token only.** Never from a request parameter, header, or body. Accepting a `tenant_id` from the client is an IDOR waiting to happen.
2. **A dependency resolves and validates the tenant context.**
3. **Repository layer always filters** — enforced structurally by a base class, so an individual developer can't forget.
4. **PostgreSQL Row-Level Security as the backstop.** A forgotten `WHERE` returns zero rows instead of every tenant's data. **This is what turns "we're careful" into "it's impossible."**
5. **404 not 403** for another tenant's resource, preventing enumeration (Q70).
6. **A CI test that attempts cross-tenant access on every endpoint.** This is the difference between claiming isolation and having it.

**Noisy-neighbour protection — the distributed-systems part:**
- **Per-tenant rate limits and quotas**, Redis-backed so they hold across instances (Q249)
- **Separate queues or consumer groups per tenant tier**, so one large customer's 10,000-job burst doesn't starve everyone (head-of-line blocking at the fleet level)
- **Per-tenant concurrency caps** on expensive operations
- **Bulkheaded connection pools** by workload class
- **Cost tracking per tenant** — for AI workloads this is essential, since spend varies by orders of magnitude between tenants

**Operations:** `tenant_id` on every log line, metric, and trace span; per-tenant dashboards; the ability to disable or throttle a single tenant during an incident without a deploy.

**Data lifecycle:** tenant deletion must propagate everywhere — database, object storage, search index, vector store, caches, backups. **This is a compliance requirement (GDPR) and it's where most designs are incomplete.** Model it as a durable multi-step workflow with verification, not a single `DELETE`.

---

## 259. Design a long-running AI workflow.

Full treatment at Q92. The distributed-systems emphasis:

**The properties that make it hard:** runs last 30 seconds to 30 minutes, cost real money per step, cannot be interrupted mid-LLM-call, and must survive worker death without repeating expensive work.

**The core design decision: persist every step.**
```sql
CREATE TABLE run_steps (
  run_id UUID, seq INT, type TEXT, payload JSONB, cost_cents INT,
  created_at TIMESTAMPTZ, PRIMARY KEY (run_id, seq)
);
```
Each step commits before the next begins. A worker dying at turn 23 is replaced by one that reads turns 1–22 and resumes. **Without this, a 30-minute run dying at minute 29 restarts from zero and you pay the LLM bill twice.** This is the single most important decision in the design, and it's what question 317 is asking about.

**Lease + heartbeat** for dead-worker detection (Q201). The lease must exceed the longest single step (an LLM call can take 60+ seconds), with heartbeats during it so detection stays fast.

**Idempotency per step** on `(run_id, seq)` — a step that completed but wasn't recorded before the crash re-runs safely.

**Cancellation is cooperative.** Set `status='cancelling'`; the worker checks between steps. **You cannot interrupt an in-flight LLM call** — say this explicitly and set the API contract accordingly.

**Cost controls as first-class design:** per-run token cap, per-tenant budget checked before starting *and* between steps, actual cost accumulated per step. An agent that loops burns money in real time; a step-count cap and a spend cap are both required (Q306).

**Progress via a stream, not a direct connection.** The worker writes events to Redis/Postgres; the SSE endpoint reads from there (Q89). This fully decouples client connectivity from job execution — client disconnects, API deploys, and reconnections don't touch the running job.

**Failure classification:** retryable (429, 5xx, timeout) vs terminal (content filter, invalid input, schema violation after N repair attempts). **Never retry a terminal error** — it burns money to fail identically.

---

## 260. Design 100k jobs/hour.

**First, the arithmetic — state it, because it reframes the problem.** 100,000/hour is ~28 jobs/second. That is *not* a large number. If each job takes 1 second, you need ~28 concurrent workers. If each takes 30 seconds, you need ~840.

**So the design question is not "how do I handle 100k?" — it's "what does each job do, and what does it depend on?"** Say that first; it's the answer they're testing for.

**Assume 5-second jobs → ~140 concurrent workers.**

**Architecture:**
```
Producer ──▶ outbox ──▶ relay ──▶ Redis Streams (partitioned by key)
                                        │
                              Consumer group, ~140 consumers
                                        │
                          PgBouncer ──▶ PostgreSQL
```

**The bottlenecks, in the order they'll actually bite:**

1. **Database connections.** 140 workers × even a small pool exceeds `max_connections`. **PgBouncer in transaction mode is mandatory**, not optional (Q86, Q249). This binds long before CPU does.

2. **Write throughput.** 28 jobs/sec × 4 rows each (job row, step, idempotency, outbox) = ~112 writes/sec. Fine for PostgreSQL, but batch where possible and keep transactions short.

3. **Upstream rate limits.** If jobs call an external API limited to 20/sec, no amount of workers helps. The limiter must be shared (Redis), and worker count should be sized to the *limit*, not to the queue depth.

4. **Redis memory.** At 28/sec with 1 KB messages and 24-hour retention, that's ~2.4 GB. Trim aggressively with `MAXLEN ~`.

**Design choices:**
- **Partition by key** if ordering matters; otherwise a single consumer group is simpler.
- **Separate queues by job duration.** Fast and slow jobs in one queue means head-of-line blocking (Q204).
- **Autoscale on oldest-pending-age**, not queue depth (Q100).
- **Batch where the work allows** — 100 rows in one insert beats 100 inserts.

**Failure handling at this rate:** at 28/sec, a 1% failure rate is 1,000 failures/hour. The DLQ needs real capacity, real monitoring, and a working replay path — at this volume you *will* use it.

**The closing point:** 100k/hour is comfortably within a single PostgreSQL instance and one Redis instance. Reaching for Kafka or sharding here would be premature (Q215). Say so.

---

## 261. Design a system with 30-minute jobs.

**Long duration changes which failure modes dominate.** The design is Q259's, with these specific consequences:

**1. Deploys become the primary failure source.** A rolling deploy every few hours against 30-minute jobs means jobs are killed mid-flight routinely. This is not an edge case; it's the normal operating condition. Therefore:
- **Incremental persistence is mandatory** (Q247) — resume, don't restart
- `terminationGracePeriodSeconds` cannot practically cover 30 minutes, so plan for kill-and-resume rather than drain-and-finish
- Or: drain workers by stopping intake and waiting, accepting slow deploys

**2. Lease duration must exceed the longest single step, not the whole job.** A 30-minute lease means 30 minutes to detect a dead worker. Instead: a 2-minute lease with heartbeats every 30 seconds. Fast detection, no false reclaims (Q201).

**3. Progress visibility is a product requirement**, not a nicety. Thirty minutes of silence is indistinguishable from a hang. Emit step-level progress events; expose a percentage or a current-step description.

**4. Timeouts need care.** A job-level timeout of 45 minutes plus a step-level timeout of 2 minutes. Without step timeouts, a single hung external call consumes the entire job budget.

**5. Resource holding.** A 30-minute job must **not** hold a database connection or a transaction for its duration (Q144). Acquire, do a short unit of work, release. This is non-negotiable and is the most common mistake.

**6. Cancellation must be cooperative and responsive.** Check a cancellation flag between steps. Users will cancel 30-minute jobs; if cancellation takes 30 minutes to take effect, it's not cancellation.

**7. Scaling down is slow.** A worker can't finish in the grace period, so scale-down either kills work (fine, if resumable) or requires long drain windows. Bias toward resumability rather than long drains.

**8. Cost exposure.** A runaway 30-minute AI job burns money the whole time. Budget checks between steps, not just at the start (Q259).

**The framing:** *for long jobs, the design centre of gravity moves from throughput to resumability. Every mechanism exists to make "the worker died at minute 28" cost 2 minutes instead of 30.*

---

## 262. What would you remove if traffic were 1/100th?

**This is the judgement question, and it's the most revealing one in the section.** An engineer who can't answer it will over-engineer everything.

**At 1/100th scale — say 1,000 jobs/hour, a few requests per second — I would remove:**

1. **Redis entirely, probably.** PostgreSQL `SKIP LOCKED` gives a durable queue with transactional claim-and-work in *one* system — which is strictly *better* than a separate broker, because there's no dual-write gap at all (Q232). One less stateful service to operate, back up, and monitor.

2. **The outbox relay.** If the queue is a PostgreSQL table, the state change and the enqueue are already in the same transaction. The dual-write problem doesn't exist, so the pattern that solves it isn't needed (Q248).

3. **Read replicas.** One instance handles the load with room to spare. Replicas add lag and read-your-writes complexity for no benefit.

4. **Caching.** At low volume, PostgreSQL primary-key lookups on a cached page are sub-millisecond. A cache adds an invalidation bug surface to solve a problem you don't have.

5. **Horizontal scaling machinery.** One or two instances. Which removes most of Q249's list — no distributed rate limiter, no distributed locks, no leader election for scheduled jobs (a single instance runs it once, correctly, by construction).

6. **Separate queues by workload class.** With low volume, head-of-line blocking is unlikely to bite.

7. **Circuit breakers**, possibly. With few concurrent requests, a dead upstream doesn't exhaust your capacity — timeouts alone suffice.

**What I would absolutely keep, regardless of scale:**

- **Idempotency keys and unique constraints.** Duplicates come from client retries and ambiguous failures, which are a function of *networks*, not volume. A double charge at 10 requests/day is exactly as bad as at 10,000.
- **The state machine and guarded transitions.** Correctness, not performance.
- **The append-only ledger and reconciliation.** Money correctness is scale-independent, and reconciliation catches bugs earlier when you have fewer records.
- **Timeouts on everything.** A hung call blocks a worker regardless of traffic.
- **Structured logging with request IDs.** Debugging is *harder* at low volume, not easier — fewer occurrences means less signal.
- **Graceful shutdown.**

**The principle to state explicitly:** *correctness mechanisms are scale-independent; capacity mechanisms are not.* Idempotency, constraints, and reconciliation exist because networks are unreliable — that's true at any volume. Sharding, caching, replicas, and circuit breakers exist because of load — those you add when you measure a need.

**And the closing line:** *"The failure mode I'd worry about at 1/100th scale isn't capacity — it's building all of this anyway and spending six months operating infrastructure for traffic that fits on one box."*

---

*End of Document 05. Next: Document 06 — LLM fundamentals (questions 263–290).*
