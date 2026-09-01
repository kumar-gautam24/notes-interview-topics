# Document 15 — System Design (Questions 548–571)

Answer format: **requirements → constraints → architecture → trade-offs → failure modes → what I'd cut**

> **Note on Section N.** System design questions are not testing whether you can name components. They test whether you **interrogate the requirements before designing**, whether you **state trade-offs honestly**, and whether you can say **what you'd remove at smaller scale**. A candidate who draws a maximal architecture without asking a question has failed before they start drawing.

---

# The method (read this first)

Every answer below follows the same shape, and you should too:

1. **Clarify.** Ask 2–4 questions that materially change the design. Read/write ratio, scale, latency SLO, consistency requirements, team size.
2. **State assumptions explicitly**, so the interviewer can correct you early rather than at the end.
3. **Do the arithmetic.** QPS, storage, concurrency via Little's Law. Numbers constrain the design and demonstrate you're not pattern-matching.
4. **Design the happy path**, then the failure paths.
5. **Name the trade-offs you chose**, and what you gave up.
6. **Say what you'd cut at 1/100th scale** (Q262). This is the judgement signal.

---

## 548. Design a RAG-powered support assistant.

**Clarify:** How large is the knowledge base? Is it per-tenant? What's the latency expectation? Does it need to take actions or only answer? What happens when it doesn't know?

**Assume:** 50k documents across 200 tenants, answers only, p95 under 3 seconds, refusal preferred over guessing.

**Architecture:**
```
Ingestion:  source → extract → structure-aware chunk → enrich metadata
                   → dedupe by hash → embed (batched, cached) → pgvector + tsvector

Query:      question → rewrite w/ history → [vector ‖ BM25] filtered by tenant
                    → RRF → rerank → threshold → top 5 → generate w/ citations
                    → verify citations → stream
```

**The decisions to defend:**
- **Hybrid + rerank**, because support queries mix conceptual questions with error codes and product names that pure vector search fails on (Q355)
- **pgvector**, because tenant filtering and permissions are SQL predicates in the same transaction (Q344)
- **Citations required and verified** — for support, "here's the article this came from" is most of the product value (Q350)
- **Explicit refusal with a calibrated threshold** (Q370), because a confident wrong answer to a support question generates a ticket *and* destroys trust

**Failure modes:** stale docs outranking current ones (fix: effective-date filter, Q360); the model answering from training knowledge (fix: refusal instruction plus unanswerable eval cases, Q369); identifier queries failing (fix: BM25).

**Measurement:** recall@5 on a golden set built from real support tickets, refusal rate on both answerable and unanswerable sets, citation validity in production (Q546).

**At 1/100th scale:** drop the reranker if recall@5 is already high, drop hybrid if there are no identifier queries, and re-index on a cron instead of event-driven.

---

## 549. Design a document Q&A system with permissions.

**Clarify:** How granular are permissions — per document, per section, per field? Do they change frequently? Are there sharing/delegation semantics?

**The core requirement: a user must never retrieve content they cannot read**, and the filter must be in the query, never applied afterwards (Q359).

**Architecture additions over Q548:**
```sql
SELECT id, content FROM chunks c
WHERE c.tenant_id = $tenant
  AND c.deleted_at IS NULL
  AND (c.access_level = ANY($user_levels)
       OR EXISTS (SELECT 1 FROM document_grants g
                  WHERE g.document_id = c.document_id AND g.user_id = $user))
ORDER BY c.embedding <=> $qvec LIMIT 20;
```

**The design trade-off to name explicitly:** denormalising permissions onto chunks makes filtering fast but creates a staleness window on revocation. Joining live permissions is always correct but slower and interacts badly with ANN indexes. **The hybrid — coarse levels denormalised, fine grants joined, revocation triggering an immediate targeted update — is usually right** (Q386).

**RLS as the backstop** so a forgotten predicate returns zero rows rather than everyone's documents (Q520).

**The subtle leaks to address unprompted:**
- **Cache keys must include the permission context**, or one user's answer is served to another (Q391)
- **Citations to inaccessible documents** leak titles even when content is filtered
- **Existence leakage** — the response shape must be identical whether a document doesn't exist or isn't permitted (Q70)

**The test that proves it:** a CI suite attempting cross-permission retrieval on every path. **Claiming isolation and testing isolation are different things.**

---

## 550. Design a multi-tenant AI platform.

