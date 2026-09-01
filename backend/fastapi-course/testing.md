# Testing — Concepts, Patterns, and Real Test Cases

From zero to writing production-quality tests. Includes actual test cases for this project.

---

## 1. Why Test?

Without tests, every change is a guess. You change one function and hope nothing else broke. You ship and find out 3 hours later from users.

Tests are a **safety net** — they tell you immediately when something breaks.

But more than that:
- Tests force you to write code that's actually testable (which means loosely coupled, well-structured)
- Tests document what your code is supposed to do
- Tests let you refactor confidently — change the internals, run tests, still green = still works

**What breaks without tests:**
- You change `community_service.py` and silently break the post creation flow
- You refactor `_row_to_post` and introduce a bug that only shows up with NULL author
- A new developer changes validation logic and removes a security check

---

## 2. Types of Tests

### Unit Test

Tests one function in isolation. Everything it depends on is **faked** (mocked).

```python
# test just the business logic — no DB, no HTTP
def test_slug_validation():
    with pytest.raises(ValueError):
        CommunityCreate(slug="Invalid Slug!", name="Test")
```

**Fast.** Milliseconds. No infrastructure needed.
**Limited.** Doesn't test that your SQL actually works.

### Integration Test

Tests multiple components together. In a backend — tests the service + repository + real database.

```python
# test that create_community actually writes to DB correctly
async def test_create_community(conn):
    community = await community_service.create_community(
        conn, slug="python", name="Python", description=None, created_by=user.id
    )
    assert community.slug == "python"
    assert community.id is not None  # DB generated this
```

**Slower.** Needs a real DB. But catches the bugs that matter — SQL errors, constraint violations, wrong column names.

### End-to-End (E2E) Test

Tests the full HTTP flow — sends a real HTTP request and checks the response.

```python
# test the entire flow: HTTP → router → service → repo → DB → response
async def test_create_community_endpoint(client):
    response = await client.post(
        "/communities",
        json={"slug": "python", "name": "Python"},
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 201
    assert response.json()["slug"] == "python"
```

**Slowest.** But catches integration bugs — wrong status codes, missing auth, wrong response shape.

### What to prioritize

```
Unit tests     — for pure logic (validators, formatters, calculations)
Integration    — for repositories and services (most valuable in this stack)
E2E            — for critical paths (signup, login, create post)
```

In this project (raw SQL, no ORM), integration tests on repositories are the most valuable. They catch SQL bugs, constraint violations, and type mismatches.

---

## 3. What to Test vs What to Skip

### Always test

- Business rules in services (ownership check, slug uniqueness)
- Repository queries (correct SQL, filters, soft delete)
- Error cases (404, 403, 409, 422)
- Auth flow (valid token, expired token, missing token)
- Input validation (required fields, format rules)

### Skip or defer

- Framework behavior (FastAPI routing, Pydantic parsing) — already tested by the library
- Trivial pass-throughs (a service method that just calls the repo with no logic)
- Third-party integrations in unit tests (mock them, test separately)

**The rule:** test behaviour, not implementation. Test what the code does, not how it does it internally.

---

## 4. Test Setup — Tools

### Install

```bash
pip install pytest pytest-asyncio httpx asyncpg
```

### `pytest.ini` or `pyproject.toml`

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"   # all async tests run automatically
testpaths = ["tests"]
```

### Directory structure

```
tests/
  conftest.py           — shared fixtures (DB, client, test user)
  test_auth.py          — auth endpoint tests
  test_communities.py   — community tests
  test_posts.py         — post tests
  repositories/
    test_community_repo.py
    test_post_repo.py
  services/
    test_community_service.py
    test_post_service.py
```

---

## 5. Fixtures — shared test setup

A **fixture** is a function that sets up something a test needs. pytest injects it automatically.

```python
import pytest
import asyncpg
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.fixture(scope="session")
async def db_pool():
    """One pool for the entire test session."""
    pool = await asyncpg.create_pool(
        "postgresql://user:pass@localhost/test_db",
        statement_cache_size=0
    )
    yield pool
    await pool.close()

@pytest.fixture
async def conn(db_pool):
    """One connection per test, rolled back after."""
    async with db_pool.acquire() as connection:
        async with connection.transaction():
            yield connection
            # transaction rolls back here — test data cleaned up automatically
            raise asyncpg.exceptions._base.InterfaceError  # force rollback

@pytest.fixture
async def client():
    """HTTP test client — no real server needed."""
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        yield ac

@pytest.fixture
async def test_user(conn):
    """A ready-made user for tests that need one."""
    from app.services import auth_service
    return await auth_service.signup(conn, email="test@example.com", password="password123")

@pytest.fixture
async def auth_headers(test_user):
    """Bearer token headers for authenticated requests."""
    from app.core.security import issue_access_token
    token = issue_access_token(test_user)
    return {"Authorization": f"Bearer {token}"}
