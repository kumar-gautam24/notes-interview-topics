# Document 02 — FastAPI / ASGI (Questions 46–100)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 46. What is FastAPI?

**Definition.** A Python web framework for building APIs, built on Starlette (ASGI toolkit) and Pydantic (validation). Its defining idea: **type hints are the source of truth**. One annotation simultaneously produces request parsing, validation, serialisation, OpenAPI schema, and editor autocomplete.

**Why it exists.** Before it, you wrote the same shape three times — a request parser, a validation schema, and API documentation — and they drifted apart. FastAPI collapses them into one declaration.

**Implementation.**
```python
@app.post("/charges", response_model=ChargeOut, status_code=201)
async def create_charge(body: ChargeIn, db: DB = Depends(get_db)) -> ChargeOut:
    ...
```
From this single signature FastAPI derives: parse JSON body → validate against `ChargeIn` → 422 with structured errors if invalid → resolve `get_db` → run → validate output against `ChargeOut` → serialise → register in OpenAPI.

**Failure.** Assuming it's fast *because it's async*. It's fast because Starlette/uvloop are efficient, but one blocking call in an `async def` endpoint destroys throughput entirely (Q36, Document 01).

**Trade-off.** Enormous productivity gain and strong runtime guarantees, at the cost of per-request validation overhead and a hard dependency on Pydantic's model of the world.

---

## 47. What is ASGI?

**Definition.** Asynchronous Server Gateway Interface — the async successor to WSGI. It specifies a contract between a server and an application: the app is a callable `async def app(scope, receive, send)`.

- `scope` — a dict describing the connection (type, path, headers, method)
- `receive` — an awaitable that yields incoming event dicts
- `send` — an awaitable that pushes outgoing event dicts

**Why it matters.** WSGI is synchronous and request/response only — one call in, one return out. It structurally cannot express WebSockets, server-sent events, streaming, or long-lived connections. ASGI's event-based model can.

**Implementation.** A minimal ASGI app:
```python
async def app(scope, receive, send):
    assert scope["type"] == "http"
    await send({"type": "http.response.start", "status": 200,
                "headers": [(b"content-type", b"text/plain")]})
    await send({"type": "http.response.body", "body": b"ok"})
```
`scope["type"]` is `"http"`, `"websocket"`, or `"lifespan"` — that last one is how startup/shutdown hooks work.

**Failure.** Deploying an ASGI app under a WSGI server (plain Gunicorn with a sync worker). It won't work; you need `uvicorn.workers.UvicornWorker`.

**Trade-off.** ASGI enables long-lived connections and concurrency, but the whole middleware/library ecosystem had to be rewritten — this is why `requests`, `psycopg2`, and older Django middleware don't fit.

---

## 48. What is Uvicorn?

**Definition.** An ASGI server. It owns the socket, speaks HTTP/1.1 and WebSocket, runs the event loop, and calls your ASGI app.

