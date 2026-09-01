# Kubernetes Workloads and Storage

Beyond Deployments: StatefulSets, DaemonSets, Jobs, CronJobs, persistent storage, probes, autoscaling, and resource management. This is the complete picture of what runs in a cluster.

---

## Table of Contents

1. [Probes — Readiness, Liveness, Startup](#1)
2. [Resource Requests and Limits](#2)
3. [Horizontal Pod Autoscaler (HPA)](#3)
4. [StatefulSets — For Stateful Applications](#4)
5. [DaemonSets — One Pod Per Node](#5)
6. [Jobs and CronJobs — Batch Processing](#6)
7. [Persistent Volumes and Claims](#7)
8. [StorageClasses](#8)
9. [Init Containers — Setup Before Main Container](#9)
10. [Pod Disruption Budgets — Safe Maintenance](#10)
11. [Node Affinity and Taints](#11)

---

## 1. Probes — Readiness, Liveness, Startup

Probes are how Kubernetes determines whether a pod is healthy and ready to serve traffic. There are three types. Understand all three — misconfiguring them causes silent outages.

### Readiness Probe — "Is the pod ready to receive traffic?"

If the readiness probe fails, the pod is removed from the Service's endpoint list. Traffic stops routing to it. The pod is not restarted — it just doesn't receive traffic until it recovers.

```yaml
readinessProbe:
  httpGet:
    path: /health          # your app must return 2xx here
    port: 8000
  initialDelaySeconds: 10  # wait 10s before first check (app startup time)
  periodSeconds: 5         # check every 5 seconds
  failureThreshold: 3      # after 3 failures: remove from endpoints
  successThreshold: 1      # after 1 success: add back to endpoints
  timeoutSeconds: 3        # probe request times out after 3s
```

**Use case:** app connects to database on startup. During startup, readiness probe fails → no traffic goes to pod → when app finishes connecting, probe succeeds → pod receives traffic. Zero dropped requests during startup.

### Liveness Probe — "Is the pod alive? Should it be restarted?"

If the liveness probe fails, Kubernetes kills the container and restarts it (according to `restartPolicy`).

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 30  # longer than readiness — app must be fully up
  periodSeconds: 10
  failureThreshold: 3      # after 3 failures: kill + restart
  timeoutSeconds: 5
```

**Use case:** detecting deadlocks or hung processes. The app is running but not responding. Without a liveness probe, it stays "Running" forever. With one, Kubernetes restarts it.

**Warning:** do not set `initialDelaySeconds` too low. If the liveness probe fires before the app is ready, it will kill and restart it in an infinite loop.

### Startup Probe — "Has the pod finished starting?"

For apps with very slow startup (legacy apps, JVM warmup). The startup probe runs first; liveness and readiness don't run until startup probe succeeds.

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8000
  failureThreshold: 30     # allow up to 30 * 10s = 5 minutes to start
  periodSeconds: 10
```

Without a startup probe, a slow-starting app may be killed by liveness probe during startup, causing a restart loop.

### Probe types

```yaml
# HTTP GET (most common):
httpGet:
  path: /health
  port: 8000
  httpHeaders:
    - name: Custom-Header
      value: Awesome

# TCP socket (check if port is open):
tcpSocket:
  port: 5432

# Execute a command:
exec:
  command:
    - cat
    - /tmp/healthy
  # Success if command exits 0

# gRPC (Kubernetes 1.24+):
grpc:
  port: 50051
```

### A complete probe configuration

```python
# FastAPI health endpoint:
from fastapi import FastAPI, HTTPException
from asyncpg import Pool

app = FastAPI()

@app.get("/health")
async def health():
    # Check DB connectivity:
    try:
        await db_pool.fetchval("SELECT 1")
    except Exception:
        raise HTTPException(status_code=503, detail="Database unavailable")
    return {"status": "ok"}

@app.get("/ready")
async def ready():
    # Check if app is done with startup tasks:
    if not startup_complete:
        raise HTTPException(status_code=503, detail="Not ready yet")
    return {"status": "ready"}
```

```yaml
startupProbe:
  httpGet:
    path: /ready
    port: 8000
  failureThreshold: 20
  periodSeconds: 5

readinessProbe:
  httpGet:
    path: /ready
    port: 8000
  periodSeconds: 5
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /health
    port: 8000
  periodSeconds: 10
  failureThreshold: 3
```

---

## 2. Resource Requests and Limits

Every container should declare what resources it needs.

```yaml
resources:
  requests:
    cpu: "250m"     # minimum CPU guaranteed (250 millicores = 0.25 core)
    memory: "256Mi" # minimum memory guaranteed
  limits:
    cpu: "500m"     # maximum CPU allowed
    memory: "512Mi" # maximum memory allowed
```

### CPU units

```
1000m (millicores) = 1 CPU core
250m = 0.25 core (25% of one core)
500m = 0.5 core

"250m" means: at minimum, this container gets 25% of one CPU core.
Under contention, it won't get less than 250m.
It may use up to 500m if the CPU is available.
```

### Memory units

```
Ki = kibibyte = 1024 bytes
Mi = mebibyte = 1024 Ki
Gi = gibibyte = 1024 Mi

256Mi ≈ 268 MB
512Mi ≈ 537 MB
1Gi   ≈ 1.07 GB
```

### Requests vs limits — why both matter

**Requests:**
- Used by the scheduler to decide which node can run the pod
- A node with 4 CPU cores and 8 GiB RAM can run pods whose requests total ≤ 4 cores and ≤ 8 GiB
- The pod is *guaranteed* at least this much

**Limits:**
- The pod cannot exceed this
- **CPU limit:** if exceeded, the container is throttled (slowed down, not killed)
- **Memory limit:** if exceeded, the container is OOM-killed (killed immediately, like `kill -9`)

```
requests:
  memory: "256Mi"
limits:
  memory: "512Mi"

Normal operation:    uses 300 Mi → fine (between request and limit)
Memory leak:         uses 600 Mi → OOM killed → restarted
Very bad memory leak: uses 600 Mi → OOM killed → restarted (loop)
                     → you need to fix the leak
```

### Quality of Service classes

Kubernetes assigns a QoS class based on requests/limits:

```
Guaranteed (best — protected):
  requests == limits for ALL containers
  resources:
    requests: {cpu: "500m", memory: "512Mi"}
    limits:   {cpu: "500m", memory: "512Mi"}
  → This pod is last to be evicted under node pressure

Burstable (middle):
  requests < limits (or only some containers have both)
  → Evicted under pressure, but not first

BestEffort (worst — no resources declared):
  No requests or limits at all
  → First to be evicted under node pressure
```

In production: always declare both requests and limits. Aim for Guaranteed or Burstable.

---

## 3. Horizontal Pod Autoscaler (HPA)

HPA automatically scales the number of pod replicas based on observed metrics.

```
CPU usage increases
    ↓
HPA reads metrics from Metrics Server
    ↓
HPA calculates: desiredReplicas = ceil(currentReplicas × (currentCPU / targetCPU))
    ↓
HPA updates Deployment's replicas field
    ↓
Deployment creates/removes pods
```

### Install Metrics Server (required for HPA)

```bash
# Most managed clusters (EKS, GKE, AKS) have it pre-installed.
# For local (minikube):
minikube addons enable metrics-server

# For vanilla Kubernetes:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### CPU-based HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app

  minReplicas: 2         # never go below this
  maxReplicas: 10        # never go above this

  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70    # scale up when avg CPU > 70%
```

### Memory and custom metric HPA

```yaml
metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80   # scale up when memory > 80%

  # Custom metric (requires Prometheus adapter or similar):
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"     # scale up when > 1000 req/s per pod
```

```bash
# Check HPA status:
kubectl get hpa -n production
kubectl describe hpa my-app-hpa -n production

# Watch live:
kubectl get hpa -n production -w
```

### Scaling behavior (preventing flapping)

```yaml
spec:
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60    # wait 60s before scaling up again
      policies:
        - type: Pods
          value: 4                      # add at most 4 pods per scale event
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300   # wait 5 min before scaling down
      policies:
        - type: Pods
          value: 2                      # remove at most 2 pods per event
          periodSeconds: 60
```

Scale-down is conservative (long stabilization window) to avoid removing pods during brief traffic dips. Scale-up is aggressive to handle spikes quickly.

---

## 4. StatefulSets — For Stateful Applications

Deployments manage stateless pods: any pod is interchangeable, they get random names, any can be restarted anywhere. For stateful applications (databases, Kafka, ZooKeeper), you need:
- Stable, predictable pod names
- Stable network identities (DNS)
- Ordered startup and shutdown
- Each pod attached to its own persistent storage

StatefulSet provides all of this.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: production
spec:
  serviceName: "postgres"   # must match a Headless Service name
  replicas: 3

  selector:
    matchLabels:
      app: postgres

  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql/data

  # Volume claim template: each pod gets its own PVC
  volumeClaimTemplates:
    - metadata:
        name: pgdata
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: standard
        resources:
          requests:
            storage: 10Gi
```

### StatefulSet pod names

```
StatefulSet "postgres" with 3 replicas:
  postgres-0   (first — starts first)
  postgres-1   (second)
  postgres-2   (third — starts last)

If postgres-1 crashes → Kubernetes restarts "postgres-1" specifically
In a Deployment, it would create "postgres-abc12" — a new random name
```

### Headless Service (required for StatefulSet DNS)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres      # must match StatefulSet's serviceName
  namespace: production
spec:
  selector:
    app: postgres
  clusterIP: None     # ← headless: no cluster IP, just DNS
  ports:
    - port: 5432
```

DNS entries created for each pod:
```
postgres-0.postgres.production.svc.cluster.local
postgres-1.postgres.production.svc.cluster.local
postgres-2.postgres.production.svc.cluster.local
```

Your application can connect to specific pods by name. Primary: `postgres-0`. Replicas: `postgres-1`, `postgres-2`.

```bash
# Scale (careful with stateful apps — test first):
kubectl scale statefulset postgres --replicas=5 -n production

# Ordered rolling update:
kubectl rollout status statefulset/postgres -n production
```

---

## 5. DaemonSets — One Pod Per Node

A DaemonSet ensures that exactly one pod runs on every node (or on a subset of nodes). When nodes are added, the pod is automatically scheduled on them. When nodes are removed, pods are cleaned up.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      containers:
        - name: fluentd
          image: fluentd:v1.16-debian-1
          resources:
            limits:
              memory: "200Mi"
              cpu: "200m"
          volumeMounts:
            - name: varlog
              mountPath: /var/log        # collect host logs
            - name: varlibdocker
              mountPath: /var/lib/docker/containers
              readOnly: true
      volumes:
        - name: varlog
          hostPath:
            path: /var/log
        - name: varlibdocker
          hostPath:
            path: /var/lib/docker/containers
```

**Use cases:**
- Log collection agents (Fluentd, Filebeat, Promtail)
- Monitoring agents (Datadog agent, Prometheus node-exporter)
- Network plugins (CNI plugins, kube-proxy itself is a DaemonSet)
- Storage plugins (CSI drivers)

---

## 6. Jobs and CronJobs — Batch Processing

### Job — run a task to completion

A Job creates one or more pods and ensures they complete successfully. Unlike Deployments, pods are not restarted after success.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  namespace: production
spec:
  completions: 1          # how many pods must succeed
  parallelism: 1          # how many pods run simultaneously
  backoffLimit: 3         # retry failed pod up to 3 times
  activeDeadlineSeconds: 600  # kill job after 10 minutes (prevent stuck jobs)

  template:
    spec:
      restartPolicy: OnFailure   # Never or OnFailure (not Always for Jobs)
      containers:
        - name: migrate
          image: myapp:1.0.0
          command: ["alembic", "upgrade", "head"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: database-url
```

```bash
# Run job:
kubectl apply -f migration-job.yaml

# Watch progress:
kubectl get jobs -n production -w
kubectl describe job db-migration -n production

# Get logs from job pod:
kubectl logs -l job-name=db-migration -n production

# Delete job (also deletes completed pods):
kubectl delete job db-migration -n production
```

**Parallel jobs** (e.g., process 100 items in parallel):

```yaml
spec:
  completions: 100    # need 100 successful completions
  parallelism: 10     # run 10 pods at a time
```

### CronJob — run on a schedule

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-cleanup
  namespace: production
spec:
  schedule: "0 2 * * *"     # run at 2:00 AM UTC every day
  # Cron syntax: minute hour day month weekday
  # 0 2 * * *    → 2:00 AM daily
  # */5 * * * *  → every 5 minutes
  # 0 0 * * 0    → midnight every Sunday
  # 0 9-17 * * 1-5 → every hour 9-17, Monday–Friday

  concurrencyPolicy: Forbid      # don't start new job if previous is still running
  # Allow: allow concurrent runs
  # Forbid: skip if previous still running
  # Replace: cancel previous, start new

  successfulJobsHistoryLimit: 3  # keep last 3 successful job logs
  failedJobsHistoryLimit: 1      # keep last 1 failed job log

  startingDeadlineSeconds: 300   # if missed, don't run if > 5 min late

  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: cleanup
              image: myapp:1.0.0
              command: ["python", "scripts/cleanup.py"]
              env:
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef:
                      name: app-secrets
                      key: database-url
```

```bash
# Check cronjob status:
kubectl get cronjobs -n production

# Manually trigger a cronjob (for testing):
kubectl create job --from=cronjob/daily-cleanup manual-cleanup-test -n production

# Get history of jobs created by cronjob:
kubectl get jobs -n production
```

---

## 7. Persistent Volumes and Claims

Pods are ephemeral. Their filesystems disappear when pods are deleted. Persistent Volumes (PV) provide durable storage that outlives pods.

### The three-layer abstraction

```
PersistentVolume (PV):
  Actual storage: NFS share, AWS EBS volume, GCP PD, etc.
  Created by a cluster admin (or dynamically by StorageClass).

PersistentVolumeClaim (PVC):
  A request for storage by a user.
  "I need 10 GB of ReadWriteOnce storage."
  Kubernetes finds a matching PV and binds it.

Pod:
  Mounts the PVC as a volume.
  App writes to /data → data goes to the bound PV → persists after pod deletion.
```

### Creating a PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: production
spec:
  accessModes:
    - ReadWriteOnce      # RWO: mounted by one node at a time (most block storage)
    # ReadOnlyMany (ROX): read by multiple nodes simultaneously
    # ReadWriteMany (RWX): read/write by multiple nodes (requires NFS or similar)
    # ReadWriteOncePod (RWOP): one pod only (Kubernetes 1.22+)
  storageClassName: standard    # which StorageClass to use
  resources:
    requests:
      storage: 10Gi
```

### Using a PVC in a Pod

```yaml
spec:
  containers:
    - name: postgres
      image: postgres:15
      volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data

  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: postgres-data   # reference the PVC
```

### PVC lifecycle

```
PVC created → Kubernetes finds matching PV (or creates one via StorageClass)
Pod uses PVC → PVC is "Bound"
Pod deleted → PVC remains (data safe)
Pod created again, mounts same PVC → data is there

PVC deleted → depends on reclaim policy:
  Retain:  PV stays, must be manually cleaned up
  Delete:  PV and underlying storage deleted automatically
  Recycle: deprecated (use Delete)
```

---

## 8. StorageClasses

A StorageClass defines how storage is provisioned. When a PVC is created with a StorageClass, the storage is dynamically provisioned (no need to pre-create PVs).

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs      # which plugin creates the storage
parameters:
  type: gp3                             # EBS volume type
  iops: "3000"
  throughput: "125"
  encrypted: "true"
reclaimPolicy: Delete                   # what happens when PVC is deleted
allowVolumeExpansion: true              # can PVCs resize themselves?
volumeBindingMode: WaitForFirstConsumer # don't provision until pod is scheduled
```

```bash
# List storage classes:
kubectl get storageclass

# Managed clusters provide default storage classes:
# EKS:  gp2 (AWS EBS)
# GKE:  standard (GCP PD)
# AKS:  default (Azure Disk)

# Set default storage class:
kubectl patch storageclass gp3 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Volume expansion

```yaml
# Increase PVC size (storageClass must have allowVolumeExpansion: true):
kubectl patch pvc postgres-data -n production -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# Check expansion status:
kubectl get pvc postgres-data -n production
kubectl describe pvc postgres-data -n production
```

---

## 9. Init Containers — Setup Before Main Container

Init containers run to completion before main containers start. They share the same volumes but run sequentially.

```yaml
spec:
  initContainers:
    # Wait for database to be ready:
    - name: wait-for-db
      image: busybox:1.35
      command: ['sh', '-c', 'until nc -z db 5432; do echo waiting; sleep 2; done']
      # nc = netcat: check if db:5432 is accepting connections

    # Run database migrations:
    - name: run-migrations
      image: myapp:1.0.0
      command: ["alembic", "upgrade", "head"]
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-url

  # Main containers start only after all init containers succeed:
  containers:
    - name: web
      image: myapp:1.0.0
      ...
```

**Use cases:**
- Wait for a dependency to be available before starting
- Run database migrations
- Download or generate config files
- Register with a service registry
- Set file permissions on a volume

---

## 10. Pod Disruption Budgets — Safe Maintenance

A PodDisruptionBudget (PDB) limits how many pods of a set can be unavailable at the same time due to **voluntary disruptions** (node drains for maintenance, cluster upgrades).

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
  namespace: production
spec:
  selector:
    matchLabels:
      app: my-app

  # Option 1: minimum available pods:
  minAvailable: 2          # at least 2 pods must always be running

  # Option 2: maximum unavailable pods:
  # maxUnavailable: 1      # at most 1 pod can be down at once
```

```bash
# Check PDB status:
kubectl get pdb -n production

# During a node drain, Kubernetes respects the PDB:
kubectl drain node-name --ignore-daemonsets --delete-emptydir-data
# If draining would violate the PDB, the drain waits
```

**Why PDBs matter:** without a PDB, a node drain can take down all pods of a small deployment at once. With `minAvailable: 2`, the drain will only proceed one pod at a time, ensuring availability.

---

## 11. Node Affinity and Taints

### Node Affinity — attract pods to nodes

```yaml
spec:
  affinity:
    nodeAffinity:
      # Required: pod MUST be placed on matching nodes
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-type
                operator: In
                values: ["gpu"]         # only run on GPU nodes

      # Preferred: prefer these nodes, but not required
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
              - key: zone
                operator: In
                values: ["us-east-1a"]  # prefer this availability zone
```

### Pod Anti-Affinity — spread pods across nodes

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: my-app
          topologyKey: kubernetes.io/hostname
      # Don't place two pods with label app=my-app on the same node
      # Each replica goes to a different node → survives single node failure
```

### Taints and Tolerations

Taints repel pods from nodes. Tolerations allow pods to be scheduled on tainted nodes.

```bash
# Taint a node (e.g., reserve it for GPU workloads):
kubectl taint nodes gpu-node-1 workload=gpu:NoSchedule
# Pods without matching toleration cannot be scheduled on this node

# Remove taint:
kubectl taint nodes gpu-node-1 workload=gpu:NoSchedule-
```

```yaml
# Toleration in Pod spec:
spec:
  tolerations:
    - key: "workload"
      operator: "Equal"
      value: "gpu"
      effect: "NoSchedule"
  # This pod can be scheduled on gpu-node-1
```

**Taint effects:**
- `NoSchedule`: new pods without toleration are not scheduled. Existing pods stay.
- `PreferNoSchedule`: prefer not to schedule, but will if no other options.
- `NoExecute`: evicts existing pods without toleration. Strongest.

---

*Previous: Fundamentals, Pods, Deployments, Services → `01-kubernetes-fundamentals.md`*
*Next: Ingress, TLS, DNS → `03-networking-and-ingress.md`*
*Production: RBAC, monitoring, Helm → `04-production-and-operations.md`*
