# Part 5 — Practice Lab (PostgreSQL)

Everything here is runnable. Paste the schema + seed, then work the exercises **before** looking at the solutions.

**Where to run it:** install Postgres locally, use Docker (`docker run --name pg -e POSTGRES_PASSWORD=pg -p 5432:5432 -d postgres:16`), or use a free hosted instance (Supabase, Neon). Client: `psql`, DBeaver, or pgAdmin. Learn `psql` — interviewers notice.

---

## Setup

```sql
DROP SCHEMA IF EXISTS lab CASCADE;
CREATE SCHEMA lab;
SET search_path = lab, public;

CREATE TABLE agent (
  agent_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  licence_no  varchar(20)  NOT NULL UNIQUE,
  full_name   text         NOT NULL,
  email       text         NOT NULL,
  city        text         NOT NULL,
  manager_id  bigint       REFERENCES agent(agent_id) ON DELETE SET NULL,
  joined_on   date         NOT NULL,
  created_at  timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT uq_agent_email UNIQUE (email)
);

CREATE TABLE course (
  course_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code          varchar(20)   NOT NULL UNIQUE,
  title         text          NOT NULL,
  fee           numeric(10,2) NOT NULL CHECK (fee >= 0),
  duration_mins integer       NOT NULL CHECK (duration_mins > 0),
  status        text          NOT NULL DEFAULT 'published'
                              CHECK (status IN ('draft','published','retired'))
);

CREATE TABLE topic (
  topic_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name     text NOT NULL UNIQUE
);

CREATE TABLE course_topic (
  course_id bigint NOT NULL REFERENCES course(course_id) ON DELETE CASCADE,
  topic_id  bigint NOT NULL REFERENCES topic(topic_id)  ON DELETE RESTRICT,
  weightage numeric(4,2) NOT NULL CHECK (weightage > 0 AND weightage <= 100),
  PRIMARY KEY (course_id, topic_id)
);

CREATE TABLE question (
  question_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  course_id   bigint NOT NULL REFERENCES course(course_id) ON DELETE CASCADE,
  topic_id    bigint NOT NULL REFERENCES topic(topic_id),
  body        text   NOT NULL,
  marks       integer NOT NULL DEFAULT 1 CHECK (marks > 0),
  difficulty  text   NOT NULL CHECK (difficulty IN ('easy','medium','hard'))
);

CREATE TABLE question_option (
  option_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  question_id bigint  NOT NULL REFERENCES question(question_id) ON DELETE CASCADE,
  body        text    NOT NULL,
  is_correct  boolean NOT NULL DEFAULT false
);

CREATE TABLE exam_attempt (
  attempt_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  agent_id     bigint NOT NULL REFERENCES agent(agent_id)  ON DELETE RESTRICT,
  course_id    bigint NOT NULL REFERENCES course(course_id) ON DELETE RESTRICT,
  started_at   timestamptz NOT NULL,
  submitted_at timestamptz,
  score        numeric(5,2) CHECK (score BETWEEN 0 AND 100),
  CONSTRAINT chk_window CHECK (submitted_at IS NULL OR submitted_at >= started_at),
  CONSTRAINT chk_score_present CHECK ((submitted_at IS NULL) = (score IS NULL))
);

CREATE TABLE attempt_answer (
  attempt_id  bigint NOT NULL REFERENCES exam_attempt(attempt_id) ON DELETE CASCADE,
  question_id bigint NOT NULL REFERENCES question(question_id),
  option_id   bigint          REFERENCES question_option(option_id),
  is_correct  boolean NOT NULL DEFAULT false,
  PRIMARY KEY (attempt_id, question_id)
);

-- Index every FK (Postgres does not do this for you)
CREATE INDEX idx_agent_manager        ON agent(manager_id);
CREATE INDEX idx_question_course      ON question(course_id);
CREATE INDEX idx_question_topic       ON question(topic_id);
CREATE INDEX idx_option_question      ON question_option(question_id);
CREATE INDEX idx_attempt_agent        ON exam_attempt(agent_id);
CREATE INDEX idx_attempt_course_start ON exam_attempt(course_id, started_at DESC);
CREATE INDEX idx_answer_question      ON attempt_answer(question_id);
```