**Implementation details worth knowing.** It uses `uvloop` (a libuv-based event loop, faster than asyncio's default) and `httptools` (a C HTTP parser) when installed — `pip install "uvicorn[standard]"`. Each Uvicorn worker is one process with one event loop.

**Uvicorn vs Gunicorn.** Gunicorn is a process manager: it forks workers, restarts dead ones, handles signals, does rolling restarts. Uvicorn is the protocol server. In production you typically run Gunicorn *managing* Uvicorn workers:
```bash
gunicorn app:app -k uvicorn.workers.UvicornWorker -w 4
```
Modern Uvicorn also has `--workers`, but Gunicorn's process supervision is more battle-tested. In Kubernetes, many teams run a single Uvicorn process per pod and let the orchestrator do the supervising — that's cleaner, because K8s already handles restarts and scaling.

**Failure.** Running `--workers 4` inside a container limited to 1 CPU. Four processes contending for one core is slower than one, and uses 4× the memory.

**Trade-off.** More workers = more parallelism and memory isolation, but 4× memory and no shared state.

---

## 49. What is Starlette?

**Definition.** The lightweight ASGI toolkit FastAPI is built on. It provides routing, middleware, request/response objects, WebSockets, background tasks, test client, and static files.

**The division of labour** — worth stating precisely, because it shows you know where the seams are:

| Layer | Owns |
|---|---|
| Uvicorn | Socket, HTTP parsing, event loop |
| Starlette | Routing, middleware, `Request`/`Response`, WebSocket |
| FastAPI | Dependency injection, Pydantic validation, OpenAPI generation |
| Pydantic | Type coercion, validation, serialisation |

**Why it matters practically.** When you hit something FastAPI doesn't document, the answer is often in Starlette's docs — middleware, streaming responses, `request.state`, custom exception handlers. And you can drop to Starlette primitives inside FastAPI at any time.

**Real example.** `StreamingResponse` for SSE is a Starlette class, not a FastAPI one.

---

## 50. What is a path operation?

**Definition.** The pairing of an HTTP method with a path, and the function that handles it. `@app.get("/users/{id}")` — `get` is the operation, `/users/{id}` is the path, the decorated function is the handler.

**Why the term.** It comes from OpenAPI, where each path has a set of operations. FastAPI's decorator arguments map directly onto OpenAPI fields: `summary`, `description`, `tags`, `response_model`, `status_code`, `deprecated`, `operation_id`.

**Failure.** Route ordering. FastAPI matches in registration order, so:
```python
@app.get("/users/{user_id}")   # registered first
@app.get("/users/me")          # unreachable — "me" matches {user_id}
```
Declare specific paths before parameterised ones.

**Trade-off.** Declarative registration gives free documentation but means route conflicts are a runtime/ordering concern rather than a compile-time error.

---

## 51. Path vs query parameter?

**Path parameter** — part of the URL structure, identifies a resource, required by definition: `/orders/{order_id}`.

**Query parameter** — after `?`, modifies how the resource is returned, usually optional: `/orders?status=paid&limit=20`.

```python
@app.get("/orders/{order_id}")
async def get_order(
    order_id: UUID,                              # path — inferred from the path string
    include_items: bool = False,                 # query — has a default
    limit: int = Query(20, ge=1, le=100),        # query with constraints
):
```
FastAPI decides which is which by matching names against the path template. Anything not in the path, and not a Pydantic model or dependency, becomes a query parameter.

**The design rule:** if changing it gives you a *different resource*, it's a path parameter. If it gives you a *different view of the same resource*, it's a query parameter. Filtering, sorting, and pagination are query parameters.

**Failure.** Putting a secret in a query parameter. Query strings appear in access logs, browser history, and `Referer` headers. Tokens belong in headers.

**Trade-off.** Path parameters cache better and read better; query parameters compose better for optional combinations.

---

## 52. Request model vs response model?

**Request model** — what the client is allowed to send. **Response model** — what you promise to return.

**Why they must be different classes.** This is the point of the question.

```python
class UserCreate(BaseModel):        # request
    email: EmailStr
    password: str                   # accepted

class UserOut(BaseModel):           # response
    id: UUID
    email: EmailStr
    created_at: datetime
    # password absent — cannot leak
```

**The security property.** `response_model` filters the output. If your ORM object has `password_hash`, `internal_notes`, and `is_admin`, and your `UserOut` doesn't declare them, they are stripped. Returning the raw ORM object with no `response_model` leaks everything on it — including columns added by a later migration that nobody re-reviewed.

**Also prevents mass assignment.** If the request model doesn't declare `is_admin`, a client sending `{"is_admin": true}` can't set it. (Add `model_config = ConfigDict(extra="forbid")` to reject unknown fields loudly rather than ignoring them.)

**Failure.** One shared model for both directions. Either the client can set fields it shouldn't, or the response exposes fields it shouldn't. Usually both.

**Trade-off.** More classes to maintain and keep in sync, in exchange for a hard boundary. Worth it every time. Use inheritance for the shared core: `UserBase` → `UserCreate`, `UserUpdate`, `UserOut`.

---

## 53. What is Pydantic validation?

Covered in depth at Q18 (Document 01). The FastAPI-specific behaviour:

- Validation failure raises `RequestValidationError`, which FastAPI converts to **HTTP 422** with a structured body listing each failing field, its location (`body`/`query`/`path`), and the error type.
- Validation runs *before* your function body. Your code never sees invalid data.
- `response_model` validation happens *after* your function returns. If your handler returns something that doesn't match, you get a 500 — which is correct: it's your bug, not the client's.

**Failure.** Expecting 400 and getting 422. If your API contract or clients require 400, override the handler:
```python
@app.exception_handler(RequestValidationError)
async def validation_handler(request, exc):
    return JSONResponse(status_code=400, content={"errors": exc.errors()})
```

**The AI-engineering connection.** The same mechanism validates LLM structured output. `ChargeIn` validating a client request and `ExtractedInvoice` validating a model's JSON are the same machinery — that's a good thing to point out in an AI-engineering interview.

---

## 54. What is dependency injection? (FastAPI-specific)

Q16 covered the concept. FastAPI's implementation:

```python
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session                 # request runs here
        # cleanup after response

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    ...

@app.get("/me")
async def me(user: User = Depends(get_current_user)):
    return user
```

**Key behaviours:**
- Dependencies form a **graph**, resolved depth-first before the handler runs.
- Results are **cached per request** by default — `get_db` called by three dependencies yields one session, not three. Disable with `Depends(fn, use_cache=False)`.
- A dependency using `yield` is a context manager: code before `yield` is setup, after is teardown. Teardown runs after the response is generated.
- Dependencies appear in the OpenAPI schema (security schemes, required headers).

**Failure.** Heavy work in a dependency that most routes don't need — every request pays for it. And: a `yield` dependency that raises during teardown produces confusing errors after the response has already started.

**Trade-off.** Enormously reduces duplication and makes testing trivial (`app.dependency_overrides[get_db] = fake_db`), at the cost of implicit control flow — the handler body doesn't show you that auth ran.

---

## 55. What is middleware?

**Definition.** Code that wraps every request/response cycle, running before the route is matched and after the response is produced.

```python
@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid4()))
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response
```

**Use for:** request IDs, timing, CORS, GZip, security headers, global logging, tracing spans.

**Failure — the important one.** Middleware runs *outside* FastAPI's exception handling for `HTTPException`. An exception raised in middleware bypasses your handlers and returns a bare 500. Also, `BaseHTTPMiddleware` (what the `@app.middleware` decorator uses) has known interactions with streaming responses and can buffer them — for SSE, prefer pure ASGI middleware.

Second failure: reading `await request.body()` in middleware consumes the stream, and the route handler then sees an empty body. You must re-inject it, which is why body-logging middleware is harder than it looks.

**Trade-off.** Middleware is truly global — cheap to add, but it runs on health checks and static files too. Anything route-specific belongs in a dependency instead.

---

## 56. What is an exception handler?

**Definition.** A function registered to convert a specific exception type into an HTTP response.

```python
class InsufficientCredits(Exception):
    def __init__(self, needed: int, available: int):
        self.needed, self.available = needed, available

@app.exception_handler(InsufficientCredits)
async def handle_credits(request: Request, exc: InsufficientCredits):
    return JSONResponse(
        status_code=402,
        content={"error": "insufficient_credits",
                 "needed": exc.needed, "available": exc.available},
    )
```

**Why.** Your service layer raises domain exceptions and knows nothing about HTTP. The handler is the single place that maps domain failure to protocol. This keeps HTTP concerns out of business logic — a real architectural win, not just tidiness.

**Failure.** Handling `Exception` broadly and returning the message to the client. That leaks stack traces, SQL, and internal paths. Log the detail, return a generic message plus a correlation ID.

**Trade-off.** Centralised mapping is consistent but distant — reading the service code doesn't tell you what status code its exception produces. Document the mapping in one file.

---

## 57. What is OpenAPI?

**Definition.** A standard, machine-readable specification for describing REST APIs — paths, operations, schemas, auth, examples. FastAPI generates it automatically from your type hints, served at `/openapi.json`, rendered at `/docs` (Swagger UI) and `/redoc`.

**Why it's valuable beyond documentation:**
- Client SDK generation for any language
- Contract testing in CI (did this PR break the contract?)
- Mock servers from the spec
- API gateway configuration
- The spec becomes the reviewable artefact in PRs

**Failure.** Leaving `/docs` public on an internal service. Disable in production: `FastAPI(docs_url=None, redoc_url=None, openapi_url=None)` or gate behind auth.

**Trade-off.** Auto-generation guarantees the docs match the code — but only as well as your models are named and described. Generated docs full of `Body_create_user_users_post` are technically accurate and practically useless; name your models.

---

## 58. What does `response_model` do?

Four things:

1. **Filters** — fields not in the model are removed from the output. This is the security property (Q52).
2. **Validates** — your return value must conform, or you get a 500.
3. **Serialises** — converts ORM objects, UUIDs, datetimes, and Enums into JSON-safe values.
4. **Documents** — becomes the response schema in OpenAPI.

```python
@app.get("/users/{id}", response_model=UserOut,
         response_model_exclude_none=True)
```

**Modern alternative.** In recent FastAPI you can use the return annotation instead, which is cleaner and type-checkable:
```python
async def get_user(id: UUID) -> UserOut:
```
An explicit `response_model=` argument still wins if both are present — useful when you want to return a subclass but document the base.

**Failure.** Performance. Validating a 10,000-item response is real CPU work, and it happens on the event loop. For large payloads consider `response_class=ORJSONResponse` and skipping validation on trusted internal data.

**Trade-off.** Safety and documentation vs. serialisation cost on every response.

---

## 59. What is APIRouter?

**Definition.** A sub-application for grouping related routes, with shared prefix, tags, dependencies, and responses.

```python
# routers/orders.py
router = APIRouter(
    prefix="/orders",
    tags=["orders"],
    dependencies=[Depends(require_authenticated)],   # applies to every route
    responses={404: {"model": ErrorOut}},
)

@router.get("/{order_id}")
async def get_order(order_id: UUID): ...

# main.py
app.include_router(router, prefix="/v1")
```

**Why.** One `main.py` with 200 routes is unmaintainable. Routers give you file-per-domain organisation, versioning (`/v1`, `/v2` from the same router), and router-level auth.

**Note on `dependencies=[...]`** — those run for their side effects; their return values aren't injected. That's the right tool for "every route here needs a valid token."

**Failure.** Circular imports when routers import from `main`. Keep `app` creation in one file that imports routers, never the reverse.

---

## 60. How do you manage configuration/secrets?

**The rule: configuration comes from the environment, never from code, and secrets never touch the image or the repo.**

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: PostgresDsn
    redis_url: RedisDsn
    llm_api_key: SecretStr                  # repr() shows '**********'
    environment: Literal["dev", "staging", "prod"] = "dev"
    log_level: str = "INFO"

@lru_cache
def get_settings() -> Settings:
    return Settings()
```

**Why `BaseSettings`:** it validates config at **startup**. A missing or malformed `DATABASE_URL` crashes the process immediately with a clear message, instead of producing a confusing failure on the first request an hour later. Fail fast on config is a genuinely important production property.

**Why `SecretStr`:** it prevents accidental logging. Its `repr` is masked, so a debug dump or an exception context can't spill the key. You call `.get_secret_value()` deliberately.

**Secrets in production:** AWS Secrets Manager or SSM Parameter Store (SecureString), injected as environment variables at container start, or fetched at boot with an IAM role. Never baked into the image — image layers are permanent and readable by anyone who can pull the image.

**Failure.** Committing `.env`. Add it to `.gitignore` on day one, commit a `.env.example` with dummy values, and run a secret scanner (`gitleaks`, `trufflehog`) in CI. A leaked key in git history requires rotation, not deletion — the history persists in every clone.

**Trade-off.** Env vars are simple and universal but flat, untyped at the OS level, and visible in `/proc/<pid>/environ` to anyone on the box. For high-sensitivity secrets, fetch at runtime and keep them only in memory.

---

# L2 — Engineering

## 61. Walk through a request from Uvicorn to an endpoint.

This is a favourite question because it separates people who *use* the framework from people who understand it.

1. **Kernel** accepts the TCP connection on the listening socket.
2. **Uvicorn** reads bytes, parses HTTP with `httptools`, builds the ASGI `scope` dict (type, method, path, headers, query string, client).
3. Uvicorn calls the ASGI app: `await app(scope, receive, send)`.
4. **Middleware stack** runs outside-in. Each wraps `call_next`. This is where CORS, GZip, request IDs, and tracing sit.
5. **Starlette router** matches the path against compiled regexes in registration order, extracting path parameters.
6. **FastAPI** builds the dependency graph for that route and resolves it depth-first. `yield` dependencies run their setup half.
7. **Request parsing and validation** — body read via `receive`, JSON parsed, Pydantic validates path/query/header/body. On failure: short-circuit to 422, handler never runs.
8. **Handler dispatch** — if `async def`, awaited directly on the event loop. If plain `def`, dispatched to the threadpool via `run_in_threadpool`. *This branch is the single most important thing to know.*
9. **Handler runs**, returns a value.
10. **`response_model` validation and serialisation** — filter fields, coerce types, JSON-encode.
11. **Response object built**, status and headers set.
12. **Middleware unwinds** inside-out — each sees the response on the way back.
13. **`send`** emits `http.response.start` (status + headers) then one or more `http.response.body` events.
14. **`yield` dependency teardown** runs, then `BackgroundTasks` if any.
15. Uvicorn writes bytes; connection is kept alive or closed.

**The two facts to emphasise:** validation happens before your code (step 7), and the sync/async branch at step 8 determines whether a blocking call is survivable.

---

## 62. When should an endpoint be `async def`?

When the handler and **everything it calls** is non-blocking:

- `asyncpg` / SQLAlchemy async / `databases`
- `httpx.AsyncClient` for outbound calls
- `redis.asyncio`
- `aiofiles` for file I/O
- Pure in-memory computation that is genuinely fast (microseconds)

**The benefit:** the endpoint runs directly on the event loop with no thread-switch overhead, and thousands can be in flight concurrently on one worker.

**Concrete rule:** `async def` if you can honestly answer "there is no blocking call anywhere in this call tree." If you can't audit the call tree, use `def`.

**Real example.** An SSE streaming endpoint *must* be async — it holds the connection open for minutes while yielding chunks. A thread per connection would not scale past a few hundred.

---

## 63. When should it be normal `def`?

When any part of the handler blocks and you can't or won't make it async:

- `psycopg2`, `pymysql`, any sync DB driver
- `requests`, `boto3`
- Sync vendor SDKs
- CPU-bound work of moderate cost
- Blocking file I/O

FastAPI runs `def` handlers in an `anyio` threadpool (default capacity 40 threads), so blocking there does **not** block the event loop.

**The counter-intuitive point worth saying out loud in an interview:** *wrong async is more dangerous than no async.* An `async def` endpoint with one `requests.get` in it takes down the entire worker for every concurrent user. The same code in a `def` endpoint is merely slow for that one request. Given a codebase you don't fully control, `def` is the safer default.

**The limit.** The threadpool is bounded. 40 concurrent slow `def` requests saturate it and everything queues. Raise it via `anyio.to_thread.current_default_thread_limiter().total_tokens`, but the real fix is to stop blocking.

**Never do this:** `async def` with `run_in_threadpool` inside — you've paid async's costs and gained nothing. Just use `def`.

---

## 64. Why can a blocking DB driver hurt an async endpoint?

Because the event loop is a single thread running a callback queue. A blocking driver call is a syscall that doesn't yield, so the loop is frozen inside it. Every other request, every health check, every background task on that worker stops.

**The numbers make it vivid.** Query takes 50ms. Async driver: 100 concurrent requests all complete in ~50–60ms because the loop interleaves the waits. Blocking driver in `async def`: the queries serialise. The 100th request waits 5 seconds. Add a 1-second Kubernetes liveness timeout and the pod gets killed and restarted, mid-traffic.

**Why it's insidious:** it looks fine in development. One developer, one request at a time, 50ms responses. It only appears under concurrency, which is production.

**Detection:** latency on *unrelated* endpoints rises together; `py-spy dump` shows the loop thread inside `psycopg2` C code; loop-lag metrics spike.

**Fixes:** `asyncpg` or SQLAlchemy's async engine; or make the endpoint `def`; or `await asyncio.to_thread(...)`.

---

## 65. How does FastAPI resolve dependencies?

At **startup**, FastAPI inspects each route's signature (via `inspect.signature` and type hints), finds every `Depends(...)`, recursively inspects those, and builds a static dependency tree per route. This is why `functools.wraps` matters (Q8) — a decorator that hides the signature breaks this.

At **request time** it walks that tree depth-first:
- Leaf dependencies resolve first
- Each result is cached in a per-request dict keyed by the dependency callable
- `async def` dependencies are awaited; `def` dependencies go to the threadpool (same rule as handlers)
- `yield` dependencies push their teardown onto an `AsyncExitStack`
- After the response is generated, the exit stack unwinds in reverse order

**Failure.** Expecting a dependency to run twice within a request. Caching means it runs once. If you need fresh values (a new UUID per call), use `Depends(fn, use_cache=False)`.

**Trade-off.** Static analysis at startup makes request-time resolution fast, but it means dependencies can't be chosen dynamically based on request data — you have to branch inside the dependency instead.

---

## 66. How do dependency chains work?

Dependencies can depend on dependencies, arbitrarily deep:

```python
def get_settings() -> Settings: ...

async def get_db(s: Settings = Depends(get_settings)): ...

async def get_token(cred = Depends(oauth2_scheme)) -> str: ...

async def get_current_user(
    token: str = Depends(get_token),
    db = Depends(get_db),
) -> User: ...

async def require_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(403)
    return user

@app.delete("/users/{id}")
async def delete_user(id: UUID, admin: User = Depends(require_admin)): ...
```

The tree resolves bottom-up: settings → db + token → current_user → require_admin → handler. `get_db` is requested by two branches but runs once, thanks to per-request caching.

**Why this design is good.** Each layer is independently testable and independently overridable. `app.dependency_overrides[get_current_user] = lambda: fake_user` replaces the whole auth chain in tests with one line.

**Failure.** Deep chains make failures hard to locate — a 401 from four levels down doesn't say which level. Include the layer in your error detail.

---

## 67. How do you create request-scoped resources?

The `yield` dependency is the mechanism:

```python
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
```

Setup before `yield`, resource handed to the handler, teardown after the response.

**Ordering guarantee:** teardown runs *after* the response body is generated but *before* it's fully sent in some configurations — which matters for streaming. If you `yield` a DB session and then return a `StreamingResponse` that lazily queries, the session may already be closed when the stream is consumed. That's a real and confusing bug; for streaming, acquire the connection inside the generator instead.

**Failure.** Committing in the dependency *and* in the service layer — double commit, or a commit that undoes an intentional rollback. Pick one owner for transaction boundaries (see Q73).

**Trade-off.** Request-scoped resources are clean and leak-proof, but they tie resource lifetime to request lifetime — bad for anything that should outlive a request (the HTTP client, the connection pool itself). Those belong in lifespan.

---

## 68. Middleware vs dependency?

| | Middleware | Dependency |
|---|---|---|
| Scope | Every request, including 404s and unmatched paths | Only routes that declare it |
| Runs | Before routing | After routing |
| Sees | Raw `Request`, raw `Response` | Parsed, validated parameters |
| Can | Modify response headers/body | Return values into the handler |
| Errors | Bypass FastAPI exception handlers | Handled normally |
| OpenAPI | Invisible | Documented (security schemes, params) |
| Testing | Requires a full request | Overridable in one line |

**Decision rule:**
- Cross-cutting, needs to see *everything*, doesn't produce a value → **middleware** (request ID, CORS, GZip, timing, security headers)
- Route-specific, produces a value, should be documented and testable → **dependency** (auth, db session, rate limit for a route group, feature flag)

**Auth specifically:** use a dependency. It appears in OpenAPI as a security scheme, is override-able in tests, can vary per route, and its `HTTPException(401)` flows through normal error handling. Auth in middleware means hardcoding path exclusions for `/health`, `/docs`, and `/metrics` — a list that always drifts.

---

## 69. Where should authentication happen?

**In a dependency, at the router or route level.**

```python
async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: AsyncSession = Depends(get_db),
) -> User:
    try:
        payload = jwt.decode(token, settings.jwt_secret,
                             algorithms=["HS256"],
                             audience=settings.audience,
                             issuer=settings.issuer)
    except jwt.ExpiredSignatureError:
        raise HTTPException(401, "token expired",
                            headers={"WWW-Authenticate": "Bearer"})
    except jwt.InvalidTokenError:
        raise HTTPException(401, "invalid token")

    user = await db.get(User, UUID(payload["sub"]))
    if user is None or not user.is_active:
        raise HTTPException(401, "user not found or inactive")
    return user
