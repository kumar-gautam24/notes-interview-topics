# The Complete Guide: Servers, Docker, Nginx, AWS & Deployment

**One document. Everything.** Concepts, history, commands, examples — taught in the order we actually
did them, but going well beyond "the steps we ran." By the end you should understand these tools as
*technologies*, not just as things you typed once.

> The other files in this folder split this up (concepts / docker / commands / troubleshooting).
> This file is the whole thing in one place. If you read only one, read this.

---

## Table of contents

**Foundations**
1. [The one idea: a request's journey](#1-the-one-idea-a-requests-journey)
2. [Networking fundamentals](#2-networking-fundamentals) — IP, ports, TCP, HTTP, NAT, firewalls
3. [DNS: the internet's phone book](#3-dns-the-internets-phone-book)

**The infrastructure**

4. [AWS & EC2: renting computers](#4-aws--ec2-renting-computers)
5. [Linux & SSH: operating a headless machine](#5-linux--ssh-operating-a-headless-machine)
6. [Docker, properly](#6-docker-properly) — history, images, containers, layers, port mapping, volumes vs bind mounts, networks, Compose
7. [Nginx, properly](#7-nginx-properly) — history, architecture, config, everything it can do
8. [HTTPS, TLS & certificates](#8-https-tls--certificates)

**The application in production**

9. [The application layer](#9-the-application-layer) — HTTP in practice, health checks, config & secrets, auth, CORS, rate limits, ASGI
10. [Databases in production](#10-databases-in-production) — migrations, pooling, backups, disaster recovery

**Doing it**

11. [The walkthrough: exactly what we did](#11-the-walkthrough-exactly-what-we-did)
12. [Deploying changes: Git, the automation ladder, CI/CD & IaC](#12-deploying-changes-git-the-automation-ladder-cicd--iac)
13. [When things break](#13-when-things-break)

**Making it real**

14. [Production hardening & security](#14-production-hardening--security)
15. [Observability: logs, metrics, alerts](#15-observability-logs-metrics-alerts)
16. [Scaling & zero-downtime deploys](#16-scaling--zero-downtime-deploys)
17. [Where to go next](#17-where-to-go-next)
18. [Appendix: command reference & glossary](#18-appendix-command-reference--glossary)

---

# 1. The one idea: a request's journey

Before any technology, hold this in your head. **A deployment is a delivery route for one request.**
Somebody taps a button; that tap must travel to your code and back. Every tool below is one stop on
that route.

```
  📱 The phone taps "record payment"
     │   sends: HTTPS request to  https://203-0-113-10.nip.io/v1/...
     ▼
  ① DNS — look up the name, get an address       "…nip.io → 203.0.113.10"
     ▼
  🌍 The internet routes the request to that address
     ▼
  ┌────────────────────────────────────────────────────────────┐
  │  ② The server — a rented computer at 203.0.113.10           │
  │                                                              │
  │   ③ Firewall (Security Group): is port 443 open? ✅          │
  │      ▼                                                        │
  │   ④ Nginx — answers the door, decrypts HTTPS,                │
  │      forwards inward to localhost:8000                       │
  │      ▼                                                        │
  │   ⑤ Docker port mapping: host :8000 → container :8000        │
  │      ▼                                                        │
  │   🐍 Your app (FastAPI/uvicorn) inside a container           │
  │      ▼                                                        │
  │   🐘 Postgres, in another container, on a private network    │
  └────────────────────────────────────────────────────────────┘
     │
     ▼   …and the answer travels all the way back.
```

🎓 **Internalise this and debugging becomes easy.** When something breaks you stop panicking and start
asking: *which stop on the route failed?* That question alone solves most problems.

---

# 2. Networking fundamentals

## 2.1 IP addresses

Every machine on a network has a numeric address — an **IP address**, like `203.0.113.10`. Think of the
internet as a vast city and the IP as a building's street number.

- **IPv4** — the familiar four-numbers form (`203.0.113.10`). ~4.3 billion possible addresses, which
  the world ran out of. That scarcity is why…
- **IPv6** — the newer, enormous address space (`2001:0db8:...`). Slowly taking over.

**Public vs private IPs.** Our server had two:
- **Public** `203.0.113.10` — routable from anywhere on the internet.
- **Private** `172.31.21.120` — only meaningful *inside* Amazon's private network. Like a room number:
  useless outside the building.

🎓 Certain ranges are reserved as *private* by convention and are never routed on the public internet:
`10.x.x.x`, `172.16–31.x.x`, `192.168.x.x`. That's why your home router hands you a `192.168.…`
address. Which brings us to…

**NAT (Network Address Translation).** Your laptop, phone, and TV at home all share *one* public IP.
The router keeps a table and rewrites addresses so replies find their way back to the right device.
That's NAT. It's also why "the internet" can't directly reach a machine behind a home router without
port-forwarding.

**Elastic IP.** On AWS, the free auto-assigned public IP can **change** if you fully stop and start
the instance (a reboot is fine). An **Elastic IP** is a permanent address you attach to an instance so
it never changes. Free while attached to a *running* instance.

## 2.2 Ports: many doors on one address

A server runs many programs but has one IP. So how does a request find the right program? **Ports** —
numbered doors on the address. A program "listens" on a port.

| Port | Conventional use |
|------|------------------|
| 22   | SSH (remote login) |
| 25 / 587 | Email (SMTP) |
| 53   | DNS |
| 80   | HTTP (plain web) |
| 443  | HTTPS (secure web) |
| 3306 | MySQL |
| 5432 | PostgreSQL |
| 6379 | Redis |
| 8000 / 8080 | common app-development ports |

Ports 0–1023 are "well-known" and (on Linux) require root privileges to bind — which is one reason a
web app runs on 8000 as a normal user, and Nginx (started by the system as root) takes port 80/443 for it.

## 2.3 TCP, UDP, and HTTP

- **TCP** — a *reliable, ordered* connection. Handshakes first, guarantees delivery, retransmits lost
  packets. Web, SSH, databases all use it.
- **UDP** — *fire and forget*. No guarantees, but fast and low-overhead. DNS, video streaming, games.
- **HTTP** — the language of the web, spoken *over* TCP. A request (`GET /health`) gets a response
  (`200 OK` + body). It's **stateless**: each request stands alone, which is why we send an auth token
  on every call.

🎓 The version matters a little: **HTTP/1.1** (one request at a time per connection), **HTTP/2**
(multiplexed, faster), **HTTP/3** (built on UDP via QUIC). Nginx speaks all of them; you get the
benefit for free.

## 2.4 Firewalls

A firewall decides which traffic is allowed through. By default, deny everything; then open exactly
what you need. On AWS this is a **Security Group** (see §4.5).

🎓 **Prove your firewall works.** From your laptop, try to reach the app's *real* port directly:
```bash
curl --max-time 5 http://203.0.113.10:8000/health   # hangs, then times out
```
It times out because port 8000 was never opened. That closed door *is* your first line of defense.

## 2.5 Load balancers (what we deliberately skipped)

A **load balancer** sits in front of *many* copies of your server and spreads traffic across them, so
one dying doesn't take you down. It solves a problem you only have at scale.

🎓 We have **one server and 1–2 users**. Adding a load balancer now would be installing traffic lights
on a driveway: more cost, more moving parts, zero benefit. Learn it the day you feel the traffic.
(When that day comes: AWS **ALB**/**NLB**, or Nginx itself — see §7.6.)

---

# 3. DNS: the internet's phone book

Nobody types `203.0.113.10`. **DNS** (Domain Name System) maps **names → addresses**.

## 3.1 How a lookup actually works

When you request `api.example.com`, roughly this happens:

```
your device → recursive resolver (e.g. your ISP, or 8.8.8.8)
                 │  (checks its cache first)
                 ├─► root servers:  "who handles .com?"
                 ├─► TLD servers:   "who handles example.com?"
                 └─► authoritative: "example.com's api = 203.0.113.10"
              ← answer cached and returned
```

**TTL** (time-to-live) on each record says how long resolvers may cache the answer. 🎓 That's why DNS
changes "take time to propagate" — you're waiting for caches to expire.

## 3.2 Record types worth knowing

| Record | Means |
|--------|-------|
| **A** | name → IPv4 address |
| **AAAA** | name → IPv6 address |
| **CNAME** | name → *another name* (an alias) |
| **MX** | where to deliver email for this domain |
| **TXT** | arbitrary text — used for domain ownership proofs, SPF/DKIM |
| **NS** | which nameservers are authoritative for this domain |

To point a real domain at our server you'd add an **A record**: `api.example.com → 203.0.113.10`.

## 3.3 The nip.io trick

We didn't buy a domain. **nip.io** is a free public DNS service with one clever rule: any hostname of
the form `203-0-113-10.nip.io` (or `203.0.113.10.nip.io`) automatically resolves to `203.0.113.10` —
the IP is embedded in the name.

Why bother, when we already have the IP? 🎓 **Because certificate authorities won't issue HTTPS
certificates for a bare IP address.** We needed a *name*. nip.io gives us one instantly, free, with no
signup — and Let's Encrypt happily issues certs for it.

> ⚠️ The IP is baked into the name — so if your server's IP changes, your URL changes too. Another
> argument for an Elastic IP, or a real domain.

---

# 4. AWS & EC2: renting computers

## 4.1 What "the cloud" actually is

Someone else's computers, in a warehouse, rented by the hour, created and destroyed via an API. That's
it. The value isn't magic hardware — it's that you can conjure a server in 60 seconds, pay only while
it runs, and never touch a screwdriver.

## 4.2 Regions and Availability Zones

- **Region** — a geographic location with a cluster of data centers (`us-east-1` = N. Virginia, where
  ours lives). Pick one near your users; latency is physics.
- **Availability Zone (AZ)** — an isolated data center *within* a region (`us-east-1a`, `us-east-1b`).
  Serious systems spread across AZs so one building's failure doesn't kill them.

🎓 **The #1 beginner panic:** "my server disappeared!" It didn't — your console is showing a different
region. Resources exist *only* in the region you created them in. Check the dropdown, top-right.

## 4.3 EC2: the instance

**EC2** = Elastic Compute Cloud = rentable virtual computers. One is an **instance**.

**AMI (Amazon Machine Image)** — the OS template you boot from. We chose **Ubuntu** (best-documented;
alternatives: Amazon Linux, Debian). The AMI decides your default login user — `ubuntu` for Ubuntu,
`ec2-user` for Amazon Linux.

**Instance types** — the size/shape. The letter is the *family*, the number the generation:

| Family | Optimised for | Example |
|--------|---------------|---------|
| **t** | burstable, cheap general purpose | `t3.micro` ← ours |
| **m** | balanced general purpose | `m7g.large` |
| **c** | compute (CPU-heavy) | `c7g.xlarge` |
| **r** | memory-heavy | `r6i.large` |

🎓 The **`t` family is "burstable"**: you get a baseline CPU allowance and earn *credits* while idle,
spending them when busy. Perfect for a small app that's mostly quiet. Also: a `g` in the name (`t4g`)
means ARM (Graviton) chips — cheaper, but your Docker images must be ARM-built.

💰 **This is the setting that costs people money.** Always pick one labelled *free-tier eligible*
(`t3.micro`) while learning.

**Pricing models** (worth knowing they exist):
- **On-Demand** — pay per second, no commitment. What we use.
- **Reserved Instances / Savings Plans** — commit 1–3 years, save ~40–70%.
- **Spot** — bid on unused capacity, up to ~90% off, but AWS can reclaim it with 2 minutes' notice.
  Great for batch jobs, terrible for your only server.

**Free credits (2025+ model):** new accounts get up to **$200** ($100 at signup + $100 from starter
activities), valid **6 months or until spent**. After that a small box is ~$7/month — or stop it and
pay ~nothing.

## 4.4 EBS: the hard drive (and the two-layer trap)

An **EBS volume** is a virtual hard drive attached to your instance. Ours started at **8 GB**.

**Volume types:** `gp3` (general-purpose SSD, the modern default), `gp2` (older), `io1/io2`
(provisioned IOPS, for demanding databases), `st1/sc1` (cheap spinning-disk-style, for big sequential
data).

**Snapshots** — point-in-time backups of a volume, stored in S3. The proper way to back up a whole disk.

🎓 **The two-layer trap — the concept that caused a real bug for us.** A disk has two layers, and they
do *not* resize together:

```
   ┌─────────────────────────────────┐
   │  EBS volume  (the drive)        │  ← resize in the AWS console
   │   ┌─────────────────────────┐   │
   │   │ partition               │   │  ← grow with `growpart`
   │   │  ┌───────────────────┐  │   │
   │   │  │ filesystem (ext4) │  │   │  ← grow with `resize2fs`
   │   │  └───────────────────┘  │   │
   │   └─────────────────────────┘   │
   └─────────────────────────────────┘
```

Making the drive bigger in the console does **nothing visible** until you stretch the partition *and*
the filesystem into the new room. Miss the second step and you'll swear the resize failed. (Free tier
covers 30 GB, so growing 8 → 20 GB cost us nothing.)

## 4.5 The network layer: VPC, subnets, Security Groups

- **VPC (Virtual Private Cloud)** — your own private network inside AWS. Every instance lives in one.
- **Subnet** — a slice of the VPC, tied to one AZ. *Public* subnets have a route to an **Internet
  Gateway**; *private* subnets don't (typical for databases).
- **Security Group** — a **stateful, instance-level firewall**. Default: deny everything inbound. You
  open specific ports. "Stateful" means if you allow a request in, the reply is automatically allowed
  out — you don't write a rule for it.
- **Network ACL** — a **stateless, subnet-level** firewall. Lower-level, rarely touched by beginners.

**Ours:** port 22 (SSH) open **only to your own IP**; ports 80 + 443 open to the world; **8000 and
5432 left closed** — which is exactly why the app and database can't be reached directly from the
internet, only through Nginx.

## 4.6 Key pairs & IAM

- **Key pair** — the `.pem` file. It's how SSH proves it's you. 🎓 **There is no reset.** Lose it and
  you're locked out of your own server permanently. Back it up.
- **IAM (Identity and Access Management)** — who can do what in your AWS *account* (as opposed to
  logging into a server). Roles, users, policies. You'll meet it properly the moment you let the server
  talk to S3 for backups: you'd attach an **IAM role** to the instance rather than pasting keys.

## 4.7 Other AWS services you'll bump into

| Service | What it is | When you'd want it |
|---------|-----------|--------------------|
| **S3** | Object storage (files, buckets) | Backups, user uploads, static sites |
| **RDS** | Managed database | You want automated backups & patching (💰 ~$12+/mo) |
| **Lightsail** | Simplified VPS with flat pricing | Predictable bills, less to learn |
| **App Runner** | "Give me a container, I'll run it" | Least ops effort, HTTPS included |
| **ECS / Fargate** | Container orchestration | Many containers, real scale |
| **Route 53** | Managed DNS | Real domains |
| **CloudWatch** | Logs & metrics & alarms | Knowing when things break |
| **ELB (ALB/NLB)** | Load balancers | Many servers |

🎓 **Why we chose plain EC2 over all of these:** it's the standard beginner path, essentially free, and
it forces you to touch the fundamentals (a server, a firewall, SSH, a proxy). The managed options hide
exactly the things you're trying to learn. You can always graduate.

---

# 5. Linux & SSH: operating a headless machine

## 5.1 SSH

**SSH (Secure Shell)** gives you an encrypted terminal on a machine with no screen or keyboard. You
type locally; commands run remotely.

```bash
chmod 400 ~/Downloads/recurring-key.pem                    # lock the key or SSH refuses it
ssh -i ~/Downloads/recurring-key.pem ubuntu@203.0.113.10   # -i = identity (key) file
```

- **Key-based auth, not passwords.** The `.pem` is your private key; AWS put the matching public key on
  the server at launch. Possession of the file *is* the proof.
- **`chmod 400`** = "only I can read this, nobody can write it." SSH refuses keys that others could
  read — a safety feature, not a nuisance.
- **The fingerprint prompt** on first connect is SSH asking "I've never seen this server; trust it?"
  Type `yes` once; it's remembered in `~/.ssh/known_hosts`.
- **`scp`** is the sibling for copying files over the same secure channel:
  ```bash
  scp -i ~/key.pem localfile ubuntu@203.0.113.10:/home/ubuntu/
  ```

## 5.2 Foreground, background, daemons

🎓 The question every beginner asks: *"if I start the server, is my terminal stuck? If I close my
laptop, does everything stop?"*

- **Foreground** — the command owns your terminal until it exits or you press `Ctrl-C`.
- **Background / detached** — it starts, hands your prompt back, keeps running unseen. That's the `-d`
  in `docker compose up -d`.
- **Daemon** — a long-running background service. Docker runs your containers as daemons, so **they
  keep running after you disconnect SSH or shut your laptop.** The server doesn't need you watching —
  that's the whole point of a server.

And: `Ctrl-C` while following logs stops your *watching*, not the app.

## 5.3 systemd & systemctl

Modern Linux manages background **services** with `systemd`. One tool controls them all:

| Command | What it does |
|---------|--------------|
| `systemctl reload nginx` | re-read config, **no dropped connections** (graceful) |
| `systemctl restart nginx` | full stop + start (brief downtime) |
| `systemctl status nginx` | running? recent logs |
| `systemctl is-active nginx` | just `active`/`inactive` |
| `systemctl enable nginx` | start automatically at boot |
| `systemctl list-timers` | scheduled jobs (e.g. Certbot's auto-renew) |

🎓 For config changes always prefer **`reload`** — it applies the change with zero downtime.

## 5.4 Packages (apt)

```bash
sudo apt update                 # refresh the catalogue of available packages
sudo apt install -y nginx       # install (-y = don't ask)
sudo apt clean                  # delete cached .deb downloads (frees disk)
sudo apt --fix-broken install   # finish a half-completed/interrupted install
```

## 5.5 Disk: memory, swap, and finding what's full

**Swap** — disk space borrowed as *pretend RAM* when real memory fills. Slower, but it stops the kernel
from killing your process under pressure. Essential on a 1 GB box during a Docker build:

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab   # survive reboots
free -h                                                       # see RAM + swap
```

**Finding what filled your disk** — three commands, increasing zoom:
```bash
df -h /                                          # how full is the filesystem? (Use%)
du -sh ~/honest-ledger                           # how big is this one folder?
sudo du -h -d1 / 2>/dev/null | sort -hr | head   # biggest top-level folders, largest first
```
🎓 Memorize the last one. It's *the* answer to "help, my disk is full," and it points straight at the
culprit (for us: `/var`, where Docker keeps its images).

**Growing a disk** (after enlarging the volume in the console):
```bash
lsblk                            # see the drive is now 20G but the filesystem still ~7G
sudo growpart /dev/nvme0n1 1     # stretch the PARTITION
sudo resize2fs /dev/nvme0n1p1    # stretch the FILESYSTEM
df -h /                          # confirm
```

## 5.6 Shell things that confuse everyone

**Redirects and pipes.**
- `>` writes output to a file (overwrite), `>>` appends.
- `|` pipes one command's output into another's input.
- `/dev/null` is the system's bin — send output there to discard it.

**The `sudo tee` gotcha.** You'd expect this to work:
```bash
sudo echo "text" > /etc/somefile      # ❌ Permission denied
```
🎓 It fails because the `>` redirect is performed by **your shell**, running as **you** — `sudo` only
elevated the harmless `echo`. The fix is to elevate the program that *does the writing*:
```bash
echo "text" | sudo tee /etc/somefile > /dev/null   # ✅
```
**`tee`** is named after a plumbing T-splitter: it writes its input to a **file** *and* to the screen.
We redirect the screen half to `/dev/null` because we don't need to see it echoed back.

**Heredocs.** `<<'EOF' ... EOF` feeds a whole multi-line block as input:
```bash
sudo tee /etc/nginx/sites-available/recurring > /dev/null <<'EOF'
server { ... }
EOF
```
🎓 The **quotes around `'EOF'`** matter: they tell the shell "don't expand `$variables` in here," so
Nginx's `$host` survives literally instead of being replaced with nothing.

**`sed -i`** edits a file in place: `sed -i "s|old|new|" file` (the `s|a|b|` is substitute).

**`openssl rand -hex 32`** generates 32 random bytes as hex — a proper secret key.

---

# 6. Docker, properly

## 6.1 The problem Docker solves

"But it works on my machine." Your app needs a specific Python version, specific libraries, specific OS
packages — and the server has different ones. Making them match by hand is misery.

🎓 **Docker's cure: package the app together with its whole environment into one sealed box.** That box
runs identically on your laptop, the server, or a colleague's machine. You stop shipping "the app" and
start shipping "the app *and* the machine it likes." "Works on my machine" becomes "the machine comes
along for the ride."

## 6.2 A little history (and why containers aren't VMs)

Isolation on Unix has a long lineage: `chroot` (1979) confined a process to a directory. Linux later
grew two kernel features that make real containers possible:

- **Namespaces** — give a process its own private view of the system: its own process list (PID), its
  own network stack (NET), its own filesystem mounts (MNT), hostname (UTS), and so on. The process
  genuinely believes it's alone on the machine.
- **cgroups (control groups)** — limit and account for resources: "this group of processes may use at
  most 512 MB of RAM and 1 CPU."

**Docker (2013)** didn't invent these — it wrapped them in a wonderful developer experience: a
`Dockerfile` to build, an image to ship, a registry to share, one command to run. (It first used LXC,
later its own `libcontainer`/`runc`; today the container format is standardised by the **OCI**.)

**Container vs Virtual Machine** — the crucial distinction:

```
   VIRTUAL MACHINES                     CONTAINERS
  ┌──────┐ ┌──────┐                   ┌──────┐ ┌──────┐
  │ App  │ │ App  │                   │ App  │ │ App  │
  │ Libs │ │ Libs │                   │ Libs │ │ Libs │
  │Guest │ │Guest │ ← a whole OS      └──────┘ └──────┘
  │  OS  │ │  OS  │   per VM (heavy)  ┌────────────────┐
  └──────┘ └──────┘                   │ Docker engine  │
  ┌────────────────┐                  ├────────────────┤
  │   Hypervisor   │                  │  Host kernel   │ ← SHARED (light)
  ├────────────────┤                  ├────────────────┤
  │  Host machine  │                  │  Host machine  │
  └────────────────┘                  └────────────────┘
```

🎓 A VM virtualizes **hardware** and runs its own kernel → slow to boot, gigabytes in size. A container
shares the **host's kernel** and only isolates the process → boots in milliseconds, megabytes in size.
That lightness is why we can run an app *and* a database as two containers on a 1 GB server.

## 6.3 The vocabulary

- **Image** — a frozen, read-only **template**: your app + its environment. Like a *recipe*, or a
  *class* in code. Built from a `Dockerfile`.
- **Container** — a **running instance** of an image. The *cooked meal*; the *object*. Many containers
  can run from one image. Containers are **disposable** — expect to destroy and recreate them.
- **Registry** — where images are stored and shared. **Docker Hub** is the public default (that's where
  `postgres:16` came from); AWS's is **ECR**.
- **Volume** — persistent storage that lives *outside* the container, so data survives rebuilds.
- **Docker engine (daemon)** — the background service that actually runs containers.
- **Docker Compose** — a tool to define and run *several* containers together from one YAML file.

## 6.4 Dockerfile, layers, and the build cache

A `Dockerfile` is a list of build steps. Ours, roughly:

```dockerfile
FROM python:3.12-slim              # start from an existing image
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /uvx /bin/
WORKDIR /app
COPY pyproject.toml uv.lock ./     # copy ONLY the dependency manifest first…
RUN uv sync --frozen --no-dev      # …so this expensive step is cached
COPY . .                           # then copy the source (changes often)
EXPOSE 8000
CMD ["bash", "entrypoint.sh"]
```

🎓 **Every instruction creates a layer** — an immutable diff stacked on the one before. Docker caches
layers: if a step's inputs haven't changed, it reuses the cached result. That's why the Dockerfile
copies `pyproject.toml` *before* the source code — editing your app code doesn't invalidate the
expensive dependency-install layer. **Order your Dockerfile from least-changing to most-changing.**

The cost: that cache **accumulates on disk**, and base images are hundreds of MB each. This is exactly
why our 8 GB server filled up. The cure:
```bash
docker system df          # see images / containers / volumes / build cache
docker builder prune -f   # delete build cache (safe: won't touch running containers)
```

**Key Dockerfile instructions:**

| Instruction | Meaning |
|-------------|---------|
| `FROM` | base image to start from |
| `RUN` | run a command **at build time** (installs deps) |
| `COPY` / `ADD` | copy files into the image |
| `WORKDIR` | set the working directory |
| `ENV` | set an environment variable |
| `EXPOSE` | *documents* which port the app listens on (doesn't publish it!) |
| `CMD` | default command **at run time** |
| `ENTRYPOINT` | the fixed executable; `CMD` becomes its arguments |

🎓 **`EXPOSE` does not open a port.** It's documentation. Publishing a port is done at *run* time with
`-p` / the compose `ports:` key. This confuses everyone once.

**`.dockerignore`** — like `.gitignore`, but for the build context. Keeps junk (`.venv`, `__pycache__`)
out of the image and makes builds faster.

## 6.5 Port mapping

A container has its own network namespace — its own private network. So how does Nginx (on the host)
reach the app (inside a container)? **Port mapping** pokes a labelled hole:

```
   ports:
     - "8000:8000"
        └─┬─┘ └─┬─┘
        HOST  CONTAINER
        door    door
```

Read it: *"traffic arriving at port 8000 **on the server** → forward it to port 8000 **inside the
container**."* Left is always the host. They needn't match: `"80:8000"` would publish the container's
8000 as the host's 80.

🎓 **Security note.** `"8000:8000"` binds to *all* host interfaces (`0.0.0.0`), meaning the port is
reachable from outside the machine — unless a firewall stops it (ours does). To be explicit, bind to
localhost only: `"127.0.0.1:8000:8000"`. Then only Nginx (on the same box) can reach it, firewall or not.

## 6.6 Persisting data: volumes vs bind mounts vs tmpfs

Containers are **disposable** — delete one and everything written inside it vanishes. That's fine for
an app, catastrophic for a database. So Docker offers three ways to keep data *outside* the container.

### Named volumes (what we use for Postgres)
```yaml
services:
  db:
    volumes:
      - dbdata:/var/lib/postgresql/data
volumes:
  dbdata:
```
- **Managed by Docker**, stored under `/var/lib/docker/volumes/`. You don't care where.
- Survives `docker compose down`, container rebuilds, image changes.
- **Best for databases and any real persistent state.**
- Portable across machines; easy to back up.

### Bind mounts (best for development)
```yaml
    volumes:
      - ./app:/app          # a HOST path : a CONTAINER path
```
- Maps a **specific folder on the host** into the container.
- Changes on the host appear instantly inside the container → **live code reload while developing.**
- 🎓 The trade-off: it depends on the host's directory layout and permissions, so it's fragile across
  machines. Great for dev, generally avoided in production.

### tmpfs mounts
```yaml
    tmpfs:
      - /tmp
```
- Lives **in memory only**, never written to disk. Vanishes when the container stops.
- For secrets or scratch data you don't want persisted.

🎓 **The rule of thumb:** *named volume* for data you must keep (databases). *Bind mount* for source
code during development. *tmpfs* for secrets and scratch.

⚠️ **The command that has erased many databases:**
```bash
docker compose down       # stops & removes containers — your VOLUME (data) is KEPT
docker compose down -v    # ⚠️ ...also deletes volumes — this DESTROYS the database
```
Burn that distinction in.

## 6.7 Networking between containers

When Compose starts your stack, it creates a **private virtual network** and puts every service on it.
Inside that network, **each service is reachable by its service name** — Docker runs a tiny DNS server
for them.

🎓 **This is why our app's database URL says `@db:5432` and not `@localhost:5432`:**
```
DATABASE_URL=postgresql://recurring:recurring@db:5432/recurring
                                              ↑
                            the compose SERVICE NAME resolves to the db container's IP
```
The two containers talk to each other over that private network. Postgres's port 5432 is **never
published to the host** — nothing outside can reach it. That's good security by default.

**Network modes** (for reference): `bridge` (the default, isolated virtual network), `host` (share the
host's network stack directly — no isolation, no port mapping), `none` (no networking).

## 6.8 Docker Compose

Compose describes a multi-container app in one YAML file. The pieces that matter in ours:

```yaml
services:
  db:
    image: postgres:16                 # use a prebuilt image from a registry
    environment:                       # config passed as env vars
      POSTGRES_USER: recurring
    volumes:
      - dbdata:/var/lib/postgresql/data   # named volume → data persists
    healthcheck:                          # 🎓 "is it REALLY ready?"
      test: ["CMD-SHELL", "pg_isready -U recurring -d recurring"]
      interval: 3s
      retries: 10

  api:
    build: .                           # build from the Dockerfile here
    env_file: .env                     # load settings from a file
    ports:
      - "8000:8000"                    # publish to the host
    depends_on:
      db:
        condition: service_healthy     # 🎓 wait for the healthcheck, not just "started"

volumes:
  dbdata:
```

🎓 Two subtleties worth noticing:
1. **`healthcheck` + `depends_on: condition: service_healthy`** — without this, `depends_on` only waits
   for the container to *start*, not for Postgres to actually accept connections. Your app would race
   the database and crash on boot. This pairing fixes a classic bug.
2. **`entrypoint.sh`** runs on *every container start* and does `yoyo apply` (migrations) then launches
   uvicorn. That's the quiet hero of easy deploys: **database migrations apply themselves**, so shipping
   a schema change needs no extra step.

**`restart: unless-stopped`** is worth adding to production services — it brings containers back after
a server reboot.

## 6.9 The commands, and when to reach for each

**"Start everything."**
```bash
docker compose up -d --build
#   --build  rebuild the image from current code first
#   -d       detached: run in the background, give me my prompt back
```

**"Is it running? Is it healthy?"**
```bash
docker compose ps
```

**"What is the app actually doing?"**
```bash
docker compose logs -f api          # follow live (Ctrl-C stops WATCHING, not the app)
docker compose logs api --tail 40   # last 40 lines
```
🎓 Your window into a running app. When we hit a mysterious bug, the logs showed the truth our theory
had gotten wrong. **Always look here first.**

**"Let me poke around *inside* the running container."**
```bash
docker compose exec api bash                            # a shell inside it; `exit` to leave
docker compose exec api grep -n '@app.get' app/main.py  # or just one command
```
🎓 Think of it as SSHing one level deeper — from the server *into* the container. The nesting is:
`your laptop → (ssh) → the server → (exec) → the container`.

⚠️ **Anything you change inside a container is temporary** — wiped on the next rebuild. `exec` is for
*looking* and debugging, never for editing real code.

**`exec` vs `run`:** `exec` runs a command in the **already-running** container. `run` spins up a
**brand-new throwaway** container. Different tools; don't confuse them.

**Housekeeping.**
```bash
docker compose down            # stop & remove containers (DATA KEPT)
docker compose down -v         # ⚠️ also delete volumes (DATA DESTROYED)
docker compose restart api     # bounce one service
docker compose up -d           # start without rebuilding (e.g. after an .env-only change)
docker compose pull            # fetch newer prebuilt images
docker system df               # Docker's disk usage
docker builder prune -f        # reclaim build cache
docker ps / docker images      # all containers / all images on the machine
```

---

# 7. Nginx, properly

## 7.1 Where it came from (and the problem it solved)

In the late 1990s, the dominant web server was **Apache**, which handled each connection with its own
**process or thread**. That works fine until you have thousands of simultaneous connections — then the
memory and context-switching overhead crushes the machine. This became famous as the **C10K problem**:
*how do you serve 10,000 concurrent connections on one box?*

**Igor Sysoev**, a Russian engineer, wrote **nginx** to solve exactly this, releasing it publicly in
**2004**. His answer was a different architecture: instead of a thread per connection, use a small
number of **worker processes**, each running an **event loop** that handles thousands of connections
asynchronously — never blocking, just reacting to "this socket has data" events.

🎓 The result: nginx serves enormous numbers of concurrent, mostly-idle connections with tiny, *flat*
memory usage. That's why it took over the internet as the front door of choice, and why the same
event-driven idea shows up in Node.js and modern async Python (like the `uvicorn` running your app).

## 7.2 What Nginx actually does for us: reverse proxy

Your app speaks plain, unencrypted HTTP and knows nothing about certificates. You don't want that
directly exposed. So Nginx acts as a **receptionist** at the front doors (80 and 443):

- Listens on the public ports so your app doesn't have to.
- Handles **TLS termination** — decrypting HTTPS, so your app deals only with simple HTTP.
- **Forwards** the request inward to `localhost:8000`.
- Attaches sticky-notes about the *original* visitor, since otherwise the app would think Nginx was the
  caller.

🎓 **"Reverse" proxy** because it stands in front of the **server** (on the server's behalf). A plain
("forward") proxy stands in front of **clients** — like a corporate proxy filtering employees' browsing.
Same machinery, opposite direction.

## 7.3 Config structure

Nginx config is a tree of **blocks** (contexts) containing **directives** (each ending in `;`).

```
main context          — worker_processes, user, …
  events { }          — connection handling
  http { }            — everything HTTP
    server { }        — one "website" (a virtual host)
      location { }    — rules for a set of URL paths
```

On Ubuntu the main file is `/etc/nginx/nginx.conf`, which `include`s your site files. And here's the
convention that confuses newcomers:

- **`/etc/nginx/sites-available/`** — every site config you've *written* (on or off).
- **`/etc/nginx/sites-enabled/`** — only the ones actually *loaded*.

🎓 You "enable" a site by placing a **symlink** (a shortcut) to it in `sites-enabled/`. To disable, you
delete the *shortcut* — the real config stays safe. Enable/disable without ever risking the original.

```bash
sudo ln -s /etc/nginx/sites-available/recurring /etc/nginx/sites-enabled/   # enable
sudo rm /etc/nginx/sites-enabled/default                                    # disable the default site
```

## 7.4 Our config, line by line

```nginx
server {                                  # one virtual host
    listen 80;                            # wait at the public HTTP door
    server_name 203-0-113-10.nip.io;      # only handle requests asking for THIS name

    location / {                          # for every path under "/":
        proxy_pass http://localhost:8000;               # ⭐ hand the request to the app
        proxy_set_header Host $host;                    # note: the name they asked for
        proxy_set_header X-Real-IP $remote_addr;        # note: the visitor's real IP
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;   # note: proxy chain
        proxy_set_header X-Forwarded-Proto $scheme;     # note: was it http or https?
    }
}
```

🎓 **Everything except `proxy_pass` is bookkeeping.** The whole job is "catch it at the front, pass it
to the app." Those four headers matter because after forwarding, your app's idea of "who called me"
would otherwise be *Nginx on localhost*. `X-Forwarded-Proto` becomes important once HTTPS is on: it's
how the app knows the *user's* connection was secure even though the Nginx→app hop is plain HTTP.

**`server_name` and virtual hosting:** one Nginx can host many sites on one IP by matching the `Host`
header. That's how a single server serves `api.example.com` and `www.example.com` differently.

**`location` matching** (in priority order): `location = /exact`, `location ^~ /prefix`,
`location ~ regex` (case-sensitive), `location ~* regex` (insensitive), `location /prefix` (plain).

## 7.5 Testing and reloading — the safety habit

```bash
sudo nginx -t                  # DRY RUN: parse the config, report errors, change nothing
sudo systemctl reload nginx    # apply gracefully — zero dropped connections
```

🎓 **Always `nginx -t` before `reload`.** Applying a broken config to a live server can take your site
down; the test catches typos first. And prefer `reload` over `restart`: reload signals the running
master process to spawn new workers with the new config and retire the old ones gracefully — nobody's
request is cut off. `restart` kills everything and starts fresh (a blip of downtime).

## 7.6 What else Nginx can do (beyond our use)

We only used one feature. Nginx is much bigger — knowing the menu helps you recognise it in the wild:

- **Static file server** — its original job. Serving images/CSS/JS straight from disk, extremely fast.
  ```nginx
  location /static/ { root /var/www; }
  ```
- **Load balancer** — spread traffic across several backends:
  ```nginx
  upstream app { server 10.0.0.1:8000; server 10.0.0.2:8000; }
  server { location / { proxy_pass http://app; } }
  ```
  Strategies: round-robin (default), `least_conn`, `ip_hash` (sticky sessions).
- **TLS termination** — what Certbot configured for us (§8).
- **Caching** — store backend responses and serve them without re-asking (`proxy_cache`).
- **Compression** — `gzip on;` shrinks responses.
- **Rate limiting** — `limit_req_zone`, to blunt abuse.
- **Redirects & rewrites** — `return 301 https://$host$request_uri;` (exactly what Certbot added to
  push HTTP → HTTPS).
- **Serving as an API gateway** — routing `/api` to one service, `/admin` to another.

**Alternatives:** **Caddy** (automatic HTTPS, far simpler config), **Traefik** (container-native,
auto-discovers services), **HAProxy** (load balancing specialist), **Apache** (the old guard).

## 7.7 Nginx command reference

```bash
sudo nginx -t                    # test config (always before reload)
sudo systemctl reload nginx      # graceful apply
sudo systemctl restart nginx     # hard restart
sudo systemctl status nginx      # is it up?
sudo nginx -T                    # dump the FULL merged config (great for debugging)
sudo tail -f /var/log/nginx/access.log   # who's hitting us
sudo tail -f /var/log/nginx/error.log    # what's failing
```

---

# 8. HTTPS, TLS & certificates

## 8.1 What HTTPS gives you

Plain HTTP is a **postcard** — anyone handling it en route can read (and alter) it. HTTPS is a sealed,
tamper-evident **envelope**. Two guarantees:

1. **Encryption** — nobody in the middle can read the traffic.
2. **Identity** — a **certificate** proves the server is who it claims to be, not an impostor.

For a finance app, plain HTTP is a non-starter. (It's also why the Flutter code comments mention iOS
App Transport Security — Apple simply refuses plain HTTP from apps by default.)

## 8.2 How TLS works, roughly

```
Client                                        Server
  │── "hello, I speak TLS 1.3, these ciphers" ──►
  ◄── "hello, here's my CERTIFICATE" ──────────│
  │   (client verifies the cert chains up to a
  │    Certificate Authority it already trusts)
  │── key exchange ─────────────────────────────►
  │   both sides derive the same secret session key
  │◄════ encrypted traffic, symmetric cipher ═══►
```

🎓 The certificate is **not** the encryption. It's the *identity proof*, signed by a **Certificate
Authority (CA)** whose root certificate is already baked into your OS/browser. Chain of trust: your
cert ← signed by an intermediate ← signed by a root your device already trusts. The actual encryption
uses a fast symmetric key negotiated during the handshake.

## 8.3 Let's Encrypt, Certbot, and ACME

Certificates used to cost money and involve email verification. **Let's Encrypt** (2015, nonprofit)
made them **free and automated**, and single-handedly pushed the web to HTTPS.

**Certbot** is the client that talks to Let's Encrypt. But how does Let's Encrypt know *you* control
`203-0-113-10.nip.io`? Through a proof-of-ownership dance called the **ACME challenge**:

| Challenge | How it proves control | Notes |
|-----------|----------------------|-------|
| **HTTP-01** | Certbot places a secret token at `http://your-domain/.well-known/acme-challenge/…`; Let's Encrypt fetches it over **port 80** | What we used. Needs port 80 open. |
| **DNS-01** | You publish a TXT record in DNS | The only one that can issue **wildcard** certs (`*.example.com`) |
| **TLS-ALPN-01** | A special TLS handshake on port 443 | For when port 80 is unavailable |

🎓 **This is exactly why we set up Nginx on port 80 *before* asking for a certificate.** The proof rides
on it. If cert issuance ever fails, "is port 80 reachable, and is Nginx serving the right
`server_name`?" is your first question.

## 8.4 Doing it

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d 203-0-113-10.nip.io
```

The `--nginx` plugin does three things for you: passes the challenge, installs the certificate, and
**rewrites your Nginx config** to add a `listen 443 ssl` block plus an HTTP→HTTPS redirect. You never
hand-edit the TLS config.

**Renewal.** Let's Encrypt certs last **90 days** — deliberately short, because short-lived certs limit
the damage of a stolen key and force automation. Certbot installs a systemd timer that renews at ~60
days, automatically, forever.

```bash
systemctl list-timers | grep certbot   # confirm the auto-renew timer is armed
sudo certbot renew --dry-run           # test renewal safely (doesn't burn rate limits)
sudo certbot certificates              # what certs do I have, when do they expire?
```

⚠️ Let's Encrypt has **rate limits** — don't re-issue in a loop while experimenting.

---

# 9. The application layer

Infrastructure gets the request to your code. This section is about the code's side of the contract —
the parts that decide whether your deployment is *actually* production-ready.

## 9.1 HTTP in practice: methods, status codes, idempotency

**Methods** describe intent, and two properties matter enormously:
- **Safe** = doesn't change anything (a read).
- **Idempotent** = doing it twice has the same effect as doing it once.

| Method | Safe? | Idempotent? | Use |
|--------|-------|-------------|-----|
| `GET` | ✅ | ✅ | read |
| `POST` | ❌ | ❌ | create (repeating it creates two!) |
| `PUT` | ❌ | ✅ | replace wholesale |
| `PATCH` | ❌ | usually not | partial update |
| `DELETE` | ❌ | ✅ | remove (deleting twice = still deleted) |

🎓 **Why idempotency matters to you:** a phone on flaky mobile data sends a request, the reply is lost,
the phone retries. With a non-idempotent `POST` you just created the payment twice. The fix is an
**idempotency key** — a client-generated unique ID sent with the request, so the server recognises a
retry. (This app does exactly that: the client generates UUIDs, so a replayed create is harmless.)

**Status codes** — the server's one-word summary. Learn the shape, not the list:

| Range | Meaning | The ones you'll actually meet |
|-------|---------|------------------------------|
| **2xx** | success | `200 OK`, `201 Created`, `204 No Content` |
| **3xx** | go elsewhere | `301` permanent redirect (what Certbot's HTTP→HTTPS uses), `304 Not Modified` |
| **4xx** | **you** (the client) messed up | `400` bad request, `401` not authenticated, `403` authenticated but not allowed, `404` no such thing, `409` conflict, `422` failed validation, `429` too many requests |
| **5xx** | **the server** messed up | `500` unhandled crash, `502` bad gateway, `503` unavailable, `504` gateway timeout |

🎓 **Three of these are specifically about your Nginx setup — learn them and you'll debug instantly:**
- **`502 Bad Gateway`** → Nginx is up, but **it couldn't reach your app**. Your container is down, crashed,
  or listening on the wrong port. *Check `docker compose ps` and `docker compose logs api`.*
- **`504 Gateway Timeout`** → Nginx reached your app, but the app **took too long** to answer.
- **`404` from Nginx vs `404` from your app** → different bodies. If you get Nginx's HTML 404 page, the
  request never reached your app (wrong `server_name` or `location`). If you get your app's JSON
  `{"detail":"Not Found"}`, it reached the app, which had no such route. *This exact distinction is how
  we solved Bug #1 in §13.*

**Headers** carry metadata: `Content-Type`, `Authorization: Bearer <token>`, `Host`, and the
`X-Forwarded-*` family the proxy adds. **HTTP is stateless** — each request stands alone, which is why
an auth token is sent on *every* call.

**`curl` is your scalpel.** Worth knowing beyond `curl URL`:
```bash
curl -i URL                          # include response status + headers  ← the debugging default
curl -v URL                          # verbose: show the whole conversation, incl. TLS handshake
curl -X POST -H 'Content-Type: application/json' -d '{"a":1}' URL
curl -H 'Authorization: Bearer TOKEN' URL
curl -L URL                          # follow redirects
curl --max-time 5 URL                # give up after 5s (proves a port is firewalled)
curl -o file URL                     # save to a file
```

## 9.2 Health checks: liveness vs readiness

Your app exposes two endpoints, and the difference is a real concept (it comes from Kubernetes but
applies everywhere):

| Endpoint | Question it answers | Checks the DB? | What a supervisor does if it fails |
|----------|--------------------|----------------|-----------------------------------|
| **`/health`** | **Liveness** — is the process alive? | ❌ no | **Restart the container** — it's wedged |
| **`/ready`** | **Readiness** — can it serve traffic *right now*? | ✅ yes | **Stop sending it traffic** (but don't restart it) |

🎓 **Why they must be separate.** Imagine your database is briefly down. If your *liveness* check also
pinged the database, every app instance would be declared dead and restarted in a loop — a restart storm
that makes an outage far worse. Liveness must be dumb and dependency-free. **Readiness** is where you
check dependencies, because the right response to "the DB is down" is *"take me out of rotation until it's
back,"* not *"kill me."*

That's why `/health` returns `{"status":"ok"}` unconditionally, and `/ready` returns `503` with
`{"status":"unavailable","db":"down"}` if Postgres is unreachable. Compose uses the same idea with its
`healthcheck:` on the `db` service (§6.8).

## 9.3 Configuration & secrets: the 12-factor way

🎓 **The rule: configuration lives in the *environment*, not in the code.** The same image should run in
dev, staging, and production, differing only by environment variables. This is the core of the
[**12-factor app**](https://12factor.net) methodology, and it's why our `docker-compose.yml` says
`env_file: .env` instead of baking values in.

Other 12-factor ideas you've already used without knowing:
- **Explicit dependencies** — `uv.lock` pins exact versions, so builds are reproducible.
- **Backing services are attached resources** — the database is reachable via a URL, so swapping the
  container for a managed RDS instance later means changing one string.
- **Logs are event streams** — the app writes to stdout; Docker captures it. It never manages log files.
- **Disposability** — containers start fast and can be killed at any moment without data loss.

**Secrets.** Three rules that matter:
1. **Never commit secrets.** `.env` is gitignored, which is why we created it *fresh on the server*.
2. **Never use a placeholder in production.** `.env.example` ships a *publicly known* `JWT_SECRET` — if
   we'd shipped that, anyone reading the repo could forge login tokens for any user. We generated a real
   one: `openssl rand -hex 32`.
3. **Never bake secrets into a Docker image.** Image layers are permanent and shippable — a secret in a
   layer is a secret leaked, even if a later layer deletes it.

*Grown-up alternatives when you're ready:* AWS Secrets Manager / SSM Parameter Store, Docker secrets,
HashiCorp Vault.

## 9.4 Authentication: JWTs, briefly

Our app signs **JWTs** (JSON Web Tokens) with `JWT_SECRET`. A JWT is three base64 chunks joined by dots:

```
header . payload . signature
```

🎓 **The payload is *not* encrypted — anyone can read it.** Paste a JWT into jwt.io and you'll see the
user id and expiry in plain text. What the signature guarantees is that nobody *altered* it, because they
can't recompute the signature without the secret. So: **never put anything private in a JWT payload**, and
**guard the secret like a password** — with it, anyone can mint a token claiming to be any user.

The usual pattern (which this app follows): a **short-lived access token** (~15 min) sent on every
request, plus a **long-lived refresh token** (~30 days) used only to get new access tokens. Short access
tokens limit the blast radius of a stolen one.

## 9.5 CORS — the one that confuses everyone

**CORS** (Cross-Origin Resource Sharing) is a rule enforced by **web browsers**: JavaScript on
`evil.com` may not read a response from `your-api.com` unless your API explicitly permits that origin.

🎓 Two things people get wrong:
1. **CORS is enforced by the browser, not by your server.** A mobile app, `curl`, or a Python script
   ignores it entirely. Our Flutter app is unaffected.
2. **CORS is not authentication.** It doesn't stop anyone from *calling* your API — it stops a
   browser page from *reading the response*.

Our config has `CORS_ALLOW_ORIGINS=*` (allow any origin), which is acceptable *specifically because* we
authenticate with a bearer token rather than cookies. Had we used cookies, a wildcard would be dangerous
(the browser would attach the user's cookies to cross-site requests). If you ever add a web frontend,
narrow this to the exact origin.

## 9.6 Rate limiting

Our app rate-limits the auth routes (`AUTH_RATE_LIMIT_MAX_REQUESTS=10` per 60 seconds) using a sliding
window. 🎓 **Why:** without it, an attacker can try passwords as fast as the network allows. A rate limit
turns an hours-long brute force into a years-long one. Login, signup, and password-reset endpoints should
*always* be limited. Responds with `429 Too Many Requests`.

You can also rate-limit at the proxy layer with Nginx's `limit_req_zone` — defence in depth.

## 9.7 What actually runs your Python: WSGI, ASGI, uvicorn

A confusing corner worth clearing up. Your Python code doesn't talk HTTP itself; a **server** does, and
they speak a standard interface:

- **WSGI** — the old, **synchronous** standard (Flask, classic Django). One request per worker at a time.
- **ASGI** — the modern, **asynchronous** standard (FastAPI, Starlette). One worker can juggle thousands
  of waiting requests — the same event-loop idea that made Nginx famous (§7.1).

**uvicorn** is an ASGI server: it accepts HTTP connections and calls your FastAPI app. In production you
often run **gunicorn** as a process manager supervising several uvicorn workers, so you use all CPU cores:

```bash
gunicorn app.main:app -k uvicorn.workers.UvicornWorker -w 4
```
🎓 We run a single `uvicorn` process — completely fine for 1–2 users. Reach for multiple workers when
CPU, not the database, becomes your bottleneck. (And note: with `-w 4` you get 4 processes, so anything
kept in a process's memory — like our in-memory rate limiter — stops being shared. That's the kind of
subtlety that makes people move such state into Redis.)

---

# 10. Databases in production

The database is the one part of your system that is **irreplaceable**. Servers, containers, images — all
disposable. The data is not. Everything below follows from that.

## 10.1 Migrations: version control for your schema

A **migration** is a small, versioned, ordered script that changes the database schema (`ALTER TABLE …`).
The tool (ours is **yoyo**) keeps a table in your database — `_yoyo_migration` — recording which have
already run, so it only applies new ones.

🎓 **Our setup applies them automatically on every container start** (`entrypoint.sh` runs `yoyo apply`
before launching uvicorn). This is the quiet hero of easy deploys: shipping a schema change requires no
extra step, and the schema can never drift from the code that expects it.

**The rules of migrations, learned the hard way by everybody:**
- **Never edit a migration that has already run** anywhere. Write a *new* one that corrects it. The
  applied set is history; you don't rewrite history.
- **Migrations should be forward-only and safe to re-run.** Additive changes (new nullable column, new
  table) are safe. Destructive ones (drop a column) deserve a two-step deploy: stop using it, ship, *then*
  drop it.
- **Beware of long locks.** Adding an index on a huge table can lock writes. Postgres offers
  `CREATE INDEX CONCURRENTLY` for this.

## 10.2 Connection pooling

Opening a database connection is expensive (TCP handshake, auth, backend process spawn). Postgres also
caps concurrent connections (`max_connections`, ~100 by default) — each one costs memory.

🎓 So apps keep a **pool**: a set of already-open connections, borrowed per request and returned. Our app
opens an `asyncpg` pool at startup and closes it at shutdown (that's the `lifespan` handler in
`main.py`). This is why the app boots *once* and reuses connections thousands of times.

Scaling note: if you ever run many app processes/servers, each keeps its own pool — and `4 servers × 20
connections` will exhaust Postgres. That's when people put **PgBouncer** in front of the database. (Same
receptionist idea as Nginx, one layer down.)

## 10.3 Backups & disaster recovery

We host Postgres ourselves in a container, which means **nobody backs it up for us.** Managed databases
(RDS) do this automatically; that convenience was the price we paid for being cheap. So we must do it.

**Two kinds of backup, and you want to know the difference:**
- **Logical** (`pg_dump`) — exports SQL/data. Portable across Postgres versions, restore selectively,
  slower for huge databases. **What we'll use.**
- **Physical** (EBS snapshot, `pg_basebackup`) — a block-level copy of the disk. Fast, whole-machine,
  but version-and-platform bound.

```bash
# take a compressed logical backup (run on the server)
docker compose exec -T db pg_dump -U recurring recurring | gzip > backup-$(date +%F).sql.gz

# restore it into a fresh database
gunzip -c backup-2026-07-08.sql.gz | docker compose exec -T db psql -U recurring recurring
```

🎓 **The 3-2-1 rule:** **3** copies of your data, on **2** different media, with **1** off-site. A backup
sitting on the same EBS volume as the database is not a backup — the disk dying takes both. That's why the
plan is `pg_dump` → **S3** (a different service, a different failure domain).

**Two acronyms that make you sound like you know what you're doing** — and genuinely clarify thinking:
- **RPO** (Recovery Point Objective) — *how much data can you afford to lose?* Nightly backups ⇒ RPO of
  24 hours. Continuous archiving (WAL shipping) ⇒ RPO of seconds.
- **RTO** (Recovery Time Objective) — *how long may restoring take?*

🎓 **And the rule everyone learns too late: a backup you have never restored is not a backup — it's a
hope.** Practice the restore. Once. On purpose. Before you need it.

## 10.4 A note on our DB's security posture

Postgres runs in a container on the same box, and its port **5432 is never published to the host or
opened in the firewall**. The app reaches it over Docker's private network by the service name `db`
(§6.7). That's why the default `recurring/recurring` password is survivable — nothing outside the machine
can even attempt a connection. It's still on the hardening list (§14), because defence in depth means not
relying on a single control.

---

# 11. The walkthrough: exactly what we did

Labels: **`[LAPTOP]`** = your own machine · **`[SERVER]`** = inside the SSH session.

### Step 1 — Rent the computer *(AWS console)*
EC2 → **Launch instance**. Name `recurring-api`. **AMI:** Ubuntu (free-tier eligible). **Type:**
`t3.micro` (free-tier eligible). Created **key pair** `recurring-key.pem` and downloaded it. Opened
ports **22** (SSH, from My IP), **80**, **443** (from anywhere). Storage 8 GB (default).
→ Running instance, public IP **`203.0.113.10`**, region `us-east-1`.

### Step 2 — Log in `[LAPTOP]`
```bash
chmod 400 ~/Downloads/recurring-key.pem
ssh -i ~/Downloads/recurring-key.pem ubuntu@203.0.113.10     # type "yes" at the fingerprint prompt
```
Prompt becomes `ubuntu@ip-172-31-21-120:~$` → you're on the server.

### Step 3 — Docker + the app `[SERVER]`
```bash
# A. swap file — overflow memory on a 1 GB box, so the Docker build can't get killed
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h

# B. install Docker, and let ubuntu run it without sudo
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
exit                                    # log out & back in so the group applies
# ...ssh back in...
docker --version && docker compose version

# C. get the code (public repo → no auth needed)
git clone https://github.com/kumar-gautam24/honest-ledger.git
cd honest-ledger/backend

# D. production settings — a REAL secret, not the example placeholder
cp .env.example .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 32)|" .env
sed -i "s|^ENV=.*|ENV=production|" .env
grep -E '^(ENV|JWT_SECRET)=' .env       # verify

# E. build & run in the background
docker compose up -d --build

# F. verify
docker compose ps
curl http://localhost:8000/health       # {"status":"ok"}            → the app is alive
curl http://localhost:8000/ready        # {"status":"ok","db":"up"}  → it reached Postgres
```
🎓 That `/ready` is the real milestone: **app + database + migrations, all live on a real server.**

### Step 3½ — The disk filled up
```bash
df -h /                    # 98% full!
docker system df           # Docker is the big eater
sudo du -h -d1 / | sort -hr | head

docker builder prune -f    # reclaim cache
sudo apt clean

# AWS console: EC2 → Volumes → Modify volume → 20 GiB (still free)
lsblk                              # drive is 20G, filesystem still ~7G
sudo growpart /dev/nvme0n1 1       # stretch the partition
sudo resize2fs /dev/nvme0n1p1      # stretch the filesystem
df -h /                            # ~19G 🎉
sudo apt --fix-broken install      # finish the interrupted kernel install
```

### Step 4 — Nginx reverse proxy `[SERVER]`
```bash
sudo apt install -y nginx

sudo tee /etc/nginx/sites-available/recurring > /dev/null <<'EOF'
server {
    listen 80;
    server_name 203-0-113-10.nip.io;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/recurring /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```
Test `[LAPTOP]`: `curl http://203-0-113-10.nip.io/health` → `{"status":"ok"}`
**The app is now reachable from anywhere on earth, by name.**

### Step 5 — HTTPS `[SERVER]`
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d 203-0-113-10.nip.io      # interactive: email, agree to ToS
```
Test `[LAPTOP]`: `https://203-0-113-10.nip.io/health` → 🔒 `{"status":"ok"}`

### Step 6 — Point the app at it `[LAPTOP]`
`lib/core/api/api_config.dart`:
```dart
static const String baseUrl = 'https://203-0-113-10.nip.io';   // was a temporary ngrok tunnel
```
🎓 It's a `const`, so hot-reload won't notice — do a full `flutter run`.

### Step 7 — Backups *(planned)*
We host our own Postgres, so nobody backs it up for us. Plan: nightly `pg_dump` → S3.

---

# 12. Deploying changes: Git, the automation ladder, CI/CD & IaC

🎓 **The thing beginners always miss: pushing to GitHub does *not* update your server.** The server has
its own copy of the code. Deploying is a deliberate, two-machine action:

```
[LAPTOP]  edit → git commit → git push
[SERVER]  cd honest-ledger/backend && git pull && docker compose up -d --build
```

Why this works cleanly:
- `git pull` brings the new code into the server's copy.
- `--build` rebuilds the image and swaps the running container for the new one.
- **Migrations run themselves** (`entrypoint.sh` → `yoyo apply` on every start).
- **`.env` is gitignored** — your production secrets are never overwritten by a pull, and never in the repo.

**Two rules:**
1. **Never edit code directly on the server.** A future `git pull` will conflict. The server only *receives*.
2. If nothing but an env var changed, plain `docker compose up -d` restarts without a full rebuild.

## 12.1 The Git model here

Three places hold the code, and it helps to see them as distinct:

```
   [LAPTOP]  ──git push──►  [GITHUB]  ──git pull──►  [SERVER]
   you edit                  the hub               a read-only consumer
```

The server is a **consumer**, never an author. Commands you'll use:
```bash
git clone <url>      # [SERVER] first time: get a copy
git pull             # [SERVER] fetch + merge the latest commits
git log --oneline -5 # what's actually deployed right now?
git status           # (on the server, should always be clean!)
```
🎓 If `git status` on the server is ever *dirty*, someone edited code there — the sin that causes pull
conflicts at the worst possible moment.

## 12.2 The automation ladder

- **Rung 1 (where we are):** SSH in, `git pull`, `docker compose up -d --build` by hand.
- **Rung 2:** a `deploy.sh` on the server so it's one command:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail                       # fail fast: any error aborts
  cd /home/ubuntu/honest-ledger/backend
  git pull
  docker compose up -d --build
  docker compose ps
  ```
- **Rung 3: CI/CD** — a robot does it on every push.

🎓 Climb it slowly. **Automate a thing only once doing it by hand feels boring** — that's precisely the
moment you understand it well enough to automate it *correctly*.

## 12.3 CI/CD: what it means

- **CI (Continuous Integration)** — on every push, automatically **build and test** the code. Catches
  breakage before it reaches anyone.
- **CD (Continuous Deployment/Delivery)** — if CI passes, automatically **ship it**.

A GitHub Actions workflow lives in `.github/workflows/deploy.yml` and, in the simplest form, SSHes to the
server and runs the deploy script:

```yaml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # (run your tests here first — that's the "CI" half)
      - name: Deploy over SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ubuntu
          key: ${{ secrets.SSH_PRIVATE_KEY }}     # stored in GitHub → Settings → Secrets
          script: |
            cd honest-ledger/backend
            git pull
            docker compose up -d --build
```

🎓 Two things to notice, because they're the real lessons:
1. **Secrets live in GitHub's encrypted secrets store**, never in the YAML. Same rule as §9.3.
2. There's a more grown-up variant: instead of building *on* the server (slow, and a failed build takes
   your site down mid-deploy), CI **builds the image, pushes it to a registry** (Docker Hub / AWS ECR),
   and the server merely pulls the finished image. Faster, safer, and lets you roll back by pulling the
   previous tag.

## 12.4 Infrastructure as Code (the next horizon)

Everything we did in the AWS console — launch the instance, open ports, resize the volume — was
**clicking**. That's fine once. It's terrible when you need to recreate it, or explain what exists, or
recover from a mistake.

**Infrastructure as Code (IaC)** means describing your infrastructure in a file, version-controlled like
any other code, and letting a tool make reality match it:

```hcl
# Terraform, roughly — this is what our clicking would have looked like
resource "aws_instance" "recurring_api" {
  ami           = "ami-xxxxxxxx"
  instance_type = "t3.micro"
  key_name      = "recurring-key"
  vpc_security_group_ids = [aws_security_group.web.id]
}
```

🎓 The magic word is **idempotent** (there it is again, §9.1): running it twice doesn't create two
servers — it converges reality onto the description. Your whole server becomes reviewable, diffable,
and rebuildable from scratch. Tools: **Terraform** (multi-cloud, the standard), **OpenTofu** (its open
fork), **CloudFormation** (AWS-native), **Pulumi** (real programming languages), **Ansible** (configures
*inside* servers rather than creating them).

Not needed for one hand-made box. Essential the moment you have three.

---

# 13. When things break

## The mindset

> 🎓 **Get evidence from the running system before you trust any theory — including your own.**

Twice during this deploy a confident, sensible theory was flat wrong, and the data corrected it in
seconds. Your evidence tools: `docker compose logs`, `docker compose exec`, `curl -i`, `df -h`, `du`,
`lsblk`, `nginx -T`.

**Look first. Theorize second. Change things third.**

## Bug #1 — the endpoint that "didn't exist" (but did)

`/health` returned `200`, but its twin `/ready` returned `{"detail":"Not Found"}` — despite both being
defined side by side in the code.

The tempting theory: *"the container is running stale code."* Completely wrong.

```bash
docker compose exec api grep -n '@app.get' app/main.py
# → BOTH routes present. Code is fine.

docker compose logs api
# → "GET /hecalhost%3A8000/ready HTTP/1.1" 404 Not Found
```
Look at that path. The **terminal had mangled a pasted multi-line command** — the URL got mashed into
the request path. `curl` asked for a route that genuinely doesn't exist. The app was never broken.

**Lessons:** evidence beats intuition; and **paste one line at a time** in this terminal.

## Bug #2 — "No space left on device"

An `apt install` died mid-way spraying `No space left on device`. It looked like an Nginx problem. It
wasn't — the disk was 98% full.

```bash
df -h /                    # → 98%, 193 MB free
docker system df           # → 877 MB images + 358 MB build cache
du -sh ~/honest-ledger     # → 5.5 MB (we suspected the repo; evidence cleared it)
sudo du -h -d1 / | sort -hr | head   # → /usr 2.5G, /var 2.1G (Docker), /snap 625M
```

**Cause:** an 8 GB disk is too small for Docker. The bare OS already used ~2 GB (visible in the very
first SSH login banner: *"Usage of /: 30.5%"*), and Docker's images + cache + a queued kernel upgrade
ate the rest.

**Fix:** grow the volume 8 → 20 GB — remembering the **two layers** (`growpart` then `resize2fs`).

## The pitfall checklist

**AWS**
- Wrong **region** → "my server vanished." Check the dropdown, top-right.
- **Lost `.pem`** → no reset, no recovery. Back it up.
- **Public IP changed** after stop→start → use an **Elastic IP**.
- 💰 Only launch *free-tier eligible* sizes; keep EBS ≤ 30 GB; check the Billing dashboard.

**Terminal / Linux**
- **Paste garble** — one line at a time.
- **`sudo echo > /etc/file` fails** — the `>` runs as *you*. Use `sudo tee`.
- **`Ctrl-C` on `logs -f`** stops watching, not the app.
- **`usermod -aG docker`** needs a fresh login before it takes effect.

**Nginx**
- Always `sudo nginx -t` **before** `reload`.
- Use `reload` (graceful), not `restart`, for config changes.
- Remove the **default site** or it can shadow yours.

**Certbot / HTTPS**
- Port 80 must be open and `server_name` correct — the ACME challenge rides on it.
- Verify auto-renew: `systemctl list-timers | grep certbot`. Test with `certbot renew --dry-run`.
- Don't re-issue certs in a loop — rate limits.

**Docker**
- **Never edit code inside a container** — wiped on rebuild.
- **`down -v` destroys your database.** Plain `down` keeps it.
- Build cache grows — `docker builder prune -f`.
- `EXPOSE` documents a port; it does **not** publish it.

**App / deploy**
- Never edit code on the server — pull conflicts.
- `.env` lives only on the server (gitignored) — set it up fresh on each new server.
- A Dart `const` needs a **full restart**, not hot-reload.

---

# 14. Production hardening & security

We built something that *works*. Making it something you'd trust with strangers' money is a different bar.
Here's the honest gap, in priority order. **Security is layers** — no single control is the answer.

## 14.1 Our current posture (the honest audit)

✅ **What we got right:** the firewall denies by default; SSH is key-only and locked to one IP; the
database isn't reachable from the internet; HTTPS is enforced; the JWT secret is real and random;
production mode hides the API docs.

⚠️ **What's still soft:**

| Gap | Risk | Fix |
|-----|------|-----|
| Container runs as **root** | A code-execution bug gets root inside the container | Add a `USER` to the Dockerfile |
| App port bound to `0.0.0.0:8000` | Only the AWS firewall protects it | Bind `127.0.0.1:8000:8000` |
| Default DB password | Defence-in-depth failure if anything else slips | Rotate it |
| No automatic OS security patches | Known vulnerabilities linger | `unattended-upgrades` |
| No brute-force protection on SSH | Endless login attempts | `fail2ban` (and we already limit by IP) |
| No backups | **Total data loss** on disk failure | §10.3 — do this first |

## 14.2 Harden the server

**Automatic security updates** — the single highest-value, lowest-effort thing:
```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

**SSH hardening** — in `/etc/ssh/sshd_config`, then `sudo systemctl restart ssh`:
```
PasswordAuthentication no      # keys only — passwords can be guessed
PermitRootLogin no             # never log in directly as root
```
🎓 Both are usually the default on AWS Ubuntu images, but *verify* rather than assume.

**fail2ban** — watches auth logs and temporarily bans IPs that fail repeatedly:
```bash
sudo apt install -y fail2ban
```

**The principle of least privilege**, everywhere: your login user isn't root (you `sudo` deliberately);
your app shouldn't run as root; when the server later reads S3 for backups, give it an **IAM role** scoped
to *one bucket*, not your account keys.

## 14.3 Harden the container

Our `Dockerfile` builds as — and runs as — **root**. That's the norm in tutorials and a bad habit in
production: if an attacker achieves code execution in your app, they're root inside the container, which
is one kernel bug away from root on the host.

```dockerfile
# after installing dependencies:
RUN useradd --create-home --uid 1000 appuser
USER appuser                     # everything after this runs unprivileged
CMD ["bash", "entrypoint.sh"]
```

Other container practices worth adopting:
- **Multi-stage builds** — compile/install in a fat "builder" stage, copy only the finished artifacts into
  a slim runtime image. Smaller images = faster deploys, less to attack.
  ```dockerfile
  FROM python:3.12 AS builder
  RUN uv sync --frozen --no-dev            # heavy build tools live here
  FROM python:3.12-slim                    # ← final image, no build tools
  COPY --from=builder /app/.venv /app/.venv
  ```
- **Pin your base image** (`python:3.12-slim`, ideally by digest) so a rebuild doesn't silently change the OS.
- **Never bake secrets into layers** — they persist even if a later layer deletes the file.
- **Scan images** for known vulnerabilities: `docker scout cves <image>`, or Trivy.
- **`restart: unless-stopped`** in compose, so containers come back after a server reboot. (Right now, a
  reboot leaves your app down until you SSH in — a real gap.)
- **Set resource limits** so one runaway container can't starve the box (`mem_limit`, `cpus`).

## 14.4 Harden the edge (Nginx)

Certbot already added the HTTP→HTTPS redirect. Two more worth adding:

```nginx
# tell browsers: only ever talk to me over HTTPS, for the next 2 years
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Content-Type-Options "nosniff" always;
server_tokens off;                 # stop advertising your exact nginx version
client_max_body_size 10M;          # don't let anyone upload a 4 GB request
```
🎓 **HSTS** (`Strict-Transport-Security`) is powerful and slightly dangerous: once a browser sees it, it
*refuses* plain HTTP to your domain for `max-age` seconds. Wonderful protection, hard to undo — turn it on
only when you're sure HTTPS works.

## 14.5 Protect your wallet 💰

Security includes not waking up to a $400 bill:
- **AWS Budgets** → set a budget of, say, $5/month with an email alert. Do this *today*; it takes 2 minutes.
- **Billing alarm** in CloudWatch for the same.
- Only launch **free-tier eligible** instance sizes; keep EBS ≤ 30 GB.
- **Delete what you stop using.** An idle EBS volume or Elastic IP not attached to a running instance still
  costs money.

---

# 15. Observability: logs, metrics, alerts

🎓 **You cannot operate what you cannot see.** Right now, the only way you'd learn your app is down is by
opening it and noticing. That's not a system; that's luck. Observability is conventionally three pillars:

| Pillar | Answers | Our status |
|--------|---------|-----------|
| **Logs** | *What happened?* (discrete events) | ✅ we have them (`docker compose logs`) |
| **Metrics** | *How much / how often?* (numbers over time) | ❌ none |
| **Traces** | *Where did the time go?* (one request across services) | ❌ none (and unnecessary for one service) |

## 15.1 Logs

Your app uses **structlog** and emits **structured JSON logs** — notice how each line is a parseable
object with `event`, `request_id`, `duration_ms`:

```json
{"method":"GET","path":"/ready","status_code":200,"duration_ms":38.53,
 "event":"http.request","request_id":"16a71b542cc9","level":"info"}
```

🎓 **Why structured logs beat prose.** `print("user 5 logged in")` is unsearchable at scale. A JSON object
can be filtered, counted, and graphed: *"show me all 5xx responses on `/v1/borrowings` in the last hour."*
And that **`request_id`** lets you follow a single request through every log line it produced — the poor
man's tracing, and genuinely invaluable during an incident.

**Log levels** exist so you can turn the volume up during a problem: `DEBUG` (development noise) → `INFO`
(normal events) → `WARNING` (odd but handled) → `ERROR` (something failed). Ours is `INFO` via `LOG_LEVEL`.

**12-factor rule (§9.3): apps log to stdout, never to files.** The platform captures the stream. That's why
`docker compose logs` just works.

⚠️ **Log rotation.** Docker's default JSON log driver grows **forever** — another way to fill a disk. Cap it:
```yaml
services:
  api:
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "3" }
```

## 15.2 Metrics & alerting

The minimum viable version, in ascending effort:

1. **An uptime pinger** (free: UptimeRobot, Better Stack, Healthchecks.io). Hit `/health` every 5 minutes;
   email you when it fails. 🎓 *If you do exactly one thing from this section, do this one.* It's five
   minutes of setup and it's the difference between "I found out" and "my user told me."
2. **CloudWatch** — AWS collects CPU/network/disk for free. Add an alarm: *"CPU > 80% for 10 minutes"* or
   *"disk > 85%"* (which would have warned us before §13's Bug #2).
3. **Prometheus + Grafana** — the real thing: your app exposes a `/metrics` endpoint, Prometheus scrapes it,
   Grafana graphs it. Overkill for one box; the standard everywhere else.

🎓 **What makes a good alert:** it's *actionable* and it's *rare*. An alert nobody acts on trains you to
ignore alerts — and then you'll ignore the one that mattered. Alert on **symptoms users feel** (the site is
down, errors are up, it's slow), not on every twitchy internal number.

---

# 16. Scaling & zero-downtime deploys

Not because you need it now — you don't, with 1–2 users — but because understanding *how* you'd grow tells
you which decisions today would hurt later.

## 16.1 Vertical vs horizontal

- **Vertical scaling** — a bigger box (`t3.micro` → `t3.large`). Trivially easy: stop, change instance
  type, start. No architecture change. But there's a ceiling, and it's a single point of failure.
- **Horizontal scaling** — *more* boxes behind a load balancer. Effectively unlimited, survives one machine
  dying — but only works if your app is **stateless**.

🎓 **"Stateless" is the property that decides your future.** It means the server keeps nothing in memory
that a *later* request depends on — any request can go to any server. Good news: **this app already is.**
Auth uses JWTs (the token carries the identity; no server-side session), and all real state lives in
Postgres.

Two things would break under horizontal scaling, and they're instructive:
- The **in-memory rate limiter** (§9.6) — each server would count separately. Fix: move the counter to Redis.
- The **database** becomes the shared bottleneck — every app server pools connections to it (§10.2).

**The order you'd actually do it:** scale vertically until it hurts (it goes a long way), then extract state,
then go horizontal. Not the reverse.

## 16.2 Zero-downtime deploys

Be honest about what we have: `docker compose up -d --build` **stops the old container and starts a new one.**
For a few seconds, requests get `502 Bad Gateway` (§9.1 — and now you know exactly why). With 1–2 users, at
midnight, nobody notices. At scale, that's an outage every deploy.

The strategies, in ascending sophistication:

- **Rolling deploy** — run N copies; replace them one at a time, so some are always serving.
- **Blue-green** — run two complete environments ("blue" live, "green" new). Deploy to green, test it, then
  flip the proxy to point at green. Instant rollback: flip back. 🎓 With Nginx this is literally changing one
  `proxy_pass` and reloading — the graceful `reload` you already learned (§7.5) drops zero connections.
- **Canary** — send 5% of traffic to the new version, watch the error rate, then ramp up.

All three need the same prerequisite: **more than one copy of your app**, which needs statelessness. It all
comes back to the same property.

🎓 And the deploy safety net that matters more than any of them: **be able to roll back.** Which is the real
argument for CI building versioned images (§12.3) — `docker compose up` with the previous tag is a rollback
you can perform in ten seconds at 3am. "Rebuild from an older git commit" is not.

---

# 17. Where to go next

Deliberate "good enough for now" calls, written down so they're not forgotten — **in the order I'd
actually do them**, because priority is the whole point of a roadmap.

### Do these next (real risk, small effort)
1. **Nightly `pg_dump` → S3.** We host our own database, so nobody backs it up. One disk failure = total
   loss of users' financial data. This is not optional. *(Learn: S3, IAM roles, cron/systemd timers.)* → §10.3
2. **A free uptime monitor** hitting `/health`. Five minutes of setup; the difference between finding out
   yourself and hearing it from a user. → §15.2
3. **An AWS budget alert** at ~$5/month. Two minutes. Protects you from a surprise bill. → §14.5
4. **`restart: unless-stopped`** on the compose services — right now a server reboot leaves your app down
   until you notice. → §14.3
5. **Docker log rotation** (`max-size`) — otherwise logs quietly refill the disk you just grew. → §15.1

### Then these (hardening & hygiene)
6. **Run the container as a non-root user.** → §14.3
7. **Bind the app to `127.0.0.1:8000:8000`** so only Nginx can reach it, firewall or not. → §6.5
8. **Rotate the default DB password.** → §14.1
9. **`unattended-upgrades`** for automatic security patches. → §14.2
10. **Elastic IP** to pin the public address (and stop your nip.io URL from changing). → §2.1
11. **A real domain** instead of nip.io — and re-run Certbot for it. → §3.3

### Then these (developer experience)
12. **`--dart-define`** for the app's base URL, so dev points at `localhost` and prod at the server
    without hardcoding.
13. **A `deploy.sh`**, then **CI/CD with GitHub Actions**. → §12.2–12.3
14. **Build images in CI and push to a registry**, so deploys are fast and rollback is one command. → §12.3

### The bigger horizons (when you genuinely need them)
Managed databases (**RDS**) once backups-by-hand annoy you · **load balancers + multiple servers** once one
box isn't enough (you're already stateless, §16.1) · **Redis** to move the rate limiter out of process
memory · **container orchestration** (ECS, Kubernetes) at real scale · **Infrastructure as Code**
(Terraform) so your whole server is a reviewable, rebuildable file (§12.4) · **Prometheus + Grafana** for
real metrics.

🎓 **The meta-lesson:** notice that the highest-priority items are all *boring* — backups, monitoring, a
budget alert, restart policies. Nobody's blog post is about those. They are, nevertheless, what separates a
system that survives from a demo that happened to work. Do the boring things first.

---

# 18. Appendix: command reference & glossary

## SSH & files `[LAPTOP]`
```bash
chmod 400 ~/key.pem                              # lock the key (SSH demands it)
ssh -i ~/key.pem ubuntu@203.0.113.10             # -i = identity file
scp -i ~/key.pem localfile ubuntu@HOST:/path/    # copy a file to the server
exit                                             # leave the server
```

## Packages & system `[SERVER]`
```bash
sudo apt update                  # refresh package catalogue
sudo apt install -y <pkg>        # install
sudo apt clean                   # clear downloaded .deb cache
sudo apt --fix-broken install    # repair an interrupted install
systemctl status|reload|restart|enable <svc>
systemctl list-timers            # scheduled jobs (certbot renewals)
free -h                          # RAM + swap
```

## Disk `[SERVER]`
```bash
df -h /                                          # filesystem fullness (Use%)
du -sh <dir>                                     # size of one folder
sudo du -h -d1 / 2>/dev/null | sort -hr | head   # biggest folders — "why is my disk full"
lsblk                                            # disks & partitions & sizes
sudo growpart /dev/nvme0n1 1                     # grow the partition
sudo resize2fs /dev/nvme0n1p1                    # grow the filesystem
```

## Docker `[SERVER]`
```bash
curl -fsSL https://get.docker.com | sudo sh      # install
sudo usermod -aG docker $USER                    # run without sudo (re-login after)
docker compose up -d --build                     # build + start detached
docker compose ps                                # status
docker compose logs -f api                       # follow logs
docker compose exec api bash                     # shell inside the container
docker compose down                              # stop & remove (data kept)
docker compose down -v                           # ⚠️ also delete volumes (data destroyed)
docker system df                                 # Docker's disk usage
docker builder prune -f                          # reclaim build cache
```

## Nginx `[SERVER]`
```bash
sudo nginx -t                                    # test config (ALWAYS before reload)
sudo nginx -T                                    # dump full merged config
sudo systemctl reload nginx                      # graceful apply
sudo tail -f /var/log/nginx/error.log            # what's failing
```

## Certbot `[SERVER]`
```bash
sudo certbot --nginx -d <domain>                 # get + install cert, edit nginx
sudo certbot certificates                        # what do I have, when does it expire
sudo certbot renew --dry-run                     # safe renewal test
systemctl list-timers | grep certbot             # is auto-renew armed?
```

## Git
```bash
git clone <url>                                  # [SERVER] first copy
git pull                                         # [SERVER] fetch the latest to deploy
git log --oneline -5                             # what's actually deployed?
git status                                       # on the server this should ALWAYS be clean
```

## Database `[SERVER]`
```bash
docker compose exec db psql -U recurring recurring        # an interactive SQL shell
docker compose exec -T db pg_dump -U recurring recurring | gzip > backup-$(date +%F).sql.gz
gunzip -c backup.sql.gz | docker compose exec -T db psql -U recurring recurring   # restore
```

## Health checks & curl
```bash
curl http://localhost:8000/health                # liveness: is the process up?
curl http://localhost:8000/ready                 # readiness: can it reach the DB?
curl -i https://203-0-113-10.nip.io/health       # -i shows status code + headers
curl -v URL                                      # verbose: whole conversation + TLS handshake
curl -H 'Authorization: Bearer TOKEN' URL        # send an auth header
curl -X POST -H 'Content-Type: application/json' -d '{"a":1}' URL
curl --max-time 5 URL                            # give up after 5s (proves a port is blocked)
```

## Status codes worth memorising
| Code | Means | In our stack, usually |
|------|-------|----------------------|
| `200` / `201` | OK / Created | ✅ |
| `301` | permanent redirect | Certbot's HTTP→HTTPS |
| `401` / `403` | not authenticated / not allowed | bad or missing token |
| `404` | not found | **Nginx's HTML page** = never reached your app. **Your app's JSON** = no such route |
| `422` | validation failed | bad request body |
| `429` | too many requests | rate limiter tripped |
| `500` | unhandled crash | check `docker compose logs api` |
| **`502`** | **bad gateway** | **Nginx is up, your app isn't.** `docker compose ps` |
| **`504`** | **gateway timeout** | app reached, but too slow to answer |

## Flag glossary
| Flag | Means |
|------|-------|
| `-i` (ssh) | **i**dentity file (the key) |
| `-i` (curl) | **i**nclude response headers |
| `-i` (sed) | **i**n-place edit |
| `-d` (docker) | **d**etached (background) |
| `-f` (logs, tail) | **f**ollow |
| `-f` (prune, rm) | **f**orce (no prompt) |
| `-h` (df, du, free) | **h**uman-readable sizes |
| `-y` (apt) | assume **y**es |
| `-s` (ln) | **s**ymbolic link |
| `-r` (sort) | **r**everse (biggest first) |
| `-t` (nginx) | **t**est config |
| `-v` (compose down) | ⚠️ also remove **v**olumes |

## Glossary
| Term | Meaning |
|------|---------|
| **ACME** | The protocol Let's Encrypt uses to verify domain ownership |
| **AMI** | Amazon Machine Image — the OS template an instance boots from |
| **ASGI / WSGI** | The async / sync interface between a Python web app and its server |
| **AZ** | Availability Zone — one data center within a region |
| **Bind mount** | Mapping a host folder into a container (great for dev) |
| **Blue-green** | Two full environments; deploy to the idle one, then flip traffic |
| **Canary** | Send a small % of traffic to a new version before ramping up |
| **cgroups** | Linux feature limiting a process group's resources |
| **CI/CD** | Automatically build+test (CI) and ship (CD) on every push |
| **Connection pool** | Reused open DB connections, because opening one is expensive |
| **Container** | A running instance of an image |
| **CORS** | A *browser* rule about which origins may read your API's responses |
| **Daemon** | A long-running background service |
| **EBS** | Elastic Block Store — a virtual hard drive |
| **EC2** | Elastic Compute Cloud — rentable virtual computers |
| **HSTS** | A header telling browsers "only ever use HTTPS for me" |
| **IaC** | Infrastructure as Code — your servers described in a version-controlled file |
| **Idempotent** | Doing it twice has the same effect as doing it once |
| **Image** | A frozen template of an app + its environment |
| **JWT** | A signed token carrying identity. Readable by anyone; forgeable by no one |
| **Liveness** | "Is the process alive?" → if not, restart it |
| **Migration** | A versioned, ordered script that changes the DB schema |
| **Namespaces** | Linux feature giving a process its own view of the system |
| **NAT** | Sharing one public IP across many private devices |
| **Readiness** | "Can it serve traffic right now?" → if not, stop routing to it |
| **Reverse proxy** | A server that fronts your app and forwards requests to it |
| **RPO / RTO** | How much data you can lose / how long recovery may take |
| **Security Group** | AWS's stateful, instance-level firewall |
| **Stateless** | The server keeps nothing in memory a later request depends on |
| **Symlink** | A shortcut file pointing at another file |
| **Swap** | Disk used as overflow RAM |
| **TLS** | The encryption behind HTTPS |
| **TTL** | How long a DNS answer may be cached |
| **Volume** | Docker-managed persistent storage outside a container |
| **VPC** | Your private network inside AWS |
| **12-factor** | A methodology: config in env, logs to stdout, disposable processes |

---

*Written while actually doing it — including the two bugs, the disk that filled up, and the theories that
turned out to be wrong. That's the honest version, and it's the useful one.*
