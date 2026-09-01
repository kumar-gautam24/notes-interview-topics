# The Entity Blueprint

Every new entity follows this exact order. Never skip ahead — each layer exposes a problem the next one solves.

```
migration → model → repository → service → schemas → router
```

---

## Layer 0 — `core/` (set up once, never touch)

```
core/
  config.py   — reads .env, exposes typed settings object
  db.py       — creates/closes asyncpg connection pool
  deps.py     — get_conn, current_user (FastAPI dependencies)
  errors.py   — AppError hierarchy + global exception handler
  security.py — hash_password, verify_password, issue_token, decode_token
```

### `deps.py` — two dependencies everything uses

```python
async def get_conn(request: Request) -> asyncpg.Connection:
    async with request.app.state.pool.acquire() as conn:
        yield conn  # checked out before handler, returned to pool after

async def current_user(
    token: str = Depends(oauth2_scheme),
    conn: asyncpg.Connection = Depends(get_conn),
) -> User:
    payload = decode_token(token)   # raises InvalidTokenError if bad/expired
    user = await user_repo.get_by_id(conn, payload["sub"])
    if user is None:
        raise InvalidTokenError()
    return user
```

### `errors.py` — full hierarchy

```
AppError (500)
├── NotFoundError (404)
├── ConflictError (409)
│   └── XAlreadyExistsError
├── UnauthorizedError (401)
│   ├── InvalidCredentialsError
│   └── InvalidTokenError
├── ForbiddenError (403)
│   └── NotYourResourceError
└── ValidationError (422)
    └── XContentMissingError
```

Adding a new error = one class, status code inherited. That's it.

```python
class PostNotFoundError(NotFoundError):
    code = "post_not_found"
    message = "Post not found."
```

---

## Layer 1 — Migration

```sql
CREATE TABLE things (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id     UUID         REFERENCES users(id) ON DELETE SET NULL,
    parent_id    UUID NOT NULL REFERENCES parents(id) ON DELETE CASCADE,
    name         VARCHAR(255) NOT NULL,
    body         TEXT,
    count        INT          NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMPTZ,
    CONSTRAINT some_rule CHECK (...)
);

-- Cover your hot query — the one every list endpoint runs
CREATE INDEX things_parent_created_idx
    ON things (parent_id, created_at DESC)
    WHERE deleted_at IS NULL;  -- partial: only indexes live rows
```

### FK rules — always decide this before writing

| Situation | ON DELETE |
|---|---|
| Parent deleted → children meaningless | `CASCADE` |
| Author deleted → content survives | `SET NULL` (column must be nullable) |
| Delete should be blocked | `RESTRICT` |

### Column rules

- `NOT NULL DEFAULT 0` on counts — `NULL + 1 = NULL`, arithmetic breaks silently
- `deleted_at TIMESTAMPTZ` not `is_deleted BOOL` — gives you when + recovery + audit
- `DEFAULT NOW()` on created_at — never pass this from app, always let DB set it
- `VARCHAR(n)` signals meaningful max length, `TEXT` signals unbounded

---

## Layer 2 — Model (`models/thing.py`)

```python
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

@dataclass(frozen=True, slots=True)
class Thing:
    id:          UUID
    owner_id:    UUID | None   # nullable FK — must be | None
    parent_id:   UUID
    name:        str
    body:        str | None
    count:       int
    created_at:  datetime
    deleted_at:  datetime | None
```

### Rules

- Mirror DB columns exactly — same names, same nullability
- No `= None` defaults — models are built from DB rows, all fields always present
- `frozen=True` — read-only data carrier, cannot be mutated after creation
- `slots=True` — memory optimization, fixed attribute slots instead of `__dict__`
- Never import from `fastapi`, `pydantic`, or `asyncpg` here

---

## Layer 3 — Repository (`repositories/thing_repository.py`)

