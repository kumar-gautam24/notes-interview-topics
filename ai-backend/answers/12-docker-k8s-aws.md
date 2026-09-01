# Document 12 — Docker / Kubernetes / AWS (Questions 470–504)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 470. What is a container?

**Definition.** A process (or group of processes) running with isolated view of the filesystem, network, process tree, and users, with bounded CPU and memory — using Linux kernel primitives, not virtualisation.

**The two kernel features that make it work:**
- **Namespaces** — isolation. `pid`, `net`, `mnt`, `uts`, `ipc`, `user`, `cgroup`. Each gives the process a private view of one kind of system resource.
- **cgroups** — limits. CPU shares, memory ceilings, I/O throttling.

**The point that matters: a container is not a VM.** It shares the host kernel. There's no guest OS, no hypervisor, and no hardware emulation. That's why it starts in milliseconds and costs almost nothing in overhead — and also why kernel-level isolation is weaker than a VM's (Q506).

**Why it's useful:**
1. **Reproducibility** — the same image runs identically anywhere with a compatible kernel. Eliminates "works on my machine."
2. **Dependency isolation** — two services needing different Python versions coexist.
3. **Density** — hundreds per host, versus tens of VMs.
4. **Fast startup** — seconds, enabling autoscaling and rolling deploys.

**The consequence people forget:** because the kernel is shared, a container built for x86 won't run on ARM without emulation, and anything depending on kernel features or modules is not portable. **A container isolates userspace, not the kernel.**

---

## 471. Image vs container?

**Image** — an immutable, layered filesystem template plus metadata (entrypoint, env, exposed ports). A build artefact.

**Container** — a running instance of an image, with a thin writable layer on top.

**The analogy:** image is to container as class is to object, or as an executable file is to a process.

**The layered structure, which is the operationally important part:**
```dockerfile
FROM python:3.12-slim          # layer 1
COPY requirements.txt .        # layer 2
RUN pip install -r ...         # layer 3
COPY . .                       # layer 4
```
Each instruction produces a layer. Layers are content-addressed and cached — **if a layer's inputs are unchanged, it's reused from cache.** This is why instruction order matters enormously (Q477).

**Copy-on-write:** the container's writable layer only stores changes. Ten containers from one image share the read-only layers, so ten instances cost one image plus ten small diffs.

**The consequence: container filesystems are ephemeral.** Anything written to the writable layer disappears when the container is removed. **Persistent data must go in a volume or an external service** — this is the rule that catches people who write logs or uploads to the local filesystem and lose them on every deploy.

**Tagging:** a tag is a mutable pointer to an immutable digest. `myapp:latest` can point at different content tomorrow. **Deploy by digest or immutable tag**, never `latest` (Q480).

---

## 472. Why containerize?

**The concrete benefits:**

1. **Environment parity.** Dev, CI, staging, and production run the identical artefact. The most common class of deployment bug — "it worked in staging" caused by a library version difference — simply disappears.
2. **Dependency isolation.** Each service carries its own runtime and libraries.
3. **Immutable deployments.** The artefact is built once and promoted through environments. You never patch a running server.
4. **Fast, reliable rollback.** Redeploy the previous digest.
5. **Density and resource limits.** cgroups make noisy-neighbour effects bounded.
6. **Orchestration becomes possible.** Kubernetes, ECS, and everything like them assume containers.
7. **Horizontal scaling** — identical replicas are trivial to run.

**The costs to be honest about:**
- **Build pipeline complexity** — registry, scanning, signing, promotion
- **Image size and pull time** — a 5 GB ML image is a real cold-start cost (Q447)
- **Debugging is harder** — no shell in a distroless image by design
- **Stateful workloads are awkward** — databases in containers are possible and often not worth it
- **Another layer to learn and operate**

**When not to containerise:** a single application on a single server that never scales. The orchestration overhead exceeds the benefit. **Containerising a monolith that will only ever run one instance buys you reproducibility and nothing else** — which may still be worth it, but say so honestly rather than reciting benefits that don't apply.

---

## 473. What is Kubernetes?

**Definition.** A container orchestration platform: you declare desired state, and controllers continuously reconcile actual state toward it.

**The core loop is the whole idea.** You say "I want 5 replicas of this image." A controller observes 3 running, creates 2. A node dies; it observes 4, creates 1. **You never issue imperative commands; you declare intent and the system converges.**

**The objects that matter:**

| Object | Purpose |
|---|---|
| **Pod** | One or more co-located containers sharing network and storage — the scheduling unit |
| **Deployment** | Manages a ReplicaSet, handles rolling updates and rollback |
| **Service** | Stable virtual IP and DNS name load-balancing to pods |
| **Ingress** | HTTP routing from outside the cluster |
| **ConfigMap / Secret** | Configuration and credentials injected as env vars or files |
| **StatefulSet** | Stable identities and persistent storage for stateful workloads |
| **Job / CronJob** | Run-to-completion and scheduled work |
| **HPA** | Horizontal Pod Autoscaler |

**What it gives you:** self-healing, rolling deploys with automatic rollback, service discovery, load balancing, autoscaling, secret management, resource scheduling, and a uniform API across cloud providers.

**The honest caveat, worth stating:** Kubernetes is complex and it is not always the right answer. For a handful of services, ECS Fargate, Cloud Run, or a managed PaaS delivers most of the benefit at a fraction of the operational cost. **Adopting Kubernetes for three services is a common and expensive mistake** — the same judgement as Q215 for Kafka.

---

## 474. Pod?

**Definition.** The smallest deployable unit — one or more containers that share a network namespace (same IP, same localhost, shared ports), storage volumes, and lifecycle.

**Why the abstraction exists rather than just "container":** some processes genuinely need to be co-located and share resources — a main container plus a log shipper, a proxy sidecar, or a metrics exporter. The pod is the boundary of that co-location.

**Container types within a pod:**
- **App containers** — run concurrently
- **Init containers** — run sequentially to completion *before* app containers start. Used for migrations, waiting on dependencies, fetching config.
- **Sidecars** — proxies (Istio/Envoy), log shippers, secret refreshers

**Properties that matter operationally:**
1. **Pods are ephemeral and disposable.** They get a new IP each time. **Never address a pod directly** — that's what Services are for.
2. **Pods are atomic for scheduling** — all containers land on one node.
3. **A pod is never "moved."** It's deleted and a new one created.
4. **Containers in a pod communicate over `localhost`.**

**The usual mistake:** putting multiple *services* in one pod because it's convenient. They then scale together, deploy together, and fail together. **One pod per independently-scalable concern.** A sidecar that supports the main container is right; two applications sharing a pod is not.

