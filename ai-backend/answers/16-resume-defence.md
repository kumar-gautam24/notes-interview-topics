# Document 16 — Resume Defence & Interviewer Attack (Questions 572–612)

> **How this document differs from the other fifteen.** Every previous answer was a technical explanation you can learn. These are **scripts for defending real work and conceding what you haven't done.** They only function if the specifics are yours.
>
> **The single most important principle here:** a clean concession followed by a concrete plan reads as *more* senior than a confident bluff. Section Q exists to find out which you'll do. Someone who says "I haven't measured that — here's how I would" is hireable. Someone who invents a number and can't survive the follow-up is not.

---

# Section P — Resume defence (572–591)

## 572. What exactly do you own?

**Structure:** scope → decisions you make alone → what you escalate → what you're accountable for when it breaks.

**Be precise about the boundary.** "I own the retrieval pipeline" is a claim. "I own chunking, embedding, the hybrid query, and its eval suite; ingestion is owned by someone else and I consume it" is an answer.

**Three things make ownership credible:**
1. **You get paged when it breaks.** Ownership without on-call is authorship.
2. **You make decisions without asking.** Name one and defend it.
3. **You know its real failure modes** — the ones that happened, not hypotheticals.

**Avoid inflating scope.** An interviewer who probes an inflated claim finds the edge in two questions, and everything else you said becomes suspect.

**The honest version if your scope is narrow:** *"I own the mobile client end to end — architecture, release, crash triage, and the attribution integration. On the backend I've contributed rather than owned."* **Narrow and true beats broad and thin.**

---

## 573. What did you personally build?

**This question exists because "we built" hides everything.** Answer in first person, specifically.

**Structure:** what existed before you → what you designed and wrote → what you changed after production → what you'd point at in the codebase.

**A strong answer sounds like:** *"I designed and wrote the attribution SDK integration — SDK wiring, deferred deep links, and the vendor-key storage approach after a security review flagged the default pattern. I wrote the security assessment that got it approved. Someone else owned the backend event endpoint."*

**Note what makes that work: it names what you didn't do.** Voluntarily drawing the boundary makes everything inside it credible.

**The trap:** describing a system you understand but didn't build. The distinguishing question is always *"what did you change after it hit production?"* — that only has an answer if you were there.

---

## 574. Walk me through your biggest technical decision.

**Structure:** context → options considered → the constraint that decided it → what you gave up → whether it held.

**What carries weight:**
1. **Genuine alternatives.** One option isn't a decision. Name two and why you rejected the other.
2. **The deciding constraint** — usually not technical superiority but team size, timeline, or an existing system.
3. **What you traded away.** A decision with no cost wasn't one.
4. **Whether it held**, including "it didn't, and here's what I'd change."

**A worked example:** integrating a third-party attribution SDK that expects a vendor key to live on the client. Options: ship the default integration, proxy attribution through your own backend, or don't integrate. The constraint was a security policy on client-embedded credentials. You assess the real exposure, document the trade-off, and decide. **Every option here carries a cost — the skill is naming yours before the interviewer does.**

Real options, real constraint, honest cost.

---

## 575. Hardest bug you debugged?

**They're testing method, not the bug.** A dramatic bug badly debugged scores worse than a mundane one debugged systematically.

**Structure:** symptom → what made it hard → hypotheses and how you eliminated them → root cause → verification → prevention.

**A strong worked example:** a macOS background service that silently stopped running. What made it hard was that the service *appeared* correctly configured; the root cause was the service disabled in `launchd`'s persistent override database by a device-management action — a state invisible in the plist. **The generalisable insight: the configuration file and the runtime state had diverged.**

**What makes an answer strong:**
- You eliminated hypotheses rather than guessing repeatedly
- You can name the specific command that produced the breakthrough
- You state what would have detected it sooner
- You changed something so it can't recur silently

**The weak version:** "I added logging until I found it."

---

## 576. Describe a production incident.

**Structure:** detection → immediate mitigation → diagnosis → resolution → prevention.

**The order is itself the signal.** A good responder mitigates before diagnosing (Q542). Starting with root-cause investigation while users are down reveals inexperience.

**What to include:** how you found out (an alert is good; a customer report is honest but names a monitoring gap), time to mitigation, the blunt instrument you reached for, what you preserved before restarting (Q39), and whether the prevention item actually got done.

**An app-store rejection works well here framed as an incident:** detection was the rejection notice; mitigation was correcting the inaccurate category declarations; diagnosis was that the app had been described by its *domain* rather than its *function*; resolution was reframing the listing around what the app actually does; prevention was a declaration review before every submission.

