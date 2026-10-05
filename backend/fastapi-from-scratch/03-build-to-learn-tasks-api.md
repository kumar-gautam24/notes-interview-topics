# Build to Learn: A Production-Style FastAPI Tasks API

## 1. What you'll build

You'll build a tasks API, where users create projects and tasks, in ten milestones. Each milestone adds one layer of real backend skill, and the finished repo covers what 1 to 3 year Python backend interviews test.

The domain is deliberately boring. When you don't have to think about the business logic, all your attention goes to the backend concepts.

### The API when finished

| Endpoint | What it does | Concepts it teaches |
| --- | --- | --- |
| `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout` | Accounts and sessions | Password hashing, JWT, HttpOnly cookies, rotation |
| `GET /users/me` | Current user | Dependencies, auth |
| `POST /projects`, `GET /projects` | A user's projects | Relations, ownership |
| `POST /projects/{id}/tasks` | Create a task | Nested resources, validation |
| `GET /projects/{id}/tasks?status=&priority=&sort=&cursor=` | List tasks | Filtering, sorting, pagination, indexes |
| `PATCH /tasks/{id}` | Update a task | Partial updates, 403 vs 404 |
| `DELETE /tasks/{id}` | Delete | 204, idempotency |
| `GET /projects/{id}/stats` | Counts per status | Aggregation, caching |
| `GET /health`, `/ready` | Liveness, readiness | Operations |

Plus: a webhook when a task is completed (async, timeouts, retries), rate limiting on login, structured logs, tests, Docker and CI.

### The stack

| Layer | Choice | Why this one |
| --- | --- | --- |
| Language | Python 3.12 | Current, stable |
| Framework | FastAPI | The target of the jobs |
| Validation | Pydantic v2 | Built into FastAPI |
| Database | PostgreSQL 16 | The default in industry |
| ORM and migrations | SQLAlchemy 2.0, Alembic | The most common Python pair |
| Cache, rate limits | Redis | The most common companion |
| Packages | uv | Fast, with a lockfile |
| Quality | ruff, mypy, pytest | Standard tooling |
| Deployment | Docker, GitHub Actions | Universal |

### The milestones

| # | Milestone | You'll be able to explain |
| --- | --- | --- |
| 0 | Setup | Project layout, settings, why a lockfile |
| 1 | In-memory CRUD | Routes, Pydantic, status codes |
| 2 | PostgreSQL | Engine, session, transactions, migrations, layers |
| 3 | Auth | Hashing, JWT, cookies, 401 vs 403 |
| 4 | Real API features | Pagination, filtering, PATCH, error format |
| 5 | Testing | Fixtures, test DB, dependency overrides |
| 6 | Async and webhooks | Event loop, timeouts, retries, background work |
| 7 | Observability | Logging, request IDs, error handling |
| 8 | Protection and speed | Rate limiting, caching, indexes |
| 9 | Ship it | Docker, CI, deploy, workers |

### How to work through it

1. One milestone at a time. Don't read ahead, and don't start the next one until the checkpoint passes.
2. Type the code; don't paste it. Typing builds the syntax memory.
3. Commit at the end of every milestone: `git commit -m "M3: cookie auth"`. Your history becomes proof of progress.
4. At every checkpoint, explain the milestone out loud in five sentences. If you can't, redo it.
5. Break something on purpose at each milestone and read the error. Debugging is half the job.
6. Budget: one or two evenings per milestone, so 3 to 5 weeks in total.

The concept guides already written (cookies, Python OOP, FastAPI Parts 1 and 2, Deep Dive, Foundations) explain the why. This guide is the how, in build order.

## 2. Milestone 0: setup

Goal: an empty but professional project with a lockfile, a clean layout, typed settings, a linter, and a `/health` endpoint you can open in the browser.

### Step 1: create the project

```bash
uv init tasks-api && cd tasks-api
uv python pin 3.12
uv add "fastapi[standard]" pydantic-settings
uv add --dev ruff mypy pytest
git init
```

`.gitignore`:

```
.venv/
__pycache__/
.env
.pytest_cache/
.mypy_cache/
```

### Step 2: the layout

Create these folders and empty `__init__.py` files now, even if most stay empty until later milestones:

```
tasks-api/
  app/
    __init__.py
    main.py              # create app, include routers
    core/
      __init__.py
      config.py          # settings
    tasks/
      __init__.py
  tests/
    __init__.py
  pyproject.toml
  uv.lock
  .env.example
```

One folder per feature (`tasks/`, later `users/`, `auth/`), and `core/` for shared infrastructure. This is the layout from FastAPI Part 1, section 7.

### Step 3: settings

```python
# app/core/config.py
from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Tasks API"
    environment: str = "local"          # local | test | production
    debug: bool = False

@lru_cache
def get_settings() -> Settings:
    return Settings()
```

`.env.example` (committed) and `.env` (not committed):

```ini
ENVIRONMENT=local
DEBUG=true
```

### Step 4: the app and health check

```python
# app/main.py
from fastapi import FastAPI
from app.core.config import get_settings

settings = get_settings()
app = FastAPI(title=settings.app_name)

@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.environment}
```

Run it:

```bash
uv run fastapi dev app/main.py
```

Open `http://localhost:8000/health` and `http://localhost:8000/docs`.

### Step 5: linting and type checking

Add to `pyproject.toml`:

```toml
[tool.ruff]
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP"]   # errors, pyflakes, import order, bugbear, modern syntax

[tool.mypy]
strict = true
plugins = ["pydantic.mypy"]
```

```bash
uv run ruff check . --fix      # lint and auto-fix
uv run ruff format .           # format
uv run mypy app                # type check
```

Run these three before every commit. Habit starts now.

### Checkpoint

- [ ] `/health` returns `{"status": "ok", ...}`
- [ ] `/docs` shows the endpoint
- [ ] `ruff check`, `ruff format --check`, `mypy app` all pass
- [ ] Commit: `M0: project setup`

Explain out loud: what `uv.lock` is for, why settings come from env vars, and what runs at import time in `main.py` (hint: `settings` and `app` are created once per process).

Break it: delete `.env` and set `environment: str` with no default. The app fails at startup with a clear validation error. That's the point of typed settings.

## 3. Milestone 1: in-memory CRUD

Goal: full create, read, update, delete for tasks, stored in a Python dict, with separate input and output models and correct status codes. No database yet, so all your attention goes to FastAPI itself.

### Step 1: schemas

