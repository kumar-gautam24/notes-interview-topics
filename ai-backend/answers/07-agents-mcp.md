# Document 07 — Agents / MCP / Tool Calling (Questions 291–339)

Answer format: **definition → why → implementation → failure → trade-off → real example**

> **Note on Section G.** Questions 302, 313–315 and several L3/L4 items refer to *your* specific workflow. The answers below give the correct structure and reasoning; you must substitute your real turn counts, tool names, and measured numbers. An interviewer will push on specifics, and a generic answer to Q302 or Q598 will not survive the follow-up.

---

# L1 — Foundation

## 291. What is an agent?

**Definition.** A system where a language model decides, in a loop, which actions to take to reach a goal — rather than following a path fixed in advance by a developer.

**The minimal loop:**
```
observe state → model decides next action → execute → observe result → repeat
                                                    ↓
                                          until goal met or limit hit
```

**The three properties that make something an agent:**
1. **The model chooses the action**, not a `switch` statement you wrote.
2. **The path is not known in advance** — the number and order of steps varies by input.
3. **It acts on the world** — tools with real effects, not just text generation.

**Why this is architecturally different.** A traditional program has a control flow you can draw. An agent's control flow is generated at runtime by a probabilistic system. That means you cannot test all paths, you cannot bound the step count by inspection, and you cannot predict cost per run. **Every engineering problem in this section flows from that one fact.**

**The honest framing to have ready** (it pre-empts Q597): most things marketed as agents are workflows with an LLM inside. That's usually the correct design. The question is not "is it agentic" but "does the task genuinely require runtime path selection?" If the steps are always the same, a workflow is simpler, cheaper, testable, and more reliable — and you should say so.

---

## 292. Chatbot vs agent?

| | Chatbot | Agent |
|---|---|---|
| Output | Text | Actions with side effects |
| Turns | One model call per user message | Many model calls per user message |
| State | Conversation history | Conversation + task state + tool results |
| Failure | A bad answer | A bad *action* — data written, money moved |
| Cost per interaction | Predictable | **Unbounded without controls** |
| Termination | User stops talking | Needs an explicit condition (Q297) |
| Testing | Compare output text | Must verify the action sequence and its effects |

**The distinction that matters most is blast radius.** A chatbot that hallucinates gives a wrong answer the user can ignore. An agent that hallucinates *calls a tool*. If that tool writes to a database, sends an email, or moves money, the mistake is durable and sometimes irreversible.

**That difference is why agents need everything in this document** — authorization at the executor (Q311), human approval for dangerous tools (Q335), audit trails (Q327), step and spend caps (Q306). None of that is needed for a chatbot.

**The middle ground worth naming:** a chatbot *with* read-only tools (RAG, search) is not really an agent — the loop is usually one retrieval and one generation, and the blast radius is zero. Call it retrieval-augmented generation and reserve "agent" for systems that take consequential actions in a variable-length loop. Being precise here is itself a signal.

---

## 293. What is a tool?

**Definition.** A function the model can request, exposed to it via a typed schema (Q283). Your code executes it; the model only proposes.

**What a well-designed tool looks like:**
- **Single responsibility.** `get_policy_details(policy_id)`, not `do_policy_stuff(action, params)`.
- **Typed and constrained** — enums, bounded numbers, validated strings (Q284).
- **Idempotent where possible** (Q310).
- **Returns structured, bounded output.** Never dump 50,000 tokens into context.
- **Fails with an actionable error** (Q319).
- **Authorised at execution**, with security context injected server-side (Q289).

**The design principle that matters:** tools should map to *user intents*, not to your database schema. `search_policies(query, type)` is a good tool. `select_from_policies_table(where_clause)` is a security incident with a friendly name (Q527).

**Read tools vs write tools** should be treated as different categories with different controls. Read tools can be liberal — worst case is wasted tokens. Write tools need authorization, idempotency keys, audit logging, and often human approval. Mixing them in one permission tier is a mistake.

**The context cost.** Every tool definition consumes tokens on every turn. Twenty verbose schemas can be several thousand tokens per call, resent every turn (Q271). Tool count is a budget, not a free dimension.

---

## 294. Agent loop?

**The canonical structure:**
```python
async def run_agent(run_id, initial_input, max_turns=40, max_spend_cents=500):
    state = await load_or_init(run_id)

    while state.turn < max_turns:
        if state.spend_cents > max_spend_cents:
            return await terminate(state, "budget_exceeded")
        if await is_cancelled(run_id):
            return await terminate(state, "cancelled")

        response = await model.call(state.messages, tools=TOOLS)
        await persist_step(run_id, state.turn, "model", response)   # ← before acting

        if response.stop_reason != "tool_use":
            return await terminate(state, "completed", response.text)

        for call in response.tool_calls:
            result = await execute_tool(call, state.ctx)             # authorised
            await persist_step(run_id, state.turn, "tool", result)
            state.messages.append(result)

        state.turn += 1

    return await terminate(state, "max_turns_exceeded")
```

**The four things that make this production code rather than a demo:**

1. **Persist before acting.** Each step is committed before the next begins, so a crash resumes rather than restarts (Q303, Q321).
2. **Bounds on both turns and spend.** Turn count alone is insufficient — one turn can be expensive.
3. **Cancellation checked between turns**, since you cannot interrupt an in-flight model call (Q323).
4. **Every terminal path is explicit.** `completed`, `max_turns_exceeded`, `budget_exceeded`, `cancelled`, `failed`. A loop with only a success exit will eventually hang in a state nobody can query.

**The ReAct pattern** (Reason → Act → Observe) is the same loop with an explicit reasoning step surfaced before each action. Useful for debuggability — you can read *why* the model chose a tool — at the cost of extra tokens per turn.

---

## 295. State machine?

**Definition.** Modelling the agent run as a set of explicit states with defined transitions, rather than as an implicit position in a Python loop.

**Why it matters here specifically.** An agent run is long, resumable, cancellable, and can be inspected mid-flight. All of that requires the run's status to be a queryable value, not a program counter in a process that may not exist.

```
queued → running → awaiting_approval → running → succeeded
    ↓        ↓              ↓                        ↓
cancelled  failed      cancelled/expired         (terminal)
```

**The properties it buys:**
1. **Resumability.** A new worker reads the state and continues (Q317).
2. **Idempotent transitions.** `UPDATE runs SET status='running' WHERE id=$1 AND status='queued'` — zero rows means someone else claimed it. Duplicate delivery becomes a no-op (Q243).
3. **Stuck detection.** "Runs in `running` with an expired lease" is a query (Q202).
4. **Human approval is a first-class state**, not an in-memory flag that vanishes on restart (Q335).
5. **Auditability** — every transition is a row with a cause and a timestamp.

**The rule from Document 03 applies unchanged:** every transition is guarded in the `WHERE` clause, and every non-terminal state needs a timeout and an owner. A state with no exit condition is where runs go to disappear.

---

## 296. Turn?

**Definition.** One iteration of the loop: a model call, plus any tool executions it requests, plus their results appended to context.

**What a turn costs:**
- One model call, billed on the *entire* accumulated context (Q271)
- Latency: time-to-first-token plus generation, plus tool execution time
- Context growth: the model's output plus all tool results

**Why turn count is the primary cost driver.** Because there is no session, turn N resends turns 1..N−1. A 40-turn run isn't 40× a single call — it's closer to the sum of a growing series. **Doubling turns roughly quadruples input tokens.** This is the arithmetic that makes agent runs surprisingly expensive and why step caps are a cost control, not just a safety net.

**Turns are the natural unit for everything operational:**
- The persistence boundary (`run_steps` keyed on `(run_id, seq)`)
- The cancellation checkpoint
- The budget check
- The progress event emitted to the client
- The resumption point

**The tuning question:** fewer, richer turns (many tools per turn, larger tool results) versus more, smaller turns. Fewer turns is cheaper and faster; more turns gives finer-grained resumption and better observability. **Parallel tool calls within one turn** is usually the right optimisation — three independent lookups in one turn instead of three sequential turns.

---

## 297. Termination condition?

**The set of conditions under which the loop stops.** An agent without explicit termination is a program that can run — and bill — forever.

**Every terminal condition you need:**

| Condition | Trigger | Result |
|---|---|---|
| **Goal reached** | Model returns text without a tool call | `succeeded` |
| **Max turns** | `turn >= limit` | `max_turns_exceeded` |
| **Budget exceeded** | Accumulated spend over cap | `budget_exceeded` |
| **Wall-clock timeout** | Run duration exceeded | `timed_out` |
| **Cancelled** | User or system requested stop | `cancelled` |
| **Repeated identical action** | Same tool + args N times (Q322) | `stuck` |
| **Unrecoverable tool failure** | Critical tool down after retries | `failed` |
| **Approval expired** | Nobody approved within the window | `expired` |
| **Content/safety stop** | Provider refusal or filter | `failed` |

**The point to make:** "the model decides it's done" is *one* condition, and it's the only one you can't rely on. Everything else is a bound you impose because the model's judgement about completion is itself probabilistic.

