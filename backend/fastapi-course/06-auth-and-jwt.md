# 6. Authentication and JWT

This walks through what a JWT actually is, what each claim (`sub`, `iat`, `exp`, `type`) means, and how the full auth flow works in this codebase.

## What is a JWT?

JWT stands for **JSON Web Token**. It's a string that looks like this:

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.<payload>.<signature>
```

Three base64-url-encoded parts joined by `.`:

```
HEADER  .  PAYLOAD  .  SIGNATURE
```

Decoded, the **header** says: "this token is signed with HS256."

```json
{ "alg": "HS256", "typ": "JWT" }
```

The **payload** is your claims (what the token says):

```json
{
  "sub": "e381a39d-...",
  "type": "access",
  "iat": 1714763020,
  "exp": 1714849420
}
```

The **signature** is HMAC-SHA256 of `header + "." + payload`, signed with the server's secret. The signature is what makes the token tamper-proof: if anyone changes a single character in the header or payload, the signature won't match anymore, and the server will reject the token.

**Crucially: the payload is signed, not encrypted.** Anyone holding the token can decode and read the claims. Don't put secrets in there. `sub` is fine because the user already knows their own ID.

## The standard claims (what each field means)

These are defined in [RFC 7519](https://datatracker.ietf.org/doc/html/rfc7519). The names are short to keep tokens small.

| Claim | Full name | What it means | Our value |
|-------|-----------|---------------|-----------|
| `sub` | Subject | Who the token is about. The user the token represents. | The user's UUID, as a string |
| `iat` | Issued At | When the token was created (unix timestamp). | `now` at signing |
| `exp` | Expiration | When the token stops being valid (unix timestamp). | `now + 24h` for access tokens |

We also add one custom claim:

| `type` | (custom) | Distinguishes access tokens from refresh tokens. | `"access"` or `"refresh"` |

The `type` claim is why someone can't take a refresh token and use it as an access token — `decode_access_token` checks `payload["type"] == "access"` and rejects anything else.

## Where this lives in code

`app/core/security.py`:

```python
def _encode(subject: UUID | str, *, token_type: str, ttl: timedelta) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(subject),
        "type": token_type,
        "iat": int(now.timestamp()),
        "exp": int((now + ttl).timestamp()),
    }
    return jwt.encode(
        payload,
        settings.jwt_secret.get_secret_value(),
        algorithm=settings.jwt_algorithm,
    )
```

So our access token's `sub` is the user ID — that's how `current_user` knows which user the request is for: it decodes the token, reads `sub`, looks up the user.

## HS256 — the signing algorithm

There are two families of JWT signing:

- **Symmetric (HS256, HS384, HS512)** — same secret signs and verifies. Good when one server (or a few servers sharing the same secret) is doing both.
- **Asymmetric (RS256, ES256, etc.)** — private key signs, public key verifies. Good when many services need to verify tokens but only one (the auth server) issues them.

We use HS256 because we have one server doing both. If we later split into auth-server + several API-servers, RS256 would let us hand the public key to the APIs without sharing the secret.

## The full signup → login → /me flow

### Signup (`POST /auth/signup`)

```
Client sends: {"email": "you@x.com", "password": "hunter222"}
   │
   ▼
Route → SignupRequest validates email format and password length
   │
   ▼
auth_service.signup:
   - lowercases email
   - hashes password with argon2id  (~50–100ms intentional slowness)
   - calls user_repository.insert_user
   │
   ▼
INSERT INTO users (email, password_hash) ... RETURNING id, email, password_hash, created_at
   │
   ▼
Returns User domain model
   │
   ▼
Route converts User → UserPublic (drops password_hash)
   │
   ▼
HTTP 201 with {id, email, created_at}
```

No token issued at signup. The client must log in to get one. (You could change that — many apps log you in directly after signup. We don't, because it keeps the login flow as the single source of truth for issuing tokens.)

### Login (`POST /auth/login`)

```
Client sends: {"email": "you@x.com", "password": "hunter222"}
   │
   ▼