```

**Points that matter and are commonly missed:**
- Pin `algorithms=` explicitly. Omitting it historically allowed the `alg: none` attack.
- Verify `aud` and `iss`, not just the signature. A valid token for a *different* service is still a valid signature.
- Check the user is still active — a token issued 20 minutes ago to a since-disabled account is cryptographically valid.
- Return 401 with `WWW-Authenticate`, not 403. 401 = "I don't know who you are"; 403 = "I know, and no."

**Where NOT to put it:** inside each handler body (duplicated, forgettable — one missed route is a breach), or in middleware (path exclusion lists drift).

**Real example.** Your bank's question 543 — "explain the soft-delete auth bug" — is almost certainly this: a user soft-deleted in the database but their JWT still valid, because the dependency verified the signature and never re-checked the row. The fix is exactly the `is_active` check above.

---

## 70. Where should authorization happen?

**Split it, deliberately:**

**Coarse-grained (role/scope) → dependency.** "Is this user an admin?" doesn't need the resource.
```python
def require_scope(scope: str):
    async def check(user: User = Depends(get_current_user)) -> User:
        if scope not in user.scopes:
            raise HTTPException(403, f"missing scope: {scope}")
        return user
    return check

@router.delete("/{id}", dependencies=[Depends(require_scope("orders:delete"))])
```

**Fine-grained (ownership) → service layer, and preferably in the query.** "Does this user own *this* order?" requires loading the resource.

**The critical implementation point:** don't fetch then check. Filter in the query.
```python
# Wrong — leaks existence, and it's easy to forget the check
order = await db.get(Order, order_id)
if order.tenant_id != user.tenant_id:
    raise HTTPException(403)

# Right — non-existent and not-yours are indistinguishable, and unforgettable
order = await db.scalar(
    select(Order).where(Order.id == order_id,
                        Order.tenant_id == user.tenant_id))
if order is None:
    raise HTTPException(404)
```
Returning 404 rather than 403 for another tenant's resource prevents enumeration: an attacker can't distinguish "exists but not yours" from "doesn't exist."

**The strongest form** for multi-tenant systems: PostgreSQL Row-Level Security with the tenant ID set as a session variable. Then a forgotten `WHERE` clause cannot leak data, because the database enforces it. That's defence in depth — this is the answer to questions 520 and 384.

---

## 71. How do you structure a large FastAPI application?

```
app/
  main.py                 # app factory, router registration, lifespan
  config.py               # Settings
  api/
    deps.py               # shared dependencies
    v1/
      orders.py           # APIRouter — HTTP concerns only
      users.py
  services/
    order_service.py      # business logic — no HTTP, no FastAPI imports
  repositories/
    order_repo.py         # data access — no business rules
  models/                 # SQLAlchemy ORM
  schemas/                # Pydantic request/response
  core/
    security.py
    exceptions.py         # domain exceptions
  workers/
    tasks.py
  db/
    session.py
    migrations/           # Alembic