**Multiple independent limits are essential**, because they fail differently. Turn caps don't catch one enormous expensive call. Budget caps don't catch a run that's cheap but stuck for an hour. Time caps don't catch a fast infinite loop. You need all of them, and each should be its own explicit terminal state so the failure mode is visible in your metrics rather than lumped into `failed`.

---

## 298. What is MCP?

**Definition.** The Model Context Protocol — an open standard for how applications expose tools, resources, and prompts to LLM systems. A client-server protocol with a defined message format, transport, and capability negotiation.

**The components:**
- **Server** — exposes tools, resources (readable data), and prompt templates
- **Client** — the LLM application that connects and consumes them
- **Transport** — stdio for local processes, HTTP/SSE for remote

**What it standardises:** tool discovery (`list_tools`), invocation (`call_tool`), typed schemas, resource access, and error semantics — so any MCP client can talk to any MCP server without bespoke integration code.

**The analogy that lands:** MCP is to tool integration what the Language Server Protocol was to editor integrations. Before LSP, every editor needed a custom plugin for every language — an N×M problem. LSP made it N+M. MCP does the same for LLM tooling.

**What it is not:** it isn't a framework, an agent runtime, or a reasoning system. It's a transport and contract layer. **It does not solve authorization** — a server can expose a dangerous tool, and it's the client's job to decide whether this user may call it. Confusing "MCP standardises the interface" with "MCP makes it safe" is a mistake worth avoiding out loud (Q311).

---

## 299. What problem does MCP solve?

**The N×M integration problem.** Before a standard, every LLM application needed custom integration code for every data source and tool. Five applications × twenty tools is a hundred bespoke integrations, each maintained separately, each with its own schema format and error conventions.

**With MCP:** twenty servers and five clients, and any client works with any server. N+M.

**The secondary problems it addresses:**

1. **Tool schema fragmentation.** Every provider had its own function-calling format. MCP gives one definition that works across clients.
2. **Reuse across applications.** A Postgres MCP server written once is usable by your agent, your IDE assistant, and your internal tooling.
3. **Separation of concerns.** The tool's owner maintains the server; the application owner maintains the agent. They evolve independently behind a versioned contract.
4. **Discovery.** A client can enumerate a server's capabilities at runtime instead of hardcoding them.

**The honest limitation.** MCP solves *plumbing*. It does not solve the hard parts: which tools to expose to which user, how to authorise a call, how to bound cost, how to prevent prompt injection from reaching a dangerous tool. **Those remain entirely your problem**, and an interviewer asking Q608 ("what problem does MCP solve") is often checking whether you'll overclaim.

---

## 300. What is an MCP tool?

**Definition.** A capability exposed by an MCP server, described by a name, a human-readable description, and a JSON Schema for its inputs — the same shape as a native tool definition (Q283), but discoverable over the protocol.

```json
{
  "name": "query_policies",
  "description": "Search insurance policy documents by keyword and type.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {"type": "string"},
      "policy_type": {"type": "string", "enum": ["life", "health", "motor"]}
    },
    "required": ["query"]
  }
}
```

**How it reaches the model.** The client calls `list_tools`, translates the MCP definitions into the provider's tool format, and passes them in the request. The model's tool-use response is translated back into a `call_tool` invocation. **The model has no idea MCP exists** — it sees ordinary tool definitions. MCP is a client-side concern.

**MCP also defines two things beyond tools**, worth mentioning because they're often overlooked:
- **Resources** — readable data identified by URI, for context rather than action. Cheaper than a tool call for static content.
- **Prompts** — reusable templates a server can offer.

**The engineering caution:** an MCP server you didn't write is untrusted code exposing untrusted tool descriptions into your model's context. A malicious or compromised server can inject instructions via a tool description. Treat third-party MCP servers with the same suspicion as any third-party dependency with network access — allowlist them, review their schemas, and never grant them privileged context.

---

## 301. Why standardize tool interfaces?

**The engineering reasons:**
1. **Reuse** — write once, use from every client (Q299).
2. **Independent evolution** — the server's implementation can change behind a stable contract.
3. **Composability** — mix tools from multiple servers in one agent without integration work.
4. **Ecosystem** — shared servers for common systems (databases, filesystems, issue trackers) that you don't write or maintain.
5. **Testability** — a standard interface can be mocked and contract-tested uniformly.

**The deeper reason, and the better answer:** it separates *capability* from *orchestration*. The team that owns the payments system owns the payments MCP server and knows what operations are safe to expose. The team building the agent owns reasoning, cost control, and UX. Neither needs to understand the other's internals. **That's the same argument as any API boundary**, and framing it that way shows you see MCP as ordinary software architecture rather than an AI novelty.

**The counter-argument to acknowledge.** Standardisation costs flexibility. A native tool definition can be tuned precisely for one model's quirks; an MCP tool is generic. For a small number of critical tools, hand-written definitions with model-specific descriptions may perform measurably better on selection accuracy. **Standardise the long tail; hand-tune the tools that matter.**

---

# L2 — Engineering

## 302. Explain your 36–40-turn workflow.

> **Substitute your real system here.** The structure below is the shape a strong answer takes; the specifics must be yours.

**The structure to follow — requirements → why an agent → the loop → controls → what breaks:**

**1. What it does and why it needs to be an agent.** State the task, then justify the loop: *"The number and order of steps depends on what the earlier steps find, so a fixed pipeline can't express it."* If you can't defend that sentence, an interviewer will correctly conclude it should be a workflow (Q597).

**2. The zones.** Describe the architecture as *LLM at the perimeter, deterministic core in the middle*:
- **Zone 1 (LLM)** — parse unstructured input into typed objects
- **Zone 2 (no LLM)** — deterministic logic: scoring, ranking, arithmetic, business rules
- **Zone 3 (LLM)** — generate the human-facing output

**This is the strongest thing you can say in this answer.** It shows you know where a model belongs and where it doesn't. Anything involving money, ordering, or correctness lives in Zone 2, where it's testable and deterministic.

**3. The loop mechanics.** Turn budget of 40, why that number (measured p95 turns × margin), what tools exist, and what terminates it.

**4. Durability.** Every turn persisted to `run_steps` before the next begins. Lease + heartbeat. Resume from turn N (Q317).

**5. Controls.** Spend cap per run, per-tenant budget, repeated-call detection, tool authorization at the executor.

**6. What actually goes wrong.** Have two real failures ready with what you changed. This is what makes the answer credible — anyone can describe an architecture; only someone who built it has scars.

**The number to bring:** turns per run (p50/p95), cost per run, and success rate. An agent described without those numbers reads as a prototype.

---

## 303. Why persist state between turns?

**Because the process will die, and without persisted state the entire run is lost.**

**The specific failures this survives:** worker OOM kill, Kubernetes node preemption, rolling deploy, SIGKILL, network partition, provider timeout cascading into a crash. For a run lasting 10–30 minutes, **a deploy during the run is normal, not exceptional** (Q261).

**What must be persisted per turn:**
```sql
CREATE TABLE run_steps (
  run_id UUID NOT NULL,
  seq INT NOT NULL,
  kind TEXT NOT NULL,            -- 'model' | 'tool_call' | 'tool_result'
  payload JSONB NOT NULL,
  input_tokens INT, output_tokens INT, cost_cents INT,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (run_id, seq)
);
```

**The economic argument, which is the one that lands:** a 40-turn run that dies at turn 38 and restarts from zero costs you the full LLM bill twice. With per-turn persistence it costs two turns. **For an expensive agent, incremental persistence pays for itself on the first crash.**

**The secondary benefits:**
- **Auditability** — you can reconstruct exactly what the model saw and did (Q327)
- **Replay** for debugging (Q328)
- **Progress events** for the UI come free from the same table
- **Cost attribution** per turn, which is how you find the expensive step

**The cost:** one database write per turn. For a 40-turn run that's 40 writes — trivial next to the LLM spend it protects.

**The rule from Document 05 restated:** assume the worker can vanish between any two instructions. Anything that must survive that must already be committed.

---

## 304. Why validate every output?

Because the model is an untrusted input source (Q280), and in an agent the consequences compound.

**In a chatbot, an invalid output is a bad answer. In an agent, an invalid output is a bad *action*, and the next turn is conditioned on it.** An unvalidated error at turn 5 propagates through 35 subsequent turns, each building on a false premise. By the time it surfaces, you've paid for the whole run and the state is incoherent.

**The three validation levels** (Q280):
1. **Schema** — Pydantic on tool arguments and structured outputs
2. **Semantic** — does the referenced ID exist? Is it in this tenant? Is the amount plausible?
3. **Grounding** — for RAG steps, is every claim supported by the retrieved context?

**Agent-specific additions:**
- **Validate the tool name against an explicit registry** (Q288) — never dynamic dispatch
- **Validate that arguments don't include security-scoped fields** — `tenant_id` comes from the session, and if the model supplied one, that's a signal worth logging
- **Validate the state transition** the action implies is legal from the current state
- **Bound the tool result** before it enters context — a 50,000-token result blows your budget and pushes earlier context out

