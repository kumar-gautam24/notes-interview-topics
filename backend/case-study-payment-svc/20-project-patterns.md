# 20 — Project Patterns (the glue between layers)

> This doc covers the cross-cutting patterns that hold the codebase together:
> how layers connect, how config works, how we log, how we talk to external
> services, and how we keep data consistent.

---

## Part A — Layered Architecture

### The three layers

```
HTTP Request
     │
     ▼
┌──────────────────────┐
│   Router              │  Translates HTTP ↔ Python
│   (app/routers/)      │  Validates input, returns responses
│                       │  Catches exceptions → HTTP errors
└───────────┬──────────┘
            │ calls
            ▼
┌──────────────────────┐
│   Service             │  Business logic
│   (app/services/)     │  Talks to Razorpay, manages credits
│                       │  Raises ValueError / RuntimeError
└───────────┬──────────┘
            │ calls
            ▼
┌──────────────────────┐
│   Utils               │  Database, config, security
│   (app/utils/)        │  No business logic — pure infrastructure
└──────────────────────┘
```

### Why separate layers?

| Rule | Reason |
|------|--------|
| Routers don't touch the database | If you change DB schema, only services need updating |
| Services don't know about HTTP | You can call `add_credits()` from a webhook, API route, or CLI script |
| Utils don't know about business logic | `execute_query_with_params` works for any SQL, any table |

### Example: the flow of `POST /subscriptions/subscribe`

```
1. Router receives HTTP request
   → validates body with Pydantic (SubscribeRequest)
   → extracts user_id from headers

2. Router calls sub_svc.create_subscription(user_id, plan_id)

3. Service:
   → gets plan from DB (via execute_query_with_params)
   → checks for existing subscription (business rule)
   → calls rz_client.subscription.create() (Razorpay SDK)
   → inserts row into user_subscriptions
   → returns dict

4. Router wraps dict in SubscribeResponse model
   → FastAPI serializes to JSON
   → sends HTTP 200 response
```

### What goes where — decision guide

| Question | Layer |
|----------|-------|
| Parse request / validate input? | Router |
| Check business rules? (already subscribed, insufficient funds) | Service |
| Talk to external API? (Razorpay, LiteLLM) | Service |
| Read/write database? | Service (calls Utils) |
| Format HTTP response? | Router |
| Handle DB connection / pool? | Utils |
| Read config values? | Utils |

---

## Part B — Config Management

### How it works

From `app/utils/config_utils.py`:

```
app_config.ini
    │
    ├── [COMMON]          ← shared across all environments
    │     DB_HOST = ...
    │     CORS_ORIGINS = ...
    │
    ├── [DEV]             ← overrides for development
    │     RAZORPAY_KEY_ID = rzp_test_xxx
    │
    └── [PROD]            ← overrides for production
          RAZORPAY_KEY_ID = rzp_live_xxx
```

The `ENVT` environment variable (defaults to `DEV`) determines which section
overrides COMMON.

### The loading chain

```python
# 1. Parser reads the INI file
parser = RawConfigParser()
parser.optionxform = str    # preserve case (default lowercases keys)
parser.read("app/config/app_config.ini")

# 2. get_all_configs merges COMMON + current env
def get_all_configs():
    common = parser_dict.get('COMMON', {})
    env = __get_current_envt_configs()    # DEV or PROD section
    return {**common, **env}              # env overrides common

# 3. get_config returns a single value
@lru_cache
def get_config(key: str):
    return get_all_configs().get(key, '').strip("'\"")
```

### Key features

**Case preservation**: `parser.optionxform = str` keeps `RAZORPAY_KEY_ID` as-is.
Without this, configparser lowercases everything to `razorpay_key_id`.

**Quote stripping**: `.strip("'\"")` removes surrounding quotes. INI files sometimes
have values like `CORS_ORIGINS='http://localhost:3000'`.

**Memoization**: `@lru_cache` on `get_config` means the INI file is parsed once
and cached forever. Config never changes at runtime.

### Config path discovery

The parser tries multiple paths to find the INI file:

```python
config_paths = [
    os.path.abspath("./../config/app_config.ini"),
    os.path.abspath("./app/config/app_config.ini"),
    os.path.abspath("./config/app_config.ini"),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "config", "app_config.ini")),
]
```

