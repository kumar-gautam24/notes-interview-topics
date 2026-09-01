# SQL & PostgreSQL — Complete Learning Guide

From absolute basics to production patterns. Every concept builds on the last.
Run every example in your Postgres console to see it work.

---

## Part 1 — Foundations

### What is SQL?

SQL (Structured Query Language) is how you talk to a relational database. It's declarative — you say **what** you want, not **how** to get it. The database figures out the how.

```sql
-- English: "Give me all users whose email ends with @gmail.com"
SELECT * FROM users WHERE email LIKE '%@gmail.com';
```

Every SQL statement is either:
- **DDL** (Data Definition Language) — defines structure: `CREATE`, `ALTER`, `DROP`
- **DML** (Data Manipulation Language) — manipulates data: `SELECT`, `INSERT`, `UPDATE`, `DELETE`
- **DCL** (Data Control Language) — permissions: `GRANT`, `REVOKE`

---

### Creating a Table

```sql
CREATE TABLE users (
    id         SERIAL      PRIMARY KEY,
    email      TEXT        NOT NULL UNIQUE,
    name       TEXT        NOT NULL,
    age        INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Each column:** `name  type  constraints`

**Types used here:**
- `SERIAL` — auto-incrementing integer (1, 2, 3...)
- `TEXT` — unlimited string
- `INT` — integer number
- `TIMESTAMPTZ` — timestamp with timezone

**Constraints used here:**
- `PRIMARY KEY` — unique + not null, identifies each row
- `NOT NULL` — this column must always have a value
- `UNIQUE` — no two rows can have the same value
- `DEFAULT NOW()` — if not provided, use current timestamp

---

### INSERT — adding rows

```sql
-- insert one row
INSERT INTO users (email, name, age)
VALUES ('john@example.com', 'John', 28);

-- insert multiple rows
INSERT INTO users (email, name, age)
VALUES
    ('jane@example.com', 'Jane', 25),
    ('bob@example.com',  'Bob',  32);

-- insert and get the row back
INSERT INTO users (email, name)
VALUES ('alice@example.com', 'Alice')
RETURNING id, email, created_at;
-- returns: 4 | alice@example.com | 2026-01-01 00:00:00+00
```

**RETURNING** — after inserting, get back the generated values (like `id`, `created_at`). Without it, you'd need a second SELECT to get them.

---

### SELECT — reading rows

Assume this data in the table:

```
id | name    | age | deleted_at
---+---------+-----+------------
1  | Alice   | 30  | NULL
2  | Bob     | 24  | NULL
3  | Charlie | 35  | 2026-01-01
4  | Diana   | 28  | NULL
```

```sql
-- everything
SELECT * FROM users;
-- returns all 4 rows

-- specific columns only
SELECT id, name FROM users;
-- id | name
-- 1  | Alice
-- 2  | Bob
-- 3  | Charlie
-- 4  | Diana

-- with a condition
SELECT * FROM users WHERE age > 25;
-- id | name    | age
-- 1  | Alice   | 30
-- 3  | Charlie | 35
-- 4  | Diana   | 28
-- (Bob excluded — age 24 is not > 25)

-- multiple conditions — both must be true
SELECT * FROM users WHERE age > 25 AND deleted_at IS NULL;
-- id | name  | age
-- 1  | Alice | 30
-- 4  | Diana | 28
-- (Charlie excluded — has deleted_at)

-- OR — either can be true
SELECT * FROM users WHERE age < 25 OR age > 34;
-- id | name    | age
-- 2  | Bob     | 24
-- 3  | Charlie | 35
```

---

### ORDER BY — sorting results

Without ORDER BY, Postgres returns rows in no guaranteed order. It may look consistent but it's not — it changes as data is inserted, updated, or vacuumed.

**Always use ORDER BY when order matters.**

```sql
-- ASC = ascending (smallest first, A→Z, oldest first) — default
SELECT * FROM users ORDER BY age ASC;
-- id | name    | age
-- 2  | Bob     | 24
-- 4  | Diana   | 28
-- 1  | Alice   | 30
-- 3  | Charlie | 35

