# Backups, IAM & CI/CD — operating a small backend (from zero)

These are **teaching notes**, written so someone starting from near-zero can follow along on
**any operating system** and *understand* each step — not memorize commands. They cover how to
take a live **FastAPI + Postgres** backend on a single cloud server and make it **safe and
repeatable**:

1. **one-command deploys** (small shell scripts),
2. a proper **cloud login and permissions** (AWS IAM),
3. **automatic, restore-tested database backups** (to cloud storage), and
4. fully **automated deploys** (CI/CD with GitHub Actions).

The running example is one specific app (an app called *recurring* / repo *honest-ledger*, on
AWS EC2), but **every concept transfers** — the same ideas apply to any Linux server, any cloud,
any similar stack. Wherever a command is OS- or tool-specific, the general idea and the
alternatives are called out.

> **How to read this**
> - **New to servers, terminals, or SSH?** Read **[Ground floor](#ground-floor--the-basics-this-assumes-start-here-if-youre-new)** first — it explains every assumed basic.
> - **`[LOCAL]`** = run on *your own computer* (macOS/Linux/Windows). **`[SERVER]`** = run *inside
>   the remote server*, after you SSH in. Example paths like `~/Downloads/key.pem` are just
>   examples — substitute your own.
> - 🎓 marks a concept worth internalizing — the *why*, not just the *what*.
> - The examples were typed on a Mac, so a few commands (like clipboard copy) show the macOS
>   form first; the Linux/Windows equivalents are always given alongside.

---

## The one picture for this session

Last time we built the *delivery route* for a request. This time we added the **safety and
convenience layer** around it:

```
   YOU (laptop)                                  THE SERVER (EC2)
   ────────────                                  ────────────────
   ./scripts/ship.sh ──push──► GitHub ──pull──►  ./scripts/deploy.sh
                                                        │ rebuilds + restarts the app
                                                        ▼
                                                  🐘 Postgres (the database)
                                                        │
                                                        │  every night at 03:30, cron runs:
                                                        ▼
                                                  pg_dump │ gzip │ aws s3 cp ──►  ☁️ S3 bucket
                                                                                  (off-site vault,
                                                                                   auto-deletes >30d)

   The server is allowed to write to S3 because it *wears an IAM role* —
   no passwords or keys are stored anywhere on the box.
```

Four capabilities, four parts below:
1. **One-command deploys** — the run-scripts.
2. **A safe cloud identity + permissions** — IAM (users, roles, policies).
3. **Automatic backups** — database dump → cloud storage, on a schedule, proven by a restore.
4. **Auto-deploy on push** — CI/CD with GitHub Actions.

---

## Ground floor — the basics this assumes (start here if you're new)

Everything below uses a handful of ideas. If they're already familiar, skip to Part 1. If not,
this section is your foundation — read it once and the rest will make sense.

### The terminal and the shell
A **terminal** is a window where you type commands instead of clicking. Inside it runs a
**shell** — a program that reads your command, runs it, and prints the result. Common shells:
`bash` and `zsh` (macOS/Linux), PowerShell (Windows). On Windows, the friendliest way to follow
Linux-style notes like this is **WSL** (Windows Subsystem for Linux) or **Git Bash**, which give
you a bash shell.

A **command** is `program [options] [arguments]`, e.g. `ls -l /home`:
- `ls` = the program (list files), `-l` = an **option/flag** (long format), `/home` = an
  **argument** (what to act on).
- **Flags** are usually a letter after `-` (e.g. `-l`) or a word after `--` (e.g. `--build`).
  Many can combine: `-fsS` = `-f -s -S`.

### Files, folders, and paths
- A **path** names a location. **Absolute** paths start at the root: `/home/ubuntu/app`
  (Linux/macOS) or `C:\Users\me\app` (Windows). **Relative** paths are from where you are now:
  `scripts/deploy.sh`.
- **`~`** is shorthand for your **home folder** (`/home/ubuntu`, `/Users/you`, …).
- **`cd`** changes folder, **`ls`** lists, **`pwd`** prints where you are.

### Input, output, pipes, and redirects (the Unix superpower)
Every program has three streams: **stdin** (input), **stdout** (normal output), **stderr**
(errors). You can rewire them:
- **`|` (pipe)** — send one program's stdout into the next program's stdin: `A | B | C` builds an
  assembly line. This is *the* core Unix idea, and the backup is literally one pipeline.
- **`>`** — redirect stdout **into a file** (overwrite). **`>>`** — same but **append**.
- **`<`** — feed a **file into** a program's stdin.
- **`2>&1`** — "send stderr (stream 2) to wherever stdout (stream 1) is going" — i.e. capture
  errors too.
- **`-`** — many tools accept `-` to mean "use stdin/stdout instead of a file" (enables streaming
  without a temp file).

There's a fuller idioms cheat-sheet near the end; this is enough to read along.

### SSH and key-based login (how you reach a remote server)
**SSH** ("secure shell") is an encrypted remote terminal: you type locally, commands run on the
server. Instead of a password, we use a **key pair** — two matching files:
- a **private key** (stays secret on your machine — like a physical key), and
- a **public key** (you place it on the server — like the lock it fits).

You log in with `ssh -i <private-key> user@host`. The server checks your private key against the
public key it holds. 🎓 Key auth beats passwords: keys are long and unguessable, and you can hand
a machine (like a CI runner) its own key without sharing a human password.

### Git in one paragraph
**Git** tracks versions of your code. A **repository** ("repo") is your project's history.
`git commit` saves a snapshot; `git push` uploads commits to a host like **GitHub**; `git pull`
downloads the latest. 🎓 Crucial mental model for deploys: **your laptop, GitHub, and the server
each hold their own copy.** Pushing to GitHub does *not* update the server — the server must
`git pull` for itself. That's why deploying is a deliberate two-machine action.

### Copying to the clipboard on any OS (the thing that prompted this rewrite)
Several steps say "copy this to your clipboard without printing it on screen." The *concept* is:
**pipe a command's output straight into the OS clipboard tool.** The tool differs by OS:

| OS / shell | Command | Notes |
|------------|---------|-------|
| **macOS** | `cat file \| pbcopy` | `pbcopy` is built in |
| **Linux (X11)** | `cat file \| xclip -selection clipboard` | install `xclip` (or use `xsel`) |
| **Linux (Wayland)** | `cat file \| wl-copy` | from `wl-clipboard` |
| **Windows (PowerShell)** | `Get-Content file \| Set-Clipboard` | built in |
| **Windows (cmd / Git Bash)** | `cat file \| clip` | `clip` is built in |

🎓 The point of piping to the clipboard (instead of `cat file` then selecting with the mouse) is
that **secrets never get displayed** — they don't appear on screen, in your scrollback, or in any
log. If you don't have a clipboard tool, you *can* just `cat` the file and copy by hand — just be
aware the secret is now on your screen.

### Installing tools per OS
When a step says "install X," the command depends on your package manager:
- **Ubuntu/Debian Linux:** `sudo apt install X`
- **macOS:** `brew install X` (Homebrew)
- **Windows:** `choco install X` (Chocolatey) or `winget install X`

---

## Part 1 — One-command deploys (the run-scripts)

### The problem

Deploying a change used to be a manual ritual: SSH in, `cd`, `git pull`, `docker compose up`.
Boring and error-prone. Boring + error-prone = **automate it.** But automate it *after* doing
it by hand a few times, so you understand what you're automating.

### What we built

Two small shell scripts, kept **inside the repo** (tracked by git, so both machines get them
the normal way — through `git pull`):

| File | Runs on | Does |
|------|---------|------|
| `scripts/deploy.sh` | `[SERVER]` | pull → rebuild → restart → wait for `/ready` → report |
| `scripts/ship.sh` | `[LOCAL]` | `git push` → SSH in → run the server's `deploy.sh` |

🎓 **Why two files?** Because they run on two different computers, and each does the half only
*its* machine can do. `ship.sh` can't rebuild containers (they live on the server); `deploy.sh`
can't push your local commits (they're on your laptop). `ship.sh` reaches across the network
(SSH) to trigger the other half. **Every deploy system on earth has this shape: a local half
and a remote half, joined by a network call.**

