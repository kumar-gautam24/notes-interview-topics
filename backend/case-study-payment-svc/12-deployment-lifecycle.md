# 12 — Deployment Lifecycle

How code on your laptop becomes a running service in the Kubernetes cluster.

Prerequisite: [11 — Networking Foundations](./11-networking-foundations.md) (especially Part E on ports).

---

## Part A — The big picture

```
Your laptop                    Azure Container Registry          AKS Cluster
───────────                    ────────────────────────          ───────────
                                                                
1. Write code                                                   
2. docker build ──────────▶ 3. docker push ──────────▶ 4. kubectl apply
   (creates image)              (uploads image)            (tells K8s to run it)
                                                                    │
                                                           5. K8s pulls image
                                                           6. Starts pod(s)
                                                           7. Traffic flows in
```

Every deployment follows this pipeline. The details vary (manual vs CI/CD), but the steps are always: **build → push → apply → verify**.

---

## Part B — Docker deep dive

### Our Dockerfile, line by line

```dockerfile
FROM python:3.12-slim
```
Start from a minimal Python image. `slim` = Debian without extras (no gcc, no docs). Smaller image = faster push/pull. ~150MB vs ~1GB for the full image.

```dockerfile
WORKDIR /code
```
All subsequent commands run inside `/code` in the container.

```dockerfile
COPY ./requirements.txt /code/requirements.txt
RUN pip3 install -r requirements.txt
```
Copy requirements **first**, then install. Why not copy all code first? **Layer caching.** Docker caches each step. If `requirements.txt` hasn't changed, Docker reuses the cached pip install (saves minutes). If you copied all code first, any code change would invalidate the cache and re-run pip install.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev python3-dev ca-certificates gcc curl
```
System dependencies. `libpq-dev` = PostgreSQL client library (needed by `psycopg2`). `gcc` = C compiler (some pip packages compile C extensions). `ca-certificates` = TLS root certs (needed for HTTPS calls to Razorpay, LiteLLM).

```dockerfile
COPY ./app /code/app
```
Now copy the application code. This layer changes on every code change, but pip install is already cached above.

```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80"]
```
The default command when the container starts. Single-process uvicorn on port 80.

```dockerfile
# CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "-w", "4", ...]
```
Commented out alternative: gunicorn with 4 worker processes. More throughput but more memory.

```dockerfile
EXPOSE 80
```
Documentation only — tells readers (and tools) that this container listens on port 80. Doesn't actually open the port.

### uvicorn vs gunicorn vs run.sh

| Method | Workers | When to use |
|--------|---------|-------------|
| `uvicorn app.main:app --port 80` (Dockerfile) | 1 | Development, low traffic, simple |
| `gunicorn -w 4 -k uvicorn.workers.UvicornWorker` (run.sh) | 4 | Production — handles 4x concurrent requests |
| Kubernetes HPA + single-worker pods | 1 per pod, many pods | Cloud-native — scale horizontally instead of vertically |

Our Dockerfile uses single-process uvicorn. In production, Kubernetes scales by adding more pods (via HPA), so each pod only needs one worker.

### Build commands

```bash
# Build the image (run from repo root)
docker build -t <payment-svc> .

# Tag for the registry
docker tag <payment-svc> <dev-registry>.azurecr.io/<payment-svc>:v1.2.3

# Run locally to test
docker run -p 8002:80 -e ENVT=DEV <payment-svc>
# Now open http://localhost:8002/docs
```

---

## Part C — Container registries

A container registry is like GitHub but for Docker images. You push images there, and Kubernetes pulls them.

### Our registries

| Environment | Registry | Image |
|-------------|----------|-------|
| DEV | `<dev-registry>.azurecr.io` | `<dev-registry>.azurecr.io/<payment-svc>:latest` |
| PROD | `<prod-registry>.azurecr.io` | `<prod-registry>.azurecr.io/<payment-svc>:latest` |

ACR = Azure Container Registry. It's a private registry — you need credentials to push/pull.

### The push workflow

```bash
# 1. Log in to the registry
az acr login --name <dev-registry>

# 2. Build
docker build -t <dev-registry>.azurecr.io/<payment-svc>:v1.2.3 .

# 3. Push
docker push <dev-registry>.azurecr.io/<payment-svc>:v1.2.3
```

### The `:latest` tag trap

Both our deployment files use `:latest`:
```yaml
image: <dev-registry>.azurecr.io/<payment-svc>:latest
```

Problems with `:latest`:
- You can't tell which version is running (`kubectl describe pod` just says `latest`)
- If you push a broken image as `latest`, rollback is harder
- Kubernetes might not pull a new image if the tag hasn't changed (imagePullPolicy matters)

Better practice: use versioned tags (`v1.2.3`, `git-abc1234`, or a build number). We don't do this yet.

---

## Part D — Deploy to the cluster

### The apply order matters

```bash
# 1. Namespace first (everything else lives inside it)
kubectl apply -f deploy/dev/namespace.yml

# 2. Service (so the Deployment has something to register with)
kubectl apply -f deploy/dev/service.yml

# 3. Deployment (creates the pods)
kubectl apply -f deploy/dev/deployment.yml

# 4. Ingress (routes external traffic to the Service)
kubectl apply -f deploy/dev/ingress-route.yml
```

If you apply the Deployment before the Namespace exists → error. If you apply the Ingress before the Service exists → 502 errors until the Service is created.

### Verify it worked

```bash
# Are pods running?
kubectl get pods -n <app>-ns
# NAME                                  READY   STATUS    RESTARTS   AGE
# <payment-svc>-7d8f9b6c4-x2k9p   1/1     Running   0          2m

