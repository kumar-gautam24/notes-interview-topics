# The concepts, taught one at a time

This is the "sit down and understand it" file. Each idea is built from scratch with a plain-language
analogy first, then the technical reality. Read it top to bottom — the ideas stack.

We'll go in the order a request travels: **the network → the server → the operating system →
security**.

---

# Part 1 — The network (how a request finds your app)

## IP addresses: every computer's phone number

Imagine the internet as an enormous city where every building has a unique number. That number is an
**IP address** — ours is `203.0.113.10`. When your phone wants to reach your server, it needs this
number, the same way a letter needs a street address.

There are two flavours, and the difference trips people up:
- A **public IP** is visible from the whole internet. Our server has one so the world can reach it.
- A **private IP** only works *inside* a private network — like a room number that means nothing
  outside the building. Our server also had `172.31.21.120`; we ignore it entirely.

🎓 **The gotcha to remember:** the free public IP is "auto-assigned," which means it can *change* if
you fully stop and restart the server (a plain reboot is fine). If you need it to never change, AWS
lets you attach a permanent one called an **Elastic IP**.

## DNS: the internet's phone book

Nobody wants to type `203.0.113.10` into an app, and numbers change. So the internet has a phone
book that maps **names** to **numbers**. That's **DNS** (Domain Name System). You look up a name like
`203-0-113-10.nip.io`, and DNS hands back `203.0.113.10`.

We used a clever free service called **nip.io**. Its whole trick: any address of the form
`203-0-113-10.nip.io` automatically resolves to `203.0.113.10` — the IP is baked right into the name.
No signup, no waiting, and it gives us a real *name*, which we need because security certificates
won't be issued for a bare number.

> **Alternatives:** buy a real domain (~$10/year) and add an "A record" pointing the name at your IP;
> or use managed DNS like Route 53 or Cloudflare. nip.io is the zero-effort learning option.

## Ports: many doors on one address

Here's a puzzle: one server runs several programs (a web app, a database…), but it has only one IP
address. How does a request reach the *right* program? **Ports.** Think of the IP as a building and
ports as **numbered doors** on it. Each program waits behind its own door:

| Door (port) | Who waits there |
|-------------|-----------------|
| 22          | SSH — the "staff entrance" for logging in |
| 80          | HTTP — the public web door (plain) |
| 443         | HTTPS — the public web door (secure) |
| 8000        | our app (internal — the public never knocks here directly) |
| 5432        | Postgres, the database (internal, kept private) |

## Reverse proxy (Nginx): the receptionist {#reverse-proxy-nginx}

Your app speaks plain, unencrypted HTTP and knows nothing about security certificates. You do **not**
want to shove that straight onto the public internet. So we hire a **receptionist** who sits at the
front doors (80 and 443) and deals with the outside world, then passes each request *inward* to your
app. That receptionist is **Nginx**, and the role is called a **reverse proxy**.

What the receptionist does for us:
- Listens on the public doors so your app doesn't have to.
- Handles the scary security stuff (HTTPS — decrypting the connection).
- Forwards the now-safe request to your app at `localhost:8000`.
- Attaches sticky-notes about the *original* visitor (their real IP, the name they asked for,
  whether they came in over http or https) — because otherwise your app would think *Nginx* was the
  visitor.

Here's our config with every line explained:

```nginx
server {                                  # one "website" this receptionist handles
    listen 80;                            # wait at the public HTTP door
    server_name 203-0-113-10.nip.io;      # only handle requests asking for THIS name

    location / {                          # for every URL path ("/" and everything under it):
        proxy_pass http://localhost:8000; # ⭐ THE key line: hand the request to the app
        proxy_set_header Host $host;                    # sticky-note: which name they asked for
        proxy_set_header X-Real-IP $remote_addr;        # sticky-note: the visitor's real IP
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;     # sticky-note: was it http or https?
    }
}
```

🎓 Everything except `proxy_pass` is bookkeeping. **The whole job is: "catch it at the front, pass it
to the app."** The name "reverse" proxy is because it stands in front of the *server*; a plain proxy
stands in front of *clients*.

> **Alternatives:** Caddy (does HTTPS automatically — simpler, but we wanted to learn Nginx like the
> team uses), Traefik (built for containers), HAProxy.

## HTTPS & TLS: the padlock

Plain HTTP is like sending a postcard — anyone who handles it along the way can read it. For a finance
app, that's a non-starter. **HTTPS** upgrades the postcard to a sealed, tamper-proof envelope. It
gives you two things:

1. **Encryption** — nobody in the middle can read the traffic.
2. **Identity** — a **certificate** proves the server really is who it claims to be (not an impostor).