**Clarify:** How many tenants, and how uneven are they? Is there a compliance driver for physical isolation? Do tenants supply their own configuration or content?

**The isolation model** (Q93, Q258): shared schema with `tenant_id` for most SaaS; schema-per-tenant when compliance demands it; database-per-tenant for a small number of large regulated customers. **Pick one and defend it with the cost/isolation trade-off.**

**The five isolation dimensions, and naming all five is the answer:**

| Dimension | Mechanism |
|---|---|
| **Data** | `tenant_id` everywhere + RLS backstop (Q520) |
| **Capacity** | Per-tenant queues, concurrency caps (Q204) |
| **Cost** | Per-tenant budgets with circuit breakers (Q336) |
| **Quota** | Shared LLM provider quota, per-tenant rate limits (Q464) |
| **Configuration** | Per-tenant prompts, tools, models — **validated templates, not free-form prompt injection** |

**The failure mode to raise unprompted:** one tenant with a buggy integration triggering thousands of runs. Without per-tenant caps that's your entire provider quota and a five-figure overnight bill. **Per-tenant spend limits are an availability control, not a billing feature.**

**Deletion completeness** (Q393): tenant offboarding must remove chunks, embeddings, caches, conversation histories, search indexes, and vector indexes. **Model it as a durable verified workflow, not a `DELETE` statement** — and build it before you need it.

**What I'd cut small:** per-tenant queues (one queue is fine at low volume), and physical isolation (shared schema plus RLS covers most requirements).

---

## 551. Design an async job platform.

**Clarify:** How long do jobs run? Must they be resumable? What's the acceptable delay? Are effects idempotent?

**Architecture:**
```
API → job row + outbox (one txn) → relay → queue → workers
                                                     │
                                          per-step persistence
                                          lease + heartbeat
                                                     │
                                          reaper (stuck detection)
```

**The decisions:**
1. **The durable record is a database row, written before enqueueing** (Q303). The queue message is a pointer. If the queue loses it, the reaper finds the orphan.
2. **Outbox**, so the state change and the enqueue are atomic (Q238).
3. **Lease + heartbeat** — short lease (2 min) with 30-second renewal gives fast crash detection without false reclaims (Q201).
4. **Idempotency on `(job_id, step)`** — at-least-once delivery guarantees duplicates (Q234).
5. **Bounded retries with jittered backoff, classified by error type, then dead-letter** (Q198, Q199).
6. **Separate queues by job duration class** — fast and slow in one queue means head-of-line blocking (Q204).

**The metric to autoscale on:** oldest-message age, not queue depth. It directly expresses the SLO (Q100).

**The honest simplification:** **PostgreSQL `SKIP LOCKED` gives you all of this in one system** (Q138), with the claim and the work in the same transaction — which is strictly better than a separate broker because there's no dual-write gap at all. For thousands of jobs per hour, that's the right answer and Redis is unnecessary complexity (Q262).

---

## 552. Design a webhook receiver.

**The requirements:** verify authenticity, tolerate duplicates and out-of-order delivery, ACK fast, never lose an event.

**The pipeline, in this exact order:**
```
1. Read RAW body                              (before any parsing)
2. Verify HMAC, constant-time                 (Q512)
3. Reject stale timestamps (>5 min)           (Q517)
4. INSERT ... ON CONFLICT DO NOTHING          (dedupe)
5. Return 200                                 (fast — providers time out)
6. Process asynchronously
```

**Why ACK-before-process:** providers time out in seconds and retry. Heavy inline processing causes timeouts and retries, multiplying load exactly when you're slow. **But the event must be durably persisted before you ACK**, or you've lost it.

**The three defences against duplicates and reordering, each failing differently:**
1. **Unique constraint on `(provider, event_id)`** — dedupe (Q153)
2. **Guarded state transitions** — `WHERE status IN ('authorized','pending')` makes a backwards or repeated event a no-op (Q154)
3. **Timestamp guard** — last-write-wins by event time, not arrival time

**The pattern that makes ordering irrelevant:** treat webhooks as **notifications, not data**. The webhook says "payment X changed"; you call `GET /payments/X` and apply the authoritative state. **For anything financial this is worth the extra API call unconditionally.**

**And the safety net:** webhooks *will* be missed — provider outage, your endpoint down during a deploy, misconfigured URL. **A reconciliation sweep polling non-terminal states, plus daily settlement comparison, is what catches events you never knew existed** (Q156). Webhooks are a latency optimisation, not a correctness mechanism.

---