**The init-container pattern worth knowing:** running database migrations in an init container means migrations complete before any app container serves traffic, and a migration failure blocks the rollout rather than producing a half-migrated system serving requests.

---

## 475. Deployment?

**Definition.** A controller managing a ReplicaSet, which manages Pods. It provides declarative updates, rolling deploys, rollback, and scaling.

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1              # extra pods allowed during rollout
      maxUnavailable: 0        # zero-downtime: never drop below 3 ready
  template:
    spec:
      containers:
      - name: api
        image: registry/api@sha256:abc...    # digest, not a tag
```

**The rolling update mechanism:** create a new ReplicaSet, scale it up while scaling the old one down, respecting `maxSurge` and `maxUnavailable`. Old pods are only terminated once new ones pass readiness.

**`maxUnavailable: 0` is the setting for zero-downtime.** With `maxUnavailable: 1` you drop to 2 of 3 replicas during the rollout, which under load means degraded capacity.

**Rollback:**
```bash
kubectl rollout undo deployment/api
kubectl rollout status deployment/api
```
The previous ReplicaSet is retained (`revisionHistoryLimit`), so rollback is fast — it scales the old one back up.

**The requirement that makes rolling updates work: old and new versions must be able to run simultaneously.** During the rollout both serve traffic. That means **database migrations must be backward-compatible** — expand/contract, never a breaking change in one step (Q484, Q165).

**What a Deployment does not suit:** workloads needing stable identity or per-pod persistent storage. That's a StatefulSet. And run-to-completion work is a Job, not a Deployment with a process that exits — that produces a crash-loop.

---

## 476. Service?

**Definition.** A stable virtual IP and DNS name that load-balances across a dynamic set of pods selected by labels.

**The problem it solves:** pods are ephemeral with changing IPs. Nothing can address them directly. A Service provides a fixed name — `http://api.default.svc.cluster.local` — that always resolves to whatever pods are currently ready.

**The types:**

| Type | Behaviour |
|---|---|
| **ClusterIP** (default) | Internal virtual IP, cluster-only |
| **NodePort** | Exposes a port on every node |
| **LoadBalancer** | Provisions a cloud load balancer (ELB/NLB on AWS) |
| **ExternalName** | DNS CNAME to an external host |
| **Headless** (`clusterIP: None`) | No VIP; DNS returns pod IPs directly |

**How it works:** an Endpoints (or EndpointSlice) object tracks the IPs of pods that are **ready**. kube-proxy programs iptables or IPVS rules so traffic to the Service IP is DNAT'd to a ready pod.

**The critical linkage: only pods passing their readiness probe receive traffic** (Q483). A pod that's running but not ready is excluded from the Endpoints list. This is what makes zero-downtime deploys possible.

**The failure mode people hit:** during pod termination, endpoint removal and SIGTERM happen **concurrently**, not in order. For a few hundred milliseconds after SIGTERM, traffic may still route to the pod. If the app stops accepting immediately, users see connection refused — visible as 502s during every deploy. **The fix is a `preStop` sleep** (Q84, Q485).

**Headless services** matter for StatefulSets, where you need to address individual pods (`db-0.db.default.svc`) rather than load-balance across them.

---

## 477. Dockerfile best practices?

**The rules that matter most, in order of impact:**

**1. Order layers by change frequency.** Dependencies before source code — this is the highest-impact rule:
```dockerfile
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt    # cached unless deps change
COPY . .                                               # invalidated on every commit
```
Reversed, every source change reinstalls all dependencies. **This is the difference between a 20-second and a 5-minute build.**

**2. Multi-stage builds** to exclude build tooling from the final image (Q478).

**3. Minimal base images.** `python:3.12-slim` over `python:3.12`; distroless where practical. Smaller means faster pulls, less attack surface, fewer CVEs.

**4. Run as non-root:**
```dockerfile
RUN useradd -u 10001 -m app
USER 10001
```
**Non-negotiable** (Q507).

**5. `.dockerignore`** — exclude `.git`, `node_modules`, `__pycache__`, `.env`. Without it the build context is huge and you risk **baking secrets into the image**, which is permanent and readable by anyone who can pull it.

**6. Pin versions** — base image by digest, dependencies by lockfile. Otherwise builds aren't reproducible.

**7. Combine related `RUN` commands** and clean up in the same layer:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
```
Cleaning in a *later* layer doesn't shrink the image — the files still exist in the earlier layer.

**8. `ENTRYPOINT` in exec form** — `["python", "app.py"]`, not shell form. Shell form wraps the process in `/bin/sh -c`, which means **your app is PID 2 and does not receive SIGTERM** — breaking graceful shutdown entirely (Q485). This is a subtle and very common bug.

**9. Never bake secrets.** Layers are permanent; `RUN rm secret` doesn't remove it from the earlier layer.

---

## 478. Multi-stage builds?

**Definition.** A Dockerfile with multiple `FROM` stages, where the final image copies only the needed artefacts from earlier stages.

```dockerfile
FROM python:3.12 AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip wheel --wheel-dir /wheels -r requirements.txt

FROM python:3.12-slim AS runtime
RUN useradd -u 10001 -m app
COPY --from=builder /wheels /wheels
RUN pip install --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
COPY --chown=app:app . /app
USER 10001
WORKDIR /app
ENTRYPOINT ["python", "-m", "app"]
```

**What it buys:**
1. **Size.** Compilers, headers, build tools, and caches never reach the final image. Reductions of 5–10× are typical for compiled dependencies.
2. **Security.** No `gcc`, no `git`, no package manager in production means far less to exploit and far fewer CVEs to triage (Q509).
3. **No build secrets in the final image.** A private-repo token used in the builder stage isn't in the runtime layers.
4. **Faster pulls**, which means faster scaling and deploys.

**The Go/Rust extreme:**
```dockerfile
FROM golang:1.22 AS build
RUN CGO_ENABLED=0 go build -o /app

FROM gcr.io/distroless/static
COPY --from=build /app /app
ENTRYPOINT ["/app"]
```
A few MB, with no shell, no package manager, and essentially no attack surface.

**The trade-off:** debugging is harder — no shell to exec into. Use **ephemeral debug containers** (`kubectl debug`) which attach a tooling container to a running pod's namespaces without modifying the image. That's the right answer to "how do you debug distroless."

---

## 479. Image layer caching?

**How it works.** Each Dockerfile instruction produces a layer identified by a hash of the instruction plus its inputs. On rebuild, Docker walks instructions in order and reuses cached layers until it finds one whose inputs changed. **From that point on, every subsequent layer is rebuilt** — cache invalidation cascades downward and never recovers.

**The consequences:**

1. **Order matters absolutely.** `COPY . .` early invalidates everything after it on every commit (Q477).
2. **`COPY` invalidates on file content/metadata changes.** `COPY requirements.txt .` only invalidates when that file changes.
3. **`RUN apt-get update` alone is dangerous** — it caches, so a later `apt-get install` may use a stale package index for months. Always combine them in one `RUN`.
4. **Build args and env vars** invalidate layers after them. Injecting a build timestamp early destroys the cache entirely.

**In CI, where every build starts fresh, you need explicit cache import/export:**
```bash
docker buildx build \
  --cache-from type=registry,ref=myrepo/app:buildcache \
  --cache-to   type=registry,ref=myrepo/app:buildcache,mode=max \
  --push -t myrepo/app:$SHA .
