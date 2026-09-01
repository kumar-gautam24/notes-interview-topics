# 05 — Config and Environments

## How configuration works

This project uses an **INI file** for configuration — a simple key-value format grouped into sections. The file is `app/config/app_config.ini`.

### The INI file structure

```ini
[COMMON]
# Settings shared across ALL environments
SOME_KEY=some_value

[DEV]
# Settings for development environment
DB_HOST=<DB_HOST>
DB_NAME=<DB_NAME>
RAZORPAY_KEY_ID=rzp_test_...

[PROD]
# Settings for production environment
DB_HOST=<DB_AZURE_HOST>
DB_NAME=<DB_NAME>
RAZORPAY_KEY_ID=rzp_live_...
```

### How config_utils.py loads it

```python
# app/utils/config_utils.py — simplified

# 1. Try multiple paths to find the INI file
config_paths = [
    "../config/app_config.ini",
    "./app/config/app_config.ini",
    "./config/app_config.ini",
    # ... relative to the script itself
]

# 2. Read the first one found
for path in config_paths:
    if parser.read(path):
        break

# 3. Determine environment from ENVT env var (defaults to "DEV")
def __get_current_envt():
    return os.environ.get('ENVT', 'DEV').strip()

# 4. Merge COMMON + environment-specific settings
def get_all_configs():
    common = parser['COMMON']       # base settings
    envt = parser[current_envt]     # DEV or PROD overrides
    return {**common, **envt}       # envt wins on conflicts

# 5. Get a single config value (cached after first call)
@lru_cache
def get_config(key):
    return get_all_configs().get(key, '').strip("'\"")
```

**Key points:**
- `ENVT` environment variable controls which section is used. Defaults to `DEV`.
- COMMON settings are loaded first, then environment-specific settings override them.
- `get_config()` is cached — once called with a key, it returns the same value forever (within the process lifetime). This means **config changes require restarting the app**.

---

## The ENVT environment variable

This is the single most important setting:

```bash
# For local development
export ENVT=DEV

# In Kubernetes (set in deployment.yml)
env:
  - name: ENVT
    value: DEV    # or PROD
```

| ENVT value | What happens |
|-----------|-------------|
| `DEV` (default) | Uses `[DEV]` section: dev DB, test Razorpay keys, dev LiteLLM |
| `PROD` | Uses `[PROD]` section: production DB, live Razorpay keys, prod LiteLLM |

**Rule: NEVER set ENVT=PROD on your local machine** unless explicitly told to by your team. You could accidentally modify production data.

---

## Every config key explained

### PostgreSQL

| Key | Example (DEV) | Used by |
|-----|--------------|---------|
| `DB_HOST` | `<DB_HOST>` | `db_utils.py`, `database.py` |
| `DB_USER_NAME` | `<DB_USER>` | Connection string |
| `DB_PSWD` | `(password)` | Connection string |
| `DB_NAME` | `<DB_NAME>` | Connection string |

These build the connection URL: `postgresql://USER:PASS@HOST:5432/DBNAME`

### Razorpay

| Key | Example (DEV) | Used by |
|-----|--------------|---------|
| `RAZORPAY_KEY_ID` | `rzp_test_...` | Razorpay SDK client auth |
| `RAZORPAY_KEY_SECRET` | `q3ne7JV...` | HMAC signature verification + SDK auth |
| `RAZORPAY_WEBHOOK_SECRET` | `<REDACTED-WEBHOOK-SECRET>` | Webhook signature verification |
| `SUBSCRIPTION_ADMIN_KEY` | `(generated hex string)` | Admin guard for `POST /subscriptions/plans` |

DEV uses **test** keys (rzp_test_...) — no real money. PROD uses **live** keys (rzp_live_...).

`SUBSCRIPTION_ADMIN_KEY` protects the plan-creation endpoint. Generate with `openssl rand -hex 32`. Use different values for DEV and PROD. Never commit production keys. See [09 — Subscription Dev Guide → Admin Key Runbook](./09-subscription-dev-guide.md) for the full setup procedure.

### LiteLLM

| Key | Example (DEV) | Used by |
|-----|--------------|---------|
| `LITELLM_BASE_URL` | `http://<app>-llm-ctrl-svc...` | `update_litellm_budget()` |
| `LITELLM_TEAM_UPDATE_URL` | `team/update` | Combined with base URL for the API path |
| `LITELLM_MASTER_KEY` | `sk-AZ-0m4e...` | Authorization header for LiteLLM API |

### Auth / Identity

