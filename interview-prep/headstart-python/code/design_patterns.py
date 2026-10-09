"""
Design patterns for a Python backend, in one runnable file.
Each section matches a question in 08-design-patterns.md.
Run: python3 design_patterns.py   (runs the self-tests at the bottom)
"""
from __future__ import annotations

import asyncio
import functools
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Awaitable, Callable, Protocol


# ---------------------------------------------------------------------------
# 1. Repository: hide how data is stored behind a class with clear methods
# ---------------------------------------------------------------------------
@dataclass
class Lead:
    id: int
    tenant_id: int
    email: str
    status: str = "new"


class LeadRepository(Protocol):
    async def get(self, tenant_id: int, lead_id: int) -> Lead | None: ...
    async def add(self, lead: Lead) -> None: ...


class InMemoryLeadRepository:                # used in tests; a PostgresLeadRepository would run SQL
    def __init__(self) -> None:
        self._rows: dict[tuple[int, int], Lead] = {}

    async def get(self, tenant_id: int, lead_id: int) -> Lead | None:
        return self._rows.get((tenant_id, lead_id))

    async def add(self, lead: Lead) -> None:
        self._rows[(lead.tenant_id, lead.id)] = lead


# ---------------------------------------------------------------------------
# 2. Service layer + Dependency Injection: business rules get their tools passed in
# ---------------------------------------------------------------------------
class NotFoundError(Exception):
    pass


class LeadService:
    def __init__(self, repo: LeadRepository, notifier: "Notifier") -> None:   # injected, not created here
        self.repo = repo
        self.notifier = notifier

    async def mark_contacted(self, tenant_id: int, lead_id: int) -> Lead:
        lead = await self.repo.get(tenant_id, lead_id)
        if lead is None:
            raise NotFoundError("lead not found")
        lead.status = "contacted"
        await self.repo.add(lead)
        await self.notifier.send(lead.email, "Thanks, a counsellor will call you soon.")
        return lead


# ---------------------------------------------------------------------------
# 3. Strategy: same job, swappable ways of doing it
# 4. Factory: one place that decides which class to create
# ---------------------------------------------------------------------------
class Notifier(ABC):
    @abstractmethod
    async def send(self, to: str, message: str) -> None: ...


class EmailNotifier(Notifier):
    def __init__(self) -> None:
        self.sent: list[tuple[str, str]] = []

    async def send(self, to: str, message: str) -> None:
        self.sent.append((to, message))


class SmsNotifier(Notifier):
    def __init__(self) -> None:
        self.sent: list[tuple[str, str]] = []

    async def send(self, to: str, message: str) -> None:
        self.sent.append((to, message))


class WhatsAppNotifier(SmsNotifier):
    pass


_NOTIFIERS: dict[str, type[Notifier]] = {
    "email": EmailNotifier,
    "sms": SmsNotifier,
    "whatsapp": WhatsAppNotifier,
}


def notifier_factory(channel: str) -> Notifier:
    try:
        return _NOTIFIERS[channel]()
    except KeyError:
        raise ValueError(f"unknown channel: {channel}") from None


# ---------------------------------------------------------------------------
# 5. Adapter: make a third-party API look like our interface
# ---------------------------------------------------------------------------
class ThirdPartyMailClient:                    # imagine this is a vendor SDK with its own method names
    def __init__(self) -> None:
        self.outbox: list[dict] = []

    def deliver_mail(self, recipient: str, subject: str, html_body: str) -> dict:
        self.outbox.append({"recipient": recipient, "subject": subject, "body": html_body})
        return {"status": "queued"}


class VendorEmailAdapter(Notifier):
    def __init__(self, client: ThirdPartyMailClient) -> None:
        self.client = client

    async def send(self, to: str, message: str) -> None:
        # translate our simple call into the vendor's shape
        await asyncio.to_thread(self.client.deliver_mail, to, "Headstart update", f"<p>{message}</p>")


# ---------------------------------------------------------------------------
# 6. Singleton (the Pythonic way): one shared instance per process
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Settings:
    db_url: str = "postgresql://localhost/app"
    jwt_ttl_minutes: int = 15


@functools.lru_cache                            # first call creates it, later calls return the same object
def get_settings() -> Settings:
    return Settings()


# ---------------------------------------------------------------------------
# 7. Decorator pattern: wrap an object to add behaviour, same interface
# ---------------------------------------------------------------------------
class RetryingNotifier(Notifier):
    def __init__(self, inner: Notifier, attempts: int = 3) -> None:
        self.inner = inner
        self.attempts = attempts

    async def send(self, to: str, message: str) -> None:
        for attempt in range(1, self.attempts + 1):
            try:
                return await self.inner.send(to, message)
            except ConnectionError:
                if attempt == self.attempts:
                    raise


class FlakyNotifier(Notifier):                  # fails twice, then works (for the test)
    def __init__(self) -> None:
        self.calls = 0

    async def send(self, to: str, message: str) -> None:
        self.calls += 1
        if self.calls < 3:
            raise ConnectionError("provider timeout")


