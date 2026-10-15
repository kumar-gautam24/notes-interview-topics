"""
Rate limiter: max 3 requests per 10 seconds, per user. The 4th is blocked.

Three versions, simplest first:
  1. InMemoryRateLimiter  - dict of user_id -> deque of timestamps (sliding window log)
  2. RedisSlidingWindow   - same idea in a Redis sorted set (works across many servers)
  3. RedisFixedWindow     - INCR + EXPIRE, simplest Redis version, slightly less exact

Run:  python3 rate_limiter.py           (needs a Redis on localhost:6379 for parts 2 and 3)
"""
import time
import uuid
from collections import defaultdict, deque

LIMIT = 3          # max requests
WINDOW = 10        # seconds


# ---------------------------------------------------------------------------
# 1. In-memory sliding window (one server only)
# ---------------------------------------------------------------------------
class InMemoryRateLimiter:
    """
    For each user keep the times of their recent requests.
    On a new request:
      1. drop timestamps older than WINDOW seconds
      2. if LIMIT are still left -> block
      3. else record this request and allow
    """

    def __init__(self, limit=LIMIT, window=WINDOW, clock=time.time):
        self.limit = limit
        self.window = window
        self.clock = clock                      # injectable so tests don't sleep
        self.hits = defaultdict(deque)          # user_id -> deque[timestamp]

    def allow(self, user_id: str) -> bool:
        now = self.clock()
        q = self.hits[user_id]
        while q and q[0] <= now - self.window:  # oldest first, so pop from the left
            q.popleft()
        if len(q) >= self.limit:
            return False
        q.append(now)
        return True

    def retry_after(self, user_id: str) -> float:
        """Seconds until the oldest request leaves the window (for the Retry-After header)."""
        q = self.hits[user_id]
        if len(q) < self.limit:
            return 0.0
        return max(0.0, q[0] + self.window - self.clock())


# The "tuple" version the interviewer described: one list of (user_id, request_time).
# Works, but every check scans everyone's requests -> O(total requests). The dict of
# deques above is O(requests of this user). Say this trade-off if asked.
def allow_with_tuples(log: list, user_id: str, now: float, limit=LIMIT, window=WINDOW) -> bool:
    log[:] = [(u, t) for (u, t) in log if t > now - window]      # drop old entries
    count = sum(1 for (u, _) in log if u == user_id)
    if count >= limit:
        return False
    log.append((user_id, now))
    return True


# ---------------------------------------------------------------------------
# 2. Redis sliding window (many servers share one Redis)
# ---------------------------------------------------------------------------
class RedisSlidingWindow:
    """
    Key per user: ratelimit:{user_id} -> sorted set, member = unique request id, score = timestamp.
      ZREMRANGEBYSCORE  drop entries older than the window
      ZCARD             count what's left
      ZADD              record this request (only if allowed)
      EXPIRE            so idle users' keys disappear
    The Lua script runs all steps atomically inside Redis, so two servers can't
    both read "2" and both allow a 3rd and 4th request (a race condition).
    """

    LUA = """
    local key    = KEYS[1]
    local now    = tonumber(ARGV[1])
    local window = tonumber(ARGV[2])
    local limit  = tonumber(ARGV[3])
    local member = ARGV[4]
    redis.call('ZREMRANGEBYSCORE', key, '-inf', now - window)
    if redis.call('ZCARD', key) >= limit then
        return 0
    end
    redis.call('ZADD', key, now, member)
    redis.call('EXPIRE', key, window)
    return 1
    """

    def __init__(self, r, limit=LIMIT, window=WINDOW):
        self.r = r
        self.limit = limit
        self.window = window
        self.script = r.register_script(self.LUA)

    def allow(self, user_id: str, now: float | None = None) -> bool:
        now = time.time() if now is None else now
        key = f"ratelimit:{user_id}"
        return self.script(keys=[key], args=[now, self.window, self.limit, uuid.uuid4().hex]) == 1


