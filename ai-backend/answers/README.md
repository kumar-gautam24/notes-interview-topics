# AI + Backend Answer Bank

Worked answers to 612 interview questions, split into 16 documents by topic. The companion
question list lives in [`../study-pack/02-question-bank.md`](../study-pack/02-question-bank.md).

Every answer follows the same shape:

> **definition → why it exists → how it's implemented → how it fails → the trade-off → a concrete example**

The "how it fails" step is the one that matters in interviews. Answers cross-reference each other
by question number (e.g. "see Q317"), so the numbering is load-bearing — keep it intact.

## The documents

| Document | Topic | Questions |
|---|---|---|
| [01-python.md](01-python.md) | Python | 1–45 |
| [02-fastapi-asgi.md](02-fastapi-asgi.md) | FastAPI / ASGI | 46–100 |
| [03-postgresql-sql.md](03-postgresql-sql.md) | PostgreSQL / SQL | 101–170 |
| [04-redis-queues.md](04-redis-queues.md) | Redis / queues | 171–215 |
| [05-distributed-systems.md](05-distributed-systems.md) | Distributed systems | 216–262 |
| [06-llm-fundamentals.md](06-llm-fundamentals.md) | LLM fundamentals | 263–290 |
| [07-agents-mcp.md](07-agents-mcp.md) | Agents / MCP / tool calling | 291–339 |
| [08-rag.md](08-rag.md) | RAG | 340–393 |
| [09-pgvector.md](09-pgvector.md) | pgvector | 394–417 |
| [10-evaluation.md](10-evaluation.md) | Evaluation | 418–440 |
| [11-model-serving.md](11-model-serving.md) | Model serving | 441–469 |
| [12-docker-k8s-aws.md](12-docker-k8s-aws.md) | Docker / Kubernetes / AWS | 470–504 |
| [13-security.md](13-security.md) | Security | 505–528 |
| [14-observability.md](14-observability.md) | Observability | 529–547 |
| [15-system-design.md](15-system-design.md) | System design (24 design prompts) | 548–571 |
| [16-resume-defence.md](16-resume-defence.md) | Resume defence + interviewer pressure | 572–612 |

## Reading order

Not sequential — work through it in five tiers.

1. **Foundations** — [01 Python](01-python.md) → [03 PostgreSQL](03-postgresql-sql.md) → [06 LLM fundamentals](06-llm-fundamentals.md)
2. **Engineering layer** — [02 FastAPI](02-fastapi-asgi.md) → [04 Redis/queues](04-redis-queues.md) → [05 Distributed systems](05-distributed-systems.md)
3. **AI layer** — [08 RAG](08-rag.md) → [09 pgvector](09-pgvector.md) → [07 Agents/MCP](07-agents-mcp.md) → [10 Evaluation](10-evaluation.md)
4. **Operational layer** — [11 Model serving](11-model-serving.md) → [12 Docker/K8s/AWS](12-docker-k8s-aws.md) → [13 Security](13-security.md) → [14 Observability](14-observability.md)
5. **Synthesis** — [15 System design](15-system-design.md) → [16 Resume defence](16-resume-defence.md)

Tier 2 is the highest-leverage section in the bank — it's where most mid-level interviews are
actually won or lost.

## A note on the worked examples

Several answers use `[bracketed placeholders]` where a real project detail belongs. Substitute
your own systems, numbers, and incidents — an answer built on someone else's example collapses
on the first follow-up.