tests/
```

**The rules that make it hold up:**
1. **Dependencies point inward.** Routers import services; services import repositories; nothing imports routers.
2. **`services/` must not import FastAPI.** If a service raises `HTTPException`, the layering has already failed — it can no longer be called from a worker or CLI. Raise domain exceptions; map them at the edge (Q56).
3. **Separate ORM models from Pydantic schemas.** Coupling them means a DB migration silently changes your API contract.
4. **Use an app factory** — `def create_app() -> FastAPI` — so tests build isolated instances with different settings.
5. **Split by domain, not by layer, once it's big.** At 50 routes, `orders/` containing its router, service, repo, and schemas beats four parallel trees.

**Failure.** Business logic in route handlers. It becomes untestable without HTTP, unreusable from workers, and impossible to call from a scheduled job.

---

## 72. Why separate router/service/repository?

**Router** — HTTP only: parse, validate, call service, map result to status code.
**Service** — business rules, orchestration, transaction boundaries. Framework-agnostic.
**Repository** — data access. Query construction only, no business rules.

**The concrete payoffs:**

1. **The same logic runs from multiple entry points.** `charge_user()` is called by an HTTP route, a Celery worker, an admin CLI, and a scheduled job. If it lived in the handler, you'd have four copies.
2. **Testing without HTTP.** Service tests are plain function calls — milliseconds, no client, no server.
3. **Swappable persistence.** Moving from raw SQL to SQLAlchemy, or adding a cache, touches the repository only.
4. **Transactions have an obvious home.** The service owns the unit of work; the repository doesn't commit.

**Failure.** An "anaemic" split where the service just forwards to the repository with no logic — pure ceremony. If a service has no rules, you don't need it yet. Add layers when they earn their keep.

**Trade-off.** More files and more indirection. For a 5-endpoint service this is over-engineering; at 50 endpoints with a team it is the difference between maintainable and not. Say this trade-off out loud — interviewers are checking whether you apply patterns reflexively or with judgement.

---

## 73. Where should a transaction begin/end?

**In the service layer, at the boundary of a business operation** — one transaction per use case.

```python
# service
async def place_order(self, user_id: UUID, items: list[Item]) -> Order:
    async with self.uow:                      # transaction begins
        await self.credits.deduct(user_id, total)     # atomic UPDATE
        order = await self.orders.create(user_id, items)
        await self.outbox.enqueue("order.created", order.id)
        await self.uow.commit()               # transaction ends
    return order
```

**Why the service, not the repository:** a repository method that commits makes composition impossible. If `deduct()` commits and `create()` then fails, the credits are gone and no order exists. The unit of work must span the whole business operation.

**Why not the route handler:** then the operation can't be reused from a worker (Q72).

**The rules:**
1. One transaction per business operation.
2. Repositories never commit.
3. **Never call an external API inside a transaction** (Q145). An HTTP call taking 30 seconds holds row locks for 30 seconds, blocks vacuum, and exhausts the connection pool. Do external calls before or after — and if the result must be atomic with the DB write, that's what the outbox is for.
4. Keep transactions short. Read what you need, decide, write, commit.
5. Don't hold a transaction across a `yield` to a streaming response.

**Trade-off.** Longer transactions give stronger consistency but worse concurrency and more deadlock risk. Prefer short transactions plus idempotency over long transactions plus optimism.

---

## 74. How do you centralize errors?

Three layers working together:

**1. A domain exception hierarchy** — no HTTP knowledge:
```python
class AppError(Exception):
    code: str = "internal_error"
    status: int = 500

class NotFound(AppError):
    code, status = "not_found", 404

class InsufficientCredits(AppError):
    code, status = "insufficient_credits", 402
```

**2. One handler that maps them:**
```python
@app.exception_handler(AppError)
async def handle_app_error(request: Request, exc: AppError):
    return JSONResponse(
        status_code=exc.status,
        content={"error": {"code": exc.code, "message": str(exc),
                           "request_id": request.state.request_id}},
    )

@app.exception_handler(Exception)
async def handle_unexpected(request: Request, exc: Exception):
    logger.exception("unhandled", extra={"request_id": request.state.request_id})
    return JSONResponse(500, {"error": {"code": "internal_error",
                                        "message": "An unexpected error occurred",
                                        "request_id": request.state.request_id}})
```

**3. A request ID in every response**, so a user reporting "it failed" gives you a string that finds the exact log line and trace.

**Failure.** Returning `str(exc)` for unexpected errors — leaks SQL, file paths, and internal hostnames. Log the detail, return the correlation ID.

---

## 75. How do you return consistent API errors?

**Pick one envelope and never deviate.** RFC 9457 (Problem Details for HTTP APIs, which obsoleted RFC 7807) is the standard choice:

```json
{
  "type": "https://api.example.com/errors/insufficient-credits",
  "title": "Insufficient credits",
  "status": 402,
  "detail": "Operation requires 500 credits; balance is 120.",
  "instance": "/v1/runs/9f2c",
  "request_id": "01H8X...",
  "errors": [{"field": "amount", "message": "must be positive"}]
}
```

**The properties that make an error format good:**
1. **Machine-readable code** — clients branch on `type`/`code`, never on the human message. If they parse `detail`, you can never rewrite the message.
2. **Human-readable message** — for the developer reading logs.
3. **Field-level detail** for validation errors, so a UI can highlight the right input.
4. **Correlation ID** always.
5. **Stable codes** treated as part of your public contract.
6. **No internals.**

Normalise FastAPI's own 422 into the same shape (Q53) — otherwise you have two error formats and every client needs two parsers.

**Status code discipline:** 400 malformed, 401 unauthenticated, 403 authenticated but forbidden, 404 not found *or* not yours, 409 state conflict, 422 semantically invalid, 429 rate limited (with `Retry-After`), 5xx your fault. Never return 200 with `{"success": false}` — it breaks every retry, monitor, and cache in the stack.

---

# L3 — Production / failure

## 76. A request starts a 5-minute AI job. Why not hold HTTP open?

Every layer between client and server will break it:

1. **Load balancers time out.** AWS ALB default idle timeout is 60 seconds. Nginx `proxy_read_timeout` defaults to 60s. Cloudflare caps at 100s. Your 5-minute request dies at 60 seconds with a 504.
2. **A worker slot is held for 5 minutes.** With 4 workers you can serve *4 concurrent jobs*, and every other endpoint is starved.
3. **A DB connection may be held** for the duration, exhausting the pool.
4. **Deploys kill it.** Any rolling restart during those 5 minutes loses the work with no record it ever started.
5. **The client can't retry safely** — was it done? Half done? No way to know.
6. **Mobile clients change networks.** A phone moving from Wi-Fi to cellular drops the connection; the work is orphaned.
7. **No progress visibility.** The user stares at a spinner for 5 minutes with no signal.

**The correct pattern:**
```
POST /runs         → 202 Accepted, {"run_id": "...", "status": "queued"}
GET  /runs/{id}    → {"status": "running", "progress": 0.4}
GET  /runs/{id}/events  → SSE stream of progress
```
The request enqueues durable work and returns immediately. A separate worker process executes it. State lives in the database, so a crash means resume, not loss.

**The rule of thumb:** if it can exceed ~10 seconds, it is a job, not a request. If it can exceed 30 seconds, this is not negotiable.

---

## 77. How do you return a run ID?

```python
@router.post("/runs", status_code=202, response_model=RunAccepted)
async def create_run(body: RunRequest,
                     user: User = Depends(get_current_user),
                     svc: RunService = Depends(get_run_service)):
    run = await svc.enqueue(user.id, body)
    return RunAccepted(
        run_id=run.id,
        status=run.status,
        status_url=f"/v1/runs/{run.id}",
        events_url=f"/v1/runs/{run.id}/events",
    )
```

**The details that matter:**

- **202 Accepted**, not 200 or 201. 202 means "received, not yet processed" — precisely true.
- **Generate the ID server-side** as a UUID (v7 if you want time-ordering for index locality).
- **Persist before enqueueing.** Write the run row in a transaction, enqueue via outbox. If you enqueue first and the DB write fails, a worker picks up a job whose row doesn't exist.
- **Include the URLs** so clients don't hardcode paths (HATEOAS-lite; cheap and genuinely useful).
- **Accept a client idempotency key.** A retried POST with the same key returns the *existing* run rather than creating a second one. Without this, a flaky mobile network produces duplicate expensive AI jobs, each costing you real money.

```python
class RunRequest(BaseModel):
    idempotency_key: str | None = None
```
Unique index on `(user_id, idempotency_key)`; on conflict, return the existing run with 200 instead of 202.

---

## 78. How does a client learn a job completed?

Four mechanisms, with honest trade-offs:

| | Latency | Server cost | Complexity | Works through firewalls |
|---|---|---|---|---|
| **Polling** | Poll interval | High at scale | Trivial | Always |
| **Long polling** | Near-instant | Holds connections | Low | Usually |
| **SSE** | Instant | One connection per client | Low | Usually |
| **WebSocket** | Instant | One connection per client | Higher | Sometimes blocked |
| **Webhook** | Instant | Lowest | Medium | N/A (server-to-server) |

**Practical recommendation:** SSE for a browser or mobile client watching a run; webhooks for server-to-server; polling as the universal fallback that must always work.

**Polling done properly** — most people do it badly:
- Exponential backoff, not a fixed 1-second interval (fixed intervals with 10k clients is a self-inflicted DDoS)
- `ETag` / `If-None-Match` so unchanged status returns 304 with no body
- `Retry-After` header telling the client when to come back
- A terminal state that stops polling — clients must know when to give up

**Webhook requirements** (these come up in questions 512, 517):
- HMAC-SHA256 signature over the raw body, with a timestamp in the signed payload
- Reject timestamps older than ~5 minutes (replay protection)
- Retries with exponential backoff, since the receiver may be down
- At-least-once delivery, so the receiver must be idempotent on event ID

---

## 79. SSE vs WebSocket for progress?

**SSE (Server-Sent Events)** — unidirectional server→client over plain HTTP, `text/event-stream`.

**WebSocket** — bidirectional, upgraded protocol, persistent frames.

**For progress updates, SSE is almost always correct**, and being able to say why is the point of the question:

1. **Progress is unidirectional.** You're pushing status down. WebSocket's return channel is unused complexity.
2. **It's just HTTP.** Auth headers, cookies, proxies, compression, HTTP/2 multiplexing, load balancers — all work unchanged. WebSocket needs `Upgrade` support end to end, and corporate proxies frequently block it.
3. **Automatic reconnection is built in.** The browser's `EventSource` reconnects on drop and sends `Last-Event-ID`, so you can resume from where the client left off. With WebSocket you implement that yourself.
4. **Simpler server side** — a generator yielding strings.

```python
@router.get("/runs/{run_id}/events")
async def stream(run_id: UUID, user: User = Depends(get_current_user)):
    async def gen():
        last = 0
        while True:
            events = await fetch_events_after(run_id, last)
            for e in events:
                last = e.seq
                yield f"id: {e.seq}\nevent: {e.type}\ndata: {json.dumps(e.data)}\n\n"
            if await is_terminal(run_id):
                yield "event: done\ndata: {}\n\n"
                return
            yield ": keepalive\n\n"          # comment frame; keeps proxies from timing out
            await asyncio.sleep(1)

    return StreamingResponse(gen(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache",
                 "X-Accel-Buffering": "no"})     # disables nginx buffering
