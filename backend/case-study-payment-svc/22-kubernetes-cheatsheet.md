# 22 — Kubernetes Cheatsheet

> Mental model: you tell Kubernetes "I want 2 copies of my app running, each with
> 512MB memory, reachable on port 80, and auto-scale if CPU goes above 70%."
> Kubernetes makes it happen and keeps it that way — forever.

---

## Part A — The Big Picture

### What K8s actually does

Without Kubernetes:
- You SSH into a server, run `docker run`, hope it stays up
- Server dies? You manually restart on another machine
- Need 3 copies? You repeat the setup 3 times
- Traffic spike? You panic

With Kubernetes:
- You write a YAML file describing what you want
- `kubectl apply -f deployment.yml`
- Kubernetes ensures your desired state is always true
- Pod dies → K8s restarts it. Node dies → K8s reschedules. Traffic spikes → HPA scales up.

### The architecture

```
┌─────────────────────────────────────────────────────┐
│                   Cluster                            │
│                                                      │
│   Control Plane (master)                             │
│   ├── API Server       ← kubectl talks to this      │
│   ├── Scheduler        ← decides which node runs what│
│   ├── Controller Manager← enforces desired state     │
│   └── etcd             ← stores all cluster state    │
│                                                      │
│   Worker Nodes                                       │
│   ├── Node 1                                         │
│   │   ├── Pod (<payment-svc>)                   │
│   │   └── Pod (another-service)                      │
│   ├── Node 2                                         │
│   │   ├── Pod (<payment-svc>)  ← replica        │
│   │   └── Pod (database)                             │
│   └── Node 3                                         │
│       └── Pod (<payment-svc>)  ← replica        │
└─────────────────────────────────────────────────────┘
```

You interact with the API Server via `kubectl`. Everything else is automatic.

---

## Part B — Core Objects (one-pager)

### Namespace — logical boundary

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <app>-ns
  labels:
    app: <app>
    env: dev
```

Think of it as a folder. All our resources live in `<app>-ns`. Different teams
or environments get different namespaces. Resources in one namespace can't
accidentally interfere with another.

### Pod — smallest deployable unit

A Pod runs one or more containers (usually one). You rarely create Pods directly —
Deployments create them for you.

```yaml
# You never write this manually, but this is what a Pod looks like:
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
    - name: myapp
      image: myregistry/myapp:v1
      ports:
        - containerPort: 80
```

### Deployment — manages Pods

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <payment-svc>
  namespace: <app>-ns
spec:
  replicas: 2                    # run 2 copies
  strategy:
    type: RollingUpdate          # zero-downtime updates
  selector:
    matchLabels:
      app: <payment-svc>    # manage Pods with this label
  template:                      # Pod template
    metadata:
      labels:
        app: <payment-svc>
    spec:
      containers:
        - name: <payment-svc>
          image: <dev-registry>.azurecr.io/<payment-svc>:latest
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 100m          # minimum guaranteed
              memory: 512Mi
            limits:
              cpu: 1             # maximum allowed
              memory: 1Gi
```

A Deployment creates a ReplicaSet, which creates Pods. You update the Deployment,
K8s handles the rest (rolling updates, rollbacks).

### Service — stable network endpoint

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <payment-svc>
  namespace: <app>-ns
spec:
  type: ClusterIP              # internal only (no external access)
  selector:
    app: <payment-svc>    # route traffic to Pods with this label
  ports:
    - port: 80                 # Service listens on 80
      targetPort: 80           # forwards to Pod port 80
```

Pods come and go (scaling, restarts). Their IPs change constantly. A Service
gives you a stable DNS name: `<payment-svc>.<app>-ns.svc.cluster.local`
that always routes to healthy Pods.

| Service Type | Access | Use case |
|-------------|--------|----------|
| ClusterIP | Inside cluster only | Service-to-service calls |
| NodePort | External via node IP:port | Testing, simple setups |
| LoadBalancer | External via cloud LB | Public APIs (expensive: one LB per service) |

We use **ClusterIP** + **Ingress** instead of LoadBalancer to save money.

### HPA — auto-scaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: <payment-svc>-hpa
  namespace: <app>-ns
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: <payment-svc>
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70     # scale up when CPU > 70%
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80     # scale up when memory > 80%
```

