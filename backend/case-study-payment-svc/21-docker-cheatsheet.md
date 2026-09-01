# 21 — Docker Cheatsheet

> Mental model: a container is a process with its own filesystem, network, and
> process space. It's NOT a VM — it shares the host kernel. Think "fancy process
> isolation", not "tiny computer inside your computer".

---

## Part A — Core Concepts

### Image vs Container

| Concept | Analogy | What it is |
|---------|---------|-----------|
| **Image** | A recipe | Read-only template. Built from a Dockerfile. Stored in a registry. |
| **Container** | A dish cooked from the recipe | Running instance of an image. Has state. Can be started/stopped. |

You build images. You run containers. Many containers can run from the same image.

### Layers

Every instruction in a Dockerfile creates a **layer**. Layers are cached.

```dockerfile
FROM python:3.12-slim          # Layer 1: base OS + Python
COPY ./requirements.txt ...    # Layer 2: just the requirements file
RUN pip install -r ...         # Layer 3: installed packages
COPY ./app /code/app           # Layer 4: your code
```

If you change your code (Layer 4), layers 1-3 are cached — Docker skips them.
If you change requirements.txt, layers 3-4 rebuild. Order matters.

### Registry

A registry stores images. Like GitHub but for Docker images.

```
Docker Hub        → hub.docker.com (public, free)
Azure ACR         → <dev-registry>.azurecr.io (our dev registry)
AWS ECR           → xxxx.dkr.ecr.region.amazonaws.com
GitHub Packages   → ghcr.io
```

---

## Part B — Our Dockerfile (line by line)

```dockerfile
FROM python:3.12-slim
```
Start from Python 3.12 on Debian slim (minimal OS, ~50MB smaller than full Debian).

```dockerfile
RUN echo 'Building Docker Image for <AppName> API service'
```
Just a build-time log message. Not strictly necessary.

```dockerfile
WORKDIR /code
```
All subsequent commands run inside `/code`. Creates the directory if it doesn't exist.

```dockerfile
COPY ./requirements.txt /code/requirements.txt
```
Copy ONLY requirements.txt first. This is the **cache optimization trick** — if
requirements don't change, the pip install layer is cached.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev python3-dev ca-certificates gcc curl
```
Install system packages needed to compile Python packages (psycopg2 needs `libpq-dev`
and `gcc`).

```dockerfile
RUN pip3 install --upgrade pip
RUN pip3 install -r requirements.txt
```
Install Python dependencies. Separate from the COPY of app code for caching.

```dockerfile
COPY ./app /code/app
```
Now copy the actual application code. This layer changes on every code push.

```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80"]
```
Default command when the container starts. `0.0.0.0` means "listen on all interfaces"
(required in containers, `localhost` won't work from outside).

```dockerfile
EXPOSE 80
```
Documentation only — tells humans this container uses port 80. Doesn't actually
open the port (that's done with `docker run -p`).

---

## Part C — Build Commands

### Build an image

```bash
# Basic build
docker build -t <payment-svc> .

# With a specific tag
docker build -t <payment-svc>:v1.2.3 .

# With a specific Dockerfile
docker build -f Dockerfile.prod -t myapp:prod .
```

| Flag | What it does |
|------|-------------|
| `-t name:tag` | Name and tag the image |
| `-f` | Use a specific Dockerfile |
| `.` | Build context (directory to send to Docker) |
| `--no-cache` | Rebuild everything from scratch (ignore cache) |
| `--platform linux/amd64` | Cross-compile for a different architecture |

### Tag and push to a registry

```bash
# Tag for Azure ACR
docker tag <payment-svc>:latest <dev-registry>.azurecr.io/<payment-svc>:latest

# Push to ACR
docker push <dev-registry>.azurecr.io/<payment-svc>:latest

# Tag with a specific version (recommended)
docker tag <payment-svc>:latest <dev-registry>.azurecr.io/<payment-svc>:v1.2.3
docker push <dev-registry>.azurecr.io/<payment-svc>:v1.2.3
```

### The `:latest` tag trap

`:latest` doesn't mean "newest". It means "no tag specified". Common mistakes:

```bash
# You push v1 as :latest
docker push myapp:latest

# Two weeks later, you push v2 as :latest
docker push myapp:latest

# Kubernetes is still running :latest but it's the OLD version
# because it cached the image and imagePullPolicy wasn't set to Always
```

Fix: always tag with a version or git SHA:

```bash
docker tag myapp:latest myregistry/myapp:$(git rev-parse --short HEAD)
```

---

## Part D — Run Commands

### Running a container

```bash
# Basic run
docker run <payment-svc>

