"""
"5 users each upload a CSV with 10 lakh (1,000,000) rows. Process them without anyone waiting."

The flow this file implements (same shape as production, with stand-ins):
  API   POST /imports          save file to storage (S3/R2 in prod; a folder here), create a job row
                               (status=queued), push job_id to the Redis queue, return 202 + job_id
  WORKER (many, separate process) pop job_id, stream the file with a GENERATOR in chunks of 5,000,
                               validate each row, insert each chunk in ONE batch + ONE commit,
                               save a checkpoint (rows_done) and progress after every chunk
  API   GET /imports/{job_id}  read progress from Redis: {"status", "rows_done", "rows_failed"}

Database here is SQLite so it runs anywhere. Postgres version of the batch insert is in insert_chunk().

Run:  python3 csv_import.py            (200k-row test, needs Redis)
      python3 csv_import.py 1000000    (full 10 lakh rows, prints timing)
"""
import csv
import json
import os
import sqlite3
import sys
import tempfile
import threading
import time
import uuid
from itertools import islice

import redis

CHUNK_SIZE = 5_000
QUEUE = "imports"
STORAGE = tempfile.mkdtemp(prefix="uploads_")       # stand-in for S3 / R2
DB_PATH = os.path.join(STORAGE, "app.db")


# ---------------------------------------------------------------------------
# DB setup
# ---------------------------------------------------------------------------
def db():
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db():
    with db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS leads (
            tenant_id TEXT NOT NULL,
            email     TEXT NOT NULL,
            name      TEXT NOT NULL,
            phone     TEXT,
            UNIQUE (tenant_id, email)          -- re-running a chunk can't create duplicates
        );
        CREATE TABLE IF NOT EXISTS import_jobs (
            job_id     TEXT PRIMARY KEY,
            tenant_id  TEXT NOT NULL,
            file_path  TEXT NOT NULL,
            status     TEXT NOT NULL,          -- queued -> processing -> done / failed
            rows_done  INTEGER NOT NULL DEFAULT 0,   -- checkpoint for resume
            rows_failed INTEGER NOT NULL DEFAULT 0
        );
        """)


# ---------------------------------------------------------------------------
# API side: accept upload, enqueue, return immediately
# ---------------------------------------------------------------------------
def create_import(r: redis.Redis, tenant_id: str, local_csv_path: str) -> str:
    job_id = uuid.uuid4().hex
    stored = os.path.join(STORAGE, f"{job_id}.csv")
    os.replace(local_csv_path, stored)              # prod: client uploads straight to S3 via a signed URL
    with db() as c:
        c.execute("INSERT INTO import_jobs (job_id, tenant_id, file_path, status) VALUES (?,?,?, 'queued')",
                  (job_id, tenant_id, stored))
    r.hset(f"import:{job_id}", mapping={"status": "queued", "rows_done": 0, "rows_failed": 0})
    r.lpush(QUEUE, job_id)                          # the message is tiny: just the id, not the file
    return job_id                                   # API returns 202 {"job_id": ...}


def get_progress(r: redis.Redis, job_id: str) -> dict:
    return {k.decode(): v.decode() for k, v in r.hgetall(f"import:{job_id}").items()}


# ---------------------------------------------------------------------------
# Worker side
# ---------------------------------------------------------------------------
def read_chunks(path: str, chunk_size: int = CHUNK_SIZE, skip: int = 0):
    """GENERATOR: yields lists of chunk_size rows. Only one chunk is in memory at a time,
    so a 1M-row file uses the same memory as a 5k-row file."""
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        rows = islice(reader, skip, None)           # resume: skip rows already committed
        while True:
            chunk = list(islice(rows, chunk_size))
            if not chunk:
                return
            yield chunk


def validate(row: dict):
    """Return a clean tuple, or None if the row is bad. (Pydantic in a real app.)"""
    email = (row.get("email") or "").strip().lower()
    name = (row.get("name") or "").strip()
    if "@" not in email or not name:
        return None
    return email, name, (row.get("phone") or "").strip() or None


def insert_chunk(conn, tenant_id: str, rows: list[tuple]):
    # SQLite: one executemany = one batch.
    conn.executemany(
        "INSERT OR IGNORE INTO leads (tenant_id, email, name, phone) VALUES (?,?,?,?)",
        [(tenant_id, *r) for r in rows],
    )
    # Postgres (psycopg2) equivalent:
    #   from psycopg2.extras import execute_values
    #   execute_values(cur,
    #       "INSERT INTO leads (tenant_id, email, name, phone) VALUES %s "
    #       "ON CONFLICT (tenant_id, email) DO NOTHING", rows_with_tenant, page_size=5000)
    # Fastest for huge loads: COPY into a staging table, then INSERT ... SELECT ... ON CONFLICT.


def process_import(r: redis.Redis, job_id: str, crash_after_chunks: int | None = None):
    conn = db()
    tenant_id, path, rows_done, rows_failed = conn.execute(
        "SELECT tenant_id, file_path, rows_done, rows_failed FROM import_jobs WHERE job_id=?", (job_id,)
    ).fetchone()
    conn.execute("UPDATE import_jobs SET status='processing' WHERE job_id=?", (job_id,))
    conn.commit()
    r.hset(f"import:{job_id}", "status", "processing")

    for n, chunk in enumerate(read_chunks(path, skip=rows_done), start=1):
        good = [v for v in (validate(row) for row in chunk) if v]
        insert_chunk(conn, tenant_id, good)
        rows_done += len(chunk)
        rows_failed += len(chunk) - len(good)
        # data + checkpoint in the SAME transaction: either both saved or neither
        conn.execute("UPDATE import_jobs SET rows_done=?, rows_failed=? WHERE job_id=?",
                     (rows_done, rows_failed, job_id))
        conn.commit()
        r.hset(f"import:{job_id}", mapping={"rows_done": rows_done, "rows_failed": rows_failed})
        if crash_after_chunks and n == crash_after_chunks:
            raise SystemExit("simulated worker crash")

    conn.execute("UPDATE import_jobs SET status='done' WHERE job_id=?", (job_id,))
    conn.commit()
    r.hset(f"import:{job_id}", "status", "done")
    conn.close()


def worker(r: redis.Redis, stop: threading.Event):
    while not stop.is_set():
        item = r.brpop(QUEUE, timeout=1)
        if item:
            process_import(r, item[1].decode())


# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------
def make_csv(n_rows: int, bad_every: int = 1000) -> str:
    fd, path = tempfile.mkstemp(suffix=".csv")
    with os.fdopen(fd, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["name", "email", "phone"])
        for i in range(n_rows):
            email = "not-an-email" if i % bad_every == 0 else f"user{i}@college.edu"
            w.writerow([f"Student {i}", email, f"98{i:08d}"])
    return path


def test(n_rows: int):
    r = redis.Redis()
    r.delete(QUEUE)
    init_db()
    expected_bad = (n_rows + 999) // 1000

    # 1) five users upload at once; uploads return instantly
    files = {f"college{u}": make_csv(n_rows) for u in range(5)}
    t0 = time.time()
    jobs = {tenant: create_import(r, tenant, path) for tenant, path in files.items()}
    print(f"5 uploads accepted in {time.time() - t0:.2f}s (API didn't wait for processing)")

    # 2) a pool of workers drains the queue
    stop = threading.Event()
    threads = [threading.Thread(target=worker, args=(r, stop)) for _ in range(3)]
    t0 = time.time()
    for t in threads:
        t.start()
    while any(get_progress(r, j)["status"] != "done" for j in jobs.values()):
        time.sleep(0.2)
    stop.set()
    for t in threads:
        t.join()
    print(f"5 x {n_rows:,} rows processed in {time.time() - t0:.1f}s by 3 workers")

    for tenant, j in jobs.items():
        p = get_progress(r, j)
        assert int(p["rows_done"]) == n_rows and int(p["rows_failed"]) == expected_bad, p
        count = db().execute("SELECT COUNT(*) FROM leads WHERE tenant_id=?", (tenant,)).fetchone()[0]
        assert count == n_rows - expected_bad
    print(f"each tenant: {n_rows - expected_bad:,} rows inserted, {expected_bad} bad rows reported: OK")

    # 3) crash halfway, then resume from the checkpoint without duplicates
    j = create_import(r, "college_crash", make_csv(20_000))
    r.lrem(QUEUE, 1, j)
    try:
        process_import(r, j, crash_after_chunks=2)
    except SystemExit:
        pass
    assert get_progress(r, j)["rows_done"] == "10000"
    process_import(r, j)                                        # retry the job
    count = db().execute("SELECT COUNT(*) FROM leads WHERE tenant_id='college_crash'").fetchone()[0]
    assert count == 20_000 - 20 and get_progress(r, j)["status"] == "done"
    print("crash after 2 chunks, resumed from row 10,000, no duplicates: OK")
    print("All CSV import tests passed")


if __name__ == "__main__":
    test(int(sys.argv[1]) if len(sys.argv) > 1 else 200_000)
