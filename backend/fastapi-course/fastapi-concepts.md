# FastAPI Concepts — Complete Reference

Theory, usage, alternatives, pitfalls. Everything used in production day to day.

---

## 1. ASGI vs WSGI — the foundation

**WSGI** (old): one request = one thread. Server blocks until response is done. Simple but can't handle concurrent IO efficiently.

**ASGI** (modern): one event loop handles many requests. While one request waits for DB, another request runs. No thread-per-request.

```
WSGI: request → thread → wait for DB → respond → thread freed
ASGI: request → coroutine → await DB → (other requests run here) → respond
```

FastAPI is ASGI. That's why:
- All handlers are `async def`
- DB client must be async (asyncpg, not psycopg2)
- One sync blocking call freezes the entire event loop

**Mixing sync and async:**
```python
# WRONG — blocks event loop
@router.get("/things")
async def get_things():
    time.sleep(5)  # freezes ALL requests for 5 seconds

# RIGHT — offload blocking work to threadpool
from fastapi.concurrency import run_in_threadpool

@router.get("/things")
async def get_things():
    result = await run_in_threadpool(some_sync_function)
```

**Can you use `def` instead of `async def`?** Yes — FastAPI runs sync handlers in a threadpool automatically. But for IO-heavy routes (DB, HTTP calls), `async def` + async client is always better.

---

## 2. Request Lifecycle

Every request goes through this pipeline:

```
Client request
    ↓
Uvicorn (ASGI server) — handles TCP, HTTP parsing
    ↓
Middleware stack (runs in order, wraps everything below)
    ↓
FastAPI routing — matches URL to handler
    ↓
Dependency resolution (Depends tree resolved before handler)
    ↓
Request body parsing + Pydantic validation
    ↓
Handler runs
    ↓
Response model serialization (response_model)
    ↓
Middleware stack (response side, reverse order)
    ↓
Client response
```

If anything raises at any step, exception handlers catch it before it reaches the client.

---

## 3. `Depends` — Dependency Injection

**What:** declares what a route needs. FastAPI resolves the full tree before handler runs.

**Without it** — every route manually fetches what it needs:
```python
async def create_post(request: Request):
    token = request.headers["Authorization"].split(" ")[1]
    payload = decode_token(token)
    async with pool.acquire() as conn:
        user = await get_user(conn, payload["sub"])
        ...  # 10 lines before you even start the actual work
```

**With Depends:**
```python
async def create_post(
    user: User = Depends(current_user),
    conn: asyncpg.Connection = Depends(get_conn),
):
    ...  # user and conn just appear
```

**Dependency chains:**
```python
# current_user depends on get_conn internally
async def current_user(
    token: str = Depends(oauth2_scheme),
    conn = Depends(get_conn),       # FastAPI resolves this too
) -> User: ...
```

FastAPI deduplicates — if 3 dependencies all need `get_conn`, it's called once and shared.

**Depends as a guard (no return value):**
```python
async def require_admin(user: User = Depends(current_user)):
    if not user.is_admin:
        raise ForbiddenError()
    # no return needed

@router.delete("/users/{id}", dependencies=[Depends(require_admin)])
async def delete_user(id: UUID, conn = Depends(get_conn)):
    ...  # admin check already done, not in signature
```

---

## 4. Path, Query, Body — how FastAPI decides

FastAPI infers parameter type from its position and type annotation:

```python
@router.get("/communities/{slug}/posts")
async def list_posts(
    slug: str,                    # in path → PATH param
    offset: int = 0,              # not in path, has default → QUERY param
    limit: int = 10,              # not in path, has default → QUERY param
    sort: str = "new",            # not in path, has default → QUERY param
    payload: PostCreate = Body(), # Pydantic model → BODY (JSON)
    conn = Depends(get_conn),     # Depends → dependency
):
```

**Explicit when ambiguous:**
```python
from fastapi import Path, Query, Body, Header, Cookie

async def example(
    id: UUID = Path(...),                      # force path
    q: str = Query(default=None, max_length=50), # query with validation
    payload: dict = Body(...),                  # explicit body
    auth: str = Header(default=None),           # from headers
    session: str = Cookie(default=None),        # from cookies
):
```

**`...` means required.** `default=None` means optional.

---

## 5. Pydantic Validation — full picture

### Field constraints
```python
from pydantic import BaseModel, Field

class PostCreate(BaseModel):
    title: str = Field(default=..., min_length=1, max_length=300)
    url:   str = Field(default=None, pattern=r"^https?://")
    body:  str | None = None
    tags:  list[str] = Field(default=[], max_length=5)  # max 5 tags
```

