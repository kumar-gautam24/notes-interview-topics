# Document 13 — Security (Questions 505–528)

Answer format: **definition → why → implementation → failure → trade-off → real example**

> **Note on Section M.** Questions 521–528 cover LLM-specific security, which is where most candidates are weakest and where the field has the least settled practice. The through-line for all of them is one sentence: **the model is an untrusted component, and any content that reaches its context is untrusted input.** Everything else follows.

---

# L1 — Foundation

## 505. Authentication vs authorization?

**Authentication** — *who are you?* Verifying identity. Fails with **401**.
**Authorization** — *what may you do?* Verifying permission. Fails with **403**.

**Why the distinction matters practically:** they belong in different places and are enforced by different mechanisms. Authentication happens once, at the edge, and establishes a principal. Authorization happens at every access, against a specific resource (Q69, Q70).

**Authentication mechanisms:**
- **JWT** — stateless, self-contained, fast. **Cannot be revoked** before expiry, which is the trade.
- **Session tokens** — server-side lookup, revocable instantly, requires shared session state.
- **API keys** — long-lived, for machine clients. Must be hashed at rest and scoped.
- **mTLS** — mutual certificates, for service-to-service.
- **OIDC/OAuth2** — delegated identity.

**The JWT details that are actually security-relevant:**
```python
jwt.decode(token, key,
           algorithms=["RS256"],      # pin explicitly — never omit
           audience=EXPECTED_AUD,     # a valid token for another service is still valid
           issuer=EXPECTED_ISS)
```
Omitting `algorithms` historically enabled the `alg: none` attack. **Verifying signature without verifying audience and issuer means any token from any service using the same key is accepted** — a real and common oversight.

**The revocation problem:** a JWT issued 20 minutes ago to a since-disabled account is cryptographically valid. **Check the account is still active on each request**, or use short expiry with refresh tokens. This is the root of the soft-delete auth bug in Q69.

**The framing:** authentication establishes a claim; authorization decides what it grants. **Neither is a substitute for the other**, and a system that authenticates well and authorises loosely is the more common failure.

---

## 506. Container isolation?

**Definition.** Containers isolate userspace using namespaces and cgroups, but **share the host kernel** (Q470).

**What that means for security: a container boundary is weaker than a VM boundary.** A kernel vulnerability exploitable from inside a container can compromise the host and every other container on it. A VM has a hypervisor boundary; a container does not.

**So: treat containers as a *deployment* isolation mechanism, not a *security* isolation mechanism**, and layer real controls on top.

**The escape vectors to know:**
- `--privileged` — effectively disables isolation. Never in production.
- Mounting the Docker socket (`/var/run/docker.sock`) — grants root on the host, full stop.
- `hostPID`, `hostNetwork`, `hostPath` mounts
- Excessive capabilities (`CAP_SYS_ADMIN` in particular)
- Running as root inside the container, combined with a kernel bug
- Writable host paths

**The hardening baseline:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities: {drop: ["ALL"]}
  seccompProfile: {type: RuntimeDefault}
```

**When you need genuinely strong isolation** — running untrusted code, multi-tenant workloads where tenants supply code — use **microVMs (Firecracker, Kata Containers)** or separate nodes/clusters per tenant. **Namespaces alone are not sufficient for a hostile tenant.**

**The practical position:** for your own trusted workloads, hardened containers are appropriate. For anything executing user-supplied code — and an agent with a code-execution tool counts — you need a stronger boundary (Q527).

---

## 507. Why non-root containers?

**Because root inside a container is often close to root on the host**, and the gap is one kernel bug wide.

**What running as root enables for an attacker who achieves code execution in your container:**
- Install tooling, modify the filesystem, write to any mounted volume
- Exploit kernel vulnerabilities that require elevated capabilities
- Escape via a misconfigured mount or capability
- Bind privileged ports and manipulate networking

**Running as an unprivileged user removes most of that.** Combined with a read-only root filesystem and dropped capabilities, a compromised process can do very little beyond what your application could already do.

**Implementation:**
```dockerfile
RUN useradd -u 10001 -m app
COPY --chown=10001:10001 . /app
USER 10001
```
```yaml
securityContext:
  runAsNonRoot: true          # enforced by kubelet — pod fails to start if the image runs as root
  runAsUser: 10001
