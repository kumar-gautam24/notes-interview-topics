# Understanding Docker (the thing doing the heavy lifting)

Docker is what let us take an app off a laptop and run it, unchanged, on a server. It deserves its
own file because if you get Docker, deployment stops feeling like magic. Let's build the mental model
before touching commands.

---

## The problem Docker solves

Ever heard "but it works on my machine"? That's the disease. Your app needs a specific Python version,
specific libraries, specific settings — and the server has *different* versions of everything. Getting
them to match by hand is misery.

🎓 Docker's cure: **package the app together with its entire environment into one sealed box.** That
box runs *identically* everywhere — your laptop, the server, a colleague's machine. You stop shipping
"the app" and start shipping "the app *and* the machine it likes to run in." "Works on my machine"
becomes "the machine comes along for the ride."

## The four words you need

- **Image** — a frozen, read-only *template* of your app + its environment. Think of it as a recipe,
  or a class in code. You build it once from a `Dockerfile` (the list of build instructions).
- **Container** — a *running copy* of an image. If the image is the recipe, the container is the
  cooked meal; if the image is the class, the container is the object. You can run many containers
  from one image.
- **Volume** — storage that lives *outside* the container, so important data (like the database)
  isn't lost when you rebuild the container. Containers are disposable; volumes are permanent.
- **The Docker engine** — the background service on the server that actually runs containers and keeps
  them alive after you log off.

And one tool on top:

- **Docker Compose** — for running *several* containers together as a set. Our app is two containers
  (the API and the Postgres database), described in one `docker-compose.yml` file. One command brings
  the whole set up.

## Port mapping: connecting the box to the outside

A container is sealed, with its own private network inside. So how does Nginx (running on the server)
reach the app (running *inside* a container)? **Port mapping** pokes a labeled hole in the box:

```
   8000:8000
   └─┬─┘ └─┬─┘
  host   container
  door    door
```

Read it as: *"traffic arriving at port 8000 on the server → send it to port 8000 inside the
container."* Left is the server's door, right is the container's door. That one mapping is how Nginx
on `localhost:8000` reaches uvicorn living inside the box.

## Why Docker ate our disk (layers & cache)

🎓 An image is built in **layers** — one per step in the `Dockerfile`. Docker caches these layers so
that rebuilding is fast (unchanged steps are reused). The catch: that cache piles up on disk, and
every `--build` can add more. Combine that with base images (`python`, `postgres`) that are hundreds
of megabytes *each*, and you understand why Docker is a disk hog — and why our 8 GB server filled up.
The cure is `docker builder prune -f`, which clears the cache safely.

---

## Our actual setup, decoded

Three files make it work — worth knowing what each does:

- **`Dockerfile`** — the recipe for the app's image: start from Python 3.12, install the exact
  dependencies (locked in `uv.lock`), copy in the code, and set the startup command.
- **`entrypoint.sh`** — runs every time the container starts. It does two things in order: **apply any
  new database migrations**, then **start the web server**. 🎓 This is the quiet hero of easy deploys —
  because migrations run automatically on startup, deploying a database change needs *no* extra step.
- **`docker-compose.yml`** — describes the two containers together:
  - `db` — Postgres, with a **volume** so the data survives restarts, and a **healthcheck** so the app
    politely waits until the database is truly ready before starting.
  - `api` — our app, built from the `Dockerfile`, reading its settings from `.env`, and told to wait
    for `db` to be healthy first.

---

## The commands, and what each is *for*

You don't need to memorize these — you need to know *which one to reach for*. Here's the thinking:

**"Start everything."**
```bash
docker compose up -d --build
```
`--build` = rebuild the image from the latest code first. `-d` = run detached (in the background) so
you get your prompt back. This one command builds, starts the database, waits for it, runs migrations,
and starts the app.

**"Is it running? Is it healthy?"**
```bash
docker compose ps
```

**"What is the app actually doing right now?"**
```bash
docker compose logs -f api        # follow live (Ctrl-C stops WATCHING, not the app)
docker compose logs api --tail 40 # just the last 40 lines
```
🎓 This is your window into a running app. When we hit a mysterious bug, the logs showed us the truth
that our theory got wrong. Always look here first.

**"Let me poke around *inside* the running container."**
```bash
docker compose exec api bash                          # open a shell inside it; 'exit' to leave
docker compose exec api grep -n '@app.get' app/main.py # or run one command inside it
```
🎓 This is like SSHing one level deeper — from the server *into* the container. We used it to check
what code the container was *really* running. ⚠️ But remember: **anything you change inside a
container is temporary** — it's wiped on the next rebuild. `exec` is for looking and debugging, never
for editing real code. (Same rule as "don't edit code on the server.")

**"How much disk is Docker using?"**
```bash
docker system df          # images / containers / volumes / build cache
docker builder prune -f   # reclaim the build cache (safe — won't touch running things)
```

## Commands you'll meet soon

```bash
docker compose down            # stop & remove the containers (your DATA/volume is kept)
docker compose down -v         # ⚠️ ...also delete volumes — this DESTROYS the database
docker compose restart api     # bounce just one service
docker compose up -d           # start again WITHOUT rebuilding (e.g. after an .env-only change)
docker compose pull            # grab newer versions of prebuilt images (like postgres)
```

🎓 Burn one distinction into memory: **`down` keeps your database; `down -v` deletes it.** The `-v`
has erased many people's data. Treat it with respect.

---

## Putting it together: the deploy

Now the update loop makes complete sense:
```bash
git pull                       # get the new code onto the server
docker compose up -d --build   # rebuild the app image, swap in the new container
```
Compose only recreates what changed — the database container and its volume stay exactly where they
are, and migrations apply themselves on startup. That's the whole deploy, and now you know *why* each
part works.
