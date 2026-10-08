# 03 · FastAPI Prep Pack

The screener already rated your FastAPI, async, auth, Redis and webhooks as strong. The client round checks whether you know *why* things work, not just how. Every pattern below appears in one runnable file, [fastapi_demo.py](code/fastapi_demo.py): a tiny multi-tenant "leads" CRM with JWT, RBAC, versioning, pagination, error handling and a 202 job pattern. It has its own tests (`python3 fastapi_demo.py`), and they pass. Read it once end to end; it's ~250 lines.

---

## 1. What FastAPI is, in one breath
> "FastAPI is an ASGI framework built on **Starlette** (routing, requests, middleware, WebSockets) and **Pydantic** (validation and serialisation). It uses type hints to validate input, serialise output and generate OpenAPI docs automatically. It runs on an ASGI server like **Uvicorn**, usually several worker processes behind Nginx or a load balancer."

- **ASGI vs WSGI:** WSGI (Flask, classic Django) is synchronous, one request per worker thread. ASGI supports async, WebSockets and long-lived connections.
- **Why fast:** async I/O on uvloop plus Pydantic v2's core written in Rust. It's not faster for CPU-bound work; that still needs processes.
- **Django vs Flask vs FastAPI:** Django is batteries-included (ORM, admin, auth, migrations), great for CRUD-heavy products. Flask is minimal and sync-first. FastAPI is async-first, type-driven and API-focused, so you bring your own ORM (SQLAlchemy, or raw asyncpg like you do).

## 2. Request lifecycle (draw this if asked)
`Client → Nginx/LB → Uvicorn worker (event loop) → middleware (outer to inner) → routing → dependency resolution → Pydantic validates body/query/path → endpoint → response_model filters and serialises → middleware (inner to outer) → client`

- Validation failure → automatic **422** with field-level details, before your code runs.
- An exception raised anywhere → matching `exception_handler`, otherwise a 500.

## 3. `async def` vs `def` endpoints (most-asked FastAPI question)
| | `async def` | `def` |
|---|---|---|
| Runs on | The event loop thread | A threadpool (default ~40 threads) |
| Use when | Everything inside is awaitable (asyncpg, httpx, redis.asyncio) | You must call blocking libraries (psycopg2, requests, boto3) |
| Danger | One blocking call freezes **every** request on that worker | Threadpool exhaustion under heavy load |

Your story: "I found a sync DB driver called inside `async def` endpoints, which blocked the loop, plus a pool capped at 10 per service." Fixes: async driver, `await run_in_threadpool(fn)` / `asyncio.to_thread(fn)`, or move the work to a queue worker.

## 4. Pydantic models and validation
```python
class LeadCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    email: str
    phone: str | None = None

    @field_validator("email")
    @classmethod
    def normalise_email(cls, v): ...

class LeadOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)   # build from ORM/record objects
    id: str; name: str; email: str
```
- **Separate input and output models** (`LeadCreate`, `LeadUpdate`, `LeadOut`): clients can't set `id`/`tenant_id`, and `response_model` strips fields like `password_hash`.
- `model_dump(exclude_unset=True)` for PATCH, so you only update the fields actually sent.
- v2 names: `model_dump`, `model_validate`, `field_validator`, `model_validator`, `ConfigDict`. (v1 used `dict()`, `parse_obj`, `validator`, `class Config`. Knowing the difference signals real use.)

## 5. Dependency injection (`Depends`)
A dependency is any callable whose parameters FastAPI resolves too, so they chain. It's cached per request by default.
- Uses: DB connection/session, current user, tenant, pagination params, settings, rate limiter, a repository/service.
- `yield` dependencies run cleanup after the response (release a connection, close a session).
- **Testing:** `app.dependency_overrides[get_repo] = lambda: FakeRepo()`, which is why DI beats importing globals.

```python
async def get_conn(request: Request):
    async with request.app.state.pool.acquire() as conn:   # released after the response
        yield conn

def require_role(*roles):
    async def checker(user = Depends(get_current_user)):
        if user.role not in roles:
            raise HTTPException(403, "Insufficient role")
        return user
    return checker

@router.post("/imports", status_code=202)
async def start_import(user = Depends(require_role(Role.admin))): ...
```
Same idea as GetIt in your Flutter apps: the endpoint asks for what it needs instead of constructing it.

