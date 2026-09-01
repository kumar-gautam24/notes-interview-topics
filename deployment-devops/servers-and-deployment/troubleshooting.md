# When things break: the two bugs we hit, and how to think

This might be the most useful file in the set. Anyone can follow steps that work — the real skill is
what you do when they *don't*. We hit two genuine problems during this deploy, and both taught a
lesson worth more than the fix itself. Read the stories; the mindset is the takeaway.

---

## The mindset (read this first)

When something behaves weirdly, every instinct screams "I know what's wrong!" and you start changing
things. **Resist that.** The single most valuable habit in this whole guide:

> 🎓 **Get evidence from the running system before you trust any theory — including your own.**

Twice below, a confident, sensible-sounding theory was flat wrong, and the *data* set us straight in
seconds. Your tools for getting evidence:

- `docker compose logs api` — what the app *actually did*.
- `docker compose exec api ...` — what's *actually inside* the container.
- `curl -i ...` — the *actual* status code and headers coming back.
- `df -h`, `du`, `lsblk` — the *actual* state of the disk.

Look first. Theorize second. Change things third.

---

## Bug #1 — the endpoint that "didn't exist" (but did)

**What we saw:** `curl .../health` returned `{"status":"ok"}` — but its twin, `curl .../ready`,
returned `{"detail":"Not Found"}` (a 404). Bizarre, because in the code these two endpoints are
defined *right next to each other*. If one works, the other should too.

**The tempting theory:** "The container must be running old code that doesn't have `/ready` yet." Very
plausible. Completely wrong.

**How the evidence corrected us:**
```bash
docker compose exec api grep -n '@app.get' app/main.py
# → showed BOTH /health AND /ready. The code was fine.

docker compose logs api
# → revealed the request the app actually received:
#   "GET /hecalhost%3A8000/ready HTTP/1.1" 404 Not Found
```
Look at that path: `/hecalhost%3A8000/ready`. The terminal had **mangled a pasted multi-line command**
— the URL got mashed into the request path, so `curl` asked for a route that genuinely doesn't exist.
A clean, one-line `curl -i http://localhost:8000/ready` returned `200 OK`. **The app was never
broken.**

**Two lessons:**
1. The obvious theory ("stale code") felt right and wasn't — the logs showed the truth in one look.
   *Evidence beats intuition.*
2. 🎓 **Pitfall:** this terminal garbles multi-line pastes. **Paste one line at a time.** (You'll see
   the tell-tale sign: commands echoing back doubled or mashed together.)

---

## Bug #2 — "No space left on device" (the disk filled up)

**What we saw:** an `apt install` failed partway through, spraying `No space left on device` while
building a Linux kernel image. It looked like an Nginx problem; it wasn't. Nginx was just the straw
that broke the camel's back.

**Getting the evidence:**
```bash
df -h /
# → 98% full, 193 MB free. There's the real problem, plain as day.

docker system df
# → 877 MB of images + 358 MB of build cache. Docker is the big eater.

du -sh ~/honest-ledger
# → 5.5 MB. (We suspected the repo — the evidence cleared it. It's tiny.)

sudo du -h -d1 / | sort -hr | head
# → /usr 2.5G, /var 2.1G (that's Docker), /snap 625M.  The 6.5 GB, accounted for.
```

**The real cause:** an 8 GB disk is simply too small for a Docker workload. The bare operating system
already used ~2 GB (you could even see it in the very first SSH login banner: *"Usage of /: 30.5%"*),
and Docker's images + cache + a queued kernel update ate the rest.

**The fix — grow the disk 8 GB → 20 GB.** And here's the concept that makes or breaks this: there are
**two layers**, and they don't grow together.
```bash
# 1. Free a little breathing room first
docker builder prune -f
sudo apt clean

# 2. In the AWS console: EC2 → Volumes → Modify volume → 20 GiB (still free-tier, ≤30 GB)

# 3. On the server — stretch BOTH layers into the new space:
lsblk                            # see: the DRIVE now shows 20G, but the filesystem still ~7G
sudo growpart /dev/nvme0n1 1     # stretch the PARTITION to fill the bigger drive
sudo resize2fs /dev/nvme0n1p1    # stretch the FILESYSTEM to fill the bigger partition
df -h /                          # → ~19 G free now 🎉

# 4. Finish the install that got interrupted mid-way
sudo apt --fix-broken install
```