HPA watches Pod metrics and adjusts `replicas`. Our config:
- Normal load: 2 Pods
- High CPU: scales up to 10 Pods
- Load drops: scales back down (with a 5-minute stabilization window)

### ConfigMap and Secret

```yaml
# ConfigMap — non-sensitive config
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: <app>-ns
data:
  ENVT: "PROD"
  LOG_LEVEL: "WARNING"

# Secret — sensitive data (base64 encoded)
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: <app>-ns
type: Opaque
data:
  DB_PASSWORD: c3VwZXJzZWNyZXQ=    # base64 of "supersecret"
  RAZORPAY_KEY: cnpwX2xpdmVfeHh4   # base64 of "rzp_live_xxx"
```

Use them in a Deployment:

```yaml
env:
  - name: ENVT
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: ENVT
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: DB_PASSWORD
```

Our current deployment puts env vars directly in the YAML (not ideal — secrets
are visible in git). ConfigMaps and Secrets are the proper way.

---

## Part C — kubectl Essentials

### Syntax

```
kubectl [verb] [resource] [name] [flags]
```

### The commands you'll use daily

**Get — list resources:**

```bash
# All Pods in our namespace
kubectl get pods -n <app>-ns

# Deployments
kubectl get deployments -n <app>-ns

# Services
kubectl get services -n <app>-ns

# Everything in the namespace
kubectl get all -n <app>-ns

# With more details (IP, node, restarts)
kubectl get pods -n <app>-ns -o wide

# Custom columns
kubectl get pods -n <app>-ns -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount
```

**Describe — detailed info + events:**

```bash
# Why is this Pod failing?
kubectl describe pod <payment-svc>-abc123 -n <app>-ns
# Look at the "Events" section at the bottom — that's where the answers are

# Describe a Deployment
kubectl describe deployment <payment-svc> -n <app>-ns
```

**Logs — container output:**

```bash
# Current logs
kubectl logs <payment-svc>-abc123 -n <app>-ns

# Follow logs (real-time)
kubectl logs -f <payment-svc>-abc123 -n <app>-ns

# Previous container's logs (if it crashed and restarted)
kubectl logs --previous <payment-svc>-abc123 -n <app>-ns

# All Pods with a label
kubectl logs -l app=<payment-svc> -n <app>-ns

# Last 100 lines
kubectl logs --tail=100 <payment-svc>-abc123 -n <app>-ns
```

**Exec — shell into a Pod:**

```bash
# Interactive shell
kubectl exec -it <payment-svc>-abc123 -n <app>-ns -- /bin/bash

# Run a one-off command
kubectl exec <payment-svc>-abc123 -n <app>-ns -- python -c "print('hello')"

# Check if the app is listening
kubectl exec <payment-svc>-abc123 -n <app>-ns -- curl -s http://localhost:80/health
```

**Apply — create or update resources:**

```bash
# Apply a single file
kubectl apply -f deploy/dev/deployment.yml

# Apply an entire directory
kubectl apply -f deploy/dev/

# Apply with a dry run (see what would change)
kubectl apply -f deploy/dev/deployment.yml --dry-run=client
```

**Delete — remove resources:**

```bash
# Delete a specific Pod (the Deployment will recreate it)
kubectl delete pod <payment-svc>-abc123 -n <app>-ns

# Delete a Deployment (removes all its Pods)
kubectl delete deployment <payment-svc> -n <app>-ns

# Delete everything from a file
kubectl delete -f deploy/dev/deployment.yml
```

**Port-forward — access a Pod from your laptop:**

```bash
# Forward local port 8080 to Pod port 80
kubectl port-forward <payment-svc>-abc123 8080:80 -n <app>-ns
# Now: http://localhost:8080/health

# Forward to a Service (load-balanced across Pods)
kubectl port-forward svc/<payment-svc> 8080:80 -n <app>-ns
```

**Top — resource usage:**

```bash
# CPU and memory per Pod
kubectl top pods -n <app>-ns

# CPU and memory per Node
kubectl top nodes
```

**Rollout — deployment management:**

```bash
# Check rollout status
kubectl rollout status deployment/<payment-svc> -n <app>-ns

# Rollout history
kubectl rollout history deployment/<payment-svc> -n <app>-ns

# Undo last deployment (rollback)
kubectl rollout undo deployment/<payment-svc> -n <app>-ns

# Restart all Pods (triggers a new rollout with same config)
kubectl rollout restart deployment/<payment-svc> -n <app>-ns
```

