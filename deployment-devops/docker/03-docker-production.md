# Docker in Production — Multi-Stage Builds, Security, and CI/CD

Everything needed to ship Docker containers confidently in production. Covers image optimization, security hardening, multi-stage builds, health checks, and integration with CI/CD pipelines.

---

## Table of Contents

1. [Multi-Stage Builds — Small, Fast, Secure Images](#1)
2. [Image Optimization Techniques](#2)
3. [Security Hardening](#3)
4. [Health Checks and Graceful Shutdown](#4)
5. [Resource Limits](#5)
6. [Logging in Production](#6)
7. [CI/CD Integration](#7)
8. [Container Registry — Pushing and Pulling Images](#8)
9. [Production docker-compose.yml](#9)
10. [Debugging a Running Production Container](#10)
11. [Common Production Checklist](#11)

---

## 1. Multi-Stage Builds — Small, Fast, Secure Images

A multi-stage build uses multiple `FROM` instructions in one Dockerfile. Earlier stages build the app; the final stage contains only what is needed to run it.

### Why multi-stage

Without multi-stage builds:
```
Single-stage Python image:
  - Python runtime        (130 MB)
  - Build tools (gcc, make) (100 MB)
  - Dev dependencies       (50 MB)
  - Your app code          (5 MB)
  Total: ~285 MB

Problem:
  - Build tools and dev deps are in the image → attack surface
  - Larger image → slower push/pull/start
  - Developer tools available to anyone who gains container access
```

With multi-stage builds:
```
Final image:
  - Python runtime        (50 MB)
  - Only production deps   (20 MB)
  - Your app code          (5 MB)
  Total: ~75 MB — 73% smaller
```

### Python / FastAPI multi-stage example

```dockerfile
# ─────────────────────────────────────────────────────────────────────
# Stage 1: builder
# Install dependencies and compile anything that needs compiling.
# This stage is thrown away — it does NOT go into the final image.
# ─────────────────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build tools needed for some Python packages (e.g., psycopg2, cryptography):
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# Upgrade pip first (good practice):
RUN pip install --upgrade pip

# Install dependencies into a specific directory (we'll copy this to final image):
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ─────────────────────────────────────────────────────────────────────
# Stage 2: final (production image)
# Only runtime — no build tools, no gcc, no dev packages.
# ─────────────────────────────────────────────────────────────────────
FROM python:3.11-slim AS production

WORKDIR /app

# Copy installed packages from builder stage:
COPY --from=builder /install /usr/local

# Copy application code:
COPY . .

# Create non-root user:
RUN adduser --disabled-password --gecos '' --uid 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

# Health check (optional here; can also be in compose):
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

### Go / static binary multi-stage example

Go compiles to a static binary — you can use `scratch` (empty image) as the final stage:

```dockerfile
# Stage 1: compile
FROM golang:1.22-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app ./cmd/server

# Stage 2: final image — just the binary
FROM scratch AS production
# scratch = empty image. Smallest possible. No shell, no OS.

COPY --from=builder /app /app
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 8080
ENTRYPOINT ["/app"]

# Final image size: ~10 MB (just the binary + TLS certs)
```

### Node.js multi-stage example

```dockerfile
# Stage 1: install and build
FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production   # only prod deps
COPY . .
RUN npm run build              # compile TypeScript, bundle, etc.


# Stage 2: production image
FROM node:20-alpine AS production

WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package.json .

USER appuser

EXPOSE 3000
CMD ["node", "dist/server.js"]
```

### Building specific stages

```bash
# Build only the production stage:
docker build --target production -t myapp:latest .

# Build only the builder stage (for debugging):
docker build --target builder -t myapp:debug .

# Build with a build argument:
docker build --build-arg ENV=production -t myapp:prod .
```

---

## 2. Image Optimization Techniques

### 1. Pin base image versions

```dockerfile
# BAD: unpredictable, breaks on new release
FROM python:latest
FROM python:3.11

# GOOD: pinned to digest — byte-for-byte identical forever
FROM python:3.11-slim
# Even better — pin to digest:
FROM python:3.11-slim@sha256:abc123...
```

### 2. Order layers by change frequency

Docker caches layers. Put rarely-changing layers first, frequently-changing last.

```dockerfile
FROM python:3.11-slim

# Rarely changes → runs from cache:
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Changes when requirements.txt changes (not on every code edit):
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Changes every time you edit code → always rebuilds, but only this layer:
COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

If you COPY . . before pip install, every code change invalidates the pip cache layer → pip install runs on every build.

### 3. Minimize layers

```dockerfile
# BAD: 3 layers
RUN apt-get update
RUN apt-get install -y git curl
RUN rm -rf /var/lib/apt/lists/*

# GOOD: 1 layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends git curl && \
    rm -rf /var/lib/apt/lists/*

# --no-install-recommends: don't install optional suggested packages (saves space)
```

### 4. Use slim or alpine base images

| Base | Size |
|------|------|
| `python:3.11` | 1.01 GB |
| `python:3.11-slim` | 125 MB |
| `python:3.11-alpine` | 51 MB |

`slim`: stripped Debian. Good compatibility. Recommended for most Python apps.
`alpine`: musl libc instead of glibc. Smallest. Some packages have compatibility issues (cryptography, numpy). Test carefully.

### 5. Check your .dockerignore

```bash
# See what would be sent as build context:
docker build --dry-run . 2>&1 | head -50

# Or: check size before and after .dockerignore:
du -sh .
```

A good `.dockerignore` can reduce build context from 500 MB to 5 MB.

### 6. Analyze image size

```bash
# Show layer sizes:
docker image history myapp:latest

# Dive — interactive layer explorer (install separately):
# https://github.com/wagoodman/dive
dive myapp:latest

# Check total size:
docker images myapp:latest
```

---

## 3. Security Hardening

### Run as non-root

Root inside the container = root on the host if container is broken out of.

```dockerfile
# Create user during build:
RUN adduser --disabled-password --gecos '' --uid 1000 appuser

# In Alpine:
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Switch to non-root:
USER appuser

# Ensure app can write to its directory:
RUN chown -R appuser:appuser /app
```

### Read-only filesystem

```bash
# Run with read-only root filesystem:
docker run --read-only \
  --tmpfs /tmp \              # allow writes to /tmp (in memory)
  --tmpfs /app/logs \         # allow writes to logs (in memory, or use volume)
  myapp

# In docker-compose.yml:
services:
  web:
    read_only: true
    tmpfs:
      - /tmp
      - /app/logs
```

### Drop capabilities

Docker containers run with a set of Linux capabilities. Drop everything you don't need:

```bash
docker run --cap-drop=ALL \
           --cap-add=NET_BIND_SERVICE \  # only if you need to bind to port < 1024
           myapp

# In docker-compose.yml:
services:
  web:
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
```

Most applications need zero capabilities. Drop all.

### No new privileges

```bash
docker run --security-opt no-new-privileges myapp

# In docker-compose.yml:
services:
  web:
    security_opt:
      - no-new-privileges:true
```

Prevents privilege escalation via setuid/setgid binaries.

### Scan images for vulnerabilities

```bash
# Docker Scout (built into Docker Desktop):
docker scout cves myapp:latest
docker scout recommendations myapp:latest

# Trivy (open source, very thorough):
# Install: https://aquasecurity.github.io/trivy
trivy image myapp:latest

# Snyk (cloud-based):
snyk container test myapp:latest
```

Scan images as part of your CI pipeline. Block builds that introduce critical vulnerabilities.

### Secrets management — never bake into image

```bash
# WRONG: secrets in environment (visible in docker inspect, process list)
docker run -e DATABASE_PASSWORD=mysecret myapp

# BETTER: Docker secrets (Swarm mode) or orchestrator secrets
# In Kubernetes: use Kubernetes Secrets (mounted as files)
# In Docker Compose (dev): use --env-file pointing to gitignored .env

# At runtime in production: use a secrets manager:
#   AWS Secrets Manager
#   HashiCorp Vault
#   GCP Secret Manager
# App fetches secret at startup, not via environment
```

---

## 4. Health Checks and Graceful Shutdown

### Implementing a health endpoint in FastAPI

```python
from fastapi import FastAPI
from asyncpg import Pool

app = FastAPI()

@app.get("/health")
async def health_check(db: Pool = Depends(get_db)):
    try:
        await db.fetchval("SELECT 1")
        return {"status": "healthy", "db": "ok"}
    except Exception as e:
        raise HTTPException(status_code=503, detail={"status": "unhealthy", "error": str(e)})
```

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=40s \
    CMD curl -f http://localhost:8000/health || exit 1
```

### Graceful shutdown

When Docker sends SIGTERM, your app should:
1. Stop accepting new requests
2. Finish processing in-flight requests
3. Close database connections
4. Exit cleanly

```python
import signal
import asyncio
from fastapi import FastAPI

app = FastAPI()

@app.on_event("shutdown")
async def shutdown():
    # Close DB pool, Redis connections, etc.
    await db_pool.close()
    await redis.close()
```

Uvicorn handles SIGTERM gracefully. It stops accepting new requests and finishes in-flight ones. Give it enough time via Docker's stop timeout:

```bash
docker stop --time=30 myapp   # 30 seconds before SIGKILL (default is 10)

# In docker-compose.yml:
services:
  web:
    stop_grace_period: 30s
```

---

## 5. Resource Limits

Containers without limits can consume all CPU and RAM on the host, starving other services.

```yaml
# docker-compose.yml
services:
  web:
    deploy:
      resources:
        limits:
          cpus: "1.0"       # max 1 CPU core
          memory: 512M      # max 512 MB RAM
        reservations:
          cpus: "0.5"       # guaranteed 0.5 CPU core
          memory: 256M      # guaranteed 256 MB RAM
```

```bash
# docker run with resource limits:
docker run \
  --cpus="1.0" \
  --memory="512m" \
  --memory-swap="512m" \    # = memory (disables swap)
  myapp

# View real-time resource usage:
docker stats

# View usage for one container:
docker stats myapp-web
```

### Choosing limits

```
Rule of thumb:
  - Measure actual usage with docker stats under load
  - Set limit at 2× observed peak (headroom for spikes)
  - Set reservation at expected average usage

Memory limit too low → OOM killed → container restarts unexpectedly
CPU limit too low → app slows down under load (throttled, not killed)
```

---

## 6. Logging in Production

### Structured logging

```python
import structlog
import logging

structlog.configure(
    processors=[
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),   # output as JSON
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    logger_factory=structlog.PrintLoggerFactory(),
)

log = structlog.get_logger()
log.info("request.completed", method="GET", path="/users", status=200, duration_ms=12)
# → {"event": "request.completed", "method": "GET", "path": "/users", "status": 200, "duration_ms": 12, "timestamp": "..."}
```

### Log drivers

Docker collects container stdout/stderr. By default: `json-file` driver.

```yaml
# docker-compose.yml
services:
  web:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"     # rotate at 10 MB
        max-file: "5"       # keep 5 rotated files

    # Other drivers:
    # driver: "syslog"           → send to system syslog
    # driver: "fluentd"          → send to Fluentd (Kubernetes-style)
    # driver: "awslogs"          → send to AWS CloudWatch
    # driver: "gcplogs"          → send to Google Cloud Logging
    # driver: "splunk"           → send to Splunk
```

### Centralized logging architecture

```
Container stdout/stderr
         │
    Log driver (fluentd/filebeat)
         │
    Log aggregator (Elasticsearch / Loki)
         │
    Dashboard (Kibana / Grafana)
```

---

## 7. CI/CD Integration

### GitHub Actions — build, test, push

```yaml
# .github/workflows/docker.yml
name: Build and Push Docker Image

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}    # e.g., myuser/myapp

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
        # Buildx: supports multi-platform builds, caching, advanced features

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch           # branch name
            type=ref,event=pr               # pr-123
            type=semver,pattern={{version}} # v1.2.3
            type=sha,prefix=sha-            # sha-abc1234

      - name: Run tests
        run: |
          docker compose -f docker-compose.test.yml run --rm test

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          target: production               # multi-stage: build to 'production' stage
          push: ${{ github.event_name != 'pull_request' }}   # don't push on PRs
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha             # GitHub Actions cache
          cache-to: type=gha,mode=max

      - name: Scan for vulnerabilities
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:main
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'    # fail the build if CRITICAL or HIGH found
```

### Tagging strategy

```bash
# Semantic versioning — for releases:
myapp:1.0.0          # exact version
myapp:1.0            # minor (points to latest 1.0.x)
myapp:1              # major (points to latest 1.x.x)
myapp:latest         # latest stable

# Git SHA — for traceability:
myapp:sha-a1b2c3d    # exact commit

# Branch — for staging:
myapp:main           # latest main branch build
myapp:develop        # latest develop branch build
```

---

## 8. Container Registry — Pushing and Pulling Images

### Docker Hub (default public registry)

```bash
# Login:
docker login

# Tag image:
docker tag myapp:latest myusername/myapp:1.0.0

# Push:
docker push myusername/myapp:1.0.0

# Pull:
docker pull myusername/myapp:1.0.0
```

### GitHub Container Registry (GHCR)

```bash
# Login with personal access token:
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Tag:
docker tag myapp:latest ghcr.io/myusername/myapp:1.0.0

# Push:
docker push ghcr.io/myusername/myapp:1.0.0
```

### AWS ECR (Elastic Container Registry)

```bash
# Authenticate (requires AWS CLI configured):
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin \
    123456789.dkr.ecr.us-east-1.amazonaws.com

# Create repository (one-time):
aws ecr create-repository --repository-name myapp --region us-east-1

# Tag:
docker tag myapp:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:latest

# Push:
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:latest
```

---

## 9. Production docker-compose.yml

A complete production Compose file with security and reliability best practices:

```yaml
# docker-compose.prod.yml

services:
  web:
    image: ghcr.io/myorg/myapp:${IMAGE_TAG}
    container_name: myapp-web
    restart: unless-stopped
    ports:
      - "127.0.0.1:8000:8000"     # only accessible locally (Nginx in front)
    env_file: .env.prod
    environment:
      DATABASE_URL: postgres://myuser:${DB_PASSWORD}@db:5432/mydb
      REDIS_URL: redis://redis:6379/0
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    stop_grace_period: 30s
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1.0"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "5"
    networks:
      - backend

  db:
    image: postgres:15-alpine
    container_name: myapp-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: mydb
      # Performance tuning:
      POSTGRES_SHARED_BUFFERS: 256MB
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myuser -d mydb"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 1G
    networks:
      - backend

  redis:
    image: redis:7-alpine
    container_name: myapp-redis
    restart: unless-stopped
    command: >
      redis-server
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
      --save 60 1
      --requirepass ${REDIS_PASSWORD}
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - backend

  nginx:
    image: nginx:1.25-alpine
    container_name: myapp-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
    depends_on:
      - web
    networks:
      - backend

volumes:
  pgdata:
  redisdata:

networks:
  backend:
    driver: bridge
```

---

## 10. Debugging a Running Production Container

```bash
# View logs:
docker logs myapp-web --tail=100 -f

# Open shell in running container:
docker exec -it myapp-web /bin/sh     # if no bash (alpine)
docker exec -it myapp-web bash        # if bash available

# Check processes inside container:
docker top myapp-web

# Real-time resource usage:
docker stats myapp-web

# Inspect container state:
docker inspect myapp-web

# Check health status:
docker inspect --format='{{json .State.Health}}' myapp-web | python -m json.tool

# Copy a file out of the container for inspection:
docker cp myapp-web:/app/logs/error.log ./error.log

# Run a debug container alongside a running container (share its network):
docker run -it --rm \
  --network container:myapp-web \
  nicolaka/netshoot \
  curl http://localhost:8000/health
# netshoot is a debug image with curl, netstat, dig, tcpdump, etc.

# Check which ports the container is listening on:
docker exec myapp-web netstat -tlnp   # if netstat is available
docker exec myapp-web ss -tlnp        # modern alternative
```

---

## 11. Production Checklist

Before deploying to production, verify:

```
Image:
  □ Pinned base image tag (not 'latest')
  □ Multi-stage build (no build tools in final image)
  □ Non-root USER in Dockerfile
  □ .dockerignore excludes .git, venv, .env, tests
  □ Image scanned for vulnerabilities (trivy, Docker Scout)
  □ Image size reviewed (docker images, dive)

Runtime:
  □ Health check defined and endpoint implemented
  □ Resource limits set (memory, CPU)
  □ Restart policy set (unless-stopped)
  □ Graceful shutdown handled (stop_grace_period)
  □ Secrets passed via environment or secrets manager, NOT baked in
  □ read_only: true + tmpfs where possible
  □ no-new-privileges: true
  □ cap_drop: ALL

Networking:
  □ Database not exposed to host (no ports: on db service)
  □ App server bound to 127.0.0.1 (Nginx in front)
  □ Only necessary ports exposed externally

Logging:
  □ Structured JSON logging
  □ Log rotation configured (max-size, max-file)
  □ Logs shipped to central store (ELK, Loki, CloudWatch)

CI/CD:
  □ Images tagged with Git SHA for traceability
  □ Images pushed to private registry (not Docker Hub public)
  □ Vulnerability scan in CI pipeline (block on CRITICAL)
  □ Tests run against image (not just source code)

Data:
  □ Named volumes for persistent data (not bind mounts in production)
  □ Volume backup strategy in place
  □ Database not running in a container in production? (managed DB: RDS, Neon, CloudSQL)
```

---

*Previous: Docker Compose → `02-docker-compose.md`*
*For orchestrating containers at scale: see `kubernetes/` folder*
