# 14 — Ingress Explained

How external traffic reaches your pods, taught line-by-line from our actual Ingress files.

Prerequisite: [11 — Networking Foundations](./11-networking-foundations.md) (Parts C and D: load balancers and reverse proxies), [13 — Kubernetes Guide](./13-kubernetes-guide.md) (Part B: Services).

---

## Part A — The problem Ingress solves

Without Ingress, every service that needs external access requires its own LoadBalancer:

```
Service A → LoadBalancer A (public IP #1, ~$15/month)
Service B → LoadBalancer B (public IP #2, ~$15/month)
Service C → LoadBalancer C (public IP #3, ~$15/month)
```

With 20 microservices, that's 20 public IPs, 20 load balancers, and no shared TLS or routing logic.

With Ingress:

```
                    ┌──────────────────────────┐
All traffic ──────▶ │  One LoadBalancer ($15)   │
                    │  One Ingress Controller   │
                    └──────┬───────┬───────┬────┘
                           │       │       │
                    Service A  Service B  Service C
```

**Analogy:** The Ingress Controller is the receptionist at an office building. All visitors enter through one door. The receptionist reads who they're here to see (Host header) and what department (URL path), then directs them to the right office (Service).

---

## Part B — Ingress vs Ingress Controller

These are two different things and the naming is confusing:

| | Ingress (resource) | Ingress Controller |
|-|--------------------|--------------------|
| **What** | A YAML config file with routing rules | A running program (nginx, Traefik, etc.) |
| **Analogy** | A routing table on paper | The receptionist who reads the table |
| **Created by** | You (`kubectl apply -f ingress-route.yml`) | Cluster admin (usually pre-installed) |
| **Lives where** | As a K8s object in your namespace | As pods in `ingress-nginx` namespace |
| **Does work?** | No — it's just data | Yes — it processes every request |

Our cluster uses **nginx** as the Ingress Controller (`ingressClassName: nginx`). When you create an Ingress resource, the nginx controller reads it and updates its internal routing config.

```bash
# See the Ingress Controller pods (usually in a system namespace)
kubectl get pods -n ingress-nginx

# See all Ingress resources in our namespace
kubectl get ingress -n <app>-ns
```

---

## Part C — Our Ingress file line by line

**File:** `deploy/dev/ingress-route.yml`

### The basics

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <payment-svc>-ingress
  namespace: <app>-ns
```

Standard K8s resource header. The Ingress lives in `<app>-ns` alongside our Deployment and Service.

### Annotations (the real config)

Most Ingress behavior is controlled through annotations, not the `spec`. This is because different Ingress Controllers (nginx, Traefik, HAProxy) support different features, and annotations are the extension mechanism.

#### TLS and HTTPS

```yaml
nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

If someone visits `http://<dev-backend-host>/...`, redirect them to `https://...`. Never serve over plain HTTP. (See [doc 11 Part B](./11-networking-foundations.md) for why TLS matters.)

#### Path rewriting

```yaml
nginx.ingress.kubernetes.io/use-regex: "true"
nginx.ingress.kubernetes.io/rewrite-target: /$2
```

This is the trickiest part. Our path rule is:

```yaml
path: /<payment-svc>(/|$)(.*)
```

This regex has two capture groups:
- `$1` = `(/|$)` — matches either `/` or end of string
- `$2` = `(.*)` — matches everything after the prefix

`rewrite-target: /$2` means: strip `/<payment-svc>` and keep the rest.

| Incoming URL | `$2` captures | App receives |
|-------------|--------------|-------------|
| `/<payment-svc>/payments/packages` | `payments/packages` | `/payments/packages` |
| `/<payment-svc>/health` | `health` | `/health` |
| `/<payment-svc>/` | (empty) | `/` |
| `/<payment-svc>` | (empty) | `/` |

Without rewriting, FastAPI would see `/<payment-svc>/payments/packages` and return 404 (no route matches that path).

#### Timeouts

```yaml
nginx.ingress.kubernetes.io/proxy-connect-timeout: "60000"
nginx.ingress.kubernetes.io/proxy-send-timeout: "60000"
nginx.ingress.kubernetes.io/proxy-read-timeout: "60000"
```

