# 06 — Adding New Features

This is your go-to checklist when you get a feature assigned. Follow the steps in order.

---

## Scenario 1: Add a new API endpoint (no new table)

**Example:** "Add an endpoint to check if a user has ever purchased."

### Step 1: Define the response model

Open `app/models/payment.py` and add a Pydantic model:

```python
class HasPurchasedResponse(BaseModel):
    user_id: str
    has_purchased: bool
    total_orders: int
```

### Step 2: Write the service function

Open `app/services/payment.py` and add the business logic:

```python
def has_user_purchased(user_id: str) -> dict:
    sql = """
        SELECT COUNT(*) as cnt FROM razorpay_orders
        WHERE user_id = :user_id AND status = 'paid'
    """
    rows = execute_query_with_params(sql, {"user_id": user_id}, to_dict=True)
    count = rows[0]["cnt"] if rows else 0
    return {"has_purchased": count > 0, "total_orders": count}
```

### Step 3: Add the route

Open `app/routers/payment.py` and add:

```python
@router.get("/has-purchased", response_model=HasPurchasedResponse)
async def check_has_purchased(request: Request):
    user_id = await get_user_id_from_request(request)
    result = pay_svc.has_user_purchased(user_id)
    return HasPurchasedResponse(
        user_id=user_id,
        has_purchased=result["has_purchased"],
        total_orders=result["total_orders"],
    )
```

### Step 4: Test

1. Run the app: `uvicorn app.main:app --reload --port 8002`
2. Open http://localhost:8002/docs
3. Find your new endpoint in Swagger
4. Click "Try it out", add the `Authorization` header, execute
5. Check the response

### The file order matters

Always: **Models → Service → Router**. This is because:
- Router imports from models (for type hints) and service (to call logic)
- Service imports from db_utils (to run queries)
- Models don't import from anything in this project

---

## Scenario 2: Add a new database table

**Example:** "Add a promo_codes table."

### Step 1: Write the migration SQL

Create `app/migrations/002_promo_codes.sql`:

```sql
BEGIN;

CREATE TABLE IF NOT EXISTS promo_codes (
    id          VARCHAR(36)  PRIMARY KEY,
    code        VARCHAR(64)  UNIQUE NOT NULL,
    credits     INTEGER      NOT NULL,
    max_uses    INTEGER      NOT NULL DEFAULT 1,
    used_count  INTEGER      NOT NULL DEFAULT 0,
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    expires_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_promo_codes_code
    ON promo_codes (code) WHERE is_active = true;

COMMIT;
```

### Step 2: Apply the migration

**Ask your team** how to apply it. Typically:
```bash
# Connect to DEV DB
psql "postgresql://USER:PASS@HOST:5432/<DB_NAME>"

# Run the migration
\i app/migrations/002_promo_codes.sql

# Verify
\dt promo_codes
\d promo_codes
```

### Step 3: Write service functions

In `app/services/payment.py` (or a new service file):

```python
def validate_promo_code(code: str) -> Optional[dict]:
    sql = """
        SELECT * FROM promo_codes
        WHERE code = :code AND is_active = true
          AND (expires_at IS NULL OR expires_at > :now)
          AND used_count < max_uses
    """
    rows = execute_query_with_params(sql, {
        "code": code,
        "now": datetime.now(timezone.utc).isoformat(),
    }, to_dict=True)
    return rows[0] if rows else None


def redeem_promo_code(code: str, user_id: str) -> int:
    promo = validate_promo_code(code)
    if not promo:
        raise ValueError("Invalid or expired promo code")

    # Increment usage count
    execute_query_with_params(
        "UPDATE promo_codes SET used_count = used_count + 1, updated_at = :now WHERE code = :code",
        {"code": code, "now": datetime.now(timezone.utc).isoformat()},
    )

    # Add credits to user
    new_balance = add_credits(user_id, promo["credits"], reason="promo", reference_id=code)
    return new_balance
```

### Step 4: Add models and routes

Follow the same pattern as Scenario 1.

---

## Scenario 3: Add a completely new router (new domain)

**Example:** "Add subscription management endpoints."

### Step 1: Create the model file

`app/models/subscription.py`:
```python
from pydantic import BaseModel

class SubscribeRequest(BaseModel):
    plan_id: str

class SubscriptionStatusResponse(BaseModel):
    user_id: str
    plan_id: str
    status: str
    # ... more fields
```

### Step 2: Create the service file

`app/services/subscription.py`:
```python
from app.utils.db_utils import execute_query_with_params

def create_subscription(user_id: str, plan_id: str) -> dict:
    # Business logic here
    pass

def get_subscription_status(user_id: str) -> dict:
    # Query DB here
    pass
```

### Step 3: Create the router file

`app/routers/subscription.py`:
```python
from fastapi import APIRouter, Request
from app.models.subscription import SubscribeRequest, SubscriptionStatusResponse
from app.services import subscription as sub_svc

router = APIRouter()

@router.post("/subscribe")
async def subscribe(request: Request, body: SubscribeRequest):
    # Auth + call service
    pass

@router.get("/status", response_model=SubscriptionStatusResponse)
async def get_status(request: Request):
    # Auth + call service
    pass
```

### Step 4: Mount in main.py

Open `app/main.py` and add:
```python
from app.routers import subscription as subscription_router

app.include_router(
    subscription_router.router,
    prefix="/subscriptions",
    tags=["Subscriptions"],
)
```

Now all routes in the subscription router are available under `/subscriptions/...`.

---

## Scenario 4: Add a new config key

### Step 1: Add to INI file

Open `app/config/app_config.ini`:
```ini
[DEV]
# ... existing keys ...
NEW_SERVICE_URL=https://dev-api.example.com

[PROD]
# ... existing keys ...
NEW_SERVICE_URL=https://api.example.com
```

### Step 2: Use in code

```python
from app.utils.config_utils import get_config

SERVICE_URL = get_config("NEW_SERVICE_URL")
```

---

## Checklist before creating a pull request

1. **Code:**
   - [ ] Models defined with proper types and Field descriptions
   - [ ] Service function handles errors (try/except or validation)
   - [ ] Router returns proper HTTP status codes (404, 400, 401, etc.)
   - [ ] No hardcoded secrets or credentials in code

2. **Database:**
   - [ ] Migration SQL file created with `BEGIN/COMMIT`
   - [ ] Indexes added for columns used in WHERE clauses
   - [ ] Parameterized queries (no f-strings in SQL)

3. **Testing:**
   - [ ] Tested via Swagger `/docs`
   - [ ] Tested error cases (missing auth, invalid input, not found)

4. **Config:**
   - [ ] New config keys added to both DEV and PROD sections
   - [ ] No new secrets accidentally committed

5. **Git:**
   - [ ] Small, focused commits with clear messages
   - [ ] Branch naming follows team convention
   - [ ] PR description explains what and why

---

## Next doc

→ [07 - Debugging Guide](./07-debugging-guide.md) — how to fix things when they break
