# Part 3 — SQL Query Craft (PostgreSQL)

This is the file that decides whether you read as a 6-month dev or a 2-year dev.

---

## 1. Logical execution order — learn this first

You *write* a query in this order:

```
SELECT → FROM → WHERE → GROUP BY → HAVING → ORDER BY → LIMIT
```

The engine *evaluates* it in this order:

```
1. FROM / JOIN      build the working set
2. WHERE            filter individual rows
3. GROUP BY         collapse rows into groups
4. HAVING           filter groups
5. SELECT           compute output columns, evaluate window functions
6. DISTINCT
7. ORDER BY
8. LIMIT / OFFSET
```

Three consequences that explain most beginner errors:

- **You can't use a `SELECT` alias in `WHERE`** — `WHERE` runs before `SELECT` exists. (Postgres kindly *does* allow aliases in `GROUP BY` and `ORDER BY`, because those run at or after `SELECT`.)
- **`WHERE` filters rows, `HAVING` filters groups.** `WHERE score > 50` before grouping; `HAVING count(*) > 3` after.
- **You can't nest a window function inside an aggregate**, or filter on a window function in `WHERE` — wrap the query in a CTE/subquery first.

---

## 2. Joins

Setup: `agent` (5 rows), `exam_attempt` (some agents have none, one attempt has a NULL course).

| Join | Returns |
|---|---|
| `INNER JOIN` | Rows with a match on both sides |
| `LEFT JOIN` | All left rows; NULLs where no right match |
| `RIGHT JOIN` | Mirror of LEFT (just rewrite as LEFT — clearer) |
| `FULL OUTER JOIN` | All rows from both, NULL-padded |
| `CROSS JOIN` | Cartesian product — every combination |
| `SELF JOIN` | A table joined to itself |

```sql
SELECT a.full_name, c.title, ea.score
FROM   exam_attempt ea
JOIN   agent  a ON a.agent_id  = ea.agent_id
JOIN   course c ON c.course_id = ea.course_id
WHERE  ea.score >= 60;
```

### The `LEFT JOIN` + `WHERE` trap

```sql
-- BROKEN: silently becomes an INNER JOIN
SELECT a.full_name, ea.score
FROM agent a
LEFT JOIN exam_attempt ea ON ea.agent_id = a.agent_id
WHERE ea.score >= 60;
```

Agents with no attempts get `ea.score = NULL`, and `NULL >= 60` is not true, so `WHERE` drops them. Any filter on the *right* table of a LEFT JOIN must go in the `ON` clause:

```sql
LEFT JOIN exam_attempt ea ON ea.agent_id = a.agent_id AND ea.score >= 60
```

Filters on the **left** table still belong in `WHERE`. On an `INNER JOIN`, `ON` and `WHERE` are equivalent.

### Anti-join — "find rows with no match"

```sql
-- Agents who never attempted an exam
SELECT a.*
FROM agent a
LEFT JOIN exam_attempt ea ON ea.agent_id = a.agent_id
WHERE ea.attempt_id IS NULL;

-- Same thing, usually clearer and often faster:
SELECT a.* FROM agent a
WHERE NOT EXISTS (SELECT 1 FROM exam_attempt ea WHERE ea.agent_id = a.agent_id);
```

**Never use `NOT IN` with a nullable subquery column.** If the subquery returns a single NULL, `NOT IN` returns zero rows — silently, with no error. Use `NOT EXISTS`.

### Self join

```sql
SELECT e.full_name AS agent, m.full_name AS manager
FROM agent e
LEFT JOIN agent m ON m.agent_id = e.manager_id;
```

### Postgres extras

```sql
-- USING: when column names match on both sides; merges them into one output column
SELECT * FROM exam_attempt JOIN agent USING (agent_id);

-- LATERAL: the right side can reference the left side. Perfect for top-N-per-group.
SELECT a.full_name, recent.score, recent.started_at
FROM agent a
LEFT JOIN LATERAL (
  SELECT ea.score, ea.started_at
  FROM exam_attempt ea
  WHERE ea.agent_id = a.agent_id
  ORDER BY ea.started_at DESC
  LIMIT 3
) recent ON true;
```

---

## 3. NULL — the source of half of all SQL bugs

NULL means *unknown*, not zero and not empty string.

