# 4. FastAPI dependencies (`Depends`)

## What problem does this solve?

A lot of route handlers need the same things — a database connection, the currently authenticated user, a settings object. Without `Depends`, you'd write that boilerplate at the top of every route:

```python
@router.get("/me")
async def me(request: Request):
    pool = request.app.state.pool
    async with pool.acquire() as conn:
        token = request.headers["authorization"].removeprefix("Bearer ").strip()
        payload = decode_access_token(token)
        user = await get_user_by_id(conn, UUID(payload["sub"]))
        return UserPublic.model_validate(user)
```

Yuck. With `Depends`:

```python
@router.get("/me")
async def me(user: User = Depends(current_user)) -> UserPublic:
    return UserPublic.model_validate(user)
```

Same behavior. FastAPI ran the connection acquisition, token parsing, and user lookup behind the scenes. Your route function just declares "I need a `User`" and gets one.

## How `Depends` works, mechanically

When a request hits a route, FastAPI looks at the function signature. For each parameter declared as `param = Depends(some_func)`:

1. FastAPI inspects `some_func`'s signature, recursively. Some of `some_func`'s parameters might also be `Depends(...)`.
2. It builds a tree of dependencies for this request.
3. It calls them in order, awaiting async ones, threading their results into the next.
4. The final results are passed to your route function.
5. After the response is sent, any yield-style dependencies get cleaned up.

So `Depends(current_user)` resolves to: call `current_user`, give it whatever *it* depends on, give the result to the route.

## Walkthrough: `get_conn`

From `app/core/deps.py`:

```python
async def get_conn(request: Request) -> AsyncIterator[asyncpg.Connection]:
    pool: asyncpg.Pool = request.app.state.pool
    async with pool.acquire() as conn:
        yield conn
```

This is a **yield-based dependency** (also called a "yielding dependency"). It's an async generator that yields exactly once. FastAPI handles it like this:

```
Request arrives
    │
    ▼
FastAPI calls get_conn(request)
    │  - body runs up to `yield conn`
    │  - `async with pool.acquire()` is entered
    │  - `conn` is yielded
    ▼
FastAPI passes `conn` to your route as a parameter
    │
    ▼
Your route runs (uses conn however it wants)
    │
    ▼
Route returns / raises
    │
    ▼
FastAPI resumes get_conn past the `yield`
    │  - generator exits
    │  - exiting the function exits `async with`
    │  - connection released back to the pool
    ▼
Response goes out
```

Notice what `get_conn` is *not* doing:
- It does not start a transaction.
- It does not commit on success.
- It does not rollback on exception.
- It does not close the connection (release ≠ close — release returns it to the pool).

That's all by design. See [05-database.md](05-database.md) for why.

## Walkthrough: `current_user`

```python
async def current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    conn: asyncpg.Connection = Depends(get_conn),
) -> User:
    payload = decode_access_token(credentials.credentials)
    sub = payload.get("sub")
    if not isinstance(sub, str):
        raise InvalidTokenError()
    try:
        user_id = UUID(sub)
    except ValueError as exc:
        raise InvalidTokenError() from exc
    try:
        return await get_user_by_id(conn, user_id)
    except NotFoundError as exc:
        raise InvalidTokenError() from exc
```

`current_user` itself depends on two other things:

- `_bearer_scheme` (an `HTTPBearer` instance) — extracts the `Authorization: Bearer <token>` header. If absent, FastAPI returns 401 automatically (because we passed `auto_error=True`).
- `get_conn` — a database connection.

When a route declares `user: User = Depends(current_user)`, FastAPI:

1. Builds the dependency tree: `current_user` needs bearer credentials and a connection. The connection comes from `get_conn`, which needs the request.
2. Resolves them in order: parses the bearer header, acquires a connection, then calls `current_user`.
3. Passes the resulting `User` to the route function.

Note `current_user` itself is *not* a yield dep — it's a regular `async def` that returns a `User`. Only `get_conn` yields.

## Why a separate `current_user` instead of doing it in each route?

Three reasons:

1. **Reusable.** Every protected endpoint just does `Depends(current_user)`. No duplication.
2. **Testable.** In a test, you can override `current_user` to return a fixed test user, without going through real JWT decoding. FastAPI supports this directly (`app.dependency_overrides[current_user] = ...`).
3. **Single point of change.** When you add refresh tokens, or rotate the JWT secret, or add a "user must not be banned" check, there's exactly one function to edit.

## When does each dependency run? Caching within a request

By default, **the same `Depends(...)` object resolves once per request**. If a route depends on `get_conn`, and `current_user` (which itself depends on `get_conn`) is also a dependency of that route, FastAPI calls `get_conn` once, not twice. Both consumers get the same connection. You can opt out with `Depends(..., use_cache=False)` but you almost never want to.

This is why we can pass the connection from the route to the service to the repo without worrying about acquiring two of them — it's the same connection threaded through.

## "Why not just import the pool everywhere?"

You could write:

```python
# bad
from app.main import app

async def some_repo_function(...):
    async with app.state.pool.acquire() as conn:
        ...
```

Don't. Two reasons:

1. **Hidden dependencies are bad dependencies.** A function that quietly reaches into a global pool is harder to test (you'd have to monkeypatch the global), harder to reason about (the function signature lies — it claims to take only its declared parameters but actually depends on a global), and creates import cycles.
2. **Transaction control is impossible.** If a service wants two repo calls in one transaction, the repos need to share a connection — easy if it's a parameter, near-impossible if each repo grabs its own from a global.

Passing the connection explicitly is more verbose. That verbosity is the feature.

## Summary

- `Depends(fn)` says "before calling me, run `fn` and pass me its result."
- Yield-based deps (`async def f(...): ...; yield X`) are setup-then-teardown helpers — the code before `yield` runs at request start, the code after runs at request end.
- `get_conn` yields a pool connection that auto-releases.
- `current_user` chains `Depends` on top of `get_conn` and an HTTP bearer scheme.

## What to read next

[05-database.md](05-database.md) — what `asyncpg.Pool` actually is, what `app.state` is for, and why we don't auto-commit per request.
