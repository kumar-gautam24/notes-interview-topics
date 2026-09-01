# Document 14 — Observability (Questions 529–547)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 529. Logs, metrics, traces?

**The three signals, and the point is that each answers a different question:**

| | Answers | Cardinality | Cost | Retention |
|---|---|---|---|---|
| **Metrics** | *Is something wrong?* | Low (aggregated) | Cheap | Long |
| **Traces** | *Where is it wrong?* | High (per request) | Medium (sampled) | Short–medium |
| **Logs** | *What exactly happened?* | Highest | **Expensive** | Short |

**The workflow they support together:** a metric alerts you that p99 latency doubled. A trace shows the time is in the vector search span. A log line for that trace ID shows the specific query and the index that wasn't used. **Metrics detect, traces localise, logs explain.**

**Why you need all three.** Metrics alone tell you something is wrong with no way to find it. Logs alone are unsearchable at volume and can't show you a distribution. Traces alone are sampled, so the specific failure you care about may not be captured.

**The requirement that makes them work as a system: correlation.** A trace ID on every log line and every span, propagated across service boundaries (Q87, Q536). **Without it you have three disconnected tools and a manual join across timestamps** — which is exactly as bad as it sounds at 3 a.m.

**The fourth signal worth naming: events.** Deploy markers, config changes, incident annotations. A latency graph with a deploy marker on it answers "what changed?" instantly, and it's nearly free to add (Q503).

**The cost reality:** logs are usually the largest observability line item and the least valuable per byte. Sample aggressively, structure everything, and resist the instinct to log more when something breaks — **log better, not more** (Q547).

---

## 530. Structured logging?

**Definition.** Logs emitted as machine-parseable key-value data (JSON), not formatted strings.

```python
# Unstructured — unsearchable at volume
logger.info(f"User {user_id} retrieved {len(chunks)} chunks in {ms}ms")

# Structured — queryable
logger.info("retrieval_complete", extra={
    "user_id": user_id, "tenant_id": tenant_id, "request_id": rid,
    "chunk_count": len(chunks), "duration_ms": ms, "top_score": score,
})
```

**Why it matters:** you can query it. `duration_ms > 1000 AND tenant_id = "x"` is a filter, not a regex against prose. At any real volume, unstructured logs are write-only — you emit them and never successfully search them.

**The conventions that make structured logs usable:**
1. **A stable event name** as the message (`retrieval_complete`), so you can count occurrences of a *type* of event.
2. **Consistent field names across services.** `user_id` everywhere, never `userId` in one place and `uid` in another.
3. **Correlation IDs on every line** — request ID, trace ID, tenant ID (Q536).
4. **Types preserved** — numbers as numbers, so you can aggregate on them.
5. **No PII values** — field names and shapes, hashed identifiers (Q519, Q537).

**Implementation:** `structlog` or `python-json-logger`, with a processor that injects context vars automatically so you never pass the request ID manually.

**The failure to avoid:** logging entire request or response bodies. It's the fastest way to a huge bill and a PII incident simultaneously. **Log the shape, not the content** — field names, sizes, counts.

**The other failure:** logging inside a hot loop. A log line per retrieved chunk across 30 chunks × 1,000 req/s is 30,000 log lines per second for information you'll never read.

---

## 531. Correlation ID?

Full mechanics at Q87. The observability framing:

**Definition.** A unique identifier attached to a request and propagated through every service, log line, metric exemplar, queue message, and trace span it touches.

**Why it's the single most valuable observability primitive:** it converts "something failed somewhere" into a query. A user reports an error with a reference code; one search returns every log line from every service for that request, in order.

**Propagation, and the places people forget:**
- **HTTP** — `X-Request-ID` in and out; generate if absent
- **Logs** — injected automatically via a `ContextVar`-aware processor, never passed by hand
- **Outbound calls** — an httpx event hook adding the header
- **Queue messages** — in the payload, so worker logs correlate with the originating request (Q193)
- **Database** — `SET application_name` or a SQL comment, so `pg_stat_activity` shows which request owns a slow query
- **Error responses** — so a user's screenshot is a searchable key

