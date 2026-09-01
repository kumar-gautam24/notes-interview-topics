# Part 2 — Types, Tables, Constraints, Casting & Indexes (PostgreSQL)

---

## 1. Data types — choose deliberately

### Text: `varchar` vs `text` vs `char` — and where `nvarchar` went

This is the first thing that trips up anyone arriving from SQL Server, so here it is straight.

| Type | Postgres behaviour |
|---|---|
| `text` | Unlimited length. **The default choice.** |
| `varchar(n)` | Identical storage to `text`, plus a length check. Errors if input exceeds `n`. |
| `varchar` (no n) | Exactly the same as `text`. |
| `char(n)` | **Blank-padded** to `n`. `'ab'` stored in `char(5)` comes back as `'ab   '`. Avoid it. |

Critical difference from SQL Server: in Postgres, **`varchar(n)` is not faster or smaller than `text`.** All three use the same variable-length storage. `varchar(n)` buys you *validation only*. Use `varchar(n)` when the limit is a real business rule (`varchar(10)` for a PAN, `varchar(15)` for a GSTIN) and `text` otherwise.

**`NVARCHAR` does not exist in Postgres, and you don't need it.** The reason SQL Server has both:

| | SQL Server | Postgres |
|---|---|---|
| `VARCHAR` | 1 byte/char, limited to a collation's codepage — non-Latin text becomes `?` | — |
| `NVARCHAR` | UTF-16, 2 bytes/char, stores any Unicode | — |
| `text`/`varchar` | — | Encoding is set **per database** (`UTF8` in practice). Every string column stores full Unicode already. |

So Devanagari, emoji, Tamil, Chinese all go into a plain `text` column with no prefix and no special declaration. Check your database encoding once with `SHOW server_encoding;` — if it says `UTF8`, you're done. (Postgres also has no `NCHAR`/`NTEXT`; and its old `text`-adjacent types like `TEXT` in SQL Server are unrelated.)

Bonus type: `citext` (extension) — case-insensitive text. Perfect for emails so `Ravi@x.com` and `ravi@x.com` collide on a `UNIQUE` constraint.

### Numbers

| Type | Use for |
|---|---|
| `smallint` / `integer` / `bigint` | Counts, ids. `int` = ±2.1 billion — fine until it isn't; use `bigint` for PKs. |
| `numeric(p,s)` | **Money, always.** Exact decimal arithmetic. `numeric(12,2)` = 12 total digits, 2 after the point. |
| `real` / `double precision` | Scientific/approximate values. **Never money.** |
| `GENERATED ALWAYS AS IDENTITY` | The modern auto-increment. Prefer over `serial`. |

Why never `float` for money: `0.1 + 0.2` in binary floating point is `0.30000000000000004`. Run `SELECT 0.1::float8 + 0.2::float8 = 0.3;` — it returns `false`. Financial reconciliation with that is a career-limiting move.

`serial` vs `identity`: `serial` is a legacy shorthand that creates a sequence and a default. `GENERATED ALWAYS AS IDENTITY` is SQL-standard, owns its sequence properly, and blocks accidental manual inserts into the id column. Use identity in new code.

### Dates and times

| Type | Notes |
|---|---|
| `timestamptz` | **Default choice.** Stores an absolute instant (UTC internally), converts to the session's timezone on read. |
| `timestamp` | No timezone. Means "wall clock somewhere" — ambiguous. Avoid unless you genuinely mean a local wall time. |
| `date` | Date only. Birthdays, policy start dates. |
| `time` / `timetz` | Time only; `timetz` is nearly useless. |
| `interval` | A duration. `now() - created_at` yields an interval. |

For a mobile app with users across timezones, `timestamptz` + storing everything in UTC + formatting on the client is the correct architecture.

### Others worth knowing

