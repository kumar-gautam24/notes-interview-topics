# 17 — FastAPI Guide (the framework behind every endpoint)

> This doc teaches FastAPI concept-by-concept, then shows exactly where each
> concept appears in our codebase. After reading this, you should be able to
> add a new endpoint without looking anything up.

---

## Part A — What FastAPI Actually Is

FastAPI is a Python web framework built on two foundations:

1. **Starlette** — handles the HTTP layer (routing, middleware, WebSockets)
2. **Pydantic** — handles data validation (request bodies, response models)

What FastAPI adds on top: automatic OpenAPI docs, dependency injection, and
seamless async support.

```
Browser/Client
     │
     ▼
  Uvicorn  (ASGI server — handles raw TCP/HTTP)
     │
     ▼
  FastAPI  (routing, validation, dependency injection)
     │
     ├── Middleware (CORS, security headers, etc.)
     │
     ├── Router → Service → Database
     │
     └── Auto-generates /docs (Swagger UI)
```

### ASGI vs WSGI (why it matters)

- **WSGI** (old): one request per thread. Flask, Django use this.
- **ASGI** (new): event loop, handles thousands of concurrent connections. FastAPI uses this.

That's why we run with **Uvicorn** (ASGI server), not Gunicorn alone. In production,
`run.sh` uses Gunicorn with Uvicorn workers:

```bash
gunicorn -w 4 -k uvicorn.workers.UvicornWorker app.main:app
```

This gives us: 4 worker processes, each running its own async event loop.

---

## Part B — App Setup

### Creating the app

From `app/main.py`:

```python
from fastapi import FastAPI

app = FastAPI(title="Common Control Service")
```

`FastAPI(title=...)` creates the application instance. The `title` appears in the
auto-generated docs at `/docs`.

### Registering routers

```python
from app.routers import payment as payment_router
from app.routers import subscription as subscription_router

app.include_router(payment_router.router, prefix="/payments", tags=["Payments"])
app.include_router(
    subscription_router.router,
    prefix="/subscriptions",
    tags=["Subscriptions"],
)
```

| Parameter | What it does |
|-----------|-------------|
| `prefix="/payments"` | All routes in this router get `/payments` prepended |
| `tags=["Payments"]` | Groups endpoints under "Payments" in the Swagger UI |

So a route decorated with `@router.post("/orders")` inside `payment_router`
becomes `POST /payments/orders` in the final app.

### Direct routes on the app

```python
@app.get("/health")
def health_check():
    return {"status": "ok"}
```

This registers `/health` directly, no prefix. We use this for health checks that
load balancers and Kubernetes probes hit.

---

## Part C — Routing

### APIRouter — splitting a big app into files

Each router file creates its own `APIRouter`:

```python
from fastapi import APIRouter

router = APIRouter()

@router.get("/plans", response_model=list[PlanResponse])
async def list_plans():
    return sub_svc.list_plans()
```

Think of `APIRouter` as a mini-app. It collects routes, then gets plugged into
the main app via `include_router`.

### HTTP methods

```python
@router.get("/plans")          # Read data
@router.post("/orders")        # Create something
@router.put("/plans/{id}")     # Replace entirely (we don't use this)
@router.patch("/plans/{id}")   # Partial update (we don't use this)
@router.delete("/plans/{id}")  # Delete (we don't use this)
```

We only use GET and POST. GET for reading, POST for everything that changes state.

### Path parameters

```python
# If we had this route:
@router.get("/plans/{plan_id}")
async def get_plan(plan_id: str):
    ...

# GET /subscriptions/plans/abc-123 → plan_id = "abc-123"
```

We don't use path params much — our endpoints use query params or request bodies.

### Query parameters

```python
@router.get("/invoices")
async def invoice_history(
    request: Request,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
```

| Part | Meaning |
|------|---------|
| `limit: int` | Must be an integer |
| `Query(50, ...)` | Default value is 50 |
| `ge=1` | Must be >= 1 |
| `le=200` | Must be <= 200 |

Request: `GET /subscriptions/invoices?limit=10&offset=20`

FastAPI validates automatically: `GET /subscriptions/invoices?limit=-5` returns
`422 Unprocessable Entity` with a clear error message.

### `response_model` — what the endpoint returns

```python
@router.get("/packages", response_model=list[CreditPackage])
async def list_packages():
    return pay_svc.get_packages()
```