```
Without this, CI has no cache and every build is cold. **This is the single biggest CI build-time win** and it's frequently missing.

**Also use package-manager cache mounts:**
```dockerfile
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
```
Persists the pip cache across builds without adding a layer.

**The trade-off:** aggressive caching risks staleness — an old base image with unpatched CVEs. Rebuild without cache periodically, or pin base images by digest and update them deliberately.

---

# L2 — Kubernetes engineering

## 480. Image tagging strategy?

**The rule: deploy immutable references. Never `latest`.**

**Why `latest` is dangerous:**
- It's a mutable pointer. The same manifest deploys different code on different days.
- **You cannot reliably roll back** — the previous `latest` no longer exists.
- Rolling updates can produce a mix of versions if pods pull at different times.
- With `imagePullPolicy: Always` you get nondeterminism; without it, stale images.

**The strategy:**
```
registry/app:git-a1b2c3d              # immutable, traceable to a commit
registry/app:v1.4.2                   # semantic version for releases
registry/app@sha256:abc123...         # digest — the strongest guarantee
```

**Deploy by digest.** A tag is a name that can be repointed; a digest is content-addressed and cannot lie. In manifests:
```yaml
image: registry/app@sha256:abc123...
```
**This is what makes GitOps reproducible** — the manifest fully determines what runs.

**The practical workflow:** CI builds and pushes `app:git-$SHA`, resolves the digest, and updates the deployment manifest with the digest. The manifest change is the deploy, in git, reviewable and revertible.

**Retention:** keep enough tags to roll back several versions. Registry lifecycle policies prune old untagged images, but be careful not to delete a digest a running deployment references — **that turns a pod restart into an `ImagePullBackOff` outage** at the worst moment.

**`imagePullPolicy`:** `IfNotPresent` with immutable tags is correct and avoids registry load. `Always` is only needed with mutable tags, which you shouldn't be using.

---

## 481. Resource requests/limits?

**Request** — what the scheduler guarantees and uses for placement decisions.
**Limit** — the hard ceiling the container cannot exceed.

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    memory: "1Gi"          # note: no CPU limit — deliberate
```

**The two resources behave completely differently, and this is the substance of the question:**

- **Memory is incompressible.** Exceeding the limit means the kernel **OOM-kills** the container immediately. No warning, no throttling.
- **CPU is compressible.** Exceeding the limit means **CFS throttling** — the process is paused until the next scheduling period. It doesn't die; it gets slower, in bursts.

**The CPU limit controversy, worth having a position on.** CPU limits cause throttling even when the node has idle CPU, because CFS quota is enforced per 100ms period. A service that occasionally bursts gets throttled mid-request, producing latency spikes that look like application problems. **Many teams set CPU requests but omit CPU limits**, relying on requests for fair scheduling. That's a defensible position; the counter-argument is that limits prevent one workload from starving others. **Always set memory limits.**

**QoS classes, which determine eviction order under node pressure:**
- **Guaranteed** — requests == limits for all resources. Evicted last.
- **Burstable** — requests < limits. Evicted second.
- **BestEffort** — nothing set. **Evicted first.** Never run production workloads this way.

**Getting the numbers:** measure actual usage under load. Request at roughly p50–p75 of observed usage; set memory limit above p99 with headroom. **Requests too high wastes capacity; too low means the scheduler overpacks the node and everything degrades together.**

---

## 482. Liveness probe?

**Definition.** A periodic check answering "is this process healthy, or should it be restarted?" **Failure means Kubernetes kills and restarts the container.**

```yaml
livenessProbe:
  httpGet: {path: /health/live, port: 8000}
  initialDelaySeconds: 10
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 3
```

**The rule that matters most: liveness must NOT check dependencies.** No database check, no Redis check, no upstream API check.

**Why.** Liveness failure means *restart*. If liveness checks the database and the database has a 30-second blip, **every pod fails liveness simultaneously and Kubernetes restarts your entire fleet.** Now a thundering herd of cold pods reconnects to an already-struggling database. **You have converted a brief dependency degradation into a full outage** (Q85).

**Liveness should answer only: is this process deadlocked or hung?** A simple handler returning 200 is usually correct. If the event loop is blocked (Q36), the probe times out, which is the genuine deadlock case liveness exists for.

**The other common misconfiguration:** thresholds too aggressive. Under load, a healthy pod may respond slowly. Killing it makes the overload worse. Use generous `timeoutSeconds` and `failureThreshold` — liveness should be the last resort, not a latency alarm.

**For slow-starting applications** (model servers, Q447), use a **startup probe** rather than a long `initialDelaySeconds`. Startup probes disable liveness until they succeed, so a 15-minute model load doesn't get killed at 30 seconds (Q466).

---

## 483. Readiness probe?

**Definition.** A periodic check answering "should this pod receive traffic right now?" **Failure means removal from Service endpoints — no restart.**

```yaml
readinessProbe:
  httpGet: {path: /health/ready, port: 8000}
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 2
```

**The distinction from liveness is the whole point:**

| | Liveness | Readiness |
|---|---|---|
| Failure means | **Restart the container** | **Stop sending traffic** |
| Should check dependencies | **No** | **Yes** |
| Correct response to a DB outage | Do nothing | Fail — stop taking traffic |

**Readiness is where dependency checks belong**, because "stop sending traffic" is the right response to an unavailable dependency. The pod stays alive and recovers when the dependency does.

```python
@app.get("/health/ready")
async def ready():
    try:
        async with asyncio.timeout(2):
            await db.fetchval("SELECT 1")
    except Exception:
        return JSONResponse(503, {"status": "not_ready"})
    return {"status": "ready"}
```

**What readiness enables:**
1. **Zero-downtime deploys** — new pods take traffic only when genuinely ready
2. **Graceful shutdown** — flip readiness to false first, so the load balancer drains you before you stop accepting (Q84)
3. **Load shedding** — fail readiness when overloaded so traffic shifts elsewhere

**The cascade risk to acknowledge:** if every pod's readiness depends on one database and that database goes down, every pod becomes unready and the Service has zero endpoints. **The entire service is down.** That's arguably correct — you can't serve without a database — but decide deliberately, and consider whether a degraded mode is possible.

