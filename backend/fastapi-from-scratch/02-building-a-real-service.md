# FastAPI Part 2: Building a Real Service

## 1. Settings and environment variables

Put every environment-specific value (secrets, URLs, cookie flags) in one typed settings class that reads env vars and `.env`. It replaces scattered `os.getenv` calls and converts types for you.

```bash
pip install pydantic-settings
```

### The settings class

```python
# app/core/config.py
from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Vaidya API"
    database_url: str                                  # required: no default
    jwt_private_key: str
    allowed_origins: list[str] = ["http://localhost:3000"]
    session_cookie_secure: bool = True
    session_cookie_max_age_days: int = 30
    refresh_cookie_path: str = "/api/v1/vaidya-ep/auth"

@lru_cache
def get_settings() -> Settings:
    return Settings()
```

```ini
# .env  (never commit this file)
DATABASE_URL=postgresql+psycopg://user:pass@localhost/vaidya
JWT_PRIVATE_KEY=...
ALLOWED_ORIGINS=["https://vaidya-ep-dev.fractal.ai","http://localhost:3000"]
SESSION_COOKIE_SECURE=true
```

### How it works

1. `Settings()` runs Pydantic's generated `__init__`, which reads each field from environment variables (case-insensitive), then from `.env`, then falls back to the default.
2. Types convert automatically: `"true"` becomes `True`, `"30"` becomes `30`, a JSON list string becomes a Python list.
3. A missing required field (like `database_url`) fails at startup with a clear error, not in the middle of a request.
4. `@lru_cache` makes `get_settings()` build the object once and return the same one afterward.

That's how `SESSION_COOKIE_SECURE=true` in the project's env becomes a Python boolean.

### Using settings

```python
from typing import Annotated
from fastapi import Depends

SettingsDep = Annotated[Settings, Depends(get_settings)]

@app.get("/info")
def info(settings: SettingsDep):
    return {"app": settings.app_name}
```

Outside routes (in `main.py` for CORS, say), call `get_settings()` directly. Using it as a dependency lets tests override settings.

### Rules

1. Commit a `.env.example` with placeholder values; add `.env` to `.gitignore`.
2. In production, set real environment variables (or a secrets manager). Don't ship `.env` files.
3. Never log the settings object; it holds secrets. Pydantic's `SecretStr` type hides a value when printed.

## 2. Databases with SQLAlchemy

SQLAlchemy maps Python classes to database tables. You create one engine for the app, one session per request through a `yield` dependency, and keep queries in the service layer.

```bash
pip install sqlalchemy psycopg[binary] alembic
```

### Engine and session

```python
# app/db/session.py
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

engine = create_engine(get_settings().database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False)

class Base(DeclarativeBase):
    pass
```

- The engine manages a pool of connections. Create it once, at import.
- `SessionLocal` is a factory (a class you call): `SessionLocal()` gives a new session.
- `pool_pre_ping=True` checks connections before use, avoiding "server closed the connection" errors.

### Models: classes become tables

```python
# app/runs/models.py
from datetime import datetime
from sqlalchemy import String, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    runs: Mapped[list["Run"]] = relationship(back_populates="owner")

class Run(Base):
    __tablename__ = "runs"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    owner: Mapped[User] = relationship(back_populates="runs")
```

Class attribute = column; inheritance from `Base` registers the table. `Mapped[int]` is a type hint SQLAlchemy reads, like Pydantic does.

### The DB dependency

```python
# app/core/deps.py
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

DB = Annotated[Session, Depends(get_db)]
```

### CRUD in a service

```python
# app/runs/service.py
from sqlalchemy import select

def create_run(db: Session, owner_id: int, data: RunCreate) -> Run:
    run = Run(owner_id=owner_id, **data.model_dump())   # ** unpacks the dict into columns
    db.add(run)
    db.commit()          # write to the database
    db.refresh(run)      # reload generated values like id and created_at
    return run

def list_runs(db: Session, owner_id: int, skip: int, limit: int) -> list[Run]:
    stmt = select(Run).where(Run.owner_id == owner_id).offset(skip).limit(limit)
    return list(db.scalars(stmt))

def get_run(db: Session, run_id: int) -> Run | None:
    return db.get(Run, run_id)

def delete_run(db: Session, run: Run) -> None:
    db.delete(run)
    db.commit()
```