What `response_model` does:
1. **Validates** — if your function returns data that doesn't match, you get an error
2. **Filters** — only fields defined in the model appear in the response (no accidental data leaks)
3. **Documents** — the response schema appears in Swagger UI

---

## Part D — Request Bodies

### How FastAPI reads POST data

When a route parameter is typed as a Pydantic model, FastAPI reads the JSON body
and validates it automatically:

```python
@router.post("/subscribe", response_model=SubscribeResponse)
async def subscribe(request: Request, body: SubscribeRequest):
    ...
```

Here `body: SubscribeRequest` means: parse the JSON body as a `SubscribeRequest`.
If the body is missing required fields or has wrong types, FastAPI returns 422.

Client sends:
```json
{ "plan_id": "abc-123" }
```

FastAPI parses it into `body.plan_id = "abc-123"`. If the client sends
`{ "plan_id": 123 }`, FastAPI rejects it (plan_id must be a string).

### Request object — when you need raw access

```python
async def razorpay_webhook(request: Request):
    raw_body = await request.body()           # raw bytes
    signature = request.headers.get("X-Razorpay-Signature", "")
```

Use `Request` when you need:
- Raw body bytes (for signature verification)
- HTTP headers (`request.headers`)
- The full request object for custom auth

You can have BOTH in the same route:

```python
async def subscribe(request: Request, body: SubscribeRequest):
    # request → for headers (auth)
    # body → for the parsed JSON payload
    user_id = await get_user_id_from_request(request)
    result = sub_svc.create_subscription(user_id, body.plan_id)
```

---

## Part E — Dependency Injection (`Depends`)

This is FastAPI's most powerful feature. It lets you inject shared logic
(auth, DB sessions, config) into routes without repeating yourself.

### Basic example — our admin auth

```python
from fastapi import Depends
from fastapi.security import APIKeyHeader

# Step 1: Define a "dependency"
_admin_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)

def verify_admin_key(api_key: str = Depends(_admin_key_header)) -> str:
    expected = get_config("SUBSCRIPTION_ADMIN_KEY")
    if not api_key or not hmac.compare_digest(api_key, expected):
        raise HTTPException(status_code=401, detail="Invalid or missing admin key")
    return api_key
```

What happens when a request comes in:

1. FastAPI sees `Depends(_admin_key_header)`
2. It calls `_admin_key_header`, which extracts the `X-Admin-Key` header
3. The header value becomes the `api_key` parameter
4. `verify_admin_key` checks it against the config
5. If invalid, it raises 401 — the route function never runs

### Using the dependency on a route

Two ways:

**Function parameter** — when you need the return value:

```python
@router.post("/admin-thing")
async def admin_thing(key: str = Depends(verify_admin_key)):
    # key = the validated admin key string
    ...
```

**Route-level dependency** — when you just need the check:

```python
@router.post("/plans", dependencies=[Depends(verify_admin_key)])
async def create_plan(body: CreatePlanRequest):
    # if we get here, the admin key was valid
    ...
```

### Why not just call the function directly?

```python
# Without DI — repeated in every admin route
@router.post("/plans")
async def create_plan(request: Request, body: CreatePlanRequest):
    api_key = request.headers.get("X-Admin-Key")
    if not api_key or not hmac.compare_digest(api_key, expected):
        raise HTTPException(status_code=401)
    ...

# With DI — declare once, use everywhere
@router.post("/plans", dependencies=[Depends(verify_admin_key)])
async def create_plan(body: CreatePlanRequest):
    ...
```

DI keeps auth logic in one place. Change the auth check once, all routes update.

### `APIKeyHeader` — built-in security dependency

```python
_admin_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)
```

| Parameter | What it does |
|-----------|-------------|
| `name="X-Admin-Key"` | Which header to extract |
| `auto_error=False` | Don't auto-raise 403; let us handle missing keys ourselves |

---

## Part F — Error Handling (HTTPException)

### The pattern

FastAPI converts `HTTPException` into proper HTTP error responses.

```python
from fastapi import HTTPException

raise HTTPException(status_code=404, detail="No active subscription")
```

Response:
```json
HTTP/1.1 404 Not Found
{ "detail": "No active subscription" }
```

### Status codes we use

