"""
Redis from zero: runs every command from 12-redis-basics.md and prints what happens.

Run:  python3 redis_basics.py      (needs Redis on localhost:6379, and `pip install redis`)
"""
import json
import time

import redis

r = redis.Redis(host="localhost", port=6379, decode_responses=True)   # create once, reuse


def show(label, value):
    print(f"  {label:<45} -> {value!r}")


def strings():
    print("String: one value")
    r.delete("name", "user:1", "count:u1")
    show('r.set("name", "Gautam")', r.set("name", "Gautam"))
    show('r.get("name")', r.get("name"))
    show('r.get("missing")', r.get("missing"))
    r.set("user:1", json.dumps({"name": "Asha", "age": 21}), ex=2)
    show('r.set("user:1", json, ex=2); r.ttl', r.ttl("user:1"))
    show("json.loads(r.get(\"user:1\"))", json.loads(r.get("user:1")))
    time.sleep(2.1)
    show("after 2 s: r.get(\"user:1\")", r.get("user:1"))
    show('r.incr("count:u1")', r.incr("count:u1"))
    show('r.incr("count:u1")', r.incr("count:u1"))
    assert r.get("count:u1") == "2"


def lists():
    print("List: queue")
    r.delete("jobs")
    r.lpush("jobs", "job1")
    r.lpush("jobs", "job2")
    show('after LPUSH job1, job2: lrange', r.lrange("jobs", 0, -1))
    show('r.rpop("jobs")', r.rpop("jobs"))
    show('r.brpop("jobs", timeout=1)', r.brpop("jobs", timeout=1))
    t = time.time()
    show('r.brpop on empty list, timeout=1', r.brpop("jobs", timeout=1))
    print(f"  (it waited {time.time() - t:.1f} s inside Redis, no loop needed)")


def hashes():
    print("Hash: small dict")
    r.delete("import:abc")
    r.hset("import:abc", mapping={"status": "processing", "rows_done": 5000})
    show('r.hget("import:abc", "status")', r.hget("import:abc", "status"))
    show('r.hincrby("import:abc", "rows_done", 5000)', r.hincrby("import:abc", "rows_done", 5000))
    show('r.hgetall("import:abc")', r.hgetall("import:abc"))


def sorted_sets():
    print("Sorted set: members sorted by score")
    r.delete("hits:u1")
    r.zadd("hits:u1", {"req-1": 1001, "req-2": 1004, "req-3": 1009})
    show('r.zcard("hits:u1")', r.zcard("hits:u1"))
    show('r.zremrangebyscore("hits:u1", 0, 1002)', r.zremrangebyscore("hits:u1", 0, 1002))
    show('r.zrange("hits:u1", 0, -1, withscores=True)', r.zrange("hits:u1", 0, -1, withscores=True))


def fixed_window_rate_limit():
    print("Use: fixed-window rate limit, 3 per 10 s")
    r.delete("rate:u1")

    def allow(user_id):
        key = f"rate:{user_id}"
        count = r.incr(key)
        if count == 1:
            r.expire(key, 10)
        return count <= 3

    results = [allow("u1") for _ in range(4)]
    show("4 requests from u1", results)
    assert results == [True, True, True, False]


if __name__ == "__main__":
    show("r.ping()", r.ping())
    strings()
    lists()
    hashes()
    sorted_sets()
    fixed_window_rate_limit()
    r.delete("name", "count:u1", "jobs", "import:abc", "hits:u1", "rate:u1")
    print("All Redis basics ran OK")
