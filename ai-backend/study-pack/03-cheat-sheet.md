# AI + Backend Cheat Sheet

## 1. FastAPI request mental model

```text
Client
 ↓ HTTP/TLS
Reverse proxy / LB
 ↓
Uvicorn / ASGI
 ↓
FastAPI middleware
 ↓
Dependencies / auth
 ↓
Route
 ↓
Service
 ↓
Repository
 ↓
PostgreSQL / Redis / external APIs
 ↓
Response
```

**ASGI:** interface between async Python servers and applications.  
**Uvicorn:** ASGI server.  
**FastAPI:** application framework.

### Async rule

`async` does not mean "faster."

It means an event loop can make progress on other work while the current task waits for I/O.

Classic failure:

```text
async endpoint
  ↓
time.sleep(5)
  ↓
event loop blocked
```

Python's asyncio documentation emphasizes the event loop, tasks/coroutines and cooperative scheduling for I/O-bound concurrency.

---

## 2. FastAPI: middleware vs dependency

**Middleware**
- wraps broad request/response processing
- request IDs
- timing
- global logging
- CORS

**Dependency**
- provides endpoint-specific resources
- current user
- DB session
- authorization
- reusable validation

FastAPI dependencies integrate with OpenAPI and can be sync or async.

---

## 3. BackgroundTasks vs workers

**FastAPI BackgroundTasks**
- small post-response tasks
- lightweight notifications

**External worker**
- heavy work
- long jobs
- retries
- durable state
- multiple machines
- independent scaling

A long-running agentic workflow is the worker model:

```text
POST case
 ↓
persist
 ↓
Redis queue
 ↓
return run_id
 ↓
worker
 ↓
persist progress
 ↓
SSE
```

---

## 4. PostgreSQL

### ACID

- Atomicity
- Consistency
- Isolation
- Durability

### Isolation

PostgreSQL default:

**Read Committed**

Then:

**Repeatable Read**

Then:

**Serializable**

### EXPLAIN

Use:

```sql
EXPLAIN ANALYZE ...
```

Look for:

- Seq Scan
- Index Scan
- Bitmap Scan
- Nested Loop
- Hash Join
- Sort
- estimated vs actual rows
- execution time

Core question:

> Why did PostgreSQL choose this plan?

---

## 5. Atomic payment example

Bad:

```text
SELECT balance
↓
if balance >= cost
↓
UPDATE balance
```

Two requests can read the same balance.

Better:

```sql
UPDATE wallet
SET balance = balance - :cost
WHERE user_id = :user
  AND balance >= :cost;
```

Then check affected rows.

**The condition and mutation are atomic.**

Use this story whenever asked about:

- race conditions
- transactions
- concurrency
- atomicity
- payment systems

---

## 6. Connection pooling

```text
request
 ↓
borrow connection
 ↓
query
 ↓
return connection
```

Pool too small:

**requests wait**

Pool too large:

**database gets overloaded**

A production debugging story worth having ready:

> A FastAPI service had a constrained pool *and* a synchronous DB driver blocking async
> endpoints — the pool size was the symptom, the blocking driver was the cause.

---

## 7. Redis

Good uses:

- cache
- TTL
- rate limiting
- ephemeral state
- locks
- queues/streams

Don't blindly make Redis your business source of truth.

### Cache-aside

```text
GET cache
 ↓ hit → return
 ↓ miss
DB
 ↓
set cache
 ↓
return
```

Questions:

- What if cache is stale?
- What if Redis dies?
- What if 100 requests miss at once?
- What invalidates the cache?

---

## 8. Queue semantics

**At-most-once:** may lose work.

**At-least-once:** may process twice.

**Exactly-once:** difficult end-to-end.

**Effectively-once:**

```text
at-least-once
+
idempotent processing
```

= duplicates become harmless.

### Retry

Never just say "retry."

Say:

> bounded retries + exponential backoff + jitter + retryable-error classification + dead-letter handling.

---

## 9. Redis Streams

```text
Producer
 ↓
Stream
 ↓
Consumer Group
 ├─ Worker A
 ├─ Worker B
 └─ Worker C
```