**On validation failure:** feed the specific error back to the model, bounded to 2–3 repair attempts, then terminate. Models repair their own output well when told exactly what was wrong. But **a systematically malformed output will fail identically forever** — unbounded repair is a money-burning loop (Q320).

---

## 305. Why not let the model write DB directly?

Full argument at Q281. The agent-specific intensification:

**In an agent, the model's output is not reviewed by a human before it acts.** A chatbot's wrong answer is read by a person who can disregard it. An agent's tool call executes immediately, forty times per run, unattended.

**And the attack surface is larger.** Every tool result enters context. If any tool reads content from outside your trust boundary — a retrieved document, a web page, an email, a user-uploaded file — that content can carry instructions (Q522, Q523). If the model can write to the database directly, **a malicious PDF has write access to your database.**

**The architecture:**
```
Model proposes → schema validation → business-rule validation
               → authorization against the USER's permissions
               → deterministic code performs the write
               → audit log records proposal, decision, and effect
```

**The deterministic core is the point.** Anything involving money, ordering, ranking, or state transitions should be Zone 2 code — testable, reviewable, and identical every run. The model's job is to decide *what to attempt*; your code decides *what actually happens*.

**Never expose an `execute_sql` tool** (Q527), even read-only. It's an injection surface, a data-exfiltration path, and it defeats every constraint you carefully placed on the typed tools.

---

## 306. How prevent infinite loops?

**Multiple independent bounds, because each catches a different failure:**

**1. Max turns.** The blunt instrument. Set from measured p95 × margin. Terminal state: `max_turns_exceeded`.

**2. Spend cap** — per run and per tenant, checked *between turns*. Turn caps don't catch one enormous call.

**3. Wall-clock timeout.** Catches runs that are cheap but stuck on a slow tool.

**4. Repeated-action detection — the most useful signal:**
```python
sig = (call.name, hash(canonical_json(call.args)))
state.action_counts[sig] += 1
if state.action_counts[sig] >= 2:
    result = f"Identical to step {first_seen}. That returned: {cached}. Try a different approach."
if state.action_counts[sig] >= 3:
    return terminate(state, "stuck")
```
Feeding the repetition back to the model is far more effective than silently returning the same result again (Q322).

**5. No-progress detection.** If N consecutive turns produce no new information — no new records touched, no state change — the model is spinning.

**6. Alternation detection.** A → B → A → B is a loop even though no single action repeats consecutively.

**The design point:** these are *independent* bounds and each should map to its own terminal state. Lumping them into `failed` means your metrics can't tell you whether agents are running out of turns, running out of money, or getting stuck — which are three different bugs with three different fixes.

**And the root cause is usually upstream:** a tool whose result format the model can't parse, a tool description promising something it doesn't deliver, or a goal the available tools genuinely cannot achieve. Loops are a symptom; instrument them, then fix the cause (Q287).

---

## 307. Tool errors?

Covered mechanically at Q285. The agent-loop specifics:

**Return errors as tool results, not exceptions**, so the model can adapt. Aborting a 30-turn run because one tool call had a bad date format wastes everything spent so far.

**Categorise, and let the category drive behaviour:**

| Category | Model-visible message | Loop behaviour |
|---|---|---|
| Invalid arguments | The specific violation + expected format | Model retries, capped at 2–3 |
| Not found | "No record for X — verify the ID" | Model tries a different ID or gives up |
| Transient upstream | "Temporarily unavailable" | Executor already retried; model may try later |
| Permanently unavailable | "This capability is unavailable" | Model routes around it |
| Unauthorized | **Generic denial only** | Log the real reason; never reveal scope details |
| Rate limited | "Rate limited, wait before retrying" | Executor backs off |

**The authorization case is the security-relevant one.** Never tell the model *why* it was denied — "you lack permission for tenant X" is information disclosure and an invitation to probe. Generic denial to the model; full detail to the audit log (Q289).

**Bound the error text.** A stack trace or a 10,000-token upstream error body consumes context and pushes out useful history. Truncate and summarise.

**Track tool error rates per tool.** A rising rate means the tool is broken *or* its description is misleading the model into wrong arguments. Both are fixable; neither is visible without the metric.

---

## 308. Tool retries?

**Retry at two different layers, for two different reasons — and confusing them causes problems.**

**Layer 1 — the executor retries transient failures transparently.** The model never sees it.
```python
async def execute_with_retry(tool, args, ctx, attempts=3):
    for i in range(attempts):
        try:
            return await tool.run(args, ctx)
        except (TimeoutError, ConnectionError, RateLimited) as e:
            if i == attempts - 1:
                return error_result("Service unavailable after retries.")
            await asyncio.sleep(random.uniform(0, 0.5 * 2**i))   # jitter
```
Appropriate for idempotent reads. Saves a full model turn on a transient blip.

**Layer 2 — the model retries after a semantic failure.** Wrong arguments, no results, needs a different approach. This costs a turn and is bounded by the turn cap and repeated-action detection.

**The critical rule: never auto-retry a non-idempotent tool after an ambiguous failure.** A timed-out `create_payment` may have succeeded (Q286). Retrying creates a second payment. Either make the tool idempotent with a key derived from `(run_id, seq)`, or return the ambiguity honestly to the model and let it check state with a read tool.

**Never retry these:** validation errors (deterministic — will fail identically), authorization failures, not-found for a well-formed ID, and content-policy refusals. Each will produce the same result every time while costing money (Q220).

**The cost angle specific to agents:** a retry at the model layer resends the entire context. Three model-layer retries on turn 30 is three full-context calls. Executor-layer retries are far cheaper — prefer them where the failure is genuinely transient.

---

## 309. Model failure vs tool failure?

**A distinction worth being precise about, because they need opposite responses.**

**Model failure** — the model itself produced something wrong or the API call failed:
- Malformed structured output (Q320)
- Invented a tool that doesn't exist (Q288)
- Provider 429, 500, or timeout
- Content filter refusal
- Hit `max_tokens` mid-JSON
- Chose a semantically wrong tool for the goal

**Tool failure** — your code or a dependency failed:
- Upstream service down
- Database error
- Timeout
- Validation rejected the arguments
- Authorization denied

**Why the distinction matters:**

| | Model failure | Tool failure |
|---|---|---|
| Retry the *same* call? | Sometimes (resample at low temp) | Only if transient and idempotent |
| Feed back to the model? | Only the parse error | Yes, as a tool result |
| Fallback available? | Different model / provider | Different tool / degrade |
| Indicates | Prompt or schema problem | Infrastructure or integration problem |
| Metric | Model error rate | Tool error rate, per tool |

**Track them separately.** Conflating them into one "agent error rate" makes the number useless — a spike could be a provider outage, a bad prompt deploy, or a broken database. Three causes, three responses, and you can't tell which from a single metric.

**Provider failures need their own handling:** circuit breaker per provider, fallback to a secondary model, and a clear terminal state when both are unavailable. A 429 from your model provider is not the same as your agent failing, and your alerting should distinguish them.

---

## 310. Tool idempotency?

**Definition.** A tool that can be called multiple times with the same arguments and produce the same effect as calling it once.

**Why it's essential in an agent specifically.** Duplicate calls come from everywhere: the model repeating itself (Q287), executor retries, run resumption after a crash re-executing an uncommitted step, and manual replay. **In a 40-turn loop with resumption, duplicate execution is routine, not exceptional.**

**Read tools are naturally idempotent.** The problem is write tools.

**The mechanism — derive the key from the run position:**
```python
idempotency_key = f"{run_id}:{step_seq}:{tool_name}"
```
This is stable across retries *and* across resumption, because turn `seq` is deterministic from the persisted state. A resumed run re-executing step 23 produces the same key as the original attempt, so the backend deduplicates.

```sql
INSERT INTO tool_executions (idempotency_key, run_id, seq, tool, result)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (idempotency_key) DO NOTHING;
```
Zero rows inserted → already executed → return the stored result without re-running.

**The essential detail** (same as Q234): the idempotency record and the tool's effect must commit in **one transaction**. Recording first in a separate transaction means a crash loses the effect while marking it done.

**For external APIs you don't control:** pass your key through as their idempotency key. Every serious payment API supports this precisely because of this problem.

**What can't be made idempotent:** sending an email, posting to Slack. Dedupe *before* the call and accept a small residual risk — or require human approval for those tools (Q335).

---

## 311. Tool authorization?

Full mechanics at Q289. The framing that matters most for agents:

**The model is not a principal.** It has no identity, no permissions, and no accountability. Every tool call is authorised against the **user** who initiated the run, at execution time, in your code.

**Why this cannot live in the prompt.** "Only call `delete_record` for admins" in a system prompt is a suggestion, not a control. Prompt injection defeats it (Q522). The system prompt is not a security boundary (Q268).

**The three enforcement points:**

1. **Tool availability.** Filter the tool list by role before the model ever sees it. A non-admin's context contains no admin tools — the model cannot call what it doesn't know exists. Cheapest and most effective.

