# Database Concepts — From Zero to Production

A complete mental model for how databases work, why they exist, and how to think about them correctly. Start here before touching SQL.

---

## 1. What is a Database?

A database is a program that stores data durably and lets you retrieve it reliably.

"Durably" means: if the server crashes, the data is still there when it restarts. This is the fundamental promise that separates a database from storing data in a Python list or a file.

"Reliably" means: you can find specific data efficiently even when there are millions of rows.

### Why not just use a file?

```
# naive approach — store users in a text file
john,john@example.com,password123
jane,jane@example.com,secret456
```

Problems:
- Finding user by email = read every line until you find it (slow with 1M users)
- Two requests writing at the same time = corruption
- Server crashes mid-write = half-written data
- No way to enforce "email must be unique"

A database solves all of these. It's not magic — it's a carefully engineered program that handles these problems so you don't have to.

---

## 2. Relational Databases — the core idea

Data is stored in **tables** (like spreadsheets). Each table has columns (fields) and rows (records).

```
users table:
┌──────────────────────────────────┬───────────────────┬──────────────┐
│ id                               │ email             │ created_at   │
├──────────────────────────────────┼───────────────────┼──────────────┤
│ 9013b019-6a8d-4e5d-8fca-...     │ john@example.com  │ 2026-01-01   │
│ ed4e0187-052d-4a7c-b381-...     │ jane@example.com  │ 2026-01-02   │
└──────────────────────────────────┴───────────────────┴──────────────┘
```

The "relational" part: tables can **relate** to each other. A `posts` table has a `user_id` column that points to a row in `users`. This is a **foreign key** — a link between tables.

```
posts table:
┌──────────┬────────────────────────────┬─────────────────┐
│ id       │ author_id                  │ title           │
├──────────┼────────────────────────────┼─────────────────┤
│ post-1   │ 9013b019-... (= john)      │ Hello world     │
│ post-2   │ ed4e0187-... (= jane)      │ My first post   │
└──────────┴────────────────────────────┴─────────────────┘
```

Instead of duplicating John's email in every post, you store his ID once. When you need both, you **JOIN** the tables.

---

## 3. ACID — the four guarantees

Every serious database guarantees ACID. This is what makes them trustworthy.

### Atomicity — all or nothing

A transaction is a group of operations that either all succeed or all fail. No partial state.

```
Transfer $100 from Alice to Bob:
  1. Subtract $100 from Alice
  2. Add $100 to Bob

Without atomicity: step 1 succeeds, server crashes, step 2 never runs.
Alice lost $100. Bob got nothing. Money vanished.

With atomicity: both steps commit together, or neither does.
```

In SQL: wrap operations in `BEGIN` / `COMMIT`. If anything fails, `ROLLBACK` undoes everything.

### Consistency — rules are always enforced

The database enforces constraints before committing. If your data would violate a rule (unique email, non-null field, foreign key), the transaction is rejected.

```
INSERT INTO users (email) VALUES ('john@example.com');
-- already exists → UNIQUE violation → rejected → no partial state
```

Your data is always in a valid state. Even if your app has a bug, the DB enforces the contract.

### Isolation — concurrent transactions don't interfere

Multiple requests running simultaneously don't see each other's in-progress work.

```
Request A: reads vote_count = 10
Request B: reads vote_count = 10
Request A: writes vote_count = 11
Request B: writes vote_count = 11  ← should be 12, not 11!
```

This is a **race condition**. Isolation levels control how the DB handles this. At the strictest level (Serializable), transactions run as if they were sequential.

### Durability — committed data survives crashes

Once the DB says "committed," the data is on disk. A power outage immediately after won't lose it.

The DB achieves this with a **Write-Ahead Log (WAL)** — every change is written to a log file first, then applied. On restart after a crash, the log is replayed.

---

## 4. Connection Pool — how apps talk to the DB

Opening a database connection is expensive (~50ms, involves network handshake, auth, memory allocation). For a web app serving 100 requests/sec, opening a connection per request = 5 seconds of overhead per second. Impossible.

**Solution: connection pool** — open N connections at startup, reuse them.

