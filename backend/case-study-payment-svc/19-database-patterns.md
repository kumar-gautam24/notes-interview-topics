# 19 — Database Patterns (how we talk to PostgreSQL)

> This doc covers every database pattern in our codebase: how we connect,
> how we query, how we stay safe, and what to avoid.

---

## Part A — SQLAlchemy Core vs ORM

SQLAlchemy has two modes:

| Mode | What it looks like | When to use |
|------|--------------------|-------------|
| **ORM** | `session.query(User).filter(User.id == 1)` | Large apps with complex relationships |
| **Core** | `connection.execute(text("SELECT * FROM users WHERE id = :id"), {"id": 1})` | Simple apps, full SQL control |

**We use Core** — raw SQL strings with parameterized queries. Why:
- Our queries are straightforward (no 5-table joins)
- We want full control over the SQL (important for PostgreSQL-specific features)
- Less magic, easier to debug

Tradeoff: no automatic schema generation, no relationship loading, no migration tools.
We write SQL by hand and manage migrations ourselves.

---

## Part B — Engine and Connection Pooling

### What the engine does

From `app/utils/db_utils.py`:

```python
from sqlalchemy import create_engine

DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:5432/{DB_NAME}"

engine = create_engine(
    DATABASE_URL,
    pool_size=2,
    max_overflow=0,
    pool_pre_ping=True,
    pool_recycle=1800,
    pool_timeout=30,
    echo=False,
    echo_pool=False,
)
```

The engine is created ONCE at module import time and shared across all requests.
It manages a **connection pool** — a set of reusable database connections.

### Why a connection pool?

Opening a new PostgreSQL connection takes ~50-100ms (TCP handshake + auth).
A pool keeps connections open and reuses them:

```
Without pool:
  Request 1: open → query → close (100ms overhead)
  Request 2: open → query → close (100ms overhead)
  Request 3: open → query → close (100ms overhead)

With pool:
  Request 1: borrow → query → return (0ms overhead)
  Request 2: borrow → query → return (0ms overhead)
  Request 3: borrow → query → return (0ms overhead)
```

### Every parameter explained

| Parameter | Value | What it does |
|-----------|-------|-------------|
| `pool_size=2` | 2 connections | How many connections to keep open permanently. We're a small service — 2 is enough. |
| `max_overflow=0` | 0 extra | How many extra connections to create under load. 0 means never exceed pool_size. |
| `pool_pre_ping=True` | enabled | Before using a connection, send a quick "SELECT 1" to check it's alive. Prevents "connection was closed" errors after DB restarts. |
| `pool_recycle=1800` | 30 minutes | Close and recreate connections older than 30 minutes. Prevents stale connections from accumulating. |
| `pool_timeout=30` | 30 seconds | How long to wait for a free connection. If all 2 are busy for 30s, raise an error instead of hanging forever. |
| `echo=False` | disabled | Don't print every SQL query to stdout (noisy in production). Set to `True` for debugging. |
| `echo_pool=False` | disabled | Don't print pool checkout/checkin events. |

### What happens under load with pool_size=2

```
Request A arrives → gets connection #1
Request B arrives → gets connection #2
Request C arrives → both connections busy → waits (up to 30s)

If A finishes before timeout → C gets connection #1
If 30s passes → C gets TimeoutError
```

With `max_overflow=0`, we NEVER open a third connection. This protects the database
from being overwhelmed, but means we can only handle 2 concurrent queries.

For a payment service, this is fine — most requests are fast (<100ms). If we needed
more concurrency, we'd increase `pool_size` or set `max_overflow=3`.

---

## Part C — Executing Queries

### The two main functions

**`execute_query(sql_query, to_dict=False)`** — for raw SQL without parameters:

```python
def execute_query(sql_query: str, to_dict=False, engine=engine):
    with engine.connect() as connection:
        result = connection.execute(text(sql_query))
        df = pd.DataFrame(result.fetchall(), columns=result.keys())
    if to_dict:
        return df.to_dict(orient='records')
    return df
```

Returns a Pandas DataFrame by default, or `list[dict]` with `to_dict=True`.

**`execute_query_with_params(sql_query, params, to_dict=False)`** — for parameterized queries:

```python
def execute_query_with_params(sql_query: str, params: dict, to_dict=False, engine=engine):
    with engine.connect() as connection:
        result = connection.execute(text(sql_query), params)
        if result.returns_rows:
            df = pd.DataFrame(result.fetchall(), columns=result.keys())
            if to_dict:
                return df.to_dict(orient='records')
            return df
        connection.commit()
        return result.rowcount
```

Key difference: for SELECT queries, it returns data. For INSERT/UPDATE/DELETE,
it commits and returns the number of affected rows.

### How results become dicts

