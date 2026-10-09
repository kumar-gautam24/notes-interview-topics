# 00 · Start Here: Headstart Client Interview

## The files
| # | File | What it's for |
|---|---|---|
| 00 | [00-start-here.md](00-start-here.md) | This page: what they expect, where each topic is covered, study order |
| 01 | [01-dsa-cpp.md](01-dsa-cpp.md) | Coding round in C++: the 6 screening problems, Fibonacci fix, right-shift, 6 likely next ones |
| 02 | [02-python-cheatsheet.md](02-python-cheatsheet.md) | Python language concepts interviewers probe (mutability, decorators, generators, OOP, exceptions, GIL) |
| 03 | [03-fastapi-pack.md](03-fastapi-pack.md) | FastAPI internals, auth, errors, versioning, background jobs, performance |
| 04 | [04-theory-answers.md](04-theory-answers.md) | Spoken answers to the recruiter's Q1–Q16, deep dives on your weak areas, the client's question bank |
| 05 | [05-indexing-deep-dive.md](05-indexing-deep-dive.md) | Indexing from zero: B-trees, composite indexes, index types, when not to index, EXPLAIN, spoken answer, self-quiz |
| 06 | [06-fastapi-rapid-fire.md](06-fastapi-rapid-fire.md) | Every FastAPI concept: glossary, middleware order, auth placement, DB sessions, errors, CORS, cookies/HTTPS, WebSockets, jobs, pagination, optimisation, trade-offs, structure |
| 07 | [07-mock-interview-log.md](07-mock-interview-log.md) | 30 mock questions: your answers, simple corrected answers, and new likely questions |
| 08 | [08-design-patterns.md](08-design-patterns.md) | Design patterns for a Python backend: simple idea, your real use, tested code, follow-ups, SOLID |
| 09 | [09-self-intro.md](09-self-intro.md) | Three self-intros (backend, SDE, Flutter), each in 30s / 90s / 2min, with follow-up answers |
| 10 | [10-project-questions.md](10-project-questions.md) | Questions your own projects will trigger (wallet, webhooks, workers, auth bugs, ABDM, gateway, multi-tenant) with follow-ups |
| code | [solutions.cpp](code/solutions.cpp) | All DSA solutions with asserts: `g++ -std=c++17 -O2 solutions.cpp -o sol && ./sol` |
| code | [fastapi_demo.py](code/fastapi_demo.py) | One-file multi-tenant CRM API showing every FastAPI pattern; `python3 fastapi_demo.py` runs its tests |
| code | [design_patterns.py](code/design_patterns.py) | 14 patterns in one file with tests: `python3 design_patterns.py` |

## What the client is actually testing
Headstart sells a **CRM to education institutions**: many colleges (tenants), lots of leads/students, bulk email/SMS campaigns, enrolment reports. The JD and question bank both point at the same thing: *can you build and scale a multi-tenant API that handles bulk data and background work safely?*

### Signals from the screening round
| Area | Screener said | What to do | Where |
|---|---|---|---|
| FastAPI, async, auth, Redis jobs, webhooks, idempotency, code reviews | **Strong** | Keep answers short and confident; one story each | 03, 04 §1–5 |
| Large-scale data processing | Weaker | Learn the streaming → batching → parallel → checkpoint model and the 2M-row CSV import story | 04 §6.1, 02 §5 |
| Multiprocessing | Weaker | GIL, I/O vs CPU-bound decision line, the comparison table, `ProcessPoolExecutor` code | 04 §6.2, 02 §10 |
| Multi-tenant architecture | Weaker | Three isolation models + trade-offs, tenant from JWT, RLS, tenant-leading indexes, noisy neighbours | 04 §6.3, 03 demo |
| Coding | 4/5; Fibonacci recursion not optimised | Always walk naive → memo → tabulation → O(1) → O(log n) out loud | 01 §1 |

### JD responsibilities → what they'll ask → where it's covered
| JD line | Likely questions | Where |
|---|---|---|
| API design & development, low latency | REST design, status codes, versioning without breaking mobile, pagination, idempotency | 03 §10, 04 Q10–Q12 |
| Database management, schemas, indexes | How indexes work / when not to, N+1, slow report from 2s to 40s, Mongo vs SQL | 04 Q13–Q15, §7.4–7.5 |
| Data consistency & integrity | Transactions, atomic updates, race conditions, unique constraints, ticketing concurrency | 04 §1 (wallet story), §7.3 |
| Authentication & authorisation (OAuth, JWT) | JWT structure, refresh rotation, logout, RBAC, 401 vs 403, OAuth flows | 03 §6 |
| Scalability & performance | Threads vs processes vs async, Celery + Redis roles, 1K vs 10M emails, caching | 04 §6.2, §7.7–7.8, 03 §11 |
| Error handling & logging | Exception hierarchy, global handlers, structured logs, request id, monitoring | 03 §7, 04 Q5, 02 §8 |
| Code quality & reviews | What you look for in a review, SOLID, testing approach | 02 §7, 03 §13 (see review checklist below) |
| Monitoring & maintenance | Finding bottlenecks, slow queries, alerts, backups | 04 Q14, 03 §11 |
| OOP proficiency (qualification) | Four pillars with a real example, ABC, classmethod vs staticmethod, MRO, composition | 02 §7, 04 Q4 |
| Django / Flask / FastAPI | Django signals, Channels vs WebSockets, ORM optimisation | 04 §7.1–7.2 |
| Microservices | Service boundaries, shared auth contract, async messaging, idempotent consumers | 04 Q1 (your auth/billing/pipeline services), §5 |
| MySQL / MongoDB / PostgreSQL | Hands-on depth, trade-offs | 04 Q13, Q15 |

### Gaps to be honest about (and how to answer)
Your resume has no production Django, Celery, MongoDB or multiprocessing. Don't bluff. Use the bridge formula:
> "I haven't used **X** in production. I've solved the same problem with **Y**, here's how, and here's how X differs."

- Celery → your Redis queue + workers (04 §5)
- Django → FastAPI + raw SQL; ORM equivalents of what you already do (04 §7.2)
- MongoDB → Postgres, plus the document-model trade-offs (04 Q15)
- Multiprocessing → threadpool offloading + the CPU-bound decision line (04 §6.2)

## Code-review checklist (they rated this strong; have it ready)
Correctness and edge cases · security (auth on every route, tenant filter, input validation, no secrets in code/logs) · DB (N+1, missing index, transactions, migrations reversible) · error handling and logging · naming and single responsibility · tests for unhappy paths · performance (blocking calls in async, unbounded queries) · backward compatibility of API changes.

## Study order
1. **01 DSA:** re-type Fibonacci (all versions) and right-shift-by-k from memory in C++; say complexities aloud.
2. **04 §6:** the three weak areas. Practise the multi-tenant spoken summary and the CSV import story until fluent.
3. **04 §7:** client question bank, especially 1K vs 10M emails and the ticketing system (they've asked these before).
4. **03 FastAPI + run the demo:** read the code once, then explain the request lifecycle and auth flow without notes.
5. **02 Python:** skim; drill §12 rapid-fire.
6. **04 §1–5:** fill every **[fill: …]** with your real numbers; rehearse Q1 to ~90 seconds.

## Day-of checklist
- Q1 pitch under 90 seconds, numbers filled in.
- Three scaling stories ready: event-loop blocking, OTP 8–10s → 500ms, Postgres blobs → R2.
- For coding: clarify → brute force → optimal → dry run → edge cases. Complexity before code.
- Two questions to ask them (04 §8).