### Single-field validator — transform or validate
```python
from pydantic import field_validator

class CommunityCreate(BaseModel):
    slug: str

    @field_validator("slug")
    @classmethod
    def normalize_slug(cls, v: str) -> str:
        v = v.lower().strip().replace(" ", "-")  # transform
        if not v.replace("-", "").isalnum():
            raise ValueError("slug can only contain letters, numbers, hyphens")
        return v
```

### Cross-field validator — when one field depends on another
```python
from pydantic import model_validator

class PostCreate(BaseModel):
    url:  str | None = None
    body: str | None = None

    @model_validator(mode="after")
    def url_or_body_required(self) -> "PostCreate":
        if not self.url and not self.body:
            raise ValueError("post must have url or body")
        if self.url and self.body:
            raise ValueError("link post cannot have body")
        return self
```

`mode="after"` = runs after all fields parsed, has access to `self`. `mode="before"` = runs on raw dict before parsing.

### Annotated — reusable constraints
```python
from typing import Annotated

SlugStr = Annotated[str, Field(min_length=3, max_length=50, pattern=r"^[a-z0-9-]+$")]
EmailStr = Annotated[str, Field(pattern=r"^[^@]+@[^@]+\.[^@]+$")]

class CommunityCreate(BaseModel):
    slug: SlugStr   # reuse anywhere
    email: EmailStr
```

### Validator decision tree
| Need | Tool |
|---|---|
| Length, range, regex | `Field(...)` |
| Reuse constraint across models | `Annotated` |
| Transform or complex single-field logic | `@field_validator` |
| Rule involving 2+ fields | `@model_validator(mode="after")` |

### `model_validate` — crossing the boundary
```python
# from dict
PostResponse.model_validate({"id": "...", "title": "..."})

# from dataclass/ORM object (needs from_attributes=True on the schema)
PostResponse.model_validate(post_dataclass)

# model_dump — back to dict
post_response.model_dump()
post_response.model_dump(exclude={"deleted_at"})  # exclude fields
post_response.model_dump(mode="json")             # UUID → str, datetime → ISO string
```

---

## 6. Middleware

**What:** wraps every request/response. Runs before routing, wraps everything.

**When to use middleware vs Depends:**
- Middleware → every request, no exceptions (logging, CORS, request ID, rate limiting)
- Depends → specific routes (auth, DB connection, permission checks)

### Custom middleware
```python
import time
from fastapi import Request

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    response = await call_next(request)  # runs the entire handler chain
    duration = time.time() - start
    print(f"{request.method} {request.url.path} → {response.status_code} ({duration:.3f}s)")
    return response
```

**Middleware runs in reverse registration order for responses.** Register A then B: request goes A→B→handler, response goes handler→B→A.

### Built-in middleware
```python
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

app.add_middleware(CORSMiddleware,
    allow_origins=["https://myapp.com"],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000)
```

**CORS** — browser security. Without it, your frontend on `app.com` can't call your API on `api.com`. Middleware adds the right headers.

**Does middleware always apply?** Yes — to every request. That's the point. If you need conditional logic, use Depends instead.

---

## 7. Connection Pool — why, how, pitfalls

**The problem without a pool:**
```python
# every request opens + closes a connection
async def get_thing():
    conn = await asyncpg.connect(DATABASE_URL)  # ~50ms
    result = await conn.fetch("SELECT ...")
    await conn.close()  # wasted
```

50ms per connection × 100 requests/sec = 5 seconds of connection overhead per second. Doesn't scale.

**Pool:** N connections opened once at startup, shared across all requests.

```python
pool = await asyncpg.create_pool(
    dsn=DATABASE_URL,
    min_size=2,          # always keep 2 alive
    max_size=10,         # never open more than 10
    command_timeout=10,  # query timeout in seconds
    statement_cache_size=0,  # REQUIRED for Neon/PgBouncer
)
```

**Why `statement_cache_size=0`?** asyncpg caches prepared statement plans per connection. Connection poolers (Neon, PgBouncer) can give you a different backend connection each time. The cached plan is for the old connection — crash. Disable the cache when using a pooler.

**Why store pool on `app.state`?**
```python
app.state.pool = pool  # accessible anywhere via request.app.state.pool
```

Global variable works but is bad practice — hard to test, hard to replace. `app.state` is scoped to the app instance.

**Connection as context manager:**
```python
async def get_conn(request: Request):
    async with request.app.state.pool.acquire() as conn:
        yield conn   # conn returned to pool when request ends — even on crash
```

`async with` guarantees cleanup. A global connection would never be returned to the pool on exceptions.