## Seed

```sql
INSERT INTO agent (licence_no, full_name, email, city, manager_id, joined_on) VALUES
 ('LIC-1001','Ravi Kumar',   'ravi@example.com',   'Hyderabad', NULL, '2019-04-01'),
 ('LIC-1002','Priya Nair',   'priya@example.com',  'Kochi',        1, '2020-06-15'),
 ('LIC-1003','Arjun Menon',  'arjun@example.com',   'Mumbai',       1, '2021-01-10'),
 ('LIC-1004','Sneha Rao',    'sneha@example.com',  'Hyderabad',    2, '2022-08-01'),
 ('LIC-1005','Vikram Singh', 'vikram@example.com', 'Delhi',        2, '2023-03-20'),
 ('LIC-1006','Neha Gupta',   'neha@example.com',   'Patna',     NULL, '2024-11-05');

INSERT INTO course (code, title, fee, duration_mins, status) VALUES
 ('IRDAI-L1', 'IRDAI Level 1',            2500.00, 60,  'published'),
 ('IRDAI-L2', 'IRDAI Level 2',            4000.00, 90,  'published'),
 ('MOTOR-01', 'Motor Insurance Basics',   1500.00, 45,  'published'),
 ('HEALTH-01','Health Insurance Advanced',3000.00, 75,  'draft');

INSERT INTO topic (name) VALUES
 ('Life'), ('Motor'), ('Health'), ('Claims'), ('Regulation');

INSERT INTO course_topic (course_id, topic_id, weightage) VALUES
 (1,1,40),(1,5,60),
 (2,1,30),(2,4,30),(2,5,40),
 (3,2,70),(3,4,30),
 (4,3,100);

INSERT INTO question (course_id, topic_id, body, marks, difficulty) VALUES
 (1,1,'What is a term plan?',                  1,'easy'),
 (1,5,'Who regulates insurance in India?',     1,'easy'),
 (1,5,'Minimum free-look period in days?',     2,'medium'),
 (2,4,'Define subrogation.',                   2,'medium'),
 (2,5,'What is a grace period?',               1,'easy'),
 (2,1,'Explain surrender value.',              3,'hard'),
 (3,2,'What does third-party cover include?',  2,'medium'),
 (3,4,'What is IDV?',                          1,'easy');

INSERT INTO question_option (question_id, body, is_correct) VALUES
 (1,'Pure risk cover',true),(1,'Investment plan',false),(1,'Annuity',false),
 (2,'IRDAI',true),(2,'SEBI',false),(2,'RBI',false),
 (3,'15',true),(3,'30',false),(3,'7',false),
 (4,'Insurer recovers from third party',true),(4,'Premium refund',false),
 (5,'Extra time to pay premium',true),(5,'Claim window',false),
 (6,'Amount payable on early exit',true),(6,'Maturity bonus',false),
 (7,'Liability to others',true),(7,'Own damage',false),
 (8,'Insured Declared Value',true),(8,'Initial Deposit Value',false);

INSERT INTO exam_attempt (agent_id, course_id, started_at, submitted_at, score) VALUES
 (1,1,'2026-01-10 09:00+05:30','2026-01-10 09:45+05:30', 82.00),
 (1,1,'2026-02-14 10:00+05:30','2026-02-14 10:50+05:30', 91.50),
 (1,2,'2026-03-02 11:00+05:30','2026-03-02 12:20+05:30', 74.00),
 (2,1,'2026-01-20 14:00+05:30','2026-01-20 14:55+05:30', 58.00),
 (2,1,'2026-03-11 14:00+05:30','2026-03-11 14:40+05:30', 66.00),
 (2,3,'2026-04-05 16:00+05:30','2026-04-05 16:30+05:30', 88.00),
 (3,1,'2026-02-01 09:30+05:30','2026-02-01 10:15+05:30', 45.00),
 (3,2,'2026-05-09 09:30+05:30',NULL,                     NULL),
 (4,3,'2026-03-18 12:00+05:30','2026-03-18 12:35+05:30', 92.00),
 (4,1,'2026-04-22 12:00+05:30','2026-04-22 12:44+05:30', 79.50),
 (5,2,'2026-05-30 15:00+05:30','2026-05-30 16:10+05:30', 61.00),
 (5,3,'2026-06-14 15:00+05:30',NULL,                     NULL);

INSERT INTO attempt_answer (attempt_id, question_id, option_id, is_correct) VALUES
 (1,1,1,true),(1,2,4,true),(1,3,8,false),
 (4,1,2,false),(4,2,4,true),(4,3,7,true),
 (7,1,1,true),(7,2,5,false),(7,3,8,false);
```

