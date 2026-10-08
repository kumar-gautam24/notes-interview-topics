# 06 · FastAPI Rapid-Fire: decorators, middleware, Pydantic, Depends, lifespan, pooling

Each question has the answer to say aloud, then the trade-off that shows depth. The trade-off is what separates a 3/5 from a 5/5. Fuller background is in [03-fastapi-pack.md](03-fastapi-pack.md); working code is in [fastapi_demo.py](code/fastapi_demo.py).

---

## A. Decorators

**Q: What is a decorator?**
> "A function that takes a function and returns a new one that wraps it. `@timed` above `def f` is just `f = timed(f)`. You use it to add behaviour around a function, like logging, timing, retries, caching or auth, without changing the function's code."

**Q: Write one.** (keep it async-aware for FastAPI)
```python
import functools, time, logging
log = logging.getLogger(__name__)

def timed(fn):
    @functools.wraps(fn)                      # keeps name, docstring and signature
    async def wrapper(*args, **kwargs):
        start = time.perf_counter()
        try:
            return await fn(*args, **kwargs)
        finally:
            log.info("%s took %.1fms", fn.__name__, (time.perf_counter() - start) * 1000)
    return wrapper
```
Decorator **with arguments** = one more level: `def retry(times): def deco(fn): ... return deco`.

**Q: Why `functools.wraps`?**
> "Without it the wrapper replaces the function's name, docstring and signature. In FastAPI that matters a lot: FastAPI reads the endpoint's signature to know which parameters are path, query, body or dependencies. `wraps` sets `__wrapped__`, so FastAPI can still see the real signature."

**Q: Where are decorators used in FastAPI?**
> "`@app.get` and `@router.post` register routes. Then `@app.middleware`, `@app.exception_handler`, Pydantic's `@field_validator`, and `@lru_cache` on `get_settings()`."

**Trade-off: decorator vs dependency for auth/RBAC**
> "I'd use `Depends` rather than a custom decorator for auth or role checks. Dependencies plug into FastAPI's injection, show up in the OpenAPI docs as security requirements, can be overridden in tests, and give the endpoint the current user as a value. A decorator hides the parameter from FastAPI and is easy to get wrong with async. Decorators are fine for cross-cutting things that aren't request inputs, like timing, retries or caching a pure function."

---

## B. Middleware

**Q: What is middleware?**
> "Code that wraps **every** request and response, before routing and after the endpoint. Common uses: request id, logging and timing, CORS, GZip, security headers, trusted hosts."

```python
@app.middleware("http")
async def request_context(request: Request, call_next):
    request.state.request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    start = time.perf_counter()
    response = await call_next(request)
    response.headers["x-request-id"] = request.state.request_id
    log.info("%s %s %s %.1fms", request.method, request.url.path,
             response.status_code, (time.perf_counter() - start) * 1000)
    return response
```

**Q: Order of middleware?**
> "It's an onion. The last one added is the outermost, so it runs first on the way in and last on the way out. CORS usually needs to be outermost so even error responses get CORS headers."