**Why `ContextVar` and not a global or thread-local:** it's async-aware. Each task gets its own copy, so 1,000 concurrent requests each see their own ID. A module-level global is overwritten by whichever request ran last; a `threading.local` is wrong because many coroutines share one thread.

**Request ID vs trace ID.** A request ID is a grep key. A **trace ID** (W3C `traceparent`) carries sampling flags and span relationships, giving you a full waterfall rather than a flat list. **Use OpenTelemetry and get both** — the trace ID serves as the correlation ID and buys you the causal structure for free.

**For agent systems, add the run ID** (Q314), which correlates work spanning many requests and many turns.

---

## 532. Distributed tracing?

**Definition.** Recording the causal path of a request across services as a tree of timed spans, linked by a shared trace ID and parent-child relationships.

**Why it's necessary the moment you have more than one service:** "the request took 3 seconds" is useless without knowing which of eight components consumed them. **A trace waterfall answers that visually in seconds.**

**The model:**
```
trace: 4bf92f...
├── span: POST /v1/query                    (2,840 ms)
│   ├── span: rewrite_query                    (180 ms)
│   ├── span: embed_query                       (45 ms)
│   ├── span: vector_search                     (28 ms)
│   ├── span: rerank                            (140 ms)
│   └── span: llm.generate                   (2,400 ms)  ← the answer
```

**Implementation with OpenTelemetry:**
```python
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("rerank") as span:
    span.set_attribute("candidates.in", len(candidates))
    span.set_attribute("candidates.out", top_k)
    results = await reranker.score(query, candidates)
```
Auto-instrumentation covers FastAPI, httpx, asyncpg, and Redis with no code changes — **start there**, then add manual spans for your domain logic.

**Sampling** (Q543) — you cannot trace everything at volume.

**The attributes that make a trace useful rather than decorative:** model name, token counts, cost, retrieved chunk count, top similarity score, cache hit/miss, tenant ID. **A span with only a name and a duration tells you where the time went; a span with attributes tells you why.**

**The LLM-specific value** (Q545): agent runs are variable-length and non-deterministic, so a trace is often the *only* record of what path a run took. One span per turn, nested spans for model calls and tool executions, makes an agent's behaviour legible in a way logs alone cannot.

---

## 533. RED / USE metrics?

**Two complementary frameworks — RED for services, USE for resources.**

**RED (request-driven services):**
- **Rate** — requests per second
- **Errors** — failed requests per second (and as a rate)
- **Duration** — latency distribution, as percentiles

**USE (resources):**
- **Utilisation** — % of time the resource is busy
- **Saturation** — queued work waiting for it
- **Errors** — error events

**Why both.** RED tells you what users experience. USE tells you what's constraining you. **A service with rising latency (RED) and a saturated connection pool (USE) has a diagnosis; either alone has a symptom.**

**Applied to your stack:**

| Component | RED | USE |
|---|---|---|
| API | req/s, 5xx rate, p50/p95/p99 | Worker pool saturation, event loop lag |
| Database | queries/s, errors, duration | Connection pool utilisation, checkout wait |
| Queue | enqueue/dequeue rate, failures | **Queue depth, oldest-message age** |
| LLM provider | calls/s, error rate, TTFT/TPOT | Rate-limit headroom, token quota used |
| GPU | requests/s | GPU utilisation, KV cache utilisation, pending queue |

**The saturation metrics are the ones people omit and the ones that give you warning.** Connection pool *checkout wait time* rises minutes before the pool exhausts (Q496). Queue *oldest-message age* tells you about SLO breach before depth does (Q202). **Utilisation tells you where you are; saturation tells you where you're going.**

**Report percentiles, never averages.** An average latency of 200ms is compatible with 5% of users waiting 4 seconds. **The average is the one number guaranteed to hide the problem.**

---

## 534. SLI / SLO / SLA?