---

## Exercises

### Tier 1 — basics (you can already do most of these)

1. All agents in Hyderabad, newest joiner first.
2. Courses with a fee between 2000 and 3500.
3. Distinct cities agents come from.
4. Count of agents per city, only cities with more than one agent.
5. Agents whose name contains "a" case-insensitively (use `ILIKE`).
6. Insert a new topic 'Underwriting'. Then rename it to 'Underwriting & Risk'.
7. Mark course `HEALTH-01` as published.
8. Delete any attempt that was started but never submitted more than 60 days ago.

### Tier 2 — joins, aggregation, NULLs

9. Every submitted attempt with agent name and course title.
10. Every agent with their attempt count — **including agents with zero attempts**.
11. Agents who have never attempted anything (two ways: `LEFT JOIN` and `NOT EXISTS`).
12. Average score per course, rounded to 2 decimals, highest first. Include courses with no attempts (show NULL).
13. Per course: attempts, passes (score ≥ 60), and pass percentage.
14. Each agent with their manager's name; agents with no manager show 'None'.
15. Total revenue per course, assuming each submitted attempt pays the course fee once.
16. Courses that have questions in more than one topic.
17. For each question, the text of its correct option.
18. Agents who scored ≥ 60 in *every* attempt they submitted (careful with agents who submitted nothing).

### Tier 3 — window functions, CTEs, casting

19. Rank agents by average score. Use `dense_rank()`.
20. Each agent's best 2 scores.
21. For every attempt, the agent's previous score and the delta (`lag`).
22. Running total of attempts per course, ordered by `started_at`.
23. Each attempt's score, plus the course average and the difference.
24. Attempt duration in minutes as an integer (`submitted_at - started_at`).
25. Format `started_at` as `DD Mon YYYY` and group attempts by month name.
26. Split agents into 3 buckets by average score using `ntile(3)`.
27. Build the full manager hierarchy with a recursive CTE, showing indent level.
28. For each course, the name of the agent who scored highest (use `DISTINCT ON` or a window function).

### Tier 4 — modeling, DDL, triggers

29. Add an `updated_at timestamptz NOT NULL DEFAULT now()` column to `course` and a trigger that maintains it.
30. Add a `course_audit` table and an `AFTER INSERT OR UPDATE OR DELETE` row trigger that records the operation and the row as `jsonb`.
31. Write a `BEFORE INSERT` trigger on `exam_attempt` that rejects an attempt on a course whose status is not `'published'`.
32. Design (DDL only) a `certificate` table: one certificate per agent per course, issued only once, with an expiry date, and a partial unique index that lets a revoked certificate be reissued.

---

## Solutions

<details>
<summary>Tier 1</summary>