## 553. Design a rate limiter.

**Clarify:** Per user, per IP, per endpoint, or per cost? Distributed across how many instances? Fail open or closed?

**The algorithm choice** (Q190): **token bucket** for user-facing APIs (permits legitimate bursts), **sliding window counter** as a good general default, **fixed window** only when simplicity dominates — it allows a 2× burst at the boundary.

**The distributed requirement:** Redis-backed with atomic Lua, because check-then-increment from the client has a race and per-instance limiters give you N× the intended rate (Q189, Q249).

```lua
-- atomic: refill, check, consume
local now, rate, cap = tonumber(ARGV[1]), tonumber(ARGV[2]), tonumber(ARGV[3])
local b = redis.call('HMGET', KEYS[1], 'tokens', 'ts')
local tokens = tonumber(b[1]) or cap
local ts = tonumber(b[2]) or now
tokens = math.min(cap, tokens + (now - ts) * rate)
if tokens >= 1 then
  redis.call('HMSET', KEYS[1], 'tokens', tokens - 1, 'ts', now)
  redis.call('EXPIRE', KEYS[1], 120)
  return 1
end
return 0
```

**Layer the limits:** edge/WAF → per-IP at ingress → per-principal in the application → per-endpoint for sensitive paths.

**The AI-specific requirement** (Q90): **limit by token spend, not request count.** A 200-token and a 50,000-token request differ by 250×; counting requests is meaningless. Debit from a token budget and reject when exhausted.

**The decision to state explicitly:** fail open or closed when Redis is unavailable? Public API → open (availability). Expensive AI endpoint → closed (cost). **The worst outcome is not having decided.**

**Response discipline:** 429 with `Retry-After` and `X-RateLimit-*` headers, so well-behaved clients self-regulate.

---

## 554. Design a payment flow.

Full schema at Q158, states at Q159, idempotency at Q160. The design summary:

**The invariants that drive everything:**
1. Money is `BIGINT` in minor units — never float
2. Financial records are append-only
3. Balances are derived and reconcilable against an immutable ledger

**The flow:**
```
Client --idempotency-key--> API
  (one transaction)
    INSERT idempotency_keys
    INSERT payments (status='created')
    INSERT ledger_entries (double-entry, sums to zero)
    INSERT outbox('payment.created')
  COMMIT → 202
      │
  relay → queue → worker → provider (with derived idempotency key)
      │
  webhook → verify → dedupe → guarded transition
      │
  reconciliation sweep + daily settlement comparison
```

**The three things that must be true:**
- **No dual writes on the critical path.** Idempotency key, payment, ledger, and outbox commit together (Q238).
- **The provider call is in a worker**, never in the request and never inside a transaction (Q145).
- **Reconciliation is mandatory** — it's the only mechanism catching payments that succeeded at the provider and were never recorded by you (Q157).

**Concurrency:** atomic conditional `UPDATE` with the guard in the `WHERE` clause, plus a `CHECK` constraint as the backstop (Q146, Q150). **The `WHERE` enforces the rule for correct code; the `CHECK` enforces it for incorrect code.**

**CAP position:** CP for the ledger — refuse to write during a partition rather than risk divergence. AP for the history view (Q223).

---

## 555. Design a notification system.

Full treatment at Q255. The summary:

**Architecture:**
```
domain events → notification service (resolve recipients, apply preferences,
                                      quiet hours, dedupe, rate limit, render)
              → per-channel queues (push / email / SMS)
              → channel workers → providers
              → delivery receipts → status + token cleanup
```

**The decisions:**
1. **Separate queue per channel** — SES limits, FCM limits, and latency expectations all differ. One queue means the slowest channel blocks all channels.
2. **Idempotency on `(user_id, event_id, channel)`** — an event delivered twice must not notify twice.
3. **Per-user rate limiting and aggregation.** Twenty notifications in a minute is a bug from the user's perspective regardless of infrastructure capacity. **"5 new comments" beats five notifications.**
4. **Preferences checked at send time, not enqueue time** — a user who unsubscribes in between must not receive it.
5. **Delivery receipts fed back** — an invalid FCM token must be deleted or you retry forever against a dead device.

**The failure mode to raise unprompted:** a bug re-emitting historical events, sending months of notifications at once. **Guard with per-user rate limits *and* a global sanity check that halts sending above a multiple of baseline.** A kill switch is worth building before you need it.

---

## 556. Design a file processing pipeline.

Full treatment at Q257. The summary:

**Presigned multipart upload direct to S3** — your API never handles bytes (Q94). Constrain content-length-range in the policy, or a client uploads 100 GB on your bill (Q518).

**Staged pipeline, each stage independently queued and scaled:**
```
scan → extract → chunk → enrich → embed → index
```
Because their resource profiles differ by orders of magnitude — virus scanning is fast, PDF extraction is CPU-heavy, embedding is rate-limited by an external API.

**Persist each stage's output** keyed on `(file_id, stage)`, so a crash resumes rather than restarts. For a 10 GB file this is the difference between minutes and hours.

**Validate after upload, never trust the client.** Sniff content type from magic bytes; mark the file `pending` and expose it only after validation (Q515).

**The two operational details that bite:**
1. **S3 lifecycle rule aborting incomplete multipart uploads after 7 days** — otherwise abandoned parts bill you silently forever. Not optional.
2. **Poison files** — a malformed PDF crashing the parser retries forever and consumes a worker permanently. Classify parse errors as terminal, dead-letter immediately (Q199).

**The quality point worth making:** **extraction determines the ceiling of the whole system.** A badly-extracted PDF with lost table structure produces bad chunks that no retrieval tuning recovers. Invest there first.

---

## 557. Design an agent execution platform.

Full treatment at Q331. The summary:

**Components:**
```
Run API (idempotent creation, 202 + run_id)
  → outbox → queue → Agent workers
                        ├── Tool registry (auth, schemas, context injection)
                        ├── Model gateway (routing, fallback, budget, caching)
                        └── Step store (durability, audit, replay, SSE source)
  + Reaper (lease expiry, timeouts, dead-lettering)
  + Eval pipeline (gates prompt/tool changes in CI)
```

**The decisions to defend:**
1. **Agent definitions are versioned code, not database rows** (Q329). Config-as-data for prompts removes your ability to review and test the highest-leverage part of the system.
2. **Deterministic core** — anything involving money, ranking, or state transitions is code, not model output (Q305).
3. **Every turn persisted before the next** — resumption costs two turns instead of forty (Q317).
4. **Tool authorization at a single choke point**, against the *user's* permissions, with security context injected server-side (Q311, Q325).
5. **Budget at three levels** — per run, per tenant per day, global kill switch.

**The metric that matters most:** terminal state distribution. A rise in `stuck` after a deploy is a regression your eval suite may have missed (Q545).

---

## 558. Design conversational memory.

**Clarify:** How long do conversations run? Does memory persist across sessions? Is it per-user or per-tenant?

**The problem:** there is no session (Q271). Every turn resends everything, so cost grows quadratically and you eventually hit the context limit.

**The three-layer design** (Q333):

| Layer | Contents | Lifetime |
|---|---|---|
| **Working context** | Last N turns verbatim | Current request |
| **Summary** | Compressed older turns | Conversation |
| **Structured memory** | Extracted facts, preferences, entities | Persistent |

```
system prompt (stable — cached)
+ structured memory (relevant facts only)
+ summary of turns 1..N-5
+ turns N-4..N verbatim
+ current message
```

**The design constraints:**
1. **Context assembly must be deterministic**, or resumption produces a different context and the agent behaves differently after a crash (Q317).
2. **Stable prefix first** for prompt caching (Q453). A summarisation step that rewrites the middle invalidates everything after it.
3. **Query rewriting before retrieval** — "what's the waiting period?" is unretrievable without resolving the referent (Q383).

**Cross-session memory** raises a product question, not just a technical one: what should be remembered, for how long, and can the user see and delete it? **Storing extracted facts about a user is a privacy surface** (Q519) that needs consent, visibility, and deletion.

**Evaluation:** your golden set must include multi-turn cases. A system scoring 0.9 on single-turn questions can collapse at turn three and single-turn evals never show it.

---

## 559. Design semantic search at scale.

**Clarify:** Corpus size, query volume, latency SLO, filter selectivity, update frequency.

**The arithmetic first** (Q408): 10M chunks × ~13 KB ≈ 130 GB including index and text. **The binding constraint is RAM, not disk** — the vector index must be cached or latency collapses (Q413).

**Architecture:**
```
query → embed (cached) → [HNSW ‖ BM25] with tenant/permission filter
      → RRF → rerank → results
```

