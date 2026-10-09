# 08 · Design Patterns for a Python Backend

**What a design pattern is:** a known, named solution to a problem that keeps coming up. Like a recipe: you don't invent "how to make dal" every time, you follow a recipe and adjust it.

**How to answer any pattern question:** *what problem it solves → simple analogy → where I used it → short code → the trade-off.*

All code is in one tested file: [design_patterns.py](code/design_patterns.py) (`python3 design_patterns.py` runs the tests, and they pass).

**Which patterns to know cold** (you've used these in real work): Repository, Dependency Injection, Strategy, Factory, Adapter, State machine, Facade/Gateway, Chain of responsibility (middleware). The rest are good to recognise.

---

## Quick map: the three families

| Family | What it's about | Patterns here |
|---|---|---|
| **Creational** | How objects get *created* | Factory, Singleton, (Builder) |
| **Structural** | How objects are *connected* | Adapter, Decorator, Facade, Proxy, Repository |
| **Behavioural** | How objects *talk and decide* | Strategy, Observer, State, Chain of responsibility, Command |
| **Backend / architecture** | How a service is *organised and stays reliable* | Service layer, DI, Unit of Work, Circuit breaker, Outbox, Saga |

---

## P1 · Repository

**Problem:** SQL scattered everywhere makes code hard to read, test and change.
**Analogy:** a librarian. You ask "get me this book"; you don't care which shelf it's on.
**What it is:** a class that hides *how* data is stored behind simple methods like `get`, `add` and `list_by_status`.

```python
class LeadRepository(Protocol):
    async def get(self, tenant_id: int, lead_id: int) -> Lead | None: ...
    async def add(self, lead: Lead) -> None: ...

class PostgresLeadRepository:
    def __init__(self, conn): self.conn = conn
    async def get(self, tenant_id, lead_id):
        row = await self.conn.fetchrow(
            "SELECT * FROM leads WHERE tenant_id = $1 AND id = $2", tenant_id, lead_id)
        return Lead(**row) if row else None
```

**Say this:**
> "I use the repository pattern in all my FastAPI services. Each table has a repository class that holds the SQL. Services only call methods like `get` or `add`. Two benefits: the business code reads cleanly, and in tests I pass an in-memory repository instead of a real database. It's also where I enforce the tenant filter, so every query includes `tenant_id`."

**Follow-ups:**
- *"Isn't that just extra code?"* → "For a tiny app, yes. Once there are many queries and tests, it pays off. I keep repositories thin: SQL in, objects out, no business rules."
- *"Repository vs ORM?"* → "An ORM maps tables to objects. A repository is a boundary around data access. You can use a repository *with* an ORM, or with raw SQL like I do with asyncpg."

---

## P2 · Dependency Injection (DI)

**Problem:** a class that creates its own database connection or email client can't be tested or reconfigured.
**Analogy:** a chef who is *handed* ingredients instead of growing them. Swap the supplier, and the chef doesn't change.
**What it is:** give a class the things it needs (through its constructor or a framework) instead of letting it build them.

```python
class LeadService:
    def __init__(self, repo: LeadRepository, notifier: Notifier):   # handed in
        self.repo, self.notifier = repo, notifier

# FastAPI does the wiring with Depends
def get_lead_service(conn = Depends(get_conn)) -> LeadService:
    return LeadService(PostgresLeadRepository(conn), EmailNotifier())

@router.post("/leads/{lead_id}/contacted")
async def mark(lead_id: int, user = Depends(get_current_user), svc = Depends(get_lead_service)):
    return await svc.mark_contacted(user.tenant_id, lead_id)
```

**Say this:**
> "In FastAPI, `Depends` is dependency injection. The endpoint declares what it needs, like a DB connection, the current user or a service, and FastAPI builds and passes it in. My services take their repositories through the constructor, so tests pass fakes. It's the same idea as GetIt in my Flutter apps."

**Follow-ups:**
- *"How do you test it?"* → "`app.dependency_overrides[get_lead_service] = lambda: LeadService(FakeRepo(), FakeNotifier())`."
- *"Which SOLID principle is this?"* → "**Dependency Inversion**: depend on an interface (`Notifier`), not a concrete class (`EmailNotifier`)."

---

## P3 · Service layer

**Problem:** business rules hidden inside route handlers can't be reused by background workers or scripts.
**What it is:** a layer of plain classes that hold the business rules. Routes only parse the request, call the service and return the response.

```
router (HTTP only) → service (business rules) → repository (SQL) → database
```

**Say this:**
> "My routes are thin: parse, call the service, return a schema. Services never import FastAPI, so a queue worker can call the same `LeadService.mark_contacted` as the API. Services raise domain errors like `NotFoundError`, and an exception handler turns them into HTTP status codes."

---

## P4 · Strategy

**Problem:** a big `if/elif` that picks *how* to do something (email vs SMS vs WhatsApp, or Razorpay vs Stripe) grows forever.
**Analogy:** Google Maps lets you choose car, bike or walk. Same goal, a different way of getting there.
**What it is:** several classes with **the same method**, swapped in at runtime.

```python
class Notifier(ABC):
    @abstractmethod
    async def send(self, to: str, message: str) -> None: ...

class EmailNotifier(Notifier):
    async def send(self, to, message): ...   # SES / SendGrid

class SmsNotifier(Notifier):
    async def send(self, to, message): ...   # SMS provider

async def notify(notifier: Notifier, to, msg):
    await notifier.send(to, msg)             # doesn't care which one
```

**Say this:**
> "For notifications, every channel implements one `send` method. The calling code works with any of them. Adding WhatsApp means adding one class, without touching existing code. That's the **Open/Closed principle**."

**Follow-ups:**
- *"Strategy vs if/else?"* → "Two simple cases: if/else is fine. Many cases, or ones that change often, or each needing its own config and tests: Strategy."
- *"Strategy vs State?"* → "Strategy is chosen **from outside** (the caller picks email or SMS). State changes **itself** based on what happens (created → active → cancelled)."

---

## P5 · Factory

**Problem:** code that creates objects (`if channel == 'sms': SmsNotifier()…`) gets copied everywhere.
**Analogy:** a restaurant counter. You say "one masala dosa"; the kitchen decides how to make it.
**What it is:** one function or class that decides **which** object to create.

```python
_NOTIFIERS = {"email": EmailNotifier, "sms": SmsNotifier, "whatsapp": WhatsAppNotifier}

def notifier_factory(channel: str) -> Notifier:
    try:
        return _NOTIFIERS[channel]()
    except KeyError:
        raise ValueError(f"unknown channel: {channel}") from None

notifier = notifier_factory(institution.preferred_channel)   # read from tenant settings
```

**Say this:**
> "A factory keeps object creation in one place. Combined with Strategy: the factory picks *which* notifier based on the institution's settings, and the rest of the code just calls `send`."

**Follow-up:** *"Factory vs constructor?"* → "Use a factory when the caller shouldn't know which class it gets, or when creation needs logic or config."

---

## P6 · Adapter

**Problem:** a third-party SDK has different method names and data shapes from your code.
**Analogy:** a travel plug adapter. Your charger stays the same; the adapter makes it fit the foreign socket.
**What it is:** a wrapper that makes an outside API look like **your** interface.

```python
class ThirdPartyMailClient:                       # vendor SDK
    def deliver_mail(self, recipient, subject, html_body): ...

class VendorEmailAdapter(Notifier):
    def __init__(self, client: ThirdPartyMailClient):
        self.client = client
    async def send(self, to, message):
        await asyncio.to_thread(self.client.deliver_mail, to, "Headstart update", f"<p>{message}</p>")
```

**Say this:**
> "Every external provider I integrate goes behind an adapter: Razorpay, the email provider, storage like R2. The rest of the code talks to our interface. When we moved document storage from Postgres to Cloudflare R2, only the storage adapter changed. Bonus: the vendor's sync SDK is wrapped with `to_thread`, so it doesn't block the event loop."

**Follow-up:** *"Adapter vs Facade?"* → "Adapter **changes the shape** of one interface to match yours. Facade **simplifies** many services behind one entry point."

---

## P7 · Facade / API Gateway (your Vaidya Insurance layer)

**Problem:** clients would need to call five services in the right order with the right auth.
**Analogy:** a hotel reception desk. You ask one person; they coordinate housekeeping, kitchen and billing.
**What it is:** one simple entry point in front of a complicated system.

```python
class ClaimsGateway:
    def __init__(self, ocr: OcrService, risk: RiskModel):
        self.ocr, self.risk = ocr, risk

    async def assess_claim(self, user_id: str, doc: str) -> dict:
        if not user_id:
            raise PermissionError("not authenticated")
        text = await self.ocr.extract(doc)
        score = await self.risk.score(text)
        return {"decision": "approve" if score < 0.5 else "review", "score": score}
```

**Say this:**
> "On Vaidya Insurance I built exactly this: the layer between the app and the AI services. The app makes one call; my layer checks auth, validates input, calls the AI services, handles their errors and returns one clean response. The app never talks to the AI services directly, so they can change without breaking the app."

[fill: check the example matches what your gateway actually calls]

**Follow-up:** *"Isn't a gateway a single point of failure?"* → "Yes, so it must be stateless and run as several instances behind a load balancer, with timeouts and circuit breakers to the services behind it."

---

## P8 · Singleton

**Problem:** some things should exist **once** per process: settings, the DB pool, an HTTP client.
**What it is:** only one instance ever gets created.

**The Pythonic way** (not the Java-style class with a private constructor):
```python
@functools.lru_cache                 # first call creates it, later calls return the same object
def get_settings() -> Settings:
    return Settings()

# or: create once in FastAPI's lifespan and store on app.state
@asynccontextmanager
async def lifespan(app):
    app.state.pool = await asyncpg.create_pool(...)
    yield
    await app.state.pool.close()
```

**Say this:**
> "In Python, a module is already a singleton, so I rarely write a Singleton class. For settings I use `lru_cache` on `get_settings()`. For the DB pool and HTTP client, I create them once in FastAPI's lifespan and store them on `app.state`."

**Follow-ups (they like this one):**
- *"Why is Singleton often called an anti-pattern?"* → "It's hidden global state. It makes tests share state, makes dependencies invisible, and makes it hard to swap implementations. That's why I inject the instance through `Depends` instead of importing a global."
- *"Is it 'one per app'?"* → "One per **process**. With 4 Uvicorn workers there are 4 pools, which matters for database connection limits."

---

## P9 · Decorator pattern (and Python decorators)

**Problem:** you want to add retries, logging or caching to something without changing it.
**Analogy:** a phone case. The phone is the same; the case adds protection.
**What it is:** wrap an object with another object that has **the same interface** and adds behaviour.

```python
class RetryingNotifier(Notifier):
    def __init__(self, inner: Notifier, attempts: int = 3):
        self.inner, self.attempts = inner, attempts
    async def send(self, to, message):
        for attempt in range(1, self.attempts + 1):
            try:
                return await self.inner.send(to, message)
            except ConnectionError:
                if attempt == self.attempts:
                    raise

notifier = RetryingNotifier(EmailNotifier())   # still a Notifier, now with retries
```

**Say this:**
> "The decorator pattern wraps an object to add behaviour while keeping the same interface. Python's `@decorator` syntax is the same idea applied to functions: `@lru_cache`, a timing decorator, a retry decorator."

**Follow-up:** *"Decorator vs inheritance?"* → "Inheritance fixes the behaviour at class level. Decorators stack at runtime: `RetryingNotifier(LoggingNotifier(EmailNotifier()))`. No class explosion."

---

## P10 · Observer / Pub-Sub

**Problem:** when a lead is created, you need an audit log, a welcome email and an analytics event. Calling all three from the create function couples everything.
**Analogy:** a YouTube subscription. The creator uploads once; every subscriber is notified.
**What it is:** publish an event; any number of listeners react, and the publisher doesn't know who they are.

```python
class EventBus:
    def __init__(self): self._handlers = {}
    def subscribe(self, event, handler): self._handlers.setdefault(event, []).append(handler)
    async def publish(self, event, payload):
        for handler in self._handlers.get(event, []):
            await handler(payload)

bus.subscribe("lead.created", write_audit_log)
bus.subscribe("lead.created", send_welcome_email)
await bus.publish("lead.created", {"id": lead.id, "tenant_id": tid})
```

**Say this:**
> "The publisher just announces 'lead created'. Listeners decide what to do. Adding a new reaction means adding a listener, not editing the create function. In-process this is a simple event bus; across services it's **Redis pub/sub** or a message queue. I use Redis pub/sub for pushing live updates to WebSocket clients on different servers."

**Follow-ups:**
- *"Downside?"* → "It's harder to follow the flow, and errors in one listener can be missed. For anything important, put the event on a durable queue instead of in-memory listeners."
- *"Django signals?"* → "They're the Observer pattern built into Django. I haven't used Django, but the trade-offs are the same: decoupled, but hidden and synchronous."

---

## P11 · State machine (your Razorpay fix)

**Problem:** webhooks arrive late, twice or out of order, and could move a subscription backwards (cancelled → active).
**Analogy:** a train ticket: booked → boarded → completed. You can't go from completed back to booked.
**What it is:** an object whose status can only change along allowed paths.

```python
ALLOWED = {
    "created":   {"active", "cancelled"},
    "active":    {"halted", "cancelled"},
    "halted":    {"active", "cancelled"},
    "cancelled": set(),                      # final
}

def transition(sub, new_status) -> bool:
    if new_status == sub.status or new_status not in ALLOWED[sub.status]:
        return False                         # duplicate or invalid: ignore safely
    sub.status = new_status
    return True
```

In the database, make the change atomic so two webhooks can't race:
```sql
UPDATE subscriptions SET status = $1
WHERE id = $2 AND status = ANY($3);        -- $3 = statuses allowed to move to $1
```

**Say this:**
> "I used a state machine in Postgres for Razorpay subscriptions. Each status only allows certain next statuses, so a late or repeated webhook can't move a cancelled subscription back to active. The update checks the current status in the same statement, so two webhooks can't race. With HMAC verification and a reconciliation job, subscription state stayed correct."

**Follow-up:** *"Where else?"* → "Orders, bookings (available → held → booked), imports (queued → running → done/failed), lead stages in a CRM."

---

## P12 · Chain of Responsibility (how middleware works)

**Problem:** many checks (auth, tenant, rate limit, logging) on every request, in a specific order.
**Analogy:** airport security. Each counter checks one thing and passes you on, or stops you.
**What it is:** each handler does one job, then calls the next, or stops the chain.

```python
async def auth_mw(req, next_):
    if req.get("token") != "valid":
        return {"status": 401}               # stop the chain
    return await next_(req)

async def tenant_mw(req, next_):
    req["tenant_id"] = 42
    return await next_(req)

chain = build_chain([auth_mw, tenant_mw], leads_endpoint)
```

**Say this:**
> "FastAPI middleware is chain of responsibility: each layer can handle or reject the request, or pass it on with `call_next`. Order matters: the last middleware added runs first. Python's `logging` handlers and exception handler lookup work the same way."

---

## P13 · Command (queue tasks)

**Problem:** you need to run work later, retry it, or run it on another machine.
**Analogy:** a restaurant order slip. The waiter writes it down; any cook can pick it up later.
**What it is:** package a request as an object with all the data needed to run it.

```python
@dataclass(frozen=True)
class SendCampaignBatch:
    campaign_id: int
    recipient_ids: tuple[int, ...]
    idempotency_key: str          # so running it twice is safe
```

**Say this:**
> "Every queue task is a command: a small, serialisable object, usually just ids, that a worker can execute later. I add an idempotency key, so if the queue delivers it twice, the second run is skipped."

---

## P14 · Unit of Work

**Problem:** a business action changes several rows (debit one wallet, credit another). Half-done is a disaster.
**Analogy:** a bank transfer. Money leaves A *and* reaches B, or nothing happens.
**What it is:** all changes in one business action are committed together, or rolled back together.

```python
async def transfer(pool, src, dst, amount):
    async with pool.acquire() as conn:
        async with conn.transaction():       # commit if no error, rollback if any error
            ok = await conn.execute(
                "UPDATE wallets SET balance = balance - $1 WHERE user_id = $2 AND balance >= $1",
                amount, src)
            if ok == "UPDATE 0":
                raise InsufficientCredits()
            await conn.execute("UPDATE wallets SET balance = balance + $1 WHERE user_id = $2",
                               amount, dst)
```

**Say this:**
> "One transaction per business action, in the service layer. With asyncpg that's `async with conn.transaction()`; with SQLAlchemy it's the session. If anything fails, nothing is half-applied."

---

## P15 · Circuit Breaker + Retry (resilience)

**Problem:** a slow external service (an AI API, a payment provider) makes every request hang and pile up.
**Analogy:** the electrical fuse at home. When something's wrong, it cuts off so the whole house doesn't burn.
**What it is:** after N failures, stop calling the service for a while and **fail fast**. Then try one call to see if it has recovered.

```
CLOSED (normal) --N failures--> OPEN (fail fast) --wait--> HALF-OPEN (one trial) --ok--> CLOSED
```

**Say this:**
> "For external calls I use timeouts, retries with backoff for temporary errors, and a circuit breaker. If the AI service keeps failing, we stop hammering it, return a clear error or fallback straight away, and try again after a cool-down. That protects our own workers and connection pool from piling up."

**Follow-up:** *"Retry dangers?"* → "Retrying a non-idempotent call can double-charge. Retry only safe or idempotent operations, use exponential backoff with jitter, and cap the attempts."

---

## P16 · Distributed patterns: Outbox, Idempotency key, Saga (name them, short answers)

| Pattern | Problem | One-line answer |
|---|---|---|
| **Outbox** | Save to DB *and* publish an event; one can fail | Write the event to an `outbox` table **in the same transaction**; a relay publishes it later and retries until it succeeds |
| **Idempotency key** | Client retries a payment or create request | Client sends a unique key; server stores the result per key and returns the same result on a retry (your client-generated UUIDs in Recurring) |
| **Saga** | A business flow spans several services, so no single DB transaction | Sequence of local steps, each with a **compensating action** to undo it (charge → book seat; if booking fails → refund) |
| **CQRS** | Reads and writes have very different needs | Separate models or stores for writing and reading, like summary tables for reports. Only when it's worth the complexity |
| **Rate limiter (token bucket)** | Protect APIs and providers from too many calls | Each key gets tokens that refill at a fixed rate; a request spends one; no token → 429 |

---

## SOLID in one table (often asked with patterns)

| Letter | Meaning in plain words | Pattern / your example |
|---|---|---|
| **S** Single responsibility | A class has one reason to change | Router / service / repository split |
| **O** Open/closed | Add new behaviour without editing old code | Strategy: add a WhatsAppNotifier class |
| **L** Liskov substitution | A child class can replace its parent without surprises | Any `Notifier` works wherever `Notifier` is expected |
| **I** Interface segregation | Small, focused interfaces | `Notifier` has only `send`, not 15 methods |
| **D** Dependency inversion | Depend on interfaces, not concrete classes | Service takes `LeadRepository`, gets Postgres or fake |

---

## Rapid-fire

| Question | Answer |
|---|---|
| Which patterns have you actually used? | Repository, DI (`Depends`), service layer, Strategy + Factory for providers, Adapter for Razorpay/R2, state machine for subscriptions, Facade for the insurance gateway, middleware as chain of responsibility |
| Pattern you'd avoid? | Singleton as a global class: hidden state, hard to test. Inject instead |
| Overusing patterns? | Yes, it's a real risk. Add a pattern when the problem appears (third provider, second implementation), not "just in case" |
| Composition vs inheritance? | Prefer composition: build behaviour from small parts (decorators, injected strategies) over deep class trees |
| Builder? | Step-by-step construction of complex objects, like a query builder. Pydantic models and keyword arguments cover most cases in Python |
| Proxy? | A stand-in that controls access: caching proxy, lazy loading, permission checks. Nginx in front of the API is a reverse proxy |
| Template method? | A base class defines the steps, and subclasses fill in some steps. An importer base with `parse_row` overridden per file type |