-- DESC = descending (largest first, Z→A, newest first)
SELECT * FROM users ORDER BY age DESC;
-- id | name    | age
-- 3  | Charlie | 35
-- 1  | Alice   | 30
-- 4  | Diana   | 28
-- 2  | Bob     | 24

-- sort by text — alphabetical
SELECT * FROM users ORDER BY name ASC;
-- Alice, Bob, Charlie, Diana

-- sort by timestamp — newest first (most common for feeds)
SELECT * FROM posts ORDER BY created_at DESC;

-- sort by multiple columns — first by age, then alphabetically within same age
SELECT * FROM users ORDER BY age DESC, name ASC;

-- NULLS LAST — NULLs appear at the end (default in DESC)
SELECT * FROM users ORDER BY deleted_at DESC NULLS LAST;
-- rows with deleted_at values come first, NULLs at the end

-- NULLS FIRST — NULLs appear at the start (default in ASC)
SELECT * FROM users ORDER BY deleted_at ASC NULLS FIRST;
```

**With LIMIT — always pair ORDER BY + LIMIT:**

```sql
-- top 3 oldest users
SELECT * FROM users ORDER BY age DESC LIMIT 3;
-- Charlie (35), Alice (30), Diana (28)

-- pagination: page 1
SELECT * FROM users ORDER BY age DESC LIMIT 2 OFFSET 0;
-- Charlie (35), Alice (30)

-- pagination: page 2
SELECT * FROM users ORDER BY age DESC LIMIT 2 OFFSET 2;
-- Diana (28), Bob (24)
```

Without ORDER BY, LIMIT returns random rows. Different runs may return different results.

---

### NULL — the absent value and its traps

NULL means "unknown" or "not applicable." It is not zero, not empty string, not false. It is the absence of a value.

**The most common mistake — comparing with `=`:**

```sql
-- setup
INSERT INTO users (name, deleted_at) VALUES
    ('Alice', NULL),
    ('Bob', '2026-01-01'),
    ('Charlie', NULL);

-- WRONG — = NULL is never true, not even for NULL values
SELECT * FROM users WHERE deleted_at = NULL;
-- result: 0 rows
-- Why: NULL = NULL evaluates to NULL (unknown), not TRUE
-- SQL treats "unknown" as falsy in WHERE clauses
-- So every row is excluded, even rows where deleted_at IS actually NULL

-- CORRECT
SELECT * FROM users WHERE deleted_at IS NULL;
-- result: Alice, Charlie (the non-deleted rows)

SELECT * FROM users WHERE deleted_at IS NOT NULL;
-- result: Bob (the deleted row)
```

**Why `NULL = NULL` is not `TRUE`:**

Think of NULL as "I don't know." Is "I don't know" equal to "I don't know"? You can't say yes — both are unknown, so the comparison result is also unknown (NULL). SQL's three-valued logic: TRUE, FALSE, NULL.

```sql
SELECT NULL = NULL;     -- result: NULL  (not true!)
SELECT NULL IS NULL;    -- result: true  ← correct check
SELECT NULL != NULL;    -- result: NULL  (not false!)
SELECT NULL = 'hello';  -- result: NULL
SELECT NULL IS NOT NULL; -- result: false
```

**NULL in arithmetic — silently wrong:**

```sql
SELECT 10 + NULL;   -- result: NULL  (not 10!)
SELECT 10 * NULL;   -- result: NULL
SELECT 10 - NULL;   -- result: NULL
```

This is why `vote_count INT NOT NULL DEFAULT 0` matters. If vote_count could be NULL:

```sql
UPDATE posts SET vote_count = vote_count + 1 WHERE id = 1;
-- if vote_count is NULL → NULL + 1 = NULL
-- vote_count stays NULL forever, silently
```

**NULL in aggregates:**

```sql
-- COUNT(*) counts all rows including NULLs
SELECT COUNT(*) FROM users;  -- 3