All in **milliseconds** (60 seconds). If the backend pod takes longer than 60s to respond, nginx returns a 504 Gateway Timeout.

Our payment operations are fast (< 1s), but these generous timeouts prevent false timeouts during DB hiccups or cold starts.

#### Rate limiting

```yaml
nginx.ingress.kubernetes.io/limit-connections: "10000"
nginx.ingress.kubernetes.io/limit-rps: "5000"
nginx.ingress.kubernetes.io/limit-rpm: "100000"
```

| Setting | Value | Meaning |
|---------|-------|---------|
| `limit-connections` | 10000 | Max 10,000 simultaneous connections |
| `limit-rps` | 5000 | Max 5,000 requests per second |
| `limit-rpm` | 100000 | Max 100,000 requests per minute |

These are very generous (effectively no limit for our scale). They protect against accidental DDoS or runaway clients.

#### Request body size

```yaml
nginx.ingress.kubernetes.io/proxy-body-size: 20m
nginx.org/client-max-body-size: "20m"
```

Max request body = 20MB. Requests larger than this get a 413 (Payload Too Large). Our payment requests are tiny (JSON, < 1KB), but this allows room for future endpoints.

#### Security headers

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

`configuration-snippet` injects raw nginx config. Each header is explained in [doc 11 Part B](./11-networking-foundations.md).

`chunked_transfer_encoding on` allows streaming responses (useful if we ever add SSE or streaming AI responses).

### The routing rule

```yaml
spec:
  ingressClassName: nginx          # use the nginx Ingress Controller
  rules:
    - host: <dev-backend-host>     # only match requests to this domain
      http:
        paths:
          - path: /<payment-svc>(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: <payment-svc>    # forward to this Service
                port:
                  number: 80                # on this port
```

`host` must match the `Host` header in the HTTP request. DNS must point this hostname to the LB IP (see [doc 11 Part A](./11-networking-foundations.md)).

`pathType: Prefix` combined with `use-regex: "true"` enables regex path matching.

### Dev vs Prod

The only difference between `deploy/dev/ingress-route.yml` and `deploy/prod/ingress-route.yml`:

| | Dev | Prod |
|-|-----|------|
| `host` | `<dev-backend-host>` | `<backend-host>` |

Everything else (annotations, path, rewrite, headers) is identical.

---

## Part D — Request routing example

A complete trace of a real request:

```
1. Browser: GET https://<dev-backend-host>/<payment-svc>/payments/packages
   │
   │  DNS: <dev-backend-host> → <AZURE_LB_IP>
   │  (doc 11 Part A)
   │
2. Azure Load Balancer (<AZURE_LB_IP>:443)
   │  L4 — forwards TCP to an Ingress Controller pod
   │  (doc 11 Part C)
   │
3. nginx Ingress Controller
   │  TLS termination: decrypts HTTPS → plain HTTP
   │  (doc 11 Part B)
   │
   │  Checks rules:
   │    host: <dev-backend-host> ✓
   │    path: /<payment-svc>/payments/packages
   │      matches /<payment-svc>(/|$)(.*)  ✓
   │      $2 = payments/packages
   │
   │  Rewrites: /<payment-svc>/payments/packages → /payments/packages
   │  Adds headers: HSTS, X-Frame-Options, etc.
   │
   │  Forwards to: <payment-svc>.<app>-ns.svc.cluster.local:80
   │
4. kube-proxy (iptables)
   │  Service ClusterIP 10.96.0.42:80 → Pod IP 10.244.0.15:80
   │  (doc 13 Part C)
   │
5. Pod: uvicorn process
   │  Receives: GET /payments/packages
   │  FastAPI matches route → list_packages()
   │  Returns: [{"id": "pro", "name": "Pro Pack", ...}]
   │
6. Response travels back:
   Pod → kube-proxy → Ingress Controller → (re-encrypts to HTTPS) → LB → Browser
```

Total hops: 5. Total time added by infrastructure: ~1-5ms (mostly TLS handshake on first request).

---

## Part E — Common Ingress bugs

### 404 Not Found