# With port mapping (host:container)
docker run -p 8080:80 <payment-svc>
# Now accessible at http://localhost:8080

# With environment variables
docker run -p 8080:80 -e ENVT=DEV -e DB_HOST=localhost <payment-svc>

# Detached mode (background)
docker run -d -p 8080:80 --name payment-svc <payment-svc>

# Interactive shell (for debugging)
docker run -it <payment-svc> /bin/bash
```

| Flag | What it does |
|------|-------------|
| `-p 8080:80` | Map host port 8080 to container port 80 |
| `-e KEY=VAL` | Set environment variable |
| `-d` | Run in background (detached) |
| `--name xyz` | Give the container a name (instead of random) |
| `-it` | Interactive terminal (for shell access) |
| `-v /host/path:/container/path` | Mount a volume |
| `--rm` | Auto-remove container when it stops |
| `--env-file .env` | Load env vars from a file |

### Stop and remove

```bash
docker stop payment-svc        # graceful shutdown (SIGTERM, then SIGKILL after 10s)
docker rm payment-svc           # remove the stopped container
docker stop payment-svc && docker rm payment-svc  # combined
```

---

## Part E — Container Management

### See what's running

```bash
# Running containers
docker ps

# All containers (including stopped)
docker ps -a

# Just IDs (useful for scripting)
docker ps -q
```

### Logs

```bash
# Show logs
docker logs payment-svc

# Follow logs in real-time (like tail -f)
docker logs -f payment-svc

# Last 100 lines
docker logs --tail 100 payment-svc

# Logs since a specific time
docker logs --since 2026-04-12T10:00:00 payment-svc
```

### Execute commands inside a running container

```bash
# Open a shell
docker exec -it payment-svc /bin/bash

# Run a one-off command
docker exec payment-svc python -c "from app.utils.config_utils import get_config; print(get_config('DB_HOST'))"

# Check what's listening on port 80
docker exec payment-svc ss -tlnp
```

### Inspect a container

```bash
# Full JSON details (network, mounts, env, state)
docker inspect payment-svc

# Just the IP address
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' payment-svc

# Just environment variables
docker inspect -f '{{.Config.Env}}' payment-svc
```

### Resource usage

```bash
# Live CPU/memory stats
docker stats

# One-time snapshot
docker stats --no-stream
```

---

## Part F — Image Management

```bash
# List local images
docker images

# Remove an image
docker rmi <payment-svc>:latest

# Remove all unused images (dangling)
docker image prune

# Remove ALL unused images (not just dangling)
docker image prune -a

# Pull an image from a registry
docker pull python:3.12-slim

# See image layers and sizes
docker history <payment-svc>:latest
```

### See how big your image is

```bash
docker images <payment-svc>
# REPOSITORY          TAG       IMAGE ID       SIZE
# <payment-svc>  latest    abc123         850MB
```

850MB is big. Slim it down with:
- `python:3.12-slim` instead of `python:3.12` (saves ~600MB)
- `.dockerignore` to exclude `docs/`, `.git/`, `__pycache__/`
- Multi-stage builds (compile in one stage, copy only binaries to a clean stage)

---

## Part G — Volumes and Networking

### Volumes (persistent data)

Containers are ephemeral — when you stop and remove a container, its data is gone.
Volumes persist data:

```bash
# Named volume (Docker manages the storage location)
docker run -v pgdata:/var/lib/postgresql/data postgres

# Bind mount (your host directory → container directory)
docker run -v $(pwd)/app:/code/app <payment-svc>
```

| Type | Syntax | When to use |
|------|--------|-------------|
| Named volume | `-v myvolume:/path` | Database data, persistent storage |
| Bind mount | `-v /host/path:/container/path` | Development (live code reload) |
| tmpfs | `--tmpfs /tmp` | Temporary files (in-memory, fast) |

### Networking

```bash
# Create a network
docker network create mynet

# Run containers on the same network
docker run -d --network mynet --name db postgres
docker run -d --network mynet --name app -p 8080:80 <payment-svc>

# Now "app" can reach "db" using the hostname "db"
# Inside the app container: postgresql://user:pass@db:5432/mydb
```

Containers on the same Docker network can reach each other by container name.

---

## Part H — Docker Compose (local dev)

### What it is

Docker Compose runs multiple containers with one command. Define everything in
`docker-compose.yml`:

```yaml
version: "3.8"

services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: <app>
      POSTGRES_PASSWORD: localdev
      POSTGRES_DB: <app>_db
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  app:
    build: .
    ports:
      - "8080:80"
    environment:
      - ENVT=DEV
      - DB_HOST=db
    depends_on:
      - db

volumes:
  pgdata:
```

### Commands

```bash
# Start everything
docker compose up