```

**The two SSE gotchas worth naming:** you must send periodic keepalive comments or intermediaries close the idle connection, and you must disable proxy buffering (`X-Accel-Buffering: no`) or nginx will hold your chunks and deliver them all at the end — which looks exactly like the feature not working.

**Choose WebSocket when** the client genuinely sends data continuously — collaborative editing, a chat where the user types mid-stream, live cursors, or a bidirectional voice/agent interface.

---

## 80. FastAPI BackgroundTasks vs worker process?

| | `BackgroundTasks` | Worker process |
|---|---|---|
| Where it runs | Same process, after response | Separate process |
| Durability | **None** — lost on crash/deploy | Persisted in queue/DB |
| Retries | None | Built in |
| Visibility | None | Queryable state, metrics |
| Scaling | Tied to API workers | Independent |
| Setup cost | Zero | Redis/queue + worker deploy |

**`BackgroundTasks` is acceptable only for:** fire-and-forget work where loss is genuinely acceptable and duration is short — a non-critical analytics ping, a cache warm, a log flush.

**It is wrong for:** sending emails, charging cards, generating reports, calling LLMs, anything a user will ask about later. The client received a 200. If the process dies, the work vanishes and *nobody knows* — no error, no retry, no record.

**The disqualifying fact:** it runs in the same process, so it also competes for the same event loop and the same memory. A heavy background task degrades your API latency.

**The upgrade path:** if you find yourself wanting retries, or wanting to know whether it succeeded, you have already outgrown `BackgroundTasks`. Move to a real queue (Redis Streams, RQ, Celery, SQS) with a durable job row.

---

## 81. What does increasing Uvicorn/Gunicorn workers do?

**Mechanically:** forks N processes, each with its own Python interpreter, GIL, event loop, memory, and connection pool. The OS load-balances accepted connections across them.

**What it helps:** CPU-bound work (real parallelism across cores), and blocking calls (one blocked worker doesn't block the others).

**What it does not help:** a single slow database query, an upstream rate limit, or an already-saturated database.

**The costs people forget:**
1. **Memory multiplies.** 4 workers × 400 MB = 1.6 GB. In a 1 GB container, workers get OOM-killed and restart in a loop.
2. **Connection pools multiply.** `pool_size=20` × 4 workers = 80 connections to PostgreSQL from one pod. Multiply by 10 pods = 800. PostgreSQL's default `max_connections` is 100. You have now taken down the database by scaling the API. **This is the single most common self-inflicted outage in this space** — use PgBouncer in transaction mode, or size pools as `max_connections / (pods × workers)` with headroom.
3. **In-memory state fragments** (Q82).
4. **Rate limiters fragment** — 4 workers × 20/sec = 80/sec against an upstream limit of 20.

**Sizing.** `(2 × cores) + 1` is the traditional heuristic for sync workers. For async workers it's usually wrong — 1–2 per core is plenty, since each handles high concurrency already. In Kubernetes, prefer **one worker per pod** and scale pods: the orchestrator then handles restarts, rolling deploys, and autoscaling, and your resource requests are accurate.

---

## 82. What happens if two workers have different in-memory state?

**You get non-deterministic behaviour that depends on which worker the load balancer picked.** This is one of the most confusing bug classes to debug because the same request succeeds and fails alternately.

**Concrete manifestations:**

| In-memory thing | Symptom |
|---|---|
| Rate limiter counter | Effective limit is N× the configured one |
| Cache | Cache hit rate collapses; stale data on some requests |
| `asyncio.Lock` | No mutual exclusion at all; races return |
| WebSocket/SSE connection registry | Broadcast reaches only clients on that worker |
| Feature flag cached at startup | Some workers have old flags after a config change |
| Idempotency key set | Duplicate processing |
| Circuit breaker state | Breaker opens on one worker while others keep hammering |
| Session data | User appears logged out on alternate requests |

**The rule:** *in a multi-worker deployment, process memory is a cache, never a source of truth.* Anything requiring a single view across requests goes in Redis or PostgreSQL.

**Fixes by category:**
- Rate limiting → Redis counters with atomic `INCR`/Lua
- Locks → Redis with a TTL and a fencing token, or a database advisory lock
- Cache → Redis, or accept per-worker caching with a short TTL (often fine!)
- Pub/sub to connections → Redis Pub/Sub; each worker relays to its own clients
- Config → fetch with a TTL, or reload on a signal

**The nuance worth stating:** per-worker caching is legitimate when staleness is acceptable and the data is read-mostly — a 60-second local cache of feature flags across 4 workers is fine. The failure is when *correctness* depends on a single shared view.

---

## 83. Why is an in-process background task not a durable queue?

Because durability requires the work to survive the process, and an in-process task is *in the process*.

**Enumerate what a durable queue provides and `BackgroundTasks` doesn't:**

| Property | Durable queue | In-process task |
|---|---|---|
| Survives crash | Yes — persisted before ack | No |
| Survives deploy | Yes | No |
| Retries | Configurable | None |
| Dead-letter on repeated failure | Yes | No |
| Visibility (queued/running/failed) | Queryable | None |
| Independent scaling | Yes | No |
| Backpressure | Bounded queue | Unbounded |
| Delivery guarantee | At-least-once | At-most-once, unmeasured |

**The precise failure sequence.** Client POSTs → handler returns 200 → `BackgroundTasks` starts sending the email → Kubernetes sends SIGTERM for a rolling deploy → process exits → email never sent. There is **no error anywhere**. The client believes it succeeded. Your logs show a successful 200. The only signal is a user complaining days later.

**The bar for "durable":** the work must be written to persistent storage (a database row or a queue with disk persistence) *before* the API responds, and only marked complete *after* it finishes. That's the invariant. `BackgroundTasks` violates it by construction.

---

## 84. How do you gracefully shut down? (FastAPI specifics)

Q44 covered the general shape. FastAPI/ASGI specifics:

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db = await create_pool()
    app.state.http = httpx.AsyncClient(timeout=10)
    app.state.ready = True
    yield                                     # app serves here
    app.state.ready = False                   # fail readiness first
    await asyncio.sleep(5)                    # let LB drain
    await app.state.http.aclose()
    await app.state.db.close()

app = FastAPI(lifespan=lifespan)
```

**The sequence Uvicorn follows on SIGTERM:**
1. Stops accepting new connections
2. Waits for in-flight requests, up to `--timeout-graceful-shutdown`
3. Runs lifespan shutdown
4. Exits

**The Kubernetes-specific correctness detail.** Pod deletion sends SIGTERM and removes the endpoint from the Service *concurrently*. For a few hundred milliseconds, kube-proxy on some nodes may still route to you. If you stop accepting immediately, those requests get connection-refused — visible to users as 502s during every deploy.

The fix is a `preStop` hook that delays before SIGTERM reaches the process:
```yaml
lifecycle:
  preStop:
    exec: {command: ["sleep", "5"]}
terminationGracePeriodSeconds: 45
```
And ensure `terminationGracePeriodSeconds` > preStop sleep + graceful timeout, or you get SIGKILL'd mid-drain.

**Long-lived connections.** SSE streams don't end on their own. Have the generator watch a shutdown event and emit a terminal event so clients reconnect to a healthy pod rather than hanging until the grace period expires.

---

## 85. How do you implement health/readiness?

**Two distinct endpoints with genuinely different semantics** — conflating them is the classic mistake.

```python
@app.get("/health/live")              # liveness: am I alive?
async def live():
    return {"status": "ok"}           # NO dependency checks

@app.get("/health/ready")             # readiness: can I serve traffic?
async def ready():
    checks = {}
    try:
        async with asyncio.timeout(2):
            await app.state.db.fetchval("SELECT 1")
        checks["db"] = "ok"
    except Exception:
        checks["db"] = "fail"
    if not app.state.ready or checks["db"] == "fail":
        return JSONResponse(503, {"status": "not_ready", "checks": checks})
    return {"status": "ready", "checks": checks}
```

**Why liveness must not check dependencies.** Liveness failure = *restart the container*. If liveness checks the database and the database has a 30-second blip, Kubernetes restarts every pod simultaneously. Now you have a thundering herd of cold pods reconnecting to an already-struggling database. You have converted a brief degradation into a full outage. **Liveness answers only "is this process deadlocked or hung?"**

**Readiness failure = stop sending traffic, don't restart.** That's the correct response to a dependency being unavailable — the pod stays up and recovers when the dependency does.

**Startup probe** — a third, for slow starts (loading model weights, running migrations). It disables liveness until the app comes up, so a 3-minute model load doesn't get killed at 30 seconds by an impatient liveness probe. This is directly relevant to question 466 (model serving readiness).

**Additional discipline:** cache readiness results for a couple of seconds so probes don't hammer the DB; keep timeouts short (2s) so a hanging check doesn't hang the probe; exclude health endpoints from access logs and auth.

---

## 86. How do you stop one expensive request exhausting DB connections?