```python
# app/tasks/schemas.py
from datetime import datetime
from enum import Enum
from pydantic import BaseModel, Field

class Status(str, Enum):
    todo = "todo"
    doing = "doing"
    done = "done"

class Priority(int, Enum):
    low = 1
    medium = 2
    high = 3

class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    priority: Priority = Priority.medium

class TaskUpdate(BaseModel):                  # every field optional, for PATCH
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    status: Status | None = None
    priority: Priority | None = None

class TaskOut(BaseModel):
    id: int
    title: str
    description: str | None
    status: Status
    priority: Priority
    created_at: datetime
```

Three models, three jobs: what the client may send on create, what it may send on update, and what it gets back. `Status` as an `Enum` restricts values and shows a dropdown in `/docs`.

### Step 2: a store class

Write it as a class with a lock, applying the Deep Dive guide's lessons:

```python
# app/tasks/store.py
import threading
from datetime import datetime, timezone
from app.tasks.schemas import Status, TaskCreate, TaskOut, TaskUpdate

class InMemoryTaskStore:
    def __init__(self) -> None:
        self._tasks: dict[int, TaskOut] = {}
        self._next_id = 1
        self._lock = threading.Lock()          # def routes run in threads

    def create(self, data: TaskCreate) -> TaskOut:
        with self._lock:
            task = TaskOut(
                id=self._next_id,
                status=Status.todo,
                created_at=datetime.now(timezone.utc),
                **data.model_dump(),
            )
            self._tasks[task.id] = task
            self._next_id += 1
            return task

    def list(self) -> list[TaskOut]:
        return list(self._tasks.values())

    def get(self, task_id: int) -> TaskOut | None:
        return self._tasks.get(task_id)

    def update(self, task_id: int, data: TaskUpdate) -> TaskOut | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return None
            changes = data.model_dump(exclude_unset=True)   # only fields the client sent
            updated = task.model_copy(update=changes)
            self._tasks[task_id] = updated
            return updated

    def delete(self, task_id: int) -> bool:
        with self._lock:
            return self._tasks.pop(task_id, None) is not None

store = InMemoryTaskStore()                    # one per process (see Deep Dive, section 11)
```

`exclude_unset=True` is the key to PATCH: `{"status": "done"}` changes only status. Without it, the missing fields would come through as `None` and wipe the title.

### Step 3: the router

```python
# app/tasks/router.py
from fastapi import APIRouter, HTTPException, status
from app.tasks.schemas import TaskCreate, TaskOut, TaskUpdate
from app.tasks.store import store

router = APIRouter(prefix="/tasks", tags=["tasks"])

@router.post("", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
def create_task(body: TaskCreate) -> TaskOut:
    return store.create(body)

@router.get("", response_model=list[TaskOut])
def list_tasks() -> list[TaskOut]:
    return store.list()

@router.get("/{task_id}", response_model=TaskOut)
def get_task(task_id: int) -> TaskOut:
    task = store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task

@router.patch("/{task_id}", response_model=TaskOut)
def update_task(task_id: int, body: TaskUpdate) -> TaskOut:
    task = store.update(task_id, body)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task

@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int) -> None:
    if not store.delete(task_id):
        raise HTTPException(status_code=404, detail="Task not found")
```

Register it in `main.py`:

```python
from app.tasks.router import router as tasks_router
app.include_router(tasks_router)
```

### Step 4: exercise it in `/docs`

1. `POST /tasks` with `{"title": "Write M1"}`: 201, with `status: "todo"` and `priority: 2`.
2. `POST /tasks` with `{"title": ""}`: 422, and read the `loc` and `msg`.
3. `PATCH /tasks/1` with `{"status": "done"}`: title is unchanged.
4. `PATCH /tasks/1` with `{"status": "finished"}`: 422, invalid enum.
5. `DELETE /tasks/1`: 204. Again: 404.

### Checkpoint

- [ ] All five routes work and return the right codes (201, 200, 204, 404, 422)
- [ ] PATCH changes only sent fields
- [ ] ruff and mypy pass
- [ ] Commit: `M1: in-memory CRUD`

Explain out loud: why three schemas instead of one; what `exclude_unset` does; why the store has a lock; why this store breaks with `--workers 2`.

Break it: remove `exclude_unset=True` and PATCH only the status. Watch the title disappear. Restore it.

## 4. Milestone 2: PostgreSQL, migrations and layers

Goal: replace the dict with PostgreSQL, add projects as a parent of tasks, manage the schema with Alembic, and split code into router, service and model layers.

### Step 1: run PostgreSQL and Redis with Docker Compose

```yaml
# docker-compose.yml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: tasks
      POSTGRES_PASSWORD: tasks
      POSTGRES_DB: tasks
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]
  redis:
    image: redis:7
    ports: ["6379:6379"]
volumes:
  pgdata:
```

```bash
docker compose up -d db redis
uv add sqlalchemy "psycopg[binary]" alembic
```

Add to settings and `.env`:

```python
database_url: str = "postgresql+psycopg://tasks:tasks@localhost:5432/tasks"
```

### Step 2: engine, session, base

```python
# app/db/session.py
from collections.abc import Iterator
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from app.core.config import get_settings

engine = create_engine(get_settings().database_url, pool_pre_ping=True, pool_size=5)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

def get_db() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

The engine is created at import but connects lazily, on the first query. `expire_on_commit=False` keeps loaded attributes readable after commit, which avoids surprise extra queries when building responses.

### Step 3: models

```python
# app/projects/models.py
from datetime import datetime
from sqlalchemy import ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.session import Base

class Project(Base):
    __tablename__ = "projects"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    tasks: Mapped[list["Task"]] = relationship(back_populates="project", cascade="all, delete-orphan")

class Task(Base):
    __tablename__ = "tasks"
    id: Mapped[int] = mapped_column(primary_key=True)
    project_id: Mapped[int] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None]
    status: Mapped[str] = mapped_column(String(10), default="todo", index=True)
    priority: Mapped[int] = mapped_column(default=2)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), index=True)
    project: Mapped[Project] = relationship(back_populates="tasks")
```

(Keep both classes in one file for now, to avoid circular imports between the two features.) Indexes go on the columns you'll filter and sort by: `project_id`, `status`, `created_at`.

### Step 4: Alembic migrations

```bash
uv run alembic init migrations
```

In `migrations/env.py`, point Alembic at your models and settings:

```python
from app.core.config import get_settings
from app.db.session import Base
import app.projects.models  # noqa: F401  (import so tables register on Base)

config.set_main_option("sqlalchemy.url", get_settings().database_url)
target_metadata = Base.metadata
```

```bash
uv run alembic revision --autogenerate -m "create projects and tasks"
# open the generated file in migrations/versions/ and read it
uv run alembic upgrade head
```

The `import app.projects.models` line is the import lesson in action: the tables only exist on `Base.metadata` once that module has run.

### Step 5: the service layer

```python
# app/projects/service.py
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.projects.models import Project, Task
from app.tasks.schemas import TaskCreate, TaskUpdate