```sql
-- 1
SELECT * FROM agent WHERE city = 'Hyderabad' ORDER BY joined_on DESC;

-- 2
SELECT * FROM course WHERE fee BETWEEN 2000 AND 3500;

-- 3
SELECT DISTINCT city FROM agent ORDER BY city;

-- 4
SELECT city, count(*) AS agents
FROM agent GROUP BY city HAVING count(*) > 1 ORDER BY agents DESC;

-- 5
SELECT full_name FROM agent WHERE full_name ILIKE '%a%';

-- 6
INSERT INTO topic (name) VALUES ('Underwriting');
UPDATE topic SET name = 'Underwriting & Risk' WHERE name = 'Underwriting';

-- 7
UPDATE course SET status = 'published' WHERE code = 'HEALTH-01';

-- 8
DELETE FROM exam_attempt
WHERE submitted_at IS NULL
  AND started_at < now() - interval '60 days';
```
</details>

<details>
<summary>Tier 2</summary>

```sql
-- 9
SELECT a.full_name, c.title, ea.score, ea.submitted_at
FROM exam_attempt ea
JOIN agent  a ON a.agent_id  = ea.agent_id
JOIN course c ON c.course_id = ea.course_id
WHERE ea.submitted_at IS NOT NULL
ORDER BY ea.submitted_at;

-- 10
SELECT a.full_name, count(ea.attempt_id) AS attempts
FROM agent a
LEFT JOIN exam_attempt ea ON ea.agent_id = a.agent_id
GROUP BY a.agent_id, a.full_name
ORDER BY attempts DESC;
-- count(ea.attempt_id), NOT count(*) — count(*) would return 1 for agents with no attempts

-- 11
SELECT a.* FROM agent a
LEFT JOIN exam_attempt ea ON ea.agent_id = a.agent_id
WHERE ea.attempt_id IS NULL;

SELECT a.* FROM agent a
WHERE NOT EXISTS (SELECT 1 FROM exam_attempt ea WHERE ea.agent_id = a.agent_id);

-- 12
SELECT c.title, round(avg(ea.score), 2) AS avg_score
FROM course c
LEFT JOIN exam_attempt ea ON ea.course_id = c.course_id
GROUP BY c.course_id, c.title
ORDER BY avg_score DESC NULLS LAST;

-- 13
SELECT c.title,
       count(ea.attempt_id)                                AS attempts,
       count(*) FILTER (WHERE ea.score >= 60)              AS passes,
       round(100.0 * count(*) FILTER (WHERE ea.score >= 60)
             / NULLIF(count(ea.score), 0), 1)              AS pass_pct
FROM course c
LEFT JOIN exam_attempt ea ON ea.course_id = c.course_id
GROUP BY c.course_id, c.title;

-- 14
SELECT a.full_name AS agent, coalesce(m.full_name, 'None') AS manager
FROM agent a LEFT JOIN agent m ON m.agent_id = a.manager_id
ORDER BY a.agent_id;

-- 15
SELECT c.title, count(ea.attempt_id) * c.fee AS revenue
FROM course c
LEFT JOIN exam_attempt ea
       ON ea.course_id = c.course_id AND ea.submitted_at IS NOT NULL
GROUP BY c.course_id, c.title, c.fee
ORDER BY revenue DESC;
-- note the filter is in ON, not WHERE, to keep zero-attempt courses

-- 16
SELECT c.title, count(DISTINCT q.topic_id) AS topics
FROM course c JOIN question q ON q.course_id = c.course_id
GROUP BY c.course_id, c.title
HAVING count(DISTINCT q.topic_id) > 1;

-- 17
SELECT q.body AS question, o.body AS correct_answer
FROM question q
JOIN question_option o ON o.question_id = q.question_id AND o.is_correct
ORDER BY q.question_id;

-- 18
SELECT a.full_name, min(ea.score) AS worst
FROM agent a
JOIN exam_attempt ea ON ea.agent_id = a.agent_id
WHERE ea.submitted_at IS NOT NULL
GROUP BY a.agent_id, a.full_name
HAVING min(ea.score) >= 60;
-- the JOIN (not LEFT JOIN) correctly excludes agents who submitted nothing
```
</details>

<details>
<summary>Tier 3</summary>

