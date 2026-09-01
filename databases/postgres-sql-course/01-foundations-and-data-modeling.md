# Part 1 — DBMS Foundations & Data Modeling (PostgreSQL)

Goal of this file: build the mental model. No syntax yet beyond what's needed.

---

## 1. What a relational DBMS actually gives you

If you've been living in Firestore/Realtime DB, the shift is this:

| Document DB (Firestore) | Relational DB (Postgres) |
|---|---|
| You design for the **read** — duplicate data into each doc | You design for the **truth** — store each fact once, join at read time |
| No schema; app enforces shape | Schema enforced by the engine; bad data is rejected |
| Denormalization is the default | Normalization is the default; denormalize only with a measured reason |
| No joins (you do N reads in a loop) | Joins are the primary tool and are cheap when indexed |
| Transactions are limited/awkward | ACID transactions across any number of tables |
| Aggregations require counters you maintain | `SUM/COUNT/AVG/GROUP BY` computed on demand |

**The single biggest habit to unlearn:** duplicating a value into 5 places "so the screen loads fast." In Postgres, duplication is a bug — it creates *update anomalies* (you change an agent's name, 4 copies go stale).

### ACID, plainly

- **Atomicity** — a transaction is all-or-nothing. Money leaves A *and* arrives at B, or neither happens.
- **Consistency** — constraints (FK, CHECK, UNIQUE, NOT NULL) hold before and after. The DB refuses writes that break them.
- **Isolation** — concurrent transactions don't see each other's half-finished work.
- **Durability** — once `COMMIT` returns, the data survives a power cut (WAL — write-ahead log).

---

## 2. Vocabulary you'll be asked about

| Term | Meaning |
|---|---|
| **Relation / table** | A set of rows with the same columns |
| **Tuple / row / record** | One entry |
| **Attribute / column / field** | One property |
| **Degree** | Number of columns |
| **Cardinality** | Number of rows (also used for "1:N" relationship type — context tells you which) |
| **Domain** | The set of legal values for a column (its type + constraints) |
| **DDL** | Data Definition Language — `CREATE`, `ALTER`, `DROP`, `TRUNCATE` |
| **DML** | Data Manipulation Language — `SELECT`, `INSERT`, `UPDATE`, `DELETE` |
| **DCL** | Data Control Language — `GRANT`, `REVOKE` |
| **TCL** | Transaction Control — `BEGIN`, `COMMIT`, `ROLLBACK`, `SAVEPOINT` |

> Interview note: in Postgres, **DDL is transactional**. You can `BEGIN; ALTER TABLE ...; ROLLBACK;`. This is *not* true in MySQL or Oracle, and it's a genuinely nice differentiator to mention.

---

## 3. Keys — the part people get wrong in interviews

- **Super key** — any set of columns that uniquely identifies a row (may contain junk columns).
- **Candidate key** — a *minimal* super key. Remove any column and it stops being unique.
- **Primary key (PK)** — the candidate key you chose. Implies `UNIQUE + NOT NULL`. One per table.
- **Alternate key** — the candidate keys you didn't choose. Enforce them with `UNIQUE`.
- **Composite key** — a PK made of 2+ columns. Standard for join tables.
- **Foreign key (FK)** — a column whose values must exist in another table's PK/unique column. This is *referential integrity*.
- **Surrogate key** — a meaningless generated id (`bigint identity`, `uuid`).
- **Natural key** — a real-world identifier (email, PAN, agent licence number, ISBN).

### Surrogate vs natural — the actual answer

Use a **surrogate PK** for almost every entity table, and put a **`UNIQUE` constraint on the natural key**. You get stable FKs (a surrogate never changes) *and* enforced business uniqueness.

```sql
CREATE TABLE agent (
  agent_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,  -- surrogate
  licence_no    text NOT NULL UNIQUE,                             -- natural key, enforced
  email         citext NOT NULL UNIQUE,
  full_name     text NOT NULL
);
```

Why not make `licence_no` the PK? Because regulators reissue licence numbers, people typo them, and every FK in your DB would have to be updated when one changes.

**`bigint` vs `uuid`:** default to `bigint GENERATED ALWAYS AS IDENTITY` — 8 bytes, sequential, index-friendly. Choose `uuid` when clients must generate ids offline (very common in mobile apps — your Flutter client creates the row id before it ever reaches the server) or when you're merging data from multiple systems. If you use UUIDs, prefer a time-ordered variant (UUIDv7) over random v4, because random ids scatter B-tree inserts across the whole index and hurt write throughput.

---

## 4. Relationships and how to physically model them

### One-to-many (1:N) — the workhorse

An agent has many exam attempts. **The FK lives on the "many" side.**

```
agent (1) ────< exam_attempt (N)
                  agent_id → agent.agent_id
```

### Many-to-many (M:N) — needs a junction table

A course covers many topics; a topic appears in many courses. Postgres has no M:N construct — you create a third table.

```
course (1) ────< course_topic >──── (1) topic
                 PK (course_id, topic_id)
```

```sql
CREATE TABLE course_topic (
  course_id bigint NOT NULL REFERENCES course(course_id) ON DELETE CASCADE,
  topic_id  bigint NOT NULL REFERENCES topic(topic_id)  ON DELETE RESTRICT,
  weightage numeric(4,2) NOT NULL CHECK (weightage > 0),
  PRIMARY KEY (course_id, topic_id)
);
```

Note the composite PK — it both identifies the row *and* prevents the same topic being added twice to a course. The moment the junction gets its own attributes (`weightage` here), it stops being a "link table" and becomes a real entity.

### One-to-one (1:1)

Rare, and usually one of three things:
1. **Table splitting for optional/bulky data** — `agent` and `agent_kyc_document`. FK + `UNIQUE` on the child.
2. **Type/subtype (inheritance)** — see below.
3. **A mistake** — the columns should just be in the parent table.

### Self-referencing

An agent has a manager, who is also an agent.

```sql
manager_id bigint REFERENCES agent(agent_id)   -- nullable: the top manager has none
```

### Type/subtype (a.k.a. inheritance / polymorphism)

`policy` is a supertype; `life_policy` and `motor_policy` are subtypes with different columns. Three strategies:

| Strategy | Shape | Use when |
|---|---|---|
| Single table | One wide table, lots of NULLs, a `policy_type` discriminator | Subtypes barely differ |
| Class table | `policy` + `life_policy` + `motor_policy`, child PK is also FK to parent | Subtypes differ a lot, you query across all of them |
| Concrete table | Fully separate tables, no shared parent | You never query across subtypes |

Class-table is the default correct answer for an interview.

---

## 5. Normalization

Normalization = organizing columns so that **every non-key fact depends on the key, the whole key, and nothing but the key**.

Start from a bad table:

| attempt_id | agent_name | agent_email | course_name | course_fee | question_ids | score |
|---|---|---|---|---|---|---|
| 1 | Ravi K | ravi@x.com | IRDAI Level 1 | 2500 | 4,7,9 | 78 |

### 1NF — atomic values, no repeating groups

`question_ids = "4,7,9"` breaks 1NF. You cannot index it, join on it, or constrain it. Fix: a child table `attempt_question(attempt_id, question_id, ...)`.

> Interview trap: "Is a Postgres `jsonb` or array column a 1NF violation?" Formally yes. Practically, they're accepted for genuinely unstructured payloads (API responses, event metadata, per-tenant custom fields). They are the wrong choice for anything you filter, join, or aggregate on regularly.

### 2NF — no partial dependency on part of a composite key

Only applies when the PK is composite. If PK is `(attempt_id, question_id)` and you store `agent_name`, that depends on `attempt_id` alone — a partial dependency. Move it out.

### 3NF — no transitive dependency (non-key → non-key)

`course_fee` depends on `course_name`, which depends on `attempt_id`. `course_fee` is a fact about the *course*, not the attempt. Move it to a `course` table.

### BCNF — every determinant is a candidate key

A stricter 3NF. Comes up when a table has overlapping candidate keys. Classic example: `(course, slot) → instructor` and `instructor → course`. Here `instructor` determines `course` but isn't a candidate key, so it's 3NF but not BCNF.

### Normalized result

```
agent(agent_id PK, full_name, email)
course(course_id PK, name, fee)
exam_attempt(attempt_id PK, agent_id FK, course_id FK, started_at, score)
attempt_question(attempt_id FK, question_id FK, chosen_option_id, is_correct, PK(attempt_id, question_id))
```

### The one legitimate exception: denormalization

Denormalize **only** when you have a measured read problem, and then you must guarantee the copy stays correct. Legitimate patterns:

1. **Historical snapshot** — `order_line.unit_price_at_purchase`. This isn't denormalization at all; the price *at that moment* is a genuine fact about the order line. Product price changing later must not rewrite history. Same for `policy.premium_at_issue`.
2. **Materialized aggregate** — `course.attempt_count`, maintained by a trigger (Part 4) or a materialized view.
3. **`jsonb` blob** — for a payload you store and return whole and never query into.

Anything else, join instead.

> **Higher normal forms (4NF/5NF)** exist and deal with multi-valued and join dependencies. Knowing the names and "4NF removes independent multi-valued facts from the same table" is sufficient for a 2-year role.

---

## 6. Designing a schema — a repeatable process

1. **List the nouns** in the requirements. Nouns become candidate entities. (Agent, Course, Topic, Question, Option, Attempt, Answer.)
2. **List the verbs** connecting them. Verbs become relationships. ("An agent *attempts* a course.")
3. **Assign cardinality to each relationship** — 1:1, 1:N, M:N. Write it down explicitly; this is where bugs are born.
4. **Give each entity a PK.** Surrogate by default.
5. **Place FKs** — many side for 1:N, junction table for M:N.
6. **Attach attributes** to the entity they actually describe, then run the 3NF check on each table: *does every column depend on the whole PK and nothing else?*
7. **Add constraints** — `NOT NULL` aggressively, `CHECK` for domain rules, `UNIQUE` for natural keys. A column is nullable only if "unknown / not applicable" is a real business state.
8. **Decide FK delete behaviour** per relationship — `CASCADE`, `RESTRICT`, `SET NULL` (Part 2).
9. **Index for your actual queries** — every FK, plus columns in `WHERE`/`ORDER BY`/`JOIN` (Part 2).
10. **Add audit columns** — `created_at timestamptz NOT NULL DEFAULT now()`, `updated_at`. You will always want them and adding them later on a big table is painful.

### Naming conventions (pick one and never deviate)

- `snake_case` everywhere. Postgres folds unquoted identifiers to lowercase, so `CamelCase` forces you into `"DoubleQuotes"` forever. Avoid.
- Singular table names (`agent`, not `agents`) — either is defensible, consistency is what matters.
- PK: `agent_id`. FK: same name as the PK it points to.
- Never name a column `user`, `order`, `group`, `desc`, `end` — reserved words.
- Constraints: `chk_agent_email_format`, `uq_agent_licence`, `fk_attempt_agent`, `idx_attempt_agent_id`.

---

## 7. Two modeling patterns you'll meet at 2 years

### Soft deletes

Instead of `DELETE`, set `deleted_at timestamptz`. Keeps history and FK integrity. Cost: every query needs `WHERE deleted_at IS NULL` — wrap tables in a view, or use a partial unique index so deleted rows don't block reuse of a natural key:

```sql
CREATE UNIQUE INDEX uq_agent_email_active
  ON agent(email) WHERE deleted_at IS NULL;
```

### Slowly changing dimensions / temporal data

When you must answer "what was the premium on 3 March?", don't overwrite. Store a validity range:

```sql
CREATE TABLE policy_premium (
  policy_id  bigint NOT NULL REFERENCES policy(policy_id),
  amount     numeric(12,2) NOT NULL,
  valid_from date NOT NULL,
  valid_to   date,                     -- NULL = current
  PRIMARY KEY (policy_id, valid_from)
);
```

Postgres can enforce non-overlap properly with a range type and an exclusion constraint — covered in Part 2.

---

## 8. Self-check before moving to Part 2

1. Difference between a candidate key and a super key?
2. Where does the FK go in a 1:N relationship, and why can't it go on the "one" side?
3. A table with PK `(order_id, product_id)` stores `customer_name`. Which normal form is violated?
4. Give one case where storing a duplicated value is correct.
5. Why is `bigint` usually a better PK than `uuid v4` for a server-generated id?
