"""
Redis cache for a user lookup, TTL = 5 seconds (cache-aside pattern).

get_user(id):
  1. look in Redis: key "user:{id}"
  2. HIT  -> return it (fast, no DB)
  3. MISS -> read from DB (slow), store in Redis with EX=5, return it
update_user(id, ...):
  write DB first, then DELETE the cache key (so the next read refetches fresh data)

Run:  python3 redis_cache.py     (needs Redis on localhost:6379)
"""
import json
import time

import redis

TTL_SECONDS = 5


class FakeUserDB:
    """Stands in for Postgres. Each read is slow and counted, so we can prove the cache works."""

    def __init__(self):
        self.rows = {1: {"id": 1, "name": "Asha", "age": 21}, 2: {"id": 2, "name": "Ravi", "age": 24}}
        self.reads = 0

    def get(self, user_id):
        self.reads += 1
        time.sleep(0.2)                                  # pretend the query is slow
        return self.rows.get(user_id)

    def update_age(self, user_id, age):
        self.rows[user_id]["age"] = age


class UserCache:
    def __init__(self, r: redis.Redis, db: FakeUserDB, ttl=TTL_SECONDS):
        self.r, self.db, self.ttl = r, db, ttl

    @staticmethod
    def key(user_id):
        return f"user:{user_id}"

    def get_user(self, user_id):
        cached = self.r.get(self.key(user_id))
        if cached is not None:
            return json.loads(cached), "HIT"

        user = self.db.get(user_id)
        if user is None:
            # cache "not found" briefly too, so repeated lookups of a missing id don't hammer the DB
            self.r.set(self.key(user_id), json.dumps(None), ex=self.ttl)
            return None, "MISS"
        self.r.set(self.key(user_id), json.dumps(user), ex=self.ttl)   # SET with EX = TTL in seconds
        return user, "MISS"

    def update_age(self, user_id, age):
        self.db.update_age(user_id, age)       # 1. write the source of truth
        self.r.delete(self.key(user_id))       # 2. invalidate; next read refills the cache

    def ttl_left(self, user_id):
        return self.r.ttl(self.key(user_id))   # -2 = key gone, -1 = no expiry, else seconds left


def demo(ttl=TTL_SECONDS):
    r = redis.Redis()
    r.delete("user:1", "user:2", "user:99")
    db = FakeUserDB()
    cache = UserCache(r, db, ttl=ttl)

    user, src = cache.get_user(1)
    assert src == "MISS" and db.reads == 1
    print(f"1st read -> {src}, db reads={db.reads}, ttl left={cache.ttl_left(1)}s")

    user, src = cache.get_user(1)
    assert src == "HIT" and db.reads == 1 and user["age"] == 21
    print(f"2nd read -> {src}, db reads={db.reads} (no DB call)")

    cache.update_age(1, 22)
    user, src = cache.get_user(1)
    assert src == "MISS" and user["age"] == 22
    print(f"after update -> {src}, age={user['age']} (invalidation worked)")

    time.sleep(ttl + 0.5)
    user, src = cache.get_user(1)
    assert src == "MISS"
    print(f"after {ttl}s -> {src}, key expired and was refilled")

    _, src = cache.get_user(99)
    _, src2 = cache.get_user(99)
    assert (src, src2) == ("MISS", "HIT")
    print("missing user cached as None too: OK")
    print("All cache tests passed")


if __name__ == "__main__":
    import sys
    demo(ttl=int(sys.argv[1]) if len(sys.argv) > 1 else TTL_SECONDS)
