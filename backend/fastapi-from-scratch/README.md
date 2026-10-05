# FastAPI from Scratch

A generic, project-agnostic FastAPI track: concepts → a production-shaped service → building a
full project milestone by milestone. (For notes tied to one specific codebase, see
[`../fastapi-course/`](../fastapi-course); for a real payments service, see
[`../case-study-payment-svc/`](../case-study-payment-svc).)

**Prerequisite:** comfortable Python — see [`python/`](../../python) if not.

| # | File | What it covers |
|---|------|----------------|
| 1 | [01-core-concepts.md](01-core-concepts.md) | Path/query params, bodies & response models, status codes, `Depends`, cookies/forms/files, `APIRouter`, how a request flows |
| 2 | [02-building-a-real-service.md](02-building-a-real-service.md) | Settings, SQLAlchemy, middleware/CORS/logging, lifespan & background tasks, testing, deployment, production checklist |
| 3 | [03-build-to-learn-tasks-api.md](03-build-to-learn-tasks-api.md) | Build a tasks API in 10 milestones: in-memory CRUD → Postgres, migrations & layers → cookie auth → filtering, pagination & errors → testing → async calls & webhooks → observability & rate limiting → Docker, CI & deploy |

## Related

- **Auth deep dive** (used in milestone 3): [`../auth/httponly-cookies-vs-localstorage.md`](../auth/httponly-cookies-vs-localstorage.md)
- **Measure it under load:** [`labs/scaling-lab/`](../../labs/scaling-lab)
- **Ship it:** [`deployment-devops/`](../../deployment-devops) — Docker, then Kubernetes / [AKS course](../../deployment-devops/kubernetes/aks-course)
