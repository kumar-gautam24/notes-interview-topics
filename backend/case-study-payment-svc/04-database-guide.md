# 04 — Database Guide

## Where is the database?

The database is **not inside this repo**. It's a remote PostgreSQL server called `<DB_NAME>` running on Azure. This repo only contains:

- **Connection settings** in `app/config/app_config.ini` (host, user, password, DB name)
- **Migration SQL** in `app/migrations/` (the CREATE TABLE statements)
- **Query code** in `app/services/payment.py` and `app/utils/db_utils.py`

To actually see and query the data, you need a PostgreSQL client connected to the remote server.

---

## How to connect

### Option 1: psql (command line)

```bash
# Install on Mac
brew install libpq
# or
brew install postgresql

# Connect (replace with actual values from app_config.ini [DEV] section)
psql "postgresql://DB_USER:DB_PASSWORD@DB_HOST:5432/DB_NAME"

# Example
psql "postgresql://<DB_USER>:PASSWORD@<DB_HOST>:5432/<DB_NAME>"
```

### Option 2: DBeaver (GUI — recommended for beginners)

1. Download from https://dbeaver.io/
2. New Connection → PostgreSQL
3. Fill in: Host, Port (5432), Database, Username, Password from the INI file
4. Test Connection → if it fails, you likely need VPN

### Reminder

You likely need to be on **VPN or corp network** to reach `DB_HOST`. Ask your team lead.

---

## The 3 payment tables

These are created by `app/migrations/001_payment_tables.sql`:

### Table: `razorpay_orders`

Tracks every payment order from creation to completion.

| Column | Type | What it stores |
|--------|------|---------------|
| `id` | VARCHAR(36) PK | Internal UUID (generated in Python) |
| `user_id` | BIGINT | The user who placed the order |
| `razorpay_order_id` | VARCHAR(64) UNIQUE | Razorpay's order ID (e.g., `order_ABC123`) |
| `razorpay_payment_id` | VARCHAR(64) | Razorpay's payment ID (filled after payment) |
| `amount` | INTEGER | Amount in **paise** (99900 = ₹999) |
| `currency` | VARCHAR(3) | Always `INR` currently |
| `package_id` | VARCHAR(64) | Which credit pack (e.g., `"pro"`) |
| `credits` | INTEGER | How many credits this order gives |
| `status` | VARCHAR(16) | `created` → `paid` → `refunded` (or `failed`) |
| `created_at` | TIMESTAMPTZ | When the order was created |
| `updated_at` | TIMESTAMPTZ | Last status change |

**Lifecycle:**
```
created ──→ paid ──→ refunded
   │
   └──→ failed ──→ refunded
```

### Table: `api_user_credits`

Running credit balance per user. One row per user.

| Column | Type | What it stores |
|--------|------|---------------|
| `user_id` | VARCHAR(128) PK | The user |
| `balance` | INTEGER (≥ 0) | Current credit balance |
| `created_at` | TIMESTAMP | When first created |
| `updated_at` | TIMESTAMP | Last balance change |

The `CHECK (balance >= 0)` constraint prevents negative balances at the database level.

### Table: `razorpay_credit_transactions`

Immutable ledger — every single credit movement is recorded here. Never updated, only inserted.

| Column | Type | What it stores |
|--------|------|---------------|
| `id` | VARCHAR(36) PK | Transaction UUID |
| `user_id` | VARCHAR(128) | The user |
| `amount` | INTEGER | How many credits moved |
| `transaction_type` | VARCHAR(16) | `credit` (added), `debit` (used), `refund` (reversed) |
| `reason` | VARCHAR(128) | Why: `purchase`, `model_usage`, `manual_topup`, `refund`, etc. |
| `reference_id` | VARCHAR(128) | Links to razorpay_payment_id, promo code, etc. |
| `created_at` | TIMESTAMP | When it happened |
| `updated_at` | TIMESTAMP | Same as created (never updated) |

### Other tables the code reads (not created by this service)

| Table | Used by | Purpose |
|-------|---------|---------|
| `api_users` | `update_litellm_budget()` | Looks up `team_id` for a user |
| `dimuser` | `get_user_id_from_email()` | Looks up `userid` by email |

These tables are managed by other services. Don't modify them.

---

## How SQL is executed

All queries go through `app/utils/db_utils.py`. Here's how it works:

### The engine (connection pool)

```python
# Created once when the module loads
engine = create_engine(
    "postgresql://user:pass@host:5432/dbname",
    pool_size=2,       # keep 2 connections ready
    max_overflow=0,    # don't create extra connections
    pool_pre_ping=True, # test connection before using (handles DB restarts)
    pool_recycle=1800,  # replace connections older than 30 minutes
)
```

This is a **connection pool** — instead of opening a new DB connection for every query (slow), it keeps a few connections open and reuses them.

### execute_query_with_params (the main one)

This is what the payment service uses for almost every query:

```python
def execute_query_with_params(sql_query, params, to_dict=False, engine=engine):
    with engine.connect() as connection:
        result = connection.execute(text(sql_query), params)
        if result.returns_rows:
            # SELECT or RETURNING — has data to read
            df = pd.DataFrame(result.fetchall(), columns=result.keys())
            if to_dict:
                return df.to_dict(orient='records')  # → list of dicts
            return df  # → pandas DataFrame
        # INSERT/UPDATE/DELETE without RETURNING
        connection.commit()  # ← THIS saves the change to the database
        return result.rowcount
```

**Key things to understand:**

1. **`text(sql_query)`** — wraps the SQL string so SQLAlchemy can process `:param` placeholders
2. **Parameterized queries** — `:user_id` in SQL + `{"user_id": "123"}` in params. SQLAlchemy replaces them safely (prevents SQL injection). **Never** use f-strings for SQL values.
3. **`returns_rows`** — if the query returns data (SELECT, or INSERT/UPDATE with RETURNING), read it into a DataFrame. Otherwise, commit the change.
4. **`to_dict=True`** — converts DataFrame to `list[dict]`, e.g., `[{"id": "abc", "balance": 1200}]`
5. **`connection.commit()`** — this is where the change actually becomes permanent in the database. Without this, the change would be rolled back when the connection closes.

### How the service calls it

Example — adding credits:
```python
# In app/services/payment.py
sql = """
    UPDATE api_user_credits
    SET balance = balance + :amount, updated_at = :now
    WHERE user_id = :user_id
    RETURNING balance
"""
rows = execute_query_with_params(sql, {
    "amount": 1200,
    "user_id": "123",
    "now": datetime.now(timezone.utc).isoformat(),
}, to_dict=True)
# rows = [{"balance": 2400}]
new_balance = rows[0]["balance"]
```

### The RETURNING pattern

Many queries use `RETURNING *` or `RETURNING balance`:
```sql
UPDATE razorpay_orders
SET status = 'paid', ...
WHERE razorpay_order_id = :order_id AND status IN ('created', 'failed')
RETURNING *
```

This means: "do the UPDATE, then give me back the updated row." It combines UPDATE + SELECT in one query. If no rows matched the WHERE clause, you get an empty result — which is how idempotency works (if status is already 'paid', nothing matches).

---

## How to write a new query

Template:

```python
# 1. Write the SQL with :named parameters
sql = """
    SELECT id, user_id, balance
    FROM api_user_credits
    WHERE user_id = :user_id AND balance >= :min_balance
"""

# 2. Call with params dict and to_dict=True
rows = execute_query_with_params(sql, {
    "user_id": user_id,
    "min_balance": 100,
}, to_dict=True)

# 3. Handle the result
if not rows:
    # No matching rows
    return None
return rows[0]  # First matching row as a dict
```

For INSERT/UPDATE (without RETURNING):
```python
sql = """
    INSERT INTO some_table (id, name, created_at)
    VALUES (:id, :name, :now)
"""
execute_query_with_params(sql, {
    "id": str(uuid.uuid4()),
    "name": "test",
    "now": datetime.now(timezone.utc).isoformat(),
})
# Returns rowcount (integer), change is committed automatically
```

---

## How to add a new table

1. Create a new migration file: `app/migrations/002_your_table.sql`
2. Write the SQL:
```sql
BEGIN;

CREATE TABLE IF NOT EXISTS your_new_table (
    id          VARCHAR(36) PRIMARY KEY,
    user_id     VARCHAR(128) NOT NULL,
    some_field  TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_your_table_user
    ON your_new_table (user_id);

COMMIT;
```
3. Ask your team how to apply it (likely: connect to DEV DB with psql, run `\i app/migrations/002_your_table.sql`)
4. Write service functions that query this table using `execute_query_with_params`

---

## Common pitfalls

### 1. String vs BIGINT user_id

The `razorpay_orders` table has `user_id BIGINT`, but most code passes user_id as a **string**. PostgreSQL silently casts `'123'` to `123` in many cases, but this can break if the user_id is not numeric. Be aware of this inconsistency.

### 2. Forgetting `to_dict=True`

Without it, you get a pandas DataFrame, not a list of dicts. The service code expects dicts:
```python
# Wrong — returns DataFrame
rows = execute_query_with_params(sql, params)
rows[0]["balance"]  # This might work but behaves differently

# Right — returns list of dicts
rows = execute_query_with_params(sql, params, to_dict=True)
rows[0]["balance"]  # Clean dict access
```

### 3. String interpolation in SQL (dangerous)

One place in the codebase does this (in `update_litellm_budget`):
```python
# BAD — vulnerable to SQL injection
result = db_utils.execute_query(f"SELECT team_id FROM api_users WHERE userid = {user_id}")
```

Always use parameterized queries instead:
```python
# GOOD — safe
result = execute_query_with_params(
    "SELECT team_id FROM api_users WHERE userid = :uid",
    {"uid": user_id}, to_dict=True
)
```

### 4. No explicit transactions

Each `execute_query_with_params` call is its own connection + commit. There is no `BEGIN ... COMMIT` wrapping multiple queries. The code relies on **idempotency guards** (WHERE clauses) instead of database transactions.

---

## Next doc

→ [05 - Config and Environments](./05-config-and-environments.md) — how configuration works