```python
import asyncpg
from uuid import UUID
from app.models.thing import Thing
from app.core.errors import ThingAlreadyExistsError, ThingContentMissingError

def _row_to_thing(row: asyncpg.Record) -> Thing:
    return Thing(
        id=row["id"],
        owner_id=row["owner_id"],
        parent_id=row["parent_id"],
        name=row["name"],
        body=row["body"],
        count=row["count"],
        created_at=row["created_at"],
        deleted_at=row["deleted_at"],
    )

async def insert_thing(
    conn: asyncpg.Connection, *, name: str, owner_id: UUID, parent_id: UUID, body: str | None
) -> Thing:
    try:
        row = await conn.fetchrow("""
            INSERT INTO things (name, owner_id, parent_id, body)
            VALUES ($1, $2, $3, $4)
            RETURNING id, name, owner_id, parent_id, body, count, created_at, deleted_at
        """, name, owner_id, parent_id, body)
    except asyncpg.UniqueViolationError as exc:
        raise ThingAlreadyExistsError() from exc
    except asyncpg.CheckViolationError as exc:
        raise ThingContentMissingError() from exc
    assert row is not None  # RETURNING on successful INSERT always yields a row
    return _row_to_thing(row)

async def get_thing_by_id(conn: asyncpg.Connection, thing_id: UUID) -> Thing | None:
    row = await conn.fetchrow("""
        SELECT id, name, owner_id, parent_id, body, count, created_at, deleted_at
        FROM things WHERE id = $1 AND deleted_at IS NULL
    """, thing_id)
    return _row_to_thing(row) if row else None

async def list_things(
    conn: asyncpg.Connection, *, parent_id: UUID, offset: int, limit: int
) -> list[Thing]:
    rows = await conn.fetch("""
        SELECT id, name, owner_id, parent_id, body, count, created_at, deleted_at
        FROM things
        WHERE parent_id = $1 AND deleted_at IS NULL
        ORDER BY created_at DESC
        OFFSET $2 LIMIT $3
    """, parent_id, offset, limit)
    return [_row_to_thing(r) for r in rows]

async def soft_delete_thing(conn: asyncpg.Connection, *, thing_id: UUID) -> None:
    await conn.execute("""
        UPDATE things SET deleted_at = NOW() WHERE id = $1
    """, thing_id)
```

### Rules

- Only layer that contains SQL
- Every DB error translated to domain error — never let asyncpg exceptions leak up
- Returns models, never dicts or raw rows
- `_row_to_thing` helper = one conversion function, all methods reuse it
- Never import from `fastapi`

### asyncpg method → use case

| Method | Returns | Use when |
|---|---|---|
| `fetchrow` | one row or None | SELECT/INSERT with RETURNING expecting one result |
| `fetch` | list of rows | SELECT expecting multiple results |
| `fetchval` | single value | SELECT COUNT(*), SELECT id, etc. |
| `execute` | nothing | UPDATE/DELETE where you don't need the row back |

### DB errors to translate

| asyncpg exception | Raise |
|---|---|
| `UniqueViolationError` | `XAlreadyExistsError` (409) |
| `CheckViolationError` | `XContentMissingError` (422) |
| `ForeignKeyViolationError` | `NotFoundError` (bad FK reference) |
| anything else | let propagate as 500 |

---

## Layer 4 — Service (`services/thing_service.py`)

```python
from uuid import UUID
import asyncpg
from app.models.thing import Thing
from app.models.user import User
from app.core.errors import NotFoundError, ForbiddenError
from app.repositories import thing_repository

async def create_thing(
    conn: asyncpg.Connection, *, name: str, body: str | None, owner: User, parent_id: UUID
) -> Thing:
    # business rule — app-level validation before hitting DB
    if not name.strip():
        raise ValidationError("name cannot be blank")
    return await thing_repository.insert_thing(
        conn, name=name, body=body, owner_id=owner.id, parent_id=parent_id
    )

async def get_thing(conn: asyncpg.Connection, *, thing_id: UUID) -> Thing:
    thing = await thing_repository.get_thing_by_id(conn, thing_id)
    if thing is None:
        raise NotFoundError()   # None → domain error happens here, not in repo
    return thing

async def delete_thing(
    conn: asyncpg.Connection, *, thing_id: UUID, requester: User
) -> None:
    thing = await get_thing(conn, thing_id=thing_id)  # raises NotFoundError if missing
    if thing.owner_id != requester.id:
        raise ForbiddenError()  # ownership check — only the owner can delete
    await thing_repository.soft_delete_thing(conn, thing_id=thing_id)
```

### Rules

- No SQL — calls repo only
- No `HTTPException` — raises `AppError` subclasses only
- `None → NotFoundError` translation happens here, not in repo
- Ownership/permission checks live here
- Can orchestrate multiple repo calls (e.g. create + add membership)
- Can call other services if needed

---

## Layer 5 — Schemas (`schemas/thing.py`)