- `boolean` — `true/false/NULL`. Don't emulate with `char(1) 'Y'/'N'`.
- `uuid` — 16 bytes, native type. Don't store UUIDs as `text` (36 bytes + slower comparison).
- `jsonb` — binary JSON, indexable with GIN, supports `->`, `->>`, `@>`. Use for genuinely schemaless payloads. `json` (non-b) just stores raw text — almost always use `jsonb`.
- `text[]` — arrays. Handy, but a junction table is usually the right answer.
- `enum` — `CREATE TYPE policy_status AS ENUM ('draft','active','lapsed')`. Fast and self-documenting, but adding a value requires `ALTER TYPE` and removing one is painful. A small lookup table is more flexible; enums are fine for stable sets.
- Range types — `daterange`, `tstzrange`, `int4range`. Enable exclusion constraints (below).

---

## 2. Casting — `CAST`, `::`, and what happened to `CONVERT`

Postgres gives you two spellings of the same thing:

```sql
SELECT CAST('2026-03-01' AS date);   -- SQL standard
SELECT '2026-03-01'::date;           -- Postgres shorthand, identical
SELECT CAST(score AS numeric(5,2)) FROM exam_attempt;
SELECT '42'::int + 8;                -- 50
```

**`CONVERT` in Postgres is not SQL Server's `CONVERT`.** In Postgres, `convert(bytea, src_encoding, dest_encoding)` changes *character encodings of binary data*. It has nothing to do with type conversion. If you write `CONVERT(varchar, getdate(), 103)` out of T-SQL habit, you'll get an error.

The Postgres equivalent of `CONVERT`'s style codes is **`to_char` / `to_date` / `to_timestamp` / `to_number`**:

```sql
SELECT to_char(now(), 'DD/MM/YYYY');            -- '01/09/2026'
SELECT to_char(now(), 'DD Mon YYYY HH24:MI');   -- '01 Sep 2026 14:30'
SELECT to_date('01/09/2026', 'DD/MM/YYYY');     -- date
SELECT to_timestamp('01-09-2026 14:30', 'DD-MM-YYYY HH24:MI');
SELECT to_char(1234567.891, 'FM999,999,999.00'); -- '1,234,567.89'
```

### Safe casting

A bad cast throws and aborts the statement:

```sql
SELECT 'abc'::int;   -- ERROR: invalid input syntax for type integer
```

Guard it:

```sql
-- Postgres 16+ has a built-in
SELECT pg_input_is_valid('abc', 'integer');   -- false

-- Portable guard for older versions
SELECT CASE WHEN raw_score ~ '^\d+$' THEN raw_score::int END FROM staging;
```

### Implicit vs explicit

Postgres is stricter than SQL Server about implicit casts, which is a feature — it stops silent wrong answers. Things to know:

```sql
SELECT 5 / 2;              -- 2   (integer division!)
SELECT 5.0 / 2;            -- 2.5
SELECT 5::numeric / 2;     -- 2.5
SELECT 'a' || 5;           -- 'a5'  (|| is string concat, not +)
```

`||` is concatenation, and `+` on strings is an error. Also: `||` with any `NULL` operand returns `NULL` — use `concat()` (which skips NULLs) or `coalesce()`.

---

## 3. Creating tables

```sql
CREATE TABLE course (
  course_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code          varchar(20) NOT NULL,
  title         text        NOT NULL,
  fee           numeric(10,2) NOT NULL DEFAULT 0 CHECK (fee >= 0),
  duration_mins integer     NOT NULL CHECK (duration_mins BETWEEN 5 AND 600),
  status        text        NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft','published','retired')),
  metadata      jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_course_code UNIQUE (code)
);
```

Column-level vs table-level constraints: identical in effect. Use table-level when the constraint spans multiple columns, or when you want to name it explicitly (you do — named constraints give readable error messages your app can pattern-match).

### The five constraint types

| Constraint | Enforces |
|---|---|
| `NOT NULL` | Value must be present |
| `UNIQUE` | No duplicates (multiple NULLs *are* allowed — NULL ≠ NULL) |
| `PRIMARY KEY` | `UNIQUE` + `NOT NULL`, one per table |
| `FOREIGN KEY` | Value exists in the referenced table |
| `CHECK` | Any boolean expression over the row's own columns |

