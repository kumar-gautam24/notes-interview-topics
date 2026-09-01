# 09 — Subscription Module: Step-by-Step Build Guide

This is a hands-on build guide. It assumes you have already read [08 — Razorpay Subscriptions](./08-razorpay-subscriptions.md) and understand what plans, subscriptions, invoices, mandates, and webhooks are. If you haven't, stop and read that first.

Here, you will create every file, run every migration, wire every webhook, and test the full flow — from "user clicks Subscribe" to "credits land in their account every month."

---

## Part A — Before you start

### Prerequisites checklist

| # | Item | How to verify |
|---|------|---------------|
| 1 | Read doc 08 completely | You can explain what `subscription.charged` does |
| 2 | Local dev running | `bash run.sh` starts the FastAPI server on port 8003 |
| 3 | PostgreSQL accessible | `psql -h <DB_HOST> -U <DB_USER> -d <DB_NAME>` connects |
| 4 | Razorpay **test mode** keys set | `RAZORPAY_KEY_ID` in `app/config/app_config.ini` starts with `rzp_test_` |
| 5 | At least one Razorpay Plan created | You have a `plan_xxx` ID (see Part C if not) |
| 6 | ngrok installed | `ngrok http 8003` opens a public tunnel |
| 7 | curl or Postman ready | For manual endpoint testing |
| 8 | A DB client | psql, DBeaver, or pgAdmin — anything that runs SQL |

### Folder structure after this guide

When you finish, the project will look like this (new files marked with `+`):

```
app/
├── config/
│   └── app_config.ini          (modified — new plan ID key)
├── migrations/
│   ├── 001_payment_tables.sql
│   └── 002_subscription_tables.sql   (+)
├── models/
│   ├── payment.py
│   └── subscription.py               (+)
├── routers/
│   ├── payment.py              (modified — new webhook branches)
│   └── subscription.py               (+)
├── services/
│   ├── payment.py
│   └── subscription.py               (+)
├── main.py                     (modified — new router mount)
└── ...
```

---

## Part B — Step 1: Database migration

### Create the migration file

Create `app/migrations/002_subscription_tables.sql`:

```sql
-- Migration: 002_subscription_tables
-- Creates the tables for the subscription system.
-- Run this against the <DB_NAME> PostgreSQL database.
-- Depends on: 001_payment_tables.sql (api_user_credits must exist)

BEGIN;

-- Plan templates (Pro Monthly, Enterprise Yearly, etc.)
CREATE TABLE IF NOT EXISTS subscription_plans (
    id               VARCHAR(36)  PRIMARY KEY,
    razorpay_plan_id VARCHAR(64)  UNIQUE NOT NULL,
    name             VARCHAR(128) NOT NULL,
    credits_per_cycle INTEGER     NOT NULL,
    price_paise      INTEGER      NOT NULL,
    currency         VARCHAR(3)   NOT NULL DEFAULT 'INR',
    period           VARCHAR(16)  NOT NULL DEFAULT 'monthly',
    interval_count   INTEGER      NOT NULL DEFAULT 1,
    trial_days       INTEGER      NOT NULL DEFAULT 0,
    is_active        BOOLEAN      NOT NULL DEFAULT true,
    features         JSONB,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- One row per user-subscription relationship
CREATE TABLE IF NOT EXISTS user_subscriptions (
    id                       VARCHAR(36)  PRIMARY KEY,
    user_id                  VARCHAR(128) NOT NULL,
    plan_id                  VARCHAR(36)  NOT NULL REFERENCES subscription_plans(id),
    razorpay_subscription_id VARCHAR(64)  UNIQUE NOT NULL,
    status                   VARCHAR(24)  NOT NULL DEFAULT 'created',
    current_start            TIMESTAMPTZ,
    current_end              TIMESTAMPTZ,
    trial_end                TIMESTAMPTZ,
    paid_count               INTEGER      NOT NULL DEFAULT 0,
    cancel_at_cycle_end      BOOLEAN      NOT NULL DEFAULT false,
    mandate_type             VARCHAR(16),
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_subs_user
    ON user_subscriptions (user_id, status);

CREATE INDEX IF NOT EXISTS idx_user_subs_rz
    ON user_subscriptions (razorpay_subscription_id);

-- One row per billing cycle charge
CREATE TABLE IF NOT EXISTS subscription_invoices (
    id                   VARCHAR(36)  PRIMARY KEY,
    subscription_id      VARCHAR(36)  NOT NULL REFERENCES user_subscriptions(id),
    razorpay_invoice_id  VARCHAR(64),
    razorpay_payment_id  VARCHAR(64),
    amount               INTEGER      NOT NULL,
    status               VARCHAR(16)  NOT NULL DEFAULT 'pending',
    cycle_number         INTEGER      NOT NULL,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sub_invoices_sub
    ON subscription_invoices (subscription_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sub_invoices_payment
    ON subscription_invoices (razorpay_payment_id)
    WHERE razorpay_payment_id IS NOT NULL;

COMMIT;
```

The last index (`idx_sub_invoices_payment`) is a **partial unique index**. It prevents the same Razorpay payment from being recorded twice, which is the foundation of webhook idempotency for subscriptions.

### Run the migration

```bash
# DEV
psql -h <DB_HOST> -U <DB_USER> -d <DB_NAME> -f app/migrations/002_subscription_tables.sql

# Or if you're inside the K8s pod
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f app/migrations/002_subscription_tables.sql
```

### Verify

```sql
-- Should return 3 rows
SELECT table_name
FROM information_schema.tables
WHERE table_name IN ('subscription_plans', 'user_subscriptions', 'subscription_invoices');

-- Check columns
\d subscription_plans
\d user_subscriptions
\d subscription_invoices
```

### Rollback (if you need to undo)

```sql
BEGIN;
DROP TABLE IF EXISTS subscription_invoices;
DROP TABLE IF EXISTS user_subscriptions;
DROP TABLE IF EXISTS subscription_plans;
COMMIT;
```

Order matters — drop child tables before parent tables (foreign key constraints).

---

## Part C — Step 2: Create a Razorpay Plan (three methods)

Before any user can subscribe, a **Razorpay Plan** must exist. A plan is a template ("Pro Monthly — ₹399/month"). You create it **once**, then every subscriber is linked to it.

There are three ways to create a plan. Pick **any one** — the result is the same: a `plan_xxx` ID on Razorpay that you then register in your database. All three are documented fully below so you can choose what fits your workflow.

```
                         ┌─────────────────────────────┐
 Method 1: Dashboard ───→│                             │
                         │  Razorpay creates plan_xxx  │
 Method 2: Python    ───→│                             │──→ You must also seed
                         │  (lives on Razorpay's side) │    subscription_plans in
 Method 3: API       ───→│                             │    your Postgres (Part D)
                         └─────────────────────────────┘
                                                            (Method 3 does this
                                                             automatically)
```

---

### C.1 — Method 1: Razorpay Dashboard (no code)

Use this if you prefer a visual interface and are doing a one-time setup.

**Step 1: Log in and check your mode**

1. Go to https://dashboard.razorpay.com and log in.
2. Look at the **top-left** of the Dashboard. You will see either **Test Mode** or **Live Mode**.
   - For development: must be **Test Mode** (matches your `rzp_test_...` key in config).
   - For production: must be **Live Mode** (matches your `rzp_live_...` key).
   - If it's wrong, click the toggle to switch.

**Step 2: Navigate to Plans**

3. In the left sidebar, click **Payment Products**.
4. Under Payment Products, click **Subscriptions**.
5. Click the **Plans** tab at the top.
6. Click the **+ Create Plan** button.

**Step 3: Fill in the plan details**

7. Fill in the form:

| Field | What to enter | Notes |
|-------|---------------|-------|
| **Plan Name** | `Pro Monthly` | This is what the user sees on checkout |
| **Amount** | `399` | **In rupees, not paise!** The Dashboard UI expects the main currency unit. The API expects paise (39900). This 100x difference is the #1 mistake. |
| **Currency** | `INR` | Usually pre-selected |
| **Billing Period** | `Monthly` | Options: Daily, Weekly, Monthly, Quarterly, Yearly |
| **Billing Interval** | `1` | "Every 1 month" — set to 3 for quarterly on a monthly period, etc. |
| **Description** | `1200 credits per month` | Optional but helpful |

8. Click **Create Plan**.

**Step 4: Copy the Plan ID**

9. After creation, the plan detail page opens. The Plan ID is shown at the top — it looks like `plan_PROMonthly123` or similar (always starts with `plan_`).
10. **Copy this ID.** You need it for the next steps.

**Step 5: What you still need to do**

The Dashboard only creates the plan **on Razorpay's side**. Your application database does not know about it yet. You must:

- **Seed `subscription_plans`** in your Postgres database (see Part D below).
- **Add the plan ID to `app_config.ini`** (see Part D below).

Without this, `POST /subscriptions/subscribe` will return "Plan not found."

**Verification:**

The plan should appear in your Dashboard under Payment Products → Subscriptions → Plans.

**Troubleshooting:**

| Problem | Cause | Fix |
|---------|-------|-----|
| Plan not visible | You created it in Live mode but are looking at Test mode (or vice versa) | Toggle mode in top-left |
| Plan shows different amount | You entered paise in the Dashboard (e.g. 39900 instead of 399) | Delete plan, create again with correct amount |

---

### C.2 — Method 2: Python REPL or script

Use this if you prefer the command line and want programmatic control.

**Step 1: Open a terminal in the project directory**

```bash
cd /path/to/<payment-svc>
```

If you use a virtual environment (you should), activate it:

```bash
source venv/bin/activate
# or on some setups:
source .venv/bin/activate
```

**Step 2: Confirm `razorpay` is installed**

```bash
pip show razorpay
```

If it says "not found", install it:

```bash
pip install razorpay
```

(It is already in `requirements.txt`, so if you ran `pip install -r requirements.txt` earlier, you have it.)

**Step 3: Run the plan creation**

You have two options for providing Razorpay credentials:

**Option A — Standalone (paste keys directly):**

Open a Python REPL:

```bash
python3
```