This handles different working directories: running from the repo root, from inside
`app/`, or from a parent directory. The `for ... else` pattern stops at the first
file that exists.

---

## Part C — Logging with Loguru

### Why loguru over stdlib logging

| Feature | stdlib `logging` | `loguru` |
|---------|-----------------|----------|
| Setup | 15+ lines of config | `from loguru import logger` — done |
| Formatting | Manual formatter objects | Auto-colored, structured output |
| Placeholders | `%s` or `.format()` | `{}` with lazy evaluation |
| Stack traces | Manual `exc_info=True` | Automatic on `logger.exception()` |

### How we use it

```python
from loguru import logger

# Info — normal operations
logger.info("Webhook: credited {} credits for order {}", credits, order_id)

# Warning — something unusual but not broken
logger.warning("Webhook: refund skipped for order {}: {}", order_id, exc)

# Error — something failed
logger.error("Razorpay subscription create failed for user {}: {}", user_id, exc)

# Critical — system-level failure requiring human intervention
logger.critical("Auto-refund also failed for order {}: {}", order_id, refund_exc)

# Debug — verbose info for development
logger.debug("Webhook: ignoring event {}", event_type)
```

### Lazy evaluation (why `{}` not f-strings)

```python
# BAD — f-string evaluates even if log level filters it out
logger.debug(f"Processing user {get_expensive_data(user_id)}")

# GOOD — {} is only evaluated if debug level is enabled
logger.debug("Processing user {}", get_expensive_data(user_id))
```

In production with log level set to WARNING, the bad version still calls
`get_expensive_data()` for nothing. The good version skips it entirely.

### Log levels (from noisiest to quietest)

```
DEBUG    → development details (webhook events we ignore)
INFO     → normal operations (order created, credits added)
WARNING  → unexpected but handled (refund skipped, subscription not found)
ERROR    → failures (Razorpay API down, LiteLLM sync failed)
CRITICAL → system-level emergencies (auto-refund failed, data inconsistency)
```

---

## Part D — HTTP Clients

### Sync: `requests`

Used in `app/services/payment.py` for LiteLLM API calls:

```python
import requests

resp = requests.post(
    url,
    json=payload,       # auto-serializes dict to JSON, sets Content-Type
    timeout=10,          # fail after 10 seconds (never hang forever)
    headers=_auth_headers(),
    verify=False,        # skip TLS certificate verification
)
resp.raise_for_status()  # raises HTTPError for 4xx/5xx responses
```

And in `app/utils/security_utils.py` for token validation:

```python
decoded_token = requests.request(
    "POST",
    TOKEN_VALIDATE_URL,
    headers=headers,
    data=payload,  # raw string body (not json=)
)
return decoded_token.json()
```

### Async: `httpx`

Used in `app/utils/security_utils.py` for async token validation:

```python
import httpx

async with httpx.AsyncClient(verify=False, timeout=30.0) as client:
    resp = await client.post(url, headers=headers, json=payload)
    return resp.json()
```

### When to use which

| Situation | Use |
|-----------|-----|
| Called from a sync service function | `requests` |
| Called from an async route/function | `httpx` (async) |
| Internal service, self-signed cert | `verify=False` |
| External API (Razorpay, etc.) | `verify=True` (default) |

### `verify=False` — why and when

Our internal services (LiteLLM, token validator) use self-signed TLS certificates
that `requests`/`httpx` don't trust by default. `verify=False` skips certificate
validation.

For external APIs (Razorpay), we use the default `verify=True` because they have
proper certificates from trusted CAs.

---

## Part E — Third-Party SDK Pattern (Razorpay)

### Module-level singleton

From `app/services/payment.py`:

```python
import razorpay

_rz_key_id = get_config("RAZORPAY_KEY_ID")
_rz_key_secret = get_config("RAZORPAY_KEY_SECRET")

rz_client = razorpay.Client(auth=(_rz_key_id, _rz_key_secret))
```

The client is created ONCE when the module is imported and reused for every request.
This avoids:
- Re-reading config on every call
- Creating a new HTTP session per request
- Re-authenticating per request

### Wrapping SDK calls

Every Razorpay call is wrapped in try/except:

```python
try:
    rz_sub = rz_client.subscription.create({
        "plan_id": plan["razorpay_plan_id"],
        "total_count": 120,
        "quantity": 1,
        "customer_notify": 1,
    })
except Exception as exc:
    logger.error("Razorpay subscription create failed for user {}: {}", user_id, exc)
    raise
```

Pattern: log the error with context, then re-raise. The router catches it and
returns 502 (Bad Gateway) to the client.

### SDK methods we use

```python
rz_client.order.create(data=payload)           # create a payment order
rz_client.plan.create({...})                    # create a subscription plan
rz_client.subscription.create({...})            # create a subscription
rz_client.subscription.cancel(rz_sub_id, {...}) # cancel a subscription
rz_client.payment.refund(payment_id, {...})     # refund a payment
```

All return dicts. We extract what we need with `.get()`.

---

## Part F — Auth Patterns

### Pattern 1: User identification from headers

```python
async def get_user_id_from_request(request: Request) -> str:
    # Path A: direct user_id header (from internal services)
    user_id = request.headers.get('userid', None)

    if user_id is None:
        # Path B: JWT token (from frontend)
        access_token = request.headers.get('authorization')
        if not access_token:
            raise HTTPException(status_code=401, detail="Unauthorized")
        user_id_email = await common_utils.get_user_id_email_from_token(access_token)
        user_id = user_id_email['user_id']

    return user_id
```

Two auth paths because:
- Internal microservices already validated the user — they pass `userid` directly
- Frontend apps send a JWT token that needs validation

### Pattern 2: Admin key via Depends

```python
_admin_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)

def verify_admin_key(api_key: str = Depends(_admin_key_header)) -> str:
    expected = get_config("SUBSCRIPTION_ADMIN_KEY")
    if not api_key or not hmac.compare_digest(api_key, expected):
        raise HTTPException(status_code=401, detail="Invalid or missing admin key")
    return api_key
```

Used only for admin endpoints (creating plans). The key is a shared secret
stored in config.

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

Razorpay signs webhook bodies with a shared secret (HMAC-SHA256). We:
1. Recompute the signature from the raw body + our secret
2. Compare it to the `X-Razorpay-Signature` header
3. If they don't match, reject with 400

### Why `hmac.compare_digest` instead of `==`

Regular `==` compares strings character by character and returns `False` early when
it finds a mismatch. An attacker can measure response times to guess the correct
string one character at a time (timing attack).

`hmac.compare_digest` always takes the same amount of time regardless of where the
strings differ. No timing information leaks.

---

## Part G — Idempotency

### The problem

Webhooks can be delivered multiple times. A user might click "Pay" twice. Network
errors can cause retries. Your system must handle duplicate requests safely.

### Our three idempotency patterns

**1. Atomic status transition (UPDATE WHERE status = 'expected')**

```python
# Only updates if the order is currently 'created' or 'failed'
sql = """
    UPDATE razorpay_orders
    SET status = 'paid'
    WHERE razorpay_order_id = :order_id
      AND status IN ('created', 'failed')
    RETURNING *
"""
# If already 'paid' → zero rows updated → return None (already processed)
```

**2. Unique constraint + catch duplicate**

```python
# subscription_invoices has a UNIQUE INDEX on razorpay_payment_id
try:
    execute_query_with_params("INSERT INTO subscription_invoices ...", params)
    return True
except Exception as exc:
    if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
        return False  # duplicate — already processed
    raise
```

**3. Pre-check before insert**

```python
existing = _get_invoice_by_payment(rz_payment_id)
if existing:
    logger.info("Payment {} already processed", rz_payment_id)
    return
```

We use all three together for belt-and-suspenders safety. The pre-check is fast
(avoids the exception path). The unique constraint catches race conditions. The
status transition prevents double-crediting.

---

## Part H — UUID Generation

### Our pattern

```python
import uuid

internal_id = str(uuid.uuid4())
# "a7b3c9d1-e2f4-4a5b-8c6d-7e8f9a0b1c2d"
```

Every primary key in our tables is a UUID v4 (random). Why:
- No central authority needed (unlike auto-increment)
- Safe to generate on any server without coordination
- Can't be guessed (unlike sequential IDs)
- Works across microservices (no "this ID belongs to service A's sequence")