Know:

- stream ID
- consumer
- consumer group
- pending entries
- ACK
- reclaim
- ordering

Redis Streams support consumer groups and pending-entry tracking.

---

## 10. Webhooks

Reliable webhook flow:

```text
provider
 ↓
verify HMAC
 ↓
deduplicate
 ↓
validate event
 ↓
state transition
 ↓
persist
 ↓
ACK
```

Need:

- signature verification
- idempotency
- ordering/state validation
- fast response
- reconciliation

A payment-webhook story is ideal here.

---

## 11. SSE vs WebSocket

**SSE**
- server → client
- simple HTTP
- progress
- token streaming

**WebSocket**
- bidirectional
- interactive realtime

Answer:

> Choose based on communication pattern and lifecycle, not because one is universally "better."

---

# AI

## 12. LLM fundamentals

### Temperature

Sampling randomness.

Higher → generally more varied.

Lower → generally more deterministic.

**Not a length setting.**

### Structured output

```text
LLM
 ↓
schema-constrained/structured response
 ↓
validation
 ↓
business logic
```

Rule:

> probabilistic model; deterministic application boundary.

---

## 13. Tool calling

```text
LLM
 ↓
tool request
 ↓
schema validation
 ↓
authorization
 ↓
tool execution
 ↓
tool result
 ↓
LLM
```

Most important sentence:

> **The model can request an action; application code decides whether it is allowed.**

---

## 14. Agent vs workflow

**LLM call:** one model invocation.

**Workflow:** application controls sequence.

**Agent:** model participates in deciding the next action.

Your prior-auth system is best described as:

> **bounded, stateful agentic workflow**

rather than "AI magically handles everything."

---

## 15. Agent failure handling

Always ask:

1. What if model fails?
2. What if tool fails?
3. What if worker dies?
4. What if tool executes twice?

Use:

- schema validation
- bounded retries
- idempotent tools
- persisted state
- job status
- timeout
- audit log
- human approval where needed

---

## 16. MCP

MCP is useful because it standardizes how models/AI applications discover and invoke external tools/resources.

For interview purposes know:

```text
Model/application
 ↓
MCP client
 ↓
MCP server
 ↓
typed tool
 ↓
real system
```

What to be able to speak to:

**typed MCP tools + validation + structured error contracts.**

Do not claim protocol-internals expertise unless you have actually studied them.

---

# RAG

## 17. RAG pipeline

```text
documents
 ↓
parse
 ↓
chunk
 ↓
metadata
 ↓
embedding
 ↓
pgvector
 ↓
dense retrieval
 ↘
  hybrid/RRF
 ↗
lexical retrieval
 ↓
reranker
 ↓
context
 ↓
LLM
 ↓
answer + citations
```

---

## 18. Why RAG?

RAG gives the model external evidence.

But:

> RAG does not automatically eliminate hallucination.

Failure can occur at:

- ingestion
- chunking
- embedding
- retrieval
- reranking
- context construction
- generation

---

## 19. Dense vs lexical

**Dense**
- semantic meaning
- paraphrases

**Lexical**
- exact terms
- names
- codes
- rare phrases

**Hybrid**
- combine both

**RRF**
- combine rankings rather than trusting raw scores to be directly comparable.

---

## 20. Reranking

```text
query
 ↓
retrieve 20
 ↓
reranker
 ↓
top 5
```

First-stage retrieval is optimized for recall/speed.

Reranking spends more computation on a smaller candidate set.

---

## 21. pgvector

Your chosen vector stack:

**PostgreSQL + pgvector**

Not five vector databases.

Know:

- exact search
- approximate search
- HNSW
- IVFFlat
- cosine
- L2
- inner product
- filtering
- metadata indexes
- hybrid PostgreSQL search

pgvector documents exact search as the default and HNSW/IVFFlat as approximate options with different speed/recall trade-offs.

---

## 22. RAG evaluation

### Retrieval

- Hit@K
- Recall@K
- MRR

### Answer