| Code | Meaning | When we use it |
|------|---------|---------------|
| 400 | Bad Request | Invalid input, business rule violation |
| 401 | Unauthorized | Missing or invalid auth token / admin key |
| 402 | Payment Required | Insufficient credits |
| 403 | Forbidden | Order doesn't belong to this user |
| 404 | Not Found | Package, order, or subscription not found |
| 502 | Bad Gateway | Razorpay API failure, external service down |

### The router-service exception contract

Services raise Python exceptions:

```python
# Service layer
raise ValueError("Plan not found or inactive")    # → 400
raise RuntimeError("Razorpay returned no plan id") # → 502
```

Routers catch and translate:

```python
# Router layer
try:
    result = sub_svc.create_plan_and_persist(...)
except ValueError as exc:
    raise HTTPException(status_code=400, detail=str(exc))
except RuntimeError as exc:
    raise HTTPException(status_code=502, detail=str(exc))
except Exception as exc:
    raise HTTPException(status_code=502, detail="Failed to create plan")
```

Why? Services shouldn't know about HTTP. They raise domain errors. Routers
translate those into HTTP responses. Clean separation.

---

## Part G — Middleware

### What middleware is

Code that runs on EVERY request, before and after your route handler.

```
Request → Middleware → Route Handler → Middleware → Response
```

### CORS middleware (the only middleware we use)

From `app/main.py`:

```python
from fastapi.middleware.cors import CORSMiddleware

ALLOWED_ORIGINS = get_config("CORS_ORIGINS").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### What CORS is (and why you need middleware for it)

When your frontend at `https://app.example.com` calls your API at
`https://api.example.com`, the browser blocks it by default. This is the
**Same-Origin Policy** — a security feature.

CORS (Cross-Origin Resource Sharing) is the opt-in mechanism. Your API says:
"I trust requests from these origins."

| Parameter | What it does |
|-----------|-------------|
| `allow_origins=ALLOWED_ORIGINS` | List of trusted frontend domains |
| `allow_credentials=True` | Allow cookies and auth headers |
| `allow_methods=["*"]` | Allow all HTTP methods (GET, POST, etc.) |
| `allow_headers=["*"]` | Allow all request headers |

If a request comes from an origin not in the list, the browser blocks it (the
server never even sees the request body).

---

## Part H — Async vs Sync in FastAPI

### The rules

| Route definition | What FastAPI does |
|-----------------|-------------------|
| `async def endpoint()` | Runs on the main event loop. You MUST `await` all I/O. |
| `def endpoint()` | Runs in a background threadpool. Blocking I/O is fine. |

### Our pattern

All our routes are `async def` because they need `await` for:
- `await request.body()` — reading the raw request body
- `await get_user_id_from_request(request)` — async token validation

But our service functions are regular `def` because they use:
- `requests.post()` — sync HTTP client
- `rz_client.order.create()` — sync Razorpay SDK
- `execute_query_with_params()` — sync SQLAlchemy

FastAPI handles this correctly. When an `async def` route calls a sync function,
it doesn't block the event loop — FastAPI detects sync functions and runs them in
a threadpool.

### What if you do it wrong?

```python
# BUG: sync I/O in an async route blocks the ENTIRE event loop
async def bad_route():
    result = requests.get("https://slow-api.com")  # blocks all other requests!
    return result.json()

# FIX 1: make the route sync (FastAPI runs it in threadpool)
def better_route():
    result = requests.get("https://slow-api.com")
    return result.json()

# FIX 2: use an async HTTP client
async def best_route():
    async with httpx.AsyncClient() as client:
        result = await client.get("https://slow-api.com")
    return result.json()
```

---

## Part I — OpenAPI / Swagger Docs

### Free documentation

FastAPI auto-generates interactive API docs. Start the server and visit:
- `http://localhost/docs` — Swagger UI (interactive, try it out)
- `http://localhost/redoc` — ReDoc (read-only, better for sharing)

### How your code shapes the docs

Everything you write in Python translates to the docs:

```python
@router.post(
    "/plans",
    response_model=PlanResponse,             # ← response schema in docs
    dependencies=[Depends(verify_admin_key)], # ← shows lock icon (auth required)
)
async def create_plan(body: CreatePlanRequest):
    """Create a new subscription plan on Razorpay."""  # ← endpoint description
    ...
```

And in the model:

```python
class CreatePlanRequest(BaseModel):
    """Body for POST /subscriptions/plans."""  # ← schema description

    name: str = Field(
        min_length=1, max_length=128,
        description="Plan display name, e.g. 'Pro Monthly'",  # ← field description
    )
    amount_paise: int = Field(
        gt=0,
        description="Price per cycle in PAISE (₹399 = 39900). Not rupees!",
    )
```