### `scripts/deploy.sh`, explained

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../backend"

git pull --ff-only
docker compose up -d --build

for _ in $(seq 1 15); do
  if curl -fsS http://localhost:8000/ready >/dev/null 2>&1; then
    echo "OK: backend is ready."; docker compose ps; exit 0
  fi
  sleep 2
done
echo "FAILED: /ready did not come up."; docker compose logs --tail=40 api; exit 1
```

Line by line:

- **`#!/usr/bin/env bash`** — the "shebang." Tells the OS *which interpreter* runs this file.
  `env bash` finds bash on the current PATH (more portable than hardcoding `/bin/bash`).
- **`set -euo pipefail`** — the safety header every serious script has. Four guards:
  - `-e` → **exit** the moment any command fails (don't blunder on after `git pull` breaks).
  - `-u` → error on an **unset** variable (catches typos like `$BUKCET`).
  - `-o pipefail` → in a pipe `a | b | c`, if *any* stage fails, the whole line fails. Without
    this, only the *last* command's success is checked — so a failed `pg_dump` piped into a
    successful `gzip` would look like success. **This one flag prevents silent data loss.**
- **`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`** — a common idiom meaning
  "the absolute folder this script lives in." `${BASH_SOURCE[0]}` is the script's own path;
  `dirname` strips the filename; `cd … && pwd` turns it into a clean absolute path. Result: the
  script works no matter what directory you call it from.
- **`git pull --ff-only`** — fetch + merge, but **fast-forward only**: refuse to create a merge
  commit. 🎓 On a server that only *consumes* code, a pull that can't cleanly fast-forward means
  *someone edited files on the server* (the one thing we swore never to do). Better to fail
  loudly than silently create a tangled history.
- **`docker compose up -d --build`** — `--build` rebuilds the image from the new code; `-d`
  ("detached") runs it in the background. Compose is **declarative**: it compares desired vs.
  running state and recreates *only what changed*. The database container keeps running
  untouched — which is why we never need `docker compose down` (and *especially* never `down -v`,
  which deletes the database volume).
- **The `for` loop + `curl`** — polls the app's `/ready` endpoint up to 15× every 2s (~30s).
  `curl -fsS`: `-f` fail on HTTP errors, `-s` silent, `-S` still show real errors.
  🎓 A deploy script should *verify*, not fire-and-hope. It only prints success once the app
  truly answers.
- **`exit 0` / `exit 1`** — the script's exit code. `0` = success, non-zero = failure. This is
  how a *robot* (GitHub Actions, tomorrow) will know whether the deploy worked.

### `scripts/ship.sh`, explained

```bash
#!/usr/bin/env bash
set -euo pipefail
KEY="${RECURRING_KEY:-$HOME/Downloads/recurring-key.pem}"
HOST="${RECURRING_HOST:-ubuntu@203.0.113.10}"
REMOTE_DIR="${RECURRING_REMOTE_DIR:-honest-ledger}"

git push
ssh -i "$KEY" "$HOST" "cd '$REMOTE_DIR' && ./scripts/deploy.sh"
```

- **`"${RECURRING_HOST:-ubuntu@203.0.113.10}"`** — "use the `RECURRING_HOST` environment
  variable if it's set, otherwise fall back to this default." 🎓 This is the **12-factor
  "config in the environment"** idea. Our server's public IP changes if the instance is
  stopped/started (no Elastic IP yet), so instead of editing the file we override for one run:
  `RECURRING_HOST=ubuntu@NEW.IP ./scripts/ship.sh`.
- **`ssh -i "$KEY" "$HOST" "…command…"`** — `-i` picks the **identity** (private key) to log in
  with. Any command in quotes after the host runs *on the server* and then SSH disconnects.
  So this one line logs in, runs `deploy.sh` remotely, and comes back.

### Using them
```bash
# one-time on the server: git pull once so it HAS the scripts
# from then on, every deploy is just:
./scripts/ship.sh        # [LOCAL]
```

---

## Part 2 — Accessing the database from your laptop (the SSH tunnel)

**Question we hit:** can I open the production database in a desktop GUI (DBeaver / TablePlus /
Azure Data Studio) on my laptop?

**Answer:** yes — but **only through an SSH tunnel**, never directly. Here's the why.

The database listens on port `5432`, but the AWS **Security Group** (the firewall) only opens
ports 22, 80, 443. Port 5432 is sealed off from the internet — **on purpose.**

🎓 Look at the DB credentials: user `recurring`, password `recurring`. If we opened 5432 to the
world so a GUI could reach it, we'd be putting a database with a *guessable* password on the
open internet — bots find that within minutes. **Rule: never expose a database port to the
internet.** The firewall is the only thing protecting `recurring/recurring` right now.

So we tunnel the DB traffic through the one door that *is* open and authenticated — SSH (22):

```bash
ssh -i ~/Downloads/recurring-key.pem -N -L 5433:localhost:5432 ubuntu@203.0.113.10   # [LOCAL]
```
Then point the GUI at `localhost:5433`, db/user/pass = `recurring`.

- **`-L 5433:localhost:5432`** — local port forward: "take port **5433 on my laptop** and forward
  anything sent there, through the SSH tunnel, to **`localhost:5432` as seen from the server**."
  That second `localhost` is the *server's* view of itself. So your laptop's 5433 becomes a
  private side-door into the server's 5432.
- **`-N`** — "don't run a remote shell, just hold the tunnel open." (Ctrl-C closes it.)
- **Why 5433, not 5432?** If you also run the DB stack *locally*, it already occupies your
  laptop's 5432. Using 5433 avoids the collision — local DB and server DB, side by side.

> Follow-up to explore: TablePlus/DBeaver have a built-in "SSH tunnel" toggle in the connection
> dialog — fill in the key + host and they run this `-L` for you automatically.

---

## Part 3 — IAM: identities and permissions in AWS

This is the biggest new concept, so it gets the most room. **IAM = Identity and Access
Management.** It answers one question: *"who is allowed to do what?"*

### The office-building analogy

| IAM thing | Building analogy | In plain terms |
|-----------|------------------|----------------|
| **Root user** | The owner holding the deed | Can do *anything*, including close the account. Unlimited, un-restrictable. |
| **IAM User** | An employee with a badge | A named identity a *human* logs in as, day to day. |
| **Group** | A department | A bucket of users that share permissions. |
| **Role** | A visitor uniform anyone (or any *machine*) can put on | A temporary identity, no permanent password/keys. |
| **Policy** | The rules printed on the badge/uniform | A JSON document: "may do X on resource Y." |
| **Instance profile** | The clip that pins a uniform onto a robot | The wrapper that lets an **EC2 instance** wear a role. |

### Lesson A — stop using root

We were logging in as **root** (the account owner). AWS's #1 security rule: **almost never do
that.** Root can't be limited by any policy, so if its credentials leak, the whole account is
lost — unlimited spend, deletion, everything. So we:

1. **[as root]** created an IAM user `admin-user` and attached the managed policy
   `AdministratorAccess`.
2. Started signing in via the **account IAM console URL** as `admin-user` for daily work.
3. (TODO) turn on **MFA** for both root and `admin-user`.

🎓 Analogy: **root is the forklift** — powerful, dangerous, kept in the shed for the one job a
year that needs it. `admin-user` is the **everyday car**. Same errands, far safer, and
*revocable* if it's ever compromised.

### Lesson B — "deny by default" (we saw it live)

When we first logged in as `admin-user`, **everything** showed "access denied" / "API Error."
That wasn't a bug — it was IAM's core rule:

> 🎓 **A brand-new identity can do NOTHING. Every action is denied unless a policy explicitly
> allows it.**

The user had zero policies attached, so AWS denied it all. The error message even said so:
*"not authorized… because no identity-based policy allows the action."* Root then attached
`AdministratorAccess`, and everything sprang to life.

Side lesson: also confirmed the EC2 instance "disappearing" was just the **wrong region**
selected (top-right dropdown). EC2 resources are region-scoped; you only see the region you're
looking at. Ours lives in **us-east-1 (N. Virginia)**.

### Lesson C — the permission chain that needs NO stored keys

This is the elegant part. We wanted the *server* to upload backups to S3. The naive way is to
generate access keys and paste them onto the box — a long-lived secret that can leak. The right
way is an **instance role**:

```
  POLICY                 ROLE                    INSTANCE PROFILE       EC2 INSTANCE
  recurring-backup-s3  → recurringbackuprole  →  (auto-created)      →  recurring-api
  "may List/Read/Write   "a wearable identity      "clips a role onto     "wears the role →
   this ONE bucket"       that EC2 can assume"      a server"              gets temporary,
                                                                           auto-rotating creds"
```

We proved it worked on the server:
```bash
aws sts get-caller-identity    # [SERVER]
# → "Arn": "arn:aws:sts::<ACCOUNT_ID>:assumed-role/recurringbackuprole/<INSTANCE_ID>"
```
🎓 That `assumed-role/...` ARN is the proof: the server authenticated to AWS **purely by wearing
the role**, receiving temporary credentials from the instance metadata service — **with zero
keys stored on disk.** If those temp creds leak, they expire in hours *and* only permit S3
access to one bucket. This is the gold standard.

### The policy we wrote

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BackupReadWrite",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::<backup-bucket>",
        "arn:aws:s3:::<backup-bucket>/*"
      ]
    }
  ]
}
```

Read it like a sentence: *"**Allow** the actions **put / get / list objects**, but **only** on
**this one bucket** and the things inside it (`/*`)."* Every IAM policy is just those three
ideas: `Effect` (Allow/Deny), `Action` (the verbs), `Resource` (the things).

🎓 **Least privilege:** it grants three actions on *one* bucket — nothing else in all of AWS.
If this role ever leaks, the blast radius is "someone can read/write one backup bucket." That
containment is the entire point. And two ARNs are needed: the bucket itself (for `ListBucket`)
*and* `/*` (the objects inside, for Put/Get) — S3 treats "the bucket" and "objects in the
bucket" as different resources.

---

## Part 4 — Backups: pg_dump → S3

### Why backups, framed properly

> "It's 3am, the database disk just died. How much data did we lose, and how long to get back?"

Those two questions have names, and they're the only backup metrics that matter:

- **RPO — Recovery Point Objective:** how much data you can afford to lose. Nightly backups →
  up to ~24h RPO (anything since last night's dump is gone). Fine for 1–2 users.
- **RTO — Recovery Time Objective:** how long to get running again. A dump in S3 you can restore
  in minutes → low RTO.

🎓 **The 3-2-1 rule:** 3 copies, 2 kinds of media, **1 off-site.** Your live DB is on the
server's disk. A backup *on the same server* is worthless — if the box dies, both die together.
**S3 is the off-site copy in a different failure domain.** That separation *is* the backup.

Two design decisions, both deliberate:
- **`pg_dump`, not "copy the data files."** `pg_dump` asks Postgres for a clean, consistent
  logical snapshot — a `.sql` script that recreates everything. Copying
  `/var/lib/postgresql/data` while the DB is live gives a torn, possibly-corrupt copy.
- **Stream, never stage.** We pipe `pg_dump | gzip | aws s3 cp -` straight to S3 with **no temp
  file** touching the small 20GB disk. It flows through memory in one pipe.

### The S3 bucket

Created `<backup-bucket>` in **us-east-1** (same region as the server → fast, free
transfer), with:
- **Block Public Access: ON** (these are DB backups — never public).
- A **lifecycle rule** `expire-old-dumps` → delete objects after **30 days**. 🎓 This is the
  **retention policy**: "keep a month of nightlies, then let them go." Without it, backups pile
  up forever and slowly cost money.

🎓 S3 = **Simple Storage Service**, AWS's "infinite hard drive in the cloud." You store
**objects** (files) in **buckets** (globally-unique named containers). It's designed for
"eleven nines" of durability — practically, files you put there don't get lost. Perfect for
backups.

### The script — `scripts/backup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
BUCKET="${BACKUP_BUCKET:?set BACKUP_BUCKET, e.g. s3://recurring-backups-<unique>}"
STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
KEY="db/recurring-${STAMP}.sql.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../backend"

docker compose exec -T db pg_dump -U recurring -d recurring \
  | gzip \
  | aws s3 cp - "${BUCKET%/}/${KEY}"
```

Command by command:

- **`"${BACKUP_BUCKET:?…}"`** — "use `BACKUP_BUCKET`, but if it's **unset, abort** with this
  message." The `:?` form is a guard: no silent uploads to nowhere. We pass the bucket at run
  time (and via cron) rather than hardcoding it.
- **`date -u +%Y-%m-%dT%H-%M-%SZ`** — the current time. `-u` = **UTC** (so backups from any
  timezone sort correctly); the `+…` part is the format → e.g. `2026-07-11T18-28-56Z`. This
  becomes part of the filename so every backup is unique and time-ordered.
- **`docker compose exec -T db pg_dump -U recurring -d recurring`** — run a command *inside a
  running container*:
  - `exec` = "run this in the already-running container" (vs. `run`, which starts a new one).
  - `-T` = **no TTY** — required when the output is piped or run non-interactively (like cron).
    Without it you get "the input device is not a TTY" errors.
  - `db` = which service (the Postgres container).
  - `pg_dump -U recurring -d recurring` = Postgres's dump tool: `-U` user, `-d` database. It
    prints the entire database as SQL to standard output.
- **`| gzip`** — compress that SQL stream (a `.sql` is very compressible — text).
- **`| aws s3 cp - "s3://…/db/recurring-<stamp>.sql.gz"`** — upload. The **`-`** means "read
  from **standard input**" instead of a file. So the compressed stream goes straight to S3.
- **`${BUCKET%/}`** — strips a trailing slash if you typed one, so we never get `s3://bucket//db`.

🎓 The whole thing is **one Unix pipeline**: dump | compress | upload. Each program does one job
and hands its output to the next. Nothing lands on disk. This is Unix philosophy in a single
line — and `pipefail` (from `set -o pipefail`) guarantees that if *any* stage fails, the whole
backup is reported as failed.

We ran it once by hand and verified the artifact really landed:
```bash
BACKUP_BUCKET=s3://<backup-bucket> ./scripts/backup.sh   # [SERVER]
aws s3 ls s3://<backup-bucket>/db/                        # → the .sql.gz, with a size
```
🎓 `aws s3 ls` = list objects. A backup you can *list and size* is real; a script that "ran
without error" but uploaded nothing is not. Always check the artifact exists.

---

## Part 5 — Automation with cron

A backup you have to *remember* to run isn't a backup. **cron** is Linux's built-in scheduler —
a background service (`crond`) that runs commands on a timetable. Each user has a **crontab**
(cron table) listing their scheduled jobs.

### What we installed
```cron
PATH=/usr/local/bin:/usr/bin:/bin
30 3 * * * BACKUP_BUCKET=s3://<backup-bucket> /home/ubuntu/honest-ledger/scripts/backup.sh >> /home/ubuntu/backup.log 2>&1
```

Decoding it:

- **The five time fields `30 3 * * *`** — `minute hour day-of-month month day-of-week`.
  `30 3 * * *` = **at 03:30, every day** (`*` means "any/every"). A few more examples:
  - `0 * * * *` = top of every hour
  - `*/15 * * * *` = every 15 minutes
  - `0 5 * * 1` = 05:00 every Monday (`1` = Monday)
  🎓 It runs on the **server's clock** — check with `date`; ours is UTC.
- **`PATH=/usr/local/bin:/usr/bin:/bin`** — 🎓 the classic cron gotcha. Cron runs jobs with a
  *bare* environment — a minimal PATH that does **not** include `/usr/local/bin`, where `aws`
  lives. Without this line, the job would fail with "aws: command not found" — even though it
  works perfectly when you type it. This line makes cron find the tools.
- **`>> /home/ubuntu/backup.log 2>&1`** — redirect output to a log file. `>>` **appends**
  (don't overwrite each night); `2>&1` means "send **stderr** (channel 2) to the same place as
  **stdout** (channel 1)" — i.e. capture errors too. 🎓 Cron is silent by default; an
  **unlogged cron job is a black box.** Now every run leaves a trace in `backup.log`.

### How we installed it (and dodged a bug)

The normal way is `crontab -e` (opens an editor). But **this terminal garbles multi-line
pastes** (we hit this exact bug twice — see `troubleshooting.md`), and it mangled the crontab:
the schedule vanished and `>>` became `<>`. So we installed it with a **single-line** command
instead:

```bash
( echo 'PATH=/usr/local/bin:/usr/bin:/bin'; echo '30 3 * * * BACKUP_BUCKET=s3://<backup-bucket> /home/ubuntu/honest-ledger/scripts/backup.sh >> /home/ubuntu/backup.log 2>&1' ) | crontab -
```
- **`( cmd1; cmd2 )`** — run both commands in a subshell; their combined output is the two lines.
- **`| crontab -`** — `crontab` with `-` means "read the new crontab **from standard input**."
  This *replaces* the whole crontab with those two lines. No editor, no multi-line paste, no bug.
- **`crontab -l`** — **l**ist the current crontab, to verify it stuck.

🎓 Lesson worth keeping: when an interactive editor + flaky paste fights you, sidestep it by
piping the content in as a single line. Same trick works for many "edit this file" situations.

---

## Part 6 — The test restore (the step everyone skips)

> 🎓 **A backup you have never restored is a rumor, not a backup.**

Backups fail silently all the time — truncated files, wrong format, missing permissions. The
only proof is to *restore one*. We did it **safely**, into a throwaway database that production
never notices:

```bash
# [SERVER], from ~/honest-ledger/backend