**The most valuable sentence:** *"What would have caught this sooner is X, and we added it."*

---

## 577. What scale did you operate at?

**Give real numbers. Don't inflate.** Inflated numbers collapse under one follow-up about cost, capacity, or a failure mode you'd only know at that scale.

**Have ready:** users or installs, peak RPS, data volume, monthly cost, latency percentiles, error rate.

**A worked example:** a Flutter app with a real consumer install base and active paid acquisition across multiple channels — real crash triage, real store compliance, real attribution data.

**The framing that makes modest scale count:** *"Not large by infrastructure standards, but they're real users with real acquisition spend behind them — a bad release costs measurably and a store rejection blocks revenue. That shaped how I think about release safety more than raw QPS would have."*

**The trap:** claiming a scale that implies experience you lack. Say "millions of requests per second" and expect questions about sharding, connection pool arithmetic, and provider quota. **Small scale honestly stated, with sharp reasoning about it, beats large scale vaguely claimed.**

---

## 578. What's your role on the team?

**Answer with behaviour, not title.** Titles vary between companies; behaviour transfers.

**Cover:** what you're the go-to person for, what you escalate, whether you review others' code, whether you set direction or execute it, and how decisions actually get made.

**Be honest about seniority.** Claiming to set architecture when you implement it is exposed by "who decided X, and why?"

**A good answer names a specific behaviour:** *"I'm who gets asked about anything touching the release pipeline or store compliance, because I've handled the store rejections we've had. On backend architecture I'm a consumer and a reviewer, not the decider."*

**If you work largely alone:** say so, and name what you do to compensate — reading others' code, writing things down, seeking review. **Working solo is a real constraint; being aware of its risks is the signal.**

---

## 579. Why are you leaving?

**Say what you're moving toward, not what you're escaping.** Complaints about a current employer preview how you'll describe this one.

**Strong shapes:** wanting to work on AI systems full-time rather than as a side interest; having learned what the role can teach; wanting to be closer to backend and infrastructure than mobile allows.

**Avoid:** blaming individuals, leading with salary (mention compensation separately if asked), vague dissatisfaction.

**A strong version:** *"I've spent years shipping production mobile apps and I'm good at it. The problems I find most interesting now — retrieval, agent infrastructure, evaluation — sit on the backend, and I'd rather do that as the job than as evening work."*

Forward-looking, true, and it explains the transition without apologising for it.

---

## 580. Why AI engineering?

**Weak answer: enthusiasm. Strong answer: a specific problem you found interesting and what you did about it.**

**Structure:** what pulled you in → what you built or learned → why you're suited to it.

**Your genuine version:** you've shipped production software with real users, so you know what production costs — release safety, crash triage, security review, compliance. **The gap between an LLM demo and an LLM product is almost entirely production engineering**, and that's the part most people entering the field haven't done.

**A strong closing line:** *"Most of the hard problems in AI engineering turned out to be ones I recognised — idempotency, at-least-once delivery, evaluation, cost control. The model is one component. The system around it is the job, and that part I've done before."*

**Avoid:** "AI is the future," "I use ChatGPT a lot," and overclaiming ML depth. **You're not an ML researcher and shouldn't pretend** — AI engineering is a different role and the distinction works in your favour (Q263).

---

## 581. Strongest technical area?

**Pick one, be specific, be ready for depth.** Naming three invites probing of the weakest.

**What a defensible claim looks like:** production mobile engineering — architecture, release safety, security review, store compliance, instrumentation of real user behaviour. Concrete artefacts: a shipped consumer app with a real install base, an attribution integration you assessed and defended, store rejections you diagnosed and resolved.

**What makes it strong: you can go three levels deep.** Level one, "I ship Flutter apps." Level two, "I handled the attribution SDK integration including the vendor-key assessment." Level three, the actual threat model, what an extracted key permits, and how you sized the exposure.

**The test:** whatever you claim, expect "why?" three times. **If you run out at level two, don't claim it.**

**Pair it with the transition:** *"My strength is shipping and operating production software. The AI-specific parts I've studied hard and built with, but I'd call that competence, not depth."*

---

## 582. Weakest area?

**Give a real weakness that matters, plus what you're doing about it.** A dodge is worse than the weakness.

