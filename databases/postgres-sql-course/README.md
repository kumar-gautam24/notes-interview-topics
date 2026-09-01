# PostgreSQL & SQL — a five-part course

A sequential, Postgres-first course that teaches SQL the way you actually use it, ending in a
runnable lab. Opinionated on purpose ("use this, not that"), and carries a running
SQL Server → PostgreSQL translation thread through Parts 2–4 for anyone arriving from T-SQL.

**Read in order** — each part builds on the last and ends with a self-check.

| Part | Covers |
|------|--------|
| [01 — Foundations & data modeling](01-foundations-and-data-modeling.md) | What an RDBMS gives you · DDL/DML/DCL/TCL · key theory · relationships · normalization to BCNF · a repeatable 10-step schema design process · soft deletes and temporal data |
| [02 — Types, tables, constraints, indexes](02-types-tables-constraints-indexes.md) | Choosing types deliberately · casting · the five constraint types plus `EXCLUDE` · generated columns · foreign keys and referential actions · zero-downtime DDL with `NOT VALID` · index types, composite/partial/covering, `CONCURRENTLY` |
| [03 — SQL query craft](03-sql-query-craft.md) | Logical execution order · joins and the `LEFT JOIN` + `WHERE` trap · NULL semantics · aggregation and `FILTER` · subqueries · CTEs including recursive and data-modifying · window functions · upserts and `RETURNING` · views |
| [04 — Triggers, functions, transactions](04-triggers-functions-transactions.md) | PL/pgSQL and volatility markers · triggers and audit logging · the "magic tables" answer (`NEW`/`OLD`, transition tables) · when *not* to use triggers · savepoints · isolation levels · locking, `SKIP LOCKED`, optimistic concurrency · `SECURITY DEFINER` |
| [05 — Practice lab](05-practice-lab.md) | An 8-table schema with seed data, 32 graded exercises across four tiers with worked solutions, a four-week study plan, and 25 interview questions to answer cold |

## See also

This course is the *taught path*. For engine internals and scaling — pages, TOAST, WAL, HOT
updates, partitioning, sharding, PgBouncer — go to
**[`../05-database-at-scale.md`](../05-database-at-scale.md)**, which covers index behaviour in
far more depth than Part 2 does. For exhaustive DBMS theory, see
[`../03-dbms-concepts.md`](../03-dbms-concepts.md); for drilling, [`../04-sql-interview-questions.md`](../04-sql-interview-questions.md).
