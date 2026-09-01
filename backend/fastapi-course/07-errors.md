# 7. Errors and exception handling

This codebase has a strict rule: **routes never `try/except` domain exceptions.** Errors flow up to a single global handler that converts them to HTTP responses.

This doc explains the why and the mechanics.

## The naive approach (and what's wrong with it)

A new developer might write:

```python
# WRONG — what we do NOT do here
@router.post("/signup")
async def signup(payload: SignupRequest, conn = Depends(get_conn)):
    try:
        user = await auth_service.signup(conn, ...)
    except EmailAlreadyExistsError:
        raise HTTPException(409, "An account with that email already exists")
    except Exception as e:
        raise HTTPException(500, "Something went wrong")
    return UserPublic.model_validate(user)
```

What's wrong:

1. **Repeats itself.** Every route that calls `signup` (or any service that can raise `EmailAlreadyExistsError`) needs the same `except` clause.
2. **Couples HTTP status codes to route files.** If you decide 409 should become 422, you'd hunt through every route.
3. **Hides errors easily.** `except Exception:` swallows everything, including programming bugs you'd want to crash on.
4. **Mixes concerns.** The route is supposed to be a thin shell. Instead it's making policy decisions about what error code maps to what scenario.

## What we do instead

```python
# What we actually do
@router.post("/signup", response_model=UserPublic, status_code=201)
async def signup(payload: SignupRequest, conn = Depends(get_conn)) -> UserPublic:
    user = await auth_service.signup(conn, email=payload.email, password=payload.password)
    return UserPublic.model_validate(user)
```

Five lines. No `try`, no `except`, no `HTTPException`. The route only knows:
- Parse the request.
- Call the service.
- Return the response.

If `auth_service.signup` raises `EmailAlreadyExistsError`, we let it propagate up. FastAPI catches it and runs our global handler, which turns it into a 409 with a uniform JSON body.

## The error tree

`app/core/errors.py` defines a small hierarchy:

```
AppError                    (base, 500 by default)
├── NotFoundError           (404)
├── ConflictError           (409)
│   └── EmailAlreadyExistsError
├── UnauthorizedError       (401)
│   ├── InvalidCredentialsError
│   └── InvalidTokenError
└── ValidationError         (422)
```

Each subclass sets two pieces of metadata as class attributes:

```python
class EmailAlreadyExistsError(ConflictError):
    code = "email_already_exists"             # stable for client logic
    message = "An account with this email already exists."   # human-readable
```

Plus the inherited `status_code = 409` from `ConflictError`.

So when a service does `raise EmailAlreadyExistsError()`, the exception object carries all three fields with it.

## The global handler

```python
async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "message": exc.message}},
    )
```

Registered in `app/main.py`:

```python
app.add_exception_handler(AppError, app_error_handler)
```

The magic is **`AppError` is the base class**. By registering for the base, every subclass is caught — no enumeration needed. New error types get HTTP behavior for free.

## The flow, end to end

```
service:    raise EmailAlreadyExistsError()
                          │
                          │  (uncaught — bubbles up)
                          ▼
route:      (no try/except, propagates further)
                          │
                          ▼
FastAPI:    sees exception is an AppError
                          │
                          ▼
global handler:  exc.status_code → 409
                 exc.code        → "email_already_exists"
                 exc.message     → "An account with this email already exists."
                          │
                          ▼
HTTP response:
  Status: 409 Conflict
  Body:   {"error": {"code": "email_already_exists",
                      "message": "An account with this email already exists."}}
```

## The response shape and why it's worth standardizing

Every error from this server looks like:

```json
{ "error": { "code": "<machine-readable>", "message": "<human-readable>" } }
```

- **`code`** is stable. Client code branches on it (e.g., on signup, "if `email_already_exists`, show the 'already have an account?' banner"). Don't change a `code` once it's deployed.
- **`message`** is for humans. You can rewrite it freely (`"That email is already in use"` → `"An account with this email already exists"`) without breaking clients.

If you ever feel like adding `details` for field-level errors (like form validation), extend the shape:

```json
{ "error": { "code": "validation_error", "message": "...", "details": { "email": "invalid format" } } }
```

Just keep `error.code` + `error.message` always present, so simple clients keep working.

## What about Pydantic's own validation errors?

When a request body doesn't match a Pydantic schema (wrong type, missing field, invalid email), Pydantic raises `RequestValidationError`. FastAPI handles those itself with a different default shape:

```json
{
  "detail": [
    { "loc": ["body", "email"], "msg": "value is not a valid email", "type": "value_error.email" }
  ]
}
```

Right now we leave that as-is. If we want consistent shape with our `{"error": {...}}` envelope, we'd register a custom handler for `RequestValidationError` too. Listed under "tech debt" in the README.

## When to add a new error type

Pretty much any time you write `raise SomeError(...)` in a service. Add it to `errors.py`:

```python
class PostNotFoundError(NotFoundError):
    code = "post_not_found"
    message = "Post not found."
```

That's the entire setup. No route changes, no handler changes. The base class chain gives it 404 behavior; the global handler gives it the right JSON shape.

## When NOT to use AppError

`AppError` is for **expected** problems — things the client did wrong, or known business-rule violations. They're not *bugs*; they're branches of normal flow.

For actual bugs (programming errors, unexpected DB outages mid-request, weird state) — let the exception escape unhandled. FastAPI will turn it into a generic 500. That 500 should land in your error tracker (Sentry, etc.) where someone fixes the code. **You do not want to catch and silently 500 your way out of bugs**; the bug needs to be visible.

A useful litmus: "would I want a stack trace for this in my error tracker?" If yes, it's a bug — let it crash. If no, it's a domain error — make it an `AppError`.

## Summary

- One handler maps every domain error to HTTP. Routes stay thin.
- Errors are real Python exception classes with `code`, `message`, and `status_code`.
- Adding a new error is one class definition.
- Bugs (anything not modeled as an `AppError`) crash to a 500. That's the feature, not a bug.

## You've reached the end

Re-read [02-layers.md](02-layers.md) once more after a few days of working with this code — the layering rules will land harder when you've seen them in action. Then come back here to think about errors when you start adding new endpoints.