---

## Part D — YAML Template Patterns

### The structure every K8s YAML follows

```yaml
apiVersion: apps/v1          # API group and version
kind: Deployment             # What kind of resource
metadata:                    # Identification
  name: myapp                #   unique name
  namespace: mynamespace     #   which namespace
  labels:                    #   key-value tags
    app: myapp
spec:                        # Desired state
  ...                        #   (varies by resource kind)
```

### Labels and selectors (how things find each other)

```
Deployment selector: app=<payment-svc>
        │
        │  "manage Pods with this label"
        ▼
Pod labels: app=<payment-svc>
        │
        │  "route traffic to Pods with this label"
        ▼
Service selector: app=<payment-svc>
```

If the labels don't match, nothing connects. This is the #1 cause of "my Service
has 0 endpoints" bugs.

### Environment variables

Three ways:

```yaml
# 1. Hardcoded (simple but not ideal for secrets)
env:
  - name: ENVT
    value: DEV

# 2. From ConfigMap
env:
  - name: ENVT
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: ENVT

# 3. From Secret
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: DB_PASSWORD
```

### Resource requests and limits

```yaml
resources:
  requests:           # Guaranteed minimum
    cpu: 100m         # 100 millicores = 0.1 CPU core
    memory: 512Mi     # 512 MiB
  limits:             # Hard maximum
    cpu: 1            # 1 full CPU core
    memory: 1Gi       # 1 GiB
```

| | Below request | Between request & limit | Above limit |
|---|---|---|---|
| **CPU** | Never happens (guaranteed) | Can use if available | Throttled (slowed down) |
| **Memory** | Never happens | Can use if available | OOMKilled (process killed) |

CPU units: `1` = 1 core, `100m` = 0.1 core, `500m` = 0.5 core.
Memory units: `Mi` = mebibytes, `Gi` = gibibytes.

### Readiness and liveness probes

```yaml
containers:
  - name: myapp
    livenessProbe:           # "Is the container alive?"
      httpGet:               # Send HTTP GET
        path: /health        # to this path
        port: 80             # on this port
      initialDelaySeconds: 10  # wait 10s before first check
      periodSeconds: 15      # check every 15s
      failureThreshold: 3    # 3 failures → restart container

    readinessProbe:          # "Is the container ready for traffic?"
      httpGet:
        path: /health
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 10
```

| Probe | Fails? | K8s does: |
|-------|--------|-----------|
| Liveness | Container is stuck | Kill and restart it |
| Readiness | Container is booting | Remove from Service (no traffic sent) |

Our deployment doesn't have probes yet — it should. Without them, K8s sends
traffic to a Pod that's still starting up, causing 502 errors.

---

## Part E — Debugging Flow

### Pod won't start

```
kubectl get pods -n <app>-ns
# STATUS: ImagePullBackOff / CrashLoopBackOff / Pending / Error

Step 1: kubectl describe pod <name> -n <app>-ns
        → scroll to "Events" section
        → look for "Failed", "Error", "Warning" messages

Step 2: Based on the status:

  ImagePullBackOff:
    → wrong image name/tag?
    → registry auth missing? (kubectl create secret docker-registry ...)
    → image doesn't exist in registry?
    Fix: kubectl describe pod → look at "Failed to pull image" message

  CrashLoopBackOff:
    → app is crashing on startup
    → kubectl logs <pod> -n <app>-ns
    → kubectl logs --previous <pod> -n <app>-ns (previous crash)
    Common causes: missing env vars, wrong DB host, Python import error

  Pending:
    → not enough CPU/memory on any node
    → nodeSelector doesn't match any node
    → PVC not bound
    Fix: kubectl describe pod → "0/3 nodes are available" message tells you why

  OOMKilled:
    → container exceeded memory limit
    → kubectl describe pod → "OOMKilled" in "Last State"
    Fix: increase memory limit or fix the memory leak
```

### App is running but returning errors

```
Step 1: kubectl logs -f <pod> -n <app>-ns
        → look for Python tracebacks, connection errors, timeouts

Step 2: kubectl exec -it <pod> -n <app>-ns -- /bin/bash
        → curl localhost:80/health (does the app respond?)
        → env (are environment variables set correctly?)
        → python -c "from app.utils.config_utils import get_config; print(get_config('DB_HOST'))"

Step 3: kubectl get svc -n <app>-ns
        → is the Service port correct?
        → kubectl get endpoints <payment-svc> -n <app>-ns
        → does it show Pod IPs? (empty = label mismatch)
```