Then paste:

```python
import razorpay

# Replace with YOUR keys from app/config/app_config.ini → [DEV] section
# NEVER commit real keys to code or docs
client = razorpay.Client(auth=("rzp_test_YOUR_KEY_ID", "YOUR_KEY_SECRET"))

plan = client.plan.create({
    "period": "monthly",
    "interval": 1,
    "item": {
        "name": "Pro Monthly",
        "amount": 39900,        # ₹399 in PAISE (API uses paise, not rupees!)
        "currency": "INR",
        "description": "1200 credits per month"
    }
})

print(plan["id"])
```

Where to find your keys: open `app/config/app_config.ini`, look under `[DEV]` for `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET`.

**Option B — Using app config (no copy-pasting keys):**

This reads keys from your config file so you never type them:

```bash
python3
```

```python
from app.utils.config_utils import get_config
import razorpay

client = razorpay.Client(auth=(
    get_config("RAZORPAY_KEY_ID"),
    get_config("RAZORPAY_KEY_SECRET"),
))

plan = client.plan.create({
    "period": "monthly",
    "interval": 1,
    "item": {
        "name": "Pro Monthly",
        "amount": 39900,
        "currency": "INR",
        "description": "1200 credits per month"
    }
})

print(plan["id"])
```

This only works if you run Python from the **project root** (`<payment-svc>/`) so that `from app.utils...` resolves.

**Step 4: Expected output**

```
plan_PROMonthly123
```

(Your actual ID will be different.) **Copy this ID.**

**Step 5: Exit the REPL**

```python
exit()
```

**Step 6: What you still need to do**

Same as Method 1 — this only creates on Razorpay. You must:

- **Seed `subscription_plans`** in Postgres (Part D).
- **Add plan ID to config** (Part D).

**Troubleshooting:**

| Problem | Cause | Fix |
|---------|-------|-----|
| `razorpay.errors.BadRequestError` | Invalid period, missing fields, or keys from wrong mode | Check `period` is one of: daily, weekly, monthly, quarterly, yearly. Check keys match your Dashboard mode. |
| `ModuleNotFoundError: No module named 'razorpay'` | Package not installed in current venv | `pip install razorpay` |
| `ModuleNotFoundError: No module named 'app'` | Not running from project root | `cd /path/to/<payment-svc>` and try again |
| `razorpay.errors.SignatureVerificationError` or auth error | Wrong key ID or secret | Re-check `app_config.ini` values carefully |

---

### C.3 — Method 3: API endpoint (POST /subscriptions/plans)

This is the **recommended** approach for a real system. You build a protected API endpoint that creates the plan on Razorpay **and** inserts it into your database in one call. No manual SQL seeding needed.

This requires writing code first. Follow the steps below — each one gives you the complete file to create or modify.

#### C.3.1 — Add the admin key to config

Before building the endpoint, set up the admin key that protects it. Open `app/config/app_config.ini`.

Generate a strong random key:

```bash
openssl rand -hex 32
```

This prints a 64-character hex string like `[REDACTED]...`. Copy it.

Add this line to **both** `[DEV]` and `[PROD]` sections:

```ini
SUBSCRIPTION_ADMIN_KEY=paste_your_generated_key_here
```

Use a **different key** for PROD than DEV. Never share the production key in chat or commits.

See the **Admin Key Runbook** section later in this doc for the full lifecycle (testing, Swagger, rotation, etc.).

#### C.3.2 — Add `CreatePlanRequest` to the model file

Open `app/models/subscription.py` and add these classes (keep any existing classes like `SubscribeRequest`, etc.):

```python
from typing import Any, Optional
from pydantic import BaseModel, Field


class PlanResponse(BaseModel):
    id: str
    razorpay_plan_id: str
    name: str
    credits_per_cycle: int
    price_paise: int
    currency: str
    period: str
    interval_count: int
    trial_days: int
    is_active: bool
    features: Optional[dict[str, Any]] = None


class CreatePlanRequest(BaseModel):
    """Body for POST /subscriptions/plans — creates a Razorpay plan + DB row."""

    name: str = Field(
        min_length=1, max_length=128,
        description="Plan display name, e.g. 'Pro Monthly'",
    )
    amount_paise: int = Field(
        gt=0,
        description="Price per cycle in PAISE (₹399 = 39900). Not rupees!",
    )
    currency: str = Field(default="INR", min_length=3, max_length=3)
    period: str = Field(
        default="monthly",
        description="Razorpay period: daily, weekly, monthly, quarterly, yearly",
    )
    interval: int = Field(default=1, ge=1, description="Every N periods")
    credits_per_cycle: int = Field(
        gt=0,
        description="Credits granted each successful charge",
    )
    trial_days: int = Field(default=0, ge=0)
    description: Optional[str] = Field(default=None, max_length=512)
    internal_plan_id: Optional[str] = Field(
        default=None,
        description="Custom subscription_plans.id; UUID generated if omitted",
    )
    features: Optional[dict[str, Any]] = Field(
        default=None,
        description="JSONB features object, e.g. {\"models\": [\"gpt-4\"]}",
    )
```

#### C.3.3 — Add `create_plan_and_persist` to the service file

Open (or create) `app/services/subscription.py` and add:

```python
import json
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from loguru import logger

from app.services.payment import rz_client
from app.utils.db_utils import execute_query_with_params


def list_plans(active_only: bool = True) -> list[dict]:
    """Return subscription plans from the DB."""
    if active_only:
        sql = "SELECT * FROM subscription_plans WHERE is_active = true ORDER BY price_paise"
    else:
        sql = "SELECT * FROM subscription_plans ORDER BY price_paise"
    rows = execute_query_with_params(sql, {}, to_dict=True)
    for row in rows:
        _normalize_features(row)
    return rows


def create_plan_and_persist(
    name: str,
    amount_paise: int,
    currency: str,
    period: str,
    interval: int,
    credits_per_cycle: int,
    trial_days: int = 0,
    description: Optional[str] = None,
    internal_plan_id: Optional[str] = None,
    features: Optional[dict[str, Any]] = None,
) -> dict:
    """Create plan on Razorpay, then INSERT into subscription_plans.

    Returns the full plan row from DB.
    Raises on Razorpay failure or DB failure.
    """
    # 1. Call Razorpay
    item: dict[str, Any] = {
        "name": name,
        "amount": amount_paise,
        "currency": currency,
    }
    if description:
        item["description"] = description

    rz_plan = rz_client.plan.create({
        "period": period,
        "interval": interval,
        "item": item,
    })
    rz_plan_id = rz_plan.get("id")
    if not rz_plan_id:
        raise RuntimeError("Razorpay plan.create returned no plan id")

    # 2. Insert into DB
    plan_id = internal_plan_id or str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    sql = """
        INSERT INTO subscription_plans
            (id, razorpay_plan_id, name, credits_per_cycle, price_paise,
             currency, period, interval_count, trial_days, is_active,
             features, created_at, updated_at)
        VALUES
            (:id, :rz_plan_id, :name, :credits, :price,
             :currency, :period, :interval_count, :trial_days, true,
             CAST(:features AS jsonb), :now, :now)
    """
    execute_query_with_params(sql, {
        "id": plan_id,
        "rz_plan_id": rz_plan_id,
        "name": name,
        "credits": credits_per_cycle,
        "price": amount_paise,
        "currency": currency,
        "period": period,
        "interval_count": interval,
        "trial_days": trial_days,
        "features": json.dumps(features) if features else None,
        "now": now,
    })

    logger.info("Created plan {} (razorpay_plan_id={})", plan_id, rz_plan_id)

    # 3. Re-read and return
    row = _get_plan_by_id(plan_id)
    if not row:
        raise RuntimeError("Plan inserted but could not be re-read")
    return row


def _get_plan_by_id(plan_id: str) -> Optional[dict]:
    sql = "SELECT * FROM subscription_plans WHERE id = :id"
    rows = execute_query_with_params(sql, {"id": plan_id}, to_dict=True)
    if rows:
        _normalize_features(rows[0])
        return rows[0]
    return None


def _normalize_features(row: dict) -> None:
    """Ensure features is a plain dict (JSONB can come back as str)."""
    feat = row.get("features")
    if feat is not None and not isinstance(feat, dict):
        try:
            row["features"] = json.loads(str(feat))
        except Exception:
            row["features"] = None
```

If the file already exists with other functions (like the webhook handlers from doc 08), add these functions alongside them — they do not conflict.

#### C.3.4 — Create the subscription router with admin protection

Create `app/routers/subscription.py`:

```python
"""
Subscription router.

Endpoints:
  GET  /subscriptions/plans     – list available subscription plans (public)
  POST /subscriptions/plans     – create a new plan (admin-only, requires X-Admin-Key)
"""

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.security import APIKeyHeader
from loguru import logger

from app.models.subscription import CreatePlanRequest, PlanResponse
from app.services import subscription as sub_svc
from app.utils.config_utils import get_config

router = APIRouter()

# ── Admin key security ────────────────────────────────────────────────
# This registers X-Admin-Key in OpenAPI/Swagger so the "Authorize" button
# appears and you can enter the key from the Swagger UI — no guessing.

_admin_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)


def verify_admin_key(api_key: str = Depends(_admin_key_header)) -> str:
    """FastAPI dependency: reject requests without a valid admin key."""
    expected = get_config("SUBSCRIPTION_ADMIN_KEY")
    if not expected:
        raise HTTPException(
            status_code=401,
            detail="Admin endpoint disabled — SUBSCRIPTION_ADMIN_KEY not configured",
        )
    if not api_key or api_key != expected:
        raise HTTPException(
            status_code=401,
            detail="Invalid or missing admin key",
        )
    return api_key


# ── Endpoints ─────────────────────────────────────────────────────────

@router.get("/plans", response_model=list[PlanResponse])
async def list_plans():
    """List all active subscription plans. No authentication required."""
    return sub_svc.list_plans()


@router.post("/plans", response_model=PlanResponse, dependencies=[Depends(verify_admin_key)])
async def create_plan(body: CreatePlanRequest):
    """Create a new subscription plan on Razorpay and persist it in the DB.

    Requires the X-Admin-Key header (see Authorize button in Swagger).
    """
    try:
        result = sub_svc.create_plan_and_persist(
            name=body.name,
            amount_paise=body.amount_paise,
            currency=body.currency,
            period=body.period,
            interval=body.interval,
            credits_per_cycle=body.credits_per_cycle,
            trial_days=body.trial_days,
            description=body.description,
            internal_plan_id=body.internal_plan_id,
            features=body.features,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        logger.error("Plan creation failed: {}", exc)
        raise HTTPException(status_code=502, detail=str(exc))
    except Exception as exc:
        logger.error("Unexpected error creating plan: {}", exc)
        raise HTTPException(status_code=502, detail="Failed to create plan on Razorpay")
    return PlanResponse(**result)
```