```

**Rollback pattern:** wrapping each test in a transaction that's rolled back means:
- Tests don't pollute each other
- No cleanup code needed
- The DB is always in a clean state
- Much faster than truncating tables

---

## 6. Writing Tests — patterns

### Basic assertion

```python
async def test_something(conn):
    result = await some_function(conn)
    assert result is not None
    assert result.id is not None
    assert result.slug == "expected-slug"
```

### Testing exceptions

```python
import pytest
from app.core.errors import NotFoundError, CommunityAlreadyExistsError

async def test_get_nonexistent_raises(conn):
    with pytest.raises(NotFoundError):
        await community_service.get_community(conn, slug="does-not-exist")

async def test_duplicate_slug_raises(conn, test_user):
    await community_service.create_community(conn, slug="python", ...)
    with pytest.raises(CommunityAlreadyExistsError):
        await community_service.create_community(conn, slug="python", ...)  # duplicate
```

### Testing HTTP responses

```python
async def test_create_community_returns_201(client, auth_headers):
    response = await client.post(
        "/communities",
        json={"slug": "python", "name": "Python"},
        headers=auth_headers,
    )
    assert response.status_code == 201
    data = response.json()
    assert data["slug"] == "python"
    assert "id" in data
    assert "password_hash" not in data  # never leak this

async def test_create_community_requires_auth(client):
    response = await client.post(
        "/communities",
        json={"slug": "python", "name": "Python"},
        # no auth headers
    )
    assert response.status_code == 401
```

---

## 7. Real Test Cases — This Project

### `tests/conftest.py`

```python
import pytest
import asyncpg
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.services import auth_service
from app.core.security import issue_access_token

TEST_DB = "postgresql://user:pass@localhost/test_db"

@pytest.fixture(scope="session")
async def pool():
    p = await asyncpg.create_pool(TEST_DB, statement_cache_size=0)
    yield p
    await p.close()

@pytest.fixture
async def conn(pool):
    async with pool.acquire() as c:
        tr = c.transaction()
        await tr.start()
        yield c
        await tr.rollback()

@pytest.fixture
async def client(conn):
    # override get_conn to use our test connection
    from app.core import deps
    app.dependency_overrides[deps.get_conn] = lambda: conn
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()

@pytest.fixture
async def user(conn):
    return await auth_service.signup(conn, email="user@test.com", password="pass1234")

@pytest.fixture
async def token(user):
    return issue_access_token(user)

@pytest.fixture
def auth(token):
    return {"Authorization": f"Bearer {token}"}
```

---

### `tests/test_auth.py`

```python
import pytest

async def test_signup_creates_user(client):
    r = await client.post("/auth/signup", json={"email": "a@b.com", "password": "pass1234"})
    assert r.status_code == 201
    assert r.json()["email"] == "a@b.com"
    assert "password_hash" not in r.json()

async def test_signup_duplicate_email_returns_409(client):
    await client.post("/auth/signup", json={"email": "a@b.com", "password": "pass1234"})
    r = await client.post("/auth/signup", json={"email": "a@b.com", "password": "pass1234"})
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "email_already_exists"

async def test_login_returns_token(client, user):
    r = await client.post("/auth/login", json={"email": "user@test.com", "password": "pass1234"})
    assert r.status_code == 200
    assert "access_token" in r.json()

async def test_login_wrong_password_returns_401(client, user):
    r = await client.post("/auth/login", json={"email": "user@test.com", "password": "wrong"})
    assert r.status_code == 401

async def test_me_returns_current_user(client, auth):
    r = await client.get("/auth/me", headers=auth)
    assert r.status_code == 200
    assert r.json()["email"] == "user@test.com"

async def test_me_without_token_returns_401(client):
    r = await client.get("/auth/me")
    assert r.status_code == 401
```

---

### `tests/test_communities.py`

```python
async def test_create_community(client, auth):
    r = await client.post(
        "/communities",
        json={"slug": "python", "name": "Python"},
        headers=auth,
    )
    assert r.status_code == 201
    assert r.json()["slug"] == "python"

async def test_create_community_requires_auth(client):
    r = await client.post("/communities", json={"slug": "python", "name": "Python"})
    assert r.status_code == 401

async def test_create_duplicate_community_returns_409(client, auth):
    await client.post("/communities", json={"slug": "python", "name": "Python"}, headers=auth)
    r = await client.post("/communities", json={"slug": "python", "name": "Python"}, headers=auth)
    assert r.status_code == 409

async def test_create_community_invalid_slug_returns_422(client, auth):
    r = await client.post(
        "/communities",
        json={"slug": "Invalid Slug!", "name": "Python"},
        headers=auth,
    )
    assert r.status_code == 422

async def test_get_community_by_slug(client, auth):
    await client.post("/communities", json={"slug": "python", "name": "Python"}, headers=auth)
    r = await client.get("/communities/python")
    assert r.status_code == 200
    assert r.json()["slug"] == "python"

async def test_get_nonexistent_community_returns_404(client):
    r = await client.get("/communities/nonexistent")
    assert r.status_code == 404