# 1. make a scratch database
docker compose exec -T db psql -U recurring -d postgres -c "CREATE DATABASE restore_test;"

# 2. download from S3 → decompress → load into the scratch DB
aws s3 cp s3://<backup-bucket>/db/recurring-2026-07-11T18-28-56Z.sql.gz - | gunzip | docker compose exec -T db psql -U recurring -d restore_test

# 3. prove the tables came back
docker compose exec -T db psql -U recurring -d restore_test -c "\dt"

# 4. clean up
docker compose exec -T db psql -U recurring -d postgres -c "DROP DATABASE restore_test;"
```

The new commands:

- **`psql -U recurring -d postgres -c "…"`** — `psql` is Postgres's command-line client.
  `-U` user, `-d` database, `-c` = "run this **one command** and exit." We connect to the
  built-in `postgres` database just to issue `CREATE DATABASE` / `DROP DATABASE` (you can't
  create a database while connected *to* it).
- **`aws s3 cp s3://… -`** — note the `-` is now the **destination**: "copy the S3 object to
  **standard output**." So it streams *down* from S3 (the reverse of the backup).
- **`| gunzip`** — decompress (the opposite of `gzip`).
- **`| psql … -d restore_test`** — feed the SQL into the scratch DB; it replays every
  `CREATE TABLE`, `COPY` (data), index, and constraint.
