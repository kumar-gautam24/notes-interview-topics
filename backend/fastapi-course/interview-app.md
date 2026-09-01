# Interview FastAPI App — Just Make It Work

No strict architecture. No layering. Auth + CRUD in one file.
Use this when you need to ship something fast or demo in an interview.

---

## Setup

```bash
pip install fastapi uvicorn asyncpg pydantic python-jose[cryptography] passlib[bcrypt] python-dotenv
```

```bash
uvicorn main:app --reload
```

---

## Full app — `main.py`

```python
from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from typing import AsyncIterator
from uuid import UUID
from contextlib import asynccontextmanager

import asyncpg
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr

# ── config ────────────────────────────────────────────────────────────────────

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://user:pass@localhost/db")
SECRET_KEY   = os.environ.get("SECRET_KEY", "change-me-in-production")
ALGORITHM    = "HS256"
TOKEN_EXPIRY = 60 * 24  # minutes

# ── security helpers ──────────────────────────────────────────────────────────

pwd = CryptContext(schemes=["bcrypt"])
oauth2 = OAuth2PasswordBearer(tokenUrl="/auth/login")

def hash_password(plain: str) -> str:
    return pwd.hash(plain)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd.verify(plain, hashed)

def create_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=TOKEN_EXPIRY)
    return jwt.encode({"sub": user_id, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

# ── database ──────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=5, statement_cache_size=0)
    app.state.pool = pool
    yield
    await pool.close()

app = FastAPI(lifespan=lifespan)

async def get_conn(request):
    async with request.app.state.pool.acquire() as conn:
        yield conn

# ── schemas ───────────────────────────────────────────────────────────────────

class UserCreate(BaseModel):
    email: str
    password: str

class UserOut(BaseModel):
    id: UUID
    email: str
    created_at: datetime

class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"

class ItemCreate(BaseModel):
    title: str
    body: str | None = None

class ItemOut(BaseModel):
    id: UUID
    title: str
    body: str | None
    owner_id: UUID
    created_at: datetime

# ── dependencies ──────────────────────────────────────────────────────────────

async def current_user(token: str = Depends(oauth2), conn=Depends(get_conn)):
    payload = decode_token(token)
    user = await conn.fetchrow("SELECT * FROM users WHERE id = $1", UUID(payload["sub"]))
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user

# ── auth routes ───────────────────────────────────────────────────────────────

@app.post("/auth/signup", response_model=UserOut, status_code=201)
async def signup(payload: UserCreate, conn=Depends(get_conn)):
    existing = await conn.fetchrow("SELECT id FROM users WHERE email = $1", payload.email)
    if existing:
        raise HTTPException(status_code=409, detail="Email already registered")
    row = await conn.fetchrow(
        "INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email, created_at",
        payload.email,
        hash_password(payload.password),
    )
    return dict(row)

@app.post("/auth/login", response_model=Token)
async def login(form: OAuth2PasswordRequestForm = Depends(), conn=Depends(get_conn)):
    user = await conn.fetchrow("SELECT * FROM users WHERE email = $1", form.username)
    if not user or not verify_password(form.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Wrong email or password")
    return {"access_token": create_token(str(user["id"])), "token_type": "bearer"}

@app.get("/auth/me", response_model=UserOut)
async def me(user=Depends(current_user)):
    return dict(user)

# ── items CRUD ────────────────────────────────────────────────────────────────

@app.post("/items", response_model=ItemOut, status_code=201)
async def create_item(payload: ItemCreate, user=Depends(current_user), conn=Depends(get_conn)):
    row = await conn.fetchrow(
        "INSERT INTO items (title, body, owner_id) VALUES ($1, $2, $3) RETURNING *",
        payload.title, payload.body, user["id"],
    )
    return dict(row)

@app.get("/items", response_model=list[ItemOut])
async def list_items(offset: int = 0, limit: int = 10, conn=Depends(get_conn)):
    rows = await conn.fetch("SELECT * FROM items ORDER BY created_at DESC OFFSET $1 LIMIT $2", offset, limit)
    return [dict(r) for r in rows]

@app.get("/items/{item_id}", response_model=ItemOut)
async def get_item(item_id: UUID, conn=Depends(get_conn)):
    row = await conn.fetchrow("SELECT * FROM items WHERE id = $1", item_id)
    if not row:
        raise HTTPException(status_code=404, detail="Item not found")
    return dict(row)

@app.put("/items/{item_id}", response_model=ItemOut)
async def update_item(item_id: UUID, payload: ItemCreate, user=Depends(current_user), conn=Depends(get_conn)):
    row = await conn.fetchrow("SELECT * FROM items WHERE id = $1", item_id)
    if not row:
        raise HTTPException(status_code=404, detail="Item not found")
    if row["owner_id"] != user["id"]:
        raise HTTPException(status_code=403, detail="Not your item")
    updated = await conn.fetchrow(
        "UPDATE items SET title=$1, body=$2 WHERE id=$3 RETURNING *",
        payload.title, payload.body, item_id,
    )
    return dict(updated)

@app.delete("/items/{item_id}", status_code=204)
async def delete_item(item_id: UUID, user=Depends(current_user), conn=Depends(get_conn)):
    row = await conn.fetchrow("SELECT * FROM items WHERE id = $1", item_id)
    if not row:
        raise HTTPException(status_code=404, detail="Item not found")
    if row["owner_id"] != user["id"]:
        raise HTTPException(status_code=403, detail="Not your item")
    await conn.execute("DELETE FROM items WHERE id = $1", item_id)
```

---

## SQL — run this first

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT        NOT NULL UNIQUE,
    password_hash TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE items (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title      TEXT        NOT NULL,
    body       TEXT,
    owner_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## Flow to demo

```
1. POST /auth/signup   {email, password}          → creates user
2. POST /auth/login    form: username+password     → returns token
3. GET  /auth/me       Bearer token                → current user
4. POST /items         Bearer token + {title,body} → creates item
5. GET  /items                                     → list all
6. GET  /items/{id}                                → get one
7. PUT  /items/{id}    Bearer token + {title,body} → update (must be owner)
8. DELETE /items/{id}  Bearer token                → delete (must be owner)
```

---

## What's deliberately missing vs production app

| Missing | Why it matters in production |
|---|---|
| Layered architecture | hard to test, change, or reuse logic |
| Domain errors (AppError) | DB errors leak to client |
| Refresh tokens | access token expires → user must re-login |
| Input validation (Field constraints) | bad data hits the DB |
| Soft delete | can't recover deleted data |
| Connection pool tuning | default settings may not fit load |
| Structured logging | can't debug prod issues |
| Rate limiting | anyone can spam your endpoints |
| Tests | no confidence when changing code |

The interview app is fine for demos. The production app is what you actually build.
