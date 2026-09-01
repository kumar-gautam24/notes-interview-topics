# Deploying a backend to a real server — a beginner's course

These are **learning notes**, not a reference manual. The goal isn't just to list the commands —
it's for you (or anyone) to *understand* what a deployment actually is, so you could do it again
from memory and know why every piece is there.

We're going to take a FastAPI + Postgres backend that runs on a laptop and put it on a real
computer on the internet, reachable securely from a phone. That's it. Everything else is detail.

> **What we're deploying:** just the backend (the API + its database). The Flutter app only gets
> pointed at the finished web address at the very end.

## How to read this

> ### 📘 Want it all in one place? → **[complete-guide.md](complete-guide.md)**
> That's the single master document: every concept, command, and example — plus a lot the rest of these
> files don't cover (HTTP status codes, health checks, secrets, JWTs, CORS, database migrations & backups,
> Docker volumes vs bind mounts, container networking, Nginx's full feature set, server hardening,
> observability, scaling, CI/CD, Infrastructure as Code). If you read only one file, read that one.

The files below are the same material, split into smaller pieces. Read them in this order:

1. **README.md** (you're here) — the big idea, then the whole story start to finish.
2. **[concepts.md](concepts.md)** — the ideas, taught one at a time. The heart of the learning.
3. **[docker.md](docker.md)** — Docker, explained properly, because it does the heavy lifting.
4. **[troubleshooting.md](troubleshooting.md)** — the two real bugs we hit and how we thought through them. Honestly the most useful file.
5. **[commands.md](commands.md)** — the quick-reference to come back to *after* you understand things.

---

## The one idea that makes everything click

Before any commands, hold this picture in your head. **A deployment is just a delivery route for
one request.** Someone taps a button in the app, and that tap has to travel all the way to your
code and back. Every single thing we set up — the server, the firewall, Nginx, the certificate —
is one stop on that route.

```
  📱 The phone taps "record payment"
     │   it sends a request to  https://203-0-113-10.nip.io/...
     ▼
  ① DNS  — looks up the name, gets back an address
     │    "203-0-113-10.nip.io lives at 203.0.113.10"
     ▼
  🌍 The internet carries the request to that address
     ▼
  ┌──────────────────────────────────────────────────────────┐
  │  ② The server (a rented computer at 203.0.113.10)         │
  │                                                            │
  │   ③ The firewall checks: is this door (port 443) open? ✅  │
  │      ▼                                                      │
  │   ④ Nginx answers the door. It handles the security        │
  │      (HTTPS), then passes the request inward...            │
  │      ▼                                                      │
  │   ⑤ ...to your app, running in a container on port 8000    │
  │      ▼                                                      │
  │   🐘 which talks to Postgres (the database) and answers    │
  └──────────────────────────────────────────────────────────┘
     │
     ▼   ...and the answer travels all the way back to the phone.
```

If you understand *that journey*, you understand the deployment. When something breaks, you'll ask
"which stop on the route failed?" — and that question alone solves most problems.

🎓 **Notice what's NOT here: a load balancer.** People mention them constantly, so you might think
you need one. You don't. A load balancer spreads traffic across *many* servers — it solves a
problem you only have with lots of users. We have one server and 1–2 users. Building one now would
be like installing traffic lights on your driveway. Learn it the day you actually feel the traffic.

---

## Why we made the choices we made

Deployment isn't one decision, it's a handful, and each has cheaper/fancier alternatives. Here's
what we picked and the honest reasoning — because *understanding the trade-off* is more useful than
the answer:

- **A single rented computer (AWS EC2), not a fancy managed platform.** It's the classic beginner
  path, it's basically free, and — most importantly — it makes you touch the real fundamentals
  (a server, a firewall, SSH). Managed platforms (App Runner, Lightsail) hide all of that, which is
  worse when you're trying to *learn*. You can always graduate later.

- **The smallest, free server (`t3.micro`).** For 1–2 users, a tiny box runs the app *and* the
  database with room to spare. Paying for more would be paying for machinery nobody's using.

- **Nginx as the "front desk," not Caddy.** Caddy is easier (it does HTTPS automatically), but the
  user's team uses Nginx — and matching the tools you'll see at work beats a shortcut. Bonus: Nginx
  makes you learn certificates properly, which is a real skill.

- **A free web name (nip.io), not a bought domain.** `203-0-113-10.nip.io` is a free trick: it turns
  any IP address into a usable name instantly. Perfect for learning; swap in a real domain later.

- **The database in a container on the same box, not a managed database.** Cheapest, and it matches
  how the app already runs locally. The trade-off (which we're honest about): no automatic backups,
  so we plan to add our own.

There's a full comparison table in [concepts.md](concepts.md) if you want the alternatives spelled out.

---

## The whole story, start to finish

Below is *exactly* what we did, in order, with the reasoning kept short (the deep explanations live
in the other files). Two labels tell you where each command runs:
**`[LAPTOP]`** = your own machine · **`[SERVER]`** = inside the remote server (after you SSH in).

### Step 1 — Rent the computer *(AWS website)*
In the EC2 console we launched an instance: named it `recurring-api`, chose **Ubuntu** as the
operating system and **`t3.micro`** as the size (both marked "free-tier eligible" so we don't get
charged). We created a **key pair** (`recurring-key.pem`) and downloaded it — *this file is the only
way to log in, so losing it means losing the server.* We opened three "doors" (ports): **22** for
logging in, **80** and **443** for web traffic. Result: a running computer with the public address
**`203.0.113.10`**.

> 🎓 *New ideas here:* a server, an operating system image, a key pair, ports/firewall. All explained
> in [concepts.md](concepts.md).

### Step 2 — Log into it `[LAPTOP]`
```bash
chmod 400 ~/Downloads/recurring-key.pem     # lock the key file, or SSH won't trust it
ssh -i ~/Downloads/recurring-key.pem ubuntu@203.0.113.10
```
🎓 **SSH** is a secure remote terminal — you type on your laptop, the commands run on the server.
When the prompt changed to `ubuntu@ip-...`, we were officially *inside the server*.

### Step 3 — Install Docker and start the app `[SERVER]`
First a safety net, because the box only has 1 GB of memory:
```bash
# make 2 GB of "swap" — overflow memory, so a heavy build doesn't crash the box
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```
Then install Docker (the tool that runs our app in a neat, self-contained box):
```bash
curl -fsSL https://get.docker.com | sudo sh      # install
sudo usermod -aG docker $USER                    # let us run it without "sudo"
exit                                             # log out & back in so that takes effect
```
Get the code and start everything:
```bash
git clone https://github.com/kumar-gautam24/honest-ledger.git
cd honest-ledger/backend

# make a production settings file with a REAL secret key (not the example placeholder)
cp .env.example .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 32)|" .env
sed -i "s|^ENV=.*|ENV=production|" .env

docker compose up -d --build                     # build & run in the background
```
And check it's alive:
```bash
curl http://localhost:8000/health     # → {"status":"ok"}          the app is up
curl http://localhost:8000/ready      # → {"status":"ok","db":"up"} it reached the database
```
🎓 That second one is the real milestone: **app + database + migrations, all running on a real
server.** Docker is explained in [docker.md](docker.md).

### Step 3½ — The disk filled up (a real detour)
Mid-way, the server ran out of disk space (`No space left on device`). This is a *great* thing to
have happened, because it's incredibly common. The short version: an 8 GB disk is too small for
Docker. We diagnosed it (`df -h`, `du`), freed some space, then **grew the disk from 8 GB to 20 GB**
— which is two steps because the "drive" and the "formatting on the drive" are separate layers:
```bash
# (after enlarging the volume to 20 GB in the AWS console)
sudo growpart /dev/nvme0n1 1      # stretch the partition to fill the bigger drive
sudo resize2fs /dev/nvme0n1p1     # stretch the filesystem to fill the bigger partition
```
The full story, and how we figured it out, is in [troubleshooting.md](troubleshooting.md) — worth reading.

### Step 4 — Put Nginx at the front door `[SERVER]`
Right now the app answers on port 8000, but the firewall only lets the world in on 80 and 443. So we
install **Nginx** to sit on port 80 and forward requests inward to the app:
```bash
sudo apt install -y nginx
```
We wrote a small config telling Nginx "for this web name, forward everything to the app on 8000,"
turned it on, checked it for typos, and applied it:
```bash
sudo nginx -t                    # test the config first — always
sudo systemctl reload nginx      # apply it with zero downtime
```
🎓 Nginx is a **reverse proxy** — a receptionist that takes public requests and passes them to the
right program inside. (Exact config in the [walkthrough below](#the-nginx-config-in-full) and concepts.)

Then from the laptop: `curl http://203-0-113-10.nip.io/health` → `{"status":"ok"}`. **The app was
now reachable from anywhere on earth, by name.**

### Step 5 — Add the padlock (HTTPS) `[SERVER]`
Plain HTTP is readable by anyone in between — unacceptable for a finance app. So we got a free
security certificate with **Certbot**:
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d 203-0-113-10.nip.io
```
🎓 Certbot proved we control the name, fetched a free certificate from **Let's Encrypt**, and edited
Nginx to use HTTPS on port 443 (plus auto-renews it forever). Now `https://203-0-113-10.nip.io` loads
with a 🔒. **The backend is live and secure.**

### Step 6 — Point the app at it `[LAPTOP]`
One line in `lib/core/api/api_config.dart`:
```dart
static const String baseUrl = 'https://203-0-113-10.nip.io';   // was a temporary ngrok tunnel
```
That's the single address the whole app uses to find the backend.

### Step 7 — Backups *(planned)*
Because we host our own database, nobody backs it up for us. So: a nightly copy of the database
saved to cheap cloud storage (S3). Not done yet — it's the last piece.

---

## How you'll deploy a change *later* (this surprises everyone)

Pushing code to GitHub does **not** update your server. The server has its *own copy*. So deploying
an update is a deliberate, two-machine action:

```
[LAPTOP]  edit code → git commit → git push
[SERVER]  cd honest-ledger/backend → git pull → docker compose up -d --build
```

🎓 The database migrations run themselves on restart (built into the app's startup), and your secret
`.env` file is never touched. **The one rule:** never edit code directly on the server — always edit
on your laptop, push, then pull. The server only *receives*.

Later you can automate this (a one-line script, then a robot that does it on every push). But do it by
hand first — you can't automate what you don't understand yet.

---

## The Nginx config, in full

For reference, the exact file we wrote to `/etc/nginx/sites-available/recurring` (line-by-line
explanation in [concepts.md](concepts.md#reverse-proxy-nginx)):

```nginx
server {
    listen 80;                                # answer on the public HTTP door
    server_name 203-0-113-10.nip.io;          # ...only for our web name

    location / {                              # for every path:
        proxy_pass http://localhost:8000;     # ⭐ forward it to the app
        proxy_set_header Host $host;                          # pass along who was really asked for
        proxy_set_header X-Real-IP $remote_addr;              # ...the visitor's real IP
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;           # ...http or https
    }
}
```
(Certbot later added the `listen 443 ssl` half automatically.)
