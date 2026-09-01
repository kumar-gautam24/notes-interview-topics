# Part 4 — Triggers, Functions, Transactions & Concurrency (PostgreSQL)

---

## 1. Functions and procedures

Postgres has no standalone "stored procedure" language like T-SQL's. You write **functions** (and, since PG11, **procedures**) in PL/pgSQL or plain SQL.

```sql
CREATE OR REPLACE FUNCTION pass_rate(p_course_id bigint)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT round(100.0 * count(*) FILTER (WHERE score >= 60) / NULLIF(count(*), 0), 2)
  FROM exam_attempt
  WHERE course_id = p_course_id AND submitted_at IS NOT NULL;
$$;

SELECT pass_rate(3);
```

PL/pgSQL when you need control flow:

```sql
CREATE OR REPLACE FUNCTION grade_attempt(p_attempt_id bigint)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_score numeric;
  v_grade text;
BEGIN
  SELECT score INTO v_score FROM exam_attempt WHERE attempt_id = p_attempt_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Attempt % not found', p_attempt_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_grade := CASE WHEN v_score >= 80 THEN 'A'
                  WHEN v_score >= 60 THEN 'B'
                  ELSE 'F' END;

  RETURN v_grade;
EXCEPTION
  WHEN division_by_zero THEN
    RAISE WARNING 'unexpected division by zero';
    RETURN NULL;
END;
$$;
```

**`$$` is dollar quoting** — it lets you write a whole function body containing quotes without escaping. You can tag it (`$body$ ... $body$`) when nesting.

### Volatility markers (matters for performance)

| Marker | Meaning |
|---|---|
| `IMMUTABLE` | Same input → same output, forever. Can be used in index expressions. |
| `STABLE` | Constant within one statement (can read tables). Most read-only functions. |
| `VOLATILE` (default) | Anything goes; called once per row, never optimized away. |

### Procedures — the difference that matters

```sql
CREATE PROCEDURE archive_old_attempts()
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM exam_attempt WHERE started_at < now() - interval '3 years';
  COMMIT;   -- functions cannot do this; procedures can
END;
$$;

CALL archive_old_attempts();
```

A function runs inside the caller's transaction and cannot `COMMIT`. A procedure, invoked with `CALL`, can manage transactions — that's the whole point of the distinction.

---

## 2. Triggers

A trigger is code the database runs **automatically** in response to `INSERT` / `UPDATE` / `DELETE` / `TRUNCATE` on a table. The application cannot bypass it, which is exactly why it's useful and exactly why it's dangerous.

In Postgres it's always two objects: a **trigger function** returning type `trigger`, and a **trigger** that binds it to a table.

### The classic: maintain `updated_at`

```sql
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_course_updated_at
BEFORE UPDATE ON course
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
```

### The anatomy

```
CREATE TRIGGER name
  { BEFORE | AFTER | INSTEAD OF }  { INSERT | UPDATE [OF col] | DELETE | TRUNCATE }
  ON table
  [ REFERENCING ... ]
  FOR EACH { ROW | STATEMENT }
  [ WHEN (condition) ]
  EXECUTE FUNCTION fn();
```

| Timing | When it runs | Typical use |
|---|---|---|
| `BEFORE` | Before the row is written | Modify or validate the incoming row |
| `AFTER` | After the row is written | Audit logging, cascading updates to other tables |
| `INSTEAD OF` | Replaces the operation — **views only** | Make a complex view writable |

| Level | Fires |
|---|---|
| `FOR EACH ROW` | Once per affected row |
| `FOR EACH STATEMENT` | Once per statement, even if 0 rows were touched |

### `NEW`, `OLD`, and `TG_OP`

Inside a row-level trigger function you get these automatic variables:

| Variable | INSERT | UPDATE | DELETE |
|---|---|---|---|
| `NEW` | the new row | the new row | **NULL** |
| `OLD` | **NULL** | the pre-update row | the deleted row |
| `TG_OP` | `'INSERT'` | `'UPDATE'` | `'DELETE'` |
| `TG_TABLE_NAME`, `TG_WHEN`, `TG_LEVEL`, `TG_ARGV[]` | metadata about the trigger itself |

### Return value rules — get these wrong and you'll lose data

- **BEFORE ... FOR EACH ROW**: return `NEW` to proceed (with any modifications you made). Return a *different* row to substitute it. **Return `NULL` to silently cancel the operation for that row.**
- **AFTER ... FOR EACH ROW**: the return value is ignored. Return `NULL` by convention.
- **Statement-level triggers**: return value ignored.
- For a `DELETE` trigger, `BEFORE` returns `OLD` to allow the delete, `NULL` to cancel it.

### Full audit-log example

```sql
CREATE TABLE course_audit (
  audit_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  course_id  bigint,
  operation  text NOT NULL,
  old_row    jsonb,
  new_row    jsonb,
  changed_by text NOT NULL DEFAULT current_user,
  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION audit_course()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO course_audit (course_id, operation, new_row)
    VALUES (NEW.course_id, TG_OP, to_jsonb(NEW));
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO course_audit (course_id, operation, old_row, new_row)
    VALUES (NEW.course_id, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;

  ELSE  -- DELETE
    INSERT INTO course_audit (course_id, operation, old_row)
    VALUES (OLD.course_id, TG_OP, to_jsonb(OLD));
    RETURN OLD;
  END IF;
END;
$$;

CREATE TRIGGER trg_course_audit
AFTER INSERT OR UPDATE OR DELETE ON course
FOR EACH ROW EXECUTE FUNCTION audit_course();
```

### The `WHEN` clause — fire only when it matters

```sql
CREATE TRIGGER trg_price_change
AFTER UPDATE ON course
FOR EACH ROW
WHEN (OLD.fee IS DISTINCT FROM NEW.fee)     -- NULL-safe comparison
EXECUTE FUNCTION log_price_change();
```

Much cheaper than firing every time and checking inside the function. Note `IS DISTINCT FROM`, not `<>` — `<>` returns NULL when either side is NULL, so the trigger wouldn't fire.

### Maintaining a denormalized counter

```sql
CREATE OR REPLACE FUNCTION sync_attempt_count()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE course SET attempt_count = attempt_count + 1 WHERE course_id = NEW.course_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE course SET attempt_count = attempt_count - 1 WHERE course_id = OLD.course_id;
  ELSIF NEW.course_id IS DISTINCT FROM OLD.course_id THEN
    UPDATE course SET attempt_count = attempt_count - 1 WHERE course_id = OLD.course_id;
    UPDATE course SET attempt_count = attempt_count + 1 WHERE course_id = NEW.course_id;
  END IF;
  RETURN NULL;
END; $$;

CREATE TRIGGER trg_attempt_count
AFTER INSERT OR UPDATE OR DELETE ON exam_attempt
FOR EACH ROW EXECUTE FUNCTION sync_attempt_count();
```

Warning: this serialises all inserts for a popular course onto one row's lock. Under high concurrency, prefer an insert-only tally table you aggregate periodically.

---

## 3. "Magic tables" — the Postgres answer

**Magic tables** is SQL Server terminology. In T-SQL, a trigger gets two read-only pseudo-tables:

- `inserted` — the new version of affected rows (populated on INSERT and UPDATE)
- `deleted` — the old version (populated on DELETE and UPDATE)

They're set-based: a statement updating 500 rows fires the trigger **once**, with 500 rows in `inserted`. There is no `updated` table — an UPDATE populates both.

Postgres has **no `inserted` / `deleted` tables**. It gives you two mechanisms instead:

### (a) `NEW` / `OLD` — row-level, one row at a time

