# 1. Overview — what is this codebase?

## What FastAPI is, in one paragraph

FastAPI is a Python web framework. You define functions (Python functions, decorated with `@router.get(...)` or `@router.post(...)`) and FastAPI turns them into HTTP endpoints. When a request comes in, FastAPI:

1. Matches the URL + method to one of your functions.
2. Reads the request body, validates it against a Pydantic schema, hands you a typed object.
3. Resolves any dependencies the function declared (`Depends(...)`).
4. Calls your function. Awaits the result.
5. Validates the return value against the response schema.
6. Serializes it to JSON and returns the HTTP response.

Everything in this codebase is wired around step 4 — your function — staying small and pushing real work into other layers.

## A Flutter analogy that maps well

| Flutter concept | Backend equivalent here |
|-----------------|-------------------------|
| `main.dart`, runApp, app shell | `app/main.py` — assembles the FastAPI app |
| `MaterialApp` route table | FastAPI routers (`app/api/routes/*.py`) |
| Widget tree handling user input | A route function handling a request |
| BLoC / Riverpod provider | A service in `app/services/` |
| Repository / data source | A repository in `app/repositories/` |
| Model class (DTO) | `app/models/user.py` (domain) + `app/schemas/user.py` (over-the-wire) |
| `Future<T>` / `async`/`await` | Same syntax in Python — see [03-async-and-context-managers.md](03-async-and-context-managers.md) |
| `runApp(MyApp())` | `uvicorn app.main:app --reload` |

Two big differences worth holding in your head:

- **Backend is request-driven, not state-driven.** No widget rebuilds, no streams pushing updates. Each HTTP request is a one-shot: a function runs, returns a value, the function exits. There's no app-level "current screen."
- **Multiple users hit the same process simultaneously.** A signup request from user A and a login from user B can be in flight at the same time. The codebase has to be safe under concurrency. That's a big part of why we use `async` and a connection *pool* (not one connection).

## The request flow, end-to-end

Take `POST /auth/signup` with body `{"email": "you@example.com", "password": "hunter222"}`.

```
HTTP request
   │
   ▼
Uvicorn (the server)         ← parses HTTP, hands an ASGI message to FastAPI
   │
   ▼
FastAPI app (app/main.py)
   │
   ▼
Router match → app/api/routes/auth.py @router.post("/signup")
   │
   ├─ Validates JSON body against SignupRequest (app/schemas/auth.py)
   ├─ Resolves Depends(get_conn) → acquires asyncpg.Connection from pool
   │
   ▼
auth_service.signup(conn, email=..., password=...)   (app/services/auth_service.py)
   │
   ├─ Lowercases email
   ├─ Hashes password with argon2
   │
   ▼
user_repository.insert_user(conn, ...)                (app/repositories/user_repository.py)
   │
   └─ Runs INSERT ... RETURNING ... via asyncpg
   │
   ▼  Returns User domain model
service returns the User to the route
   │
   ▼
Route converts User → UserPublic (app/schemas/user.py)
   │
   ▼
FastAPI serializes UserPublic to JSON, returns 201 Created
   │
   ▼
Connection released back to pool (because the get_conn context manager exits)
```

Five files cooperate to handle one request, but each does one thing:
- **Router** — HTTP shape only (parse, validate, return).
- **Service** — business rules (lowercase email, hash password).
- **Repository** — SQL only.
- **Schemas** — what the wire looks like.
- **Models** — what the row looks like in memory.

If you ever feel a function in this codebase is doing two of those jobs, it's a smell.

## "Why so many folders?"

Because the alternative — one file per endpoint with SQL, business logic, password hashing, and JSON serialization mashed together — works for 5 endpoints and falls apart at 50. Layered code is intentionally redundant up front so it stays readable as the project grows. You'll feel the cost on day one and the benefit on day thirty.

## What to read next

[02-layers.md](02-layers.md) — what each layer is allowed to do and what it is not.