- **`\dt`** — a psql meta-command: "**d**escribe **t**ables" (list them).

The result: **all 15 tables rebuilt** (`borrowings`, `lenders`, `cards`, `users`,
`_yoyo_migration`, …), with the `COPY 9 / COPY 14 / …` lines showing real rows flowing back in.
🎓 That output *is* your **RTO demonstrated** — proof you can go from "S3 file" to "working
database" in minutes. Backups: genuinely done.

---

## The whole session, end to end (single flow)

Here's everything we did tonight, in order, condensed. `[LOCAL]` / `[SERVER]` / `[AWS]` = where.

```
── Run-scripts (rung 2 automation) ────────────────────────────────────────
[LOCAL]     wrote scripts/deploy.sh (server-side) + scripts/ship.sh (local-side),
          committed + pushed them to GitHub.
[SERVER]  (bootstrap) git pull once so the box has the scripts.
          → future deploys are now just:  [LOCAL] ./scripts/ship.sh

── DB access from laptop ──────────────────────────────────────────────────
[LOCAL]     ssh -i key -N -L 5433:localhost:5432 ubuntu@<ip>   (tunnel; GUI → localhost:5433)
          (Never open 5432 in the Security Group — weak DB password, firewall is its shield.)

── AWS account hardening (IAM) ────────────────────────────────────────────
[AWS root]  created IAM user admin-user + attached AdministratorAccess.
            (Saw deny-by-default live: new user = access denied everywhere until policy added.)
[AWS]       now sign in as admin-user, not root.   TODO: MFA on both.

── Permissions for backups (no stored keys) ───────────────────────────────
[AWS]     Policy  recurring-backup-s3   (S3 List/Read/Write on ONE bucket)
             ▼ attached to
          Role    recurringbackuprole   (EC2 trust + instance profile)
             ▼ attached to
          EC2     recurring-api (<INSTANCE_ID>)
[SERVER]  aws sts get-caller-identity → assumed-role ARN = it works, zero keys on disk.

── The backup itself ──────────────────────────────────────────────────────
[AWS]     S3 bucket <backup-bucket> (us-east-1, public access OFF,
          lifecycle: delete after 30 days).
[SERVER]  installed AWS CLI v2. Wrote/pulled scripts/backup.sh:
             docker compose exec -T db pg_dump | gzip | aws s3 cp - s3://…/db/<utc>.sql.gz
          ran it once by hand → aws s3 ls confirmed the .sql.gz landed.

── Automate it (cron) ─────────────────────────────────────────────────────
[SERVER]  crontab (installed via  ( echo…; echo… ) | crontab -  to dodge paste-garble):
             PATH=/usr/local/bin:/usr/bin:/bin
             30 3 * * *  BACKUP_BUCKET=…  …/scripts/backup.sh  >> ~/backup.log 2>&1
          → nightly backup at 03:30 server time, logged.

── Prove it (restore test) ────────────────────────────────────────────────
[SERVER]  CREATE DATABASE restore_test
          aws s3 cp …sql.gz - | gunzip | psql -d restore_test
          \dt → all 15 tables back.   DROP DATABASE restore_test.
          → RTO proven. Backups DONE. ✅
```