Covered above. This is the everyday equivalent. Difference in mental model: a T-SQL trigger fires once per *statement* with a set; a Postgres `FOR EACH ROW` trigger fires once per *row* with scalars. Postgres's version is easier to reason about and impossible to get wrong the way people get set-based T-SQL triggers wrong (the classic T-SQL bug is writing a trigger that assumes `inserted` has exactly one row).

### (b) Transition tables — the true set-based equivalent

For statement-level triggers, Postgres has `REFERENCING`, which gives you real relations you can query:

```sql
CREATE OR REPLACE FUNCTION log_bulk_score_changes()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO score_change_log (attempt_id, old_score, new_score, changed_at)
  SELECT n.attempt_id, o.score, n.score, now()
  FROM   new_rows n
  JOIN   old_rows o ON o.attempt_id = n.attempt_id
  WHERE  o.score IS DISTINCT FROM n.score;

  RETURN NULL;
END; $$;

CREATE TRIGGER trg_bulk_score
AFTER UPDATE ON exam_attempt
REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT
EXECUTE FUNCTION log_bulk_score_changes();
```

Mapping:

| SQL Server | PostgreSQL |
|---|---|
| `inserted` | `NEW` (row-level) / `NEW TABLE AS ...` (transition table) |
| `deleted` | `OLD` (row-level) / `OLD TABLE AS ...` |
| INSERT | `NEW` only / `NEW TABLE` only |
| DELETE | `OLD` only / `OLD TABLE` only |
| UPDATE | both |

Restrictions on transition tables: `AFTER` triggers only, not on constraint triggers, and for `UPDATE` triggers you can't also specify a column list (`UPDATE OF col`).

### (c) `RETURNING` — often the better answer

For "I need to see what I just changed", you frequently don't need a trigger at all:

```sql
UPDATE exam_attempt SET score = 0 WHERE started_at < now() - interval '1 day'
                                    AND submitted_at IS NULL
RETURNING attempt_id, agent_id;
```

This is roughly T-SQL's `OUTPUT` clause, and it's the idiomatic Postgres solution when the *application* wants the affected rows.

---

## 4. When NOT to use triggers

Triggers are invisible. Someone debugging your app in six months will not know they exist. Use them for:

- ✅ Audit trails you must not be able to bypass
- ✅ `updated_at` maintenance
- ✅ Denormalized counters/caches with correctness requirements
- ✅ Enforcing rules that span rows or tables and can't be a `CHECK` constraint

Avoid them for:

- ❌ Business logic that belongs in the application (it becomes untestable and hidden)
- ❌ Anything a `CHECK`, `UNIQUE`, `FOREIGN KEY`, `EXCLUDE`, or generated column can do — declarative constraints are faster, clearer, and validated on existing data
- ❌ Calling external services / sending emails — the trigger runs inside the transaction and can be rolled back after the email is sent. Write to an outbox table instead.
- ❌ Chains of triggers that update tables with triggers. Cascades become impossible to reason about and can loop.

Inspect what's there: `\dS+ tablename` in psql, or query `pg_trigger` / `information_schema.triggers`.

---

## 5. Transactions

```sql
BEGIN;
  UPDATE account SET balance = balance - 5000 WHERE account_id = 1;
  UPDATE account SET balance = balance + 5000 WHERE account_id = 2;
COMMIT;   -- or ROLLBACK;
```

Savepoints for partial rollback:

```sql
BEGIN;
  INSERT INTO agent (...) VALUES (...);
  SAVEPOINT sp1;
  INSERT INTO exam_attempt (...) VALUES (...);   -- fails
  ROLLBACK TO SAVEPOINT sp1;                     -- agent insert survives
COMMIT;
```

Postgres quirk worth knowing: after **any** error inside a transaction, the transaction enters an aborted state and every subsequent statement fails with "current transaction is aborted" until you `ROLLBACK` or `ROLLBACK TO SAVEPOINT`. There's no "continue past the error" like SQL Server's default.

---

## 6. Isolation levels and read phenomena