#### C.3.5 — Mount the router in main.py

Open `app/main.py`. Add:

```python
from app.routers import subscription as subscription_router

app.include_router(
    subscription_router.router,
    prefix="/subscriptions",
    tags=["Subscriptions"],
)
```

The full `main.py` after modification:

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import payment as payment_router
from app.routers import subscription as subscription_router
from app.utils.config_utils import get_config

app = FastAPI(title="Common Control Service")

ALLOWED_ORIGINS = get_config("CORS_ORIGINS").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(payment_router.router, prefix="/payments", tags=["Payments"])
app.include_router(subscription_router.router, prefix="/subscriptions", tags=["Subscriptions"])


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

#### C.3.6 — Restart the app and test

Restart the server:

```bash
# Kill existing process, then:
bash run.sh
# or:
uvicorn app.main:app --reload --port 8003
```

**Test 1: List plans (should be empty initially)**

```bash
curl http://localhost:8003/subscriptions/plans
```

Expected: `[]` (empty list — no plans created yet).

**Test 2: Create a plan via curl**

```bash
curl -X POST http://localhost:8003/subscriptions/plans \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: paste_your_dev_admin_key_here" \
  -d '{
    "name": "Pro Monthly",
    "amount_paise": 39900,
    "currency": "INR",
    "period": "monthly",
    "interval": 1,
    "credits_per_cycle": 1200,
    "trial_days": 0,
    "description": "1200 credits per month",
    "features": {"models": ["gpt-4", "gpt-3.5", "<app>-30b"], "max_file_uploads": 10}
  }' | python3 -m json.tool
```

Expected response:

```json
{
    "id": "some-generated-uuid",
    "razorpay_plan_id": "plan_PROMonthly123",
    "name": "Pro Monthly",
    "credits_per_cycle": 1200,
    "price_paise": 39900,
    "currency": "INR",
    "period": "monthly",
    "interval_count": 1,
    "trial_days": 0,
    "is_active": true,
    "features": {
        "models": ["gpt-4", "gpt-3.5", "<app>-30b"],
        "max_file_uploads": 10
    }
}
```