🎓 **Why two commands, not one?** The *volume* (the drive) and the *filesystem* (the formatting on it)
are separate things. Making the drive bigger in the console does nothing visible until you `growpart`
the partition and then `resize2fs` the filesystem to actually use the new room. Forget the second step
and you'll be convinced the resize failed.

**How to avoid it next time:** don't run Docker on a tiny 8 GB disk; check `df -h /` now and then; and
prune the build cache (`docker builder prune -f`) when space gets tight.

---

## The pitfall checklist (learn from others' scars)

Grouped by where they bite. None of these are exotic — they're the everyday trip-wires.

### AWS
- **Looking in the wrong region.** Your server only exists in the region you made it in. "It vanished!"
  → check the region dropdown, top-right.
- **Losing the `.pem` key.** It's the *only* way in — no reset, no recovery. Back it up somewhere safe.
- **The public IP changed.** Auto-assigned IPs shuffle when you stop→start the instance. Attach an
  **Elastic IP** to pin it (and remember your nip.io name would change with the IP too).
- **A surprise bill.** Only ever launch *free-tier eligible* sizes; keep the disk ≤ 30 GB; peek at the
  Billing dashboard occasionally.

### The terminal & Linux
- **Paste garble** — one line at a time (see Bug #1).
- **`sudo echo > /etc/file` fails** with Permission denied. The `>` runs as *you*, not root. Use
  `sudo tee <file>` instead. (Explained in [concepts.md](concepts.md).)
- **`Ctrl-C` while following logs** stops your *watching*, not the app. The app keeps running.
- **A group change needs a fresh login.** After `usermod -aG docker $USER`, log out and back in before
  `docker` works without `sudo`.

### Nginx
- **Always run `sudo nginx -t` before `reload`.** It's a dry run that catches typos; applying a broken
  config live can take the site down.
- **Use `reload`, not `restart`, for config changes** — zero downtime vs. a brief cut-off.
- **Don't forget to remove the default site** — it can quietly shadow yours.

### HTTPS / Certbot
- **Port 80 must be open and Nginx serving the right name** — the certificate proof (ACME challenge)
  rides on it. Cert issuance failing? Check that first.
- **Certs auto-renew, but verify it:** `systemctl list-timers | grep certbot`. Test safely with
  `sudo certbot renew --dry-run` (it won't burn through rate limits).
- **Don't re-issue certs in a tight loop** while experimenting — Let's Encrypt has rate limits.

### Docker
- **Never edit code inside a running container** — it's wiped on the next rebuild.
- **`docker compose down -v` deletes your database.** Plain `down` keeps it. Respect the `-v`.
- **Build cache grows** — prune it when the disk tightens.

### The app & deploying
- **Never edit code directly on the server** — a later `git pull` will conflict. Edit on your laptop,
  push, pull. The server only receives.
- **`.env` lives only on the server** (it's gitignored). Good news: `git pull` never clobbers your
  secrets. Flip side: you set it up fresh on each new server.
- **A Dart `const` needs a full restart** — hot-reload won't notice a changed `baseUrl`.

---

## The roadmap of things we deliberately left for later

Not bugs — conscious "good enough for now, improve when it matters" calls. Written down so they're not
forgotten:

- **Nightly database backup to S3.** We host our own database, so no one backs it up for us. For a
  finance app, this is the first thing to add.
- **Rotate the default database password.** Low risk today (the DB isn't exposed to the internet), but
  worth doing.
- **`--dart-define` for the app's backend URL.** So you can point at `localhost` for development and
  the live server for production without hardcoding.
- **An Elastic IP.** To pin the public address so it survives a stop/start.
- **CI/CD with GitHub Actions.** To automate the `git pull && docker compose up -d --build` loop once
  doing it by hand feels boring — which is exactly the right time to automate it.