### The route

```python
@router.post("/runs", response_model=RunOut, status_code=201)
def create(body: RunCreate, db: DB, user: CurrentUser):
    return service.create_run(db, user.id, body)
```

`RunOut` needs `model_config = {"from_attributes": True}` to read the SQLAlchemy object.

### Transactions

Changes stay pending until `db.commit()`. If something fails midway, `db.rollback()` undoes them. For multi-step writes:

```python
with db.begin():        # commits at the end, rolls back on any exception
    db.add(a)
    db.add(b)
```

### Migrations with Alembic

Never change tables by hand in production. Alembic tracks schema changes as versioned scripts:

```bash
alembic init migrations
alembic revision --autogenerate -m "add runs table"   # compares models to the DB
alembic upgrade head                                  # apply
```

### Async option

For `async def` routes, use `create_async_engine`, `AsyncSession` and an async driver such as `asyncpg`, then `await db.execute(...)`. Don't use the sync session inside `async def` routes; it blocks the event loop.

## 3. Middleware, CORS and logging

Middleware wraps every request and response. Use it for cross-cutting work such as CORS, request IDs, timing and logging, and keep per-route logic in dependencies.

### How middleware wraps a request

```python
import time, uuid, logging
from fastapi import Request

logger = logging.getLogger("api")

@app.middleware("http")
async def log_requests(request: Request, call_next):
    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    start = time.perf_counter()
    response = await call_next(request)          # everything else happens here
    ms = (time.perf_counter() - start) * 1000
    response.headers["X-Request-Id"] = request_id
    logger.info("%s %s %s %.1fms id=%s", request.method, request.url.path,
                response.status_code, ms, request_id)
    return response
```

Code before `await call_next(request)` runs on the way in; code after runs on the way out. It's the same before-and-after shape as a `yield` dependency.

### Order

Middleware added later wraps the earlier ones, so it runs first on the way in and last on the way out. Add CORS last so it wraps everything, including error responses.

```python
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(CORSMiddleware, allow_origins=settings.allowed_origins,
                   allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
```

CORS rules (exact origins with cookies, never `*`, one place only when behind a gateway) are covered in the HttpOnly cookie guide.

### Built-in middleware worth knowing

| Middleware | Import from | Use |
| --- | --- | --- |
| `CORSMiddleware` | `fastapi.middleware.cors` | Cross-origin browser access |
| `GZipMiddleware` | `fastapi.middleware.gzip` | Compress large responses |
| `TrustedHostMiddleware` | `fastapi.middleware.trustedhost` | Reject unexpected `Host` headers |
| `HTTPSRedirectMiddleware` | `fastapi.middleware.httpsredirect` | Force HTTPS (usually done by the gateway instead) |

### Logging setup

```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("api")

logger.info("run created id=%s", run.id)       # use % args, not f-strings, in log calls
logger.exception("refresh failed")             # inside except: logs the traceback
```

Never log tokens, cookies, passwords or `Authorization` headers. Production systems usually log JSON lines so tools can search them.

### Middleware vs dependency

|  | Middleware | Dependency |
| --- | --- | --- |
| Runs for | Every request | Only routes that declare it |
| Sees | Raw request and response | Parsed parameters |
| Can return data to the route | No | Yes |
| Good for | CORS, logging, timing, request IDs | Auth, DB session, pagination |

## 4. Lifespan events and background tasks

Lifespan code runs once when the app starts and once when it stops, which suits shared clients and model loading. Background tasks run small jobs after the response is sent.

### Lifespan: startup and shutdown

```python
from contextlib import asynccontextmanager
import httpx

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http = httpx.AsyncClient(timeout=10)   # startup: create shared client
    yield                                            # the app serves requests here
    await app.state.http.aclose()                    # shutdown: clean up

app = FastAPI(lifespan=lifespan)
```