**Cache the readiness result for a couple of seconds** so probes don't hammer the database at `periodSeconds × replicas` frequency.

---

## 484. Rolling update?

**The mechanism:** a new ReplicaSet is created and scaled up while the old one scales down, bounded by `maxSurge` and `maxUnavailable`, with new pods only counted once they pass readiness.

```yaml
strategy:
  rollingUpdate:
    maxSurge: 25%
    maxUnavailable: 0
```

**`maxUnavailable: 0` for zero-downtime.** Capacity never drops below the desired replica count.

**The requirement that governs everything: old and new versions run simultaneously during the rollout.** Which means:

1. **Database migrations must be backward-compatible.** Expand/contract across multiple deploys, never a breaking change in one step (Q165). Adding a column is safe; renaming one is not — the old pods still query the old name.
2. **API contracts must be compatible in both directions** during the window.
3. **Message formats** — old consumers may receive new messages.
4. **Cache formats** — version the keys so old and new don't misread each other's entries (Q182).

**Failure handling:** if new pods never become ready, the rollout stalls (it doesn't auto-rollback by default). `progressDeadlineSeconds` marks it failed after a timeout. Use:
```bash
kubectl rollout status deployment/api --timeout=5m || kubectl rollout undo deployment/api
```
in CI so a bad deploy reverts automatically.

**Other strategies worth naming:**
- **Recreate** — kill all, then start new. Downtime, but necessary when versions genuinely cannot coexist.
- **Blue/green** — full parallel environment, instant cutover, easy rollback, double the resources.
- **Canary** — small percentage first, compare metrics, then proceed. **The best option for risky changes**, and what you'd want for a prompt or model change (Q329).

---

## 485. Graceful shutdown in k8s?

**The sequence, and the concurrency detail is what people get wrong:**

1. Pod marked Terminating.
2. **Simultaneously:** endpoint removal begins *and* `preStop` hook runs, then SIGTERM is sent.
3. Application drains.
4. After `terminationGracePeriodSeconds`, SIGKILL.

**The problem: endpoint removal propagates asynchronously across every node's kube-proxy.** For a few hundred milliseconds after SIGTERM, traffic may still be routed to this pod. **If the app stops accepting immediately, users see connection resets — visible as 502s during every deploy.**

**The fix:**
```yaml
spec:
  terminationGracePeriodSeconds: 45
  containers:
  - name: api
    lifecycle:
      preStop:
        exec: {command: ["sleep", "5"]}
```
The `preStop` sleep delays SIGTERM by 5 seconds, giving endpoint removal time to propagate. **This is the standard fix and it's essential for genuinely zero-downtime deploys.**

**The application side** (Q84):
```python
@asynccontextmanager
async def lifespan(app):
    yield
    app.state.ready = False          # fail readiness first
    await drain_inflight(timeout=25) # bounded
    await close_resources()
```

**The arithmetic that must hold:** `preStop sleep + drain timeout < terminationGracePeriodSeconds`. With a 5s sleep and a 25s drain, 45s grace is comfortable. Reverse it and you get SIGKILL'd mid-write.

**The Dockerfile trap that silently breaks all of this:** `ENTRYPOINT` in shell form wraps your process in `/bin/sh -c`. Your app becomes PID 2 and **never receives SIGTERM** — the shell gets it and doesn't forward it. Every shutdown is a SIGKILL. Use exec form (Q477).

---

## 486. Secrets management?

**Kubernetes Secrets are base64-encoded, not encrypted, by default.** Anyone with API read access on the namespace can decode them, and they're stored in etcd in plaintext unless encryption at rest is configured.

**The layers, from minimum to good:**

1. **Enable etcd encryption at rest** — a cluster-level configuration, not automatic.
2. **RBAC** restricting `get`/`list` on secrets to the service accounts that need them.
3. **Mount as files, not environment variables.** Env vars leak into crash dumps, `/proc/<pid>/environ`, child processes, and logging of the full environment. **Files can be permission-restricted and are not inherited by subprocesses.**
4. **External secret stores** — AWS Secrets Manager or SSM, synced via External Secrets Operator or mounted via the Secrets Store CSI driver. The secret lives in a purpose-built system with audit logging, rotation, and fine-grained IAM.
5. **IRSA on EKS** (Q492) — for AWS access, use IAM roles rather than storing credentials at all. **The best secret is one that doesn't exist.**
6. **Rotation** — automated, with the application able to reload without a restart.

**Never:**
- Commit secrets to git (use Sealed Secrets or SOPS if you must store them in the repo)
- Bake them into images — layers are permanent (Q477)
- Log them, or log the full environment
- Pass them as command-line arguments — visible in `ps`

**The detection layer:** secret scanning in CI (`gitleaks`, `trufflehog`), and treat any leaked credential as compromised — **rotate it, don't just delete the commit.** Git history persists in every clone.

---

## 487. ConfigMap?

**Definition.** Non-sensitive configuration data as key-value pairs or files, decoupled from the image.

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: api-config}
data:
  LOG_LEVEL: "INFO"
  MAX_WORKERS: "4"
  app.yaml: |
    retrieval:
      top_k: 20
```

**Consumption:**
```yaml
envFrom:
- configMapRef: {name: api-config}     # as env vars
volumeMounts:
- {name: config, mountPath: /etc/app}  # as files
```

**Why:** the same image runs in dev, staging, and production with different configuration. **This is what makes "build once, promote the artefact" possible** — the image is environment-independent.

**The behaviours that surprise people:**

1. **Env vars are injected at pod start and never change.** Updating the ConfigMap does *nothing* to running pods. You must restart them.
2. **Mounted files DO update** — the kubelet syncs them, typically within a minute. But **your application must watch the file and reload**; most don't.
3. **The standard fix:** annotate the Deployment with a hash of the ConfigMap so a config change alters the pod template and triggers a rolling update. Helm does this with a checksum annotation, and it's the pattern to name.

**The limits:** 1 MiB total size, and there's no schema validation — a typo in a value fails at runtime, not at apply time. **Validate configuration at application startup** with Pydantic Settings so a bad value crashes immediately with a clear message rather than failing on the first request an hour later (Q60).

**ConfigMap vs Secret:** functionally similar; Secrets have base64 encoding, separate RBAC, and are excluded from some logging. **Use Secrets for anything sensitive** even though the protection is weak (Q486).

---

## 488. Horizontal scaling?

**Definition.** Adding more pod replicas rather than making each larger.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef: {kind: Deployment, name: api}
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Pods
    pods:
      metric: {name: http_requests_per_second}
      target: {type: AverageValue, averageValue: "100"}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300    # avoid flapping
```

