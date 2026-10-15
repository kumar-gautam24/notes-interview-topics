"""
The SIMPLE hand-written version of these fastapi-redis-sdk snippets:

    Depends(cache(ttl=60, eviction_group="users"))      on GET    /users/{id}
    Depends(cache_evict(..., key_builder=...))          on DELETE /users/{id}
    Depends(cache_put(eviction_group="users", ttl=300)) on PUT    /users/{id}
    Depends(rate_limit("100/minute"))                   on GET    /api

Same behaviour, written by hand with plain Redis commands so you can explain every line.

Run:  python3 fastapi_cache_ratelimit.py     (needs Redis on localhost:6379, `pip install fastapi httpx redis`)
"""
import json

import redis.asyncio as redis
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.testclient import TestClient
from pydantic import BaseModel

app = FastAPI()
r = redis.Redis(decode_responses=True)


class User(BaseModel):
    id: int | None = None
    name: str | None = None
    age: int | None = None


# stand-in for Postgres
DB: dict[int, dict] = {1: {"id": 1, "name": "Asha", "age": 21}}
db_reads = 0


async def db_get_user(user_id: int):
    global db_reads
    db_reads += 1
    return DB.get(user_id)


def user_key(user_id: int) -> str:
    return f"user:{user_id}"                       # ONE key format used by GET, PUT and DELETE


# ---------------------------------------------------------------------------
# 1. cache(ttl=60): read path (cache-aside)
# ---------------------------------------------------------------------------
@app.get("/users/{user_id}")
async def get_user(user_id: int):
    cached = await r.get(user_key(user_id))
    if cached is not None:
        return json.loads(cached)                  # HIT: DB never touched
    user = await db_get_user(user_id)              # MISS
    if user is None:
        raise HTTPException(404, "User not found")
    await r.set(user_key(user_id), json.dumps(user), ex=60)
    return user


# ---------------------------------------------------------------------------
# 2. cache_evict(): delete from DB, then delete the cached copy
# ---------------------------------------------------------------------------
@app.delete("/users/{user_id}")
async def delete_user(user_id: int):
    DB.pop(user_id, None)                          # 1. DB first
    await r.delete(user_key(user_id))              # 2. only after the DB succeeded
    return {"deleted": user_id}


# ---------------------------------------------------------------------------
# 3. cache_put(ttl=300): write-through, update DB, then write the NEW value into the cache
# ---------------------------------------------------------------------------
@app.put("/users/{user_id}")
async def replace_user(user_id: int, body: User):
    user = {**body.model_dump(), "id": user_id}
    DB[user_id] = user                             # 1. DB first
    await r.set(user_key(user_id), json.dumps(user), ex=300)   # 2. fresh copy, next GET is a hit
    return user


# ---------------------------------------------------------------------------
# 4. rate_limit("100/minute"): fixed window counter as a dependency
# ---------------------------------------------------------------------------
def rate_limit(limit: int, window: int):
    async def check(request: Request):
        key = f"rate:{request.url.path}:{request.client.host}"   # per route, per client IP
        count = await r.incr(key)                  # 1, 2, 3 ... (atomic across servers)
        if count == 1:
            await r.expire(key, window)            # first request opens the window
        if count > limit:
            retry = await r.ttl(key)
            raise HTTPException(429, "Too Many Requests", headers={"Retry-After": str(retry)})
    return check


@app.get("/api", dependencies=[Depends(rate_limit(100, 60))])
async def api():
    return {"ok": True}


@app.get("/small", dependencies=[Depends(rate_limit(3, 10))])   # tiny limit, for the test
async def small():
    return {"ok": True}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
def test():
    import redis as sync_redis
    s = sync_redis.Redis(decode_responses=True)
    s.delete("user:1", "user:2", *s.keys("rate:*"))

    with TestClient(app) as c:
        assert c.get("/users/1").json()["age"] == 21 and db_reads == 1
        assert c.get("/users/1").json()["age"] == 21 and db_reads == 1
        print("GET twice: 1st MISS (DB), 2nd HIT (no DB): OK")

        c.put("/users/1", json={"name": "Asha", "age": 22})
        assert s.ttl("user:1") > 60                                  # written with ttl=300
        assert c.get("/users/1").json()["age"] == 22 and db_reads == 1
        print("PUT writes the new value into the cache, next GET is a HIT with age 22: OK")

        c.delete("/users/1")
        assert s.get("user:1") is None
        assert c.get("/users/1").status_code == 404
        print("DELETE removes DB row and cache key, next GET is 404: OK")

        codes = [c.get("/small").status_code for _ in range(4)]
        assert codes == [200, 200, 200, 429], codes
        res = c.get("/small")
        assert res.status_code == 429 and int(res.headers["Retry-After"]) > 0
        print(f"rate limit 3/10s: {codes}, Retry-After={res.headers['Retry-After']}s: OK")
        assert c.get("/api").status_code == 200

    s.delete("user:1", *s.keys("rate:*"))
    print("All FastAPI cache + rate limit tests passed")


if __name__ == "__main__":
    test()
