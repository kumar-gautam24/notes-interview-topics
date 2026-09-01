# 5. Database — pool, app.state, and the transaction question

This doc answers your three database questions head-on:

1. What is an `asyncpg.Pool`?
2. Shouldn't we have a dependency that opens a connection, yields, and rolls back/closes in `finally`?
3. What is `app.state`?

And one bonus question that always comes next: **when should I use a transaction?**

## What is a connection pool?

Every Postgres conversation starts with a TCP connection: TLS handshake, authentication, server handshake. That's expensive — tens of milliseconds. If we opened a fresh connection for every HTTP request, the server would spend most of its time on handshakes.

A **connection pool** is a small set of pre-opened, reusable database connections. When code needs to talk to the DB, it *acquires* a connection from the pool, uses it, *releases* it back. Acquiring is essentially free; the heavy lifting happened once at pool creation.

```
            ┌───── pool (10 connections, all open) ─────┐
            │   c1   c2   c3   c4   c5   ...   c10      │
            └───────────────────────────────────────────┘
                ↑ acquire (instant)        ↓ release
                │                          │
          ┌─────┴──────┐              ┌────┴────────┐
          │  Request A │              │  Request B  │
          └────────────┘              └─────────────┘
```

In our `app/core/db.py`:

```python
async def create_pool() -> asyncpg.Pool:
    return await asyncpg.create_pool(
        dsn=str(settings.database_url),
        min_size=1,
        max_size=10,
        command_timeout=10,
    )
```

- `min_size=1` — keep at least 1 connection warm even when idle.
- `max_size=10` — never open more than 10 simultaneous connections to Postgres. If 11 requests need a connection at once, the 11th waits until one is released.
- `command_timeout=10` — any single SQL statement that takes longer than 10s is killed. Prevents a runaway query from holding a slot forever.

You sized the pool based on (a) what your DB allows (Neon free tier has a low connection cap; the pooler URL helps) and (b) your expected concurrency.

## What is `app.state`?

`app` is the `FastAPI()` instance — your application object. `app.state` is a tiny namespace attached to it where you can stash things that are **process-wide and built once.** Anything you put on `app.state` is accessible from every request via `request.app.state.thing`.

We use it for the pool:

```python
# in lifespan (runs once at startup):
pool = await create_pool()
app.state.pool = pool

# in any handler:
pool: asyncpg.Pool = request.app.state.pool
```

It's the official "process-global" location. Two reasons we use it instead of a top-level Python global:

1. **Testability.** In tests, you can build a separate `app` with a different pool. No monkey-patching modules.
2. **Lifecycle clarity.** The pool exists as long as `app` is being served. There's no question of "is this initialized yet?" — if you have a request, `app.state.pool` is set.

## Now to your big question — yield, except, rollback, finally close

You're describing a pattern that looks like this (this is **what we DON'T do** here):

```python
# Common SQLAlchemy-style pattern. NOT used in this codebase.
async def get_db():
    db = SessionLocal()
    try:
        yield db
        await db.commit()       # auto-commit on success
    except Exception:
        await db.rollback()     # rollback on failure
        raise
    finally:
        await db.close()        # always close
```

Your instinct is good — that's a very common pattern. We don't use it here, and it's worth understanding why, because the reasoning generalizes.

### What we actually have

```python
async def get_conn(request: Request) -> AsyncIterator[asyncpg.Connection]:
    pool: asyncpg.Pool = request.app.state.pool
    async with pool.acquire() as conn:
        yield conn
```

The `async with pool.acquire()` is the try/finally — when the generator exits (normally or via exception), the `async with` block exits, and **the connection is released back to the pool.** No leaks, no manual close.

What's missing compared to the SQLAlchemy pattern is the auto-commit and auto-rollback. That's deliberate. Three reasons:

### Reason 1: asyncpg auto-commits each statement by default

Postgres always runs every statement inside a transaction. asyncpg starts that transaction implicitly for each statement and commits it the moment the statement returns. Unless you explicitly say "I want a multi-statement transaction," there is no transaction to commit or roll back.

So in our `signup` endpoint:
```
INSERT INTO users (...)   ← auto-committed by asyncpg, atomically
```

There's no half-finished state to roll back. The single statement either fully happened or fully didn't.

### Reason 2: the SQLAlchemy pattern hides transaction boundaries