**Good answers — specific, relevant, not disqualifying:**
- *"I've never operated GPU infrastructure. I understand vLLM's architecture and where the self-host cost crossover is, but I've used hosted APIs. If the role needs inference ops, I'd be learning on the job."*
- *"Distributed systems at genuine scale. I know the patterns and have built with them at moderate volume, but I haven't operated something where sharding or multi-region was forced on me."*
- *"My evaluation practice is newer than my engineering practice. I know what a golden set and a held-out split are for; I've built fewer than I should have."*

**Each is true, specific, names the boundary precisely, and implies you know what competence would look like.**

**Avoid:** a weakness central to the role, a fake one, or one with no plan attached.

---

## 583. A time you disagreed with a decision?

**They're testing how you disagree, not whether you were right.**

**Structure:** the decision → your position and reasoning → how you raised it → the outcome → **how you behaved afterwards.**

**That last part matters most.** Disagreeing and then committing fully is the behaviour they want. Disagreeing and quietly undermining, or being right and saying so later, is not.

**Strong endings:**
- *"I was overruled, I committed, and it worked — I'd underweighted a constraint I didn't own."*
- *"I was overruled, it didn't work, and we changed course. I'd raised it in writing with a specific failure prediction, which made the reversal fast rather than contentious."*

**The mechanics worth naming:** raise it early, in writing, with a *testable* claim. **"I think this breaks when X" is falsifiable; "I don't like this approach" is not.**

**Avoid** stories where you were obviously right and everyone else was foolish.

---

## 584. What have you learned recently?

**Specific, recent, applied. Not a reading list.**

**Structure:** what you learned → why you went looking → what you did with it → **what surprised you.**

**The surprise proves it's real.** Anyone can say they learned about RAG. *"What surprised me was that reranking helps because a bi-encoder embeds the document before seeing the query — so it has to represent the passage for all possible questions. That's why cross-encoders beat it, and it reframed retrieval for me as a two-stage problem rather than a similarity problem"* — that's learning, not reading.

**What genuine material looks like:** going from zero domain knowledge to a full architecture for a domain-specific agent, landing on "LLM at the perimeter, deterministic core in the middle" as the organising principle. **A real insight with a real origin.**

**Avoid** naming a technology without an application. The follow-up is always "what surprised you?" and it can't be faked.

---

## 585. Walk me through your architecture end to end.

**Structure:** the request path, in order, with the decision at each hop.

**Do it in layers.** Start at 30 seconds — "client, API, queue, workers, Postgres, LLM provider." Then go deeper where they push. **Starting at maximum detail is a common mistake** — the interviewer can't steer.

**At each component:** why this and not the alternative, what happens when it fails, how you'd know.

**What they reliably probe:** the sync/async boundary and why (Q76), what happens on a crash mid-operation (Q246), where authorization is enforced (Q70), how you'd know it's broken (Q546).

**Include the parts that aren't impressive** — a cron job, a manual step, a piece of debt. **Naming a rough edge unprompted makes the polished parts credible.** An architecture with no acknowledged weaknesses reads as a diagram, not a system.

**Have numbers ready:** requests, latency, cost, data volume. An architecture without numbers can't be evaluated.

---

## 586. What would you rebuild?

**Every real system has one.** No answer means you didn't build it or haven't reflected.

**Strong shapes:**
- **A boundary you got wrong** — two things in one service that scale differently
- **A shortcut that compounded** — "I skipped the eval set early, so every retrieval change after was unverifiable"
- **A dependency you'd remove** — "We added Redis for a queue. PostgreSQL `SKIP LOCKED` gives the same thing with transactional claim-and-work and one fewer system to operate"
- **Something over-built** — "I built for a scale that never arrived"

**That last category is the most impressive**, because recognising your own over-engineering is the failure mode of ambitious engineers.

**What makes it land:** the specific cost the decision imposed. *"It made X take three days instead of one, every time."*

**Avoid** something trivial, or something you'd rebuild only because a new tool exists.

---

## 587. Build vs buy?

**The criteria in the order you'd actually apply them:**

1. **Is it your core differentiator?** Build. Everything else, buy. **Nobody won on having a better internal queue.**
2. **True cost of building** — not the prototype; the operation, on-call, patching, and the person who owns it forever.
3. **Cost of buying** — price, lock-in, and the ceiling if it doesn't do what you need later.
4. **Team size.** **This dominates for a small team** (Q570).
5. **Is the boundary clean?** If you can swap it later behind an interface, buying is low-risk.

**The AI-specific instances:** hosted API vs self-hosted inference (Q449) — buy unless residency forces it or utilisation justifies it. pgvector vs a dedicated vector store (Q417) — use what you already run until you measure a limit. Observability vendor vs self-hosted — buy until the bill exceeds an engineer's time.