```python
# Database returns:
# | id     | name       | price_paise |
# | abc-1  | Pro Monthly | 39900      |

# result.fetchall() returns: [("abc-1", "Pro Monthly", 39900)]
# result.keys() returns: ["id", "name", "price_paise"]

# Pandas merges them:
df = pd.DataFrame(result.fetchall(), columns=result.keys())
# DataFrame:
#       id        name  price_paise
# 0  abc-1  Pro Monthly        39900

# to_dict(orient='records') gives:
# [{"id": "abc-1", "name": "Pro Monthly", "price_paise": 39900}]
```

This is why every service function calls with `to_dict=True` — we want dicts,
not DataFrames.

---

## Part D — Parameterized SQL (why it matters)

### The wrong way (SQL injection)

```python
# NEVER DO THIS
user_input = "'; DROP TABLE users; --"
sql = f"SELECT * FROM users WHERE name = '{user_input}'"
# Becomes: SELECT * FROM users WHERE name = ''; DROP TABLE users; --'
# Your users table is gone.
```

Our codebase has one instance of this anti-pattern:

```python
# In app/services/payment.py — update_litellm_budget
result = db_utils.execute_query(
    f"SELECT team_id FROM api_users WHERE userid = {user_id}"
)
# If user_id comes from a trusted source (DB), this is less dangerous
# but still bad practice. Don't copy this.
```

### The right way (parameterized queries)

```python
sql = "SELECT * FROM users WHERE name = :name"
execute_query_with_params(sql, {"name": user_input})
```

The database driver sends the SQL template and parameters SEPARATELY. The database
never confuses parameters with SQL commands. Even if `user_input` contains
`'; DROP TABLE users; --`, it's treated as a literal string value.

### Parameter syntax

SQLAlchemy uses `:name` for named parameters:

```python
sql = """
    UPDATE razorpay_orders
    SET status = 'paid',
        razorpay_payment_id = :payment_id,
        updated_at = :now
    WHERE razorpay_order_id = :order_id
      AND status IN ('created', 'failed')
    RETURNING *
"""
params = {
    "payment_id": razorpay_payment_id,
    "order_id": razorpay_order_id,
    "now": datetime.now(timezone.utc).isoformat(),
}
rows = execute_query_with_params(sql, params, to_dict=True)
```

Each `:name` in the SQL matches a key in the params dict.

---

## Part E — SQL Patterns We Use

### 1. INSERT ... RETURNING * (atomic insert + read)

```python
sql = """
    INSERT INTO razorpay_orders
        (id, user_id, razorpay_order_id, amount, currency,
         package_id, credits, status, created_at, updated_at)
    VALUES
        (:id, :user_id, :razorpay_order_id, :amount, :currency,
         :package_id, :credits, :status, :now, :now)
"""
```

Without `RETURNING`: you insert a row, then need a separate SELECT to read it back.
That's two network round trips and a race condition (another process could modify
the row between your INSERT and SELECT).

When we add `RETURNING *`, the INSERT returns the row it just created — one query,
zero race conditions.

### 2. UPDATE ... RETURNING (atomic update + read)

```python
sql = """
    UPDATE razorpay_orders
    SET status = 'paid', razorpay_payment_id = :payment_id, updated_at = :now
    WHERE razorpay_order_id = :order_id
      AND status IN ('created', 'failed')
    RETURNING *
"""
```

This is our **idempotency pattern**. The WHERE clause includes `status IN ('created', 'failed')`.
If the order is already `paid`, the UPDATE matches zero rows and returns nothing.
We check `if not rows: return None` — already processed.

No separate SELECT needed. No race condition between two webhook deliveries.

### 3. ON CONFLICT DO NOTHING (upsert / idempotent insert)

```python
sql = """
    INSERT INTO api_user_credits (user_id, balance, created_at, updated_at)
    VALUES (:user_id, 0, :now, :now)
    ON CONFLICT (user_id) DO NOTHING
"""
```

If the `user_id` already exists (unique constraint), the INSERT silently does nothing.
No error, no exception. Safe to call multiple times.

We use this in `_ensure_user_credits()` — called before every credit operation to
guarantee the row exists.

### 4. GREATEST(value, 0) — safe decrement

```python
sql = """
    UPDATE api_user_credits
    SET balance = GREATEST(balance - :amount, 0), updated_at = :now
    WHERE user_id = :user_id
    RETURNING balance
"""
```

`GREATEST(balance - 100, 0)` means: subtract 100, but never go below 0.

Without `GREATEST`: if balance is 50 and you subtract 100, you get -50. With it,
you get 0. Database-level protection against negative balances.

### 5. Conditional WHERE for idempotency