2. **Per-call scope check in the executor**, before running anything.

3. **Server-side context injection.** `tenant_id`, `user_id`, and every security-scoped field come from the authenticated session and are *never* accepted from the model's arguments. **This eliminates the vulnerability class rather than defending against it** — the model cannot specify a tenant because the parameter doesn't exist in the schema (Q325).

**The audit requirement:** every proposed call, the decision, the arguments (redacted), and the result, tied to run ID and user ID. When something goes wrong with an agent, "what did it try to do and what did we let it do" is the first question, and it needs to be a query.

**The MCP caveat worth stating** (Q298): MCP standardises the interface, not the authorization. A third-party MCP server exposes tools; deciding whether *this user* may call them is entirely your client's job.

---

## 312. Dangerous tool protection?

**Classify tools by blast radius and apply controls proportionally.**

| Tier | Examples | Controls |
|---|---|---|
| **Read** | search, get, list | Scope check, bounded results |
| **Reversible write** | create draft, add tag | Scope check, idempotency, audit |
| **Irreversible write** | delete, send email, charge card, external post | All the above **plus human approval** |
| **Bulk** | anything affecting N > threshold records | Approval + explicit count confirmation |

**The controls for the dangerous tier:**

1. **Human-in-the-loop approval** (Q335) — the run pauses in a durable `awaiting_approval` state, showing the human the exact operation, its arguments, and the count of affected records.
2. **Confirmation of scale.** `delete_records(filter=...)` should first return "this matches 4,312 records" and require a second, explicit call with the expected count. Bulk destruction from an ambiguous filter is a classic agent incident.
3. **Rate limits per tool per run and per tenant.** No run should send 500 emails.
4. **Dry-run mode** — the tool reports what it *would* do; approval executes it.
5. **Reversibility by design.** Soft delete over hard delete; scheduled send with a cancellation window over immediate send. **Making an action reversible is better than gating it.**
6. **Never expose arbitrary execution** — no `execute_sql`, no shell, no eval (Q527).

**The design principle:** the safest dangerous tool is one that doesn't exist. Before adding a destructive capability, ask whether the agent needs to *do* it or merely to *propose* it. An agent that drafts a deletion for a human to execute has most of the value and almost none of the risk.

---

## 313. Why Redis workers?

> Substitute your actual reasoning; the structure below is the defensible version.

**The argument:** the agent run is long (minutes to tens of minutes), so it cannot happen in an HTTP request (Q76). It needs a durable queue and a worker pool that scales independently of the API tier (Q100).

**Why Redis Streams specifically over the alternatives:**
- **Over Pub/Sub** — Streams give at-least-once delivery, acknowledgement, and pending-entry recovery. Pub/Sub loses messages when no subscriber is connected, which for a job queue is disqualifying (Q213).
- **Over Kafka** — moderate volume, hours of retention sufficient, and Redis was already in the stack. Kafka's operational cost isn't justified until you hit a measured limit (Q215).
- **Over PostgreSQL `SKIP LOCKED`** — this is the interesting one, and the honest answer is that `SKIP LOCKED` is often *better*: the claim and the work commit in one transaction, so there's no dual-write gap at all. If you chose Redis, the justification is usually throughput or existing infrastructure, not correctness.

**The critical caveat to state unprompted, because it's what a good interviewer probes:** Redis replication is asynchronous, so an acknowledged `XADD` can be lost on failover (Q240). **Therefore the durable record is a PostgreSQL `runs` row, written before enqueueing; the stream message is only a notification.** If the stream loses it, a reaper finds the orphaned row and requeues. Saying this pre-empts Q601 entirely.

---

## 314. Why run ID?

**It's the correlation key that makes everything else possible.**

**What it enables:**
1. **Client polling and status** — `GET /runs/{id}` without holding a connection (Q77)
2. **Idempotency** — a retried submission with the same client key returns the existing run rather than starting a second expensive one
3. **Resumption** — a new worker loads state by run ID (Q317)
4. **Step keying** — `run_steps` primary key is `(run_id, seq)`
5. **Tool idempotency keys** derived from `(run_id, seq)` (Q310)
6. **Audit and replay** — every action traceable to a run (Q327)
7. **Cost attribution** — spend per run, per tenant
8. **Log correlation** — every log line carries it, so one grep reconstructs the whole run
9. **SSE reconnection** — the client resumes the event stream by run ID

**Implementation details worth mentioning:** generate it server-side (never trust a client ID), use UUIDv7 for time-ordered index locality (Q101), and return it in the 202 response along with the status and events URLs.

**The point that ties it together:** the run ID is what turns a fire-and-forget background job into an *observable, resumable, auditable* object. Without it you have a process; with it you have a record.

---

## 315. Why SSE?

Full comparison at Q79. The agent-specific reasoning:

**Progress is unidirectional** — the server pushes turn-by-turn updates, the client just watches. WebSocket's return channel is unused complexity.

**It's plain HTTP**, so auth headers, proxies, load balancers, and HTTP/2 all work unchanged. WebSocket needs `Upgrade` support end-to-end and is blocked by some corporate proxies.

**Automatic reconnection with `Last-Event-ID`.** For a 20-minute agent run, the client *will* lose connectivity — mobile network change, laptop sleep, wifi handoff. `EventSource` reconnects automatically and sends the last event ID, and you replay from `run_steps` where `seq > last_id`. **You get resumable progress essentially for free**, which is exactly what a long run needs.

**The architectural point that matters most** (Q89): don't stream directly from the model to the client. The worker writes events to `run_steps` and Redis; the SSE endpoint reads from there. This fully decouples client connectivity from run execution — the client disconnecting doesn't stop the run, and an API deploy doesn't kill it. Streaming model output straight through couples them, and then every deploy kills every in-flight run.

**The two operational gotchas:** send periodic keepalive comments (`: ping\n\n`) or intermediaries close the idle connection, and set `X-Accel-Buffering: no` or nginx buffers the whole stream and delivers it at the end — which looks precisely like the feature being broken.

---

## 316. When WebSocket?

**When the client genuinely needs to send data mid-run**, not just receive it.

**The cases:**
- **Interactive agents** where the user steers mid-execution — "no, search the other database instead"
- **Inline approval** for dangerous tools, where the user approves without a separate HTTP call (Q335)
- **Voice or conversational interfaces** with continuous bidirectional audio
- **Collaborative sessions** — multiple users watching and directing one run
- **Very high message frequency** where SSE's per-event overhead matters

**What you take on by choosing it:**
- Reconnection and resumption logic you write yourself (SSE gives it free)
- Heartbeat/ping-pong to detect dead connections
- Connection state per worker, so a multi-instance deployment needs Redis Pub/Sub fanout (Q82)
- Sticky sessions or a shared connection registry
- Proxy compatibility issues in some corporate environments
- Auth on a long-lived connection — token expiry mid-session needs handling

**The pragmatic recommendation:** start with SSE plus a normal `POST /runs/{id}/input` endpoint for the rare cases where the client needs to send something. That gives you bidirectionality without a persistent bidirectional connection, and it's dramatically simpler. Move to WebSocket only when the interaction is genuinely continuous.

---

## 317. How resume failed agent run?

**This is the highest-value question in the section**, because it's where every mechanism converges.

**The mechanism:**

1. **Detection.** The lease expired and heartbeats stopped (Q201). A reaper query finds it:
```sql
SELECT id FROM runs
WHERE status='running' AND lease_expires_at < now() AND attempt < $max;
```

2. **Reclaim.** A new worker claims it atomically:
```sql
UPDATE runs SET worker_id=$1, lease_expires_at=now()+interval '2 min', attempt=attempt+1
WHERE id=$2 AND status='running' AND lease_expires_at < now()
RETURNING *;
```
Zero rows means another worker got there first.

3. **Rebuild context from persisted steps:**
```python
steps = await fetch("SELECT * FROM run_steps WHERE run_id=$1 ORDER BY seq", run_id)
messages = rebuild_messages(steps)      # deterministic reconstruction
next_seq = steps[-1].seq + 1
```

4. **Resume the loop** from `next_seq`, with the accumulated spend already counted.

**The three details that make it actually work:**

- **Persist before acting** (Q303). If you act then persist, a crash between them loses the record of an action that happened — and resumption re-executes it.
- **Tool idempotency keyed on `(run_id, seq)`** (Q310), so the *last* step — which may have executed but not been recorded — is safe to re-run.
- **The rebuild must be deterministic.** Same steps → same messages, every time. If context reconstruction is lossy or order-dependent, a resumed run diverges from the original and behaves differently, which is nearly impossible to debug.

**When NOT to resume:** if the failure is terminal (invalid input, content-policy refusal, a tool permanently gone), retrying burns money to fail identically. Classify before requeueing (Q199).

**The number that justifies all of it:** a 40-turn run failing at turn 38 costs two turns to resume instead of forty to restart.

---

## 318. Why typed MCP tools?

Q284 covers typing generally. The MCP-specific additions:

1. **The contract survives the boundary.** The server owns the schema; the client receives it over the protocol with types intact. There's no separate copy of the schema in the client that can drift from the implementation — which is the most insidious integration bug, because the model behaves correctly according to a schema the server doesn't honour.

2. **Discovery is meaningful.** `list_tools` returns machine-readable schemas, so a client can validate arguments *before* invoking, generate UI, or reason about capabilities without hardcoding.

3. **Version negotiation.** Typed schemas make it possible to detect incompatibility explicitly rather than failing at runtime with a confusing error.

4. **Validation happens on both sides.** The client validates the model's arguments before sending; the server validates again on receipt. Defence in depth across a trust boundary you don't fully control.

5. **Constrained types limit the injection blast radius.** A tool whose `limit` is `integer, max 20` cannot be coerced by prompt injection into an unbounded query, regardless of what the model was persuaded to attempt.

**The caution that belongs in this answer:** typed schemas from a *third-party* MCP server are untrusted input. The `description` field goes into your model's context verbatim — a malicious server can inject instructions through it. Allowlist servers, review their schemas, and treat them as you would any dependency with network access.

---

## 319. What makes a good tool error contract?

**Six properties, and being able to enumerate them is the answer:**

**1. Actionable.** Say what was wrong *and* what would be right.
```
Bad:  "Invalid input"
Good: "policy_type must be one of: life, health, motor. Received: 'Life Insurance'."
```

**2. Categorised.** The model needs to know whether to adapt, retry, or give up.
```json
{"error": {"category": "invalid_arguments", "retryable": true, "message": "..."}}
```

**3. Bounded.** Never dump a stack trace or a 10,000-token upstream body into context. Truncate and summarise — every error token displaces useful history and is resent on every subsequent turn.

**4. Explicit about retry.** "Do not retry this tool" prevents the model from looping (Q322). Models take this instruction well; without it they often retry indefinitely.

**5. Safe.** No internal paths, no SQL, no stack traces, no other tenants' data, and — critically — no explanation of *why* authorization failed (Q307).

**6. Consistent in shape.** The same envelope for every tool, so the model learns the pattern once. Inconsistent error formats mean the model interprets each one afresh, badly.

**The one to add for agents specifically: suggest the alternative.**
```
"No results for that policy number. It may be formatted differently —
 try search_policies with the customer name instead."
```
This measurably reduces wasted turns, because the model's next action is guided rather than guessed. **The error message is a prompt**, and it deserves the same iteration as your system prompt.

---

# L3 — Production failure

## 320. Malformed JSON on turn 17?

**First, diagnose the cause — the fixes differ:**

| Cause | Signal | Fix |
|---|---|---|
| Hit `max_tokens` mid-generation | `stop_reason == "max_tokens"` | Raise the cap; check the stop reason *always* |
| Model wrapped it in prose or markdown fences | Parseable after stripping | Strip ```json fences before parsing |
| Genuinely invalid structure | Parse error after cleanup | Repair loop |
| Schema mismatch (valid JSON, wrong shape) | Pydantic ValidationError | Repair loop with the specific field errors |
| High temperature | Intermittent | Lower to 0 for structured output |

**The stop-reason check is the one people miss.** A truncated response is *always* invalid JSON, and it looks like a model failure when it's a configuration failure.

**The repair loop:**
```python
for attempt in range(3):
    try:
        return Model.model_validate_json(clean(raw))
    except ValidationError as e:
        raw = await model.call(messages + [
            {"role": "assistant", "content": raw},
            {"role": "user", "content":
             f"That failed validation: {e.errors()}. Return only valid JSON matching the schema."}
        ])
raise TerminalError("could not obtain valid output after 3 attempts")
```
Feeding the *specific* validation errors back works well — models repair their own output reliably when told exactly what was wrong. Generic "that was invalid" does not.

**Bound it at 2–3 attempts.** A systematically malformed output fails identically forever, and each attempt resends the full turn-17 context — which by then is large (Q296).

**The structural prevention:** use constrained decoding or strict structured output, where schema violations are impossible by construction (Q270). Prompting for JSON is the weakest of the three mechanisms and shouldn't be the production answer.

**The cost framing:** failing at turn 17 of 40 means you've already spent 17 turns. Repair is worth 2–3 attempts; a fourth is throwing money at a deterministic failure.

---

## 321. Tool succeeds, worker dies before persistence?

**This is Q41 and Q246 in agent form, and it's the scenario the whole persistence design exists for.**

**What happened:** the tool executed with real effect — a record created, an email sent, a payment made — and the crash occurred before `run_steps` recorded it. On resumption, the rebuilt context has no memory of it, so the model does it again.

**The mitigations, layered:**

**1. Tool idempotency keyed on `(run_id, seq)`** (Q310) — the primary defence. The re-execution produces the same key, the backend's unique constraint rejects it, and the stored result is returned. **The effect happens once even though the tool was called twice.**

**2. Order of operations: persist the *intent* before executing.**
```python
await persist_step(run_id, seq, "tool_call", call)     # intent recorded
result = await execute_tool(call, ctx)                  # ← crash window
await persist_step(run_id, seq, "tool_result", result)
```
Now a resumed run sees the intent at seq N with no result, and knows to check: query the tool's backend by idempotency key to discover whether it completed. That converts "unknown" into "resolvable."

**3. For tools that genuinely cannot be idempotent** (an email), require human approval (Q335) or accept a small duplicate risk and dedupe at the send layer.

**The honest framing** — same as Q246: **you cannot make a tool's external effect and your database write atomic.** You can only shrink the window and make the ambiguity resolvable. Idempotency keys are how you resolve it; recording intent first is how you know to look.

**The window that remains:** crash between the tool's backend committing and returning its response. Unavoidable, and handled by the idempotency check on retry.

---

## 322. Model repeats tool five times?

**A loop symptom, and the response is graduated rather than binary.**

**Detect:**
```python
sig = (call.name, hash(canonical_json(call.args)))
count = state.action_counts[sig] = state.action_counts[sig] + 1
```

**Respond by count:**
- **2nd** — return the cached result *plus* an explicit note: `"Identical to step 4, which returned no results. Try different search terms or a different tool."` **This is the intervention that actually works** — silently returning the same result again teaches the model nothing.
- **3rd** — stronger: `"You have now repeated this three times with the same result. This approach will not succeed. Either try a fundamentally different approach or tell the user this cannot be answered with available tools."`
- **4th** — terminate with `status='stuck'`.

**Also detect alternation** — A→B→A→B is a loop even though no action repeats consecutively. Hash the last N actions and look for cycles.

**Cache the results** so repeats cost nothing but a model turn — no duplicate side effects, no duplicate upstream calls.

**The root causes, and this is where the real fix lives:**
1. **The tool result is unparseable to the model** — an empty array with no explanation reads as "something went wrong" rather than "no matches." Return `{"results": [], "message": "No policies matched. Try a broader query."}`
2. **The tool description over-promises** relative to what it returns.
3. **The goal is unachievable** with the available tools, and the model doesn't know it's allowed to say so. **Explicitly authorise giving up in the system prompt** — this alone eliminates a large fraction of loops.

**Track repeated-call rate per tool.** It's one of the most actionable agent metrics and almost nobody instruments it.

---

## 323. Agent loops forever?

Prevention is Q306; this asks about the incident.

**Why it happens despite bounds:** the bounds weren't set, were set too high, or the loop is *between* checkpoints — a single tool call hanging indefinitely with no timeout.

**Immediate response:**
1. **Cancel the run** — set `status='cancelling'`; the worker checks between turns and exits.
2. **If it's stuck inside a call**, cancellation won't fire until that call returns. Kill the worker; the lease expires and the reaper handles it (Q317).
3. **Check the spend.** A runaway agent burns money continuously — this is the urgent part.

**Why cancellation is cooperative and must be explained honestly:** you cannot interrupt an in-flight LLM call. If a model call takes 90 seconds, cancellation takes effect up to 90 seconds later. **State this in the API contract** so nobody expects instant termination.

**The defences that should have caught it:**
- Turn cap, spend cap, wall-clock cap — all three, since each catches a different shape
- Per-tool timeouts, so no single call hangs the run
- Repeated-action detection (Q322)
- No-progress detection

**The systemic fix after the incident:**
1. **Alert on runs exceeding p99 turns**, not just on the hard cap. The cap is the last line; the alert is early warning.
2. **A global kill switch** — a flag that halts all agent execution, checked between turns. Worth building before you need it at 3 a.m.
3. **Per-tenant spend circuit breaker** that stops accepting new runs when daily budget is exceeded.

**The framing:** an infinite loop in ordinary software wastes CPU. An infinite loop in an agent **spends money at a measurable rate per minute**, so the bounds are a financial control, not just a correctness one.

---

## 324. Tool becomes slow?

**The impact is amplified by the loop.** A tool that goes from 200ms to 20 seconds, called three times per run across 40 turns, adds an hour to every run. Worker capacity collapses; the queue backs up; SSE clients time out.

**Immediate handling:**
1. **Timeout it** — every tool call bounded, budgeted below the run's remaining time.
2. **Circuit break** after N slow/failed calls: fail fast and tell the model the capability is unavailable, so it routes around it (Q236). **This is the mechanism that keeps the rest of the run working.**
3. **Degrade** — return cached or partial results with a note, rather than failing.

**Detection before users notice:** per-tool latency percentiles, and alert on p95 rising relative to baseline. Tool latency should be a first-class metric per tool, exactly like an HTTP endpoint's.

**The structural fix for tools that are legitimately slow:** make them asynchronous. The tool returns a job ID immediately; a separate `check_status` tool polls. The agent continues doing other work rather than blocking on one operation. This also keeps turns short, which keeps resumption granular.

**Capacity implications:** if a tool's latency doubles, your effective worker throughput halves. Autoscaling on queue depth will add workers, which increases concurrent load on the *already-slow* tool — potentially making it worse. **Rate-limit calls to the slow dependency independently of worker count**, or you scale yourself into a cascading failure (Q204).

---

## 325. Unauthorized tool arguments?

**The scenario:** the model produces `{"tenant_id": "other-company", "policy_id": "..."}` — either because it hallucinated, or because a prompt injection told it to.

**The correct answer is that this should be impossible by construction, not caught by a check.**

**Server-side context injection** (Q289): security-scoped fields are **not in the tool schema at all**. The model cannot specify a tenant because there is no parameter for it.
```python
class SearchPoliciesInput(BaseModel):
    query: str
    policy_type: Literal["life","health","motor"] | None = None
    # NO tenant_id — injected server-side