**The failure mode:** one endpoint holds connections for 30 seconds. Pool size is 20. Twenty concurrent such requests take every connection. Now `/health/ready` can't get one either, readiness fails, the pod is pulled from the LB, traffic shifts to other pods, and they fall over the same way. Cascading failure from a single slow query.

**Layered defences:**

**1. Timeouts at every level** — the most important one:
```python
engine = create_async_engine(
    url,
    pool_size=20, max_overflow=10,
    pool_timeout=5,          # fail fast if no connection in 5s
    pool_recycle=1800,
    pool_pre_ping=True,
)
# and at the database:
await conn.execute("SET statement_timeout = '10s'")
await conn.execute("SET idle_in_transaction_session_timeout = '30s'")
```
`statement_timeout` is the backstop that makes runaway queries impossible. `idle_in_transaction_session_timeout` kills the worst case — a transaction left open by a crashed client, holding locks forever.

**2. Bulkheads — separate pools by workload class.** A small dedicated pool for reports, a large one for interactive traffic. Reports can starve their own pool without touching the interactive path. This is the single most effective structural fix.

**3. Don't hold connections across slow operations.** Never hold a connection while calling an LLM. Fetch → release → call → reacquire → write.

**4. Read replicas** for expensive analytical queries (Q167).

**5. Move it out of the request entirely** — if it's expensive, it's a job (Q76).

**6. Concurrency limit per route** — a semaphore sized well below the pool, so the expensive endpoint can never consume more than its share.

**7. PgBouncer in transaction mode** so app-side pools don't map 1:1 to PostgreSQL backends.

**Monitoring that catches it early:** pool checkout wait time (p99), pool utilisation percentage, and `pg_stat_activity` count by state. Rising checkout wait is the leading indicator — it precedes the outage by minutes.

---

## 87. How do you propagate request IDs?

```python
import contextvars
request_id_var = contextvars.ContextVar("request_id", default=None)

@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    rid = request.headers.get("X-Request-ID") or str(uuid4())
    request_id_var.set(rid)
    request.state.request_id = rid
    response = await call_next(request)
    response.headers["X-Request-ID"] = rid
    return response
```

**Why `ContextVar` and not a global or a thread-local:** `ContextVar` is async-aware. Each task gets its own copy, so 1,000 concurrent requests each see their own ID. A module-level global would be overwritten by whichever request ran last; a `threading.local` is wrong because many coroutines share one thread.

**Then inject it everywhere:**
- **Logging** — a filter that adds `request_id` to every record, so you never pass it manually
- **Outbound HTTP** — an httpx event hook adding the `X-Request-ID` header, so downstream services log the same ID
- **Queue messages** — include it in the payload so worker logs correlate with the originating request
- **Error responses** — so a user's screenshot is a searchable key
- **Database** — `SET application_name` or a SQL comment, so `pg_stat_activity` shows which request owns a slow query

**The one gotcha:** `contextvars` propagate to tasks created with `create_task` (the context is copied at creation), but *not* backwards. Setting a var inside a task doesn't affect the parent.

**Trace ID vs request ID.** For real distributed tracing, use OpenTelemetry's W3C `traceparent` header — it carries trace ID, span ID, and sampling flags, and gives you a full waterfall across services rather than just a grep key. Request ID is the cheap version; both are worth having.

---

## 88. How do you handle upstream timeouts?

**Layer the response:**

**1. Always set a timeout.** No exceptions. `httpx.AsyncClient(timeout=httpx.Timeout(connect=2, read=10, write=5, pool=2))`. Separate connect and read timeouts matter — a slow connect means the host is down (fail fast), a slow read means it's working but slow (be more patient).

**2. Budget downward.** If your caller's timeout is 30s, yours to upstream must be less — say 8s — leaving room for retries and your own processing. Propagate a deadline header if you control both sides. Timeouts that increase as you go deeper guarantee that the outer caller gives up while inner work continues, wasting capacity.

**3. Retry, but only what's safe.** Retry GET and idempotent POSTs (with an idempotency key). Exponential backoff with full jitter. Cap attempts at 2–3.

**4. Circuit breaker.** After N consecutive failures, open for a cooldown and fail fast. Without this, a dead upstream consumes all your workers in timeout waits — the classic cascading failure. Half-open state lets one probe through to test recovery.

**5. Degrade, don't die.** Decide per dependency: return cached/stale data, return partial results with a flag, use a fallback provider, or fail the request. **This is a product decision, not a technical one** — say that in an interview. For an AI product, "the enrichment service is down so we return the answer without citations" may be entirely acceptable; "the payment provider is down so we assume payment succeeded" never is.

**6. Correct status code.** 504 if you timed out waiting on upstream; 503 with `Retry-After` if you're shedding load.

**7. Remember: a timeout does not mean it didn't happen.** The upstream may have completed the work. Retrying a charge after a timeout without an idempotency key double-charges the customer.

---

## 89. How do you handle a client disconnect during streaming?

**Detection:**
```python
async def gen(request: Request):
    try:
        async for chunk in llm_stream():
            if await request.is_disconnected():
                logger.info("client gone; aborting")
                break
            yield chunk
    finally:
        await cleanup()          # runs on disconnect too
```
Starlette also raises `ClientDisconnect` on write to a closed connection, and cancels the task — so `finally` is your reliable cleanup hook.

**Why you must handle it:** if you don't, you keep generating. For an LLM stream that means **you keep paying for tokens nobody will read**. A user hitting stop on 100 requests generates 100 abandoned completions at full cost. At scale this is a real line item.

**The decisions to make explicitly:**

1. **Abort or complete?** If the result is valuable and expensive, finish it, persist it, and let the client reconnect and fetch it. If it's cheap and disposable, abort and save money. For an agent run costing $0.40, finish and persist. For an autocomplete, abort.

2. **Persist partial output** as you stream, not at the end. Then a reconnecting client resumes from event N rather than restarting.

3. **Support resumption.** SSE's `Last-Event-ID` header exists exactly for this. Store events with sequence numbers; on reconnect, replay from `Last-Event-ID + 1`.

4. **Distinguish disconnect from error** in metrics. A high disconnect rate is a UX signal (users bored of waiting), not an error signal. Conflating them makes your error rate meaningless.

5. **Release resources.** DB connections, semaphore slots, rate-limit tokens.

**The architecture that makes this a non-issue:** don't stream directly from the LLM to the client. Have the worker write events to Redis/Postgres, and have the SSE endpoint read from there. Then client disconnect is completely decoupled from job execution — the job continues, the client reconnects and catches up. This is the right design for anything long-running, and it's the answer to question 317 (resuming a failed agent run) as well.

---

## 90. How do you protect an endpoint from floods?

**Defence in depth, outermost first — because the cheapest rejection is the one furthest from your code:**

**1. Edge / CDN** — Cloudflare, AWS WAF. Blocks volumetric attacks before they reach your infrastructure. Nothing you write in Python competes with this.

**2. Load balancer / ingress** — connection limits, per-IP rate limits in nginx (`limit_req_zone`).

**3. Application rate limiting** — per user/API key, not just per IP (IPs are shared behind NAT and trivially rotated):
```python
async def rate_limit(user: User = Depends(get_current_user)):
    key = f"rl:{user.id}:{int(time.time() // 60)}"
    count = await redis.incr(key)
    if count == 1:
        await redis.expire(key, 120)
    if count > user.tier_limit:
        raise HTTPException(429, headers={"Retry-After": "60"})
```
Use a sliding window or token bucket rather than a fixed window (a fixed window permits a 2× burst at the boundary). Must be Redis-backed, not in-memory — see Q82.

**4. Concurrency limits** — a semaphore per expensive endpoint, so even permitted request rates can't exhaust workers.

**5. Cost-based limiting for AI endpoints.** This is the AI-specific insight. Requests are not equal: one may cost 200 tokens, another 50,000. Rate-limiting by *request count* is meaningless when cost varies by 250×. Limit by **tokens per hour** or **spend per day**, debited from a budget. Reject when the budget is exhausted, and enforce `max_tokens` per request so a single call can't blow the budget.

**6. Payload limits** — reject oversized bodies at the proxy, before Python allocates memory for them.

**7. Load shedding** — when p99 latency exceeds a threshold or the queue is deep, start returning 503 with `Retry-After`. Serving 80% of traffic well beats serving 100% badly, and a queue you can never drain is an outage.

**8. Auth as the first filter.** Unauthenticated endpoints get much tighter limits. Reject before doing expensive work — validate the token before parsing a 10 MB body.

**Response discipline:** 429 with `Retry-After`, plus `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` headers so well-behaved clients self-regulate instead of hammering.

---

# L4 — System design

## 91. Design FastAPI for 10k requests/sec.

**Start by interrogating the number** — this is what interviewers actually want. 10k req/s of what? A 1ms cache read and a 200ms LLM call are different systems by three orders of magnitude. Assume: mixed reads and writes, p99 target 200ms, some cacheable.

**Capacity arithmetic (state it explicitly).** By Little's Law, concurrency = throughput × latency. At 10k req/s and 50ms average latency, you need 500 concurrent requests in flight. That's the number that drives everything downstream.

**The architecture:**

```
CDN/WAF → ALB → Ingress → [API pods ×N] → PgBouncer → Postgres (primary + replicas)
                                        → Redis (cache + rate limit)
                                        → Queue → [Workers ×M]
```

**Layer by layer:**

**Edge.** CDN for static and cacheable GETs. If 30% of traffic is cacheable, that's 3,000 req/s that never reach you — the cheapest capacity you will ever buy.

