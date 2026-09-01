# 01 — Project Overview

## What is this service?

**<payment-svc>** is the backend that handles **money and credits** for the <AppName> platform (an AI-powered healthcare assistant built by <Company>). It does three things:

1. **Accepts payments** — users buy "credit packs" via Razorpay (India's payment gateway, like Stripe)
2. **Manages a credit balance** — every user has a credit wallet; credits are added on purchase, deducted when they use AI models
3. **Syncs budgets** — after a purchase, it tells the LiteLLM proxy (the AI gateway) "this user now has X credits available"

It is a **microservice** — it only handles payments/credits. The main <AppName> app, the auth system, and the AI inference are separate services.

---

## Tech stack

| Technology | What it does here |
|-----------|-------------------|
| **Python 3.12** | Language |
| **FastAPI** | Web framework — handles HTTP routes, request validation, OpenAPI docs |
| **Uvicorn** | ASGI server — actually runs the FastAPI app and listens on a port |
| **Gunicorn** | Process manager — spawns multiple uvicorn workers in production |
| **SQLAlchemy** | Database toolkit — creates connection pool and executes raw SQL (no ORM used) |
| **PostgreSQL** | The database — stores orders, credit balances, transaction history |
| **Razorpay SDK** | Python client for Razorpay API — creates orders, processes refunds |
| **Pydantic** | Data validation — defines the shape of every request body and response |
| **httpx** | Async HTTP client — used for calling external services (auth, LiteLLM) |
| **requests** | Sync HTTP client — used in some older code paths |
| **loguru** | Logging library — better than Python's built-in logging |
| **Redis** | In-memory cache — used for rate limiting and token caching (not core to payment flow) |
| **Docker** | Containerization — packages the app for deployment |
| **Kubernetes** | Orchestration — runs the Docker container in dev/prod clusters |

---

## Architecture (how everything connects)

```
                    ┌──────────────┐
                    │   Frontend   │
                    │  (web/app)   │
                    └──────┬───────┘
                           │ HTTP requests
                           ▼
                    ┌──────────────┐
                    │  FastAPI App │  ← this service
                    │  (payment)   │
                    └──┬───┬───┬──┘
                       │   │   │
          ┌────────────┘   │   └────────────┐
          ▼                ▼                 ▼
   ┌─────────────┐  ┌───────────┐   ┌─────────────┐
   │  Razorpay   │  │ PostgreSQL│   │   LiteLLM   │
   │  (payments) │  │ (data)    │   │  (AI proxy) │
   └─────────────┘  └───────────┘   └─────────────┘
                           │
          ┌────────────────┼─────────────────┐
          ▼                ▼                  ▼
   razorpay_orders  api_user_credits  razorpay_credit_
                                      transactions
```

**External systems this service talks to:**

| System | Why | How |
|--------|-----|-----|
| **Razorpay** | Create payment orders, verify payments, process refunds | Razorpay Python SDK + HMAC signature verification |
| **PostgreSQL** | Store orders, credit balances, transaction ledger | SQLAlchemy raw SQL via `db_utils.py` |
| **LiteLLM proxy** | Update user's spending budget after purchase | HTTP POST via `requests` library |
| **Astra Auth** | Validate user tokens, get user_id from JWT | HTTP POST via `httpx` |

---

## How to run the app

There are three ways (all from the project root):

**1. For local development (recommended):**
```bash
# Set environment to DEV
export ENVT=DEV

# Install dependencies
pip install -r requirements.txt

# Run with auto-reload (restarts when you save files)
uvicorn app.main:app --reload --port 8002
```

**2. Using the provided scripts:**
```bash
# Windows
run.bat          # runs: uvicorn app.main:app --reload --port 8002

# Linux/Mac (production-style with gunicorn)
bash run.sh      # runs: gunicorn -w 4 -k uvicorn.workers.UvicornWorker app.main:app
```

**3. Via Docker:**
```bash
docker build -t <payment-svc> .
docker run -p 8080:80 -e ENVT=DEV <payment-svc>
```

After starting, open **http://localhost:8002/docs** in your browser — this is the auto-generated Swagger UI where you can see and test all endpoints.

---

## API endpoints at a glance

Most routes live under the **`/payments`** prefix (one-time packs and credits). The service also exposes **`/subscriptions`** for Razorpay subscription plans and (per [09 — Subscription dev guide](./09-subscription-dev-guide.md)) subscribe, status, cancel, and invoice routes once wired.

**Payments** (`/payments`):

| Method | Path | What it does |
|--------|------|--------------|
| GET | `/payments/packages` | List available credit packages |
| POST | `/payments/orders` | Create a Razorpay order for a credit pack |
| POST | `/payments/verify` | Verify payment after user completes checkout |
| POST | `/payments/webhook` | Razorpay server-to-server notification |
| POST | `/payments/refund` | Refund a payment |
| GET | `/payments/credits` | Get user's credit balance |
| POST | `/payments/credits/deduct` | Deduct credits (called by AI usage layer) |
| POST | `/payments/credits/add` | Manually add credits (admin/promo) |
| GET | `/payments/transactions` | Credit ledger history |
| GET | `/payments/history` | Payment order history |

**Subscriptions** (`/subscriptions`):

| Method | Path | What it does |
|--------|------|--------------|
| GET | `/subscriptions/plans` | List active subscription plans (catalog) |
| POST | `/subscriptions/plans` | Create a plan (admin; `X-Admin-Key`, see doc 09) |
| POST | `/subscriptions/subscribe` | Start a subscription (when implemented; doc 09) |
| GET | `/subscriptions/status` | Current subscription for user (doc 09) |
| POST | `/subscriptions/cancel` | Cancel subscription (doc 09) |
| GET | `/subscriptions/invoices` | Billing history (doc 09) |

**Global:**

| Method | Path | What it does |
|--------|------|--------------|
| GET | `/health` | Health check (returns `{"status": "ok"}`) |

---

## Next doc

→ [02 - Code Architecture](./02-code-architecture.md) — every file explained
