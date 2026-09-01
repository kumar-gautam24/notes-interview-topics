# Docker Fundamentals — From Zero to Confident

Everything you need to understand containers, images, and Docker from scratch. Every concept is explained before any command is introduced. Use as a learning guide and keep as a reference.

---

## Table of Contents

1. [What Is Docker and Why It Exists](#1)
2. [Containers vs Virtual Machines](#2)
3. [Core Concepts: Image, Container, Layer, Registry](#3)
4. [Installing Docker](#4)
5. [Your First Container](#5)
6. [Working with Images](#6)
7. [Writing a Dockerfile](#7)
8. [Volumes — Persisting Data](#8)
9. [Networking — Connecting Containers](#9)
10. [Environment Variables and Configuration](#10)
11. [Essential Docker Commands — Full Reference](#11)
12. [Common Patterns and Pitfalls](#12)

---

## 1. What Is Docker and Why It Exists

**The problem Docker solves:**

```
Developer A builds an app on macOS with Python 3.11, postgres 15, redis 7.
Developer B runs it on Ubuntu with Python 3.9, postgres 14, redis 6.
Production runs on Amazon Linux with Python 3.10, postgres 15.

"Works on my machine" → breaks everywhere else.
```

Docker packages your application **and its entire environment** into a single unit called a **container**. The container runs identically on any machine that has Docker installed — your laptop, your colleague's laptop, CI, and production.

```
Without Docker:
  app code + "hope the environment matches" → ships

With Docker:
  app code + Python 3.11 + all dependencies + config → container → ships
  Container runs the same everywhere.
```

**What Docker is:**
- A tool for building, shipping, and running containers
- A standard format for packaging applications

**What Docker is not:**
- A virtual machine (it does not emulate hardware)
- A replacement for an operating system
- Magic — it's Linux kernel features (namespaces + cgroups) wrapped in a friendly CLI

---

## 2. Containers vs Virtual Machines

Both solve the "works on my machine" problem. They solve it differently.

### Virtual Machine (VM)

```
┌────────────────────────────────────────┐
│            Your Laptop                 │
│  ┌──────────────────────────────────┐  │
│  │         Hypervisor               │  │
│  │  ┌───────────┐  ┌───────────┐   │  │
│  │  │    VM 1   │  │    VM 2   │   │  │
│  │  │  Full OS  │  │  Full OS  │   │  │
│  │  │  (2 GB)   │  │  (2 GB)   │   │  │
│  │  │  App 1    │  │  App 2    │   │  │
│  │  └───────────┘  └───────────┘   │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

Each VM includes a full operating system kernel, libraries, and the application. Isolated but heavy.
- Startup time: 30–60 seconds
- Memory: 1–4 GB per VM
- Full OS = full isolation, but full overhead

### Container

```
┌────────────────────────────────────────┐
│            Your Laptop                 │
│  ┌──────────────────────────────────┐  │
│  │      Host OS Kernel              │  │
│  │  ┌──────────┐  ┌──────────┐     │  │
│  │  │Container1│  │Container2│     │  │
│  │  │Libraries │  │Libraries │     │  │
│  │  │  App 1   │  │  App 2   │     │  │
│  │  └──────────┘  └──────────┘     │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

Containers share the host OS kernel. Each container has its own isolated filesystem and process space.
- Startup time: milliseconds
- Memory: 10–100 MB per container
- Shares kernel = lightweight, but slightly less isolated than VMs

### When to use which

| | Container | VM |
|--|-----------|-----|
| Startup | Milliseconds | Seconds–minutes |
| Overhead | Low (~50 MB) | High (1–4 GB) |
| Isolation | Process-level | Full OS |
| Use for | Apps, services, CI | Different OS, legacy, max isolation |

In practice: containers for your applications, VMs for the infrastructure (the machines containers run on).

---

## 3. Core Concepts: Image, Container, Layer, Registry

### Image

An image is a **read-only template** that describes what a container should look like: which OS, which software, which files, what command to run.

Think of an image as a recipe or a class definition. It is not running — it is a blueprint.

```
Image "python:3.11-slim":
  - Ubuntu 22.04 base
  - Python 3.11 installed
  - pip installed
  - Entry point: python
```

### Container

A container is a **running instance of an image**. One image can run as many containers as you want, simultaneously.

Think of a container as an object instantiated from a class.

```
Image (class)  →  Container 1 (running instance)
               →  Container 2 (another instance, same image)
               →  Container 3 (third instance)
```

### Layer

Docker images are built in **layers**. Each instruction in a Dockerfile creates one layer.

```
Dockerfile:
  FROM ubuntu:22.04        ← Layer 1: base OS (100 MB)
  RUN apt-get install ...  ← Layer 2: installed packages (+50 MB)
  COPY . /app              ← Layer 3: your application code (+10 MB)
  CMD ["python", "app.py"] ← Layer 4: metadata (0 MB)

Total image size: 160 MB
```

Layers are cached and shared:
- If Layer 1 and 2 are unchanged, Docker reuses the cache. Only layers that changed are rebuilt.
- Multiple images can share the same base layers. If two images both start from `ubuntu:22.04`, that layer is stored once on disk.

```
Image A: [ubuntu] [python] [app_code_v1]
Image B: [ubuntu] [python] [app_code_v2]
                 ↑────────────────────┘
                 Layers 1 and 2 are shared. Not duplicated.
```

### Registry

A registry is a storage and distribution system for Docker images. The default is **Docker Hub** (hub.docker.com).

```
Push image:  docker push myname/myapp:1.0   → stores image on Docker Hub
Pull image:  docker pull myname/myapp:1.0   → downloads image from Docker Hub
Run image:   docker run myname/myapp:1.0    → downloads if not local, then runs

Other registries:
  AWS ECR    (private, for AWS deployments)
  GCP GAR    (Google Artifact Registry)
  GitHub GHCR (GitHub Container Registry — free for public repos)
  Self-hosted (with `registry` Docker image)
```

---

## 4. Installing Docker

### macOS / Windows

Install Docker Desktop: https://www.docker.com/products/docker-desktop

Docker Desktop includes the Docker CLI, Docker Engine, and Docker Compose. It creates a lightweight Linux VM under the hood (required because containers need the Linux kernel).

### Linux (Ubuntu/Debian)

```bash
# Install Docker Engine:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Run Docker without sudo (log out and back in after):
sudo usermod -aG docker $USER

# Verify:
docker --version
docker run hello-world
```

---

## 5. Your First Container

```bash
# Run a container from the official nginx image:
docker run nginx

# What happens:
# 1. Docker looks for "nginx" image locally → not found
# 2. Docker pulls "nginx" from Docker Hub
# 3. Docker starts a container from the image
# 4. nginx starts serving on port 80 inside the container
# (you can't reach it yet — port is not exposed to host)

# Ctrl+C to stop. The container is stopped but still exists.

# Run detached (background), expose port, and give it a name:
docker run -d --name my-nginx -p 8080:80 nginx
#           ↑                  ↑          ↑
#       background          host:container  image
#
# -p 8080:80 maps host port 8080 → container port 80
# Open http://localhost:8080 → you see the nginx welcome page

# View running containers:
docker ps

# View all containers (including stopped):
docker ps -a

# View logs:
docker logs my-nginx
docker logs -f my-nginx   # follow (live tail)

# Execute a command inside a running container:
docker exec -it my-nginx bash
# -i = interactive (keep stdin open)
# -t = allocate a pseudo-TTY (for interactive shell)
# Now you are inside the container. Type 'exit' to leave.

# Stop the container:
docker stop my-nginx

# Start it again:
docker start my-nginx

# Remove a stopped container:
docker rm my-nginx

# Stop and remove in one command:
docker rm -f my-nginx
```

---

## 6. Working with Images

```bash
# List local images:
docker images
# or:
docker image ls

# Pull an image without running it:
docker pull python:3.11-slim

# Image tags:
# python:3.11-slim   ← specific version + variant (recommended for production)
# python:3.11        ← full image, larger
# python:latest      ← whatever is newest — AVOID in production (unpredictable)
# python             ← same as python:latest

# Search Docker Hub:
docker search postgres

# Remove an image:
docker rmi nginx
docker image rm nginx

# Remove all unused images (not referenced by any container):
docker image prune

# Remove all images, including used ones:
docker image prune -a

# Build an image from a Dockerfile in the current directory:
docker build -t myapp:1.0 .
# -t = tag: name:version
# .  = build context (the directory Docker reads files from)

# Build with a different Dockerfile name:
docker build -f Dockerfile.prod -t myapp:prod .

# View image layers (history):
docker image history myapp:1.0

# Inspect image metadata:
docker inspect myapp:1.0

# Push to Docker Hub (must be logged in):
docker login
docker push myusername/myapp:1.0

# Copy image between registries:
docker tag myapp:1.0 myusername/myapp:1.0
docker push myusername/myapp:1.0
```

---

## 7. Writing a Dockerfile

A Dockerfile is a text file of instructions that Docker reads to build an image.

### Complete Dockerfile for a Python/FastAPI app

```dockerfile
# ─── Stage 1: base image ───────────────────────────────────────────
# Always pin to a specific version tag. Never use 'latest' in Dockerfile.
# 'slim' = stripped-down Debian image (smaller than full, larger than alpine)
FROM python:3.11-slim AS base

# Set working directory inside the container.
# All subsequent commands run relative to this path.
WORKDIR /app

# ─── Stage 2: install dependencies ─────────────────────────────────
# Copy only requirements.txt first (before copying the rest of the code).
# Why: Docker caches layers. If only your code changes (not requirements),
#      Docker reuses the cached layer where pip install ran — much faster builds.
COPY requirements.txt .

# Install dependencies.
# --no-cache-dir: don't store pip's cache inside the image (saves space)
# --upgrade pip: always use latest pip (optional but good practice)
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ─── Stage 3: copy application code ────────────────────────────────
# Copy everything else after dependencies are installed.
# This layer is rebuilt every time code changes — that's fine, it's fast.
COPY . .

# ─── Metadata ───────────────────────────────────────────────────────
# Declare which port the app listens on. Documentation only — does not publish.
EXPOSE 8000

# Environment variables with sensible defaults.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# CMD is the default command when the container starts.
# Use JSON array form (exec form) — avoids shell signal handling issues.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Dockerfile instructions explained

```dockerfile
FROM image:tag
  # Base image to start from. Every Dockerfile starts with FROM.
  # FROM scratch — start from nothing (for static binaries like Go)

WORKDIR /path
  # Set working directory. Creates directory if it doesn't exist.
  # Like 'cd /path && mkdir -p /path' combined.

COPY src dest
  # Copy files from build context (your machine) into the image.
  # COPY requirements.txt .   → copies requirements.txt to /app/requirements.txt
  # COPY . .                  → copies everything to /app/
  # .dockerignore controls what is excluded (like .gitignore)

RUN command
  # Executes a shell command during the build. Creates a new layer.
  # Chain commands with && to minimize layers:
  RUN apt-get update && \
      apt-get install -y curl git && \
      rm -rf /var/lib/apt/lists/*   ← always clean up apt cache in the same RUN

ADD src dest
  # Like COPY but also handles URLs and auto-extracts tar archives.
  # Prefer COPY for simple file copies — it's more predictable.

ENV KEY=VALUE
  # Set environment variables. Available at both build and runtime.
  ENV PORT=8000 DEBUG=false

ARG NAME=default
  # Build-time variable. Not available in running container.
  # docker build --build-arg API_KEY=abc123 .
  ARG API_KEY
  RUN echo "Using key: $API_KEY"    # available during build

EXPOSE port
  # Documents which port the container uses. Does not actually publish.
  # Publishing happens with -p flag in docker run.

CMD ["executable", "arg1", "arg2"]
  # Default command when container starts. Can be overridden by docker run.
  # JSON array form (exec form): signals go directly to process — PREFERRED
  # Shell form: CMD command arg1 — runs in /bin/sh -c, signals don't reach app

ENTRYPOINT ["executable"]
  # Like CMD but not easily overridden. docker run args are appended.
  # Common: ENTRYPOINT ["python"] CMD ["app.py"]
  # → docker run myimage         runs: python app.py
  # → docker run myimage test.py runs: python test.py

USER username
  # Run as a non-root user. Security best practice.
  RUN adduser --disabled-password --gecos '' appuser
  USER appuser

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1
  # Docker checks this periodically. Container marked unhealthy if it fails.

VOLUME ["/data"]
  # Declares a mount point. Data written here persists outside the container.
  # Better practice: declare volumes in docker-compose.yml or docker run.
```

### .dockerignore — exclude files from the build context

Create `.dockerignore` in the same directory as your Dockerfile:

```
# Version control
.git
.gitignore

# Python artifacts
__pycache__
*.pyc
*.pyo
*.egg-info
dist/
build/
.eggs/
venv/
.venv/
env/

# Test and dev files
tests/
.pytest_cache/
.coverage
htmlcov/
.tox/

# IDE and OS files
.idea/
.vscode/
*.swp
.DS_Store
Thumbs.db

# Docker files
Dockerfile*
docker-compose*

# Secrets — NEVER send to build context
.env
*.key
*.pem
secrets/
```

If you don't have a `.dockerignore`, Docker sends your entire directory (including `.git`, `node_modules`, `venv`) as the build context. This can be hundreds of MB for every build. Always use `.dockerignore`.

---

## 8. Volumes — Persisting Data

Containers are ephemeral: when a container is removed, its filesystem is gone. Volumes solve this.

### Three types of storage

**Volume (managed by Docker):**

```bash
# Create a named volume:
docker volume create mydata

# Run a container with the volume:
docker run -v mydata:/app/data postgres:15

# Data in /app/data inside the container is stored in the Docker volume.
# Container can be deleted and recreated — volume persists.

# Inspect where Docker stores the volume on disk:
docker volume inspect mydata
# → /var/lib/docker/volumes/mydata/_data  (on Linux)

# List volumes:
docker volume ls

# Remove a volume:
docker volume rm mydata

# Remove all unused volumes:
docker volume prune
```

**Bind mount (maps a host directory into the container):**

```bash
# Map /home/user/myapp (host) → /app (container):
docker run -v /home/user/myapp:/app myimage
# or (shorter syntax with current directory):
docker run -v $(pwd):/app myimage

# Changes on the host are immediately visible in the container.
# Changes in the container are immediately visible on the host.
# Perfect for development: edit code on host, container picks up changes.

# Read-only bind mount:
docker run -v $(pwd)/config:/app/config:ro myimage
```

**tmpfs mount (in-memory, not persisted):**

```bash
docker run --tmpfs /tmp myimage
# /tmp inside the container lives in RAM. Fast, but lost on restart.
# Good for: temporary files, caches, secrets you don't want on disk.
```

### When to use which

| Type | Use for |
|------|---------|
| Named volume | Database data, any production persistent data |
| Bind mount | Development (live code reload), config files |
| tmpfs | Temporary files, in-memory caches, secrets |

---

## 9. Networking — Connecting Containers

### Default networks

```bash
# List networks:
docker network ls
# NETWORK ID    NAME      DRIVER    SCOPE
# abc123        bridge    bridge    local  ← default for single containers
# def456        host      host      local
# ghi789        none      null      local
```

**bridge:** default network. Containers can reach each other by IP. Not by name (unless using custom bridge).

**host:** container shares the host's network stack directly. No isolation. Container's `localhost` = host's `localhost`. Highest performance, least isolation.

**none:** no network at all. Fully isolated.

### Custom bridge network — container DNS

```bash
# Create a custom network:
docker network create mynetwork

# Run containers on this network:
docker run -d --name db --network mynetwork postgres:15
docker run -d --name app --network mynetwork myapp

# Now 'app' can reach 'db' by name:
# Inside 'app' container: psql -h db -U postgres
# Docker's built-in DNS resolves 'db' to the db container's IP

# This is the correct way to connect containers.
# Default bridge network: containers can only reach each other by IP (which changes).
# Custom network: containers reach each other by container name. ✓
```

### Port publishing — reaching containers from outside

```bash
# -p host_port:container_port
docker run -p 8080:80 nginx
# Requests to localhost:8080 → forwarded to container port 80

# Bind to a specific interface:
docker run -p 127.0.0.1:8080:80 nginx
# Only reachable from localhost, not from the network

# Let Docker pick a random available host port:
docker run -p 80 nginx
docker port container_name   # see which port was assigned
```

---

## 10. Environment Variables and Configuration

### Passing env vars at runtime

```bash
# Single variable:
docker run -e DATABASE_URL=postgres://... myapp

# Multiple variables:
docker run \
  -e DATABASE_URL=postgres://... \
  -e REDIS_URL=redis://... \
  -e SECRET_KEY=abc123 \
  myapp

# From a file:
docker run --env-file .env myapp
```

### .env file format

```bash
# .env
DATABASE_URL=postgres://user:password@localhost:5432/mydb
REDIS_URL=redis://localhost:6379/0
SECRET_KEY=supersecretkey
DEBUG=false
PORT=8000
```

**Important:** Never add `.env` to version control. Add it to `.gitignore` and `.dockerignore`. It contains secrets.

### Accessing env vars in your application

```python
# Python:
import os
DATABASE_URL = os.environ["DATABASE_URL"]          # raises KeyError if missing
DATABASE_URL = os.getenv("DATABASE_URL", "default") # returns default if missing

# Pydantic Settings (FastAPI):
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    redis_url: str
    secret_key: str
    debug: bool = False
    port: int = 8000

settings = Settings()  # reads from environment automatically
```

---

## 11. Essential Docker Commands — Full Reference

### Container lifecycle

```bash
docker run [OPTIONS] IMAGE [COMMAND]
  -d                  Run in background (detached)
  --name NAME         Assign a name
  -p HOST:CONTAINER   Publish port
  -v SRC:DEST         Mount volume or bind
  -e KEY=VALUE        Set environment variable
  --env-file FILE     Load env vars from file
  --rm                Remove container when it stops
  --network NAME      Connect to network
  --restart POLICY    Restart policy: no, always, on-failure, unless-stopped
  -it                 Interactive terminal

docker start CONTAINER    # Start a stopped container
docker stop CONTAINER     # Graceful stop (SIGTERM, 10s timeout, then SIGKILL)
docker kill CONTAINER     # Force stop immediately (SIGKILL)
docker restart CONTAINER  # Stop + start
docker pause CONTAINER    # Pause all processes in container
docker unpause CONTAINER  # Resume

docker rm CONTAINER         # Remove stopped container
docker rm -f CONTAINER      # Force remove (even if running)
docker rm $(docker ps -aq)  # Remove all stopped containers
```

### Inspecting containers

```bash
docker ps                    # Running containers
docker ps -a                 # All containers (including stopped)
docker ps -q                 # Only IDs (for scripting)

docker logs CONTAINER        # View stdout/stderr
docker logs -f CONTAINER     # Follow (live tail)
docker logs --tail 100 CONTAINER  # Last 100 lines
docker logs --since 1h CONTAINER  # Last hour

docker exec -it CONTAINER bash     # Open shell in running container
docker exec CONTAINER cat /etc/os-release  # Run single command

docker inspect CONTAINER     # Full JSON metadata
docker stats                 # Live CPU/memory/network usage
docker top CONTAINER         # Running processes in container

docker cp CONTAINER:/path/file ./local  # Copy file from container
docker cp ./local CONTAINER:/path/      # Copy file to container
```

### Image commands

```bash
docker images               # List local images
docker image ls             # Same
docker pull IMAGE:TAG       # Download image
docker push IMAGE:TAG       # Upload image
docker rmi IMAGE            # Remove image
docker image prune          # Remove unused images
docker image prune -a       # Remove all images not used by containers
docker image history IMAGE  # Show layers
docker inspect IMAGE        # Full metadata
docker build -t NAME:TAG .  # Build from Dockerfile in current directory
docker build -t NAME:TAG -f Dockerfile.custom .  # Custom Dockerfile name
```

### System commands

```bash
docker system df            # Disk usage by Docker
docker system prune         # Remove all stopped containers, unused images, networks
docker system prune -a      # Also remove images not used by running containers
docker system prune --volumes  # Also remove volumes (CAREFUL: data loss)

docker version              # Client and server version
docker info                 # System-wide info (storage driver, etc.)
```

### Volume and network commands

```bash
docker volume ls
docker volume create NAME
docker volume inspect NAME
docker volume rm NAME
docker volume prune

docker network ls
docker network create NAME
docker network inspect NAME
docker network connect NETWORK CONTAINER
docker network disconnect NETWORK CONTAINER
docker network rm NAME
```

---

## 12. Common Patterns and Pitfalls

### Pattern: Run a one-off command in a container

```bash
# Run Python script without installing Python locally:
docker run --rm -v $(pwd):/app -w /app python:3.11 python script.py

# Run database migration:
docker run --rm --network mynetwork -e DATABASE_URL=... myapp python manage.py migrate

# Open an interactive Python shell:
docker run --rm -it python:3.11 python
```

### Pattern: Development with live reload

```bash
docker run -d \
  --name dev-app \
  -p 8000:8000 \
  -v $(pwd):/app \           # bind mount: code changes reflected immediately
  -e DEBUG=true \
  myapp \
  uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
#                                                   ↑ reload on code changes
```

### Pitfall: Running as root

By default, container processes run as root. If an attacker breaks out of the container, they have root on the host. Always create and switch to a non-root user:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# Create non-root user:
RUN adduser --disabled-password --gecos '' --uid 1000 appuser && \
    chown -R appuser:appuser /app

# Switch to non-root user:
USER appuser

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Pitfall: Large images

Large images take longer to build, push, pull, and start. They also have a larger attack surface.

```bash
# Check image size:
docker images

# Common size reducers:
# 1. Use slim or alpine base images:
python:3.11           → 1.01 GB
python:3.11-slim      → 125 MB    ← good balance
python:3.11-alpine    → 51 MB     ← smallest, but musl libc can cause issues

# 2. Clean up in the same RUN layer:
RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*   ← clean in the SAME RUN, not a separate step

# 3. Use multi-stage builds (see docker/03-docker-production.md)

# 4. .dockerignore to exclude dev files

# 5. Don't install dev dependencies in production:
RUN pip install --no-cache-dir -r requirements.txt  # not requirements-dev.txt
```

### Pitfall: Storing secrets in images

```dockerfile
# WRONG — secret is baked into the image layer, visible in history:
ENV API_KEY=supersecret
RUN curl -H "Authorization: $API_KEY" https://api.example.com

# CORRECT — pass secrets at runtime via environment:
# In Dockerfile: don't include the secret
# At runtime: docker run -e API_KEY=supersecret myimage
#          or: docker run --env-file .env myimage
```

### Pitfall: Not handling signals

When Docker stops a container, it sends SIGTERM to the process. If your app runs in a shell (CMD form) instead of directly (exec form), the shell gets SIGTERM but doesn't forward it to your app. Your app gets SIGKILL after the timeout.

```dockerfile
# WRONG — shell form: signals go to /bin/sh, not your app
CMD uvicorn app.main:app --host 0.0.0.0 --port 8000

# CORRECT — exec form: signals go directly to uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

*Next: Docker Compose for multi-container applications → `02-docker-compose.md`*
*Production: Multi-stage builds, security, CI/CD → `03-docker-production.md`*