**The framing:** *"I default to buying anything that isn't the product, and revisit when a specific measured constraint forces it — not when it becomes fashionable."*

---

## 588. How do you keep current?

**Show a method, not a reading list.**

- **Primary sources** — provider docs and changelogs, papers when they matter, engineering blogs from teams operating at scale
- **Building** — the field moves too fast for reading to produce competence. **Something you built with it beats something you read about it.**
- **A filter** — most announcements change nothing. **Naming what you've deliberately ignored is a stronger signal than a long list of what you follow.**

**A good closing line:** *"I try to distinguish things that change how I'd build something from things that are just news. Most are news. Prompt caching changed how I structure prompts; a new model release changes nothing until I've evaluated it."*

**Avoid** naming only newsletters, or implying you follow everything.

---

## 589. An unpopular technical opinion?

**They're testing independent judgement versus repeated consensus.**

**Requirements:** genuinely contrarian somewhere, defensible with reasoning, not gratuitously provocative.

**Defensible options from this bank:**
- *"Most things called agents should be workflows. Runtime path selection is expensive, hard to test, and usually unnecessary"* (Q291, Q597)
- *"Prompt engineering is over-invested relative to retrieval. In most RAG systems 70–80% of failures are retrieval failures, and prompt iteration can't touch them"* (Q375)
- *"A separate vector database is premature for almost everyone. Below ten million vectors, pgvector plus SQL filtering wins"* (Q417)
- *"In FastAPI, `def` is often safer than `async def`. One blocking call in an async endpoint kills the worker; the same code in a sync endpoint is merely slow"* (Q63)

**What makes it work:** you state the reasoning, name the counter-argument, and say what evidence would change your mind. **An opinion with no falsification condition is a preference.**

---

## 590. How did you evaluate your RAG system?

> **Must be your real answer.** Asked twice in this bank (here and Q599) because it's the highest-signal question in the section.

**The shape of a complete answer:**
1. **The golden set** — how many questions, sourced from where, labelled how
2. **Retrieval measured separately** — recall@5, recall@20, and the *gap* (Q372)
3. **Generation measured given correct context** — isolating it from retrieval (Q419)
4. **End-to-end**, plus unanswerable questions measuring refusal (Q425)
5. **A specific change and its measured delta**
6. **Where it runs** — CI, gating changes

**The three-layer decomposition is what makes it strong** rather than a list of metrics: retrieval 0.85 / generation-given-context 0.95 / end-to-end 0.70 tells you immediately that retrieval is the bottleneck. One number tells you nothing.

**If you haven't done this, the script that works:**

*"I haven't measured it formally, and that's the gap I'd close first. Concretely: 30 questions sampled from real queries, labelled by which chunk answers each, then measure recall@5 and recall@20. The gap between those tells me whether to add a reranker or fix chunking. Right now I'd be tuning retrieval on intuition, and that's not good enough."*

**That answer is genuinely strong.** It shows you know the method, know why it matters, and won't fabricate a number.

---

## 591. What are you most proud of?

**Pick something with a measurable outcome and a hard part.**

**Structure:** what it was → what made it hard → what you did → what it produced.

**Candidates worth having ready:**
- **Shipping and operating a real product** — a real install base, paid acquisition, store rejections diagnosed correctly rather than guessed at
- **A hard diagnosis** — a service failure traced to a runtime-state divergence invisible in the configuration, written up as an actionable ticket
- **An agent architecture** — zero domain knowledge to a defensible design, with a real organising principle

**Pick the one you can go deepest on**, because the follow-up is always "what was the hardest part?"

**What lands:** *"I'm proud that I diagnosed it rather than escalating it, because the obvious explanation was wrong and everyone had accepted it."*

**Avoid** anything with no measurable outcome or an ambiguous role.

---

# Section Q — Interviewer attack (592–612)

> Adversarial by design. **The correct posture is calm, specific, willing to concede.** Defensiveness is the failure mode; over-apologising is the second.

## 592. Your resume says X but you couldn't explain Y.

**Do not bluff. Do not crumble.**

**The script:** *"Fair. I used it rather than built it — I wired it up and shipped it, but I don't have the internals at the level you're asking. What I do have is [the level you actually have]. If that's a requirement, it's a gap."*

Then redirect to something adjacent you *can* defend at depth.

**Why it works:** an interviewer who catches a gap is testing what you do next. **A clean concession costs you one question. A bluff costs the interview**, because they now doubt everything before it.

