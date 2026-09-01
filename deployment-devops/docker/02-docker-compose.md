# Docker Compose — Multi-Container Applications

Real applications have multiple services: web server, database, cache, background workers. Docker Compose lets you define and run all of them together with a single file and a single command.

---

## Table of Contents

1. [What Is Docker Compose](#1)
2. [Installation](#2)
3. [The docker-compose.yml File](#3)
4. [Core Fields Explained](#4)
5. [Complete Real-World Example](#5)
6. [Networking in Compose](#6)
7. [Volumes in Compose](#7)
8. [Environment Variables in Compose](#8)
9. [Health Checks and Dependency Order](#9)
10. [Overrides — Dev vs Prod Configs](#10)
11. [Essential Commands](#11)
12. [Common Patterns](#12)

---

## 1. What Is Docker Compose

Without Compose, running a multi-service app looks like this:

```bash
# Start the database:
docker run -d --name db \
  --network myapp \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  postgres:15

# Start Redis:
docker run -d --name redis \
  --network myapp \
  redis:7-alpine

# Start the web app:
docker run -d --name web \
  --network myapp \
  -p 8000:8000 \
  -e DATABASE_URL=postgres://postgres:secret@db:5432/mydb \
  -e REDIS_URL=redis://redis:6379/0 \
  myapp:latest

# Start the background worker:
docker run -d --name worker \
  --network myapp \
  -e DATABASE_URL=postgres://postgres:secret@db:5432/mydb \
  -e REDIS_URL=redis://redis:6379/0 \
  myapp:latest \
  python worker.py
```

Repeat this every time. Remember all the flags. Update in multiple places when something changes.

**With Compose:** define everything once in `docker-compose.yml`, then:

```bash
docker compose up -d    # starts everything
docker compose down     # stops and removes everything
```

---

## 2. Installation

### Docker Desktop (macOS, Windows)

Docker Compose is included with Docker Desktop. Nothing extra to install.

```bash
docker compose version
# Docker Compose version v2.27.0
```

### Linux

Compose is included as a plugin with Docker Engine:

```bash
sudo apt-get install docker-compose-plugin

docker compose version
```

**Note:** The old standalone `docker-compose` (with a hyphen) is v1 — deprecated. The modern command is `docker compose` (space, no hyphen). V2 is faster, written in Go, and the supported version.

---

## 3. The docker-compose.yml File

A `docker-compose.yml` file has four top-level keys:

```yaml
version: "3.9"    # Compose file format version (optional in modern Compose)

services:         # Define your containers here
  web: ...
  db: ...

volumes:          # Named volumes used by services
  pgdata: ...

networks:         # Custom networks (optional — Compose creates one by default)
  backend: ...
```

---

## 4. Core Fields Explained

Every field you will actually use:

```yaml
services:
  myservice:
    # ── Image ────────────────────────────────────────────────────────
    image: postgres:15              # Use a pre-built image from a registry

    # OR build from a Dockerfile:
    build:
      context: .                    # Directory with the Dockerfile
      dockerfile: Dockerfile        # Defaults to 'Dockerfile' if omitted
      args:
        BUILD_ENV: production       # Build-time arguments (ARG in Dockerfile)
      target: production            # For multi-stage builds: which stage to build to

    # ── Container name ───────────────────────────────────────────────
    container_name: my-postgres     # Defaults to projectname_service_1

    # ── Ports ────────────────────────────────────────────────────────
    ports:
      - "8000:8000"                 # host:container
      - "127.0.0.1:5432:5432"       # bind to localhost only (more secure)

    # ── Environment variables ─────────────────────────────────────────
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: mydb

    # OR load from a file:
    env_file:
      - .env
      - .env.local                  # loaded in order, later overrides earlier

    # ── Volumes ───────────────────────────────────────────────────────
    volumes:
      - pgdata:/var/lib/postgresql/data   # named volume
      - ./config/postgres.conf:/etc/postgresql/postgresql.conf:ro  # bind mount (read-only)

    # ── Networks ──────────────────────────────────────────────────────
    networks:
      - backend

    # ── Dependencies ──────────────────────────────────────────────────
    depends_on:
      db:
        condition: service_healthy   # wait until db passes health check
      redis:
        condition: service_started   # just wait for it to start (no health check)

    # ── Health check ──────────────────────────────────────────────────
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "myuser"]
      interval: 10s       # how often to check
      timeout: 5s         # how long to wait for response
      retries: 5          # mark unhealthy after this many failures
      start_period: 30s   # grace period before first check (allow startup time)

    # ── Restart policy ────────────────────────────────────────────────
    restart: unless-stopped
    # no            (default) — don't restart
    # always        — always restart (even on manual stop)
    # on-failure    — only restart on non-zero exit
    # unless-stopped — restart unless explicitly stopped

    # ── Resource limits ───────────────────────────────────────────────
    deploy:
      resources:
        limits:
          cpus: "0.5"          # max 50% of one CPU core
          memory: 512M         # max 512 MB RAM
        reservations:
          cpus: "0.25"         # guaranteed 25% of one CPU core
          memory: 256M         # guaranteed 256 MB RAM

    # ── Command ───────────────────────────────────────────────────────
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000
    # Overrides CMD in the Dockerfile

    # ── Working directory ─────────────────────────────────────────────
    working_dir: /app

    # ── User ─────────────────────────────────────────────────────────
    user: "1000:1000"            # UID:GID — run as non-root

    # ── Stdin ─────────────────────────────────────────────────────────
    stdin_open: true             # keeps stdin open (-i in docker run)
    tty: true                    # allocates a TTY (-t in docker run)
    # Both needed for interactive containers (e.g., shells, debuggers)

    # ── Logging ───────────────────────────────────────────────────────
    logging:
      driver: "json-file"
      options:
        max-size: "10m"          # rotate logs at 10 MB
        max-file: "3"            # keep 3 rotated files
```

---

## 5. Complete Real-World Example

A full FastAPI application with PostgreSQL, Redis, and a Celery background worker.

```yaml
# docker-compose.yml

services:

  # ── PostgreSQL ────────────────────────────────────────────────────
  db:
    image: postgres:15-alpine
    container_name: myapp-db
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: mydb
    volumes:
      - pgdata:/var/lib/postgresql/data
      # Optional: run init scripts on first start:
      # - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myuser -d mydb"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    restart: unless-stopped
    networks:
      - backend

  # ── Redis ─────────────────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    container_name: myapp-redis
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - backend

  # ── FastAPI Web Server ─────────────────────────────────────────────
  web:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: myapp-web
    ports:
      - "8000:8000"
    env_file:
      - .env
    environment:
      DATABASE_URL: postgres://myuser:mypassword@db:5432/mydb
      REDIS_URL: redis://redis:6379/0
    volumes:
      - ./uploads:/app/uploads    # persist user uploads
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
    restart: unless-stopped
    networks:
      - backend
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ── Celery Worker ─────────────────────────────────────────────────
  worker:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: myapp-worker
    command: celery -A app.celery worker --loglevel=info --concurrency=4
    env_file:
      - .env
    environment:
      DATABASE_URL: postgres://myuser:mypassword@db:5432/mydb
      REDIS_URL: redis://redis:6379/0
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - backend

  # ── Celery Beat (scheduler) ────────────────────────────────────────
  beat:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: myapp-beat
    command: celery -A app.celery beat --loglevel=info
    env_file:
      - .env
    environment:
      DATABASE_URL: postgres://myuser:mypassword@db:5432/mydb
      REDIS_URL: redis://redis:6379/0
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - backend

  # ── Nginx (optional: reverse proxy + static files) ─────────────────
  nginx:
    image: nginx:1.25-alpine
    container_name: myapp-nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./static:/app/static:ro
    depends_on:
      - web
    restart: unless-stopped
    networks:
      - backend

# ── Named Volumes ─────────────────────────────────────────────────────
volumes:
  pgdata:
    driver: local
  redisdata:
    driver: local

# ── Networks ──────────────────────────────────────────────────────────
networks:
  backend:
    driver: bridge
```

---

## 6. Networking in Compose

### Default behavior

Compose automatically creates a network named `{projectname}_default`. All services in the file join this network and can reach each other by service name.

```yaml
services:
  web:
    image: myapp
  db:
    image: postgres:15
# web can reach db at hostname 'db', port 5432
# db can reach web at hostname 'web', port 8000
```

No need to define networks for simple setups.

### Custom networks for isolation

```yaml
services:
  web:
    networks:
      - frontend
      - backend        # web can talk to both nginx and db
  db:
    networks:
      - backend        # db can only be reached by services on backend
  nginx:
    networks:
      - frontend       # nginx can talk to web, but not directly to db

networks:
  frontend:
  backend:
```

Isolation: nginx cannot talk directly to the database. Traffic must go through web.

### Reaching a service from your host machine

Only services with `ports:` are reachable from your host machine.

```yaml
web:
  ports:
    - "8000:8000"     # reachable at localhost:8000

db:
  # no ports: section
  # Only reachable by other containers on the same network
  # NOT reachable from your host machine
```

In production: expose only the services that need external access (web, nginx). Keep databases internal.

---

## 7. Volumes in Compose

### Named volumes

```yaml
services:
  db:
    volumes:
      - pgdata:/var/lib/postgresql/data   # named volume

volumes:
  pgdata:                    # simple declaration — Docker manages location
  pgdata_backup:
    driver: local            # explicitly local
    driver_opts:
      type: none
      device: /mnt/external-disk/pgdata  # store on specific path on host
      o: bind
```

Named volumes survive `docker compose down`. To remove them:

```bash
docker compose down -v    # WARNING: deletes ALL volumes for this project
docker volume rm projectname_pgdata  # remove specific volume
```

### Bind mounts in Compose

```yaml
services:
  web:
    volumes:
      # Relative paths are relative to docker-compose.yml location:
      - ./src:/app/src              # bind mount for dev (live reload)
      - ./config:/app/config:ro     # read-only config
      - /absolute/host/path:/data   # absolute path on host
```

### Volume for sharing between services

```yaml
services:
  web:
    volumes:
      - shared:/app/uploads
  worker:
    volumes:
      - shared:/worker/uploads  # worker can read files web uploaded

volumes:
  shared:
```

---

## 8. Environment Variables in Compose

### Variable interpolation

Compose reads from a `.env` file in the same directory automatically:

```bash
# .env
POSTGRES_PASSWORD=secret
APP_PORT=8000
IMAGE_TAG=latest
```

```yaml
# docker-compose.yml uses ${VARIABLE} syntax:
services:
  db:
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  web:
    image: myapp:${IMAGE_TAG}
    ports:
      - "${APP_PORT}:8000"
```

### Environment precedence (highest to lowest)

```
1. Values set in the shell where you run docker compose
2. Values in docker-compose.yml (hardcoded)
3. Values in .env file
4. Defaults in docker-compose.yml (KEY: ${VAR:-default})
```

```yaml
environment:
  DEBUG: ${DEBUG:-false}          # use $DEBUG from env, default to 'false'
  PORT:  ${PORT:-8000}            # use $PORT from env, default to '8000'
```

### Multiple env files

```yaml
env_file:
  - .env              # common settings
  - .env.local        # local overrides (gitignored)
  - .env.${ENV:-dev}  # e.g., .env.prod or .env.dev
```

---

## 9. Health Checks and Dependency Order

`depends_on` alone does not wait for a service to be ready. It only waits for the container to start. Use `condition: service_healthy` with a health check.

```yaml
services:
  db:
    image: postgres:15
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s      # check every 10 seconds
      timeout: 5s        # timeout after 5 seconds
      retries: 5         # after 5 failures → mark unhealthy
      start_period: 20s  # don't count failures in first 20 seconds (startup time)

  web:
    depends_on:
      db:
        condition: service_healthy   # web will NOT start until db is healthy
```

### Health check commands by service

```yaml
# PostgreSQL:
test: ["CMD-SHELL", "pg_isready -U myuser -d mydb"]

# MySQL:
test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]

# Redis:
test: ["CMD", "redis-cli", "ping"]

# HTTP service:
test: ["CMD", "curl", "-f", "http://localhost:8000/health"]

# Custom script:
test: ["CMD-SHELL", "/app/scripts/healthcheck.sh"]
```

---

## 10. Overrides — Dev vs Prod Configs

### The pattern: base file + override file

Compose automatically merges `docker-compose.yml` with `docker-compose.override.yml`.

```
docker compose up
→ reads: docker-compose.yml + docker-compose.override.yml (merged)
```

**docker-compose.yml** — base config (production-like, no dev extras):

```yaml
services:
  web:
    image: myapp:${IMAGE_TAG:-latest}
    environment:
      DATABASE_URL: postgres://myuser:mypassword@db:5432/mydb
    restart: unless-stopped

  db:
    image: postgres:15-alpine
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

**docker-compose.override.yml** — local dev extras (gitignored or development-specific):

```yaml
services:
  web:
    build: .              # build from local code instead of pulling image
    volumes:
      - .:/app            # live code reload
    environment:
      DEBUG: "true"
      RELOAD: "true"
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
    ports:
      - "8000:8000"

  db:
    ports:
      - "5432:5432"       # expose DB to host for local DB clients (TablePlus, DBeaver)
```

**docker-compose.prod.yml** — explicit production overrides:

```yaml
services:
  web:
    image: myregistry/myapp:${IMAGE_TAG}
    restart: always
    deploy:
      resources:
        limits:
          memory: 512M
```

```bash
# Development (uses override.yml automatically):
docker compose up

# Production (explicitly specify files):
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

## 11. Essential Commands

```bash
# ── Starting and Stopping ──────────────────────────────────────────────

docker compose up               # Start all services (foreground, shows logs)
docker compose up -d            # Start in background (detached)
docker compose up --build       # Rebuild images before starting
docker compose up web           # Start only the 'web' service (and its deps)

docker compose down             # Stop and remove containers and networks
docker compose down -v          # Also remove volumes (DATA LOSS — be careful)
docker compose down --rmi all   # Also remove images built from Dockerfile

docker compose stop             # Stop containers (don't remove)
docker compose start            # Start stopped containers
docker compose restart          # Restart all services
docker compose restart web      # Restart only 'web' service

# ── Status and Logs ───────────────────────────────────────────────────

docker compose ps               # Show service status
docker compose logs             # Logs from all services
docker compose logs web         # Logs from 'web' only
docker compose logs -f          # Follow (live tail all services)
docker compose logs -f web      # Follow 'web' only
docker compose logs --tail=100  # Last 100 lines
docker compose top              # Running processes in each container

# ── Running Commands ──────────────────────────────────────────────────

docker compose exec web bash          # Shell in running web container
docker compose exec web python        # Python shell in running web container
docker compose exec db psql -U myuser # psql in running db container

docker compose run --rm web pytest    # Run a command in a NEW container, then remove it
docker compose run --rm web python manage.py migrate

# ── Building ──────────────────────────────────────────────────────────

docker compose build            # Build all services with build: section
docker compose build web        # Build only 'web'
docker compose build --no-cache # Build without cache (fresh build)
docker compose pull             # Pull latest versions of all images

# ── Scaling ───────────────────────────────────────────────────────────

docker compose up -d --scale worker=3  # Run 3 worker containers
# Each will be named: projectname_worker_1, _2, _3
# Note: scaled services cannot use container_name (would conflict)
# Note: scaled services cannot use host port mapping (would conflict)

# ── Config Inspection ─────────────────────────────────────────────────

docker compose config           # Show merged config (after variable substitution)
docker compose config --services # List service names
docker compose config --volumes  # List volume names
```

---

## 12. Common Patterns

### Pattern: Database migration on startup

```yaml
services:
  migrate:
    build: .
    command: alembic upgrade head
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
    restart: on-failure       # retry if migration fails

  web:
    build: .
    depends_on:
      migrate:
        condition: service_completed_successfully  # wait for migration to finish
```

### Pattern: Nginx as reverse proxy for multiple services

```nginx
# nginx/nginx.conf
upstream api {
    server web:8000;
}

server {
    listen 80;
    server_name example.com;

    location / {
        proxy_pass http://api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /static/ {
        root /app;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### Pattern: Watching logs from specific services

```bash
# Watch web and worker, not db:
docker compose logs -f web worker

# Filter for errors only:
docker compose logs web | grep ERROR

# With timestamps:
docker compose logs -f -t web
```

### Pattern: Running tests in isolation

```bash
# Run tests in a fresh container, with test database:
docker compose -f docker-compose.yml -f docker-compose.test.yml run --rm test
```

```yaml
# docker-compose.test.yml
services:
  test:
    build: .
    command: pytest tests/ -v
    environment:
      DATABASE_URL: postgres://testuser:testpass@testdb:5432/testdb
    depends_on:
      testdb:
        condition: service_healthy

  testdb:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: testuser
      POSTGRES_PASSWORD: testpass
      POSTGRES_DB: testdb
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U testuser"]
      interval: 5s
      retries: 5
    # No volume — test DB is ephemeral
```

---

*Previous: Docker fundamentals → `01-docker-fundamentals.md`*
*Next: Production builds, security, CI/CD → `03-docker-production.md`*
