# Learning notes

Short, focused explanations of the concepts used in this codebase. Read in order — each one assumes the previous.

| # | File | What it covers | Why first |
|---|------|----------------|-----------|
| 1 | [01-overview.md](01-overview.md) | The big picture: what FastAPI does, what happens when a request arrives, mental model | Set the frame before any details |
| 2 | [02-layers.md](02-layers.md) | What each folder/layer does, how a request flows through them, models vs schemas | The structural rules everything else lives inside |
| 3 | [03-async-and-context-managers.md](03-async-and-context-managers.md) | `async`/`await`, the event loop, `with` / `async with`, generators, `lifespan` | You can't read this codebase without these |
| 4 | [04-fastapi-deps.md](04-fastapi-deps.md) | What `Depends(...)` is, the `yield`-based dependency pattern, `get_conn` and `current_user` walkthrough | Half the file calls in `app/api/routes/` use `Depends` |
| 5 | [05-database.md](05-database.md) | What a connection pool is, `asyncpg.Pool`, `app.state`, why we don't auto-commit per request, when to use transactions | Answers your "shouldn't deps have rollback in finally?" question |
| 6 | [06-auth-and-jwt.md](06-auth-and-jwt.md) | What a JWT is, what `sub`/`iat`/`exp` mean, HTTP Bearer, the full signup → login → /me flow | Auth touches every protected endpoint |
| 7 | [07-errors.md](07-errors.md) | Why routes never `try/except`, the `AppError` tree, the global handler | The cleanest part of the codebase, easy to miss why |

These are learning notes, not API reference. They'll go stale if the code changes — when you find a mismatch, trust the code and update the note.