**The scaling decisions in order:**
1. **`halfvec`** — halves vector storage with usually-negligible recall loss. **First thing to try** (Q408).
2. **Partition by tenant**, which also solves the ANN+filter recall problem (Q414)
3. **Dedicated read replica** for search, so vector queries don't evict the OLTP working set
4. **Then**, and only with a measured limit, a dedicated vector database (Q417)

**The filter problem is the hard part** (Q414): HNSW traverses the graph then filters, so a selective filter can silently return fewer than k results. **Alert when a query returns fewer rows than its `LIMIT`** — trivial to instrument and almost nobody does it. Use iterative scans (pgvector 0.8+) or partitioned indexes.

**Measurement:** ANN recall against exact search on a fixed ground-truth set, re-run on a schedule to catch gradual graph degradation (Q412).

**The judgement point:** below ~10M vectors, pgvector with proper tuning is the right answer, and reaching for a distributed vector database first is the same mistake as reaching for Kafka at 1,000 msg/s.

---

## 560. Design cost-aware LLM routing.

**The premise** (Q290, Q467): most requests don't need your strongest model. Routing the simple majority to a cheaper one is usually the **single largest cost win available** — often 3–5×.

**Architecture:**
```
request → classify (task type, or a cheap difficulty classifier)
        → route → model tier
        → [optional] confidence check → escalate if low
```

**The strategies:**
1. **Task-based** — the most reliable. Classification and extraction to a small model; synthesis and reasoning to a large one. **No classifier needed; the code path already knows what it's doing.**
2. **Cascade** — try cheap, escalate on low confidence. Effective, but you pay twice on escalation.
3. **Tenant tier** — premium customers get the better model.
4. **Load-based** — spill to a secondary when the primary is saturated.

**The prerequisite, and it's non-negotiable: an eval set per route** (Document 10). "Is the cheap model adequate for extraction?" is an empirical question with a number. **Routing without evals is guessing about quality to save money**, which is the wrong trade to make blind.

**Implementation in the model gateway** (Q465), configured rather than coded, so route changes can be canaried without a deploy.

**What to measure:** quality **per route** (aggregate hides that the cheap route degraded), cost per route, escalation rate, and traffic mix. **A shift in the mix changes your cost profile without anything breaking.**

**The trap:** routing on a proxy for difficulty — query length, keyword presence — that doesn't actually correlate with difficulty. **Validate the router itself** against labelled examples, not just the models it routes to.

---

## 561. Design an eval and deployment pipeline.

**The premise:** prompts are the highest-leverage and least-tested component in an LLM system. **Treating a prompt edit as an untested code change is the actual maturity gap** (Q433).

**The tiers:**
```
every commit    → retrieval eval, schema validation, tool selection (mocked)
                  deterministic, seconds, free
PR touching     → generation eval, grounding, citation validity, refusal,
prompts/models    regression set — minutes, ~₹100
nightly         → full golden set, adversarial, multi-turn, human sample
```

**Gating:**
```yaml
- run: python -m evals.run --baseline main --fail-on-regression 0.03
```
**Report deltas against baseline**, not absolutes — "recall@5: 0.84 → 0.91 (+0.07)" is what a reviewer needs.

**What must trigger a full run:** prompt, model version, chunking, embedding model, retrieval parameters, tool schemas. **These look harmless in a diff and aren't** (Q329).

**Deployment:** canary rather than blue/green for prompt and model changes, because their effects only appear under real query distribution. Route 5%, compare refusal rate, citation validity, cost per request, and thumbs-down, then proceed (Q500).

**Handle non-determinism:** run N times, report mean and spread, and set thresholds above the measured noise floor (Q439).

**The loop that keeps it honest** (Q437): production failure → regression case → CI. **A golden set that hasn't changed in six months is measuring a system that no longer exists.**

---

## 562. Design for a 10× traffic increase.

**Interrogate first: 10× of what?** Read-heavy or write-heavy? Sustained or spiky? Same query mix?

**Then work through the layers, in the order they'll actually break:**

**1. Fix the queries first.** A missing index routinely accounts for more load than any scaling change. **Do not scale a broken query — you'll pay 10× for the same problem** (Q167).

**2. Cache.** An 80% hit rate removes 80% of read load for a fraction of a replica's cost, and it's faster. **Best effort-to-result ratio available.** Add stampede protection or a hot key expiring recreates the spike you were avoiding (Q186).

**3. Connection pooling.** PgBouncer. **This binds before CPU does** — `replicas × workers × pool_size` against `max_connections` is the most common self-inflicted outage when scaling (Q496).