```
**`runAsNonRoot: true` is the enforcement point** — it rejects the pod rather than trusting the image.

**The friction and how to handle it:**
- **Ports below 1024** need root to bind. Bind 8080 and map it at the Service — there's no reason to run on 80 inside the container.
- **Writable paths** — a read-only root filesystem breaks anything writing to `/tmp`. Mount an `emptyDir` at the specific paths that need it.
- **File ownership** — `COPY --chown` at build time, or `fsGroup` for volumes.

**The framing:** non-root is defence in depth. It doesn't prevent compromise; **it bounds what a compromise achieves.** That's the correct way to describe most container hardening.

---

## 508. Least privilege?

**Definition.** Every component gets exactly the permissions it needs to do its job, and nothing more.

**Why it's the most important security principle in practice:** you cannot prevent all compromises. Least privilege is what determines whether a compromise is an incident or a catastrophe. **It converts "attacker has full access" into "attacker has read access to one S3 prefix."**

**Applied at every layer:**

| Layer | Least privilege means |
|---|---|
| **IAM** | The role reads one bucket prefix, not `s3:*` |
| **Database** | The app user has `SELECT/INSERT/UPDATE` on its tables — not `DROP`, not superuser |
| **Kubernetes RBAC** | No cluster-admin for applications; namespace-scoped roles |
| **Network** | Default-deny NetworkPolicies with explicit allows |
| **Container** | Non-root, dropped capabilities, read-only root |
| **API keys** | Scoped per-integration, revocable independently |
| **LLM tools** | Read tools by default; write tools require explicit scope (Q526) |

**The database example worth stating**, because it's cheap and rarely done: revoke `UPDATE` and `DELETE` on your ledger tables from the application user (Q161). Now a SQL injection or an application bug **cannot** mutate financial history, regardless of what the code attempts. The constraint is enforced by the database, not by discipline.

**The practical difficulty:** least privilege is discovered iteratively. Start restrictive, observe failures, grant narrowly. **Starting permissive and tightening later almost never happens** — nobody has an incentive to remove permissions that are currently working.

**The audit habit:** periodically review what permissions are actually *used* versus granted. IAM Access Analyzer and similar tools show unused permissions, and pruning them is a low-risk, high-value exercise.

---

## 509. Image scanning?

**Definition.** Analysing container images for known vulnerabilities in OS packages and application dependencies, matched against CVE databases.

**Why:** you inherit every vulnerability in your base image and dependency tree. A `python:3.12` base image typically carries dozens of CVEs at any moment, most irrelevant and some not.

**Where to scan:**
1. **In CI, on every build** — Trivy, Grype, Snyk. Block on critical/high severity in reachable code.
2. **In the registry, continuously** — ECR scanning re-evaluates existing images as new CVEs are published. **An image that was clean when built is not clean forever**, and this is the scan that catches it.
3. **At admission** — reject unsigned or unscanned images from running.
4. **At runtime** — detect anomalous behaviour (Falco).

**The practical problem: alert fatigue.** Scanning a typical image returns hundreds of findings, most in packages your application never invokes. Blocking on all of them means nobody can ship, and the gate gets disabled.

**How to make it workable:**
- **Minimal base images** (distroless, slim) — the single most effective reduction. Fewer packages means fewer CVEs, and most are irrelevant anyway (Q478).
- **Block only on critical/high with a known fix**, alert on the rest
- **Reachability analysis** where the tooling supports it — is the vulnerable function actually called?
- **Documented, expiring exceptions** rather than permanent suppressions
- **Rebuild regularly** so base image patches flow through. Pin by digest and update deliberately, not by floating tags.

**The wider supply chain:** SBOM generation, dependency pinning by lockfile, image signing (Cosign) with admission verification, and provenance attestation. **Signing plus admission control is the strongest single supply-chain control** — only images your pipeline built and signed may run.

---

## 510. Encryption in transit and at rest?

**In transit:**
- **TLS 1.2+ everywhere**, including inside the cluster. "It's on a private network" is not a security boundary — an attacker with a foothold in one pod can read plaintext traffic between others.
- **Terminate TLS at the ingress**, and use mTLS or a service mesh for pod-to-pod where the threat model warrants it.
- **Certificate management** — cert-manager with automated renewal. Expired certificates are a routine, avoidable outage.
- **HSTS**, and reject downgrade.

**At rest:**
- **EBS, RDS, S3** encrypted with KMS. On by default in most modern configurations — verify rather than assume.
- **etcd encryption** in Kubernetes — **not enabled by default**, and it's what protects your Secrets (Q486).
- **Backups and snapshots** encrypted, including cross-region copies.
- **Application-level encryption** for the most sensitive fields, so even a database dump doesn't expose them.

**The distinction worth making about at-rest encryption:** it protects against **physical media theft and unauthorised access to storage**. It does **not** protect against a compromised application — your app decrypts the data by design, so an attacker with application access reads it in plaintext. **At-rest encryption is a compliance and disk-disposal control, not an application-security control**, and being precise about that is a good signal.

**Key management:** KMS with rotation, separate keys per environment and per data classification, and IAM controlling key usage. **Who can decrypt is an access control decision**, and it's often more meaningful than the encryption itself.

**Field-level encryption** for the highest-sensitivity data (Q519) — encrypted in the application, so the database never sees plaintext. Costs you the ability to query or index those fields, which is a real trade.

---

## 511. Input validation?

**The principle: validate at the trust boundary, using a positive (allowlist) model, and reject rather than sanitise.**

**Why allowlist over blocklist:** a blocklist enumerates known-bad patterns and is always incomplete. An allowlist enumerates known-good and rejects everything else. **Blocklists fail open; allowlists fail closed.**

**Implementation with Pydantic** (Q18):
```python
class CreateUser(BaseModel):
    model_config = ConfigDict(extra="forbid")     # reject unknown fields
    email: EmailStr
    age: int = Field(ge=13, le=120)
    role: Literal["viewer", "editor"]             # enum, not free string
    display_name: str = Field(min_length=1, max_length=100)
