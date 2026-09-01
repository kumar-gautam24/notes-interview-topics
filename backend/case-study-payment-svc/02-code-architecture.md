# 02 — Code Architecture

## The layered pattern

This project follows a common backend pattern with **three layers**. Think of it as a chain — each layer has a specific job and only talks to the layer next to it:

```
  HTTP Request
       │
       ▼
  ┌─────────────┐   Thin layer: parse request, check auth,
  │   ROUTER    │   return HTTP status codes
  │  (payment)  │   File: app/routers/payment.py
  └──────┬──────┘
         │ calls functions
         ▼
  ┌─────────────┐   Thick layer: ALL business logic,
  │   SERVICE   │   Razorpay API, SQL queries, LiteLLM sync
  │  (payment)  │   File: app/services/payment.py
  └──────┬──────┘
         │ uses helpers
         ▼
  ┌─────────────┐   Shared utilities: DB connection,
  │   UTILS     │   config, HTTP client, logging
  │  (various)  │   Files: app/utils/*.py
  └─────────────┘
```

**Why this matters:** When you add a feature, you touch files in a predictable order: models → service → router. You never put SQL in the router or HTTP status codes in the service.

---

## Every file explained

### Entry point

**`app/main.py`** — The starting point of the entire application.

```python
app = FastAPI(title="Common Control Service")   # creates the app
app.add_middleware(CORSMiddleware, ...)          # allows frontend to call this API
app.include_router(payment_router.router, prefix="/payments", tags=["Payments"])
app.include_router(
    subscription_router.router,
    prefix="/subscriptions",
    tags=["Subscriptions"],
)
```

