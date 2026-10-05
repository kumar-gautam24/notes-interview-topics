"""
Scaling Lab - Module 1 API.

Every endpoint exists to demonstrate ONE resource behaviour.
Some are deliberately written badly. Don't copy the /bad ones into real code.
"""
import asyncio
import hashlib
import os
import time
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Gauge, Histogram, generate_latest

DB_DSN = os.getenv("DB_DSN", "postgresql://lab:lab@db:5432/lab")
DB_POOL_SIZE = int(os.getenv("DB_POOL_SIZE", "10"))

# ---------------------------------------------------------------------------
# Metrics
# A Histogram counts requests into latency buckets. Prometheus computes
# p50/p95/p99 from these counts (you can't average percentiles, so we store
# the distribution instead).
# ---------------------------------------------------------------------------
LATENCY_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Time from request received to response sent",
    ["method", "route", "status"],
    buckets=LATENCY_BUCKETS,
)
IN_FLIGHT = Gauge("http_requests_in_flight", "Requests currently being handled")
POOL_ACQUIRE = Histogram(
    "db_pool_acquire_seconds",
    "Time spent WAITING for a free DB connection (queue time, not query time)",
    buckets=LATENCY_BUCKETS,
)
POOL_MAX = Gauge("db_pool_max", "Max connections in the pool")
POOL_IN_USE = Gauge("db_pool_in_use", "Connections currently checked out")
LEAKED_MB = Gauge("leaked_megabytes", "Memory deliberately leaked by /leak")

pool: asyncpg.Pool | None = None
_leak: list[bytes] = []
_leaked_bytes = 0


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    pool = await asyncpg.create_pool(DB_DSN, min_size=1, max_size=DB_POOL_SIZE)
    POOL_MAX.set(DB_POOL_SIZE)
    yield
    await pool.close()


app = FastAPI(title="Scaling Lab", lifespan=lifespan)


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)
    IN_FLIGHT.inc()
    start = time.perf_counter()
    status = "500"
    try:
        response = await call_next(request)
        status = str(response.status_code)
        return response
    finally:
        # Label by route TEMPLATE (/items/{item_id}), not the raw path.
        # Raw paths would create a new time series for every id -> memory blowup in Prometheus.
        route = request.scope.get("route")
        path = getattr(route, "path", "unmatched")
        REQUEST_LATENCY.labels(request.method, path, status).observe(time.perf_counter() - start)
        IN_FLIGHT.dec()


async def db_fetch(query: str, *args):
    """Run a query, recording how long we waited for a pool connection."""
    assert pool is not None
    t0 = time.perf_counter()
    async with pool.acquire() as conn:
        POOL_ACQUIRE.observe(time.perf_counter() - t0)
        return await conn.fetch(query, *args)


@app.get("/metrics", include_in_schema=False)
async def metrics():
    if pool is not None:
        POOL_IN_USE.set(pool.get_size() - pool.get_idle_size())
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ---------------------------------------------------------------------------
# Baseline
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    return {"ok": True}


# ---------------------------------------------------------------------------
# CPU
# ---------------------------------------------------------------------------
def burn_cpu(n: int) -> str:
    h = b"x"
    for _ in range(n):
        h = hashlib.sha256(h).digest()
    return h.hex()


@app.get("/cpu/bad")
async def cpu_bad(n: int = 200_000):
    """BAD: CPU work inside `async def` blocks the event loop.
    While this runs, EVERY other request on this worker waits, including /health."""
    return {"hash": burn_cpu(n)}


@app.get("/cpu/threadpool")
def cpu_threadpool(n: int = 200_000):
    """Plain `def`: FastAPI runs it in a threadpool, so the event loop stays responsive.
    But the GIL still caps this worker at ~1 CPU core total."""
    return {"hash": burn_cpu(n)}


# ---------------------------------------------------------------------------
# I/O
# ---------------------------------------------------------------------------
@app.get("/io/bad")
async def io_bad(ms: int = 200):
    """BAD: blocking sleep inside `async def`. Stands in for requests.get(), a sync DB
    driver, reading a big file, etc. Freezes the whole worker for `ms` per request."""
    time.sleep(ms / 1000)
    return {"slept_ms": ms}


@app.get("/io/good")
async def io_good(ms: int = 200):
    """GOOD: `await` hands control back to the event loop while waiting,
    so thousands of these can be in flight on one worker."""
    await asyncio.sleep(ms / 1000)
    return {"slept_ms": ms}


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
@app.get("/items/{item_id}")
async def get_item(item_id: int):
    """Primary-key lookup: uses an index, should be fast."""
    rows = await db_fetch(
        "SELECT id, name, category, price FROM items WHERE id = $1", item_id
    )
    if not rows:
        raise HTTPException(status_code=404, detail="not found")
    return dict(rows[0])


@app.get("/search")
async def search(name: str):
    """No index on `name` -> Postgres scans all 1M rows for every request.
    DB CPU climbs; each query holds a pool connection for a long time."""
    rows = await db_fetch("SELECT id, name, price FROM items WHERE name = $1", name)
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Memory
# ---------------------------------------------------------------------------
@app.get("/bulk")
async def bulk(limit: int = 10_000):
    """Loads `limit` rows fully into memory, then serialises them all to JSON.
    Memory per request grows with limit; peak memory ~ concurrency x per-request memory."""
    rows = await db_fetch(
        "SELECT id, name, category, price FROM items LIMIT $1", limit
    )
    return [dict(r) for r in rows]


@app.get("/leak")
async def leak(kb: int = 1024):
    """BAD: appends to a global list that is never cleared. Memory climbs until OOM kill."""
    global _leaked_bytes
    _leak.append(os.urandom(kb * 1024))  # urandom so pages are actually touched
    _leaked_bytes += kb * 1024
    LEAKED_MB.set(_leaked_bytes / 1024 / 1024)
    return {"leaked_mb": round(_leaked_bytes / 1024 / 1024, 1)}
