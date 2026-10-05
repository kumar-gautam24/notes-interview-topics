# Scaling Lab: Module 1 (Monitoring)

## 1. Run it

```bash
docker compose up -d --build
docker compose logs -f db      # first start seeds 1M rows; wait until "ready to accept connections"
curl localhost:8000/items/42   # should return one item
```

| What | URL |
|---|---|
| API docs | http://localhost:8000/docs |
| Raw app metrics | http://localhost:8000/metrics |
| Prometheus | http://localhost:9090 (Status → Targets: all 3 should be UP) |
| Grafana | http://localhost:3000 (no login) |
| cAdvisor | http://localhost:8080 |

Install k6 by following https://grafana.com/docs/k6/latest/set-up/install-k6/

```bash
k6 run -e ENDPOINT=/items/{id} tests/load.js                     # ramp 0 → 200 users
k6 run -e ENDPOINT=/io/good -e VUS=50 -e DURATION=60s tests/load.js  # constant 50 users
```

To change limits, set an env var and recreate the container:
```bash
API_CPUS=0.5 docker compose up -d api
DB_POOL_SIZE=2 docker compose up -d api
API_MEM=512M docker compose up -d api
```
Reset everything, including the database: `docker compose down -v`

## 2. Endpoints

| Endpoint | Demonstrates |
|---|---|
| `/health` | Baseline: almost no work |
| `/cpu/bad` | CPU work inside `async def` blocks the event loop |
| `/cpu/threadpool` | Same CPU work in `def`: loop stays free, but the GIL caps it at ~1 core |
| `/io/bad` | Blocking `time.sleep` inside `async def` freezes the worker |
| `/io/good` | `await asyncio.sleep`: thousands can wait at once |
| `/items/{id}` | Indexed primary-key lookup (fast) |
| `/search?name=item-N` | Unindexed column: full scan of 1M rows |
| `/bulk?limit=N` | Loads N rows into memory and serialises them |
| `/leak?kb=N` | Leaks N KB per call, forever |

## 3. Build your dashboard

In Grafana, go to **Dashboards → New → Add visualization → Prometheus**, then paste each query as a separate panel.

**RED (the API as users see it)**

| Panel | PromQL |
|---|---|
| RPS by route | `sum by (route) (rate(http_request_duration_seconds_count[1m]))` |
| p50 by route | `histogram_quantile(0.50, sum by (le, route) (rate(http_request_duration_seconds_bucket[1m])))` |
| p95 by route | `histogram_quantile(0.95, sum by (le, route) (rate(http_request_duration_seconds_bucket[1m])))` |
| p99 by route | `histogram_quantile(0.99, sum by (le, route) (rate(http_request_duration_seconds_bucket[1m])))` |
| Error rate | `sum(rate(http_request_duration_seconds_count{status=~"5.."}[1m])) / sum(rate(http_request_duration_seconds_count[1m]))` |
| In-flight requests | `http_requests_in_flight` |

**USE (resources)**

| Panel | PromQL |
|---|---|
| API CPU (cores) | `rate(process_cpu_seconds_total{job="api"}[1m])` |
| API memory (RSS) | `process_resident_memory_bytes{job="api"}` |
| API CPU throttled % | `rate(container_cpu_cfs_throttled_periods_total{name=~".*api.*"}[1m]) / rate(container_cpu_cfs_periods_total{name=~".*api.*"}[1m])` |
| API container memory | `container_memory_working_set_bytes{name=~".*api.*"}` |
| DB container memory | `container_memory_working_set_bytes{name=~".*db.*"}` |
| DB CPU (cores) | `rate(container_cpu_usage_seconds_total{name=~".*db.*"}[1m])` |
| Pool in use vs max | `db_pool_in_use` and `db_pool_max` |
| Pool wait p95 | `histogram_quantile(0.95, sum by (le) (rate(db_pool_acquire_seconds_bucket[1m])))` |
| Postgres connections | `sum by (state) (pg_stat_activity_count)` |
| Leaked MB | `leaked_megabytes` |

Set the dashboard refresh to 5s and the time range to "Last 15 minutes".

> **Mac or Windows:** cAdvisor sometimes can't label containers under Docker Desktop, so the `name=~` panels may be empty. The `process_*` panels come from the app itself and always work. For everything else, keep `docker stats` open in a terminal.

## 4. Experiments

Before each experiment, **write down your prediction**. Then record p50, p95, p99, RPS, error rate, CPU, and memory. Keep all of this in a lab notebook.