```python
# Only deduct if balance is sufficient (atomic check-and-update)
sql = """
    UPDATE api_user_credits
    SET balance = balance - :amount, updated_at = :now
    WHERE user_id = :user_id AND balance >= :amount
    RETURNING balance
"""
```

If `balance < amount`, the UPDATE matches zero rows. We check the result:

```python
if not rows:
    return False, get_balance(user_id), None  # insufficient funds
```

This is an **atomic check-and-update**. No race condition between checking the
balance and deducting it.

### 6. CAST for JSON columns

```python
sql = """
    INSERT INTO subscription_plans (... features ...)
    VALUES (... CAST(:features AS jsonb) ...)
"""
params = {"features": json.dumps({"models": ["gpt-4"]})}
```

PostgreSQL needs to know that the string `'{"models":["gpt-4"]}'` should be stored
as JSONB, not as a plain text string. `CAST(:features AS jsonb)` does this conversion.

### 7. Dynamic SET clause

```python
def _update_sub_status(rz_sub_id, status, paid_count_increment=0, cancel_at_cycle_end=None):
    parts = ["status = :status", "updated_at = :now"]
    params = {"rz_sub_id": rz_sub_id, "status": status, "now": now}

    if paid_count_increment:
        parts.append("paid_count = paid_count + :inc")
        params["inc"] = paid_count_increment

    if cancel_at_cycle_end is not None:
        parts.append("cancel_at_cycle_end = :cace")
        params["cace"] = cancel_at_cycle_end

    sql = f"UPDATE user_subscriptions SET {', '.join(parts)} WHERE razorpay_subscription_id = :rz_sub_id"
    execute_query_with_params(sql, params)
```

Build the SET clause dynamically based on which fields need updating. The `f-string`
here is safe because we're only interpolating field names we control (not user input).
The VALUES are still parameterized.

---

## Part F — Transactions

### Two connection styles in our code

**`engine.connect()` — manual commit:**

```python
with engine.connect() as connection:
    result = connection.execute(text(sql), params)
    connection.commit()   # YOU must commit
# If an exception occurs before commit(), changes are rolled back
```

**`engine.begin()` — auto-commit:**

```python
with engine.begin() as connection:
    result = connection.execute(text(sql))
# If the block exits normally, auto-commits
# If an exception occurs, auto-rolls-back
```

### Which we use

Our `execute_query_with_params` uses `engine.connect()` with manual commit.
The `insert_row` and `execute_stmt` helpers use `engine.begin()`.

For most of our service code, we call `execute_query_with_params` which handles
the commit internally.

### Why transactions matter

A transaction groups multiple operations into one atomic unit:

```python
# Without transaction: if step 2 fails, step 1 already happened
update_balance(user_id, -100)     # step 1: deduct credits ✓
record_transaction(user_id, 100)  # step 2: log it ✗ (DB error!)
# Balance deducted but no record — data inconsistency!

# With transaction: either BOTH happen or NEITHER happens
with engine.begin() as conn:
    conn.execute(update_balance_sql)
    conn.execute(record_transaction_sql)
# If either fails, both are rolled back
```

### Our transaction gap

Our `add_credits` function does two separate queries (UPDATE balance + INSERT
transaction) in two separate calls to `execute_query_with_params`. Each gets its
own connection and commit. If the second fails, the balance is updated but the
transaction log is missing.

In practice, INSERT into a log table rarely fails, so this hasn't caused issues.
But for a production payment system, wrapping both in a single transaction would
be safer.

---

## Part G — Pandas Integration

### Why we use Pandas at all

Our `execute_query` and `execute_query_with_params` convert SQL results to Pandas
DataFrames as the default return type:

```python
result = connection.execute(text(sql_query))
df = pd.DataFrame(result.fetchall(), columns=result.keys())
```

This was the original design — some parts of the app (data analysis, batch operations)
use DataFrames directly. For the payment/subscription code, we always pass
`to_dict=True` to get `list[dict]` instead.

### Batch inserts via DataFrame

```python
def insert_df_with_batch_mode(df: pd.DataFrame, table_name: str, batch_size: int):
    records = df.to_dict(orient='records')
    for i in range(0, total_rows, batch_size):
        batch = records[i : i + batch_size]
        insert_batch(table_name, batch)
```

Converts a DataFrame to dicts, then inserts in chunks. Useful for bulk data loads
but not used in the payment/subscription flow.

### DataFrame to dict conversion

```python
def get_dict_from_pdf(df: pd.DataFrame) -> list[dict]:
    return df.to_dict(orient='records')
```

Used in `update_litellm_budget` to convert the SELECT result from a DataFrame
to a list of dicts. The `pdf` in the name is a misnomer — it means "Pandas DataFrame",
not "PDF file".

---

## Part H — Other DB Utilities

### Password hashing (not for payments, but in the utils)