Both `id` (your internal UUID) and `razorpay_plan_id` (Razorpay's ID) are in the response.

**Test 3: Verify in Swagger**

1. Open http://localhost:8003/docs in your browser.
2. You should see a **Subscriptions** section with `GET /subscriptions/plans` and `POST /subscriptions/plans`.
3. Click the **Authorize** button (top-right, has a lock icon).
4. In the popup, enter your admin key in the **X-Admin-Key** field and click **Authorize**.
5. Now expand `POST /subscriptions/plans`, click **Try it out**, fill in the body, click **Execute**.

**Test 4: Wrong or missing admin key**

```bash
# No key
curl -X POST http://localhost:8003/subscriptions/plans \
  -H "Content-Type: application/json" \
  -d '{"name":"test","amount_paise":100,"credits_per_cycle":10}' \
  -w "\nHTTP %{http_code}\n"
# Expected: HTTP 401, {"detail": "Invalid or missing admin key"}

# Wrong key
curl -X POST http://localhost:8003/subscriptions/plans \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: wrongwrongwrong" \
  -d '{"name":"test","amount_paise":100,"credits_per_cycle":10}' \
  -w "\nHTTP %{http_code}\n"
# Expected: HTTP 401, {"detail": "Invalid or missing admin key"}
```

**Test 5: List plans again**

```bash
curl http://localhost:8003/subscriptions/plans | python3 -m json.tool
```

Your created plan should now appear.

**Error responses reference:**

| HTTP code | Meaning | What to check |
|-----------|---------|--------------|
| `401` | Missing or wrong `X-Admin-Key` | Check header name (case-sensitive) and value matches `SUBSCRIPTION_ADMIN_KEY` in config |
| `400` | Validation error (bad body) | Check field names, types, and constraints (e.g. `amount_paise` must be > 0) |
| `502` | Razorpay API failed | Check Razorpay keys match your Dashboard mode (test vs live), check network, check app logs |

**Advantage of Method 3:** Unlike Methods 1 and 2, you do **not** need to manually seed the database (Part D). The API creates the Razorpay plan and the DB row in one call. You also get it in Swagger for easy re-use.

---

### C.4 — Verification (works for all three methods)

After using any method, run this SQL to confirm your DB has the plan:

```sql
SELECT id, razorpay_plan_id, name, credits_per_cycle, price_paise, is_active
FROM subscription_plans;
```

And confirm it exists on Razorpay: Dashboard → Payment Products → Subscriptions → Plans.

---

## Part D — Step 3: Seed the database and config (Methods 1 and 2 only)

**If you used Method 3 (API), skip this section** — the endpoint already inserted the row and you do not need to seed manually.

If you used Method 1 (Dashboard) or Method 2 (Python), Razorpay has the plan but your **Postgres database does not**. Your app looks up plans in `subscription_plans`, so you must insert a row.

### D.1 — Where and how to run the seed SQL

You need to run a SQL INSERT statement against your PostgreSQL database. Here are three ways — pick whichever tool you have:

**Option A — psql (command line):**

```bash
# Connect to the DEV database
psql -h <DB_HOST> -U <DB_USER> -d <DB_NAME>
```

It will ask for the password (check `DB_PSWD` in `app/config/app_config.ini` → `[DEV]` section).

Once connected, you see a prompt like `<DB_NAME>=>`. Paste the INSERT SQL below and press Enter. Then type `\q` to exit.

**Option B — DBeaver or pgAdmin:**

1. Open your database client.
2. Connect to the DEV database (host: `<DB_HOST>`, user: `<DB_USER>`, db: `<DB_NAME>`).
3. Open a new SQL editor / query tab.
4. Paste the INSERT SQL below.
5. Click the **Run** / **Execute** button (or press Ctrl+Enter / Cmd+Enter).

**Option C — Python REPL (from project root):**

```bash
cd /path/to/<payment-svc>
python3
```

```python
from app.utils.db_utils import execute_query

sql = """
INSERT INTO subscription_plans
    (id, razorpay_plan_id, name, credits_per_cycle, price_paise, currency,
     period, interval_count, trial_days, is_active, features)
VALUES
    ('plan-pro-monthly-v1', 'plan_xxx', 'Pro Monthly', 1200, 39900, 'INR',
     'monthly', 1, 0, true,
     '{"models": ["gpt-4", "gpt-3.5", "<app>-30b"], "max_file_uploads": 10}'::jsonb)
ON CONFLICT (id) DO NOTHING;
"""
execute_query(sql)
print("Done — plan seeded.")
```

### D.2 — The seed SQL

Replace `plan_xxx` with the **actual Razorpay plan ID** you copied from Method 1 or Method 2:

```sql
INSERT INTO subscription_plans
    (id, razorpay_plan_id, name, credits_per_cycle, price_paise, currency,
     period, interval_count, trial_days, is_active, features)
VALUES
    (
        'plan-pro-monthly-v1',          -- your internal plan ID (can be anything unique)
        'plan_xxx',                     -- ← REPLACE with your actual plan_xxx from Razorpay
        'Pro Monthly',                  -- display name
        1200,                           -- credits granted each billing cycle
        39900,                          -- ₹399 in paise
        'INR',
        'monthly',
        1,                              -- every 1 month
        0,                              -- no trial period
        true,                           -- plan is active
        '{"models": ["gpt-4", "gpt-3.5", "<app>-30b"], "max_file_uploads": 10}'::jsonb
    )
ON CONFLICT (id) DO NOTHING;
```

`ON CONFLICT (id) DO NOTHING` makes this **idempotent** — you can run it multiple times safely. If the row already exists, it does nothing.

### D.3 — Add the plan ID to config

Open `app/config/app_config.ini`. Add this line to **both** `[DEV]` and `[PROD]`:

```ini
RAZORPAY_PLAN_ID_PRO_MONTHLY=plan_xxx
```

Replace `plan_xxx` with your actual Razorpay plan ID. This config key is used by the subscribe endpoint later to know which Razorpay plan to link users to.

Verify it reads correctly:

```bash
cd /path/to/<payment-svc>
python3 -c "from app.utils.config_utils import get_config; print(get_config('RAZORPAY_PLAN_ID_PRO_MONTHLY'))"
```

If it prints your plan ID, the config is wired correctly. If it prints an empty string, double-check the key name and that you saved the file.

### D.4 — Verify the seed

Run this SQL (in psql, DBeaver, or Python — same methods as D.1):

```sql
SELECT id, name, razorpay_plan_id, credits_per_cycle, price_paise, is_active
FROM subscription_plans;
```

Expected:

```
        id              |     name      | razorpay_plan_id | credits_per_cycle | price_paise | is_active
------------------------+---------------+------------------+-------------------+-------------+-----------
 plan-pro-monthly-v1    | Pro Monthly   | plan_xxx         |              1200 |       39900 | t
```

### D.5 — Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `ERROR: relation "subscription_plans" does not exist` | Migration not run | Go back to Part B, run `002_subscription_tables.sql` |
| `ERROR: duplicate key value violates unique constraint` | Row already exists with a **different** `id` but same `razorpay_plan_id` | Check existing rows: `SELECT * FROM subscription_plans;` — you may already have it |
| `ON CONFLICT` does nothing, no row appears | Row with same `id` already exists (possibly with wrong `razorpay_plan_id`) | Delete the old row first: `DELETE FROM subscription_plans WHERE id = 'plan-pro-monthly-v1';` then re-run INSERT |
| Config prints empty string | Key name typo or file not saved | Check exact key name and that the line is in the correct `[DEV]` or `[PROD]` section |

---

## Part D-A — Admin Key Runbook (for Method 3)

If you are using Method 3 (the API endpoint `POST /subscriptions/plans`), you need an admin key. This section explains the full lifecycle — generating it, configuring it, testing it, and managing it in production.

### What is the admin key?

It is a **shared secret** — a long random string. When you call `POST /subscriptions/plans`, you send it as the header `X-Admin-Key`. The server compares it to `SUBSCRIPTION_ADMIN_KEY` from config. If they match, the request proceeds. If not, you get **401 Unauthorized**.

This is **not** end-user authentication. It is a simple guard so only your team (admins, ops) can create subscription plans. Regular users never see or need this key.

### Step 1: Generate a key

On your Mac:

```bash
openssl rand -hex 32
```

This prints a 64-character random hex string, for example:

```
[REDACTED-ADMIN-KEY]
```

Copy this string. This is your admin key for **DEV**. Generate a **different** one for PROD.

### Step 2: Add to config

Open `app/config/app_config.ini`. Add to the `[DEV]` section:

```ini
SUBSCRIPTION_ADMIN_KEY=[REDACTED-ADMIN-KEY]
```

And to the `[PROD]` section (with a **different** value):

```ini
SUBSCRIPTION_ADMIN_KEY=<generate-a-separate-key-for-prod>
```

### Step 3: Restart the app

Config values are cached by `@lru_cache` in `config_utils.py`. After changing the INI file, you **must restart** the application for the new key to take effect:

```bash
# Kill existing, then:
bash run.sh
```

### Step 4: Test it works

```bash
# With correct key — should succeed (or fail on Razorpay if body is invalid, but not 401)
curl -X POST http://localhost:8003/subscriptions/plans \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: [REDACTED-ADMIN-KEY]" \
  -d '{"name":"Test","amount_paise":100,"credits_per_cycle":10}' \
  -w "\nHTTP %{http_code}\n"
```

### Step 5: Test wrong key

```bash
curl -X POST http://localhost:8003/subscriptions/plans \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: this-is-wrong" \
  -d '{"name":"Test","amount_paise":100,"credits_per_cycle":10}' \
  -w "\nHTTP %{http_code}\n"
```

Expected: `HTTP 401` with `{"detail": "Invalid or missing admin key"}`.

### Step 6: Test missing key

```bash
curl -X POST http://localhost:8003/subscriptions/plans \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","amount_paise":100,"credits_per_cycle":10}' \
  -w "\nHTTP %{http_code}\n"
```

Expected: `HTTP 401` with `{"detail": "Invalid or missing admin key"}`.

### Step 7: Swagger UI

1. Open http://localhost:8003/docs.
2. Click the **Authorize** button (top-right of the page, lock icon).
3. In the popup, you will see a field for **X-Admin-Key**. Paste your admin key.
4. Click **Authorize**, then **Close**.
5. Now when you use `POST /subscriptions/plans` from the Swagger UI, it automatically sends the header.

### Step 8: What if SUBSCRIPTION_ADMIN_KEY is not set?

If you do not add `SUBSCRIPTION_ADMIN_KEY` to your config (or leave it empty), every `POST /subscriptions/plans` request will return **401** with:

```json
{"detail": "Admin endpoint disabled — SUBSCRIPTION_ADMIN_KEY not configured"}
```

This is by design — the endpoint is disabled until you explicitly configure a key.

### Step 9: Production checklist

| # | Item |
|---|------|
| 1 | PROD key is **different** from DEV key |
| 2 | Key was generated with `openssl rand -hex 32` (strong randomness) |
| 3 | Key is shared only via secure channel (password manager, not Slack/email) |
| 4 | Production uses **HTTPS** — never send the key over plain HTTP |
| 5 | If key is leaked: regenerate, update config, restart app immediately |
| 6 | This endpoint is for **admin/ops only** — do not expose it in frontend code |

---

## Part E — Step 4: Create the model file

Create `app/models/subscription.py`. **Order matters:** define plan-related models first (`PlanResponse`, `CreatePlanRequest`), then user-subscription models (`SubscribeRequest`, …). This matches what the routers import.

```python
from typing import Any, Optional
from pydantic import BaseModel, Field


class PlanResponse(BaseModel):
    """Returned by GET/POST /subscriptions/plans — mirrors subscription_plans + JSONB features."""
    id: str
    razorpay_plan_id: str
    name: str
    credits_per_cycle: int
    price_paise: int
    currency: str
    period: str
    interval_count: int
    trial_days: int
    is_active: bool
    features: Optional[dict[str, Any]] = None


class CreatePlanRequest(BaseModel):
    """Body for POST /subscriptions/plans — creates a Razorpay plan + DB row (admin)."""

    name: str = Field(min_length=1, max_length=128)
    amount_paise: int = Field(
        gt=0,
        description="Price per cycle in PAISE (₹399 = 39900). Not rupees!",
    )
    currency: str = Field(default="INR", min_length=3, max_length=3)
    period: str = Field(
        default="monthly",
        description="Razorpay period: daily, weekly, monthly, quarterly, yearly",
    )
    interval: int = Field(default=1, ge=1)
    credits_per_cycle: int = Field(gt=0)
    trial_days: int = Field(default=0, ge=0)
    description: Optional[str] = Field(default=None, max_length=512)
    internal_plan_id: Optional[str] = Field(
        default=None,
        description="Custom subscription_plans.id; UUID generated if omitted",
    )
    features: Optional[dict[str, Any]] = Field(default=None)


# ── User subscriptions (subscribe / cancel / invoices) ────────────────

class SubscribeRequest(BaseModel):
    plan_id: str


class SubscribeResponse(BaseModel):
    subscription_id: str
    razorpay_subscription_id: str
    short_url: str
    status: str


class SubscriptionStatusResponse(BaseModel):
    user_id: str
    plan_name: str
    status: str
    current_start: Optional[str] = None
    current_end: Optional[str] = None
    paid_count: int
    credits_per_cycle: int


class CancelSubscriptionRequest(BaseModel):
    cancel_at_cycle_end: bool = True


class CancelSubscriptionResponse(BaseModel):
    subscription_id: str
    status: str
    cancel_at_cycle_end: bool


class SubscriptionInvoice(BaseModel):
    id: str
    razorpay_invoice_id: Optional[str] = None
    razorpay_payment_id: Optional[str] = None
    amount: int
    status: str
    cycle_number: int
    created_at: str


class InvoiceHistoryResponse(BaseModel):
    subscription_id: str
    invoices: list[SubscriptionInvoice]
    total: int
```

### Why these models matter

| Model | Used by |
|-------|---------|
| `PlanResponse` | `GET /subscriptions/plans` and `POST /subscriptions/plans` responses — includes `razorpay_plan_id` and optional `features` |
| `CreatePlanRequest` | `POST /subscriptions/plans` (admin) — body for creating a Razorpay plan + DB row |
| `SubscribeRequest/Response` | `POST /subscriptions/subscribe` — initiate a subscription |
| `SubscriptionStatusResponse` | `GET /subscriptions/status` — check current subscription |
| `CancelSubscriptionRequest/Response` | `POST /subscriptions/cancel` — cancel subscription |
| `SubscriptionInvoice` / `InvoiceHistoryResponse` | `GET /subscriptions/invoices` — billing history |

---

## Part F — Step 5: Create the service file

Create **`app/services/subscription.py`**. This file does two jobs:

1. **Plan API** (from Part C.3) — `list_plans`, `create_plan_and_persist`, JSONB normalization. Used by `GET`/`POST /subscriptions/plans`.
2. **User subscriptions** — create Razorpay subscription, webhooks, cancel, invoices. Uses `get_plan()` for the subscribe flow.

**If you already implemented Part C.3**, you already have the plan helpers at the top of this file. **Do not delete them.** Append the **F.2** block below after the plan section. If you are building from scratch in one pass, use **F.1** then **F.2** in one file.

### F.1 — Plan helpers (match Part C.3 and the repo)

```python
import json
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from loguru import logger

from app.services.payment import rz_client
from app.utils.db_utils import execute_query_with_params


def list_plans(active_only: bool = True) -> list[dict]:
    """Return subscription plans from the DB (used by GET /subscriptions/plans)."""
    if active_only:
        sql = "SELECT * FROM subscription_plans WHERE is_active = true ORDER BY price_paise"
    else:
        sql = "SELECT * FROM subscription_plans ORDER BY price_paise"
    rows = execute_query_with_params(sql, {}, to_dict=True)
    for row in rows:
        _normalize_features(row)
    return rows


def create_plan_and_persist(
    name: str,
    amount_paise: int,
    currency: str,
    period: str,
    interval: int,
    credits_per_cycle: int,
    trial_days: int = 0,
    description: Optional[str] = None,
    internal_plan_id: Optional[str] = None,
    features: Optional[dict[str, Any]] = None,
) -> dict:
    """Create plan on Razorpay, then INSERT into subscription_plans."""
    item: dict[str, Any] = {
        "name": name,
        "amount": amount_paise,
        "currency": currency,
    }
    if description:
        item["description"] = description

    rz_plan = rz_client.plan.create({
        "period": period,
        "interval": interval,
        "item": item,
    })
    rz_plan_id = rz_plan.get("id")
    if not rz_plan_id:
        raise RuntimeError("Razorpay plan.create returned no plan id")

    plan_id = internal_plan_id or str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    sql = """
        INSERT INTO subscription_plans
            (id, razorpay_plan_id, name, credits_per_cycle, price_paise,
             currency, period, interval_count, trial_days, is_active,
             features, created_at, updated_at)
        VALUES
            (:id, :rz_plan_id, :name, :credits, :price,
             :currency, :period, :interval_count, :trial_days, true,
             CAST(:features AS jsonb), :now, :now)
    """
    execute_query_with_params(sql, {
        "id": plan_id,
        "rz_plan_id": rz_plan_id,
        "name": name,
        "credits": credits_per_cycle,
        "price": amount_paise,
        "currency": currency,
        "period": period,
        "interval_count": interval,
        "trial_days": trial_days,
        "features": json.dumps(features) if features else None,
        "now": now,
    })

    logger.info("Created plan {} (razorpay_plan_id={})", plan_id, rz_plan_id)

    row = _get_plan_by_id(plan_id)
    if not row:
        raise RuntimeError("Plan inserted but could not be re-read")
    return row


def _get_plan_by_id(plan_id: str) -> Optional[dict]:
    sql = "SELECT * FROM subscription_plans WHERE id = :id"
    rows = execute_query_with_params(sql, {"id": plan_id}, to_dict=True)
    if rows:
        _normalize_features(rows[0])
        return rows[0]
    return None


def _normalize_features(row: dict) -> None:
    feat = row.get("features")
    if feat is not None and not isinstance(feat, dict):
        try:
            row["features"] = json.loads(str(feat))
        except Exception:
            row["features"] = None


def get_plan(plan_id: str) -> Optional[dict]:
    """Single active plan by internal id — used by create_subscription (not the same as list_plans)."""
    sql = "SELECT * FROM subscription_plans WHERE id = :plan_id AND is_active = true"
    rows = execute_query_with_params(sql, {"plan_id": plan_id}, to_dict=True)
    if not rows:
        return None
    _normalize_features(rows[0])
    return rows[0]
```

### F.2 — User subscription lifecycle (append in the same file)

Continue **below** F.1 in `app/services/subscription.py`. Reuse **`rz_client`** from `app.services.payment` (do not create a second `razorpay.Client`).

```python
import uuid
from datetime import datetime, timezone
from typing import Optional

import razorpay
from loguru import logger

from app.utils.config_utils import get_config
from app.utils.db_utils import execute_query_with_params
from app.services.payment import (
    add_credits,
    update_litellm_budget,
    get_balance,
    refund_payment,
    rz_client,
)

# ── Subscription creation ─────────────────────────────────────────────

def create_subscription(user_id: str, plan_id: str) -> dict:
    """Create a new Razorpay subscription for a user.

    Edge cases handled:
      - Plan not found or inactive  → ValueError
      - User already has active sub → ValueError (no double-billing)
      - Razorpay API failure        → logs error, re-raises
    """
    plan = get_plan(plan_id)
    if not plan:
        raise ValueError("Plan not found or inactive")

    existing = get_active_subscription(user_id)
    if existing:
        raise ValueError(
            f"User already has an active subscription: {existing['razorpay_subscription_id']}. "
            "Cancel it first before subscribing to a new plan."
        )

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

    sub_id = str(uuid.uuid4())
    sql = """
        INSERT INTO user_subscriptions
            (id, user_id, plan_id, razorpay_subscription_id, status, created_at, updated_at)
        VALUES (:id, :user_id, :plan_id, :rz_sub_id, :status, :now, :now)
    """
    execute_query_with_params(sql, {
        "id": sub_id,
        "user_id": user_id,
        "plan_id": plan_id,
        "rz_sub_id": rz_sub["id"],
        "status": "created",
        "now": datetime.now(timezone.utc).isoformat(),
    })

    logger.info("Subscription {} created for user {} on plan {}", sub_id, user_id, plan_id)

    return {
        "subscription_id": sub_id,
        "razorpay_subscription_id": rz_sub["id"],
        "short_url": rz_sub.get("short_url", ""),
        "status": "created",
    }


# ── Active subscription lookup ────────────────────────────────────────

def get_active_subscription(user_id: str) -> Optional[dict]:
    """Return the user's current active (or authenticated) subscription, if any."""
    sql = """
        SELECT * FROM user_subscriptions
        WHERE user_id = :user_id
          AND status IN ('created', 'authenticated', 'active')
        ORDER BY created_at DESC
        LIMIT 1
    """
    rows = execute_query_with_params(sql, {"user_id": user_id}, to_dict=True)
    return rows[0] if rows else None


# ── Webhook handlers ──────────────────────────────────────────────────

def handle_subscription_authenticated(rz_sub_id: str) -> None:
    """subscription.authenticated — user authorized the mandate but hasn't been
    charged yet. For UPI: mandate registered. For cards: token saved."""
    sub = _get_sub_by_rz_id(rz_sub_id)
    if not sub:
        logger.warning("Webhook: subscription {} not found in DB (authenticated)", rz_sub_id)
        return
    _update_sub_status(rz_sub_id, "authenticated")
    logger.info("Subscription {} authenticated", rz_sub_id)


def handle_subscription_activated(rz_sub_id: str) -> None:
    """subscription.activated — first charge succeeded and subscription is now
    running. Note: subscription.charged also fires at the same time for the
    first charge, so credits are handled there, not here."""
    sub = _get_sub_by_rz_id(rz_sub_id)
    if not sub:
        logger.warning("Webhook: subscription {} not found in DB (activated)", rz_sub_id)
        return
    _update_sub_status(rz_sub_id, "active")
    logger.info("Subscription {} activated", rz_sub_id)


def handle_subscription_charged(rz_sub_id: str, payment_entity: dict) -> None:
    """subscription.charged — THE main money event. Razorpay successfully
    charged the user for a billing cycle. This is where credits are added.

    Edge cases handled:
      - Subscription not in DB                → log + skip (don't crash)
      - Plan not found (shouldn't happen)     → log error + skip
      - Duplicate payment (idempotency)       → skip via invoice uniqueness
      - LiteLLM budget sync failure           → log error (credits still added)
    """
    sub = _get_sub_by_rz_id(rz_sub_id)
    if not sub:
        logger.warning("Webhook: subscription {} not found in DB (charged)", rz_sub_id)
        return

    plan = get_plan(sub["plan_id"])
    if not plan:
        logger.error("Webhook: plan {} not found for subscription {}", sub["plan_id"], rz_sub_id)
        return

    rz_payment_id = payment_entity.get("id", "")

    # Idempotency: check if we already recorded this payment
    existing = _get_invoice_by_payment(rz_payment_id)
    if existing:
        logger.info("Webhook: payment {} already processed for subscription {}", rz_payment_id, rz_sub_id)
        return

    # Record the invoice
    _save_invoice(sub["id"], payment_entity)

    # Add credits (reuses existing one-time payment credit system)
    new_balance = add_credits(
        user_id=str(sub["user_id"]),
        amount=plan["credits_per_cycle"],
        reason="subscription",
        reference_id=rz_payment_id,
    )

    # Sync LiteLLM budget (matching one-time payment flow)
    budget_ok = update_litellm_budget(
        user_id=str(sub["user_id"]),
        max_budget=float(new_balance),
    )
    if not budget_ok:
        logger.error(
            "LiteLLM budget sync failed for subscription {} payment {}. "
            "Credits were added but budget not updated — manual fix needed.",
            rz_sub_id, rz_payment_id,
        )

    # Update subscription status and paid_count
    _update_sub_status(rz_sub_id, "active", paid_count_increment=1)

    logger.info(
        "Webhook: credited {} credits for subscription {} (payment {}, balance {})",
        plan["credits_per_cycle"], rz_sub_id, rz_payment_id, new_balance,
    )


def handle_subscription_pending(rz_sub_id: str) -> None:
    """subscription.pending — charge attempt is in progress (common with UPI
    where debit takes time). No action needed, just log."""
    _update_sub_status(rz_sub_id, "pending")
    logger.info("Subscription {} pending (charge in progress)", rz_sub_id)


def handle_subscription_halted(rz_sub_id: str) -> None:
    """subscription.halted — all payment retries exhausted. The user will NOT
    receive credits until they update their payment method.

    This is a CRITICAL event in production — you should alert on it."""
    _update_sub_status(rz_sub_id, "halted")
    logger.warning(
        "ALERT: Subscription {} HALTED — payment retries exhausted. "
        "User will not receive credits until payment method is updated.",
        rz_sub_id,
    )


def handle_subscription_cancelled(rz_sub_id: str) -> None:
    """subscription.cancelled — subscription was cancelled (by user, by you,
    or by Razorpay after being halted too long)."""
    _update_sub_status(rz_sub_id, "cancelled")
    logger.info("Subscription {} cancelled", rz_sub_id)


def handle_subscription_completed(rz_sub_id: str) -> None:
    """subscription.completed — all billing cycles exhausted (total_count
    reached). Rare if you set total_count=120."""
    _update_sub_status(rz_sub_id, "completed")
    logger.info("Subscription {} completed (all cycles exhausted)", rz_sub_id)


def handle_subscription_paused(rz_sub_id: str) -> None:
    """subscription.paused — you explicitly paused the subscription via API."""
    _update_sub_status(rz_sub_id, "paused")
    logger.info("Subscription {} paused", rz_sub_id)


def handle_subscription_resumed(rz_sub_id: str) -> None:
    """subscription.resumed — you explicitly resumed a paused subscription."""
    _update_sub_status(rz_sub_id, "active")
    logger.info("Subscription {} resumed", rz_sub_id)


# ── User-facing operations ────────────────────────────────────────────

def cancel_subscription(user_id: str, rz_sub_id: str, at_cycle_end: bool = True) -> dict:
    """Cancel a subscription via the Razorpay API.

    Edge cases:
      - Subscription not found    → ValueError
      - Wrong user                → ValueError (security)
      - Already cancelled         → ValueError
      - Razorpay API failure      → logs + re-raises
    """
    sub = _get_sub_by_rz_id(rz_sub_id)
    if not sub:
        raise ValueError("Subscription not found")
    if str(sub["user_id"]) != user_id:
        raise ValueError("Subscription does not belong to this user")
    if sub["status"] in ("cancelled", "completed"):
        raise ValueError(f"Subscription is already {sub['status']}")

    try:
        rz_client.subscription.cancel(rz_sub_id, {
            "cancel_at_cycle_end": 1 if at_cycle_end else 0,
        })
    except Exception as exc:
        logger.error("Razorpay cancel failed for subscription {}: {}", rz_sub_id, exc)
        raise

    new_status = "cancelled" if not at_cycle_end else sub["status"]
    _update_sub_status(rz_sub_id, new_status, cancel_at_cycle_end=at_cycle_end)

    return {
        "subscription_id": sub["id"],
        "status": new_status,
        "cancel_at_cycle_end": at_cycle_end,
    }


def get_invoices(subscription_id: str, limit: int = 50, offset: int = 0) -> list[dict]:
    """Return billing invoices for a subscription, newest first."""
    sql = """
        SELECT * FROM subscription_invoices
        WHERE subscription_id = :sub_id
        ORDER BY cycle_number DESC
        LIMIT :lim OFFSET :off
    """
    return execute_query_with_params(
        sql, {"sub_id": subscription_id, "lim": limit, "off": offset}, to_dict=True
    )


def count_invoices(subscription_id: str) -> int:
    sql = "SELECT COUNT(*) as cnt FROM subscription_invoices WHERE subscription_id = :sub_id"
    rows = execute_query_with_params(sql, {"sub_id": subscription_id}, to_dict=True)
    return rows[0]["cnt"] if rows else 0


# ── Internal helpers ──────────────────────────────────────────────────

def _get_sub_by_rz_id(rz_sub_id: str) -> Optional[dict]:
    sql = "SELECT * FROM user_subscriptions WHERE razorpay_subscription_id = :rz_sub_id"
    rows = execute_query_with_params(sql, {"rz_sub_id": rz_sub_id}, to_dict=True)
    return rows[0] if rows else None


def _get_invoice_by_payment(rz_payment_id: str) -> Optional[dict]:
    sql = "SELECT * FROM subscription_invoices WHERE razorpay_payment_id = :pid"
    rows = execute_query_with_params(sql, {"pid": rz_payment_id}, to_dict=True)
    return rows[0] if rows else None


def _save_invoice(subscription_id: str, payment_entity: dict) -> None:
    sql = """
        INSERT INTO subscription_invoices
            (id, subscription_id, razorpay_invoice_id, razorpay_payment_id,
             amount, status, cycle_number, created_at, updated_at)
        VALUES
            (:id, :sub_id, :inv_id, :pay_id, :amount, :status, :cycle, :now, :now)
    """
    execute_query_with_params(sql, {
        "id": str(uuid.uuid4()),
        "sub_id": subscription_id,
        "inv_id": payment_entity.get("invoice_id"),
        "pay_id": payment_entity.get("id"),
        "amount": payment_entity.get("amount", 0),
        "status": "paid",
        "cycle": 0,
        "now": datetime.now(timezone.utc).isoformat(),
    })


def _update_sub_status(rz_sub_id: str, status: str,
                       paid_count_increment: int = 0,
                       cancel_at_cycle_end: Optional[bool] = None) -> None:
    parts = ["status = :status", "updated_at = :now"]
    params: dict = {
        "rz_sub_id": rz_sub_id,
        "status": status,
        "now": datetime.now(timezone.utc).isoformat(),
    }

    if paid_count_increment:
        parts.append("paid_count = paid_count + :inc")
        params["inc"] = paid_count_increment

    if cancel_at_cycle_end is not None:
        parts.append("cancel_at_cycle_end = :cace")
        params["cace"] = cancel_at_cycle_end

    sql = f"UPDATE user_subscriptions SET {', '.join(parts)} WHERE razorpay_subscription_id = :rz_sub_id"
    execute_query_with_params(sql, params)
```

### Edge cases reference table

| Edge case | Where handled | What happens |
|-----------|---------------|-------------|
| User already subscribed | `create_subscription()` | `ValueError` before hitting Razorpay |
| Plan not found / inactive | `create_subscription()` | `ValueError` with clear message |
| Razorpay API down | `create_subscription()`, `cancel_subscription()` | Exception logged, re-raised to router (→ 502) |
| Duplicate webhook (same payment) | `handle_subscription_charged()` | `_get_invoice_by_payment()` finds existing → skip |
| Webhook for unknown subscription | All `handle_*` functions | Log warning, return without crashing |
| LiteLLM budget sync fails | `handle_subscription_charged()` | Credits still added, error logged for manual fix |
| Cancel already-cancelled sub | `cancel_subscription()` | `ValueError` |
| Wrong user tries to cancel | `cancel_subscription()` | `ValueError` (security check) |
| `subscription.charged` arrives before `subscription.activated` | Both handlers are independent | `charged` adds credits regardless of current status; `activated` just updates status |
| UPI mandate registered but not charged | `handle_subscription_authenticated()` | Status → `authenticated`, no credits (credits only on `charged`) |
| All retries exhausted | `handle_subscription_halted()` | Status → `halted`, ALERT-level log |

---

## Part G — Step 6: Create the router file

Create or extend **`app/routers/subscription.py`**.

**If you already created this file in Part C.3** (admin-only `GET`/`POST /plans`), **merge** — add the subscribe/status/cancel/invoices routes below the plan routes. Do **not** remove `POST /plans` or `verify_admin_key`.

**One file** should expose:

- **Plans:** `GET /subscriptions/plans` (public), `POST /subscriptions/plans` (admin, `X-Admin-Key`).
- **Users:** `POST /subscribe`, `GET /status`, `POST /cancel`, `GET /invoices` (auth via `userid` / token as in payment router).

```python
"""
Subscription router.

Endpoints:
  GET  /subscriptions/plans      – list plans (public)
  POST /subscriptions/plans    – create plan (admin, X-Admin-Key)
  POST /subscriptions/subscribe
  GET  /subscriptions/status
  POST /subscriptions/cancel
  GET  /subscriptions/invoices
"""

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.security import APIKeyHeader
from loguru import logger

from app.models.subscription import (
    CreatePlanRequest,
    PlanResponse,
    SubscribeRequest,
    SubscribeResponse,
    SubscriptionStatusResponse,
    CancelSubscriptionRequest,
    CancelSubscriptionResponse,
    SubscriptionInvoice,
    InvoiceHistoryResponse,
)
from app.services import subscription as sub_svc
from app.routers.payment import get_user_id_from_request
from app.utils.config_utils import get_config

router = APIRouter()

_admin_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)


def verify_admin_key(api_key: str = Depends(_admin_key_header)) -> str:
    expected = get_config("SUBSCRIPTION_ADMIN_KEY")
    if not expected:
        raise HTTPException(
            status_code=401,
            detail="Admin endpoint disabled — SUBSCRIPTION_ADMIN_KEY not configured",
        )
    if not api_key or api_key != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing admin key")
    return api_key


@router.get("/plans", response_model=list[PlanResponse])
async def list_plans():
    """List all active subscription plans. Uses sub_svc.list_plans() (not get_plans)."""
    return sub_svc.list_plans()


@router.post("/plans", response_model=PlanResponse, dependencies=[Depends(verify_admin_key)])
async def create_plan(body: CreatePlanRequest):
    try:
        result = sub_svc.create_plan_and_persist(
            name=body.name,
            amount_paise=body.amount_paise,
            currency=body.currency,
            period=body.period,
            interval=body.interval,
            credits_per_cycle=body.credits_per_cycle,
            trial_days=body.trial_days,
            description=body.description,
            internal_plan_id=body.internal_plan_id,
            features=body.features,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        logger.error("Plan creation failed: {}", exc)
        raise HTTPException(status_code=502, detail=str(exc))
    except Exception as exc:
        logger.error("Unexpected error creating plan: {}", exc)
        raise HTTPException(status_code=502, detail="Failed to create plan on Razorpay")
    return PlanResponse(**result)


@router.post("/subscribe", response_model=SubscribeResponse)
async def subscribe(request: Request, body: SubscribeRequest):
    """Create a new subscription. Returns a short_url for the user to
    complete payment authorization."""
    user_id = await get_user_id_from_request(request)
    try:
        result = sub_svc.create_subscription(user_id, body.plan_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=502, detail="Failed to create subscription on Razorpay")
    return SubscribeResponse(**result)


@router.get("/status", response_model=SubscriptionStatusResponse)
async def subscription_status(request: Request):
    """Get the current subscription for the authenticated user."""
    user_id = await get_user_id_from_request(request)
    sub = sub_svc.get_active_subscription(user_id)
    if not sub:
        raise HTTPException(status_code=404, detail="No active subscription")
    plan = sub_svc.get_plan(sub["plan_id"])
    return SubscriptionStatusResponse(
        user_id=user_id,
        plan_name=plan["name"] if plan else "Unknown",
        status=sub["status"],
        current_start=str(sub["current_start"]) if sub.get("current_start") else None,
        current_end=str(sub["current_end"]) if sub.get("current_end") else None,
        paid_count=sub["paid_count"],
        credits_per_cycle=plan["credits_per_cycle"] if plan else 0,
    )


@router.post("/cancel", response_model=CancelSubscriptionResponse)
async def cancel_subscription(request: Request, body: CancelSubscriptionRequest):
    """Cancel the user's active subscription."""
    user_id = await get_user_id_from_request(request)
    sub = sub_svc.get_active_subscription(user_id)
    if not sub:
        raise HTTPException(status_code=404, detail="No active subscription")
    try:
        result = sub_svc.cancel_subscription(
            user_id, sub["razorpay_subscription_id"], body.cancel_at_cycle_end
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=502, detail="Failed to cancel subscription on Razorpay")
    return CancelSubscriptionResponse(**result)


@router.get("/invoices", response_model=InvoiceHistoryResponse)
async def invoice_history(
    request: Request,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """Billing history: list all invoices for the user's active subscription."""
    user_id = await get_user_id_from_request(request)
    sub = sub_svc.get_active_subscription(user_id)
    if not sub:
        raise HTTPException(status_code=404, detail="No active subscription")
    invoices = sub_svc.get_invoices(sub["id"], limit, offset)
    total = sub_svc.count_invoices(sub["id"])
    return InvoiceHistoryResponse(
        subscription_id=sub["id"],
        invoices=[
            SubscriptionInvoice(
                id=inv["id"],
                razorpay_invoice_id=inv.get("razorpay_invoice_id"),
                razorpay_payment_id=inv.get("razorpay_payment_id"),
                amount=inv["amount"],
                status=inv["status"],
                cycle_number=inv["cycle_number"],
                created_at=str(inv["created_at"]),
            )
            for inv in invoices
        ],
        total=total,
    )
```

---

## Part H — Step 7: Extend the webhook handler

Open `app/routers/payment.py`. You need to add subscription event handling inside the existing `razorpay_webhook` function.

### What to change

Add this import at the top of the file:

```python
from app.services import subscription as sub_svc
```

Then, inside the `razorpay_webhook` function, add a new `elif` branch **after** the existing `refund.created` handler and **before** the `else` that logs ignored events:

```python
    elif event_type.startswith("subscription."):
        sub_entity = event.get("payload", {}).get("subscription", {}).get("entity", {})
        rz_sub_id = sub_entity.get("id")

        if not rz_sub_id:
            logger.warning("Webhook: subscription event {} with no subscription ID", event_type)
        elif event_type == "subscription.authenticated":
            sub_svc.handle_subscription_authenticated(rz_sub_id)
        elif event_type == "subscription.activated":
            sub_svc.handle_subscription_activated(rz_sub_id)
        elif event_type == "subscription.charged":
            sub_svc.handle_subscription_charged(rz_sub_id, payment_entity)
        elif event_type == "subscription.pending":
            sub_svc.handle_subscription_pending(rz_sub_id)
        elif event_type == "subscription.halted":
            sub_svc.handle_subscription_halted(rz_sub_id)
        elif event_type == "subscription.cancelled":
            sub_svc.handle_subscription_cancelled(rz_sub_id)
        elif event_type == "subscription.completed":
            sub_svc.handle_subscription_completed(rz_sub_id)
        elif event_type == "subscription.paused":
            sub_svc.handle_subscription_paused(rz_sub_id)
        elif event_type == "subscription.resumed":
            sub_svc.handle_subscription_resumed(rz_sub_id)
        else:
            logger.debug("Webhook: ignoring subscription event {}", event_type)
```

### The full webhook function after modification

For clarity, here is what the complete `razorpay_webhook` function should look like:

```python
@router.post("/webhook")
async def razorpay_webhook(request: Request):
    """Razorpay server-to-server webhook. Handles payment.captured,
    payment.failed, refund.created, and subscription.* events."""
    raw_body = await request.body()
    signature = request.headers.get("X-Razorpay-Signature", "")

    if not pay_svc.verify_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    event = json.loads(raw_body)
    event_type = event.get("event", "")
    payment_entity = (
        event.get("payload", {}).get("payment", {}).get("entity", {})
    )
    rz_order_id = payment_entity.get("order_id")
    rz_payment_id = payment_entity.get("id")

    # ── One-time payment events ──────────────────────────────────
    if event_type == "payment.captured" and rz_order_id and rz_payment_id:
        try:
            order = pay_svc.process_payment_captured(rz_order_id, rz_payment_id)
            if order:
                logger.info("Webhook: credited {} credits for order {}",
                            order["credits"], rz_order_id)
            else:
                logger.info("Webhook: order {} already processed", rz_order_id)
        except RuntimeError as exc:
            logger.error("Webhook: payment captured but LiteLLM sync failed "
                         "for order {}, auto-refund triggered: {}",
                         rz_order_id, exc)

    elif event_type == "payment.failed" and rz_order_id:
        pay_svc.mark_order_failed(rz_order_id)
        logger.info("Webhook: marked order {} as failed", rz_order_id)

    elif event_type == "refund.created" and rz_order_id:
        try:
            result = pay_svc.process_refund(rz_order_id, reason="razorpay_dashboard")
            logger.info("Webhook: refunded order {}, reversed {} credits",
                        rz_order_id, result["credits_reversed"])
        except ValueError as exc:
            logger.warning("Webhook: refund skipped for order {}: {}",
                           rz_order_id, exc)

    # ── Subscription events ──────────────────────────────────────
    elif event_type.startswith("subscription."):
        sub_entity = event.get("payload", {}).get("subscription", {}).get("entity", {})
        rz_sub_id = sub_entity.get("id")

        if not rz_sub_id:
            logger.warning("Webhook: subscription event {} with no subscription ID", event_type)
        elif event_type == "subscription.authenticated":
            sub_svc.handle_subscription_authenticated(rz_sub_id)
        elif event_type == "subscription.activated":
            sub_svc.handle_subscription_activated(rz_sub_id)
        elif event_type == "subscription.charged":
            sub_svc.handle_subscription_charged(rz_sub_id, payment_entity)
        elif event_type == "subscription.pending":
            sub_svc.handle_subscription_pending(rz_sub_id)
        elif event_type == "subscription.halted":
            sub_svc.handle_subscription_halted(rz_sub_id)
        elif event_type == "subscription.cancelled":
            sub_svc.handle_subscription_cancelled(rz_sub_id)
        elif event_type == "subscription.completed":
            sub_svc.handle_subscription_completed(rz_sub_id)
        elif event_type == "subscription.paused":
            sub_svc.handle_subscription_paused(rz_sub_id)
        elif event_type == "subscription.resumed":
            sub_svc.handle_subscription_resumed(rz_sub_id)
        else:
            logger.debug("Webhook: ignoring subscription event {}", event_type)

    else:
        logger.debug("Webhook: ignoring event {}", event_type)

    return {"status": "ok"}
```

### Why `subscription.charged` uses `payment_entity`

When Razorpay fires `subscription.charged`, the webhook payload contains **both** `payload.subscription.entity` (the subscription object) and `payload.payment.entity` (the payment that was captured for this cycle). The `payment_entity` gives you the `razorpay_payment_id` and `amount`, which you need for the invoice record and idempotency check.

---

## Part I — Step 8: Mount in main.py

Open `app/main.py` and add the subscription router:

```python
from app.routers import subscription as subscription_router

app.include_router(
    subscription_router.router,
    prefix="/subscriptions",
    tags=["Subscriptions"],
)
```

The full `main.py` after modification:

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import payment as payment_router
from app.routers import subscription as subscription_router
from app.utils.config_utils import get_config

app = FastAPI(title="Common Control Service")

ALLOWED_ORIGINS = get_config("CORS_ORIGINS").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(payment_router.router, prefix="/payments", tags=["Payments"])
app.include_router(subscription_router.router, prefix="/subscriptions", tags=["Subscriptions"])


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

### Verify

Restart the server and open http://localhost:8003/docs. You should see a new **Subscriptions** section with these endpoints:

```
GET  /subscriptions/plans
POST /subscriptions/subscribe
GET  /subscriptions/status
POST /subscriptions/cancel
GET  /subscriptions/invoices
```

---

## Part J — Testing guide

### J.1 — Manual testing flow (step-by-step)

This is the full happy-path test you should run after building the module.

**Step 1: Verify plans are loaded**

```bash
curl http://localhost:8003/subscriptions/plans | python3 -m json.tool
```

Expected: a JSON array with your seeded plan. If empty, re-run the seed SQL from Part D.

**Step 2: Create a subscription**

```bash
curl -X POST http://localhost:8003/subscriptions/subscribe \
  -H "Content-Type: application/json" \
  -H "userid: 12345" \
  -d '{"plan_id": "plan-pro-monthly-v1"}' | python3 -m json.tool
```

Expected response:

```json
{
    "subscription_id": "some-uuid",
    "razorpay_subscription_id": "sub_xxx",
    "short_url": "https://rzp.io/i/xxx",
    "status": "created"
}
```

**Step 3: Complete payment**

Open the `short_url` in a browser. Razorpay shows a checkout page. In **test mode**, use:

| Field | Test value |
|-------|-----------|
| Card number | `4111 1111 1111 1111` |
| Expiry | Any future date |
| CVV | Any 3 digits |
| OTP | `1234` (Razorpay test mode auto-accepts) |

**Step 4: Check the database**

```sql
-- Subscription should exist
SELECT id, user_id, status, paid_count, razorpay_subscription_id
FROM user_subscriptions
WHERE user_id = '12345';

-- If webhook fired, credits should be added
SELECT balance FROM api_user_credits WHERE user_id = '12345';

-- Invoice should be recorded
SELECT * FROM subscription_invoices
WHERE subscription_id = (
    SELECT id FROM user_subscriptions WHERE user_id = '12345' LIMIT 1
);
```

**Step 5: Check subscription status via API**

```bash
curl http://localhost:8003/subscriptions/status \
  -H "userid: 12345" | python3 -m json.tool
```

**Step 6: Cancel the subscription**

```bash
curl -X POST http://localhost:8003/subscriptions/cancel \
  -H "Content-Type: application/json" \
  -H "userid: 12345" \
  -d '{"cancel_at_cycle_end": true}' | python3 -m json.tool
```

### J.2 — Webhook testing with ngrok

Razorpay cannot call `localhost`. You need a public URL.

**Step 1: Start ngrok**

```bash
ngrok http 8003
```

ngrok gives you a URL like `https://a1b2c3d4.ngrok-free.app`.

**Step 2: Configure Razorpay webhooks**

1. Go to https://dashboard.razorpay.com → **Settings → Webhooks**
2. Click **Add New Webhook**
3. Webhook URL: `https://a1b2c3d4.ngrok-free.app/payments/webhook`
4. Secret: must match `RAZORPAY_WEBHOOK_SECRET` in your config (`<REDACTED-WEBHOOK-SECRET>` for DEV)
5. **Events to enable** (check ALL of these):
   - `payment.captured`
   - `payment.failed`
   - `refund.created`
   - `subscription.authenticated`
   - `subscription.activated`
   - `subscription.charged`
   - `subscription.pending`
   - `subscription.halted`
   - `subscription.cancelled`
   - `subscription.completed`
   - `subscription.paused`
   - `subscription.resumed`

**Step 3: Test the flow**

After completing a payment (Step 3 above), you should see webhook requests arriving in the ngrok terminal and in your FastAPI logs.

**Step 4: Verify in ngrok inspector**

Open http://127.0.0.1:4040 — ngrok's web inspector. You can see every request, replay them, and inspect payloads.

### J.3 — Simulating edge cases

**Test duplicate webhook (idempotency):**

In ngrok inspector (http://127.0.0.1:4040), find a `subscription.charged` webhook and click **Replay**. Your logs should show "already processed" — no duplicate credits.

**Test failed payment:**

Use Razorpay's test card for failures:

| Card | Behavior |
|------|----------|
| `4000 0000 0000 0002` | Card declined |
| `5104 0600 0000 0008` | Insufficient funds |

The subscription should stay in `authenticated` and eventually fire `subscription.pending` / `subscription.halted`.

**Test no active subscription:**

```bash
# User with no subscription
curl http://localhost:8003/subscriptions/status \
  -H "userid: 99999" -w "\n%{http_code}\n"
# Expected: 404 "No active subscription"
```

**Test cancel of already-cancelled subscription:**

```bash
# Cancel again — should get 400 or 404
curl -X POST http://localhost:8003/subscriptions/cancel \
  -H "Content-Type: application/json" \
  -H "userid: 12345" \
  -d '{"cancel_at_cycle_end": true}' -w "\n%{http_code}\n"
```

**Test double subscribe:**

```bash
# While already subscribed
curl -X POST http://localhost:8003/subscriptions/subscribe \
  -H "Content-Type: application/json" \
  -H "userid: 12345" \
  -d '{"plan_id": "plan-pro-monthly-v1"}' -w "\n%{http_code}\n"
# Expected: 400 "User already has an active subscription"
```

### J.4 — SQL verification queries (cheat sheet)

Run these after testing to confirm everything is consistent:

```sql
-- 1. All subscriptions and their status
SELECT us.user_id, sp.name, us.status, us.paid_count,
       us.razorpay_subscription_id, us.created_at
FROM user_subscriptions us
JOIN subscription_plans sp ON us.plan_id = sp.id
ORDER BY us.created_at DESC;

-- 2. All invoices with subscription info
SELECT si.cycle_number, si.amount / 100.0 as amount_inr, si.status,
       si.razorpay_payment_id, us.user_id
FROM subscription_invoices si
JOIN user_subscriptions us ON si.subscription_id = us.id
ORDER BY si.created_at DESC;

-- 3. Credit ledger entries from subscriptions
SELECT * FROM razorpay_credit_transactions
WHERE reason = 'subscription'
ORDER BY created_at DESC;

-- 4. Cross-check: credits in ledger vs balance
SELECT uc.user_id, uc.balance as current_balance,
       COALESCE(SUM(CASE WHEN ct.transaction_type = 'credit' THEN ct.amount ELSE 0 END), 0)
       - COALESCE(SUM(CASE WHEN ct.transaction_type IN ('debit', 'refund') THEN ct.amount ELSE 0 END), 0)
       as ledger_balance
FROM api_user_credits uc
LEFT JOIN razorpay_credit_transactions ct ON uc.user_id = ct.user_id
GROUP BY uc.user_id, uc.balance
HAVING uc.balance != (
    COALESCE(SUM(CASE WHEN ct.transaction_type = 'credit' THEN ct.amount ELSE 0 END), 0)
    - COALESCE(SUM(CASE WHEN ct.transaction_type IN ('debit', 'refund') THEN ct.amount ELSE 0 END), 0)
);
-- If this returns rows, you have a balance mismatch — investigate.
```

---

## Part K — Production checklist

Before going live with subscriptions, walk through every item:

| # | Item | Done? |
|---|------|-------|
| 1 | Migration `002_subscription_tables.sql` run on **production** DB | [ ] |
| 2 | `subscription_plans` table seeded with **live** Razorpay plan ID | [ ] |
| 3 | `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` set to **live** keys in `[PROD]` config | [ ] |
| 4 | `RAZORPAY_WEBHOOK_SECRET` set to the **production** webhook secret | [ ] |
| 5 | Razorpay Plan created in **live** mode (not test) | [ ] |
| 6 | `RAZORPAY_PLAN_ID_PRO_MONTHLY` set to the **live** plan ID in `[PROD]` | [ ] |
| 7 | Webhook URL set to production domain (e.g. `https://api.<app>.ai/payments/webhook`) | [ ] |
| 8 | All `subscription.*` events enabled in Razorpay webhook settings | [ ] |
| 9 | Test one real subscription with a ₹1 plan (create a cheap test plan, subscribe, verify credits, cancel) | [ ] |
| 10 | Delete or deactivate the ₹1 test plan after verification | [ ] |
| 11 | Monitor first real subscription cycle (wait for first `subscription.charged` webhook) | [ ] |
| 12 | Verify LiteLLM budget syncs on subscription credit add | [ ] |
| 13 | Set up alerting for `subscription.halted` events (at minimum: check logs daily) | [ ] |

### Going live sequence

```
1. Deploy code with subscription module
2. Run migration on production DB
3. Seed subscription_plans with live plan ID
4. Configure webhook URL + events in Razorpay live Dashboard
5. Test with ₹1 plan (real money, real webhook, real credits)
6. Activate real plan for users
7. Monitor logs for first 48 hours
```

---

## Part L — Common mistakes and pitfalls

### Mistake 1: Forgetting to enable subscription events in Razorpay Dashboard

**Symptom:** Subscription works, user pays, but no credits appear.

**Why:** Razorpay only sends webhooks for events you explicitly enable. If you only have `payment.captured` enabled, you will never receive `subscription.charged`.

**Fix:** Go to Razorpay Dashboard → Settings → Webhooks → edit your webhook → check all `subscription.*` events.

---

### Mistake 2: Using `payment.captured` for subscription payments

**Symptom:** First subscription payment works (credits added), but renewal payments are ignored.

**Why:** For subscriptions, the first payment may come as `payment.captured` **and** `subscription.charged`. But renewal payments **only** come as `subscription.charged` — there is no `payment.captured` for recurring charges because there is no Razorpay order associated with them.

**Fix:** Always handle subscription credits in `handle_subscription_charged()`, never in `process_payment_captured()`.

---

### Mistake 3: Not handling `subscription.halted`

**Symptom:** User's payment fails silently. They stop getting credits but don't know why.

**Why:** Razorpay retries failed payments for 3 days (cards) or immediately stops (UPI). After retries are exhausted, it fires `subscription.halted`. If you don't handle this, the subscription stays "active" in your DB but Razorpay has stopped charging.

**Fix:** `handle_subscription_halted()` updates status to `halted`. In production, also send a notification to the user and/or your ops team.

---

### Mistake 4: Not seeding `subscription_plans`

**Symptom:** `POST /subscriptions/subscribe` returns `400 Plan not found or inactive`.

**Why:** The service looks up the plan in your database, not directly in Razorpay. If you forgot the INSERT from Part D, the table is empty.

**Fix:** Run the seed SQL from Part D.

---

### Mistake 5: Webhook URL not reachable from the internet

**Symptom:** Everything works in Postman, but webhooks never arrive.

**Why:** Razorpay sends webhooks from their servers to your webhook URL. If your URL is `localhost:8003`, Razorpay can't reach it. In production, your URL must be publicly accessible (e.g. `https://api.<app>.ai/payments/webhook`).

**Fix:**
- Dev: use ngrok (`ngrok http 8003`)
- Production: use your public domain through the ingress/load balancer

---

### Mistake 6: `user_id` type mismatch

**Symptom:** Queries joining `razorpay_orders` and `user_subscriptions` behave unexpectedly.

**Why:** In the existing `razorpay_orders` table, `user_id` is `BIGINT`. In the new `user_subscriptions` table, `user_id` is `VARCHAR(128)`. PostgreSQL can auto-cast in some cases but not all (especially in JOINs or WHERE clauses).

**Fix:** Be explicit about casting when joining:

```sql
SELECT * FROM razorpay_orders ro
JOIN user_subscriptions us ON ro.user_id::text = us.user_id;
```

Or, if you control the migration, consider changing `razorpay_orders.user_id` to `VARCHAR(128)` in a future migration to keep types consistent.

---

### Mistake 7: Not handling out-of-order webhooks

**Symptom:** Subscription status jumps around (e.g. goes from `active` back to `authenticated`).

**Why:** Razorpay does not guarantee webhook delivery order. `subscription.charged` might arrive before `subscription.activated`. If your handler blindly sets status from the event name, you could regress the status.

**Fix:** The service code handles this correctly because:
1. `handle_subscription_charged()` always sets status to `active`
2. `handle_subscription_activated()` also sets status to `active`
3. Both paths end at the same status, so order doesn't matter

The only scenario where order matters is if `subscription.cancelled` arrives before a final `subscription.charged`. This is handled by idempotency — the charged handler adds credits regardless of current status (it checks the invoice table, not the subscription status).

---

### Mistake 8: Forgetting LiteLLM budget sync on subscription credits

**Symptom:** Credits show up in the database, but the user can't actually use the AI models.

**Why:** The one-time payment flow calls `update_litellm_budget()` after `add_credits()`. If the subscription flow only calls `add_credits()` without syncing LiteLLM, the user has credits in your DB but their LiteLLM team budget doesn't increase.

**Fix:** The service code in this guide already includes `update_litellm_budget()` in `handle_subscription_charged()`. Verify it's there.

---

## Summary

```
Files created:
  app/migrations/002_subscription_tables.sql   (DB schema)
  app/models/subscription.py                    (Pydantic models)
  app/services/subscription.py                  (Business logic + webhook handlers)
  app/routers/subscription.py                   (HTTP endpoints)

Files modified:
  app/config/app_config.ini                     (new plan ID key)
  app/routers/payment.py                        (webhook extension)
  app/main.py                                   (router mount)

Testing order:
  1. Run migration
  2. Seed plan
  3. Start server
  4. GET /subscriptions/plans          → verify data
  5. POST /subscriptions/subscribe     → get short_url
  6. Complete payment in browser       → webhook fires
  7. Check DB (subscriptions, invoices, credits)
  8. POST /subscriptions/cancel        → verify
  9. Replay webhook                    → verify idempotency
```

---

← [Previous: 08 — Razorpay Subscriptions](./08-razorpay-subscriptions.md)
