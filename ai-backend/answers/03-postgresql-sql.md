# Document 03 — PostgreSQL / SQL (Questions 101–170)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 101. Primary key?

**Definition.** A column or set of columns that uniquely identifies each row. Implies `NOT NULL` + `UNIQUE`, and PostgreSQL automatically creates a B-tree index for it. One per table.

**Why.** Row identity is the basis for updates, deletes, foreign keys, and replication. Without it you cannot reliably address a single row.

**Natural vs surrogate.** A natural key uses real data (email, ISBN). A surrogate key is meaningless and system-generated (UUID, bigint). **Prefer surrogate** — natural keys change (people change emails), and a changing primary key cascades through every referencing table.

**`bigint` identity vs UUID:**
- `GENERATED ALWAYS AS IDENTITY` — 8 bytes, sequential, excellent index locality, but enumerable (`/orders/1002` reveals volume) and hard to generate client-side or merge across shards.
- **UUIDv4** — 16 bytes, unguessable, generatable anywhere. But random values scatter B-tree inserts across the whole index, causing page splits and write amplification.
- **UUIDv7** — time-ordered UUID. Unguessable *and* sequential, so you get index locality back. Native `uuidv7()` arrived in PostgreSQL 18; before that, generate it in the application. **This is the modern default for distributed systems.**

**Failure.** UUIDv4 primary keys on a high-insert table. Insert throughput degrades measurably as the index grows, because every insert lands on a random page.

---

## 102. Foreign key?

**Definition.** A constraint requiring a column's values to exist in another table's primary/unique key. Enforces referential integrity in the database.

**Implementation.**
```sql
order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE
```
Referential actions: `CASCADE`, `RESTRICT` (default, blocks), `SET NULL`, `SET DEFAULT`, `NO ACTION` (like RESTRICT but deferrable).

**The thing people miss:** PostgreSQL indexes the *referenced* side automatically (it's a PK) but **not the referencing side**. An unindexed FK column makes every delete on the parent do a sequential scan of the child table to check the constraint. On a large child table this turns a 1ms delete into a 30-second one. **Always index your foreign key columns.**

**Failure.** `ON DELETE CASCADE` on something you didn't intend to be destructive — deleting a user silently removes their entire order history and the associated financial records. For anything auditable, use `RESTRICT` and soft-delete instead.

**Trade-off.** FKs guarantee integrity but add a check on every write, complicate bulk loads and migrations, and constrain sharding (you cannot enforce an FK across databases). High-throughput systems sometimes drop them and enforce in application code — a real trade-off, not a best practice.

---

## 103. Normalization?

**Definition.** Organising data to eliminate redundancy, so each fact is stored exactly once.

- **1NF** — atomic values, no repeating groups
- **2NF** — 1NF + no partial dependency on part of a composite key
- **3NF** — 2NF + no transitive dependency (non-key columns depend only on the key)
- **BCNF** — a stricter 3NF

Practical summary: *every non-key column depends on the key, the whole key, and nothing but the key.*

**Why.** Redundancy causes update anomalies. If a customer's address is stored on every order row, changing it means updating thousands of rows, and any missed row is now wrong. Normalised, there's one row to change.

**Denormalisation is a deliberate trade.** You duplicate data to avoid joins, accepting update complexity for read speed. Legitimate when reads vastly outnumber writes and the join is genuinely expensive.

**The one place denormalisation is mandatory:** financial records must store the price *as it was at the time*, not join to a current price. That's not denormalisation for performance — it's correctness. An invoice from 2023 must not change when you update your price list.

---

## 104. INNER vs LEFT JOIN?

**INNER JOIN** returns rows where the condition matches in both tables. **LEFT JOIN** returns all rows from the left table, with NULLs where the right has no match.

```sql
-- users who have placed orders
SELECT u.*, o.* FROM users u INNER JOIN orders o ON o.user_id = u.id;

-- all users, with order data where it exists
SELECT u.*, o.* FROM users u LEFT JOIN orders o ON o.user_id = u.id;

-- users with NO orders (anti-join)
SELECT u.* FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE o.id IS NULL;
```

**The classic bug.** Putting a filter on the right table in `WHERE` instead of `ON`:
```sql
-- silently becomes an INNER JOIN
LEFT JOIN orders o ON o.user_id = u.id WHERE o.status = 'paid'

-- correct: filter in the join condition
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'paid'
```
The first drops every user with no paid orders, because their `o.status` is NULL and `NULL = 'paid'` is not true. This is one of the most common SQL bugs in production.

**Also:** joining one-to-many multiplies rows. A user with 5 orders appears 5 times, and `SUM(u.credit)` now counts their credit 5 times. Aggregate in a subquery or use `DISTINCT` deliberately.

---

## 105. WHERE vs HAVING?

**`WHERE` filters rows before grouping. `HAVING` filters groups after aggregation.**

```sql
SELECT user_id, COUNT(*) AS n
FROM orders
WHERE created_at > now() - interval '30 days'   -- filters rows first
GROUP BY user_id
HAVING COUNT(*) > 5;                             -- filters groups after
```

**Execution order** (the mental model that answers most SQL questions): `FROM → JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT`.

This explains several oddities: you can't reference a `SELECT` alias in `WHERE` (SELECT hasn't run yet), but you *can* in `ORDER BY`. And `HAVING` can use aggregates because grouping has already happened.

**Performance point.** Filter in `WHERE` whenever you can — it reduces rows *before* the expensive grouping. Putting a non-aggregate condition in `HAVING` is correct but wasteful.

---

## 106. GROUP BY?

**Definition.** Collapses rows sharing the same values in the grouped columns into one row per group, so aggregates (`COUNT`, `SUM`, `AVG`, `MIN`, `MAX`) can be computed per group.

**Rule.** Every column in `SELECT` must either appear in `GROUP BY` or be inside an aggregate. PostgreSQL enforces this strictly (MySQL historically did not, which produced silently arbitrary results).

**Exception worth knowing:** if you group by a primary key, PostgreSQL allows other columns of that table, since the PK functionally determines them.

**Useful extensions:**
```sql
GROUP BY GROUPING SETS ((region), (product), ())   -- multiple groupings at once
GROUP BY ROLLUP(region, product)                    -- subtotals + grand total
FILTER (WHERE status='paid')                        -- conditional aggregation
```
`FILTER` is much cleaner than `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`:
```sql
SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE status='paid') AS paid
FROM orders;
```

**Window functions vs GROUP BY** — the distinction interviewers probe: `GROUP BY` collapses rows; window functions (`OVER (PARTITION BY ...)`) compute per-group values while *keeping* every row.

---

## 107. What is an index?

**Definition.** A separate data structure mapping column values to row locations, letting the database find rows without scanning the table.

**Why.** Without one, finding rows means reading every page — O(n). A B-tree index is O(log n). On a 10-million-row table that's the difference between 3 seconds and 0.1 milliseconds.

**Types in PostgreSQL:**

| Type | Use |
|---|---|
| **B-tree** (default) | Equality, ranges, sorting, `LIKE 'prefix%'` |
| **Hash** | Equality only; rarely worth it over B-tree |
| **GIN** | Multi-valued: JSONB, arrays, full-text search |
| **GiST** | Geometric, ranges, nearest-neighbour |
| **BRIN** | Very large naturally-ordered tables (time-series); tiny index, coarse |
| **HNSW / IVFFlat** (pgvector) | Vector similarity — see Document 09 |

**Key structural fact.** PostgreSQL indexes do not store visibility information. An index entry doesn't know whether the row it points to is visible to your transaction — so the engine usually must visit the heap too. The **visibility map** enables index-only scans when a page is known all-visible, which is one reason `VACUUM` matters for read performance.

---

## 108. Why can indexes slow writes?

**Because every index must be updated on every write that touches it.**

- **INSERT** — one heap write plus one index entry per index. Five indexes means six writes.
- **UPDATE** — PostgreSQL's MVCC creates a *new row version*, so it must add index entries for every index, even ones whose columns didn't change. The exception is a **HOT update** (Heap-Only Tuple): if no indexed column changed *and* there's free space on the same page, PostgreSQL skips index updates entirely. Maintaining `fillfactor` below 100 on update-heavy tables makes HOT updates more likely — a genuinely useful tuning lever.
- **DELETE** — index entries aren't removed immediately; they're cleaned up by `VACUUM`.

**Secondary costs:** more WAL written (which means more replication traffic and slower recovery), more memory competing for shared buffers, more disk, and longer `VACUUM` runs.

**Rule of thumb.** Each additional index costs roughly 10–20% write throughput on that table. Five indexes can halve your insert rate.