Plus Postgres-specific: **`EXCLUDE`** — a generalised UNIQUE. This prevents two overlapping premium periods for the same policy, which no other constraint can express:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE policy_premium (
  policy_id bigint NOT NULL REFERENCES policy(policy_id),
  amount    numeric(12,2) NOT NULL,
  validity  daterange NOT NULL,
  EXCLUDE USING gist (policy_id WITH =, validity WITH &&)
);
```

### Generated columns

Computed and stored automatically; you can index them.

```sql
line_total numeric(12,2) GENERATED ALWAYS AS (qty * unit_price) STORED
```

---

## 4. Foreign keys and referential actions

```sql
CREATE TABLE exam_attempt (
  attempt_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  agent_id   bigint NOT NULL REFERENCES agent(agent_id)   ON DELETE RESTRICT,
  course_id  bigint NOT NULL REFERENCES course(course_id) ON DELETE RESTRICT,
  started_at timestamptz NOT NULL DEFAULT now(),
  submitted_at timestamptz,
  score      numeric(5,2) CHECK (score BETWEEN 0 AND 100),

  CONSTRAINT chk_attempt_window CHECK (submitted_at IS NULL OR submitted_at >= started_at)
);
```

`ON DELETE` options:

| Action | Effect when the parent row is deleted |
|---|---|
| `NO ACTION` (default) | Error — but the check is deferred to end of statement |
| `RESTRICT` | Error immediately, cannot be deferred |
| `CASCADE` | Delete the child rows too |
| `SET NULL` | Set the FK column to NULL (column must be nullable) |
| `SET DEFAULT` | Set to the column default |

Rule of thumb: `CASCADE` when the child cannot exist without the parent and has no independent value (`attempt_question` under `exam_attempt`). `RESTRICT` for anything financial or auditable — you want the delete to fail loudly. `SET NULL` for optional links like `employee.manager_id`.

`ON UPDATE CASCADE` matters only if PKs change — with surrogate keys they never do, which is exactly why surrogates are preferred.

**Postgres does not auto-index foreign keys.** This is the #1 real-world performance bug from developers coming from SQL Server. Every FK column needs its own index (see §6), otherwise every parent delete does a sequential scan of the child table.

### Deferrable constraints

For circular references or bulk loads:

```sql
ALTER TABLE a ADD CONSTRAINT fk_a_b FOREIGN KEY (b_id) REFERENCES b(b_id)
  DEFERRABLE INITIALLY IMMEDIATE;

BEGIN;
  SET CONSTRAINTS fk_a_b DEFERRED;   -- checked at COMMIT, not per statement
  ...
