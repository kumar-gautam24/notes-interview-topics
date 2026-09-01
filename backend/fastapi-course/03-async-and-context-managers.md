# 3. async, await, and context managers

This is the foundation. Once these click, the rest of the codebase reads naturally.

## Sync vs async — the mental model

A normal Python function blocks. When it calls `time.sleep(2)` or `requests.get(...)`, the entire process sits there for 2 seconds, doing nothing useful while it waits.

An **async function** can pause. When it `await`s something slow, it tells the runtime "I'm waiting on this; go do something else and wake me when it's ready." The runtime — called the **event loop** — keeps a queue of paused coroutines and resumes whichever one is ready next.

```python
import asyncio

async def fetch_user():
    await asyncio.sleep(1)   # pause here, let the loop do other work
    return "alice"

async def fetch_posts():
    await asyncio.sleep(1)
    return ["post1", "post2"]

async def main():
    # Run both at the same time. Total wall-clock time: ~1 second, not 2.
    user, posts = await asyncio.gather(fetch_user(), fetch_posts())
```

In Flutter terms: `async` in Python is essentially the same as `async`/`await` in Dart. `Future<T>` ↔ `Coroutine[..., ..., T]`. The `await` keyword pauses; the runtime resumes when ready.

### Why we use it for a web server

A web server spends >99% of its time waiting on I/O — waiting on the database, waiting on network, waiting on disk. With sync code, while one request is waiting on the database, the whole process can't serve another request. With async code, that thread can serve hundreds of requests concurrently as long as no single one does CPU-heavy work.

**Rule of thumb in this codebase:** anything that touches the network, the database, or disk must be `async`. Anything CPU-only (string formatting, math) can be sync. We never call a blocking library (`time.sleep`, `requests`, blocking `psycopg2`) — they would freeze the entire server.

### `async def` vs `def`

```python
async def signup(...):    # a coroutine; returns when awaited
def hash_password(...):   # a normal function; runs to completion
```

You can call an async function from another async function with `await`. You cannot directly call an async function from a sync function (you'd get back a coroutine object, not the result). FastAPI handles the entry into async-land for you — it `await`s your route handler.

## Context managers (`with`)

A context manager is "set up something, run a block, tear it down — even if an exception happens." The classic example:

```python
with open("file.txt") as f:
    data = f.read()
# file is closed here, whether read() succeeded or threw
```

The equivalent without a context manager would be:

```python
f = open("file.txt")
try:
    data = f.read()
finally:
    f.close()
```

Same behavior. The `with` form is just shorter and impossible to get wrong.

## Async context managers (`async with`)

Same idea, but the setup and teardown can themselves be async. From `app/api/routes/health.py`:

```python
async with pool.acquire() as conn:
    await conn.fetchval("SELECT 1")
# connection released back to the pool here
```

`pool.acquire()` returns an *async* context manager. On entry, it `await`s a free connection from the pool. On exit, it releases it back. The `async with` block guarantees release even if `fetchval` raises.

This is the same `try/finally` pattern, just sugar.

## Generators (`yield`)

A generator is a function that pauses and resumes at each `yield`:

```python
def counter():
    yield 1
    yield 2
    yield 3

for n in counter():
    print(n)   # 1, then 2, then 3
```

The function body runs up to the first `yield`, hands the value to the caller, then *pauses*. When the caller asks for the next value, the function body resumes from where it paused. This is the same mechanism FastAPI uses for "yield-based dependencies" (see [04-fastapi-deps.md](04-fastapi-deps.md)).

## Async generators

Generators that are also async:

```python
async def get_conn(request: Request) -> AsyncIterator[asyncpg.Connection]:
    pool: asyncpg.Pool = request.app.state.pool
    async with pool.acquire() as conn:
        yield conn
```

Read this top to bottom:

1. The function gets called.
2. It looks up the pool from app state.
3. It enters `async with pool.acquire() as conn` — awaits a connection.
4. It hits `yield conn` — pauses here, hands the connection to the caller (FastAPI).
5. The caller (FastAPI) uses the connection during the request.
6. When the request ends, FastAPI signals the generator to resume.
7. Execution continues past the `yield`. There's nothing after it, so the function exits.
8. **Exiting the function exits the `async with` block** — connection is released back to the pool.

That `async with ... yield` pattern is the FastAPI equivalent of:

```python
conn = acquire_from_pool()
try:
    yield conn   # request handler runs while paused here
finally:
    release_to_pool(conn)
```

So the answer to "shouldn't deps have try/yield/finally close?" — yes, that's the standard pattern, and `get_conn` is doing exactly that. The `async with` IS the try/finally; we just spell it with a context manager because asyncpg gives us one for free. (More on this in [05-database.md](05-database.md).)

## `@asynccontextmanager` — turning an async generator into a context manager

Look at `app/main.py`:

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    pool = await create_pool()
    app.state.pool = pool
    try:
        yield                # FastAPI runs here, serving requests
    finally:
        await close_pool(pool)
```

Step by step:

- `lifespan` is an async generator (it has `yield`).
- `@asynccontextmanager` wraps it so it can be used with `async with`.
- Code before `yield` runs at startup. Code after `yield` runs at shutdown. Anything in `try/finally` runs even on errors.
- FastAPI itself does `async with lifespan(app):` internally. So:
  - Before `yield`: pool is created, attached to `app.state`.
  - `yield`: FastAPI pauses our generator and starts accepting requests.
  - On shutdown (Ctrl-C, SIGTERM): FastAPI resumes our generator, which closes the pool.

This is how we guarantee the pool is created exactly once and closed exactly once, regardless of how the server exits.

(`lifespan` replaces the older `@app.on_event("startup")` and `@app.on_event("shutdown")` decorators, which are deprecated.)

## Two failure modes to know about

**1. Forgetting `await`.**

```python
result = conn.fetchval("SELECT 1")        # WRONG — result is a coroutine, not a value
result = await conn.fetchval("SELECT 1")  # right
```

If you forget `await`, you get back a coroutine *object*, not the awaited result. Often the bug shows up as a confusing error later when you try to use it. Modern type checkers (mypy, pyright) catch this; turn one on as soon as you can.

**2. Calling a blocking function from async code.**

```python
async def handler():
    time.sleep(5)   # WRONG — freezes the entire server for 5 seconds
    await asyncio.sleep(5)   # right — frees the loop while waiting
```

If a library you want to use is sync-only and slow, the right escape hatch is `asyncio.to_thread(blocking_fn, ...)` — that runs the blocking call on a separate thread and `await`s its completion.

## Short cheat sheet

| You see... | It means... |
|------------|-------------|
| `async def f():` | A coroutine function. Call with `await f()`. |
| `await x` | Wait for `x` (a coroutine or future) to finish, get its result. |
| `with x:` | Sync context manager — setup at entry, teardown at exit. |
| `async with x:` | Async context manager — same, but setup/teardown can be async. |
| `yield x` in a regular function | Generator. Pauses at `yield`, resumes when caller iterates. |
| `yield x` in an `async def` | Async generator (used in FastAPI yield deps). |
| `@asynccontextmanager` | Turns an async generator into something usable with `async with`. |

## What to read next

[04-fastapi-deps.md](04-fastapi-deps.md) — how `Depends(...)` actually works, with `get_conn` and `current_user` walked line by line.
