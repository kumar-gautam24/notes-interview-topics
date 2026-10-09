# 10 · Questions From Your Own Projects

After your intro, interviewers dig into what you said. This file lists the questions each project will trigger, a simple answer, and the follow-ups that come after it.

**How to use it:** cover the answer, say yours out loud, then compare. Every answer follows the same shape: **what the problem was → what I did → why → what I gave up.** That last part matters. An answer with no trade-off sounds junior.

**[fill: …]** marks things only you know.

---

## Part A · Vaidya: credit wallet and payments

### A1. "How does the credit wallet work?"
> "Users buy credits, and each paid action costs credits. The balance is a row in Postgres. To deduct, I run **one SQL statement**:
> ```sql
> UPDATE wallets SET balance = balance - :cost
> WHERE user_id = :uid AND balance >= :cost
> RETURNING balance;
> ```
> If no row comes back, the user didn't have enough credits. Because the check and the update happen in **one statement**, two requests at the same time can't both pass the check."

**Follow-ups**
- **"Why not read the balance in Python, check it, then update?"** Two requests both read 100, both see enough, both deduct. That's a race condition. Doing it in one statement lets Postgres lock the row for you.
- **"What about `SELECT ... FOR UPDATE`?"** Also correct: lock the row, check, update, commit. Use it when the logic is too complex for one statement. The trade-off is that the lock is held longer, so it's slower under contention.
- **"How do you keep a history of credits?"** [fill: do you have a ledger/transactions table?] Good answer: every change also inserts a row into a **ledger** table in the **same transaction**, so the balance can always be rebuilt and audited.
- **"What if the deduction succeeds but the action fails afterwards?"** Refund with a compensating ledger entry, or deduct only after the action succeeds. [fill: which one Vaidya does]

### A2. "Walk me through your webhook handler."
> "Razorpay calls our endpoint when a payment succeeds or fails.
> 1. **Verify the signature.** Razorpay signs the raw body with HMAC-SHA256 using a shared secret. I compute the same hash and compare with `hmac.compare_digest`. If it doesn't match, return 400.
> 2. **Deduplicate.** Each event has an id. I store processed event ids with a **unique constraint**, so the same event processed twice is a no-op.
> 3. **Apply the change in a transaction**, for example add credits and mark the order paid.
> 4. **Return 200 quickly.** If I'm slow, Razorpay retries and I get duplicates."

**Follow-ups**
- **"Why `compare_digest` and not `==`?"** `==` stops at the first wrong character, so response time leaks how much matched (a timing attack). `compare_digest` always takes the same time.
- **"Why verify the raw body, not the parsed JSON?"** Parsing and re-serialising can change spacing or key order, and then the hash won't match.
- **"Two webhooks for the same payment arrive at the same moment?"** Both try to insert the event id; the unique constraint lets only one win. The other gets a conflict and returns 200 without doing anything.
- **"Webhooks arrive out of order: `failed` after `captured`?"** I keep a **state machine** on the order: only allowed transitions are applied (`created → paid`, never `paid → failed`). A late, older event is ignored.
- **"What if the webhook never arrives?"** That's why there's a **reconciliation job**: it periodically asks Razorpay for orders stuck in `created` and fixes them. Webhooks are the fast path, reconciliation is the safety net. ("Two paths for reliability.")
- **"Return 200 first, then process. What if processing then fails?"** If you return 200 before doing the work, Razorpay won't retry, so the work must be saved somewhere durable first (an events table or a queue) and retried from there. [fill: does Vaidya process inline or store-then-process?]

### A3. "What part of payments did you NOT own?"
> "The Razorpay dashboard configuration, the payment-flow endpoints that create orders, and the checkout UI were owned by Prithvi, a senior engineer. I owned the wallet, the deduction, the webhook handler and reconciliation."

Interviewers ask this to test honesty. A clear split makes everything else you say more believable.

---

## Part B · Vaidya: long-running jobs (Redis workers + SSE)

### B1. "You said some requests take minutes. How did you handle that?"
> "An HTTP request can't stay open for minutes: proxies time out, and if the app goes to the background the connection drops. So:
> 1. The API **validates and creates a run row** in Postgres, pushes a job to **Redis**, and returns the **run id** immediately.
> 2. **Workers** pick jobs from Redis and do the work, writing progress as they go.
> 3. The app opens an **SSE** stream for that run id and gets progress events. If the stream drops, it reconnects and continues from the saved state."

**Follow-ups**
- **"Why not FastAPI `BackgroundTasks`?"** BackgroundTasks runs in the same process after the response. If the pod restarts, the job is lost, and there's no retry. Fine for sending one email, not for minutes of important work.
- **"What happens if a worker crashes halfway?"** [fill: how Vaidya handles it] Good answer: the job is only acknowledged/removed when done; a crashed job becomes visible again after a timeout and another worker retries. Each step must be safe to run twice.
- **"Why SSE and not WebSockets?"** Updates only go server → client. SSE is plain HTTP, simpler, works through proxies and reconnects on its own. WebSockets are for two-way traffic like chat.
- **"How do you scale it?"** Add more workers. The API stays fast because it only enqueues. What you give up: more moving parts (Redis, workers, monitoring of queue length).
- **"How do you know the queue is backing up?"** Watch the queue length and job age, and alert when the oldest job is older than [fill: threshold].