# Check logs
kubectl logs -n <app>-ns -l app=<payment-svc> --tail=50

# Is the service up?
kubectl get svc -n <app>-ns

# Is the ingress configured?
kubectl get ingress -n <app>-ns
```

### Updating a running deployment

```bash
# After pushing a new image, restart pods to pull it
kubectl rollout restart deployment/<payment-svc> -n <app>-ns

# Watch the rollout
kubectl rollout status deployment/<payment-svc> -n <app>-ns
```

With `RollingUpdate` strategy (our config), Kubernetes creates new pods with the new image, waits for them to be healthy, then kills the old pods. Zero downtime.

---

## Part E — Dev vs Prod differences

Side-by-side comparison from the actual files:

| Setting | DEV (`deploy/dev/`) | PROD (`deploy/prod/`) | Why |
|---------|--------------------|-----------------------|-----|
| `replicas` | 1 | 2 | Prod needs redundancy — if one pod dies, the other handles traffic |
| `nodeSelector` | `agentpool: <app>poc` | `kubernetes.io/os: linux` | Dev runs on a specific node pool; prod runs on any Linux node |
| Image registry | `<dev-registry>.azurecr.io` | `<prod-registry>.azurecr.io` | Separate registries per environment |
| `ENVT` env var | `DEV` | `PROD` | Controls which config section is loaded from `app_config.ini` |
| HPA | Not present | `hpa.yml` (2-10 pods, 70% CPU) | Prod auto-scales under load |
| Ingress host | `<dev-backend-host>` | `<backend-host>` | Different domains per environment |
| Namespace label | `env: dev` | `env: prod` | Metadata for filtering |

Everything else (Service, port, volume mounts, resource requests/limits) is identical.

---

## Part F — Common bugs and gotchas

### 1. ImagePullBackOff

```
NAME                                  READY   STATUS             RESTARTS   AGE
<payment-svc>-7d8f9b6c4-x2k9p   0/1     ImagePullBackOff   0          5m
```

**Causes:**
- Wrong image name or tag (typo in `deployment.yml`)
- Registry credentials not configured (AKS needs `imagePullSecrets` or ACR integration)
- Image doesn't exist (you forgot to `docker push`)

**Debug:** `kubectl describe pod <name> -n <app>-ns` — look at the Events section.

### 2. CrashLoopBackOff

```
NAME                                  READY   STATUS             RESTARTS   AGE
<payment-svc>-7d8f9b6c4-x2k9p   0/1     CrashLoopBackOff   5          10m
```

The pod starts, crashes, K8s restarts it, it crashes again, repeat with increasing backoff.

**Causes:**
- Missing environment variable (`ENVT` not set → config loading fails)
- Database unreachable (wrong `DB_HOST`, not on VPN/network)
- Python import error (missing dependency)
- Port already in use (shouldn't happen in K8s, but possible)

**Debug:** `kubectl logs <pod-name> -n <app>-ns --previous` — shows logs from the crashed container.

### 3. OOMKilled

```
State:          Terminated
Reason:         OOMKilled
```

The pod used more memory than its `limits.memory` (1Gi in our config). Kubernetes kills it.

**Causes:** Memory leak, loading large data into memory, too many concurrent requests.

**Fix:** Increase `limits.memory` in `deployment.yml`, or fix the leak.

### 4. Port mismatch

Pod is `Running` but requests return 502 from Ingress.

The full port chain must match (see [doc 11 Part E](./11-networking-foundations.md)). Most common: Service `targetPort: 80` but the app listens on 8000.

### 5. Secrets in plain text

Our `deployment.yml` has this:

```yaml
- name: OPENAI_API_KEY
  value: "sk-proj-<REDACTED>..."
```

This is **bad**. Anyone with `kubectl` access can read it. The fix:

```bash
# Create a Kubernetes Secret
kubectl create secret generic <app>-secrets -n <app>-ns \
  --from-literal=OPENAI_API_KEY=sk-proj-<REDACTED>...

# Reference it in deployment.yml instead of hardcoding
env:
  - name: OPENAI_API_KEY
    valueFrom:
      secretKeyRef:
        name: <app>-secrets
        key: OPENAI_API_KEY
```

Secrets are base64-encoded (not encrypted by default), but at least they're not in your YAML files in git.

---

## Part G — Rollback and debugging

### Rollback a bad deployment

```bash
# See rollout history
kubectl rollout history deployment/<payment-svc> -n <app>-ns

# Undo the last rollout (go back to previous version)
kubectl rollout undo deployment/<payment-svc> -n <app>-ns

# Undo to a specific revision
kubectl rollout undo deployment/<payment-svc> -n <app>-ns --to-revision=3
```

### Debugging a running pod

```bash
# Get a shell inside the pod
kubectl exec -it <pod-name> -n <app>-ns -- /bin/bash

# Check if the app is listening
curl http://localhost:80/health

# Check environment variables
env | grep ENVT

# Check if DB is reachable
python3 -c "import socket; socket.create_connection(('<DB_HOST>', 5432), timeout=5); print('OK')"
```

### Port-forward for local access

```bash
# Forward local port 8002 to the pod's port 80
kubectl port-forward -n <app>-ns <pod-name> 8002:80

# Now open http://localhost:8002/docs in your browser
```

Useful for testing a pod directly without going through Ingress.

### View resource usage

```bash
# CPU and memory per pod
kubectl top pods -n <app>-ns

# CPU and memory per node
kubectl top nodes
```

---

## Next doc

→ [13 — Kubernetes Guide](./13-kubernetes-guide.md) — Kubernetes concepts from zero, mapped to our files