```python
from passlib.hash import pbkdf2_sha256

def encrypt_string(pass_phrase: str) -> str:
    return pbkdf2_sha256.hash(pass_phrase)

def verify_encrypted_string(pass_phrase: str, enc_pass_phrase: str) -> bool:
    return pbkdf2_sha256.verify(pass_phrase, enc_pass_phrase)
```

PBKDF2-SHA256 is a slow hash designed for passwords. "Slow" is intentional — it
makes brute-force attacks expensive.

### Dynamic INSERT statement builder

```python
def get_insert_stmt(table_name: str, col_names: list, return_field: str = None):
    columns_str = ", ".join(col_names)
    values_str = ", ".join([f":{col}" for col in col_names])
    returning_clause = f"RETURNING {return_field}" if return_field else ""
    return f"INSERT INTO {table_name} ({columns_str}) VALUES ({values_str}) {returning_clause};"
```

Generates SQL like:
```sql
INSERT INTO users (name, email) VALUES (:name, :email) RETURNING id;
```

Used by `insert_row` and `insert_batch` for generic inserts.

### Fetch table columns

```python
def fetch_table_columns(table_name: str) -> list:
    query = text("""
        SELECT column_name FROM INFORMATION_SCHEMA.COLUMNS
        WHERE table_name = :table_name ORDER BY ordinal_position
    """)
    ...
```

Queries the database's internal schema to discover column names. Useful for dynamic
operations where you don't know the table structure at write time.

---

## Part I — Common Mistakes

### 1. SQL injection via f-strings

```python
# NEVER — user_id could be malicious
sql = f"SELECT * FROM users WHERE id = {user_id}"

# ALWAYS — parameterized
sql = "SELECT * FROM users WHERE id = :id"
execute_query_with_params(sql, {"id": user_id})
```

### 2. Forgetting to commit

```python
with engine.connect() as conn:
    conn.execute(text("INSERT INTO logs (msg) VALUES ('hello')"))
    # Forgot connection.commit()!
    # The INSERT is silently rolled back when the block exits
```

Our `execute_query_with_params` commits for non-SELECT queries, so this is handled
automatically. But if you write custom code with `engine.connect()`, remember to commit.

### 3. Pool exhaustion

If you open connections without closing them (no `with` block), the pool runs out:

```python
# BAD — connection is never returned to the pool
conn = engine.connect()
result = conn.execute(text("SELECT 1"))
# conn is leaked! Pool has one fewer connection forever.

# GOOD — with block returns connection to pool
with engine.connect() as conn:
    result = conn.execute(text("SELECT 1"))
# Connection returned to pool here
```

### 4. Not handling IntegrityError for unique constraints

```python
# BAD — crashes on duplicate
execute_query_with_params("INSERT INTO invoices (...) VALUES (...)", params)

# GOOD — handle the expected duplicate case
try:
    execute_query_with_params("INSERT INTO invoices (...) VALUES (...)", params)
    return True
except Exception as exc:
    if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
        return False  # expected duplicate, not an error
    raise  # unexpected error, re-raise
```

We use this pattern in `_save_invoice` for idempotent webhook processing.

### 5. Reading stale data (read-then-write race)

```python
# BAD — race condition between check and update
balance = get_balance(user_id)      # reads 100
if balance >= 50:
    update_balance(user_id, -50)    # deducts 50
# Between the read and update, another request could deduct 60!
# Result: balance goes negative.

# GOOD — atomic check-and-update in one query
sql = """
    UPDATE api_user_credits
    SET balance = balance - :amount
    WHERE user_id = :user_id AND balance >= :amount
    RETURNING balance
"""
# If balance < amount, zero rows match and nothing happens.
```

This is the most important pattern in our payment code. Every credit operation
uses atomic SQL instead of read-then-write.

---

## Quick Reference

| Pattern | SQL | Where we use it |
|---------|-----|----------------|
| Parameterized query | `WHERE id = :id` | Every service function |
| Insert + read | `INSERT ... RETURNING *` | `save_order` |
| Atomic update + read | `UPDATE ... RETURNING balance` | `add_credits`, `deduct_credits` |
| Idempotent insert | `ON CONFLICT DO NOTHING` | `_ensure_user_credits` |
| Safe decrement | `GREATEST(balance - :amt, 0)` | `process_refund` |
| Idempotent update | `WHERE status = 'created'` | `mark_order_paid` |
| JSON casting | `CAST(:val AS jsonb)` | `create_plan_and_persist` |
| Dynamic SET | `f"SET {', '.join(parts)}"` | `_update_sub_status` |
| Count | `SELECT COUNT(*) as cnt` | `count_invoices`, `count_transactions` |
| Pagination | `LIMIT :lim OFFSET :off` | `get_invoices`, `get_transactions` |
