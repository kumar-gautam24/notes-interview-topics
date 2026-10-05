# Python for Backend Engineers

Python taught from zero up to what a FastAPI backend actually needs: OOP, the object model,
concurrency (threads, async, the GIL), imports, DB lifecycle and production serving.
Comparisons to Dart/Java are called out along the way. Read in order.

| # | File | What it covers |
|---|------|----------------|
| 1 | [01-python-and-oop-from-zero.md](01-python-and-oop-from-zero.md) | Syntax, collections, functions, classes, dunders, decorators, context managers, imports/venv, `async`/`await` — mapped to where each shows up in FastAPI |
| 2 | [02-oop-pillars-constructors-overloading.md](02-oop-pillars-constructors-overloading.md) | The four pillars Python-style, what runs when, constructors, comparing objects, overloading, composition vs inheritance, SOLID |
| 3 | [03-classes-and-concurrency-deep-dive.md](03-classes-and-concurrency-deep-dive.md) | What `ClassName(...)` really does, object lifetimes in FastAPI, threads, async in depth, shared-state bugs across workers, CPU-heavy work |
| 4 | [04-backend-foundations-imports-db-production.md](04-backend-foundations-imports-db-production.md) | How `import` works, the execution model, DB lifecycle and race conditions, pip/uv/Poetry, Gunicorn+Uvicorn, production at scale, interview Q&A |

## Where to go next

- **FastAPI:** [`backend/fastapi-from-scratch/`](../backend/fastapi-from-scratch) — Part 1 → Part 2 → build a real project.
- **See the concurrency ideas break under load:** [`labs/scaling-lab/`](../labs/scaling-lab) — `/cpu/bad`, `/io/bad` and `/cpu/threadpool` are section 9–12 of note 3, measured.
- Shorter / interview-shaped: [`ai-backend/answers/01-python.md`](../ai-backend/answers/01-python.md) · [`fundamentals/oop-concepts.md`](../fundamentals/oop-concepts.md).
