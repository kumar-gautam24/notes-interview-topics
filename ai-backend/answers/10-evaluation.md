# Document 10 — Evaluation (Questions 418–440)

Answer format: **definition → why → implementation → failure → trade-off → real example**

> **Note on Section J.** This is the section that most distinguishes candidates, because almost nobody does it properly. It is also the section where a fabricated answer is most easily exposed — Q599 and Q590 both come back here. If you have not built an eval suite, the honest answer plus a concrete plan beats an invented metric every time.

---

# L1 — Foundation

## 418. What is an eval?

**Definition.** A repeatable measurement of system quality against a fixed dataset with known expected outcomes.

**Why it exists.** LLM systems are non-deterministic, and their behaviour changes when you edit a prompt, upgrade a model, change chunking, or adjust retrieval. **Without evals, every change is a guess and every "it seems better" is confirmation bias.** You cannot ship confidently because you cannot tell whether you improved or regressed.

**The three things an eval gives you:**
1. **A baseline** — where you are now
2. **A comparison** — did this change help, and by how much
3. **A regression guard** — did this change break something that used to work

**The distinction from testing.** A unit test asserts a deterministic output. An eval measures a *distribution* of quality over a dataset, because the system is probabilistic and no single output is guaranteed. **An eval that asserts exact string equality on LLM output will flake** and will be deleted within a month (Q439).

**The maturity signal.** Most teams building on LLMs have no evals. They iterate on prompts, look at a handful of outputs, and ship on vibes. **Saying "the first thing I built was a golden set, because I couldn't tell whether my changes were helping" is one of the strongest things you can say in an AI engineering interview** — it demonstrates the discipline the field is short of.

**What an eval is not:** a guarantee of correctness. It measures performance on the cases you thought to include. Production will find cases you didn't (Q437).

---

## 419. Retrieval vs generation eval?

**They must be measured separately, and this is the single most important structural decision in RAG evaluation.**

**Retrieval eval** — did we fetch the right chunks?
- Dataset: question → labelled relevant chunk IDs
- Metrics: recall@k, MRR, NDCG@k (Q364)
- **Deterministic** — no model call, so it runs in seconds and never flakes
- Fast enough to run on every commit

**Generation eval** — given correct context, did we produce a good answer?
- Dataset: question + *known-correct* context → reference answer
- Metrics: faithfulness, correctness, citation validity
- Non-deterministic, slow, costs money

**End-to-end eval** — the full pipeline.

**Why separating them is essential.** An end-to-end score of 0.70 tells you nothing actionable. But:

| Retrieval | Generation (given context) | End-to-end | Diagnosis |
|---|---|---|---|
| 0.85 | 0.95 | 0.70 | **Retrieval is the bottleneck** |
| 0.95 | 0.72 | 0.70 | **Generation is the bottleneck** |
| 0.60 | 0.95 | 0.58 | Retrieval, severely |

**Same end-to-end number, opposite fixes.** This decomposition is what turns a score into a decision (Q354, Q375).

**The practical benefit:** retrieval evals are cheap and deterministic, so you can run them on every PR and sweep dozens of configurations. Generation evals are expensive, so you run them on a schedule or before release. **Different cadences for different costs** — and separating them is what makes that possible.

---

## 420. Golden dataset?

**Definition.** A fixed set of inputs with known-correct outputs, used as the reference for measuring quality.

**Composition for a RAG system:**
```python
@dataclass
class GoldenCase:
    id: str
    question: str
    relevant_chunk_ids: list[str]     # for retrieval eval
    reference_answer: str             # for generation eval
    must_contain: list[str]           # required facts
    must_not_contain: list[str]       # common wrong answers
    category: str                     # for per-segment breakdown
    is_answerable: bool               # unanswerable cases go here too
```

**Where the cases come from, best first:**
1. **Real production queries.** The distribution that matters. Sample from logs, especially from thumbs-down and escalations.
2. **Domain experts** writing questions they'd actually ask.
3. **LLM-generated from chunks**, then human-reviewed. Fast for bootstrapping; **beware the circularity** — questions generated from a chunk are trivially retrievable by that chunk, which inflates recall.
4. **Every production failure you've fixed** — the regression set (Q437).

**Size:** 30 questions is enough to be useful and detect large differences. 100+ before you trust a 5-point delta. **Report the confidence interval** — recall@5 = 0.80 on 30 questions has roughly a ±0.14 interval, and treating a 0.80-vs-0.83 comparison as meaningful at that size is a statistical error.