```
App starts → pool opens 10 connections to Postgres
                         ┌─────────────┐
Request A arrives   →    │ connection 1 │ ← checked out, used, returned
Request B arrives   →    │ connection 2 │ ← checked out, used, returned
Request C arrives   →    │ connection 3 │ ← checked out, used, returned
...
                         │ connection 4 │ ← idle, waiting
                         │ connection 5 │ ← idle, waiting
                         └─────────────┘
```

Each request checks out a connection, runs its queries, returns the connection. The connection itself is never closed — just reused.

**Pool sizing:**
- `min_size` — always keep this many connections alive
- `max_size` — never open more than this many
- Rule of thumb: `(2 × CPU cores) + 1`

**What happens when pool is full?** New requests wait. If they wait too long, they timeout. This is connection pool exhaustion — a sign your queries are too slow or pool is too small.

---

## 5. Indexes — how the DB finds things fast

Without an index, finding a row requires reading every row in the table. For a table with 1 million rows, that's 1 million reads — called a **sequential scan** or **full table scan**.

An index is a separate data structure (usually a B-tree) that lets the DB jump directly to matching rows.

```
Without index — find user by email:
Scan row 1: email = 'alice@...' ← not it
Scan row 2: email = 'bob@...'   ← not it
...
Scan row 847,293: email = 'john@...' ← found! (847,293 reads)

With index on email:
Binary search in B-tree → found at position 847,293 (20 reads)
```

**B-tree index** — the default. Good for equality (`=`) and range (`>`, `<`, `BETWEEN`) queries. Keeps data sorted so binary search works.

**When the DB uses the index:**
```sql
SELECT * FROM users WHERE email = 'john@example.com';  -- uses index ✓
SELECT * FROM users WHERE email LIKE '%john%';          -- can't use index ✗ (starts with wildcard)
SELECT * FROM users ORDER BY email;                     -- uses index ✓ (already sorted)
```

**Indexes are not free:**
- Every INSERT, UPDATE, DELETE must also update the index
- Indexes take disk space
- Too many indexes slow down writes more than they speed up reads

**Rule:** index columns you filter or sort by in hot queries. Don't index everything.

---

## 6. Primary Key vs Foreign Key

**Primary key** — uniquely identifies a row. Every table has one. Cannot be NULL, must be unique.

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY  -- no two rows can have the same id
);
```

**Foreign key** — a column that references a primary key in another table. Enforces that the referenced row actually exists.

```sql
CREATE TABLE posts (
    author_id UUID REFERENCES users(id)
    -- can't insert a post with an author_id that doesn't exist in users
);
```

**What happens when the referenced row is deleted?**

```sql
-- Option 1: block the delete (safe, explicit)
author_id UUID REFERENCES users(id) ON DELETE RESTRICT

-- Option 2: delete children too (cascade)
author_id UUID REFERENCES users(id) ON DELETE CASCADE

-- Option 3: set to NULL (orphan the child, keep it alive)
author_id UUID REFERENCES users(id) ON DELETE SET NULL
-- (column must be nullable for this to work)
```

**Choosing:**
- Author deleted → post still has value → `SET NULL`
- Community deleted → posts inside it are meaningless → `CASCADE`
- User deleted → should be prevented until they're not referenced → `RESTRICT`

---

## 7. NULL — the absent value

`NULL` means "unknown" or "not applicable." It is not zero, not empty string, not false.

**NULL arithmetic breaks silently:**
```sql
SELECT 10 + NULL;   -- result: NULL (not 10!)
SELECT NULL = NULL; -- result: NULL (not true!)
SELECT NULL IS NULL; -- result: true ← correct way to check
```

This is why `vote_count INT NOT NULL DEFAULT 0` matters. If `vote_count` were nullable, `vote_count + 1` could silently return `NULL` when it's `NULL`.

**Filtering NULL:**
```sql
-- WRONG — always returns no rows even when deleted_at is NULL
WHERE deleted_at = NULL

-- CORRECT
WHERE deleted_at IS NULL
WHERE deleted_at IS NOT NULL
```

---

## 8. Transactions in Practice

```sql
BEGIN;