**What if global connection instead of pool?**
- One connection = one request at a time (no concurrency)
- If it crashes, all requests fail until restart
- No timeout, no retry, no limits

---

## 8. Authentication — JWT full flow

### Signup
```
POST /auth/signup {email, password}
    → hash password (bcrypt, never store plain)
    → INSERT user
    → return UserPublic (no password_hash)
```

### Login
```
POST /auth/login {email, password}
    → fetch user by email
    → bcrypt.verify(plain, hash)
    → if wrong → 401
    → if correct → create JWT
    → return {access_token, token_type: "bearer"}
```

### JWT structure
```
header.payload.signature

payload = {
    "sub": "user-uuid",    # subject — who this token is for
    "type": "access",
    "iat": 1234567890,     # issued at
    "exp": 1234567890,     # expires at
}
```

Signed with `SECRET_KEY` using HS256. Anyone can decode the payload (it's base64) — but they can't forge a signature without the secret key.

### Protected route flow
```
GET /me + Authorization: Bearer <token>
    → oauth2_scheme reads "Bearer <token>" from header, strips prefix
    → decode_token verifies signature + expiry
    → reads sub (user_id) from payload
    → fetches User from DB
    → handler receives User object
```

### Why JWT over sessions?
- Sessions require server-side storage (DB/Redis lookup per request)
- JWT is self-contained — verify with secret key, no DB lookup needed
- Stateless — works across multiple servers without shared state

**Pitfall:** JWT can't be revoked before expiry (unless you maintain a denylist). Short expiry (15min-1hr) + refresh tokens is the standard solution.

---

## 9. Logging

**Never use `print()` in production.** Use the standard `logging` module.

```python
import logging

logger = logging.getLogger(__name__)  # logger named after the module

logger.debug("detailed info for debugging")
logger.info("normal operation info")
logger.warning("something unexpected but not breaking")
logger.error("something failed")
logger.exception("something failed", exc_info=True)  # includes traceback
```

**Setup once in lifespan:**
```python
logging.basicConfig(
    level=settings.log_level,  # DEBUG in dev, INFO in prod
    format="%(asctime)s %(levelname)-8s %(name)s %(message)s",
)
```

**Structured logging (production):** use `structlog` — outputs JSON, includes request_id, user_id, path, latency. Machines can parse it. Phase 7 of this project.

**Log levels:** DEBUG → INFO → WARNING → ERROR → CRITICAL. Setting INFO means DEBUG is silent.

---

## 10. `response_model` — output control

```python
@router.get("/users/{id}", response_model=UserPublic)
async def get_user(id: UUID) -> UserPublic:
    user = await user_service.get_user(id)
    return UserPublic.model_validate(user)
```

**What `response_model` does:**
1. Generates Swagger response schema
2. Filters response — fields not in `UserPublic` are stripped (security)
3. Validates the response before sending (catches bugs where handler returns wrong type)

**`response_model_exclude`:**
```python
@router.get("/users/me", response_model=UserPublic, response_model_exclude={"created_at"})
```

**Return type annotation vs response_model:** annotation is for your IDE/type checker, `response_model` is for FastAPI runtime. Use both.

---

## 11. Status codes

```python
from fastapi import status

@router.post("/things", status_code=status.HTTP_201_CREATED)   # 201
@router.delete("/things/{id}", status_code=status.HTTP_204_NO_CONTENT)  # 204
@router.get("/things")   # default 200
```

**Common codes:**
| Code | Meaning | When |
|---|---|---|
| 200 OK | success with body | GET, PUT |
| 201 Created | resource created | POST |
| 204 No Content | success, no body | DELETE |
| 400 Bad Request | client sent bad data | generic input error |
| 401 Unauthorized | not authenticated | no/bad token |
| 403 Forbidden | authenticated, not allowed | valid token, wrong user |
| 404 Not Found | resource missing | bad ID/slug |
| 409 Conflict | state conflict | duplicate create |
| 422 Unprocessable | validation failed | Pydantic rejection |
| 500 Internal Server Error | bug in your code | unhandled exception |

**401 vs 403:** 401 = "please log in." 403 = "you're logged in but you can't do this." Returning 401 when you mean 403 tells the user to log in again, which won't help.

---

## 12. Optimizations and Pitfalls

### N+1 query problem
```python
# BAD — 1 query for posts + N queries for authors
posts = await post_repo.list_posts(conn)
for post in posts:
    author = await user_repo.get_user(conn, post.author_id)  # N queries!

# GOOD — JOIN in one query
posts_with_authors = await post_repo.list_posts_with_authors(conn)
```

Always check: "does this loop contain an await?" If yes, you probably have N+1.

### Async all the way down
```python
# BAD — sync DB in async handler blocks event loop
@router.get("/things")
async def get_things():
    conn = psycopg2.connect(...)  # BLOCKS
    return conn.execute("SELECT ...")

# GOOD — async DB
@router.get("/things")
async def get_things(conn = Depends(get_conn)):
    return await conn.fetch("SELECT ...")
```

### Don't catch broad exceptions
```python
# BAD — swallows bugs
try:
    result = await repo.insert(...)
except Exception:
    return {"error": "something went wrong"}

# GOOD — only catch what you can handle
try:
    result = await repo.insert(...)
except asyncpg.UniqueViolationError as exc:
    raise AlreadyExistsError() from exc
# everything else propagates as 500
```

### Connection pool exhaustion
If all pool connections are busy and a new request comes in, it waits. If `max_size=10` and you have 10 slow queries, request 11 hangs. Signs: requests timing out under load. Fix: faster queries, bigger pool, read replicas.

### Never log sensitive data
```python
# BAD
logger.info(f"User login: email={email} password={password}")

# GOOD
logger.info(f"User login attempt: email={email}")
```

### Soft delete — always filter
Every list query must include `WHERE deleted_at IS NULL`. Forget it once = deleted content appears in listings. Add it to `_row_to_thing` or always in the SQL — never rely on the caller to filter.

---

## 13. `lifespan` — startup and shutdown

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # STARTUP — runs before first request
    pool = await create_pool()
    app.state.pool = pool

    yield  # app runs here

    # SHUTDOWN — runs after last request (guaranteed, even on crash)
    await pool.close()

app = FastAPI(lifespan=lifespan)
```

**Why not global variable for pool?**
```python
pool = None  # BAD

@app.on_event("startup")
async def startup():
    global pool
    pool = await create_pool()
```
- `global` state is hard to test (can't reset between tests)
- `app.state` is per-instance — multiple test apps don't share state
- Old `on_event` API is deprecated

---

## 14. `BackgroundTasks` — fire and forget

```python
from fastapi import BackgroundTasks

async def send_welcome_email(email: str):
    # slow operation — don't block the response
    await email_client.send(email, "Welcome!")

@router.post("/auth/signup", status_code=201)
async def signup(payload: SignupRequest, background_tasks: BackgroundTasks):
    user = await auth_service.signup(payload.email, payload.password)
    background_tasks.add_task(send_welcome_email, user.email)  # runs after response sent
    return UserPublic.model_validate(user)
```

**Pitfall:** if the server restarts, queued background tasks are lost. For reliable async jobs, use a proper worker queue (ARQ, Celery) — Phase 5 of this project.

---

## 15. `include_router` and API versioning

```python
# no versioning (current)
app.include_router(communities.router)
# routes: /communities, /communities/{slug}

# with prefix versioning
app.include_router(communities.router, prefix="/api/v1")
# routes: /api/v1/communities, /api/v1/communities/{slug}

# with multiple versions
from app.api.v1 import communities as communities_v1
from app.api.v2 import communities as communities_v2

app.include_router(communities_v1.router, prefix="/api/v1")
app.include_router(communities_v2.router, prefix="/api/v2")
```

**When to version:** when you need to change a response shape and can't update all clients at once. Don't version prematurely.

---

## 16. `assert` — executable invariants

```python
assert row is not None  # RETURNING on successful INSERT always yields a row
```

Not error handling. It's a guarantee — "if this is False, something is fundamentally broken, crash immediately and loudly."

**When:** when the type system can't express the guarantee and a None/wrong value would cause a confusing error 3 layers later.

**Never use assert for user input validation** — `assert` can be disabled with `python -O`. Use `raise ValueError` or Pydantic for user-facing validation.

---

## 17. Swagger / OpenAPI — automatic docs

FastAPI auto-generates:
- `/docs` — Swagger UI (interactive)
- `/redoc` — ReDoc (readable)
- `/openapi.json` — raw schema

Powered by your type annotations and Pydantic models. Zero config.

**Improve docs:**
```python
@router.post(
    "/communities",
    response_model=CommunityResponse,
    status_code=201,
    summary="Create a community",                # short label in Swagger
    description="Creates a new community. Slug must be unique and URL-safe.",
    responses={
        409: {"description": "Slug already taken"},
        422: {"description": "Validation error"},
    }
)
```

**Disable docs in production:**
```python
app = FastAPI(docs_url=None, redoc_url=None)  # hidden from public
```