**The metric choice is the substance of this question.** CPU is the default and is usually **wrong for async I/O-bound services** — a FastAPI service waiting on database calls has low CPU while being fully saturated on concurrency. By the time CPU rises, you're already degraded.

**Better signals:**
- **Request rate** or **p99 latency** for API tiers
- **Queue depth**, or better **oldest-message age**, for workers (Q100) — this directly expresses the SLO
- **Connection count** or in-flight requests

These need a metrics adapter (Prometheus Adapter) or **KEDA**, which reads external sources like Redis queue length natively. **KEDA is the practical answer for queue-driven autoscaling.**

**The constraints that bound replica count** — naming these is what shows experience:
- **Database connections**: `replicas × workers × pool_size ≤ max_connections`. **This binds long before CPU does** and is the most common self-inflicted outage when scaling (Q249).
- Upstream rate limits
- Node capacity — HPA can't schedule pods with nowhere to go; you need Cluster Autoscaler or Karpenter too

**Scale-down needs a stabilisation window** or you flap. Scale up fast, scale down slowly (Q466).

---

## 489. Node scheduling?

**How the scheduler places pods:** filter nodes that *can* run the pod (resources, taints, affinity, node selectors), then score the survivors and pick the best.

**The controls:**

**Node selection:**
```yaml
nodeSelector: {node-type: gpu}
```

**Taints and tolerations** — a taint repels pods unless they tolerate it. This is how you reserve nodes:
```yaml
# on the node
taints: [{key: nvidia.com/gpu, effect: NoSchedule}]
# on the pod
tolerations: [{key: nvidia.com/gpu, operator: Exists, effect: NoSchedule}]
```
**Taints are the correct mechanism for expensive GPU nodes** — without them, ordinary pods land on your GPU nodes and consume capacity.

**Affinity/anti-affinity:**
```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector: {matchLabels: {app: api}}
```
Forces replicas onto different nodes — **essential for availability**, otherwise all three replicas can land on one node and a node failure takes out the whole service.

**Topology spread constraints** — the modern, more flexible version, spreading across zones:
```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
```

**PodDisruptionBudget** — bounds *voluntary* disruption (node drains, cluster upgrades):
```yaml
spec: {minAvailable: 2, selector: {matchLabels: {app: api}}}
```
**Without a PDB, a node drain can evict all your replicas simultaneously.** This is a real outage cause during routine cluster maintenance and it's frequently missing.

**Priority classes** determine what gets preempted under pressure — critical workloads should have a higher priority class than batch jobs.

---

# L3 — Production

## 490. Pod OOMKilled?

**What happened:** the container exceeded its memory limit and the kernel killed it. `kubectl describe pod` shows `Reason: OOMKilled`, `Exit Code: 137`.

**Diagnosis:**
```bash
kubectl describe pod <pod> | grep -A5 "Last State"
kubectl top pod <pod>
```
Check whether it's a steady climb (leak) or a spike (a specific request).

**The causes:**
1. **Limit too low** for actual usage — measure p99, not average
2. **Memory leak** (Q38) — unbounded cache, task leak, accumulating list
3. **A large request** — a 100 MB upload loaded into memory, or a huge LLM context
4. **Concurrency higher than budgeted** — memory scales with in-flight requests
5. **JVM/runtime not aware of the cgroup limit** — less common now, but a classic

**The Python-specific one worth naming:** Python doesn't return freed memory to the OS aggressively, so RSS plateaus high after a spike. A single large request can permanently raise the pod's footprint. `MALLOC_ARENA_MAX=2` sometimes helps.

**Fixes:**
- Raise the limit if usage is legitimate
- Fix the leak if it's a climb
- **Bound request size at the ingress**, so a huge payload is rejected before Python allocates for it
- Reduce concurrency per pod and scale horizontally instead
- Set `maxUnavailable: 0` so OOM restarts don't compound during a deploy

**The design point:** a memory limit is a **containment mechanism**. It converts "one pod leaks and takes down the node" into "one pod restarts." **Being OOMKilled is the system working as designed** — the bug is the memory usage, not the limit. Treat repeated OOMKills as a bug ticket, never as a reason to keep raising the limit.

---

## 491. CrashLoopBackOff?

**What it means:** the container repeatedly starts and exits, and Kubernetes is backing off between restarts (10s, 20s, 40s… capped at 5 minutes).

**Diagnosis, in order:**
```bash
kubectl logs <pod> --previous       # ← logs from the CRASHED instance
kubectl describe pod <pod>          # events, exit code, last state
```
**`--previous` is the key flag** — without it you see the current (probably still-starting) instance, not the one that failed.

**Exit codes tell you a lot:**
- **0** — the process exited successfully. For a Deployment this is a crash loop; **it should have been a Job** (Q475).
- **1** — application error. Read the logs.
- **137** — SIGKILL, usually OOM (Q490)
- **143** — SIGTERM
- **139** — segfault

**The common causes:**
1. **Missing configuration** — a required env var absent, so startup validation fails. **This is the most common**, and it's why fail-fast config validation with a clear message matters (Q60).
2. **Dependency unavailable at startup** — the database isn't reachable. Consider retrying with backoff rather than exiting, or use an init container to wait.
3. **Liveness probe failing during a slow start** — the app never gets time to warm up. **Use a startup probe** (Q482).
4. **Wrong command/entrypoint** — the container runs and exits immediately.
5. **Permission errors** — running as non-root without access to a needed path.
6. **Image architecture mismatch** — an arm64 image on amd64 nodes, or vice versa. Increasingly common with Apple Silicon development machines.

**The debugging technique for a container that won't stay up:** override the command to keep it alive and inspect from inside:
```bash
kubectl run debug --image=<same-image> --command -- sleep 3600
kubectl exec -it debug -- sh
```

---

## 492. Secrets in production?

**The best answer: don't have long-lived secrets at all.**