---

## Shell & terminal idioms decoded (the symbols we leaned on)

We used a lot of small shell notation. None of it is magic — here's every piece, generally, so
it transfers to *any* command you meet later.

### Redirection & pipes
| Symbol | Means | Example from this guide |
|--------|-------|-------------------------|
| `\|` | pipe: stdout of left → stdin of right | `pg_dump \| gzip \| aws s3 cp -` |
| `>` | write stdout to a file (**overwrite**) | `printf '%s\n' "$KEY" > ~/.ssh/id_ed25519` |
| `>>` | write stdout to a file (**append**) | `... >> ~/.ssh/authorized_keys` |
| `<` | feed a file **into** a program's stdin | `... "cat >> authorized_keys" < key.pub` |
| `2>&1` | send **stderr** to the same place as **stdout** | `... >> backup.log 2>&1` |
| `>/dev/null` | discard output (`/dev/null` = the trash) | `curl ... >/dev/null 2>&1` |
| `-` (as a filename) | use stdin/stdout instead of a real file | `aws s3 cp - s3://…` / `aws s3 cp s3://… -` |

🎓 Combined example: `ssh host "cat >> ~/.ssh/authorized_keys" < key.pub` — the `< key.pub` feeds
your local public-key file into the ssh command's stdin, and on the far side `cat >>` appends it
to the server's file. Two redirects, one line, no temp file.

