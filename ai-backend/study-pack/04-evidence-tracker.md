# Hands-On Evidence Tracker

## Status scale

- [ ] L1 — can define
- [ ] L2 — can explain mental model
- [ ] L3 — can implement
- [ ] L4 — can break/debug
- [ ] L5 — can explain trade-offs
- [ ] L6 — interview-ready

---

# Backend

| Topic | Target | Evidence / project |
|---|---:|---|
| Python async/await | L6 | |
| Event loop | L6 | |
| FastAPI lifecycle | L6 | |
| Middleware | L5 | |
| Dependencies/DI | L5 | |
| Error handling | L5 | |
| PostgreSQL indexes | L6 | |
| EXPLAIN ANALYZE | L6 | |
| Transactions | L6 | |
| Isolation levels | L5 | |
| Locks/deadlocks | L5 | |
| Connection pooling | L6 | |
| Migrations | L5 | |
| pytest | L5 | |
| Redis cache | L5 | |
| Redis Streams | L5 | |
| Queues/workers | L6 | |
| Retry/backoff/jitter | L6 | |
| Idempotency | L6 | |
| Event ordering | L5 | |
| Rate limiting | L5 | |
| Observability | L5 | |
| Docker | L5 | |
| AWS EC2/RDS/S3/IAM/SSM | L5 | |
| System design | L5 | |

# AI

| Topic | Target | Evidence / project |
|---|---:|---|
| Tokens/context | L5 | |
| Temperature/sampling | L5 | |
| Structured outputs | L6 | |
| Tool calling | L6 | |
| Tool authorization | L5 | |
| Agent loops | L6 | |
| State machines | L6 | |
| Durable agent state | L5 | |
| MCP | L5 | |
| Streaming | L5 | |
| RAG architecture | L6 | |
| Chunking | L5 | |
| Embeddings | L5 | |
| pgvector | L6 | |
| HNSW | L5 | |
| IVFFlat | L4 | |
| Hybrid retrieval | L5 | |
| RRF | L5 | |
| Reranking | L5 | |
| Golden sets | L6 | |
| Hit@K | L5 | |
| MRR | L5 | |
| Groundedness | L5 | |
| Refusal thresholds | L5 | |
| Prompt injection | L5 | |
| AI tool security | L5 | |
| Ollama | L5 | |
| Hugging Face | L4 | |
| vLLM | L5 | |
| KV cache | L4 | |
| Continuous batching | L4 | |
| Kubernetes model serving | L4 | |

---

# Lab 1 — Reliable Job Service

Build:

```text
FastAPI
  ↓
POST /jobs
  ↓
PostgreSQL job record
  ↓
Redis queue
  ↓
Worker
  ↓
PostgreSQL result
  ↓
SSE progress
```

Must test:

- duplicate job
- worker death
- DB failure
- Redis failure
- timeout
- client disconnect

Must explain:

- why queue
- why run ID
- why SSE
- retry semantics
- idempotency

---

# Lab 2 — Payment Simulator

Build:

- order
- payment
- webhook
- refund
- reconciliation

Implement:

- idempotency key
- HMAC
- state machine
- atomic balance deduction
- duplicate webhook protection
- out-of-order event handling

Failure tests:

- duplicate webhook
- missing webhook
- out-of-order webhook
- concurrent spending
- crash after commit
- client retry

---

# Lab 3 — RAG

Use 50–200 public documents.

Pipeline:

```text
parse
→ chunk
→ metadata
→ embed
→ pgvector
→ lexical retrieval
→ RRF
→ rerank
→ answer
→ citation
```

Golden set:

- 50 answerable
- 20 unanswerable
- 10 adversarial

Measure:

- Hit@5
- Recall@5
- MRR
- answer correctness
- groundedness
- citation correctness
- refusal rate
- latency/cost

---

# Lab 4 — Agentic Workflow

Build:

```text
POST /runs
GET /runs/{id}
GET /runs/{id}/events
```

Workflow:

```text
input
 ↓
LLM
 ↓
tool decision
 ↓
validate
 ↓
authorize
 ↓
execute
 ↓
persist
 ↓
next turn
```

Add:

- max turns
- tool timeout
- retry
- idempotency
- audit events
- SSE
- human approval for a dangerous tool

---

# Lab 5 — Model Serving

Run:

```text
FastAPI
 ↓
OpenAI-compatible client
 ↓
Ollama
```

Then:

```text
FastAPI
 ↓
vLLM
 ↓
model
```

Measure:

- latency
- tokens/sec
- concurrent requests
- memory
- failure behavior

Then deploy a basic version in Kubernetes.

---

# Daily proof log

## Date

### I learned
1.
2.
3.

### I built
1.
2.

### I deliberately broke
1.
2.

### I fixed
1.
2.

### I can explain
1.
2.
3.

### Questions I could not answer
- 
- 
- 

### Resume impact
What can now be added to the resume and defended under follow-up?

---

# Final readiness gate

Before you start interviewing, you should be able to:

- build FastAPI without a tutorial
- write non-trivial SQL
- explain transactions/isolation
- read EXPLAIN ANALYZE
- explain Redis queue semantics
- design idempotent workers
- defend a payment/webhook architecture end to end
- defend a multi-turn agentic workflow end to end
- build RAG with pgvector
- evaluate retrieval
- explain why RAG can still hallucinate
- explain tool-calling security
- explain vLLM conceptually and operate a basic local server
- deploy Dockerized FastAPI
- explain your AWS architecture
- design a backend system
- defend every line of the resume

If an answer becomes:

> "Claude Code handled that."

the topic is not green yet.

---

# Source shelf

Use official docs first:

- FastAPI — https://fastapi.tiangolo.com/tutorial/
- Python asyncio — https://docs.python.org/3/library/asyncio.html
- PostgreSQL — https://www.postgresql.org/docs/current/
- Redis — https://redis.io/docs/
- Docker — https://docs.docker.com/get-started/
- Kubernetes — https://kubernetes.io/docs/concepts/
- pgvector — https://github.com/pgvector/pgvector
- vLLM — https://docs.vllm.ai/
- OWASP GenAI Security — https://genai.owasp.org/