**On EKS, use IRSA (IAM Roles for Service Accounts):**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/api-role
```
The pod receives a projected, short-lived OIDC token which the AWS SDK exchanges for temporary credentials, automatically refreshed. **No AWS keys exist anywhere** — not in a Secret, not in an env var, not in a config file. Nothing to leak or rotate.

**This is the single most important secrets improvement available on EKS** and it eliminates the most commonly leaked credential type entirely.

**For secrets that must exist** (database passwords, third-party API keys):
1. **Store in AWS Secrets Manager or SSM Parameter Store (SecureString)** — versioned, audited, IAM-controlled, rotatable.
2. **Sync into the cluster** via External Secrets Operator, or mount directly with the Secrets Store CSI driver.
3. **Mount as files, not env vars** (Q486).
4. **Rotate automatically**, with the application reloading without a restart.
5. **Least privilege IAM** — the role can read only the specific secrets it needs.

**What to audit:** who read which secret, when. Secrets Manager gives this via CloudTrail; a raw Kubernetes Secret does not.

**Incident response:** treat any exposed credential as compromised — **rotate immediately**. Deleting the commit doesn't help; git history persists in every clone and every CI cache. **The rotation is the remediation; the deletion is cosmetic.**

---

## 493. Rolling deploy fails mid-rollout?

**What's happening:** new pods aren't becoming ready, so the rollout stalls. With `maxUnavailable: 0`, **old pods keep serving** — the service is degraded in capacity, not down. That's the design working.

**Diagnose:**
```bash
kubectl rollout status deployment/api
kubectl get pods -l app=api                 # which are not Ready
kubectl describe pod <new-pod>              # events
kubectl logs <new-pod>
```

**The causes:**
1. **Readiness probe failing** — a dependency the new version needs is missing, or the probe path changed
2. **Crash on startup** — missing config, bad migration state (Q491)
3. **Image pull failure** — `ImagePullBackOff`, often a deleted tag or a registry auth problem
4. **Insufficient node resources** — `Pending`, nothing to schedule onto
5. **A migration that made the schema incompatible with the *old* version**, so old pods start failing too — **this is the dangerous case**

**Immediate action:**
```bash
kubectl rollout undo deployment/api
```
Fast, because the old ReplicaSet still exists and just scales back up.

**Automate it:**
```bash
kubectl rollout status deployment/api --timeout=5m || kubectl rollout undo deployment/api
```
in your pipeline. **A rollout that stalls without auto-rollback silently leaves you at reduced capacity** until someone notices.

**`progressDeadlineSeconds`** (default 600) marks the rollout failed after a timeout — but it does *not* auto-rollback. It only sets a condition.

**The one that can't be rolled back:** a migration that dropped a column the old code needs. **This is why expand/contract exists** (Q484, Q165) — every deploy must be independently revertible, and a destructive migration breaks that property.

---

## 494. Node failure?

**What Kubernetes does automatically:**
1. The node stops sending heartbeats; after `node-monitor-grace-period` (~40s) it's marked `NotReady`.
2. After a further toleration period (~5 min by default), pods are marked for deletion.
3. Controllers create replacement pods, which the scheduler places on healthy nodes.
4. Endpoints update; traffic shifts.

**Total time to recovery is typically 5–6 minutes by default** — which surprises people expecting instant failover. Tune `tolerationSeconds` for `node.kubernetes.io/unreachable` if you need faster.

**What you must do to make this work:**

1. **Multiple replicas.** One replica means downtime, full stop.
2. **Pod anti-affinity or topology spread** so replicas aren't all on the failed node (Q489). **Without this, three replicas on one node is a single point of failure that looks like redundancy.**
3. **Multi-AZ node groups** so a zone failure doesn't take everything.
4. **PodDisruptionBudget** for voluntary disruptions.
5. **Cluster Autoscaler / Karpenter** to provision a replacement node if capacity is now insufficient.
6. **No local state.** Anything on the node's disk is gone (Q471).

**For stateful workloads:** EBS volumes are zone-bound, so a pod using one can only reschedule within the same AZ. If that AZ is down, it cannot recover until the AZ does. **This is why databases in Kubernetes are hard** and why managed RDS is usually the better answer.

**The application-side requirement:** jobs in flight on the failed node die without SIGTERM. **Recovery depends on leases and idempotency** (Q201, Q317), not on Kubernetes — the orchestrator restarts the pod, but only your design recovers the work.

---

## 495. Autoscaling misconfigured?

**The failure patterns and their signatures:**

**1. Flapping.** Replicas oscillate up and down. Cause: aggressive thresholds and no stabilisation window. Each scale event changes the metric, which triggers the opposite action.
```yaml
behavior:
  scaleDown: {stabilizationWindowSeconds: 300}
  scaleUp:   {stabilizationWindowSeconds: 60}
```
**Asymmetric windows** — scale up quickly, scale down slowly.

**2. Scaling on the wrong metric.** CPU on an I/O-bound async service (Q488). CPU stays at 20% while the service is saturated on concurrency, so it never scales and just degrades.

**3. Scaling into a downstream bottleneck.** More replicas mean more database connections (Q249), more requests against a rate-limited upstream (Q204), or more load on a struggling dependency. **Scaling makes it worse, and the autoscaler keeps scaling because the metric keeps looking bad.** This is a genuine amplification loop.

**4. `maxReplicas` too low** — you silently cap out and degrade with no alert.

**5. `minReplicas` too low** — scaling from 1 to 20 during a spike takes minutes, and each new pod is cold.

**6. Nodes can't be provisioned** — pods sit `Pending`. HPA has no idea; it thinks it scaled.

**7. Metrics pipeline broken** — the adapter is down, HPA sees no metrics and does nothing. **Silent.** Alert on HPA `ScalingActive` being false.

**The diagnostic:**
```bash
kubectl describe hpa api          # current metrics, decisions, conditions
kubectl get events --field-selector involvedObject.name=api
```

**The design principle:** **autoscaling amplifies whatever is happening.** If the bottleneck is downstream, autoscaling accelerates the outage. Always ask "what breaks if this scales to `maxReplicas`?" before setting the number.

---

## 496. Connection pool exhaustion?

**The arithmetic that causes it, and it's the most common self-inflicted outage when scaling Kubernetes workloads:**
```
total_connections = replicas × workers_per_pod × pool_size
```
20 replicas × 4 Uvicorn workers × pool_size 20 = **1,600 connections**. PostgreSQL's default `max_connections` is 100.

**What happens:** new connections are refused. Every service using that database fails, including ones that were scaling fine. **You took down the database by scaling the API** (Q249).

**The fixes, in order:**

**1. PgBouncer in transaction mode.** Multiplexes thousands of client connections onto ~100 server connections. **This is the standard answer** and it decouples app-side pool sizing from PostgreSQL's limit entirely.

Note the caveat: transaction pooling breaks session-level features — prepared statements (unless configured), `SET` that must persist, advisory locks, and `LISTEN/NOTIFY`. Use `SET LOCAL` inside transactions (Q93).

**2. Size pools from the constraint, not from intuition:**
```
pool_size = (max_connections × 0.8) / (replicas × workers)
```

**3. One Uvicorn worker per pod** and scale pods (Q81). Cleaner arithmetic, and Kubernetes already handles restarts and scaling.

**4. `pool_timeout`** so exhaustion fails fast rather than hanging:
```python
create_async_engine(url, pool_size=10, max_overflow=5, pool_timeout=5,
                    pool_pre_ping=True, pool_recycle=1800)