async def run(self, args: SearchPoliciesInput, ctx: UserContext):
    return await repo.search(args.query, args.policy_type,
                             tenant_id=ctx.tenant_id)   # from the session
```
**This eliminates the vulnerability class**, rather than defending against instances of it.

**If the model supplies an unexpected field anyway** (`extra="forbid"` on the model catches it):
1. **Reject the call.**
2. **Return a generic denial to the model** — never "you cannot access tenant X," which is information disclosure and an invitation to probe (Q307).
3. **Log it as a security event** with full detail, the run ID, the user, and the preceding context.
4. **Alert.** A model attempting cross-tenant access is either a serious bug or an active injection attempt. Either warrants investigation.

**Defence in depth:** PostgreSQL Row-Level Security as the backstop (Q258), so even a code path that forgets the filter returns zero rows rather than another tenant's data.

**The test that proves it:** a CI suite that attempts cross-tenant access through every tool. Claiming isolation and testing isolation are different things.

---

## 326. Sensitive patient data exposure?

**The threat surfaces, enumerated:**

1. **Into the model's context** — retrieved documents, tool results, conversation history all go to a third-party provider
2. **Into logs and traces** — the default behaviour of most observability tooling is to log payloads
3. **Into the model's output** — summarising a record and including identifiers that shouldn't be surfaced
4. **Across tenants** — a retrieval or tool call returning another patient's data (Q325)
5. **Via prompt injection** — a malicious document instructing the model to include other records
6. **Into provider training data** — depending on the contract and endpoint

**The controls:**

**1. Minimise what enters context.** Retrieve the specific fields needed, not whole records. An agent answering "when is my next appointment" needs a date, not a full medical history.

**2. Redact or tokenise before the model call.** Replace identifiers with tokens (`PATIENT_A`), map back after generation. The model reasons over structure without ever seeing the identifier.

**3. Never log payloads by default.** Log field *names* and shapes, not values. Hash identifiers for correlation. This must be the default, not an opt-in — one debug log line added during an incident is how leaks happen.

**4. Provider contracts.** Zero-retention endpoints, a BAA where applicable, explicit no-training terms. **Verify which endpoint you're actually calling** — many providers have different retention policies per tier.

**5. Output filtering.** Scan generated text for identifier patterns before returning it, especially in RAG where the model may echo context verbatim.

**6. Tenant/patient isolation** enforced at the database with RLS, not in application logic alone.

**7. Access audit** — who read what, when, via which run. For health data this is a regulatory requirement, and the agent's tool calls *are* accesses.

**8. Consider a self-hosted model** for the most sensitive processing. This is where vLLM and on-prem serving earn their operational cost (Q457) — the data never leaves your infrastructure.

**The framing:** an agent is a system that reads sensitive data and sends it to a third party by design. **Every control above exists because that's the default behaviour**, and the engineering work is deciding, per field, whether it needs to be there at all.

---

## 327. How audit an agent run?

**Everything is already there if you persisted per turn** (Q303) — the audit trail falls out of the durability design rather than being a separate system. That's the answer worth giving.

**What a complete audit record contains:**

```sql
-- per run
runs: id, tenant_id, user_id, status, input, result,
      total_cost_cents, model, prompt_version, tools_version,
      created_at, completed_at, attempt

-- per turn
run_steps: run_id, seq, kind, payload, input_tokens, output_tokens,
           cost_cents, latency_ms, created_at

-- per tool execution
tool_executions: run_id, seq, tool_name, arguments_redacted,
                 authorized (bool), denial_reason, result_summary,
                 idempotency_key, duration_ms
```

**The four questions an audit must answer:**
1. **What did the model see?** The exact messages at each turn — including retrieved context, which is where injection attacks live.
2. **What did it propose?** Every tool call, including ones that were denied.
3. **What did we allow?** The authorization decision and its reason.
4. **What actually changed?** Links from tool executions to the affected records.

**The versioning requirement people forget:** record the **prompt version, model version, and tool schema version** on every run. Without them, a run from three weeks ago is uninterpretable — you can't tell whether behaviour changed because of a prompt edit, a model upgrade, or a data change (Q329).

**Redaction discipline:** arguments logged with sensitive fields redacted, identifiers hashed for correlation (Q326).

**Retention:** for regulated data, typically years. Partition `run_steps` by month; it will be your largest table by a wide margin.

**The property that makes this genuinely valuable:** an agent's behaviour is not reproducible from its code. The code is the same for every run; the behaviour differs. **The audit trail is the only record of what actually happened**, which makes it more essential here than in deterministic systems, not less.

---

## 328. How replay a run?

**Two distinct meanings — distinguish them, because interviewers use the word loosely.**

**1. Inspection replay (safe, and what you want 95% of the time).** Reconstruct exactly what happened from `run_steps` — every message, every tool call, every result — and display it. No execution, no cost, no side effects. This is your primary debugging tool, and it should be a UI, not a database query someone runs manually.

**2. Re-execution replay (dangerous).** Actually re-run the agent. Necessary for testing prompt changes against real cases, but it will:
- Cost money again
- Produce **different** output (models aren't deterministic even at `temperature=0`, Q265)
- Re-execute tools with real side effects

**For re-execution, you need tool mocking:**
```python
class ReplayToolExecutor:
    """Returns recorded results instead of executing."""
    def __init__(self, steps):
        self.recorded = {(s.seq, s.tool): s.result for s in steps}

    async def execute(self, call, seq, ctx):
        if (seq, call.name) in self.recorded:
            return self.recorded[(seq, call.name)]
        return error_result("Diverged from recorded run — no result available.")
```

**The divergence problem is the interesting part.** As soon as the model makes a different choice than the original run, your recorded tool results no longer apply. You must decide: stop and report divergence (useful — divergence itself is the signal), fall back to live execution (expensive, side effects), or use a fuzzy match on similar calls (fragile).

**Stopping at divergence is usually right.** When testing a prompt change, "the model chose a different tool at turn 6" *is* the finding.

**What replay requires from your design:** deterministic context reconstruction (Q317) and versioned prompts/tools (Q329). Without versioning, you can't distinguish "the prompt change caused this" from "the model changed underneath us."

---

## 329. How version prompts/tools?

**Treat prompts and tool schemas as code, because they are.** They determine behaviour, they break things when changed, and they need review, testing, and rollback.

**The mechanism:**

1. **In the repository**, not a database or an admin UI. Version-controlled, code-reviewed, diffable.
```
prompts/
  agent_system/v3.md
  extraction/v7.md
tools/
  schemas.py          # Pydantic → JSON Schema