```sql
-- 19
SELECT a.full_name,
       round(avg(ea.score),2) AS avg_score,
       dense_rank() OVER (ORDER BY avg(ea.score) DESC) AS rnk
FROM agent a JOIN exam_attempt ea USING (agent_id)
WHERE ea.score IS NOT NULL
GROUP BY a.agent_id, a.full_name;
-- window functions may wrap aggregates, since they run after GROUP BY

-- 20
WITH ranked AS (
  SELECT ea.*, row_number() OVER (PARTITION BY agent_id ORDER BY score DESC) AS rn
  FROM exam_attempt ea WHERE score IS NOT NULL
)
SELECT agent_id, course_id, score FROM ranked WHERE rn <= 2 ORDER BY agent_id, rn;

-- 21
SELECT agent_id, started_at, score,
       lag(score) OVER (PARTITION BY agent_id ORDER BY started_at) AS prev_score,
       score - lag(score) OVER (PARTITION BY agent_id ORDER BY started_at) AS delta
FROM exam_attempt WHERE score IS NOT NULL;

-- 22
SELECT course_id, started_at,
       count(*) OVER (PARTITION BY course_id ORDER BY started_at
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_attempts
FROM exam_attempt ORDER BY course_id, started_at;

-- 23
SELECT attempt_id, course_id, score,
       round(avg(score) OVER (PARTITION BY course_id), 2)   AS course_avg,
       round(score - avg(score) OVER (PARTITION BY course_id), 2) AS diff
FROM exam_attempt WHERE score IS NOT NULL;

-- 24
SELECT attempt_id,
       extract(epoch FROM (submitted_at - started_at))::int / 60 AS minutes
FROM exam_attempt WHERE submitted_at IS NOT NULL;

-- 25
SELECT to_char(started_at, 'DD Mon YYYY') AS on_date,
       to_char(started_at, 'Mon')          AS month,
       count(*)
FROM exam_attempt
GROUP BY to_char(started_at,'DD Mon YYYY'), to_char(started_at,'Mon'), date_trunc('month', started_at)
ORDER BY date_trunc('month', started_at);

-- 26
SELECT full_name, avg_score, ntile(3) OVER (ORDER BY avg_score DESC) AS bucket
FROM (SELECT a.full_name, avg(ea.score) AS avg_score
      FROM agent a JOIN exam_attempt ea USING (agent_id)
      WHERE ea.score IS NOT NULL
      GROUP BY a.agent_id, a.full_name) t;

-- 27
WITH RECURSIVE org AS (
  SELECT agent_id, full_name, manager_id, 1 AS lvl
  FROM agent WHERE manager_id IS NULL
  UNION ALL
  SELECT a.agent_id, a.full_name, a.manager_id, o.lvl + 1
  FROM agent a JOIN org o ON a.manager_id = o.agent_id
)
SELECT repeat('   ', lvl - 1) || full_name AS hierarchy, lvl
FROM org ORDER BY lvl, full_name;

-- 28 (DISTINCT ON — a Postgres-only shortcut)
SELECT DISTINCT ON (ea.course_id)
       c.title, a.full_name, ea.score
FROM exam_attempt ea
JOIN agent a  USING (agent_id)
JOIN course c USING (course_id)
WHERE ea.score IS NOT NULL
ORDER BY ea.course_id, ea.score DESC;
-- DISTINCT ON keeps the first row per listed expression; the ORDER BY must start with it
```
</details>

<details>
<summary>Tier 4</summary>