**What must be included and usually isn't:**
- **Unanswerable questions** (15–20%) measuring refusal (Q425)
- **Adversarial cases** where training knowledge contradicts your corpus (Q369)
- **Multi-turn cases** if you support conversation (Q383)
- **Edge cases** — long queries, identifiers, typos, code-mixed language

**Maintenance:** version it, review it as the corpus changes, and add every production failure. **A golden set that hasn't changed in six months is measuring a system that no longer exists.**

---

## 421. Regression test?

**Definition.** A test that verifies previously-working behaviour still works after a change.

**In LLM systems, the regression set is your accumulated failures.** Every bug you fix becomes a permanent case. Over time this becomes the most valuable dataset you own, because **it's made entirely of things that actually broke in your system** rather than cases you imagined.

**The workflow:**
```
production failure → reproduce → add to regression set with expected behaviour
                  → fix → verify the case passes → merge
```
**The case is added before the fix**, so you've proven it fails first. Otherwise you don't know your test tests anything.

**What it catches that a golden set doesn't:** narrow, specific breakages. The golden set measures general quality; the regression set asserts "this exact thing must not come back."

**The property that makes it valuable in LLM systems specifically:** changes have **non-local effects**. Editing a system prompt to fix one behaviour routinely breaks a different one you fixed three months ago — and nothing warns you. In deterministic code, a change to module A doesn't silently alter module B. In a prompt, it does. **The regression set is the only defence against this**, and it's why prompt changes need CI gating as much as code changes do (Q329).

**Run it on every prompt, model, tool-schema, or retrieval change**, and block the merge on failure.

**The practical caution:** because outputs are non-deterministic, regression assertions must be robust — "must contain this fact," "must refuse," "must call this tool" — not exact string matches (Q439).

---

## 422. Accuracy?

**Definition.** The fraction of cases where the output is correct.

**The immediate problem: "correct" is often not binary for generated text.** A summary can be 80% right. An answer can be correct but incomplete, or correct with a fabricated citation.

**Where accuracy works well:**
- **Classification** — the label is right or wrong
- **Extraction** — field-by-field comparison against expected values
- **Structured output** — exact comparison after parsing
- **Tool selection** — did it call the right tool (Q430)

For these, use it. It's unambiguous and cheap.

**Where it works badly:**
- **Free-form answers** — needs a judge, and judges are noisy (Q432)
- **Summarisation** — no single correct output
- **Anything with multiple valid phrasings**

**Better decompositions for generated text:**
- **`must_contain` / `must_not_contain`** — assert specific facts appear and specific wrong answers don't. **Deterministic, cheap, robust to phrasing** — this is the workhorse and it's underused.
- **Claim-level correctness** — decompose into atomic claims and check each
- **Faithfulness** separately from correctness (Q365)

**The trap to name:** aggregate accuracy hides segment failures. 85% overall can mean 95% on common queries and 40% on identifier lookups. **Always break accuracy down by category** — that breakdown is usually where the actionable finding is (Q436).

---

## 423. Precision/recall?

**In evaluation terms:**
- **Precision** = of the things we returned/claimed, what fraction were correct
- **Recall** = of the things we should have returned/claimed, what fraction did we

**In RAG retrieval** (Q364, Q373):
- **Recall@k** is the primary metric. If the answer isn't retrieved, nothing downstream recovers.
- **Precision@k** is weak for RAG, because most questions have 1–2 relevant chunks. Perfect retrieval at k=10 gives precision 0.2, and optimising it pushes you toward a smaller k, which hurts recall.

**In classification and extraction**, both matter, and the trade-off is set by the cost asymmetry:
- **High precision, lower recall** — when false positives are costly. Flagging a transaction as fraudulent.
- **High recall, lower precision** — when false negatives are costly. Screening for a serious diagnosis.

**F1** is the harmonic mean, useful as a single number when both matter roughly equally. **Fβ** weights one over the other — F2 favours recall, F0.5 favours precision. Using Fβ with a justified β is a stronger answer than defaulting to F1.

**The framing that matters:** precision and recall are not a technical choice, they're a **product decision about which error is more expensive**. For an insurance assistant, a wrong answer (low precision) has regulatory consequences; a refusal (low recall) is merely unhelpful. That asymmetry says: optimise precision, accept refusals. **Say the asymmetry out loud** — that's what distinguishes an engineer from someone reciting metric definitions.

---

## 424. Hallucination rate?

**Definition.** The fraction of outputs containing at least one claim not supported by the provided context or by ground truth.

**Two things are being conflated and should be separated:**
- **Ungrounded** — not supported by the retrieved context (measurable mechanically)
- **Factually wrong** — contradicts reality (needs ground truth)

