# Database at Scale — How It Actually Works

For every developer who wants to go beyond "add an index." This doc explains physical storage, internals, trade-offs, and system-design patterns — from first principles, beginner to intermediate depth. Read it once to understand. Keep it as reference forever.

---

## Table of Contents

1. [The Honest Answer — Yes, It's Line by Line](#1)
2. [How Postgres Stores Data](#2)
3. [The Write Path — WAL and Durability](#3)
4. [MVCC — Concurrent Reads and Writes](#4)
5. [Isolation Levels](#5)
6. [How Indexes Work](#6)
7. [Index Types](#7)
8. [Covering Indexes and Index-Only Scans](#8)
9. [HOT Updates](#9)
10. [Composite Indexes](#10)
11. [When Postgres Ignores Your Index](#11)
12. [Index Cost](#12)
13. [VACUUM — Reclaiming Dead Space](#13)
14. [EXPLAIN ANALYZE](#14)
15. [N+1 Queries](#15)
16. [Pagination at Scale](#16)
17. [Table Partitioning](#17)
18. [Sharding](#18)
19. [CAP Theorem](#19)
20. [ACID vs BASE](#20)
21. [Caching Strategies](#21)
22. [CQRS and Event Sourcing](#22)
23. [Read Replicas](#23)
24. [Connection Pooling and PgBouncer](#24)
25. [Schema Design Checklist](#25)
26. [Things That Kill Performance Quietly](#26)
27. [The Mental Model](#27)
28. [Quick Decision Guide](#28)

---

## 1. The Honest Answer — Yes, It's Line by Line

Without an index, Postgres reads every single row to find what you asked for. No magic.

```sql
SELECT * FROM users WHERE name = 'gautam';
```

With 10 million rows and no index on `name`:

- Postgres opens the table file on disk
- Reads row 1: `name = 'alice'` — not it, skip
- Reads row 2: `name = 'bob'` — not it, skip
- ...continues until all 10 million rows are checked

This is a **Sequential Scan (Seq Scan)**. It is `O(n)` — time grows linearly with data size.

```sql
EXPLAIN SELECT * FROM users WHERE name = 'gautam';
-- Seq Scan on users  (cost=0.00..250000.00 rows=1 width=80)
--                              ↑ reads the entire table to find 1 row
```

At 10k rows — fast enough you don't notice. At 10M rows — seconds. At 100M rows — minutes.

---

## 2. How Postgres Stores Data

Understanding storage makes every other concept obvious.

### 2.1 Pages — the unit of storage

Postgres stores data in fixed-size **pages** (8 KB each by default). Every disk read is at least one full page — you cannot read half a page.

```
Table file on disk (one big file, split into 8 KB chunks):

┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   Page 0    │  │   Page 1    │  │   Page 2    │  ...
│ row1 row2   │  │ row6 row7   │  │ row11 row12 │
│ row3 row4   │  │ row8 row9   │  │ row13 row14 │
│ row5        │  │ row10       │  │ ...         │
└─────────────┘  └─────────────┘  └─────────────┘
  page number 0    page number 1    page number 2
```

Disk reads are the bottleneck — not CPU, not memory. A spinning disk read is ~1 ms. SSD is ~0.1 ms. The goal is always: minimize the number of pages you touch.

---

### 2.2 TID — How Every Row Gets an Address

Each row has a **TID** (Tuple ID, also written as `ctid`): a pair `(page_number, slot_number)`.

```
TID = (7, 3)
       ↑    ↑
   page 7   slot 3 on that page
```

**How a TID is assigned when you INSERT:**

```
INSERT INTO users (name, age) VALUES ('gautam', 25);

Step 1: Postgres scans its free-space map to find a page with enough room.
        → Page 7 has 1200 bytes free. The new row needs ~60 bytes. OK.

Step 2: Postgres picks the next available slot on page 7.
        → Slots 1 and 2 are already used. Slot 3 is free.

Step 3: TID (7, 3) is assigned. This is now the row's physical address.

Step 4: The row data is written into page 7, near the bottom of the page.
        Item pointer 3 at the top of the page records the byte offset.

Step 5: If there is an index on 'name', the entry  'gautam' → TID (7, 3)
        is inserted into the index.
```

TID is not a sequential number. It is a **physical location**. If rows are reorganized (e.g., `CLUSTER` or `VACUUM FULL`), TIDs change and indexes are updated.

---

### 2.3 Inside a Page — The Full Layout

```
Page 7 — 8192 bytes total:

┌───────────────────────────────────────────────────┐
│ Page Header (24 bytes)                            │
│   lsn     — WAL position of last change           │
│   lower   — byte where free space starts (top)    │
│   upper   — byte where free space ends (bottom)   │
│   flags, checksum                                 │
├───────────────────────────────────────────────────┤
│ Item Pointer 1 → offset 8100, length 70 bytes     │ ← slot 1
│ Item Pointer 2 → offset 8020, length 80 bytes     │ ← slot 2
│ Item Pointer 3 → offset 7960, length 60 bytes     │ ← slot 3 (gautam)
│   (each item pointer = 4 bytes)                   │
├───────────────────────────────────────────────────┤
│                                                   │
│              FREE SPACE                           │
│   item pointers grow downward ↓                   │
│   row data grows upward ↑                         │
│                                                   │
├───────────────────────────────────────────────────┤
│ Row 3 data — gautam's tuple (at offset 7960)      │ ← bottom of page
│ Row 2 data                                        │
│ Row 1 data                                        │
└───────────────────────────────────────────────────┘
```

When item pointers (growing down) meet row data (growing up), the page is full. Postgres allocates a new page.

---

### 2.4 Inside a Heap Tuple — What a Row Looks Like on Disk

A "heap tuple" is what Postgres calls a stored row. It has a header, then column data.

```
Row: (id=1, name='gautam', age=25)

┌──────────────────────────────────────────────────────┐
│  TUPLE HEADER (23 bytes)                             │
│                                                      │
│  xmin  (4 bytes)  Transaction ID that created this   │
│                   row version. e.g. xmin=12345       │
│                   "inserted by transaction 12345"    │
│                                                      │
│  xmax  (4 bytes)  Transaction ID that deleted this   │
│                   row version. 0 = still alive.      │
│                   If xmax=99999, deleted by txn 99999│
│                                                      │
│  ctid  (6 bytes)  Current TID of this tuple.         │
│                   Normally = own TID: (7, 3)         │
│                   After UPDATE: points to new version │
│                                                      │
│  infomask, infomask2, hoff (flags + column count)    │
├──────────────────────────────────────────────────────┤
│  NULL BITMAP (optional, 1 bit per column)            │
│  Only present if ANY column could be NULL.           │
│  Bit 0 = col 1 null? Bit 1 = col 2 null? etc.       │
├──────────────────────────────────────────────────────┤
│  COLUMN DATA                                         │
│                                                      │
│  id (integer — fixed 4 bytes):                       │
│    0x00 0x00 0x00 0x01  →  value 1                   │
│                                                      │
│  name (text — variable length):                      │
│    4-byte varlena header: says "6 bytes follow"      │
│    data bytes: 0x67 0x61 0x75 0x74 0x61 0x6D        │
│               g    a    u    t    a    m             │
│    (padding to 4-byte alignment if needed)           │
│                                                      │
│  age (integer — fixed 4 bytes):                      │
│    0x00 0x00 0x00 0x19  →  value 25                  │
└──────────────────────────────────────────────────────┘
```

**Column storage order:** Postgres internally reorders columns to store fixed-length types (int, bool, timestamp) before variable-length types (text, bytea, arrays). This is an internal optimization; you don't control it.

---

### 2.5 Tracing 'gautam' — The Full Journey

**Q: My table has a row where `name = 'gautam'`. How does Postgres know which TID and which page that lives on?**

**Without an index (Sequential Scan):**

```
SELECT * FROM users WHERE name = 'gautam';

Postgres does:
  for each page (0 to N):
    1. Load page into buffer pool (or read from disk)
    2. for each item pointer on the page:
         a. Read item pointer → get byte offset of tuple
         b. Jump to that byte offset on the page
         c. Read tuple header → check xmin/xmax
            (is this row version visible to my current transaction?)
         d. If visible: read past header → read column values in order
            - col 1 (id): read 4 bytes → value 1 → skip
            - col 2 (name): read 4-byte length header → read 6 bytes → 'gautam'
            - compare 'gautam' == 'gautam' → MATCH → collect row
            - if no match: skip to next item pointer
```

For 10M rows across 100k pages: 100k page reads, millions of comparisons.

**With a B-tree index on `name` (Index Scan):**

```
Index on users.name stores: ('gautam', TID=(7,3))

Step 1: Walk the B-tree
        3–4 page reads to find the leaf containing 'gautam'
        → read TID = (7, 3)

Step 2: Heap fetch using TID (7, 3)
        → load page 7 (1 disk read, or buffer pool hit)
        → read item pointer 3 → byte offset 7960
        → jump to offset 7960
        → read tuple header → check visibility
        → read column data → return row

Total: ~5 page reads instead of 100,000+
```

**Why item pointers exist (the indirection layer):**

The index stores TID `(7, 3)` — not a byte offset. The item pointer stores the byte offset. This means rows can be moved within a page (compacted) without updating the index — only the item pointer changes, which is inside the page, not inside the index.

---

### 2.6 Buffer Pool — Memory Cache

Postgres does not read from disk on every query. It has a **buffer pool** — a cache of recently accessed pages held in RAM.

```
Query comes in
    ↓
Is page 7 in the buffer pool?
    → YES: read from RAM (nanoseconds)
    → NO:  read from disk (milliseconds), store in buffer pool
```

`shared_buffers` in `postgresql.conf` controls the pool size. Default: 128 MB. For production: set to **25% of total RAM**.

Hot pages (frequently read) stay in pool. Cold pages get evicted when the pool fills. This means:
- First query after server restart is slow (cold cache, all disk reads)
- Repeated queries are fast (warm cache, RAM reads)
- Full-table scans thrash the cache (evict hot pages, everything slows down after)

---

### 2.7 TOAST — Storing Large Values

Postgres has a rule: **one row must fit on one page (8 KB)**. But what about a 1 MB JSON blob or a 5 MB text document?

**TOAST** (The Oversized-Attribute Storage Technique) handles this transparently.

```
When a column value is too large to fit inline:

1. Postgres tries to compress it first (pglz or lz4).
   → A 1 MB JSON might compress to 200 KB.

2. If still too large (> ~2 KB), Postgres slices it into ~2 KB chunks.

3. Chunks are stored in a hidden "TOAST table" — one per main table.
   → You never see this table. Postgres manages it automatically.

4. The main row stores a small pointer (a few bytes) to the TOAST data.
   → The main row stays tiny, fits on the page.
```

```sql
-- TOAST is invisible to you:
INSERT INTO posts (body) VALUES (repeat('x', 1000000));  -- 1 MB text
-- Postgres silently: compresses → chunks → stores in toast table
-- Main row: tiny TOAST pointer

SELECT body FROM posts WHERE id = 1;
-- Postgres silently: fetches chunks → reassembles → returns to you
```

**Performance implication:**

```sql
-- BAD: fetches TOAST for every row even if you don't use 'body'
SELECT * FROM posts LIMIT 100;

-- GOOD: skips TOAST entirely for rows where you don't need 'body'
SELECT id, title, created_at FROM posts LIMIT 100;
```

Always use explicit column selection on tables with large text/JSONB columns.

---

## 3. The Write Path — WAL and Durability

### What happens when you INSERT

```sql
INSERT INTO users (name, age) VALUES ('gautam', 25);
```

```
Step 1: Find page 7 with free space (using free-space map)
Step 2: Assign TID (7, 3) to the new row
Step 3: Write the tuple (header + column data) into buffer pool — page 7 is now "dirty"
Step 4: Write a WAL record to the Write-Ahead Log file on disk:
          [LSN 5042] INSERT into users: page 7 slot 3, xmin=12345, data=(name='gautam',age=25)
Step 5: WAL is flushed to disk → you get "INSERT 1" response
Step 6: (Later, async) Background writer flushes dirty page 7 to disk
```

The WAL is written before the table page — hence "Write-Ahead Log." You get a response as soon as WAL is durable. The table file may lag behind. On crash, WAL is replayed to recover.

### WAL — Write-Ahead Log

WAL is an append-only sequential log. Every change is recorded before it is applied.

```
WAL file (append-only, sequential):
[LSN 5040] BEGIN transaction 12345
[LSN 5041] INSERT into users: page 7 slot 3, xmin=12345, data=...
[LSN 5042] COMMIT transaction 12345
```

LSN = Log Sequence Number. Monotonically increasing. Every WAL record has one.

**Crash recovery:**

```
Server crashes right after COMMIT:
  - Page 7 might not be flushed to disk yet (still in buffer pool)
  - But WAL [LSN 5042] IS on disk
  - On restart: Postgres replays WAL from last checkpoint
  - Re-applies the INSERT → data recovered
  - You lose nothing
```

**Checkpoint:** Periodically, Postgres flushes all dirty pages to disk and writes a checkpoint record to WAL. On crash recovery, replay starts from the last checkpoint — not from WAL's beginning.

### fsync

`fsync = on` (default): when Postgres says COMMIT, WAL is flushed from OS buffer to physical disk. Without fsync, a power failure could lose "committed" data that the OS hadn't written yet.

`fsync = off`: OS buffer only. Faster. Risk of data loss. Only for throwaway data (test DBs, analytics scratch).

---

## 4. MVCC — Concurrent Reads and Writes

**MVCC** (Multi-Version Concurrency Control) lets readers and writers work simultaneously without blocking each other. No read locks needed.

### Multiple versions of the same row

Every row version has `xmin` (who created it) and `xmax` (who deleted/replaced it) in its header.

```
UPDATE users SET age = 26 WHERE name = 'gautam';
-- (done by transaction 99999)

BEFORE:
  Page 7, slot 3: xmin=12345, xmax=0,     age=25  ← alive (current version)

AFTER:
  Page 7, slot 3: xmin=12345, xmax=99999, age=25  ← dead (old version)
  Page 7, slot 4: xmin=99999, xmax=0,     age=26  ← alive (new version)
```

Postgres does **not** update in-place. It writes a new version and marks the old one dead. Both versions exist on disk simultaneously.

```
Transaction A started BEFORE txn 99999 committed:
  → Reads slot 3 (age=25) — still the "current" version from A's perspective

Transaction B started AFTER txn 99999 committed:
  → Reads slot 4 (age=26) — this is now the current version
```

Readers see different versions depending on when their transaction started. Neither blocks the other.

### Snapshot

When a transaction starts, Postgres captures a **snapshot** — a list of which transaction IDs are currently in-progress. The transaction sees:
- Rows where `xmin` is committed AND `xmin` is before the snapshot → visible
- Rows where `xmax` is 0, or `xmax` is not yet committed → visible (not deleted yet)
- Rows where `xmax` is committed AND before snapshot → invisible (already deleted)

This is why reads don't block writes and writes don't block reads. Each transaction lives in its own consistent snapshot of the world.

### The cost: dead tuples

Old row versions accumulate. VACUUM cleans them. Without VACUUM, tables grow forever even if you "delete" all rows.

```sql
DELETE FROM users WHERE name = 'old_user';
-- Row marked dead (xmax set). Bytes still on disk.

VACUUM users;
-- Scans pages. Finds tuples where both xmin and xmax are committed.
-- Marks that space as reusable for future inserts.
-- Does NOT shrink the file on disk.
```

---

## 5. Isolation Levels

Transactions have 4 isolation levels. Each prevents different categories of anomalies.

### The anomalies

**Dirty Read** — reading uncommitted data from another transaction.
```
Txn A: UPDATE age = 99 WHERE name = 'gautam'  (not committed yet)
Txn B: SELECT age WHERE name = 'gautam'  → sees 99  (dirty read)
Txn A: ROLLBACK  → gautam's age was never really 99
Txn B acted on wrong data.
```

**Non-Repeatable Read** — same row gives different values within the same transaction.
```
Txn A: SELECT age → 25
Txn B: UPDATE age = 26, COMMIT
Txn A: SELECT age again → 26  (different result, same query, same transaction)
```

**Phantom Read** — same query returns different rows.
```
Txn A: SELECT COUNT(*) WHERE age > 20  → 5
Txn B: INSERT a new user age=25, COMMIT
Txn A: SELECT COUNT(*) WHERE age > 20  → 6  (new row appeared)
```

### Isolation levels in Postgres

| Level | Dirty Read | Non-Repeatable | Phantom |
|-------|-----------|----------------|---------|
| READ COMMITTED (default) | Impossible | Possible | Possible |
| REPEATABLE READ | Impossible | Impossible | Impossible* |
| SERIALIZABLE | Impossible | Impossible | Impossible |

*Postgres uses snapshot isolation for REPEATABLE READ, which also prevents phantoms.

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT age FROM users WHERE name = 'gautam';
-- ... do more work ...
COMMIT;
```

**When to use each:**
- **READ COMMITTED** — 99% of use cases. Good default.
- **REPEATABLE READ** — consistent reads within a long transaction (generating a report).
- **SERIALIZABLE** — financial operations (transfer money, book last seat). Most correct. Most expensive.

---

## 6. How Indexes Work

An index is a **separate data structure** that maps column values to row TIDs, kept sorted for efficient search.

### B-tree Index — the default

```
Index on users.name (B-tree):

                    ['john']
                   /        \
          ['alice']            ['mike']
          /       \            /      \
   ['alice']  ['gautam']  ['john'] ['zara']
                  ↓
         leaf node: 'gautam' → TID (7, 3)
```

**Finding `name = 'gautam'`:**
1. Root: is 'gautam' < 'john'? Yes → go left
2. Node 'alice': is 'gautam' > 'alice'? Yes → go right
3. Leaf: found 'gautam' → TID = (7, 3)
4. Heap fetch: go to page 7, slot 3 → read the actual row

This is `O(log n)`. 10M rows → ~24 tree levels → 24 page reads vs 100,000. That is the magic.

**B-tree is pre-sorted**, so it also handles:

```sql
WHERE name > 'alice'          -- range scan: start at 'alice', read right
ORDER BY name ASC             -- already sorted, traverse in order
WHERE name LIKE 'gau%'        -- prefix match (not '%utam' — no prefix, no index)
BETWEEN 'a' AND 'g'           -- start at 'a', read right until 'g'
```

### The heap fetch step

After finding the TID in the index:
1. Load page 7 from buffer pool (or disk)
2. Read item pointer 3 → byte offset 7960
3. Read tuple at 7960 → check visibility (xmin/xmax)
4. Return row

This is called a **heap fetch**. For small result sets it is fast. For large result sets (>10–15% of the table), Postgres may decide a sequential scan is cheaper — random disk access is slower than sequential access.

---

## 7. Index Types

### B-tree (default)

```sql
CREATE INDEX idx_users_name ON users (name);
```

Good for: `=`, `<`, `>`, `<=`, `>=`, `BETWEEN`, `LIKE 'prefix%'`, `ORDER BY`, `IN`
Not good for: `LIKE '%suffix'`, full-text search, array containment

### GIN — Generalized Inverted Index

```sql
CREATE INDEX idx_posts_search ON posts USING GIN(search_vector);  -- full-text
CREATE INDEX idx_posts_tags   ON posts USING GIN(tags);           -- array column
CREATE INDEX idx_posts_meta   ON posts USING GIN(metadata);       -- JSONB @>
```

Instead of `value → row`, GIN maps **each element** to all rows containing it:

```
Text "python tutorial" indexed as:
  'python'   → [row1, row5, row12]
  'tutorial' → [row1, row3, row9]

Query: WHERE search @@ 'python & tutorial'
  → intersect lists → [row1]
```

### GiST — Generalized Search Tree

Good for: geometric data, ranges, nearest-neighbor.

```sql
CREATE INDEX idx_locations ON locations USING GIST(coordinates);
-- Enables: WHERE coordinates <-> point(0,0) < 10   (within 10 km)
```

### Hash Index

```sql
CREATE INDEX idx_users_email ON users USING HASH(email);
```

Good for: equality only (`=`). Smaller than B-tree. Useless for ranges or sorting. Rarely worth it over B-tree.

### Partial Index

```sql
-- Only index non-deleted rows:
CREATE INDEX idx_posts_active ON posts (community_id, created_at DESC)
    WHERE deleted_at IS NULL;
```

If 10% of rows are soft-deleted, a full index has 100% of rows. A partial index has 90% — smaller, faster, fits better in memory. Only queries that include `WHERE deleted_at IS NULL` can use it — but that is every real query anyway.

### Expression Index

```sql
-- Normal index on email won't help with LOWER(email):
CREATE INDEX idx_users_email_lower ON users (LOWER(email));

-- Now this query uses the index:
WHERE LOWER(email) = LOWER('Gautam@Example.COM')
```

---

## 8. Covering Indexes and Index-Only Scans

### The problem

Every normal index lookup has two steps:
1. Walk the B-tree → get TID
2. Heap fetch: go to the table page → read the full row

Step 2 is expensive for large result sets — many random disk reads.

### Covering index — skip the heap fetch

If the index contains **all columns the query needs**, Postgres can answer entirely from the index. No heap fetch.

```sql
-- You always run: SELECT name, age FROM users WHERE name = 'gautam'

-- Normal index:
CREATE INDEX idx ON users (name);
-- Step 1: find 'gautam' in B-tree → TID (7,3)
-- Step 2: heap fetch → read full row → extract name and age

-- Covering index (INCLUDE clause, Postgres 11+):
CREATE INDEX idx_covering ON users (name) INCLUDE (age);
-- Index stores: name + age + TID at every leaf node
-- Step 1: find 'gautam' → read name='gautam', age=25 RIGHT FROM INDEX
-- Step 2: ← SKIPPED — no heap fetch needed
```

```sql
EXPLAIN SELECT name, age FROM users WHERE name = 'gautam';
-- Without covering: "Index Scan"       (2 steps)
-- With covering:    "Index Only Scan"  (1 step) ← much faster at scale
```

**INCLUDE vs search key:**

```sql
CREATE INDEX idx ON users (name) INCLUDE (age, email);
-- name    = search key (used for B-tree ordering and WHERE filtering)
-- age, email = stored only in leaf nodes for projection

-- Columns in INCLUDE cannot be used for range conditions or ORDER BY.
-- They only eliminate the heap fetch for SELECT.
```

**Trade-off:** Covering indexes are larger (store extra columns). Use them for high-frequency queries on a fixed, small column set.

---

## 9. HOT Updates — Free Optimization

### The problem

```sql
UPDATE users SET age = 26 WHERE name = 'gautam';
```

Postgres writes a new tuple version. If there is an index on `age`, Postgres must also update the index — `age=25 → (7,3)` becomes `age=26 → (7,4)`. A table with 10 indexes and 1000 updates/second = 10,000 index write operations per second.

### HOT — Heap Only Tuple

If two conditions are met, Postgres skips the index update entirely:
1. The updated column is **not in any index**
2. The new tuple fits on the **same page** as the old one (free space available)

```
UPDATE users SET bio = 'new bio' WHERE name = 'gautam';
-- bio is not indexed → HOT is possible
-- page 7 has free space → new tuple fits as slot 4

Result:
  Page 7, slot 3: old tuple, ctid → (7, 4)   ← HOT chain pointer
  Page 7, slot 4: new tuple, bio='new bio'    ← current version

Index on name still says: 'gautam' → (7, 3)
When Postgres reads (7, 3) → sees ctid → follows chain to (7, 4) → current version
```

No index write at all. This is a HOT update.

**Ensure HOT works reliably — set fillfactor:**

```sql
-- Leave 20% of each page empty on INSERT, reserved for HOT updates:
ALTER TABLE users SET (fillfactor = 80);
-- Pages fill to 80% on INSERT → 20% headroom for HOT updates later
-- Trade-off: tables use ~20% more disk space
```

**Design tip:** Put frequently-updated, non-lookup columns (`bio`, `last_seen_at`, `updated_at`, `view_count`) outside of indexes. Updates to those columns become HOT — cheap even on write-heavy tables.

---

## 10. Composite Indexes — Column Order Matters

```sql
CREATE INDEX idx ON posts (community_id, created_at DESC);
```

One index, two columns. Column order is critical.

**Helps:**

```sql
WHERE community_id = 'abc'                           -- ✓ leading column match
WHERE community_id = 'abc' ORDER BY created_at DESC  -- ✓ both columns used
WHERE community_id = 'abc' AND author_id = 'xyz'     -- ✓ partially (community_id only)
```

**Does NOT help:**

```sql
WHERE created_at > '2026-01-01'   -- ✗ skipped leading column
ORDER BY created_at DESC           -- ✗ no leading column filter
```

**Rule:** The index is useful starting from the leftmost column, in order. You cannot skip columns.

Think of a phone book sorted by (last_name, first_name). You can find all "Smith"s, or all "Smith, John"s. You cannot efficiently find all "John"s — first name is the second column.

### High cardinality first

```sql
-- BAD: status has 3 possible values (draft, published, deleted) — low cardinality
CREATE INDEX bad ON posts (status, community_id);

-- GOOD: community_id has millions of distinct values — high cardinality
CREATE INDEX good ON posts (community_id, status);
```

Low cardinality first = the first filter eliminates almost nothing. High cardinality first = the first filter immediately eliminates most rows.

---

## 11. When Postgres Ignores Your Index

The query planner estimates costs and picks the cheapest plan. Even with a perfect index, it may choose a sequential scan.

### Too many rows match

```sql
-- 1 million rows, 800k have status = 'published'
SELECT * FROM posts WHERE status = 'published';
-- Postgres: "80% of rows match. Sequential scan beats 800k random heap fetches."
-- Index ignored.
```

When a query matches >10–15% of the table, sequential scan is usually cheaper. Random disk access (index → random page) is slower than sequential disk access (read every page in order).

### Function wrapping the column

```sql
WHERE LOWER(email) = 'gautam@example.com';
-- Index on email stores 'Gautam@Example.COM', not its lowercased form.
-- The function prevents index use.
-- Fix: CREATE INDEX idx ON users (LOWER(email));
```

### Implicit type cast

```sql
-- age column is INTEGER, query passes a string
WHERE age = '28';
-- Postgres must cast '28' → integer → may skip index
-- Fix: pass correct type: WHERE age = 28
```

### Stale statistics

```sql
ANALYZE users;  -- rebuild column statistics used by the query planner
-- Run manually after large bulk imports
-- Autovacuum does this automatically but may lag behind bulk loads
```

---

## 12. Index Cost — Nothing Is Free

```
INSERT a row  → write to table + update every index on that table
UPDATE a row  → write new tuple + update indexes for changed columns
DELETE a row  → mark tuple dead + update every index
```

Table with 10 indexes = 11 write operations per INSERT.

```sql
-- Find index usage statistics:
SELECT indexrelname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE relname = 'users'
ORDER BY idx_scan DESC;
-- idx_scan = 0 → index never used → safe to drop

-- Drop an unused index without locking the table:
DROP INDEX CONCURRENTLY idx_users_old;
```

**Signs of too many indexes:** writes are slow, many indexes show `idx_scan = 0`.
**Signs of too few indexes:** `EXPLAIN` shows Seq Scans on large tables, slow list endpoints.

---

## 13. VACUUM — Reclaiming Dead Space

Dead tuples (from UPDATE and DELETE via MVCC) accumulate on disk. VACUUM cleans them.

### VACUUM vs VACUUM FULL vs VACUUM ANALYZE

```sql
VACUUM users;
-- Marks dead tuple space as reusable for future inserts.
-- Does NOT shrink the file on disk.
-- Safe in production: no table lock. Shares with readers/writers.
-- Normally handled automatically by autovacuum.

VACUUM FULL users;
-- Rewrites the entire table into a new, compact file.
-- Actually shrinks disk usage.
-- Takes ACCESS EXCLUSIVE lock — blocks ALL reads and writes.
-- Use only during maintenance windows on severely bloated tables.

VACUUM ANALYZE users;
-- VACUUM + rebuilds column statistics for the query planner.
-- Run after bulk imports.
```

### Autovacuum tuning

Autovacuum triggers when dead tuples exceed a threshold:

```
Default: trigger when dead tuples > 20% of table + 50 rows
  autovacuum_vacuum_scale_factor = 0.2   (20%)
  autovacuum_vacuum_threshold    = 50
```

For large write-heavy tables, 20% is too slow to trigger. Tune per-table:

```sql
ALTER TABLE posts SET (autovacuum_vacuum_scale_factor = 0.05);
-- Triggers at 5% dead tuples instead of 20% → less bloat, better performance
```

### Monitoring bloat

```sql
SELECT relname, n_dead_tup, n_live_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct
FROM pg_stat_user_tables
WHERE relname = 'users';
-- dead_pct > 20% → run VACUUM manually or tune autovacuum
```

### Index bloat

Indexes also bloat after heavy updates. Rebuild without locking:

```sql
REINDEX INDEX CONCURRENTLY idx_users_name;
-- Postgres 12+. Rebuilds the index while reads/writes continue.
```

---

## 14. EXPLAIN ANALYZE — Reading the Output

The most important tool for diagnosing slow queries.

```sql
EXPLAIN ANALYZE
SELECT u.name, p.title
FROM posts p
JOIN users u ON p.author_id = u.id
WHERE p.community_id = 'abc-123'
  AND p.deleted_at IS NULL
ORDER BY p.created_at DESC
LIMIT 10;
```

Sample output:

```
Limit  (cost=0.56..45.20 rows=10 width=300) (actual time=0.123..0.456 rows=10)
  → Sort  (cost=0.56..45.20 rows=150) (actual time=0.120..0.200 rows=10)
       Sort Key: p.created_at DESC
       → Nested Loop  (actual time=0.050..0.100 rows=150)
            → Index Scan using posts_community_idx on posts p
                 Index Cond: (community_id = 'abc-123')
                 Filter: (deleted_at IS NULL)
                 Rows Removed by Filter: 12
            → Index Scan using users_pkey on users u
                 Index Cond: (id = p.author_id)
Planning time: 0.5 ms
Execution time: 1.2 ms
```

**How to read it:**
- **Read from innermost (most indented) outward** — that is execution order
- `cost=X..Y` — planner estimate (X = startup cost, Y = total cost, arbitrary units)
- `actual time=X..Y` — real milliseconds (X = time to first row, Y = time to last row)
- `rows=N` — actual rows returned at this step
- `Rows Removed by Filter: 12` — 12 rows passed the index scan but failed `deleted_at IS NULL` → a partial index would eliminate these

**Red flags:**

```
Seq Scan on posts  (rows=10000000)    ← scanning entire 10M-row table
Sort              (rows=500000)       ← sorting 500k rows (check work_mem)
Hash Join         (rows=1000000)      ← large join without index
```

**Green signs:**

```
Index Only Scan  (rows=50)            ← answered from index, no heap fetch
Index Scan       (rows=10)            ← precise lookup
Limit            (rows=10)            ← early termination working
```

---

## 15. N+1 Queries — The Silent Killer

The most common performance bug in application code.

```python
# Fetch 100 users:
users = await conn.fetch("SELECT * FROM users LIMIT 100")

# For each user, fetch their posts — 100 MORE queries!
for user in users:
    posts = await conn.fetch(
        "SELECT * FROM posts WHERE author_id = $1", user["id"]
    )
```

Result: **101 queries** instead of 1. At 10 ms per query = 1 second wasted.

**The fix — one query with JOIN:**

```sql
SELECT u.id, u.name, p.title, p.created_at
FROM users u
LEFT JOIN posts p ON p.author_id = u.id
ORDER BY u.id, p.created_at DESC;
```

**How to spot N+1:** look for a database query inside a `for` loop, or `await` inside a loop that touches the DB. If you are querying the DB N times to display N items, you have N+1.

---

## 16. Pagination at Scale

### OFFSET — simple but broken at scale

```sql
SELECT * FROM posts ORDER BY created_at DESC LIMIT 10 OFFSET 10000;
```

What Postgres actually does:
1. Read and sort **10,010 rows**
2. Discard the first **10,000**
3. Return the last **10**

Every page number gets slower. Page 1000 = reading 10,000 rows just to discard them.

Use OFFSET only for: admin panels, small datasets, anything under ~100 pages.

### Cursor Pagination — correct at scale

Use "give me rows after this specific row" instead of "skip N rows."

```sql
-- First page:
SELECT * FROM posts
WHERE deleted_at IS NULL
ORDER BY created_at DESC, id DESC
LIMIT 10;
-- Save the last row's (created_at, id) as your cursor.

-- Next page — pass cursor values:
SELECT * FROM posts
WHERE deleted_at IS NULL
  AND (created_at, id) < ('2026-01-15 10:30:00', 'last-seen-uuid')
ORDER BY created_at DESC, id DESC
LIMIT 10;
```

Postgres uses the composite index to jump directly to the cursor position. No scanning and discarding. **Page 10,000 is as fast as page 1.**

**Why `(created_at, id)` and not just `created_at`?** Multiple posts can share a timestamp. Adding `id` makes the cursor unique and deterministic.

---

## 17. Table Partitioning — One Table, Many Files

When a table hits 100M+ rows, even indexed queries slow down because the index itself becomes enormous and no longer fits in memory.

**Partitioning** splits one logical table into multiple physical files (partitions), each smaller and independently managed.

### Range Partitioning (most common — use for dates)

```sql
CREATE TABLE events (
    id          UUID,
    user_id     UUID,
    event_type  TEXT,
    created_at  TIMESTAMPTZ
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2025 PARTITION OF events
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

CREATE TABLE events_2026 PARTITION OF events
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
```

```
Logical table "events" (what you query):
        │
   ┌────┴────┐
   ▼         ▼
events_2025  events_2026   ← actual physical files on disk
```

```sql
-- Postgres only reads the matching partition (partition pruning):
SELECT * FROM events WHERE created_at > '2026-01-01';
-- → reads only events_2026, skips events_2025 entirely
```

**Dropping old data is instant:**

```sql
-- DELETE-ing 100M old rows = slow, bloated, vacuum-heavy
DELETE FROM events WHERE created_at < '2025-01-01';

-- Dropping a partition = instant (just removes a file pointer)
DROP TABLE events_2024;  -- gone in milliseconds
```

### Hash Partitioning (even distribution, no natural range)

```sql
CREATE TABLE users PARTITION BY HASH (id);

CREATE TABLE users_0 PARTITION OF users FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE users_1 PARTITION OF users FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE users_2 PARTITION OF users FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE users_3 PARTITION OF users FOR VALUES WITH (MODULUS 4, REMAINDER 3);
-- Each partition gets ~25% of rows
```

### List Partitioning (discrete values — regions, categories)

```sql
CREATE TABLE orders PARTITION BY LIST (region);
CREATE TABLE orders_india  PARTITION OF orders FOR VALUES IN ('IN');
CREATE TABLE orders_us     PARTITION OF orders FOR VALUES IN ('US');
CREATE TABLE orders_europe PARTITION OF orders FOR VALUES IN ('EU', 'UK', 'DE');
```

### Partitioning trade-offs

```
Benefits:
  + Queries hitting one partition skip all others (partition pruning)
  + Smaller per-partition index → fits in memory
  + VACUUM runs per partition → faster, less disruptive
  + Instant partition drop for old data (vs slow DELETE)

Trade-offs:
  - Cross-partition queries (no partition key in WHERE) hit all partitions
  - Joins across partitions are more complex for the planner
  - Partition key must be in almost every query for pruning to work
  - Adding new partitions requires schema planning
```

**Partitioning vs Sharding:**
- Partitioning = multiple files, one Postgres instance, one connection string
- Sharding = multiple Postgres instances, different servers, requires routing logic in your application

---

## 18. Sharding — One Database Becomes Many

When a single Postgres server hits its hardware ceiling (disk, CPU, RAM, connections), sharding splits data across multiple independent database servers.

```
Without sharding:
  All 500M users → one Postgres server (maxed out)

With sharding (4 shards by user_id hash):
  Users hash%4=0 → Shard 1  (separate server)
  Users hash%4=1 → Shard 2  (separate server)
  Users hash%4=2 → Shard 3  (separate server)
  Users hash%4=3 → Shard 4  (separate server)
```

### Shard key — the most important decision

The shard key determines which shard a row lives on. Getting this wrong is very hard to undo.

**Hash sharding:**

```
shard_number = hash(user_id) % total_shards

user_id = 'gautam-uuid' → hash → 2813947839 → 2813947839 % 4 = 3 → Shard 3
```

Good: even distribution, no hot spots. Bad: range queries (all users in a region) must hit all shards.

**Range sharding:**

```
user_id starts 0000–3FFF → Shard 1
user_id starts 4000–7FFF → Shard 2
user_id starts 8000–BFFF → Shard 3
user_id starts C000–FFFF → Shard 4
```

Good: range queries hit one shard. Bad: hot spots if one range is disproportionately popular.

### Problems sharding introduces

```
1. Cross-shard queries
   "Get all users who signed up this week"
   → must query ALL shards → aggregate results in application layer
   → no SQL JOIN across shards

2. Cross-shard transactions
   "Transfer money from Shard 1 user to Shard 3 user"
   → no ACID guarantee across shards
   → requires distributed transactions (2-phase commit) or eventual consistency

3. Rebalancing
   Add a 5th shard → must move data from existing shards to new one
   → painful, requires careful migration with zero downtime

4. Operational cost
   10 shards = 10 databases to monitor, backup, upgrade, tune separately

5. Hot shards
   One user or region generates 80% of traffic → their shard is overloaded
   → requires careful shard key selection to avoid
```

### When to shard — the order of operations

**Do not shard until you must.** In order:

1. Read replicas — scale reads horizontally
2. Better indexing and query optimization
3. Table partitioning — manage large tables
4. Caching (Redis) — serve from memory
5. Bigger hardware (vertical scaling)
6. **Then** consider sharding

Most applications never need sharding. Tools like Citus (Postgres extension) make sharding more manageable when you do.

---

## 19. CAP Theorem — The Distributed System Trade-off

In a distributed system, you can only guarantee **2 of these 3** properties:

```
C — Consistency
    Every read receives the most recent write.
    "After gautam updates his age, every reader immediately sees age=26."

A — Availability
    Every request gets a response (not an error), even if data may be stale.
    "The system always responds, even during failures."

P — Partition Tolerance
    The system keeps working when network partitions happen
    (servers temporarily cannot communicate with each other).
```

**Network partitions always happen** in distributed systems — cables get cut, servers crash, latency spikes. P is non-negotiable. The real choice is always **C vs A during a partition**:

```
CP systems — prioritize Consistency:
  When a partition happens, refuse reads/writes to maintain consistency.
  "I'd rather be unavailable than serve wrong data."
  Examples: Postgres (sync replication), HBase, ZooKeeper

AP systems — prioritize Availability:
  When a partition happens, keep accepting reads/writes; accept stale data.
  "I'd rather serve slightly old data than be unavailable."
  Examples: DynamoDB, Cassandra, CouchDB
```

### CAP in Postgres

Single-node Postgres: CAP doesn't apply (no network partition between components).

With replicas:

```
Async replication (default):
  → AP: reads from replica may be stale, but the system is always available
  → Not strictly consistent (replica lag exists)

Synchronous replication:
  → CP: if the replica is down, the primary may refuse commits
  → Strictly consistent but reduced availability

Read-your-own-writes (app routing):
  → Compromise: write to primary, immediately read from primary
  → Other users may see stale data; the writing user always sees their own write
```

### PACELC — the extension to CAP

CAP only describes behavior during partitions. PACELC adds: **even without partitions, you choose between Latency and Consistency.**

```
PACELC: If Partition → (C or A)   |   Else → (L or C)

Postgres with sync replication:
  During partition: C (consistent, may be unavailable)
  Normal operation: C (consistent, but higher write latency — waits for replica ACK)

DynamoDB:
  During partition: A (available, may serve stale data)
  Normal operation: L (low latency, eventual consistency)
```

---

## 20. ACID vs BASE — Two Schools of Thought

### ACID — the relational guarantee

**A — Atomicity:** A transaction is all-or-nothing.

```sql
BEGIN;
  UPDATE accounts SET balance = balance - 100 WHERE user_id = 'gautam';
  UPDATE accounts SET balance = balance + 100 WHERE user_id = 'alice';
COMMIT;
-- Both updates happen, or neither does. Never one without the other.
```

**C — Consistency:** Every transaction moves the database from one valid state to another. Constraints, foreign keys, and CHECK constraints are enforced.

```sql
-- If accounts has CHECK (balance >= 0):
UPDATE accounts SET balance = -50 WHERE user_id = 'gautam';
-- ERROR: violates check constraint — transaction rolled back. Data stays valid.
```

**I — Isolation:** Concurrent transactions do not interfere with each other (see Section 5 — Isolation Levels).

**D — Durability:** Once committed, data survives crashes. (The WAL guarantees this — see Section 3.)

### BASE — the distributed trade-off

Used by NoSQL and distributed databases that prioritize availability and throughput over strict consistency.

```
BA — Basically Available
     The system responds to every request.
     Some responses may contain stale data.

S  — Soft State
     The system's state may change over time even without new input.
     (Replicas converging toward the same value.)

E  — Eventually Consistent
     Given no new updates, all replicas will eventually agree on the same value.
```

```
Example — Cassandra with eventual consistency:

  User updates name: 'gautam' → 'gautam kumar'
  Write goes to replica 1 immediately.
  Replicas 2 and 3 receive it ~100 ms later.

  If you read from replica 2 within that 100 ms:
    → You see 'gautam'  (stale, but the system is available)

  After convergence (all replicas updated):
    → Everyone sees 'gautam kumar'
```

### When to choose ACID vs BASE

| Choose ACID (Postgres, MySQL) | Choose BASE (Cassandra, DynamoDB) |
|-------------------------------|----------------------------------|
| Financial transactions | Social media feeds |
| User accounts and auth | Analytics and time-series |
| Inventory (can't oversell) | IoT sensor writes |
| Any operation where correctness > speed | Any operation where availability > consistency |

---

## 21. Caching Strategies

The fastest query is the one that never hits the database.

### Cache-Aside (Lazy Loading) — the most common pattern

The application manages the cache. The cache is populated only on cache miss.

```python
async def get_user(user_id: str) -> dict:
    # 1. Check cache first
    cached = await redis.get(f"user:{user_id}")
    if cached:
        return json.loads(cached)          # cache hit: ~1 ms

    # 2. Cache miss → query database
    user = await db.fetchrow(
        "SELECT * FROM users WHERE id = $1", user_id
    )                                      # DB read: ~5–50 ms

    # 3. Populate cache with TTL
    await redis.setex(f"user:{user_id}", 300, json.dumps(dict(user)))
    return dict(user)


async def update_user(user_id: str, data: dict):
    await db.execute("UPDATE users SET ... WHERE id = $1", user_id)
    await redis.delete(f"user:{user_id}")  # invalidate stale cache entry
```

### Write-Through

Write to cache and database simultaneously. Cache is always warm; no cold misses.

```python
async def update_user(user_id: str, data: dict):
    await db.execute("UPDATE users SET ... WHERE id = $1", user_id)
    await redis.setex(f"user:{user_id}", 300, json.dumps(data))  # keep cache fresh
```

Good: reads always hit cache. Bad: write latency is slightly higher (two writes).

### Write-Behind (Write-Back)

Write to cache only; flush to database asynchronously later. Fastest writes; risk of data loss.

```
App → write to Redis → return success
Background worker → flush Redis → DB every few seconds

Danger: if Redis crashes before the flush, those writes are lost.
Use for: counters, view counts, metrics — losing a few is acceptable.
```

### Cache eviction policies

| Policy | Description | Best for |
|--------|-------------|----------|
| LRU (Least Recently Used) | Evict the key accessed longest ago | General user data caches |
| LFU (Least Frequently Used) | Evict the key accessed least often | Popularity-based caches |
| TTL (Time-To-Live) | Keys expire after N seconds | Always set a TTL as a baseline |

### What to cache vs what not to

```
Good candidates:
  ✓ User profiles (read many times, change rarely)
  ✓ Configuration and feature flags
  ✓ Top posts / trending content (computed, expensive to rebuild)
  ✓ Aggregations: post count, total revenue, leaderboards
  ✓ Session data

Bad candidates:
  ✗ Account balances (must be exact → always read from DB)
  ✗ Inventory counts (same reason — overselling is costly)
  ✗ Data that changes faster than your TTL
  ✗ Data where stale reads cause user harm or legal issues
```

### Cache Stampede — the thundering herd

When a popular cache key expires, thousands of simultaneous requests all miss and hammer the database.

```python
# Naive (broken under load):
async def get_popular(key):
    result = await redis.get(key)
    if not result:
        result = await db.expensive_query()   # 10,000 requests all do this simultaneously
        await redis.setex(key, 300, result)
    return result

# Fix — distributed lock: only one request rebuilds the cache
async def get_popular_safe(key):
    result = await redis.get(key)
    if result:
        return result

    lock_key = f"lock:{key}"
    acquired = await redis.set(lock_key, "1", nx=True, ex=5)  # NX = only if not exists
    if acquired:
        result = await db.expensive_query()
        await redis.setex(key, 300, result)
        await redis.delete(lock_key)
        return result
    else:
        await asyncio.sleep(0.05)              # brief wait for lock holder to finish
        return await redis.get(key)
```

---

## 22. CQRS and Event Sourcing

### CQRS — Command Query Responsibility Segregation

**The idea:** use separate models (and sometimes separate databases) for reads and writes.

```
Traditional:
  Write → normalized table → Read from same table
  Problem: optimizing for writes (normalized) conflicts with reads (denormalized joins)

CQRS:
  Write side (Commands)          Read side (Queries)
  ─────────────────────          ───────────────────
  Normalized Postgres tables     Denormalized read models
  ACID transactions              Optimized for query speed
  Strict schema                  Could be Redis, Elasticsearch,
                                 or a Postgres materialized view
```

**Example:**

```python
# Write side: normalized, strict
await db.execute(
    "INSERT INTO orders (user_id, product_id, quantity) VALUES ($1, $2, $3)",
    user_id, product_id, quantity
)
# Publish an event: "OrderPlaced"

# Read side: event handler updates denormalized summary table
await db.execute("""
    INSERT INTO user_order_summary (user_id, total_orders, total_spent)
    VALUES ($1, 1, $2)
    ON CONFLICT (user_id) DO UPDATE
    SET total_orders = user_order_summary.total_orders + 1,
        total_spent  = user_order_summary.total_spent + EXCLUDED.total_spent
""", user_id, quantity * price)
```

```
Trade-offs:
  + Read queries are fast (pre-computed, no joins)
  + Write side stays normalized and consistent
  + Read and write sides can scale independently
  - Two data models to maintain
  - Eventual consistency between write and read sides
  - More code
```

Use CQRS when read and write loads are drastically different, or when different consumers need different data shapes.

### Event Sourcing

Instead of storing current state, store a **log of all events** that produced the current state.

```
Traditional (store current state):
  users table: id=1, name='gautam', age=26  ← only the current state

Event Sourcing (store all events):
  user_events table:
    [2026-01-01]  UserCreated:       id=1, name='gautam', age=25
    [2026-03-15]  AgeUpdated:        id=1, age=26
    [2026-05-01]  EmailChanged:      id=1, email='new@example.com'

  Current state = replay all events for user id=1 in order
```

**Benefits:**
- Complete audit trail — every change ever made is recorded
- Time travel — "What was gautam's age on March 1st?" → replay events up to that date
- Events can trigger side effects (send email when UserCreated fires)
- Natural fit with CQRS — events update read models asynchronously

**Trade-offs:**
- Reading current state requires replaying events (mitigated by periodic snapshots)
- More complex to implement and reason about
- Not a sensible default — use only when audit history or time travel is genuinely needed

---

## 23. Read Replicas — Scaling Reads

### How replication works

```
App writes → Primary (one server, accepts all writes)
                 │
                 │  WAL stream (continuous, near real-time)
                 │
         ┌───────┼───────┐
         ▼       ▼       ▼
    Replica 1  Replica 2  Replica 3
    (read)     (read)     (read + reporting)
```

Replication streams the primary's WAL to replicas. Each replica replays the WAL — the same mechanism used for crash recovery. Replicas are read-only.

Most applications do 90% reads and 10% writes. Replicas let you distribute the 90%.

### Replication lag

Replicas are slightly behind the primary — usually milliseconds, sometimes seconds under heavy write load.

```
User posts a comment → written to primary
User refreshes immediately → request routes to replica
Replica is 200 ms behind → user doesn't see their own comment
```

**Solutions:**
- **Read-your-own-writes:** route reads to primary for a short window after a write
- **Accept staleness:** for feeds, lists, analytics — users don't notice 1s lag
- **Synchronous replication:** primary waits for at least one replica to confirm before COMMIT — zero lag, slightly slower writes

### Async vs Sync replication

| | Write speed | Lag | Data loss on primary failure |
|--|------------|-----|------------------------------|
| Async (default) | Fast | Milliseconds | Possible (recent commits) |
| Sync | Slower | Zero | None |

For most applications: async is the right default. The replica catches up quickly.

---

## 24. Connection Pooling and PgBouncer

### Why connection pools exist

Opening a Postgres connection costs ~50 ms: TCP handshake, authentication, memory allocation on both sides. You cannot afford this per request.

A connection pool opens a fixed set of connections at startup and reuses them:

```
Pool with 10 connections:
  App starts → opens 10 connections to Postgres
  Request A  → borrows connection 3 → runs query → returns it
  Request B  → borrows connection 7 → runs query → returns it
```

### Why the pool alone breaks at scale

Each app process has its own pool. Scale horizontally:

```
4 servers × 4 workers × pool size 10 = 160 connections

Postgres default max_connections = 100
→ You are 60 over the limit. Postgres starts rejecting connections.
```

Each Postgres connection is a full OS process, consuming ~5 MB RAM. 500 connections = 2.5 GB just for connections, before any queries run.

### PgBouncer

PgBouncer sits between the application and Postgres. The app connects to PgBouncer; PgBouncer maintains a small pool of real Postgres connections.

```
Without PgBouncer:
  1000 app connections → 1000 Postgres backend processes

With PgBouncer (transaction pooling):
  1000 app connections → PgBouncer → 20 real Postgres connections
```

### PgBouncer pooling modes

**Transaction pooling** (what you actually want):

```
Real Postgres connection is held only for the duration of one transaction.
Released back to PgBouncer's pool between transactions.

1000 app connections, each doing 1 transaction per second.
Average transaction = 10 ms → connection held 10 ms out of every 1000 ms.
Real connections needed: 1000 × 0.01 = 10 real connections.
```

**Session pooling:** Real connection held for the entire session. Provides no benefit over direct connection. Do not use.

**Statement pooling:** Released after every single SQL statement. Breaks multi-statement transactions. Rarely practical.

### asyncpg + PgBouncer: the prepared statement problem

asyncpg caches prepared statements per connection. In transaction pooling mode, you may get a different real Postgres connection each transaction. The cached statement from the previous connection does not exist on the new one → `InvalidCachedStatementError`.

```python
# Fix: disable statement caching
pool = await asyncpg.create_pool(dsn, statement_cache_size=0)
```

### Connection pool sizing

```
Without PgBouncer:
  max_pool_size × workers_per_server × server_count < postgres max_connections
  Example: 5 × 4 × 4 = 80 → safely under 100

With PgBouncer (transaction pooling):
  PgBouncer pool size: 20–50 real connections to Postgres
  App connects to PgBouncer with any number of connections

Rule of thumb for Postgres max_connections:
  Active connections ≈ (2 × CPU cores) + disk spindle count
  4-core server → aim for ≤ 20 active connections at once
  (Postgres is CPU-bound for in-memory queries)
```

---

## 25. Schema Design Checklist

Before shipping any table to production:

```
□ Primary key defined?

□ All foreign key columns indexed?
  (Postgres does NOT auto-index FKs — you must add them manually)

□ Hot query columns indexed?
  (Think about WHERE, JOIN, ORDER BY in your most frequent queries)

□ Partial index for soft-deleted rows?
  WHERE deleted_at IS NULL  → smaller index, faster queries

□ NOT NULL on columns that should never be null?

□ DEFAULT values on counts, booleans, timestamps?

□ CHECK constraints for business rules?
  e.g., CHECK (balance >= 0), CHECK (quantity > 0)

□ RETURNING on INSERT/UPDATE to avoid a second round-trip query?
  INSERT INTO ... RETURNING id, created_at;

□ Covering index (INCLUDE) for high-frequency small-column reads?

□ fillfactor set on write-heavy tables to enable HOT updates?
  ALTER TABLE t SET (fillfactor = 80);

□ Partition strategy planned for tables expected to grow > 100M rows?
  (Much harder to add partitioning after the fact)

□ JSONB vs separate columns? JSONB adds flexibility but loses column-level indexing.
```

**Postgres does NOT auto-index foreign keys:**

```sql
-- Auto-indexed by Postgres:
PRIMARY KEY → ✓
UNIQUE       → ✓

-- NOT auto-indexed (you must create manually):
FOREIGN KEY  → ✗   e.g., author_id UUID REFERENCES users(id)
Regular col  → ✗
```

---

## 26. Things That Kill Performance Quietly

| Problem | Symptom | Fix |
|---------|---------|-----|
| Missing FK index | Slow joins, slow `WHERE author_id =` queries | Add index manually |
| N+1 queries | Slow list endpoints, dozens of tiny queries per request | Rewrite with JOIN |
| `SELECT *` | Extra data over network, breaks covering index | Use explicit column list |
| No LIMIT | OOM crash on large tables | Always paginate |
| OFFSET pagination | Page 1000 takes seconds | Switch to cursor pagination |
| Stale statistics | Planner chooses wrong query plan | Run `ANALYZE tablename` |
| Too many indexes | Writes slow under load | Drop unused indexes |
| No partial index | Index is larger than it needs to be | Add `WHERE` condition to index |
| Function on indexed column | Index not used | Create expression index |
| Type mismatch in query | Implicit cast skips index | Pass correct type |
| No HOT-friendly fillfactor | Index update on every UPDATE | Set `fillfactor = 80` |
| Table bloat | Queries slower over time, disk growing | Tune autovacuum |
| Index bloat | Index unusually large, cache misses | `REINDEX CONCURRENTLY` |
| Cache stampede | DB spikes on cache key expiry | Distributed lock on rebuild |
| No caching | DB hit on every request for the same data | Redis cache-aside |
| Cross-shard queries | Slow and complex at shard boundary | Redesign shard key |

---

## 27. The Mental Model

Think of your database as a city library:

| Database concept | Library analogy |
|-----------------|-----------------|
| Table | A floor of millions of books |
| Page | One shelf section — you check out a whole section, not one book |
| Row / Tuple | One book |
| TID `(7, 3)` | Shelf address: floor 7, slot 3 |
| Item pointer | The label on slot 3 that says "book starts at position 7960 cm on this shelf" |
| Tuple header (xmin/xmax) | Book's inside cover: who added it, whether it has been retired |
| Sequential scan | Walking every aisle reading every spine to find books about Python |
| B-tree index | The card catalog — sorted alphabetically, each card has the exact shelf address |
| Index-only scan | Finding the book's summary directly on the catalog card — you never enter the stacks |
| Buffer pool | Books currently on your reading desk — fast to access, limited space |
| TOAST | Oversized books stored in a special archive room; the main shelf has a slip saying "see archive room" |
| MVCC | Multiple editions of the same book exist simultaneously; old readers keep the old edition |
| Dead tuple | An old edition waiting to be removed from the shelf |
| VACUUM | The librarian who collects retired editions and frees up shelf space |
| WAL | The library's change log — survives even if the building burns down |
| Connection pool | A team of librarians — limited in number, each handles one request at a time |
| PgBouncer | A front desk that assigns librarians — you queue at the desk, not at each librarian |
| Read replica | A branch library — reads distributed, all new books go to main branch first |
| Partitioning | Splitting one floor into sections by year — 2026 searches never touch the 2025 shelves |
| Sharding | Multiple library buildings across the city — each holds a subset of books |
| Caching (Redis) | A photocopier at the entrance — popular books are photocopied so you never enter the library |
| CAP theorem | City outage: close main library and keep data accurate (CP), or open branch with possibly outdated books (AP) |

---

## 28. Quick Decision Guide

```
Query slow?
  → EXPLAIN ANALYZE

  → Seq Scan on a large table?
      → Index missing → create one
      → Index exists but not used?
          → Function on column → expression index
          → Too many rows match → query is too broad, add more filters
          → Type mismatch → fix types in your query
          → Stale statistics → ANALYZE tablename

  → Index Scan but still slow?
      → Large heap fetch cost → add covering index with INCLUDE

Write slow under load?
  → Too many indexes → check pg_stat_user_indexes, drop unused
  → Index updates on non-critical columns → HOT + fillfactor
  → Connection pool exhausted → check max_connections, add PgBouncer

List endpoint slow at high page numbers?
  → OFFSET pagination → switch to cursor pagination

Endpoint fires many small DB queries?
  → N+1 → rewrite with JOIN

Same data fetched on every request?
  → Add Redis cache-aside with TTL

Table growing without bound?
  → Soft-deleted rows not purged → schedule periodic hard-delete job
  → Autovacuum not keeping up → tune autovacuum_vacuum_scale_factor per table
  → Index bloat → REINDEX CONCURRENTLY

Too many Postgres connections?
  → Add PgBouncer in transaction pooling mode
  → Set statement_cache_size=0 on asyncpg

Single Postgres server is the bottleneck?
  1. Add read replicas (scale reads)
  2. Add Redis caching (reduce DB load)
  3. Add table partitioning for large tables
  4. Vertical scale (bigger server)
  5. Only then: sharding (last resort, high complexity)

Need full audit history or time-travel queries?
  → Event sourcing

Read and write workloads look very different?
  → CQRS — separate read and write models

Distributed system — consistency vs availability trade-off?
  → Financial data, inventory → CP + ACID (Postgres, sync replication)
  → Social feeds, analytics → AP + BASE (acceptable eventual consistency)
  → Mixed workload → route critical writes through CP, non-critical through AP
```