class NotFound(Exception):
    pass

def create_project(db: Session, name: str) -> Project:
    project = Project(name=name)
    db.add(project)
    db.commit()
    db.refresh(project)
    return project

def get_project(db: Session, project_id: int) -> Project:
    project = db.get(Project, project_id)
    if project is None:
        raise NotFound(f"project {project_id}")
    return project

def create_task(db: Session, project_id: int, data: TaskCreate) -> Task:
    get_project(db, project_id)                         # 404 if the project is missing
    task = Task(project_id=project_id, **data.model_dump())
    db.add(task)
    db.commit()
    db.refresh(task)
    return task

def list_tasks(db: Session, project_id: int) -> list[Task]:
    stmt = select(Task).where(Task.project_id == project_id).order_by(Task.id)
    return list(db.scalars(stmt))

def update_task(db: Session, task_id: int, data: TaskUpdate) -> Task:
    task = db.get(Task, task_id)
    if task is None:
        raise NotFound(f"task {task_id}")
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(task, field, value)                     # change only sent fields
    db.commit()
    db.refresh(task)
    return task
```

No `HTTPException` in the service: it raises its own `NotFound`, and the router (or, from Milestone 4, an exception handler) turns it into a 404. That keeps business logic free of HTTP.

### Step 6: the router with the DB dependency

```python
# app/projects/router.py
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.projects import service
from app.projects.schemas import ProjectCreate, ProjectOut
from app.tasks.schemas import TaskCreate, TaskOut

DB = Annotated[Session, Depends(get_db)]
router = APIRouter(prefix="/projects", tags=["projects"])

@router.post("", response_model=ProjectOut, status_code=status.HTTP_201_CREATED)
def create_project(body: ProjectCreate, db: DB):
    return service.create_project(db, body.name)

@router.post("/{project_id}/tasks", response_model=TaskOut, status_code=201)
def create_task(project_id: int, body: TaskCreate, db: DB):
    try:
        return service.create_task(db, project_id, body)
    except service.NotFound as e:
        raise HTTPException(status_code=404, detail=str(e)) from e

@router.get("/{project_id}/tasks", response_model=list[TaskOut])
def list_tasks(project_id: int, db: DB):
    return service.list_tasks(db, project_id)
```

Write `ProjectCreate` (`name`) and `ProjectOut` (`id`, `name`, `created_at`) in `app/projects/schemas.py`, and add `model_config = {"from_attributes": True}` to `TaskOut` and `ProjectOut` so they can read ORM objects. Move the `PATCH` and `DELETE` task routes to use the service the same way, then delete `store.py`.

### Checkpoint

- [ ] Data survives a server restart
- [ ] `alembic upgrade head` on an empty DB creates the tables
- [ ] Creating a task in a missing project returns 404
- [ ] Deleting a project deletes its tasks
- [ ] Commit: `M2: postgres, alembic, service layer`

Explain out loud: engine vs session vs transaction lifetimes; why `get_db` uses `yield`; why services don't raise `HTTPException`; what `ondelete="CASCADE"` does.

Break it: run with `--workers 2` now. Unlike Milestone 1, data stays consistent, because it lives in PostgreSQL, not in process memory.

## 5. Milestone 3: users and cookie auth

Goal: users register and log in, passwords are hashed, sessions use HttpOnly cookies with a short access token and a rotated refresh token in Redis, and every project belongs to its owner.

### Step 1: dependencies and settings

```bash
uv add pyjwt "pwdlib[argon2]" redis "pydantic[email]"
```

Use `pwdlib` with Argon2 for password hashing; avoid `passlib`, which is no longer maintained.

```python
# add to Settings
jwt_secret: str                       # required: a long random string in .env
access_ttl_seconds: int = 900
refresh_ttl_seconds: int = 7 * 24 * 3600
cookie_secure: bool = False           # True in production
redis_url: str = "redis://localhost:6379/0"
allowed_origins: list[str] = ["http://localhost:3000"]
```

Generate a secret: `python -c "import secrets; print(secrets.token_urlsafe(48))"`.

### Step 2: the user model and ownership

```python
# app/users/models.py
class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
```

Add `owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)` to `Project`, then:

```bash
uv run alembic revision --autogenerate -m "users and project owners"
uv run alembic upgrade head
```

If the projects table already has rows, the new non-null column fails. Either wipe dev data (`docker compose down -v`) or add it as nullable first, backfill, then make it required. That's the zero-downtime migration pattern in miniature.

### Step 3: security helpers

```python
# app/core/security.py
import hashlib, secrets
from datetime import datetime, timedelta, timezone
import jwt
from pwdlib import PasswordHash
from app.core.config import get_settings

password_hash = PasswordHash.recommended()          # Argon2

def hash_password(raw: str) -> str:
    return password_hash.hash(raw)

def verify_password(raw: str, hashed: str) -> bool:
    return password_hash.verify(raw, hashed)

def create_access_token(user_id: int) -> str:
    s = get_settings()
    now = datetime.now(timezone.utc)
    payload = {"sub": str(user_id), "iat": now, "exp": now + timedelta(seconds=s.access_ttl_seconds)}
    return jwt.encode(payload, s.jwt_secret, algorithm="HS256")

def decode_access_token(token: str) -> int:
    payload = jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])
    return int(payload["sub"])

def new_refresh_token() -> tuple[str, str]:
    raw = secrets.token_urlsafe(32)
    return raw, hashlib.sha256(raw.encode()).hexdigest()   # (cookie value, stored hash)
```

Argon2 is slow on purpose (tens of milliseconds): brute-forcing stolen hashes becomes impractical. Never use plain SHA-256 for passwords. For refresh tokens it's fine, because they're long random strings, not guessable human passwords.

### Step 4: the refresh store in Redis

```python
# app/auth/refresh_store.py
import redis
from app.core.config import get_settings

class RefreshStore:
    def __init__(self, client: redis.Redis):
        self.client = client

    def save(self, token_hash: str, user_id: int, ttl: int) -> None:
        self.client.set(f"refresh:{token_hash}", user_id, ex=ttl)

    def consume(self, token_hash: str) -> int | None:
        value = self.client.getdel(f"refresh:{token_hash}")   # single use: rotation
        return int(value) if value is not None else None

redis_client = redis.Redis.from_url(get_settings().redis_url, decode_responses=True)

def get_refresh_store() -> RefreshStore:
    return RefreshStore(redis_client)
```

This is the fix from the Deep Dive's shared-state section: sessions survive restarts and work across workers.

### Step 5: the auth router

```python
# app/auth/router.py
ACCESS, REFRESH = "access_token", "refresh_token"
REFRESH_PATH = "/auth"