COMMIT;
```

---

## 5. `ALTER`, `DROP`, `TRUNCATE`

```sql
ALTER TABLE course ADD COLUMN language text NOT NULL DEFAULT 'en';
ALTER TABLE course ALTER COLUMN title TYPE varchar(300);
ALTER TABLE course ALTER COLUMN fee SET NOT NULL;
ALTER TABLE course ALTER COLUMN fee DROP DEFAULT;
ALTER TABLE course RENAME COLUMN title TO course_title;
ALTER TABLE course ADD CONSTRAINT chk_fee CHECK (fee >= 0);
ALTER TABLE course DROP CONSTRAINT chk_fee;
ALTER TABLE course DROP COLUMN language;
```

**`DELETE` vs `TRUNCATE` vs `DROP`** — a guaranteed interview question:

| | `DELETE FROM t` | `TRUNCATE t` | `DROP TABLE t` |
|---|---|---|---|
| Type | DML | DDL | DDL |
| Removes | Rows matching `WHERE` | All rows | Rows + table definition |
| `WHERE` clause | Yes | No | No |
| Speed on large tables | Slow (row by row, writes WAL per row) | Very fast | Fast |
| Fires row triggers | Yes | No (only `TRUNCATE` triggers) | No |
| Resets identity | No | Optionally, with `RESTART IDENTITY` | N/A |
| Transactional in Postgres | Yes | **Yes** | **Yes** |

That last row is the Postgres-specific point worth making — you can `BEGIN; TRUNCATE t; ROLLBACK;` and get your data back, unlike in some other engines.

Production safety: adding a `NOT NULL` column *with a non-volatile default* is a fast metadata-only change in modern Postgres. Adding a `CHECK` constraint rewrites/scans the table and takes a strong lock — use `NOT VALID` then `VALIDATE CONSTRAINT` to avoid a long outage:

```sql
ALTER TABLE big ADD CONSTRAINT chk_x CHECK (x > 0) NOT VALID;
ALTER TABLE big VALIDATE CONSTRAINT chk_x;   -- weaker lock, scans concurrently
```

---

## 6. Indexes

An index is a separate sorted structure that lets the engine find rows without scanning the whole table. It costs disk and slows down writes. That's the trade.

### Index types

| Type | Use for |
|---|---|
| **B-tree** (default) | `=`, `<`, `>`, `BETWEEN`, `ORDER BY`, `LIKE 'abc%'`. 95% of cases. |
| **GIN** | `jsonb` containment, arrays, full-text search |
| **GiST** | Geometric data, ranges, exclusion constraints, fuzzy text |
| **BRIN** | Huge tables where rows are physically ordered by the column (time-series `created_at`). Tiny index, coarse. |
| **Hash** | Only `=`. Rarely worth it over B-tree. |

### What to index

1. Every **foreign key column** (Postgres won't do it for you).
2. Columns in `WHERE`, `JOIN ... ON`, `ORDER BY`, `GROUP BY`.
3. **Not** low-cardinality columns alone (`is_active`, `gender`) — a scan is cheaper. Use them in *partial* indexes instead.

### Composite indexes and the leftmost-prefix rule

```sql
CREATE INDEX idx_attempt_agent_started ON exam_attempt (agent_id, started_at DESC);
```

This index serves:
- `WHERE agent_id = 5` ✅
- `WHERE agent_id = 5 ORDER BY started_at DESC` ✅ (no sort step at all)
- `WHERE started_at > '2026-01-01'` ❌ — can't skip the leading column efficiently

Order columns: equality predicates first, then range/sort columns.

### Partial and expression indexes

```sql
-- Only index the rows you actually query
CREATE INDEX idx_attempt_pending ON exam_attempt (agent_id)
  WHERE submitted_at IS NULL;

-- Index a transformation, so the query can use it
CREATE INDEX idx_agent_lower_email ON agent (lower(email));
-- serves: WHERE lower(email) = 'ravi@x.com'
```

Critical rule: **a function on the indexed column in your `WHERE` clause kills a plain index.** `WHERE lower(email) = ?` cannot use `idx_agent_email`; `WHERE created_at::date = '2026-09-01'` cannot use an index on `created_at`. Rewrite as a range instead:

```sql
WHERE created_at >= '2026-09-01' AND created_at < '2026-09-02'
```

### Covering indexes

```sql
CREATE INDEX idx_attempt_cover ON exam_attempt (agent_id) INCLUDE (score);
```

`INCLUDE` columns aren't searchable but let the query be answered from the index alone (index-only scan) without touching the table.

### Building without downtime

```sql
CREATE INDEX CONCURRENTLY idx_x ON t (col);   -- doesn't block writes; can't run inside a transaction
```

### Reading a plan

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM exam_attempt WHERE agent_id = 42;
```

What to look for:
- `Seq Scan` on a large table with a selective filter → missing index.
- Big gap between `rows=` (estimate) and `actual rows=` → stale statistics; run `ANALYZE tablename`.
- `Nested Loop` with a huge outer row count → usually a missing index on the inner side.
- Join strategies: **Nested Loop** (small outer set), **Hash Join** (large unsorted sets, builds a hash table), **Merge Join** (both inputs already sorted).

Maintenance vocabulary: `VACUUM` reclaims space from dead rows left by `UPDATE`/`DELETE` (Postgres uses MVCC — an update writes a new row version rather than editing in place); `ANALYZE` refreshes planner statistics; autovacuum does both in the background.

---

## 7. Self-check

1. Why is `varchar(50)` not faster than `text` in Postgres?
2. A column must hold Hindi and English. Which type, and do you need anything special?
3. Write the Postgres equivalent of `CONVERT(varchar, my_date, 103)`.
4. You delete a parent row and it takes 40 seconds. What's the likely cause?
5. Query is `WHERE lower(name) = 'ravi'` and there's an index on `name`. Is it used? What do you do?
6. When does `TRUNCATE` fire your row-level triggers?
