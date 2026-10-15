"""
Redis as a job queue, hands-on.

Basic idea (a Redis LIST is the queue):
  producer: LPUSH jobs '{"job_id": ...}'      -> push on the left
  worker:   BRPOP jobs 5                       -> pop from the right, BLOCK up to 5s if empty
  LPUSH + BRPOP = first in, first out.

Problem with plain BRPOP: the worker pops the job, then crashes -> job is gone forever.
Reliable version (used below):
  worker:   BLMOVE jobs jobs:processing RIGHT LEFT   -> atomically move job to a "processing" list
            ... do the work ...
            LREM jobs:processing 1 <job>              -> "ack": remove only after success
  on failure: retry up to MAX_RETRIES by pushing back on the queue, then move to a dead-letter list
  a reaper can move jobs stuck in "processing" too long back to "jobs" (crashed worker)

Run:  python3 redis_queue.py      (needs Redis on localhost:6379)
"""
import json
import threading
import time
import uuid

import redis

QUEUE = "jobs"
PROCESSING = "jobs:processing"
DEAD = "jobs:dead"
MAX_RETRIES = 3


def enqueue(r: redis.Redis, kind: str, payload: dict) -> str:
    job = {"job_id": uuid.uuid4().hex, "kind": kind, "payload": payload, "attempts": 0}
    r.lpush(QUEUE, json.dumps(job))
    return job["job_id"]


def worker_loop(r: redis.Redis, handlers: dict, stop: threading.Event, name="w1"):
    while not stop.is_set():
        raw = r.blmove(QUEUE, PROCESSING, timeout=1, src="RIGHT", dest="LEFT")
        if raw is None:              # queue empty for 1s, loop again (lets us check stop)
            continue
        job = json.loads(raw)
        try:
            handlers[job["kind"]](job["payload"])
            r.lrem(PROCESSING, 1, raw)                      # ack: done, remove
        except Exception as e:
            r.lrem(PROCESSING, 1, raw)
            job["attempts"] += 1
            job["last_error"] = str(e)
            if job["attempts"] >= MAX_RETRIES:
                r.lpush(DEAD, json.dumps(job))              # give up, keep it for a human
            else:
                r.lpush(QUEUE, json.dumps(job))             # retry later
                time.sleep(0.05 * 2 ** job["attempts"])     # small backoff


def requeue_stuck(r: redis.Redis):
    """Reaper (run on a schedule): put jobs from crashed workers back on the queue.
    Simplified: real code stores a 'started_at' per job and only moves old ones."""
    moved = 0
    while r.rpoplpush(PROCESSING, QUEUE):
        moved += 1
    return moved


# ---------------------------------------------------------------------------
# RabbitMQ equivalent (for comparison; needs `pip install pika` and a RabbitMQ server)
# ---------------------------------------------------------------------------
RABBITMQ_EXAMPLE = '''
import pika, json
conn = pika.BlockingConnection(pika.ConnectionParameters("localhost"))
ch = conn.channel()
ch.queue_declare(queue="jobs", durable=True)              # survives a broker restart

# producer
ch.basic_publish(exchange="", routing_key="jobs", body=json.dumps(job),
                 properties=pika.BasicProperties(delivery_mode=2))   # persistent message

# worker
ch.basic_qos(prefetch_count=1)                            # one unacked job per worker at a time
def on_message(ch, method, props, body):
    try:
        handle(json.loads(body))
        ch.basic_ack(method.delivery_tag)                 # done -> broker deletes it
    except Exception:
        ch.basic_nack(method.delivery_tag, requeue=False) # -> dead-letter exchange if configured
ch.basic_consume(queue="jobs", on_message_callback=on_message)
ch.start_consuming()
'''
# Redis list vs RabbitMQ in one line each:
#   Redis list: you build ack/retry/dead-letter yourself (as above); simple, already in your stack.
#   RabbitMQ:   ack, redelivery on worker crash, dead-letter, routing are built in; one more system to run.


# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------
def test():
    r = redis.Redis()
    r.delete(QUEUE, PROCESSING, DEAD)
    done, attempts = [], {}

    def send_email(p):
        done.append(p["to"])

    def flaky(p):
        attempts[p["n"]] = attempts.get(p["n"], 0) + 1
        raise RuntimeError("provider down")

    handlers = {"email": send_email, "flaky": flaky}
    for i in range(5):
        enqueue(r, "email", {"to": f"user{i}@x.com"})
    enqueue(r, "flaky", {"n": 1})

    stop = threading.Event()
    workers = [threading.Thread(target=worker_loop, args=(r, handlers, stop, f"w{i}")) for i in range(2)]
    for w in workers:
        w.start()
    deadline = time.time() + 5
    while time.time() < deadline and (len(done) < 5 or r.llen(DEAD) < 1):
        time.sleep(0.05)
    stop.set()
    for w in workers:
        w.join()

    assert sorted(done) == [f"user{i}@x.com" for i in range(5)], done
    assert attempts[1] == MAX_RETRIES
    assert r.llen(DEAD) == 1 and r.llen(QUEUE) == 0 and r.llen(PROCESSING) == 0
    print("5 jobs done by 2 workers, flaky job retried 3x then dead-lettered: OK")

    # crash simulation: job moved to processing, worker dies before ack
    r.delete(DEAD)
    enqueue(r, "email", {"to": "crash@x.com"})
    r.blmove(QUEUE, PROCESSING, timeout=1, src="RIGHT", dest="LEFT")   # "worker" takes it and dies
    assert r.llen(QUEUE) == 0 and r.llen(PROCESSING) == 1
    assert requeue_stuck(r) == 1 and r.llen(QUEUE) == 1
    print("crashed worker's job recovered by the reaper: OK")
    r.delete(QUEUE, PROCESSING, DEAD)
    print("All queue tests passed")


if __name__ == "__main__":
    test()