## 6. Authentication and authorisation
- **Flow:** login checks an argon2/bcrypt hash → issue a short-lived **access JWT** (5–15 min) and a long-lived **refresh token** (stored hashed in the DB for revocation) → client sends `Authorization: Bearer <access>` → a dependency verifies signature + `exp` and loads claims → RBAC dependency checks role → repository filters by `tenant_id` from the token.
- **Refresh rotation:** each refresh issues a new refresh token and invalidates the old one; reuse of an old one means theft, so revoke the whole family. Change-password revokes all sessions (you built this in Recurring).
- **JWT facts:** header.payload.signature, base64url, **signed not encrypted**, so never put secrets in it. HS256 = shared secret; RS256 = private key signs, public key verifies (better when many services validate, which fits your "token contract every service validates against").
- **Logout with stateless JWT:** short expiry + a denylist in Redis keyed by `jti` until expiry (your Apple Sign-In bug was exactly this key design).
- **OAuth2:** a delegation protocol. Authorization Code + PKCE for user login via Google/Apple; Client Credentials for service-to-service. FastAPI has `OAuth2PasswordBearer` helpers for the docs UI.
- **401 vs 403:** 401 = who are you (missing or invalid token); 403 = I know you, you're not allowed. For another tenant's resource return **404**, so you don't reveal it exists.
- Other hardening: CORS allowlist (`CORSMiddleware`), rate-limit login/OTP per IP and per account, HTTPS only, secrets from env, Pydantic everywhere (no SQL injection via parameterised queries `$1`).

## 7. Error handling (JD point 5)
```python
class AppError(Exception): status_code = 500; code = "internal_error"
class NotFoundError(AppError): status_code, code = 404, "not_found"

@app.exception_handler(AppError)
async def handle_app_error(request, exc):
    return JSONResponse(status_code=exc.status_code, content={"code": exc.code, "message": exc.message,
                                          "request_id": request.state.request_id})

@app.exception_handler(Exception)
async def handle_unexpected(request, exc):
    log.exception("unhandled, request_id=%s", request.state.request_id)
    return JSONResponse(status_code=500, content={"code": "internal_error", "message": "Something went wrong",
                              "request_id": request.state.request_id})
```
- Services raise **domain errors** with no HTTP knowledge; handlers map them to status codes. Clean Architecture boundary.
- `HTTPException` is fine at the router layer, not inside services.
- Customise 422 with a `RequestValidationError` handler if the frontend needs one error shape.
- Logging: structured JSON with `request_id`, user, tenant, path, latency (middleware in the demo). Monitoring: Sentry for exceptions, metrics on p95 latency and error rate, alerts.

## 8. Middleware
Runs around every request: request id, timing/logging, CORS, GZip, trusted hosts, auth for some apps. Order matters: first added = outermost. Don't do heavy work or DB calls in middleware; prefer dependencies for anything route-specific.

## 9. Background work: three levels
| Tool | Where it runs | Survives restart? | Use for |
|---|---|---|---|
| `BackgroundTasks` | Same process, after the response is sent | No | Tiny fire-and-forget (audit log, cache warm) |
| `asyncio.create_task` | Same event loop | No | Rarely in APIs; easy to lose errors |
| **Queue + workers** (Celery / RQ / arq / your Redis workers) | Separate processes | Yes, with retries | Emails, imports, reports, LLM pipelines, anything slow or important |

