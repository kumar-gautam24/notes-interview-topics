# 18 — Pydantic and Models (data validation you get for free)

> Pydantic is the library that validates every request and response in our API.
> This doc covers every Pydantic feature we use, with examples from our code.

---

## Part A — What Pydantic Does

Pydantic takes a Python class and turns it into a **validator + serializer**.

Without Pydantic, you'd write this:

```python
def create_plan(data: dict):
    if "name" not in data:
        raise ValueError("name is required")
    if not isinstance(data["name"], str):
        raise ValueError("name must be a string")
    if len(data["name"]) > 128:
        raise ValueError("name too long")
    if "amount_paise" not in data:
        raise ValueError("amount_paise is required")
    if not isinstance(data["amount_paise"], int):
        raise ValueError("amount_paise must be an integer")
    if data["amount_paise"] <= 0:
        raise ValueError("amount_paise must be positive")
    # ... 30 more lines of validation ...
```

With Pydantic:

```python
class CreatePlanRequest(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    amount_paise: int = Field(gt=0)
```

Same validation, declared in two lines. Pydantic generates all the error messages
automatically.

---

## Part B — BaseModel Basics

### Defining a model

```python
from pydantic import BaseModel

class CreditBalanceResponse(BaseModel):
    user_id: str
    balance: int
```