The Swagger UI shows all of this: field names, types, constraints, descriptions,
example values. You get an API reference for free.

---

## Part J — Security Patterns

### Pattern 1: Header-based user ID

```python
async def get_user_id_from_request(request: Request) -> str:
    user_id = request.headers.get('userid', None)
    if user_id is None:
        access_token = request.headers.get('authorization')
        if not access_token:
            raise HTTPException(status_code=401, detail="Unauthorized")
        user_id_email = await common_utils.get_user_id_email_from_token(access_token)
        user_id = user_id_email['user_id']
    return user_id
```

Two auth paths:
1. Direct `userid` header (from internal services that already validated)
2. `authorization` header (JWT token from the frontend)

### Pattern 2: Admin key with `Depends`

```python
_admin_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)

def verify_admin_key(api_key: str = Depends(_admin_key_header)) -> str:
    expected = get_config("SUBSCRIPTION_ADMIN_KEY")
    if not api_key or not hmac.compare_digest(api_key, expected):
        raise HTTPException(status_code=401, detail="Invalid or missing admin key")
    return api_key
```

`hmac.compare_digest` instead of `==` prevents timing attacks — an attacker can't
guess the key character by character by measuring response time.

### Pattern 3: Webhook signature verification

```python
def verify_webhook_signature(raw_body: bytes, signature: str) -> bool:
    expected = hmac.new(
        _rz_webhook_secret.encode(),
        raw_body,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)
```

Razorpay signs the webhook body with a shared secret. We recompute the signature
and compare. If they don't match, someone is forging requests.

---

## Part K — Common Mistakes

### 1. Forgetting `await`

```python
# BUG
user_id = get_user_id_from_request(request)
# user_id is now a coroutine object, not a string

# FIX
user_id = await get_user_id_from_request(request)
```

### 2. Returning a dict when `response_model` expects a Pydantic model

```python
# Works but loses validation:
@router.get("/plans", response_model=list[PlanResponse])
async def list_plans():
    return sub_svc.list_plans()  # returns list[dict]
```

This actually works because FastAPI will try to construct PlanResponse from the dict.
But if the dict has extra keys or missing keys, you'll get confusing 500 errors.

### 3. Wrong exception for the situation

```python
# BAD — 500 Internal Server Error for a user mistake
raise Exception("Plan not found")

# GOOD — proper HTTP error
raise HTTPException(status_code=404, detail="Plan not found")
```

### 4. Not using `response_model`

```python
# BAD — no validation, leaks internal fields
@router.get("/credits")
async def get_credits(request: Request):
    return {"user_id": user_id, "balance": 100, "internal_secret": "oops"}

# GOOD — only fields in CreditBalanceResponse are returned
@router.get("/credits", response_model=CreditBalanceResponse)
async def get_credits(request: Request):
    ...
```

### 5. Hardcoding status codes

Instead of raw numbers, use descriptive names when the meaning isn't obvious:

```python
from starlette.status import HTTP_422_UNPROCESSABLE_ENTITY
# or just use the number with a comment
raise HTTPException(status_code=402)  # 402 = Payment Required (insufficient credits)
```

---

## Quick Reference

| Concept | Our code | File |
|---------|---------|------|
| App creation | `FastAPI(title="...")` | `app/main.py` |
| Router | `APIRouter()` | `routers/payment.py` |
| include_router | `app.include_router(router, prefix=, tags=)` | `app/main.py` |
| GET endpoint | `@router.get("/plans")` | `routers/subscription.py` |
| POST endpoint | `@router.post("/orders")` | `routers/payment.py` |
| Query params | `Query(50, ge=1, le=200)` | `routers/payment.py` |
| Response model | `response_model=list[PlanResponse]` | `routers/subscription.py` |
| Request body | `body: CreatePlanRequest` | `routers/subscription.py` |
| Raw request | `request: Request` | `routers/payment.py` |
| Dependency injection | `Depends(verify_admin_key)` | `routers/subscription.py` |
| HTTPException | `raise HTTPException(status_code=400)` | everywhere |
| CORS | `CORSMiddleware` | `app/main.py` |
| APIKeyHeader | `APIKeyHeader(name="X-Admin-Key")` | `routers/subscription.py` |