### B2. "What was hard about it?"
> "Keeping it correct when things fail: duplicates, retries and clients that disconnect. The rule I followed is that **the database is the source of truth**, not the stream. The stream only shows what's already saved, so a reconnect never loses anything."

---

## Part C · Vaidya: auth service

### C1. "Tell me about a production bug you debugged."
Use the Apple Sign-In story. It's two bugs in a row, and both are server-side.

> "One Apple user was getting **userId 0**, only that user, and we couldn't reproduce it.
> **How I found it:** I added logs along each branch of the login function to see which path the request took in production.
> **Cause:** we'd recently added **soft delete**. Most queries were updated with `is_active = 1`, but the Apple Sign-In path still used an old `getUser` query without that filter. The user had deleted their account, and the old query returned the deleted row.
> **Fix:** updated the query, and checked every other path that loads a user.
>
> Right after that, a second bug: after logout, Apple users **couldn't log in again**. On logout we put the token id in Redis for 30 minutes to block it. Google gives a new token id on every login, but **Apple gives the same one**. So the new login matched the blocked id.
> **Fix:** [fill: what you changed, e.g. block by our own session id instead of the provider's token id]."

**Follow-ups**
- **"What did you learn?"** When you add a rule like soft delete, search for **every** query that loads that table, or put the rule in one shared function. And never assume all identity providers behave the same.
- **"How would you prevent this next time?"** One repository function to load users (so the filter lives in one place), and a test for each login provider.
- **"Why did Google work?"** Its token id is random per login, so the block never matched a new login.

### C2. "How do your tokens work?"
> "Short-lived **access token** (JWT, signed, carries user id and role) and a longer-lived **refresh token** stored in the database so it can be revoked. On logout we delete the refresh token and block the access token's id in Redis until it expires."

**Follow-ups**
- **"Why not just a long-lived JWT?"** You can't revoke a JWT before it expires, so if it's stolen it works until then. Short access tokens limit the damage.
- **"What do other services check?"** The signature and expiry, using the shared key, without calling the auth service on every request. That's why the token format is a contract other services depend on.
- **"401 vs 403?"** 401: we don't know who you are (missing or bad token). 403: we know who you are, but you're not allowed.

---

## Part D · Vaidya: performance

### D1. "OTP went from 8–10 seconds to 500 ms. How?"
> "The login API was sending the OTP email **inside the request**, waiting for the email provider to respond. I moved the sending off the request path, so the API saves the OTP, queues the send and returns. The email provider was the slow part, not our code."

**Follow-ups**
- **"How did you find it?"** [fill: logs with timings per step / tracing]. Good answer: timing logs around each step showed almost all the time was the email call.
- **"What if the email then fails?"** Retry in the background, and let the user tap "resend". The trade-off: the API says "sent" before it's actually delivered.

### D2. "Tell me about a blocking call in async code."
> "We used a **synchronous database driver inside `async def` routes**. While one query waited, the whole event loop was blocked, so every other request on that worker waited too. Under load everything slowed down at once. The fix is an async driver (asyncpg), or running sync code in a threadpool, or making the route a plain `def` so FastAPI runs it in a thread."

**Follow-up:** "How did you notice?" Latency went up for **all** endpoints together, even simple ones. That pattern points to a blocked event loop, not one slow query.

### D3. "Your pool was capped at 10. Why does that matter?"
> "Each pod × worker has its own pool. Total connections = pods × workers × pool size, and it must stay under Postgres' `max_connections`. Scaling pods up can run Postgres out of connections. PgBouncer helps by sharing a small number of real connections."

---

## Part E · Vaidya: ABDM integration and the 403

### E1. "Tell me about an integration that went wrong."
> "We integrate with **ABDM**, India's national health ID system. Calls started failing with **403**. Our code and credentials were correct. The cause was that ABDM's **CloudFront firewall was blocking our server's IP**, because our server was in an **Azure region in the US**. The fix is to send ABDM traffic from an **Indian IP**: either a small proxy in Azure Central India or moving the service to an Indian region, and registering that **static outbound IP** with the ABDM authority before go-live."

**Follow-ups**
- **"How did you know it wasn't your code?"** 403 came from the CDN layer, not the API itself ([fill: the response headers/body that showed CloudFront]). Same request from an Indian network worked. [fill: confirm]
- **"Why a static IP?"** The partner allow-lists IPs. Cloud servers get a new outbound IP when they restart unless you reserve one (a NAT gateway or a fixed-IP proxy).
- **"Trade-off of the proxy?"** One extra hop and one more thing that can go down, plus a monthly cost. A region move is cleaner but a bigger change.

---

## Part F · Vaidya Insurance: the gateway

### F1. "What does the gateway between the app and AI services do?"
> "The app talks only to the gateway. The gateway **checks auth, validates input with Pydantic, calls the internal services, and turns their errors into one consistent error format** for the app. So the app doesn't know about internal URLs or each service's quirks."

**Follow-ups**
- **"What if an internal service is slow?"** Set **timeouts** on every outgoing call (never wait forever), return a clear error, and retry only safe calls. A **circuit breaker** stops calling a service that keeps failing.
- **"Isn't that a single point of failure?"** Yes, so it runs as multiple pods behind a load balancer and holds no state.
- **"Why not let the app call services directly?"** Auth and validation would be duplicated in every service, internal services would be exposed, and every internal change would break old app versions.
- **Pattern names** (see [08-design-patterns.md](08-design-patterns.md)): Facade/Gateway, Adapter for each service's response shape.

---

## Part G · Observability

### G1. "How do you know something is broken in production?"
> "On the Vaidya app I set up Crashlytics, Analytics and Performance Monitoring. Failed API calls are logged as non-fatal errors with the endpoint, user id and app version, so we can see which users fail and what they did before. Once, every API was failing at the same time, and the logs showed the **base URL was missing** in a build, which we'd have taken much longer to find otherwise."

**Follow-up you should expect for a backend role:** "And on the backend?"
> "The same three ideas: **logs** (structured JSON with a request id on every line), **metrics** (request rate, errors, latency p95, queue length) and **traces** (one request's path across services). I'd add a request-id middleware first, because it ties every log line of one request together."

Don't call Firebase "OpenTelemetry". It isn't.

---

## Part H · Manpower Management (multi-tenant, Go)

This is your **real multi-tenant story**, which the screener flagged as a weak area. Use it.

### H1. "How did you make it multi-tenant?"
> "One database, shared tables, and every table has a **`company_id`**. The company comes from the **logged-in user's token**, never from the request body, and **every query filters by it**. On top of that is **role-based access** with 4 levels, which decides what a user can do *inside* their company."

**Follow-ups**
- **"What's the difference between tenant isolation and RBAC?"** Isolation: you can never see another company's data. RBAC: inside your company, what you're allowed to do. You need both. RBAC alone doesn't stop a query from leaking another company's rows.
- **"What if a developer forgets the `company_id` filter?"** That's the main risk. Defences: put the filter in one repository layer, add tests that try to read another tenant's data, and use **Postgres Row-Level Security** as a database-level safety net.
- **"Indexes?"** Put `company_id` first in composite indexes, e.g. `(company_id, status)`, since almost every query filters by company.
- **"When would you give a tenant its own database?"** A very large client, or a legal requirement. The trade-off is many databases to migrate and monitor.

### H2. "What's the compliance engine?"
> "It checks employee documents (visas, permits) for expiry, grace periods and penalties. I wrote it as **pure functions**: input data in, result out, with no database or HTTP inside. So I can test every rule without a server, and a scheduled background job runs it daily."

**Follow-up:** "Why pure functions?" Easy to test, easy to change rules, and the same logic can run from an API call or a scheduled job.

### H3. "Files?"
> "Documents go to **Cloudflare R2** (S3-compatible). The API gives the client a short-lived **signed URL** to upload or download directly, so big files don't pass through our server."

### H4. "Why Go, for a Python role?" → see [09-self-intro.md](09-self-intro.md#backend-follow-ups).

---

## Part I · Learning projects (only if they ask "what are you learning?")

### I1. "Your book project uses raw SQL with psycopg2. Why no ORM?"
> "On purpose, to learn what the ORM hides: parameterised queries, transactions, and how JOINs actually run. In a team project I'd use an ORM or a query builder for speed, but I'd still check the SQL it generates for N+1 problems."

Follow-up: **"How do you prevent SQL injection?"** Always pass values as parameters (`%s` with psycopg2), never build SQL with f-strings.

### I2. "Event booking project" (mention only once it actually works end to end)
It's the same problem as the ticketing question in the client's bank (see [07-mock-interview-log.md](07-mock-interview-log.md)): atomic seat reservation and Razorpay webhooks as the only source of payment truth. Finishing it gives you a real answer to that question. Right now it's a spec and a hello-world, so don't present it as built.

---

## Part J · If they open your GitHub

- Your public repos include two FastAPI multi-service projects (`deflect`, `pramana`). Present them as **backend** work (FastAPI services, Postgres, Redis streams, tests, CI), not AI work.
- Their commit history is very fast (dozens of commits a day). If asked, be straight: "I used AI coding tools heavily, and I can explain every design decision." Then make sure you **can**: pick the 3 main design decisions in each and practise explaining them without notes.
- Don't quote metrics you can't explain.

---

## Rapid-fire check (answer each in one sentence)

1. Why one SQL statement for the wallet deduction?
2. What makes a webhook handler idempotent?
3. Webhook vs reconciliation: which one is the safety net?
4. Why not BackgroundTasks for minutes-long work?
5. SSE or WebSocket for progress, and why?
6. Why did the Apple user get userId 0?
7. Why did Apple users get blocked after logout but Google users didn't?
8. What blocked the event loop?
9. Why did ABDM return 403?
10. Tenant isolation vs RBAC?
11. Where does `company_id` come from in a request?
12. Why pure functions for the compliance engine?
