# 11 — Networking and Backend Foundations

This doc covers the concepts that appear everywhere in deployment, Kubernetes, and Ingress but are rarely explained from scratch. Each part is self-contained — read the ones you need.

Prerequisite for: [12 — Deployment Lifecycle](./12-deployment-lifecycle.md), [13 — Kubernetes Guide](./13-kubernetes-guide.md), [14 — Ingress Guide](./14-ingress-guide.md).

---

## Part A — DNS: how names become IP addresses

When you type `<dev-backend-host>` in a browser, your computer doesn't know where that is. It only understands IP addresses like `<AZURE_LB_IP>`. DNS (Domain Name System) is the phone book that translates names to IPs.

### The lookup chain

```
You type: <dev-backend-host>

1. Browser cache       → "Have I looked this up in the last few minutes?"
2. OS cache            → "Has any app on this machine looked it up?"
3. Recursive resolver  → Your ISP's (or 8.8.8.8's) DNS server
4. Root servers        → "I don't know .ai, but here's who does"
5. .ai TLD server      → "I don't know example.com, but here's who does"
6. example.com auth NS  → "<dev-backend-host> = <AZURE_LB_IP>"

Answer flows back: <AZURE_LB_IP>
Browser connects to that IP.
```

### Record types you'll see

| Type | What it does | Example |
|------|-------------|---------|
| **A** | Name → IPv4 address | `<dev-backend-host> → <AZURE_LB_IP>` |
| **AAAA** | Name → IPv6 address | Same but for IPv6 |
| **CNAME** | Name → another name (alias) | `api.example.com → <dev-backend-host>` |

### Why it matters for us

Our Ingress file has `host: <dev-backend-host>`. This only works because someone configured DNS to point `<dev-backend-host>` to the Azure Load Balancer's IP. If DNS is wrong, the browser never reaches your cluster.

### Commands to verify

```bash
# Look up the IP for a hostname
nslookup <dev-backend-host>

# More detailed (shows the full chain)
dig <dev-backend-host>

# Just the IP
dig +short <dev-backend-host>
```

### Common DNS problems

- **Propagation delay** — you changed the DNS record but it still resolves to the old IP. DNS records have a TTL (time to live). Caches hold the old value until TTL expires (minutes to hours).
- **Wrong record type** — you created a CNAME where you needed an A record (or vice versa).
- **VPN/split DNS** — on corporate VPN, internal DNS resolves `example.com` differently than public DNS. If `dig` works off VPN but not on VPN (or vice versa), this is why.

---

## Part B — TLS/HTTPS/SSL: what the padlock means

### The problem

HTTP sends everything in **plaintext**. Anyone on the network (your ISP, the coffee shop WiFi, a man-in-the-middle) can read:
- The URL you're requesting
- Request headers (including your `Authorization` token)
- Request body (including your Razorpay webhook secret)
- Response body (including user data)

### What TLS does

TLS (Transport Layer Security) wraps HTTP in an encrypted tunnel. HTTPS = HTTP + TLS. SSL is the old name for TLS (SSL 3.0 → TLS 1.0 → ... → TLS 1.3). People still say "SSL" but mean TLS.

### The handshake (simplified)

```
Browser                                    Server
   |                                          |
   |──── ClientHello (supported ciphers) ────▶|
   |                                          |
   |◀─── ServerHello + Certificate ──────────|
   |     (server's public key, signed by CA)  |
   |                                          |
   |──── Key Exchange ───────────────────────▶|
   |     (both sides derive a shared secret)  |
   |                                          |
   |◀════ Encrypted tunnel established ══════▶|
   |     (all HTTP traffic flows inside)      |
```

After the handshake, every byte is encrypted. Even if someone intercepts the packets, they see gibberish.

### Certificates

A certificate is a file that says "I am `<dev-backend-host>` and here's my public key." It's signed by a **Certificate Authority** (CA) — a trusted third party (Let's Encrypt, DigiCert, etc.). Your browser has a built-in list of trusted CAs. If the certificate is signed by one of them, the browser trusts it. If not → "Your connection is not private" warning.