def _set_session(response: Response, user_id: int, store: RefreshStore) -> None:
    s = get_settings()
    raw, hashed = new_refresh_token()
    store.save(hashed, user_id, s.refresh_ttl_seconds)
    common = {"httponly": True, "secure": s.cookie_secure}
    response.set_cookie(ACCESS, create_access_token(user_id), max_age=s.access_ttl_seconds,
                        path="/", samesite="lax", **common)
    response.set_cookie(REFRESH, raw, max_age=s.refresh_ttl_seconds,
                        path=REFRESH_PATH, samesite="strict", **common)

@router.post("/register", response_model=UserOut, status_code=201)
def register(body: RegisterIn, db: DB):
    if db.scalar(select(User).where(User.email == body.email)):
        raise HTTPException(status_code=409, detail="Email already registered")
    user = User(email=body.email, password_hash=hash_password(body.password))
    db.add(user); db.commit(); db.refresh(user)
    return user

@router.post("/login", response_model=UserOut)
def login(body: LoginIn, response: Response, db: DB, store: Annotated[RefreshStore, Depends(get_refresh_store)]):
    user = db.scalar(select(User).where(User.email == body.email))
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")  # same message for both
    _set_session(response, user.id, store)
    return user

@router.post("/refresh", status_code=204)
def refresh(response: Response, store: Annotated[RefreshStore, Depends(get_refresh_store)],
            refresh_token: Annotated[str | None, Cookie()] = None):
    user_id = store.consume(sha256_hex(refresh_token)) if refresh_token else None
    if user_id is None:
        raise HTTPException(status_code=401, detail="Session expired")
    _set_session(response, user_id, store)

@router.post("/logout", status_code=204)
def logout(response: Response, store: Annotated[RefreshStore, Depends(get_refresh_store)],
           refresh_token: Annotated[str | None, Cookie()] = None):
    if refresh_token:
        store.consume(sha256_hex(refresh_token))
    response.delete_cookie(ACCESS, path="/")
    response.delete_cookie(REFRESH, path=REFRESH_PATH)
```

Write the small pieces yourself: `RegisterIn` (`email: EmailStr`, `password: str = Field(min_length=8)`), `LoginIn`, `UserOut` (`id`, `email`, no hash), and `sha256_hex`. The login error is identical for "no such email" and "wrong password", so attackers can't discover which emails exist.

### Step 6: `get_current_user` and ownership

```python
# app/core/deps.py
def get_current_user(db: DB, access_token: Annotated[str | None, Cookie()] = None) -> User:
    if not access_token:
        raise HTTPException(status_code=401, detail="Not logged in")
    try:
        user_id = decode_access_token(access_token)
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="User not found")
    return user

CurrentUser = Annotated[User, Depends(get_current_user)]
```

In the service, every project lookup takes the user and checks ownership:

```python
def get_project(db: Session, project_id: int, user: User) -> Project:
    project = db.get(Project, project_id)
    if project is None or project.owner_id != user.id:
        raise NotFound(f"project {project_id}")        # 404, not 403: don't reveal it exists
    return project
```

Returning 404 for another user's project hides whether it exists. Use 403 when the resource is visible but the action isn't allowed (for example, a viewer trying to delete in a shared project). Add `user: CurrentUser` to every project and task route, and pass it into the service. Finally add CORS with `allow_origins=settings.allowed_origins` and `allow_credentials=True` in `main.py`.

### Checkpoint

- [ ] Register, log in, and see `Set-Cookie` for both cookies in DevTools or curl's `-i`
- [ ] `GET /users/me` works with the cookie and returns 401 without it
- [ ] User B gets 404 for user A's project
- [ ] Refresh works once with a given token and fails the second time
- [ ] Logout, then refresh fails
- [ ] Commit: `M3: users and cookie auth`

Explain out loud: why Argon2 and not SHA-256 for passwords; why the refresh token lives in Redis; why the login error message is the same for both failures; 404 vs 403 for ownership.

Break it: set the access TTL to 10 seconds, wait, call `/users/me` (401), call `/auth/refresh` (204), call `/users/me` again (200).

## 6. Milestone 4: real API features

Goal: the task list supports filtering, sorting and cursor pagination; all errors share one JSON shape; and business errors are raised from services and mapped to HTTP in one place.

### Step 1: one error family, one handler

```python
# app/core/errors.py
class AppError(Exception):
    status_code = 500
    code = "internal_error"

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message

class NotFound(AppError):
    status_code, code = 404, "not_found"

class Conflict(AppError):
    status_code, code = 409, "conflict"

class InvalidTransition(AppError):
    status_code, code = 422, "invalid_transition"
```

```python
# app/main.py
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError):
    return JSONResponse(status_code=exc.status_code,
                        content={"error": {"code": exc.code, "message": exc.message}})

@app.exception_handler(RequestValidationError)
async def validation_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(status_code=422, content={"error": {
        "code": "validation_error", "message": "Invalid request", "details": exc.errors()}})
```

Now services raise `NotFound(...)` directly, routes lose their `try/except` blocks, and every error the client sees looks like `{"error": {"code": ..., "message": ...}}`. Frontends love a consistent shape.

### Step 2: status rules in the service

```python
ALLOWED = {"todo": {"doing"}, "doing": {"todo", "done"}, "done": {"doing"}}

def update_task(db: Session, task_id: int, data: TaskUpdate, user: User) -> Task:
    task = get_task(db, task_id, user)                     # ownership check inside
    changes = data.model_dump(exclude_unset=True)
    new_status = changes.get("status")
    if new_status and new_status != task.status and new_status not in ALLOWED[task.status]:
        raise InvalidTransition(f"{task.status} -> {new_status} not allowed")
    for field, value in changes.items():
        setattr(task, field, value)
    db.commit(); db.refresh(task)
    return task
```

The rule lives in one place, and it's the same encapsulation idea as the OOP guide's `Run._move`.

### Step 3: filtering and sorting as a dependency

```python
# app/tasks/schemas.py
from typing import Literal

class TaskFilters(BaseModel):
    status: Status | None = None
    priority: Priority | None = None
    q: str | None = Field(default=None, max_length=100)     # search in title
    sort: Literal["created_at", "-created_at", "priority", "-priority"] = "-created_at"
```

```python
# router
@router.get("/{project_id}/tasks", response_model=TaskPage)
def list_tasks(project_id: int, db: DB, user: CurrentUser,
               filters: Annotated[TaskFilters, Query()],
               limit: Annotated[int, Query(ge=1, le=100)] = 20,
               cursor: str | None = None):
    return service.list_tasks(db, project_id, user, filters, limit, cursor)