### Service has 0 endpoints

```bash
kubectl get endpoints <payment-svc> -n <app>-ns
# ENDPOINTS: <none>   ← BAD — no Pods matched!

# Check 1: Do the labels match?
kubectl get pods -n <app>-ns --show-labels
# Compare with:
kubectl get svc <payment-svc> -n <app>-ns -o yaml | grep selector -A5

# Check 2: Are the Pods ready?
kubectl get pods -n <app>-ns
# If STATUS is not "Running" or READY is "0/1", the Pod isn't healthy
```

---

## Part F — Scaling

### Manual scaling

```bash
# Scale to 5 replicas
kubectl scale deployment <payment-svc> --replicas=5 -n <app>-ns

# Scale to 0 (stop all Pods — useful for maintenance)
kubectl scale deployment <payment-svc> --replicas=0 -n <app>-ns
```

### HPA behavior from our config

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 30      # wait 30s before scaling up
    policies:
      - type: Pods
        value: 4                        # add up to 4 Pods per minute
        periodSeconds: 60
  scaleDown:
    stabilizationWindowSeconds: 300     # wait 5 min before scaling down
    policies:
      - type: Pods
        value: 2                        # remove up to 2 Pods per 2 min
        periodSeconds: 120
```

Scale UP is aggressive (30s delay, +4 Pods/min). Scale DOWN is conservative
(5-min delay, -2 Pods/2min). This prevents "flapping" — rapidly scaling up and
down during variable load.

### Check HPA status

```bash
kubectl get hpa -n <app>-ns
# NAME                      REFERENCE                        TARGETS         MINPODS   MAXPODS   REPLICAS
# <payment-svc>-hpa    Deployment/<payment-svc>    45%/70%, 30%/80%   2        10        3

kubectl describe hpa <payment-svc>-hpa -n <app>-ns
# Shows scaling events, current metrics, conditions
```

---

## Part G — Rolling Updates

### How they work

```yaml
strategy:
  type: RollingUpdate
```

When you push a new image:

```
Step 1: K8s creates 1 new Pod with the new image
Step 2: Waits for the new Pod to be Ready
Step 3: Terminates 1 old Pod
Step 4: Repeats until all Pods are updated
```

Zero downtime — there's always at least 1 old Pod serving traffic while new ones
are starting.

### Controlling the rollout

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1           # at most 1 extra Pod during update
    maxUnavailable: 0     # never have fewer than replicas running
```

| Setting | Value | Meaning |
|---------|-------|---------|
| `maxSurge: 1` | 1 | Create at most 1 Pod above desired count |
| `maxUnavailable: 0` | 0 | Never drop below the desired count |
| `maxSurge: 25%` | 25% | For 4 replicas, allow 1 extra |
| `maxUnavailable: 1` | 1 | Allow 1 Pod to be down during update |

### Rollback

```bash
# Something wrong with the new version?
kubectl rollout undo deployment/<payment-svc> -n <app>-ns

# Rollback to a specific revision
kubectl rollout history deployment/<payment-svc> -n <app>-ns
kubectl rollout undo deployment/<payment-svc> --to-revision=3 -n <app>-ns
```

---

## Part H — Networking

### DNS inside the cluster

Every Service gets a DNS name:

```
<service-name>.<namespace>.svc.cluster.local
```

Our Service: `<payment-svc>.<app>-ns.svc.cluster.local`

From any Pod in the cluster:
```bash
curl http://<payment-svc>.<app>-ns.svc.cluster.local/health
# or (within the same namespace):
curl http://<payment-svc>/health
```

### The traffic chain

```
Internet
  │
  ▼
Load Balancer (cloud provider)
  │
  ▼
Ingress Controller (nginx Pod)
  │ reads Ingress rules
  ▼
Service (<payment-svc>, ClusterIP)
  │ load-balances across
  ▼
Pod 1, Pod 2, Pod 3
```

### Port mapping

```
Client → port 443 (HTTPS) → Ingress → port 80 → Service → port 80 → Pod → container port 80
```

Every hop can have a different port. In our case, they're all 80 from Service onward.

---

## Part I — Secrets and ConfigMaps