| Key | Example | Used by |
|-----|---------|---------|
| `ASTRA_AUTH_URL` | `https://<dev-backend-host>/astra-auth/user/id-from-token/` | `common_utils.get_user_id_email_from_token()` |
| `TOKEN_VALIDATE_URL` | `https://<dev-backend-host>/astra-auth/auth/decode-token` | `security_utils.decode_token()` |
| `VALIDATE_URL` | (same or similar) | `common_utils.api_key_validation()` |

### Redis

| Key | Example | Used by |
|-----|---------|---------|
| `REDIS_HOST` | `redis://<cache-name>.redis.cache.windows.net` | `redis_utils.py` |
| `REDIS_PORT` | `6380` | Redis connection |
| `REDIS_ACC_KEY` | `(access key)` | Redis authentication |
| `REDIS_ACCESS_TOKEN_EXPIRE_MINUTES` | `100` | Cache TTL for tokens |

### CORS

| Key | Example | Used by |
|-----|---------|---------|
| `CORS_ORIGINS` | `http://localhost:3000,https://<app>.example.com,...` | `main.py` CORS middleware |

Comma-separated list of frontend URLs allowed to call this API.

### Other

| Key | Used by |
|-----|---------|
| `OPENAI_API_KEY` | Not used by payment service directly |
| `AZURE_OPENAI_KEY/ENDPOINT/MODEL` | Not used by payment service directly |
| `AZURE_STORAGE_CONNECTION_STRING` | File upload (not payment-related) |
| `APP_ID`, `PROJECT_NAME` | Log shipping in `log_utils.py` |

---

## DEV vs PROD: what's different

| Aspect | DEV | PROD |
|--------|-----|------|
| DB host | Private IP `<DB_HOST>` | Azure hostname `<DB_AZURE_HOST>...postgres.database.azure.com` |
| DB password | Different | Different |
| Razorpay keys | `rzp_test_...` (test mode, no real charges) | `rzp_live_...` (real money) |
| LiteLLM URL | Kubernetes internal service URL | Different internal URL |
| CORS origins | Includes `localhost`, dev domains | Only production domains |

---

## Local development setup

### Step 1: Set ENVT

```bash
# In your terminal (or add to ~/.zshrc)
export ENVT=DEV
```

### Step 2: Install dependencies

```bash
# Create a virtual environment (recommended)
python3.12 -m venv venv
source venv/bin/activate

# Install packages
pip install -r requirements.txt
```

### Step 3: Ensure network access

The DEV `DB_HOST` is a private IP. You likely need:
- **VPN** connected, OR
- Be on the **office network**

Test: `ping <DB_HOST>` — if it responds, you have access.

### Step 4: Run the app

```bash
uvicorn app.main:app --reload --port 8002
```

### Step 5: Test

Open http://localhost:8002/docs — if you see Swagger UI, the app started. Try GET `/health` — should return `{"status": "ok"}`. Try GET `/payments/packages` — if this works, the app is running correctly (this doesn't need DB).

---

## Adding a new config key

1. Add it to **both** `[DEV]` and `[PROD]` sections in `app/config/app_config.ini`:
```ini
[DEV]
MY_NEW_KEY=dev_value

[PROD]
MY_NEW_KEY=prod_value
```

2. Read it in your code:
```python
from app.utils.config_utils import get_config

my_value = get_config("MY_NEW_KEY")
```

3. Remember: config is cached, so if you change the INI while the app is running, you need to **restart** the app.

---

## Docker and Kubernetes config

### Dockerfile

The Dockerfile copies the INI file as part of `COPY ./app /code/app`. So the container always has the config baked in.

### Kubernetes

Environment variables are set in `deploy/dev/deployment.yml`:
```yaml
env:
  - name: ENVT
    value: DEV
  - name: OPENAI_API_KEY
    value: "sk-proj-..."
```

`ENVT=DEV` tells the app to use the `[DEV]` config section. Additional env vars can override settings if the code checks `os.environ` (currently only `ENVT` does this).

---

## Secrets hygiene

The INI file in this repo contains **real credentials** (DB passwords, API keys). This is common in internal projects but not ideal:

- **Do NOT add new secrets** to the INI if possible
- **Do NOT copy-paste secrets** into Slack, email, or screenshots
- **Do NOT set ENVT=PROD locally** unless specifically instructed
- If you need a secret you don't have, **ask your team lead** rather than hunting through config files
- Future improvement: move secrets to environment variables or a secrets manager (Azure Key Vault, etc.)

---

## Next doc

→ [06 - Adding New Features](./06-adding-new-features.md) — step-by-step guide for adding endpoints, tables, and more