**The preventive measure:** audit your CV against this question. For every claim, ask "can I go three levels deep?" **If not, soften the claim before the interview rather than defending it during one.**

---

## 593. That sounds like something you read, not built.

**The distinguishing evidence is always specifics that only come from doing.**

**What proves authorship:**
- **A number** — how long, how many, what it cost
- **A failure** — what broke and how you found out
- **A decision you'd reverse**
- **A boring detail** — the config value you had to tune, the library version that broke

**The script:** *"Reasonable challenge. Here's the specific thing: [failure, how it was detected, what changed]. That's not in any blog post — it's what I got wrong."*

**The failure story is the strongest available evidence**, because nobody writes up their own mistakes in enough detail for you to have read them.

**If it *is* something you read:** say so. *"You're right — that one I understand from reading, not building. What I've actually built is [X]."* The concession preserves everything else.

---

## 594. You keep saying "we" — what did YOU do?

**Switch to first person immediately. Don't get defensive.**

**The script:** *"Let me be precise. I designed and wrote [components]. [Colleague] owned [other part]. The decision about [X] was mine; the decision about [Y] I disagreed with and it went the other way."*

**Naming what someone else did makes your claims more credible, not less.** A candidate who claims everything on a team project isn't believed; one who draws the boundary clearly is.

**Why they ask:** "we" is the standard way people inflate contribution without lying. It's usually reflex rather than dishonesty — but it hides exactly what they need to assess.

**The preparation:** for every project on your CV, rehearse the first-person version. What did *you* write, decide, and get paged for?

---

## 595. You say idempotency — show me exactly where.

**A general description will not survive this. Point at the mechanism.**

**The answer they want:** *"Deduplication is on `UNIQUE (provider, event_id)` in `webhook_events`. The insert is `ON CONFLICT DO NOTHING`, and it's in the same transaction as the state change — so if the effect fails, the dedupe row rolls back with it and a retry genuinely reprocesses."*

**The three details that prove understanding** (Q234):
1. **The specific constraint** — table and column names
2. **`ON CONFLICT DO NOTHING`** or equivalent
3. **Same transaction as the work** — this is the one that separates real understanding from a memorised term

**The follow-up:** "what if the marker commits and the work doesn't?" — they're in one transaction, so it can't. **If they weren't, you'd have marked something done that never happened**, which is the classic bug.

**If your system lacks it:** *"Honestly, we rely on the operation being naturally idempotent rather than an explicit key. That works for [X] and wouldn't for [Y] — for payments I'd want the explicit table."*

---

## 596. You call it a distributed system — is it?

**Usually yes, and it's easy to defend with the right definition.**

**The script:** *"Two processes and a network is a distributed system. We have an API, a database on another host, a queue, workers, and a third-party provider — each fails independently and I can't observe them atomically. The label isn't reserved for planet-scale infrastructure; the properties that make it hard are partial failure and no global state, and we have both"* (Q216).

**Then prove it** by naming a problem you actually hit: a dual-write, an ambiguous timeout, a duplicate delivery. **The evidence that it's distributed is that you hit distributed-systems problems.**

**Where to concede:** *"What I haven't dealt with is consensus, sharding, or multi-region — those I know from reading."* Drawing that line yourself pre-empts the follow-up.

---

## 597. Why isn't your agent just a workflow?

**Take it seriously, because most of the time the interviewer is right.**

**The honest test:** *does the number and order of steps depend on what earlier steps find?* If the sequence is always the same, it's a workflow with an LLM inside — **and that's usually the better design** (Q291).

**If it genuinely is an agent:** *"Step count varies from 8 to 40 depending on what earlier retrievals return. A fixed pipeline can't express 'if this lookup is ambiguous, search differently.' That's the runtime path selection that makes it an agent."*

**If it isn't:** *"You're right — most of it is a workflow. There's one branch where the model chooses between three tools based on what it found, and that's the only genuinely agentic part. Calling the whole thing an agent oversells it."*

**The second answer is stronger if it's true.** "Agent" is the most inflated term in the field right now, and a candidate who resists the inflation stands out.

**Extra credit:** *"And workflows are easier to test, cheaper, and more reliable — so I'd want a reason before choosing an agent."*

---

## 598. What did you build beyond API calls?

**The implied accusation: you wrote a wrapper around someone else's model.**

**What counts as beyond:** the deterministic core — scoring, ranking, business rules, state machines (Q305); durability infrastructure — per-step persistence, leases, resumption (Q317); the retrieval pipeline (Q381); tool authorization and validation (Q311); the eval suite (Q371); cost and rate control (Q338).