-- COUNT(column) counts only non-NULL values
SELECT COUNT(deleted_at) FROM users;  -- 1  (only Bob has a value)

-- AVG, SUM, MIN, MAX all ignore NULLs
SELECT AVG(age) FROM users;  -- averages only non-NULL age values
```

**NULL in ORDER BY:**

```sql
-- ASC: NULLs come FIRST by default in Postgres
SELECT * FROM users ORDER BY deleted_at ASC;
-- Alice (NULL), Charlie (NULL), Bob (2026-01-01)

-- DESC: NULLs come LAST by default in Postgres
SELECT * FROM users ORDER BY deleted_at DESC;
-- Bob (2026-01-01), Alice (NULL), Charlie (NULL)

-- control it explicitly
SELECT * FROM users ORDER BY deleted_at ASC NULLS LAST;
-- Bob (2026-01-01), Alice (NULL), Charlie (NULL)
```

**COALESCE — replace NULL with a default:**

```sql
SELECT name, COALESCE(deleted_at::text, 'active') AS status FROM users;
-- Alice   | active
-- Bob     | 2026-01-01
-- Charlie | active
```

**WHERE operators:**

```sql
WHERE age = 28               -- equal (never use = for NULL)
WHERE age != 28              -- not equal
WHERE age > 25               -- greater than
WHERE age >= 25              -- greater than or equal
WHERE age BETWEEN 20 AND 30  -- inclusive range (20 and 30 included)
WHERE name LIKE 'A%'         -- starts with A (% = any characters)
WHERE name LIKE '%ice'       -- ends with ice
WHERE name LIKE '%li%'       -- contains li
WHERE name ILIKE '%alice%'   -- case-insensitive (Postgres only)
WHERE id IN (1, 2, 3)        -- any of these values
WHERE id NOT IN (1, 2, 3)    -- none of these values
WHERE deleted_at IS NULL     -- null check — ALWAYS use IS, never =
WHERE deleted_at IS NOT NULL -- not null check
```

---

### UPDATE — modifying rows

```sql
-- update one field
UPDATE users SET name = 'Jonathan' WHERE id = 1;

-- update multiple fields
UPDATE users SET name = 'Jonathan', age = 29 WHERE id = 1;

-- update all rows (dangerous — always use WHERE)
UPDATE users SET age = age + 1;

-- update and return the modified row
UPDATE users SET name = 'Jonathan'
WHERE id = 1
RETURNING id, name, email;
```

**Always use WHERE with UPDATE.** Without it, every row is updated.

---

### DELETE — removing rows

```sql
-- delete one row
DELETE FROM users WHERE id = 1;

-- delete with condition
DELETE FROM users WHERE created_at < NOW() - INTERVAL '1 year';

-- delete and return deleted rows
DELETE FROM users WHERE id = 1 RETURNING *;
```

**Always use WHERE with DELETE.** Without it, every row is deleted.

---

## Part 2 — Constraints & Integrity

Constraints are rules the database enforces on every write. They're your safety net.

### NOT NULL

```sql
CREATE TABLE posts (
    title TEXT NOT NULL  -- every post must have a title
);

INSERT INTO posts (title) VALUES (NULL);
-- ERROR: null value in column "title" violates not-null constraint
```

### UNIQUE

```sql
CREATE TABLE users (
    email TEXT NOT NULL UNIQUE  -- no duplicate emails
);

INSERT INTO users (email) VALUES ('john@example.com');
INSERT INTO users (email) VALUES ('john@example.com');
-- ERROR: duplicate key value violates unique constraint
```

### CHECK — custom rule

```sql
CREATE TABLE products (
    price    INT NOT NULL CHECK (price > 0),
    discount INT NOT NULL CHECK (discount >= 0 AND discount <= 100)
);

INSERT INTO products (price, discount) VALUES (-10, 50);
-- ERROR: new row violates check constraint "products_price_check"