```python
from pydantic import BaseModel, ConfigDict, Field, model_validator
from datetime import datetime
from uuid import UUID

class ThingCreate(BaseModel):
    name: str = Field(default=..., min_length=1, max_length=255)
    url:  str | None = None
    body: str | None = None

    @model_validator(mode="after")
    def url_or_body_required(self) -> "ThingCreate":
        if not self.url and not self.body:
            raise ValueError("must provide url or body")
        return self

class ThingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)  # reads dataclass attrs not just dicts

    id:         UUID
    owner_id:   UUID | None
    parent_id:  UUID
    name:       str
    body:       str | None = None
    count:      int
    created_at: datetime
    # deleted_at intentionally omitted — internal field, never exposed
```

### Rules

- `Create` — validates input shape. Field constraints + cross-field rules.
- `Response` — shapes output. Always `from_attributes=True`. Never expose internal fields.
- `model_validate(obj)` — crosses model→schema boundary in the router
- Cross-field rules → `@model_validator(mode="after")`
- Single-field format rules → `Field(pattern=...)` or `@field_validator`

### Validator decision tree

| Need | Tool |
|---|---|
| Length, regex, min/max | `Field(min_length=, max_length=, pattern=)` |
| Reuse same constraint across models | `Annotated[str, Field(...)]` |
| Transform or complex logic on one field | `@field_validator` |
| Rule involving two or more fields | `@model_validator(mode="after")` |

---

## Layer 6 — Router (`api/routes/things.py`)

```python
"""
POST   /things          create thing (auth required)
GET    /things          list things (paginated)
GET    /things/{id}     get thing by id
DELETE /things/{id}     soft delete (auth required, must be owner)
"""

from fastapi import APIRouter, Depends, status
import asyncpg
from uuid import UUID
from app.core.deps import get_conn, current_user
from app.models.user import User
from app.schemas.thing import ThingCreate, ThingResponse
from app.services import thing_service

router = APIRouter(tags=["things"])

@router.post("/things", response_model=ThingResponse, status_code=status.HTTP_201_CREATED)
async def create_thing(
    payload: ThingCreate,
    user: User = Depends(current_user),
    conn: asyncpg.Connection = Depends(get_conn),
) -> ThingResponse:
    thing = await thing_service.create_thing(conn, name=payload.name, owner=user)
    return ThingResponse.model_validate(thing)

@router.get("/things", response_model=list[ThingResponse])
async def list_things(
    offset: int = 0,
    limit: int = 10,
    conn: asyncpg.Connection = Depends(get_conn),
) -> list[ThingResponse]:
    things = await thing_service.list_things(conn, offset=offset, limit=limit)
    return [ThingResponse.model_validate(t) for t in things]

@router.get("/things/{thing_id}", response_model=ThingResponse)
async def get_thing(
    thing_id: UUID,
    conn: asyncpg.Connection = Depends(get_conn),
) -> ThingResponse:
    thing = await thing_service.get_thing(conn, thing_id=thing_id)
    return ThingResponse.model_validate(thing)

@router.delete("/things/{thing_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_thing(
    thing_id: UUID,
    user: User = Depends(current_user),
    conn: asyncpg.Connection = Depends(get_conn),
) -> None:
    await thing_service.delete_thing(conn, thing_id=thing_id, requester=user)
```

### Rules

- No business logic
- No SQL
- No try/except — global handler catches everything
- model → schema conversion happens here only
- `status_code=201` for creation, `204` for deletion
- Register in `main.py`: `app.include_router(things.router)`

---

## Exception flow — full picture

```
DB throws UniqueViolationError
        ↓
Repository catches → raises ThingAlreadyExistsError (AppError subclass, status=409)
        ↓
Service — doesn't catch it, propagates up
        ↓
Router — doesn't catch it, propagates up
        ↓
FastAPI runtime — hits global handler (registered in main.py)
        ↓
app_error_handler reads exc.status_code, exc.code, exc.message
        ↓
Client gets: {"error": {"code": "thing_already_exists", "message": "..."}}
```

Unexpected errors (bugs, connection drops) are NOT AppError — they propagate as 500. Client gets a generic error. Your logs have the full traceback.

---

## Layer hygiene — check before every commit

```bash
grep -r "HTTPException" app/services      # must be empty
grep -r "HTTPException" app/repositories  # must be empty
grep -r "SELECT\|INSERT\|UPDATE\|DELETE" app/services  # must be empty
```