# ---------------------------------------------------------------------------
# 8. Observer / pub-sub: publish an event, many listeners react
# ---------------------------------------------------------------------------
Handler = Callable[[dict], Awaitable[None]]


class EventBus:
    def __init__(self) -> None:
        self._handlers: dict[str, list[Handler]] = {}

    def subscribe(self, event: str, handler: Handler) -> None:
        self._handlers.setdefault(event, []).append(handler)

    async def publish(self, event: str, payload: dict) -> None:
        for handler in self._handlers.get(event, []):
            await handler(payload)


# ---------------------------------------------------------------------------
# 9. State machine: only allow valid status changes (your Razorpay webhook fix)
# ---------------------------------------------------------------------------
class SubStatus(str, Enum):
    CREATED = "created"
    ACTIVE = "active"
    HALTED = "halted"
    CANCELLED = "cancelled"


ALLOWED: dict[SubStatus, set[SubStatus]] = {
    SubStatus.CREATED: {SubStatus.ACTIVE, SubStatus.CANCELLED},
    SubStatus.ACTIVE: {SubStatus.HALTED, SubStatus.CANCELLED},
    SubStatus.HALTED: {SubStatus.ACTIVE, SubStatus.CANCELLED},
    SubStatus.CANCELLED: set(),                 # final state: nothing moves out of it
}


@dataclass
class Subscription:
    id: str
    status: SubStatus = SubStatus.CREATED

    def transition(self, new: SubStatus) -> bool:
        if new == self.status:
            return False                        # duplicate event: ignore
        if new not in ALLOWED[self.status]:
            return False                        # late or out-of-order event: ignore
        self.status = new
        return True


# ---------------------------------------------------------------------------
# 10. Chain of responsibility: each handler does one check, then passes it on
#     (this is exactly how middleware works)
# ---------------------------------------------------------------------------
Request = dict
Next = Callable[[Request], Awaitable[dict]]
Middleware = Callable[[Request, Next], Awaitable[dict]]


def build_chain(middlewares: list[Middleware], endpoint: Next) -> Next:
    handler = endpoint
    for mw in reversed(middlewares):            # wrap from the inside out
        handler = functools.partial(mw, next_=handler)
    return handler


async def auth_mw(req: Request, next_: Next) -> dict:
    if req.get("token") != "valid":
        return {"status": 401}
    return await next_(req)


async def tenant_mw(req: Request, next_: Next) -> dict:
    req["tenant_id"] = 42                      # pretend we read it from the token
    return await next_(req)


async def leads_endpoint(req: Request) -> dict:
    return {"status": 200, "tenant_id": req["tenant_id"]}


# ---------------------------------------------------------------------------
# 11. Command: package a request as an object (queue tasks are commands)
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class SendCampaignBatch:
    campaign_id: int
    recipient_ids: tuple[int, ...]
    idempotency_key: str


class CommandQueue:
    def __init__(self) -> None:
        self.items: list[SendCampaignBatch] = []
        self.done: set[str] = set()

    def enqueue(self, cmd: SendCampaignBatch) -> None:
        self.items.append(cmd)

    async def work(self, handle: Callable[[SendCampaignBatch], Awaitable[None]]) -> None:
        while self.items:
            cmd = self.items.pop(0)
            if cmd.idempotency_key in self.done:   # same command twice: skip
                continue
            await handle(cmd)
            self.done.add(cmd.idempotency_key)


# ---------------------------------------------------------------------------
# 12. Unit of Work: all writes in one business action succeed or none do
# ---------------------------------------------------------------------------
class FakeDB:
    def __init__(self) -> None:
        self.committed: dict[str, int] = {"wallet:u1": 100, "wallet:u2": 0}


class UnitOfWork:
    def __init__(self, db: FakeDB) -> None:
        self.db = db
        self.pending: dict[str, int] = {}

    async def __aenter__(self) -> "UnitOfWork":
        self.pending = dict(self.db.committed)  # work on a copy
        return self

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        if exc_type is None:
            self.db.committed = self.pending    # commit
        return False                            # on error: drop changes (rollback) and re-raise


async def transfer(db: FakeDB, src: str, dst: str, amount: int) -> None:
    async with UnitOfWork(db) as uow:
        if uow.pending[src] < amount:
            raise ValueError("insufficient balance")
        uow.pending[src] -= amount
        uow.pending[dst] += amount


# ---------------------------------------------------------------------------
# 13. Facade / Gateway: one simple entry point in front of many services
#     (your Vaidya Insurance layer between the app and the AI services)
# ---------------------------------------------------------------------------
class OcrService:
    async def extract(self, doc: str) -> str:
        return f"text-of-{doc}"


class RiskModel:
    async def score(self, text: str) -> float:
        return 0.2


class ClaimsGateway:
    def __init__(self, ocr: OcrService, risk: RiskModel) -> None:
        self.ocr, self.risk = ocr, risk

    async def assess_claim(self, user_id: str, doc: str) -> dict:
        if not user_id:
            raise PermissionError("not authenticated")
        text = await self.ocr.extract(doc)
        score = await self.risk.score(text)
        return {"decision": "approve" if score < 0.5 else "review", "score": score}


