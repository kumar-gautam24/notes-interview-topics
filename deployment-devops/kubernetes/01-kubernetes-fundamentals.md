# Kubernetes Fundamentals — From Zero to Deploying Your First App

Kubernetes (K8s) is the standard platform for running containers in production at scale. This guide covers what Kubernetes is, why it exists, how it works internally, and the essential objects every developer must know — with real YAML and real kubectl commands.

---

## Table of Contents

1. [What Is Kubernetes and Why It Exists](#1)
2. [Architecture — Control Plane and Worker Nodes](#2)
3. [Core Objects Overview](#3)
4. [kubectl — The Command Line Tool](#4)
5. [Namespaces](#5)
6. [Pods — The Smallest Unit](#6)
7. [Deployments — Running and Managing Pods](#7)
8. [Services — Networking Inside the Cluster](#8)
9. [ConfigMaps and Secrets](#9)
10. [Practical: Deploy a FastAPI App to Kubernetes](#10)
11. [Quick Reference — kubectl Commands](#11)

---

## 1. What Is Kubernetes and Why It Exists

### The problem

Docker solves "runs on my machine." But in production you have new problems:

```
Problem 1: Your container crashes. Nobody restarts it.
Problem 2: Traffic spikes. You need 10 containers, not 1. How do you start them?
Problem 3: You deploy a new version. How do you update containers with zero downtime?
Problem 4: You have 50 containers across 10 servers. Where does each one run?
Problem 5: Container A needs to talk to Container B. What is B's address?
```

Kubernetes solves all of these.

### What Kubernetes does

```
You tell Kubernetes: "I want 3 copies of my web app running, with 512 MB RAM each."
Kubernetes figures out:
  - Which nodes (servers) have capacity
  - Schedules the containers on those nodes
  - Monitors their health and restarts them if they crash
  - Replaces them during rolling deployments
  - Routes traffic to healthy copies
  - Re-schedules if a node fails
```

You describe the **desired state**. Kubernetes continuously works to make reality match your description. This is called **declarative configuration**.

### Kubernetes vs Docker Compose

| | Docker Compose | Kubernetes |
|--|---------------|-----------|
| Scope | Single machine | Cluster of machines |
| Use for | Local development | Production, staging |
| Self-healing | No | Yes |
| Auto-scaling | No | Yes |
| Rolling updates | No | Yes |
| Load balancing | Basic | Built-in |
| Complexity | Simple | Complex |

Use Docker Compose for development. Use Kubernetes for production.

---

## 2. Architecture — Control Plane and Worker Nodes

A Kubernetes cluster has two kinds of machines:

```
┌──────────────────────────────────────────────────────────────────┐
│                         CLUSTER                                   │
│                                                                   │
│  ┌─────────────────────────────────┐                             │
│  │         Control Plane           │  ← brains of the cluster    │
│  │                                 │                             │
│  │  API Server  ← all communication goes through here            │
│  │  etcd        ← stores all cluster state (database)            │
│  │  Scheduler   ← decides which node runs each pod               │
│  │  Controller  ← watches state, makes corrections               │
│  └─────────────────────────────────┘                             │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │  Worker Node │  │  Worker Node │  │  Worker Node │           │
│  │              │  │              │  │              │           │
│  │  kubelet     │  │  kubelet     │  │  kubelet     │           │
│  │  kube-proxy  │  │  kube-proxy  │  │  kube-proxy  │           │
│  │  container   │  │  container   │  │  container   │           │
│  │  runtime     │  │  runtime     │  │  runtime     │           │
│  │  [pods...]   │  │  [pods...]   │  │  [pods...]   │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└──────────────────────────────────────────────────────────────────┘
```

### Control Plane components

**API Server (`kube-apiserver`):**
The front door to the cluster. Every kubectl command you run sends an HTTP request to the API server. Every component in the cluster talks through the API server. Never bypassed.

**etcd:**
A distributed key-value store. Holds the entire cluster state: which pods exist, what their desired state is, which nodes are registered, etc. If etcd is lost and you have no backup, your cluster state is gone.

**Scheduler (`kube-scheduler`):**
When a new Pod is created, the scheduler decides which node to place it on. It considers:
- How much CPU/memory does the pod need?
- Which nodes have capacity?
- Are there any placement rules (node affinity, taints)?

**Controller Manager (`kube-controller-manager`):**
Runs a set of controllers — loops that watch the cluster state and make corrections. The ReplicaSet controller watches: "I need 3 pods, I see 2 running → start 1 more."

### Worker Node components

**kubelet:**
An agent running on every worker node. It talks to the API server, receives pod specs, and tells the container runtime to start/stop containers. Reports pod status back to the control plane.

**kube-proxy:**
Handles network rules on each node. Maintains IPtables/eBPF rules so that traffic to a Service is forwarded to the correct pod.

**Container runtime:**
The software that actually runs containers. Usually containerd (Docker uses it too). Kubernetes talks to the runtime via CRI (Container Runtime Interface).

---

## 3. Core Objects Overview

Everything in Kubernetes is an **object** — a piece of desired state stored in etcd. You create objects with YAML files.

```
Pod            → 1 or more containers, runs on one node
ReplicaSet     → ensures N pods are always running
Deployment     → manages ReplicaSets, adds rolling updates and rollback
Service        → stable network endpoint in front of pods
ConfigMap      → configuration data (non-secret)
Secret         → sensitive configuration data (passwords, tokens)
Namespace      → virtual cluster within the cluster, for isolation
Ingress        → HTTP routing rules (external → service)
PersistentVolume → storage abstraction
HorizontalPodAutoscaler → auto-scaling based on CPU/memory
```

Every Kubernetes YAML has the same four top-level fields:

```yaml
apiVersion: apps/v1        # which API group handles this object
kind: Deployment           # what type of object
metadata:                  # name, namespace, labels
  name: my-app
  namespace: default
  labels:
    app: my-app
spec:                      # desired state (what you want)
  ...
```

---

## 4. kubectl — The Command Line Tool

kubectl is how you talk to Kubernetes. Install it at: https://kubernetes.io/docs/tasks/tools/

### Configuration

kubectl reads from `~/.kube/config` to know which cluster to talk to.

```bash
# See current context (which cluster you're talking to):
kubectl config current-context

# List all contexts (clusters configured):
kubectl config get-contexts

# Switch to a different cluster:
kubectl config use-context my-production-cluster

# View config:
kubectl config view
```

### Basic interaction patterns

```bash
# Apply a YAML file (create or update):
kubectl apply -f deployment.yaml

# Apply all YAML files in a directory:
kubectl apply -f ./k8s/

# Get resources:
kubectl get pods
kubectl get pods -n kube-system        # in a specific namespace
kubectl get pods -A                    # all namespaces
kubectl get pods -o wide               # with node and IP
kubectl get pods -o yaml               # full YAML output
kubectl get pods -w                    # watch (live updates)

# Describe (detailed info, events):
kubectl describe pod my-pod
kubectl describe deployment my-app

# Delete:
kubectl delete pod my-pod
kubectl delete -f deployment.yaml      # delete everything in the file

# Logs:
kubectl logs my-pod
kubectl logs my-pod -f                 # follow
kubectl logs my-pod --tail=100
kubectl logs my-pod -c my-container    # specific container in multi-container pod

# Execute command in pod:
kubectl exec -it my-pod -- bash
kubectl exec my-pod -- cat /etc/config

# Port-forward (expose pod to your localhost for debugging):
kubectl port-forward pod/my-pod 8080:8000
kubectl port-forward service/my-service 8080:80
```

---

## 5. Namespaces

Namespaces are virtual clusters inside a physical cluster. They provide isolation and organization.

```
Cluster
├── namespace: default        ← where objects go if you don't specify
├── namespace: kube-system    ← Kubernetes internal components (don't touch)
├── namespace: production     ← your production workloads
├── namespace: staging        ← your staging workloads
└── namespace: monitoring     ← Prometheus, Grafana, etc.
```

```bash
# List namespaces:
kubectl get namespaces

# Create a namespace:
kubectl create namespace production
# or with YAML:
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    env: production
EOF

# Work in a specific namespace:
kubectl get pods -n production
kubectl apply -f app.yaml -n production

# Set default namespace for this session:
kubectl config set-context --current --namespace=production
# Now kubectl get pods uses 'production' namespace by default

# Delete a namespace (and EVERYTHING in it):
kubectl delete namespace staging  # careful — no undo
```

Resource limits by namespace (ResourceQuota):

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"           # total CPU requested across all pods
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    pods: "100"                  # max number of pods
    persistentvolumeclaims: "10"
```

---

## 6. Pods — The Smallest Unit

A Pod is the smallest deployable unit in Kubernetes. It is one or more containers that:
- Share the same network namespace (same IP address)
- Can communicate via localhost
- Share the same storage volumes

### Why not just "one pod = one container"?

The multi-container pod pattern is used for **sidecars**:

```
Pod: web-app
  Container 1: FastAPI app (main workload)
  Container 2: Log shipper (reads app logs, sends to Elasticsearch)
  Container 3: Proxy sidecar (Envoy — for service mesh)
```

The log shipper runs alongside the app and shares its log volume. They start and stop together.

### Pod YAML

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: default
  labels:
    app: my-app
    version: "1.0"
spec:
  containers:
    - name: web
      image: myapp:1.0.0
      ports:
        - containerPort: 8000
          name: http
      env:
        - name: DATABASE_URL
          value: "postgres://..."
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets      # name of a Secret object
              key: secret-key
      resources:
        requests:
          cpu: "250m"               # 0.25 CPU core
          memory: "256Mi"           # 256 MB
        limits:
          cpu: "500m"               # 0.5 CPU core
          memory: "512Mi"           # 512 MB
      readinessProbe:               # is the pod ready to receive traffic?
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 10
        periodSeconds: 5
        failureThreshold: 3
      livenessProbe:                # is the pod alive? restart if not
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 30
        periodSeconds: 10
        failureThreshold: 3
  restartPolicy: Always             # Always, OnFailure, Never
```

### Important: do not run bare Pods in production

Bare Pods (created directly) are not rescheduled if a node fails. Always use a Deployment. Pods are rarely created directly — they're managed by higher-level objects.

---

## 7. Deployments — Running and Managing Pods

A Deployment is the most common way to run an application in Kubernetes. It manages a ReplicaSet, which manages Pods.

```
Deployment
  └── ReplicaSet (desired: 3)
        ├── Pod 1 (running)
        ├── Pod 2 (running)
        └── Pod 3 (running)
```

If a Pod crashes, the ReplicaSet notices and starts a replacement. The Deployment manages rolling updates — replacing old Pods with new ones gradually.

### Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
  labels:
    app: my-app
spec:
  replicas: 3                    # how many pod copies to run

  selector:
    matchLabels:
      app: my-app                # manages pods with this label

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1          # at most 1 pod unavailable during update
      maxSurge: 1                # at most 1 extra pod during update

  template:                      # pod template — same as a Pod spec
    metadata:
      labels:
        app: my-app              # MUST match selector.matchLabels
    spec:
      containers:
        - name: web
          image: myapp:1.0.0
          ports:
            - containerPort: 8000
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: database-url
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 10
```

### Working with Deployments

```bash
# Apply:
kubectl apply -f deployment.yaml

# Check status:
kubectl get deployments -n production
kubectl rollout status deployment/my-app -n production

# Scale manually:
kubectl scale deployment/my-app --replicas=5 -n production

# Update image (trigger rolling update):
kubectl set image deployment/my-app web=myapp:2.0.0 -n production

# Watch pods update:
kubectl get pods -n production -w

# Check rollout history:
kubectl rollout history deployment/my-app -n production

# Rollback to previous version:
kubectl rollout undo deployment/my-app -n production

# Rollback to specific revision:
kubectl rollout undo deployment/my-app --to-revision=2 -n production

# Pause a rollout (e.g., to check if new version is healthy):
kubectl rollout pause deployment/my-app -n production
kubectl rollout resume deployment/my-app -n production
```

### Understanding the rolling update

With `replicas: 3`, `maxUnavailable: 1`, `maxSurge: 1`:

```
Initial state:
  Pod-v1 (running)  Pod-v1 (running)  Pod-v1 (running)

Step 1: Start a new pod:
  Pod-v1 (running)  Pod-v1 (running)  Pod-v1 (running)  Pod-v2 (starting)
  (4 pods = 3 desired + 1 surge)

Step 2: New pod is ready. Terminate one old pod:
  Pod-v1 (running)  Pod-v1 (terminating)  Pod-v1 (running)  Pod-v2 (running)
  (3 pods — within bounds)

Step 3: Repeat until all old pods replaced:
  Pod-v2 (running)  Pod-v2 (running)  Pod-v2 (running)

No downtime. At least 2 pods (3 - 1 maxUnavailable) serving traffic throughout.
```

---

## 8. Services — Networking Inside the Cluster

Pods come and go — they get new IP addresses when rescheduled. A **Service** is a stable IP address and DNS name that routes traffic to healthy pods.

```
ClusterIP Service (my-app)
  IP: 10.96.45.100    DNS: my-app.production.svc.cluster.local

Selects pods with label: app=my-app

Traffic to 10.96.45.100:80 → load-balanced to:
  Pod 1 (10.244.0.5:8000)
  Pod 2 (10.244.1.3:8000)
  Pod 3 (10.244.2.7:8000)
```

### Service types

**ClusterIP** (default): accessible only within the cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: production
spec:
  selector:
    app: my-app          # routes to pods with this label
  ports:
    - protocol: TCP
      port: 80           # service port (what clients use)
      targetPort: 8000   # container port (where app listens)
  type: ClusterIP        # default
```

**NodePort**: exposes service on a port on every node's IP.

```yaml
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8000
      nodePort: 30080    # port on every node (30000-32767)
      # Access: http://<node-ip>:30080
```

Use for: development clusters, on-premise without a cloud load balancer.

**LoadBalancer**: provisions a cloud load balancer (AWS ELB, GCP LB, Azure LB).

```yaml
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8000
```

Use for: exposing a service directly to the internet from a managed K8s cluster (EKS, GKE, AKS). Creates a real cloud load balancer with an external IP.

**ExternalName**: maps a service name to an external DNS name.

```yaml
spec:
  type: ExternalName
  externalName: my-database.us-east-1.rds.amazonaws.com
# Pods can reach the DB as: postgres://db-service:5432/mydb
# Actual traffic goes to: my-database.us-east-1.rds.amazonaws.com:5432
# Useful for referencing external services by an internal name
```

### Service DNS

Kubernetes has a built-in DNS server (CoreDNS). Every service gets a DNS entry:

```
service-name.namespace.svc.cluster.local

Examples:
  my-app.production.svc.cluster.local
  db.production.svc.cluster.local
  redis.production.svc.cluster.local

From within the same namespace, short names work:
  my-app         → my-app.production.svc.cluster.local
  db             → db.production.svc.cluster.local

From a different namespace:
  my-app.production   → my-app.production.svc.cluster.local
```

---

## 9. ConfigMaps and Secrets

### ConfigMap — non-sensitive configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
data:
  # Key-value pairs:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "10"

  # File content:
  config.yaml: |
    server:
      port: 8000
      timeout: 30s
    logging:
      level: info
      format: json
```

**Use ConfigMap in a Pod:**

```yaml
spec:
  containers:
    - name: web
      image: myapp:1.0
      # Option 1: load all keys as environment variables
      envFrom:
        - configMapRef:
            name: app-config

      # Option 2: load specific keys as environment variables
      env:
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL

      # Option 3: mount as files in a volume
      volumeMounts:
        - name: config-volume
          mountPath: /app/config
          readOnly: true

  volumes:
    - name: config-volume
      configMap:
        name: app-config
        # Mounts: /app/config/config.yaml with the file content above
```

### Secret — sensitive configuration

Secrets store sensitive data: passwords, API keys, certificates. They are base64-encoded (NOT encrypted by default — use encryption at rest in production).

```bash
# Create secret from literals (command line):
kubectl create secret generic app-secrets \
  --from-literal=database-url="postgres://user:pass@host:5432/db" \
  --from-literal=secret-key="supersecretkey" \
  -n production

# Create secret from a file (good for TLS certificates):
kubectl create secret generic tls-cert \
  --from-file=tls.crt=./cert.pem \
  --from-file=tls.key=./key.pem \
  -n production

# Create TLS secret (built-in type):
kubectl create secret tls my-tls \
  --cert=cert.pem \
  --key=key.pem \
  -n production
```

```yaml
# Or as YAML (values must be base64-encoded):
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: production
type: Opaque
data:
  database-url: cG9zdGdyZXM6Ly91c2VyOnBhc3NAaG9zdDo1NDMyL2Ri  # base64
  secret-key: c3VwZXJzZWNyZXRrZXk=  # base64

# Encode manually:
echo -n "mysecret" | base64
# Decode:
echo "bXlzZWNyZXQ=" | base64 -d
```

**Use Secret in a Pod:**

```yaml
spec:
  containers:
    - name: web
      env:
        # Single key:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-url

        # All keys as env vars:
      envFrom:
        - secretRef:
            name: app-secrets

      # Mounted as files (better — not visible in process list):
      volumeMounts:
        - name: secrets-volume
          mountPath: /app/secrets
          readOnly: true

  volumes:
    - name: secrets-volume
      secret:
        secretName: app-secrets
```

---

## 10. Practical: Deploy a FastAPI App to Kubernetes

Complete working example.

### Directory structure

```
k8s/
├── namespace.yaml
├── secrets.yaml       (gitignored — never commit)
├── configmap.yaml
├── deployment.yaml
├── service.yaml
└── ingress.yaml       (see kubernetes/02-workloads-and-services.md)
```

### namespace.yaml

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
```

### secrets.yaml (never commit to git)

```bash
# Create via kubectl (not YAML — keeps secret out of git):
kubectl create secret generic app-secrets \
  --from-literal=database-url="postgres://user:pass@db:5432/mydb" \
  --from-literal=secret-key="$(openssl rand -hex 32)" \
  -n production
```

### configmap.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
data:
  APP_ENV: production
  LOG_LEVEL: info
  PORT: "8000"
```

### deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: web
          image: ghcr.io/myorg/myapp:1.0.0
          ports:
            - containerPort: 8000
          envFrom:
            - configMapRef:
                name: app-config
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: database-url
            - name: SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: secret-key
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3
      imagePullSecrets:
        - name: registry-credentials    # if using private registry
```

### service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: production
spec:
  selector:
    app: my-app
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8000
  type: ClusterIP
```

### Deploy

```bash
# Apply all at once:
kubectl apply -f k8s/

# Check status:
kubectl get all -n production
kubectl rollout status deployment/my-app -n production

# Test (port-forward to your laptop):
kubectl port-forward service/my-app 8080:80 -n production
# Open http://localhost:8080
```

---

## 11. Quick Reference — kubectl Commands

```bash
# Context / cluster:
kubectl config get-contexts
kubectl config use-context CONTEXT
kubectl config set-context --current --namespace=NAMESPACE

# Get resources:
kubectl get pods
kubectl get pods -n NAMESPACE
kubectl get pods -A              # all namespaces
kubectl get pods -o wide         # with node IP and image
kubectl get pods -w              # watch
kubectl get all                  # pods, services, deployments, replicasets
kubectl get events -n NAMESPACE  # recent events (useful for debugging)

# Apply / delete:
kubectl apply -f file.yaml
kubectl apply -f directory/
kubectl delete -f file.yaml
kubectl delete pod POD_NAME
kubectl delete pod POD_NAME --grace-period=0 --force  # force kill

# Describe (events and details):
kubectl describe pod POD_NAME
kubectl describe deployment DEPLOY_NAME
kubectl describe service SERVICE_NAME

# Logs:
kubectl logs POD_NAME
kubectl logs POD_NAME -c CONTAINER   # multi-container pod
kubectl logs POD_NAME -f             # follow
kubectl logs POD_NAME --previous     # logs from crashed previous container

# Execute:
kubectl exec -it POD_NAME -- bash
kubectl exec -it POD_NAME -c CONTAINER -- bash  # specific container

# Port-forward:
kubectl port-forward pod/POD_NAME 8080:8000
kubectl port-forward service/SERVICE_NAME 8080:80

# Scale:
kubectl scale deployment/DEPLOY_NAME --replicas=5

# Rolling update:
kubectl set image deployment/DEPLOY_NAME CONTAINER=IMAGE:TAG
kubectl rollout status deployment/DEPLOY_NAME
kubectl rollout history deployment/DEPLOY_NAME
kubectl rollout undo deployment/DEPLOY_NAME
kubectl rollout pause deployment/DEPLOY_NAME
kubectl rollout resume deployment/DEPLOY_NAME

# Secrets and ConfigMaps:
kubectl get secrets
kubectl get configmaps
kubectl describe secret SECRET_NAME
kubectl create secret generic NAME --from-literal=KEY=VALUE

# Namespaces:
kubectl get namespaces
kubectl create namespace NAME
kubectl delete namespace NAME
```

---

*Next: Persistent storage, StatefulSets, HPA, probes in depth → `02-workloads-and-services.md`*
*Networking, Ingress, TLS → see `03-networking-and-ingress.md`*
*Production operations, RBAC, monitoring → see `04-production-and-operations.md`*