**SLI (Indicator)** — a measured quantity. "Proportion of requests completing in under 500ms."
**SLO (Objective)** — your internal target. "99.5% of requests under 500ms over 28 days."
**SLA (Agreement)** — a contractual commitment with penalties. Always looser than your SLO.

**Why the layering:** the SLO is where you actually operate; the SLA has money attached and needs margin. **If your SLO equals your SLA, you pay out every time you miss internally.**

**Choosing good SLIs — the test is whether the user would notice.** Availability and latency, measured from the user's perspective (at the load balancer, not inside the pod). CPU utilisation is not an SLI; nobody has ever been unhappy about CPU.

**Error budget — the concept that makes SLOs operationally useful:**
```
error_budget = 1 - SLO = 0.5% of requests over 28 days
```
This is a **budget you are allowed to spend.** It reframes reliability from "never fail" to "fail within an agreed allowance," which:
- Makes the reliability/velocity trade-off explicit and negotiable
- Gives an objective rule: budget exhausted → freeze risky deploys until it recovers
- Stops the argument between shipping and stability being about opinions

**Alert on burn rate, not on threshold breaches** (Q539). "We're consuming error budget 14× faster than sustainable" is actionable; "error rate is 0.6%" is not, because it doesn't tell you whether that matters.

**For an AI system**, SLIs need care: availability and latency are standard, but **answer quality is also an SLI** and it's much harder to measure continuously. Proxies: refusal rate, citation validity, thumbs-down rate (Q438, Q546).

---

# L2 — Engineering

## 535. What should you log?

**Log decisions and boundaries, not narration.**

**Log these:**
- **Request boundaries** — method, path, status, duration, request ID (usually via middleware, once per request)
- **External calls** — service, operation, duration, outcome
- **State transitions** — order moved from `pending` to `paid`, with cause
- **Authorization decisions**, especially denials
- **Errors with context** — what was being attempted, with which inputs (redacted), and the exception chain (Q19)
- **Business events** worth counting or auditing
- **Configuration at startup** — versions, feature flags, which model, which prompt hash

**Do not log:**
- **Entire request/response bodies** — cost and PII in one move (Q537)
- **Inside hot loops** — per-chunk, per-token, per-row
- **Success narration** — "entering function", "got a result", "about to return"
- **Anything a metric would answer better.** "Request took 120ms" is a metric. Logging it per request and then aggregating in your log tool is expensive and slow.

**The discipline that most improves log quality:** before adding a log line, ask *what question does this answer, and would a metric or a trace answer it better?* Most log lines in a typical codebase answer no question anyone asks.

**Log levels, used consistently:**
- **ERROR** — something failed that needs a human. Should be rare enough to alert on.
- **WARN** — degraded but handled. Fallback used, retry exhausted, circuit opened.
- **INFO** — business events and boundaries.
- **DEBUG** — off in production. If you need it in production, that's a signal you're missing a trace or a metric.

**The volume test:** if a log level generates so much output that nobody reads it, it isn't logging — it's a bill.

---

## 536. Correlating across services?

Full mechanics at Q531. The cross-service specifics:

**Use W3C Trace Context** — the `traceparent` header — rather than a bespoke ID. It's the standard, it's what OpenTelemetry propagates automatically, and it carries the sampling decision so downstream services make the same choice.

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             │  └─ trace-id ──────────────────┘ └─ span-id ────┘ └─ flags
```

**Where propagation breaks, and these are the gaps that make traces useless:**

1. **Queue boundaries.** Async work loses the trace unless you explicitly inject the context into the message and extract it in the consumer. **This is the most common gap** — you get a beautiful trace for the API request and nothing for the work it triggered.
```python
carrier = {}
TraceContextTextMapPropagator().inject(carrier)
await queue.publish({"payload": data, "trace_context": carrier})
```
2. **Background tasks** — `create_task` copies the context at creation, so this usually works; a task created outside the request scope does not.
3. **Third-party services** that don't propagate — the trace ends there. Record what you sent and received.
4. **Batch processing** — one message per trace, or a link back to the originating traces via span links.

**Beyond the trace ID, propagate business identifiers** — tenant ID, user ID, run ID — via OpenTelemetry Baggage, so every downstream span carries them and you can filter traces by tenant. **Filtering by tenant is what turns tracing from a debugging tool into an incident-response tool.**

**The verification:** pick a request in production and confirm you can follow it from ingress through queue to worker to database. **If you can't, your tracing is decorative.**

---

## 537. What should you never log?

**The prohibited list:**

- **Credentials** — passwords, tokens, API keys, session IDs, private keys
- **PII values** — names, emails, phone numbers, addresses, national IDs, dates of birth
- **Payment data** — card numbers, CVV, bank details
- **Health data**
- **Full request/response bodies** — these contain all of the above by default
- **The full environment** — a common way keys leak
- **Query strings containing tokens** — access logs capture these automatically (Q51)

**How leaks actually happen, which is more useful than the list:**
1. **Debug logging added during an incident** and never removed. **This is the most common path** — someone adds `logger.debug(f"payload: {body}")` at 2 a.m. to diagnose something, and it ships.
2. **Exception handlers logging the full request context**
3. **Error-tracking tools capturing local variables by default** (Sentry does this)
4. **Access logs recording query strings**
5. **A third-party SDK logging its own requests**

**The controls:**
1. **Redaction at the logging layer**, not at each call site. A processor that scrubs known-sensitive field names centrally, so an individual developer forgetting doesn't cause a leak.
```python
SENSITIVE = {"password", "token", "api_key", "authorization", "ssn", "card_number"}
def redact(logger, name, event_dict):
    for k in list(event_dict):
        if k.lower() in SENSITIVE:
            event_dict[k] = "[REDACTED]"
    return event_dict
```
2. **Log field names and shapes, never values.** `{"fields": ["email", "name"], "size": 412}`.
3. **Hash identifiers** for correlation without exposure.
4. **Configure error tools** to disable variable capture on sensitive paths.
5. **Automated scanning** of log output for identifier patterns.

**The LLM-specific hazard** (Q326): retrieved chunks and prompts contain source-document content. **Logging the full prompt logs the customer data you just retrieved.** Log chunk IDs and token counts, not chunk text.

---

## 538. Sampling logs and traces?

**Why sample: at volume, capturing everything is prohibitively expensive** and the marginal value of the 10,000th identical successful trace is zero.

**Trace sampling strategies:**

**Head-based** — decide at the start of the request, propagate the decision.
- Simple, low overhead, consistent across services
- **Problem: you decide before you know whether the request is interesting.** A 1% sample misses 99% of your errors.

**Tail-based** — buffer spans, decide when the trace completes.
- **Keep all errors, all slow requests, and a sample of the rest.** This is what you actually want.
- Costs memory in the collector and requires all spans of a trace to reach the same collector instance.

**The practical configuration:**
```yaml
tail_sampling:
  policies:
    - {type: status_code, status_code: {status_codes: [ERROR]}}   # 100%
    - {type: latency, latency: {threshold_ms: 1000}}              # 100%
    - {type: probabilistic, probabilistic: {sampling_percentage: 1}}