**Finding waste:**
```sql
SELECT relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes WHERE idx_scan = 0 ORDER BY pg_relation_size(indexrelid) DESC;
```
Unused indexes cost writes and buy nothing. Drop them (after confirming across a full business cycle — a monthly report's index looks unused for 29 days).

---

## 109. What is a transaction?

**Definition.** A unit of work that either fully completes or has no effect. Bounded by `BEGIN` and `COMMIT`/`ROLLBACK`.

**Why.** Multi-step operations must not be observable half-done. Debiting one account and crediting another must be atomic, or money is created or destroyed.

**In PostgreSQL:** every statement runs in a transaction even without an explicit `BEGIN` (autocommit wraps it). PostgreSQL supports transactional DDL — you can `BEGIN; ALTER TABLE ...; ROLLBACK;` which most databases cannot, and which makes migrations dramatically safer.

**Savepoints** allow partial rollback:
```sql
BEGIN;
  INSERT INTO a ...;
  SAVEPOINT sp1;
  INSERT INTO b ...;      -- fails
  ROLLBACK TO sp1;        -- keeps the first insert
COMMIT;
```

**Failure.** Leaving a transaction open. `idle in transaction` sessions hold locks and — worse — hold back the xmin horizon, which prevents `VACUUM` from cleaning up dead tuples *anywhere in the database*. One forgotten transaction can cause table bloat across your entire system. Set `idle_in_transaction_session_timeout`.

---

## 110. ACID?

**Atomicity** — all or nothing. Implemented via WAL: changes are logged before being applied; on crash, incomplete transactions are undone.

**Consistency** — the database moves from one valid state to another, respecting constraints, FKs, and triggers. Note this is the *weakest* of the four as a database guarantee; much of "consistency" is your schema's job, not the engine's.

**Isolation** — concurrent transactions don't observe each other's intermediate states. Implemented via MVCC in PostgreSQL. This is the property with *levels* (Q131–133) and the one with real trade-offs.

**Durability** — once committed, it survives a crash. Implemented by `fsync`ing the WAL before acknowledging the commit.

**The nuance that shows depth:** durability is configurable. `synchronous_commit = off` acknowledges commits before the WAL is flushed — dramatically faster, at the risk of losing the last few hundred milliseconds of committed transactions on a crash. Legitimate for analytics ingestion, never for payments. Similarly, `fsync = off` is a "my data is disposable" setting.

**Also worth saying:** the "C" in ACID and the "C" in CAP are different things and are frequently conflated in interviews.

---

## 111. Constraints?

Rules the database enforces on data:

| Constraint | Purpose |
|---|---|
| `NOT NULL` | Value required |
| `UNIQUE` | No duplicates (multiple NULLs allowed — they're not equal to each other) |
| `PRIMARY KEY` | NOT NULL + UNIQUE, one per table |
| `FOREIGN KEY` | Referential integrity |
| `CHECK` | Arbitrary boolean expression |
| `EXCLUDE` | Generalised uniqueness — e.g. no overlapping time ranges |

```sql
CREATE TABLE bookings (
  room_id INT,
  during TSRANGE,
  EXCLUDE USING gist (room_id WITH =, during WITH &&)   -- no double-booking
);
```

**Why enforce in the database rather than the application.** The database is the last line and the only shared one. Application code has bugs, admins run manual SQL, migrations misbehave, and multiple services may write to the same table. A constraint makes bad data *impossible*, not merely unlikely.

**Failure.** Adding `NOT NULL` to a large existing table takes an `ACCESS EXCLUSIVE` lock and rewrites it — an outage. Use `NOT VALID` + `VALIDATE CONSTRAINT` for CHECK constraints, or add the column with a default (which is metadata-only in PostgreSQL 11+).

---

## 112. Unique constraint?

**Definition.** Guarantees no two rows share the same value(s). Implemented with a unique B-tree index.

**The NULL rule.** By default, NULLs are considered distinct, so multiple rows can have NULL in a unique column. PostgreSQL 15 added `NULLS NOT DISTINCT` to change that:
```sql
CREATE UNIQUE INDEX ... ON t (a, b) NULLS NOT DISTINCT;
```

**Its most valuable use is not preventing duplicates — it's providing atomic concurrency control.** The database serialises unique checks, so a unique constraint gives you race-free deduplication:
```sql
INSERT INTO processed_events (event_id) VALUES ($1)
ON CONFLICT (event_id) DO NOTHING;
```
Two concurrent workers processing the same event: exactly one insert succeeds. This is the foundation of idempotency (Q42, Q160) and it works across processes, unlike any application-level lock.

**Partial unique index** — uniqueness only under a condition:
```sql
CREATE UNIQUE INDEX one_active_sub ON subscriptions (user_id)
  WHERE status = 'active';
```
One active subscription per user, unlimited cancelled ones. Extremely useful and underused.

---

## 113. Partial index?

**Definition.** An index over only the rows matching a `WHERE` clause.

```sql
CREATE INDEX idx_pending_jobs ON jobs (created_at) WHERE status = 'pending';
```

**Why.** If 99% of your jobs are `completed` and you only ever query `pending`, a full index wastes 99% of its size on rows you'll never look for. The partial index is 100× smaller — it fits in memory, is faster to scan, and costs nothing to maintain for completed rows.

**Requirement.** The planner uses it only if it can prove your query's `WHERE` implies the index predicate. `WHERE status = 'pending' AND created_at > $1` matches. `WHERE status = $1` with a parameter does **not** — the planner can't prove `$1 = 'pending'` at plan time. This surprises people constantly.

**Best uses:**
- Queue tables (index only unprocessed rows)
- Soft deletes (`WHERE deleted_at IS NULL`)
- Enforcing conditional uniqueness (Q112)
- Any heavily-skewed status column

**Real example.** A `runs` table with 50 million rows, of which ~200 are `queued` at any moment. A partial index on `queued` makes the worker's claim query a sub-millisecond operation forever, regardless of table growth.

---

## 114. Composite index?

**Definition.** An index on multiple columns, ordered.

```sql
CREATE INDEX idx_orders ON orders (tenant_id, status, created_at DESC);
```

**The leftmost-prefix rule.** The index can serve queries filtering on a leading prefix:

| Query filter | Uses index? |
|---|---|
| `tenant_id` | Yes |
| `tenant_id, status` | Yes |
| `tenant_id, status, created_at` | Yes, fully |
| `status` alone | No (not a prefix) |
| `tenant_id, created_at` | Partially — seeks on `tenant_id`, then filters |

Think of a phone book sorted by (last name, first name). Finding "Kumar, Gautam" is fast. Finding everyone named "Gautam" regardless of surname is not.

**Column order rules:**
1. Equality columns first, range/sort columns last.
2. Among equality columns, most selective generally first — though for prefix reuse, put the column that's *always* in the query first (usually `tenant_id`).
3. Match `ORDER BY` direction to get a sorted scan for free.

**Covering indexes:**
```sql
CREATE INDEX ... ON orders (tenant_id, status) INCLUDE (total_cents);
```
`INCLUDE` stores extra columns in the leaf pages without making them part of the key, enabling an **index-only scan** — the heap is never visited. Excellent for hot read paths.

**Trade-off.** One composite index often replaces several single-column ones (fewer writes, less space). But it's larger per entry and less flexible.

---

## 115. Offset vs cursor pagination?

**OFFSET** — `LIMIT 20 OFFSET 10000`. **Cursor (keyset)** — `WHERE (created_at, id) < ($1, $2) ORDER BY created_at DESC, id DESC LIMIT 20`.

**Why OFFSET is bad:**
1. **It's O(offset).** The database must generate and discard all 10,000 rows before returning 20. Page 1 is instant; page 500 takes seconds. Performance degrades linearly with page depth.
2. **It's incorrect under concurrent writes.** If a row is inserted between requests, everything shifts — the user sees an item twice or misses one entirely. Silent data loss in the UI.

**Cursor pagination fixes both.** It's O(log n) via index seek, constant regardless of depth, and stable under inserts.

```sql
-- first page
SELECT * FROM orders WHERE tenant_id=$1
ORDER BY created_at DESC, id DESC LIMIT 20;

-- next page, cursor = last row's (created_at, id)
SELECT * FROM orders
WHERE tenant_id=$1 AND (created_at, id) < ($2, $3)
ORDER BY created_at DESC, id DESC LIMIT 20;
```
The row-value comparison `(a, b) < (x, y)` is the clean way to express this and maps directly onto a composite index. **Include a unique tiebreaker (`id`)** — without it, rows sharing a timestamp get skipped or repeated.

Encode the cursor as an opaque base64 token so clients don't depend on its structure.

**Trade-off.** Cursor pagination can't jump to page 47 and can't show a total count cheaply. If the product genuinely needs numbered pages, OFFSET on a small bounded set is acceptable; for infinite scroll and APIs, cursors are strictly correct.

---

# L2 — Indexes and the planner

## 116. How does a B-tree work conceptually?

**Structure.** A balanced tree. The root and internal nodes hold separator keys and child pointers; leaf nodes hold indexed values plus TIDs (physical row pointers). All leaves are at the same depth — that's the "balanced" part, and it's why lookup cost is uniform.

**Lookup.** Start at the root, binary-search the keys to pick a child, descend, repeat, arrive at a leaf. Depth is `log_f(n)` where `f` is the fanout — typically several hundred, since a node is an 8 KB page holding many keys.

**The number that makes it concrete:** with a fanout of ~200, a 3-level tree indexes ~8 million rows; 4 levels indexes ~1.6 billion. So finding one row among a billion is 4 page reads, and the top levels are almost always cached in memory. That's why an index lookup is microseconds.

**Range scans are the other half.** Leaf pages are linked in a doubly-linked list, so `WHERE created_at BETWEEN a AND b` descends once to the start and then walks leaves sequentially. This is why B-trees serve ranges, sorting, `ORDER BY`, `MIN`/`MAX`, and prefix `LIKE` — and why hash indexes, which support none of that, are rarely worth using.

**Writes.** Insert into the right leaf; if full, split it in half and push a separator up, potentially cascading to the root. Splits are why random-UUID inserts hurt: sequential keys always append to the rightmost leaf (cheap, cache-hot), random keys split pages all over the index.

**Bloat.** PostgreSQL doesn't merge underfull pages. After heavy deletion an index can stay large and sparse. `REINDEX CONCURRENTLY` rebuilds it without blocking writes.

---

## 117. When will PostgreSQL not use an index?

**The planner is cost-based, not rule-based.** It chooses whatever it estimates is cheapest. It declines an index when:

**1. Low selectivity.** If the query returns a large fraction of the table (roughly >5–10%), a sequential scan is genuinely cheaper. An index scan does random I/O per row plus a heap fetch; a seq scan does sequential I/O and reads each page once. **This is the planner being right, not wrong.**

**2. Small table.** Under a few hundred rows, everything is on a handful of pages already in memory.

**3. Function applied to the column** — the classic:
```sql
WHERE lower(email) = 'x@y.com'          -- index on (email) unusable
WHERE created_at::date = '2026-01-01'   -- index on (created_at) unusable
WHERE amount * 100 > 5000               -- unusable
```
Fix with an expression index (`CREATE INDEX ON users (lower(email))`) or rewrite as a range (`created_at >= '2026-01-01' AND created_at < '2026-01-02'`).

**4. Type mismatch.** Comparing `bigint` to a `numeric` parameter can prevent index use. Cast the parameter, not the column.

**5. Leading wildcard.** `LIKE '%abc%'` — no prefix to seek on (Q118).

**6. `OR` across different columns.** Sometimes resolved via BitmapOr; often better rewritten as `UNION ALL`.

**7. Stale statistics.** The planner thinks the table has 1,000 rows when it has 10 million. `ANALYZE` fixes it. This is the most common cause of a query that was fast yesterday and is slow today.

**8. Not a leftmost prefix** of a composite index (Q114).

**9. `NULL` handling** — `IS NULL` can use a B-tree in PostgreSQL, but `<> value` generally cannot.

**Diagnosis:** `EXPLAIN (ANALYZE, BUFFERS)`. Compare the planner's estimated rows to actual rows. A large gap means bad statistics — that's the root cause, and forcing the index with `enable_seqscan=off` treats the symptom while leaving the disease.

---

## 118. Why is `%abc%` expensive?

**Because a B-tree is sorted by value from the left.** It can seek to a known prefix, but `%abc%` has no known prefix — the match could begin at any character position of any row. So the only option is to read every row and test it. Full sequential scan, every time.

`LIKE 'abc%'` **is** indexable (with a caveat: for non-C collations you need `text_pattern_ops` for the index to be usable by `LIKE`).

**The fixes, by use case:**

**1. Trigram index — the direct solution:**
```sql
CREATE EXTENSION pg_trgm;
CREATE INDEX idx_name_trgm ON users USING gin (name gin_trgm_ops);
-- now LIKE '%abc%' and ILIKE '%abc%' can use the index
```
It decomposes text into 3-character grams and indexes those. Also enables fuzzy matching (`similarity()`, `%` operator) for typo-tolerant search.

**2. Full-text search** — for word-based rather than substring search:
```sql
CREATE INDEX ON docs USING gin (to_tsvector('english', body));
WHERE to_tsvector('english', body) @@ plainto_tsquery('english', 'invoice');
```
Handles stemming and ranking; doesn't do substrings.

**3. Reverse index for suffix search:** `CREATE INDEX ON t (reverse(col) text_pattern_ops)` makes `%abc` indexable.

**4. A dedicated search engine** (Elasticsearch, Typesense) when you need relevance ranking, facets, and typo tolerance at scale.

**The AI-relevant version:** semantic search with embeddings solves the *meaning* problem that neither `LIKE` nor full-text solves — but it doesn't solve exact substring matching. In practice, production RAG uses **hybrid** retrieval: BM25/trigram for lexical precision plus vector search for semantics, fused with RRF (Q361).

---

## 119. Why does composite-index column order matter?

Because a composite index is sorted by the first column, then the second within each first-column value, and so on. It's a single ordered list, not a set of independent lookups.

Given `(a, b, c)`, the index is effectively sorted by the concatenation. You can seek to a value of `a`, then within it to a value of `b`. But you cannot seek directly to a value of `b` without knowing `a` — those entries are scattered throughout.

**Practical impact:**
```sql
CREATE INDEX ON events (tenant_id, event_type, created_at);

WHERE tenant_id=$1                                    -- seek
WHERE tenant_id=$1 AND event_type='click'             -- seek
WHERE tenant_id=$1 AND event_type='click'
  AND created_at > $2                                 -- seek + range: ideal
WHERE event_type='click'                              -- cannot seek
```

**The ordering rules:**
1. **Equality before range.** `(status, created_at)` supports `status = 'x' AND created_at > y` with a clean seek-then-range. `(created_at, status)` forces scanning a date range and filtering — much worse.
2. **Once you hit a range column, subsequent columns can only filter, not seek.** So only one range column is useful, and it goes last.
3. **Match `ORDER BY`** — including direction — to avoid a sort step entirely.
4. **Put the always-present column first.** In multi-tenant systems that's `tenant_id`, which also makes one index serve many query shapes.

**Verification.** In `EXPLAIN`, look at `Index Cond` versus `Filter`. Conditions in `Index Cond` were used to seek; conditions in `Filter` were applied after reading rows — that's the wasted work column order is meant to eliminate.

---

## 120. What is selectivity?

**Definition.** The fraction of rows a predicate is estimated to return. `WHERE id = 5` on a million-row table has selectivity 0.000001 — highly selective. `WHERE is_active = true` where 95% are active has selectivity 0.95 — poorly selective.

**Why it drives everything.** The planner multiplies selectivity by table size to estimate row counts, and row counts determine whether an index scan or a sequential scan wins, which join algorithm to use, and join order. Get selectivity wrong and every subsequent decision is wrong.

**How PostgreSQL estimates it.** From `pg_statistic`, populated by `ANALYZE`:
- **Most Common Values (MCVs)** with their frequencies — exact for skewed data
- **A histogram** of the remaining values — for range estimation
- **n_distinct** — number of distinct values
- **correlation** — how well physical order matches logical order (drives index scan cost)

**Where estimation goes wrong:**
- **Correlated columns.** `WHERE city='Patna' AND state='Bihar'` — the planner multiplies the two selectivities as if independent, underestimating badly. Fix with `CREATE STATISTICS ... (dependencies)`.
- **Skew beyond the MCV list.** Raise `default_statistics_target` or set it per column: `ALTER TABLE t ALTER COLUMN c SET STATISTICS 1000;`
- **Expressions** the planner can't reason about — it falls back to a hardcoded default guess.
- **Stale stats** after bulk loads.

**Diagnosis.** In `EXPLAIN ANALYZE`, compare `rows=` (estimate) to `actual rows=`. A 100× discrepancy is your root cause. Fixing statistics is almost always better than forcing a plan.

---

## 121. What is cardinality?

Used in two senses, and being precise about both is worth a point:

**1. Column cardinality** — the number of distinct values. `is_active` has cardinality 2 (low); `email` has cardinality ≈ row count (high, unique).

**2. Result cardinality** — the number of rows a node in the plan produces. This is what `EXPLAIN` estimates, and what planners get wrong.

**Relationship to selectivity:** high cardinality generally means predicates on that column are more selective, so indexes help more. Indexing a boolean is usually pointless — unless the distribution is heavily skewed, in which case a *partial* index on the rare value is excellent (Q113).

**Why cardinality estimation errors compound.** In a 5-table join, a 10× error at the first join becomes 10× wrong input to the second, which may then choose a nested loop where it should have chosen a hash join, and so on. Multi-table joins are where estimation errors turn a 50ms query into an 8-second one (Q166). PostgreSQL's `join_collapse_limit` and extended statistics exist precisely because of this.

---

## 122. Sequential scan?

**Definition.** Read every page of the table from start to finish, applying the filter to each row.

**Cost:** O(n) in pages, but **sequential I/O**, which is far faster per page than random I/O — PostgreSQL's default `seq_page_cost=1.0` vs `random_page_cost=4.0` encodes this ratio.

**When it's correct** (and it often is):
- Returning a large fraction of the table
- Small tables
- No usable index
- Aggregating everything (`SELECT count(*) FROM t`)

**PostgreSQL optimisations:** parallel sequential scans split the table across workers; synchronised scans let concurrent scans share the same physical read; large scans use a small ring buffer so they don't evict your entire cache.

**When it's a problem.** A seq scan on a large table in an OLTP query path. The signature: fast in dev with 1,000 rows, catastrophic in production with 50 million. If `EXPLAIN` shows `Seq Scan` with a `Filter` that removes 99.9% of rows, you're missing an index.

---

## 123. Index scan?

**Definition.** Traverse the index to find matching entries, then fetch each corresponding row from the heap.

**Cost.** For each match: descend the B-tree (mostly cached) plus a **random** heap page read. So the cost is roughly `matching_rows × random_page_cost`. This is why it loses to a seq scan past a few percent of the table — random I/O per row eventually exceeds reading everything sequentially.

**Index-only scan** — the important variant. If every column the query needs is in the index, *and* the visibility map says the page is all-visible, the heap fetch is skipped entirely. Enormously faster.
```sql
CREATE INDEX ON orders (tenant_id, status) INCLUDE (total_cents);
SELECT total_cents FROM orders WHERE tenant_id=$1 AND status='paid';
```
In `EXPLAIN`, check `Heap Fetches:` — if it's high, your visibility map is stale and you need `VACUUM`. An index-only scan with many heap fetches isn't actually index-only.

**Correlation matters.** If the table's physical order matches the index order (high `correlation` in `pg_stats`), heap fetches become nearly sequential and the scan is much cheaper. `CLUSTER` physically reorders a table by an index — a one-time, locking operation, but occasionally the right answer for a read-heavy table.

---

## 124. Bitmap heap scan?

**Definition.** A two-phase strategy for when an index matches many rows: build an in-memory bitmap of the pages containing matches, then read those pages **in physical order**.

**Why it wins.** It converts scattered random reads into a mostly-sequential pass, and each page is read once even if it holds 50 matching rows. It's the planner's answer to "too many rows for a plain index scan, too few for a seq scan."

**In `EXPLAIN` it appears as two nodes:**
```
Bitmap Heap Scan on orders
  Recheck Cond: (status = 'paid')
  Heap Blocks: exact=1240 lossy=0
  -> Bitmap Index Scan on idx_status
```

**`lossy` is the number to watch.** If the bitmap exceeds `work_mem`, PostgreSQL degrades it from tracking individual rows to tracking whole pages. Then it must recheck every row on those pages — the `Recheck Cond`. Non-zero `lossy` means raising `work_mem` will likely help.

**BitmapAnd / BitmapOr** combine bitmaps from multiple indexes:
```sql
WHERE status='paid' AND created_at > $1     -- two indexes, ANDed
```
Useful, but a single composite index is usually faster than combining two. If you see BitmapAnd on the same two columns repeatedly, create the composite.

---

## 125. What does EXPLAIN show?

**The planner's chosen execution plan** — a tree of nodes, read inside-out and bottom-up. Each node shows:

```
Index Scan using idx_orders on orders  (cost=0.43..8.45 rows=1 width=64)
  Index Cond: (id = '...'::uuid)
  Filter: (status = 'paid')
```

- **cost=0.43..8.45** — estimated startup cost..total cost, in arbitrary units where 1.0 ≈ one sequential page read. Not milliseconds.
- **rows=1** — estimated output rows (the number that matters most)
- **width=64** — estimated average row width in bytes
- **Index Cond** — used to seek within the index (efficient)
- **Filter** — applied after fetching rows (wasteful; rows read then discarded)

**The startup vs total cost distinction matters.** A node with high startup cost (a sort, a hash build) must complete before producing the first row — bad under `LIMIT`. A low-startup node streams. This is why `LIMIT 10` can flip the planner to an entirely different plan.

**What to look for:** `Seq Scan` on a big table, large estimate-vs-actual gaps, `Filter` removing most rows, `Nested Loop` with a high row count on the outer side, and external sorts spilling to disk.

---

## 126. EXPLAIN vs EXPLAIN ANALYZE?

**`EXPLAIN`** — plans only. Does not execute. Fast, safe.

**`EXPLAIN ANALYZE`** — actually **runs the query** and reports real timings and row counts alongside the estimates.

**The critical safety warning:** `EXPLAIN ANALYZE` on an `UPDATE`/`DELETE`/`INSERT` *performs the write*. To inspect safely:
```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS) UPDATE ...;
ROLLBACK;
```

**Always use the full option set:**
```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, FORMAT TEXT) SELECT ...;
```
- **BUFFERS** — shared hit/read/dirtied. This tells you whether you're reading from cache or disk, which is the difference between a 2ms and a 200ms query with an otherwise identical plan. Arguably the most useful option and the most commonly omitted.
- **SETTINGS** — non-default planner settings in effect
- **WAL** — WAL generated by write statements

**Reading the output:**
```
Index Scan ... (cost=0.43..8.45 rows=1 width=64)
                (actual time=0.021..0.023 rows=1 loops=1)
```
- `actual time=startup..total` is **per loop, in milliseconds**
- **`loops=N` means multiply.** `actual time=0.5 rows=1 loops=10000` is 5 seconds and 10,000 rows, not 0.5ms and 1 row. This is the single most misread thing in `EXPLAIN` output.
- `rows=1` (estimate) vs `rows=50000` (actual) → statistics problem

**Caveat.** `ANALYZE` adds per-node timing instrumentation that can inflate total time on plans with many nodes. Use `EXPLAIN (ANALYZE, TIMING OFF)` to check whether measurement overhead is distorting the picture.

---

## 127. What does planner cost mean?

**An abstract, unitless estimate of resource consumption** used only to compare plans against each other. It is *not* milliseconds and does not convert to them.

**The base parameters:**
| Parameter | Default | Meaning |
|---|---|---|
| `seq_page_cost` | 1.0 | Sequential page read (the reference unit) |
| `random_page_cost` | 4.0 | Random page read |
| `cpu_tuple_cost` | 0.01 | Processing one row |
| `cpu_index_tuple_cost` | 0.005 | Processing one index entry |
| `cpu_operator_cost` | 0.0025 | One operator/function call |

**The most important tuning fact:** `random_page_cost = 4.0` was calibrated for spinning disks, where a seek genuinely cost ~4× a sequential read. **On SSDs the real ratio is closer to 1.1–1.5.** Leaving it at 4.0 on SSD storage systematically makes the planner under-value index scans, causing it to choose sequential scans that are actually slower. Setting `random_page_cost = 1.1` on SSD/NVMe is one of the highest-value single-line changes in PostgreSQL tuning.

Also set `effective_cache_size` to roughly 50–75% of system RAM. It doesn't allocate anything — it tells the planner how much data is likely already cached, which makes index scans look appropriately cheaper.

**How the plan is chosen.** The planner enumerates candidate plans (with `geqo` kicking in for very many tables), costs each, and picks the minimum. Cost estimates are only as good as the statistics feeding them (Q120).

---

## 128. What is the query planner?

**Definition.** The component that transforms parsed SQL into an execution plan. SQL is declarative — you state *what*, the planner decides *how*.

**Pipeline:** parse → rewrite (views, rules, RLS policies) → **plan/optimise** → execute.

**What the planner decides:**
- Access method per table (seq scan, index scan, bitmap, index-only)
- Join order (the combinatorially hardest part)
- Join algorithm: **nested loop** (good when one side is tiny), **hash join** (good for large unsorted equi-joins), **merge join** (good when both inputs are already sorted)
- Aggregation strategy: hash aggregate vs sorted group aggregate
- Whether to parallelise
- Whether to materialise intermediate results

**Prepared statements and the generic-plan trap.** PostgreSQL caches plans for prepared statements. After five executions it may switch from a custom plan (re-planned per parameter set) to a **generic plan** (planned once for all parameters). For skewed data this can be disastrous — a plan optimal for `status='completed'` (99% of rows) is terrible for `status='pending'` (0.001%). Control with `plan_cache_mode = force_custom_plan`. This is a real production failure mode that also shows up through connection poolers and ORMs, and knowing it signals depth.

**Its limits.** It can't see your application's semantics, it trusts its statistics completely, and it doesn't learn from past executions. When it's wrong, fix the statistics or rewrite the query — reaching for `enable_seqscan=off` is a last resort that hides the real problem.

---

## 129. Why can a sequential scan beat an index?

**Because an index scan does random I/O per matching row, plus a heap fetch, while a sequential scan does sequential I/O and touches each page exactly once.**

**The arithmetic.** A table has 1,000,000 rows across 10,000 pages, ~100 rows per page. A query matches 100,000 rows (10%).

- **Seq scan:** 10,000 sequential page reads. Cost ≈ 10,000 × 1.0 + 1,000,000 × 0.01 = 20,000.
- **Index scan:** 100,000 index entries plus up to 100,000 random heap fetches. Cost ≈ 100,000 × 4.0 = 400,000 plus index traversal.

The seq scan is 20× cheaper. **The planner is correct**, and this is the case people most often try to "fix" by forcing an index — making it slower.

**The crossover** is typically around 5–10% of the table, but it depends on:
- **Correlation.** If physical order matches index order, heap fetches are nearly sequential and the index wins much later.
- **Caching.** If everything is in `shared_buffers`, random I/O is nearly free and the index wins earlier. This is why `effective_cache_size` matters.
- **Row width.** Wide rows mean fewer per page, so a seq scan reads more pages.
- **`random_page_cost`.** On SSD, lowering it correctly shifts the crossover.

**The real fix when a seq scan is genuinely too slow:** don't force the index — make the query more selective, add a covering index for an index-only scan, add a partial index, or partition the table.

---

## 130. Offset vs cursor pagination at scale?

Q115 covered the mechanics; here is the scale story.

**OFFSET degrades linearly with depth.** Measured on a 10-million-row table:

| Page | OFFSET | Cursor |
|---|---|---|
| 1 | 1 ms | 1 ms |
| 100 | 15 ms | 1 ms |
| 10,000 | 900 ms | 1 ms |
| 100,000 | 9,000 ms | 1 ms |

The database generates and discards every skipped row. `OFFSET 1000000` produces a million rows to throw away. Under `ORDER BY`, it may also sort them all first.

**The operational consequence at scale.** A crawler or a script paginating to the end of a large table generates progressively slower queries. Each holds a connection longer. Enough of them and the connection pool saturates (Q86) — one background job walking a table takes down the API. This is a real and common outage shape.

**Cursor pagination is O(log n) per page**, forever. The composite index seek is identical work whether you're on page 1 or page 100,000.

**The two things cursors cost you:**
1. **No random page access.** No "jump to page 47". Usually fine — infinite scroll and "next/previous" cover almost every real UI.
2. **No cheap total count.** `SELECT count(*)` on a large filtered set is itself expensive. Options: show "1,000+", use `reltuples` from `pg_class` for an approximate total, or maintain a counter table.

**Implementation notes for production:**
- Always include a unique tiebreaker in the sort key, or rows at identical timestamps get skipped
- Use row-value syntax `(created_at, id) < ($1, $2)` — it maps cleanly onto a composite index
- Encode the cursor opaquely (base64 of a signed JSON blob) so it's not a client-visible contract
- For deep exports, don't paginate at all — use a server-side cursor (`DECLARE ... CURSOR`) or `COPY`

---

# L3 — Transactions and concurrency

## 131. Read Committed?

**PostgreSQL's default.** Each **statement** sees a snapshot taken at the moment that statement began. So within one transaction, two identical `SELECT`s can return different data if another transaction committed in between.

**Prevents:** dirty reads.
**Allows:** non-repeatable reads, phantom reads, lost updates (in read-modify-write patterns).

**The behaviour people find surprising** — statement-level snapshots plus a special rule for writes. If `UPDATE ... WHERE status='pending'` finds a row that another transaction is concurrently updating, it *blocks*, and when that transaction commits, it **re-evaluates the `WHERE` clause against the new version**. If the row no longer matches, it's skipped. So an `UPDATE` in Read Committed can see a mix of snapshots — this is deliberate and it's what makes `UPDATE ... WHERE balance >= x` safe.

**Why it's the default.** Best concurrency, no serialisation failures to retry, and adequate for most workloads.

**When it's not enough.** Any read-modify-write in application code (Q147). Read Committed will happily let two transactions read the same balance and both write.

---

## 132. Repeatable Read?

**One snapshot for the entire transaction**, taken at the first statement. Every read sees the same consistent view no matter how long the transaction runs.

**Prevents:** dirty reads, non-repeatable reads, and — in PostgreSQL — **phantom reads too**. PostgreSQL's implementation is stronger than the SQL standard requires, because MVCC snapshots naturally exclude rows committed after the snapshot.

**Allows:** write skew (which is why Serializable exists).

**The new failure mode you must handle:**
```
ERROR: could not serialize access due to concurrent update  (SQLSTATE 40001)
```
If your transaction updates a row that another transaction modified after your snapshot, PostgreSQL aborts yours rather than producing an inconsistent result. **Your application must catch 40001 and retry the whole transaction.** Code written for Read Committed usually doesn't, so switching isolation levels without adding retry logic converts a correctness bug into an availability bug.

**Best use.** Reports and exports that must see one consistent point in time — a financial statement that would otherwise show a transfer's debit but not its credit.

---

## 133. Serializable?

**The strongest level.** Guarantees that concurrent transactions produce a result identical to *some* serial (one-at-a-time) execution order.

**Implementation: Serializable Snapshot Isolation (SSI).** PostgreSQL's approach is optimistic — it doesn't lock reads. It tracks read/write dependencies between transactions and detects "dangerous structures" (patterns that could produce a non-serialisable outcome), then aborts one of the participants with a 40001 error. This is genuinely clever and worth naming; it's why PostgreSQL's Serializable is far more usable than lock-based implementations.

**Prevents everything**, including **write skew** — the anomaly Repeatable Read allows:

> Two doctors are on call. A rule says at least one must remain. Both simultaneously check "is another doctor on call?" (yes, in each one's snapshot), both mark themselves off duty. Now nobody is on call. No row was modified by both transactions, so Repeatable Read permits it. Serializable detects the read-write dependency cycle and aborts one.

**Requirements:**
1. **Retry logic on 40001 is mandatory** — not optional. Under Serializable, aborts are the normal cost of concurrency.
2. Keep transactions short; long ones increase conflict probability.
3. Mark read-only transactions `READ ONLY DEFERRABLE` to reduce tracking overhead.
4. All participating transactions must use Serializable — the guarantee doesn't hold if some don't.

**Trade-off.** Correctness by default without hand-written locking, paid for in abort rate and throughput under contention. For a payments system with complex invariants, that trade is often worth it. For a high-throughput logging table, it is not.

---

## 134. Dirty read?

**Definition.** Reading uncommitted data from another transaction — data that may be rolled back and never have existed.

**PostgreSQL never permits this at any isolation level.** Even `READ UNCOMMITTED` is accepted syntactically but behaves as `READ COMMITTED`. MVCC makes it structurally impossible: uncommitted row versions aren't visible in any other transaction's snapshot.

**Why it would be catastrophic.** You read a balance of ₹1,000 that was mid-transfer, make a decision on it, and the transfer rolls back. Your decision was based on a state that never existed.

**Interview value.** Saying "PostgreSQL cannot produce dirty reads because of MVCC, unlike lock-based engines where READ UNCOMMITTED is a real level" is a precise, correct distinction.

---

## 135. Non-repeatable read?

**Definition.** Reading the same row twice in one transaction and getting different values, because another transaction committed an update in between.

```
T1: SELECT balance FROM accounts WHERE id=1;   -- 1000
T2: UPDATE accounts SET balance=500 WHERE id=1; COMMIT;
T1: SELECT balance FROM accounts WHERE id=1;   -- 500  ← changed
```

**Allowed in:** Read Committed. **Prevented in:** Repeatable Read, Serializable.

**When it actually breaks things.** Any multi-step calculation: compute a total, then read the components again to itemise it, and the two no longer agree. A report showing a total of ₹50,000 with line items summing to ₹48,000 — with no bug in the arithmetic.

**Fixes:** raise the isolation level; or take the data in one statement (a single query with a join, rather than several queries); or lock explicitly with `SELECT ... FOR SHARE`.

---

## 136. Phantom read?

**Definition.** Re-running a *range* query in the same transaction and getting different **rows** (not just different values), because another transaction inserted or deleted rows matching the predicate.

```
T1: SELECT count(*) FROM orders WHERE total > 1000;   -- 42
T2: INSERT INTO orders (total) VALUES (5000); COMMIT;
T1: SELECT count(*) FROM orders WHERE total > 1000;   -- 43  ← phantom
```

**Non-repeatable read vs phantom:** the first concerns *existing rows changing*, the second concerns *the set of rows changing*.

**In PostgreSQL:** Repeatable Read prevents phantoms, which is stronger than the SQL standard requires (the standard only mandates prevention at Serializable). This is a direct consequence of snapshot isolation — rows inserted after your snapshot are simply invisible to it.

**Where phantoms still bite** even under Repeatable Read: when you *write* based on a range you read. That's write skew, and it needs Serializable or explicit locking.

---

## 137. Lost update?

**Definition.** Two transactions read the same value, both compute a new value from it, both write. The second write overwrites the first, which is silently lost.

```
T1: SELECT balance → 100
T2: SELECT balance → 100
T1: UPDATE SET balance = 100 - 30 = 70
T2: UPDATE SET balance = 100 - 50 = 50   ← T1's deduction vanished
```
Final balance 50; correct answer 20. **You just created ₹30 out of nothing.**

**This is the most commercially damaging concurrency bug** because it doesn't error, doesn't log, and only surfaces in reconciliation — if you have reconciliation.

**Four fixes, in order of preference:**

**1. Atomic UPDATE — best.** Do the arithmetic in the database:
```sql
UPDATE accounts SET balance = balance - $1
WHERE id = $2 AND balance >= $1;
-- check rowcount: 0 means insufficient funds
```
No read-then-write, no race window, works at Read Committed, no retry logic needed. **This should be your default answer.**

**2. Pessimistic lock:**
```sql
SELECT balance FROM accounts WHERE id=$1 FOR UPDATE;   -- blocks others
```
Necessary when the decision logic is too complex for SQL.

**3. Optimistic concurrency:**
```sql
UPDATE accounts SET balance=$1, version=version+1
WHERE id=$2 AND version=$3;
```
Zero rows means someone else won; re-read and retry. Good for low-contention, long-thinking-time flows.

**4. Serializable isolation** — the database detects it and aborts one. Requires retry logic.

**This is exactly questions 146–150 in your bank.** Rehearse fix #1 until it's automatic.

---

## 138. What does `SELECT FOR UPDATE` do?

**Takes a row-level exclusive lock** on every row the query returns, held until the transaction ends. Other transactions attempting to lock or update those rows block.

```sql
BEGIN;
SELECT * FROM accounts WHERE id=$1 FOR UPDATE;   -- lock
-- ... application logic ...
UPDATE accounts SET balance = $2 WHERE id=$1;
COMMIT;                                           -- lock released
```

**The variants, and knowing them is the point of the question:**

| Clause | Behaviour |
|---|---|
| `FOR UPDATE` | Exclusive; blocks other lockers and writers |
| `FOR NO KEY UPDATE` | Weaker; allows concurrent FK reference checks |
| `FOR SHARE` | Shared; multiple readers, blocks writers |
| `FOR KEY SHARE` | Weakest; what FK checks take |
| `... NOWAIT` | Error immediately instead of blocking |
| `... SKIP LOCKED` | **Skip locked rows** — the queue pattern |

**`SKIP LOCKED` is the single most useful of these**, because it makes PostgreSQL a competent job queue:
```sql
UPDATE jobs SET status='running', worker_id=$1
WHERE id = (
  SELECT id FROM jobs WHERE status='queued'
  ORDER BY created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1
)
RETURNING *;
```
Ten workers running this concurrently each claim a *different* job with no coordination, no blocking, and no duplicate work. This is how you build a queue without Redis, and it's worth knowing even if you use Redis — it's the right answer for moderate volumes and it inherits transactional guarantees for free.

**Failures.** Holding locks across an external API call (Q145) — the lock is held for the network round trip. Also: inconsistent lock ordering causes deadlocks (Q142).

---

## 139. What is MVCC?

**Multi-Version Concurrency Control** — instead of locking rows for reads, the database keeps multiple versions of each row and shows each transaction the version appropriate to its snapshot.

**The core property: readers never block writers, and writers never block readers.** That's why PostgreSQL handles mixed read/write workloads well.

**Implementation.** Every row version carries hidden system columns:
- `xmin` — the transaction ID that created this version
- `xmax` — the transaction ID that deleted/superseded it (0 if live)

A transaction's **snapshot** records which transaction IDs were committed when it started. A row version is visible if `xmin` is committed-and-visible and `xmax` is not.

- `UPDATE` = insert a new version + set `xmax` on the old one. **PostgreSQL never updates in place.**
- `DELETE` = set `xmax`. The row stays on disk.

**The consequences — this is where the depth is:**

1. **Dead tuples accumulate.** Old versions remain until `VACUUM` reclaims them. An update-heavy table grows continuously without vacuuming.
2. **Bloat.** If dead tuples aren't reclaimed fast enough, the table occupies far more pages than its live data needs, and every scan reads them.
3. **Long transactions are poison.** A transaction open for hours holds back the **xmin horizon**, so `VACUUM` cannot remove *any* tuple newer than it — database-wide. One idle-in-transaction session can bloat every table in the system.
4. **Transaction ID wraparound.** XIDs are 32-bit. Without vacuuming, approaching wraparound forces PostgreSQL into emergency mode and eventually refuses writes to protect data. This has caused famous production outages.
5. **`count(*)` is expensive** because visibility must be checked per row — it can't just read a counter.

**Autovacuum is therefore not optional maintenance — it is a core correctness requirement.** On high-churn tables, tune it more aggressively than the defaults (`autovacuum_vacuum_scale_factor` down to 0.01–0.05 from the default 0.2).

---

## 140. Why doesn't PostgreSQL lock everything?

**Because locking reads would destroy concurrency**, and MVCC makes it unnecessary.

Under a lock-based scheme (two-phase locking), a read takes a shared lock, blocking writers; a write takes an exclusive lock, blocking readers. A long analytical query would block every write to those rows for its duration. In a mixed workload, throughput collapses.

MVCC gives readers a consistent snapshot without any lock. A 10-minute report runs against a snapshot while writes proceed at full speed. That's the whole design.

**What PostgreSQL still locks:**
- **Row-level exclusive locks on write** — two transactions writing the same row must serialise. That's unavoidable; someone has to go second.
- **Explicit locks** you request (`FOR UPDATE`).
- **Table-level locks** for DDL. `ALTER TABLE` variants take `ACCESS EXCLUSIVE`, which blocks *everything*, including reads. This is why naive migrations cause outages (Q165) and why `CREATE INDEX CONCURRENTLY` exists.
- **Advisory locks** — application-controlled, useful for distributed mutual exclusion (`pg_advisory_lock`).

**The cost of the choice:** vacuum, bloat, and the xmin horizon (Q139). Every design has a bill; MVCC's arrives as maintenance rather than as contention.

---

## 141. What happens when two transactions update the same row?

**The second one blocks** until the first commits or rolls back. Row-level exclusive locks are the one place MVCC cannot help — a write must serialise against another write.

**Then behaviour diverges by isolation level:**

**Read Committed:** when T1 commits, T2 unblocks and **re-evaluates its `WHERE` clause against the newly committed version**. If the row still matches, the update proceeds using the new values. If it no longer matches, the row is skipped.

This re-evaluation is why the atomic pattern is safe:
```sql
UPDATE accounts SET balance = balance - 50 WHERE id=1 AND balance >= 50;
```
T2 re-reads the post-T1 balance, so it deducts from the *current* value and re-checks the guard. Both deductions apply correctly, or the second fails cleanly with zero rows affected.

**Repeatable Read / Serializable:** T2 cannot silently adopt a version newer than its snapshot without breaking its consistency guarantee, so PostgreSQL aborts it:
```
ERROR: could not serialize access due to concurrent update
```
T2 must retry from the beginning.

**The practical takeaway.** In Read Committed, correctness depends entirely on whether your `WHERE` clause contains the guard. `WHERE id=1` alone loses updates (Q137). `WHERE id=1 AND balance >= 50` is safe. One clause is the difference between correct and creating money.

---

## 142. How can deadlocks happen?

**Two or more transactions each hold a lock the other needs, in a cycle.**

```
T1: UPDATE accounts SET ... WHERE id=1;   -- holds lock on 1
T2: UPDATE accounts SET ... WHERE id=2;   -- holds lock on 2
T1: UPDATE accounts SET ... WHERE id=2;   -- waits for T2
T2: UPDATE accounts SET ... WHERE id=1;   -- waits for T1  → deadlock
```

**PostgreSQL detects it** after `deadlock_timeout` (default 1 second) by building a wait-for graph and finding the cycle. It then aborts one transaction:
```
ERROR: deadlock detected  (SQLSTATE 40P01)
DETAIL: Process 123 waits for ShareLock on transaction 456...
```
The victim's application must retry.

**Non-obvious sources:**
- **Foreign keys.** Inserting a child row takes a `KEY SHARE` lock on the parent. Two transactions inserting children of each other's parents deadlock.
- **Unique constraint waits.** Two transactions inserting the same key in different orders.
- **Batch updates with unordered IDs.** `UPDATE ... WHERE id IN (3,1,2)` vs `(1,2,3)` acquire locks in different orders.
- **Triggers** taking locks you didn't write.
- **Upserts** (`ON CONFLICT`) on multiple rows in different orders.
- **Index page locks** during concurrent index maintenance.

**Diagnosis.** `log_lock_waits = on` plus `deadlock_timeout` logs the full lock graph. The log tells you exactly which two statements collided — read it before theorising.

---

## 143. How do you prevent deadlocks?

**1. Consistent lock ordering — the primary defence.** If every transaction acquires locks in the same order (e.g. ascending primary key), a cycle is impossible.
```python
for account_id in sorted(account_ids):        # always ascending
    await conn.execute("SELECT ... FOR UPDATE", account_id)
```
```sql
UPDATE accounts SET ... WHERE id = ANY($1) ORDER BY id;   -- deterministic
```

**2. Keep transactions short.** Shorter lock hold time means a smaller collision window. Do computation before `BEGIN`, not inside.

**3. Never call external services inside a transaction** (Q145). A 30-second HTTP call is 30 seconds of held locks.

**4. Do it in one statement.** A single atomic `UPDATE` acquires and releases locks in one step, with no window for interleaving.

**5. Lock at the right granularity.** Locking a parent row to serialise operations on its children can be *safer* than locking many child rows, because it collapses many lock acquisitions into one.

**6. Use `SKIP LOCKED` for queues** (Q138) — workers never contend for the same row at all.

**7. Retry on 40P01.** Deadlocks cannot be fully eliminated in a concurrent system. Bounded retry with jittered backoff is part of a correct design, not an admission of failure.
```python
for attempt in range(3):
    try:
        return await do_transaction()
    except (DeadlockDetected, SerializationFailure):
        if attempt == 2: raise
        await asyncio.sleep(random.uniform(0, 0.1 * 2**attempt))
```

**8. Lower isolation where sufficient.** Serializable raises abort rates; use it where you need it, not everywhere.

**The honest framing:** you reduce deadlock *probability* with ordering and short transactions, and you handle the residue with retries. Claiming you can prevent them entirely is a red flag.

---

## 144. Why keep transactions short?

Six independent reasons — being able to list several shows real operational experience:

1. **Lock hold time.** Locks are held until commit. Long transactions block other writers proportionally.

2. **Deadlock probability** rises with hold time (Q142).

3. **Connection pool exhaustion.** A transaction owns a connection for its entire duration. Long transactions × concurrency = pool exhausted → cascading failure (Q86).

4. **The xmin horizon — the one people miss.** An open transaction prevents `VACUUM` from removing *any* tuple newer than its snapshot, **across the whole database**. One `idle in transaction` session bloats every table in the system, degrading every query. This is the most damaging and least obvious cost.

5. **Replication lag.** Long transactions generate WAL that replicas must replay; with `hot_standby_feedback` on, a long query on a replica holds back vacuum on the *primary*.

6. **Larger blast radius on rollback.** More work lost, more retry cost.

**The discipline:**
```python
# Wrong
async with db.transaction():
    user = await get_user(uid)
    result = await llm.generate(prompt)      # 8 seconds of held locks
    await save(result)

# Right
user = await get_user(uid)
result = await llm.generate(prompt)          # outside
async with db.transaction():
    await save(result)                       # milliseconds
```

Set `idle_in_transaction_session_timeout = '30s'` and `statement_timeout` so a bug can't hold a transaction indefinitely.

---

## 145. Why is calling an external API inside a DB transaction dangerous?

**Because you have coupled a fast, local, lock-holding resource to a slow, remote, unreliable one.** Every failure mode of the network becomes a failure mode of your database.

**The specific harms:**

1. **Locks held for the network round trip.** A 5-second API call holds row locks for 5 seconds. Other writers queue behind it. Under concurrency, throughput collapses.

2. **Connection held.** The pool drains (Q86).

3. **Vacuum blocked.** Held-open transactions hold back the xmin horizon (Q139).

4. **Timeout amplification.** If the API hangs for 60 seconds, so does your transaction, and so do all its locks.

5. **The atomicity is an illusion anyway.** The external call is *not* transactional. If the transaction rolls back after a successful API call, the external side effect has already happened. You charged the card and rolled back the order — the worst possible outcome.

6. **Deadlock probability** rises with hold time.

**The correct patterns:**

**Read before, write after:**
```python
external = await api.fetch(x)          # outside
async with db.transaction():
    await save(external)                # inside, fast
```

**Outbox for triggered side effects** (Q41):
```sql
BEGIN;
  UPDATE orders SET status='paid' WHERE id=$1;
  INSERT INTO outbox (topic, payload) VALUES ('order.paid', $2);
COMMIT;
```
A relay makes the external call after commit, with retries. Atomic where it can be, at-least-once where it can't.

**Saga with compensation** for multi-step distributed flows — each step commits independently, with a defined compensating action for rollback.

**The one-line version for an interview:** *"You cannot make an HTTP call transactional, so don't pretend. Commit locally, then publish, and make consumers idempotent."*

---

# L3 — Payment story (146–157)

## 146. Explain the atomic credit deduction.

**The pattern:**
```sql
UPDATE user_credits
SET credits = credits - $1,
    updated_at = now()
WHERE user_id = $2
  AND credits >= $1
RETURNING credits;
```

**Why every part matters:**

- **`credits = credits - $1`** — the arithmetic happens *inside* the database, on the current committed value. The application never reads-then-writes, so there is no window between read and write for another transaction to interleave.
- **`AND credits >= $1`** — the guard. Under Read Committed, when a concurrent update commits, PostgreSQL re-evaluates this predicate against the new row version (Q141). So the check is applied to the *current* balance, not a stale one.
- **`RETURNING`** — gives you the resulting balance without a second query, and its presence or absence tells you whether the row matched.
- **`rowcount == 0`** means insufficient credits (or no such user). That is your business-logic branch, and it is race-free.

```python
row = await conn.fetchrow(SQL, amount, user_id)
if row is None:
    raise InsufficientCredits(needed=amount)
```

**Why not `SELECT FOR UPDATE` then `UPDATE`?** It's also correct, but it's two round trips, holds a lock for the duration of application logic, and is easier to get wrong. Single-statement atomicity is simpler and faster. Reach for `FOR UPDATE` only when the decision logic genuinely can't be expressed in SQL.

**Completing the design:** pair the balance update with an append-only ledger entry in the same transaction (Q161), so you always have an auditable trail explaining how the balance reached its value.

---

## 147. Why is read-check-write unsafe?

Because there is a **window between the read and the write** during which another transaction can change the value you based your decision on. Your decision is then applied to a state that no longer exists.

```python
balance = await conn.fetchval("SELECT credits FROM user_credits WHERE user_id=$1", uid)
if balance >= amount:                    # ← T2 deducts here
    await conn.execute("UPDATE user_credits SET credits=$1 WHERE user_id=$2",
                       balance - amount, uid)
```

**The interleaving:**
```
T1: read 100
T2: read 100
T1: check 100 >= 80 ✓
T2: check 100 >= 80 ✓
T1: write 20
T2: write 20        ← should be -60, i.e. should have been rejected
```
Both spent 80 from a balance of 100. You gave away 60 units of value.

**Why it survives testing.** The window is milliseconds. It never fires with one user clicking a button. It fires when a user double-taps on a slow connection, when a mobile client retries after a timeout, or under any real concurrency. It appears in production, sporadically, and looks like a "mystery" until someone reconciles the ledger.

**Two independent defects here:**
1. The check is on stale data (the race).
2. The write is absolute (`SET credits = 20`) rather than relative (`SET credits = credits - 80`), so it *overwrites* rather than *adjusts* — the lost update (Q137).

The atomic UPDATE (Q146) fixes both simultaneously. That's why it's the answer rather than merely *an* answer.

---

## 148. What condition belongs in the SQL UPDATE?

**Everything the decision depends on.** The `WHERE` clause is your transaction guard — the entire business rule must live in it, because that is the only place it's evaluated atomically against current data.

```sql
UPDATE user_credits
SET credits = credits - $1
WHERE user_id = $2
  AND credits >= $1;            -- sufficiency
```

For a richer rule, everything moves in:
```sql
UPDATE subscriptions
SET status = 'cancelled', cancelled_at = now()
WHERE id = $1
  AND tenant_id = $2            -- authorization (Q70)
  AND status = 'active'         -- state machine guard
  AND expires_at > now();       -- temporal validity
```

**The principle: if a condition is checked in application code before the UPDATE, it is checked against stale data.** Any condition you check in Python and then act on in SQL has a race window. Move it into the `WHERE`.

**Then branch on `rowcount`:**
- `1` → succeeded
- `0` → some precondition failed

**The one weakness of `rowcount == 0`:** it doesn't tell you *which* condition failed — insufficient credits? wrong tenant? already cancelled? For good error messages, do a follow-up diagnostic `SELECT` *after* the failed update, purely to explain the failure. That read is not part of the decision, so its raciness is harmless.

---

## 149. What happens with two simultaneous deductions?

With the atomic pattern, walk through it precisely — this is the answer they want narrated:

**Setup:** balance 100. T1 deducts 80, T2 deducts 80, simultaneously.

1. Both execute `UPDATE ... SET credits = credits - 80 WHERE user_id=1 AND credits >= 80`.
2. T1 acquires the row-level exclusive lock first (arbitrarily; either could win).
3. T1 evaluates the guard against the committed value: `100 >= 80` ✓. It writes a new row version with `credits = 20`. Not yet committed.
4. **T2 blocks** on the row lock. It cannot proceed while T1 holds it.
5. T1 commits. Lock released.
6. **T2 unblocks and re-evaluates its `WHERE` against T1's committed version** (Read Committed re-check, Q141): `20 >= 80` ✗.
7. The row no longer matches. T2 updates zero rows.
8. T2's application sees `rowcount == 0` and raises `InsufficientCredits`.

**Final balance: 20. One deduction succeeded, one was correctly rejected. No money created.**

**Contrast with read-check-write:** both would have read 100, both passed the check, both written 20, and 80 units would have vanished from your accounting.

**If T1 rolls back instead of committing:** T2 re-evaluates against the *original* value of 100, passes, and succeeds. Also correct.

**The key sentence to have ready:** *"Read Committed re-evaluates the WHERE clause against the newly committed row version after a blocking write commits — that re-check is what makes the guard safe without explicit locking."* That single sentence demonstrates you understand the mechanism rather than having memorised the pattern.

---

## 150. How do you guarantee no negative balance?

**Defence in depth — three independent layers, because any one of them can be bypassed by a bug:**

**Layer 1 — The `WHERE` guard** (Q146). Prevents the deduction from applying when funds are insufficient.

**Layer 2 — A `CHECK` constraint.** The database refuses to store an invalid state, regardless of what any code does:
```sql
ALTER TABLE user_credits ADD CONSTRAINT credits_non_negative CHECK (credits >= 0);
```
This is the crucial layer. Now a bug in *any* code path — a migration, a manual SQL fix, a new service, an admin script — cannot produce a negative balance. The transaction errors out instead. **A constraint makes an invalid state impossible; a `WHERE` clause makes it unlikely.**

**Layer 3 — The ledger as source of truth.** Store an append-only, immutable ledger of every credit and debit; the balance column is a materialised cache of `SUM(amount)`. A reconciliation job compares them and alerts on drift. If they ever disagree, the ledger wins and you have a full audit trail explaining exactly where the discrepancy entered.

```sql
CREATE TABLE credit_ledger (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL,
  amount BIGINT NOT NULL,           -- signed: +topup, -spend
  reason TEXT NOT NULL,
  reference_id TEXT NOT NULL,       -- run_id, payment_id
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, reason, reference_id)   -- idempotency, built in
);
```
That unique constraint means replaying the same debit twice is impossible — idempotency comes free from the schema rather than from application discipline.

**Layer 4 (optional) — a database function or trigger** that owns the deduction, so no caller can bypass the pattern.

**The framing that scores:** *"The WHERE clause enforces the rule for correct code. The CHECK constraint enforces it for incorrect code. The ledger lets me prove which one happened."*

---

## 151. What if the process crashes after deduction but before response?

**Database state:** the transaction either committed or it didn't. Atomicity guarantees no in-between. If the commit was acknowledged, the credits are deducted and the ledger entry exists. If not, everything rolled back.

**Client state:** the client has no idea which happened. It sent a request and got a connection reset. Both outcomes look identical from outside.

**This ambiguity is fundamental and cannot be eliminated** — you cannot make a database commit and a network response atomic. What you can do is make the ambiguity *safe to resolve*.

**The resolution is idempotency keys.** The client sends a key with the request; the server records it in the same transaction as the work:
```sql
BEGIN;
  INSERT INTO idempotency_keys (key, user_id, status)
    VALUES ($1, $2, 'in_progress');       -- unique constraint
  UPDATE user_credits SET credits = credits - $3
    WHERE user_id=$2 AND credits >= $3;
  INSERT INTO credit_ledger (...) VALUES (...);
  UPDATE idempotency_keys SET status='completed', response=$4 WHERE key=$1;
COMMIT;
```

Now on retry with the same key:
- **Key doesn't exist** → the transaction never committed → do the work.
- **Key exists, `completed`** → it did commit → return the *stored response*. No double deduction.
- **Key exists, `in_progress`** → another attempt is running right now → return 409 and let the client retry shortly.

The unique constraint on `key` provides the atomicity: two concurrent retries, exactly one insert succeeds.

**The essential property:** the idempotency record and the business change commit **in the same transaction**. Writing the key in a separate transaction reintroduces exactly the gap you're trying to close.

**Operational note:** these rows accumulate. Partition by day or TTL them after your retry window (24 hours is typical) — otherwise this becomes your largest table.

---

## 152. What if the client retries?

**With idempotency keys (Q151), a retry is safe by construction** — it returns the original result rather than repeating the work.

**The contract to define explicitly, because interviewers push on it:**

1. **Who generates the key?** The client, before the first attempt, and it must reuse the *same* key for every retry of that logical operation. A key generated per HTTP attempt is useless. In practice you often generate it on the client at the moment of user intent (button press) and hold it until success.

2. **Scope.** Keys are scoped per user or per API key, not global — otherwise one tenant can collide with another's keys, deliberately or otherwise.

3. **Same key + different body?** Return **422**. This catches client bugs where a key is accidentally reused for a different operation. Store a hash of the request body alongside the key and compare.

4. **Same key while still processing?** **409 Conflict**, with `Retry-After`. Don't run it twice concurrently.

5. **Retention window.** State it in your docs (e.g. 24 hours). After expiry, the same key is treated as new. Clients must not retry beyond the window.

6. **Which responses are stored and replayed?** Successes definitely. Client errors (4xx) usually yes — they're deterministic. Server errors (5xx) usually no — the client *should* be able to retry those and get a fresh attempt.

**On the client side:** exponential backoff with jitter, a bounded attempt count, and a clear terminal state so a user isn't left staring at a spinner forever.

**The failure without any of this:** flaky mobile network → client retries → user is charged twice. This is the single most common real-world payments bug, and it's a *client-and-server* protocol problem, not a database problem.

---

## 153. What if a webhook arrives twice?

**Assume it will.** Every serious webhook provider (Stripe, Razorpay, PayPal) documents at-least-once delivery. Duplicates happen when their retry logic fires because your ACK was lost, or when they replay after an incident.

**The fix is a dedupe table with a unique constraint:**
```sql
CREATE TABLE webhook_events (
  provider TEXT NOT NULL,
  event_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  processed_at TIMESTAMPTZ,
  PRIMARY KEY (provider, event_id)
);
```

```python
async def handle(provider, event):
    async with conn.transaction():
        inserted = await conn.execute(
            "INSERT INTO webhook_events (provider, event_id, payload) "
            "VALUES ($1,$2,$3) ON CONFLICT DO NOTHING",
            provider, event.id, event.raw)
        if inserted == "INSERT 0 0":
            return 200            # already seen; ACK and stop
        await apply_effect(event)  # same transaction
```

**Three properties that make this correct:**
1. **Insert and effect in one transaction.** If the effect fails, the dedupe row rolls back too, so a retry will genuinely reprocess. Recording receipt separately from processing is the classic bug — you mark it seen, crash before applying it, and the event is lost forever.
2. **`ON CONFLICT DO NOTHING`** is atomic. Two concurrent deliveries of the same event: exactly one proceeds.
3. **Always return 200 for duplicates.** Returning an error makes the provider retry harder, and eventually disable your endpoint.

**Also required for a production webhook endpoint:**
- **Verify the HMAC signature over the raw body** — before parsing, and using a constant-time comparison. Parsing first and re-serialising breaks signature verification (byte-for-byte matters).
- **Reject stale timestamps** (>5 minutes) to prevent replay.
- **ACK fast, process async.** Providers time out in seconds. Verify → persist → return 200 → process in a worker. Doing heavy work inline causes the provider to time out and retry, multiplying your load exactly when you're already slow.
- **Never trust the payload's amount or status alone.** For anything financial, call the provider's API to fetch the authoritative object by ID.

---

## 154. What if webhook B arrives before A?

**Out-of-order delivery is normal**, not exceptional. HTTP has no ordering guarantee, providers retry independently, and network paths differ. You will receive `payment.captured` before `payment.authorized`.

**Three strategies, best first:**

**1. State machine with guarded transitions — the primary answer.** Define legal transitions and make each update assert its precondition:
```sql
UPDATE payments SET status='captured', captured_at=now()
WHERE id=$1 AND status IN ('authorized', 'pending');
```
If the row is already in a *later* state, zero rows update and you ignore the event. If it's in an *earlier* state than expected, you have a genuine gap.

Define the machine explicitly:
```
created → authorized → captured → settled
       ↘ failed      ↘ refunded
```
Terminal states accept nothing. An event that would move backwards is dropped.

**2. Sequence or timestamp guard.** If the provider supplies a monotonic sequence or event timestamp, store the highest applied and reject anything older:
```sql
UPDATE payments SET status=$2, last_event_at=$3
WHERE id=$1 AND last_event_at < $3;
```
Last-write-wins by *event* time rather than arrival time.

**3. Buffer and reorder.** If B arrives and A hasn't, park B in a pending table and apply it when A arrives — or after a timeout, reconcile by fetching current state from the provider. More complex; use it only when the state machine genuinely can't tolerate gaps.

**The pattern that makes all of this robust:** treat webhooks as **notifications, not data**. The webhook says "something changed on object X." You then call `GET /payments/X` and apply the authoritative current state. Order stops mattering entirely, because you always converge on the provider's truth. This costs an API call per event and is worth it for anything financial.

---

## 155. Why use a state machine?

**Because it converts "did we remember to check?" into "the illegal transition is impossible."**

**What it gives you:**

1. **Illegal transitions are rejected structurally.** `refunded → captured` can't happen because no transition defines it. Without a state machine, that's a conditional someone must remember to write in every code path.

2. **Idempotency for free.** Applying `→ captured` to an already-captured payment updates zero rows. Duplicate events are absorbed with no special handling (Q153).

3. **Out-of-order tolerance.** A backwards transition doesn't match its guard and is ignored (Q154).

4. **Concurrency safety.** The guard is in the `WHERE` clause, so it's evaluated atomically against the current row version (Q148). Two concurrent transitions: one wins, one no-ops.

5. **Auditability.** Every transition is a row in a transitions table: from-state, to-state, cause, actor, timestamp. When money is wrong, you can reconstruct exactly what happened, in order.

6. **Stuck-state detection.** "Payments in `authorized` for more than 24 hours" is a trivial query and a valuable alert. Without explicit states you cannot even ask the question.

7. **It's a shared vocabulary.** Support, product, and engineering can all talk about "it's stuck in pending" and mean the same thing.

**Implementation:**
```sql
CREATE TABLE payment_transitions (
  id BIGSERIAL PRIMARY KEY,
  payment_id UUID NOT NULL,
  from_status TEXT, to_status TEXT NOT NULL,
  event_id TEXT, actor TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```
Encode allowed transitions in one table or constant so they're reviewable in one place, and enforce them in the `WHERE` clause of every update.

**Trade-off.** More upfront design and more states than feel necessary at the start. But adding a state later to a system that already has a machine is easy; retrofitting a machine onto ad-hoc boolean flags (`is_paid`, `is_refunded`, `is_cancelled` — which can be simultaneously true) is very hard. That flag-soup anti-pattern is what state machines exist to prevent.

---

## 156. What if a webhook never arrives?

**It will happen** — provider outage, your endpoint down during deploy, a misconfigured URL, a firewall change, the provider exhausting its retries while you were broken. Any system that depends solely on webhooks for correctness will eventually be wrong.

**You need active mechanisms, not just passive listening:**

**1. Polling reconciliation — the primary safety net.** A scheduled job finds records in non-terminal states past a threshold and asks the provider directly:
```sql
SELECT id, provider_ref FROM payments
WHERE status IN ('pending','authorized')
  AND created_at < now() - interval '15 minutes'
  AND (last_polled_at IS NULL OR last_polled_at < now() - interval '5 minutes')
LIMIT 100;
```
Then `GET /payments/{ref}` and apply the authoritative state through the same state machine. **Poll with increasing intervals** — every minute for the first hour, hourly for a day, daily after — so you don't hammer the provider for a payment abandoned two weeks ago.

**2. Timeout transitions.** Some states must expire. A payment `pending` for 24 hours becomes `expired`. Otherwise rows accumulate in limbo forever and nobody notices.

**3. Daily settlement reconciliation.** Providers publish a settlement report. Compare their record of every transaction against yours. **This is the only mechanism that catches events you never knew existed** — a payment that succeeded on their side and was never recorded on yours. For anything financial, this is mandatory, not optional.

**4. Alerting on the shape of the problem.** Alert on webhook *volume dropping* — a silent endpoint looks identical to a quiet day unless you're watching the rate. Also alert on the count of records stuck in non-terminal states, and on the age of the oldest one.

**5. Idempotency everywhere**, because reconciliation and webhooks will both apply the same event. If they're not idempotent, your safety net double-applies transactions.

**The design principle to state:** *webhooks are an optimisation for latency, not a mechanism for correctness.* The system must be correct with webhooks entirely disabled — they just make it fast. If your design breaks when webhooks stop, you've built on an unreliable foundation.

---

## 157. Why reconciliation?

**Because in any distributed system, two records of the same fact will eventually disagree, and you need a mechanism that detects it rather than discovering it from a customer.**

**The sources of drift:**
- Lost webhooks (Q156)
- Bugs that applied an effect twice or zero times
- Manual database edits during incidents
- Partial failures — provider succeeded, your write failed
- Clock and timezone errors in period boundaries
- Currency rounding accumulating over millions of transactions
- Refunds and chargebacks arriving through separate channels

**What reconciliation actually does:**

**1. Internal consistency** — the balance column vs the sum of the ledger:
```sql
SELECT u.user_id, u.credits, COALESCE(SUM(l.amount), 0) AS ledger_sum
FROM user_credits u LEFT JOIN credit_ledger l USING (user_id)
GROUP BY u.user_id, u.credits
HAVING u.credits <> COALESCE(SUM(l.amount), 0);
```
Any row returned is a bug. This should return zero rows, always, and should run daily with an alert on any output.

**2. External consistency** — your records vs the provider's settlement file. Classify differences: in-yours-not-theirs (you recorded a payment that didn't happen), in-theirs-not-yours (a missed webhook), and amount mismatches (rounding or a bug).

**3. Double-entry invariants.** In a proper ledger, every entry has a matching counter-entry and the system-wide sum is zero. That single check catches an enormous class of errors.

**Why it's non-negotiable for money:**
- **Regulatory.** Auditors require it.
- **Trust.** "Our balances are correct" is only a claim unless you verify it continuously.
- **Early detection.** A bug found by reconciliation on day one affects a few records; found by a customer on day ninety it affects thousands and the fix requires reconstructing history.
- **Recoverability.** With an append-only ledger you can *replay* to rebuild any derived state. Without it, corruption is permanent.

**The operational shape:** run daily, produce a report of exceptions, alert on any non-zero count, and — critically — **never auto-correct financial discrepancies**. Flag for human review. An automated "fix" that's wrong turns one error into a systematic one.

---

# L4 — Design and scale

## 158. Design a payment database.

**Core principles first:** money is `BIGINT` in minor units (never float — `0.1 + 0.2 != 0.3` and rounding errors accumulate into real losses), every financial record is append-only, and derived balances are always reconcilable against an immutable ledger.

```sql
CREATE TABLE payments (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  currency CHAR(3) NOT NULL,
  status TEXT NOT NULL,             -- state machine
  provider TEXT NOT NULL,
  provider_ref TEXT,                -- their ID
  idempotency_key TEXT NOT NULL,
  failure_code TEXT, failure_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, idempotency_key),
  UNIQUE (provider, provider_ref)
);

CREATE TABLE payment_transitions (        -- append-only audit
  id BIGSERIAL PRIMARY KEY,
  payment_id UUID NOT NULL REFERENCES payments(id),
  from_status TEXT, to_status TEXT NOT NULL,
  cause TEXT, event_id TEXT, actor TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ledger_entries (             -- double-entry, immutable
  id BIGSERIAL PRIMARY KEY,
  transaction_id UUID NOT NULL,           -- groups the pair
  account_id UUID NOT NULL,
  amount_minor BIGINT NOT NULL,           -- signed; sum per transaction_id = 0
  currency CHAR(3) NOT NULL,
  entry_type TEXT NOT NULL,
  reference_type TEXT, reference_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (reference_type, reference_id, account_id, entry_type)
);

CREATE TABLE webhook_events (
  provider TEXT, event_id TEXT, payload JSONB,
  signature_valid BOOLEAN, received_at TIMESTAMPTZ, processed_at TIMESTAMPTZ,
  PRIMARY KEY (provider, event_id)
);
```

**Design decisions worth defending:**

1. **No `UPDATE` on ledger entries, ever.** A correction is a new compensating entry. Revoke UPDATE and DELETE privileges on the table at the database level so it's enforced, not merely intended.
2. **Double-entry**: every transaction produces balanced entries summing to zero. This makes a whole class of bugs detectable by a single query.
3. **Currency on every row.** Never mix currencies in a sum. A composite check on `(account, currency)` prevents it.
4. **Two unique constraints** on `payments` — one for client idempotency, one preventing double-recording a provider transaction.
5. **`payment_transitions` is the audit log**, and it exists because `payments.status` only shows the current value. Regulators and post-incident analysis both need the history.
6. **Balances are materialised, not authoritative.** Either a `balances` table updated in the same transaction as the ledger entry, or computed on read for low-volume accounts. Reconciled daily (Q157).

**Indexes:** `(tenant_id, user_id, created_at DESC)` for user history, `(status, created_at)` partial on non-terminal states for the reconciliation sweep, `(transaction_id)` on ledger entries.

**Retention:** ledger and transitions are permanent (usually a 7-year regulatory floor). Partition by month; move old partitions to cheaper storage.

---

## 159. Design order/payment states.

**Two separate machines that reference each other.** Conflating them is the classic mistake — an order can be cancelled while its payment is refunded, and those are independent lifecycles.

**Payment:**
```
created → authorized → captured → settled
    ↓          ↓           ↓          ↓
  failed   cancelled   refunded   refunded
                        ↓
                  partially_refunded → refunded
```

**Order:**
```
draft → pending_payment → paid → fulfilling → fulfilled → completed
   ↓          ↓            ↓         ↓
cancelled  cancelled   cancelled  cancelled → refund_pending → refunded
```

**Rules that make this work:**

1. **Terminal states are terminal.** `settled`, `refunded`, `failed`, `completed`, `cancelled` accept no further transitions. Enforce with `WHERE status NOT IN (terminal_states)` on every update.

2. **Every transition is guarded** (Q148) — `WHERE id=$1 AND status=$2`. Zero rows means the transition was illegal or already applied; that's your idempotency.

3. **Every transition writes an audit row** in the same transaction.

4. **Cross-machine reactions go through the outbox**, never a direct call. Payment `→ captured` publishes `payment.captured`; a handler transitions the order `→ paid`. This keeps the machines decoupled and makes the coupling replayable and observable.

5. **Every non-terminal state needs a timeout and an owner.** `pending_payment` for 30 minutes → `cancelled`. `fulfilling` for 48 hours → alert a human. States with no exit condition are where records go to disappear.

6. **Model partial refunds explicitly.** `partially_refunded` with a running `refunded_amount_minor`, and a check that it never exceeds the captured amount. Trying to represent partial refunds with a boolean is a guaranteed future incident.

**What to say about the trade-off:** more states means more code but far fewer "how did it get into this state?" investigations. The cost is paid once at design time; the alternative is paid repeatedly at 2 a.m.

---

## 160. Design an idempotent payment endpoint.

```
POST /v1/payments
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
{ "amount_minor": 50000, "currency": "INR", "method_id": "pm_x" }
```

**The full algorithm, with every failure case handled:**

```python
async def create_payment(key: str, body: PaymentIn, user: User):
    body_hash = sha256(canonical_json(body))

    async with conn.transaction():
        row = await conn.fetchrow("""
            INSERT INTO idempotency_keys
              (key, tenant_id, request_hash, status, created_at)
            VALUES ($1, $2, $3, 'in_progress', now())
            ON CONFLICT (tenant_id, key) DO NOTHING
            RETURNING key
        """, key, user.tenant_id, body_hash)

        if row is None:                       # key already exists
            existing = await conn.fetchrow(
                "SELECT * FROM idempotency_keys WHERE tenant_id=$1 AND key=$2 FOR UPDATE",
                user.tenant_id, key)

            if existing["request_hash"] != body_hash:
                raise HTTPException(422, "key reused with different payload")
            if existing["status"] == "in_progress":
                raise HTTPException(409, headers={"Retry-After": "2"})
            return JSONResponse(existing["response_code"], existing["response_body"])

        # first time through
        payment = await insert_payment(user, body, key)
        await conn.execute(
            "UPDATE idempotency_keys SET status='completed', "
            "response_code=201, response_body=$1 WHERE tenant_id=$2 AND key=$3",
            payment.json(), user.tenant_id, key)

    await outbox_publish("payment.created", payment.id)   # after commit
    return JSONResponse(201, payment)
```

**The properties that make it correct:**

1. **The unique constraint is the concurrency control.** Two simultaneous requests with the same key: one insert wins, the other takes the `DO NOTHING` path. No application-level locking, works across all workers and pods.
2. **Key record and payment commit in one transaction.** Separate transactions reintroduce the crash window (Q151).
3. **Request hash comparison** catches client bugs where a key is reused for different data.
4. **`in_progress` → 409**, so a client retrying during processing doesn't trigger a second attempt.
5. **The stored response is replayed byte-identically**, so retry and original are indistinguishable to the client.
6. **The provider call happens with its own idempotency key** derived from yours, so even the external side effect is deduplicated.

**Scope and retention:** keys are per-tenant, retained 24 hours, table partitioned by day with old partitions dropped. Document the window in your API docs — clients need to know when a key stops being honoured.

**Failure modes to mention unprompted:** clock skew doesn't matter here (good), but a client that generates a new key per retry defeats the entire mechanism — so the client SDK must own key generation, not the caller.

---

## 161. Design a ledger.

**Double-entry, append-only, immutable.** The design is 500 years old and it is still correct because it makes errors detectable by construction.

```sql
CREATE TABLE accounts (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL,
  owner_type TEXT NOT NULL,        -- 'user','platform','provider','fees'
  owner_id UUID,
  account_type TEXT NOT NULL,      -- 'asset','liability','revenue','expense'
  currency CHAR(3) NOT NULL,
  UNIQUE (tenant_id, owner_type, owner_id, account_type, currency)
);

CREATE TABLE ledger_transactions (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL,
  description TEXT NOT NULL,
  reference_type TEXT, reference_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, reference_type, reference_id)     -- idempotency
);

CREATE TABLE ledger_entries (
  id BIGSERIAL PRIMARY KEY,
  transaction_id UUID NOT NULL REFERENCES ledger_transactions(id),
  account_id UUID NOT NULL REFERENCES accounts(id),
  amount_minor BIGINT NOT NULL,     -- signed; debits +, credits −
  currency CHAR(3) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON ledger_entries (account_id, created_at DESC);
```

**The invariant that everything rests on:** for every `transaction_id`, `SUM(amount_minor) = 0`. Money is never created or destroyed — only moved between accounts. Enforce it with a deferred constraint trigger checked at commit:
```sql
-- verification query; should always return zero rows
SELECT transaction_id FROM ledger_entries
GROUP BY transaction_id HAVING SUM(amount_minor) <> 0;
```

**A payment as ledger entries:**
```
txn: "user pays ₹500 for credits"
  +50000  provider_receivable   (asset increases)
  −49000  user_credit_liability (we now owe them credits)
  −1000   platform_revenue      (fee)
```

**Design rules:**

1. **Never UPDATE or DELETE.** `REVOKE UPDATE, DELETE ON ledger_entries FROM app_user;` — enforce it at the privilege level so it isn't a matter of discipline.
2. **Corrections are compensating entries**, not edits. A mistake stays visible in history alongside its reversal. That's a feature — auditors require it.
3. **Balance = `SUM(amount_minor)` for an account.** Materialise it in a `balances` table updated in the same transaction for read performance, and reconcile daily (Q157).
4. **One currency per account.** Cross-currency movements use an explicit FX transaction with a recorded rate, hitting an FX gain/loss account. Never sum mixed currencies.
5. **Idempotency at the transaction level** via `UNIQUE (tenant_id, reference_type, reference_id)`.
6. **Partition by month** — this becomes your largest table by an order of magnitude.

**Why this is worth the complexity:** it makes an entire class of financial bugs *detectable by a single query*, and it makes any historical state reconstructible by replay. Neither is true of a simple `balance` column.

---

## 162. How do you audit money movement?

**Layered, because different questions need different evidence:**

**1. The ledger is the primary audit trail** (Q161). Immutable, complete, replayable. Any balance at any past time is `SUM(amount) WHERE created_at <= T`.

**2. State transitions** (Q155) — the lifecycle of each payment, with cause and actor.

**3. Access audit** — who *read* what. For financial and health data this is a compliance requirement, not a nicety. Log user, resource, action, timestamp, IP, and request ID.

**4. Change data capture** for defence in depth — a trigger-based audit table, or logical replication to an append-only store. This catches changes made outside your application (manual SQL during an incident, a rogue migration).

**5. Immutability guarantees.** Ledger tables with `UPDATE`/`DELETE` revoked; audit logs shipped to write-once storage (S3 with Object Lock); optionally hash-chain each entry to its predecessor so tampering is detectable.

**What must be on every audit record:**
- **Who** — user ID, service account, or `system`
- **What** — resource type and ID, before and after values
- **When** — with timezone, at the database
- **Why** — reason code, ticket reference, or the triggering event ID
- **Correlation** — request ID and trace ID (Q87), tying it to everything else

**The queries auditors and incidents actually ask:**
- "Show every movement on this account in Q3" → indexed by `(account_id, created_at)`
- "Who changed this payment's status and when?" → transitions table
- "Prove this balance is correct" → replay the ledger and compare
- "Show everyone who accessed this customer's records" → access audit

**Retention.** Typically 7 years for financial data. Partition by month, move old partitions to cold storage, and — importantly — **test that you can still read them**. An archive you've never restored is a hypothesis, not a backup.

---

## 163. How do you handle refunds?

**A refund is a new transaction, never a reversal of an old one.** The original payment record must remain untouched — its immutability is what makes the audit trail trustworthy.

```sql
CREATE TABLE refunds (
  id UUID PRIMARY KEY,
  payment_id UUID NOT NULL REFERENCES payments(id),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  currency CHAR(3) NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL,                     -- own state machine
  provider_ref TEXT,
  idempotency_key TEXT NOT NULL,
  requested_by UUID, created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (payment_id, idempotency_key)
);
```

**The invariant that must be enforced atomically:**
```sql
UPDATE payments
SET refunded_amount_minor = refunded_amount_minor + $1,
    status = CASE
      WHEN refunded_amount_minor + $1 = amount_minor THEN 'refunded'
      ELSE 'partially_refunded' END
WHERE id = $2
  AND refunded_amount_minor + $1 <= amount_minor;   -- ← the guard
```
Zero rows means over-refund attempted. Back this with `CHECK (refunded_amount_minor <= amount_minor)` so it's impossible even from a different code path (Q150's layering principle applied again).

**Ledger entries reverse the money flow:**
```
txn: "refund ₹200 of payment X"
  −20000  provider_receivable
  +19600  user_credit_liability
  +400    platform_revenue        (if the fee is refunded — often it isn't)
```
**Whether fees are returned is a business decision, not a technical one.** Ask; don't assume. Most providers keep their fee on a refund, which means a full refund leaves your platform out of pocket — that needs to be represented, not hidden.

**The hard cases to raise unprompted:**
- **Refund after the credits were spent** — the balance goes negative or you need a claw-back policy. Decide explicitly; the schema must be able to represent whichever you choose.
- **Partial refunds summing to the full amount** — must land in `refunded`, not stay `partially_refunded`. The `CASE` above handles it.
- **Refund of a refund** — disallow it structurally.
- **Chargebacks** — a *different* flow, initiated by the bank, with fees and a dispute window. Model separately; conflating them with refunds loses the distinction that matters for disputes.
- **Currency drift** — refund in the original currency at the original amount, never re-converted at today's rate.
- **Async settlement** — the provider's refund is not instant. Refunds need their own state machine and their own reconciliation.

---

## 164. How do you handle concurrent spending?

This is Q137/146/149 elevated to a system design. The layers:

**1. Atomic conditional UPDATE** as the primitive (Q146). No read-check-write anywhere.

**2. CHECK constraint** as the backstop (Q150).

**3. Reservation pattern for multi-step spending.** When a spend must be authorised before its final amount is known — an AI run whose token cost isn't known until it finishes:

```sql
-- reserve an estimate up front
UPDATE user_credits
SET credits = credits - $estimate, reserved = reserved + $estimate
WHERE user_id=$1 AND credits >= $estimate;

-- ... work happens ...

-- settle: release the reservation, charge the actual
UPDATE user_credits
SET reserved = reserved - $estimate,
    credits  = credits + ($estimate - $actual)
WHERE user_id=$1;
```
This prevents a user starting ten concurrent expensive runs on a balance sufficient for one. **Reservations need expiry** — a crashed worker must not lock funds forever, so a sweeper releases reservations older than the maximum run duration.

**4. Row-level contention management.** All spending for one user contends on one row. For a very high-volume account that becomes a bottleneck. The standard fix is **sharded counters** — N sub-balance rows per account, spend from a random one, sum for the total. Adds complexity; only do it when you've measured the contention.

**5. Handle the "spend exceeds balance mid-run" case explicitly.** An agent run can consume more than estimated. Decide the policy: hard-stop mid-run, allow a bounded overdraft, or let it complete and carry a negative balance to be settled. All three are defensible; having no policy is not.

**6. Rate limit by cost, not request count** (Q90). Ten cheap requests and ten expensive ones are wildly different spend.

**7. Reconcile daily** (Q157).

**The AI-specific insight worth stating:** unlike a fixed-price purchase, LLM spending is *unknown until after the work is done*. That inverts the normal authorise-then-charge model and is precisely why reservations plus post-hoc settlement, rather than simple deduction, is the right architecture here.

---

## 165. How would you migrate a huge table?

**The governing constraint: `ACCESS EXCLUSIVE` locks block everything, including reads.** On a 500-million-row table, a naive `ALTER TABLE` is an outage.

**What's safe in modern PostgreSQL (metadata-only, instant):**
- `ADD COLUMN` with or without a default (PG 11+ stores the default in catalog metadata rather than rewriting rows)
- `DROP COLUMN` (marks it dropped; space reclaimed later)
- Renaming a column or table
- `ALTER TABLE ... SET NOT NULL` when a validated matching CHECK constraint already exists (PG 12+)

**What rewrites the table (dangerous):**
- Changing a column type in most cases
- `ADD COLUMN` with a volatile default
- `SET NOT NULL` without a supporting constraint
- Adding a `PRIMARY KEY` from scratch

**The safe patterns:**

**Adding an index:**
```sql
CREATE INDEX CONCURRENTLY idx_x ON big_table (col);
```
Doesn't block writes. Takes two table passes, so it's slower. **Can fail and leave an `INVALID` index** — check `pg_index.indisvalid` afterwards and drop/retry if needed. Cannot run inside a transaction, which means your migration tool must support it (many do, with a flag).

**Adding a constraint:**
```sql
ALTER TABLE t ADD CONSTRAINT c CHECK (...) NOT VALID;   -- instant, no scan
ALTER TABLE t VALIDATE CONSTRAINT c;                     -- SHARE UPDATE EXCLUSIVE, doesn't block writes
```

**Changing a column type — the expand/contract pattern:**
1. Add the new column (instant)
2. Backfill in batches, with commits between (see below)
3. Dual-write both columns from the application
4. Verify they agree
5. Switch reads to the new column
6. Stop writing the old one
7. Drop the old column

Steps 3–6 span multiple deploys. That's the point: **each deploy is independently reversible.**

**Backfilling safely:**
```sql
-- batched, committed per batch, with a pause
UPDATE big_table SET new_col = old_col::bigint
WHERE id BETWEEN $1 AND $2 AND new_col IS NULL;
```
Small batches (1,000–10,000 rows), a short sleep between them, and monitoring of replication lag and dead-tuple count. One giant `UPDATE` locks every row it touches, generates enormous WAL, blows out replication lag, and bloats the table.

**Always set a lock timeout:**
```sql
SET lock_timeout = '3s';
SET statement_timeout = '30s';
```
Without this, your `ALTER TABLE` waits behind a long-running query — and every subsequent query queues behind *your* pending `ACCESS EXCLUSIVE` request. **That's the mechanism by which a "quick migration" takes down a healthy database**, and it's the single most valuable thing to know about PostgreSQL migrations. Fail fast and retry instead.

**For truly massive changes:** partition first, migrate partition by partition; or use logical replication to a new table and cut over.

---

## 166. A query goes from 50ms to 8s. Diagnose.

**Work through causes in order of likelihood, and say you'd check "what changed" first:**

**1. Statistics went stale (most common).** After bulk loads or rapid growth, the planner's estimates diverge from reality and it flips to a bad plan.
```sql
EXPLAIN (ANALYZE, BUFFERS) <query>;   -- compare rows= to actual rows=
ANALYZE big_table;
```
A 100× estimate error is the fingerprint.

**2. Plan flip from a generic prepared-statement plan** (Q128). Common after a connection pool cycles or after five executions of a prepared statement. Check with `plan_cache_mode = force_custom_plan`.

**3. Data volume crossed a threshold.** The table grew past the point where an index scan is cheaper than a seq scan (or vice versa). The plan changed because the *right* answer changed — now you need a better index, a partial index, or partitioning.

**4. Missing or invalid index.** Was an index dropped? Did a `CREATE INDEX CONCURRENTLY` fail and leave it `INVALID`?
```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```

**5. Bloat.** Heavy update/delete churn with insufficient vacuuming means scanning far more pages than there is live data.
```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum FROM pg_stat_user_tables
WHERE relname='big_table';
```

**6. Lock contention.** The query isn't slow — it's *waiting*.
```sql
SELECT pid, state, wait_event_type, wait_event, query, now()-query_start AS dur
FROM pg_stat_activity WHERE state <> 'idle' ORDER BY dur DESC;
```
`wait_event_type = 'Lock'` means this is a concurrency problem, not a query problem.

**7. Cache eviction.** `BUFFERS` shows `shared read` (disk) where it used to show `shared hit` (memory). Another workload evicted your working set.

**8. Parameter change.** Someone lowered `work_mem` and your sort now spills to disk. `EXPLAIN` shows `Sort Method: external merge Disk: 120MB`.

**9. Resource contention** — a new report job, a replica rebuild, autovacuum running aggressively, or CPU throttling at the container level.

**10. An application change** — an added `ORDER BY`, a different parameter value hitting a skewed distribution, or an ORM producing a different query shape.

**The systematic approach to state:** capture the current plan, compare it to the known-good plan (which is why you should save plans for critical queries), and identify which *node* changed. That localises it to one of the above immediately, instead of guessing.

**`pg_stat_statements` is the tool** that tells you this query regressed at all, and when — enable it everywhere.

---

## 167. How do you scale PostgreSQL reads?

**In order of effort and effect:**

**1. Fix the queries first.** Indexing, eliminating N+1, cursor pagination, avoiding `SELECT *`. A single missing index routinely accounts for more load than everything below. **Do not scale a broken query — you'll just pay more for the same problem.**

**2. Cache.** Redis in front of hot reads. An 80% hit rate removes 80% of read load for a fraction of the cost of a replica, and it's faster. This is almost always the best ratio of effort to result.

**3. Connection pooling.** PgBouncer in transaction mode. Doesn't add read capacity directly, but it stops connection overhead from consuming the capacity you have — and it's what makes many app instances viable at all.

**4. Vertical scaling.** More RAM so the working set fits in `shared_buffers` and the OS page cache. Boring, effective, and often cheaper than the engineering time for anything below.

**5. Read replicas.** Streaming replication; route read-only queries to replicas. This is where real horizontal read scaling begins.
- Application-level routing (an explicit read-only session/engine) is clearest
- Requires accepting replication lag (Q170)
- Analytics and reports should go to a dedicated replica so they can't affect interactive traffic

**6. Materialised views** for expensive aggregations, refreshed periodically:
```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_stats;   -- needs a unique index
```

**7. Partitioning** (Q168) — smaller indexes and partition pruning.

**8. A separate analytical store.** OLAP queries on an OLTP database is the wrong tool. Ship to ClickHouse, BigQuery, or a columnar warehouse via CDC. Beyond a certain point this isn't an optimisation, it's the correct architecture.

**The trade-off to name:** every layer adds a consistency compromise. Cache adds staleness, replicas add lag, materialised views add refresh delay, warehouses add ETL latency. Scaling reads is largely the practice of deciding *how stale is acceptable, per query* — and that's a product question as much as a technical one.

---

## 168. When partition?

**Partition when at least one of these is true:**

1. **The table exceeds roughly 100 GB** and queries scan large ranges. Indexes stop fitting in memory; partition pruning restores locality.
2. **You delete old data in bulk.** `DROP TABLE partition_2024_01` is instant and reclaims space immediately. `DELETE FROM t WHERE created_at < ...` on 50 million rows takes hours, generates enormous WAL, bloats the table, and leaves the space unreturned. **This alone justifies partitioning for time-series data.**
3. **Queries almost always filter on one dimension** (usually time or tenant) — so pruning eliminates most partitions.
4. **Maintenance windows are too long.** `VACUUM`, `REINDEX`, and `ANALYZE` run per partition, in parallel, rather than on one monolith.
5. **Tiered storage** — recent partitions on fast disk, old on cheap.

**Strategies:**
- **RANGE** — by date. The dominant case for events, logs, ledgers, runs.
- **LIST** — by discrete value, e.g. region or tenant tier.
- **HASH** — even distribution when there's no natural range key; good for spreading write contention.

```sql
CREATE TABLE events (
  id BIGSERIAL, tenant_id UUID, created_at TIMESTAMPTZ NOT NULL, ...
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2026_08 PARTITION OF events
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
```

**The constraints to raise, because they bite people:**
- **The partition key must be in every unique constraint and primary key.** So a globally-unique `id` alone is not possible — you need `(id, created_at)`. This surprises people and can force schema changes.
- Pruning only works if the query filters on the partition key. `WHERE tenant_id=$1` on a time-partitioned table scans every partition.
- Too many partitions (thousands) makes *planning* slow. Keep it in the tens to low hundreds.
- Partitions must be created ahead of time — use `pg_partman` or a scheduled job. An insert with no matching partition fails.

**When not to partition.** Under ~50 GB, partitioning usually adds complexity without benefit. Proper indexing does more. Don't partition speculatively.

---

## 169. When use replicas?

**Use them when:**
1. Read load exceeds what one instance handles, *after* caching and query fixes
2. Analytical queries need isolation from interactive traffic
3. You need high availability — a replica can be promoted on primary failure
4. Geographic distribution — a replica near users cuts latency
5. Backups should run somewhere that isn't the primary
6. Zero-downtime major-version upgrades via logical replication

**Types:**
- **Streaming (physical)** — byte-level WAL shipping, whole cluster, read-only. The default.
- **Logical** — replicates specific tables via decoded changes. Enables cross-version replication, selective tables, and a writable target. Slower and more constrained (no DDL, needs replica identity).
- **Synchronous** — the primary waits for replica confirmation before acknowledging commit. Zero data loss, higher write latency, and **an availability risk**: with `synchronous_standby_names` set and the replica down, writes on the primary *block*. Use `ANY 1 (...)` with multiple standbys, or accept the trade knowingly.

**Routing.** Explicit in the application is best — a separate read-only engine/session that developers choose deliberately:
```python
async with read_session() as s:      # explicitly a replica
    ...
```
Automatic proxy-based routing (pgpool) looks convenient but routes queries wrongly at the worst moments, and hides the lag question from the developer who needs to answer it.

**When NOT to use replicas:** to fix a write bottleneck (they don't help — replicas are read-only and every write still hits the primary and is replayed everywhere), or to avoid fixing a bad query.

---

## 170. What consistency do replicas sacrifice?

**Read-your-writes consistency.** That's the precise answer.

Streaming replication is **asynchronous by default**. The primary commits and acknowledges; the WAL then travels to replicas and is replayed. Between those moments — typically milliseconds, but seconds or minutes under load — a replica serves stale data.

**The user-visible failure:**
```
POST /profile   → writes to primary        → 200 OK
GET  /profile   → reads from replica       → old data
```
The user updates their name, the page reloads, and their old name is still there. They update it again. Now you have a support ticket and a user who believes your product is broken.

**Where lag comes from:**
- Network latency (severe cross-region)
- Replica replay is largely single-threaded, so a burst of writes on a multi-core primary can outpace it
- Long-running queries on the replica conflict with replay; with `hot_standby_feedback=on` the replica wins and the primary's vacuum is held back; with it off, the *query* gets cancelled with "conflict with recovery"
- Bulk operations — a large migration or backfill can push lag into minutes

**Mitigations, in increasing strength:**

1. **Route reads to the primary after a write**, for a short window per user (session stickiness). Simplest effective fix.
2. **LSN-based tracking.** Capture `pg_current_wal_lsn()` on write, pass it forward, and only read from a replica whose `pg_last_wal_replay_lsn()` has caught up. Precise but requires plumbing.
3. **Classify queries by tolerance.** Balances, permissions, and just-written data → primary. Search results, analytics, listings, recommendations → replica. **Make this an explicit, reviewed decision per endpoint** rather than a default.
4. **Synchronous replication** for the subset that truly needs it — at a real write-latency cost.
5. **Monitor and alert on lag**, and automatically stop routing reads to a replica exceeding a threshold:
```sql
SELECT client_addr, replay_lag FROM pg_stat_replication;
```

**The framing that scores in an interview:** *"Replicas trade consistency for read capacity. The engineering work isn't setting up replication — it's deciding, per query, whether stale data is acceptable, and having a mechanism for the ones where it isn't."*

---

*End of Document 03. Next: Document 04 — Redis / Queues (questions 171–215).*