### Chaining & grouping
| Symbol | Means |
|--------|-------|
| `;` | run commands in sequence, regardless of success |
| `&&` | run the next **only if** the previous succeeded (exit 0) |
| `\|\|` | run the next **only if** the previous **failed** |
| `( cmd1; cmd2 )` | **subshell**: run grouped commands; their combined output can be piped as one |

🎓 We used the subshell to build a two-line crontab and pipe it in:
`( echo 'LINE1'; echo 'LINE2' ) | crontab -`.

### Permissions: `chmod` and the number codes
Files have permissions for **owner / group / others**, each with **r**ead(4) **w**rite(2)
**e**xecute(1). Add them per role → a 3-digit octal:
| Code | Meaning | Used for |
|------|---------|----------|
| `600` | owner read+write; nobody else | private keys (`id_ed25519`), so SSH trusts them |
| `400` | owner read-only | `.pem` keys |
| `700` | owner full; nobody else | the `~/.ssh` folder |
| `755` | owner full; others read+execute | scripts/dirs everyone may run |

🎓 SSH **refuses** a private key that others can read (too loose) — that's why we `chmod 600` it.

### Quoting & variables
- **`"double quotes"`** allow variable expansion (`"$VAR"` becomes its value); **`'single
  quotes'`** are literal (no expansion) — we used single quotes in `echo '...'` so `$` and `*`
  stayed literal in the crontab line.
- **Always quote `"$VAR"`** so a value containing spaces isn't split into multiple arguments.
- **`printf '%s\n' "$X"`** is safer than `echo "$X"` for arbitrary data (like keys): `echo`
  mangles values that start with `-` or contain backslashes; `printf` prints them verbatim.
- Variable tricks: `${VAR:-default}` (use default if unset), `${VAR:?message}` (abort with a
  message if unset), `${VAR%/}` (strip a trailing slash). We used all three.

### SSH host verification (what `ssh-keyscan` and `known_hosts` are about)
The first time you SSH to a host, SSH asks "the authenticity of host … can't be established —
continue?" That's it checking the server's **host key** against your `~/.ssh/known_hosts` file to
detect impostors. Two ways we handled it non-interactively:
- **`ssh-keyscan -H host >> ~/.ssh/known_hosts`** — fetch the host key up front and record it, so
  ssh won't stop to ask (used in the CI runner).
- **`ssh -o StrictHostKeyChecking=accept-new`** — "trust a *new* host automatically, but still
  error if a known host's key ever changes."
🎓 This is **TOFU** — Trust On First Use. Convenient, and fine here; the stricter alternative is
to pin the known host key yourself.

### A couple more we ran
- **`grep -qF "text" file`** — `-F` treat the pattern as a **fixed string** (not a regex), `-q`
  **quiet** (print nothing, just succeed/fail). We used it to check "is this key already in
  authorized_keys?" before appending, so we don't add duplicates.
- **`sudo`** — run a command as the **superuser** (root), needed to touch system files/ports.
- **`<<'EOF' … EOF`** (a *heredoc*) — feed a multi-line block as stdin to a command; quoting the
  `EOF` keeps `$` literal. (Used in the earlier deployment notes for writing config files.)

---

## Commands reference (this session)

`[S]` = server · `[LOCAL]` = your computer. Every one we actually ran.