```sql
NULL = NULL        → NULL   (not true!)
NULL <> NULL       → NULL
5 > NULL           → NULL
NULL AND false     → false
NULL AND true      → NULL
NULL OR true       → true
```

`WHERE` keeps only rows where the condition is **true** — `NULL` is discarded like `false`.

Rules:
- Test with `IS NULL` / `IS NOT NULL`, never `= NULL`.
- `IS DISTINCT FROM` is NULL-safe equality: `a IS DISTINCT FROM b` treats two NULLs as equal-ish (returns false when both NULL).
- `COALESCE(a, b, c)` → first non-NULL.
- `NULLIF(a, b)` → NULL if `a = b`, else `a`. Classic use: `x / NULLIF(y, 0)` to avoid divide-by-zero.
- Aggregates **skip NULLs**: `COUNT(col)` ignores NULLs, `COUNT(*)` counts rows. `AVG` divides by the non-NULL count.
- `UNIQUE` allows multiple NULLs (they're all "unknown", so not proven duplicate).
- `||` propagates NULL; `concat()` ignores it.

---

## 4. Aggregation

```sql
SELECT c.title,
       count(*)                                    AS attempts,
       count(ea.score)                             AS scored_attempts,
       round(avg(ea.score), 2)                     AS avg_score,
       max(ea.score)                               AS best,
       count(*) FILTER (WHERE ea.score >= 60)      AS passes,
       round(100.0 * count(*) FILTER (WHERE ea.score >= 60) / count(*), 1) AS pass_pct
FROM   course c
JOIN   exam_attempt ea ON ea.course_id = c.course_id
GROUP BY c.title
HAVING count(*) >= 10
ORDER BY avg_score DESC NULLS LAST;
```

`FILTER (WHERE ...)` is the Postgres way to do conditional aggregation — cleaner than `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`, though that form still works and is portable.

**Golden rule:** every column in `SELECT` must be either inside an aggregate or listed in `GROUP BY`. (Exception: if you group by a table's PK, Postgres lets you select any column of that table, since it's functionally dependent.)

Useful aggregates beyond the basics:
```sql
string_agg(a.full_name, ', ' ORDER BY a.full_name)   -- concatenate a group
array_agg(ea.score ORDER BY ea.started_at)           -- collect into an array
jsonb_agg(jsonb_build_object('id', ea.attempt_id, 'score', ea.score))
percentile_cont(0.5) WITHIN GROUP (ORDER BY score)   -- median
bool_or(is_correct), bool_and(is_correct)
```

Grouping extensions: `GROUP BY ROLLUP (region, city)` adds subtotal + grand-total rows; `CUBE` gives every combination; `GROUPING SETS` lets you specify them explicitly.

---

## 5. Subqueries

```sql
-- Scalar subquery (returns one value)
SELECT full_name,
       (SELECT count(*) FROM exam_attempt ea WHERE ea.agent_id = a.agent_id) AS attempts
FROM agent a;

-- IN / EXISTS
SELECT * FROM agent a
WHERE EXISTS (SELECT 1 FROM exam_attempt ea
              WHERE ea.agent_id = a.agent_id AND ea.score >= 90);

-- Derived table (subquery in FROM) — must be aliased
SELECT t.agent_id, t.avg_score
FROM (SELECT agent_id, avg(score) AS avg_score
      FROM exam_attempt GROUP BY agent_id) t
WHERE t.avg_score > 70;
```

**Correlated vs non-correlated:** a correlated subquery references the outer query (`ea.agent_id = a.agent_id`) and is conceptually re-evaluated per outer row. Non-correlated runs once. Postgres often rewrites correlated `EXISTS` into a hash semi-join anyway, so readability usually wins — but a correlated *scalar* subquery in `SELECT` over a million rows is a genuine performance smell; convert it to a `LEFT JOIN` on an aggregate.

`IN` vs `EXISTS`: with a modern planner, similar for most cases. `EXISTS` is safer (no NULL trap) and better when the subquery is large. `IN` is fine for a small explicit list.

---

## 6. CTEs (`WITH`)

CTEs turn one unreadable 60-line query into named steps.

```sql
WITH scored AS (
    SELECT agent_id, course_id, score
    FROM   exam_attempt
    WHERE  submitted_at IS NOT NULL
),
per_agent AS (
    SELECT agent_id, avg(score) AS avg_score, count(*) AS n
    FROM   scored
    GROUP  BY agent_id
)
SELECT a.full_name, p.avg_score, p.n
FROM   per_agent p
JOIN   agent a USING (agent_id)
WHERE  p.n >= 3
ORDER  BY p.avg_score DESC;
```

In modern Postgres, CTEs are **inlined** into the main query by default (so no automatic performance penalty), unless the CTE is recursive, used more than once, or contains a data-modifying statement. Force the behaviour with `WITH x AS MATERIALIZED (...)` or `AS NOT MATERIALIZED (...)`.

### Recursive CTEs — hierarchies

```sql
WITH RECURSIVE org AS (
    -- anchor: top-level managers
    SELECT agent_id, full_name, manager_id, 1 AS level
    FROM   agent
    WHERE  manager_id IS NULL

    UNION ALL

    -- recursive step
    SELECT a.agent_id, a.full_name, a.manager_id, o.level + 1
    FROM   agent a
    JOIN   org o ON a.manager_id = o.agent_id
)
SELECT repeat('  ', level - 1) || full_name AS tree, level
FROM org ORDER BY level;
```

Use for org charts, category trees, bill-of-materials, comment threads. Guard against cycles with a `level < 20` condition or by tracking visited ids in an array.

### Data-modifying CTEs (very Postgres)

```sql
WITH archived AS (
    DELETE FROM exam_attempt
    WHERE started_at < now() - interval '2 years'
    RETURNING *
)
INSERT INTO exam_attempt_archive SELECT * FROM archived;
```

---

## 7. Window functions — the 2-year dividing line

An aggregate collapses rows. A **window function computes across a set of rows but keeps every row**.

```sql
SELECT
  a.full_name,
  ea.course_id,
  ea.score,
  avg(ea.score)  OVER (PARTITION BY ea.course_id)                    AS course_avg,
  ea.score - avg(ea.score) OVER (PARTITION BY ea.course_id)          AS vs_avg,
  rank()         OVER (PARTITION BY ea.course_id ORDER BY ea.score DESC) AS rank_in_course,
  lag(ea.score)  OVER (PARTITION BY ea.agent_id ORDER BY ea.started_at) AS prev_score,
  count(*)       OVER ()                                             AS total_rows
FROM exam_attempt ea
JOIN agent a USING (agent_id);
```

Anatomy: `function() OVER (PARTITION BY ... ORDER BY ... frame)`
- `PARTITION BY` — reset the calculation per group (optional; omit = whole result set)
- `ORDER BY` — order within the partition (required for ranking and offset functions)
- **frame** — which rows within the partition are visible

### The functions

| Function | Does |
|---|---|
| `row_number()` | 1,2,3,4 — always unique |
| `rank()` | 1,2,2,4 — ties share, then gap |
| `dense_rank()` | 1,2,2,3 — ties share, no gap |
| `ntile(4)` | Split into 4 buckets (quartiles) |
| `lag(col, n, default)` | Value from n rows back |
| `lead(col, n, default)` | Value from n rows ahead |
| `first_value` / `last_value` / `nth_value` | Value at a position in the frame |
| `sum/avg/count/max/min` | Same aggregates, windowed |

### Top-N per group — the classic interview question

"Give me each agent's 2 highest scores."

```sql
WITH ranked AS (
  SELECT ea.*,
         row_number() OVER (PARTITION BY agent_id ORDER BY score DESC, started_at) AS rn
  FROM exam_attempt ea
)
SELECT * FROM ranked WHERE rn <= 2;
```

The CTE is required — you cannot put a window function in `WHERE`, because windows are evaluated at `SELECT` time, after `WHERE`.

Which ranker? `row_number()` when you need exactly N rows. `rank()`/`dense_rank()` when ties should all be included.

### Running totals and frames

```sql
SELECT started_at, score,
       sum(score) OVER (PARTITION BY agent_id ORDER BY started_at
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
       avg(score) OVER (PARTITION BY agent_id ORDER BY started_at
                        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)          AS moving_avg_3
FROM exam_attempt;
```

**Frame gotcha:** if you write `ORDER BY` without an explicit frame, the default is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, which includes *all peer rows with the same ORDER BY value*. That's why `last_value()` so often returns the current row instead of the partition's last — you need `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

### Deduplication with window functions

```sql
DELETE FROM agent a
USING (
  SELECT agent_id,
         row_number() OVER (PARTITION BY lower(email) ORDER BY created_at) AS rn
  FROM agent
) d
WHERE a.agent_id = d.agent_id AND d.rn > 1;
```

---

## 8. `CASE`, set operations, and other tools

```sql
SELECT full_name,
       CASE WHEN score >= 80 THEN 'A'
            WHEN score >= 60 THEN 'B'
            WHEN score IS NULL THEN 'Not attempted'
            ELSE 'Fail' END AS grade
FROM ...;
```

Order matters — the first matching branch wins. No `ELSE` means NULL. `CASE` works in `SELECT`, `WHERE`, `ORDER BY`, `GROUP BY`, and inside aggregates.

Set operations (both sides need the same column count and compatible types):

| Op | Result |
|---|---|
| `UNION` | Combined, **duplicates removed** (costs a sort/hash) |
| `UNION ALL` | Combined, duplicates kept — **use this unless you need dedup** |
| `INTERSECT` | Rows in both |
| `EXCEPT` | Rows in the first, not in the second (SQL Server calls it `MINUS` in Oracle) |

---

## 9. Writes beyond `INSERT`/`UPDATE`/`DELETE`

### `RETURNING` — get the row back in one round trip

```sql
INSERT INTO agent (licence_no, email, full_name)
VALUES ('LIC-9981', 'ravi@x.com', 'Ravi K')
RETURNING agent_id, created_at;

UPDATE exam_attempt SET score = 88, submitted_at = now()
WHERE attempt_id = 12
RETURNING attempt_id, score;
```

This is Postgres's answer to a lot of what SQL Server's OUTPUT clause and magic tables are used for.

### Upsert — `INSERT ... ON CONFLICT`

```sql
INSERT INTO course (code, title, fee)
VALUES ('IRDAI-L1', 'IRDAI Level 1', 2500)
ON CONFLICT (code) DO UPDATE
  SET title = EXCLUDED.title,
      fee   = EXCLUDED.fee,
      updated_at = now()
RETURNING course_id;
```

`EXCLUDED` is the pseudo-table holding the row you *tried* to insert. `ON CONFLICT DO NOTHING` skips silently. The conflict target must have a unique index.

### `UPDATE ... FROM` (Postgres's join-update)

```sql
UPDATE exam_attempt ea
SET    score = calc.total
FROM  (SELECT attempt_id, sum(marks) AS total
       FROM attempt_question GROUP BY attempt_id) calc
WHERE  ea.attempt_id = calc.attempt_id;
```

### Bulk insert

```sql
INSERT INTO topic (name) VALUES ('Life'), ('Motor'), ('Health');   -- multi-row
COPY topic (name) FROM '/tmp/topics.csv' WITH (FORMAT csv, HEADER);  -- fastest bulk load
```

---

## 10. Views

```sql
CREATE VIEW v_agent_performance AS
SELECT a.agent_id, a.full_name, count(ea.attempt_id) AS attempts, avg(ea.score) AS avg_score
FROM agent a LEFT JOIN exam_attempt ea USING (agent_id)
GROUP BY a.agent_id, a.full_name;
```

A view is a stored query — no data of its own, always current, and it's expanded into the calling query at run time. Uses: hiding join complexity, exposing a restricted column set for security, providing a stable interface while the underlying tables change.

A **materialized view** does store results:

```sql
CREATE MATERIALIZED VIEW mv_daily_stats AS SELECT ... ;
CREATE UNIQUE INDEX ON mv_daily_stats (day);          -- required for CONCURRENTLY
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_stats;
```

Fast to read, stale until refreshed. Use for expensive dashboard aggregates.

---

## 11. Self-check

1. Why does `WHERE score > 50` on a `LEFT JOIN`'s right table break the join?
2. Difference between `rank()`, `dense_rank()` and `row_number()`?
3. Write "top 3 scores per course" two ways.
4. Why can `NOT IN` return zero rows unexpectedly?
5. Where does `HAVING` run relative to `WHERE`, and why can't you swap them?
6. What is `EXCLUDED` in an upsert?