Certificates **expire** (typically 90 days for Let's Encrypt, 1 year for paid CAs). When they expire, browsers reject the connection. This is a common production outage cause.

### How it connects to us

Our Ingress file has these relevant settings:

```yaml
# Force HTTPS — if someone tries HTTP, redirect to HTTPS
nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

And in the `configuration-snippet`:

```yaml
# Tell browsers: "always use HTTPS for this domain for the next year"
more_set_headers "Strict-Transport-Security: max-age=31556926; includeSubDomains";
```

### Security headers explained (from our Ingress)

| Header | What it does |
|--------|-------------|
| `Strict-Transport-Security` (HSTS) | Browser remembers "always use HTTPS" for 1 year. Even if user types `http://`, browser upgrades to `https://` automatically. |
| `X-Content-Type-Options: nosniff` | Prevents browser from guessing file types. If server says "this is JSON", browser won't try to render it as HTML (prevents XSS via MIME sniffing). |
| `X-Frame-Options: DENY` | Prevents your pages from being embedded in an `<iframe>` on another site (prevents clickjacking). |
| `X-XSS-Protection: 1; mode=block` | Legacy XSS filter. Modern browsers have better protections, but this doesn't hurt. |
| `Cross-Origin-Opener-Policy: same-origin` | Prevents other sites from getting a reference to your window object. |
| `Referrer-Policy: strict-origin-when-cross-origin` | When navigating to another site, only send the origin (not the full URL path) as the referrer. |

---

## Part C — Load Balancers: the traffic cop

### The problem

In production, you have **2 pods** running `<payment-svc>` (see `deploy/prod/deployment.yml`, `replicas: 2`). But the outside world sees **one IP address**. Who decides which pod gets each request?

### What a load balancer does

A load balancer sits in front of multiple servers (or pods) and distributes incoming requests across them.

```
                    ┌──────────┐
                    │  User 1  │
                    └────┬─────┘
                         │
                    ┌────▼─────┐
                    │   Load   │  ← one public IP
                    │ Balancer │
                    └──┬───┬───┘
                       │   │
              ┌────────┘   └────────┐
              ▼                     ▼
         ┌─────────┐          ┌─────────┐
         │  Pod 1  │          │  Pod 2  │
         └─────────┘          └─────────┘
```

### Layer 4 vs Layer 7

| Type | Works at | Sees | Decides based on | Speed |
|------|----------|------|-----------------|-------|
| **L4 (Transport)** | TCP/UDP | Source IP, dest IP, ports | IP + port only | Very fast |
| **L7 (Application)** | HTTP | Full request (URL, headers, cookies) | URL path, Host header, cookies | Slower but smarter |

### Our setup

Azure provisions an **L4 load balancer** automatically when the nginx Ingress Controller is deployed. The chain:

```
User
  │
  ▼
Azure Load Balancer (L4 — TCP level, one public IP)
  │
  │  Doesn't know about /payments vs /subscriptions.
  │  Just forwards TCP connections to the Ingress Controller.
  │
  ▼
nginx Ingress Controller pod (L7 — reads HTTP host/path)
  │
  │  THIS is where the smart routing happens.
  │  Reads the Host header and URL path.
  │
  ├── /<payment-svc>/*  → Service → Payment pods
  ├── /<app>-auth/*         → Service → Auth pods
  └── /other-svc/*           → Service → Other pods
```

So we have **two layers** of load balancing:
1. **Azure LB (L4)** — distributes TCP connections across Ingress Controller replicas
2. **nginx Ingress Controller (L7)** — reads HTTP and routes to the right Service, which then distributes across pods

### Load balancing algorithms

| Algorithm | How it works | When to use |
|-----------|-------------|-------------|
| **Round-robin** | Pod 1, Pod 2, Pod 1, Pod 2, ... | Default. Works for stateless services like ours. |
| **Least connections** | Send to whichever pod has the fewest active requests | Better when requests have varying processing times |
| **IP hash** | Same client IP always goes to same pod | When you need "sticky sessions" (we don't) |

### Health checks

The LB periodically pings each backend ("are you alive?"). If a pod stops responding, the LB stops sending traffic to it. This is why your pods need a `/health` endpoint — our `app/main.py` has one:

```python
@app.get("/health")
def health_check():
    return {"status": "ok"}
```

### Why "sticky sessions" don't matter for us

Some apps store user state in memory (shopping cart, session data). If request 1 goes to Pod 1 and creates a session, request 2 must also go to Pod 1 or the session is lost. That's "sticky sessions."

Our service is **stateless** — all state is in PostgreSQL. Any pod can handle any request. Round-robin is fine.

---

## Part D — Reverse proxy vs forward proxy

### Forward proxy

Sits in front of **clients**. The client knows it's using a proxy.

```
You → Corporate Proxy → Internet → Server
```

Examples: corporate web filter, VPN, `http_proxy` environment variable. The proxy can block sites, log traffic, cache responses.

### Reverse proxy

Sits in front of **servers**. The client doesn't know it's talking to a proxy.

```
User → Reverse Proxy → Server 1
                     → Server 2
                     → Server 3
```

Examples: nginx, Traefik, Cloudflare, AWS ALB.

### Our nginx Ingress Controller is a reverse proxy

It does all of these:

| Job | How |
|-----|-----|
| **TLS termination** | Decrypts HTTPS, forwards plain HTTP to pods (pods don't need certs) |
| **Path rewriting** | `/<payment-svc>/payments/packages` → `/payments/packages` |
| **Rate limiting** | 5000 RPS, 100000 RPM per our annotations |
| **Security headers** | Adds HSTS, X-Frame-Options, etc. |
| **Load balancing** | Distributes requests across pods behind a Service |

Why "reverse"? Because the user thinks they're talking directly to `<dev-backend-host>`. They don't know (or care) that nginx is intercepting their request, stripping the path prefix, and forwarding it to a pod.

---

## Part E — Ports: the full chain

This is the most confusing part of deployment. A request passes through **six layers**, each with its own port number. If any one doesn't match, you get a connection error.

### The chain for our service

| Hop | Port | Set where | Why this value |
|-----|------|-----------|---------------|
| Browser | **443** | HTTPS standard | Always 443 for HTTPS |
| Azure LB | 443 → **80** | LB config (auto) | TLS terminated at Ingress Controller, forwards HTTP on 80 |
| Ingress Controller | **80** | Ingress Controller deployment | Listens for HTTP from the LB |
| K8s Service | port: **80**, targetPort: **80** | `deploy/dev/service.yml` | `port` = what other pods use to reach this service. `targetPort` = the port on the actual pod. |
| Pod | containerPort: **80** | `deploy/dev/deployment.yml` | Informational (doesn't actually restrict), but should match what the app listens on |
| Uvicorn | `--port 80` | `Dockerfile` CMD | What Python actually binds to |

### What breaks if they don't match

- **Service targetPort ≠ container's actual port** → Service sends traffic to a port nobody is listening on → connection refused → 502 from Ingress
- **Dockerfile `--port 80` but `run.sh` uses gunicorn (default 8000)** → works in Docker (uses Dockerfile CMD), breaks if someone runs `bash run.sh` inside the container
- **containerPort says 80 but app listens on 8000** → `containerPort` is just metadata, so the pod starts fine, but the Service (targetPort: 80) can't reach the app → 502

### Quick test

```bash
# Check what port a pod is actually listening on
kubectl exec -n <app>-ns <pod-name> -- ss -tlnp
# or
kubectl exec -n <app>-ns <pod-name> -- netstat -tlnp
```

---

## Part F — Event-driven architecture and webhooks

### Polling vs push

Two ways to find out "did something happen?"

**Polling** (you ask repeatedly):
```
Your server: "Hey Razorpay, did the user pay yet?"     → "No"
Your server: "Hey Razorpay, did the user pay yet?"     → "No"
Your server: "Hey Razorpay, did the user pay yet?"     → "Yes!"
```

Problems: wasteful (99% of requests get "no"), delayed (you only find out at the next poll interval), and doesn't scale.

**Push / webhooks** (they tell you):
```
Razorpay: *user pays*
Razorpay: POST https://your-server/payments/webhook  →  "payment.captured"
Your server: *processes it*
```

Instant, efficient, no wasted requests.

### The pattern generalized

```
Producer (Razorpay)          Consumer (your webhook handler)
       │                              │
       │── event: payment.captured ──▶│
       │                              │── add credits
       │                              │── sync LiteLLM
       │                              │── return 200
```

This is **event-driven architecture**: instead of asking "what happened?", you react to events as they arrive.

### Where you'll see this pattern

| Producer | Event | Consumer |
|----------|-------|----------|
| Razorpay | `payment.captured`, `subscription.charged` | Our webhook handler |
| GitHub | `push`, `pull_request` | CI/CD pipeline |
| Stripe | `invoice.paid`, `customer.subscription.deleted` | Billing service |
| Slack | `message`, `reaction_added` | Slack bot |
| Your service | Could emit events too | Other microservices |

### Pub/sub: webhooks at scale

Webhooks are point-to-point (Razorpay → your server). When you have many producers and many consumers, you use a **message broker**:

```
Producers → [ Message Broker ] → Consumers
             (Kafka, RabbitMQ,
              SQS, Redis Streams)
```

The broker stores events durably and lets multiple consumers process them independently. We don't use one yet, but it's the natural next step if this service grows.

For our specific webhook implementation (verify → process inline, idempotency), see [doc 10 — Webhook Patterns](./10-webhook-patterns.md).

---

## Part G — Idempotency: why "at least once" is the real world

### The problem

Networks are unreliable. Here's what can go wrong with a webhook:

```
Razorpay ── POST /webhook ──▶ Your server
                               │
                               │ processes payment
                               │ adds credits ✓
                               │
                               │── 200 OK ──▶ ... packet lost!
                               
Razorpay: "I never got a 200. Let me retry."

Razorpay ── POST /webhook ──▶ Your server
                               │
                               │ processes payment AGAIN
                               │ adds credits AGAIN ← double credits!
```

This isn't hypothetical. Razorpay (and every webhook provider) retries on timeout or 5xx. You **will** receive duplicate events.

### Delivery guarantees

| Guarantee | Meaning | Who offers it |
|-----------|---------|---------------|
| **At most once** | Might not arrive, but never duplicated | Nobody (too unreliable) |
| **At least once** | Will arrive, but might be duplicated | Razorpay, Stripe, most webhooks |
| **Exactly once** | Arrives exactly once | Almost impossible in distributed systems |

Since we live in an "at least once" world, our handlers must be **idempotent**: running them twice with the same input produces the same result as running once.

### Techniques (with our code)

**1. Atomic conditional update (strongest)**

Our `mark_order_paid()` in `app/services/payment.py`:

```sql
UPDATE razorpay_orders
SET status = 'paid', razorpay_payment_id = :payment_id
WHERE razorpay_order_id = :order_id
  AND status IN ('created', 'failed')
RETURNING *
```

First call: `status` is `'created'` → matches → updates → returns the row.
Second call: `status` is now `'paid'` → doesn't match `IN ('created', 'failed')` → returns nothing.

No race condition possible. The database handles concurrency atomically.

**2. Unique constraint (good, with caveats)**

Our `subscription_invoices` table:

```sql
CREATE UNIQUE INDEX idx_sub_invoices_payment
    ON subscription_invoices (razorpay_payment_id)
    WHERE razorpay_payment_id IS NOT NULL;
```

First INSERT with `razorpay_payment_id = 'pay_ABC'` → succeeds.
Second INSERT with the same value → unique violation → our code catches it and skips.

Slightly weaker than the atomic update: there's a tiny window where two concurrent INSERTs could both pass the pre-check but the DB catches the second one.

**3. Idempotency keys (client-side)**

The client sends a UUID with the request. The server stores it and rejects duplicates. We don't use this pattern, but it's common in payment APIs (Stripe uses it).

### The checklist

For any webhook handler or critical operation, ask:

- [ ] Can this be called twice with the same payload without side effects?
- [ ] Can two identical calls arrive at the exact same time (concurrency)?
- [ ] Does it log clearly when it detects a duplicate?
- [ ] Does it still return success (200) on duplicates?

For details on how our specific handlers score on this checklist, see [doc 10 — Webhook Patterns, Part D](./10-webhook-patterns.md).

---

## Next doc

→ [12 — Deployment Lifecycle](./12-deployment-lifecycle.md) — from code on your laptop to running in the cluster