It's the `yield` pattern from the Python guide, applied to the whole app instead of one request. Older code uses `@app.on_event("startup")`, which is deprecated.

Use lifespan for:

1. Shared HTTP clients (reusing connections is much faster than one client per request).
2. Loading an ML model or embeddings index into memory once.
3. Connecting to Redis or a message queue.
4. Running a startup check, such as confirming the DB is reachable.

Access it in routes via `request.app.state.http`.

### Background tasks

```python
from fastapi import BackgroundTasks

def send_welcome_email(email: str):
    ...   # slow work

@app.post("/users", status_code=201)
def create_user(body: UserIn, tasks: BackgroundTasks):
    user = save(body)
    tasks.add_task(send_welcome_email, user.email)   # function and its arguments
    return user                                       # response goes out immediately
```

The client gets its response first; the task runs afterward in the same process.

### When background tasks aren't enough

| Need | Use |
| --- | --- |
| Short fire-and-forget work (email, audit log) | `BackgroundTasks` |
| Long jobs (minutes), retries, surviving restarts | A task queue: Celery, RQ, Arq, or a cloud queue |
| Scheduled jobs | A scheduler (APScheduler, cron) or the queue's scheduler |
| Long AI or eval runs | Queue plus a status endpoint the client polls, or a WebSocket or SSE progress stream |

Background tasks die with the process and aren't retried. If the server restarts, queued tasks are lost.

## 5. Testing

`TestClient` sends real HTTP requests to your app in memory, with no server running. `dependency_overrides` swaps auth, DB or settings for test versions.

```bash
pip install pytest httpx
```

### First test

```python
# tests/test_health.py
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
```

```bash
pytest -q          # finds files named test_*.py and functions named test_*
```

`assert` fails the test when its condition is false.

### Testing the cookie flow

`TestClient` keeps cookies between calls, like a browser:

```python
def test_login_sets_httponly_cookie():
    r = client.post("/auth/login", json={"username": "gautam", "password": "pass"})
    assert r.status_code == 200
    set_cookie = r.headers["set-cookie"]
    assert "access_token=" in set_cookie
    assert "HttpOnly" in set_cookie
    assert "access_token" not in r.json()          # token must not be in the body

    me = client.get("/me")                          # cookie sent automatically
    assert me.json() == {"user": "gautam"}

def test_me_without_cookie():
    fresh = TestClient(app)                         # new client, empty cookie jar
    assert fresh.get("/me").status_code == 401
```

Test cookies with `Secure=True` over `https://` by creating `TestClient(app, base_url="https://testserver")`; otherwise the client won't send them.

### Overriding dependencies

```python
from app.core.deps import get_current_user

def test_admin_route():
    app.dependency_overrides[get_current_user] = lambda: "admin-user"
    try:
        r = client.delete("/runs/1")
        assert r.status_code == 204
    finally:
        app.dependency_overrides.clear()            # don't leak into other tests
```

The key is the original function; the value is its replacement. Your route code doesn't change at all.

### A test database with fixtures

```python
# tests/conftest.py  (pytest loads this automatically)
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

engine = create_engine("sqlite:///./test.db")
TestingSession = sessionmaker(bind=engine)

@pytest.fixture
def client():
    Base.metadata.create_all(engine)
    def override_db():
        db = TestingSession()
        try:
            yield db
        finally:
            db.close()
    app.dependency_overrides[get_db] = override_db
    yield TestClient(app)
    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine)

# in a test file:
def test_create_run(client):          # pytest passes the fixture by name
    r = client.post("/runs", json={"name": "eval-1"})
    assert r.status_code == 201
```

A fixture is setup code with `yield`: everything before `yield` prepares, everything after cleans up. The same pattern again.

### What to test first

1. Auth: login sets cookies, `/me` works with the cookie and fails without it, refresh rotates, logout clears.
2. Validation: missing or bad fields return 422.
3. Permissions: a normal user gets 403 on admin routes.
4. Each service function's business rules, directly, without HTTP.