In the SQLAlchemy pattern, every endpoint is implicitly one transaction. That sounds nice until:
- A read-only endpoint that calls 3 reads still creates and commits a transaction (waste).
- An endpoint with side effects in two different services has both wrapped in *one* transaction whether you want it or not.
- You have to remember that "commit" happens magically at the end. New people on the team write `await conn.execute("DELETE ...")` and don't realize it'll only commit if the response is a 2xx.

Explicit > implicit. When we want a multi-statement transaction, we say so:

```python
async def transfer_credits(conn, *, from_user, to_user, amount):
    async with conn.transaction():
        await debit(conn, from_user, amount)
        await credit(conn, to_user, amount)
    # If anything in the block raises, asyncpg automatically rolls back.
    # If the block exits cleanly, asyncpg commits.
```

`conn.transaction()` IS an async context manager that does the same try/commit/except/rollback dance — but at the *service* layer, where the boundary belongs.

### Reason 3: the connection is released, not closed

`async with pool.acquire()` releases the connection back to the pool when the block exits. We never *close* connections during normal operation — closing them would mean re-handshaking later, which defeats the pool. The pool owns the lifetime; we just borrow.

When a request raises an exception, asyncpg also resets the connection to a clean state before returning it to the pool, so the next borrower doesn't inherit weirdness. You don't have to handle that yourself.

### Could we add commit-on-success / rollback-on-error?

Yes, if you wanted endpoint-level transactions you could write:

```python
async def get_tx_conn(request: Request) -> AsyncIterator[asyncpg.Connection]:
    pool = request.app.state.pool
    async with pool.acquire() as conn:
        async with conn.transaction():   # auto-commit on clean exit, auto-rollback on exception
            yield conn
```

…and use it as `Depends(get_tx_conn)` for write endpoints. We don't right now because (a) we don't yet have endpoints that need multi-statement atomicity, and (b) for our single-statement writes it's overkill. We can add `get_tx_conn` the day we need it without changing `get_conn`.

## When DO you use a transaction?

Whenever you have **two or more statements that must succeed together or not at all.** Examples:

- Insert a post AND increment a denormalized counter in another row → one transaction.
- Move money from account A to account B (debit + credit) → one transaction.
- Insert a user AND insert their default settings row → one transaction.

If it's one statement, you don't need anything; asyncpg handles it. If it's many independent reads, no transaction is needed (and a long-running transaction holds locks — bad). The line in the sand is "atomicity required."

## What about the `# type: ignore` on `import asyncpg`?

You may notice in `app/api/routes/health.py`:

```python
import asyncpg  # type: ignore
```

That's a hint to a static type checker (mypy/pyright) saying "I know asyncpg's type stubs are incomplete here; trust me." asyncpg ships limited type information, and depending on the version, the type checker complains about `asyncpg.Pool` being missing or generic. `# type: ignore` silences that for one line. Not security-relevant, just tooling.

## Connection pools and async generators together

To pull it all together, here's the full lifetime of a connection in this codebase:

```
[startup]   create_pool() → 10 connections opened, parked in pool
                                    │
[request A] get_conn() ─────────────┤
            async with pool.acquire() → grabs connection #3
            yield conn → routed to route handler
            (handler runs)
            generator resumes → async with exits → release #3
                                    │
[request B] get_conn() ─────────────┤
            async with pool.acquire() → grabs connection #3 (same one!)
            yield conn → ...
                                    │
[shutdown]  close_pool() → all 10 connections closed gracefully
```

Same connection serves many requests. Same pool exists for the entire process lifetime. The async generator (`get_conn`) creates the per-request *acquire/release* cycle.

## Summary

- A **pool** is a reusable set of pre-opened DB connections — much faster than reconnecting per request.
- `app.state` is FastAPI's official place for process-global state; the pool lives there.
- `get_conn` is a yield-based dependency that acquires from the pool on entry and releases on exit. The `async with` IS the try/finally.
- We don't auto-commit/rollback because asyncpg auto-commits single statements and we want explicit transaction control at the service layer for multi-statement work.
- Use `async with conn.transaction():` in a service when you need atomicity across multiple statements.

## What to read next

[06-auth-and-jwt.md](06-auth-and-jwt.md) — JWT structure, what `sub`/`iat`/`exp` mean, and the full signup → login → /me flow.
