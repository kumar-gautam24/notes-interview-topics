# 09 · Self-Introductions: Backend, SDE, Flutter

Three intros for three kinds of roles: **backend**, **general SDE** and **Flutter/mobile**. Each comes in 30-second, 90-second and 2-minute versions. Every version is written out in full, so you can practise it as is.

They all draw from one **project bank** (Part 1). When an interviewer says "tell me more about X", the bank has the detail to say next. **[fill: …]** marks things only you can confirm.

| Interview for | Go to |
|---|---|
| Python / FastAPI backend (Headstart) | [Track A](#track-a--backend-python--fastapi) |
| General SDE / software engineer | [Track B](#track-b--sde-general-software-engineer) |
| Flutter / mobile | [Track C](#track-c--flutter--mobile) |
| Questions after any intro | [Part 3](#part-3--follow-ups-for-every-track) |

**Rules for every intro**
1. **Order:** who I am → where I work → 3 strongest things I built, each with a number or a hard problem → one debugging story → why this role.
2. **90 seconds is the default.** Stop there and let them choose what to dig into. A short intro that makes them curious beats a long one that answers everything.
3. Every claim gets **one concrete detail**: a number, a design decision, or the hard part. "I built auth" is weak. "I own the auth service, including the token format every other service checks" is strong.
4. Say **"I built"** or **"I own"**, and only for what you did. On payments, say you built the wallet and webhook side. Prithvi did checkout.
5. Never call Manpower Management "vibe-coded". You designed it, reviewed every line and run it in production for a paying client.

---

# Part 1 · Your project bank

Read this once so every project is fresh. Each row says **what it is**, **your strongest point**, and **the detail to give if they ask more**.

## 1.1 Timeline

| When | Where | What |
|---|---|---|
| 2020–2024 | Darbhanga College of Engineering | B.Tech CSE. Competitive programming, hackathons |
| Sept 2023 – Aug 2024 | MithilaStack (intern) | Sole engineer on EduDoor |
| Feb 2025 – Oct 2025 | Ailoitte Technologies | Client apps: **Guardian Bubble** (major), MyCard, Nile Source, Kailado, Golden Bridge |
| Oct 2025 – present | Ailoitte, contracted to **Fractal Analytics** | **Vaidya AI** (major) and Vaidya Insurance: Flutter app + FastAPI backend |
| Alongside | Own / freelance | Recurring (App Store), Manpower Management (UAE client), Stac open source, Flittz, Revilo, MedCompass, Flutter web |

[fill: confirm where Flittz, Revilo, MedCompass and the Flutter web app fit in time: college, internship, Ailoitte or freelance]

## 1.2 Backend work

**Vaidya AI backend** (FastAPI, PostgreSQL, Redis) · *your main backend story*
- **Owns auth, admin and billing services**, including the **token contract every other service validates against**.
- **Credit wallet:** deduction is one atomic SQL statement (`WHERE balance >= cost`), not read-then-write, so simultaneous requests can't overspend.
- **Webhooks:** HMAC-SHA256 verification, duplicate events ignored, a **PostgreSQL state machine** that only allows forward transitions so a late webhook can't corrupt a subscription, and a **reconciliation job** for webhooks that never arrive.
- **Long-running pipeline:** the API accepts a case, returns a **run id** at once, **Redis-queued workers** do the multi-minute run, and the client gets progress over **SSE**. No HTTP timeout can kill the run.
- **Workflow orchestration:** a turn manager running **36–40 steps across 6 phases**, calling a layer of **29 internal tools**. Every step's output is **validated with a Pydantic schema** and saved before the next step runs, so bad output fails where it was produced instead of corrupting later steps.
- **Performance:** OTP delivery **8–10s → ~500ms** (slow email call moved off the request path). Found a **sync DB driver blocking the event loop** in async endpoints, and **connection pools capped at 10** per service.
- **Debugging without a repro:** a login failure for specific users (soft delete left an old query returning a deleted account), then **every Apple Sign-In user locked out after logout** (the Redis block was keyed on a token id Apple reuses and Google doesn't).
- **ABDM integration:** India's national health ID system. Diagnosed a **403 from a CloudFront firewall** blocking the US-region server IP. The fix routes traffic through an Indian IP registered with the authority.
- Billing split: Prithvi (senior) owned Razorpay dashboard config, payment-flow endpoints and checkout UI.

**Vaidya Insurance backend**
- Built the **platform APIs**, the **insurance APIs** and **auth**.
- Built the **gateway between the app and the AI services**: one place for auth, Pydantic validation and a consistent error format, so the app never sees internal services.

**Recurring** (personal project, live on the App Store) · *your best "built it end to end" story*
- Personal-finance app: tracks EMIs, loans, subscriptions and card bills, and shows the **true cost of a "No Cost EMI"** after GST and fees. **Flutter app and FastAPI + PostgreSQL backend, both yours.**
- **Offline-first sync:** client-generated UUIDs make creates safe to retry (a retry returns 200, not a duplicate); updates carry `updated_at` and get **409 with the current row** if stale; deletes are tombstones; a **sequence-number change feed** lets an offline client catch up.
- **Money as integer paise**, never floats. Raw SQL over **asyncpg**, hand-written migrations, **argon2** passwords, JWT access + refresh **with rotation and revocation** (changing the password logs out every session), per-IP rate limiting on auth, structured logs, **integration tests against a real Postgres**.

**Manpower Management System** (production, paying UAE client) · *your multi-tenant story*
- **Multi-tenant** backend, ~**50 REST APIs**, JWT, **4-level RBAC**, **178+ employees across 6+ companies**. Written in Go (Chi).
- Moved documents from **Postgres blobs to Cloudflare R2 with signed URLs**, so document reads stopped competing with normal queries.
- **Compliance engine as pure functions** (document status, grace periods, configurable penalties), separate from HTTP and the database, so the most important rules are testable without either.

## 1.3 Mobile work

**Vaidya AI app** (Flutter, live on App Store and Play Store) · *major project*
- **Owns the architecture:** Clean Architecture, BLoC, sync and lock managers, secure storage, localization.
- Built the team's **base project template** (folder structure, naming, Husky pre-commit lint/format checks), **later used on other Flutter projects**.
- **Health data sync** from HealthKit and Health Connect: **10,600+ entries per user**, processed in **isolates** in chunks, aggregated per day, with last-synced tracking.
- **Background sync engine:** iOS is woken by the OS when new data arrives (~30s budget); Android is scheduled with WorkManager (~30 min). Both run **one shared Dart sync engine**. Records have deterministic ids, so retries are harmless. **Only the foreground moves the sync cursor.** Ran a **7–8 day multi-user field test**.
- **Cold start 3.5s → under 1s (71%)** and **app size −35%**: parallel initialisation, a trimmed dependency tree, and removing a main-thread serialization bottleneck.
- **Security:** SSL pinning, root/jailbreak detection, obfuscation, encrypted storage. Fixed the **iOS Keychain keeping credentials after uninstall**.
- **Real-time chat** over WebSocket with cache-first refresh and speech-to-text.
- **Observability (your own idea):** Crashlytics fatal + non-fatal with breadcrumbs and custom keys, Analytics, Performance Monitoring. It once showed every API failing because a build was **missing the base URL**.
- **iOS white screen at launch:** zero repro steps, the #1 user complaint. Cause: a malformed token plus corrupted navigation state.

**Guardian Bubble** (Flutter, parental control, live on App Store) · *major project, inherited codebase*
- **SOS that fires even when the app is killed**, with **critical alerts that bypass Do Not Disturb** and a live audio room. Found why the **first alarm after a cold boot was silent** (audio codec not ready) using `adb logcat`.
- **Live location over sockets** with ETA, distance and bearing; **Douglas-Peucker + KDE smoothing** for flicker-free routes; map matching with Google and Mapbox.
- **Isolates** for large JSON and syncing **1,000+ contacts** without freezing the UI. **Multi-device switching** that keeps state.
- Android PoC: **VPN + accessibility service** reading on-screen text to detect adult content.
- **Modernised the inherited code:** moved off deprecated APIs to Clean Architecture, added Husky hooks and **unit tests that caught a parsing bug before release** that would have broken location history. RevenueCat subscriptions.

**Other apps** [fill: one line each with your role and one number or hard problem]
- **Flittz:** Flutter app, **10K+ downloads**. [fill: what it is, what you built]
- **Revilo:** [fill]
- **MedCompass:** Flutter **Windows desktop** app. [fill: what it does; any desktop-specific challenge like packaging, file system, window management]
- **Flutter web app:** [fill: which one, what it did]
- **EduDoor (MithilaStack):** sole engineer from Figma to Play Store; auth, role-based flows, search, REST, push notifications; designed the architecture and mentored juniors.

**Open source**
- **Stac** (server-driven UI for Flutter, 786+ stars): your PR adding a **badge widget and its JSON parser** was merged.

**Firefighting on client apps** (great for "learn fast" and "pressure" questions)
- **Kailado (React Native):** a security audit found **tokens surviving logout** and the app was pulled. You fixed the P0 in **under 24 hours with no prior React Native experience**.
- **MyCard:** a **20+ second splash hang** on slow devices, caused by deep-link processing at startup; deferred it.
- **Nile Source:** inherited a broken codebase and **closed 40+ bugs in one week** to unblock a stalled release.
- **Golden Bridge:** loan app; production performance and accessibility fixes under time pressure.

## 1.4 Foundations
- **CodeChef rank 32 of 5,000+** (2022), **Google Kickstart** (2021), **GATE CS** (2023).
- **Hackathons:** **Manthan 2021**, **Smart India Hackathon 2022 (finalist)**, **Smart India Hackathon 2024**. [fill: what you built at SIH 2022 and results for Manthan and SIH 2024]

---

# Part 2 · The intros

## Track A · Backend (Python / FastAPI)

Lead with the server. Mobile appears once, as the reason you design good APIs.

### A · 30 seconds
> "Hi, I'm Gautam, a software engineer at Ailoitte Technologies with about two years of experience. I work on **Vaidya AI**, a healthcare platform we build for Fractal Analytics, where I own the **auth, admin and billing services** in **FastAPI, PostgreSQL and Redis**. I built the credit wallet and payment webhooks so money stays correct under concurrency and retries, and the job flow that runs multi-minute work on Redis workers and streams progress over SSE. I started on mobile and moved into backend ownership, and that's where I'm going deeper."

### A · 90 seconds (default)
> "Hi, I'm Gautam. I'm a software engineer at **Ailoitte Technologies** in Bangalore, and I work on **Vaidya AI**, a healthcare platform we build for **Fractal Analytics**. I started on the mobile app and **took over backend ownership** as the product grew. Today I own the **auth, admin and billing services** in FastAPI and PostgreSQL, including the token format every other service validates.
>
> Three things I'm proud of there:
>
> **First, billing.** The credit wallet deducts in **one atomic SQL statement**, so two requests at the same moment can't overspend. Razorpay webhooks are **HMAC-verified**, duplicates are ignored, a **state machine** stops a late webhook from moving a subscription backwards, and a **reconciliation job** catches webhooks that never arrive.
>
> **Second, long-running work.** Some requests take minutes. The API returns a **run id** immediately, **Redis workers** do the work, and the app follows progress over **SSE**, so no HTTP timeout can kill a run.
>
> **Third, performance.** I took OTP delivery from **8–10 seconds to about half a second**, and found a **synchronous database driver blocking the event loop** in our async services.
>
> Outside Vaidya, I built **Recurring**, a finance app on the App Store with an **offline-first FastAPI backend**, and I run a **multi-tenant backend** in production for a UAE client across six companies.
>
> Headstart is a multi-tenant CRM with a lot of data and background work, which is exactly where I want to go deeper."

### A · 2 minutes
> "Hi, I'm Gautam. I studied Computer Science at **Darbhanga College of Engineering**, graduating in 2024. In college I did a lot of competitive programming, **CodeChef rank 32 out of 5,000+**, Google Kickstart, and I qualified **GATE CS**. I also did hackathons: **Manthan 2021**, and **Smart India Hackathon 2022, where we were finalists**, and 2024. In my final year I was the only engineer at **MithilaStack** on **EduDoor**, a jobs marketplace for schools, from design to the Play Store.
>
> I joined **Ailoitte** in February 2025. I started on mobile apps and moved into backend. Since October 2025 I've been on **Vaidya AI** for **Fractal Analytics**, where I own the **auth, admin and billing services**.
>
> On **billing**, the wallet deducts credits in **one atomic SQL statement**, webhooks are **HMAC-verified and idempotent**, a **Postgres state machine** only allows forward transitions, and **reconciliation** catches missed webhooks.
>
> For the **pipeline**, the API returns a **run id**, **Redis workers** run the job, and progress streams over **SSE**. I also built the **orchestrator** that runs **36 to 40 steps across six phases** with **29 internal tools**, and every step's output is **validated with Pydantic** before the next one runs, so bad data fails early instead of spreading.
>
> I've also fixed production problems with no reproduction: users locked out after **Apple Sign-In** because Apple reuses a token id our logout block-list was keyed on, and a **blocking database driver** inside async code.
>
> On my own, I built **Recurring**, a personal-finance app on the App Store. Both the Flutter app and the **FastAPI backend** are mine. It has **offline-first sync** with client UUIDs, conflict detection with 409s, and money stored as integer paise. I also run a **multi-tenant backend** in production for a UAE client: about **50 APIs, four-level RBAC, 178+ employees across six companies**.
>
> I'm looking to go deeper into multi-tenant systems and data at scale, which is why Headstart interests me."

### Backend follow-ups

**"Why backend, when you started in mobile?"**
> "On the app I kept running into problems that started on the server: slow APIs, payment edge cases, login bugs. I wanted to fix them at the source. At Vaidya I took on backend work and ended up owning services. Mobile experience helps: I design APIs for bad networks, retries and old app versions, because I've been on the other side."

**"Which backend work are you proudest of?"**
> "The wallet and webhooks, because money has to be exactly right. I listed what could go wrong and built for each: two spends at once (atomic update), the same webhook twice (unique event id), webhooks out of order (state machine), a webhook never arriving (reconciliation). Each failure has its own guard."

**"Tell me about Recurring's sync."**
> "The phone can be offline, so every write must be safe to replay. The client generates the UUID, so a retried create returns 200 instead of creating a duplicate. Updates carry `updated_at`; if the server row is newer, it returns 409 with the current row and the client resolves it. Deletes are tombstones so other devices learn about them. A sequence-number feed lets a device ask 'what changed since 1042?' and catch up. The trade-off is last-write-wins: two offline edits to the same field, the later one wins."

**"What's the biggest scale you've handled?"**
> "Vaidya, with [fill: one user number]. Honestly, our hardest problems weren't user count but speed: a blocking driver in async code, a slow email call in login, and connection limits as pods scale. Adding pods also multiplies database connections, so pool size had to be planned against Postgres' limit."

**"The multi-tenant project is in Go. Why, for a Python role?"**
> "The client project started in Go and I kept it there. My day job and my personal backend, Recurring, are Python and FastAPI, and that's where I'm going deeper. The design carries over: tenant from the token, every query scoped, roles inside a tenant, background jobs."

**"What did you NOT own in billing?"**
> "Prithvi, a senior engineer, owned the Razorpay dashboard config, the payment-flow endpoints and the checkout UI. I owned the wallet, the deduction, webhooks and reconciliation."

**"Weakness?"**
> "My production work has been I/O-heavy, so I've had less hands-on time with CPU-heavy work like multiprocessing and very large data jobs. I'm closing it deliberately: chunked processing for large imports, and comparing threads with processes on real workloads."

**"Why Headstart?"**
> "It's a multi-tenant product with lots of data: many institutions, many leads, bulk messages and reports. That's the next level of what I've built at a smaller scale. And my first product, EduDoor, was in education, so the domain feels familiar." [fill: one specific thing you read about Headstart]

More project-specific questions: [10-project-questions.md](10-project-questions.md).

---

## Track B · SDE (general software engineer)

Lead with **range, ownership and problem solving**: production apps on both mobile and backend, a CP background, and a habit of fixing hard bugs fast.

### B · 30 seconds
> "Hi, I'm Gautam, a software engineer at Ailoitte Technologies with about two years of experience. I build **across mobile and backend**: on **Vaidya AI**, a healthcare platform for Fractal Analytics, I own the Flutter app's architecture and the backend's auth and billing services. Before that I took over **Guardian Bubble**, a parental-control app, and built features like SOS alerts that work even when the app is killed. My base is competitive programming, **CodeChef rank 32**, and **GATE CS**."

### B · 90 seconds (default)
> "Hi, I'm Gautam, a software engineer at **Ailoitte Technologies**. I work **across the stack**, and my two major projects are **Vaidya AI** and **Guardian Bubble**.
>
> On **Vaidya AI**, a healthcare platform for **Fractal Analytics**:
> - On the **backend**, I own the **auth, admin and billing services** in FastAPI and PostgreSQL. The credit wallet can't be overspent under concurrency, webhooks are idempotent, and a reconciliation job catches missed payments.
> - On the **app**, I own the architecture, built a **background health-data sync** for iOS and Android, and cut cold start from **3.5 seconds to under 1**.
>
> On **Guardian Bubble**, a parental-control app I inherited, I built **SOS alerts that fire even when the app is killed** and bypass Do Not Disturb, and **live location** with smooth routes using path simplification.
>
> I'm often the one who fixes things fast. When a security audit pulled a **React Native** app from the store, I fixed the auth bug in **under 24 hours** with no React Native experience. On another app, I closed **40+ bugs in a week** to unblock a release.
>
> I've also built my own **App Store app with a FastAPI backend**, contributed to the open-source **Stac** framework, and my foundation is CP: **CodeChef rank 32**, **GATE CS**, and an **SIH 2022 finalist**.
>
> I'm looking for a role where I own systems end to end and keep solving harder problems."

### B · 2 minutes
> "Hi, I'm Gautam. I studied CS at **Darbhanga College of Engineering**, 2020 to 2024. I got into competitive programming early, **Google Kickstart 2021** and **CodeChef rank 32 out of 5,000+** in 2022, qualified **GATE CS** in 2023, and did hackathons every year I could: **Manthan 2021**, **SIH 2022 as finalists**, and **SIH 2024**. In my final year I was the only engineer at **MithilaStack**, taking **EduDoor** from Figma to the Play Store.
>
> At **Ailoitte**, my first major project was **Guardian Bubble**, a parental-control app. I inherited the codebase, moved it to Clean Architecture with tests, and built the hard platform features: **SOS that fires when the app is killed**, **critical alerts that bypass Do Not Disturb**, and **live location** over sockets with smooth routes. I also worked on other client apps: fixing a **20-second splash hang**, closing **40 bugs in a week**, and a **24-hour security fix** in React Native.
>
> Since October 2025 I've been on **Vaidya AI** for **Fractal Analytics**, on **both sides**. On the app, I own the architecture, built a **health-data sync** handling **10,000+ entries per user** in the background on both platforms, and cut cold start by **71%**. On the backend, I own **auth, admin and billing**: an atomic wallet, idempotent webhooks with a state machine, and a **Redis worker pipeline** that streams progress over SSE.
>
> On my own I built **Recurring**, a finance app on the App Store with an **offline-first FastAPI backend**, and a **multi-tenant backend** used by six companies in the UAE. And my PR to the open-source **Stac** framework was merged.
>
> What ties it together is that I like owning something end to end and making it correct when things go wrong."

### SDE follow-ups

**"Mobile or backend, which do you prefer?"**
> "Backend is where I'm going deeper, because the hardest correctness problems live there: concurrency, payments, data. Having built both means I can follow a bug across the whole stack instead of stopping at my layer, and I design APIs with the client in mind."

**"Tell me about a hard problem you solved."** Pick by interviewer:
- **Backend-minded:** the Apple Sign-In lockout ([10-project-questions.md](10-project-questions.md#part-c--vaidya-auth-service)).
- **Systems-minded:** the health sync engine: idempotent records, foreground owns the cursor (Track C follow-ups).
- **Pressure / no repro:** the iOS white screen at launch, or Guardian Bubble's silent first SOS alarm.

**"How do you learn something new fast?"**
> "Kailado. A security audit found tokens surviving logout and the app was pulled from the store. I'd never written React Native. Instead of a tutorial, I traced the real login and logout code end to end, found where tokens were stored and not cleared, fixed it and shipped in under 24 hours. I learn fastest by following the actual code path."

**"Tell me about your open-source contribution."**
> "Stac is a server-driven UI framework for Flutter: the server sends JSON and the app renders widgets from it. I added a badge widget and its JSON parser, following the project's conventions, and it was merged. It taught me to read a large unfamiliar codebase and match its style." [fill: anything the maintainers asked you to change]

**"How's your DSA now?"** (honest; it's a known gap)
> "I was strong in college: CodeChef rank 32. Working full-time I practised less, so I'm rebuilding with regular LeetCode in C++. I always start with brute force, then optimise out loud and state the complexity." [fill: what you've actually practised recently]

**"What do hackathons show about you?"**
> "Building something that works, under a deadline, with a team, and cutting scope to what matters. At SIH 2022 we reached the finals with [fill: one line on the problem and what you built]."

**"Where do you see yourself in 2–3 years?"**
> "Owning a backend system end to end at a product company: designing it, running it in production, and being the person called when it breaks."

---

## Track C · Flutter / mobile

Lead with **architecture, performance and platform depth**. Backend becomes your edge: you understand both sides of every API.

### C · 30 seconds
> "Hi, I'm Gautam, a Flutter engineer at Ailoitte Technologies with about two years of experience. My two major apps are **Vaidya AI**, a healthcare app for Fractal Analytics where I own the architecture and cut cold start from **3.5 seconds to under 1**, and **Guardian Bubble**, a parental-control app where I built **SOS alerts that fire even when the app is killed**. I also work on Vaidya's FastAPI backend and I've contributed to the open-source **Stac** framework."

### C · 90 seconds (default)
> "Hi, I'm Gautam, a software engineer at **Ailoitte Technologies**, mainly Flutter, and I also work on the backend.
>
> My two major projects:
>
> **Vaidya AI**, a healthcare app for **Fractal Analytics**, live on both stores. I **own the app's architecture**: Clean Architecture, BLoC, secure storage and sync managers. I set up the **base project template** the team now uses on new Flutter projects. I built **health-data sync** from HealthKit and Health Connect, over **10,000 entries per user** processed in **isolates**, including **background sync** on both platforms. I cut **cold start from 3.5 seconds to under 1** and **app size by 35%**, and hardened security with **SSL pinning, jailbreak detection and encrypted storage**.
>
> **Guardian Bubble**, a parental-control app I inherited. I built **SOS that fires even when the app is killed**, with **critical alerts that bypass Do Not Disturb**, and **live location** over sockets with smooth routes using **Douglas-Peucker and KDE smoothing**. I also modernised the codebase with Clean Architecture and **unit tests that caught a bug before release**.
>
> I've shipped other Flutter apps too: **Flittz** with **10K+ downloads**, **Revilo**, a **Windows desktop app**, MedCompass, and a Flutter web app. And my PR to the open-source **Stac** framework was merged.
>
> Because I also work on the backend, I design what the app needs from the API instead of working around it. I'm looking for a role where I own a large app's architecture and performance."

### C · 2 minutes
> "Hi, I'm Gautam. I studied CS at **Darbhanga College of Engineering**, 2020 to 2024, with competitive programming, **CodeChef rank 32**, **GATE CS**, and hackathons: **Manthan 2021**, **SIH 2022 finalists** and **SIH 2024**. In my final year I was the only engineer at **MithilaStack**, taking **EduDoor**, a jobs marketplace for schools, from Figma to the Play Store: auth, role-based flows, search and push notifications.
>
> At **Ailoitte**, my first major app was **Guardian Bubble**. I inherited it, moved it to Clean Architecture with Husky hooks and unit tests, and built the platform-level features most apps skip: **SOS firing from a killed state**, **critical alerts through Do Not Disturb**, **live location** with ETA and smooth routes, **isolates** to sync **1,000+ contacts** without freezing the UI, and **multi-device switching**. I also did an Android proof of concept with a **VPN and accessibility service** to detect unsafe content.
>
> Since October 2025 I've been on **Vaidya AI** for **Fractal Analytics**. I own the architecture and built the **base template** other projects adopted. The hardest part was **background health sync**: iOS wakes the app when data arrives, Android runs on a WorkManager schedule, and both call **one shared Dart sync engine**. Records have fixed ids so retries are harmless, and only the foreground moves the sync cursor. We validated it with a **week-long multi-user field test**. I also cut cold start by **71%**, app size by **35%**, and fixed an **iOS white screen** with zero repro steps.
>
> Along the way I've shipped **Flittz**, **10K+ downloads**, **Revilo**, **MedCompass** on **Windows desktop**, and a **Flutter web** app, and contributed to **Stac**. I also build backends in FastAPI, including the backend for my own App Store app, **Recurring**.
>
> I'm looking for a role where I own a large app's architecture and performance end to end."

### Flutter follow-ups

**"How did you cut cold start from 3.5s to under 1s?"**
> "I measured first with Firebase Performance and timing logs. Startup did everything one after another, and a heavy serialization step ran on the main thread. I ran independent initialisation in parallel with `Future.wait`, deferred anything the first screen didn't need, moved the heavy work off the main thread, and trimmed the dependency tree, which also cut app size by 35%."

**"Explain the background health sync."**
> "iOS and Android wake the app differently. **iOS pushes:** HealthKit wakes us when new data arrives and gives about 30 seconds. **Android, we schedule:** WorkManager runs about every 30 minutes with a longer budget. Both call **one shared Dart sync engine**, so the platforms can't behave differently.
> The key is **idempotency**: each record has a fixed id like `steps_2026-06-14_09`, so sending it twice just overwrites the same row. Retries, duplicates and out-of-order sends become harmless.
> One rule keeps it safe: **only the foreground sync moves the 'last synced' cursor**, and only after the server confirms. Background sync is best-effort and never touches the cursor, so a half-finished background run can't skip data."

**Follow-up: "What broke in production?"**
> "Hive can only be opened from one isolate, and the foreground had about 30 boxes open, so the background isolate **deadlocked**. I made the background start without Hive, using only SharedPreferences and secure storage. Also, the background entry function was **removed by the compiler** because nothing imported it, so I had to reference it explicitly. I added breadcrumb diagnostics to prove the OS was really firing background runs."

**"How do you structure a Flutter app?"**
> "Clean Architecture: **presentation** (widgets + BLoC), **domain** (entities, use cases, repository interfaces), **data** (models, remote and local sources, repository implementations). Dependencies come from **GetIt**, never created inside widgets. **Theme tokens** for colors, spacing and text styles, nothing hard-coded. Model fields stay nullable, and the UI decides defaults. **Husky** runs lint and format before every commit."

**"Tell me about a hard mobile bug."**
> "Guardian Bubble's **SOS**: when the app was killed, the **first alarm after a cold boot was silent**, but the second worked. There was no reliable repro, so I watched `adb logcat` across many attempts until I caught it: the **audio codec wasn't ready** on a cold start. [fill: the fix]."
> Alternatives: the **iOS white screen** at launch (malformed token + corrupted navigation state, zero repro steps), or the **iOS Keychain** keeping credentials after uninstall (Keychain survives uninstall, so we detect a fresh install and clear it).

**"How did you do smooth live location?"**
> "Raw GPS points jitter, so routes looked jagged. I used **Douglas-Peucker** to drop points that don't change the shape, **KDE smoothing** to remove jitter, and **map matching** with Google and Mapbox to snap routes to real roads. Updates came over sockets, **debounced** so the map didn't redraw on every point."

**"Isolates: when do you use them?"**
> "For CPU-heavy work that would block the UI for more than a frame: parsing large JSON, processing thousands of health entries, syncing 1,000+ contacts. Not for network calls; those are already async and don't block."

**"What was different about the Windows app?"** [fill: e.g. desktop packaging, window sizing, file system access, plugins without Windows support]

**"Why do you also do backend?"**
> "Many app problems are really API problems. Knowing the backend lets me ask for the right API: pagination, idempotent retries on bad networks, backward compatibility for old app versions. On Recurring I built both sides, and the offline sync only works because I designed the client and server together."

---

# Part 3 · Follow-ups for every track

**"Gap between August 2024 and February 2025?"**
> [fill: the honest reason in one sentence.] "I joined Ailoitte in February 2025." Don't apologise or over-explain.

**"Why are you looking for a change?"** (positive, never criticise Ailoitte)
> "I've grown a lot at Ailoitte, from client apps to owning major parts of a large product on both mobile and backend. Now I want a product company where I stay on one platform long term and go deeper on [backend and data at scale / app architecture at scale]." [fill: your real reason]

**"Biggest strength?"**
> "Ownership of correctness, and debugging without a reproduction. On billing I planned for concurrent spends, duplicate and missing webhooks. Many of my best fixes were bugs that only happened for one user in production: Apple Sign-In, the iOS white screen, the silent first SOS alarm."

**"Biggest weakness?"** Match it to the track:
- **Backend:** less hands-on with CPU-heavy work and very large data jobs; practising chunked processing and threads vs processes.
- **SDE:** DSA speed dropped since college; rebuilding with regular practice.
- **Flutter:** native Swift/Kotlin limited to platform channels and background work.

**"Something you took ownership of without being asked?"**
> "Observability on the Vaidya app. When users reported failures we were guessing. I proposed Crashlytics with non-fatal errors, breadcrumbs and custom keys, plus Analytics and Performance Monitoring, told the PM, and built it. Later, when every API started failing at once, the logs showed a build was missing the base URL, and we fixed it fast instead of guessing."

**"A time something went wrong because of you?"**
> [fill: a real one. Shape: what happened → how you noticed → how you fixed it → what you changed so it can't happen again. No blame on others.]

**"A disagreement with a teammate or senior?"**
> [fill: a real one. Shape: the disagreement → the data you brought → what was decided → the result. Show you can push back politely and then commit.]

**"Notice period / location?"** [fill: notice period]. For Noida on-site: [fill: confirm relocating from Bangalore is fine].

**Questions to ask them** (have two ready)
- "What does success look like in the first 3 months for this role?"
- "What's the biggest technical problem the team is working on right now?"
- For Headstart: "How do you isolate data between institutions today, and where does it hurt?"

---

## Delivery checklist
- Say the 90-second version of your track out loud **three times**, timing it. If it runs over 100 seconds, cut a sentence; don't speed up.
- Know which **three items** you'd most like them to ask about, and make sure each appears in your intro.
- Fill every **[fill]** above before the interview, especially the user count, hackathon results, the gap, and one line each for Flittz, Revilo, MedCompass and the web app.
