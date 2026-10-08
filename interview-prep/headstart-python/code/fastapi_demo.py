"""
One-file FastAPI demo of the patterns interviewers ask about.
In a real project each section is its own module (routers / schemas / services / repositories).

Run tests:  pip install fastapi httpx pyjwt && python3 fastapi_demo.py
Run server: uvicorn fastapi_demo:app --reload   (then open /docs)
"""
import asyncio
import logging
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from enum import Enum

import jwt
from fastapi import APIRouter, BackgroundTasks, Depends, FastAPI, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, field_validator

log = logging.getLogger("demo")
SECRET = "demo-secret-at-least-32-bytes-long!!"   # real app: env var / secrets manager
ALGO = "HS256"


# ---------- Domain errors (no HTTP knowledge) ----------
class AppError(Exception):
    status_code = 500
    code = "internal_error"

    def __init__(self, message: str = "Something went wrong"):
        self.message = message


class NotFoundError(AppError):
    status_code, code = 404, "not_found"


class ConflictError(AppError):
    status_code, code = 409, "conflict"


# ---------- Schemas (Pydantic v2) ----------
class Role(str, Enum):
    admin = "admin"
    counsellor = "counsellor"


class LeadCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    email: str
    phone: str | None = None

    @field_validator("email")
    @classmethod
    def normalise_email(cls, v: str) -> str:
        if "@" not in v:
            raise ValueError("invalid email")
        return v.strip().lower()


class LeadOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    name: str
    email: str
    phone: str | None = None


class LeadOutV2(LeadOut):       # additive change: v2 adds a field, v1 untouched
    source: str | None = None


class Page(BaseModel):
    items: list[LeadOut]
    next_cursor: str | None


class JobOut(BaseModel):
    job_id: str
    status: str
    progress: int = 0


# ---------- Repository (data layer; swap for asyncpg in real life) ----------
class LeadRepository:
    def __init__(self):
        self._rows: dict[tuple[str, str], dict] = {}     # (tenant_id, lead_id) -> row

    async def create(self, tenant_id: str, data: LeadCreate) -> dict:
        if any(t == tenant_id and r["email"] == data.email for (t, _), r in self._rows.items()):
            raise ConflictError("Lead with this email already exists")   # UNIQUE(tenant_id, email)
        row = {"id": str(uuid.uuid4()), "tenant_id": tenant_id, "source": "web", **data.model_dump()}
        self._rows[(tenant_id, row["id"])] = row
        return row

    async def get(self, tenant_id: str, lead_id: str) -> dict:
        row = self._rows.get((tenant_id, lead_id))       # tenant always part of the lookup
        if not row:
            raise NotFoundError("Lead not found")        # 404 even if it exists for another tenant
        return row

    async def list(self, tenant_id: str, after: str | None, limit: int) -> list[dict]:
        rows = sorted((r for (t, _), r in self._rows.items() if t == tenant_id), key=lambda r: r["id"])
        if after:
            rows = [r for r in rows if r["id"] > after]  # keyset pagination: WHERE id > :after
        return rows[:limit]


class JobStore:
    def __init__(self):
        self.jobs: dict[str, dict] = {}


# ---------- Lifespan: create shared resources once ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.leads = LeadRepository()       # real app: asyncpg.create_pool(...)
    app.state.jobs = JobStore()
    yield
    # real app: await pool.close()


app = FastAPI(title="Headstart-style CRM demo", lifespan=lifespan)


# ---------- Middleware: request id + timing ----------
@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    request.state.request_id = request_id
    start = time.perf_counter()
    response = await call_next(request)
    response.headers["x-request-id"] = request_id
    log.info("%s %s %s %.1fms", request.method, request.url.path, response.status_code,
             (time.perf_counter() - start) * 1000)
    return response


# ---------- Exception handlers: one consistent error shape ----------
@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError):
    return JSONResponse(status_code=exc.status_code, content={
        "code": exc.code, "message": exc.message, "request_id": request.state.request_id})


@app.exception_handler(Exception)
async def unhandled_handler(request: Request, exc: Exception):
    log.exception("unhandled error, request_id=%s", request.state.request_id)  # traceback to logs / Sentry
    return JSONResponse(status_code=500, content={
        "code": "internal_error", "message": "Something went wrong", "request_id": request.state.request_id})


# ---------- Auth dependencies ----------
bearer = HTTPBearer(auto_error=False)


class CurrentUser(BaseModel):
    user_id: str
    tenant_id: str
    role: Role


def create_access_token(user_id: str, tenant_id: str, role: Role, minutes: int = 15) -> str:
    now = datetime.now(timezone.utc)
    payload = {"sub": user_id, "tid": tenant_id, "role": role.value,
               "iat": now, "exp": now + timedelta(minutes=minutes), "type": "access"}
    return jwt.encode(payload, SECRET, algorithm=ALGO)


async def get_current_user(creds: HTTPAuthorizationCredentials | None = Depends(bearer)) -> CurrentUser:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing token")
    try:
        p = jwt.decode(creds.credentials, SECRET, algorithms=[ALGO])   # verifies signature + exp
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    return CurrentUser(user_id=p["sub"], tenant_id=p["tid"], role=Role(p["role"]))


