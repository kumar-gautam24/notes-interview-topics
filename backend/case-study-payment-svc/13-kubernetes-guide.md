# 13 — Kubernetes from Zero

Everything you need to understand Kubernetes, taught using the files in this repo.

Prerequisite: [11 — Networking Foundations](./11-networking-foundations.md), [12 — Deployment Lifecycle](./12-deployment-lifecycle.md) (at least Parts A-B).

---

## Part A — What problem does K8s solve?

You have a Docker image. You can run it on your laptop with `docker run`. But in production you need:

| Need | Without K8s | With K8s |
|------|------------|----------|
| **Run on a server** | SSH in, `docker run` manually | `kubectl apply` — K8s picks a server |
| **Restart on crash** | Write a systemd service or hope someone notices | K8s auto-restarts crashed pods |
| **Scale up** | SSH in, run more containers, configure a load balancer | Change `replicas: 5` or let HPA do it |
| **Update without downtime** | Stop old container, start new one (users see errors) | Rolling update — new pods start before old ones stop |
| **Multiple services** | Manage ports, networking, DNS yourself | K8s Services give each app a stable internal address |

**Analogy:** Docker is like having a shipping container. Kubernetes is the port — it decides which ship carries your container, moves it if a ship sinks, and makes sure cargo gets to the right destination.

---

## Part B — Core objects

Every Kubernetes resource is a YAML file that declares "I want this to exist." K8s continuously works to make reality match your declaration.

### Namespace

**What:** An isolation boundary. Like folders on a filesystem — keeps resources organized and separated.

**Our file:** `deploy/dev/namespace.yml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <app>-ns
  labels:
    app: <app>
    env: dev
```

Everything we deploy goes into `<app>-ns`. Other teams deploy into their own namespaces. This prevents name collisions (two teams can both have a Service called `api` in different namespaces).

**Why not `default`?** The `default` namespace is shared by everyone. No isolation, easy to accidentally delete someone else's stuff.

### Pod

**What:** The smallest deployable unit. A pod is one or more containers that share networking and storage.

You almost never create pods directly. You create a Deployment, which creates pods for you. If a pod dies, the Deployment creates a replacement.

Think of a pod as a single instance of your application. Our service runs one container per pod (the Python/uvicorn process).

### Deployment

**What:** Declares "I want N copies of this container running at all times." Handles rolling updates, rollbacks, and self-healing.

**Our file:** `deploy/dev/deployment.yml` — every field explained:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <payment-svc>      # name of this Deployment object
  namespace: <app>-ns           # which namespace it lives in
```

```yaml
spec:
  replicas: 1                    # how many pods to run (dev=1, prod=2)
```

```yaml
  strategy:
    type: RollingUpdate          # update pods one at a time, not all at once
```

RollingUpdate means: start a new pod with the new image → wait until it's healthy → kill an old pod → repeat. Users never see downtime.

The alternative `Recreate` kills all old pods first, then starts new ones. Causes downtime but is simpler.

```yaml
  selector:
    matchLabels:
      app: <payment-svc>    # "manage pods that have this label"
```

This ties the Deployment to its pods. The Deployment only manages pods with `app: <payment-svc>`. Critical — if this doesn't match the template labels below, the Deployment can't find its own pods.

```yaml
  template:                      # template for creating pods
    metadata:
      labels:
        app: <payment-svc>  # pods get this label (must match selector above)
    spec:
      nodeSelector:
        agentpool: <app>poc     # only schedule on nodes in this pool
        app: <app>
```

`nodeSelector` constrains which cluster nodes can run this pod. Dev uses a specific node pool (`<app>poc`). Prod uses `kubernetes.io/os: linux` (any Linux node).

```yaml
      containers:
        - name: <payment-svc>
          image: <dev-registry>.azurecr.io/<payment-svc>:latest
          env:
            - name: ENVT
              value: DEV
            - name: OPENAI_API_KEY
              value: "sk-proj-..."     # should be a Secret (see doc 12 Part F)
          ports:
            - containerPort: 80        # informational: app listens on 80
