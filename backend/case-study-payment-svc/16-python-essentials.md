# 16 — Python Essentials (every pattern we actually use)

> Read this doc if you can read Python but don't *think* in Python yet.
> Every example below is pulled from our codebase — nothing hypothetical.

---

## Part A — Type Hints

Python doesn't enforce types at runtime, but type hints make code self-documenting
and let tools like mypy catch bugs before you ship.

### Basic types

```python
user_id: str = "u_123"
amount: int = 500
budget_ok: bool = True
max_budget: float = 1200.0
```

### Optional — "this might be None"

```python
from typing import Optional

# Means: rz_payment_id is either a str or None
rz_payment_id: Optional[str] = payment_entity.get("id")
```

Where we use it: almost every function that reads from a dict. `dict.get()` returns
`None` if the key is missing, so the return type is `Optional`.

```python
# From app/services/payment.py
def get_order_by_rz_id(razorpay_order_id: str) -> Optional[dict]:
    ...
    return rows[0] if rows else None
```

### Collections

```python
# A list of dicts (each dict is a DB row)
def list_plans() -> list[dict]:
    ...

# A dict whose keys are strings and values are dicts
DEFAULT_PACKAGES: dict[str, dict] = { "pro": { ... } }

# A tuple with mixed types — (success, balance, transaction_id)
def deduct_credits(...) -> tuple[bool, int, Optional[str]]:
    ...
```

Note: `list[dict]` is the modern syntax (Python 3.9+). Older code uses
`List[Dict]` from `typing`. Both work, but we use the lowercase version.

### Literal — "only these exact values are allowed"

```python
from typing import Literal

period: Literal["daily", "weekly", "monthly", "quarterly", "yearly"]
```

Where we use it: `CreatePlanRequest` in `app/models/subscription.py`. Pydantic
will reject any value not in the list.

### Any — "I don't know the type"

```python
from typing import Any

features: Optional[dict[str, Any]] = None
```

`Any` is an escape hatch. Use it when the shape is genuinely unpredictable (like
a JSON blob from an external API). Don't use it out of laziness.

---

## Part B — Async / Await

### The mental model

Imagine a restaurant with one waiter (= one thread). Synchronous code means the
waiter stands at the kitchen door doing nothing while food cooks. Async code means
the waiter takes another table's order while waiting.

```python
# Synchronous — blocks the thread
def get_data():
    result = db.query("SELECT ...")   # thread sits idle during network I/O
    return result

# Asynchronous — releases the thread during I/O
async def get_data():
    result = await db.query("SELECT ...")  # thread serves other requests
    return result
```

### How our codebase uses it

| Layer | Sync or Async? | Why? |
|-------|---------------|------|
| Routers (`app/routers/*.py`) | `async def` | FastAPI runs async handlers on the event loop — max throughput |
| Services (`app/services/*.py`) | `def` (sync) | SQLAlchemy + `requests` are sync libraries. FastAPI auto-runs sync functions in a threadpool |
| Utils (`app/utils/security_utils.py`) | Both | `decode_token` is sync (uses `requests`), `async_decode_token` is async (uses `httpx`) |

### Rules of thumb

1. If the function calls `await` anything, it MUST be `async def`
2. If you call a sync function from an async route, FastAPI handles it — no deadlock
3. Never call an async function without `await` — you'll get a coroutine object, not the result

```python
# WRONG — forgot await
user_id = get_user_id_from_request(request)  # Returns a coroutine, not a string!

# RIGHT
user_id = await get_user_id_from_request(request)
```

### Where we mix them

In `app/routers/payment.py`, the route is `async def` but calls sync service
functions like `pay_svc.process_payment_captured()`. FastAPI detects this and runs
the sync function in a threadpool automatically. You don't need to do anything special.

```python
# Route is async (to use await for request.body())
async def razorpay_webhook(request: Request):
    raw_body = await request.body()           # async — needs await
    ...
    order = pay_svc.process_payment_captured(  # sync — FastAPI handles it
        rz_order_id, rz_payment_id
    )
```

---

## Part C — Context Managers (the `with` statement)

### The problem they solve

Resources like database connections and file handles need cleanup. If your code
crashes between "open" and "close", the resource leaks.

```python
# BAD — if query() throws, connection is never closed
conn = engine.connect()
result = conn.execute(query)
conn.close()

# GOOD — with guarantees close() runs even if an exception occurs
with engine.connect() as conn:
    result = conn.execute(query)
# conn.close() happens automatically here
```

### How we use them

In `app/utils/db_utils.py`:

```python
# engine.connect() — manual commit needed
with engine.connect() as connection:
    result = connection.execute(text(sql_query), params)
    connection.commit()   # you must explicitly commit

# engine.begin() — auto-commits on success, auto-rolls-back on exception
with engine.begin() as connection:
    result = connection.execute(text(sql_stmt))
    # commit happens automatically when the block exits without error
```

In `app/utils/security_utils.py`:

```python
# httpx.AsyncClient as an async context manager
async with httpx.AsyncClient(verify=False, timeout=30.0) as client:
    resp = await client.post(url, headers=headers, json=payload)
# client is closed automatically here
```

### How they work under the hood

Any object with `__enter__` and `__exit__` methods can be used with `with`.
For async, it's `__aenter__` and `__aexit__` with `async with`.

```python
# What "with engine.connect() as conn:" really does:
conn = engine.connect().__enter__()
try:
    # your code
finally:
    conn.__exit__(exc_type, exc_val, traceback)
```

---

## Part D — Decorators

### What they are

A decorator wraps a function with extra behavior. The `@` syntax is just shorthand.

```python
@router.get("/health")
def health_check():
    return {"status": "ok"}

# Is exactly the same as:
def health_check():
    return {"status": "ok"}
health_check = router.get("/health")(health_check)
```

### Decorators we use

| Decorator | Where | What it does |
|-----------|-------|-------------|
| `@router.get("/path")` | Routers | Registers a GET endpoint |
| `@router.post("/path")` | Routers | Registers a POST endpoint |
| `@router.get("/path", response_model=X)` | Routers | Also validates the return type |
| `@lru_cache` | `config_utils.py` | Caches the return value so the function only runs once |
| `@app.get("/health")` | `main.py` | Same as router but on the app directly |

### `@lru_cache` — memoization

From `app/utils/config_utils.py`:

```python
from functools import lru_cache

@lru_cache
def get_config(key: str):
    config_value = get_all_configs().get(key, '').strip("'\"")
    return config_value
```

First call: reads the INI file, parses it, returns the value.
Every subsequent call with the same `key`: returns the cached result instantly.

Why it matters: `get_config("RAZORPAY_KEY_ID")` is called at module import time.
Without caching, it would re-parse the INI file every single time.

### Decorators with arguments

`@router.get("/plans", response_model=list[PlanResponse])` is a decorator *factory*.
`router.get("/plans", response_model=list[PlanResponse])` returns a decorator, and
that decorator wraps your function.

```python
# Step 1: router.get(...) returns a decorator function
decorator = router.get("/plans", response_model=list[PlanResponse])

# Step 2: that decorator wraps list_plans
list_plans = decorator(list_plans)
```

---

## Part E — Comprehensions

### List comprehension — transform a list in one line

```python
# From app/services/payment.py — filter active packages
def get_packages() -> list[dict]:
    return [p for p in DEFAULT_PACKAGES.values() if p["is_active"]]
```

Equivalent long form:

```python
def get_packages() -> list[dict]:
    result = []
    for p in DEFAULT_PACKAGES.values():
        if p["is_active"]:
            result.append(p)
    return result
```

### Nested comprehension — building response objects

From `app/routers/payment.py`:

```python
transactions=[
    CreditTransaction(
        transaction_id=t["id"],
        user_id=t["user_id"],
        amount=t["amount"],
        transaction_type=t["transaction_type"],
        reason=t["reason"],
        reference_id=t.get("reference_id"),
        created_at=str(t["created_at"]),
    )
    for t in txns
],
```

This turns a `list[dict]` from the DB into a `list[CreditTransaction]` of Pydantic
models. Each dict is unpacked into a model constructor.

### Dict comprehension

From `app/utils/config_utils.py`:

```python
parser_dict = {s.upper(): dict(parser.items(s)) for s in parser.sections()}
```

Turns INI sections into a dict of dicts: `{"COMMON": {...}, "DEV": {...}, "PROD": {...}}`.

### When NOT to use comprehensions

If the logic has side effects (logging, DB writes, exceptions) or is more than
2 conditions deep, use a regular loop. Readability > cleverness.

---

## Part F — String Formatting

### f-strings (what we use most)

```python
# From app/services/payment.py
receipt = f"usr_{user_id}_{body.package_id}"
url = f"{_litellm_base_url.rstrip('/')}/{_litellm_team_update_path.lstrip('/')}"
```

f-strings evaluate expressions inside `{}` at runtime. Any valid Python expression
works: function calls, arithmetic, method calls, ternaries.

### Loguru placeholders

