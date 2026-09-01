# Kubernetes in Production — RBAC, Helm, Monitoring, and Operations

Running Kubernetes in production means more than deploying workloads. This doc covers security (RBAC), package management (Helm), observability, and operational patterns that every production cluster requires.

---

## Table of Contents

1. [RBAC — Role-Based Access Control](#1)
2. [Helm — Kubernetes Package Manager](#2)
3. [Monitoring — Prometheus and Grafana](#3)
4. [Logging — Loki and Fluent Bit](#4)
5. [Resource Quotas and LimitRanges](#5)
6. [Rolling Updates and Deployment Strategies](#6)
7. [Backup and Disaster Recovery](#7)
8. [Production Operations Checklist](#8)
9. [Common kubectl Debugging Commands](#9)

---

## 1. RBAC — Role-Based Access Control

RBAC controls who can do what in the cluster. Without it, every user and service account has unlimited access.

### Concepts

```
Subject (who):
  User      → a human (authenticated via cert, OIDC, etc.)
  Group     → a set of users
  ServiceAccount → an identity for pods (processes inside the cluster)

Resource (what):
  pods, deployments, services, secrets, nodes, namespaces, ...

Verb (action):
  get, list, watch, create, update, patch, delete

Role (namespace-scoped):
  A set of rules: "this role can get/list pods in namespace X"

ClusterRole (cluster-scoped):
  Same but applies across all namespaces or to cluster-level resources

RoleBinding:
  Grants a Role to a Subject within a namespace

ClusterRoleBinding:
  Grants a ClusterRole to a Subject across the entire cluster
```

### Creating a Role

```yaml
# A role that allows reading pods and logs in the 'production' namespace:
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
  - apiGroups: [""]                 # "" = core API group (pods, services, etc.)
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]

  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch"]
```

### Binding a Role to a User

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: gautam-pod-reader
  namespace: production
subjects:
  - kind: User
    name: gautam@example.com      # must match the identity from your auth provider
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### ClusterRole for cross-namespace access

```yaml
# Allow reading pods across ALL namespaces:
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: global-pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["nodes"]          # cluster-level resource
    verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ops-team-readers
subjects:
  - kind: Group
    name: ops-team                # all users in the 'ops-team' group
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: global-pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### ServiceAccount RBAC — for pods

Pods use a ServiceAccount to make Kubernetes API calls (e.g., a CI runner listing pods, or an operator creating resources).

```yaml
# 1. Create ServiceAccount:
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: production

---
# 2. Create Role:
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: my-app-role
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]    # app can read ConfigMaps (e.g., for dynamic config)

---
# 3. Bind Role to ServiceAccount:
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-role-binding
  namespace: production
subjects:
  - kind: ServiceAccount
    name: my-app-sa
    namespace: production
roleRef:
  kind: Role
  name: my-app-role
  apiGroup: rbac.authorization.k8s.io

---
# 4. Use ServiceAccount in Deployment:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
spec:
  template:
    spec:
      serviceAccountName: my-app-sa    # use this identity
      automountServiceAccountToken: true  # mount token into pod (default: true)
      containers:
        - name: web
          image: myapp:1.0
```

### Checking permissions

```bash
# Can I do X?
kubectl auth can-i get pods -n production
kubectl auth can-i delete secrets -n production

# Can user 'gautam' do X?
kubectl auth can-i get pods -n production --as=gautam@example.com

# List what a ServiceAccount can do:
kubectl auth can-i --list -n production --as=system:serviceaccount:production:my-app-sa

# Get all roles in a namespace:
kubectl get roles -n production
kubectl get rolebindings -n production
kubectl describe rolebinding my-app-role-binding -n production
```

---

## 2. Helm — Kubernetes Package Manager

Helm is a package manager for Kubernetes. A **chart** is a package of Kubernetes YAML templates. Helm renders the templates with your values and applies them to the cluster.

```
Without Helm: manage 10+ YAML files manually, hand-edit values for each environment.
With Helm:    one chart, one `values.yaml` per environment, one command to deploy.
```

### Install Helm

```bash
# macOS:
brew install helm

# Linux:
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify:
helm version
```

### Using a public Helm chart

Install NGINX Ingress Controller via Helm:

```bash
# Add the chart repository:
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Search for available charts:
helm search repo ingress-nginx

# Install (deploys to cluster):
helm install my-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.service.type=LoadBalancer

# Install with values file:
helm install my-nginx ingress-nginx/ingress-nginx \
  -f nginx-values.yaml \
  --namespace ingress-nginx \
  --create-namespace

# Check status:
helm list -n ingress-nginx
helm status my-nginx -n ingress-nginx

# Upgrade:
helm upgrade my-nginx ingress-nginx/ingress-nginx -f nginx-values.yaml -n ingress-nginx

# Rollback to previous release:
helm rollback my-nginx 1 -n ingress-nginx

# Uninstall:
helm uninstall my-nginx -n ingress-nginx
```

### Chart structure

```
mychart/
├── Chart.yaml             # chart metadata (name, version, description)
├── values.yaml            # default values
├── values-staging.yaml    # staging overrides
├── values-prod.yaml       # production overrides
├── templates/             # YAML templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── _helpers.tpl       # template helper functions
│   └── NOTES.txt         # shown after install
└── charts/                # sub-charts (dependencies)
```

### Chart.yaml

```yaml
apiVersion: v2
name: my-app
description: My FastAPI application
type: application
version: 0.1.0           # chart version
appVersion: "1.0.0"      # app version (your Docker image tag)
```

### values.yaml — default values

```yaml
replicaCount: 2

image:
  repository: ghcr.io/myorg/myapp
  pullPolicy: IfNotPresent
  tag: ""                     # defaults to Chart.appVersion if empty

service:
  type: ClusterIP
  port: 80
  targetPort: 8000

ingress:
  enabled: true
  className: nginx
  host: example.com
  tls: true

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

env:
  APP_ENV: production
  LOG_LEVEL: info

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### Deployment template

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          env:
            {{- range $key, $val := .Values.env }}
            - name: {{ $key }}
              value: {{ $val | quote }}
            {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

### Deploying with Helm

```bash
# Create a new chart scaffold:
helm create my-app

# Install from local chart:
helm install my-app ./my-app -n production --create-namespace

# Install with production values:
helm install my-app ./my-app \
  -f ./my-app/values.yaml \
  -f ./my-app/values-prod.yaml \
  --set image.tag=1.2.3 \
  -n production

# Upgrade when chart or values change:
helm upgrade my-app ./my-app \
  -f ./my-app/values-prod.yaml \
  --set image.tag=1.2.4 \
  -n production

# Upgrade and install if not already installed (idempotent):
helm upgrade --install my-app ./my-app \
  -f values-prod.yaml \
  --set image.tag=1.2.4 \
  -n production \
  --create-namespace

# Preview what will be applied (without applying):
helm template my-app ./my-app -f values-prod.yaml

# Debug template rendering:
helm install my-app ./my-app --dry-run --debug -f values-prod.yaml

# List installed releases:
helm list -n production
helm list -A   # all namespaces

# View release history:
helm history my-app -n production

# Get values of current release:
helm get values my-app -n production
```

---

## 3. Monitoring — Prometheus and Grafana

The standard monitoring stack for Kubernetes.

```
Pods expose /metrics endpoint (Prometheus format)
       ↓
Prometheus scrapes /metrics every 15 seconds
       ↓
Grafana visualizes data → dashboards and alerts
       ↓
AlertManager sends notifications (PagerDuty, Slack, email)
```

### Install kube-prometheus-stack (the easy way)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin \
  --set prometheus.prometheusSpec.retention=7d

# What this installs:
#   Prometheus server
#   Grafana (with pre-built dashboards)
#   AlertManager
#   kube-state-metrics (cluster-level metrics)
#   node-exporter (node-level metrics)
#   Prometheus operator (manages Prometheus config via CRDs)

# Access Grafana:
kubectl port-forward -n monitoring service/prometheus-grafana 3000:80
# Open: http://localhost:3000  (admin / admin)
```

### Exposing metrics from your app

```python
# FastAPI with Prometheus metrics:
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from fastapi import FastAPI, Response
import time

app = FastAPI()

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration",
    ["method", "endpoint"]
)

ACTIVE_REQUESTS = Gauge(
    "http_active_requests",
    "Active HTTP requests"
)

@app.middleware("http")
async def metrics_middleware(request, call_next):
    ACTIVE_REQUESTS.inc()
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    ACTIVE_REQUESTS.dec()
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    REQUEST_DURATION.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)
    return response

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

### ServiceMonitor — tell Prometheus to scrape your app

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: production
  labels:
    release: prometheus    # must match Prometheus's serviceMonitorSelector
spec:
  selector:
    matchLabels:
      app: my-app          # select services with this label
  endpoints:
    - port: http           # port name on the Service
      path: /metrics
      interval: 15s        # scrape every 15 seconds
```

### PrometheusRule — define alerts

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-app-alerts
  namespace: production
  labels:
    release: prometheus
spec:
  groups:
    - name: my-app.rules
      rules:
        - alert: HighErrorRate
          expr: |
            rate(http_requests_total{status=~"5.."}[5m]) /
            rate(http_requests_total[5m]) > 0.01
          for: 5m                     # must be true for 5 minutes before firing
          labels:
            severity: critical
          annotations:
            summary: "High error rate on {{ $labels.instance }}"
            description: "Error rate is {{ $value | humanizePercentage }}"

        - alert: HighLatency
          expr: |
            histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "p99 latency above 2s"

        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total[15m]) > 0.1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ $labels.pod }} is crash-looping"
```

---

## 4. Logging — Loki and Fluent Bit

### Install Loki stack

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set fluent-bit.enabled=true \
  --set grafana.enabled=false    # use existing Grafana from kube-prometheus-stack
```

This installs:
- **Loki:** log aggregation and storage (like Prometheus but for logs)
- **Fluent Bit:** lightweight log collector (DaemonSet — one per node)

### Add Loki as data source in Grafana

```bash
kubectl port-forward -n monitoring service/prometheus-grafana 3000:80
# Go to: Configuration → Data Sources → Add data source → Loki
# URL: http://loki.monitoring.svc.cluster.local:3100
```

### Query logs in Grafana (LogQL)

```logql
# All logs from the 'my-app' pod:
{namespace="production", app="my-app"}

# Filter for errors:
{namespace="production", app="my-app"} |= "ERROR"

# Parse JSON logs and filter:
{namespace="production", app="my-app"} | json | level="error"

# Rate of error logs per minute:
rate({namespace="production", app="my-app"} |= "ERROR" [1m])
```

---

## 5. Resource Quotas and LimitRanges

### ResourceQuota — namespace-level limits

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    # Compute resources:
    requests.cpu: "10"           # total CPU requests across all pods
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"

    # Object counts:
    pods: "100"
    services: "20"
    persistentvolumeclaims: "10"
    secrets: "50"
    configmaps: "50"
```

```bash
kubectl describe resourcequota production-quota -n production
# Shows: hard limits + current usage
```

### LimitRange — per-pod defaults

```yaml
# If a pod doesn't specify resources, apply these defaults:
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
    - type: Container
      default:                  # applied if no limits specified
        cpu: "500m"
        memory: "256Mi"
      defaultRequest:           # applied if no requests specified
        cpu: "100m"
        memory: "128Mi"
      max:                      # no container can exceed this
        cpu: "2"
        memory: "2Gi"
      min:                      # no container can go below this
        cpu: "50m"
        memory: "64Mi"
```

With a LimitRange, pods without resource declarations still get sensible defaults. Prevents "BestEffort" pods in production.

---

## 6. Rolling Updates and Deployment Strategies

### Rolling Update (default)

Covered in `01-kubernetes-fundamentals.md`. New pods start before old pods stop. Zero downtime.

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0     # never remove old pod before new one is ready
    maxSurge: 1           # run 1 extra pod during update
```

### Recreate — stop old, start new

```yaml
strategy:
  type: Recreate
# Stops ALL old pods, then starts new ones.
# Results in downtime.
# Use for: apps that cannot run two versions simultaneously (e.g., DB schema changes).
```

### Blue-Green deployment

Run two identical environments. Switch traffic atomically.

```
Blue environment (v1): 3 pods with label version=blue
Green environment (v2): 3 pods with label version=green

Service selector: version=blue  → traffic goes to v1

Upgrade:
  1. Deploy v2 alongside v1 (version=green)
  2. Test v2 (port-forward, staging checks)
  3. Switch service selector: version=green → instant traffic switch
  4. Keep v1 running for quick rollback
  5. Delete v1 after confidence period
```

```yaml
# Service that switches between blue and green:
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: production
spec:
  selector:
    app: my-app
    version: blue     # change to 'green' to switch traffic

# Patch to switch:
kubectl patch service my-app -n production \
  -p '{"spec":{"selector":{"version":"green"}}}'
```

### Canary deployment

Route a percentage of traffic to the new version. See `03-networking-and-ingress.md` for Ingress-level canary.

```
10% → v2 (canary)
90% → v1 (stable)

Monitor error rate and latency on v2.
If healthy: increase to 25%, 50%, 100%.
If unhealthy: set canary weight to 0 (instant rollback).
```

---

## 7. Backup and Disaster Recovery

### etcd backup

etcd is the source of truth. If it's lost without backup, the cluster state is gone.

```bash
# Backup etcd (run on control plane node):
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup:
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-$(date +%Y%m%d).db

# For managed clusters (EKS, GKE, AKS): etcd is managed for you.
# Your responsibility: back up persistent volumes and application data.
```

### Velero — application backup

Velero backs up Kubernetes objects and persistent volume data.

```bash
# Install Velero (example: AWS S3 backend):
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket my-velero-backups \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1 \
  --secret-file ./credentials-velero

# Create a backup:
velero backup create production-backup \
  --include-namespaces production \
  --wait

# Schedule automatic daily backup:
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces production \
  --ttl 168h     # keep for 7 days

# Restore from backup:
velero restore create --from-backup production-backup

# Check backup status:
velero backup describe production-backup
velero backup logs production-backup
```

---

## 8. Production Operations Checklist

```
Cluster setup:
  □ RBAC enabled (default in modern K8s)
  □ NetworkPolicies applied (deny-all + explicit allows)
  □ Resource quotas per namespace
  □ LimitRanges to enforce default resource declarations
  □ PodSecurityAdmission: restrict privileged containers

Workloads:
  □ All pods have readiness + liveness probes
  □ All containers have resource requests AND limits
  □ Deployments use RollingUpdate with sensible maxUnavailable/maxSurge
  □ PodDisruptionBudget defined for critical services
  □ Pod anti-affinity: spread replicas across nodes/zones
  □ No containers running as root
  □ No privileged containers

Secrets:
  □ No secrets in ConfigMaps or environment variables visible in YAML
  □ Secrets managed via sealed-secrets, Vault, or cloud secrets manager
  □ serviceAccountToken automount disabled where not needed:
      automountServiceAccountToken: false

Networking:
  □ Ingress with TLS (cert-manager + Let's Encrypt)
  □ Services not unnecessarily exposed (no NodePort in prod if avoidable)
  □ NetworkPolicies enforced

Observability:
  □ Prometheus + Grafana deployed
  □ Application exposes /metrics
  □ Alerts configured (error rate, latency, pod restarts, disk, memory)
  □ Centralized logging (Loki or ELK)
  □ Distributed tracing (Jaeger or AWS X-Ray)

Reliability:
  □ Multiple replicas for all critical services (never replicas: 1)
  □ HPA configured for services with variable load
  □ Cluster autoscaler configured (add/remove nodes automatically)
  □ Pod topology spread constraints for multi-zone deployments

Backup:
  □ etcd backed up regularly (managed clusters: provider handles this)
  □ Persistent volumes backed up (Velero or cloud snapshots)
  □ Disaster recovery runbook written and tested

CI/CD:
  □ Helm or GitOps (Argo CD, Flux) for deployments
  □ image tags pinned (not :latest)
  □ Kubernetes manifests in version control
  □ Deployment pipeline: test → staging → production
```

---

## 9. Common kubectl Debugging Commands

```bash
# ── Cluster health ─────────────────────────────────────────────────
kubectl get nodes                         # node status
kubectl describe node NODE_NAME           # node details, capacity, events
kubectl top nodes                         # CPU/memory usage per node

# ── Pod debugging ─────────────────────────────────────────────────
kubectl get pods -n production -o wide    # pods with node + IP
kubectl get events -n production          # recent events (errors, warnings)
kubectl get events -n production --sort-by='.lastTimestamp'  # sorted

kubectl describe pod POD_NAME -n production
# Look for:
#   Events section (at bottom) — shows what happened
#   Container state: Waiting → reason: CrashLoopBackOff, ImagePullBackOff, OOMKilled
#   Last State: why did previous container exit?

kubectl logs POD_NAME -n production --previous   # logs from crashed container

# ── What failed? ────────────────────────────────────────────────────
# CrashLoopBackOff → container keeps crashing
kubectl logs POD_NAME -n production               # check app error logs
kubectl describe pod POD_NAME -n production       # check exit code and reason

# ImagePullBackOff → can't pull the Docker image
kubectl describe pod POD_NAME -n production
# → Events: Failed to pull image: ... 401 Unauthorized → check imagePullSecrets
# → Events: Image not found → check image name and tag

# OOMKilled → container exceeded memory limit
kubectl describe pod POD_NAME -n production       # "OOMKilled" in Last State
# → Increase memory limit OR fix memory leak

# Pending → pod can't be scheduled
kubectl describe pod POD_NAME -n production
# → "Insufficient cpu" / "Insufficient memory" → nodes are full, scale cluster
# → "node(s) had taints that the pod didn't tolerate" → add tolerations

# ── Resource usage ─────────────────────────────────────────────────
kubectl top pods -n production                    # CPU/memory per pod
kubectl top pods -n production --sort-by=memory   # sort by memory usage

# ── Deployment rollout ─────────────────────────────────────────────
kubectl rollout status deployment/my-app -n production
kubectl rollout history deployment/my-app -n production
kubectl rollout undo deployment/my-app -n production   # rollback

# ── Service connectivity ────────────────────────────────────────────
kubectl get endpoints my-app -n production        # pods behind the service
kubectl port-forward service/my-app 8080:80 -n production  # test locally

# ── etcd (if running self-managed cluster) ─────────────────────────
kubectl get --raw /healthz                        # API server health
kubectl get --raw /readyz                         # API server readiness

# ── Useful oneliners ───────────────────────────────────────────────
# Get all pods that are NOT running:
kubectl get pods -A --field-selector='status.phase!=Running'

# Delete all completed Jobs:
kubectl delete job -n production $(kubectl get jobs -n production -o jsonpath='{.items[?(@.status.conditions[0].type=="Complete")].metadata.name}')

# Force delete a stuck pod:
kubectl delete pod POD_NAME -n production --grace-period=0 --force

# Copy file from pod to local:
kubectl cp production/my-pod:/app/logs/error.log ./error.log

# Execute command on all pods with a label:
for pod in $(kubectl get pods -l app=my-app -n production -o name); do
  echo "=== $pod ===" && kubectl exec $pod -n production -- cat /tmp/status
done

# Watch resource usage live:
watch -n 2 kubectl top pods -n production
```

---

*Previous: Networking, Ingress, TLS → `03-networking-and-ingress.md`*
*Start here: Fundamentals, Pods, Deployments → `01-kubernetes-fundamentals.md`*