**Q: Middleware vs dependency?**
| | Middleware | Dependency (`Depends`) |
|---|---|---|
| Runs for | Every request, including 404s and static | Only routes that declare it (or a router's `dependencies=[...]`) |
| Knows the route/params? | No, sees the raw request | Yes, gets typed, validated params |
| Can return a value to the endpoint? | Only via `request.state` | Yes, injected directly (e.g. `user`) |
| Appears in OpenAPI docs? | No | Yes |
| Good for | Logging, timing, request id, CORS, GZip | Auth, current user, tenant, DB connection, pagination, permissions |

> "Rule: if it applies to everything and doesn't need route knowledge, it's middleware. If it's an input to the endpoint, it's a dependency."

**Trade-offs to mention:**
- Don't do DB calls or heavy work in middleware. It runs on every request, including health checks.
- `@app.middleware("http")` uses Starlette's `BaseHTTPMiddleware`, which adds overhead and has historically had issues with streaming responses and background tasks. For hot paths, a **pure ASGI middleware** (a class with `__call__(scope, receive, send)`) is faster.
- Middleware can't see exceptions that a handler already turned into a response. Use exception handlers for error shaping, and middleware for logging the final status.

---

## C. Validation and Pydantic

**Q: How does FastAPI validate requests?**
> "From type hints. Path and query params are validated from their annotations, and a body parameter typed as a Pydantic model is parsed and validated from JSON. If validation fails, FastAPI returns **422** with field-level errors before my code runs. On the way out, `response_model` validates and **filters** the response, so fields like `password_hash` never leak."

**Q: Show validation.**
```python
from typing import Annotated
from pydantic import BaseModel, Field, field_validator, model_validator

class LeadCreate(BaseModel):
    name: Annotated[str, Field(min_length=1, max_length=100)]
    email: str
    age: int | None = Field(default=None, ge=15, le=80)
    password: str
    confirm_password: str

    @field_validator("email")
    @classmethod
    def normalise_email(cls, v: str) -> str:
        if "@" not in v:
            raise ValueError("invalid email")
        return v.strip().lower()

    @model_validator(mode="after")          # cross-field rule
    def passwords_match(self):
        if self.password != self.confirm_password:
            raise ValueError("passwords do not match")
        return self
```
Query validation: `limit: int = Query(20, ge=1, le=100)`.

**Q: Why separate input and output models?**
> "`LeadCreate` has what the client may send. `LeadOut` has what we return. `LeadUpdate` has all fields optional for PATCH. That stops clients setting `id`, `tenant_id` or `role`, and stops internal fields leaking. For PATCH I use `model_dump(exclude_unset=True)`, so only the fields actually sent get updated."

**Q: Pydantic v1 vs v2?**
> "v2's core is rewritten in Rust (pydantic-core), so it's much faster. The API was renamed: `dict()` became `model_dump()`, `parse_obj` became `model_validate`, `@validator` became `@field_validator`, and `class Config` became `model_config = ConfigDict(...)`. `orm_mode` became `from_attributes=True`."

**Trade-offs to mention:**
- **Lax vs strict mode:** by default Pydantic *coerces*, so `"123"` becomes `123`. Convenient, but it can hide client bugs. Use `strict=True` or `StrictInt` where it matters, like money or ids.
- **Validation isn't free:** validating a response with 10,000 nested objects costs CPU. For trusted internal data you can skip it with `model_construct()`, or return a `JSONResponse` directly, at the cost of safety. Paginate instead of returning huge lists.
- **Validation at boundaries:** validate where data *enters*: requests, webhook payloads, LLM output, third-party API responses. Your Vaidya turn manager validated every model turn's output against a schema so bad output failed where it was produced. That's a great example to give.
- **Pydantic validates shape, not business rules that need the DB**, like "email must be unique in this tenant". Those belong in the service layer and return 409.

---

## D. `Depends` (dependency injection)

**Q: What is `Depends`?**
> "FastAPI's dependency injection. A dependency is any callable. FastAPI calls it, resolving *its* parameters too, so dependencies can chain, and passes the result to the endpoint. I use it for the DB connection, current user, tenant, role checks, pagination params and settings."

```python
async def get_conn(request: Request):
    async with request.app.state.pool.acquire() as conn:   # acquired per request
        yield conn                                          # code after yield = cleanup

async def get_current_user(token = Depends(bearer), conn = Depends(get_conn)) -> User: ...

def require_role(*roles):
    async def checker(user: User = Depends(get_current_user)):
        if user.role not in roles:
            raise HTTPException(403)
        return user
    return checker

@router.delete("/leads/{id}", dependencies=[Depends(require_role("admin"))])
async def delete_lead(id: int, conn = Depends(get_conn)): ...
```

**Key facts:**
- **Cached per request:** if two dependencies both need `get_current_user`, it runs once. Disable with `Depends(fn, use_cache=False)`.
- **`yield` dependencies** run setup before the endpoint and cleanup after, like releasing a DB connection or closing a session. Exceptions in the endpoint can be caught around the `yield` for rollback.
- **Router-level and app-level dependencies:** `APIRouter(dependencies=[Depends(auth)])` applies auth to every route in that router.
- **Testing:** `app.dependency_overrides[get_conn] = fake_conn`. This is the biggest practical win.
- A plain `def` dependency runs in the thread pool; an `async def` one runs on the event loop. Same blocking rules as endpoints.

**Trade-offs to mention:**
> "Pros: endpoints declare what they need instead of building it, so they're testable and easy to reuse, and auth shows up in the docs. It's the same idea as GetIt in my Flutter apps. Cons: deep dependency chains can get hard to trace, there's a small per-request overhead, and it only works inside FastAPI's request cycle. Background workers and scripts don't get `Depends`, so I keep business logic in plain service classes that take their dependencies through the constructor, and use `Depends` only at the HTTP edge to build them."

---

## E. Lifespan and async context managers

**Q: What is an async context manager?**
> "An object used with `async with` that runs async setup on entry and guaranteed cleanup on exit, even if an exception happens. It implements `__aenter__` and `__aexit__`, or you write it as a generator with `@asynccontextmanager`: code before `yield` is setup, code after is cleanup. Examples: `async with pool.acquire() as conn`, `async with conn.transaction()`, `async with httpx.AsyncClient() as client`."

**Q: What is FastAPI's lifespan?**
> "An async context manager passed to `FastAPI(lifespan=...)`. Code before `yield` runs once at startup, code after runs once at shutdown. It's where shared resources are created once per worker process: the DB pool, Redis client and HTTP client. It replaced the old `@app.on_event('startup')` / `'shutdown'` hooks."

```python
from contextlib import asynccontextmanager
import asyncpg, httpx, redis.asyncio as redis

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pool = await asyncpg.create_pool(dsn=settings.db_url, min_size=2, max_size=10,
                                               command_timeout=10)
    app.state.redis = redis.from_url(settings.redis_url)
    app.state.http = httpx.AsyncClient(timeout=10)
    yield                                     # app serves requests here
    await app.state.http.aclose()
    await app.state.redis.aclose()
    await app.state.pool.close()

app = FastAPI(lifespan=lifespan)
```

**Why it matters / trade-offs:**
- Creating a pool or HTTP client **per request** is a classic performance bug: new TCP and TLS handshakes and new DB connections every time. Create once, reuse.
- If startup fails (DB unreachable), the app fails to boot, which is what you want: the orchestrator restarts it instead of serving errors.
- Clean shutdown lets in-flight requests finish and releases connections, which matters during rolling deploys.
- **Each worker process runs its own lifespan**, so `--workers 4` means 4 pools. That feeds directly into pool sizing (next section).
- Prefer `app.state` set in lifespan over module-level globals: easier to test and clearer ownership.

---

## F. DB connection pooling and performance

**Q: Why use a connection pool?**
> "Opening a Postgres connection is expensive: TCP, TLS, authentication, and a new backend process on the server, often tens of milliseconds. A pool keeps a set of open connections; each request borrows one and returns it. That gives lower latency, and it caps how many connections hit the database."

**Q: How do you size it?** (your real story lives here)
> "The database has a hard limit, `max_connections`, 100 by default in Postgres, and each connection uses server memory. Total connections = **pods × worker processes per pod × pool max_size**. That must stay under the DB limit with headroom for migrations and admin. Example: 3 pods × 4 workers × 10 = 120, already over 100.
> In Vaidya I found the pool capped at 10 per service, so under load requests queued waiting for a connection. The fix isn't just 'make the pool bigger'. If you scale pods, each brings its own pool, so you can exhaust the database. You size against the DB limit, keep transactions short so connections are returned fast, and put **PgBouncer** in front when you have many app instances."

**Q: What's PgBouncer?**
> "A lightweight connection pooler between the app and Postgres. Thousands of client connections share a small number of real DB connections. In transaction mode, a server connection is only held for the duration of a transaction. Gotcha: transaction mode breaks session features like prepared statements, so with asyncpg you set `statement_cache_size=0`. Neon's pooled connection string is PgBouncer underneath."

**Q: Pool performance pitfalls?**
- **Holding a connection during slow non-DB work** (calling an LLM or a payment API while inside `async with pool.acquire()`): the pool drains fast. Acquire late, release early.
- **Long transactions** hold connections and locks. Keep them short; never wait on user input or a network call inside one.
- **Sync driver in async code:** psycopg2 inside `async def` blocks the event loop. Use asyncpg or psycopg3 async (your Vaidya fix).
- **No timeouts:** set an acquire timeout and a `command_timeout`, so a slow query fails instead of hanging every request.
- **N+1 queries** multiply connection usage. Batch or JOIN.
- Monitor pool usage (in use vs idle), wait time to acquire, and `pg_stat_activity` on the DB side.

**Q: Bigger pool = faster?**
> "No. Past a point, more connections make Postgres slower: CPU context switching, lock contention, memory. A common starting point is around (CPU cores × 2) + disk spindles on the DB server, then measure. A small pool with short transactions usually beats a big pool."

---

## G. Putting it together: "walk me through a request"

> "A request hits Nginx, then a Uvicorn worker process. The worker's event loop picks it up. Middleware runs first (request id, timing, CORS), then routing. FastAPI resolves the dependencies: it borrows a connection from the pool created in lifespan, decodes the JWT into the current user, checks the role and tenant. Pydantic validates the body, and a failure returns 422 here. The endpoint calls the service layer, which calls the repository, which runs SQL with the borrowed connection. The result goes through `response_model` to filter and serialise. The `yield` dependency returns the connection to the pool, middleware adds headers and logs the latency, and the response goes out. If anything raises, an exception handler maps it to a consistent error JSON with the request id."

---

## H. Glossary: every FastAPI term in one line

| Term | What it is |
|---|---|
| **ASGI** | The async interface between server and app (successor to WSGI). Supports async, WebSockets and long-lived connections |
| **Uvicorn** | The ASGI server that runs your app. `--workers N` starts N processes |
| **Gunicorn** | Process manager; with `UvicornWorker` it supervises and restarts Uvicorn workers |
| **Worker (process)** | One OS process with its own event loop, memory, lifespan and DB pool |
| **Event loop** | Single thread per worker that runs coroutines, switching at each `await` |
| **Coroutine** | An `async def` function's result; runs only when awaited or scheduled |
| **Starlette** | The toolkit FastAPI is built on: routing, Request/Response, middleware, WebSockets, background tasks |
| **Pydantic** | Data validation and serialisation from type hints |
| **App (`FastAPI()`)** | The ASGI application: holds routes, middleware, exception handlers, lifespan, `app.state` |
| **Router (`APIRouter`)** | A group of routes with a shared prefix, tags and dependencies; mounted with `include_router` |
| **Path operation** | One route: method + path + endpoint function (`@router.get("/leads/{id}")`) |
| **Endpoint / handler** | The function that handles a path operation |
| **Path / query / body / header / cookie params** | Where an input comes from: `{id}` in the URL, `?limit=`, JSON body (Pydantic model), `Header()`, `Cookie()` |
| **Request / Response** | Starlette objects for the raw request and the outgoing response |
| **`response_model`** | Output schema: validates, filters and documents the response |
| **`status_code`** | Default success code for the route (e.g. 201) |
| **Dependency (`Depends`)** | A callable FastAPI runs and injects; chainable, cached per request |
| **`Security`** | `Depends` plus OAuth2 scopes; shows as a security requirement in docs |
| **Yield dependency** | Dependency with setup before `yield` and cleanup after the response |
| **Middleware** | Wraps every request/response (onion layers) |
| **Exception handler** | Maps an exception type to a response |
| **`HTTPException`** | Exception carrying a status code and detail; FastAPI turns it into a response |
| **`RequestValidationError`** | Raised when input fails validation; default response is 422 |
| **Lifespan** | Async context manager for startup/shutdown resources |
| **`app.state` / `request.state`** | App-wide shared objects / per-request scratch space |
| **`BackgroundTasks`** | Run a function after the response is sent, in the same process |
| **WebSocket** | Persistent two-way connection, upgraded from HTTP |
| **SSE** | Server-Sent Events: one-way server → client stream over HTTP |
| **OpenAPI / `/docs`** | Auto-generated API schema and Swagger UI |
| **`dependency_overrides`** | Swap dependencies in tests |
| **Mount** | Attach a sub-app or static files at a path (`app.mount("/static", ...)`) |

---

## I. Middleware order: 5 middlewares, which order, and why

**The rule (verified by running it):** middleware is an onion. **The last one added is the outermost.** It runs first on the way in and last on the way out.

```python
app.add_middleware(A)   # added 1st  → innermost
app.add_middleware(B)
app.add_middleware(C)
@app.middleware("http") # added last → outermost
async def D(request, call_next): ...
```
Actual run order of a request: `D in → C in → B in → A in → endpoint → A out → B out → C out → D out`.

**Recommended order for 5 middlewares, outermost first:**

| # (outer → inner) | Middleware | Why here |
|---|---|---|
| 1 | **TrustedHost / ProxyHeaders** | Reject bad `Host` headers and fix client IP/scheme from Nginx's `X-Forwarded-*` before anything logs or uses them |
| 2 | **CORS** | Must answer browser preflight `OPTIONS` requests itself, and must add CORS headers even to error responses; if it's inside something that fails, the browser hides the real error behind a "CORS error" |
| 3 | **Request id + logging/timing** | Wraps everything below, so it logs the final status and total latency, and every inner layer can use the request id |
| 4 | **Rate limiting** (if done as middleware) | After logging, so blocked requests are logged with 429; before the expensive work |
| 5 | **GZip** | Innermost, closest to the response body, so it compresses the endpoint's output; outer layers only touch headers |

**So you add them in reverse:** GZip first, then rate limit, then logging, then CORS, then TrustedHost last.
```python
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(RateLimitMiddleware)
app.add_middleware(RequestContextMiddleware)
app.add_middleware(CORSMiddleware, allow_origins=[...], allow_credentials=True,
                   allow_methods=["*"], allow_headers=["*"])
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["api.headstart.in"])
```

**Where middleware sits in the whole stack:**
`Uvicorn → Starlette's ServerErrorMiddleware (catches anything unhandled → 500) → your middlewares → ExceptionMiddleware (runs your exception handlers / HTTPException) → router → dependencies → endpoint`.
So by the time your middleware sees the response, an `HTTPException` has already become a normal 4xx response.

**Middleware applies to the whole app, not to individual routes or routers.** For route-specific behaviour, use a dependency (next section), or check `request.url.path` inside the middleware (only for simple cases).

**Auth in middleware or in a dependency?** Prefer a dependency: per-route control, typed user object, shows in docs, testable. Middleware auth fits only when *everything* is protected and you just need a gate (e.g. an internal service behind an API gateway).

---

## J. Adding auth: whole app, a router, certain routes, or a piece of code

The router-level and route-level versions were run against a real FastAPI app (401 without a token, 200 with one, public routes unaffected).

```python
async def get_current_user(token: str = Depends(bearer)) -> User: ...   # 401 if bad
def require_role(*roles): ...                                           # 403 if wrong role
```

| Scope | How | Use when |
|---|---|---|
| **Whole app** | `app = FastAPI(dependencies=[Depends(get_current_user)])` | Internal APIs where nothing is public. Careful: `/health` and `/docs` get protected too |
| **A whole router** | `APIRouter(prefix="/admin", dependencies=[Depends(require_role("admin"))])` | A group of routes sharing a rule (all admin routes) |
| **At include time** | `app.include_router(reports.router, dependencies=[Depends(get_current_user)])` | Same router reused with different protection |
| **One route, no value needed** | `@router.delete("/leads/{id}", dependencies=[Depends(require_role("admin"))])` | Just a gate |
| **One route, need the user** | `async def get_lead(id: int, user: User = Depends(get_current_user))` | Endpoint uses `user.tenant_id` etc. |
| **Optional auth** | Dependency returns `None` instead of raising when no token | Public page that shows extra data when logged in |
| **Inside a piece of code** | Explicit check in the service: `if lead.owner_id != user.id and user.role != "admin": raise ForbiddenError()` | **Object-level** rules ("only the assigned counsellor can edit this lead") that need the DB row first |
| **Scopes** | `Security(get_current_user, scopes=["leads:write"])` | Fine-grained permissions in tokens, OAuth-style |

**Layering to say in the interview:**
> "Authentication once, as a dependency that turns the token into a user. Coarse authorisation at the router level (admin router needs the admin role). Fine-grained, object-level checks in the service layer, because they need the actual record. And tenant scoping in every repository query. Public routes like `/login`, `/health` and webhooks live on a separate router without the auth dependency, and webhooks use HMAC signature checks instead of user tokens."

---

## K. DB session: `Depends` vs async context manager

They aren't competitors: a `yield` dependency **is** an async context manager that FastAPI enters and exits for you.

```python
# 1. As a dependency: FastAPI manages it per request
async def get_conn(request: Request):
    async with request.app.state.pool.acquire() as conn:
        yield conn                          # released after the response is sent

@router.get("/leads")
async def list_leads(conn = Depends(get_conn)): ...

# 2. As an explicit async context manager: you control the exact scope
async def transfer_credits(pool, from_id, to_id, amount):
    async with pool.acquire() as conn:
        async with conn.transaction():      # commit on success, rollback on exception
            await conn.execute("UPDATE wallets SET balance = balance - $1 WHERE user_id=$2 AND balance >= $1", amount, from_id)
            await conn.execute("UPDATE wallets SET balance = balance + $1 WHERE user_id=$2", amount, to_id)
```

| | `Depends(get_conn)` | `async with pool.acquire()` in code |
|---|---|---|
| Lifetime | Whole request: acquired before the endpoint, released **after the response** | Exactly the block you write |
| Pros | Clean endpoints, easy test overrides, one connection shared by all dependencies in the request | Tight scope: hold the connection only while querying; clear transaction boundaries |
| Cons | Holds a connection for the whole request, even during slow non-DB work (LLM call, external API) | More boilerplate; must pass the pool around |
| Works outside HTTP? | No | Yes: workers, scripts, cron jobs |

**What to say:**
> "For simple CRUD endpoints I use a `yield` dependency: one connection per request, released automatically. For endpoints that also call slow external services, or for background workers, I acquire explicitly with `async with` around only the DB part, so the connection goes back to the pool fast. Transactions are always explicit `async with conn.transaction()` around one unit of work, in the service layer, never spread across the HTTP layer."

**Unit of Work:** the pattern of one transaction per business operation (all writes succeed or none do). In SQLAlchemy it's the `AsyncSession`; with asyncpg it's `conn.transaction()`.

---

## L. DB practices checklist

- **Parameterised queries always** (`$1`, `%s`, ORM). Never f-strings into SQL (SQL injection).
- **One pool per worker**, created in lifespan; sized against `max_connections` (section F).
- **Short transactions**; no network calls inside them.
- **Atomic updates instead of read-modify-write:** `UPDATE ... SET balance = balance - $1 WHERE balance >= $1` (your wallet fix). Or `SELECT ... FOR UPDATE` when you must read first.
- **Constraints in the DB, not only in code:** `NOT NULL`, `UNIQUE (tenant_id, email)`, `CHECK (amount > 0)`, foreign keys. The DB is the last line of defence against race conditions.
- **Idempotent writes:** `INSERT ... ON CONFLICT DO NOTHING / DO UPDATE`.
- **Migrations** versioned and reviewed (Alembic, or your hand-written SQL files); backwards-compatible steps (add column nullable → backfill → add constraint), never a destructive change in the same deploy as the code that depends on it.
- **Indexes from real queries**, verified with `EXPLAIN ANALYZE` (see [05](05-indexing-deep-dive.md)).
- **Select only needed columns**; paginate every list endpoint.
- **Money as integer minor units** (paise), never float (you do this).
- **Timestamps as `timestamptz`**, stored in UTC.
- **Soft delete** with `deleted_at` + partial indexes, if you need history; remember every query must filter it.
- **Timeouts:** `command_timeout`, pool acquire timeout, Postgres `statement_timeout`.
- **Read replicas** for heavy reads/reports; writes go to the primary.
- **Backups + tested restores**, and least-privilege DB users (the app user can't drop tables).
- **Test against a real Postgres** in Docker, not mocks (you do this).

---

## M. Exception handling: the full picture

**Layers, from inside out:**
1. **Service layer** raises **domain errors** (`NotFoundError`, `ConflictError`, `InsufficientCreditsError`). No HTTP knowledge.
2. **Exception handlers** map them to HTTP status codes and one consistent JSON shape.
3. **Validation errors** (`RequestValidationError`) get a handler too, if the frontend needs the same shape instead of FastAPI's default 422 body.
4. **Catch-all `Exception` handler**: log the full traceback with request id, return a safe generic 500.
5. **Monitoring**: Sentry / CloudWatch alarms on error rate.

```python
from fastapi.exceptions import RequestValidationError

@app.exception_handler(AppError)
async def app_error(request: Request, exc: AppError):
    return JSONResponse(status_code=exc.status_code, content={"code": exc.code, "message": exc.message,
                                          "request_id": request.state.request_id})

@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    return JSONResponse(status_code=422, content={"code": "validation_error", "message": "Invalid input",
                              "errors": exc.errors(), "request_id": request.state.request_id})

@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception):
    log.exception("unhandled request_id=%s", request.state.request_id)
    return JSONResponse(status_code=500, content={"code": "internal_error", "message": "Something went wrong",
                              "request_id": request.state.request_id})
```

**Points that show depth:**
- `HTTPException` is fine in routers and dependencies; services should raise domain errors so they're reusable from workers.
- Never leak stack traces, SQL or internal ids in error bodies; the request id lets support find the log.
- Use `raise NewError(...) from e` to keep the original cause in logs.
- In a `yield` dependency, wrap `yield` in `try/except` to roll back a transaction if the endpoint failed.
- Retry only transient errors (timeouts, 503, deadlocks), with backoff; never retry 4xx.
- **Status codes that matter:** 400 bad request, 401 not authenticated, 403 not allowed, 404 not found (also for other tenants' data), 409 conflict, 422 validation, 429 rate limited, 500 our bug, 502/503/504 upstream or overload.

---

## N. CORS

**What it is:** a *browser* security rule. JavaScript on `https://app.headstart.in` can only read responses from `https://api.headstart.in` if the API says that origin is allowed. Origin = scheme + host + port. It doesn't apply to mobile apps, curl or server-to-server calls, which is why "it works in Postman but not in the browser" is the classic symptom.

**Preflight:** for "non-simple" requests (JSON body, `Authorization` header, PUT/DELETE), the browser first sends `OPTIONS` with `Origin` and `Access-Control-Request-Method`. The server replies with `Access-Control-Allow-Origin`, `-Methods`, `-Headers`, `-Credentials`, `-Max-Age`. Only then is the real request sent.

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.headstart.in", "https://admin.headstart.in"],   # explicit list
    allow_credentials=True,          # needed for cookies
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    max_age=600,                     # cache preflight for 10 min
)
```
(Verified: a preflight from the allowed origin gets 200 with the allow headers; one from `https://evil.com` gets 400.)

**Rules and trade-offs:**
- `allow_origins=["*"]` **cannot** be combined with credentials (cookies); browsers reject it. Use an explicit list.
- CORS is **not** a security boundary for your API: it only stops *browsers* from reading responses. Auth still has to be enforced on the server.
- Put CORS middleware outermost so error responses also carry CORS headers.
- Multi-tenant subdomains (`*.headstart.in`): use `allow_origin_regex` carefully, anchored: `r"https://[a-z0-9-]+\.headstart\.in"`.

---

## O. HTTPS, cookies and HttpOnly auth

**HTTPS/TLS:** encrypts traffic and proves the server's identity. In production, **TLS terminates at Nginx or the load balancer**, which forwards plain HTTP to Uvicorn on the private network. Then:
- run Uvicorn with `--proxy-headers --forwarded-allow-ips=...` so `request.url.scheme` and client IP come from `X-Forwarded-Proto` / `X-Forwarded-For`;
- redirect HTTP → HTTPS at Nginx, and send **HSTS** (`Strict-Transport-Security`) so browsers never try HTTP again;
- you set this up yourself (Nginx + TLS on your resume): mention Let's Encrypt / certbot renewal.

**Bearer token in header vs HttpOnly cookie:**

| | `Authorization: Bearer` (stored by the client) | **HttpOnly cookie** |
|---|---|---|
| Who sends it | Client code adds it to each request | Browser attaches it automatically |
| XSS (injected JS) | If stored in `localStorage`, JS can steal it | `HttpOnly`: JS **cannot** read it |
| CSRF (another site triggers a request) | Not vulnerable: other sites can't add your header | **Vulnerable** unless `SameSite` + CSRF token |
| Best for | Mobile apps (secure storage), service-to-service | Browser web apps |

```python
@router.post("/login")
async def login(body: LoginIn, response: Response):
    user = await auth_service.verify(body.email, body.password)
    response.set_cookie("access_token", create_access_token(user), httponly=True, secure=True,
                        samesite="lax", max_age=900, path="/")
    response.set_cookie("refresh_token", create_refresh_token(user), httponly=True, secure=True,
                        samesite="strict", max_age=30 * 86400, path="/auth/refresh")
    return {"ok": True}

async def get_current_user(access_token: str | None = Cookie(default=None)) -> User: ...
```
(Verified header: `access_token=...; HttpOnly; Max-Age=900; Path=/; SameSite=lax; Secure`.)

**Cookie flags:** `HttpOnly` (no JS access) · `Secure` (HTTPS only) · `SameSite=Lax/Strict` (not sent on cross-site POSTs, main CSRF defence; `None` requires `Secure` and is for genuine cross-site setups) · `Path` (refresh cookie only sent to the refresh endpoint) · `Max-Age`.
**CSRF defence for cookie auth:** `SameSite`, plus a CSRF token (double-submit cookie or header) for state-changing requests, plus checking `Origin`.

**What to say:**
> "For the Flutter app I use bearer tokens in secure storage. For a browser dashboard I'd use HttpOnly, Secure, SameSite cookies, so XSS can't steal the token, and add CSRF protection because the browser sends cookies automatically."

---

## P. WebSockets: upgrade, auth and scaling

**The upgrade:** a WebSocket starts as an HTTP GET with `Upgrade: websocket`, `Connection: Upgrade` and `Sec-WebSocket-Key`. The server answers **`101 Switching Protocols`**, and the same TCP connection becomes a two-way message channel. `wss://` is WebSocket over TLS (always use it in production).

```python
from fastapi import WebSocket, WebSocketDisconnect, Cookie

@app.websocket("/ws/leads")
async def leads_ws(ws: WebSocket, access_token: str | None = Cookie(default=None)):
    user = verify_token_or_none(access_token)
    if user is None or ws.headers.get("origin") not in ALLOWED_ORIGINS:
        await ws.close(code=1008)            # policy violation, before accept()
        return
    await ws.accept()
    await manager.connect(user.tenant_id, ws)
    try:
        while True:
            msg = await ws.receive_json()
            await handle(user, msg)
    except WebSocketDisconnect:
        manager.disconnect(user.tenant_id, ws)
```
(Verified: with a valid cookie the socket accepts and echoes; without it, the client gets close code 1008.)

**Auth options, because browsers can't set an `Authorization` header on `new WebSocket(url)`:**

| Option | How | Trade-off |
|---|---|---|
| **HttpOnly cookie** | Browser sends cookies with the upgrade request automatically | Best for same-site web apps; **must check `Origin`** to stop cross-site WebSocket hijacking (cookies are sent cross-site too) |
| **Short-lived ticket in query string** | `POST /ws-ticket` (normal auth) → one-time 30s token → `wss://.../ws?ticket=...` | Works anywhere; query strings can end up in logs, so keep it one-use and short-lived |
| **First message auth** | Accept, then require `{"type":"auth","token":...}` within a few seconds or close | Simple; the connection is briefly open unauthenticated |
| **Header** | Mobile/native clients *can* set headers | Fine for the Flutter app, not for browsers |

**Re-check on long connections:** tokens expire while sockets stay open; close or re-auth when the token expires.

**Scaling:** each socket lives on one worker in one pod. To broadcast ("lead updated" to everyone in a tenant), publish to **Redis pub/sub** and every worker forwards to its own connected sockets. Nginx needs `proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";` and a long `proxy_read_timeout`. Send pings/heartbeats to detect dead connections.
**WebSocket vs SSE vs polling:** two-way and real-time → WebSocket; server → client only (progress, notifications) → SSE (simpler, plain HTTP, auto-reconnect; what you used for the Vaidya pipeline); infrequent updates → polling.

---

## Q. Background task vs queue (adding work after the response)

```python
# 1. BackgroundTasks: same process, after the response is sent
@router.post("/leads", status_code=201)
async def create_lead(body: LeadCreate, bg: BackgroundTasks, svc = Depends(get_lead_service)):
    lead = await svc.create(body)
    bg.add_task(audit_log, "lead.created", lead.id)      # tiny, OK to lose
    return lead

# 2. Queue: separate worker processes, survives restarts, retries
@router.post("/campaigns/{id}/send", status_code=202)
async def send_campaign(id: int, user = Depends(require_role("admin"))):
    job_id = await jobs.create(kind="send_campaign", ref=id, tenant_id=user.tenant_id)
    await queue.enqueue("send_campaign", job_id)          # arq / RQ / Celery: send_campaign.delay(job_id)
    return {"job_id": job_id, "status": "queued"}
```

| | `BackgroundTasks` | Queue + workers |
|---|---|---|
| Runs in | The API worker, after the response | Separate worker processes/pods |
| Lost on restart/deploy? | **Yes** | No (message stays in the broker) |
| Retries, scheduling, monitoring | No | Yes |
| Uses API capacity? | Yes, competes with requests | No, scales separately |
| Use for | Audit log, cache warm-up, non-critical notification | Emails, OTP, imports, reports, payments follow-ups, LLM pipelines |

> "If losing the work would be a bug, it goes on a queue. `BackgroundTasks` is only for small things that are fine to lose."

Pass **ids, not objects**, to tasks; make tasks **idempotent**; use **separate queues** for urgent (OTP) vs bulk (campaign) work; use the **outbox pattern** if the enqueue must be atomic with a DB write.

---

## R. Pagination

| | Offset (`?page=3&size=20`) | Cursor / keyset (`?after=<last_id>`) |
|---|---|---|
| SQL | `ORDER BY id LIMIT 20 OFFSET 40` | `WHERE id > $1 ORDER BY id LIMIT 20` |
| Speed on deep pages | Slows down: DB reads and discards all skipped rows | Constant: index seek to the cursor |
| New rows inserted while paging | Items shift: duplicates or skipped rows | Stable |
| Jump to page 50 / show total pages | Easy | Not possible (only next/previous) |
| Best for | Small admin tables with page numbers | Feeds, infinite scroll, mobile lists, exports, big tables |

```python
@router.get("/leads", response_model=Page)
async def list_leads(after: int | None = None, limit: int = Query(20, ge=1, le=100),
                     user = Depends(get_current_user), conn = Depends(get_conn)):
    rows = await conn.fetch(
        """SELECT id, name, email, created_at FROM leads
           WHERE tenant_id = $1 AND ($2::bigint IS NULL OR id < $2)
           ORDER BY id DESC LIMIT $3""",
        user.tenant_id, after, limit + 1)                   # fetch one extra to know if there's more
    has_more = len(rows) > limit
    rows = rows[:limit]
    return {"items": rows, "next_cursor": rows[-1]["id"] if has_more else None}
```
- Sorting by a non-unique column (e.g. `created_at`) needs a tie-breaker: cursor = `(created_at, id)` and `WHERE (created_at, id) < ($1, $2)`, with an index on `(tenant_id, created_at, id)`.
- Encode the cursor (base64 of the values) so clients treat it as opaque.
- **Always cap `limit`** (`le=100`) so nobody requests a million rows.
- Total counts on huge tables are expensive (`COUNT(*)` scans); show "100+" or an estimate.
- **DB cursors** (server-side cursors) are a different thing: streaming a big result set in chunks inside one transaction, used in exports and batch jobs, not for HTTP pagination.

---

## S. API and DB optimisation (concept map)

**Measure first:** request timing middleware, tracing (OpenTelemetry), `EXPLAIN ANALYZE`, `pg_stat_statements`, load test with k6/Locust. Optimise the biggest number, not the most interesting one.

| Layer | Techniques | Trade-off |
|---|---|---|
| **Query** | Right index, avoid `SELECT *`, fix N+1 (JOIN / `= ANY($1)`), keyset pagination, do aggregation in SQL | Indexes slow writes |
| **Data shape** | Denormalise a hot read field, summary tables, materialized views refreshed on schedule | Data can be stale; more write paths |
| **Connections** | Pool sizing, PgBouncer, short transactions, async driver | Pool too large hurts the DB |
| **Caching** | Redis cache-aside with TTL; invalidate on write; key by tenant | Stale data, invalidation bugs, memory cost |
| **HTTP** | GZip, smaller payloads, ETag / `Cache-Control`, `ORJSONResponse` | CPU for compression |
| **Concurrency** | `asyncio.gather` for independent I/O calls in one request | More load on downstream services |
| **Offloading** | Queue slow work and return 202 | Eventual consistency; more moving parts |
| **Scaling** | More workers/pods (stateless API), read replicas, partitioning big tables | Replica lag; cost; connection limits |
| **Code** | Avoid blocking calls in async, avoid repeated work in loops, profile CPU hot spots | — |

**Caching pattern to name (cache-aside):** read → check Redis → miss → query DB → store with TTL → return. On write → update DB → delete the cache key. Protect against a **stampede** (many requests missing at once) with a short lock or early refresh.

---

## T. Trade-offs to have ready (one line each)

| Choice | Trade-off |
|---|---|
| `async def` vs `def` endpoint | Async: huge concurrency but one blocking call stalls the loop. Def: safe for blocking libs, limited by thread pool size |
| ORM vs raw SQL | ORM: faster to build, portable, risk of hidden N+1. Raw SQL (your choice): full control and performance, more code, manual mapping |
| Middleware vs dependency | Global and cheap but blind to routes vs per-route, typed and testable |
| Bearer vs cookie | Bearer: no CSRF, XSS risk if in localStorage. Cookie: HttpOnly blocks XSS theft, needs CSRF protection |
| JWT vs server sessions | JWT: stateless, scales, hard to revoke (needs denylist / short expiry). Sessions: easy revoke, needs a shared store (Redis) |
| Offset vs cursor pagination | Page numbers vs speed and stability |
| BackgroundTasks vs queue | Simple vs durable |
| WebSocket vs SSE vs polling | Two-way vs one-way simple vs simplest |
| Cache vs always-fresh | Speed vs staleness and invalidation complexity |
| Monolith vs microservices | Simple deploys and transactions vs independent scaling/ownership, network failures, distributed data |
| Shared schema vs DB per tenant | Cheap and simple vs strong isolation and cost |
| Strong vs eventual consistency | Correct immediately vs available and fast under load |
| Normalised vs denormalised | No duplication vs faster reads with update complexity |

---

## U. Project structure (folders) and code style

```
app/
  main.py                 # create_app(): FastAPI(lifespan=...), middleware, routers, handlers
  core/
    config.py             # pydantic-settings BaseSettings, get_settings() with lru_cache
    security.py           # hashing, JWT create/verify
    logging.py            # structured JSON logging setup
    exceptions.py         # AppError hierarchy + handler registration
  api/
    deps.py               # get_conn, get_current_user, require_role, pagination params
    v1/
      router.py           # include all v1 routers
      leads.py            # HTTP only: parse → call service → return schema
      auth.py
  schemas/                # Pydantic request/response models (LeadCreate, LeadOut, Page)
  services/               # business rules; raise domain errors; no FastAPI imports
  repositories/           # SQL only; every method takes tenant_id
  workers/                # queue tasks (reuse services, not routers)
  db/migrations/          # versioned SQL / Alembic
tests/
  unit/                   # services with fake repos
  integration/            # real Postgres in Docker, TestClient / httpx.AsyncClient
```
**Dependency direction:** `api → services → repositories → db`. Services never import FastAPI, so workers and scripts can reuse them. Same Clean Architecture idea as your Flutter apps (presentation / domain / data).

**Code style:**
- PEP 8, enforced by **ruff** (lint + format) or black + isort; **mypy** or pyright for types; pre-commit hooks; run them in CI (GitHub Actions, which is on your resume).
- Type hints everywhere, including return types; Pydantic models at boundaries.
- `snake_case` functions and variables, `PascalCase` classes, `UPPER_CASE` constants; plural resource names in URLs (`/leads`).
- Small functions, one responsibility; no business logic in routers; no SQL in services.
- Config from environment, never hardcoded secrets.
- Logs structured (JSON) with request id, never log passwords, tokens or full PII.
- Docstrings for non-obvious behaviour; comments explain *why*, not *what*.
- Tests for unhappy paths (401, 403, 404 cross-tenant, 409, 422), not only the happy path.

---

## Practice order
Say each answer aloud once, then explain the trade-offs without looking:
1. **D (Depends) → K (DB session) → F (pooling)**: they connect to your production stories.
2. **I (middleware order) → J (auth placement)**: very likely follow-ups.
3. **M (errors) → N (CORS) → O (cookies/HTTPS) → P (WebSockets)**.
4. **Q (jobs) → R (pagination) → S (optimisation) → T (trade-offs)**.
5. **E, C, A, H, U, L** as a final skim, then **G** (walk through a request) out loud.
