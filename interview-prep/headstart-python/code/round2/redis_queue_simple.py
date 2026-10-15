"""
Redis as a queue, the SIMPLE version first (say and type this one in the interview).

Level 1: LPUSH + BRPOP                 (the basic queue, 6 lines)
Level 2: BLMOVE + LREM                 (only if they ask "what if the worker crashes?")

The bigger version with retries, dead-letter and a reaper is in redis_queue.py.

Run:  python3 redis_queue_simple.py    (needs Redis on localhost:6379)
"""
import threading
import time

import redis

r = redis.Redis(decode_responses=True)       # decode_responses: get str back, not bytes


# ---------------------------------------------------------------------------
# Level 1: basic queue
# ---------------------------------------------------------------------------
def enqueue(job_id: str):
    r.lpush("jobs", job_id)                  # add to the LEFT end, returns instantly


def worker_basic(handle, stop: threading.Event):
    while not stop.is_set():
        item = r.brpop("jobs", timeout=1)    # take from the RIGHT end; wait up to 1 s if empty
        if item is None:                     # nothing came in 1 s, loop (and check stop)
            continue
        _queue_name, job_id = item           # BRPOP returns (list name, value)
        handle(job_id)


# ---------------------------------------------------------------------------
# Level 2: don't lose the job if the worker crashes
# ---------------------------------------------------------------------------
def worker_safe(handle, stop: threading.Event):
    while not stop.is_set():
        # take from the right of "jobs" and put it on the left of "jobs:processing", in ONE step
        job_id = r.blmove("jobs", "jobs:processing", timeout=1, src="RIGHT", dest="LEFT")
        if job_id is None:
            continue
        handle(job_id)                       # if we crash here, job_id is still in jobs:processing
        r.lrem("jobs:processing", 1, job_id) # success -> remove it ("ack")


def recover_stuck():
    """Run at startup / on a schedule: put jobs of crashed workers back on the queue."""
    moved = 0
    while r.lmove("jobs:processing", "jobs", src="RIGHT", dest="RIGHT"):
        moved += 1                           # RIGHT end of "jobs" = next to be picked up
    return moved


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
def run_workers(target, handle, n=2, until=lambda: False, seconds=3):
    stop = threading.Event()
    threads = [threading.Thread(target=target, args=(handle, stop)) for _ in range(n)]
    for t in threads:
        t.start()
    deadline = time.time() + seconds
    while time.time() < deadline and not until():
        time.sleep(0.02)
    stop.set()
    for t in threads:
        t.join()


def test():
    r.delete("jobs", "jobs:processing")

    # 1) FIFO order with one worker
    for j in ["job1", "job2", "job3"]:
        enqueue(j)
    assert r.lrange("jobs", 0, -1) == ["job3", "job2", "job1"]   # newest left, oldest right
    seen = []
    run_workers(worker_basic, seen.append, n=1, until=lambda: len(seen) == 3)
    assert seen == ["job1", "job2", "job3"], seen
    print("Level 1: LPUSH + BRPOP is first in, first out: OK")

    # 2) two workers: every job done exactly once
    seen, lock = [], threading.Lock()

    def handle(j):
        with lock:
            seen.append(j)
    for i in range(20):
        enqueue(f"job{i}")
    run_workers(worker_basic, handle, n=2, until=lambda: len(seen) == 20)
    assert sorted(seen) == sorted(f"job{i}" for i in range(20))
    print("Level 1: 2 workers, 20 jobs, each done exactly once: OK")

    # 3) the problem: worker pops, then crashes -> job lost
    enqueue("lost_job")
    r.brpop("jobs", timeout=1)                       # worker took it ... and died
    assert r.llen("jobs") == 0
    print("Level 1 problem: popped then crashed -> job is gone: shown")

    # 4) safe version: crash leaves the job in processing, recovery puts it back
    enqueue("safe_job")
    r.blmove("jobs", "jobs:processing", timeout=1, src="RIGHT", dest="LEFT")   # took it ... and died
    assert r.lrange("jobs:processing", 0, -1) == ["safe_job"]
    assert recover_stuck() == 1
    seen = []
    run_workers(worker_safe, seen.append, n=1, until=lambda: seen == ["safe_job"])
    assert seen == ["safe_job"] and r.llen("jobs:processing") == 0
    print("Level 2: crash keeps job in processing, recovered and finished: OK")

    r.delete("jobs", "jobs:processing")
    print("All simple queue tests passed")


if __name__ == "__main__":
    test()
