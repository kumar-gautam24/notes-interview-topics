# 23 — Ingress Cheatsheet

> Mental model: Ingress is the front door of your building. One door, many offices
> inside. Without it, every office (Service) would need its own street entrance
> (LoadBalancer) — expensive and messy.

---

## Part A — The Problem Ingress Solves

### Without Ingress

Every Service that needs external access gets its own LoadBalancer:

```
payment-svc  → LoadBalancer 1 → public IP 1 ($18/month)
user-svc     → LoadBalancer 2 → public IP 2 ($18/month)
admin-svc    → LoadBalancer 3 → public IP 3 ($18/month)
model-svc    → LoadBalancer 4 → public IP 4 ($18/month)
```

4 services = 4 LoadBalancers = 4 public IPs = ~$72/month just for routing.
Plus: no shared TLS, no shared rate limiting, no path-based routing.

### With Ingress

One LoadBalancer, one IP, Ingress rules route traffic:

```
                        ┌──→ payment-svc  (ClusterIP)
browser → LB → Ingress ─┤
                        ├──→ user-svc     (ClusterIP)
                        └──→ admin-svc    (ClusterIP)
```

Cost: 1 LoadBalancer (~$18/month). All features (TLS, rate limiting, path rewriting)
in one place.

---

## Part B — Ingress vs Ingress Controller

These are two different things:

| | Ingress (Resource) | Ingress Controller |
|---|---|---|
| **What** | A YAML config file | A running Pod (nginx, traefik, etc.) |
| **Does** | Declares routing rules | Reads rules and enforces them |
| **Analogy** | A sign saying "Room 101: Payments" | The receptionist who reads the sign and directs visitors |
| **You create** | `kubectl apply -f ingress.yml` | Installed once per cluster (by infra team) |

The Ingress resource is useless without a controller. The controller is useless
without Ingress rules. You need both.

### Common controllers

| Controller | Maintained by | Notes |
|-----------|--------------|-------|
| **nginx-ingress** | Kubernetes community | Most popular, what we use |
| **NGINX Inc** | F5/NGINX | Commercial version, more features |
| **Traefik** | Traefik Labs | Auto-discovery, good for dynamic environments |
| **HAProxy** | HAProxy Technologies | High performance |
| **AWS ALB** | AWS | Native AWS integration |

Our cluster uses `nginx-ingress` (the `ingressClassName: nginx` field).

---

## Part C — Our Ingress YAML (line by line)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <payment-svc>-ingress
  namespace: <app>-ns
```

Standard K8s resource header. Lives in our `<app>-ns` namespace.

### Annotations — the power features

Annotations are key-value pairs that configure the Ingress Controller's behavior.
They're not part of the Kubernetes Ingress spec — they're controller-specific.

```yaml
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
```
Force HTTPS. If someone hits `http://`, redirect to `https://`.

```yaml
    nginx.ingress.kubernetes.io/use-regex: "true"
```
Enable regex in path matching (needed for our rewrite-target pattern).

```yaml
    nginx.ingress.kubernetes.io/rewrite-target: /$2
```
Strip the service prefix from the URL before forwarding. The `$2` refers to the
second capture group in our path regex.

```
Incoming:  /<payment-svc>/payments/orders
                                ↓ rewrite
Forwarded: /payments/orders
```

Without this, FastAPI would receive `/<payment-svc>/payments/orders` and
return 404 (no route matches that path).

```yaml
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "60000"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60000"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60000"
```
Timeout configuration (in milliseconds):
- **connect**: how long to wait for a TCP connection to the backend
- **send**: how long to wait when sending request to the backend
- **read**: how long to wait for the backend to respond

60 seconds is generous — our endpoints are fast, but some webhook processing or
Razorpay calls can be slow.

```yaml
    nginx.ingress.kubernetes.io/proxy-body-size: 20m
```
Maximum request body size. Default is 1MB. We set 20MB to handle larger payloads.

```yaml
    nginx.ingress.kubernetes.io/limit-connections: "10000"
    nginx.ingress.kubernetes.io/limit-rps: "5000"
    nginx.ingress.kubernetes.io/limit-rpm: "100000"
```
Rate limiting:
- Max 10,000 concurrent connections
- Max 5,000 requests per second
- Max 100,000 requests per minute