```

2. **Content-hash them** so a version identifier is derived, not manually assigned:
```python
PROMPT_VERSION = sha256(system_prompt.encode()).hexdigest()[:12]
```
Manual version numbers drift; hashes cannot.

3. **Record the version on every run** (Q327). This is what makes "did quality drop after Tuesday's deploy?" a query rather than a guess.

4. **Gate changes on evals.** A prompt change is a behaviour change. Run the golden set, compare against the current baseline, and block the merge if key metrics regress (Q433). **A prompt edit deployed without an eval is an untested code change to your most behaviour-critical component.**

5. **Roll out gradually.** Canary the new prompt on a percentage of traffic; compare metrics before full rollout.

6. **Keep old versions loadable** so replay of historical runs uses the prompt that actually ran (Q328).

**Tool schema versioning specifically:** changing a tool's parameters is a breaking change for in-flight runs. A resumed run built its context against the old schema. Either version tools alongside prompts and pin per run, or make schema changes strictly additive with defaults.

**The point to make:** most teams treat prompts as configuration to be tweaked freely. They are the highest-leverage, least-tested part of the system. **Treating them as code is the single biggest maturity difference between a prototype and production.**

---

## 330. How evaluate an agent after code changes?

**Agent evaluation is harder than model evaluation because you must evaluate a *trajectory*, not an output.** Say that first.

**The four layers, and you need all of them:**

**1. Final-output correctness.** Did it reach the right answer? Exact match, structured comparison, or LLM-as-judge with a rubric. Necessary but insufficient — a run can reach the right answer via twenty wasted turns.

**2. Trajectory quality.** Did it take a sensible path?
- **Tool selection accuracy** — did it choose the right tool at each decision point (Q430)?
- **Argument correctness** — were the parameters right (Q431)?
- **Turn efficiency** — turns taken versus the minimum needed
- **Repeated/wasted calls** per run

**3. Operational metrics.** Cost per run, latency p50/p95, success rate, and the distribution of terminal states — `max_turns_exceeded` and `stuck` rates are quality signals, not just error counts.

**4. Safety.** Unauthorized tool attempts, prompt-injection resistance on adversarial cases, refusal behaviour on out-of-scope requests.

**The eval set:**
```python
@dataclass
class AgentTestCase:
    input: str
    expected_output: str | None
    expected_tools: list[str]         # tools that must be called
    forbidden_tools: list[str]        # tools that must NOT be called
    max_turns: int
    mocked_tool_results: dict         # determinism
    fixture_state: dict               # DB state before the run
```

**Mock the tools.** Without mocking, evals are slow, expensive, non-deterministic, and have side effects. With mocking, you get a fast deterministic suite that runs on every PR — but you're then testing the *reasoning*, not the integration, so keep a small live-integration suite too.

**Run it in CI on every prompt, tool, or model change** (Q329), with thresholds that block the merge. And **run N times per case** — agents are non-deterministic, so a single pass tells you very little. Report pass rate across runs, not a binary.

**The honest caveat to state:** trajectory evaluation is genuinely immature as a discipline. There's no equivalent of accuracy for "did it reason well." Most teams use LLM-as-judge on trajectories and accept the noise (Q432). Saying that shows you've engaged with the real state of the field rather than reciting a solved-problem answer.

---

# L4 — System design

## 331. Design an agent platform.

**Requirements:** many tenants, many agent definitions, long runs, durable execution, cost control, tool authorization, observability, safe deployment of prompt changes.

**Architecture:**
```
API ──▶ runs table + outbox ──▶ queue ──▶ Agent workers
                                             │
                            ┌────────────────┼────────────────┐
                       Tool registry    Model gateway    Step store
                       (auth, schemas)  (routing,        (run_steps)
                                         fallback,           │
                                         budget)         SSE reader ──▶ client
```

**The components and why each exists:**

1. **Run service** — creates runs idempotently, enqueues via outbox (Q246), returns 202 with a run ID (Q314).
2. **Agent workers** — execute the loop, persist every turn, heartbeat the lease (Q294, Q317).
3. **Tool registry** — the security boundary. Explicit allowlist, per-tool scopes, typed schemas, server-side context injection (Q289, Q311).
4. **Model gateway** — one place for provider routing, fallback, rate limiting, prompt caching, and cost accounting. Without it, every worker independently reimplements retry and budget logic (Q343 in Doc 11 territory).
5. **Step store** — `run_steps`, which serves durability, resumption, audit, replay, and SSE from one table.
6. **Reaper** — reclaims expired leases, enforces timeouts, dead-letters exhausted runs (Q202).
7. **Eval pipeline** — gates prompt and tool changes in CI (Q330).

**The design decisions to defend:**
- **Agent definitions are versioned code, not database rows** (Q329). Config-as-data for prompts feels flexible and removes your ability to review and test changes.
- **Deterministic core.** Anything involving money, ranking, or state transitions is Zone 2 code, not model output (Q305).
- **Multi-tenancy** enforced at the database with RLS, plus per-tenant queues so one tenant's burst can't starve others (Q258).
- **Budget enforced at three levels** — per run, per tenant per day, and globally as a kill switch.

**What I'd say about scope:** this is a lot of infrastructure. For a single agent with ten runs a day, most of it is unnecessary — a PostgreSQL job table and a worker would do. The platform exists when you have many agents, many tenants, and real spend.

---

## 332. Durable agent execution engine?

**The property:** a run survives worker death, deploys, and node loss, resuming from where it stopped rather than restarting.

**The mechanisms, which are the same ones as Document 05 applied to a loop:**

1. **Every turn persisted before the next begins** — `run_steps` keyed `(run_id, seq)` (Q303).
2. **Lease + heartbeat** — short lease (2 min), renewed every 30s, so detection is fast without false reclaims (Q201). The lease must exceed the longest single *step*, not the whole run.
3. **Atomic claim** with a guarded `UPDATE` — two workers cannot claim the same run (Q317).
4. **Deterministic context reconstruction** from persisted steps.
5. **Tool idempotency keyed on `(run_id, seq)`** so the boundary step is safe to re-execute (Q310, Q321).
6. **Outbox for external effects** so a crash between the effect and its record is recoverable (Q246).
7. **Bounded attempts** — after N reclaims, dead-letter rather than looping forever.

**The comparison to make:** this is a hand-rolled durable execution engine. Temporal, Restate, and similar systems provide it as a product — durable timers, automatic replay, deterministic workflow code. **The trade-off is real:** they eliminate a lot of the above, at the cost of a substantial new infrastructure dependency and a programming model your team must learn. For a single agent, hand-rolling on PostgreSQL is simpler. For a platform with many long workflows, a durable execution engine earns its cost.

**Being able to name that trade-off** — rather than either reinventing it unaware or reaching for Temporal reflexively — is what the question is testing.

---

## 333. Agent state persistence?

**Three categories with different lifetimes, and conflating them is a common design error:**

**1. Run state** — the current turn, status, lease, accumulated cost. One row, updated per turn. Small and hot.

**2. Step history** — the append-only log of every turn (Q303). Large, immutable, and the source for resumption, audit, replay, and SSE.

**3. Working memory** — facts the agent accumulates that shouldn't live in raw message history. Extracted entities, intermediate results, a scratchpad.

**Why separate the third:** raw message history grows without bound and is resent every turn (Q271). At turn 30, carrying 29 turns of verbatim tool results is enormously expensive and hits the context limit. Structured working memory lets you re-inject only what's relevant:
```sql
CREATE TABLE run_memory (
  run_id UUID, key TEXT, value JSONB, updated_at TIMESTAMPTZ,
  PRIMARY KEY (run_id, key)
);
```

**Context construction strategies** as history grows:
- **Sliding window** — last N turns verbatim. Simple; loses early context.
- **Summarise-and-replace** — compress old turns into a summary. Preserves gist; loses detail and costs a model call.
- **Structured memory + selective re-injection** — best quality, most engineering.
- **Hybrid** — system prompt + memory + summary of turns 1..N−5 + last 5 turns verbatim.

**The constraint that shapes all of it:** whatever you choose must be **deterministic**, or resumption produces a different context than the original run and the agent behaves differently after a crash — a genuinely miserable bug to diagnose (Q317).

**And prompt caching interacts with this** (Q277): keeping the stable prefix byte-identical means your context strategy should append rather than rewrite. A summarisation step that rewrites the middle of the context invalidates the cache for everything after it.

---

## 334. Tool authorization service?

**Centralise the decision so it cannot be forgotten per tool.**

```python
class ToolAuthorizer:
    async def authorize(self, tool: str, args: dict, ctx: UserContext) -> Decision:
        spec = self.registry.get(tool)
        if spec is None:
            return Decision.deny("unknown_tool")                  # Q288
        if spec.required_scope not in ctx.scopes:
            return Decision.deny("insufficient_scope")
        if spec.tier == "dangerous":
            return Decision.require_approval(spec, args)          # Q335
        if await self.over_limit(tool, ctx):
            return Decision.deny("rate_limited")
        return Decision.allow(inject_context(args, ctx))          # Q325
```

**The properties that matter:**

1. **A single choke point.** Every tool call goes through it. No tool implements its own auth, because a tool that forgets is a hole.
2. **Explicit registry** — unknown tool names are denied, never dispatched dynamically.
3. **Server-side context injection** — security-scoped fields never come from the model.
4. **Decisions are logged**, allowed and denied alike, with reason.
5. **Denials return generically to the model**, with detail only in the audit log (Q307).
6. **Rate limits per tool, per user, per run** — so even authorised tools can't be called 500 times.

**Where the policy lives.** For a handful of tools, scopes in the registry are fine. Beyond that, an external policy engine (OPA, Cedar) lets you express and audit policy separately from code. That's worth doing when policies become conditional on resource attributes rather than just user scopes.

**The extension for agents specifically:** the authorizer should also see the *run context* — how many times this tool has been called in this run, how much has been spent, whether the run is in an approved state. Authorization for an agent is not purely a function of (user, tool); it's a function of (user, tool, run state).

---

## 335. Human approval for dangerous tools?

**The requirement:** the run pauses, a human reviews the exact proposed action, and the run resumes or aborts based on their decision — surviving worker restarts throughout.

**The mechanism, and the key insight is that approval is a durable state, not a blocking call:**

```python
if decision.requires_approval:
    approval_id = await create_approval_request(
        run_id=run_id, seq=seq, tool=call.name,
        arguments=redact(call.args),
        preview=await tool.dry_run(call.args, ctx),   # what WOULD happen
        expires_at=now() + timedelta(hours=24),
    )
    await transition(run_id, "awaiting_approval")
    await notify_approvers(approval_id)
    return                                            # worker exits cleanly
