# 30-Day AI + Backend Roadmap

## Objective

A four-week plan to get genuinely interview-ready for mid-level (roughly 2–4 YOE) AI/backend
roles — not to fake seniority, but to turn practical experience into answers that survive
three rounds of "why?".

**It assumes you already have** working experience with Python/FastAPI, PostgreSQL, Redis,
queues and workers, webhooks and payments, auth, SSE, and deploying on AWS — plus some hands-on
LLM work (tool calling, structured outputs, MCP, local inference).

**It goes deliberately deep on** AsyncIO internals, PostgreSQL internals, queue failure
semantics, testing, system design, RAG/pgvector, retrieval evaluation, AI security, vLLM
operations, and Docker/AWS architecture.

**A note on scope:** don't claim a technology on your resume that you can't defend
independently — including anything an AI coding tool generated for you. Day 30 is about exactly
that filter.

---

# Final target profile

### Master
**Software Engineer — Backend & AI Systems**

### Backend
**Python / FastAPI Backend Engineer**

Python → FastAPI → Pydantic → AsyncIO → PostgreSQL → Redis → queues/workers → transactions → idempotency → Docker → AWS → observability → testing → system design.

### AI
**AI Engineer / AI Backend Engineer**

LLMs → structured outputs → tool calling → agentic workflows → MCP → RAG → embeddings → pgvector → hybrid retrieval → reranking → evaluation → streaming → workers → model serving.

---

# Skill priority

| Topic | 30-day target |
|---|---|
| Python | Interview-strong |
| FastAPI/Pydantic | Deep |
| PostgreSQL/SQL | Deep internals |
| AsyncIO | Deep |
| Redis | Deep |
| Queues/workers | Deep failure semantics |
| Transactions/idempotency | Expert for YOE |
| Testing/pytest | Strong |
| Docker | Strong |
| AWS | Strong architecture |
| Observability | Strong |
| System design | Interview-ready |
| LLM fundamentals | Deep |
| Tool calling/agents | Deep |
| MCP | Strong conceptual |
| RAG | Build from scratch |
| pgvector | Build + tune |
| Hybrid/RRF/reranking | Implement + evaluate |
| Evaluation | Golden set + metrics + CI |
| Ollama | Strong |
| vLLM | Hands-on local |
| Kubernetes | Basic operational |
| AI security | Strong fundamentals |

---

# Rules

A skill is not "done" because you watched a tutorial.

Use five levels:

**L1:** define it  
**L2:** explain why/how  
**L3:** implement it  
**L4:** break/debug it  
**L5:** explain trade-offs under interview pressure

Resume-worthy skills should normally reach L4–L5.

Daily rhythm for a full study day:

- 2h learning
- 3h building
- 1.5h deliberately breaking/debugging
- 1.5h interview questions aloud
- 30m written recall

---

# WEEK 1 — FastAPI + AsyncIO + PostgreSQL

## Day 1 — ASGI/FastAPI lifecycle

Learn:
- HTTP lifecycle
- ASGI
- Uvicorn
- Starlette
- middleware
- dependency injection
- request/response validation
- exception handling
- workers/processes

Build a FastAPI service with request ID middleware, timing middleware, dependencies, custom exceptions.

Interview gate:

`client → HTTP → Uvicorn → ASGI → middleware → dependency → route → response`

Resource: https://fastapi.tiangolo.com/tutorial/

## Day 2 — AsyncIO

Learn:
- event loop
- coroutine
- task
- await
- cooperative scheduling
- cancellation
- timeout
- semaphore
- asyncio.Queue
- blocking vs non-blocking I/O
- threads vs processes

Build blocking vs async endpoints and compare under concurrency.

Deliberately put `time.sleep()` and a blocking DB call inside an async endpoint.

The classic production story here: a FastAPI service where a synchronous DB driver silently blocked async endpoints.

Resource: https://docs.python.org/3/library/asyncio.html

## Day 3 — Middleware, DI, errors

Build:
- auth dependency
- DB dependency
- request ID
- centralized error schema
- exception handlers

Understand middleware vs dependency.

Resource: https://fastapi.tiangolo.com/tutorial/dependencies/

## Day 4 — PostgreSQL indexes + EXPLAIN