An answer can be ungrounded but true (the model knew it from training) — **still a failure in a document-grounded product**, because it will be wrong for the next user whose document differs (Q369).

**How to measure:**

**1. Claim-level grounding.** Decompose the answer into atomic claims; for each, ask a judge whether the context entails it.
```
grounding_rate = supported_claims / total_claims
hallucination_rate = 1 - grounding_rate
```

**2. Citation verification — cheap and mechanical** (Q368):
- Does every cited index exist?
- Does the cited chunk contain the claimed content?
- What fraction of claims carry a citation?

**These are pure code, no judge, no cost.** They catch the most common and most damaging failure — fabricated citations and invented identifiers.

**3. Adversarial cases** where the corpus contradicts common knowledge. If the model gives the common answer instead of the document's, it's hallucinating from training (Q369).

**What to report:** hallucination rate at the *claim* level, not the answer level. "12% of claims were unsupported" is more actionable than "30% of answers contained a hallucination," because it tells you whether answers are mostly-right-with-one-error or wholesale invention.

**The metric to watch in production:** citation validity rate. It's computable on every response at zero cost, and a drop after a deploy is one of the earliest quality-regression signals available.

---

## 425. Refusal rate?

**Definition.** The fraction of queries where the system declines to answer.

**Why it's a first-class metric, not an error count:** refusal is the *correct* behaviour when the context is insufficient. A system that never refuses is hallucinating on every unanswerable question (Q366).

**Measure it on two distinct sets:**

| Set | Desired | Failure mode |
|---|---|---|
| **Unanswerable questions** | Refusal rate near 100% | Under-refusal → hallucination |
| **Answerable questions** | Refusal rate near 0% | Over-refusal → useless product |

**Both numbers are needed.** Reporting only one is meaningless — a system that refuses everything scores perfectly on the first set.

**This is a precision/recall trade-off in disguise** (Q423), controlled by your similarity or reranker threshold (Q370). Raising the threshold increases correct refusals *and* incorrect ones. **Plot the two rates against the threshold and pick the operating point that matches your cost asymmetry.**

**Constructing the unanswerable set** — 15–20 questions that are:
- Plausibly in-domain (so retrieval returns *something*, which is the hard case)
- Genuinely absent from the corpus
- **Answerable from general knowledge**, so a model using parametric knowledge is caught (Q369)

That third property is what makes the set diagnostic rather than trivial.

**In production:** track refusal rate over time. A sudden rise means retrieval broke, an index went stale, or a filter is misconfigured. A gradual rise means corpus drift. **It's one of the cheapest and most informative production signals**, and it's computable without any judge or labelling.

---

# L2 — Building evals

## 426. How build a golden dataset?

**The process, and the honest framing is that it's a few hours of work that most teams never do:**

**1. Source the questions.**
- **Production logs first** — real queries have the real distribution. Sample across common and long-tail.
- **Thumbs-down and escalations** — these are pre-labelled failures.
- **Domain experts** writing what they'd actually ask.
- **LLM-generated from chunks** for bootstrapping, but **beware circularity**: a question generated from chunk X is trivially retrievable by chunk X, which inflates recall by construction. Have a human rewrite them into natural phrasing.

**2. Label the relevant chunks.** For each question, identify which chunk(s) actually answer it. **This is the work** — it's manual and it's why people skip it. Budget 2–4 minutes per question, so 30 questions is roughly two hours.

Speed it up: run your current retriever at k=20, have a human mark which of the 20 are relevant. Much faster than searching the corpus manually. **Accept the bias** — you may miss relevant chunks your retriever never surfaces, which slightly inflates recall. Mitigate by labelling from a *union* of vector and lexical results.

**3. Write reference answers** for generation eval, plus `must_contain` facts.

**4. Add the negative cases** — unanswerable, adversarial, edge cases (Q420).

**5. Categorise** every case so you can break results down by segment (Q436).

**6. Version it.** In the repo, reviewed like code.

**Start at 30 cases.** It's enough to detect large differences and it's achievable in an afternoon. Grow it from production failures over time — that growth is automatic if you have the workflow (Q421).

**The answer to give:** *"I built it from 30 real production queries, labelled by which chunk answers each, plus 10 deliberately unanswerable ones. It took an afternoon and it's the reason I can say the reranker helped rather than guessing."*

---

## 427. How measure retrieval?

Full metric definitions at Q364. The implementation:

```python
def evaluate_retrieval(golden: list[GoldenCase], retriever, k: int) -> dict:
    hits, rr, ndcgs = 0, [], []
    for case in golden:
        results = retriever(case.question, k)
        ids = [r.id for r in results]
        relevant = set(case.relevant_chunk_ids)

        if relevant & set(ids):
            hits += 1
        first = next((i for i, cid in enumerate(ids, 1) if cid in relevant), None)
        rr.append(1/first if first else 0)
        ndcgs.append(ndcg(ids, relevant, k))

    return {"recall_at_k": hits/len(golden),
            "mrr": mean(rr),
            "ndcg_at_k": mean(ndcgs)}
```

**Report recall at multiple k**, because the *shape* is the diagnostic (Q372):
- recall@5 = 0.74, recall@20 = 0.93 → answer is in the pool, ranked badly → **add a reranker**
- recall@5 = 0.74, recall@20 = 0.76 → answer isn't retrieved → **fix chunking, add lexical search**

**Break down by category** (Q436). Aggregate recall of 0.85 can hide identifier queries at 0.40, which points straight at hybrid search (Q355).

**Why this eval is the one to build first:** it's **deterministic**, so it never flakes; it's **fast**, so it runs on every commit; it's **free**, no model calls; and it measures the stage where most failures originate (Q354). You can sweep chunk sizes, embedding models, k values, and fusion weights in an afternoon and get a number for each.

**The thing it unlocks:** every tuning argument in Documents 08 and 09 becomes an experiment. "Should we use 300 or 600 token chunks" stops being a discussion.

---

## 428. How measure grounding?

Full treatment at Q365. The implementation choices in order of cost:

**1. Citation verification — free, mechanical, do this first:**
```python
def verify(answer: str, chunks: list[Chunk]) -> dict:
    cited = extract_citation_indices(answer)
    invalid = [i for i in cited if not 1 <= i <= len(chunks)]
    claims = extract_claims(answer)
    uncited = [c for c in claims if not has_citation(c)]
    bad_quotes = [q for q, i in extract_quotes(answer)
                  if q not in chunks[i-1].content]
    return {"invalid_citation_rate": len(invalid)/max(len(cited),1),
            "uncited_claim_rate": len(uncited)/max(len(claims),1),
            "bad_quote_rate": len(bad_quotes)/max(len(claims),1)}
```
**No judge, no cost, runs on every response including in production.** Catches fabricated citations, which is the most damaging RAG failure (Q368).

**2. Claim-level entailment — the rigorous version.** Decompose the answer into atomic claims; for each, ask a judge model whether the context entails it. This is RAGAS faithfulness and it's the most defensible number, at the cost of one judge call per claim.

**3. Whole-answer judge with a rubric.** Cheaper, noisier (Q432).

**The set to measure on:** include unanswerable questions, or you're only measuring grounding in the easy case (Q425).

**The interpretation that makes it useful:** pair grounding with context recall.
- **Low grounding, high context recall** → generation problem. The model was given what it needed and didn't use it.
- **Low context recall** → retrieval problem, and grounding is irrelevant until you fix it.

**That pairing is the whole point of measuring both** — one number tells you the score, two tell you what to do.

---

## 429. How measure answer quality?

**No single metric works, so use a layered approach:**

**1. Deterministic assertions first — cheap and robust:**
```python
must_contain: ["30 days", "waiting period"]
must_not_contain: ["90 days", "no waiting period"]
```
Phrasing-independent, no judge, no cost. **This catches most real regressions** and is dramatically underused because it feels unsophisticated.

**2. Structured comparison** where the output is structured — field-by-field (Q422).

**3. Citation validity** (Q428).

**4. LLM-as-judge** for holistic quality, with an explicit rubric (Q432):
```
Score 1-5 on: correctness, completeness, groundedness, clarity.
Provide reasoning before the score.
```

**5. Pairwise comparison** rather than absolute scoring. Judges are much more reliable at "is A or B better" than at "rate this 1–5" — absolute scores drift and cluster. **Pairwise against the current baseline is the more trustworthy method** and worth naming.

**6. Human review** on a sample. Expensive, and still the ground truth against which you validate your judge (Q432).

**What NOT to use:** BLEU, ROUGE, and exact-match against a reference answer. They measure surface overlap, penalise correct answers phrased differently, and reward wrong answers that share vocabulary. **They are actively misleading for LLM output** and their presence in an eval suite is a sign nobody validated the metrics.

**The composite to report:** a small dashboard, not one number — correctness, faithfulness, citation validity, refusal rate on both sets, plus latency and cost. **One number hides the trade-offs you're actually making.**

---

## 430. How measure tool selection accuracy?

**Definition.** Given a query, did the agent call the correct tool(s)?