What happens when the app starts:
1. Python loads this file
2. FastAPI app is created
3. CORS middleware is added (so browsers don't block requests from the frontend)
4. The **payment** router is mounted — routes get the `/payments` prefix
5. The **subscription** router is mounted — routes get the `/subscriptions` prefix
6. A `/health` endpoint is added for monitoring

### Router layer

**`app/routers/payment.py`** — One-time payments and credit wallet HTTP endpoints.

**`app/routers/subscription.py`** — Subscription plan catalog and admin plan creation (`GET`/`POST /subscriptions/plans`); additional subscribe/status/cancel/invoice routes follow the same pattern as doc 09 when implemented.

Responsibilities (and ONLY these):
- Define the URL path and HTTP method (`@router.post("/orders")`)
- Extract user identity from request headers
- Call service functions
- Convert exceptions to HTTP error responses
- Return Pydantic response models

Key pattern — the `get_user_id_from_request` helper:
```python
async def get_user_id_from_request(request: Request) -> str:
    # First check: is user_id directly in headers?
    user_id = request.headers.get('userid', None)
    if user_id is None:
        # Second check: decode from Authorization token
        access_token = request.headers.get('authorization')
        user_id_email = await common_utils.get_user_id_email_from_token(access_token)
        user_id = user_id_email['user_id']
    return user_id
```

### Service layer

**`app/services/payment.py`** — One-time payment and credit wallet business logic.

This is the biggest file (~460 lines). It handles:
- Razorpay client setup and API calls
- LiteLLM budget sync
- Credit package definitions (hardcoded dict, not DB)
- All SQL queries (INSERT, UPDATE, SELECT)
- Idempotent payment processing
- Refund orchestration

Key sections (in order):
1. **Lines 1-38:** Imports, Razorpay client init, LiteLLM config
2. **Lines 40-66:** Credit packages (hardcoded `DEFAULT_PACKAGES` dict), getters
3. **Lines 70-106:** Razorpay helpers — create order, verify signature (HMAC)
4. **Lines 108-176:** `process_payment_captured()` — the most important function (idempotent payment handler)
5. **Lines 180-260:** DB operations for `razorpay_orders` table
6. **Lines 266-344:** Refund logic
7. **Lines 348-416:** Credit balance operations (`add_credits`, `deduct_credits`, `get_balance`)
8. **Lines 420-460:** Transaction ledger operations

**`app/services/subscription.py`** — Razorpay subscription plans (`list_plans`, `create_plan_and_persist`), user subscription lifecycle, and webhook helpers per [09 — Subscription dev guide](./09-subscription-dev-guide.md).

### Models

**`app/models/payment.py`** — Pydantic schemas for request/response validation.

These are NOT database models (no ORM). They define:
- What fields a request body must have (e.g., `CreateOrderRequest` needs `package_id`)
- What fields a response contains (e.g., `CreateOrderResponse` has `razorpay_order_id`, `amount`, etc.)
- Enums for valid values (`OrderStatus`: created, paid, failed, refunded)

**`app/models/subscription.py`** — Pydantic schemas for plans (`PlanResponse`, `CreatePlanRequest`) and user subscription flows (`SubscribeRequest`, invoice types, etc.).

FastAPI uses these for:
- Auto-validating incoming JSON
- Auto-generating Swagger docs
- Type-checking responses

### Utilities

**`app/utils/db_utils.py`** — Database connection and query execution.

The core of how this app talks to PostgreSQL:
- Creates a **sync** SQLAlchemy engine with connection pooling
- `execute_query(sql)` — run raw SQL, return pandas DataFrame
- `execute_query_with_params(sql, params)` — run parameterized SQL (safe from SQL injection), return DataFrame or dict
- `execute_non_query(sql)` — INSERT/UPDATE/DELETE, returns rowcount
- Helper functions for batch inserts, table column fetching

**`app/utils/config_utils.py`** — Configuration loader.

- Reads `app/config/app_config.ini` (tries multiple paths)
- Selects section based on `ENVT` environment variable (DEV or PROD)
- Merges COMMON + environment-specific settings
- `get_config("KEY")` — the function you'll use everywhere; result is cached

**`app/utils/common_utils.py`** — Shared helpers.

A grab-bag of utilities:
- Date/time formatting (IST timezone)
- User lookup by email (`get_user_id_from_email`)
- Token → user_id resolution (`get_user_id_email_from_token`)
- Sync and async HTTP callers
- String manipulation helpers

**`app/utils/security_utils.py`** — Token validation.

- `decode_token()` — sync token validation via external auth endpoint
- `async_decode_token()` — async version
- Redis-based phone/email verification checks

**`app/utils/redis_utils.py`** — Async Redis wrapper.

- `RedisUtil` class with `set_msg`, `get_msg`, `delete_msg`
- Used for caching (tokens, rate limit counters)
- Payment flow doesn't directly require Redis — it's used by rate limiting and auth caching

**`app/utils/http_client.py`** — Async HTTP with retry.

- `AsyncHTTPClient` class with `post_with_retry()` — exponential backoff on 429/5xx
- `stream_post()` — for SSE streaming responses
- Used by inference services, not directly by payment flow

**`app/utils/rate_limit.py`** — Redis-backed rate limiting middleware.

- `RateLimitMiddleware` — checks RPM/TPM per API key
- Only activates for paths under `/fathom-<app>-30b` (not payment routes)
- Reads key metadata from Redis, enforces limits

**`app/utils/log_utils.py`** — Logging setup.

- Wraps loguru logger
- `AstraLogger` class with optional HTTP log shipping
- Throughout the codebase, you'll see `from loguru import logger` used directly

**`app/utils/response_codes.py`** — HTTP status constants.

- `Failure.UNAUTHORIZED_CODE = 401`
- `Failure.UNAUTHORIZED_MSG = "Authorization token is required."`

**`app/utils/request_utils.py`** — Test helper.

- `create_dummy_request()` — builds a fake Starlette Request with a hardcoded test token
- Useful for calling router functions from a Python REPL

**`app/utils/prompt_utils.py`** — AI system prompts (not payment-related).

- Contains the <AppName> healthcare chatbot system prompt
- Exists in this repo likely because it was split from a larger service

**`app/utils/connection.py`** — WebSocket manager (not payment-related).

- `ConnectionManager` for WebSocket connections
- Not used by any payment endpoint

### Database (async — unused)

**`app/database.py`** — Async SQLAlchemy setup.

- Creates an async engine using `asyncpg` driver
- Provides `get_db()` dependency for FastAPI's `Depends()`
- **Currently not used** by any router or service — the payment flow uses sync `db_utils.py` instead
- Likely prepared for a future migration to async DB access

### Migrations

**`app/migrations/001_payment_tables.sql`** — SQL to create the payment tables.

- Run manually against PostgreSQL (not auto-applied)
- Creates 3 tables + indexes

### Deployment

**`deploy/dev/`** and **`deploy/prod/`** — Kubernetes YAML manifests.

- `namespace.yml` — creates the `<app>-ns` namespace
- `deployment.yml` — pod spec: image, env vars (`ENVT=DEV`), resources, volume mounts
- `service.yml` — internal Kubernetes service (ClusterIP)
- `ingress-route.yml` — external access rules

**`Dockerfile`** — Builds the container image.

- Base: `python:3.12-slim`
- Installs system deps (libpq for PostgreSQL), pip deps
- Copies app code, runs uvicorn on port 80

---

## Dependency flow (what imports what)

```
main.py
  ├── routers/payment.py
  │     ├── models/payment.py      (Pydantic schemas)
  │     ├── services/payment.py    (business logic)
  │     │     ├── utils/db_utils.py      (SQL execution)
  │     │     │     └── utils/config_utils.py  (DB credentials)
  │     │     ├── utils/config_utils.py  (Razorpay keys, LiteLLM URL)
  │     │     └── razorpay SDK           (external)
  │     ├── utils/common_utils.py  (token → user_id)
  │     └── utils/response_codes.py
  ├── routers/subscription.py
  │     ├── models/subscription.py
  │     └── services/subscription.py   (plans, subs, webhooks)
  └── utils/config_utils.py        (CORS origins)
```

---

## Next doc

→ [03 - Request Lifecycle](./03-request-lifecycle.md) — step-by-step trace of a real request