### Creating from command line

```bash
# ConfigMap from literal values
kubectl create configmap app-config \
  --from-literal=ENVT=PROD \
  --from-literal=LOG_LEVEL=WARNING \
  -n <app>-ns

# Secret from literal values
kubectl create secret generic app-secrets \
  --from-literal=DB_PASSWORD=supersecret \
  --from-literal=RAZORPAY_KEY=rzp_live_xxx \
  -n <app>-ns

# ConfigMap from a file
kubectl create configmap app-config \
  --from-file=app_config.ini \
  -n <app>-ns

# View a Secret (base64 decoded)
kubectl get secret app-secrets -n <app>-ns -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
```

### Mounting as a file (instead of env var)

```yaml
containers:
  - name: myapp
    volumeMounts:
      - name: config-volume
        mountPath: /code/config/
volumes:
  - name: config-volume
    configMap:
      name: app-config
```

This puts the ConfigMap data as files inside `/code/config/` in the container.

### Updating without redeployment

```bash
# Update a ConfigMap
kubectl edit configmap app-config -n <app>-ns

# Pods using env vars from the ConfigMap won't see the change until restart:
kubectl rollout restart deployment/<payment-svc> -n <app>-ns

# Pods using mounted ConfigMaps see changes within ~60 seconds (no restart needed)
```

---

## Part J — Mistakes Students Make

### 1. Forgetting resource limits

```yaml
# BAD — no limits
containers:
  - name: myapp
    image: myapp:v1
    # No resources section → Pod can eat all node memory → OOMKilled other Pods

# GOOD
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### 2. Label mismatch (0 Pods matched)

```yaml
# Deployment creates Pods with label:
template:
  metadata:
    labels:
      app: payment-svc       # ← Pod label

# Service selects:
selector:
  app: <payment-svc>    # ← doesn't match! Different name!
```

Result: Service has 0 endpoints. All traffic gets 502/503.

### 3. Editing live objects instead of YAML files

```bash
# BAD — changes are lost on next kubectl apply
kubectl edit deployment <payment-svc> -n <app>-ns

# GOOD — edit the YAML file, then apply
vim deploy/dev/deployment.yml
kubectl apply -f deploy/dev/deployment.yml
```

Your YAML files are the source of truth. `kubectl edit` makes changes that
drift from your files and confuse everyone.

### 4. `imagePullPolicy: Always` without registry auth

If your cluster can't authenticate to your private registry, every Pod restart
triggers an image pull that fails → ImagePullBackOff.

```bash
# Create registry credentials
kubectl create secret docker-registry acr-auth \
  --docker-server=<dev-registry>.azurecr.io \
  --docker-username=xxx \
  --docker-password=yyy \
  -n <app>-ns

# Reference in Deployment
spec:
  imagePullSecrets:
    - name: acr-auth
```

### 5. Not checking events

```bash
# The first thing to do when something is wrong:
kubectl get events -n <app>-ns --sort-by='.lastTimestamp'
# or
kubectl describe pod <name> -n <app>-ns  # scroll to Events
```

Events tell you exactly what went wrong. Logs tell you what the app said.
Check both.

### 6. Port confusion

```
Dockerfile: EXPOSE 80
Deployment: containerPort: 80
Service: port: 80, targetPort: 80
Ingress: service port: 80

If ANY of these don't match, traffic doesn't flow.
```

---

## Quick Reference Card

```bash
# Status
kubectl get pods -n <app>-ns
kubectl get all -n <app>-ns
kubectl top pods -n <app>-ns

# Debugging
kubectl describe pod <name> -n <app>-ns
kubectl logs <name> -n <app>-ns
kubectl logs --previous <name> -n <app>-ns
kubectl exec -it <name> -n <app>-ns -- /bin/bash
kubectl get events -n <app>-ns --sort-by='.lastTimestamp'

# Deploying
kubectl apply -f deploy/dev/
kubectl rollout status deployment/<payment-svc> -n <app>-ns
kubectl rollout undo deployment/<payment-svc> -n <app>-ns

# Scaling
kubectl scale deployment/<payment-svc> --replicas=3 -n <app>-ns
kubectl get hpa -n <app>-ns

# Access
kubectl port-forward svc/<payment-svc> 8080:80 -n <app>-ns

# Cleanup
kubectl delete -f deploy/dev/deployment.yml
```