**The dataset:**
```python
@dataclass
class ToolCase:
    query: str
    expected_tools: list[str]       # must be called
    forbidden_tools: list[str]      # must NOT be called
    expected_order: list[str] | None
    mocked_results: dict            # for determinism
```

**Metrics:**
```python
correct_tool_rate   = # cases where the right tool was called first
precision           = correct calls / total calls          # wasted calls
recall              = expected tools called / expected tools
forbidden_call_rate = # cases calling a forbidden tool      # safety
turn_efficiency     = actual turns / minimum turns
```

**`forbidden_call_rate` is the safety metric** and it's the one to lead with. A query about coverage must never trigger `delete_policy`, and that's a categorical failure, not a quality score.

**Mock all tool results** so the eval is deterministic, fast, free of side effects, and cheap enough to run in CI. You're testing the *reasoning*, not the integration — keep a small live suite separately.

**Run each case N times** (5 is reasonable) and report the pass rate. Tool selection is non-deterministic; a single run tells you almost nothing (Q439).

**What this eval actually tunes: tool descriptions.** The `description` field is the primary determinant of selection accuracy (Q283), and it's a prompt that deserves iteration and measurement like any other. **Most teams write tool descriptions once and never measure them.** A tool-selection eval turns description-writing from guesswork into an experiment.

**The diagnostic value:** low accuracy on one tool means its description is unclear or overlaps another's. High `invented tool` rate means a capability gap (Q288). Both are visible only if you measure.

---

## 431. How measure argument correctness?

**Separate from tool selection**, because the right tool with wrong arguments fails just as completely.

**The levels, and each catches a different failure:**

**1. Schema validity (deterministic, free):**
```python
try:
    tool.input_model.model_validate(call.args)
    schema_valid = True
except ValidationError:
    schema_valid = False
```
Rate of schema violations. Should be near zero with constrained decoding (Q270); a non-zero rate points at a schema that's too permissive or a description that misleads.

**2. Exact match on critical fields.** For an extraction or lookup, compare argument values to expected:
```python
expected: {"policy_type": "health", "query": <any>}
```
Compare the fields that determine correctness; allow free variation in the rest (a search `query` string has many valid phrasings).

**3. Semantic equivalence** for free-text arguments — did the query capture the user's intent? Needs a judge, or a downstream proxy: **did the resulting retrieval return the right chunks?** That proxy is better than judging the string, because it measures the thing you actually care about.

**4. Constraint violations** — did it request `limit=1000` when the max is 20? These should be impossible via schema (Q284); a non-zero rate means your schema is under-constrained.

**5. Security-relevant arguments** — did it attempt to supply a `tenant_id`? **This should be structurally impossible** (Q325); any occurrence is a finding, not a metric.

**What this tunes:** parameter descriptions, enum constraints, and default values. A high error rate on one parameter means its description doesn't convey the expected format — for example, a date parameter without a stated format will receive three different formats.

**Report per tool and per parameter.** Aggregate argument accuracy hides that one tool's date field fails 40% of the time.

---

## 432. LLM-as-judge?

**Definition.** Using a language model to score outputs against a rubric.

**Why it's necessary:** free-form quality can't be measured mechanically, and human review doesn't scale to every PR.

**How to do it properly:**

1. **Explicit rubric with defined levels.** Not "rate 1–5" but "5 = fully correct and complete; 4 = correct but omits a minor detail; 3 = partially correct…"
2. **Reasoning before the score.** Force the judge to justify first; scores improve measurably.
3. **Pairwise comparison over absolute scoring.** Judges are far more reliable at A-vs-B than at absolute ratings, which drift and cluster around the middle. **This is the single biggest reliability improvement available.**
4. **Randomise position** in pairwise comparisons — judges have a documented position bias.
5. **A strong model as judge**, and note it may be more expensive per eval run than the system being evaluated.
6. **Structured output** so scores parse reliably.

**The biases to name — this is what an interviewer is checking:**
- **Position bias** — favours the first (or last) option
- **Verbosity bias** — favours longer answers regardless of quality
- **Self-preference** — models rate their own family's outputs higher
- **Leniency** — scores skew high without a sharp rubric
- **Sycophancy** — agrees with a framing embedded in the prompt