```
**100% of errors and slow requests, 1% of the healthy majority.** Ten to a hundred times cheaper than full capture, with essentially no loss of diagnostic value.

**Log sampling:** always log errors and warnings; sample high-volume INFO. Sample *per event type*, not uniformly — health check logs can be sampled at 0.01% while payment events are kept entirely.

**The trade-off to name:** sampling means the specific request a user complains about may not be captured. **Mitigations:** always sample by trace ID consistently so a sampled trace is complete; keep correlation IDs in *all* logs even when the trace is dropped; and support **forced sampling** via a debug header so support can capture a full trace on demand for a reproducing user.

**Metrics are never sampled** — they're aggregated, so they're cheap and complete. That's why the metric layer, not the log layer, should answer "how often does this happen."

---

## 539. Alert design?

**The principle: alert on symptoms users experience, not on causes.**

High CPU is a cause; it may or may not matter. Elevated error rate is a symptom; it always matters. **Cause-based alerts produce noise because most causes are self-correcting.**

**What to alert on:**
1. **SLO burn rate** (Q534) — the best primary alert. Multi-window: a fast burn (2% of budget in 1 hour) pages immediately; a slow burn (10% in 3 days) creates a ticket.
2. **Error rate** above baseline
3. **Latency percentiles** breaching the SLO
4. **Saturation approaching limits** — connection pool wait time, queue oldest-message age, disk filling. **These are the leading indicators** (Q533).
5. **Absence of expected activity** — no orders processed in an hour. **Silence is a failure mode nothing else catches.**
6. **Cost anomalies** — cost per request rising (Q462)

**What NOT to alert on:** individual errors, CPU/memory without user impact, single pod restarts, anything that self-heals before a human could respond.

**Alert quality rules:**
- **Every page must be actionable.** If the response is "acknowledge and ignore," delete the alert.
- **A runbook link on every alert** — what it means, what to check, what to do.
- **Severity tiers** — page vs ticket vs dashboard-only. Most alerts are not pages.
- **Bounded duration and thresholds** to avoid flapping.
- **Inhibition** — a "database down" alert should suppress the twelve dependent service alerts.

**The failure mode that matters most: alert fatigue.** A team paged six times a night stops reading pages, and the seventh — the real one — is missed. **Fewer, better alerts is a safety improvement, not a compromise.** Review alert volume monthly and delete the ones that never led to action.

---

## 540. Dashboards?

**Design them for a specific question, not as a display of everything you collect.**

**The tiers:**

**1. Service overview (the on-call first stop).** RED metrics for the service, top errors, deploy markers, and the state of its dependencies. **One screen, no scrolling.** The question it answers: *is this service healthy, and if not, is it us or a dependency?*

**2. Per-domain deep-dive.** Retrieval quality, queue health, LLM cost and latency, database performance. Reached from the overview when it points somewhere.

**3. Business/product.** Requests per tenant, cost per tenant, feature usage, quality signals.

**The conventions that make dashboards usable at 3 a.m.:**
- **Deploy and config-change annotations on every time series.** A latency graph with a deploy marker answers "what changed?" in one glance, and it's the highest value-to-effort addition available (Q503).
- **Percentiles, not averages** (Q533)
- **Consistent time ranges** across panels so you can compare
- **Thresholds drawn on the graph** so "is this bad?" is visual
- **Links to the corresponding traces and logs**, pre-filtered

**The anti-patterns:**
- **Wall-of-graphs dashboards** with 40 panels nobody reads. If a panel has never informed a decision, remove it.
- **Vanity metrics** — total requests ever served
- **Dashboards nobody opens except during incidents.** If it's only useful during an incident, it hasn't been validated — you'll discover it's wrong exactly when you need it.

**The test:** hand the dashboard to someone who didn't build it and ask them to determine whether the service is healthy. **If they can't in 30 seconds, redesign it.**

---

## 541. On-call and runbooks?

**A runbook turns an alert into a procedure**, so the person paged at 3 a.m. doesn't have to reason from first principles while half awake.

**What a runbook must contain:**
1. **What this alert means**, in one sentence
2. **User impact** — is anyone affected, and how badly?
3. **First checks** — the specific dashboards and queries, linked
4. **Common causes**, ordered by likelihood
5. **Mitigation steps** — including the safe blunt instruments (roll back, scale up, disable the feature)
6. **Escalation** — who to call and when
7. **What NOT to do** — the actions that make it worse

**The mitigation-first principle:** the runbook's job is to **stop user impact**, not to diagnose root cause. Roll back first, investigate afterwards. **A runbook that starts with "identify the root cause" is wrong** — that's the post-incident job.

**What makes on-call sustainable:**
- **Alert volume low enough to sleep** (Q539)
- **Blameless post-incident reviews** focused on system and process, not people
- **Action items tracked and completed** — a review that produces items nobody does is theatre
- **Rotation with genuine handoff**, and time off after a bad night
- **The people who write the code carry the pager.** It's the only reliable feedback loop for operability.

**Runbook maintenance:** update after every incident that used it. **A runbook that's wrong is worse than none**, because it sends someone confidently in the wrong direction.

**For AI systems specifically**, runbooks need entries for: provider outage and fallback (Q461), cost spike and kill switch (Q462), quality regression after a prompt deploy (Q546), and index staleness. **These are the failure modes that don't exist in ordinary services**, and nobody will improvise them well at 3 a.m.

---

## 542. Debugging a production issue?

**A method, not a list — that's what the question is testing.**

**1. Stop the bleeding first.** If users are affected, mitigate before diagnosing. Roll back, scale, disable the feature, shed load. **Diagnosis happens after impact is contained**, and a deploy in the last hour is the single most likely cause — check that first, always.

**2. Establish the shape.** Which users, which endpoints, which regions, since when? **The blast radius is the most informative early signal.** All endpoints slow → shared resource (event loop, database, network). One endpoint → that code path. One tenant → their data or their configuration.

**3. Correlate with changes.** Deploys, config changes, feature flags, migrations, traffic shifts, dependency updates. **Most incidents are caused by a change**, and the annotation on your dashboard should make this a five-second check (Q540).

**4. Follow the signals in order.** Metric (what changed) → trace (where the time or errors are) → log (what specifically happened) (Q529).

**5. Form one hypothesis and test it.** Not five simultaneously. Changing several things at once during an incident means you won't know what fixed it.

**6. Preserve evidence before restarting.** `py-spy dump`, a heap snapshot, the current plan, `pg_stat_activity`. **Restarting destroys the only evidence you have**, and "it resolved on restart" is not a diagnosis (Q39).

**The tools worth naming for a Python service:**
```bash
py-spy dump --pid <pid>          # what every thread is doing, no restart
py-spy top  --pid <pid>          # live CPU by function
kubectl logs <pod> --previous    # the crashed instance (Q491)
```
`py-spy` is the highest-value production debugging tool for Python and works with zero code changes.

**7. Write it up.** What happened, why, what would have detected it sooner, what prevents recurrence. **"What would have detected it sooner" is the most valuable question** and the one most often skipped.

---

# L3 — AI observability

## 543. Tracing an LLM pipeline?

**Why LLM pipelines need tracing more than ordinary services:** the path is variable, the components are numerous, and the latency is dominated by a black box. **"The query took 4 seconds" has eight possible explanations** and only a trace distinguishes them.

**The span structure:**
```
rag.query                                    (3,140 ms)
├── rewrite_query          model=haiku       (   180 ms)
├── embed_query            cache_hit=false   (    45 ms)
├── retrieve
│   ├── vector_search      k=50, top=0.83    (    28 ms)
│   └── bm25_search        k=50              (    19 ms)
├── fuse                   in=87, out=50     (     2 ms)
├── rerank                 in=50, out=5      (   140 ms)
└── generate               model=sonnet      ( 2,720 ms)
    ├── ttft                                 (   610 ms)
    └── tokens_out=412, cost_cents=3.1
