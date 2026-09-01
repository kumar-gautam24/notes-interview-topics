# Kubernetes Networking and Ingress

How traffic moves inside and into a Kubernetes cluster — Services, Ingress controllers, TLS termination, DNS, and NetworkPolicies. From internal service-to-service calls to HTTPS routing from the internet.

---

## Table of Contents

1. [Kubernetes Networking Model](#1)
2. [Services — Deep Dive](#2)
3. [Ingress — HTTP Routing from Outside](#3)
4. [TLS Termination with cert-manager](#4)
5. [DNS in Kubernetes](#5)
6. [NetworkPolicies — Firewall Between Pods](#6)
7. [Common Networking Patterns](#7)
8. [Debugging Network Issues](#8)

---

## 1. Kubernetes Networking Model

Kubernetes has a simple, flat networking model:

```
Rule 1: Every pod gets a unique IP address.
Rule 2: Any pod can talk to any other pod directly, using its IP.
         No NAT (Network Address Translation) needed.
Rule 3: Agents on a node can communicate with all pods on that node.
```

```
Node A                          Node B
┌─────────────────────────┐    ┌─────────────────────────┐
│  Pod 1: 10.244.0.1      │    │  Pod 3: 10.244.1.1      │
│  Pod 2: 10.244.0.2      │    │  Pod 4: 10.244.1.2      │
└─────────────────────────┘    └─────────────────────────┘

Pod 1 (10.244.0.1) can directly send packets to Pod 4 (10.244.1.2)
No NAT. Direct routing via the CNI plugin (Flannel, Calico, Cilium, etc.)
```

### CNI Plugin

The CNI (Container Network Interface) plugin implements the networking model. Different plugins, same result:

| Plugin | Highlights |
|--------|-----------|
| Flannel | Simple, low overhead, good for small clusters |
| Calico | Supports NetworkPolicies, BGP routing, good for production |
| Cilium | eBPF-based, best performance, deep observability, Layer 7 policies |
| Weave | Simple, auto-discovery |

Managed clusters (EKS, GKE, AKS) have their own default CNI. You usually don't configure this yourself.

---

## 2. Services — Deep Dive

Services were introduced in `01-kubernetes-fundamentals.md`. Here: how they actually work.

### kube-proxy and iptables

kube-proxy runs on every node and maintains iptables rules that implement Services.

```
Service "my-app" (ClusterIP: 10.96.45.100) → pods: 10.244.0.5, 10.244.1.3

iptables rule (simplified):
  If destination is 10.96.45.100 and port 80:
    → randomly choose one of: 10.244.0.5:8000, 10.244.1.3:8000

This happens on every node.
The ClusterIP never actually exists on any interface — it's a virtual IP.
kube-proxy intercepts traffic destined for it and redirects to real pod IPs.
```

### Service types recap

```yaml
type: ClusterIP      # default. Only reachable inside the cluster.
type: NodePort       # reachable via <any-node-ip>:<node-port>
type: LoadBalancer   # creates a cloud load balancer with external IP
type: ExternalName   # DNS alias to an external service
```

### EndpointSlices — what backs a Service

```bash
# See which pods a Service routes to:
kubectl get endpointslices -l kubernetes.io/service-name=my-app -n production

# Or describe the service:
kubectl describe service my-app -n production
# → "Endpoints: 10.244.0.5:8000,10.244.1.3:8000,10.244.2.7:8000"
```

When a pod fails its readiness probe, it is removed from EndpointSlices. Traffic stops routing to it. When readiness is restored, it is re-added.

### Headless Service — direct pod access

```yaml
spec:
  clusterIP: None    # headless
  selector:
    app: postgres
```

With a headless Service, DNS returns the IP of each individual pod instead of a single virtual IP. Used for StatefulSets where clients need to reach specific pods (primary/replica).

```
Normal Service DNS:
  my-app.namespace.svc.cluster.local → 10.96.45.100 (virtual IP, load-balanced)

Headless Service DNS:
  postgres.namespace.svc.cluster.local → 10.244.0.5, 10.244.1.3, 10.244.2.7 (all pod IPs)
  postgres-0.postgres.namespace.svc.cluster.local → 10.244.0.5 (specific pod)
```

---

## 3. Ingress — HTTP Routing from Outside

A Service of type `LoadBalancer` creates one cloud load balancer per service — expensive. An Ingress handles all external HTTP/HTTPS traffic with one load balancer, routing by hostname and path.

```
                Internet
                   │
            ┌──────┴──────┐
            │    Nginx    │  ← Ingress Controller (one LoadBalancer Service)
            │    Ingress  │
            └──────┬──────┘
                   │
         ┌─────────┼─────────┐
         │         │         │
    ┌────▼────┐ ┌──▼───┐ ┌──▼────┐
    │  api    │ │ app  │ │ docs  │
    │ service │ │svc   │ │ svc   │
    └─────────┘ └──────┘ └───────┘

api.example.com      → api service
app.example.com      → app service
docs.example.com     → docs service
app.example.com/api  → api service  (path-based routing)
```

### Ingress Controller

An Ingress resource alone does nothing. You need an **Ingress Controller** — a running application that reads Ingress resources and configures itself.

Popular Ingress Controllers:
- **Nginx Ingress Controller** (most common, community-supported)
- **Traefik** (auto-discovers services, good for microservices)
- **AWS ALB Ingress Controller** (native AWS Application Load Balancer)
- **GCE Ingress** (GKE's built-in)

```bash
# Install Nginx Ingress Controller:
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Check it's running:
kubectl get pods -n ingress-nginx
kubectl get service -n ingress-nginx ingress-nginx-controller
# → EXTERNAL-IP: 34.123.45.67  (the public IP for your domain)
```

### Ingress YAML — basic

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /   # rewrite URL path
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"  # max upload size
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
spec:
  ingressClassName: nginx        # which controller handles this Ingress

  rules:
    # Route by hostname:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 80

    # Multiple paths on same host:
    - host: example.com
      http:
        paths:
          - path: /api
            pathType: Prefix     # matches /api, /api/users, /api/anything
            backend:
              service:
                name: api-service
                port:
                  number: 80

          - path: /
            pathType: Prefix     # catch-all — must come last
            backend:
              service:
                name: frontend-service
                port:
                  number: 80
```

### pathType values

```
Exact:   /api    matches only /api    (not /api/, not /api/users)
Prefix:  /api    matches /api, /api/, /api/users, /api/v1/posts
ImplementationSpecific: depends on controller
```

### Ingress for multiple domains

```yaml
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80

    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: backend
                port:
                  number: 80

    - host: docs.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: docs
                port:
                  number: 80
```

---

## 4. TLS Termination with cert-manager

cert-manager automates TLS certificate issuance and renewal from Let's Encrypt (or other CAs).

### Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Wait for it to be ready:
kubectl get pods -n cert-manager
```

### Create a ClusterIssuer (Let's Encrypt)

```yaml
# letsencrypt-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: you@example.com         # required by Let's Encrypt
    server: https://acme-v02.api.letsencrypt.org/directory  # production
    # For testing (no rate limits):
    # server: https://acme-staging-v02.api.letsencrypt.org/directory

    privateKeySecretRef:
      name: letsencrypt-prod-key   # stores the account private key

    solvers:
      - http01:
          ingress:
            ingressClassName: nginx  # same as your Ingress class
```

```bash
kubectl apply -f letsencrypt-issuer.yaml
kubectl describe clusterissuer letsencrypt-prod
```

### Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  namespace: production
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"   # cert-manager annotation
    nginx.ingress.kubernetes.io/ssl-redirect: "true"      # redirect HTTP → HTTPS
spec:
  ingressClassName: nginx

  tls:
    - hosts:
        - example.com
        - api.example.com
      secretName: example-tls      # cert-manager stores the certificate here

  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80

    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: backend
                port:
                  number: 80
```

**What happens:**
1. You apply the Ingress
2. cert-manager sees the annotation and requests a certificate from Let's Encrypt
3. Let's Encrypt validates domain ownership (via HTTP challenge on `/.well-known/acme-challenge/`)
4. cert-manager stores the certificate in Secret `example-tls`
5. Nginx reads the certificate and serves HTTPS
6. cert-manager auto-renews before expiry (~30 days before the 90-day cert expires)

```bash
# Check certificate status:
kubectl get certificates -n production
kubectl describe certificate example-tls -n production

# Check certificate request:
kubectl get certificaterequests -n production
```

---

## 5. DNS in Kubernetes

CoreDNS runs in the cluster and provides DNS resolution for:

### Service DNS

```
Format: <service-name>.<namespace>.svc.cluster.local

my-app.production.svc.cluster.local   → 10.96.45.100 (ClusterIP)
redis.production.svc.cluster.local    → 10.96.12.34

Short forms (from within the same namespace):
  my-app                               → my-app.production.svc.cluster.local
  redis                                → redis.production.svc.cluster.local

From different namespace:
  my-app.production                    → my-app.production.svc.cluster.local
```

### Pod DNS

```
Format: <pod-ip-with-dashes>.<namespace>.pod.cluster.local

10-244-0-5.production.pod.cluster.local   → Pod at 10.244.0.5
```

### DNS configuration in pods

```yaml
spec:
  dnsConfig:
    nameservers:
      - 1.1.1.1                    # additional DNS servers
    searches:
      - production.svc.cluster.local
      - svc.cluster.local
    options:
      - name: ndots
        value: "5"                 # number of dots before using search domain
  dnsPolicy: ClusterFirst          # default: use cluster DNS, fall back to upstream
  # ClusterFirstWithHostNet: for pods using hostNetwork: true
  # None: fully custom DNS config
```

### Debugging DNS

```bash
# Test DNS resolution from inside a pod:
kubectl run dns-test --image=busybox:1.35 -it --rm --restart=Never -- nslookup my-app.production.svc.cluster.local

kubectl run dns-test --image=busybox:1.35 -it --rm --restart=Never -- nslookup kubernetes.default

# Or exec into a running pod:
kubectl exec -it my-pod -- nslookup redis

# Check CoreDNS logs:
kubectl logs -n kube-system -l k8s-app=kube-dns -f

# Check CoreDNS config:
kubectl get configmap coredns -n kube-system -o yaml
```

---

## 6. NetworkPolicies — Firewall Between Pods

By default, any pod can talk to any other pod. NetworkPolicies define allow/deny rules.

**Important:** NetworkPolicies require a CNI plugin that supports them (Calico, Cilium, Weave). Flannel alone does not enforce NetworkPolicies.

### Default deny all

```yaml
# Deny all ingress and egress for pods in the 'production' namespace:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}          # {} = all pods in namespace
  policyTypes:
    - Ingress
    - Egress
```

After this: no pod can communicate with anything. Add specific allow rules on top.

### Allow specific traffic

```yaml
# Allow the web pod to receive traffic from nginx on port 8000:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-to-web
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web               # this policy applies to pods with app=web
  policyTypes:
    - Ingress

  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: nginx     # only allow from pods with app=nginx
      ports:
        - protocol: TCP
          port: 8000
```

```yaml
# Allow the web pod to reach the database:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
    - Ingress

  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: web
      ports:
        - protocol: TCP
          port: 5432
```

### Allow egress to external DNS

```yaml
# Allow all pods in namespace to reach DNS:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to: []
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### Cross-namespace communication

```yaml
# Allow the 'monitoring' namespace to scrape metrics from 'production':
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            name: monitoring    # namespace must have this label
        podSelector:
          matchLabels:
            app: prometheus
    ports:
      - port: 9090
```

```bash
# Label a namespace:
kubectl label namespace monitoring name=monitoring

# Check existing policies:
kubectl get networkpolicies -n production
kubectl describe networkpolicy allow-web-to-db -n production
```

---

## 7. Common Networking Patterns

### Pattern: Service mesh with Istio/Linkerd

A service mesh adds a proxy sidecar to every pod that handles:
- mTLS (mutual TLS between services — encrypted + authenticated)
- Traffic shaping (canary deployments, circuit breaker, retries)
- Observability (traces, metrics per service)

```
Without service mesh:
  Pod A → HTTP → Pod B    (unencrypted, no auth)

With Istio:
  Pod A → Envoy sidecar → mTLS → Envoy sidecar → Pod B
  (encrypted, authenticated, observable, controllable)
```

Use Istio/Linkerd when you need:
- Zero-trust networking (all traffic encrypted)
- Fine-grained traffic control between services
- Automatic retry and circuit breaking at the network layer

### Pattern: Canary deployment via Ingress

Route 10% of traffic to the new version:

```yaml
# Primary Ingress (90% of traffic):
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-primary
  namespace: production
spec:
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app-v1
                port:
                  number: 80

---
# Canary Ingress (10% of traffic):
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-canary
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"   # 10% of traffic
spec:
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app-v2
                port:
                  number: 80
```

---

## 8. Debugging Network Issues

```bash
# 1. Can pods reach each other?
# Run a debug pod in the same namespace:
kubectl run netdebug -it --rm --image=nicolaka/netshoot --restart=Never -- bash

# Inside netdebug pod:
curl http://my-app.production.svc.cluster.local/health
nslookup my-app.production.svc.cluster.local
ping 10.244.0.5    # ping another pod directly
nc -zv db 5432     # check TCP connectivity to DB

# 2. Is the Service pointing to healthy endpoints?
kubectl get endpoints my-app -n production
# If empty: no pods match the selector or pods failing readiness probe

kubectl describe service my-app -n production

# 3. Check pod labels match service selector:
kubectl get pods -n production -l app=my-app     # what pods have this label?
kubectl get service my-app -n production -o yaml  # what label does service select?

# 4. Check Ingress is configured correctly:
kubectl describe ingress my-ingress -n production
kubectl get ingress -n production

# Check Ingress controller logs:
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# 5. Check NetworkPolicy:
kubectl get networkpolicies -n production
# NetworkPolicy blocking traffic? Temporarily delete it to test:
kubectl delete networkpolicy default-deny-all -n production  # temporary test

# 6. Check if service port is correct:
kubectl exec -it my-pod -- curl localhost:8000/health   # is app listening on right port?

# 7. DNS issues:
kubectl exec -it my-pod -- nslookup kubernetes.default    # basic DNS works?
kubectl exec -it my-pod -- nslookup my-app                # short name works?
kubectl exec -it my-pod -- cat /etc/resolv.conf           # DNS config

# 8. External connectivity from pod:
kubectl exec -it my-pod -- curl https://google.com        # can pods reach internet?
kubectl exec -it my-pod -- curl http://169.254.169.254    # AWS metadata endpoint
```

---

*Previous: Workloads, storage, HPA, probes → `02-workloads-and-storage.md`*
*Next: RBAC, Helm, monitoring, production operations → `04-production-and-operations.md`*