**Symptom:** Browser shows nginx 404 page (not your FastAPI 404).

**Causes:**
- `host` doesn't match the request's Host header (check DNS, check you're hitting the right domain)
- `path` regex doesn't match the URL (test your regex at regex101.com)
- `rewrite-target` is wrong (app receives a path it doesn't have a route for)

**Debug:**
```bash
# Check Ingress is configured
kubectl get ingress -n <app>-ns -o yaml

# Check nginx controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100
```

### 502 Bad Gateway

**Symptom:** nginx returns 502.

**Causes:**
- Service has no endpoints (selector doesn't match any pods)
- Pods are not ready (still starting, or failing health checks)
- Port mismatch (Service targetPort ≠ what the app listens on)

**Debug:**
```bash
# Check if Service has endpoints
kubectl get endpoints <payment-svc> -n <app>-ns
# If ENDPOINTS is <none>, the selector doesn't match any running pods

# Check pod readiness
kubectl get pods -n <app>-ns
# Look for 0/1 in READY column
```

### 413 Request Entity Too Large

**Cause:** Request body exceeds `proxy-body-size` (20MB in our config).

**Fix:** Increase `proxy-body-size` annotation, or send smaller requests.

### 504 Gateway Timeout

**Cause:** Backend took longer than `proxy-read-timeout` (60s in our config).

**Fix:** Optimize the slow endpoint, or increase the timeout annotation.

### Mixed content / TLS errors

**Cause:** Certificate not configured, expired, or doesn't match the hostname.

**Debug:**
```bash
# Check certificate
echo | openssl s_client -connect <dev-backend-host>:443 -servername <dev-backend-host> 2>/dev/null | openssl x509 -noout -dates -subject
```

---

## Part F — Testing Ingress locally

### With minikube

```bash
# Start minikube
minikube start

# Enable the Ingress addon
minikube addons enable ingress

# Wait for the controller to be ready
kubectl get pods -n ingress-nginx -w

# Apply your manifests
kubectl apply -f deploy/dev/namespace.yml
kubectl apply -f deploy/dev/service.yml
kubectl apply -f deploy/dev/deployment.yml
```

Create a simplified Ingress for local testing:

```yaml
# local-ingress.yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: local-test
  namespace: <app>-ns
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: <app>.local
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

```bash
kubectl apply -f local-ingress.yml

# Get minikube's IP
minikube ip
# e.g., 192.168.49.2

# Test with curl (pass Host header manually)
curl -H "Host: <app>.local" http://192.168.49.2/<payment-svc>/health

# Or add to /etc/hosts for browser testing
echo "192.168.49.2 <app>.local" | sudo tee -a /etc/hosts
# Then open http://<app>.local/<payment-svc>/docs
```

---

## Part G — Beyond basics (what to learn next)

### TLS with cert-manager

Automate certificate issuance and renewal:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
```

Then add annotations to your Ingress:
```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - <dev-backend-host>
      secretName: <app>-tls
```

cert-manager automatically gets a Let's Encrypt certificate and renews it before expiry.

### Multiple services, one Ingress

```yaml
rules:
  - host: <dev-backend-host>
    http:
      paths:
        - path: /<payment-svc>(/|$)(.*)
          backend:
            service:
              name: <payment-svc>
              port: { number: 80 }
        - path: /<app>-auth(/|$)(.*)
          backend:
            service:
              name: <app>-auth-svc
              port: { number: 80 }
        - path: /<app>-inference(/|$)(.*)
          backend:
            service:
              name: <app>-inference-svc
              port: { number: 80 }
```

One domain, one LB, many services routed by path prefix.

### Canary deployments

Route a percentage of traffic to a new version:

```yaml
annotations:
  nginx.ingress.kubernetes.io/canary: "true"
  nginx.ingress.kubernetes.io/canary-weight: "10"  # 10% to canary
```

### Monitoring

The nginx Ingress Controller exposes Prometheus metrics:
- Request rate, latency, error rate per Ingress
- Upstream response times
- Connection counts

Useful for dashboards and alerting.

---

## Next doc

→ [15 — Database Internals](./15-database-internals.md) — connection pooling, ACID, transactions, and what happens under load