- correctness
- groundedness
- citation correctness

### Safety

- refusal rate
- unsupported-answer rate

### System

- latency
- cost
- throughput

Golden set:

```text
answerable
+
unanswerable
+
adversarial
```

---

## 23. Hallucination reduction

Don't say:

> "Use a better prompt."

Use layers:

```text
retrieval
 ↓
grounding
 ↓
structured output
 ↓
citation
 ↓
validation
 ↓
threshold/refusal
 ↓
evaluation
```

---

## 24. AI security

Treat model output as **untrusted input**.

Know:

- prompt injection
- indirect prompt injection
- malicious RAG documents
- data leakage
- excessive tool permissions
- insecure output handling

Least privilege applies to AI tools too.

---

# Model serving

## 25. Ollama

Know:

```text
model weights
 ↓
Ollama
 ↓
local API
 ↓
application
```

You already have hands-on deployment experience.

---

## 26. vLLM

Mental model:

```text
FastAPI
 ↓
OpenAI-compatible HTTP API
 ↓
vLLM
 ↓
GPU
 ↓
model
```

Know:

- model loading
- batching
- continuous batching concept
- KV cache concept
- streaming
- GPU memory
- throughput vs latency

vLLM provides an OpenAI-compatible HTTP server, including chat-completions APIs.

---

# Infrastructure

## 27. Docker

```text
Dockerfile
 ↓
image
 ↓
container
```

Know:

- layers
- multi-stage builds
- networking
- volumes
- health checks
- environment variables

Never bake secrets into images.

---

## 28. Kubernetes

**Pod:** deployable workload unit.

**Deployment:** manages Pods/rollouts.

**Service:** stable network endpoint.

**ConfigMap:** configuration.

**Secret:** sensitive configuration.

**Readiness:** should receive traffic?

**Liveness:** is process alive?

You only need operational competence for this target, not Kubernetes administration.

---

## 29. AWS

A practical single-server architecture:

```text
Internet
 ↓
Nginx/TLS
 ↓
EC2
 ↓
FastAPI
 ├── RDS/PostgreSQL
 └── Redis

S3 ← files
IAM ← permissions
SSM ← server management
```

Be exact about what you personally configured.

Do not claim Terraform expertise.

---

# System design

Always answer:

1. Requirements
2. Scale
3. APIs
4. Data model
5. Main flow
6. Failure modes
7. Consistency
8. Idempotency
9. Scaling
10. Observability
11. Security
12. Trade-off
13. Cost/complexity

The key phrase:

> **Every design decision has a cost.**

Avoid:

> "Just add Redis."

Say:

> "I'd add Redis here because X; the cost is cache invalidation and an additional failure dependency."

---

# Six production-story shapes to prepare

Have one story of your own for each shape. Aim for a spread — six variations of the same bug
is a thin interview. For each, be able to give: symptom → what made it hard → how you narrowed
it → root cause → verification → prevention.

## 1. A concurrency bug
Read-then-write race on a balance or counter → fixed with an atomic conditional UPDATE.

## 2. A payment or webhook integration
Signature verification + state machine + reconciliation for missed or duplicated events.

## 3. A long-running pipeline
Work that exceeds an HTTP budget → queue + worker + run ID + persisted state + SSE progress.

## 4. A blocking-call bug
Sync I/O inside an async endpoint → event-loop starvation → diagnosis and fix.

## 5. An auth failure
A token/identity assumption that held in testing and broke in production → root cause and fix.

## 6. A large idempotent sync
High per-user record volume → deterministic IDs + idempotent upsert + a cursor invariant.

---

# Five dangerous interview phrases

Avoid:

- "I'll use Redis."
- "I'll add a queue."
- "We'll scale horizontally."
- "RAG prevents hallucinations."
- "We'll use an agent."

Replace with:

> **problem → reason → architecture → failure → trade-off**

Example:

> "The job can exceed the HTTP request budget, so I enqueue it, return a run ID, persist state in PostgreSQL, and stream progress through SSE. The trade-off is worker/queue complexity and the need to handle duplicate delivery."