The underlying technology is called **TLS**, and the certificate is issued by a trusted **Certificate
Authority (CA)**.

## Let's Encrypt, Certbot & the ACME challenge

Certificates used to cost money. Then **Let's Encrypt** appeared: a free, automated CA. But how does
it know *you* actually control `203-0-113-10.nip.io` and aren't just claiming it? Through a little
proof-of-ownership dance called the **ACME challenge**:

1. **Certbot** (the tool that talks to Let's Encrypt for you) places a secret token on your server.
2. Let's Encrypt visits `http://203-0-113-10.nip.io/.well-known/...` over **port 80** and checks the
   token is there.
3. Only someone who controls the server could have placed it → proof accepted → certificate issued.

🎓 *This is why we set up Nginx on port 80 first.* The proof rides on it. Certbot then edits Nginx to
turn on HTTPS, and installs a background timer that **renews the certificate automatically** (they
expire every 90 days on purpose — short-lived certs are safer). You genuinely never think about it
again.

---

# Part 2 — The server & the cloud (AWS)

## EC2: renting a computer

**EC2** (Elastic Compute Cloud) is just Amazon's name for *rentable computers*. One rented computer is
an **instance**. Don't let the jargon inflate it — you're renting a PC in a data center that never
sleeps. Three settings mattered when we created ours:

- **Region** — which city the data center is in (we used N. Virginia, `us-east-1`). 🎓 Your instance
  only exists in its region. A classic beginner panic is "my server disappeared!" — it didn't, you're
  just looking at the wrong region in the console.
- **AMI** (Amazon Machine Image) — the pre-installed operating system to start from. We chose Ubuntu
  because the whole internet's tutorials assume it.
- **Instance type** — the size and power. We chose `t3.micro` because it's **free-tier eligible**.
  This is *the* setting that accidentally costs people money — always pick a free one while learning.

## EBS: the hard drive (and the two-layer trap)

Your instance needs a disk. That's an **EBS volume** — a virtual hard drive (ours started at 8 GB).

🎓 **The single most important thing to understand here**, because it caused a real bug: there are
**two separate layers**, and they don't resize together.
1. The **volume** — the drive itself. You make it bigger in the AWS *console*.
2. The **filesystem** — the formatting *on* the drive that actually holds files. You make it bigger
   on the *server* with `growpart` then `resize2fs`.

Enlarging the drive does *nothing* until you also stretch the filesystem to fill it. Miss the second
part and you'll swear the resize "didn't work." (Free tier covers 30 GB, so growing to 20 was free.)

## Security Groups: the firewall

A **Security Group** is the firewall wrapped around your instance. By default it blocks *everything* —
which is the right default. You then explicitly open the specific doors you need:

- Port **22** (SSH) — opened only to *your* IP, so only you can log in.
- Ports **80** and **443** — opened to the whole world, because that's the public web.
- Ports 8000 and 5432 — *left closed*. This is why your app and database can't be reached directly
  from the internet, only through Nginx. Your first and best line of defense.

🎓 Prove it to yourself: from your laptop, try to hit the app's real port —
`curl http://203.0.113.10:8000/health` — and watch it hang and time out. That closed door *is* the
firewall doing its job.

## The free-credit reality

New AWS accounts get up to **$200** in credits ($100 at signup, $100 more for doing a few starter
activities), good for **6 months or until spent**. Plan to stay cheap so nothing surprises you when
they run out. A small EC2 box after credits is still only ~$7/month — or you stop it and pay ~nothing.

---

# Part 3 — The operating system (Linux basics you now know)

## SSH: your remote terminal

**SSH** (Secure Shell) is how you operate a computer that has no screen or keyboard in front of you.
You type on your laptop; the commands run on the server; the output comes back — all encrypted.

- It logs you in with a **key file** (the `.pem`), not a password. That file *is* your password —
  which is why we `chmod 400` it (lock it down) and why losing it locks you out forever.
- The `ubuntu@` part is the username: Ubuntu servers come with a default user called `ubuntu`.
- The first time you connect, it asks you to trust the server's "fingerprint" — you say `yes` once
  and it remembers.

Its cousin is **`scp`** (secure copy), for copying files to/from the server over the same secure
channel.

## Foreground, background, and daemons

🎓 A question every beginner asks: *"if I start the server, won't my terminal be stuck? And if I close
my laptop, does everything stop?"* Great questions — here's the model:

- A **foreground** command takes over your terminal until it finishes (or you press `Ctrl-C`).
- A **background** (or "detached") command starts, hands your prompt back, and keeps running out of
  sight. That's what the `-d` in `docker compose up -d` means.
- A **daemon** is a background service. Your containers run as daemons managed by Docker, which means
  **they keep running after you disconnect SSH or shut your laptop.** The server doesn't need you
  watching it — that's the entire point of a server.

## Symlinks: shortcuts that enable things

A **symlink** (`ln -s`) is a shortcut — a tiny file that points at another file, like a desktop alias.

Nginx uses this beautifully. It keeps two folders: `sites-available/` (every config you've *written*)
and `sites-enabled/` (the ones actually *switched on*). You "turn on" a site by dropping a *shortcut*
to it into `sites-enabled/`. To turn it off, you delete the shortcut — the real config stays safe and
untouched. Enable/disable with zero risk to the original.

## systemctl: the switchboard for services

Background programs like Nginx are **services**, and you control them all with one tool, `systemctl`:

| Command | What it does |
|---------|--------------|
| `systemctl reload nginx`  | re-read the config **without dropping any connections** (graceful) |
| `systemctl restart nginx` | fully stop and start (a brief blip of downtime) |
| `systemctl status nginx`  | is it running? show recent logs |
| `systemctl enable nginx`  | start automatically every time the server boots |

🎓 For a config change, always prefer **`reload`** over `restart` — reload applies your change with
zero downtime, restart briefly cuts everyone off.

## Swap: emergency overflow memory

Our little server has only 1 GB of RAM, and a Docker build is memory-hungry. **Swap** is disk space
the system borrows as *pretend RAM* when real RAM fills up. It's slower than real memory, but it stops
the system from killing your program when things spike. We made 2 GB of it and, via `/etc/fstab`, made
it survive reboots.

## Finding out why a disk is full

Three commands, in increasing zoom:
- `df -h /` — how full is the whole disk? (Look at the **Use%** column.)
- `du -sh <folder>` — how big is *this one* folder?
- `du -h -d1 / | sort -hr | head` — list the biggest folders at the top level, largest first.

🎓 That last one is *the* command for "help, my disk is full." Memorize it. It points straight at the
culprit (for us: `/var`, where Docker stores its images).

## The `sudo tee` gotcha (a genuinely confusing one)

You'd think `sudo echo "text" > /etc/somefile` would write a file as root. **It doesn't** — it fails
with "Permission denied." Why? Because the `>` (the redirect that actually writes the file) is
performed by *your shell*, running as *you* — `sudo` only elevated the harmless `echo`. The fix is
**`sudo tee`**: `tee` is a program that writes to a file, and running *it* under sudo means the write
itself happens as root.

We paired it with a **heredoc** (`<<'EOF' ... EOF`) to feed it a multi-line config. The quotes around
`'EOF'` are important: they tell the shell "don't touch the `$` signs in here," so Nginx's `$host` and
friends stay literal instead of getting mangled.

---

# Part 4 — The security decisions we made (and why)

These weren't afterthoughts — each one closes a specific hole:

- **A real `JWT_SECRET`.** The app signs login tokens with a secret key. The example file ships with a
  *publicly known* placeholder — if we'd shipped that, anyone could forge a login and impersonate a
  user. We generated a proper random one with `openssl rand -hex 32`.
- **`ENV=production` turns off the API docs.** In development the app publishes an interactive map of
  every endpoint at `/docs`. In production we switch that off so we're not handing attackers a
  blueprint.
- **The database is invisible to the internet.** Its port (5432) isn't opened in the firewall, so it's
  only reachable from inside the server. (Follow-up we noted: also rotate its default password, just
  in case.)
- **The login door is locked to you.** SSH (port 22) is open only to your own IP address, not the
  whole world — dramatically shrinking who can even *attempt* to log in.

---

## The full decision table (with alternatives)

| Decision | We chose | Why | Other options |
|----------|----------|-----|---------------|
| Where to run it | Single EC2 server | Cheapest, teaches fundamentals | App Runner+RDS (managed, pricier), Lightsail (flat price), ECS Fargate (complex) |
| Server size | `t3.micro` (free) | Plenty for 1–2 users | t4g.small (bigger, not free), anything larger = 💰 |
| Operating system | Ubuntu | Best-documented | Amazon Linux, Debian |
| Front-door proxy | Nginx | Matches the team's tooling | Caddy (auto-HTTPS), Traefik, HAProxy |
| HTTPS certificate | Let's Encrypt + Certbot | Free & automated | Caddy (built-in), Cloudflare, paid CA |
| Web name | nip.io (free) | Instant, works with certs | Real domain (~$10/yr), Route 53, Cloudflare |
| Database | Postgres in a container | Cheap, matches local dev | Managed RDS/Lightsail/Neon (auto-backups, 💰) |
| Deploys | Manual `git pull` + rebuild | Best way to *learn* the pieces | `deploy.sh` script, then GitHub Actions CI/CD |