Learn:
- B-tree
- sequential scan
- index scan
- bitmap scan
- composite indexes
- selectivity/cardinality
- query planner
- EXPLAIN/ANALYZE
- cursor vs offset pagination

Create 1M+ rows and compare indexed/unindexed queries.

Resource: https://www.postgresql.org/docs/current/using-explain.html

## Day 5 — Transactions/isolation

Learn:
- ACID
- Read Committed
- Repeatable Read
- Serializable
- MVCC
- row locks
- `FOR UPDATE`
- lost update
- deadlocks

Rebuild a payment-wallet debit under a concurrency test.

Key interview story:

**read-check-write is unsafe; atomic conditional UPDATE protects the invariant.**

Resource: https://www.postgresql.org/docs/current/transaction-iso.html

## Day 6 — Pooling, migrations, pytest

Learn:
- connection pool
- pool exhaustion
- transaction lifetime
- migration discipline
- unit/integration tests
- mocks/stubs

Deliberately cap pool size and load the API.

## Day 7 — Week 1 exam

No tutorials.

Build one mini service:

**FastAPI + PostgreSQL + auth + middleware + transaction + tests**

Then answer 40 L1–L3 questions aloud.

---

# WEEK 2 — Redis + queues + distributed systems

## Day 8 — Redis

Learn:
- strings/hashes/sets/sorted sets
- TTL
- atomic operations
- cache-aside
- rate limiting
- locks
- Pub/Sub vs Streams

Your real examples: Redis auth lockout and Redis workers.

Resource: https://redis.io/docs/

## Day 9 — Queue/worker architecture

Build:

`POST /jobs → persist job → enqueue → return run_id → worker → PostgreSQL → SSE`

Learn:
- producer/consumer
- ack
- retries
- at-most-once
- at-least-once
- effectively-once
- dead-letter queues
- poison messages

## Day 10 — Failure semantics

Break:
- worker before DB commit
- worker after DB commit
- duplicate delivery
- job timeout
- DB unavailable
- Redis unavailable

Make duplicate processing harmless.

## Day 11 — Redis Streams

Learn:
- stream IDs
- consumer groups
- pending entries
- XREADGROUP
- XACK
- reclaiming abandoned work
- ordering

Resource: https://redis.io/docs/latest/develop/data-types/streams/

## Day 12 — Caching/rate limiting

Implement:
- cache-aside
- TTL
- invalidation
- token-bucket style rate limiter

Be ready for cache stampede, stale data, Redis outage.

## Day 13 — Distributed systems

Learn:
- CAP
- eventual consistency
- retry/backoff/jitter
- idempotency
- ordering
- duplicate delivery
- distributed locks
- circuit breakers
- backpressure
- outbox pattern

Use a payment-webhook handler and a large data-sync job as your worked examples.

## Day 14 — System design exam

Design:
1. payment webhook processor
2. notification queue
3. long-running AI job service
4. file processing system
5. rate limiter

Every design must include:

**requirements → API → DB → flow → failure → consistency → scaling → observability → security → trade-off**

---

# WEEK 3 — AI Engineering

## Day 15 — LLM fundamentals

Learn:
- tokens
- context window
- system/user/tool messages
- temperature
- top-p
- structured output
- streaming
- sessions
- latency/cost
- model selection

Connect to your Gemma app and 36–40-turn workflow.

## Day 16 — Tool calling

Build:

`LLM → tool decision → schema validation → authorization → execution → tool result → LLM`

Use a multi-tool assistant (20+ tools) as the mental model.

Rule:

**The model can request an action; application code decides whether it is allowed.**

## Day 17 — Agents

Learn:
- workflow vs agent
- state machine
- bounded loops
- turn manager
- termination
- persisted state
- tool budgets
- human-in-the-loop
- retries

Be able to draw a multi-phase agentic workflow — phases, turn budget, tool boundaries — from memory.

## Day 18 — RAG from scratch

Build:

`documents → chunks → embeddings → pgvector → similarity search → top-k → LLM`

Learn:
- embeddings
- cosine/L2/dot product
- chunking
- metadata
- top-k

## Day 19 — Retrieval quality

Implement and compare:

1. dense
2. lexical
3. hybrid
4. hybrid + RRF
5. reranking

Learn:
- BM25 intuition
- RRF
- cross-encoder
- metadata filtering