```
**`extra="forbid"` is the mass-assignment defence** — a client sending `{"is_admin": true}` gets a 422 rather than being silently ignored (or worse, honoured).

**What must be validated beyond types:**
- **Size limits** — body size at the proxy, before your process allocates memory
- **Ranges** on every number, especially anything that becomes a `LIMIT` or an allocation
- **Enums** wherever the set is finite
- **Format** — dates, UUIDs, identifiers
- **Business rules** — the amount is within the user's balance, the referenced record exists *and belongs to this tenant*

**That last one is where validation meets authorization** (Q70): validating that a `document_id` is a well-formed UUID is not the same as validating that this user may access it. **Both are required and they're separate checks.**

**The rule for output:** validate input, **encode output**. Escaping is contextual — HTML, SQL, shell, and JSON all need different treatment, and the right defence is context-appropriate encoding at the point of use, not sanitising at the point of input (Q525).

**And the LLM extension:** model output is input to your next stage. Validate it with the same rigour as a request body (Q280).

---

## 512. Webhook signature verification?

**The problem:** a webhook endpoint is a publicly reachable URL that causes state changes. Without verification, anyone can call it and forge events — marking payments as captured, triggering refunds, whatever the handler does.

**The mechanism — HMAC over the raw body:**
```python
async def verify(request: Request) -> bytes:
    raw = await request.body()                       # RAW bytes, before parsing
    timestamp = request.headers["X-Timestamp"]
    signature = request.headers["X-Signature"]

    signed_payload = f"{timestamp}.".encode() + raw
    expected = hmac.new(SECRET, signed_payload, hashlib.sha256).hexdigest()

    if not hmac.compare_digest(expected, signature):  # constant-time
        raise HTTPException(401)
    return raw
```

**The details that are load-bearing:**

1. **Sign the raw body, byte-for-byte.** Parsing JSON and re-serialising changes whitespace and key order, and the signature will never match. **You must capture the raw bytes before any parsing** — in FastAPI this requires care because reading the body consumes the stream (Q55).

2. **`hmac.compare_digest`, not `==`.** String comparison short-circuits on the first differing byte, leaking timing information that can be used to forge a signature byte by byte. **Constant-time comparison is not optional.**

3. **Include a timestamp in the signed payload** and reject stale ones (Q517).

4. **Never trust the payload's contents for anything financial.** The signature proves it came from the provider; it doesn't prove the values are what you should act on. **For payments, call the provider's API to fetch the authoritative object by ID** (Q154).

**Secret management:** stored in Secrets Manager, rotatable, and support two valid secrets during rotation so you don't drop events.

**Failure to avoid:** verifying the signature *after* parsing and acting on the payload. The order is verify → dedupe → process.

---

# L2 — Application security

## 513. SQL injection?

**The mechanism:** user input concatenated into a SQL string is interpreted as SQL rather than data.

**The fix is parameterised queries, always:**
```python
# Vulnerable
await conn.execute(f"SELECT * FROM users WHERE email = '{email}'")