-- named check (better error messages)
CREATE TABLE posts (
    url  TEXT,
    body TEXT,
    CONSTRAINT url_or_body CHECK (url IS NOT NULL OR body IS NOT NULL)
);
```

### Foreign Key

```sql
CREATE TABLE communities (
    id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL
);

CREATE TABLE posts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    community_id UUID NOT NULL REFERENCES communities(id),
    title        TEXT NOT NULL
);

-- try to insert a post with a non-existent community
INSERT INTO posts (community_id, title)
VALUES ('00000000-0000-0000-0000-000000000000', 'My post');
-- ERROR: insert or update violates foreign key constraint
-- (that community doesn't exist)
```

**ON DELETE behaviour:**
```sql
-- block deletion of parent if children exist
community_id UUID REFERENCES communities(id) ON DELETE RESTRICT

-- delete children when parent deleted
community_id UUID REFERENCES communities(id) ON DELETE CASCADE

-- set to NULL when parent deleted (column must be nullable)
author_id UUID REFERENCES users(id) ON DELETE SET NULL

-- do nothing — children keep the dead reference (rarely useful)
author_id UUID REFERENCES users(id) ON DELETE NO ACTION
```

---

## Part 3 — JOINs

JOINs combine rows from multiple tables based on a condition.

### Setup for examples

```sql
CREATE TABLE users (
    id    INT  PRIMARY KEY,
    name  TEXT NOT NULL
);

CREATE TABLE posts (
    id        INT  PRIMARY KEY,
    author_id INT  REFERENCES users(id),
    title     TEXT NOT NULL
);

INSERT INTO users VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');
INSERT INTO posts VALUES
    (1, 1, 'Alice post 1'),
    (2, 1, 'Alice post 2'),
    (3, 2, 'Bob post'),
    (4, NULL, 'Orphan post');  -- no author
```

### INNER JOIN — only matching rows

```sql
SELECT users.name, posts.title
FROM posts
INNER JOIN users ON posts.author_id = users.id;

-- result:
-- name  | title
-- Alice | Alice post 1
-- Alice | Alice post 2
-- Bob   | Bob post
-- (Orphan post excluded — no matching user)
```

Use when you only want rows that have a match on both sides.

### LEFT JOIN — all rows from left, matching from right

```sql
SELECT users.name, posts.title
FROM posts
LEFT JOIN users ON posts.author_id = users.id;

-- result:
-- name  | title
-- Alice | Alice post 1
-- Alice | Alice post 2
-- Bob   | Bob post
-- NULL  | Orphan post  ← included, user is NULL
```

Use when you want all rows from the left table, even without a match.

### Aliases — cleaner queries

```sql
SELECT u.name, p.title
FROM posts p
JOIN users u ON p.author_id = u.id;
-- same result, less typing
```

### Joining multiple tables

```sql
SELECT u.name, c.slug, p.title
FROM posts p
JOIN users       u ON p.author_id    = u.id
JOIN communities c ON p.community_id = c.id
WHERE p.deleted_at IS NULL
ORDER BY p.created_at DESC;
```

Each `JOIN` adds another table. Chain as many as you need.

---

## Part 4 — Aggregates & Grouping

### Aggregate functions

```sql
SELECT COUNT(*)    FROM posts;                    -- total rows
SELECT COUNT(url)  FROM posts;                    -- rows where url is NOT NULL
SELECT AVG(age)    FROM users;                    -- average
SELECT SUM(vote_count) FROM posts;                -- sum
SELECT MAX(created_at) FROM posts;                -- latest post date
SELECT MIN(created_at) FROM posts;                -- earliest post date
```

### GROUP BY — aggregate per group

```sql
-- count posts per community
SELECT community_id, COUNT(*) as post_count
FROM posts
WHERE deleted_at IS NULL
GROUP BY community_id;

-- result:
-- community_id | post_count
-- abc-123      | 15
-- def-456      | 3
```

### HAVING — filter after grouping

```sql
-- communities with more than 10 posts
SELECT community_id, COUNT(*) as post_count
FROM posts
WHERE deleted_at IS NULL
GROUP BY community_id
HAVING COUNT(*) > 10;
```

**WHERE vs HAVING:**
- `WHERE` filters rows **before** grouping
- `HAVING` filters groups **after** aggregating

---

## Part 5 — Indexes

### Creating an index

```sql
-- basic index
CREATE INDEX users_email_idx ON users(email);

-- unique index (same as UNIQUE constraint)
CREATE UNIQUE INDEX users_email_unique ON users(email);

-- composite index — for queries filtering on multiple columns
CREATE INDEX posts_community_created_idx
    ON posts (community_id, created_at DESC);

-- partial index — only index rows matching a condition
CREATE INDEX posts_live_idx
    ON posts (community_id, created_at DESC)
    WHERE deleted_at IS NULL;
-- smaller index, only covers non-deleted rows
-- perfect for WHERE deleted_at IS NULL queries
```

### When the DB uses an index

```sql
-- these use the index on email:
WHERE email = 'john@example.com'          -- equality
WHERE email > 'j'                         -- range
ORDER BY email                            -- sorting (index is pre-sorted)

-- these do NOT use the index:
WHERE email LIKE '%john%'                 -- leading wildcard
WHERE LOWER(email) = 'john@example.com'  -- function on column
```

**Rule:** if you wrap a column in a function, the index is useless. Use expression indexes for that:
```sql
CREATE INDEX users_email_lower ON users (LOWER(email));
-- now LOWER(email) = '...' uses the index
```

### EXPLAIN ANALYZE — see what's happening

```sql
EXPLAIN ANALYZE
SELECT * FROM posts
WHERE community_id = 'abc-123' AND deleted_at IS NULL
ORDER BY created_at DESC LIMIT 10;
```

Read the output:
```
Index Scan using posts_live_idx  ← good, index used
  rows=10  actual time=0.05ms   ← fast

Seq Scan on posts                ← bad, full table scan
  rows=500000  actual time=250ms ← slow
```

Run this before shipping any list endpoint.

---

## Part 6 — Advanced Queries

### Subqueries

```sql
-- find users who have at least one post
SELECT * FROM users
WHERE id IN (
    SELECT DISTINCT author_id FROM posts WHERE deleted_at IS NULL
);

-- find communities with more posts than average
SELECT * FROM communities
WHERE id IN (
    SELECT community_id
    FROM posts
    GROUP BY community_id
    HAVING COUNT(*) > (SELECT AVG(cnt) FROM (
        SELECT COUNT(*) as cnt FROM posts GROUP BY community_id
    ) sub)
);
```

### CTEs — Common Table Expressions

CTEs (Common Table Expressions) give subqueries a name. Cleaner than nested subqueries. Defined with `WITH`.

```sql
-- same query as above, but readable
WITH post_counts AS (
    SELECT community_id, COUNT(*) as cnt
    FROM posts
    WHERE deleted_at IS NULL
    GROUP BY community_id
),
avg_count AS (
    SELECT AVG(cnt) as avg FROM post_counts
)
SELECT c.*, pc.cnt
FROM communities c
JOIN post_counts pc ON c.id = pc.community_id
JOIN avg_count ac ON pc.cnt > ac.avg;
```

### Recursive CTE — threading/hierarchies

Used for threaded comments (Phase 3). A recursive CTE calls itself.

```sql
-- get all comments in a thread, preserving hierarchy
WITH RECURSIVE comment_tree AS (
    -- base case: top-level comments (no parent)
    SELECT id, parent_id, body, 0 AS depth
    FROM comments
    WHERE post_id = $1 AND parent_id IS NULL AND deleted_at IS NULL

    UNION ALL

    -- recursive case: children of already-found comments
    SELECT c.id, c.parent_id, c.body, ct.depth + 1
    FROM comments c
    JOIN comment_tree ct ON c.parent_id = ct.id
    WHERE c.deleted_at IS NULL
)
SELECT * FROM comment_tree ORDER BY depth, id;
```

---

## Part 7 — Postgres-Specific Features

### UUID generation

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- generate a UUID
SELECT gen_random_uuid();
-- a8098c1a-f86e-11da-bd1a-00112444be1e

-- use as default
CREATE TABLE things (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);
```

### TIMESTAMPTZ vs TIMESTAMP

```sql
-- TIMESTAMP — stores exactly what you give it, no timezone
-- TIMESTAMPTZ — converts to UTC on store, converts to local on read

-- always use TIMESTAMPTZ
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
```

**Why TIMESTAMPTZ:** users in different timezones insert data. If you store bare timestamps, you lose the timezone information. With TIMESTAMPTZ, everything is stored as UTC and displayed in the querying user's timezone. No confusion.

### INTERVAL — time arithmetic

```sql
-- posts from last 7 days
SELECT * FROM posts
WHERE created_at > NOW() - INTERVAL '7 days';

-- posts from last 30 minutes
WHERE created_at > NOW() - INTERVAL '30 minutes';

-- age of each post
SELECT title, NOW() - created_at AS age FROM posts;
```

### COALESCE — handle NULLs gracefully

```sql
-- if bio is NULL, use 'No bio provided' instead
SELECT name, COALESCE(bio, 'No bio provided') AS bio FROM users;

-- first non-null value
SELECT COALESCE(NULL, NULL, 'fallback');
-- result: 'fallback'
```

### UPSERT — INSERT or UPDATE

```sql
-- insert a vote, or update it if it already exists
INSERT INTO votes (user_id, post_id, value)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, post_id)
DO UPDATE SET value = EXCLUDED.value;
-- EXCLUDED = the row that would have been inserted
```

Without UPSERT, you'd need to check if the row exists first (two queries, race condition). UPSERT is atomic.

### Returning from UPDATE and DELETE

```sql
-- update and see what changed
UPDATE posts
SET vote_count = vote_count + 1
WHERE id = $1
RETURNING id, vote_count;

-- soft delete and confirm
UPDATE posts
SET deleted_at = NOW()
WHERE id = $1 AND author_id = $2
RETURNING id, deleted_at;
-- if no row returned → either doesn't exist or not the author
```

### Full-Text Search (Phase 3 preview)

```sql
-- add a search vector column
ALTER TABLE posts ADD COLUMN search_vector TSVECTOR;

-- populate it
UPDATE posts SET search_vector = to_tsvector('english', title || ' ' || COALESCE(body, ''));

-- create a GIN index (fast for FTS)
CREATE INDEX posts_search_idx ON posts USING GIN(search_vector);

-- search
SELECT * FROM posts
WHERE search_vector @@ to_tsquery('english', 'python & tutorial')
ORDER BY ts_rank(search_vector, to_tsquery('english', 'python & tutorial')) DESC;
```

---

## Part 8 — Schema Design Patterns

### The standard table template

Every table in this project follows this pattern:

```sql
CREATE TABLE entities (
    -- identity
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- relationships (FKs)
    parent_id UUID NOT NULL REFERENCES parents(id) ON DELETE CASCADE,
    owner_id  UUID         REFERENCES users(id)    ON DELETE SET NULL,

    -- content
    name TEXT NOT NULL,
    body TEXT,

    -- counters (denormalized for performance)
    count INT NOT NULL DEFAULT 0,

    -- timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,   -- NULL = alive, value = soft deleted

    -- cross-column rules
    CONSTRAINT some_business_rule CHECK (...)
);

-- index for the hot query (list by parent, newest first, live only)
CREATE INDEX entities_parent_created_idx
    ON entities (parent_id, created_at DESC)
    WHERE deleted_at IS NULL;
```

### Composite Primary Key — many-to-many

```sql
-- votes: one vote per user per post
CREATE TABLE votes (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    value   SMALLINT NOT NULL CHECK (value IN (-1, 1)),
    PRIMARY KEY (user_id, post_id)  -- composite PK, no separate id column
);
```

The composite PK automatically prevents duplicate votes and creates an index on `(user_id, post_id)`.

### Denormalization — trading storage for speed

**Normalized** (correct but slow for reads):
```sql
-- to get vote_count, always count the votes table
SELECT COUNT(*) FROM votes WHERE post_id = $1 AND value = 1;
-- minus
SELECT COUNT(*) FROM votes WHERE post_id = $1 AND value = -1;
```

**Denormalized** (slight duplication, fast reads):
```sql
-- store vote_count directly on the post
posts.vote_count INT NOT NULL DEFAULT 0

-- update it when a vote changes
UPDATE posts SET vote_count = vote_count + 1 WHERE id = $1;
```

Risk: `vote_count` can get out of sync with the `votes` table if a bug skips the update. Mitigate with periodic reconciliation jobs. Trade-off: read speed vs write complexity.

---

## Part 9 — Common Mistakes

### 1. `WHERE column = NULL` — always empty

```sql
-- WRONG — never returns rows
SELECT * FROM posts WHERE deleted_at = NULL;

-- CORRECT
SELECT * FROM posts WHERE deleted_at IS NULL;
```

### 2. SELECT * in production

```sql
-- BAD — returns everything, including columns added later
SELECT * FROM users;

-- GOOD — explicit, stable, documents what you need
SELECT id, email, created_at FROM users;
```

If you add a `password_hash` column later, `SELECT *` would return it. Explicit columns are safer.

### 3. No LIMIT on list queries

```sql
-- BAD — returns every row, crashes at scale
SELECT * FROM posts WHERE community_id = $1;

-- GOOD — always paginate
SELECT * FROM posts WHERE community_id = $1 LIMIT $2 OFFSET $3;
```

### 4. String concatenation for queries (SQL injection)

```sql
-- DEADLY — never do this
query = f"SELECT * FROM users WHERE email = '{user_input}'"
# user_input = "' OR '1'='1" → dumps entire users table

-- CORRECT — parameterized queries
await conn.fetch("SELECT * FROM users WHERE email = $1", user_input)
# asyncpg handles escaping, injection impossible
```

### 5. Missing `deleted_at IS NULL` in list queries

```sql
-- BAD — soft-deleted posts appear in results
SELECT * FROM posts WHERE community_id = $1;

-- GOOD
SELECT * FROM posts WHERE community_id = $1 AND deleted_at IS NULL;
```

### 6. Offset pagination breaks at scale

```sql
-- reading page 1000 with 10 items per page
SELECT * FROM posts ORDER BY created_at DESC LIMIT 10 OFFSET 10000;
-- Postgres reads and discards 10,000 rows to get to row 10,001
-- gets slower as page number increases
```

Fix: cursor pagination (Phase 3) — use the last-seen `created_at` as a cursor instead of offset.

---

## Quick Reference

```sql
-- create
CREATE TABLE t (id SERIAL PRIMARY KEY, name TEXT NOT NULL);

-- read
SELECT id, name FROM t WHERE name = 'x' ORDER BY id DESC LIMIT 10 OFFSET 0;

-- create + return
INSERT INTO t (name) VALUES ('x') RETURNING id, name;

-- update + return
UPDATE t SET name = 'y' WHERE id = 1 RETURNING *;

-- soft delete
UPDATE t SET deleted_at = NOW() WHERE id = 1;

-- hard delete
DELETE FROM t WHERE id = 1;

-- upsert
INSERT INTO t (id, name) VALUES (1, 'x')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

-- count
SELECT COUNT(*) FROM t WHERE deleted_at IS NULL;

-- join
SELECT t.name, u.email FROM t JOIN users u ON t.user_id = u.id;

-- aggregate per group
SELECT user_id, COUNT(*) FROM t GROUP BY user_id HAVING COUNT(*) > 5;

-- explain
EXPLAIN ANALYZE SELECT * FROM t WHERE name = 'x';
```