**API tier.** Async endpoints throughout, `uvloop`, `ORJSONResponse`. One Uvicorn worker per pod; scale pods, not workers. Sizing: measure a single pod's ceiling (say 800 req/s), then run 10k/800 × 1.5 headroom ≈ 19 pods. HPA on a custom metric (request rate or queue depth), not CPU — CPU is a lagging indicator for I/O-bound services.

**Caching — the highest-leverage layer.** Redis for hot reads with a short TTL. Guard against stampede with a per-key lock or probabilistic early expiry: without it, a popular key expiring sends 10k simultaneous requests to the database. Cache negative results too. Target an 80%+ hit rate; that turns 10k req/s into 2k database req/s.

**Database — this is where 10k req/s actually dies.** PostgreSQL will not take 10k connections. PgBouncer in transaction mode multiplexes thousands of client connections onto ~100 server connections. Read replicas for read traffic (accepting replication lag — Q170). Every query indexed, `statement_timeout` set, no N+1 queries. Cursor pagination, never OFFSET (Q130).

**Async everything expensive.** Anything over ~100ms goes to a queue. The API tier should only accept, validate, and enqueue.

**Observability.** RED metrics per endpoint, p50/p95/p99 (never averages), distributed tracing sampled at 1%, and alerting on error budget burn rate rather than raw thresholds.

**The trade-offs to state:** caching buys throughput with staleness; replicas buy read capacity with eventual consistency; async buys latency with complexity and eventual delivery. Then close with: "and I'd want to know the read/write ratio and cacheability before committing, because those two numbers change this design more than anything else."

---

## 92. Design a long-running AI job API.

**Requirements:** runs take 30 seconds to 30 minutes, must survive worker crashes and deploys, need progress visibility, cost money per run, must be cancellable, multi-tenant.

**API surface:**
```
POST   /v1/runs                 → 202 {run_id, status_url, events_url}
GET    /v1/runs/{id}            → status, progress, result, cost
GET    /v1/runs/{id}/events     → SSE stream
POST   /v1/runs/{id}/cancel     → 202
GET    /v1/runs?status=&cursor= → list
```

**Data model:**
```sql
CREATE TABLE runs (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL,
  status TEXT NOT NULL,          -- queued|running|succeeded|failed|cancelled
  idempotency_key TEXT,
  input JSONB, result JSONB, error JSONB,
  attempt INT DEFAULT 0,
  lease_expires_at TIMESTAMPTZ,   -- for stuck detection
  cost_cents INT DEFAULT 0,
  created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX ON runs (tenant_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE TABLE run_steps (          -- durable per-turn state
  run_id UUID, seq INT, type TEXT, payload JSONB, created_at TIMESTAMPTZ,
  PRIMARY KEY (run_id, seq)
);
```