# Safe — the driver sends the query and parameters separately
await conn.execute("SELECT * FROM users WHERE email = $1", email)
```
Parameterisation isn't escaping — the query structure is sent to the database separately from the values, so a value **cannot** change the query's meaning regardless of its content.

**What parameterisation doesn't cover:**
- **Identifiers** — table and column names cannot be parameterised. If they're dynamic, use a strict allowlist mapping user input to known-safe identifiers. Never interpolate.
- **`ORDER BY` direction and column** — same problem. Allowlist.
- **Dynamic `IN` lists** — use array parameters (`= ANY($1)`), not string building.

**ORMs help but don't immunise you.** SQLAlchemy's `text()` with f-string interpolation is just as vulnerable, and raw query escape hatches exist in every ORM.

**Defence in depth:**
1. Parameterised queries (the actual fix)
2. **Least-privilege database user** (Q508) — no `DROP`, no access to tables it doesn't need. This bounds what an injection achieves.
3. **Row-Level Security** — even a successful injection is scoped to the tenant (Q520)
4. `statement_timeout` — bounds resource-exhaustion attempts
5. Input validation as a secondary layer

**The LLM-specific escalation** (Q527): if a model can generate SQL that you execute, **every prompt injection becomes a SQL injection.** This is why `execute_sql` must never be a tool. Expose typed, parameterised operations instead.

---

## 514. SSRF?

**Server-Side Request Forgery** — an attacker causes your server to make HTTP requests to destinations of their choosing.

**Why it's severe in cloud environments:** your server sits inside the network perimeter. It can reach internal services, private subnets, and — critically — the **cloud metadata endpoint** (`169.254.169.254`), which on misconfigured instances returns IAM credentials. **SSRF plus IMDSv1 equals full AWS account compromise**, which is why IMDSv2 (requiring a PUT with a token header) exists and should be enforced.

**Where SSRF enters:**
- A user-supplied URL to fetch (webhook registration, "import from URL", avatar fetching)
- Document ingestion from a URL (Q390)
- **An agent with a `fetch_url` tool** — the model can be induced by prompt injection to fetch an internal address (Q523)

**Defences:**
1. **Allowlist destinations** where possible. If it must fetch arbitrary URLs, that's a much harder problem.
2. **Resolve DNS and validate the resolved IP**, not just the hostname. Check against private ranges (RFC1918, loopback, link-local, IPv6 equivalents).
3. **Re-validate after redirects** — a public URL can redirect to `169.254.169.254`. Validate every hop, or disable redirects.
4. **Beware DNS rebinding** — the name resolves to a public IP during validation and a private one at request time. Resolve once and connect to the resolved IP.
5. **Enforce IMDSv2** and set the hop limit to 1, so a container cannot reach it.
6. **Egress network policy** — the pod can only reach explicitly allowed destinations. **This is the strongest control** because it doesn't depend on getting the URL parsing right.
7. Short timeouts, no redirects, response size limits.

**The agent-specific note:** a URL-fetching tool is an SSRF primitive handed to a model that can be persuaded by untrusted document content. **Allowlist the domains it may reach**, and treat that allowlist as a security control (Q526).

---

## 515. File upload security?

**The threats:**
1. **Malicious content** — malware, a payload targeting whatever parses it
2. **Content-type confusion** — an HTML file served from your domain becomes stored XSS
3. **Path traversal** in the filename
4. **Zip bombs / decompression bombs** — a 1 MB archive expanding to 100 GB
5. **Resource exhaustion** — huge files, or many concurrent uploads
6. **Parser exploits** — image and PDF libraries have a long CVE history

**The controls:**

1. **Never trust the client-declared content type or extension.** **Sniff the actual type from magic bytes** and validate against an allowlist. This is the single most important check.
2. **Never use the client-supplied filename.** Generate your own identifier and store the original name as metadata only. This eliminates path traversal entirely.
3. **Enforce size limits at the proxy**, before your process allocates memory (Q94).
4. **Store outside the web root** — object storage, not a served directory.
5. **Serve from a separate domain** with `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`. **A user-uploaded file served from your primary domain can execute JavaScript in your origin.**
6. **Presigned URLs** so bytes never transit your API (Q94, Q518).
7. **Scan asynchronously**, mark the file `pending`, and expose it only after validation passes.
8. **Parse in a sandbox** — a separate process or container with no network and low privileges, so a parser exploit is contained.
9. **Bound decompression** — limit the expanded size and the number of entries.

**The RAG-specific angle** (Q523): an uploaded document's *text content* becomes part of a model's context. **A file upload is therefore also a prompt-injection vector**, not just a malware vector. The document doesn't need to exploit a parser; it just needs to contain instructions.

---

## 516. Abuse and rate limiting?

Full mechanics at Q90 and Q189. The security framing:

**Rate limiting is a security control, not just a capacity control.** It bounds credential stuffing, enumeration, scraping, and cost-exhaustion attacks.

**Layer it:**
1. **Edge/WAF** — volumetric attacks blocked before reaching your infrastructure. Nothing you write in Python competes with this.
2. **Per-IP** at the ingress — cheap, but IPs are shared behind NAT and trivially rotated.
3. **Per-authenticated-principal** — the meaningful limit. Redis-backed so it holds across replicas (Q249).
4. **Per-endpoint** — login and password reset need far tighter limits than a read endpoint.
5. **Progressive delays and lockouts** on authentication failures.

**The abuse patterns to defend specifically:**
- **Credential stuffing** — tight per-IP and per-account login limits, plus a CAPTCHA or proof-of-work after failures
- **Enumeration** — identical responses and timing whether or not an account exists. **Return 404 rather than 403 for another tenant's resource** (Q70).
- **Scraping** — per-principal limits on list endpoints, cursor pagination that doesn't allow deep arbitrary access
- **Cost exhaustion — the AI-specific one.** An attacker sends expensive queries to burn your LLM budget. **Rate-limit by token spend, not request count** (Q90), because a 200-token and a 50,000-token request are not equivalent. Per-tenant daily budgets with a circuit breaker are the containment (Q336).

**The response discipline:** 429 with `Retry-After` and the standard `X-RateLimit-*` headers, so legitimate clients self-regulate rather than hammering.

**Fail open or closed?** Decide deliberately. If the limiter is unavailable, a public API probably fails open (availability); an expensive AI endpoint fails closed (cost). **The worst outcome is not having decided** (Q189).

---

## 517. Webhook replay protection?

**The threat:** an attacker captures a validly-signed webhook and re-sends it. The signature verifies — it's a genuine message. Without replay protection, the effect is applied again.

**The two defences, and you need both:**

**1. Timestamp validation.** The timestamp must be inside the signed payload, or an attacker simply changes it:
```python
signed_payload = f"{timestamp}.".encode() + raw_body
expected = hmac.new(SECRET, signed_payload, hashlib.sha256).hexdigest()

if abs(time.time() - int(timestamp)) > 300:      # 5 minute window
    raise HTTPException(401, "stale timestamp")
```
Bounds the replay window to a few minutes. **The timestamp must be signed** — this is the detail that's easy to get wrong.

**2. Idempotency via a dedupe table** (Q153) — the real protection:
```sql
CREATE TABLE webhook_events (
  provider TEXT, event_id TEXT, PRIMARY KEY (provider, event_id)
);
```
```python
inserted = await conn.execute(
    "INSERT INTO webhook_events (provider, event_id, payload) VALUES ($1,$2,$3) "
    "ON CONFLICT DO NOTHING", provider, event.id, raw)