Loguru uses `{}` as positional placeholders — NOT f-strings:

```python
# RIGHT — loguru handles the formatting (and it's lazy — skipped if log level is off)
logger.info("Webhook: credited {} credits for order {}", credits, order_id)

# WRONG — f-string evaluates even if info-level logging is disabled
logger.info(f"Webhook: credited {credits} credits for order {order_id}")
```

Why this matters: if you log at `INFO` level but production is set to `WARNING`,
the f-string version still does all the string formatting work for nothing.

### `.format()` — older style, rarely used

```python
"Hello {}".format(name)         # positional
"Hello {name}".format(name=x)   # named
```

We don't use this, but you'll see it in older Python code.

---

## Part G — Error Handling

### The hierarchy

```
BaseException
  └── Exception
        ├── ValueError     (bad input: "Plan not found", "Already refunded")
        ├── RuntimeError   (system failure: "Razorpay returned no ID")
        ├── TypeError      (wrong type passed)
        ├── KeyError       (missing dict key)
        └── ... hundreds more
```

### How we use it

**Raise specific exceptions in services:**

```python
# app/services/subscription.py
if not plan:
    raise ValueError("Plan not found or inactive")
```

**Catch and translate in routers:**

```python
# app/routers/subscription.py
try:
    result = sub_svc.create_subscription(user_id, body.plan_id)
except ValueError as exc:
    raise HTTPException(status_code=400, detail=str(exc))
except Exception:
    raise HTTPException(status_code=502, detail="Failed to create subscription")
```

Pattern: services raise Python exceptions, routers catch them and convert to HTTP errors.

**Re-raising:**

```python
# app/services/subscription.py — log, then let the caller handle it
except Exception as exc:
    logger.error("Razorpay subscription create failed for user {}: {}", user_id, exc)
    raise   # bare raise re-raises the same exception with original traceback
```

**String inspection for DB errors:**

```python
# app/services/subscription.py — _save_invoice
except Exception as exc:
    if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
        logger.info("Invoice insert skipped (duplicate payment_id)")
        return False
    raise   # not a duplicate? re-raise the unknown error
```

### Mistakes to avoid

```python
# BAD — catches everything, including KeyboardInterrupt
try:
    ...
except:
    pass

# BAD — catches too broadly, hides real bugs
try:
    result = complex_operation()
except Exception:
    return None   # What went wrong? Nobody knows.

# GOOD — catch specific exceptions
try:
    result = complex_operation()
except ValueError as exc:
    logger.warning("Bad input: {}", exc)
    return None
```

---

## Part H — Imports and Packages

### How Python finds modules

When you write `from app.services import payment`, Python:
1. Looks for a directory called `app/`
2. Inside it, looks for `services/`
3. Inside that, looks for `payment.py`
4. Each directory must have `__init__.py` (can be empty) to be a package

### Import styles we use

```python
# Import a module and alias it
from app.services import payment as pay_svc
from app.services import subscription as sub_svc

# Import specific names from a module
from app.models.payment import CreateOrderRequest, CreateOrderResponse

# Import from stdlib
from datetime import datetime, timezone
from typing import Optional, Any, Literal
from functools import lru_cache
import json
import uuid
import hmac
import hashlib

# Import a third-party library
import razorpay
import requests
from loguru import logger
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException
```

### Why aliasing matters

```python
# Without alias — ambiguous, which "payment"?
from app.services import payment
payment.process_payment_captured(...)

# With alias — immediately clear it's the service layer
from app.services import payment as pay_svc
pay_svc.process_payment_captured(...)
```

### Circular imports (the #1 import headache)

If `payment.py` imports from `subscription.py` AND `subscription.py` imports from
`payment.py`, Python will crash with `ImportError`.

How we handle it: `subscription.py` imports specific functions from `payment.py`:

```python
# app/services/subscription.py
from app.services.payment import add_credits, update_litellm_budget, rz_client
```

And `payment.py` imports `subscription` as a module (not specific functions):

```python
# app/routers/payment.py
from app.services import subscription as sub_svc
```

This works because by the time the router runs, both service modules are fully loaded.

---

## Part I — Standard Library Highlights

### `uuid` — generating unique IDs

```python
import uuid
internal_id = str(uuid.uuid4())   # "a7b3c9d1-e2f4-4a5b-8c6d-7e8f9a0b1c2d"
```

UUID v4 is random. The chance of collision is astronomically low — safe for primary keys.

### `hmac` + `hashlib` — cryptographic signatures