UPDATE accounts SET balance = balance - 100 WHERE id = 'alice';
UPDATE accounts SET balance = balance + 100 WHERE id = 'bob';

-- if both succeed:
COMMIT;

-- if anything fails:
ROLLBACK;  -- both updates undone
```

In asyncpg:
```python
async with conn.transaction():
    await conn.execute("UPDATE accounts SET balance = balance - 100 WHERE id = $1", alice_id)
    await conn.execute("UPDATE accounts SET balance = balance + 100 WHERE id = $1", bob_id)
# auto-commits if no exception, auto-rollbacks if exception
```

**Nested transactions** — Postgres supports savepoints (partial rollback within a transaction), but for most use cases a flat transaction is enough.

---

## 9. Soft Delete vs Hard Delete

**Hard delete:**
```sql
DELETE FROM posts WHERE id = $1;
-- row is gone forever
```

**Soft delete:**
```sql
ALTER TABLE posts ADD COLUMN deleted_at TIMESTAMPTZ;

-- "delete"
UPDATE posts SET deleted_at = NOW() WHERE id = $1;

-- query live posts
SELECT * FROM posts WHERE deleted_at IS NULL;
```

**Why soft delete?**
- Audit trail — you know when and can restore
- Referential integrity — other tables may reference this row
- Business requirement — "deleted" posts can be restored by moderators
- Analytics — count total posts created, not just current

**Why hard delete?**
- Privacy (GDPR) — you must truly erase personal data on request
- Storage — soft-deleted rows accumulate forever
- Complexity — every query must add `WHERE deleted_at IS NULL`

**In this project:** posts and comments use soft delete. Users should eventually support hard delete for GDPR compliance.

---

## 10. UUID vs Auto-increment Integer

**Auto-increment (SERIAL/BIGSERIAL):**
```sql
id SERIAL PRIMARY KEY  -- 1, 2, 3, 4, ...
```
- Simple, small (4 bytes)
- Sequential — B-tree index stays compact, writes are fast
- Enumerable — attacker can try `/posts/1`, `/posts/2`...
- Requires DB round-trip to generate

**UUID:**
```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid()
```
- 16 bytes
- Random — not guessable, not enumerable
- Generate anywhere without DB (in app, in tests, in workers)
- Random inserts fragment B-tree index over time (worse write performance at scale)

**UUIDv7 (time-ordered):** newer standard, combines timestamp + random. Sequential enough to avoid B-tree fragmentation, random enough to prevent enumeration. Best of both — not yet standard in all tools.

**Rule:** use UUID for user-facing IDs. Sequential IDs are fine for internal join tables.

---

## 11. Schema Migrations

The database schema (tables, columns, indexes) changes over time as your app evolves. Migrations are versioned scripts that apply changes one at a time.

```
001_init_users.sql        — creates users table
002_communities.sql       — creates communities table
003_posts.sql             — creates posts table
004_add_user_bio.sql      — adds bio column to users
```

**Rules:**
- Migrations are append-only. Never edit a migration that's been applied to prod.
- Each migration should be idempotent where possible (`CREATE TABLE IF NOT EXISTS`)
- Migrations run in a transaction — failure = rollback, no partial state
- Run migrations before deploying new code, never on server startup

**Why not ORM auto-migrations?** They hide what's happening. A migration that drops a column or changes a type can destroy data. Knowing your SQL means knowing exactly what runs.

---

## 12. EXPLAIN ANALYZE — understanding query performance

`EXPLAIN ANALYZE` runs the query and shows how Postgres executed it — which indexes it used, how many rows it scanned, how long each step took.

```sql
EXPLAIN ANALYZE
SELECT * FROM posts
WHERE community_id = 'abc' AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 10;
```

Output to look for:
```
Seq Scan on posts  ← BAD: reading every row
Index Scan using posts_community_created_idx  ← GOOD: using the index
rows=1000000  ← how many rows scanned
actual time=0.123ms  ← how long it took
```

**Seq Scan** on a large table = missing index. Add one.
**Index Scan** = good. The DB found rows efficiently.

Run this on every endpoint that handles a list before shipping to production.