if inserted == "INSERT 0 0":
    return Response(200)            # already processed
```

**Why both.** The timestamp window bounds replay in time; the dedupe table makes replay a no-op regardless of timing. **Neither alone is sufficient** — a replay inside the 5-minute window passes timestamp validation, and a dedupe table with unbounded retention is impractical without a time bound.

**And the third layer:** guarded state transitions (Q155). Even if a duplicate slips through both, `UPDATE ... WHERE status = 'pending'` makes reapplying a completed transition a no-op. **Three independent defences, each of which fails differently.**

**Clock skew:** a 5-minute window tolerates normal skew. Tighter windows cause spurious rejections; wider ones widen the replay window.

---

## 518. Presigned URL security?

**Definition.** A time-limited URL granting direct access to an object in S3, signed with your credentials, so the client talks to S3 without transiting your API (Q94).

**Why use them:** your API never handles the bytes. Bandwidth, scaling, and throughput become S3's problem, and a 10 GB upload doesn't occupy a worker for minutes.

**The security properties to control:**

**For uploads (`PUT`):**
```python
s3.generate_presigned_post(
    Bucket=bucket,
    Key=f"{tenant_id}/{upload_id}/{part}",     # tenant-scoped prefix
    Fields={"Content-Type": "application/pdf"},
    Conditions=[
        ["content-length-range", 1, 10_000_000],   # ← essential
        {"Content-Type": "application/pdf"},
    ],
    ExpiresIn=900,                                  # 15 minutes
)
```
**`content-length-range` is the one people omit.** Without it a client uploads a 100 GB file on your bill. Constrain content type too, though **still validate server-side after upload** — the declared type is a hint, not a guarantee (Q515).

**For downloads (`GET`):**
- **Short expiry** — minutes, not days. A presigned URL is a bearer token; anyone with it has access.
- **Generate per request, after authorisation.** Authorise the user for that object *before* signing, every time.
- **Never store or cache presigned URLs** — they'd outlive the permission check that produced them.
- `ResponseContentDisposition: attachment` so browser-rendered content can't execute in your origin.

**The failure modes:**
1. **URLs leaking via `Referer` headers, logs, or shared links.** They're bearer credentials in a query string. Short expiry is the mitigation.
2. **Over-broad IAM on the signing role** — the presign can only grant what the role has. A role with `s3:*` on the whole bucket means a bug in your key construction exposes everything. **Scope the role to the prefix.**
3. **Predictable keys** — use UUIDs, not sequential IDs.
4. **Abandoned multipart uploads** consuming storage forever — lifecycle rule to abort after 7 days.

---

## 519. PII handling?

**The principle: minimise, then protect what remains.**

**Data minimisation first**, because the cheapest data to protect is data you don't have:
- Collect only what you need
- Retain only as long as needed, with automated deletion
- **Don't propagate PII into systems that don't need it** — logs, analytics, caches, third-party services

**The controls:**

1. **Classification.** Know which fields are PII, health data, or financial. You cannot protect what you haven't identified.
2. **Encryption** — at rest and in transit, with field-level encryption for the most sensitive (Q510).
3. **Access control** — RLS (Q520), least privilege, and **audit every access.** For health and financial data, read access is auditable by regulation.
4. **Redaction in logs — the most commonly violated control.** Log field *names* and shapes, never values. Hash identifiers for correlation. **This must be the default**, because one debug log line added during an incident is how leaks happen (Q326).
5. **Redaction in traces and error reports** — Sentry-style tools capture local variables by default.
6. **Deletion that actually completes** — database, backups (or a documented retention window), caches, search indexes, vector stores, conversation histories (Q393).

**The LLM-specific concerns**, which are the differentiator in this answer:
- **Context sent to a third party.** Every retrieved chunk and tool result goes to the provider. Minimise what enters context; retrieve fields, not whole records.
- **Tokenise before sending** — replace identifiers with placeholders, map back after generation. The model reasons over structure without seeing the identifier.
- **Provider retention and training terms.** Verify which endpoint you're calling — retention policies differ by tier. Zero-retention endpoints and a BAA where applicable.
- **Output filtering** — scan generated text for identifier patterns, especially in RAG where the model may echo context verbatim.
- **Self-hosting** for the most sensitive processing, so data never leaves your infrastructure (Q449).

---

## 520. Tenant isolation?

Full treatment at Q93 and Q385. The security framing:

**Cross-tenant data exposure is the most severe bug a multi-tenant system can have.** It's a breach, it's reportable, and it usually ends the customer relationship. So the design must make it **structurally impossible**, not merely unlikely.

**The layers, and the point is that each one catches what the previous missed:**

**1. Tenant identity from the authenticated token only.** Never from a request parameter, header, body, or — in an agent — a model-supplied tool argument (Q325). **Accepting a `tenant_id` from the client is an IDOR by design.**

**2. A dependency resolves and validates the tenant context** once, at the edge.

**3. Repository layer always filters**, enforced structurally by a base class so an individual developer cannot omit it.

**4. Row-Level Security as the backstop:**
```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON orders
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```
**This is the layer that converts "we're careful" into "it's impossible."** A forgotten `WHERE` returns zero rows rather than every tenant's data. Application bugs stop being breaches.

Note the PgBouncer interaction — in transaction pooling mode, use `SET LOCAL` inside the transaction (Q93).

**5. 404, not 403**, for another tenant's resource — prevents enumeration (Q70).

**6. Cache keys include the tenant.** A response cache keyed only on the query serves one tenant's data to another (Q391).

**7. A CI test suite that attempts cross-tenant access on every endpoint and every tool.** **This is the difference between claiming isolation and having it**, and it's the artefact to point at when asked how you know.

**The audit requirement:** log every access with tenant, user, and resource, so a suspected leak can be investigated rather than guessed at.

---

## 521. Is the system prompt a security boundary?

**No. This is the most important thing to be clear about in LLM security.**

**Why not:**
1. **Role boundaries are a trained prior, not an enforced separation.** The model was fine-tuned to weight system messages more heavily. That's a statistical tendency, not a guarantee (Q268).
2. **Everything in the context is the same tensor.** There's no memory protection, no privilege bit, no execution boundary between "instructions" and "data."
3. **Instructions in user content or retrieved documents are sometimes followed** — that's prompt injection, and it works precisely because the boundary is soft (Q522).
4. **System prompts leak.** Users extract them routinely. Anything secret in your system prompt should be considered public.

**So the rule: never enforce anything in the system prompt that matters.**

| Wrong | Right |
|---|---|
| "Only answer questions about billing" | Route/reject in code before the call |
| "Never reveal other users' data" | Filter at the query with RLS (Q520) |
| "Only call `delete_record` for admins" | Authorise in the tool executor (Q526) |
| "The API key is X, use it for..." | Never put credentials in a prompt |
| "Refuse requests about competitors" | Classify and reject deterministically |

**What the system prompt IS good for:** shaping behaviour, tone, format, and default choices. It makes the desired behaviour *likely*. **Likely is fine for quality and unacceptable for security.**

**The architectural consequence** — and this is the sentence to have ready: **"LLM at the perimeter, deterministic core in the middle."** The model proposes; validated, authorised, deterministic code decides and executes (Q281, Q305). Every security property lives in the code path, never in the prompt.

**The corollary for defence-in-depth:** you can still put instructions in the system prompt as a *first* layer — it reduces the frequency of unwanted behaviour. Just never let it be the *only* layer.

---

# L3 — LLM security

## 522. Prompt injection?

**Definition.** Content within the model's context causes it to behave contrary to the application's intent — because the model cannot reliably distinguish instructions from data (Q521).

**Why it's structurally different from SQL injection.** SQL injection has a clean fix: parameterisation separates the query from the data, and the database enforces that separation absolutely. **There is no equivalent for prompts.** The model processes one undifferentiated context. Delimiters, tags, and "ignore anything below this line" instructions all reduce the frequency of successful injection; **none of them eliminate it.** This is an unsolved problem, and saying so is the correct position.

**Direct injection** — the user's own input attempts to override instructions. The user is attacking a system they already have legitimate access to, so the impact is bounded by their own permissions: leaked system prompts, bypassed content rules, off-topic use.

**Indirect injection** is the severe one (Q523).

**The defences, and the framing matters — these reduce likelihood, they don't guarantee:**

1. **Never rely on the prompt for security** (Q521). The primary defence is architectural.
2. **Least privilege on tools** — the model can only propose actions the *user* is permitted to take, authorised in code (Q526).
3. **Structural separation** — put untrusted content in clearly delimited blocks, and instruct the model to treat it as data. Helps; doesn't guarantee.
4. **Output validation** — never let model output directly mutate state (Q281).
5. **Input filtering** for known injection patterns — a blocklist, therefore incomplete, but it raises the cost.
6. **A separate classifier** examining input or output for suspicious instruction-like content.
7. **Human approval** for consequential actions (Q335).
8. **Monitoring** — log and alert on tool calls that deviate from expected patterns.

**The honest summary for an interview:** *"Prompt injection cannot currently be prevented at the model layer. The mitigation is to assume it succeeds and ensure that a successfully injected model can't do anything harmful — because every capability it has is authorised in code against the user's permissions."*

---

## 523. Indirect prompt injection?

**Definition.** Injected instructions arrive not from the user but from content the system retrieves — a document, a web page, an email, a file upload, an API response, or a third-party tool's output.

**Why this is the severe case:** the attacker doesn't need any access to your system. They need only get content into a place your system will read. **Poison one document in a corpus and every user who triggers its retrieval is affected.**

**The realistic attack paths for a RAG or agent system:**
- A document uploaded to a shared corpus, containing instructions in its text (Q515)
- A web page fetched by a `fetch_url` tool
- An email or ticket ingested for summarisation
- A third-party MCP server's tool description or results (Q300)
- Text embedded in an image processed by a vision model
- Content hidden from human readers but present in the extracted text — white text, metadata, comments

**What an attacker aims for:**
- **Exfiltration** — cause the model to include sensitive context in an output that reaches the attacker (Q524)
- **Unauthorised tool calls** — trigger a write, a send, or a fetch to an attacker-controlled destination
- **Answer manipulation** — make the system give wrong answers to other users

**The defences:**
1. **Tool authorization in code against the user's permissions** — the model being persuaded doesn't grant the *user* new rights (Q526). **This is the primary defence.**
2. **Egress control** — the model cannot cause a request to an arbitrary destination (Q514). No unrestricted URL fetching, no rendering of model-supplied image URLs (Q524).
3. **Content provenance** — mark retrieved content as untrusted in the context and instruct accordingly. Partial mitigation.
4. **Corpus hygiene** — who can add documents? A corpus anyone can write to is a corpus anyone can poison. **Treat ingestion permissions as a security control.**
5. **Human approval for consequential actions** (Q335).
6. **Output validation and grounding checks** (Q365) — an answer citing nothing, or containing unexpected instructions, is a signal.
7. **Detection** — log the retrieved context with every response so an incident can be traced to the poisoned document (Q388).

**The framing:** *"Indirect injection means any content that enters the context is untrusted input from an unknown party. I design as though the retrieved documents are hostile, because for a shared corpus they eventually will be."*

---

## 524. Data exfiltration via the model?

**The threat:** an injected instruction causes the model to place sensitive context into an output that reaches the attacker — without the model ever "sending" anything itself.

**The channels, and the point is that they're all indirect:**

1. **Markdown image rendering.** The model emits an image reference whose URL contains encoded data. **The victim's browser fetches it, and the attacker's server receives the data in the request log.** The model made no network call; the renderer did.
2. **Links** the user is induced to click, with data in the query string.
3. **A tool that makes outbound requests** — a URL fetcher, a webhook sender, an email tool. The model is persuaded to call it with data in the payload.
4. **Written into an artefact** — a document, a ticket comment, a commit — that the attacker can read.
5. **Answer content itself**, if the attacker can see the output.

**The defences:**

1. **Do not render model-generated URLs.** Strip or neutralise image and link syntax from model output before rendering, or allowlist the domains. **This closes the most common channel and costs almost nothing** — it's the single highest-value control here.
2. **Content Security Policy** restricting `img-src` and `connect-src` to your own domains, so even a rendered reference can't reach an attacker's server.
3. **Egress allowlist** for any tool that fetches or sends (Q514).
4. **No tools that transmit to arbitrary destinations** without approval.
5. **Minimise what's in context** (Q519) — data that isn't there cannot be exfiltrated.
6. **Output scanning** for encoded blobs and identifier patterns.
7. **Human approval** for anything sending data outward (Q335).

**The insight worth stating:** exfiltration doesn't require the model to have network access. **It only requires that something downstream of the model's output makes a request.** So the security boundary is the *renderer* and the *tool executor*, not the model — and reasoning about it that way is what leads to the right controls.

---

## 525. Rendering model output safely?

**Model output is untrusted content. Rendering it as HTML without treatment is stored XSS with extra steps.**

**The threats:**
- **XSS** — the model emits markup or script, either through injection or by faithfully reproducing content from a retrieved document
- **Exfiltration via images and links** (Q524)
- **Phishing** — a plausible-looking link to an attacker's site
- **UI redressing** via CSS or iframes

**The controls:**

1. **Render markdown, not HTML**, and configure the renderer to disable raw HTML passthrough. Most markdown libraries allow inline HTML by default — **turn it off explicitly.**
2. **Sanitise the rendered output** with an allowlist (DOMPurify or equivalent). Allowlist the tags and attributes you want; reject everything else (Q511).
3. **Strip or allowlist URLs** in links and images (Q524).
4. **Content Security Policy** — `script-src 'self'`, restricted `img-src` and `connect-src`. **This is the backstop that makes a sanitiser bug survivable.**
5. **Escape by context.** Output going into an HTML attribute, a JavaScript string, or a URL each needs different encoding.
6. **Never `dangerouslySetInnerHTML`** with model output unsanitised. Never `eval` generated code.
7. **For generated code specifically** — display it, don't execute it. If execution is a feature, sandbox it with no network and no credentials (Q527).

**The RAG-specific angle:** even without injection, the model may faithfully reproduce content from a retrieved document. **If your corpus contains any HTML or script, that content can reach your renderer through a completely benign path.** Sanitisation must therefore apply to all output, not only to output you suspect.

**The framing:** *"Model output is user-generated content from an untrusted source. It gets the same treatment as a comment box — sanitise, escape by context, and rely on CSP as the backstop."*

---

## 526. Tool authorization in agents?

Full mechanics at Q289 and Q311. The security framing, which is the core of LLM security:

**The model is not a principal.** It has no identity, no permissions, and no accountability. **Every tool call is authorised against the user who initiated the run, in code, at execution time.**

**Why this is the primary defence against prompt injection:** if the model is persuaded to call `delete_all_records`, the executor checks whether *this user* may do that. A non-admin user's injected model gets a denial. **The attack fails at the boundary regardless of what the model was convinced to propose** (Q522, Q523).

**The layers:**

1. **Tool availability filtered by role** before the model sees them. The model cannot call what isn't in its context — the cheapest and most effective control.
2. **Explicit registry, never dynamic dispatch.** `getattr(self, tool_name)` on a model-supplied string is remote code execution (Q288).
3. **Per-call scope check** in a single choke point (Q334).
4. **Server-side context injection.** `tenant_id` and `user_id` come from the session and are **not parameters in the tool schema.** The model cannot specify a tenant because there's nowhere to put one. **This eliminates the vulnerability class rather than defending against instances** (Q325).
5. **Typed, constrained arguments** — a bounded `limit` cannot be coerced into an unbounded query (Q284).
6. **Human approval for irreversible actions** (Q335).
7. **Generic denials to the model, full detail in the audit log** — telling the model why it was denied is information disclosure and an invitation to probe (Q307).
8. **Audit every proposed call**, allowed and denied.

**The tiering** (Q312): read tools liberal; reversible writes need scope and idempotency; irreversible writes need approval. **The safest dangerous tool is one that doesn't exist** — before adding a destructive capability, ask whether the agent needs to *do* it or merely to *propose* it.

---

## 527. Why never expose arbitrary execution?

**No `execute_sql`. No `run_shell`. No `eval`. No unrestricted `fetch_url`.** These are not tools; they are capability grants to whoever controls the model's context.

**Why, precisely:**

1. **Every prompt injection becomes a full exploit.** A tool that runs arbitrary SQL turns a poisoned document into a SQL injection with your application's database privileges (Q513, Q523).
2. **You cannot authorise it meaningfully.** Authorisation requires knowing what an action does. `execute_sql(query)` could be anything. There's no scope you can attach to it.
3. **No constraints are enforceable.** You can't bound a `limit` or scope a tenant when the model writes the whole query.
4. **Read-only doesn't save you.** A read-only SQL tool is a data-exfiltration primitive covering every table the user can reach — and it defeats RLS if the connection isn't scoped.
5. **The blast radius is your application's full privilege**, not the user's.

**What to do instead: expose typed, parameterised operations that map to user intents.**
```python
# Never
async def execute_sql(query: str) -> list[dict]: ...