**Core flow.** API writes the run row and an outbox entry in one transaction (Q41). A relay publishes to the queue. A worker claims the run with a **lease** — `UPDATE runs SET status='running', lease_expires_at=now()+interval '2 min' WHERE id=$1 AND status='queued'` — and zero rows affected means someone else got it. The worker heartbeats the lease while working. A reaper requeues runs whose lease expired (that's your dead-worker recovery, Q201).

**Every step is persisted to `run_steps` before proceeding.** This is the single most important design decision: it makes the run resumable. A worker that dies at step 23 is replaced by one that reads steps 1–22 and continues. Without it, a 30-minute run that dies at minute 29 restarts from zero and costs you twice.

**Progress** goes to `run_steps` and to a Redis Stream; the SSE endpoint reads from Redis with a Postgres fallback for replay. The API never talks to the worker directly — full decoupling means client disconnects and API deploys don't touch running jobs (Q89).

**Cancellation** is cooperative: set `status='cancelling'`; the worker checks between steps and exits cleanly. You cannot interrupt an in-flight LLM call, so state that honestly and set expectations in the API contract.

**Cost control:** per-run token cap, per-tenant daily budget checked before starting, actual cost accumulated per step. Reject at 429 when the budget is exhausted.

**Failure handling:** classify errors as retryable (429, 5xx, timeout) vs terminal (invalid input, content filter). Retry the first with backoff and an attempt cap; dead-letter the second immediately. Never retry a terminal error — it burns money to fail identically.

---

## 93. Design multi-tenant FastAPI auth.

**Three isolation models, and the trade-off is the answer:**

| Model | Isolation | Cost | Ops burden | Use when |
|---|---|---|---|---|
| Shared schema, `tenant_id` column | Logical | Lowest | Lowest | Most SaaS |
| Schema per tenant | Stronger | Medium | Migrations × N | Hundreds of tenants, compliance pressure |
| Database per tenant | Strongest | Highest | Heavy | Regulated, few large tenants |

Assume shared schema — the common choice — and defend it with layered enforcement:

**Layer 1 — Token carries tenant.** JWT with `sub` (user), `tid` (tenant), `scopes`. Never accept the tenant from a request parameter, header, or body; that's an IDOR waiting to happen.

**Layer 2 — Dependency extracts and verifies:**
```python
async def get_tenant_ctx(user: User = Depends(get_current_user)) -> TenantCtx:
    if not await tenant_is_active(user.tenant_id):
        raise HTTPException(403, "tenant suspended")
    return TenantCtx(tenant_id=user.tenant_id, scopes=user.scopes)
```

**Layer 3 — Repository always filters.** Every query takes `tenant_id`. Enforce it structurally — a base repository that injects the filter — so an individual developer cannot forget.

**Layer 4 — PostgreSQL Row-Level Security as the backstop.** This is what makes the design genuinely defensible:
```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON orders
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```
Set `app.tenant_id` per connection checkout. Now a forgotten `WHERE` clause returns *zero rows* instead of every tenant's data. Application bugs stop being breaches.

**Note the PgBouncer interaction:** in transaction pooling mode, session variables don't persist across transactions. Use `SET LOCAL` inside the transaction, and verify this works with your pooler configuration — it's a real footgun.

**Layer 5 — 404 not 403** for other tenants' resources (Q70), preventing enumeration.

**Cross-cutting:** per-tenant rate limits and quotas; `tenant_id` on every log line and metric; encryption keys per tenant if compliance demands; and a test suite that specifically attempts cross-tenant access on every endpoint. That last one is the difference between claiming isolation and having it.

---

## 94. Design a 10 GB upload API.

**Never proxy 10 GB through your API.** That's the core insight and the whole answer follows from it.

**Presigned URLs — the correct pattern:**
```
POST /v1/uploads          → {upload_id, presigned_urls[], part_size}
   (client uploads parts directly to S3)
POST /v1/uploads/{id}/complete  → {file_id}
```

Your API issues credentials and records metadata. Bytes go client → S3 directly. Benefits: your workers never hold a 10 GB stream, bandwidth costs and scaling become S3's problem, and uploads survive your deploys.

**Multipart upload** is mandatory at this size:
- Split into 5 MB–100 MB parts (S3 minimum is 5 MB except the last; maximum 10,000 parts)
- Parts upload in parallel — 10 concurrent parts is roughly 10× faster
- A failed part retries alone, not the whole 10 GB
- Resumable: the client queries completed parts and continues
- Each part returns an ETag; `CompleteMultipartUpload` takes the list

**Security controls on the presigned URL:**
- Short expiry (15 minutes)
- Constrain content-type and content-length-range in the policy, or a client uploads a 100 GB file and you pay for it
- Key path namespaced by tenant: `{tenant_id}/{upload_id}/{part}`
- The IAM role backing the presign grants `PutObject` only, on that prefix only

**Validation happens after upload, not during.** Trust nothing the client declared. On completion, trigger async processing: verify size and checksum, sniff the actual content type from magic bytes (never the extension or the client-declared type), scan for malware, extract metadata, generate derivatives. Mark the file `pending` until validation passes; expose it only after.

**Lifecycle and cleanup:** abandoned multipart uploads consume storage silently and bill you forever. An S3 lifecycle rule aborting incomplete uploads after 7 days is not optional. Also expire `pending` upload rows in your database.

**Downloads mirror this** — presigned GET URLs with short expiry, never streaming through your API (Q518).

**If you truly cannot use presigned URLs** (on-prem, no object store): stream to disk in chunks with `aiofiles`, never `await request.body()` (which loads 10 GB into RAM), enforce a hard size limit at the reverse proxy, and use a dedicated upload service so a slow upload can't starve the main API's workers.

---

## 95. Design an API calling five downstream services.

**First question: are the five calls independent or sequential?** Independent means parallel — total latency is the slowest, not the sum. That single decision is worth 5× on latency.

```python
async with asyncio.TaskGroup() as tg:
    profile = tg.create_task(profile_svc.get(uid))
    prefs   = tg.create_task(prefs_svc.get(uid))
    billing = tg.create_task(billing_svc.get(uid))
```

**Second question: which are essential and which are optional?** This is the design decision that determines availability.

Availability multiplies. Five dependencies at 99.9% each, all required, gives 99.5% — that's 3.6 hours of downtime a month caused entirely by dependencies. Making three of them optional with graceful degradation raises your effective availability dramatically.

```python
async def get_dashboard(uid):
    core = await asyncio.gather(
        profile_svc.get(uid),           # essential — failure fails the request
        billing_svc.get(uid),           # essential
    )
    optional = await asyncio.gather(
        recommendations.get(uid),
        activity_feed.get(uid),
        notifications.get(uid),
        return_exceptions=True,          # failures become values, not raises
    )
    return build(core, [r for r in optional if not isinstance(r, Exception)],
                 degraded=any(isinstance(r, Exception) for r in optional))
```
Return a `degraded: true` flag so clients and dashboards can see partial responses rather than guessing.

**Per-dependency resilience:** each gets its own timeout (budgeted below the caller's), its own circuit breaker, its own connection pool (bulkheading — one slow service must not consume the shared pool), and its own retry policy for idempotent calls only.

**Caching by volatility.** A profile that changes daily gets a 5-minute cache; a balance that changes per transaction gets none. Serve stale on upstream failure — a 10-minute-old recommendation list is far better than an error.

**When there are writes across services,** you cannot have a distributed transaction in practice. Use a saga: sequential steps with compensating actions, orchestrated by a durable workflow with persisted state. Say plainly that this gives eventual consistency and requires idempotent steps — and that the alternative, 2PC, trades availability for consistency in a way that's rarely worth it.

**Observability:** distributed tracing is not optional here. Without a trace waterfall, "the dashboard is slow" has five possible causes and no way to distinguish them.

---

## 96. Where do retries live?

**Principle: retry as close to the failure as possible, and only at one layer per failure class.** Retries at multiple layers multiply — 3 client × 3 gateway × 3 service = 27 requests from one user action. That's how retry storms start.

| Layer | Should retry? | What |
|---|---|---|
| Client (browser/mobile) | Yes, carefully | Network failures, 5xx, with long backoff. Never on 4xx |
| API gateway | Usually not | Blind retries amplify; it can't tell safe from unsafe |
| Service → service | **Yes — primary location** | Idempotent calls, 3 attempts, jittered backoff, circuit breaker |
| Database driver | Yes, narrowly | Connection errors and serialisation failures only, not query errors |
| Queue consumer | **Yes — primary location** | Failed jobs, with backoff and a dead-letter queue |

**The rules:**

1. **Only retry idempotent operations** — or make them idempotent with an idempotency key.
2. **Only retry retryable errors.** 429, 502, 503, 504, connection reset, timeout. Never 400, 401, 403, 404, 422 — those will fail identically forever and burn money doing it.
3. **Exponential backoff with full jitter** — `random.uniform(0, min(cap, base * 2**n))`. Without jitter, synchronised retries recreate the load spike that caused the failure.
4. **Cap attempts and total time.** Three attempts, 10 seconds total. Then fail.
5. **Circuit breaker above retries.** When the breaker is open, don't retry at all — fail fast.
6. **Honour `Retry-After`** — it overrides your backoff calculation.
7. **Budget retries.** Cap retries at ~10% of total requests. Above that, shed load instead — the system is already overloaded and retrying makes it worse.

**Where retries do NOT belong:** inside a database transaction (you're holding locks while sleeping), and inside a request handler for something long-running (return 202 and let a worker retry).

---

## 97. Where does caching live?

Layered, each with different invalidation characteristics:

| Layer | TTL | Invalidation | Good for |
|---|---|---|---|
| Client / browser | Minutes | `ETag`, `Cache-Control` | Static assets, user's own data |
| CDN | Minutes–days | Purge API, versioned URLs | Public, shared content |
| API response cache | Seconds–minutes | TTL or event | Expensive, low-volatility reads |
| Application (Redis) | Seconds–hours | Explicit, event-driven | Sessions, computed results, hot rows |
| In-process | Seconds | TTL only | Config, feature flags, tiny hot data |
| Database buffer pool | — | Automatic | Handled for you |

**Decision rule.** Cache high enough to skip the most work, low enough that you can invalidate correctly. The most valuable cache is usually the one closest to the user; the safest is the one closest to the data.

**The hard part is always invalidation.** Strategies, in increasing order of correctness and cost:
- **TTL only** — simplest, guaranteed stale window. Fine for most things. Be honest about the window.
- **Write-through** — update cache on write. Fails across multiple writers.
- **Event-driven** — publish invalidation on change. Correct, needs infrastructure.
- **Versioned keys** — `user:{id}:v{version}`; bump the version instead of deleting. Avoids the delete-then-repopulate race entirely.

**Stampede protection is mandatory** for hot keys. When a popular key expires, every concurrent request misses simultaneously and hits the database. Fix with a per-key lock (one request recomputes, others wait or serve stale) or probabilistic early expiry.

**AI-specific caching, which is where the money is:**
- **Prompt/response cache** keyed by a hash of the full prompt — exact-match, huge savings on repeated queries
- **Semantic cache** — embed the query, return a cached answer if similarity exceeds a threshold. Powerful and dangerous: too low a threshold returns confidently wrong answers to different questions. Needs evaluation, not intuition.
- **Embedding cache** — embeddings are deterministic per model+text. Never compute one twice. Key on `hash(text) + model_version`.
- **Provider-side prompt caching** for long stable system prompts and retrieved context.

**What never to cache:** anything authorisation-dependent without the principal in the key (the classic cache-poisoning leak, where user A's data is served to user B), and financial balances used for decisions.

---

## 98. Where does authorization live?

Covered mechanically at Q70; the architectural version:

**Three tiers, each with a different home:**

1. **Authentication** — at the edge (dependency), once. Establishes *who*.
2. **Coarse authorization** (roles, scopes, tenant validity) — dependency, before the handler. Cheap, no resource needed.
3. **Fine authorization** (ownership, per-record rules) — service layer, expressed in the query, backed by RLS.

**The design principle: authorization must not be forgettable.** Anything that relies on a developer remembering to write a check will eventually be forgotten. So push it into structures that fail closed:

- Repository base class that requires a tenant context
- PostgreSQL RLS as the backstop
- A test that attempts cross-tenant access on every endpoint, run in CI
- Default-deny routing: routes require explicit opt-in to be public, rather than requiring opt-in to be protected

**For an AI/agent platform, add a fourth tier — tool authorization.** The model proposes actions; the model is not a principal and cannot be trusted. Every tool call is authorised against the *user's* permissions, not the agent's, at execution time. The model may request `delete_all_records`; the executor checks whether this user may do that and refuses. Tool arguments get validated and constrained (a tenant filter injected server-side, never taken from the model's output). Dangerous tools require human approval. This is questions 311, 312, 325, and 335 — and it's the thing that distinguishes someone who has actually built an agent from someone who has read about them.

---

## 99. How do you prevent retry storms?

**The mechanism to describe:** a service degrades → clients retry → load increases → more degradation → more retries → collapse. The retries, not the original fault, cause the outage. Recovery is impossible because the moment the service comes back it's hit by the entire accumulated retry backlog and falls over again.

**Prevention, layered:**

**1. Jitter.** Non-negotiable. Without it, all clients that failed at T retry at T+1 simultaneously — you've built a synchronised load generator. Full jitter (`random.uniform(0, backoff)`) is the standard.

**2. Retry budgets.** Cap retries as a *fraction* of total traffic (~10%). Track the ratio; when it's exceeded, stop retrying entirely. This bounds amplification no matter how bad things get, and it's more robust than per-request attempt caps.

**3. Circuit breakers.** After N consecutive failures, open and fail fast. Half-open lets one probe through. This is what allows recovery: while open, the struggling service receives almost no traffic and can actually recover.

**4. Retry at one layer only.** Audit the full path. Multi-layer retries multiply (Q96).

**5. `Retry-After` on 429/503** — and honour it. This lets the server coordinate client behaviour, which is far better than each client guessing.

**6. Load shedding.** Reject early and cheaply when overloaded. A fast 503 costs almost nothing; a slow timeout holds a connection for 30 seconds.

**7. Deadline propagation.** Pass the remaining budget downstream. If the client's deadline has already passed, don't start the work at all — you'd be doing work whose result nobody will read.

**8. Queue instead of retry** for anything that can be asynchronous. A queue absorbs the spike and drains at a sustainable rate; that's backpressure doing its job.

**Detection.** Alert on the ratio of retried to original requests, and on request rate rising while success rate falls — that divergence is the signature of a storm in progress.

---

## 100. How do API servers and workers scale independently?

**Because they have entirely different resource profiles and load curves,** and coupling them wastes money in both directions.

| | API tier | Worker tier |
|---|---|---|
| Bound by | Concurrency, network I/O | CPU, memory, GPU, upstream rate limits |
| Latency target | Milliseconds | Minutes acceptable |
| Load signal | Requests per second | Queue depth |
| Scaling trigger | Request rate / p99 latency | Queue depth / oldest message age |
| Failure impact | Users see errors immediately | Jobs delayed, not lost |
| Scale-down | Fast | Must drain first |

**The queue is the decoupling mechanism.** The API writes durable work and returns; workers consume at their own pace. Traffic spikes lengthen the queue instead of dropping requests. That's backpressure at the architectural level.

**Scaling the API** on request rate or p99 latency — not CPU, which is a lagging and misleading indicator for I/O-bound async services.

**Scaling workers on queue depth**, and more precisely on **oldest-message age**, which directly expresses the SLO: "no job waits more than 2 minutes." Queue depth alone is ambiguous — 1,000 fast jobs and 10 slow ones are different situations. In Kubernetes this means KEDA or a custom metric adapter, since HPA won't read your queue natively.

**The constraints that actually bound worker count** — and naming these is what shows experience:
- Database connections: `workers × pool_size` must stay under `max_connections`
- Upstream rate limits: 50 workers against a 20/sec API just produces 429s
- GPU count for model serving: you cannot scale past your hardware
- Cost: each LLM-calling worker burns real money per second

More workers is not always faster. Past the downstream bottleneck it just moves queuing from your queue into someone else's.

**Separate worker pools by workload class.** Fast jobs and 30-minute jobs in one queue means a burst of slow jobs starves the fast ones (head-of-line blocking). Separate queues, separate deployments, separate scaling policies. Similarly, separate pools per tenant tier prevent one large customer from starving everyone else.

**Deployment independence** is an underrated benefit: you can ship a prompt change to workers without touching the API, and vice versa. Different risk profiles, different release cadences.

---

*End of Document 02. Next: Document 03 — PostgreSQL / SQL (questions 101–170).*