**The essential step almost everyone skips: validate the judge against human labels.** Have humans score 50 cases, run the judge on the same 50, and measure agreement (Cohen's kappa or simple correlation). **If the judge doesn't agree with humans, its scores are noise you're making decisions on.** Doing this once, at the start, is what makes every subsequent judge-based number credible.

**The honest position:** LLM-as-judge is useful and noisy. Use deterministic metrics where possible (Q429), judges for what's left, and validate the judge before trusting it.

---

## 433. Continuous evaluation?

**Definition.** Evals running automatically on every change, in CI, gating merges — the same way tests do.

**The tiered structure, because cost differs by orders of magnitude:**

| Tier | Cadence | Contents | Cost |
|---|---|---|---|
| **Fast** | Every commit | Retrieval eval, schema validation, tool selection (mocked) | Seconds, free |
| **Full** | Every PR touching prompts/models/retrieval | Generation eval, grounding, refusal, regression set | Minutes, ~₹100 |
| **Deep** | Nightly / pre-release | Large golden set, adversarial, multi-turn, human sample | Longer, higher |

**The fast tier is deterministic and free**, which is why the retrieval/generation split matters so much (Q419) — it lets you gate every commit on something meaningful.

**Gating:**
```yaml
- name: Run evals
  run: python -m evals.run --baseline main --fail-on-regression 0.03
```
Block the merge if a key metric drops more than the threshold. **Report deltas against baseline**, not absolutes — "recall@5: 0.84 → 0.91 (+0.07)" is what a reviewer needs.

**What must trigger a full run:** prompt changes, model version changes, chunking changes, embedding model changes, retrieval parameter changes, tool schema changes. **These are exactly the changes that look harmless in a diff and aren't** (Q329).

**Handle non-determinism:** run N times, report mean and spread, set thresholds accounting for variance (Q439).

**The production feedback loop:** thumbs-down responses flow into a review queue; confirmed failures become regression cases. **This is what keeps the eval set representative** rather than measuring a distribution from six months ago.

**The framing:** *"Prompts are the highest-leverage and least-tested part of an LLM system. Treating a prompt edit as an untested code change is the actual maturity gap."*

---

# L3 — Failure and interpretation

## 434. Eval passes, production fails. Why?

**The most important question in this section, and the answer is a list of distribution gaps:**

**1. Distribution mismatch.** Your eval set has clean, well-formed questions. Production has typos, fragments, code-mixed Hinglish, copy-pasted error text, and multi-part questions. **The eval measures a distribution that doesn't exist.**

**2. The eval set is stale.** Built six months ago against a corpus that has since changed.

**3. Overfitting to the eval set.** You tuned until the metric went up. The set has become a target rather than a measurement — **Goodhart's law applied to evals** (Q440).

**4. Missing edge cases.** Long documents, empty results, adversarial input, concurrent load.

**5. Multi-turn not covered.** Single-turn evals miss conversational degradation (Q383).

**6. Production-only conditions** — real latency, rate limits, timeouts, partial failures, cold caches, index lag. Evals run against a warm, healthy system.

**7. Mocked tools hide integration failures.** The reasoning is correct and the tool call fails against the real service (Q430).

**8. Real data is messier.** Scanned PDFs, tables, mixed languages, formatting artefacts.

**9. Non-determinism.** Your eval passed on one sample; production runs thousands (Q439).

**10. The metric doesn't capture what users want.** High faithfulness, useless answers.

**The fixes:**
- **Source eval cases from production logs**, continuously (Q426)
- **Hold out a test set** you never tune against (Q440)
- **Add every production failure to the regression set** (Q437)
- **Monitor production quality directly** — refusal rate, citation validity, thumbs-down (Q438)

**The framing:** *"Evals measure the distribution you thought to include. Production is the distribution that exists. The loop from production failures back into the eval set is what closes the gap, and it's the part most teams don't build."*

---

## 435. Metric improves, users unhappy. Why?

**Goodhart's law: when a measure becomes a target, it ceases to be a good measure.**

**The concrete mechanisms:**

**1. You optimised the wrong thing.** Grounding rate went up because the system started refusing more. Faithfulness is perfect on refusals. **Users wanted answers.** This is the most common version and it's insidious because the metric is genuinely correct.

**2. The metric is a proxy that came unstuck.** Retrieval recall improved while answer *usefulness* didn't, because the chunks were retrieved but poorly synthesised.

**3. An unmeasured dimension degraded.** Accuracy up, latency doubled. Or answers became correct and three times longer, and nobody reads them.

**4. Aggregate improvement, segment regression.** Overall accuracy +3%, but the most common query type −10%, offset by gains on rare types. **Users experience the common case** (Q436).

**5. The metric measures the system, not the outcome.** A correct answer to the question asked, when the user asked the wrong question.

**6. Distribution mismatch** (Q434).

**The defences:**
- **Track a metric suite, not one number** — quality, latency, cost, refusal rate, length
- **Guardrail metrics** that must not regress even when the target improves
- **Segment every metric** (Q436)
- **Watch direct user signals** — thumbs-down, follow-up rate, escalation rate, abandonment. **These are ground truth and your metrics are proxies for them.**
- **Hold out a test set** (Q440)

**The answer to give:** *"I'd check the guardrails first — usually the target metric improved by trading against something I wasn't watching, and refusal rate is the classic one. Then I'd segment, because an aggregate gain can hide a regression on the queries users actually send."*

---

## 436. How segment eval results?

**Aggregate metrics hide the finding. Segmentation is where the actionable information lives.**

**The dimensions to segment by:**

| Dimension | Reveals |
|---|---|
| **Query type** (factual / comparative / procedural / identifier) | Identifier queries failing → add BM25 (Q355) |
| **Document type / source** | Bad extraction from one source (Q390) |
| **Query length** | Short queries under-specified; long ones diluted |
| **Answerable vs not** | Refusal calibration (Q425) |
| **Single vs multi-turn** | Conversational degradation (Q383) |
| **Language** | Hindi/Hinglish underperforming (Q343) |
| **Tenant / customer** | One customer's corpus is worse |
| **Recency** | Newly indexed content failing |
| **Difficulty** | Where the ceiling is |

**The implementation is trivial** — tag every golden case with a category and group the results:
```python
for category, cases in group_by(golden, lambda c: c.category):
    print(category, recall_at_k(cases, retriever, 5), len(cases))
```

**The pattern to expect:** overall recall@5 of 0.85 decomposing into 0.94 on conceptual questions and 0.42 on identifier lookups. **That single breakdown tells you to add lexical search**, and it's invisible in the aggregate.

**Weight by production frequency.** If identifier queries are 5% of traffic, a 0.42 there is less urgent than a 0.80 on the 60% case. **Report both the per-segment score and the segment's share of traffic**, or you'll optimise a rare case.

**Watch for Simpson's paradox:** an overall improvement composed of per-segment regressions, if the segment mix shifted. Always check that segment sizes are stable between runs.

**Sample size caveat:** segmenting 30 cases into six categories gives five per category, which is noise. **Segment when you have enough cases**, or accept that segment numbers are directional only.

---

## 437. Handling new failure modes?

**The workflow that turns a production failure into permanent protection:**

```
1. Detect      → user report, thumbs-down, monitoring alert, sampled review
2. Reproduce   → capture the exact input, retrieved context, and output
3. Classify    → retrieval / generation / tool / infrastructure (Q375)
4. Add to regression set  ← BEFORE fixing, and verify it fails
5. Fix
6. Verify the case passes
7. Merge with the case in CI
```

**Step 4 before step 5 is the discipline.** If you fix first and add the test after, you don't know the test tests anything — it may pass for unrelated reasons.

**Where new failure modes come from:**
- Corpus changes — a new document type your chunker handles badly
- Query distribution shift — a marketing campaign brings a new user population
- Model updates — provider changes behaviour under a stable name
- Dependency changes — an embedding model version bump
- Scale — behaviours that only appear under concurrency

**Detection mechanisms you need in place:**
1. **Explicit feedback** — thumbs up/down with the full retrieval trace attached
2. **Implicit signals** — follow-up rate, rephrasing, abandonment, escalation to support
3. **Automatic checks in production** — citation validity, refusal rate, grounding on a sample (Q438)
4. **Sampled human review** — 20 responses a week, read by someone who knows the domain. **Unglamorous and consistently the highest-yield source of new failure modes.**

**The compounding property:** a regression set built this way is made entirely of things that actually broke *in your system*. After a year it's more valuable than any synthetic benchmark, and it's the artefact that makes prompt changes safe to ship (Q421).

---

## 438. Continuous production monitoring?

**Evals measure a fixed set. Production measures reality. You need both** (Q434).

**What you can measure in production without labels — this is the key insight, since production has no ground truth:**

| Signal | Cost | Detects |
|---|---|---|
| **Citation validity rate** | Free, mechanical | Generation regression (Q368) |
| **Refusal rate** | Free | Retrieval breakage, index staleness (Q425) |
| **Retrieval score distribution** | Free | Corpus or embedding drift (Q370) |
| **Zero/low-result rate** | Free | Filter bugs, ANN+filter interaction (Q414) |
| **Answer length distribution** | Free | Prompt regression |
| **Thumbs down rate** | Free | Direct user judgement |
| **Follow-up / rephrase rate** | Free | Unsatisfying answers |
| **Escalation to human** | Free | Hard failures |
| **Sampled grounding check** | Cheap (judge on 1%) | Hallucination trend |
| **Latency and cost per query** | Free | Regression, budget |

**The free mechanical ones are the workhorses.** Citation validity and refusal rate cost nothing, compute on every response, and move immediately when something breaks. **A deploy that raises the refusal rate from 8% to 22% is visible within minutes**, before any user complains.

**Alerting:** on *changes* in distribution, not absolute thresholds. Refusal rate rising 3× is a signal regardless of its baseline value.

**Sampled evaluation:** run a judge on 1% of production traffic for grounding and quality. Gives a continuous quality trend at a manageable cost.

**The loop that matters:** production signals → sampled review → confirmed failures → regression set → CI. **Without that loop, your eval set slowly stops representing your system** (Q437).

**Log the retrieval trace with every response** — chunk IDs, scores, the reranked order. It costs storage and it's what makes post-hoc diagnosis possible (Q375). Without it, you cannot answer "was the right chunk retrieved?" for last week's failure.

---

## 439. Non-determinism in evals?

**The fundamental problem: the same input can produce different outputs**, even at `temperature=0` (Q265), because of floating-point non-associativity in batched GPU inference, variable batch composition, and MoE routing.

**What breaks:**
- Exact string assertions flake, get marked flaky, and are deleted
- A single run tells you little about a change's effect
- Small metric differences are indistinguishable from noise

**The handling:**

**1. Never assert exact output.** Assert properties:
```python
assert "30 days" in answer                    # required fact
assert "90 days" not in answer                # common wrong answer
assert extract_citations(answer) ⊆ valid      # structural
assert schema.model_validate(output)          # structural
```

**2. Run N times and report the distribution.**
```python
results = [evaluate(case) for _ in range(5)]
return {"mean": mean(results), "std": stdev(results), "pass_rate": ...}
```
**Report pass rate across runs, not a binary pass/fail.** "Passes 4/5 times" is honest and actionable; "passed" from a single run is luck.

**3. Set thresholds accounting for variance.** If run-to-run standard deviation is 0.03, a 0.02 improvement is noise. **Require the delta to exceed the noise floor** before treating it as real — and measure the noise floor once, by running the same config twice.

**4. Use enough cases.** Variance falls with dataset size. 30 cases gives roughly a ±0.14 interval on a proportion; 200 gives ±0.05.

**5. Fix what you can.** `temperature=0`, pinned model versions, seeded sampling where the provider supports it, deterministic retrieval, mocked tools.

**6. Separate deterministic from non-deterministic evals** (Q419). Retrieval evals are fully deterministic — run them on every commit with tight thresholds. Generation evals need statistical treatment.

**The answer that shows rigour:** *"I run each generation case five times and compare distributions, because I measured the run-to-run variance first and it was about 3 points — so I don't treat anything under that as a real change."*

---

## 440. Overfitting to evals?

**The failure: your metric improves while the system doesn't.** You've tuned against a fixed set until you're fitting its idiosyncrasies rather than improving general quality (Q435).

**How it happens, and it's usually not deliberate:**
- Iterating on prompts until the eval score rises
- Adding examples that happen to cover eval cases
- Tuning k, thresholds, and chunk sizes against the same set repeatedly
- Selecting the model that scores best on this set

Each individual decision is reasonable. The accumulation is overfitting.

**The defences:**

**1. Hold out a test set you never look at.** Split the golden set: ~70% development (tune freely), ~30% test (evaluate rarely, never tune against). **When development and test scores diverge, you've overfitted** — and that divergence is the only reliable detector.

**2. Refresh continuously from production.** New cases from real failures keep the set representative and dilute anything you've fitted to (Q437).

**3. Guardrail metrics** that must not regress — latency, cost, refusal rate, answer length. Overfitting usually shows up as a trade you didn't intend.

**4. Validate against direct user signals.** Thumbs-down and escalation rates are ground truth; your metrics are proxies (Q435).

**5. Prefer general changes over specific ones.** Adding a reranker generalises. Adding a few-shot example that happens to cover three eval cases does not. **Ask "would this help a query I haven't seen?"** — that question catches most overfitting at the point of decision.

**6. Track how many times you've evaluated against the set.** Each evaluation leaks a little information from it into your decisions. A set you've run 200 times is no longer independent.

**The framing that closes it:** *"A golden set is a measurement instrument, and using it as an optimisation target degrades it. I keep a held-out split and I watch production signals, because the eval set can only tell me I haven't broken the things I thought to test."*

---

*End of Document 10. Next: Document 11 — Model serving (questions 441–469).*