These are high limits — more of a DDoS safety net than actual throttling.

```yaml
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
```
Tell the controller that our backend speaks HTTP (not HTTPS). The TLS terminates
at the Ingress, so internal traffic is plain HTTP.

```yaml
    nginx.ingress.kubernetes.io/configuration-snippet: |
      chunked_transfer_encoding on;
      more_set_headers "Cross-Origin-Opener-Policy: same-origin";
      more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
      more_set_headers "Strict-Transport-Security: max-age=31556926; includeSubDomains";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-XSS-Protection: 1; mode=block";
```
Raw nginx config injected into the server block. This adds security headers to
every response. These are the same headers from `security_utils.py` — applied at
the infrastructure level so they can't be forgotten in application code.

### Spec — the routing rules

```yaml
spec:
  ingressClassName: nginx
```
Which Ingress Controller handles this resource. Must match the controller installed
in the cluster.

```yaml
  rules:
    - host: <dev-backend-host>
```
Only handle requests for this hostname. Requests to other hostnames are ignored.

```yaml
      http:
        paths:
          - path: /<payment-svc>(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: <payment-svc>
                port:
                  number: 80
```

| Part | Meaning |
|------|---------|
| `path: /<payment-svc>(/\|$)(.*)` | Match URLs starting with `/<payment-svc>` |
| `(/\|$)` | Followed by `/` or end-of-string (so `/<payment-svc>` and `/<payment-svc>/` both match) |
| `(.*)` | Capture everything after (this is the `$2` in rewrite-target) |
| `pathType: Prefix` | Match this path and anything under it |
| `service.name` | Forward to the `<payment-svc>` Service |
| `port.number: 80` | On port 80 |

### Request trace example

```
1. Browser sends: GET https://<dev-backend-host>/<payment-svc>/payments/orders

2. DNS resolves <dev-backend-host> → LoadBalancer IP

3. LoadBalancer forwards to Ingress Controller Pod

4. Ingress Controller checks rules:
   - host: <dev-backend-host> ✓
   - path: /<payment-svc>(/|$)(.*) ✓
   - captures: $1 = "/" , $2 = "payments/orders"

5. Rewrite: /$2 = /payments/orders

6. Forward to: <payment-svc>:80/payments/orders

7. Service load-balances to one of the Pods

8. Pod receives: GET /payments/orders
   FastAPI matches @router.get("/orders") → handler runs

9. Response flows back: Pod → Service → Ingress → LB → Browser
   (with security headers added by the configuration-snippet)
```

---

## Part D — TLS / HTTPS

### How HTTPS works at the Ingress level

```
Browser ──HTTPS──→ Ingress ──HTTP──→ Service ──HTTP──→ Pod
         (encrypted)       (plain text inside cluster)
```

TLS terminates at the Ingress Controller. Internal traffic is unencrypted (faster,
simpler, and safe inside the cluster network).

### Adding TLS to an Ingress

```yaml
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - <dev-backend-host>
      secretName: rnp-dev-tls    # K8s Secret containing the cert + key
  rules:
    - host: <dev-backend-host>
      ...
```

The TLS Secret contains:

```bash
kubectl create secret tls rnp-dev-tls \
  --cert=fullchain.pem \
  --key=privkey.pem \
  -n <app>-ns
```

### Auto-certificates with cert-manager

Instead of manually creating TLS Secrets, cert-manager automates it:

1. Install cert-manager in the cluster
2. Create a ClusterIssuer (e.g. Let's Encrypt)
3. Add one annotation to your Ingress:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-prod
```

cert-manager will:
- Request a certificate from Let's Encrypt
- Prove you own the domain (HTTP-01 or DNS-01 challenge)
- Store the cert as a K8s Secret
- Auto-renew before it expires

---

## Part E — Multiple Services

### One Ingress, multiple paths

```yaml
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /payments(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: payment-svc
                port:
                  number: 80
          - path: /users(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: user-svc
                port:
                  number: 80
          - path: /models(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: model-svc
                port:
                  number: 80
```

### Multiple hosts (subdomains)

```yaml
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 80
    - host: admin.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: admin-svc
                port:
                  number: 80
```

### pathType explained

| pathType | `/foo` matches | `/foo/bar` matches | `/foobar` matches |
|----------|---------------|-------------------|-------------------|
| **Exact** | yes | no | no |
| **Prefix** | yes | yes | yes (!) |
| **ImplementationSpecific** | depends on controller | depends | depends |

The Prefix gotcha: `/foo` as a Prefix also matches `/foobar`. If you have
`/payment` and `/payment-admin`, both match `/payment-admin`. Order your paths
from most specific to least specific, or use Exact where possible.

---

## Part F — Annotations Reference

### Must-know annotations for nginx-ingress

| Annotation | Value | What it does |
|-----------|-------|-------------|
| `ssl-redirect` | `"true"` | Force HTTPS |
| `use-regex` | `"true"` | Enable regex in path |
| `rewrite-target` | `/$2` | Rewrite URL before forwarding |
| `proxy-body-size` | `20m` | Max request body |
| `proxy-connect-timeout` | `"60"` | Backend connection timeout (seconds) |
| `proxy-read-timeout` | `"60"` | Backend response timeout |
| `proxy-send-timeout` | `"60"` | Backend send timeout |
| `limit-rps` | `"100"` | Rate limit: requests per second |
| `limit-rpm` | `"6000"` | Rate limit: requests per minute |
| `limit-connections` | `"50"` | Max concurrent connections |
| `backend-protocol` | `"HTTP"` | Protocol to the backend |
| `cors-allow-origin` | `"*"` | CORS allowed origins |
| `cors-allow-methods` | `"GET, POST"` | CORS allowed methods |
| `affinity` | `"cookie"` | Sticky sessions (same user → same Pod) |
| `proxy-buffering` | `"off"` | Disable buffering (for streaming) |
| `configuration-snippet` | nginx config | Raw nginx directives |
| `server-snippet` | nginx config | Nginx directives at server level |
| `whitelist-source-range` | `10.0.0.0/8` | IP whitelist |
| `auth-type` | `basic` | HTTP basic auth |

### Streaming-specific (commented out in our config)

```yaml
# For SSE (Server-Sent Events) or streaming responses:
nginx.ingress.kubernetes.io/proxy-buffering: "off"
nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
```

These are commented out in our Ingress but would be needed if we add streaming
endpoints (e.g. streaming AI model responses).

---

## Part G — Debugging Ingress

### The debugging checklist

```
1. Is the Ingress resource created?
   kubectl get ingress -n <app>-ns

2. Does it have an ADDRESS?
   kubectl get ingress -n <app>-ns
   # ADDRESS column should show an IP or hostname
   # If blank: Ingress Controller isn't processing it

3. Check Ingress details:
   kubectl describe ingress <payment-svc>-ingress -n <app>-ns
   # Look for:
   #   - "Default backend" errors
   #   - Events section for warnings

4. Is the backend Service healthy?
   kubectl get endpoints <payment-svc> -n <app>-ns
   # Should show Pod IPs. If empty → labels don't match.

5. Can you reach the Pod directly?
   kubectl port-forward svc/<payment-svc> 8080:80 -n <app>-ns
   curl http://localhost:8080/health
   # If this works but Ingress doesn't → Ingress config issue
   # If this also fails → app/Service issue

6. Check Ingress Controller logs:
   kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx
   # Look for 502, 503 errors, connection refused, timeouts
```

### Common errors and fixes

**502 Bad Gateway:**
```
Cause: Ingress can reach the Service but the Service can't reach a healthy Pod.
Check:
  - kubectl get endpoints <service> -n <ns>  → any IPs listed?
  - kubectl get pods -n <ns>  → are Pods Running and Ready?
  - Is the containerPort correct?
```

**503 Service Unavailable:**
```
Cause: No backend endpoints available.
Check:
  - Same as 502
  - Also check if all Pods are in CrashLoopBackOff
```

**504 Gateway Timeout:**
```
Cause: Backend took too long to respond.
Check:
  - proxy-read-timeout annotation (increase if needed)
  - Is the backend actually slow? (long DB queries, external API calls)
  - kubectl logs <pod> to see what's taking time
```

**404 Not Found:**
```
Cause: Path doesn't match any Ingress rule OR path rewriting is wrong.
Check:
  - Is use-regex enabled? (needed for capture groups)
  - Does the rewrite-target correctly strip the prefix?
  - Test: curl the backend directly via port-forward
    curl http://localhost:8080/payments/orders  ← does this path exist?
```

**DNS not resolving:**
```
Cause: Domain doesn't point to the LoadBalancer IP.
Check:
  - kubectl get ingress -n <ns>  → note the ADDRESS
  - nslookup <dev-backend-host>  → does it resolve to that ADDRESS?
  - If not → DNS record needs updating
```

**TLS certificate error:**
```
Cause: Missing or expired TLS Secret.
Check:
  - kubectl get secret <tls-secret> -n <ns>
  - kubectl describe certificate <name> -n <ns>  (if using cert-manager)
  - openssl s_client -connect <dev-backend-host>:443  → check cert dates
```

---

## Part H — Dev vs Prod Differences (our files)

| Setting | Dev (`deploy/dev/`) | Prod (`deploy/prod/`) |
|---------|--------------------|-----------------------|
| Host | `<dev-backend-host>` | `<backend-host>` |
| Replicas | 1 (no HPA) | 2 (with HPA up to 10) |
| nodeSelector | `agentpool: <app>poc` | `kubernetes.io/os: linux` |
| Registry | `<dev-registry>.azurecr.io` | `<prod-registry>.azurecr.io` |
| ENVT | `DEV` | `PROD` |

Same Ingress annotations in both — security headers, rate limits, and timeouts
apply equally.

---

## Part I — Mistakes Students Make

### 1. Wrong pathType

```yaml
# You want exact path matching for /api
pathType: Prefix
path: /api
# This also matches /api-admin, /api2, /apifoo — probably not what you want!

# Fix: use Exact or a regex with end anchor
pathType: Exact
path: /api
```

### 2. Missing IngressClass

```yaml
# If you omit ingressClassName, no controller picks it up
spec:
  # ingressClassName: nginx  ← forgot this!
  rules:
    ...
# Result: Ingress has no ADDRESS, nothing works
```

### 3. Annotation typos (silent failures)

```yaml
# Typo — no error, just silently ignored
nginx.ingress.kubernetes.io/ssl-rediect: "true"   # "rediect" not "redirect"

# Correct
nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

Annotations are free-form strings. K8s doesn't validate them. A typo means the
feature just doesn't activate — no error message, no warning. Always copy
annotation names from documentation.

### 4. Backend Service name mismatch

```yaml
# Ingress routes to:
backend:
  service:
    name: payment-svc     # ← this Service must exist!
    port:
      number: 80

# But your Service is actually named:
# name: <payment-svc>
```

Result: 503. The Ingress can't find the Service. Check with:
```bash
kubectl get svc -n <app>-ns
```

### 5. Forgetting rewrite-target with prefixed paths

```yaml
# Your app expects: /payments/orders
# URL is: /<payment-svc>/payments/orders

# Without rewrite: FastAPI receives /<payment-svc>/payments/orders → 404
# With rewrite:    FastAPI receives /payments/orders → 200
```

If you add a new service behind an Ingress with a path prefix, you MUST set up
`rewrite-target` or your app will get the wrong paths.

### 6. Not testing with port-forward first

Before blaming Ingress, verify the app works:

```bash
# Bypass Ingress entirely — talk directly to the Service
kubectl port-forward svc/<payment-svc> 8080:80 -n <app>-ns
curl http://localhost:8080/health

# If this fails → the problem is your app or Service, not Ingress
# If this works → the problem is in Ingress config
```

Always isolate the problem layer.

---

## Quick Reference

```bash
# Check Ingress
kubectl get ingress -n <app>-ns
kubectl describe ingress <payment-svc>-ingress -n <app>-ns

# Check backends
kubectl get endpoints <payment-svc> -n <app>-ns

# Ingress Controller logs
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --tail=100

# Test without Ingress (bypass)
kubectl port-forward svc/<payment-svc> 8080:80 -n <app>-ns

# Test with curl
curl -v https://<dev-backend-host>/<payment-svc>/health

# Check TLS cert
openssl s_client -connect <dev-backend-host>:443 -servername <dev-backend-host>
```