```

`Annotated[TaskFilters, Query()]` makes FastAPI read the model's fields from the query string: `?status=todo&sort=-priority`. Recent FastAPI versions support Pydantic models for query parameters like this.

### Step 4: cursor pagination

Offset pagination (`OFFSET 10000`) gets slow on deep pages and skips or repeats rows when data changes. A cursor says "continue after this item".

```python
# response shape
class TaskPage(BaseModel):
    items: list[TaskOut]
    next_cursor: str | None
```

The simplest correct version sorts by `id` descending (newest first) and uses the last id as the cursor:

```python
def list_tasks(db, project_id, user, filters, limit, cursor):
    get_project(db, project_id, user)
    stmt = select(Task).where(Task.project_id == project_id)
    if filters.status:
        stmt = stmt.where(Task.status == filters.status.value)
    if filters.priority:
        stmt = stmt.where(Task.priority == filters.priority.value)
    if filters.q:
        stmt = stmt.where(Task.title.ilike(f"%{filters.q}%"))   # bound parameter: no SQL injection
    if cursor:
        stmt = stmt.where(Task.id < int(cursor))
    stmt = stmt.order_by(Task.id.desc()).limit(limit + 1)      # fetch one extra
    rows = list(db.scalars(stmt))
    has_more = len(rows) > limit
    items = rows[:limit]
    return TaskPage(items=items, next_cursor=str(items[-1].id) if has_more else None)
```

Fetching `limit + 1` rows tells you whether another page exists without a separate count query. Sorting by other fields (priority) needs a compound cursor (`priority, id`); implement it as a stretch goal once this version works.

### Step 5: stats with aggregation

```python
from sqlalchemy import func

def project_stats(db, project_id, user) -> dict[str, int]:
    get_project(db, project_id, user)
    rows = db.execute(
        select(Task.status, func.count()).where(Task.project_id == project_id).group_by(Task.status)
    ).all()
    counts = {s.value: 0 for s in Status}
    counts.update({status: n for status, n in rows})
    return counts                                        # {"todo": 3, "doing": 1, "done": 5}
```

One `GROUP BY` query, not three counts, and never loading all tasks into Python to count them.

### Checkpoint

- [ ] `?status=todo&priority=3&q=bug` filters correctly
- [ ] Following `next_cursor` walks all tasks with no duplicates and ends with `null`
- [ ] `done` to `todo` returns 422 `invalid_transition`
- [ ] Every error, including validation, has the `{"error": {...}}` shape
- [ ] Commit: `M4: filters, pagination, errors`

Explain out loud: cursor vs offset pagination; why `limit + 1`; why `ilike` with a bound value is safe from SQL injection but an f-string SQL query isn't; why aggregation belongs in the database.

## 7. Milestone 5: testing

Goal: a test suite that runs against a real PostgreSQL test database, rolls back after every test, and covers auth, ownership, validation and pagination. From here on, every new feature comes with a test.

### Step 1: a separate test database

```bash
uv add --dev pytest-cov
docker compose exec db psql -U tasks -c "CREATE DATABASE tasks_test;"
```

Test against PostgreSQL, not SQLite: types, constraints and SQL differ, and bugs hide in the differences.

### Step 2: fixtures with a rollback per test

```python
# tests/conftest.py
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from app.db.session import Base, get_db
from app.main import app

TEST_URL = "postgresql+psycopg://tasks:tasks@localhost:5432/tasks_test"
engine = create_engine(TEST_URL)

@pytest.fixture(scope="session", autouse=True)
def create_schema():
    Base.metadata.create_all(engine)        # once for the whole run
    yield
    Base.metadata.drop_all(engine)

@pytest.fixture
def db():
    connection = engine.connect()
    transaction = connection.begin()        # outer transaction
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    yield session
    session.close()
    transaction.rollback()                  # undo everything this test did
    connection.close()

@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
```

How the rollback trick works: each test runs inside a transaction that's never committed. Your code's `db.commit()` only commits a savepoint inside it, and the final `rollback()` throws everything away. Every test starts with an empty database, and the suite stays fast.

Also override the Redis refresh store with a fake in tests, so tests don't depend on a running Redis:

```python
class FakeRefreshStore:
    def __init__(self): self.data: dict[str, int] = {}
    def save(self, h, user_id, ttl): self.data[h] = user_id
    def consume(self, h): return self.data.pop(h, None)

@pytest.fixture(autouse=True)
def fake_refresh_store():
    store = FakeRefreshStore()
    app.dependency_overrides[get_refresh_store] = lambda: store
    yield store