```

```yaml
          resources:
            requests:
              cpu: 100m               # "I need at least 0.1 CPU cores"
              memory: 512Mi           # "I need at least 512MB RAM"
            limits:
              cpu: 1                  # "never use more than 1 CPU core"
              memory: 1Gi             # "never use more than 1GB RAM"
```

`requests` = minimum guaranteed. K8s uses this for scheduling (finding a node with enough free resources). `limits` = hard cap. Exceed memory limit → OOMKilled. Exceed CPU limit → throttled (slowed down, not killed).

```yaml
          volumeMounts:
            - name: blob-user-data
              mountPath: "/mnt/"
      volumes:
        - name: blob-user-data
          persistentVolumeClaim:
            claimName: pvc-blob-<app>-user-data
```

Mounts Azure Blob Storage at `/mnt/` inside the container. The PVC (PersistentVolumeClaim) is defined elsewhere — not in this repo.

### Service

**What:** A stable network identity for a set of pods. Pods come and go (crashes, updates, scaling), but the Service always has the same internal address.

**Our file:** `deploy/dev/service.yml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <payment-svc>
  namespace: <app>-ns
spec:
  type: ClusterIP               # internal-only (no external IP)
  selector:
    app: <payment-svc>      # route traffic to pods with this label
  ports:
    - port: 80                   # other services connect to this port
      targetPort: 80             # forward to this port on the pod
```

**ClusterIP** = only reachable from inside the cluster. Other pods (and the Ingress Controller) can reach it at `<payment-svc>.<app>-ns.svc.cluster.local:80`. External users cannot.

The `selector` is the glue. The Service watches for pods with `app: <payment-svc>` and automatically routes traffic to them. When a pod dies and a new one starts, the Service updates its routing — no manual config.

**Service types:**

| Type | Reachable from | Use case |
|------|---------------|----------|
| **ClusterIP** | Inside cluster only | Internal services (ours) |
| **NodePort** | Cluster + node IPs | Testing, simple external access |
| **LoadBalancer** | Internet | Provisions a cloud LB (expensive per service) |

We use ClusterIP + Ingress instead of LoadBalancer. One Ingress Controller with one LoadBalancer routes to many Services. See [doc 14](./14-ingress-guide.md).

### HPA (Horizontal Pod Autoscaler)

**What:** Automatically adjusts the number of pods based on resource usage.

**Our file:** `deploy/prod/hpa.yml` (prod only — dev doesn't auto-scale)

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: <payment-svc>     # which Deployment to scale
  minReplicas: 2                  # never fewer than 2
  maxReplicas: 10                 # never more than 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70   # scale up when avg CPU > 70%
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80   # scale up when avg memory > 80%
```

```yaml
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30    # wait 30s before scaling up again
      policies:
        - type: Pods
          value: 4                       # add up to 4 pods at once
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300   # wait 5 minutes before scaling down
      policies:
        - type: Pods
          value: 2                       # remove up to 2 pods at once
          periodSeconds: 120
```

**Why scale down is slower:** Scaling up is urgent (users are waiting). Scaling down should be cautious — if traffic spikes again in 5 minutes, you don't want to have just killed pods.

---

## Part C — Container networking: how pods talk to each other

### Every pod gets its own IP

When a pod starts, Kubernetes assigns it a unique IP (e.g., `10.244.0.15`). This IP is routable within the cluster — any pod can reach any other pod by IP.

### The problem with pod IPs

Pod IPs are **ephemeral**. When a pod restarts, it gets a new IP. You can't hardcode `10.244.0.15` anywhere.

### Services solve this

A Service provides a **stable virtual IP** (ClusterIP) that never changes. Behind the scenes, `kube-proxy` maintains iptables/IPVS rules that map the Service IP to the current set of pod IPs.

```
Pod A wants to reach <payment-svc>
  │
  ▼
DNS: <payment-svc>.<app>-ns.svc.cluster.local → 10.96.0.42 (ClusterIP)
  │
  ▼
kube-proxy (iptables): 10.96.0.42:80 → 10.244.0.15:80 (Pod 1)
                                      → 10.244.0.22:80 (Pod 2)
                                      (round-robin)
```

### DNS inside the cluster

Every Service gets a DNS name automatically:

```
<service-name>.<namespace>.svc.cluster.local
```

For us: `<payment-svc>.<app>-ns.svc.cluster.local`

Within the same namespace, you can use just the service name: `<payment-svc>`.

### How our service reaches external systems

| System | How we reach it | Defined where |
|--------|----------------|---------------|
| PostgreSQL | Direct IP (`<DB_HOST>:5432`) | `app_config.ini` `DB_HOST` |
| LiteLLM | Internal cluster URL or external URL | `app_config.ini` `LITELLM_BASE_URL` |
| Razorpay API | Public internet (`api.razorpay.com`) | Razorpay SDK default |

For PostgreSQL, we use a direct IP because the DB runs outside the cluster (Azure managed PostgreSQL). If it were inside the cluster, we'd use a Service name.

---

## Part D — The full traffic chain (Internet to Pod)

A request to `https://<dev-backend-host>/<payment-svc>/payments/packages`:

```
1. Browser
   │  DNS lookup: <dev-backend-host> → <AZURE_LB_IP> (Azure LB IP)
   │
2. Azure Load Balancer (L4)
   │  Forwards TCP to one of the Ingress Controller pods
   │
3. nginx Ingress Controller pod
   │  Terminates TLS (HTTPS → HTTP)
   │  Matches host: <dev-backend-host>
   │  Matches path: /<payment-svc>(/|$)(.*)
   │  Rewrites to: /payments/packages
   │  Adds security headers
   │
4. kube-proxy (iptables)
   │  Resolves Service ClusterIP to a pod IP
   │  10.96.0.42:80 → 10.244.0.15:80
   │
5. Pod: uvicorn
   │  Receives: GET /payments/packages
   │  FastAPI routes to list_packages()
   │  Returns JSON response
   │
6. Response travels back: Pod → kube-proxy → Ingress → LB → Browser
```

Each layer is explained in detail: DNS in [doc 11 Part A](./11-networking-foundations.md), LB in [doc 11 Part C](./11-networking-foundations.md), Ingress in [doc 14](./14-ingress-guide.md), ports in [doc 11 Part E](./11-networking-foundations.md).

---

## Part E — Labels and selectors

Labels are key-value pairs attached to objects. Selectors filter objects by labels. This is how Kubernetes ties everything together.

### The chain for our service

```
Deployment                    Service                     HPA
selector:                     selector:                   scaleTargetRef:
  matchLabels:                  app: <payment-svc>     name: <payment-svc>
    app: <payment-svc>         │                            │
         │                          │                            │
         ▼                          ▼                            ▼
    Pod template              Routes traffic to          Scales the Deployment
    labels:                   pods with this label       (which creates/deletes pods)
      app: <payment-svc>
```

### What breaks if labels don't match

| Mismatch | Symptom |
|----------|---------|
| Deployment selector ≠ pod template labels | Deployment creates pods but can't find them → stuck at 0 ready |
| Service selector ≠ pod labels | Service has no endpoints → 502 from Ingress |
| HPA targets wrong Deployment name | HPA does nothing (no error, just no scaling) |

### Check endpoints

```bash
# See which pods a Service is routing to
kubectl get endpoints <payment-svc> -n <app>-ns
# Should show pod IPs. If empty, selector doesn't match any pods.
```

---

## Part F — Resource management

### requests vs limits

| | `requests` | `limits` |
|-|-----------|---------|
| **Purpose** | Scheduling guarantee | Hard ceiling |
| **What happens** | K8s finds a node with this much free capacity | Container is killed (memory) or throttled (CPU) if it exceeds |
| **Our CPU** | 100m (0.1 cores) | 1 (1 full core) |
| **Our memory** | 512Mi | 1Gi |

**100m CPU** = 100 millicores = 10% of one CPU core. This is the minimum the pod is guaranteed. It can burst up to 1 full core (the limit) if the node has spare capacity.

**512Mi memory** = 512 mebibytes ≈ 537MB. The pod is guaranteed this much. If it tries to use more than 1Gi (the limit), it's OOMKilled.

### How to check usage

```bash
# Current CPU and memory per pod
kubectl top pods -n <app>-ns

# Example output:
# NAME                                  CPU(cores)   MEMORY(bytes)
# <payment-svc>-7d8f9b6c4-x2k9p   23m          187Mi
```