```bash
# Deploy loop
./scripts/ship.sh                                   # [LOCAL] push + remote deploy (one command)
git pull --ff-only                                  # [S] fetch, refuse messy merges
docker compose up -d --build                        # [S] rebuild + restart, background

# DB tunnel
ssh -i ~/Downloads/recurring-key.pem -N -L 5433:localhost:5432 ubuntu@203.0.113.10   # [LOCAL]

# AWS CLI basics
aws --version                                       # [S] check version (we have v2)
aws sts get-caller-identity                         # [S] "who am I?" — proves the role works
aws s3 ls s3://<backup-bucket>/db/        # [S] list backups
aws s3 cp <src> <dst>                               # copy; use "-" for stdin/stdout (streaming)

# Backup
BACKUP_BUCKET=s3://<backup-bucket> ./scripts/backup.sh                     # [S]
docker compose exec -T db pg_dump -U recurring -d recurring                          # dump
gzip / gunzip                                        # compress / decompress a stream

# Cron
crontab -l                                          # [S] list scheduled jobs
crontab -e                                          # [S] edit (we avoided this — paste bug)
( echo 'LINE1'; echo 'LINE2' ) | crontab -          # [S] install crontab from stdin

# Restore (into a scratch DB)
docker compose exec -T db psql -U recurring -d postgres -c "CREATE DATABASE restore_test;"  # [S]
aws s3 cp s3://…/x.sql.gz - | gunzip | docker compose exec -T db psql -U recurring -d restore_test  # [S]
docker compose exec -T db psql -U recurring -d restore_test -c "\dt"                        # [S]
docker compose exec -T db psql -U recurring -d postgres -c "DROP DATABASE restore_test;"    # [S]
```

### Flag glossary (the little letters, this session)
| Flag | Where | Means |
|------|-------|-------|
| `-e -u -o pipefail` | bash `set` | exit-on-error · error-on-unset · fail-a-pipe-if-any-stage-fails |
| `-N` | ssh | no remote shell — just hold the tunnel |
| `-L a:host:b` | ssh | forward local port `a` → `host:b` (as seen from the server) |
| `-T` | docker compose exec | no TTY — required for pipes / cron |
| `-U` / `-d` | pg_dump, psql | user / database |
| `-c` | psql | run one command and exit |
| `-` | aws s3 cp | read stdin (as source) or write stdout (as dest) — enables streaming |
| `-l` / `-e` | crontab | list / edit |
| `-u` | date | UTC |

---

## Going deeper (follow-ups for thorough knowledge)

Threads worth pulling when you're ready — each is a natural next question from what we did:

**IAM & security**
- **MFA** on root and `admin-user` (do this soon — it's the single biggest account-safety win).
- **IAM Groups** vs. attaching policies directly — how teams manage permissions at scale.
- **Rotate the DB password** off the default `recurring/recurring` (low risk since 5432 is
  firewalled, but good hygiene). Then move it into a secrets manager.
- **Roles vs. access keys** generally — why "assume a role" beats "hold a key" everywhere.

**Backups & databases**
- **Encryption at rest** — enable SSE (S3-managed or KMS) on the bucket so the dumps are
  encrypted in storage.
- **S3 Versioning + a lifecycle to Glacier** — cheaper long-term retention, protection against
  overwrite.
- **Point-in-time recovery (PITR)** via Postgres WAL archiving — restore to *any second*, not
  just last night (much lower RPO). This is what managed databases (RDS) do for you.
- **Restore drills** — schedule an occasional automated restore-test, so "it restores" is
  monitored, not assumed.
- **`pg_dump` formats** (`-Fc` custom format + `pg_restore`) — selective restore, parallelism.

**Automation & ops**
- **systemd timers** — a more modern, more debuggable alternative to cron (with logs in
  `journalctl`).
- **Monitoring/alerting** — get notified if a nightly backup *fails* or is suspiciously small.
- **Elastic IP** — pin the server's public address so it survives a stop/start (and the nip.io
  name stops changing).
- **GitHub Actions (CI/CD)** — the next thing we'll build: a robot that runs `deploy.sh` on
  every push. *(This doc will get a Part 7 once we do it.)*

---

## Facts for this session (so the doc is self-contained)

- **Server:** EC2 `t3.micro`, region **us-east-1** (AZ us-east-1c), instance `<INSTANCE_ID>`
  named `recurring-api`, public IP `203.0.113.10`, Ubuntu 26.04, user `ubuntu`, key
  `~/Downloads/recurring-key.pem`. App at `https://203-0-113-10.nip.io`.
- **AWS account:** `<ACCOUNT_ID>`. Daily user: `admin-user`.
- **Backup bucket:** `<backup-bucket>` (us-east-1, public access off, 30-day expiry).
- **IAM:** policy `recurring-backup-s3` → role `recurringbackuprole` → instance `<INSTANCE_ID>`.
- **Scripts (in repo):** `scripts/deploy.sh`, `scripts/ship.sh` (commit `ae19e7c`),
  `scripts/backup.sh` (commit `42e0e7f`).
- **Cron:** nightly `30 3 * * *` (server/UTC), logs to `/home/ubuntu/backup.log`.
- **AWS CLI:** v2 (2.31.35) on the server.

---

## Part 7 — Auto-deploy with GitHub Actions (CI/CD)

The final rung. So far *you* were the automation: you typed `./scripts/ship.sh`. Now we hand
that job to a robot. **After this, `git push` is your entire deploy** — nothing else.

### What CI/CD means

- **CI — Continuous Integration:** on every push, automatically *check* the code (run tests,
  linting). We're not doing this part yet, but it's where you'd add it.
- **CD — Continuous Deployment:** on every push to `main`, automatically *ship* it. That's what
  we built — the robot runs your `deploy.sh` instead of your finger.

🎓 The key insight: **the robot reuses the exact `deploy.sh` you already had.** We didn't invent
a new deploy mechanism; CI/CD is just "something presses the existing button for you." That's
why we built the script first — automation is only worth doing once the manual steps are solid.

### The picture

```
[LOCAL] git push ─► GitHub ─► spins up a "runner" (throwaway Linux VM)
                              │  reads 3 encrypted Secrets
                              │  writes the deploy key to a file
                              ▼
                            ssh into the server ─► ./scripts/deploy.sh ─► live
```

New vocabulary:
- **Runner** — the clean, throwaway computer GitHub gives you for each run. Fresh every time.
- **Secret** — an encrypted, write-only value stored in the repo settings. The workflow can use
  it; it's masked in logs; even you can't read it back (only overwrite). This is how credentials
  stay out of your source code.
- **Trigger** (`on:`) — the *when*. Ours is `push` to `main`.
- **Workflow** — a YAML file in `.github/workflows/` describing the steps.