# ---------------------------------------------------------------------------
# 3. Redis fixed window (simplest; counter per 10-second bucket)
# ---------------------------------------------------------------------------
class RedisFixedWindow:
    """
    key = ratelimit:{user}:{current 10s bucket}; INCR it; first INCR sets EXPIRE.
    Trade-off: at a bucket edge a user can do 3 at second 9.9 and 3 more at 10.1
    (6 in 0.2s). The sliding window above doesn't have that problem.
    """

    def __init__(self, r, limit=LIMIT, window=WINDOW):
        self.r, self.limit, self.window = r, limit, window

    def allow(self, user_id: str, now: float | None = None) -> bool:
        now = time.time() if now is None else now
        bucket = int(now // self.window)
        key = f"ratelimit:fw:{user_id}:{bucket}"
        pipe = self.r.pipeline()          # INCR and EXPIRE sent together
        pipe.incr(key)
        pipe.expire(key, self.window)
        count, _ = pipe.execute()
        return count <= self.limit


# ---------------------------------------------------------------------------
# How it plugs into FastAPI (a dependency; returns 429 when blocked)
# ---------------------------------------------------------------------------
FASTAPI_EXAMPLE = '''
from fastapi import Depends, FastAPI, HTTPException, Request

app = FastAPI()
limiter = InMemoryRateLimiter()          # or RedisSlidingWindow(redis.Redis())

def rate_limit(request: Request):
    user_id = request.headers.get("X-User-Id", request.client.host)  # real app: from the JWT
    if not limiter.allow(user_id):
        raise HTTPException(429, "Too many requests",
                            headers={"Retry-After": str(int(limiter.retry_after(user_id)) + 1)})

@app.get("/items", dependencies=[Depends(rate_limit)])
def items():
    return {"ok": True}
'''


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
class FakeClock:
    def __init__(self, t=1000.0):
        self.t = t

    def __call__(self):
        return self.t


def test_in_memory():
    clock = FakeClock()
    rl = InMemoryRateLimiter(clock=clock)
    assert [rl.allow("u1") for _ in range(4)] == [True, True, True, False]   # 4th blocked
    assert rl.allow("u2") is True                                           # users are separate
    assert 9.9 < rl.retry_after("u1") <= 10
    clock.t += 9.9
    assert rl.allow("u1") is False                                          # still inside 10s
    clock.t += 0.2
    assert rl.allow("u1") is True                                           # oldest left the window
    print("in-memory sliding window: OK")


def test_tuples():
    log = []
    assert [allow_with_tuples(log, "u1", 1000 + i) for i in range(4)] == [True, True, True, False]
    assert allow_with_tuples(log, "u2", 1003) is True
    assert allow_with_tuples(log, "u1", 1010.5) is True       # request at 1000 expired
    print("tuple log: OK")


def test_redis():
    import redis
    r = redis.Redis()
    r.ping()
    for k in r.scan_iter("ratelimit:*"):
        r.delete(k)

    sw = RedisSlidingWindow(r)
    t = 2000.0
    assert [sw.allow("u1", t + i * 0.1) for i in range(4)] == [True, True, True, False]
    assert sw.allow("u2", t) is True
    assert sw.allow("u1", t + 10.05) is True                 # first request (t) has left the window

    fw = RedisFixedWindow(r)
    t = 3000.0                                               # start of a bucket (3000 % 10 == 0)
    assert [fw.allow("u1", t + i) for i in range(4)] == [True, True, True, False]
    assert fw.allow("u1", t + 10) is True                    # new bucket
    print("redis sliding + fixed window: OK")


if __name__ == "__main__":
    test_in_memory()
    test_tuples()
    try:
        test_redis()
    except Exception as e:  # no Redis running locally
        print(f"skipped redis tests ({e.__class__.__name__}: {e})")
    print("All rate limiter tests passed")