If you see memory consistently near the limit (e.g., 950Mi out of 1Gi), increase the limit before you get OOMKilled.

---

## Part G — Volumes and storage

### PersistentVolumeClaim (PVC)

Our deployment mounts a volume:

```yaml
volumeMounts:
  - name: blob-user-data
    mountPath: "/mnt/"
volumes:
  - name: blob-user-data
    persistentVolumeClaim:
      claimName: pvc-blob-<app>-user-data
```

A PVC is a request for storage. It's like saying "I need a disk." The cluster finds (or creates) a PersistentVolume that satisfies the request and binds them together.

Our PVC (`pvc-blob-<app>-user-data`) is backed by Azure Blob Storage. It's defined outside this repo (managed by the platform team). The payment service mounts it at `/mnt/` but doesn't actively use it for payment logic — it's there for other <AppName> services that share the namespace.

---

## Part H — Day-to-day kubectl commands

| Command | What it does |
|---------|-------------|
| `kubectl get pods -n <app>-ns` | List all pods in our namespace |
| `kubectl get pods -n <app>-ns -w` | Watch pods in real-time (see status changes) |
| `kubectl logs -n <app>-ns <pod> --tail=100` | Last 100 log lines |
| `kubectl logs -n <app>-ns <pod> -f` | Stream logs live (like `tail -f`) |
| `kubectl logs -n <app>-ns <pod> --previous` | Logs from the last crashed container |
| `kubectl describe pod <pod> -n <app>-ns` | Full details: events, conditions, mounts, env |
| `kubectl exec -it <pod> -n <app>-ns -- /bin/bash` | Shell into a running pod |
| `kubectl port-forward <pod> 8002:80 -n <app>-ns` | Access pod locally at localhost:8002 |
| `kubectl rollout status deploy/<payment-svc> -n <app>-ns` | Watch a deployment rollout |
| `kubectl rollout undo deploy/<payment-svc> -n <app>-ns` | Rollback to previous version |
| `kubectl scale deploy/<payment-svc> --replicas=3 -n <app>-ns` | Manually set 3 pods |
| `kubectl top pods -n <app>-ns` | CPU/memory usage |
| `kubectl delete pod <pod> -n <app>-ns` | Kill a pod (Deployment auto-recreates it) |
| `kubectl get events -n <app>-ns --sort-by=.lastTimestamp` | Recent cluster events |

### Useful shortcuts

```bash
# Alias for less typing
alias k=kubectl
alias kgp="kubectl get pods -n <app>-ns"
alias klogs="kubectl logs -n <app>-ns"

# Get pod name without copy-pasting
POD=$(kubectl get pods -n <app>-ns -l app=<payment-svc> -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD -n <app>-ns
```

---

## Part I — Learning path

A step-by-step progression from zero to confident:

1. **Read [doc 11](./11-networking-foundations.md)** — understand DNS, TLS, load balancers, ports before touching K8s.

2. **Install minikube** — a single-node K8s cluster on your laptop.
   ```bash
   brew install minikube
   minikube start
   ```

3. **Deploy this service to minikube** — build the Docker image, load it into minikube, apply the dev YAMLs. See if `/health` works via `kubectl port-forward`.

4. **Break things on purpose** — change the Service selector to something wrong. Watch what happens. Change the memory limit to 10Mi. Watch OOMKill. Change the image tag to something that doesn't exist. Watch ImagePullBackOff. This builds intuition faster than reading.

5. **Add Ingress** — `minikube addons enable ingress`, create an Ingress resource, test with `curl`. Then read [doc 14](./14-ingress-guide.md).

6. **Read the prod files** — compare `deploy/prod/` with `deploy/dev/`. Understand why prod has HPA, more replicas, different node selectors.

7. **Practice on the real cluster** — with your team's permission, run read-only commands (`get`, `describe`, `logs`, `top`) on the dev cluster. Don't `apply` or `delete` anything in prod without approval.

---

## Next doc

→ [14 — Ingress Guide](./14-ingress-guide.md) — how external traffic reaches your pods