**The framing that answers it properly:** *"The model calls are the smallest part. The architecture is LLM at the perimeter, deterministic core in the middle — the model parses unstructured input into typed objects and phrases the output, and everything involving money, ordering, or state transitions is ordinary code I wrote and can test. Remove the model and the scoring and state machine are still the system"* (Q302, Q609).

**If the honest answer is "not much beyond API calls":** say so and name what you'd add. **Better than inflating a wrapper into a platform.**

---

## 599. You say RAG — how did you measure it?

**Identical to Q590, asked twice deliberately.**

**One sentence if you have numbers:** *"Thirty-question golden set from real queries, labelled by answering chunk. Recall@5 was 0.74 with pure vector search; hybrid plus a reranker took it to 0.91. Faithfulness measured separately given correct context, plus fifteen unanswerable questions measuring refusal."*

**One sentence if you don't:** *"I haven't measured it formally. That's the first thing I'd fix — 30 questions from production logs, labelled, then measure recall@5 and recall@20. Without those two numbers I'm tuning retrieval on intuition."*

**Why it's asked twice:** it separates people who built a RAG demo from people who operated one. **There is no third answer.** Anything answering with process rather than numbers — "we did extensive testing," "we iterated on user feedback" — is heard as a no.

---

## 600. Your numbers seem too good. Where's the catch?

**Every real number has a caveat. Producing one immediately is the proof of authenticity.**

**The caveats that are nearly always true:**
- **Sample size** — "0.91 on 30 questions is roughly ±0.10; I wouldn't treat a 5-point difference as real" (Q439)
- **Distribution** — "the golden set came from logged queries, which skews toward queries that worked well enough for users to keep using the product"
- **Overfitting** — "I tuned against that set repeatedly, so it's optimistic. I'd want a held-out split" (Q440)
- **Segment variance** — "the aggregate hides that identifier queries are much worse"
- **Conditions** — "that latency is with a warm cache and warm index"

**The script:** *"There is one. [Specific caveat.] I'd want [larger sample / held-out set / production validation] before defending that in a design review."*

**Volunteering the caveat is the single strongest credibility move in this section.** Numbers without limitations read as marketing; numbers with them read as measurement.

---

## 601. Redis loses data on failover — how does your design survive?

**Concede the premise immediately; it's correct** (Q240).

**The script:** *"Yes — replication is asynchronous, so an acknowledged `XADD` can be lost if the primary dies before replicating. That's why the durable record is a PostgreSQL row written before the enqueue. The stream message is a notification, not the source of truth. If the stream loses it, a reaper finds the job row with an expired lease and requeues"* (Q313).

**Follow-up: "what if the reaper is down?"** — *"Then jobs sit in `queued` and the oldest-pending-age metric alerts. It's a delay, not a loss."*

**Follow-up: "why Redis at all?"** — the honest answer is usually throughput or existing infrastructure, **not correctness.** *"For our volume, PostgreSQL `SKIP LOCKED` would have been sufficient and would put the claim and the work in one transaction. I'd choose that today"* (Q551).

**Conceding you'd choose differently now is a strength.** It shows the reasoning is live rather than rehearsed.

---

## 602. You say exactly-once — prove it.

**The correct answer is to withdraw the claim** (Q232).

**The script:** *"I shouldn't claim exactly-once delivery — it's impossible over an unreliable network; that's the Two Generals result. What I have is at-least-once delivery with idempotent consumers, giving effectively-once processing. The enforcement is a unique constraint on `(message_id)` in the same transaction as the effect, so deliveries two through N are no-ops."*

**Why withdrawing is the strong move:** anyone claiming exactly-once delivery is either mistaken or redefining the term. **The interviewer is checking whether you know that.** Defending fails; correcting yourself passes.

**The nuance if they push:** exactly-once *is* achievable within a single system — PostgreSQL `SKIP LOCKED` with the work in the claim's transaction, or Kafka transactions within Kafka. **The moment you have two systems, you're back to at-least-once plus idempotency.**

---

## 603. What breaks first at 10×?

**Have a specific answer with reasoning, not "we'd scale horizontally."**

**The usual order:**
1. **Database connections** — `replicas × workers × pool_size` against `max_connections`. **Binds before CPU does**, and it's the most common self-inflicted outage (Q496).
2. **LLM provider quota** — TPM, where no amount of worker scaling helps (Q339)
3. **A specific slow query** whose plan flips as the table grows (Q166)
4. **Vector index memory** — once it doesn't fit in RAM, latency collapses off a cliff (Q413)
5. **Cost**, before anything technical breaks