The three classic anomalies:

| Anomaly | What happens |
|---|---|
| **Dirty read** | You read another transaction's uncommitted change |
| **Non-repeatable read** | You read a row twice in one transaction and get different values |
| **Phantom read** | You run the same `WHERE` twice and get a different *set* of rows |

| Level | Dirty | Non-repeatable | Phantom | In Postgres |
|---|---|---|---|---|
| Read Uncommitted | possible | possible | possible | Accepted but **behaves as Read Committed** — Postgres never allows dirty reads |
| **Read Committed** | no | possible | possible | **Default.** Each statement sees a fresh snapshot |
| Repeatable Read | no | no | no* | Snapshot for the whole transaction. Postgres also blocks phantoms here |
| Serializable | no | no | no | Full SSI — transactions behave as if run one after another |

\* Postgres's Repeatable Read is stronger than the SQL standard requires; it prevents phantoms too.

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
...
COMMIT;
```

Trade-off: at Repeatable Read and Serializable, Postgres may abort your transaction with a **serialization failure** (`40001`) rather than block. Your application must catch that error and retry the whole transaction. That retry loop is the price of higher isolation, and forgetting it is a common production bug.

---

## 7. Locking and the concurrency patterns you'll actually need

Postgres uses **MVCC**: readers never block writers, writers never block readers. Only writer-vs-writer on the same row blocks.

### `SELECT ... FOR UPDATE` — pessimistic locking

Reserving the last seat in an exam slot:

```sql
BEGIN;
  SELECT seats_left FROM exam_slot WHERE slot_id = 7 FOR UPDATE;   -- locks the row
  -- no other transaction can update this row until we commit
  UPDATE exam_slot SET seats_left = seats_left - 1 WHERE slot_id = 7;
COMMIT;
```

Variants: `FOR UPDATE SKIP LOCKED` (job-queue workers grab different rows instead of queueing), `FOR UPDATE NOWAIT` (fail immediately instead of waiting), `FOR SHARE` (block writes, allow other readers to lock).

### Optimistic locking — version columns

```sql
UPDATE course SET title = 'New', version = version + 1
WHERE course_id = 3 AND version = 7;
-- 0 rows affected → someone else changed it; show the user a conflict
```

Better for mobile/offline-sync apps than holding a DB lock across a network round trip.

### Deadlocks

Two transactions each hold a lock the other wants. Postgres detects it and kills one with error `40P01`. Prevention: **always acquire locks on multiple rows in a consistent order** (e.g. always by ascending `account_id`), keep transactions short, and don't do network I/O inside one.

---

## 8. Permissions, briefly

```sql
CREATE ROLE app_readonly;
GRANT CONNECT ON DATABASE training TO app_readonly;
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_readonly;
```

`SECURITY DEFINER` on a function makes it run with the *owner's* privileges rather than the caller's — how you let a limited user perform one specific privileged action. Always pin the search path on such functions (`SET search_path = pg_catalog, public`) to avoid injection via schema shadowing.

**SQL injection** — the only correct defence is parameterised queries. Never build SQL with string concatenation:

```sql
-- catastrophic
'SELECT * FROM agent WHERE email = ''' + userInput + ''''
-- correct (client side)
'SELECT * FROM agent WHERE email = $1', [userInput]
```

Inside PL/pgSQL dynamic SQL, use `format()` with `%I` (identifier) and `%L` (literal), or `EXECUTE ... USING`.

---

## 9. Self-check

1. Write a `BEFORE UPDATE` trigger that prevents `score` from ever decreasing.
2. What does returning `NULL` from a `BEFORE ... FOR EACH ROW` trigger do?
3. What is `OLD` during an `INSERT`?
4. What replaces SQL Server's `inserted` table when you need the whole affected set?
5. Which isolation level is Postgres's default, and which anomaly does it still permit?
6. Two workers must each pull a different job from a queue table. Which clause?
