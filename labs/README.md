# Labs

Runnable, hands-on projects. Notes elsewhere in the repo explain the *why*; labs make you
measure it. Each lab is self-contained (`docker compose up`) with its own README.

| Lab | What you'll learn |
|-----|-------------------|
| [scaling-lab/](scaling-lab) — Module 1: Monitoring | FastAPI + Postgres (1M rows) + Prometheus/Grafana/cAdvisor + k6. Seven experiments: event-loop blocking, the GIL, Little's Law, CPU throttling, OOM kills, memory leaks, connection-pool exhaustion — and reading RED/USE dashboards to find the bottleneck |

Background reading: [`python/03-classes-and-concurrency-deep-dive.md`](../python/03-classes-and-concurrency-deep-dive.md)
(threads, async, CPU-heavy work) and [`databases/05-database-at-scale.md`](../databases/05-database-at-scale.md).