### Piece 1 — a dedicated deploy key

We made a **separate** SSH key just for the robot (not reusing the personal `recurring-key.pem`):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/recurring-deploy -N "" -C "gh-actions-recurring-deploy"   # [LOCAL]
```
- **`-t ed25519`** — the key type (modern, small, fast — preferred over old RSA).
- **`-f …`** — the **f**ilename for the keypair (makes `recurring-deploy` + `recurring-deploy.pub`).
- **`-N ""`** — no passphrase (a robot can't type one).
- **`-C …`** — a **c**omment label, so you recognize the key later.

Then the **public** half goes onto the server (this is what says "trust this key"), and the
**private** half goes into a GitHub Secret:
```bash
# install the public key on the server (append to authorized_keys)   [LOCAL]
ssh -i ~/Downloads/recurring-key.pem ubuntu@203.0.113.10 "cat >> ~/.ssh/authorized_keys" < ~/.ssh/recurring-deploy.pub
```
🎓 A **separate key is independently revocable**: if a GitHub secret ever leaked, you delete this
one line from the server's `authorized_keys` and your personal access is unaffected. Least
privilege, applied to keys.

Copy the private key to the clipboard **without printing it** (it's the one secret that matters).
Pick the line for your OS (see [Ground floor → clipboard](#copying-to-the-clipboard-on-any-os-the-thing-that-prompted-this-rewrite)):
```bash
cat ~/.ssh/recurring-deploy | pbcopy                              # macOS
cat ~/.ssh/recurring-deploy | xclip -selection clipboard         # Linux (X11)
cat ~/.ssh/recurring-deploy | wl-copy                            # Linux (Wayland)
cat ~/.ssh/recurring-deploy | clip                              # Windows (Git Bash / cmd)
Get-Content ~/.ssh/recurring-deploy | Set-Clipboard              # Windows (PowerShell)
```
🎓 Same idea everywhere: **pipe the file into the OS clipboard tool** so the private key is copied
but never shown. Then paste it into the GitHub Secret.

### Piece 2 — three GitHub Secrets

In the repo: **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|--------|-------|
| `DEPLOY_SSH_KEY` | the private key (the whole `-----BEGIN…END-----` block) |
| `SERVER_HOST` | `203.0.113.10` |
| `SERVER_USER` | `ubuntu` |

🎓 Secret names allow only letters, numbers, and `_` — no spaces (so `DEPLOY_SSH_KEY`, not
`DEPLOY SSH KEY`).

### Piece 3 — the workflow file

`.github/workflows/deploy.yml`:
```yaml
name: Deploy to server
on:
  push:
    branches: [main]
concurrency:
  group: deploy-production
  cancel-in-progress: false
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy over SSH
        run: |
          mkdir -p ~/.ssh
          printf '%s\n' "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H "${{ secrets.SERVER_HOST }}" >> ~/.ssh/known_hosts 2>/dev/null
          ssh -i ~/.ssh/id_ed25519 "${{ secrets.SERVER_USER }}@${{ secrets.SERVER_HOST }}" \
            "cd honest-ledger && ./scripts/deploy.sh"
```
- **`on: push: branches: [main]`** — the trigger.
- **`concurrency`** — if you push twice quickly, the second deploy *queues* instead of colliding
  with the first on the server.
- **`runs-on: ubuntu-latest`** — the runner OS.
- **`${{ secrets.X }}`** — how a workflow reads a secret (masked in logs as `***`).
- **`ssh-keyscan -H host >> known_hosts`** — pre-loads the server's host key so ssh doesn't stop
  to ask "are you sure you want to connect?" (which would hang a non-interactive runner).
- **No `actions/checkout`** — 🎓 the runner never downloads your code, because the *server* pulls
  it in `deploy.sh`. The robot's only job is to log in and press the button.

### The bug we hit (and how the masked log still gave it away)

The first run failed in 6 seconds: **`hostname contains invalid characters`**. The masked log
showed the command as `ssh-keyscan -H " ***"` — a **space before the masked secret**. Cause:
the `SERVER_HOST` secret had been saved as ` 203.0.113.10` (a **leading space**, easily grabbed
when copy-pasting an IP). 🎓 Lesson: **even masked secrets reveal their shape** — the tell-tale
space was visible even though the value wasn't. We re-saved the secret cleanly and re-ran.

### Running & watching from the terminal (the `gh` CLI)

You don't need the browser — the GitHub CLI shows runs live:
```bash
gh run list --limit 3                 # recent runs + status
gh run view <run-id> --log-failed     # just the failing lines
gh run view <run-id> --log            # full log
gh run rerun <run-id>                 # re-run a job (reads secrets FRESH — no new commit needed)
```
🎓 That last one is why fixing a bad secret didn't need a dummy commit: secrets are read at run
time, so `gh run rerun` picked up the corrected `SERVER_HOST` immediately.

### The result

A push to `main` now triggers: runner boots → ssh in → `deploy.sh` runs (pull → rebuild →
recreate the API container → wait for `/ready`) → `OK: backend is ready`. **Fully hands-off
deploys.** The automation ladder is complete: manual → script → robot.

---

## Where the ladder stands now

| Rung | Thing | Status |
|------|-------|--------|
| 1 | Manual deploy | ✅ |
| 2 | Run-scripts (`deploy.sh` / `ship.sh`) | ✅ |
| — | Backups → S3 (nightly + restore-tested) | ✅ |
| 3 | GitHub Actions (auto-deploy on push) | ✅ |
| 4 | Terraform / IaC | later (learn-only; needs a 2nd environment) |

**Deferred hygiene (worth doing, none urgent):** MFA on root + `admin-user`; an **Elastic IP**
to pin the server's address (also stops `SERVER_HOST` and the nip.io name changing on a
stop/start); rotate the DB password off the default; optionally add a **path filter** to the
workflow so only `backend/**` changes trigger a deploy.

*Next up when you want it: Terraform (define the server itself as code) — a different ladder,
best tackled when you add a second environment.*