**10-minute request pattern** (demo's `/v1/imports`): `POST` → validate → create job row → enqueue → **202 + job_id** → worker updates progress → client polls `GET /jobs/{id}`, or SSE/WebSocket, or a webhook. That's your Vaidya pipeline: run id → Redis workers → SSE.

## 10. API design and versioning (JD point 1)
- Resources as nouns, HTTP verbs for actions: `GET /leads`, `POST /leads`, `GET /leads/{id}`, `PATCH /leads/{id}`, `DELETE /leads/{id}`. Sub-resources: `/leads/{id}/notes`.
- Status codes: 200 OK · 201 Created · 202 Accepted (async job) · 204 No Content · 400 bad request · 401 · 403 · 404 · 409 conflict (duplicate / stale version) · 422 validation · 429 rate limited · 500 · 503.
- **Idempotency:** GET/PUT/DELETE are idempotent by definition; make POST idempotent with an `Idempotency-Key` header or client-generated UUID (your Recurring sync: retry returns 200, not a duplicate).
- **Pagination:** offset (`?page=3`) is simple but slow at depth and shifts when rows are inserted; **cursor/keyset** (`?after=<last_id>`) is stable and uses the index. Demo uses keyset.
- Filtering/sorting via query params with an allowlist of sortable fields.
- **Versioning without breaking mobile:** only additive changes in place (demo: v2 adds `source`, v1 response unchanged); for breaking changes use `/v2` routers (`APIRouter(prefix="/v2")`), keep v1, add `Deprecation`/`Sunset` headers, track v1 traffic, enforce a minimum app version, then remove.
- Optimistic concurrency: send `updated_at` or a `version`; return 409 with the current row when stale (you built this).

## 11. Performance (JD point 4)
- Async drivers + **connection pool** sized to the DB's max connections ÷ number of workers × instances (your "pool capped at 10" lesson). Create the pool once in `lifespan`, not per request.
- Fix N+1 (JOIN or `WHERE id = ANY($1)`), select only needed columns, paginate, index filter/sort columns.
- Cache hot reads in Redis with TTL; invalidate on write. HTTP caching with ETag for static-ish data.
- `ORJSONResponse` for big JSON, GZip middleware, return fewer fields.
- Multiple Uvicorn/Gunicorn workers (processes) per machine, horizontal scaling behind a load balancer; keep the API **stateless** (sessions/state in Redis/DB) so any instance can serve any request.
- Offload slow things (emails, PDFs, third-party calls) to workers: your OTP 8–10s → ~500ms.
- Measure first: request timing middleware, `EXPLAIN ANALYZE`, APM traces, load testing with Locust/k6.

## 12. Lifespan, config, structure
- `lifespan` async context manager replaces `@app.on_event("startup")`: create the DB pool, Redis client and HTTP client once; close them on shutdown.
- Config via `pydantic-settings` `BaseSettings` reading env vars; one cached `get_settings()` dependency.
- Structure (Clean Architecture, like your Flutter apps):
  ```
  app/
    api/v1/routers/       # HTTP only: parse, call service, return schema
    schemas/              # Pydantic request/response models
    services/             # business rules, raise domain errors
    repositories/         # SQL, one per aggregate
    core/                 # config, security, logging, exceptions
    workers/              # queue tasks
  ```

## 13. Testing
- `TestClient` (sync) or `httpx.AsyncClient` with `ASGITransport` for async tests; `pytest` + `pytest-asyncio`.
- Override dependencies for auth/DB in unit tests; run integration tests against a **real Postgres** in Docker (you do this, say so).
- Test the unhappy paths: 401, 403, 404 cross-tenant, 409, 422. The demo's self-test covers all of these.

## 14. WebSockets and SSE
- `@app.websocket("/ws")` → `await ws.accept()`, `receive_text()`, `send_json()`; handle `WebSocketDisconnect`.
- SSE: `StreamingResponse(gen(), media_type="text/event-stream")`, one-way server → client over HTTP, auto-reconnect. Simpler than WebSockets when the client only listens (your pipeline progress).
- Multiple instances: a client is connected to one worker, so broadcast via **Redis pub/sub** (Django Channels' channel layer does the same job).

## 15. Rapid-fire
| Question | Answer |
|---|---|
| How does FastAPI generate docs? | From route signatures + Pydantic models → OpenAPI JSON → Swagger UI at `/docs`, ReDoc at `/redoc` |
| Path vs query vs body | Path in URL template; scalar params not in the path are query; Pydantic model params are body |
| `response_model` purpose | Validates and **filters** output; documents the schema |
| `status_code=` on the decorator | Default success status, e.g. 201 for create |
| Where to put DB pool | `app.state` via lifespan; get it through a dependency |
| How to run in prod | `gunicorn -k uvicorn.workers.UvicornWorker -w 4` or `uvicorn --workers 4`, behind Nginx with TLS, in Docker |
| Rate limiting | Redis `INCR` + `EXPIRE` per key (IP/user/tenant) in a dependency or middleware; return 429 with `Retry-After` |
| Webhook handling | Verify HMAC on the raw body, dedupe by event id (idempotent), return 2xx fast, process in a worker, reconcile missed events (your Razorpay setup) |
| File uploads | `UploadFile` streams to disk/S3; for big files issue a **presigned URL** so uploads skip the API (your R2 signed URLs) |