def require_role(*roles: Role):
    async def checker(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if user.role not in roles:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Insufficient role")
        return user
    return checker


def get_leads_repo(request: Request) -> LeadRepository:
    return request.app.state.leads


# ---------- Routers (v1 + additive v2) ----------
v1 = APIRouter(prefix="/v1", tags=["leads v1"])
v2 = APIRouter(prefix="/v2", tags=["leads v2"])


@v1.post("/leads", response_model=LeadOut, status_code=201)
async def create_lead(body: LeadCreate,
                      bg: BackgroundTasks,
                      user: CurrentUser = Depends(get_current_user),
                      repo: LeadRepository = Depends(get_leads_repo)):
    row = await repo.create(user.tenant_id, body)        # tenant from the token, never the body
    bg.add_task(send_welcome_email, row["email"])         # tiny fire-and-forget only; real work -> queue
    return row


@v1.get("/leads/{lead_id}", response_model=LeadOut)
async def get_lead(lead_id: str, user: CurrentUser = Depends(get_current_user),
                   repo: LeadRepository = Depends(get_leads_repo)):
    return await repo.get(user.tenant_id, lead_id)


@v1.get("/leads", response_model=Page)
async def list_leads(after: str | None = None, limit: int = Query(20, ge=1, le=100),
                     user: CurrentUser = Depends(get_current_user),
                     repo: LeadRepository = Depends(get_leads_repo)):
    rows = await repo.list(user.tenant_id, after, limit)
    return Page(items=rows, next_cursor=rows[-1]["id"] if len(rows) == limit else None)


@v2.get("/leads/{lead_id}", response_model=LeadOutV2)
async def get_lead_v2(lead_id: str, user: CurrentUser = Depends(get_current_user),
                      repo: LeadRepository = Depends(get_leads_repo)):
    return await repo.get(user.tenant_id, lead_id)


# ---------- Long-running work: 202 + job id + status ----------
@v1.post("/imports", response_model=JobOut, status_code=202)
async def start_import(request: Request, user: CurrentUser = Depends(require_role(Role.admin))):
    job_id = str(uuid.uuid4())
    request.app.state.jobs.jobs[job_id] = {"status": "queued", "progress": 0, "tenant_id": user.tenant_id}
    # real app: await redis.enqueue("import_leads", job_id)  /  import_leads.delay(job_id)
    asyncio.create_task(fake_worker(request.app.state.jobs, job_id))
    return JobOut(job_id=job_id, status="queued")


@v1.get("/imports/{job_id}", response_model=JobOut)
async def import_status(job_id: str, request: Request, user: CurrentUser = Depends(get_current_user)):
    job = request.app.state.jobs.jobs.get(job_id)
    if not job or job["tenant_id"] != user.tenant_id:
        raise NotFoundError("Job not found")
    return JobOut(job_id=job_id, status=job["status"], progress=job["progress"])


app.include_router(v1)
app.include_router(v2)


@app.get("/health")
async def health():
    return {"status": "ok"}


# ---------- Helpers ----------
async def send_welcome_email(email: str) -> None:
    await asyncio.sleep(0)       # pretend I/O


async def fake_worker(store: JobStore, job_id: str) -> None:
    store.jobs[job_id]["status"] = "running"
    for p in (25, 50, 75, 100):
        await asyncio.sleep(0.01)
        store.jobs[job_id]["progress"] = p
    store.jobs[job_id]["status"] = "done"


# ---------- Self-tests ----------
if __name__ == "__main__":
    from fastapi.testclient import TestClient

    with TestClient(app) as c:
        admin = {"Authorization": f"Bearer {create_access_token('u1', 'collegeA', Role.admin)}"}
        staff = {"Authorization": f"Bearer {create_access_token('u2', 'collegeA', Role.counsellor)}"}
        other = {"Authorization": f"Bearer {create_access_token('u3', 'collegeB', Role.admin)}"}

        assert c.get("/v1/leads").status_code == 401
        assert c.get("/v1/leads", headers={"Authorization": "Bearer junk"}).status_code == 401

        r = c.post("/v1/leads", json={"name": "Asha", "email": " ASHA@x.com "}, headers=admin)
        assert r.status_code == 201 and r.json()["email"] == "asha@x.com", r.text
        lead_id = r.json()["id"]
        assert "source" not in r.json()                                          # v1 contract unchanged

        assert c.post("/v1/leads", json={"name": "A", "email": "asha@x.com"}, headers=admin).status_code == 409
        assert c.post("/v1/leads", json={"name": "", "email": "bad"}, headers=admin).status_code == 422

        assert c.get(f"/v1/leads/{lead_id}", headers=admin).status_code == 200
        assert c.get(f"/v1/leads/{lead_id}", headers=other).status_code == 404   # tenant isolation
        assert c.get(f"/v2/leads/{lead_id}", headers=admin).json()["source"] == "web"

        err = c.get("/v1/leads/nope", headers=admin).json()
        assert err["code"] == "not_found" and "request_id" in err

        for i in range(3):
            c.post("/v1/leads", json={"name": f"L{i}", "email": f"l{i}@x.com"}, headers=admin)
        p1 = c.get("/v1/leads?limit=2", headers=admin).json()
        assert len(p1["items"]) == 2 and p1["next_cursor"]
        p2 = c.get(f"/v1/leads?limit=2&after={p1['next_cursor']}", headers=admin).json()
        assert len(p2["items"]) == 2

        assert c.post("/v1/imports", headers=staff).status_code == 403          # RBAC
        job = c.post("/v1/imports", headers=admin)
        assert job.status_code == 202
        time.sleep(0.2)
        assert c.get(f"/v1/imports/{job.json()['job_id']}", headers=admin).json()["status"] in {"running", "done"}

        print("All FastAPI demo tests passed")