```

This is duck typing (the OOP guide, section 1): `FakeRefreshStore` has the same methods, so the code can't tell the difference.

### Step 3: a helper for logged-in clients

```python
# tests/helpers.py
def register_and_login(client, email="a@example.com", password="password123"):
    client.post("/auth/register", json={"email": email, "password": password})
    r = client.post("/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200
    return client                            # cookies are now stored in client
```

### Step 4: the tests that matter

```python
# tests/test_auth.py
def test_me_requires_login(client):
    assert client.get("/users/me").status_code == 401

def test_login_sets_httponly_cookies(client):
    client.post("/auth/register", json={"email": "a@example.com", "password": "password123"})
    r = client.post("/auth/login", json={"email": "a@example.com", "password": "password123"})
    cookies = r.headers.get_list("set-cookie")
    assert any(c.startswith("access_token=") and "HttpOnly" in c for c in cookies)
    assert "access_token" not in r.text          # token never in the body

def test_wrong_password(client):
    client.post("/auth/register", json={"email": "a@example.com", "password": "password123"})
    r = client.post("/auth/login", json={"email": "a@example.com", "password": "nope12345"})
    assert r.status_code == 401
```

```python
# tests/test_tasks.py
from fastapi.testclient import TestClient
from app.main import app

def test_other_user_gets_404(client):
    register_and_login(client, "a@example.com")
    project_id = client.post("/projects", json={"name": "A's"}).json()["id"]

    other = TestClient(app)                    # separate cookie jar
    register_and_login(other, "b@example.com")
    assert other.get(f"/projects/{project_id}/tasks").status_code == 404

def test_pagination_walks_all(client):
    register_and_login(client)
    pid = client.post("/projects", json={"name": "p"}).json()["id"]
    for i in range(25):
        client.post(f"/projects/{pid}/tasks", json={"title": f"t{i}"})
    seen, cursor = [], None
    while True:
        params = {"limit": 10} | ({"cursor": cursor} if cursor else {})
        page = client.get(f"/projects/{pid}/tasks", params=params).json()
        seen += [t["id"] for t in page["items"]]
        cursor = page["next_cursor"]
        if cursor is None:
            break
    assert len(seen) == 25 and len(set(seen)) == 25

def test_invalid_transition(client):
    register_and_login(client)
    pid = client.post("/projects", json={"name": "p"}).json()["id"]
    tid = client.post(f"/projects/{pid}/tasks", json={"title": "t"}).json()["id"]
    client.patch(f"/tasks/{tid}", json={"status": "doing"})
    client.patch(f"/tasks/{tid}", json={"status": "done"})
    r = client.patch(f"/tasks/{tid}", json={"status": "todo"})
    assert r.status_code == 422 and r.json()["error"]["code"] == "invalid_transition"
```

### Step 5: run with coverage

```bash
uv run pytest -q --cov=app --cov-report=term-missing
```

Aim for the important paths, not 100%. The `term-missing` report shows untested lines; each one is a question: "Does this line matter?"

### What to test, in priority order

1. Security: 401 without login, 404 for others' data, cookies are HttpOnly.
2. Business rules: status transitions, duplicate email returns 409.
3. Validation: bad input returns 422 with the error shape.
4. Tricky logic: pagination, filters, stats.
5. Happy-path CRUD.

### Checkpoint

- [ ] `uv run pytest` passes and each test is independent (run any single one alone)
- [ ] Tests don't need Redis
- [ ] At least one test per item in the priority list
- [ ] Commit: `M5: test suite`

Explain out loud: how the rollback-per-test fixture works; why test against PostgreSQL; what `dependency_overrides` replaces and why that's only possible because of dependency injection.

## 8. Milestone 6: async calls and webhooks

Goal: when a task moves to `done`, the API calls the project's webhook URL after responding, using a shared async HTTP client, with a timeout, retries with backoff, and a signature so the receiver can trust it.

### Step 1: store the webhook URL

Add `webhook_url: Mapped[str | None] = mapped_column(String(500))` to `Project`, a migration, and an optional `webhook_url: HttpUrl | None` in `ProjectCreate`. Add `webhook_secret: str` to settings.

### Step 2: one shared async client, created in lifespan

```python
# app/main.py
from contextlib import asynccontextmanager
import httpx

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http = httpx.AsyncClient(timeout=httpx.Timeout(5.0, connect=2.0))
    yield
    await app.state.http.aclose()

app = FastAPI(title=settings.app_name, lifespan=lifespan)
```

One client per worker reuses connections. Creating a client per request throws away connection pooling and is a common performance bug.

### Step 3: the sender, with retries and a signature

```python
# app/webhooks/sender.py
import asyncio, hashlib, hmac, json, logging, random
import httpx
from app.core.config import get_settings

logger = logging.getLogger(__name__)
RETRYABLE = {429, 500, 502, 503, 504}

def sign(body: bytes) -> str:
    secret = get_settings().webhook_secret.encode()
    return hmac.new(secret, body, hashlib.sha256).hexdigest()

async def send_webhook(http: httpx.AsyncClient, url: str, event: dict, attempts: int = 3) -> None:
    body = json.dumps(event).encode()
    headers = {"Content-Type": "application/json", "X-Signature": sign(body),
               "X-Event-Id": event["id"]}                     # lets the receiver ignore duplicates
    for attempt in range(1, attempts + 1):
        try:
            r = await http.post(url, content=body, headers=headers)
            if r.status_code < 400:
                return
            if r.status_code not in RETRYABLE:
                logger.warning("webhook rejected status=%s url=%s", r.status_code, url)
                return                                          # 4xx: retrying won't help
        except httpx.TransportError as e:                       # timeouts, connection errors
            logger.warning("webhook attempt %s failed: %s", attempt, e)
        if attempt < attempts:
            await asyncio.sleep(0.5 * 2 ** (attempt - 1) + random.random() * 0.2)   # backoff + jitter
    logger.error("webhook gave up after %s attempts url=%s", attempts, url)
```

Every line applies a production rule: timeouts come from the client; only transient errors are retried; backoff doubles with random jitter; the signature proves the sender; the event id makes duplicates harmless (idempotency on the receiver's side).

### Step 4: trigger it after the response

```python
# app/tasks/router.py
import uuid
from fastapi import BackgroundTasks, Request

@router.patch("/{task_id}", response_model=TaskOut)
def update_task(task_id: int, body: TaskUpdate, db: DB, user: CurrentUser,
                background: BackgroundTasks, request: Request):
    before = service.get_task(db, task_id, user).status
    task = service.update_task(db, task_id, body, user)
    url = task.project.webhook_url
    if before != "done" and task.status == "done" and url:
        event = {"id": str(uuid.uuid4()), "type": "task.completed",
                 "task": {"id": task.id, "title": task.title}}
        background.add_task(send_webhook, request.app.state.http, url, event)
    return task
```

The route is a plain `def` (the database session is sync, so it runs in the thread pool). The background task is `async def`, so FastAPI runs it on the event loop after sending the response. The user doesn't wait for the webhook, and a slow receiver can't slow the API.

### Step 5: test it without the network

```python
# tests/test_webhooks.py
import httpx, pytest
from app.webhooks.sender import send_webhook

@pytest.mark.anyio
async def test_retries_then_succeeds():
    calls = []
    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return httpx.Response(503 if len(calls) < 3 else 200)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        await send_webhook(http, "https://example.com/hook", {"id": "e1", "type": "t"})
    assert len(calls) == 3
    assert "X-Signature" in calls[0].headers
```

`MockTransport` replaces the network with a function. This tests retries in milliseconds, without a real server. `@pytest.mark.anyio` runs async tests using the `anyio` plugin that ships with FastAPI's dependencies.

### The honest limitation, and the next step

`BackgroundTasks` runs in the same process. If the server restarts right after responding, the webhook is lost. For guaranteed delivery, production systems use the outbox pattern: in the same transaction as the status change, insert a row into an `outbox` table; a separate worker reads the table and sends, marking rows done. Build it as a stretch goal with a worker using Arq or RQ plus Redis.

### Checkpoint

- [ ] Completing a task sends one signed POST (test with a free request-inspector site or a local `nc -l 9000`)
- [ ] A receiver returning 503 twice then 200 gets exactly three attempts
- [ ] A 400 response is not retried
- [ ] The PATCH response time doesn't depend on the webhook
- [ ] Commit: `M6: async webhooks`

Explain out loud: why one shared `AsyncClient`; which errors to retry and why; what backoff and jitter prevent; why the route is `def` but the sender is `async def`; what the outbox pattern fixes.

## 9. Milestones 7 and 8: observability, protection and speed

Goal: every request is logged as one JSON line with a request ID and timing; unexpected errors are logged and hidden from clients; login is rate limited; project stats are cached; and `/ready` checks the database and Redis.

### Milestone 7, step 1: JSON logs

```python
# app/core/logging.py
import json, logging, sys
from contextvars import ContextVar

request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        data = {"time": self.formatTime(record), "level": record.levelname,
                "logger": record.name, "msg": record.getMessage(),
                "request_id": request_id_var.get()}
        if record.exc_info:
            data["exc"] = self.formatException(record.exc_info)
        return json.dumps(data)

def setup_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=level, handlers=[handler], force=True)
```

`ContextVar` holds a value per request, even with async code and threads, so every log line written during a request gets its ID automatically. Log to stdout; the platform (Docker, Kubernetes) collects it.

### Milestone 7, step 2: request ID and timing middleware

```python
# app/main.py
import time, uuid, logging
from app.core.logging import request_id_var, setup_logging