**4. Horizontal API scaling** on request rate or p99 latency, not CPU (Q488).

**5. Read replicas**, accepting replication lag and handling read-your-writes explicitly (Q170).

**6. Async everything expensive** — anything over ~100ms goes to a queue (Q76).

**7. Then** partitioning, sharding, or a different datastore.

**The AI-specific ceiling:** your LLM provider quota. **10× traffic against a fixed TPM allocation means queuing, model routing to smaller models, or negotiated capacity** — no amount of worker scaling helps (Q339).

**The closing point:** most 10× problems are solved by items 1–3. Items 5–7 are where teams start when they should finish there.

---

## 563. Design for global users.

**Clarify: what's the actual driver — latency, data residency, or disaster recovery?** They require different architectures and conflating them produces an expensive design that solves none of them well (Q501).

**For latency:**
- **CDN first.** Static assets and cacheable responses at the edge. **Often this alone is sufficient** and costs almost nothing.
- Regional read replicas for read-heavy workloads
- Edge compute for lightweight logic
- **Accept that writes go to one region.** Cross-region write latency is physics; a 200ms round trip to the primary is usually acceptable when reads are local.

**For data residency:** regional isolation where data never crosses. Tenant home region assigned at signup, routing by tenant. **This is the cleanest active-active model** because it avoids write conflicts entirely.

**For DR:** active-passive with cross-region replication and a **tested** failover (Q502).

**The hard part is always data, not compute.** Running pods in three regions is trivial; keeping state consistent is the whole problem.

**The costs to state:** cross-region transfer is billed and significant, active-active roughly doubles infrastructure, replication lag creates read-your-writes problems across regions, and **failover that isn't regularly drilled does not work.**

**The honest recommendation:** multi-AZ within one region plus a CDN gives most of the benefit at a fraction of the complexity. **Multi-region is justified by a specific requirement, not by ambition.**

---

## 564. Design for zero data loss.

**First, be precise: zero data loss means RPO = 0, and that has a specific cost** (Q502).

**What it requires:**
1. **Synchronous replication** — the primary waits for a replica to confirm before acknowledging. Costs write latency, and **if the replica is down, writes block.** You've traded availability for durability, deliberately.
2. **`synchronous_commit = on`** with WAL fsync before acknowledging.
3. **Multi-AZ synchronous standby** — protects against zone loss.
4. **WAL archiving** for point-in-time recovery.

**But durability at the database is not the whole system.** The gaps:
- **Data accepted but not yet committed** — a crash mid-request loses it. **The client must retry with an idempotency key** (Q244). Zero data loss requires a cooperating client.
- **Dual writes** — a database commit plus an external effect cannot be atomic. **Outbox** (Q238).
- **In-memory state** — anything not committed is lost on SIGKILL (Q45).
- **Queue durability** — Redis async replication can lose acknowledged writes on failover (Q240). **The durable record must be a database row.**

**The architecture:** durable write first, then derive everything else. Every stage idempotent. Reconciliation to catch what the mechanisms missed (Q157).

**The honest framing:** *"True zero data loss requires synchronous replication, idempotent clients, and reconciliation — and each costs something. For most systems the correct answer is a small, defined RPO with a tested recovery path, not zero."*

---

## 565. Design for zero downtime.

Full mechanics at Q497. The design summary:

**The six things that must hold simultaneously:**
1. Multiple replicas, `maxUnavailable: 0`
2. Correct readiness probes (Q483)
3. Graceful shutdown with a `preStop` sleep for the endpoint-removal race (Q485)
4. **Backward-compatible migrations** — expand/contract, because both versions run during the rollout (Q484)
5. Backward-compatible contracts — API, message formats, cache keys
6. **Exec-form `ENTRYPOINT`**, or SIGTERM never reaches your process (Q477)

**Item 4 is where the discipline is required and where rollback is most often lost.** A migration that drops a column the old code needs makes the deploy irreversible. **Every deploy must be independently revertible**, which means destructive schema changes span multiple releases.

**The verification that turns a claim into a fact:** run continuous synthetic traffic during a staging deploy and assert zero non-200 responses. **The endpoint-removal race is invisible at low traffic and obvious at high traffic** — so testing at realistic load is the only way to know.

**Beyond deploys:** zero downtime also means surviving node failure (multi-AZ, anti-affinity, PDBs — Q494), dependency failure (circuit breakers, degradation — Q461), and traffic spikes (autoscaling plus queuing).