```sql
-- 29
ALTER TABLE course ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END; $$;

CREATE TRIGGER trg_course_updated
BEFORE UPDATE ON course FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 30
CREATE TABLE course_audit (
  audit_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  course_id  bigint,
  operation  text NOT NULL,
  old_row    jsonb,
  new_row    jsonb,
  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION audit_course() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO course_audit (course_id, operation, old_row, new_row)
  VALUES (coalesce(NEW.course_id, OLD.course_id),
          TG_OP,
          CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
  RETURN NULL;               -- AFTER trigger: return value ignored
END; $$;

CREATE TRIGGER trg_course_audit
AFTER INSERT OR UPDATE OR DELETE ON course
FOR EACH ROW EXECUTE FUNCTION audit_course();

-- 31
CREATE OR REPLACE FUNCTION block_unpublished_attempt() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM course WHERE course_id = NEW.course_id;
  IF v_status <> 'published' THEN
    RAISE EXCEPTION 'Course % is % and cannot be attempted', NEW.course_id, v_status
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_block_unpublished
BEFORE INSERT ON exam_attempt FOR EACH ROW
EXECUTE FUNCTION block_unpublished_attempt();

-- 32
CREATE TABLE certificate (
  certificate_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  agent_id   bigint NOT NULL REFERENCES agent(agent_id)   ON DELETE RESTRICT,
  course_id  bigint NOT NULL REFERENCES course(course_id) ON DELETE RESTRICT,
  attempt_id bigint NOT NULL REFERENCES exam_attempt(attempt_id) ON DELETE RESTRICT,
  serial_no  varchar(30) NOT NULL UNIQUE,
  issued_on  date NOT NULL DEFAULT current_date,
  expires_on date NOT NULL,
  revoked_at timestamptz,
  CONSTRAINT chk_expiry CHECK (expires_on > issued_on)
);

CREATE UNIQUE INDEX uq_cert_active
  ON certificate (agent_id, course_id)
  WHERE revoked_at IS NULL;
```
</details>

---

## Study plan (4 weeks, ~1 hr/day)

| Week | Focus | Deliverable |
|---|---|---|
| 1 | Part 1 + Part 2. Model a domain of your own from scratch. | An ER sketch + working DDL for a 6–8 table schema, with constraints and indexes |
| 2 | Part 3 §1–6. Tiers 1–2 of the lab, twice — second time without looking. | All Tier 2 solved cold |
| 3 | Part 3 §7 (windows) + Part 4 triggers. Tier 3 + 29–31. | Explain `rank` vs `dense_rank` vs `row_number` out loud, unprompted |
| 4 | Part 4 transactions/isolation/locking. `EXPLAIN ANALYZE` every query you wrote. Tier 4. | Identify one missing index by reading a plan |

Then: take one real screen from an app you've built, and design the Postgres schema that would back it. That exercise is what interviews actually test.

---

## Interview questions you should be able to answer cold

**Modeling**
1. Walk me through normalizing this table to 3NF. *(They'll show you a flat spreadsheet.)*
2. When would you denormalize?
3. Surrogate vs natural key — which and why?
4. How do you model many-to-many? Many-to-many with attributes?
5. How do you store data that changes over time and must be queryable historically?

**SQL**
6. Difference between `WHERE` and `HAVING`.
7. `INNER` vs `LEFT` vs `FULL` join. Draw the Venn diagram, then explain why the Venn diagram is a lie for duplicate keys.
8. `UNION` vs `UNION ALL` — which is faster and why.
9. Second-highest salary/score, three different ways.
10. Find and delete duplicate rows.
11. `rank` vs `dense_rank` vs `row_number`.
12. Top N per group.
13. Why does `NOT IN` with NULLs return nothing?
14. `DELETE` vs `TRUNCATE` vs `DROP`.
15. `COUNT(*)` vs `COUNT(col)` vs `COUNT(DISTINCT col)`.

**Engine**
16. What is an index, and when does adding one hurt?
17. Why is my query not using the index?
18. Explain ACID.
19. Isolation levels and the anomalies each prevents.
20. What is a deadlock and how do you prevent it?
21. What is MVCC / why does Postgres need `VACUUM`?
22. What is a trigger, and when would you avoid one?
23. Clustered vs non-clustered index — *(trap: Postgres has no clustered indexes. All indexes are secondary; the heap is unordered. `CLUSTER` is a one-time physical reorder that isn't maintained. Say this and you'll stand out.)*
24. How do you prevent SQL injection?
25. How would you debug a query that suddenly got slow in production?