**The script:** *"Connection pool, almost certainly. At 10× replicas we'd exceed `max_connections` before CPU. The fix is PgBouncer in transaction mode, and I'd want it in place before scaling — because the failure mode is that scaling the API takes down the database, which takes down everything."*

**What makes it strong:** the failure, the arithmetic, the fix, and why the fix must precede the scaling.

---

## 604. What's in your system you don't understand?

**Everyone has one. Claiming otherwise is the wrong answer.**

**Honest categories:** a dependency you use without knowing internals ("I use HNSW without being able to derive its complexity bounds; I know the parameters and how to measure recall against exact search"); inherited code; a layer below your abstraction ("I understand what the ORM emits when I check; I don't hold its query generation in my head").

**The script:** *"[Specific thing]. I know its interface and failure modes well enough to operate it. If it broke in a way the docs didn't cover, I'd be reading source."*

**What makes it good:** you know the boundary of your understanding and can operate safely inside it. **That's professional competence.** Claiming to understand everything is either false or indicates a very small system.

**Bonus:** name how you'd close the gap if it mattered.

---

## 605. If I removed your best engineer, what falls over?

**Testing bus factor and whether you're honest about organisational risk.**

**The honest answer names a real single point of failure:** *"The [X] service — one person wrote it and holds most of the context. It's documented at the interface level, not the reasoning level. If they left, changing it would be slow and risky for months."*

**Then the mitigation:** what you've done (pairing, documentation, rotating on-call) and **what you haven't.**

**If you're the single point of failure:** say so. *"For [the component you own], that's me. I've written up the process and the decisions, but the accumulated context about why things are the way they are is mostly in my head."*

**Why honesty is better:** every team has this. Claiming otherwise means you either haven't thought about it or aren't being straight. **Naming your own bus factor is a maturity signal.**

---

## 606. What would a staff engineer criticise about your design?

**Argue against yourself competently. One of the highest-signal questions here.**

**Credible criticisms:**
- *"Too many moving parts for the volume. A staff engineer would ask why Redis is there when PostgreSQL `SKIP LOCKED` would do, and I don't have a great answer beyond 'it was already there.'"*
- *"The eval suite came after the system, so early retrieval decisions were unverified."*
- *"No held-out test set, so my quality numbers are optimistic."*
- *"The boundary between [A] and [B] is wrong — they scale differently but deploy together."*
- *"Cost controls were added reactively after a spike, not designed in."*

**What makes it strong:** the criticism is *specific and correct*, and you can either defend the trade or admit you'd change it.

**Failure modes:** a fake criticism ("maybe it's over-engineered for reliability"), or inability to produce one. **Not being able to criticise your own design suggests you never considered alternatives.**

---

## 607. You've never operated this at scale, have you?

**If true, concede immediately and precisely.**

**The script:** *"No. The largest I've operated is [real number]. I know the patterns for the next order of magnitude and where they break — connection pooling, sharding, provider quota — but I'd be applying them for the first time. What I have done is operate something real, with users and money attached, where a bad release cost something."*

**The honest reframe:** **scale is one axis of difficulty and not the only one.** Shipping to a real consumer user base with paid acquisition means release safety, crash triage, store compliance, and attribution — all genuinely hard, none of them QPS.

**What not to do:** claim scale you don't have. The follow-ups — "what was your p99?", "how many connections?", "what did it cost?" — have no answers if you weren't there.

**The closing line:** *"I'd rather tell you the truth about my scale than have you find out in week three."*

---

## 608. What problem does MCP actually solve?

**Answer narrowly and resist overclaiming** (Q299).

**The script:** *"The N×M integration problem. Before it, every LLM application needed custom code for every tool. It standardises tool discovery, invocation, and typed schemas so any client works with any server. Same idea as LSP for editors — turning N×M into N+M."*

**Then, unprompted, the limits:** *"What it doesn't solve is anything hard. It doesn't handle authorization — a server exposes tools, and whether this user may call them is entirely the client's job. It doesn't bound cost and it doesn't help with prompt injection. It's plumbing. Useful plumbing, but I'd be careful not to describe it as more."*

**Why it's on the attack list:** MCP is currently over-described, and interviewers use it to see whether you repeat marketing. **Naming the limits is the point of the answer.**

**Bonus:** a third-party MCP server's tool descriptions enter your model's context verbatim — so it's also a supply-chain and injection surface (Q300).

---

## 609. Where does the LLM NOT belong in your system?