```

The worker **releases the run and exits**. It does not block. When approval arrives, the run is re-enqueued and a (possibly different) worker resumes from the persisted state (Q317).

**Why blocking would be wrong:** a worker waiting hours for a human holds a slot, a connection, and memory, and dies on the next deploy taking the pending approval with it.

**What the human must see:**
- The exact operation and arguments, in plain language
- **A dry-run preview** — "this will delete 4,312 records" (Q312). Approving an abstract "delete_records" call is not informed consent.
- The context: what the user asked for, what the agent has done so far, why it chose this
- Who requested it and when

**The states and their timeouts:** `awaiting_approval` must expire. An approval nobody acts on for 24 hours becomes `expired`, and the run terminates. **A non-terminal state with no timeout is where runs disappear** (Q295).

**Audit:** who approved, when, what they saw. For regulated actions this is the record that matters.

**The product point:** approval friction is a real cost. Over-gating makes the agent useless; under-gating makes it dangerous. **Reversibility is often better than approval** — a scheduled send with a cancellation window gives the safety without the wait (Q312).

---

## 336. Multi-tenant agent execution?

Full isolation model at Q258. The agent-specific concerns:

**1. Tool availability varies by tenant.** Different tenants have different integrations enabled. The tool list is constructed per run from tenant configuration — and a tenant's model context must never contain another tenant's tools.

**2. Prompt and configuration per tenant.** Custom instructions, domain vocabulary, branding. **This must not become arbitrary tenant-supplied prompt content injected into the system prompt** — that's a self-service prompt-injection vector. Constrain it to a template with validated fields.

**3. Cost isolation is the hard one.** Agent spend varies by orders of magnitude between tenants. Required:
- Per-tenant daily/monthly budget, checked before starting a run *and* between turns
- Per-run cap so one run can't consume the tenant's whole budget
- Spend attribution per run, per tenant, in `run_steps`
- A circuit breaker that stops accepting runs when the budget is exhausted

**4. Capacity isolation.** Separate queues or consumer groups per tenant tier, so one tenant enqueueing 10,000 runs doesn't starve everyone (head-of-line blocking, Q204). Per-tenant concurrency caps.

**5. Data isolation** — RLS on every table, server-side tenant injection into every tool call (Q325), and a CI suite attempting cross-tenant access through each tool.

**6. Rate limiting against shared upstreams.** All tenants share your LLM provider quota. Without per-tenant limits, one tenant consumes the whole TPM allocation and everyone else gets 429s.

**The failure mode to name unprompted:** a single tenant with a buggy integration triggering thousands of runs. Without per-tenant caps, that's your entire provider quota and a five-figure bill overnight. **Per-tenant spend limits are not a billing feature; they're an availability control.**

---

## 337. Agent observability?

**The distinguishing difficulty: an agent's behaviour isn't reproducible from its code.** Same code, different behaviour per run. So observability is not a debugging aid here — it's the only record of what the system actually did (Q327).

**The layers:**

**1. Traces.** One trace per run, one span per turn, nested spans for model calls and tool executions. Attributes: model, tokens, cost, tool name, latency. **A trace waterfall is the single most useful agent debugging artifact** — it shows immediately where time and money went.

**2. Metrics (the ones that matter):**
- Runs by terminal state — `succeeded`, `max_turns_exceeded`, `budget_exceeded`, `stuck`, `failed`. **The distribution is your quality signal.**
- Turns per run: p50/p95/p99
- Cost per run and per tenant
- Tool call rate, error rate, and latency **per tool**
- Repeated-call rate (Q322)
- Time to first token, total run duration
- Queue depth and oldest-pending age (Q202)

**3. Logs** — structured, with `run_id` on every line (Q314), payloads redacted (Q326).

**4. The step store itself** — the complete record of what the model saw and did, queryable.

**5. A run inspector UI.** Not optional. When someone reports "the agent did something weird," you need to open that run and read the trajectory. Reconstructing it from logs is too slow to be useful.

**What to alert on:**
- Terminal-state distribution shifting (a rise in `stuck` is a regression)
- Cost per run rising — often the first sign of a prompt change gone wrong
- Tool error rate per tool
- p99 turns approaching the cap
- Unauthorized tool attempts (Q325)

**The point that closes Q610:** these metrics don't just help you debug — a shift in terminal-state distribution after a deploy *is* how you detect a prompt regression in production, before the eval suite catches it in the next release cycle.

---

## 338. Agent cost controls?

**Cost is a first-class engineering constraint here, not an afterthought.** An agent spends money continuously while running, and the spend is unbounded by construction (Q291).

**The layers, innermost first:**

**1. Per-model-call.** `max_tokens` cap so one call can't be enormous. Context trimming so input doesn't grow unbounded (Q333).

**2. Per-turn.** Bounded tool results — a tool returning 50,000 tokens costs you on every subsequent turn.

**3. Per-run.** Turn cap and spend cap, both checked *between turns* (Q297). Terminal states distinct so the metrics tell you which bound is binding.

**4. Per-tenant.** Daily and monthly budgets. Checked before starting a run and between turns. Circuit breaker when exhausted (Q336).

**5. Global.** A kill switch and an aggregate spend alert. Worth building before you need it.

**The optimisations, in order of leverage:**

1. **Prompt caching** (Q277). The stable prefix — system prompt and tool schemas — is resent every turn. Caching it is the single largest saving available in an agent loop, and it costs nothing in quality. **Requires the prefix to be byte-identical**, so structure prompts accordingly.
2. **Model routing** (Q290). Not every turn needs the strongest model. Tool-selection turns are often adequately handled by a cheaper model; final synthesis may need the stronger one.
3. **Fewer turns.** Parallel tool calls in one turn instead of sequential turns. Better tool descriptions reducing wasted exploration.
4. **Context trimming.** Summarise old turns; carry structured memory instead of verbatim history.
5. **Result caching** — identical tool calls within a run return cached results (Q287).

**The metric to track:** cost per *successful* run, broken down by turn. That decomposition tells you which turn is expensive and whether it's worth it — and it's the number that makes cost conversations concrete rather than anxious.

---

## 339. 10k concurrent agent runs?

**Start with the arithmetic, because it reframes the problem.** 10,000 concurrent runs, each averaging 5 minutes, means roughly 33 runs starting per second and 33 completing. If each run is 20 turns, that's ~660 model calls per second sustained.

**The binding constraint is almost certainly your LLM provider quota, not your infrastructure.** Say that first — it's the answer.

**Working through the limits:**

1. **Provider TPM/RPM.** 660 calls/sec with 10k-token contexts is ~6.6M input tokens per second. That is far beyond standard quotas. **You need negotiated capacity, multiple providers, or model routing to smaller models.** This determines whether the system is possible at all.

2. **Worker capacity.** Runs are I/O-bound (waiting on model calls), so each worker handles many concurrently via asyncio. Perhaps 50–100 concurrent runs per worker → 100–200 workers.

3. **Database.** 660 model calls/sec × ~2 writes each = ~1,300 writes/sec to `run_steps`. Fine for PostgreSQL, but partition the table by month and keep transactions short. **PgBouncer is mandatory** at this worker count (Q249).

4. **Redis.** Stream throughput is fine; memory is the constraint. Trim aggressively.

5. **Cost.** At even ₹5 per run, 10k concurrent runs turning over every 5 minutes is ₹600,000 per hour. **The cost controls (Q338) are not optional at this scale — they're the primary system requirement.**

**Design choices:**
- **Shared rate limiter** across all workers (Redis token bucket), sized to the provider quota. Per-worker limiting gives you 200× the intended rate (Q249).
- **Model routing** to reduce load on the expensive model.
- **Prompt caching** — at this volume the savings are enormous.
- **Per-tenant queues and caps** so no tenant monopolises quota.
- **Autoscale on oldest-pending-age**, not queue depth (Q100).
- **Graceful degradation** — when quota is exhausted, queue rather than fail, and communicate expected wait.

**The closing point:** at this scale the engineering problem shifts from "can we run agents" to "how do we allocate a scarce, expensive, externally-rate-limited resource fairly across tenants." That's a scheduling and quota problem, not an agent problem — and framing it that way is the L4 answer.

---

*End of Document 07. Next: Document 08 — RAG (questions 340–393).*