async def test_list_communities(client, auth):
    await client.post("/communities", json={"slug": "python", "name": "Python"}, headers=auth)
    await client.post("/communities", json={"slug": "rust", "name": "Rust"}, headers=auth)
    r = await client.get("/communities")
    assert r.status_code == 200
    assert len(r.json()) == 2
```

---

### `tests/test_posts.py`

```python
import pytest

@pytest.fixture
async def community(client, auth):
    r = await client.post("/communities", json={"slug": "python", "name": "Python"}, headers=auth)
    return r.json()

async def test_create_link_post(client, auth, community):
    r = await client.post(
        "/communities/python/posts",
        json={"title": "Cool article", "url": "https://example.com"},
        headers=auth,
    )
    assert r.status_code == 201
    assert r.json()["title"] == "Cool article"
    assert r.json()["url"] == "https://example.com"

async def test_create_text_post(client, auth, community):
    r = await client.post(
        "/communities/python/posts",
        json={"title": "My thoughts", "body": "Some text here"},
        headers=auth,
    )
    assert r.status_code == 201

async def test_post_requires_url_or_body(client, auth, community):
    r = await client.post(
        "/communities/python/posts",
        json={"title": "Empty post"},  # no url, no body
        headers=auth,
    )
    assert r.status_code == 422

async def test_post_in_nonexistent_community_returns_404(client, auth):
    r = await client.post(
        "/communities/nonexistent/posts",
        json={"title": "Post", "body": "text"},
        headers=auth,
    )
    assert r.status_code == 404

async def test_list_posts_excludes_deleted(client, auth, community):
    r = await client.post(
        "/communities/python/posts",
        json={"title": "Will be deleted", "body": "text"},
        headers=auth,
    )
    post_id = r.json()["id"]

    # delete it
    await client.delete(f"/posts/{post_id}", headers=auth)

    # should not appear in list
    r = await client.get("/communities/python/posts")
    assert all(p["id"] != post_id for p in r.json())

async def test_delete_post_as_author(client, auth, community):
    r = await client.post(
        "/communities/python/posts",
        json={"title": "Delete me", "body": "text"},
        headers=auth,
    )
    post_id = r.json()["id"]

    r = await client.delete(f"/posts/{post_id}", headers=auth)
    assert r.status_code == 204

    # get returns 404 after delete
    r = await client.get(f"/posts/{post_id}")
    assert r.status_code == 404

async def test_delete_post_as_non_author_returns_403(client, auth, community):
    # create post as user A
    r = await client.post(
        "/communities/python/posts",
        json={"title": "Not yours", "body": "text"},
        headers=auth,
    )
    post_id = r.json()["id"]

    # sign up user B
    await client.post("/auth/signup", json={"email": "b@test.com", "password": "pass1234"})
    login = await client.post("/auth/login", json={"email": "b@test.com", "password": "pass1234"})
    other_auth = {"Authorization": f"Bearer {login.json()['access_token']}"}

    # user B tries to delete user A's post
    r = await client.delete(f"/posts/{post_id}", headers=other_auth)
    assert r.status_code == 403
```

---

### `tests/repositories/test_community_repo.py`

```python
from uuid import uuid4
from app.repositories import community_repository
from app.core.errors import CommunityAlreadyExistsError
import pytest

async def test_insert_and_get(conn, user):
    community = await community_repository.insert_community(
        conn, slug="python", name="Python", description=None, created_by=user.id
    )
    assert community.slug == "python"
    assert community.id is not None
    assert community.created_by == user.id

    fetched = await community_repository.get_community_by_slug(conn, "python")
    assert fetched is not None
    assert fetched.id == community.id

async def test_get_nonexistent_returns_none(conn):
    result = await community_repository.get_community_by_slug(conn, "nonexistent")
    assert result is None

async def test_duplicate_slug_raises(conn, user):
    await community_repository.insert_community(conn, slug="python", name="Python", description=None, created_by=user.id)
    with pytest.raises(CommunityAlreadyExistsError):
        await community_repository.insert_community(conn, slug="python", name="Python 2", description=None, created_by=user.id)

async def test_list_communities(conn, user):
    await community_repository.insert_community(conn, slug="python", name="Python", description=None, created_by=user.id)
    await community_repository.insert_community(conn, slug="rust",   name="Rust",   description=None, created_by=user.id)
    results = await community_repository.list_communities(conn, offset=0, limit=10)
    assert len(results) == 2
```

---

## 8. When to Skip Tests

- You're prototyping — test after the shape settles
- The test would only verify framework behavior (FastAPI, Pydantic already tested by libraries)
- A trivial one-liner with no logic (`return await repo.get(conn, id)` with no branching)
- The cost of writing + maintaining the test exceeds the risk of the bug

**Never skip:**
- Auth logic
- Ownership/permission checks
- Soft delete filters
- Any code that touches money, security, or data deletion

---

## 9. Running Tests

```bash
# run all tests
pytest

# run one file
pytest tests/test_communities.py

# run one test
pytest tests/test_communities.py::test_create_community

# verbose output
pytest -v

# stop on first failure
pytest -x

# show print statements
pytest -s
```