```

**5. Bulkheads** — a small dedicated pool for reports so they can't starve interactive traffic (Q86).

**The monitoring that catches it early:** pool checkout wait time at p99, and `pg_stat_activity` count by state. **Rising checkout wait precedes the outage by minutes** — it's the leading indicator, and total connection count is the lagging one.

---

## 497. Zero-downtime deploy?

**Everything must hold simultaneously — and listing all six is the answer:**

**1. Multiple replicas** with `maxUnavailable: 0` and `maxSurge: 25%`.

**2. Correct readiness probes** so new pods take traffic only when genuinely ready (Q483).

**3. Graceful shutdown** with a `preStop` sleep to handle the endpoint-removal race (Q485):
```yaml
terminationGracePeriodSeconds: 45
lifecycle: {preStop: {exec: {command: ["sleep", "5"]}}}
```

**4. Backward-compatible migrations.** Expand/contract, because both versions run simultaneously (Q484, Q165). **This is the constraint that requires the most discipline** and the one that most often makes rollback impossible.

**5. Backward-compatible contracts** — API responses, message formats, cache key formats. Old and new must interoperate in both directions during the window.

**6. Exec-form `ENTRYPOINT`** so SIGTERM actually reaches your process (Q477).

**The failure modes each of these prevents:**

| Missing | Symptom |
|---|---|
| `maxUnavailable: 0` | Reduced capacity mid-deploy, latency spike |
| Readiness probe | Traffic to pods that aren't ready → 502s |
| `preStop` sleep | 502s from the endpoint-removal race |
| Graceful shutdown | In-flight requests killed |
| Compatible migrations | Old pods error against the new schema |
| Exec-form entrypoint | SIGTERM never delivered; all shutdowns are SIGKILL |

**How to verify rather than assume:** run continuous synthetic traffic during a deploy in staging and assert zero non-200 responses. **"We have zero-downtime deploys" is a claim until you've measured it**, and the endpoint-removal race in particular is invisible at low traffic and obvious at high traffic.

---

## 498. Cost optimization?

**In order of typical impact:**

**1. Right-size requests and limits.** Most clusters are dramatically over-provisioned because requests were guessed. Measure actual usage and set requests near p50–p75. **Requests determine node count**, so this directly reduces spend. Use VPA in recommendation mode to get the numbers.

**2. Spot / Karpenter.** Spot instances are 60–90% cheaper. Suitable for stateless services with multiple replicas, batch jobs, and CI. **Not** for single-replica stateful workloads. Karpenter provisions the cheapest instance type that fits, consolidates underutilised nodes, and handles spot interruption.

**3. Cluster Autoscaler / Karpenter consolidation.** Nodes running at 20% utilisation are pure waste. Consolidation bin-packs pods onto fewer nodes.

**4. Savings Plans / Reserved Instances** for baseline capacity, spot for burst.

**5. Graviton (ARM)** — roughly 20% cheaper for equivalent performance. Requires multi-arch images, which `docker buildx` makes straightforward.

**6. Scale to zero** for dev and staging environments outside working hours. **Often the easiest large win** and frequently overlooked.

**7. Storage.** Delete unattached EBS volumes and old snapshots. Lifecycle-policy your ECR repositories — image storage accumulates silently.

**8. Data transfer.** Cross-AZ traffic is billed. Topology-aware routing keeps traffic in-zone where availability requirements permit.

**9. Logs.** CloudWatch and observability ingest costs are frequently a top-three line item. Sample, set retention, and drop debug logs in production.

**The measurement:** cost allocation tags per namespace or team, and a tool like OpenCost or Kubecost to attribute spend to workloads. **You cannot optimise what you cannot attribute** — and unattributed cluster cost is where most waste hides.

---

# L4 — System design

## 499. Design k8s architecture?

**Cluster layout:**
- **Multi-AZ** node groups across three availability zones
- **Separate node groups by workload class**: general (spot-heavy), memory-optimised, GPU (tainted so only tolerating pods land there, Q489)
- **Namespaces per environment or team**, with ResourceQuotas and LimitRanges
- **Managed control plane** (EKS) — running your own is not a good use of anyone's time

**Workload layout:**
```
ingress-nginx / ALB Controller
  ├── api           Deployment, HPA on request rate, 3–20 replicas
  ├── workers       Deployment, KEDA on queue depth
  ├── gpu-inference Deployment on tainted GPU nodes, startup probe
  └── cron          CronJobs with concurrencyPolicy: Forbid
Platform:
  ├── external-secrets, cert-manager, karpenter
  └── prometheus, grafana, otel-collector, fluent-bit
Data (outside the cluster):
  └── RDS, ElastiCache, S3, SQS