# Start in background
docker compose up -d

# Rebuild images before starting
docker compose up --build

# Stop everything
docker compose down

# Stop and remove volumes (delete DB data!)
docker compose down -v

# See logs
docker compose logs -f app

# Run a one-off command
docker compose exec app python -c "print('hello')"
```

### Why use Compose for development

Without Compose, you'd run:
```bash
docker run -d --name db -p 5432:5432 -e POSTGRES_PASSWORD=xxx postgres
docker run -d --name app -p 8080:80 -e DB_HOST=db --link db myapp
```

With Compose: `docker compose up` — one command, everything configured, reproducible.

---

## Part I — Debugging Containers

### Container won't start?

```bash
# Check the exit code
docker ps -a
# STATUS: Exited (1)  ← non-zero means crash

# Read the logs
docker logs mycontainer

# Common causes:
# Exit 1:   application error (Python exception on startup)
# Exit 137:  OOMKilled (out of memory, killed by kernel)
# Exit 139:  segfault
# Exit 126:  permission denied (CMD not executable)
# Exit 127:  command not found (wrong CMD path)
```

### App is running but not reachable?

```bash
# Check port mapping
docker port mycontainer
# 80/tcp -> 0.0.0.0:8080

# Check if the app is listening inside the container
docker exec mycontainer ss -tlnp
# or
docker exec mycontainer curl -v http://localhost:80/health

# Common cause: app listens on 127.0.0.1 instead of 0.0.0.0
# Fix: --host 0.0.0.0 in CMD
```

### Need to debug interactively?

```bash
# Shell into a running container
docker exec -it mycontainer /bin/bash

# Shell into a NEW container (even if the app crashes on startup)
docker run -it --entrypoint /bin/bash <payment-svc>
# Now you're inside the container with no app running — debug freely
```

---

## Part J — Mistakes Students Make

### 1. COPY before pip install (cache busting)

```dockerfile
# BAD — every code change rebuilds pip install (slow!)
COPY . /code
RUN pip install -r requirements.txt

# GOOD — requirements cached separately from code
COPY ./requirements.txt /code/requirements.txt
RUN pip install -r requirements.txt
COPY ./app /code/app
```

### 2. Running as root

```dockerfile
# BAD — container runs as root (security risk)
CMD ["python", "app.py"]

# GOOD — create a non-root user
RUN useradd -m appuser
USER appuser
CMD ["python", "app.py"]
```

If someone exploits your app, they get root access to the container. With a
non-root user, the damage is limited.

### 3. No `.dockerignore`

Without `.dockerignore`, `COPY . .` sends everything to the Docker daemon:
`.git/` (hundreds of MB), `node_modules/`, `__pycache__/`, `docs/`, test data...

Create a `.dockerignore`:
```
.git
__pycache__
*.pyc
docs/
.env
*.md
.vscode
```

### 4. `:latest` tag in production

```yaml
# BAD — which version of "latest" are we running?
image: myregistry/myapp:latest

# GOOD — pinned, auditable, rollback-friendly
image: myregistry/myapp:v1.2.3
# or
image: myregistry/myapp:abc1234  # git SHA
```

### 5. Secrets in build args

```dockerfile
# BAD — secret is baked into the image layer (anyone can extract it)
ARG DB_PASSWORD=supersecret
RUN echo $DB_PASSWORD > /etc/db.conf

# GOOD — pass secrets at runtime via environment variables
# docker run -e DB_PASSWORD=supersecret myapp
```

Image layers are stored permanently. Anyone with access to the image can
`docker history` or extract layers to find the secret.

### 6. Not setting health checks

```dockerfile
# Add a health check so Docker/K8s knows if your app is actually working
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:80/health || exit 1
```

Without this, Docker thinks the container is "healthy" as long as the process
is running — even if it's stuck in an infinite loop.

### 7. Ignoring `.env` files

```bash
# BAD — .env file gets copied into the image
COPY . /code

# .env might contain:
# DB_PASSWORD=<db-password>
# RAZORPAY_KEY_SECRET=live_key_xxx
```

Always add `.env` to `.dockerignore`.

---

## Quick Reference

```bash
# Build
docker build -t myapp:v1 .

# Run
docker run -d -p 8080:80 --name myapp -e ENVT=DEV myapp:v1

# Logs
docker logs -f myapp

# Shell
docker exec -it myapp /bin/bash

# Stop + remove
docker stop myapp && docker rm myapp

# Push to registry
docker tag myapp:v1 registry.io/myapp:v1
docker push registry.io/myapp:v1

# Compose
docker compose up -d --build
docker compose down

# Cleanup
docker system prune -a    # remove ALL unused images, containers, networks
```