**The honest scoping:** zero downtime for *deploys* is achievable and standard. Zero downtime overall is an SLO with an error budget, not an absolute (Q534).

---

## 566. Design for observability from day one.

**The argument: retrofitting observability is far more expensive than building it in, and you can't debug what you didn't instrument.**

**The day-one minimum:**
1. **Structured JSON logging** with automatic correlation ID injection (Q530, Q531)
2. **OpenTelemetry auto-instrumentation** — FastAPI, httpx, asyncpg, Redis. Nearly free, and it gives you traces immediately.
3. **RED metrics per endpoint**, with **bounded label cardinality** — route templates, not resolved paths (Q547)
4. **Health and readiness endpoints**, correctly distinguished (Q482, Q483)
5. **Deploy annotations** on dashboards — highest value-to-effort item available (Q540)
6. **A redaction processor** in the logging pipeline before any PII exists to leak (Q537)

**The AI-specific additions:**
7. **Token counts and cost on every model call** (Q544)
8. **Retrieved chunk IDs logged with every RAG response** — this is what makes post-hoc failure diagnosis possible (Q375, Q543)
9. **Prompt and model version recorded per request** (Q329)

**Why these three matter disproportionately:** each answers a question you *will* ask and cannot answer retroactively. "Was the right chunk retrieved for that failed query last Tuesday?" is either a one-line query or unanswerable, and the difference is a single field.

**What to defer:** custom dashboards beyond the service overview, tail-based sampling (until volume justifies it), and specialised LLM observability tooling.

**The design principle:** **instrument the questions you'll ask during an incident, not everything you can measure.** More signals cost money and obscure the useful ones.

---

## 567. Design an API for AI features.

**The design constraints that make AI APIs different:**
1. Latency is high and variable — seconds to minutes
2. Cost is per request and varies by 100×
3. Output is non-deterministic
4. Failures are partial and semantic, not just HTTP

**The API shape:**
```
POST /v1/queries          → 200 + streamed response   (fast, <10s)
POST /v1/runs             → 202 + run_id              (slow, async)
GET  /v1/runs/{id}        → status, result, cost
GET  /v1/runs/{id}/events → SSE
```
**The 10-second rule** (Q76): anything that can exceed it is a job, not a request.

**The design decisions:**
1. **Idempotency keys on every mutating endpoint** — a retried expensive AI call must not run twice (Q160)
2. **Stream by default** for interactive responses — transforms perceived latency for free (Q269)
3. **Return cost and token usage** in the response, so clients can reason about their spend
4. **Model and prompt version in the response** — clients need to know when behaviour changed
5. **Structured errors distinguishing semantic from technical failure** — "the model refused" is not a 500
6. **Confidence or grounding signals** where available, and citations where the answer is document-grounded

**The error taxonomy** worth defining explicitly: rate limited (429), budget exhausted (402), content filtered (422), no answer available (200 with a refusal payload, not an error), provider unavailable (503).

**That refusal case matters:** a refusal is a valid outcome, not an error. Returning 500 for "I don't have that information" breaks every client retry loop (Q75).

---

## 568. Design a feature flag system.

**Why it belongs in an AI system specifically:** prompt changes, model swaps, and retrieval parameter changes are high-risk behaviour changes that need gradual rollout and instant rollback **without a deploy** (Q329, Q500).

**The design:**
```python
class Flags(BaseModel):
    reranker_enabled: bool = False
    generation_model: str = "sonnet"
    retrieval_k: int = 20
    prompt_version: str = "v3"
```

**The properties that matter:**
1. **Evaluated per request**, with the tenant and user in context, so you can target
2. **Fetched with a short TTL cache** — not read at startup, or a change requires a restart (Q487)
3. **Safe defaults** — if the flag service is unavailable, fall back to the last known good config or a compiled-in default. **A flag system that fails closed takes down your product.**
4. **Percentage rollout with sticky bucketing** on user ID, so a user doesn't flip between variants mid-session
5. **The flag value recorded in traces and logs**, so you can segment metrics by variant — otherwise you can't tell whether the new variant is better
6. **A kill switch** for each risky path

**The critical addition for AI:** **flags are your canary mechanism.** Route 5% to the new prompt, compare refusal rate, citation validity, cost per request, and thumbs-down between variants, then proceed or roll back instantly.

**The discipline that keeps it maintainable:** flags accumulate and become permanent conditional complexity. **Every flag needs an owner and an expiry date**, and removing a fully-rolled-out flag is part of the work, not optional cleanup.