```python
import hmac
import hashlib

# Create an HMAC-SHA256 signature
message = f"{order_id}|{payment_id}"
expected = hmac.new(
    secret_key.encode(),     # key as bytes
    message.encode(),        # message as bytes
    hashlib.sha256,          # hash algorithm
).hexdigest()                # hex string output

# Constant-time comparison (prevents timing attacks)
hmac.compare_digest(expected, signature)
```

We use this for: Razorpay payment verification, webhook signature verification,
and admin key comparison.

### `json` — serialize/deserialize

```python
import json

# Python dict → JSON string (for DB storage)
json.dumps({"models": ["gpt-4"]})    # '{"models": ["gpt-4"]}'

# JSON string → Python dict (reading from DB)
json.loads('{"models": ["gpt-4"]}')  # {"models": ["gpt-4"]}
```

### `datetime` and `timezone` — timestamps

```python
from datetime import datetime, timezone

# Current UTC time as ISO string (what we store in the DB)
now = datetime.now(timezone.utc).isoformat()
# "2026-04-12T10:30:00+00:00"

# Convert Unix timestamp (from Razorpay) to ISO
ts = 1712923800
dt = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
```

Always use `timezone.utc`. Never use `datetime.now()` without a timezone — it
returns local time, which is different on every machine.

### `configparser` — INI file parsing

```python
from configparser import RawConfigParser

parser = RawConfigParser()
parser.optionxform = str   # preserve key case (default lowercases everything)
parser.read("app_config.ini")
```

### `functools.lru_cache` — memoization

```python
from functools import lru_cache

@lru_cache
def expensive_function(key: str):
    # This runs once per unique key, then returns cached result
    return compute_something(key)
```

---

## Part J — Common Mistakes (and how to spot them)

### 1. Mutable default arguments

```python
# BUG — the same list is shared across all calls!
def add_item(item, items=[]):
    items.append(item)
    return items

add_item("a")  # ["a"]
add_item("b")  # ["a", "b"]  ← "a" leaked from the previous call!

# FIX
def add_item(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items
```

### 2. Forgetting `timezone.utc`

```python
# BAD — returns local time (IST in India = UTC+5:30)
datetime.now()

# GOOD — always UTC
datetime.now(timezone.utc)
```

If your server is in India and your DB stores UTC, you'll be off by 5.5 hours.

### 3. Catching bare `Exception`

```python
# BAD — catches SystemExit, KeyboardInterrupt too
except:
    pass

# BAD — swallows the error silently
except Exception:
    return None

# GOOD — catch specific, log the rest
except ValueError as exc:
    handle_bad_input(exc)
except Exception as exc:
    logger.error("Unexpected: {}", exc)
    raise
```

### 4. String formatting in SQL

```python
# CRITICAL BUG — SQL injection vulnerability
sql = f"SELECT * FROM users WHERE id = {user_id}"

# SAFE — parameterized query
sql = "SELECT * FROM users WHERE id = :user_id"
execute_query_with_params(sql, {"user_id": user_id})
```

Our `update_litellm_budget` in `payment.py` actually has this bug — it uses
an f-string for a SQL query. Don't copy that pattern.

### 5. Not awaiting async functions

```python
# BUG — result is a coroutine object, not the actual user_id
user_id = get_user_id_from_request(request)

# FIX
user_id = await get_user_id_from_request(request)
```

Python won't crash — it'll just use the coroutine object as if it were the result,
which leads to bizarre bugs downstream.

---

## Quick Reference Table

| Pattern | Example from our code | File |
|---------|----------------------|------|
| Type hints | `-> Optional[dict]` | `services/payment.py` |
| Async route | `async def create_order(...)` | `routers/payment.py` |
| Context manager | `with engine.connect() as conn` | `utils/db_utils.py` |
| Decorator | `@router.post("/verify")` | `routers/payment.py` |
| List comprehension | `[p for p in PACKAGES.values() if p["is_active"]]` | `services/payment.py` |
| f-string | `f"usr_{user_id}_{body.package_id}"` | `routers/payment.py` |
| try/except/raise | `except ValueError as exc: raise HTTPException(...)` | `routers/subscription.py` |
| Module alias | `from app.services import payment as pay_svc` | `routers/payment.py` |
| UUID | `str(uuid.uuid4())` | `services/payment.py` |
| HMAC | `hmac.compare_digest(expected, signature)` | `services/payment.py` |
| lru_cache | `@lru_cache def get_config(key)` | `utils/config_utils.py` |
| Literal | `Literal["daily", "weekly", ...]` | `models/subscription.py` |