```

**The decision worth defending: stateful services stay outside the cluster.** RDS and ElastiCache rather than PostgreSQL and Redis in StatefulSets. Managed services give you backups, failover, patching, and monitoring that you would otherwise build and operate. **Running a database in Kubernetes is possible and rarely the best use of your time** (Q494).

**Security baseline:** IRSA for AWS access (Q492), network policies default-deny, pod security standards enforced, non-root containers, read-only root filesystems.

**Deployment:** GitOps (ArgoCD/Flux) — the cluster state is what's in git, deploys are commits, and drift is detected and corrected. Images referenced by digest (Q480).

**The honest scoping note:** for a small team with a handful of services, **ECS Fargate or Cloud Run delivers most of this with a fraction of the operational surface.** Kubernetes earns its complexity at a certain scale and team size, and saying where that line is demonstrates judgement (Q473).

---

## 500. Blue/green vs canary?

| | Blue/Green | Canary |
|---|---|---|
| Mechanism | Two full environments, switch traffic at once | Shift a small percentage, increase gradually |
| Resource cost | **2× during deploy** | Marginal |
| Rollback speed | **Instant** — switch back | Fast — route to 0% |
| Risk exposure | All users at once after cutover | **Small subset first** |
| Validation | Test green before cutover | Compare live metrics between versions |
| Complexity | Lower | Higher — needs traffic splitting and metric comparison |
| Database migrations | Still must be compatible | Still must be compatible |

**Blue/green when:** you can afford double resources, you want instant rollback, and validation can happen before any user traffic. Good for infrequent, high-stakes releases.

**Canary when:** you want to limit blast radius, you have good metrics to compare, and you deploy frequently. **Better for changes whose effects only appear under real traffic** — which includes almost everything in an LLM system.

**The LLM-specific argument for canary** (Q329): a prompt or model change cannot be validated fully in staging. Its effect on quality, cost, and latency shows up under real query distribution. Canary lets you route 5% of traffic and compare refusal rate, citation validity, cost per request, and thumbs-down rate before committing (Q438).

**Implementation:** Argo Rollouts or Flagger automate progressive delivery with automatic rollback on metric regression:
```yaml
steps:
- setWeight: 5
- pause: {duration: 10m}
- analysis: {templates: [{templateName: success-rate}]}
- setWeight: 25
```

**The caveat that applies to both:** neither solves database migrations. **Both versions run simultaneously in both strategies**, so expand/contract is required regardless (Q484). Choosing a deployment strategy doesn't relieve you of migration discipline.

---

## 501. Multi-region?

**Ask first: what problem are you solving?** The answer determines the architecture, and the three motivations require very different designs.

| Goal | Architecture |
|---|---|
| **Latency** for global users | Active-active with regional reads, or just a CDN |
| **Disaster recovery** | Active-passive with replication and a tested failover |
| **Data residency** | Regional isolation — data never crosses |

**The hard part is always data, not compute.** Running pods in two regions is easy. Keeping state consistent across them is the entire problem.

**Active-passive (DR):** primary region serves everything; a standby has cross-region replicated data (RDS cross-region read replica, S3 replication). Failover is a manual or semi-automated promotion. **RTO in minutes to hours, RPO in seconds** (async replication lag). Simplest and adequate for most requirements.

**Active-active:** both regions serve traffic. Now you must solve write conflicts. Options: partition by tenant so each has a home region (**usually the right answer** — it avoids conflicts entirely), or use a globally distributed database (Aurora Global, DynamoDB Global Tables, Spanner) and accept its consistency model.

**The costs to state honestly:**
- Cross-region data transfer is billed and significant
- Double the infrastructure for active-active
- Replication lag means read-your-writes problems across regions (Q170)
- Operational complexity roughly doubles
- **Failover that isn't regularly tested does not work** — this is the one that catches people

**The honest recommendation:** multi-AZ within one region gives you most of the availability benefit at a fraction of the complexity. **Multi-region is justified by a specific requirement — a regulatory one, a genuine RTO commitment, or measured latency for a distant user base — not by ambition.**

---

## 502. Disaster recovery?

**Define the two numbers first, because everything else follows from them:**
- **RPO** (Recovery Point Objective) — how much data can you lose?
- **RTO** (Recovery Time Objective) — how long can you be down?

**These are business decisions, and the architecture and cost follow directly.** RPO of zero requires synchronous replication and its latency cost. RTO of minutes requires a warm standby and its expense.

**The tiers:**

| Tier | RPO | RTO | Cost |
|---|---|---|---|
| Backup and restore | Hours | Hours–days | Lowest |
| Pilot light | Minutes | ~1 hour | Low |
| Warm standby | Seconds | Minutes | Medium |
| Active-active | ~0 | ~0 | Highest |

**What must be recoverable:**
1. **Database** — automated backups, PITR, cross-region snapshot copies
2. **Object storage** — versioning plus cross-region replication
3. **Infrastructure** — Terraform, so the environment is reproducible from code
4. **Application config and secrets** — replicated to the DR region
5. **Container images** — cross-region ECR replication, or a pull-through cache
6. **DNS** — health-checked failover records with low TTLs

**The vector-store-specific note** (Q409): embeddings are *derived* data and can be rebuilt from chunk text. The irreplaceable asset is the source documents. **But rebuilding an HNSW index takes hours**, so physical backups including index files give a far better RTO than logical dumps.

**The part that determines whether any of this works: test it.** A DR plan that has never been exercised is a document, not a capability. **Run a real failover drill on a schedule** — the failures you find will be DNS TTLs, missing IAM roles in the DR region, and images that aren't replicated. All discoverable in a drill and all outage-causing in a real event.

---

## 503. Observability stack?

Full treatment in Document 14. The infrastructure layer:

**The three pillars plus one:**
- **Metrics** — Prometheus (or Amazon Managed Prometheus), visualised in Grafana
- **Logs** — Fluent Bit → CloudWatch/Loki/OpenSearch, structured JSON
- **Traces** — OpenTelemetry Collector → Jaeger/Tempo/X-Ray
- **Events** — Kubernetes events, deploy markers, incident annotations

**The unifying requirement: correlation.** A trace ID on every log line and every span, propagated across service boundaries (Q87). Without it you have three disconnected systems and a manual join.

**Deployment pattern:**
```
Application → OTel SDK → OTel Collector (DaemonSet) → backends
Kubernetes  → kube-state-metrics + node-exporter → Prometheus
```
The **OpenTelemetry Collector as a single pipeline** is the modern approach — one agent receiving metrics, logs, and traces, applying sampling and redaction centrally, and exporting to whatever backends you choose. **It decouples your instrumentation from your vendor**, which is worth a lot when vendor pricing changes.

**What to instrument at the platform level:**
- RED metrics (Rate, Errors, Duration) per service
- USE metrics (Utilisation, Saturation, Errors) per node
- Pod restarts, OOMKills, pending pods, HPA state
- Deployment events as annotations on dashboards

**That last one is disproportionately useful:** a graph showing a latency change with a deploy marker on it answers "what changed?" instantly, and it costs almost nothing to add.

**The cost warning:** observability ingest is frequently a top-three infrastructure line item. **Sample traces (1–5%), set log retention, drop debug logs in production, and control metric cardinality** — a label with unbounded values (user ID, request ID) creates millions of time series and will produce a memorable bill (Q547).

---

## 504. Security posture?

Full treatment in Document 13. The Kubernetes/AWS layer:

**Identity and access:**
- **IRSA** for pod-to-AWS access — no long-lived credentials anywhere (Q492)
- **RBAC** least-privilege; no cluster-admin for applications
- **Separate AWS accounts** per environment, so a staging compromise can't reach production

**Network:**
- **NetworkPolicies default-deny**, with explicit allows. Without them, any pod can reach any pod — including your database.
- Private subnets for nodes; no public IPs
- Security groups least-privilege
- TLS everywhere, including in-cluster (service mesh or application-level)

**Workload:**
- **Non-root, read-only root filesystem, dropped capabilities, no privilege escalation:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities: {drop: ["ALL"]}
```
- **Pod Security Standards** enforced at `restricted` where possible
- Resource limits on everything, so one workload can't starve a node

**Supply chain:**
- Image scanning in CI, blocking on critical CVEs (Q509)
- Minimal base images (Q478)
- **Image signing and admission verification** — only signed images from your registry may run
- SBOM generation
- Dependency pinning by digest

**Data:**
- Encryption at rest (EBS, RDS, S3) and in transit
- etcd encryption enabled — **not on by default**
- Secrets from Secrets Manager, mounted as files (Q486)

**Detection:** GuardDuty, CloudTrail, runtime detection (Falco), and audit logging of the Kubernetes API. **Prevention fails eventually; detection is what bounds the damage.**

---

*End of Document 12. Next: Document 13 — Security (questions 505–528).*