### E1: Baseline
```bash
k6 run -e ENDPOINT=/health tests/load.js
k6 run -e ENDPOINT=/items/{id} tests/load.js
```
Find the **knee**: the number of users at which p95 stops being flat. Which resource is busiest at that point, API CPU or DB CPU?

### E2: Blocking the event loop with CPU
```bash
k6 run -e ENDPOINT=/cpu/bad -e VUS=10 -e DURATION=60s tests/load.js
# in a second terminal, while that runs:
curl -o /dev/null -s -w "health took %{time_total}s\n" localhost:8000/health
```
Repeat with `/cpu/threadpool`.
**Look for:** with `/cpu/bad`, `/health` takes seconds even though it does no work. With `/cpu/threadpool`, `/health` stays fast. Check API CPU in both cases; it never goes above ~1 core (the GIL).

### E3: Blocking I/O and Little's Law
```bash
k6 run -e ENDPOINT=/io/bad  -e VUS=50 -e DURATION=60s tests/load.js
k6 run -e ENDPOINT=/io/good -e VUS=50 -e DURATION=60s tests/load.js
```
**Predict first:** each request waits 0.2s.
- `/io/bad` handles one request at a time, so max RPS = 1 / 0.2 = **5 RPS**.
- `/io/good` lets all 50 wait together, so RPS = 50 / 0.2 = **250 RPS**.

Did the numbers match? Why did `/io/bad` time out? (The k6 timeout is 10s; 50 users queued × 0.2s = 10s.)

### E4: CPU throttling
```bash
k6 run -e ENDPOINT=/cpu/threadpool -e VUS=10 -e DURATION=60s tests/load.js
API_CPUS=0.5 docker compose up -d api
k6 run -e ENDPOINT=/cpu/threadpool -e VUS=10 -e DURATION=60s tests/load.js
API_CPUS=1.0 docker compose up -d api
```
**Look for:** at 0.5, CPU sits flat at exactly 0.5, the throttled % jumps, RPS roughly halves, and p95 roughly doubles. The container stays up: it gets slower, but nothing crashes.

### E5: Memory spike leading to an OOM kill
```bash
docker events --filter event=oom        # terminal 1: prints a line on every OOM kill
k6 run -e ENDPOINT="/bulk?limit=100000" -e VUS=5 -e DURATION=60s tests/load.js
docker inspect -f 'restarts={{.RestartCount}}' $(docker compose ps -q api)
```
**Look for:** memory climbs, drops to near zero, and errors spike: the sawtooth. Then try `VUS=1`. Does it survive? That shows peak memory ≈ concurrency × memory per request. (If it doesn't OOM at 5, raise VUS.)

### E6: Memory leak
```bash
k6 run -e ENDPOINT=/leak -e VUS=1 -e DURATION=120s tests/load.js
```
**Look for:** a straight upward line under *steady* load. That's what distinguishes a leak from a spike. Predict the call number at which it dies, given the 256M limit and 1MB per call.

### E7: Connection pool exhaustion
```bash
DB_POOL_SIZE=2 docker compose up -d api
k6 run -e ENDPOINT="/search?name=item-{id}" -e VUS=30 -e DURATION=60s tests/load.js
DB_POOL_SIZE=20 docker compose up -d api
k6 run -e ENDPOINT="/search?name=item-{id}" -e VUS=30 -e DURATION=60s tests/load.js
DB_POOL_SIZE=10 docker compose up -d api
```
**Look for:** with pool = 2, API CPU is low, *pool wait* p95 is high, and the pool is pinned at 2/2. The API is waiting, not working. With pool = 20, pool wait drops, but does overall p95 improve? Check DB CPU. You may have just moved the queue into Postgres. That is the core scaling lesson: fixing one bottleneck exposes the next.

## 5. Lab notebook template

```
Experiment:
Config:        (cpus, mem, pool size, VUs)
Prediction:
Result:        RPS=  p50=  p95=  p99=  errors=  API CPU=  API mem=  DB CPU=
Bottleneck:
Why:
```

## 6. Related notes

- Why `/cpu/bad`, `/io/bad` and `/cpu/threadpool` behave the way they do: [`python/03-classes-and-concurrency-deep-dive.md`](../../python/03-classes-and-concurrency-deep-dive.md) (sections 7–12)
- Pools, indexes and the database side: [`databases/05-database-at-scale.md`](../../databases/05-database-at-scale.md)
- Gunicorn/Uvicorn workers and production at scale: [`python/04-backend-foundations-imports-db-production.md`](../../python/04-backend-foundations-imports-db-production.md)
