# 05 · Database Indexing, from zero to interview-ready

Examples use PostgreSQL and a Headstart-style table:

```sql
CREATE TABLE leads (
  id          bigserial PRIMARY KEY,
  tenant_id   uuid        NOT NULL,     -- which institution
  email       text        NOT NULL,
  name        text,
  status      text        NOT NULL,     -- 'new' | 'contacted' | 'enrolled' | 'lost'
  counsellor_id bigint,
  created_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz              -- soft delete
);
-- imagine 20 million rows across 500 institutions
```

---

## 1. The problem an index solves

Postgres stores table rows in a **heap**: an unordered pile of 8 KB pages. Rows go wherever there's space, not in any useful order.

Without an index, `SELECT * FROM leads WHERE email = 'a@x.com'` has to do a **sequential scan**: read every page and check every row. That's 20 million rows, **O(n)**, to find one.

**An index is a separate, sorted data structure** that maps column values to row locations, so the database can jump straight to the matching rows.

**Analogy:** the index at the back of a textbook. To find "recursion", you don't read all 800 pages. You look it up alphabetically in the index (fast, because it's sorted), and it tells you "page 412". The index is extra pages the book has to carry, and if you add a new chapter, the index has to be updated too. Both costs are real for databases as well.

## 2. How a B-tree index works (the default)

`CREATE INDEX idx_leads_email ON leads (email);` builds a **B-tree** (balanced tree):

```
                    [ root:  "g..." | "p..." ]
                   /           |            \
     [ "a".."f" ]        [ "g".."o" ]        [ "p".."z" ]      ← internal pages
      /    |   \            /   \               /   \
  [leaf][leaf][leaf]   [leaf][leaf]       [leaf][leaf]          ← leaf pages
   a@x.com → (page 9183, row 4)                                  (sorted values + row pointer)
   ab@y.com → (page 22, row 17)
   ...  leaves are linked left ↔ right
```

