"""
"Store a user in Redis with a TTL of 5 seconds" -- the SIMPLE version (say and type this one).

get_user:    look in Redis -> found? return it (HIT) -> not found? read DB, save in Redis for 5 s (MISS)
update_user: write DB -> delete the Redis key (next read gets fresh data)

The bigger version (class, caching "not found") is in redis_cache.py.

Run:  python3 redis_cache_simple.py    (needs Redis on localhost:6379)
"""
import json
import time

import redis

r = redis.Redis(decode_responses=True)

DB = {1: {"id": 1, "name": "Asha", "age": 21}}      # stand-in for Postgres
db_reads = 0


def db_get_user(user_id):
    global db_reads
    db_reads += 1
    time.sleep(0.1)                                   # pretend the DB is slow
    return DB.get(user_id)


def get_user(user_id):
    key = f"user:{user_id}"
    cached = r.get(key)                               # 1. look in Redis
    if cached is not None:
        return json.loads(cached)                     # 2. HIT: no DB call
    user = db_get_user(user_id)                       # 3. MISS: go to the DB
    if user is not None:
        r.set(key, json.dumps(user), ex=5)            # 4. save for 5 s, Redis deletes it after
    return user


def update_user_age(user_id, age):
    DB[user_id]["age"] = age                          # 1. write the DB (source of truth)
    r.delete(f"user:{user_id}")                       # 2. drop the old copy from Redis


# FastAPI version (same logic):
#
#   @app.get("/users/{user_id}")
#   def read_user(user_id: int):
#       user = get_user(user_id)
#       if user is None:
#           raise HTTPException(404, "User not found")
#       return user


def test():
    r.delete("user:1")

    t = time.time(); u = get_user(1)
    print(f"1st call: MISS, from DB, {1000 * (time.time() - t):.0f} ms, ttl left = {r.ttl('user:1')} s")
    assert db_reads == 1 and u["age"] == 21

    t = time.time(); u = get_user(1)
    print(f"2nd call: HIT, from Redis, {1000 * (time.time() - t):.1f} ms, db reads still {db_reads}")
    assert db_reads == 1

    update_user_age(1, 22)
    u = get_user(1)
    print(f"after update: MISS, fresh age = {u['age']}")
    assert u["age"] == 22 and db_reads == 2

    print("waiting 5 s for the key to expire...")
    time.sleep(5.2)
    print(f"key exists after 5 s? {bool(r.exists('user:1'))}")
    get_user(1)
    assert db_reads == 3
    print("after expiry: MISS again, refilled from DB")
    r.delete("user:1")
    print("All simple cache tests passed")


if __name__ == "__main__":
    test()