### Where we generate them

```python
# Payment orders
internal_id = str(uuid.uuid4())  # in save_order()

# Subscriptions
sub_id = str(uuid.uuid4())       # in create_subscription()

# Invoices
"id": str(uuid.uuid4()),         # in _save_invoice()

# Transactions
txn_id = str(uuid.uuid4())       # in _record_transaction()
```

---

## Part I — Timestamp Conventions

### Our standard

```python
from datetime import datetime, timezone

now = datetime.now(timezone.utc).isoformat()
# "2026-04-12T10:30:00+00:00"
```

Every `created_at` and `updated_at` field uses this format. Always UTC, always
ISO 8601 with timezone offset.

### Converting Razorpay Unix timestamps

Razorpay sends timestamps as Unix seconds:

```python
# Razorpay: current_start = 1712923800 (seconds since 1970-01-01)
cs = sub_entity.get("current_start")
if cs:
    iso = datetime.fromtimestamp(int(cs), tz=timezone.utc).isoformat()
    # "2026-04-12T14:30:00+00:00"
```

### Converting for API responses

When returning timestamps to the frontend, we use `str()`:

```python
current_start=str(sub["current_start"]) if sub.get("current_start") else None,
created_at=str(inv["created_at"]),
```

This handles both `datetime` objects and already-stringified timestamps.

---

## Part J — Security Headers

From `app/utils/security_utils.py`:

```python
SECURITY_HEADERS = {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Strict-Transport-Security": "max-age=31556926; includeSubDomains",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block",
}
```

These same headers appear in our Ingress configuration-snippet. They protect against:

| Header | Protects against |
|--------|-----------------|
| `Strict-Transport-Security` | Downgrade attacks (forcing HTTP instead of HTTPS) |
| `X-Content-Type-Options: nosniff` | MIME-type confusion attacks |
| `X-Frame-Options: DENY` | Clickjacking (embedding your site in an iframe) |
| `X-XSS-Protection` | Cross-site scripting (older browsers) |
| `Cross-Origin-Opener-Policy` | Cross-origin window access |
| `Referrer-Policy` | Leaking URLs to third-party sites |

---

## Part K — Common Mistakes

### 1. Circular imports

```python
# payment.py imports from subscription.py
from app.services.subscription import handle_subscription_charged

# subscription.py imports from payment.py
from app.services.payment import add_credits

# Python tries to load payment.py, which needs subscription.py,
# which needs payment.py → ImportError!
```

Fix: import the module, not the function, and use it later:

```python
from app.services import payment as pay_svc
# Later:
pay_svc.add_credits(...)
```

### 2. Sync calls in async routes (blocking the event loop)

```python
# BAD — blocks the entire event loop for all users
async def my_route():
    result = requests.get("https://slow-api.com")  # sync HTTP in async route!

# GOOD — use async client
async def my_route():
    async with httpx.AsyncClient() as client:
        result = await client.get("https://slow-api.com")
```

Our services use sync functions, which is fine because FastAPI auto-runs them in
a threadpool. The problem is only when you put sync I/O directly in an async route.

### 3. Secrets in code

```python
# BAD — secret is in the source code (and git history)
ADMIN_KEY = "super-secret-key-123"

# GOOD — read from config (which reads from env/config file)
ADMIN_KEY = get_config("SUBSCRIPTION_ADMIN_KEY")
```

Our config file `app_config.ini` is committed to git — that's also not ideal for
production secrets, but it's better than hardcoding. In production, secrets should
come from environment variables or a secrets manager.

### 4. Missing error handling around external calls

```python
# BAD — if Razorpay is down, your whole route crashes with 500
rz_order = rz_client.order.create(data=payload)

# GOOD — catch, log, and return a meaningful error
try:
    rz_order = rz_client.order.create(data=payload)
except Exception as exc:
    logger.error("Razorpay order creation failed: {}", exc)
    raise HTTPException(status_code=502, detail="Payment gateway unavailable")
```

### 5. Not using `to_dict=True`

```python
# Returns a Pandas DataFrame — useless for JSON responses
rows = execute_query_with_params(sql, params)

# Returns list[dict] — what you actually want
rows = execute_query_with_params(sql, params, to_dict=True)
```