setup_logging()
logger = logging.getLogger("api")

@app.middleware("http")
async def request_context(request: Request, call_next):
    rid = request.headers.get("x-request-id") or uuid.uuid4().hex
    token = request_id_var.set(rid)
    start = time.perf_counter()
    try:
        response = await call_next(request)
    finally:
        ms = (time.perf_counter() - start) * 1000
        request_id_var.reset(token)
    response.headers["X-Request-Id"] = rid
    logger.info("%s %s %s %.1fms", request.method, request.url.path, response.status_code, ms)
    return response
```

When a user reports a problem, the `X-Request-Id` in their response finds every log line for that request.

### Milestone 7, step 3: the catch-all error handler

```python
@app.exception_handler(Exception)
async def unhandled_error(request: Request, exc: Exception):
    logger.exception("unhandled error")            # full traceback in the logs
    return JSONResponse(status_code=500, content={"error": {
        "code": "internal_error", "message": "Something went wrong",
        "request_id": request_id_var.get()}})
```

The client gets a safe message plus the ID; the traceback stays in the logs. Never send exception text to clients.

### Milestone 7, step 4: readiness check

```python
@app.get("/ready", tags=["ops"])
def ready(db: DB):
    db.execute(text("SELECT 1"))
    redis_client.ping()
    return {"status": "ready"}
```

`/health` says the process is alive; `/ready` says it can do real work. Orchestrators route traffic only to ready instances.

### Milestone 8, step 1: rate limiting login

A fixed-window limiter in Redis: count requests per key per minute.

```python
# app/core/rate_limit.py
from fastapi import HTTPException, Request

class RateLimit:
    def __init__(self, limit: int, window_seconds: int, prefix: str):
        self.limit, self.window, self.prefix = limit, window_seconds, prefix

    def __call__(self, request: Request) -> None:
        ip = request.client.host if request.client else "unknown"
        key = f"rl:{self.prefix}:{ip}"
        count = redis_client.incr(key)             # atomic in Redis: safe across workers
        if count == 1:
            redis_client.expire(key, self.window)  # start the window on the first hit
        if count > self.limit:
            raise HTTPException(status_code=429, detail="Too many attempts",
                                headers={"Retry-After": str(self.window)})

@router.post("/login", dependencies=[Depends(RateLimit(5, 60, "login"))])
def login(...): ...
```

This is the `__call__` dependency pattern from the Python guides: `__init__` stores the config once, `__call__` runs per request. `INCR` is atomic in Redis, so no lock is needed even with many workers. Behind a gateway, read the real client IP from the forwarded header (Uvicorn's `--proxy-headers` does this).

### Milestone 8, step 2: caching stats

```python
import json

def project_stats_cached(db, project_id, user) -> dict[str, int]:
    key = f"stats:{project_id}"
    cached = redis_client.get(key)
    if cached:
        get_project(db, project_id, user)          # still check ownership
        return json.loads(cached)
    stats = project_stats(db, project_id, user)
    redis_client.set(key, json.dumps(stats), ex=60)
    return stats

def invalidate_stats(project_id: int) -> None:
    redis_client.delete(f"stats:{project_id}")     # call after any task create/update/delete
```

The two hard parts of caching are both here: invalidation (delete the key when data changes) and security (never serve a cached value without the ownership check). The 60-second TTL is a safety net if an invalidation is ever missed.

### Milestone 8, step 3: check the indexes

```sql
EXPLAIN ANALYZE
SELECT * FROM tasks WHERE project_id = 1 AND status = 'todo' ORDER BY id DESC LIMIT 21;
```

Look for `Index Scan` rather than `Seq Scan` once there are many rows. For this exact query shape, a composite index `(project_id, status, id)` is ideal; add it in a migration with `Index("ix_tasks_project_status_id", "project_id", "status", "id")`.

### Checkpoint

- [ ] Every request produces one JSON log line with `request_id` and duration
- [ ] A deliberately raised exception returns a safe 500 with a request ID, and the traceback appears in the logs
- [ ] The sixth login attempt within a minute returns 429 with `Retry-After`
- [ ] Stats are served from Redis on the second call and refresh after a task change
- [ ] `/ready` fails when you stop Postgres (`docker compose stop db`)
- [ ] Commits: `M7: observability` and `M8: rate limit, cache, indexes`

Explain out loud: what a request ID is for; why `ContextVar` and not a global; why Redis `INCR` is safe across workers; the two hard parts of caching; `/health` vs `/ready`.

## 10. Milestone 9: Docker, CI and deployment

Goal: a small, non-root Docker image; the whole stack runs with one `docker compose up`; GitHub Actions runs lint, types and tests on every push; and the API is deployed with migrations applied before the new code serves traffic.

### Step 1: the Dockerfile

```dockerfile
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
WORKDIR /app

# dependencies first: this layer is cached until the lockfile changes
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# then the code
COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./

RUN useradd --create-home appuser
USER appuser

ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
```

What each choice does:

1. `slim` base: a smaller image, fewer vulnerabilities.
2. `PYTHONUNBUFFERED=1`: logs appear immediately instead of sitting in a buffer.
3. Lockfile copied before code: code changes rebuild in seconds because the dependency layer is cached.
4. `--frozen`: fail if `uv.lock` doesn't match `pyproject.toml`, so builds are reproducible.
5. Non-root user: if the app is compromised, the attacker isn't root in the container.
6. One Uvicorn process per container: scale by running more containers (see the Foundations guide, section 6).

Add a `.dockerignore` with `.venv`, `.git`, `tests`, `.env` and `__pycache__`.

### Step 2: the full stack in Compose

Add the API to `docker-compose.yml`:

```yaml
  api:
    build: .
    env_file: .env
    environment:
      DATABASE_URL: postgresql+psycopg://tasks:tasks@db:5432/tasks   # service name, not localhost
      REDIS_URL: redis://redis:6379/0
    ports: ["8000:8000"]
    depends_on: [db, redis]
    command: sh -c "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"