# Instead
class GetOrdersInput(BaseModel):
    status: Literal["pending", "paid", "shipped"] | None = None
    limit: int = Field(default=20, ge=1, le=100)
    # tenant_id NOT here — injected server-side

async def get_orders(args: GetOrdersInput, ctx: UserContext):
    return await repo.list_orders(ctx.tenant_id, args.status, args.limit)
```
Every parameter is constrained, the tenant scope is not model-controllable, and the query shape is fixed.

**If code execution is genuinely a product requirement** — a data-analysis agent, say — then it needs a real isolation boundary, not a container (Q506): a microVM or gVisor sandbox, no network, no credentials, no access to your data, ephemeral, with CPU/memory/time limits, and results validated before they re-enter the context.

**The one-line version:** *"An arbitrary execution tool means the security boundary is the model's judgement, and the model's judgement is manipulable by anyone who can get text into its context."*

---

## 528. Security posture for an AI system?

**The synthesis. Organised by where the LLM changes the threat model, because that's what distinguishes this from generic application security.**

**What stays the same:** authn/authz (Q505), least privilege (Q508), input validation (Q511), parameterised queries (Q513), encryption (Q510), tenant isolation (Q520), container hardening (Q506–507), supply chain (Q509), secrets management (Q486, Q492). **None of this is optional, and most AI security incidents are ordinary application security failures.** Say that first — it resists the temptation to treat AI security as exotic.

**What is genuinely new:**

1. **The context window is a trust boundary you cannot enforce.** Anything reaching it can influence behaviour (Q521, Q522).
2. **Retrieved content is untrusted input from an unknown party** (Q523). Corpus write permissions are a security control.
3. **The model is not a principal.** Tool authorisation is against the user, in code (Q526).
4. **Model output is untrusted content** — validate before acting (Q281), sanitise before rendering (Q525).
5. **Exfiltration happens downstream of the model** — via renderers and tools, not by the model itself (Q524).
6. **Cost is an attack surface.** Budget exhaustion is a denial-of-service vector unique to this domain (Q516).
7. **Data leaves your perimeter by design** — to the model provider. Minimisation, tokenisation, retention terms (Q519).

**The architecture that ties it together:** *LLM at the perimeter, deterministic core in the middle.* The model parses and phrases; validated, authorised, deterministic code decides and executes.

**Detection and response, because prevention fails:**
- Audit every tool call, proposal and decision alike (Q327)
- Log retrieved context with responses, so a poisoned document is traceable (Q388)
- Alert on unauthorised tool attempts, unusual tool sequences, cost anomalies, and refusal-rate shifts
- A kill switch that halts agent execution (Q338)
- An incident path: revoke, rotate, identify affected runs from the audit trail, remove the poisoned content, add the case to your eval suite (Q437)

**The closing framing:** *"Most of this is normal application security. The genuinely new part is that I now have a component I cannot fully control, sitting between untrusted input and privileged actions — so I bound what it can cause rather than trying to constrain what it will decide."*

---

*End of Document 13. Next: Document 14 — Observability (questions 529–547).*
