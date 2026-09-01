# 2. Layered architecture — what each layer does

Every layer has a job. More importantly, **every layer has things it must NOT do.** The "must not" is what makes the code stay clean as it grows.

```
api/routes  ──>  services  ──>  repositories  ──>  asyncpg
   (HTTP)        (logic)        (raw SQL)         (driver)
```

Arrows point in only one direction. A repository never imports a service. A service never imports a router. This is enforced by convention, not by the language.

## `app/api/routes/` — the HTTP layer

**Job:** translate between HTTP and your domain. Take a request, hand it to a service, return a response.

**Must do:**
- Declare the URL and method (`@router.post("/signup")`).
- Validate the request body via a Pydantic schema (`SignupRequest`).
- Declare dependencies (`Depends(get_conn)`, `Depends(current_user)`).
- Call into a service.
- Convert the domain model the service returned into a response schema.

**Must NOT do:**
- Run SQL.
- Implement business rules ("if the user is admin, then...").
- `try/except` domain exceptions — let them bubble.

A good test: if you read the body of a route function, every line should be one of these four — call a service, convert a model to a schema, return it, or declare a dependency. If you see an `if`, an SQL string, or a hashing call inside a route, something belongs in the service.

Look at `app/api/routes/auth.py` — the `signup` function is 4 lines. That's not by accident; the route is a thin shell.

## `app/services/` — the business logic layer

**Job:** make decisions. Compose repository calls, enforce rules, raise meaningful errors.

**Must do:**
- Take an `asyncpg.Connection` from the caller. Pass it down to repositories.
- Call repositories to read or write data.
- Apply business rules (lowercase the email before storing, hash the password, refuse duplicate emails, decide which user is allowed to do what).
- Raise *domain* exceptions: `EmailAlreadyExistsError`, `InvalidCredentialsError`, etc.

**Must NOT do:**
- `import HTTPException` or anything from `fastapi`. A service doesn't know it's serving HTTP — it could just as easily be called from a CLI script or a background worker.
- Run SQL directly.
- Decide HTTP status codes.

`auth_service.authenticate` is a clean example: it knows about emails and passwords (domain), but it has no idea what a 401 is. It raises `InvalidCredentialsError`; the global error handler decides that becomes a 401.

## `app/repositories/` — the data access layer

**Job:** the only place SQL lives.

**Must do:**
- Take a `Connection` from the caller — never acquire one itself.
- Run parameterized SQL (`$1`, `$2`).
- Return domain model instances (e.g. `User`) or `None`.
- Re-raise database errors as domain exceptions where it makes sense (`asyncpg.UniqueViolationError` → `EmailAlreadyExistsError`).

**Must NOT do:**
- Make decisions ("if user is None, raise"). That's a service's job.
- Call services or other repositories.
- String-concatenate or f-string user input into SQL — always use `$1, $2, …` parameters.

Repos are the *boringest* layer. That's the point.

## `app/models/` — domain models

**Job:** represent an entity as it exists inside our system.

```python
@dataclass(frozen=True, slots=True)
class User:
    id: UUID
    email: str
    password_hash: str
    created_at: datetime
```

`frozen=True` means you can't mutate it after construction (`user.email = "..."` raises). That's deliberate: services compose domain values, they don't mutate them.

**Models live INSIDE the system. They never leave it over HTTP.** The route layer always converts them to a schema first.

## `app/schemas/` — wire formats

**Job:** describe what JSON looks like — both for incoming requests and outgoing responses.

This is Pydantic. A Pydantic `BaseModel` does three things: it validates incoming JSON, it serializes outgoing data, and it generates the OpenAPI/Swagger documentation you see at `/docs`.

```python
class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    email: EmailStr
    created_at: datetime
```

Compare that with the `User` domain model above. Same fields *except* `password_hash` is missing. **That difference is the whole point of having both.** A route function is typed to return `UserPublic` — there is no field on `UserPublic` to put a password hash on, so you cannot leak it. The compiler / Pydantic enforces it.

`from_attributes=True` lets Pydantic build a `UserPublic` from any object (including our dataclass `User`) by reading attributes — that's what makes `UserPublic.model_validate(user)` work.

### "Why not one type and exclude `password_hash` on response?"

Tempting, especially for one-field divergence. The reasons we don't:

1. **Default-deny is safer than default-allow.** If you forget to exclude a field once, you leak. With two types, the compiler refuses to put a hash on `UserPublic` because there's no slot.
2. **They diverge fast.** Soon `UserPublic` will gain `display_name`, `bio`, `avatar_url`. There will be `UserCreate` (signup body), `UserUpdate` (PATCH body), `UserAdminView` (admin-only fields). If they share a base, you end up doing `exclude=`, `include=`, `by_alias=`, and the rules accumulate. Independent classes are simpler.
3. **They mean different things.** `User` is "the entity in our system." `UserPublic` is "what we choose to show the world." The fact that they happen to overlap a lot today doesn't make them the same concept.

## `app/core/` — cross-cutting infrastructure

**Job:** things every layer needs but no layer owns.

| File | Concern |
|------|---------|
| `config.py` | Reads env vars, validates them, exposes a `settings` object |
| `db.py` | Creates and closes the asyncpg connection pool |
| `security.py` | Password hashing, JWT encode/decode |
| `errors.py` | The `AppError` tree + the global exception handler |
| `deps.py` | FastAPI dependency providers (`get_conn`, `current_user`) |

Nothing in `core/` knows about your domain (users, posts, votes). If you ever feel like `core/` needs to know "users have an email" — that's a service concern, not core.

## A useful litmus test

Before adding code, ask: *if this exact line moved to a different layer, would the code still work?* If yes, the line might be in the wrong place. Examples:
- An `if user is None: raise` inside a repository — would also work in the service. Move it to the service; let repos return `None`.
- An `email.lower()` inside a route — would also work in the service. Move it; routes shouldn't mutate domain values.
- An SQL string inside a service — wouldn't work in the route, would work in a repo. Move it to a repo.

## What to read next

[03-async-and-context-managers.md](03-async-and-context-managers.md) — the language-level mechanics that make the rest of this codebase tick.