auth_service.authenticate:
   - lowercases email
   - looks up the user
   - argon2.verify(stored_hash, supplied_password)
   - if user is missing OR password mismatches → InvalidCredentialsError (401)
   │
   ▼
auth_service.issue_access_token(user) → JWT with sub=user.id, type=access, exp=24h
   │
   ▼
HTTP 200 with {"access_token": "eyJ...", "token_type": "bearer"}
```

The client stores the `access_token` somewhere safe (memory, secure storage in mobile, httpOnly cookie if you wired one up — we don't here).

### Protected request (`GET /me`)

```
Client sends:  GET /me
               Authorization: Bearer eyJ...
   │
   ▼
HTTPBearer scheme extracts the token from the header
   │
   ▼
current_user dependency:
   - decode_access_token(token)
       - jwt.decode validates the signature against JWT_SECRET
       - jwt.decode validates `exp` (expired token → JWTError → InvalidTokenError → 401)
       - we check payload["type"] == "access"
   - reads sub, parses to UUID
   - get_user_by_id(conn, user_id)
       - if not found → InvalidTokenError (treat dangling tokens as invalid)
   - returns User
   │
   ▼
Route receives the User, returns UserPublic
   │
   ▼
HTTP 200 with {id, email, created_at}
```

If any step fails, an `AppError` subclass propagates up, the global handler turns it into a 401 with the response shape `{"error": {"code": "...", "message": "..."}}`.

## The Authorization header — why "Bearer"?

The HTTP spec defines several auth schemes (Basic, Digest, Bearer, etc.). "Bearer" means *whoever bears (holds) the token gets access*. There's no challenge, no proof of identity beyond having the token. That's why losing a JWT is bad — anyone with it can act as you until it expires.

The header literally looks like:

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

Our `HTTPBearer(auto_error=True)` dependency parses that header, strips the `Bearer ` prefix, and gives us just the token in `credentials.credentials`. With `auto_error=True`, if the header is missing or malformed, FastAPI returns 401 automatically — we don't have to.

In Swagger, the **Authorize** button asks for just the token (the part after "Bearer "). Swagger sends the `Bearer ` prefix on every subsequent call.

## Why argon2id and not bcrypt or plain SHA?

- **SHA / MD5 / etc.** are general-purpose hashes designed to be fast. That's the opposite of what you want for passwords — fast = brute-forceable.
- **bcrypt** is a deliberately slow hash. Better, but doesn't resist GPU/ASIC attacks well.
- **argon2id** is the current OWASP recommendation. Memory-hard (uses a configurable amount of RAM per hash), which makes GPU attacks expensive. It's the default winner of the Password Hashing Competition.

`argon2-cffi` ships sensible defaults; we don't tune them in this scaffold. For production you'd benchmark and pick parameters that take ~100–500ms on your target hardware.

The hash format looks like:

```
$argon2id$v=19$m=65536,t=3,p=4$random_salt_bytes$hash_bytes
```

All parameters are encoded into the string itself, so verifying just needs the stored hash + the password. There's no separate "salt" column — the salt is in the string.

## What we DON'T have yet (and what's missing if this were a real product)

- **No refresh tokens.** The function exists in `security.py` but no endpoint issues them. Today: token expires in 24h, user has to log in again.
- **No logout / revocation.** Once a token is issued, it's valid until `exp`. Nothing on the server can invalidate it. Real systems either keep a "revoked tokens" table, or use short-lived access tokens + refresh, or both.
- **No rate limiting on `/auth/login`.** Brute-forceable. A real deployment puts rate limiting in front of this — at the gateway/CDN, or via something like `slowapi` here.
- **No password reset flow.**
- **No email verification.**
- **No "remember me" / device-bound tokens.**

These are real concerns; they aren't in this scaffold because the goal was the foundation, not the full auth product.

## What to read next

[07-errors.md](07-errors.md) — the AppError tree and why routes never `try/except`.