```

Inside Compose, containers reach each other by service name (`db`, `redis`), not `localhost`. That's the most common Docker networking mistake.

### Step 3: CI with GitHub Actions

```yaml
# .github/workflows/ci.yml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_USER: tasks, POSTGRES_PASSWORD: tasks, POSTGRES_DB: tasks_test }
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 5s --health-timeout 5s --health-retries 10
    env:
      JWT_SECRET: test-secret-not-real
      WEBHOOK_SECRET: test-webhook-secret
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --frozen
      - run: uv run ruff check .
      - run: uv run ruff format --check .
      - run: uv run mypy app
      - run: uv run pytest -q --cov=app
```

Now every push proves the project works on a clean machine. A green CI badge in the README is a small but real signal to reviewers.

### Step 4: deploy

Any platform that runs a container works (Render, Railway, Fly.io, or a cloud provider's container service). The steps are the same everywhere:

1. Create a managed PostgreSQL and a managed Redis; copy their URLs.
2. Set environment variables on the platform: `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `WEBHOOK_SECRET`, `COOKIE_SECURE=true`, `ENVIRONMENT=production`, `ALLOWED_ORIGINS`.
3. Configure a release or pre-deploy command: `alembic upgrade head`. It runs once per deploy, before new instances take traffic, instead of in every container at startup.
4. Point the platform's health check at `/ready`.
5. Deploy, then test with curl from your machine: register, log in (check the cookies are `Secure`), create a project and tasks.

### Production settings to flip

| Setting | Local | Production |
| --- | --- | --- |
| `COOKIE_SECURE` | `false` | `true` |
| `DEBUG` | `true` | `false` |
| `/docs` | On | On for internal APIs; off for public ones |
| `ALLOWED_ORIGINS` | `http://localhost:3000` | The real frontend URL only |
| Log level | `DEBUG` | `INFO` |
| Secrets | `.env` file | Platform secrets or a secrets manager |

### Checkpoint

- [ ] `docker compose up --build` runs the whole stack from a clean clone
- [ ] CI is green, and a deliberately failing test turns it red
- [ ] The deployed `/ready` returns 200, and cookies arrive with `Secure`
- [ ] Commit: `M9: docker, ci, deploy`, then tag `v1.0.0`

Explain out loud: why the lockfile is copied before the code; why migrations run as a release step rather than at container start; `localhost` vs service names in Compose; what changes between local and production settings.

## 11. Habits, mental models, and the interview story

The code is half the value. The other half is the habits you build while writing it, and your ability to explain every decision, because that's what an interviewer for a 1 to 3 year role actually tests.

### Habits to build on every milestone

1. Run `ruff check`, `ruff format`, `mypy` and `pytest` before every commit. Automate it later with pre-commit hooks.
2. Write the test in the same sitting as the feature, not "later".
3. Read the error message fully, top to bottom, before searching. The last line says what; the traceback says where.
4. Keep routes thin: parse, call the service, return. If a route grows past about 10 lines, logic is leaking into it.
5. Name things by what they are: `TaskCreate`, `get_current_user`, `RefreshStore`. Good names beat comments.
6. Commit small and often, with messages that say why.
7. Every outbound call gets a timeout; every list endpoint gets a limit; every secret comes from settings.

### The mental models this project drills

| Model | Where you felt it |
| --- | --- |
| Import runs once; module-level objects live per process | Settings, engine, Redis client, the M1 store breaking with 2 workers |
| Three lifetimes: process, request, transaction | `engine`, `get_db`, `commit` |
| Layers: router parses, service decides, model stores | M2 onward |
| State lives outside the process | Refresh tokens and rate limits in Redis |
| Waiting vs computing | Async webhooks vs sync DB routes |
| Validate at the edge, trust inside | Pydantic schemas on every input |
| Assume failure | Timeouts, retries, 404 vs 403, safe 500s |

### The README (your project's first impression)

Write it last, and keep it short:

1. One line: what it is. "A production-style tasks API in FastAPI with cookie auth, PostgreSQL, Redis and CI."
2. Features as a short list, with the concepts (cursor pagination, refresh rotation, rate limiting, signed webhooks).
3. Quick start: `cp .env.example .env && docker compose up --build`, then open `/docs`.
4. An architecture diagram: client, API, PostgreSQL, Redis, webhook receiver.
5. "Design decisions": three to five bullets, each a decision plus its reason. This section gets read the most.
6. "What I'd do next": the outbox pattern, async SQLAlchemy, metrics with Prometheus. Knowing the limits of your own work reads as seniority.

### The two-minute walkthrough

Practice this until it's natural:

> "It's a tasks API: users, projects, tasks. FastAPI with PostgreSQL through SQLAlchemy and Alembic, and Redis. Auth uses HttpOnly cookies with a 15-minute JWT and a refresh token rotated through Redis, so sessions work across workers. The code is layered: routers only parse and respond, services hold the rules like status transitions, and errors are one exception family mapped to a single JSON shape. Lists use cursor pagination with composite indexes. When a task completes, a signed webhook goes out after the response, with timeouts and exponential backoff; the next step would be an outbox table for guaranteed delivery. It's tested against a real Postgres with rollback-per-test fixtures, containerized as a non-root image, and CI runs lint, types and tests on every push."

Every sentence invites a follow-up question you can answer from the milestone that built it.

### Questions this project prepares you for

| They ask | You answer from |
| --- | --- |
| How does your auth work? Why cookies? | M3 |
| How do you handle a DB session per request? | M2 |
| How do you test code that uses the DB or Redis? | M5 |
| What happens if the webhook receiver is down? | M6 |
| How would you debug a slow endpoint? | M7 logs and request IDs, M8 `EXPLAIN ANALYZE` |
| How do you stop brute-force login? | M8 rate limit |
| What breaks when you add a second worker? | M1 store vs M3 Redis |
| How do you deploy a schema change safely? | M2 and M9 migrations |
| Offset vs cursor pagination? | M4 |
| `def` vs `async def` routes? | M6 |

### After version 1

Pick one stretch per week, each a new commit series:

1. The outbox table plus a worker (Arq or RQ) for guaranteed webhooks.
2. Shared projects with roles (owner, editor, viewer): real 403 cases.
3. Async SQLAlchemy with `asyncpg`, and compare latency under load with `hey` or `locust`.
4. Prometheus metrics endpoint and a Grafana dashboard.
5. Split auth into its own service with RS256 tokens (the cookie guide's microservices section).

Finish version 1 first. A complete, tested, deployed simple project beats an ambitious unfinished one in every interview.
