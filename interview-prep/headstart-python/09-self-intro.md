# 09 · Self-Introduction ("Tell me about yourself")

Built from your resume and what you told me in the mock round. **[fill: …]** marks things only you can confirm. Say it, don't read it: learn the *order*, not the exact words.

**Order to remember:** *who I am → what I do now → 2–3 things I built → what I'm good at → why this role.*

---

## 30-second version (when they say "quick intro")

> "Hi, I'm Gautam. I'm a backend engineer at Ailoitte, working on Vaidya, a healthcare AI app for Fractal Analytics, and its insurance product. I work mainly in **Python and FastAPI** with PostgreSQL and Redis. I own the auth, admin and billing services, built the Razorpay subscription billing and the gateway between the app and the AI services. I started on the Flutter app and moved into backend ownership as the product grew. I enjoy building systems that stay correct under real-world problems: payments, retries, concurrency."

---

## 60–90 second version (the default, use this one)

> "Hi, I'm Gautam. I'm a software engineer at **Ailoitte Technologies**, and since February 2025 I've been working on **Vaidya**, a healthcare AI app for Fractal Analytics, and **Vaidya Insurance**.
>
> I started on the Flutter mobile app and **took over backend ownership as the product grew**. Today I own the **auth, admin and billing services**, including the token format every other service checks.
>
> A few things I built:
> - **Subscription billing on Razorpay.** I made the credit wallet safe when payments happen at the same time, and made webhooks safe to receive twice or out of order.
> - On Vaidya Insurance, the **platform APIs and the gateway between the app and the AI services**, which handles auth, validation and errors in one place.
> - The **AI pipeline's request flow**: the API returns a run id immediately, Redis workers do the multi-minute job, and the app gets progress over SSE.
>
> I've also fixed real performance problems: a blocking database driver inside async code, and moving a slow email call off the request path, which took OTP delivery from 8–10 seconds to about half a second.
>
> Outside work, I built **Recurring**, a personal-finance app on the App Store, with both the Flutter app and the FastAPI backend, and a **multi-tenant backend** used by a client in the UAE across 6+ companies.
>
> I'm looking for a backend role where I can go deeper on scale and data, which is why Headstart's CRM platform interests me."

---

## 2-minute version (if they say "take your time" or "walk me through your background")

Add these before the Vaidya part:

> "I did my B.Tech in Computer Science from Darbhanga College of Engineering, finishing in 2024. I was a CodeChef top-32 out of 5,000+ in 2022, a Smart India Hackathon 2022 finalist, and I qualified GATE CS in 2023.
> During college I interned at **MithilaStack** for a year as the sole engineer on **EduDoor**, a jobs marketplace for schools and teachers. I took it from design to the Play Store: authentication, role-based flows, APIs and push notifications."

Then the 60–90 second version, and end with the "why Headstart" line.

---

## Lines for the follow-ups that usually come next

**"Why backend, when you started in Flutter?"**
> "Working on the app, I kept running into problems that were really backend problems: failed payments, slow APIs, auth issues. I wanted to fix them at the source, so I took on backend work at Vaidya and ended up owning the services. Having built the app side too helps me design APIs that mobile clients can actually use, like keeping changes backward compatible for old app versions."

**"Why Headstart?"**
> "Headstart is a multi-tenant CRM for institutions, with a lot of data, bulk communication and reporting. That's exactly the next level I want: I've built multi-tenant systems and background-job pipelines at smaller scale, and I want to work on them at larger scale. Education is also a space I care about: my first product, EduDoor, was in education."

[fill: anything specific you like about Headstart or the role]

**"Why are you looking for a change?"** (keep it positive, never criticise the current company)
> "I've learned a lot at Ailoitte and grown from the mobile side into owning backend services. I'm now looking for a product company where backend and data at scale are the core of the work, and where I can stay with one platform long term."

[fill: adjust to your real reason]

**"Your biggest strength?"**
> "Ownership of correctness. I don't stop at 'it works on the happy path'. With billing, I thought through concurrent spends, duplicate webhooks and missed webhooks, and built for each. And debugging: I've root-caused issues with no reproduction, like Apple Sign-In users being locked out because Apple reuses a token id that Google doesn't."

**"A weakness?"** (true, plus what you're doing about it)
> "My production work has been I/O-heavy, so I've had less hands-on time with CPU-heavy work like multiprocessing and very large data processing. I've been closing that gap deliberately: benchmarking threads against processes and practising chunked processing for large imports."

**"Notice period / location?"** → [fill: your notice period] · the role is on-site in Noida: [fill: confirm you're fine relocating or commuting]

---

## Delivery tips
- **Under 90 seconds** unless asked for more. Stop and let them pick what to dig into.
- Say **"I built"** for what you built. Never "anyone could have done it".
- End on something you *want* them to ask about (billing, the gateway, the pipeline).
- Have the [fill] numbers ready: users, requests per day. Interviewers often follow up with "how big?"