## 6. Deployment

In production, run Uvicorn without `--reload`, with several worker processes, inside a Docker image, behind a gateway or load balancer that handles HTTPS.

### Running for production

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4 --proxy-headers
# or, with the FastAPI CLI:
fastapi run app/main.py --workers 4
```

| Flag | Why |
| --- | --- |
| `--host 0.0.0.0` | Listen on all interfaces, required inside a container |
| `--workers 4` | Several processes to use several CPU cores; a common start is one per core |
| `--proxy-headers` | Trust `X-Forwarded-For` / `X-Forwarded-Proto` from the gateway, so client IP and `https` are correct |
| No `--reload` | Reload is for development only |

In Kubernetes, teams often run one worker per container and scale the number of containers instead.

### Dockerfile

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
```

Copying `requirements.txt` before the code lets Docker cache the dependency layer, so code-only changes rebuild fast.

```bash
docker build -t vaidya-api .
docker run -p 8000:8000 --env-file .env vaidya-api
```

### Behind a gateway with a path prefix

When the gateway serves the app under a prefix (like `/vaidya-ep-api-svc`) and strips it before forwarding, tell FastAPI so its docs and generated URLs include it:

```python
app = FastAPI(root_path="/vaidya-ep-api-svc")
# or: uvicorn app.main:app --root-path /vaidya-ep-api-svc
```

`root_path` does not change cookie paths. Cookie `path` must still be written as the browser sees the URL, prefix included (see the cookie guide's gateway gotcha).

### Health checks

```python
@app.get("/health")          # liveness: the process is up
def health():
    return {"status": "ok"}

@app.get("/ready")           # readiness: dependencies reachable
def ready(db: DB):
    db.execute(text("SELECT 1"))
    return {"status": "ready"}
```

The gateway or orchestrator calls these to decide whether to send traffic.

### Docs in production

If the API is internal, keep `/docs`. If it's public and shouldn't advertise itself, disable it: `FastAPI(docs_url=None, redoc_url=None, openapi_url=None)`, or enable it only in dev through a setting.

## 7. Production checklist

Work through these before shipping a FastAPI service. Each item points to where it's explained.

### Config and secrets

- [ ] All settings in one `Settings` class; required values fail at startup (section 1)
- [ ] No secrets in code or git; `.env` ignored, `.env.example` committed
- [ ] Long random JWT secret or an RS256 key pair from a secrets manager

### Auth and cookies

- [ ] Tokens in HttpOnly, Secure, SameSite cookies; not in the response body
- [ ] Access token about 15 minutes; refresh token rotated and stored hashed
- [ ] Refresh cookie path matches the URL the browser sees, gateway prefix included
- [ ] Logout deletes cookies with the same path and domain, and revokes the refresh token

### CORS and network

- [ ] Exact origins from settings, `allow_credentials=True`, no `*` (section 3)
- [ ] CORS configured in exactly one place: gateway or app
- [ ] `--proxy-headers` on, so client IP and scheme are correct behind the gateway
- [ ] WebSocket endpoints check `Origin`

### Code quality

- [ ] Separate input and output models; `response_model` or return types on every route
- [ ] Thin routes; logic in services; DB session per request via `yield` dependency (section 2)
- [ ] No blocking calls inside `async def` routes
- [ ] One consistent error shape via exception handlers; no raw exception text to clients

### Data

- [ ] Schema changes only through Alembic migrations
- [ ] Connection pool with `pool_pre_ping=True`
- [ ] Multi-step writes wrapped in a transaction

### Operations

- [ ] No `--reload`; workers or container replicas sized to CPU (section 6)
- [ ] `/health` and `/ready` endpoints wired to the gateway
- [ ] Request logging with request IDs; no tokens or passwords in logs
- [ ] Long jobs on a real task queue, not `BackgroundTasks` (section 4)

### Tests

- [ ] Auth flow tests: login, `/me`, refresh rotation, logout, 401 without cookie (section 5)
- [ ] Validation tests returning 422, permission tests returning 403
- [ ] Tests run in CI on every pull request