# ---------------------------------------------------------------------------
# 14. Circuit breaker: stop calling a failing service for a while
# ---------------------------------------------------------------------------
class CircuitOpenError(Exception):
    pass


@dataclass
class CircuitBreaker:
    max_failures: int = 3
    reset_after: float = 30.0
    failures: int = 0
    opened_at: float | None = None
    clock: Callable[[], float] = field(default=time.monotonic)

    async def call(self, fn: Callable[[], Awaitable[str]]) -> str:
        if self.opened_at is not None:
            if self.clock() - self.opened_at < self.reset_after:
                raise CircuitOpenError("service is down, failing fast")
            self.opened_at = None               # half-open: allow one trial call
        try:
            result = await fn()
        except Exception:
            self.failures += 1
            if self.failures >= self.max_failures:
                self.opened_at = self.clock()
            raise
        self.failures = 0
        return result


# ---------------------------------------------------------------------------
# Self-tests
# ---------------------------------------------------------------------------
async def _tests() -> None:
    # Repository + Service + DI
    repo = InMemoryLeadRepository()
    email = EmailNotifier()
    await repo.add(Lead(id=1, tenant_id=7, email="a@x.com"))
    svc = LeadService(repo, email)
    assert (await svc.mark_contacted(7, 1)).status == "contacted"
    assert email.sent == [("a@x.com", "Thanks, a counsellor will call you soon.")]
    try:
        await svc.mark_contacted(8, 1)                       # other tenant can't see it
        raise AssertionError
    except NotFoundError:
        pass

    # Strategy + Factory
    assert isinstance(notifier_factory("sms"), SmsNotifier)
    assert isinstance(notifier_factory("whatsapp"), WhatsAppNotifier)
    try:
        notifier_factory("fax")
        raise AssertionError
    except ValueError:
        pass

    # Adapter
    vendor = ThirdPartyMailClient()
    await VendorEmailAdapter(vendor).send("b@x.com", "Hi")
    assert vendor.outbox[0]["body"] == "<p>Hi</p>"

    # Singleton
    assert get_settings() is get_settings()

    # Decorator pattern
    flaky = FlakyNotifier()
    await RetryingNotifier(flaky, attempts=3).send("c@x.com", "Hi")
    assert flaky.calls == 3

    # Observer
    bus, seen = EventBus(), []
    async def audit(p): seen.append(("audit", p["id"]))
    async def welcome(p): seen.append(("welcome", p["id"]))
    bus.subscribe("lead.created", audit)
    bus.subscribe("lead.created", welcome)
    await bus.publish("lead.created", {"id": 5})
    assert seen == [("audit", 5), ("welcome", 5)]

    # State machine
    sub = Subscription("sub_1")
    assert sub.transition(SubStatus.ACTIVE)
    assert not sub.transition(SubStatus.ACTIVE)            # duplicate webhook
    assert sub.transition(SubStatus.CANCELLED)
    assert not sub.transition(SubStatus.ACTIVE)            # late webhook can't revive it
    assert sub.status == SubStatus.CANCELLED

    # Chain of responsibility
    chain = build_chain([auth_mw, tenant_mw], leads_endpoint)
    assert await chain({"token": "bad"}) == {"status": 401}
    assert await chain({"token": "valid"}) == {"status": 200, "tenant_id": 42}

    # Command + idempotency
    q, handled = CommandQueue(), []
    cmd = SendCampaignBatch(1, (10, 11), "camp1-batch0")
    q.enqueue(cmd); q.enqueue(cmd)
    async def handle(c): handled.append(c.idempotency_key)
    await q.work(handle)
    assert handled == ["camp1-batch0"]

    # Unit of Work
    db = FakeDB()
    await transfer(db, "wallet:u1", "wallet:u2", 30)
    assert db.committed == {"wallet:u1": 70, "wallet:u2": 30}
    try:
        await transfer(db, "wallet:u2", "wallet:u1", 999)
    except ValueError:
        pass
    assert db.committed == {"wallet:u1": 70, "wallet:u2": 30}   # nothing half-applied

    # Facade
    out = await ClaimsGateway(OcrService(), RiskModel()).assess_claim("u1", "claim.pdf")
    assert out == {"decision": "approve", "score": 0.2}

    # Circuit breaker
    now = [0.0]
    cb = CircuitBreaker(max_failures=2, reset_after=10, clock=lambda: now[0])
    async def down(): raise ConnectionError
    async def up(): return "ok"
    for _ in range(2):
        try:
            await cb.call(down)
        except ConnectionError:
            pass
    try:
        await cb.call(up)                                   # open: fails fast without calling
        raise AssertionError
    except CircuitOpenError:
        pass
    now[0] = 11
    assert await cb.call(up) == "ok"                       # after the wait, it recovers

    print("All design pattern tests passed")


if __name__ == "__main__":
    asyncio.run(_tests())