This class:
- Validates that `user_id` is a string and `balance` is an integer
- Converts compatible types (e.g. `"123"` won't become an int — Pydantic v2 is strict about this)
- Generates a JSON schema (used by Swagger docs)

### Creating instances

Three ways we create Pydantic models in our code:

**1. From explicit arguments:**

```python
return CreditBalanceResponse(user_id=user_id, balance=balance)
```

**2. From a dict using `**` unpacking:**

```python
# row is a dict from the DB: {"id": "abc", "razorpay_plan_id": "plan_xxx", ...}
return PlanResponse(**row)
```

This is the same as:
```python
return PlanResponse(
    id=row["id"],
    razorpay_plan_id=row["razorpay_plan_id"],
    name=row["name"],
    # ... every key becomes a keyword argument
)
```

**3. FastAPI creates it from the request body:**

```python
async def subscribe(request: Request, body: SubscribeRequest):
    # FastAPI parsed the JSON body and created body as a SubscribeRequest
    plan_id = body.plan_id
```

### Accessing fields

```python
plan = CreatePlanRequest(name="Pro Monthly", amount_paise=39900)
print(plan.name)            # "Pro Monthly"
print(plan.amount_paise)    # 39900
```

---

## Part C — Field (constraints and metadata)

`Field` lets you add validation rules and documentation to each field.

### Syntax

```python
from pydantic import Field

class CreatePlanRequest(BaseModel):
    name: str = Field(
        min_length=1,
        max_length=128,
        description="Plan display name, e.g. 'Pro Monthly'",
    )
    amount_paise: int = Field(
        gt=0,
        description="Price per cycle in PAISE (₹399 = 39900). Not rupees!",
    )
    interval: int = Field(default=1, ge=1, description="Every N periods")
    trial_days: int = Field(default=0, ge=0)
    description: Optional[str] = Field(default=None, max_length=512)
```

### Constraint reference

| Constraint | Meaning | Used for |
|-----------|---------|----------|
| `gt=0` | Greater than 0 | `amount_paise` — price must be positive |
| `ge=0` | Greater than or equal to 0 | `trial_days` — can be zero |
| `ge=1` | Greater than or equal to 1 | `interval` — at least 1 |
| `le=200` | Less than or equal to 200 | `limit` query param — cap pagination |
| `min_length=1` | At least 1 character | `name` — can't be empty string |
| `max_length=128` | At most 128 characters | `name` — DB column limit |
| `max_length=512` | At most 512 characters | `description` |
| `default=0` | Default value if not provided | `trial_days` |
| `default=None` | Defaults to None | `description`, `features` |
| `description="..."` | Appears in Swagger docs | Every field |

### What happens when validation fails

Client sends:
```json
{ "name": "", "amount_paise": -100 }
```

FastAPI returns `422 Unprocessable Entity`:
```json
{
  "detail": [
    {
      "loc": ["body", "name"],
      "msg": "String should have at least 1 character",
      "type": "string_too_short"
    },
    {
      "loc": ["body", "amount_paise"],
      "msg": "Input should be greater than 0",
      "type": "greater_than"
    }
  ]
}
```

You get field-level error messages for free.

---

## Part D — Optional and Defaults

### The four patterns

```python
# 1. Required, no default
name: str
# Client MUST provide this. Missing → 422 error.

# 2. Required with a default
currency: str = "INR"
# If client doesn't send it, defaults to "INR". If they send "USD", uses "USD".

# 3. Optional, defaults to None
description: Optional[str] = None
# Client can omit it (becomes None) or send a string.

# 4. Optional with Field
features: Optional[dict[str, Any]] = Field(
    default=None,
    description="JSONB features object",
)
# Same as #3 but with documentation and potential constraints.
```

### When to use which

| Need | Pattern |
|------|---------|
| Always required, no sensible default | `field: str` |
| Usually the same value | `field: str = "default"` |
| Sometimes present, sometimes absent | `field: Optional[str] = None` |
| The field is complex and needs docs | `field: type = Field(default=..., description=...)` |

### Gotcha: `Optional` without a default

```python
# This is STILL required — Optional only means "can be None", not "can be missing"
notes: Optional[dict]

# You almost always want:
notes: Optional[dict] = None
```

In Pydantic v2, `Optional[dict]` without a default means the client must explicitly
send `"notes": null`. That's rarely what you want.

---

## Part E — Literal (constrained strings)

### The problem

```python
period: str = "monthly"
# What stops someone from sending period = "banana"? Nothing.
```

### The solution

```python
from typing import Literal

period: Literal["daily", "weekly", "monthly", "quarterly", "yearly"] = Field(
    default="monthly",
    description="Razorpay billing period",
)
```

Now if someone sends `"banana"`, Pydantic rejects it:

```json
{
  "detail": [
    {
      "loc": ["body", "period"],
      "msg": "Input should be 'daily', 'weekly', 'monthly', 'quarterly' or 'yearly'",
      "type": "literal_error"
    }
  ]
}
```

### Literal vs Enum

Both constrain values. Use `Literal` for simple string constraints (like `period`).
Use `Enum` when you need to reference the values elsewhere in code.

---

## Part F — Enum (named constants)

### Definition

```python
from enum import Enum

class TransactionType(str, Enum):
    CREDIT = "credit"
    DEBIT = "debit"
    REFUND = "refund"

class OrderStatus(str, Enum):
    CREATED = "created"
    PAID = "paid"
    FAILED = "failed"
    REFUNDED = "refunded"
```

### Why `str, Enum` (the str mixin)?

Without `str`:
```python
class Color(Enum):
    RED = "red"

json.dumps({"color": Color.RED})
# TypeError: Object of type Color is not JSON serializable
```

With `str`:
```python
class Color(str, Enum):
    RED = "red"

json.dumps({"color": Color.RED})
# '{"color": "red"}'  ← works!
```

The `str` mixin makes the enum value behave like a string in JSON serialization.
Pydantic and FastAPI need this to include enum values in responses.

### Using enums in models

```python
class PaymentRecord(BaseModel):
    status: OrderStatus      # must be one of "created", "paid", "failed", "refunded"
    ...

class CreditTransaction(BaseModel):
    transaction_type: TransactionType  # "credit", "debit", or "refund"
    ...
```

### Using enums in code

```python
# Reference by name
if order["status"] == OrderStatus.PAID:
    ...

# Or by value (since str mixin)
if order["status"] == "paid":
    ...
```

Both work because `OrderStatus.PAID == "paid"` is `True` (thanks to the `str` mixin).

---

## Part G — Nested Models

### What they are

A model field whose type is another model:

```python
class SubscriptionInvoice(BaseModel):
    id: str
    razorpay_invoice_id: Optional[str] = None
    amount: int
    status: str
    cycle_number: int
    created_at: str

class InvoiceHistoryResponse(BaseModel):
    subscription_id: str
    invoices: list[SubscriptionInvoice]   # ← nested list of models
    total: int
```

### How we construct them

```python
return InvoiceHistoryResponse(
    subscription_id=sub["id"],
    invoices=[
        SubscriptionInvoice(
            id=inv["id"],
            razorpay_invoice_id=inv.get("razorpay_invoice_id"),
            amount=inv["amount"],
            status=inv["status"],
            cycle_number=inv["cycle_number"],
            created_at=str(inv["created_at"]),
        )
        for inv in invoices    # list comprehension builds the nested list
    ],
    total=total,
)
```

### What the JSON looks like

```json
{
  "subscription_id": "abc-123",
  "invoices": [
    {
      "id": "inv-1",
      "razorpay_invoice_id": "inv_xxx",
      "amount": 39900,
      "status": "paid",
      "cycle_number": 1,
      "created_at": "2026-04-01T00:00:00"
    },
    {
      "id": "inv-2",
      "razorpay_invoice_id": "inv_yyy",
      "amount": 39900,
      "status": "paid",
      "cycle_number": 2,
      "created_at": "2026-05-01T00:00:00"
    }
  ],
  "total": 2
}
```

Swagger UI shows this entire nested structure, including the schema for each invoice.

---

## Part H — Model Construction Patterns

### Pattern 1: Explicit construction (most common)

```python
return CreateOrderResponse(
    razorpay_order_id=rz_order["id"],
    amount=pkg["price_paise"],
    currency=pkg["currency"],
    package_id=body.package_id,
    credits=pkg["credits"],
    status="created",
)
```

When to use: fields come from different sources (body, DB, computed values).

### Pattern 2: Dict unpacking (`**row`)

```python
return PlanResponse(**result)
```

When to use: the dict keys match the model fields exactly. Our DB queries use
`SELECT *`, so the column names must match the model field names.

Danger: if the dict has extra keys that aren't in the model, Pydantic v2 ignores
them by default. If it has missing required keys, you get a validation error.

### Pattern 3: Conditional fields

```python
return SubscriptionStatusResponse(
    user_id=user_id,
    plan_name=plan["name"] if plan else "Unknown",
    status=sub["status"],
    current_start=str(sub["current_start"]) if sub.get("current_start") else None,
    current_end=str(sub["current_end"]) if sub.get("current_end") else None,
    paid_count=sub["paid_count"],
    credits_per_cycle=plan["credits_per_cycle"] if plan else 0,
)
```

When to use: some values might be `None` or need transformation.

---

## Part I — Serialization

### How FastAPI uses models for responses

When your route returns a Pydantic model:

1. FastAPI calls `model.model_dump()` to convert it to a dict
2. Filters the dict to only include fields defined in `response_model`
3. Converts to JSON and sends the response

### Manual serialization (when you need it)

```python
plan = PlanResponse(id="abc", name="Pro", ...)

# To a dict
plan.model_dump()
# {"id": "abc", "name": "Pro", ...}

# To a JSON string
plan.model_dump_json()
# '{"id":"abc","name":"Pro",...}'

# Exclude None values
plan.model_dump(exclude_none=True)
# Only includes fields that aren't None
```

### When FastAPI returns dicts vs models

```python
# Returns a dict — FastAPI validates it against response_model
@router.get("/plans", response_model=list[PlanResponse])
async def list_plans():
    return sub_svc.list_plans()  # returns list[dict]

# Returns a model — FastAPI validates it too
@router.post("/plans", response_model=PlanResponse)
async def create_plan(body: CreatePlanRequest):
    ...
    return PlanResponse(**result)  # returns a PlanResponse instance
```

Both work. FastAPI handles dict-to-model conversion automatically when you have
`response_model` set.

---

## Part J — Our Model Organization

### File structure

```
app/models/
├── payment.py        # Enums, packages, orders, credits, refunds, transactions
└── subscription.py   # Plans, subscribe, status, cancel, invoices
```

### Naming conventions

| Suffix | Purpose | Example |
|--------|---------|---------|
| `Request` | Incoming data from client | `CreatePlanRequest`, `SubscribeRequest` |
| `Response` | Outgoing data to client | `PlanResponse`, `SubscribeResponse` |
| None | Shared/nested models | `CreditPackage`, `SubscriptionInvoice` |

### The full model map

```
CreateOrderRequest      → POST /payments/orders
CreateOrderResponse     ← POST /payments/orders

VerifyPaymentRequest    → POST /payments/verify
VerifyPaymentResponse   ← POST /payments/verify

RefundRequest           → POST /payments/refund
RefundResponse          ← POST /payments/refund

CreditBalanceResponse   ← GET  /payments/credits
                        ← POST /payments/credits/add

DeductCreditsRequest    → POST /payments/credits/deduct
DeductCreditsResponse   ← POST /payments/credits/deduct

AddCreditsRequest       → POST /payments/credits/add

CreditTransaction       (nested in TransactionHistoryResponse)
TransactionHistoryResponse ← GET /payments/transactions

PaymentRecord           (nested in PaymentHistoryResponse)
PaymentHistoryResponse  ← GET /payments/history

CreditPackage           ← GET /payments/packages

CreatePlanRequest       → POST /subscriptions/plans
PlanResponse            ← GET  /subscriptions/plans
                        ← POST /subscriptions/plans

SubscribeRequest        → POST /subscriptions/subscribe
SubscribeResponse       ← POST /subscriptions/subscribe

SubscriptionStatusResponse ← GET /subscriptions/status

CancelSubscriptionRequest → POST /subscriptions/cancel
CancelSubscriptionResponse ← POST /subscriptions/cancel

SubscriptionInvoice     (nested in InvoiceHistoryResponse)
InvoiceHistoryResponse  ← GET /subscriptions/invoices
```

---

## Part K — Common Mistakes

### 1. DB column names don't match model fields

```python
# DB returns: {"razorpay_plan_id": "plan_xxx"}
# Model expects:
class PlanResponse(BaseModel):
    razorpay_plan_id: str   # must match exactly
```

If the DB column is `rz_plan_id` but the model field is `razorpay_plan_id`,
`PlanResponse(**row)` will fail with a missing field error.

Fix: either rename the model field or use SQL aliases: `SELECT rz_plan_id AS razorpay_plan_id`.

### 2. Forgetting `response_model`

```python
# Without response_model, FastAPI returns whatever you return — no validation
@router.get("/credits")
async def get_credits(request: Request):
    return {"user_id": uid, "balance": 100, "internal_field": "leaked!"}
```

Always set `response_model` to prevent accidental data exposure.

### 3. `Optional[X]` without `= None`

```python
# WRONG — field is required, but can be None (confusing)
class Plan(BaseModel):
    description: Optional[str]
    # Client must send: {"description": null}  or  {"description": "text"}
    # Client cannot omit it!

# RIGHT — field is optional (can be omitted)
class Plan(BaseModel):
    description: Optional[str] = None
```

### 4. Using dict when you should use a model

```python
# BAD — no validation, no docs, no type safety
@router.post("/plans")
async def create_plan(body: dict):
    name = body.get("name")  # might be None, might be an int, who knows?

# GOOD
@router.post("/plans")
async def create_plan(body: CreatePlanRequest):
    name = body.name  # guaranteed to be a valid string
```

### 5. Returning raw DB rows without a model

```python
# Risky — might expose internal columns (password hashes, internal IDs)
return sub_svc.list_plans()

# Safe — response_model filters to only declared fields
@router.get("/plans", response_model=list[PlanResponse])
async def list_plans():
    return sub_svc.list_plans()  # extra columns in the dict are stripped out
```