Resource: https://github.com/pgvector/pgvector

## Day 20 — Evaluation

Create a golden set:
- 50 answerable
- 20 unanswerable
- 10 adversarial

Measure:
- Hit@K
- Recall@K
- MRR
- correctness
- groundedness
- citation correctness
- refusal rate
- latency/cost

Put evaluation in CI.

## Day 21 — Hallucination + AI security

Learn:
- prompt injection
- indirect injection
- malicious documents
- RAG poisoning
- tool abuse
- data leakage
- output validation
- refusal thresholds

Resource: https://genai.owasp.org/

## Day 22 — Model serving

Hands-on:
- Ollama
- Hugging Face model weights/gating/licensing
- OpenAI-compatible APIs
- vLLM
- batching
- continuous batching concept
- KV cache concept
- GPU memory
- throughput vs latency

Resource: https://docs.vllm.ai/

## Day 23 — Kubernetes model serving

Deploy a basic model service.

Know:
- Pod
- Deployment
- Service
- ConfigMap
- Secret
- volume
- readiness
- liveness
- resource requests/limits

Resource: https://kubernetes.io/docs/concepts/

---

# WEEK 4 — Production + interview

## Day 24 — Docker

Build Docker Compose:

`FastAPI + PostgreSQL + Redis + worker`

Learn:
- image
- container
- Dockerfile
- layers
- multi-stage builds
- networking
- volumes
- health checks

Resource: https://docs.docker.com/get-started/

## Day 25 — AWS

You already used EC2/RDS/S3/IAM/SSM.

Deepen:
- security groups
- public/private subnet concept
- IAM roles
- RDS vs PostgreSQL on EC2
- S3 presigned URLs
- SSM
- secrets
- logging

Draw your own project's deployment topology from memory.

## Day 26 — Observability/debugging

Learn:
- logs
- metrics
- traces
- request IDs
- p50/p95/p99
- throughput
- saturation
- SLI/SLO

Prepare six production stories from your own history. Aim for a spread rather than six of
the same kind — for example: a configuration mistake, an auth/login failure, a data-model bug
with a security consequence, a concurrency or blocking bug, a capacity limit you hit, and a
latency win you measured. For each: symptom → what made it hard → how you narrowed it →
root cause → verification → what you changed to prevent it.

## Day 27 — Security

Backend:
- authn/authz
- JWT
- refresh tokens
- RBAC
- SQL injection
- SSRF
- secrets
- webhook verification
- tenant isolation

AI:
- prompt injection
- tool authorization
- data leakage
- RAG poisoning
- output validation

## Day 28 — System design

Design from scratch:
1. prior authorization AI
2. RAG assistant
3. payment system
4. notification system
5. file processing
6. multi-tenant backend

## Day 29 — Full mock interviews

Six rounds:
- Python/FastAPI
- SQL/PostgreSQL
- Redis/distributed systems
- AI/LLM/RAG
- system design
- resume deep dive

## Day 30 — Resume defense

For every resume line answer:

1. What is it?
2. Why did you use it?
3. How did you implement it?
4. What failed?
5. What alternative existed?
6. What trade-off?
7. What happens at 10x scale?

If you cannot defend it, downgrade or remove it.

---

# Resources — use, don't binge

Primary resources should be official docs:

- FastAPI: https://fastapi.tiangolo.com/tutorial/
- Python asyncio: https://docs.python.org/3/library/asyncio.html
- PostgreSQL: https://www.postgresql.org/docs/current/
- Redis: https://redis.io/docs/
- Docker: https://docs.docker.com/get-started/
- Kubernetes: https://kubernetes.io/docs/concepts/
- pgvector: https://github.com/pgvector/pgvector
- vLLM: https://docs.vllm.ai/
- OWASP GenAI: https://genai.owasp.org/

Use one resource for a topic, then build. Do not open ten courses for the same concept.

---

# Explicitly deprioritized

Do NOT spend this 30-day block on:
- becoming a LangChain expert
- LangGraph internals
- CrewAI/AutoGen
- five vector databases
- deep Kafka
- Terraform
- Go
- advanced Kubernetes administration
- training LLMs from scratch
- ML research mathematics

The target is **backend + AI engineering depth**, not tool-count.
