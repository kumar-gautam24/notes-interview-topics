# Interview & Engineering Notes

In-depth, teaching-style notes for interview prep and real engineering — organized by topic.
Every note aims to teach the *why*, not just list commands, so you can perform (in an interview
or on the job), not just recognize definitions.

## How this repo is organized

Two kinds of material live here, and it helps to know which you're reading:

- **Generic topic references** — reusable deep-dives on a technology (Docker, Kubernetes, SQL,
  system design). Not tied to any one project.
- **Applied case studies / courses** — the same ideas taught by walking through a *real*
  codebase end to end. These keep their project context on purpose (it's what makes them stick).

## Map

| Folder | What's inside | Kind |
|--------|---------------|------|
| [`ai-backend/`](ai-backend) | `answers/` (a 612-question answer bank, Python → system design, with the failure modes) · `study-pack/` (30-day roadmap, question bank, cheat sheet, evidence tracker) | Reference + prep |
| [`backend/`](backend) | `fastapi-course/` (generic FastAPI learning course) · `case-study-payment-svc/` (a real Razorpay payments/credits microservice, taught 01→23) | Course + case study |
| [`databases/`](databases) | Database concepts → SQL & PostgreSQL → DBMS theory → SQL interview Q&A → databases at scale · `postgres-sql-course/` (a five-part taught course ending in a runnable lab) | Reference + course |
| [`deployment-devops/`](deployment-devops) | `servers-and-deployment/` (deploy a backend to a real server, 0→1) · `docker/` (fundamentals→production) · `kubernetes/` (fundamentals→operations) | Reference + case study |
| [`system-design/`](system-design) | System design from first principles | Reference |
| [`go/`](go) | Go language fundamentals + backend development with Go | Reference |
| [`flutter/`](flutter) | Rendering internals, layout, rebuilds, common bugs, interview Qs · `mobile-app/` (build/release, deep links, speech) · `api-monitor/` (a package) · `dartpad-snippets/` | Reference + project |
| [`dsa/`](dsa) | LeetCode cheatsheets (C++/Java/Dart) + Amazon SDE last-minute | Reference |
| [`fundamentals/`](fundamentals) | Git (workflow guide + cheatsheet) · OOP concepts | Reference |
| [`interview-prep/`](interview-prep) | Company/role survival guides (Visa, Amazon) + general technical-interview theory | Prep |
| [`personal/`](personal) | Self-intro + roadmap/calendar/planning docs | Personal |

## Suggested entry points

- **Deploying a backend from zero:** [`deployment-devops/servers-and-deployment/README.md`](deployment-devops/servers-and-deployment/README.md)
  → then [`backups-iam-and-automation.md`](deployment-devops/servers-and-deployment/backups-iam-and-automation.md) (backups, IAM, CI/CD, OS-agnostic).
- **Learning FastAPI properly:** [`backend/fastapi-course/README.md`](backend/fastapi-course/README.md).
- **How a real payments microservice is built:** [`backend/case-study-payment-svc/01-project-overview.md`](backend/case-study-payment-svc/01-project-overview.md).
- **Learning SQL properly, Postgres-first:** [`databases/postgres-sql-course/README.md`](databases/postgres-sql-course/README.md)
  → Parts 1–4 teach, [`05-practice-lab.md`](databases/postgres-sql-course/05-practice-lab.md) makes you prove it.
- **Interview prep for AI/backend roles:** [`ai-backend/answers/README.md`](ai-backend/answers/README.md)
  (612 worked answers) · [`ai-backend/study-pack/01-30-day-roadmap.md`](ai-backend/study-pack/01-30-day-roadmap.md) (if you want a schedule).
- **Docker / Kubernetes deep dives:** [`deployment-devops/docker/`](deployment-devops/docker) · [`deployment-devops/kubernetes/`](deployment-devops/kubernetes).

## Conventions

- Files are numbered (`NN-topic.md`) where reading order matters; read them in sequence.
- `[LOCAL]` = run on your own machine (any OS) · `[SERVER]` = run on the remote server.
- 🎓 marks a concept worth internalizing.