**The best question in the section, and the one where a good answer separates you clearly.**

**The script:** *"Anywhere correctness matters and is expressible in code. Concretely: scoring and ranking, arithmetic, state transitions, authorization decisions, anything touching money, and anything that must be identical across runs."*

**The organising principle:** *"LLM at the perimeter, deterministic core in the middle. The model parses unstructured input into typed objects at the front and phrases the result at the back. Everything between is ordinary code I can unit test"* (Q302, Q305).

**Why it belongs there and nowhere else:** the model is non-deterministic, manipulable by anyone whose text reaches its context, and can't be unit tested. **Those three properties disqualify it from anything where being right every time matters.**

**Concrete examples:**
- **Not** deciding whether a user can afford a transaction — that's a conditional `UPDATE` with a guard
- **Not** ranking by business rules — that's a scoring function
- **Not** authorising a tool call — that's the executor checking the user's scopes (Q311)
- **Yes** for extracting structured data from a document
- **Yes** for writing the explanation a human reads

**Delivered well, this answer does more work than any other single answer in the bank.**

---

## 610. How do you know your agent is working in production?

**Name specific metrics, not "we monitor it."**

**The script:** *"Terminal state distribution is the primary signal — the split between `succeeded`, `max_turns_exceeded`, `budget_exceeded`, `stuck`, and `failed`. A rise in `stuck` after a deploy is a regression the eval suite may have missed. Alongside it: turns per run at p95, cost per successful run, tool error rate per tool, and repeated-call rate"* (Q545).

**The quality proxies, since production has no ground truth:** *"Citation validity and refusal rate compute free on every response and move within minutes of a bad deploy. Thumbs-down and follow-up rate are the direct user signals"* (Q546).

**The tooling:** *"One trace per run, one span per turn, and a run inspector UI — because when someone says the agent did something weird, I need to open that run and read the trajectory. Reconstructing it from logs is too slow."*

**The loop:** *"Thumbs-down responses with their retrieval traces go to a review queue, and confirmed failures become regression cases in CI"* (Q437).

**What makes it strong:** these metrics only exist if you built them, and naming terminal-state distribution specifically signals you've watched one.

---

## 611. What would you be most embarrassed for me to find?

**Answer honestly with something real but not disqualifying.**

**Credible answers:** a module with no tests; error handling that swallows exceptions too broadly; a hardcoded value that should be config; an eval suite covering retrieval well and generation thinly; a TODO from eight months ago that's now load-bearing.

**The script:** *"[Specific thing]. It's been on the list, it hasn't been urgent enough to displace anything, and here's what fixing it would actually take."*

**Why honesty is correct:** the question is designed so any polished answer sounds evasive. **Naming a real rough edge shows you know your own codebase**, and every codebase has them.

**Avoid:** something indicating negligence (no backups, plaintext credentials, no tests at all), something trivially fake ("the naming could be better"), or claiming there's nothing.

---

## 612. Why hire you over someone with five years of AI experience?

**Do not argue you're equivalent. You're not, and claiming it fails immediately.**

**Structure: concede the gap, then name what you bring that they may not.**

**The script:**

*"If the role needs someone who's trained models or run GPU clusters for five years, hire them. What I bring is different: I've shipped and operated production software with real users and real money — release safety, crash triage, security review, compliance. Most of the hard problems in AI engineering turned out to be ones I already recognised: idempotency, at-least-once delivery, cost control, evaluation discipline, and knowing where a non-deterministic component doesn't belong.*

*The gap between an LLM demo and an LLM product is almost entirely production engineering, and that's the part a lot of people arriving from the ML side haven't done. I've done that part. The AI-specific layer I've learned deliberately and can go deep on — retrieval, agent infrastructure, evaluation — but I'd call that strong competence, not five years of scars."*

**Why it works:** true, specific, names the gap without apologising, and identifies a real complementarity rather than a claimed equivalence.

**Optional closing line:** *"I'd rather you hire me for what I actually am than discover in month two that I oversold it."*

---

# Closing note

**The three sentences that do the most work across the entire bank:**

1. **"LLM at the perimeter, deterministic core in the middle."** (Q302, Q609)
2. **"You cannot make this atomic across two systems — you choose which failure you prefer."** (Q41, Q246)
3. **"A Redis lock is an efficiency optimisation, not a correctness guarantee."** (Q188)

**And the one behaviour that matters more than any answer:** concede cleanly, then be specific about what you'd do instead. Every question in Section Q is ultimately testing that.

---

*End of Document 16. All 612 questions complete.*