---

## 569. Design a migration from monolith to services.

**The first honest answer: don't, unless you have a specific reason.** Team autonomy, independent scaling of a genuinely different workload, or an isolation requirement. **"Microservices" as an architectural aspiration is how teams turn a working system into a distributed one with all of Document 05's problems and none of the benefits.**

**If there is a reason, the strangler fig pattern:**
1. **Put a facade in front** of the monolith — a routing layer
2. **Extract one bounded context** with clear boundaries and few dependencies
3. **Route that traffic** to the new service through the facade
4. **Verify**, then repeat
5. **The monolith shrinks** rather than being rewritten

**Never a big-bang rewrite.** It takes longer than estimated, the old system keeps changing underneath you, and there's no incremental value until the end.

**What to extract first:** something with a clear boundary, low coupling, a different scaling profile, and genuine value in isolation. **AI/ML workloads are often the ideal first extraction** — different resource profile (GPU or heavy I/O), different scaling signal, different deploy cadence, and a naturally narrow interface (Q100).

**The hard part is data**, not code. Options: shared database initially (pragmatic, couples them), database per service with an anti-corruption layer, or CDC to sync. **Splitting the database is usually the longest phase** and the one that determines whether the migration succeeds.

**What you take on** (Document 05): network failure between what used to be a function call, distributed transactions you now can't have, eventual consistency, distributed tracing as a requirement rather than a nicety, and deployment coordination. **Name these costs.**

---

## 570. Design for a small team.

**The most underrated design constraint, and the one interviewers most respect a candid answer on.**

**The principles:**

1. **Managed services over self-operated.** RDS not PostgreSQL in a StatefulSet. Hosted LLM APIs not vLLM (Q449). SQS or PostgreSQL queues not Kafka (Q215). **Every stateful system you run is a permanent tax on someone's attention.**

2. **Fewer systems.** PostgreSQL as your database, queue (`SKIP LOCKED`), vector store (pgvector), and full-text search. **One system to back up, monitor, secure, and understand** — and it gives you transactional consistency across all four for free (Q551).

3. **Boring technology.** Choose tools with large communities and abundant documentation, because you can't afford to be the person who debugs an obscure failure alone.

4. **Optimise for deletion.** Code you can delete is code you don't maintain. Prefer explicit simplicity over clever abstraction.

5. **Automate the repeated, not the hypothetical.** CI, deploys, and backups yes. A bespoke platform for a use case you might have, no.

6. **Invest in the three things that compound:** structured logging with correlation IDs, an eval suite, and a test suite. **These pay back continuously and are miserable to retrofit.**

**What to skip:** Kubernetes for a handful of services (ECS Fargate or Cloud Run), microservices, multi-region, custom infrastructure, and premature abstraction.

**The framing that lands:** *"With a small team, operational load is the binding constraint, not compute. I'd choose the architecture with the fewest things that can page someone at 3 a.m., even if it's less elegant."*

---

## 571. What would you do differently?

**This question rewards specific, honest reflection and punishes both defensiveness and performative self-criticism.**

**The structure that works:**
1. **Name one concrete thing**, not a list
2. **Say what it cost** — time, an incident, rework
3. **Say what you'd do instead**, specifically
4. **Say what you learned that generalises**

**The categories that produce genuinely good answers:**

- **Building before measuring.** "I spent two weeks tuning prompts before building a golden set. When I finally measured, 70% of failures were retrieval — the prompt work was wasted. **Now I build the eval set first, always**" (Q375, Q378).
- **Premature infrastructure.** Adding a system for scale that never arrived.
- **Missing a failure mode.** An idempotency gap, an unbounded queue, a missing timeout — and the incident that found it.
- **Under-investing in observability**, then debugging blind.
- **Coupling that made a later change expensive.**

**What makes an answer strong:** it shows you *noticed*, you *changed your behaviour*, and the lesson **generalises beyond the specific incident**. "I'd add more tests" is weak. "I'd measure before optimising, because I've now twice optimised the wrong layer" is strong.

**What to avoid:** blaming other people or constraints, claiming you'd do nothing differently (nobody believes it), or performative self-flagellation about something trivial.

**The version that closes well:** *"The thing I'd change most is the order — I built the system, then measured it. Building the measurement first would have changed what I built."*

---

*End of Document 15. Next: Document 16 — Resume defence and interviewer attack (questions 572–612).*