```

**The attributes that make it diagnostic rather than decorative:**
- **Per stage:** duration, input/output counts, cache hit/miss
- **Retrieval:** k, top score, score distribution, filter applied, **the retrieved chunk IDs**
- **Generation:** model, prompt version, input/output tokens, TTFT, cost, stop reason, cache hit rate
- **Cross-cutting:** tenant, user, request ID, run ID

**Logging the retrieved chunk IDs is the one to insist on.** It's what makes the retrieval-vs-generation diagnostic possible after the fact (Q375) — without it you cannot answer "was the right chunk in context?" for a query that failed last week.

**Sampling:** keep 100% of errors, 100% of slow requests, 100% of thumbs-down responses, and 1–5% of the rest (Q538). **Sampling on the feedback signal is the AI-specific addition** — a trace attached to a negative rating is a labelled failure case, ready for your eval set (Q437).

**Tooling:** OpenTelemetry with semantic conventions for GenAI, or a purpose-built tool (LangSmith, Langfuse, Phoenix). **OTel keeps you portable**; the specialised tools give better prompt-diffing and eval integration out of the box.

---

## 544. Token and cost tracking?

**Cost is a first-class operational metric in AI systems**, because it varies per request by orders of magnitude and can run away silently (Q462).

**What to record on every model call:**
```python
span.set_attributes({
    "llm.model": model,
    "llm.prompt_version": prompt_hash,
    "llm.tokens.input": usage.input_tokens,
    "llm.tokens.output": usage.output_tokens,
    "llm.tokens.cache_read": usage.cache_read_input_tokens,
    "llm.tokens.cache_write": usage.cache_creation_input_tokens,
    "llm.cost_cents": compute_cost(model, usage),
    "llm.stop_reason": response.stop_reason,
})
```

**The dimensions to aggregate by:** tenant, endpoint/feature, model, prompt version, and — for agents — run and turn.

**The metrics that matter:**

1. **Cost per successful request.** Not total cost. **Total cost rising with traffic is normal; cost per request rising is a bug** (Q462). The "successful" qualifier matters because failed and refused requests still cost money.
2. **Cache hit rate** and the fraction of input tokens served from cache. A drop means someone put something volatile in the prompt prefix (Q453) — invisible otherwise, and expensive.
3. **Input:output token ratio.** A shift means context or output length changed.
4. **Cost per tenant**, for billing, capacity planning, and detecting a runaway integration.
5. **Tokens per turn** for agents — the driver of the quadratic cost growth (Q296).

**Alerting:**
- Cost per request above baseline → a prompt or retrieval change
- Tenant approaching daily budget → circuit breaker imminent (Q336)
- Absolute spend rate → the blunt safety net
- Cache hit rate dropping → a prefix regression

**The `stop_reason` field is worth calling out:** a rising rate of `max_tokens` means truncated outputs, which for structured output means parse failures (Q275, Q320). It's free to track and it catches a real failure class.

---

## 545. Agent run observability?

**The distinguishing problem: an agent's behaviour is not reproducible from its code.** Same code, different path per run. **The trace and the step store are the only record of what happened** (Q327, Q337).

**The structure:** one trace per run, one span per turn, nested spans for model calls and tool executions.
```
agent.run  run_id=abc  turns=14  cost=42c  status=succeeded
├── turn.1  ├── llm.call (tokens, cost)  └── tool.search_policies (140ms)
├── turn.2  ├── llm.call                  └── tool.get_policy      (60ms)
...
└── turn.14 └── llm.call  stop_reason=end_turn
```

**The metrics unique to agents:**

| Metric | Signals |
|---|---|
| **Terminal state distribution** | `succeeded` / `max_turns` / `budget_exceeded` / `stuck` / `failed` |
| Turns per run (p50/p95/p99) | Efficiency; approaching the cap |
| Cost per run | (Q544) |
| Tool call rate, error rate, latency **per tool** | Which tool is broken or badly described (Q430) |
| **Repeated-call rate** | Loops, unclear tool results (Q322) |
| Invented-tool-name rate | A capability gap (Q288) |
| Unauthorized tool attempts | Security signal (Q325) |
| Time to first progress event | Perceived responsiveness |

**The terminal state distribution is the single most valuable agent metric.** It's your quality signal, your cost signal, and your regression detector in one. **A rise in `stuck` after a prompt deploy is a regression your eval suite may not have caught** (Q337).

**A run inspector UI is not optional.** When someone reports "the agent did something weird," you open that run and read the trajectory — every message, every tool call, every result. Reconstructing that from logs is too slow to be useful, and it's the single highest-value internal tool for an agent product.

**Version everything on the run** — prompt hash, model version, tool schema version (Q329). Without them a run from three weeks ago is uninterpretable.

---

## 546. Detecting quality regression?

**The hardest observability problem in AI systems, because production has no ground truth.** You cannot compute accuracy on live traffic — nobody labelled it.

**So you use proxies, and the good ones are free and mechanical:**

| Signal | Cost | Detects |
|---|---|---|
| **Citation validity rate** | Free | Generation regression, fabricated citations (Q368) |
| **Refusal rate** | Free | Retrieval breakage, index staleness, threshold drift (Q425) |
| **Retrieval score distribution** | Free | Corpus or embedding drift (Q370) |
| **Zero-result rate** | Free | Filter bugs, ANN+filter interaction (Q414) |
| **Answer length distribution** | Free | Prompt regression |
| **Thumbs-down rate** | Free | Direct user judgement |
| **Follow-up / rephrase rate** | Free | Unsatisfying answers |
| Sampled LLM-judge grounding | ~1% of traffic | Hallucination trend |

**The free mechanical ones are the workhorses.** Citation validity and refusal rate compute on every response at zero cost and move immediately when something breaks. **A deploy that takes refusal rate from 8% to 22% is visible in minutes**, long before anyone complains.

**Alert on distribution shifts, not absolute thresholds.** Refusal rate tripling matters regardless of its baseline value.

**The critical linkage: deploy annotations.** A quality metric shifting *at a deploy boundary* is a regression; the same shift without a deploy is drift, and they need different responses (Q540).

**Sampled judge evaluation** on 1% of traffic gives a continuous quality trend at manageable cost — the closest thing to measuring quality in production.

**The loop that makes it worthwhile** (Q437): production signal → sampled review → confirmed failure → regression set → CI. **Without that loop you detect regressions and never prevent the next one.**

**And the honest caveat:** these are proxies. They detect large regressions reliably and subtle quality erosion poorly. **The eval suite catches what proxies miss; production monitoring catches what the eval set didn't include.** You need both (Q434).

---

## 547. Observability cost control?

**Observability spend is routinely a top-three infrastructure line item**, and it's usually dominated by logs, which are the least valuable signal per byte.

**The levers, in order of impact:**

**1. Sample traces** (Q538). Tail-based: 100% of errors and slow requests, 1% of the rest. **10–100× reduction with essentially no diagnostic loss.**

**2. Control metric cardinality — the biggest and least understood cost driver.** Every unique label combination is a separate time series. A label with unbounded values (user ID, request ID, full URL path) creates millions of series and will produce a memorable bill and an unstable Prometheus.
```python
# Catastrophic — one series per user
counter.labels(user_id=uid, endpoint=path).inc()

# Correct — bounded label values
counter.labels(endpoint=route_template, status=status_class).inc()
```
**Use the route template, not the resolved path.** `/users/{id}` is one series; `/users/12345` is one per user.

**3. Cut log volume.** Drop DEBUG in production, sample high-volume INFO, remove health-check and static-asset logs, and delete the log lines that answer no question (Q535).

**4. Tier retention.** Traces 7 days, logs 14–30, metrics 13 months. Archive to S3 if you need long retention for compliance — object storage is orders of magnitude cheaper than an indexed log store.

**5. Move to metrics what doesn't need to be a log.** Counting occurrences is a metric, not a log query. **This is usually the largest structural saving** because it converts an expensive high-cardinality store into a cheap aggregated one.

**6. Self-host where volume justifies it** — Prometheus, Loki, Tempo instead of a per-GB vendor. Trades cost for operational burden; the crossover is real and volume-dependent (same reasoning as Q450).

**The framing:** *"Observability cost is mostly a symptom of logging things a metric should answer. Fixing the signal choice reduces cost and improves usability at the same time — I'd rather have fewer, better signals than complete capture nobody can query."*

---

*End of Document 14. Next: Document 15 — System design (questions 548–571).*