- **Every page holds hundreds of keys**, so the tree is very wide and very shallow. 20 million rows usually means a tree only **3–4 levels deep**.
- **Lookup:** start at the root, pick the child whose range contains the value, repeat down to a leaf, then follow the pointer (the row's physical location, called a TID or ctid) to the heap. About 4 page reads instead of hundreds of thousands. That's **O(log n)**.
- **Balanced:** all leaves are the same depth, so every lookup costs about the same. Inserts split pages when they fill up, which keeps the tree balanced.
- **Leaves are sorted and linked**, so once you find the start of a range you just walk along the leaves. That's why B-trees are good at ranges and sorting, not just exact matches.

**What a B-tree can speed up:**
| Query | Uses the index? |
|---|---|
| `WHERE email = 'a@x.com'` | Yes, exact match |
| `WHERE created_at > now() - interval '7 days'` | Yes, range (with an index on `created_at`) |
| `ORDER BY created_at DESC LIMIT 20` | Yes, reads leaves in order and stops after 20, no sort needed |
| `WHERE email LIKE 'gau%'` | Yes, prefix (needs `text_pattern_ops` or C collation) |
| `WHERE email LIKE '%gmail.com'` | **No**, a leading wildcard has no sorted starting point |
| `WHERE lower(email) = 'a@x.com'` | **No**, unless you have an index on `lower(email)` |
| `MIN(created_at)`, `MAX(created_at)` | Yes, just the first or last leaf |

## 3. Index scan, index-only scan, bitmap scan, seq scan

The **query planner** estimates the cost of each option using table statistics, then picks the cheapest:

- **Index scan:** walk the tree, then fetch each matching row from the heap. Great when few rows match.
- **Index-only scan:** every column the query needs is *in the index*, so it skips the heap entirely. Fastest.
- **Bitmap index scan → bitmap heap scan:** for a medium number of matches, collect all the row locations first, sort them by page, then read each heap page once. This avoids jumping around randomly. It can also combine two indexes with AND/OR.
- **Seq scan:** read the whole table. Often **the right choice** when a big fraction of rows match (roughly 5–10% or more), because reading pages in order is much faster than thousands of random jumps.

**Key idea: selectivity.** An index pays off when the condition matches *few* rows. `WHERE email = ...` matches 1 row out of 20M, which is perfect. `WHERE status = 'new'` might match 40% of rows, so the planner will ignore the index and seq scan, correctly.

## 4. Composite (multi-column) indexes: the left-prefix rule

```sql
CREATE INDEX idx_leads_tenant_status_created ON leads (tenant_id, status, created_at);
```
The index is sorted by `tenant_id`, then by `status` within each tenant, then by `created_at` within each status. It's like a phone book sorted by surname, then first name.

| Query filters on | Uses this index? | Why |
|---|---|---|
| `tenant_id` | Yes | Leftmost column |
| `tenant_id, status` | Yes | Left prefix |
| `tenant_id, status` + `ORDER BY created_at` | Yes, **perfectly** | Filters narrow it down, and the rest is already sorted |
| `tenant_id` + `created_at` (no status) | Partly | Uses `tenant_id`, then has to scan every status within that tenant |
| `status` only | Usually no | Skips the first column, like finding everyone named "Rahul" in a phone book sorted by surname |
| `created_at` only | No | Same reason |

**How to order the columns:**
1. **Equality filters first** (`tenant_id = ?`, `status = ?`).
2. **Range or sort column last** (`created_at > ?`, `ORDER BY created_at`).
3. Among the equality columns, put the one you *always* filter on first. In a multi-tenant app that's `tenant_id`, which is why tenant-first indexes come up in multi-tenancy answers.

`(a, b)` makes a separate index on `(a)` redundant. `(a)` alone does **not** help a query on `b`.

## 5. Special index types you should name

| Type | What it is | Use it for | Example |
|---|---|---|---|
| **Unique** | B-tree that rejects duplicates | Enforcing business rules | `CREATE UNIQUE INDEX ON leads (tenant_id, email);` (unique *per institution*) |
| **Partial** | Indexes only rows matching a `WHERE` | Smaller, faster index for the rows you query | `CREATE INDEX ON leads (tenant_id, created_at) WHERE deleted_at IS NULL;` (fits soft delete) |
| **Expression** | Indexes a computed value | Queries that wrap a column in a function | `CREATE INDEX ON leads (lower(email));` |
| **Covering** (`INCLUDE`) | Extra columns stored in the leaf, not used for sorting | Enables index-only scans | `CREATE INDEX ON leads (tenant_id, status) INCLUDE (name, email);` |
| **Hash** | Hash table | Exact `=` only, no ranges | Rarely better than a B-tree |
| **GIN** | Inverted index: each element → list of rows | JSONB, arrays, full-text search | `CREATE INDEX ON leads USING gin (custom_fields);` for per-institution custom fields |
| **GiST** | Generalised search tree | Geo data, ranges, nearest-neighbour | Campus location search |
| **BRIN** | Stores min/max per block of pages; tiny | Huge, append-only, naturally ordered data | Event or log tables ordered by time |

Primary keys and unique constraints automatically create a unique B-tree index. **Foreign keys do not** in Postgres: index `counsellor_id` yourself if you join or delete on it. (MySQL InnoDB does index FKs automatically, and it stores the table itself ordered by the primary key, a "clustered index".)

## 6. The cost of indexes (why not index everything?)

1. **Slower writes:** every `INSERT` must add an entry to *every* index on the table, and every `UPDATE` to an indexed column must update it. 8 indexes means roughly 9 writes per insert, plus more WAL (write-ahead log) and replication traffic.
2. **Storage and memory:** indexes take disk space and compete for RAM (the buffer cache) with the actual data. An index that doesn't fit in memory gets slower.
3. **Maintenance:** indexes bloat over time with updates and deletes; vacuum and occasional `REINDEX` are needed.
4. **Planner confusion:** many overlapping indexes make plans harder to predict.

## 7. When NOT to add an index (the interview answer)

- **Small tables:** a few thousand rows fit in a handful of pages, and a seq scan is faster than walking a tree.
- **Low-cardinality columns on their own**, like `status`, `is_active` or `gender`: each value matches a big chunk of the table, so the planner seq scans anyway. If you only ever query the rare value, use a *partial* index (`WHERE status = 'enrolled'`) instead.
- **Write-heavy tables with few reads:** logs, events or audit tables, where insert speed matters more than lookups. Consider BRIN or nothing.
- **Columns you never filter, join or sort on.**
- **Duplicates or overlaps:** `(tenant_id)` is redundant if `(tenant_id, created_at)` exists.
- **During bulk loads:** drop indexes, load with `COPY`, then recreate them. That's much faster than maintaining them row by row.
- **When the query can't use it anyway:** `LIKE '%x'`, a function on the column, or a mismatched type. Fix the query or add the right expression index.

## 8. Things that silently stop an index being used

- A function or operation on the column: `WHERE lower(email) = ...`, `WHERE created_at::date = '2026-10-08'`, `WHERE amount + 0 = 5`. Rewrite as a range (`created_at >= '2026-10-08' AND created_at < '2026-10-09'`) or add an expression index.
- A leading wildcard: `LIKE '%term'`. Use full-text search or a trigram GIN index (`pg_trgm`).
- Type mismatch: comparing a `bigint` column to a text parameter.
- `OR` across different columns. The planner may combine two indexes with a bitmap scan, or it may not; `UNION` is sometimes better.
- Skipping the leftmost column of a composite index.
- Stale statistics: the planner thinks a table is tiny. Run `ANALYZE`.

## 9. How to check: `EXPLAIN ANALYZE`

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name FROM leads
WHERE tenant_id = '…' AND status = 'new'
ORDER BY created_at DESC LIMIT 20;
```
**Before** (no useful index):
```
Limit (actual time=4210.3..4210.4 rows=20)
  -> Sort (Sort Method: top-N heapsort)
     -> Seq Scan on leads (rows=20000000) Filter: tenant_id = … AND status = 'new'
        Rows Removed by Filter: 19985000
```
**After** `CREATE INDEX ON leads (tenant_id, status, created_at DESC);`:
```
Limit (actual time=0.05..0.09 rows=20)
  -> Index Scan using leads_tenant_id_status_created_at_idx on leads
```
What to look for: `Seq Scan` on a big table, a large `Rows Removed by Filter`, a `Sort` that spills to disk, and estimated rows far off from actual rows (stale stats).

**Find unused indexes** (all cost, no benefit):
```sql
SELECT relname AS table, indexrelname AS index, idx_scan
FROM pg_stat_user_indexes WHERE idx_scan = 0 ORDER BY pg_relation_size(indexrelid) DESC;
```

**Add indexes safely in production:** `CREATE INDEX CONCURRENTLY ...` builds without locking writes. It's slower and can't run inside a transaction, but it doesn't take the app down.

## 10. Designing indexes from queries (the method)

Don't index columns, **index queries**. List the app's hot queries, then build one index per pattern:

| Query in the app | Index |
|---|---|
| Lead list page: tenant + status, newest first | `(tenant_id, status, created_at DESC)` |
| Lookup by email during import (dedupe) | `UNIQUE (tenant_id, email)` |
| Counsellor's assigned leads | `(counsellor_id)` (also helps FK joins) |
| Only non-deleted rows everywhere | add `WHERE deleted_at IS NULL` to the above (partial) |
| Search custom fields (JSONB) | `GIN (custom_fields)` |

Then verify each one with `EXPLAIN ANALYZE` and watch write latency.

---

## Spoken interview answer (~60–90 seconds)

> "An index is a separate sorted structure, usually a B-tree, that maps column values to row locations, so the database can find rows in O(log n) instead of scanning the whole table. The B-tree is very wide and shallow: millions of rows is only 3 or 4 levels, so a lookup is a few page reads. Because the leaves are sorted and linked, it also handles ranges and `ORDER BY` without a separate sort.
> For multi-column indexes, the left-prefix rule applies: `(tenant_id, status, created_at)` helps queries filtering on tenant, or tenant and status, and serves the sort on created_at, but not a query on status alone. I put equality columns first and the range or sort column last. In multi-tenant systems that means tenant_id first.
> Postgres also has partial indexes, like `WHERE deleted_at IS NULL` for soft deletes, expression indexes for things like `lower(email)`, covering indexes for index-only scans, and GIN for JSONB and full-text search.
> When not to index: small tables, low-cardinality columns like a boolean on their own, write-heavy tables like logs where every index slows inserts, columns you never filter or sort on, and duplicate indexes. Indexes cost write speed, storage and memory. And always verify with `EXPLAIN ANALYZE`: if the planner expects a large share of rows to match, it will correctly choose a sequential scan anyway."

---

## Self-quiz (answers below)
1. You have an index on `(tenant_id, created_at)`. Does `WHERE created_at > '2026-01-01'` use it?
2. `WHERE status = 'new'` matches 40% of rows and there's an index on `status`. Why does Postgres ignore it?
3. Why does `WHERE lower(email) = 'x'` not use an index on `email`, and what are the two fixes?
4. Does Postgres automatically index foreign keys?
5. You must load 5 million rows into an indexed table tonight. What do you do?
6. What makes an index-only scan possible?

**Answers:** 1) Not efficiently, because it skips the leftmost column. 2) Low selectivity: a seq scan is cheaper than millions of random heap reads. 3) The index stores `email`, not `lower(email)`; add an expression index on `lower(email)`, or store emails already lowercased (normalise on write, like the Pydantic validator in the FastAPI demo). 4) No, only primary keys and unique constraints; index FK columns yourself. 5) Drop or skip secondary indexes, `COPY` the data, recreate indexes (`CONCURRENTLY` if the table is live), then `ANALYZE`. 6) All columns the query needs are in the index (via key columns or `INCLUDE`), and the visibility map shows the pages are all-visible, so the heap can be skipped.
