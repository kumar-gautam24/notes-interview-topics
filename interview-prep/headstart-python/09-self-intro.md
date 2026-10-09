# 09 · Self-Introductions: Backend, SDE, Flutter

Three intros for three kinds of roles, each in 30-second, 90-second and 2-minute versions, with follow-up answers. **[fill: …]** marks things only you can confirm.

| Role you're interviewing for | Use |
|---|---|
| Python / FastAPI backend (Headstart) | [Track 1](#track-1--backend-python--fastapi) |
| General SDE / software engineer | [Track 2](#track-2--sde-general-software-engineer) |
| Flutter / mobile | [Track 3](#track-3--flutter--mobile) |

**Order to remember (all tracks):** *who I am → where I work now → 3 things I built → one hard bug → why this role.* Learn the order, not the words. Stop at 90 seconds unless they ask for more.

---

## Your facts (check once, then use the same numbers everywhere)

| Fact | Value |
|---|---|
| Ailoitte Technologies, Bangalore | Feb 2025 – present |
| Feb – Oct 2025 | Client apps: Guardian Bubble, MyCard, Nile Source, Kailado, Golden Bridge |
| Vaidya AI (contracted to Fractal Analytics) | Oct 2025 – present. Flutter app + FastAPI/PostgreSQL/Redis backend |
| Billing split | **You:** credit wallet tables, atomic deduction, webhook handler (HMAC), reconciliation job, internal credit-deduction endpoint. **Prithvi (senior):** Razorpay dashboard config, payment-flow endpoints, frontend checkout |
| Manpower Management | Go + Chi, multi-tenant, ~50 APIs, 4-level RBAC, production for a UAE client, 178+ employees, 6+ companies |
| MithilaStack internship | Sept 2023 – Aug 2024, sole engineer on EduDoor (Figma → Play Store) |
| Education | B.Tech CSE, Darbhanga College of Engineering, 2020–2024 |
| Competitive programming | CodeChef rank 32 of 5,000+ (2022), Google Kickstart 2021, GATE CS 2023 |
| Hackathons | Manthan 2021 [fill: result], Smart India Hackathon 2022 **finalist**, Smart India Hackathon 2024 [fill: result] |
| Open source | Stac framework (786+ stars): merged a PR adding a badge widget + parser |
| Vaidya mobile numbers | Cold start 3.5s → under 1s (71%), app size −35%, health sync 10,600+ entries per user |
| Vaidya users | [fill: pick ONE number and use it everywhere. You said ~1M in the mock; your resume notes say "50K+"] |

**Rules that apply to every track**
- Say **"I built"** or **"I own"**, and only for what you actually did. On payments, say you built **the wallet and webhook side**, and name Prithvi if asked who did checkout.
- Never call Manpower Management "vibe-coded". You designed it, reviewed every line and run it in production.
- Don't quote a number you can't explain. "I don't have that number, but here's what I know…" is a fine answer.

---

# Track 1 · Backend (Python / FastAPI)

Lead with the server. Mobile is one sentence, as the reason you understand API clients.

## 30 seconds
> "Hi, I'm Gautam, a software engineer at Ailoitte with about two years of experience. I work on **Vaidya AI**, a healthcare app we build for Fractal Analytics, on the **backend in Python, FastAPI, PostgreSQL and Redis**. I own the **auth and admin services** and the **credit wallet and payment webhooks**, and I built the flow where long-running work goes to Redis workers and streams progress back to the app. I started in mobile and moved to backend, and that's where I'm going deeper."

## 90 seconds (default)
> "Hi, I'm Gautam. I'm a software engineer at **Ailoitte Technologies** in Bangalore. Since October 2025 I've been on **Vaidya AI**, a healthcare app we build for **Fractal Analytics**, mostly on its **FastAPI and PostgreSQL backend**.
>
> Three things I own there:
> - **Auth and admin services:** OTP, Google and Apple login, tokens and logout. I took OTP delivery from **8–10 seconds to about half a second** by moving the slow email call off the request path.
> - **The credit wallet and Razorpay webhooks:** the deduction is one atomic SQL update so two requests can't overspend; the webhook handler verifies the HMAC signature, ignores duplicate events, and a reconciliation job catches webhooks that never arrive.
> - **Long-running jobs:** the API returns a run id immediately, Redis workers do the multi-minute work, and the app gets progress over **SSE**.
>
> I've also debugged production issues with no reproduction, like Apple Sign-In users being locked out after logout because Apple reuses the same token id.
>
> Outside Vaidya, I run a **multi-tenant backend** in production for a UAE client, used by 6+ companies, with role-based access.
>
> Headstart is a multi-tenant CRM with a lot of data and background work, which is exactly what I want to go deeper on."

## 2 minutes
Add this before the 90-second version:
> "I did my B.Tech in Computer Science from Darbhanga College of Engineering, graduating in 2024. In college I did competitive programming, CodeChef rank 32 out of 5,000+, and I qualified GATE CS in 2023. I took part in hackathons: Manthan 2021, and Smart India Hackathon 2022, where we were finalists, and 2024. I interned for a year at **MithilaStack** as the only engineer on **EduDoor**, a jobs marketplace for schools and teachers, and joined Ailoitte in 2025."

## Backend follow-ups

**"Why backend, when you started in mobile?"**
> "On the app I kept hitting problems that started on the server: slow APIs, payments, login bugs. I wanted to fix them at the source, so I took on backend work at Vaidya and ended up owning services. Knowing the mobile side helps: I design APIs that old app versions don't break on, and I think about flaky networks and retries."

**"Which backend work are you proudest of?"**
> "The wallet and webhooks, because money has to be exactly right. I planned for three failures: two spends at the same time (atomic update), the same webhook arriving twice (unique event id), and a webhook never arriving (reconciliation). Each one has its own fix."

**"What's the largest scale you've handled?"**
> "Vaidya, with [fill: user number]. Honestly, user count wasn't our hardest problem. Our real problems were speed: a blocking database driver inside async code, a slow email call in the login path, and connection limits when pods scale. When load rose we added pods, but adding pods also multiplies database connections, so we capped the pool."

**"Your multi-tenant project is in Go. Why, for a Python role?"**
> "The client project started in Go and I kept it there. My day job is Python and FastAPI, and that's where I'm going deeper. The ideas are the same in any language: tenant id from the token, every query scoped, roles inside a tenant, background jobs."

**"What are you weaker at?"**
> "My production work has been I/O-heavy, so I've had less hands-on time with CPU-heavy work like multiprocessing and very large data jobs. I'm practising chunked processing and comparing threads with processes to close that."

**"Why Headstart?"**
> "It's a multi-tenant product with lots of data: many institutions, many leads, bulk messages and reports. I've built multi-tenant systems and job pipelines at a smaller scale and want to do it at a bigger one. My first product, EduDoor, was also in education." [fill: one specific thing about Headstart]

Deeper project questions: [10-project-questions.md](10-project-questions.md).

---

# Track 2 · SDE (general software engineer)

Lead with **range and problem solving**: you've shipped mobile and backend, own systems end to end, and have a CP background.

## 30 seconds
> "Hi, I'm Gautam, a software engineer at Ailoitte with about two years of experience. I've shipped production apps on **both mobile and backend**: on **Vaidya AI**, a healthcare app for Fractal Analytics, I built parts of the Flutter app and own backend services in FastAPI and PostgreSQL. Before that I did competitive programming, CodeChef rank 32 out of 5,000+, and I qualified GATE CS. I like owning a feature end to end, from the database to the screen."

## 90 seconds (default)
> "Hi, I'm Gautam, a software engineer at **Ailoitte Technologies**. I work across **mobile and backend**.
>
> On **Vaidya AI**, a healthcare app we build for Fractal Analytics:
> - On the **backend**, I own the auth and admin services and the credit wallet with Razorpay webhooks, built so that money stays correct even with duplicate or missing events.
> - On the **app**, I built a background **health-data sync engine** for iOS and Android, and cut cold start from **3.5 seconds to under 1 second**.
>
> Before Vaidya I worked on several client apps, often fixing hard production bugs fast. For example, I fixed a critical auth vulnerability in a **React Native app in under 24 hours with no prior React Native experience**, after a security audit pulled it from the store.
>
> On the side I run a **multi-tenant backend** in production for a UAE client across 6+ companies.
>
> My foundation is CS fundamentals: competitive programming, GATE CS 2023, and hackathons including **Smart India Hackathon 2022 as a finalist**.
>
> I'm looking for a role where I own systems end to end and solve harder problems."

## 2 minutes
Add before the 90-second version:
> "I studied Computer Science at Darbhanga College of Engineering, 2020–2024. I got into competitive programming early, Google Kickstart 2021 and CodeChef rank 32 in 2022, and did hackathons every year I could: Manthan 2021, SIH 2022 as finalists, and SIH 2024. In my final year I interned at **MithilaStack** as the only engineer on **EduDoor**, a jobs marketplace for schools and teachers: design, auth, APIs, Play Store release. I also contributed to the open-source **Stac** framework, where my PR adding a new widget was merged."

## SDE follow-ups

**"Mobile or backend, which do you prefer?"**
> "Backend is where I'm going deeper, because the hardest correctness problems are there: concurrency, payments, data. But having built both means I design APIs with the client in mind and can debug a problem across the whole stack instead of stopping at my layer."

**"Tell me about a hard problem you solved."** Pick based on the interviewer:
- Backend-leaning: the **Apple Sign-In** two-bug story (old query missing the soft-delete filter, then Apple reusing the same token id). Details in [10-project-questions.md](10-project-questions.md#part-c--vaidya-auth-service).
- Systems-leaning: the **health sync engine** (Track 3 follow-ups below): idempotent records, foreground owns the cursor, background never does.

**"How do you learn something new fast?"**
> "Kailado is the clearest example. A security audit found that tokens survived logout and the app was pulled from the store. I'd never written React Native. I read the auth flow end to end, found where tokens were stored and not cleared, fixed it and shipped in under 24 hours. I learn by tracing the real code path, not by doing a tutorial first."

**"How's your DSA now?"** (be honest; it's a known gap)
> "I was strong in college, CodeChef rank 32. Working full-time I practised less, so I'm rebuilding with regular LeetCode in C++. I'm solid on arrays, hashing, two pointers and DP basics, and I always start from the brute force and optimise out loud." [fill: adjust to what you've actually practised]

**"What do hackathons show about you?"**
> "Building something working under a deadline with a team, and cutting scope to what matters. At SIH 2022 we reached the finals: [fill: one line on the problem statement and what you built]."

**"Where do you see yourself in 2–3 years?"**
> "Owning a backend system end to end at a product company: designing it, running it in production and being the person who's called when it breaks."

---

# Track 3 · Flutter / mobile

Lead with **architecture, performance and platform depth**. Backend becomes an advantage: you know both sides of the API.

## 30 seconds
> "Hi, I'm Gautam, a Flutter engineer at Ailoitte with about two years of experience. On **Vaidya AI**, a healthcare app for Fractal Analytics that's live on both stores, I own the app's architecture, built a background **health-data sync** for iOS and Android, and cut cold start from **3.5 seconds to under 1 second**. I also work on the FastAPI backend, so I understand both sides of every API the app calls."

## 90 seconds (default)
> "Hi, I'm Gautam, a software engineer at **Ailoitte Technologies**, mainly Flutter.
>
> On **Vaidya AI**, a healthcare app for Fractal Analytics:
> - I own the **architecture**: Clean Architecture with BLoC, secure storage and sync managers. I set up the **base project template** with folder structure and pre-commit checks, which the team now uses on new Flutter projects.
> - I built the **health-data sync** from HealthKit and Health Connect: 10,000+ entries per user, processed in isolates so the UI never freezes, plus **background sync** on both platforms.
> - **Performance:** cold start from **3.5s to under 1s** and app size down **35%**, by running startup work in parallel, trimming dependencies and removing a serialization step on the main thread.
> - **Security:** SSL pinning, root and jailbreak detection, obfuscation, encrypted storage.
>
> Before that I took over **Guardian Bubble**, a parental-control app, and built SOS alerts that fire even when the app is killed, and live location with smooth routes.
>
> I also work on Vaidya's FastAPI backend, which helps me design what the app needs from the API.
>
> I'm looking for a role where I own a large app's architecture and performance."

## 2 minutes
Add before the 90-second version:
> "I did my B.Tech in CS from Darbhanga College of Engineering, 2020–2024, with competitive programming (CodeChef rank 32) and hackathons: Manthan 2021, SIH 2022 finalists and SIH 2024. During college I was the only engineer at **MithilaStack** on **EduDoor**, taking it from Figma to the Play Store. I've also contributed to the open-source **Stac** framework for server-driven Flutter UI; my PR adding a widget and its parser was merged."

## Flutter follow-ups

**"How did you cut cold start from 3.5s to under 1s?"**
> "I measured first: Firebase Performance and timing logs showed startup was doing everything one after another, and a large JSON parse ran on the main thread. I ran independent initialisation in parallel with `Future.wait`, delayed what wasn't needed for the first screen, moved the heavy parsing off the main thread, and removed unused packages, which also cut app size by 35%."

**"Explain the health sync design."**
> "iOS and Android wake the app differently. **iOS pushes**: HealthKit wakes us when new data arrives, with about 30 seconds to work. **Android we schedule**: WorkManager runs roughly every 30 minutes. Both call the **same Dart sync engine**, so behaviour can't drift between platforms.
> The key is **idempotency**: each record has a fixed id like `steps_2026-06-14_09`, so sending it twice just overwrites the same row. Retries and duplicates become harmless.
> And one rule: **only the foreground sync moves the 'last synced' cursor**, and only after the server confirms. Background sync is best-effort freshness and never touches the cursor, so a half-finished background run can't skip data."

**Follow-up: "What broke?"**
> "Hive can only be opened from one isolate, and the foreground already had about 30 boxes open, so the background isolate **deadlocked**. I made the background start without Hive, using only SharedPreferences and secure storage. Another one: the background entry function was removed by the compiler because nothing imported it, so I had to reference it explicitly."

**"How do you structure a Flutter app?"**
> "Clean Architecture: presentation (widgets + BLoC), domain (entities, use cases, repository interfaces), data (models, API and local sources, repository implementations). Dependencies come from GetIt, never created inside widgets. Theme tokens for colors, spacing and text styles, so there's nothing hard-coded. Models keep fields nullable and the UI decides defaults."

**"Tell me about a hard mobile bug."**
> "Guardian Bubble's **SOS alarm**: when the app was killed, the first SOS alarm didn't play, but the second did. The audio codec wasn't loaded on a cold start. There was no reliable repro, so I watched `adb logcat` across many attempts until I caught it, then [fill: the fix, e.g. initialising the audio before the first play]."
> Other options: the iOS **white screen at launch** with no repro steps (a malformed token plus corrupted navigation state), or the iOS **Keychain** keeping credentials after uninstall.

**"Isolates: when do you use them?"**
> "For CPU-heavy work that would block the UI for more than a frame: parsing large JSON, processing thousands of health entries, syncing 1,000+ contacts in Guardian Bubble. Not for network calls; those are already async."

**"Why do you also do backend?"**
> "Many app problems are really API problems. Knowing the backend lets me design APIs that work for the app (pagination, idempotent retries on bad networks, backward compatibility for old versions) instead of working around them."

---

## Follow-ups for every track

**"Gap between August 2024 and February 2025?"**
> [fill: the honest reason in one sentence, e.g. job search after graduating or preparation.] "I joined Ailoitte in February 2025." Don't apologise or over-explain.

**"Why are you looking for a change?"** (positive, never criticise Ailoitte)
> "I've grown a lot at Ailoitte, from client apps to owning parts of a large product. Now I want a product company where I stay on one platform long term and go deeper on [backend and data / app architecture at scale]." [fill: your real reason]

**"Biggest strength?"**
> "Thinking about what goes wrong, not just the happy path, and debugging without a reproduction. Most of my best work is fixing things that only failed for one user in production."

**"Biggest weakness?"** Pick the one that fits the track:
- Backend: less hands-on with CPU-heavy work and very large data jobs (above).
- Flutter: "I've gone deep on Flutter, so my native Swift/Kotlin is limited to platform channels and background work."
- SDE: DSA speed has dropped since college and I'm rebuilding it (above).

**"Notice period / location?"** [fill: notice period]. For Noida on-site: [fill: confirm relocating from Bangalore is fine].

**Questions to ask them** (have two ready)
- "What does the first 3 months look like for this role?"
- "What's the biggest technical problem the team is working on right now?"
