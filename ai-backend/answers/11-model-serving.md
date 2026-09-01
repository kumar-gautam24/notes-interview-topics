# Document 11 — Model Serving (Questions 441–469)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 441. What is vLLM?

**Definition.** An open-source inference server for large language models, built around **PagedAttention** — a memory management technique that treats the KV cache like virtual memory pages rather than one contiguous allocation.

**Why it exists.** Naive inference servers pre-allocate KV cache for each request's maximum possible length. If a request *might* generate 2,000 tokens, you reserve memory for 2,000 even if it produces 50. Most of that memory sits unused, so you can only fit a handful of concurrent requests on a GPU. **vLLM reports this waste as high as 60–80% in naive implementations.**

**What PagedAttention changes.** KV cache is allocated in fixed-size blocks, on demand, non-contiguously — exactly like OS paging. A request uses only the blocks it actually needs. The result is far higher batch sizes and dramatically better throughput on the same hardware.

**The other features that matter:**
- **Continuous batching** (Q444) — new requests join the running batch immediately
- **Prefix caching** — shared prompt prefixes reuse KV blocks across requests
- **Tensor parallelism** for models too large for one GPU
- **An OpenAI-compatible API**, so it's usually a base-URL change to swap in

**When you'd use it:** self-hosting open-weight models. If you're calling a hosted API, vLLM is irrelevant to you — and being clear about that distinction matters, because Section K only applies if you self-host (Q457).

---

## 442. What is batching?

**Definition.** Processing multiple requests together in a single forward pass through the model.

**Why it produces such large gains — the mechanism is the answer.** LLM decoding is **memory-bandwidth-bound**, not compute-bound. Generating one token requires reading the entire model's weights from GPU memory. For a 7B model in fp16 that's ~14 GB read per token. **Reading those weights takes the same time whether you're generating for one request or sixty** — the matrix multiplication for 60 sequences is barely more expensive than for one.

So batching converts a bandwidth-limited operation into a compute-limited one, and throughput rises close to linearly with batch size until compute becomes the constraint.

**The numbers to have ready:** batch size 1 might give 30 tokens/second. Batch size 32 might give 800 tokens/second aggregate — roughly 27× the throughput at only slightly higher per-request latency.

**The trade-off:** individual requests wait for the batch and share compute, so per-request latency rises modestly while aggregate throughput rises enormously (Q446).

**What limits batch size:** GPU memory for the KV cache. Each sequence's KV cache grows with its length, so long contexts mean smaller batches. **This is exactly why PagedAttention matters** — it lets you fit far more sequences in the same memory by eliminating over-allocation (Q441).

---

## 443. What is a KV cache?

**Definition.** During generation, the model computes key and value tensors for every token in the context. The KV cache stores them so each new token's attention doesn't recompute keys and values for all previous tokens.

**Why it's essential.** Without it, generating token N requires recomputing attention over all N−1 previous tokens — making generation O(n²) in total work. With it, each new token only computes its own K and V and attends against the cached ones, making generation O(n) incrementally.

**The memory cost, and this is the number that governs everything:**
```
KV cache bytes ≈ 2 × layers × kv_heads × head_dim × seq_len × batch × dtype_bytes
```
For a 7B model with a 4,000-token context, that's roughly 2 GB **per sequence**. Multiply by batch size and it quickly exceeds the model weights themselves.

**Which is the key insight to state: at scale, the KV cache — not the model weights — is what limits how many requests you can serve concurrently.** A 14 GB model on an 80 GB GPU leaves 66 GB for KV cache, and that number divided by per-sequence cache size is your maximum batch.

**The optimisations that follow from this:**
- **PagedAttention** — allocate in blocks, no over-reservation (Q441)
- **Prefix caching** — shared system prompts reuse the same blocks across requests
- **Grouped-query attention (GQA)** — fewer KV heads than query heads, cutting cache size several-fold. This is why modern model architectures use it.
- **KV cache quantisation** — store in fp8 or int8

**The connection to prompt caching** (Q277): provider-side prompt caching is KV cache reuse for a stable prefix. Same mechanism, exposed as an API feature.

---

## 444. Continuous batching?

**Definition.** Adding and removing requests from the running batch at every decoding step, rather than processing fixed batches to completion.

**The problem it solves — static batching wastes enormous capacity.** With static batching, you collect 32 requests and run them together until all finish. But generation lengths vary wildly: one request produces 20 tokens, another 2,000. **The whole batch is held hostage by the longest request**, and 31 slots sit idle for most of the run.

**Continuous batching (also called in-flight or iteration-level batching):**
- A request that finishes leaves the batch immediately
- A waiting request joins at the next step
- The batch is re-formed every iteration

**The effect:** GPU utilisation stays near maximum, and reported throughput improvements over static batching are often several-fold — vLLM's original work cites up to 23× against naive serving.

**The secondary benefit: latency.** A new request doesn't wait for the current batch to drain. Under static batching, arriving just after a batch starts means waiting for the longest request in it. Under continuous batching, you join at the next step.

**What makes it possible:** PagedAttention. Non-contiguous block allocation means sequences can enter and leave without defragmenting a contiguous memory region (Q441).

**This is the default in every modern inference server** — vLLM, TGI, TensorRT-LLM. Static batching is a legacy approach, and describing it as current would date you.

---

## 445. GPU memory?

**What occupies GPU memory, in order:**

| Component | Size |
|---|---|
| **Model weights** | `params × bytes_per_param`. 7B in fp16 = 14 GB; in int8 = 7 GB; in int4 = 3.5 GB |
| **KV cache** | Grows with batch × sequence length (Q443) — **usually the binding constraint** |
| **Activations** | Transient, per forward pass |
| **CUDA context / framework overhead** | ~1–2 GB |

**The arithmetic to have ready:**
- 7B fp16 → 14 GB weights. Fits on a 24 GB card with modest KV cache room.
- 70B fp16 → 140 GB. Needs 2× 80 GB GPUs with tensor parallelism, or quantisation.
- 70B int4 → ~35 GB. Fits on one 40 GB card.

**The rule of thumb:** you need roughly `weights × 1.2` before any KV cache, and then KV cache determines your concurrency.

**vLLM's `gpu_memory_utilization`** (default 0.9) sets what fraction of the GPU vLLM claims. Everything not used by weights becomes the KV cache pool. **Raising it increases concurrency; setting it too high causes OOM under load**, and OOM on a GPU typically kills the server rather than failing one request.

**The failure mode to name:** OOM at a specific concurrency level that worked fine in testing. Testing with short prompts and short outputs uses little KV cache; production with long contexts uses far more per sequence. **The capacity you measured is not the capacity you have** unless you tested with representative sequence lengths.

**Mitigation:** set `max_model_len` to bound per-sequence cache, and `max_num_seqs` to bound batch size. Both are hard limits that make OOM impossible at the cost of queuing.

---

## 446. Latency vs throughput?

**The central trade-off in model serving, and they pull in opposite directions.**

- **Latency** — time for one request. What a user experiences.
- **Throughput** — requests or tokens per second across all users. What determines cost per request.

**Why batching creates the tension:** larger batches raise throughput substantially (Q442) but each request shares GPU compute, so per-token generation is slightly slower, and requests may wait to be scheduled.

**The two latency metrics that matter, and conflating them is a mistake:**

| Metric | Meaning | Bound by |
|---|---|---|
| **TTFT** (time to first token) | Prompt processing + scheduling | Prefill compute, queue depth, prompt length |
| **TPOT / ITL** (time per output token) | Steady-state generation speed | Memory bandwidth, batch size |

Total latency ≈ `TTFT + (output_tokens × TPOT)`.

**Why the split matters operationally:** for a streaming interface, TTFT is what the user perceives as responsiveness (Q269). A 200ms TTFT with slower TPOT often feels better than a 2s TTFT with fast generation. **Optimise TTFT for interactive workloads; optimise throughput for batch.**

**The tuning knobs:**
- Batch size — the primary dial
- `max_num_seqs` — caps concurrency, bounding worst-case latency
- **Chunked prefill** — splits long prompt processing across steps so it doesn't stall decoding for everyone else. Important when prompt lengths vary widely.
- Separate deployments for interactive and batch traffic

**That last point is the architectural answer:** rather than finding one configuration that serves both, run two — a low-batch, low-latency deployment for interactive requests and a high-batch deployment for bulk processing. **Different SLOs deserve different infrastructure** (Q463).

---

## 447. Cold start?

**Definition.** The delay between a server instance starting and being able to serve requests.

**Why it's severe for model serving:**

| Phase | Typical duration |
|---|---|
| Container image pull | 1–10 min (images are 5–20 GB) |
| Model weight download | 2–20 min (7B ≈ 14 GB; 70B ≈ 140 GB) |
| Load weights into GPU memory | 30 s – 3 min |
| CUDA graph capture / warmup | 10–60 s |
| **Total** | **often 5–20 minutes** |

**Compare that to a stateless API pod starting in 10 seconds**, and the operational consequences follow directly:

1. **Autoscaling barely works.** By the time a new replica is ready, the traffic spike is over. You cannot scale reactively.
2. **Deploys are slow and risky.** Rolling updates take a long time; rollback is equally slow.
3. **Spot/preemptible instances are painful** — a preemption costs 15 minutes of capacity.

**The mitigations:**
- **Bake weights into the container image** — trades a large image for eliminating the download. Usually worth it.
- **Persistent volume cache** shared across pods, so weights download once per node.
- **Model streaming loaders** (e.g. tensorizer-style) that load directly to GPU without a full disk round trip.
- **Startup probes**, not liveness, during warmup — otherwise Kubernetes kills the pod at 30 seconds for failing a liveness check it was never going to pass (Q85, Q466).
- **Keep a warm pool.** Over-provision and scale on a predictive schedule rather than reactively.
- **Scale on leading indicators** — queue depth rising, not GPU utilisation already saturated.

**The design implication:** with 15-minute cold starts, **queuing is your burst absorber, not autoscaling** (Q465).

---

## 448. Quantization?

**Definition.** Representing model weights (and sometimes activations) in fewer bits than fp16 — typically int8, int4, or fp8.

**Why:** memory and speed. A 70B model in fp16 is 140 GB and needs two 80 GB GPUs. In int4 it's ~35 GB and fits on one 40 GB card. **Since decoding is memory-bandwidth-bound (Q442), reading fewer bytes per token also makes generation faster.**

**The main methods:**

| Method | Bits | Notes |
|---|---|---|
| **GPTQ** | 4 | Post-training, calibration-based, widely supported |
| **AWQ** | 4 | Activation-aware; preserves salient weights. Often better quality than GPTQ |
| **fp8** | 8 | Native support on H100/Ada. Minimal quality loss, good speedup |
| **bitsandbytes (NF4)** | 4 | Easy, slower inference than GPTQ/AWQ |
| **KV cache quantisation** | 8 | Orthogonal — shrinks cache, raising batch size (Q443) |

**The quality cost — be precise rather than dismissive:**
- **fp8 and int8** — usually negligible degradation on most tasks
- **int4** — measurable but often acceptable; degrades more on reasoning, long-context, and multilingual tasks than on simple generation
- **Below int4** — significant degradation

**The critical point for an interview:** **measure the quality cost on your own evals** (Document 10). Published perplexity numbers don't tell you whether int4 breaks *your* extraction task. "We quantised to AWQ int4 and recall@5 on our eval set was unchanged, so we took the 4× memory saving" is an answer; "we use int4 because it's faster" is not.

**The trade-off summary:** quantisation buys memory, throughput, and cheaper hardware, and costs some accuracy plus quantisation time and format-compatibility constraints.

---

# L2 — Engineering

## 449. When self-host vs API?

**The honest default: use the API.** Self-hosting is justified by specific constraints, not by preference, and starting from that position is what shows judgement.

**Self-host when:**

1. **Data cannot leave your infrastructure.** Health records, financial data under residency rules, or contractual restrictions. **This is the strongest and most common justification.**
2. **Volume makes it cheaper.** There's a crossover point (Q450). Below it, APIs win; above it, self-hosting can be substantially cheaper — but only at high, *sustained* utilisation.
3. **You need a fine-tuned or specialised model** that no provider hosts.
4. **Latency requirements** that network round trips can't meet.
5. **No rate limits** — you own the capacity.
6. **Model stability** — providers deprecate and silently update models; you control your version.

**Use the API when:**
- Volume is low or spiky (**self-hosting idle GPUs is expensive**)
- You want frontier model quality — the best models aren't open-weight
- The team is small; GPU ops is a specialised skill
- You need many models
- Time to market matters

**The costs of self-hosting people underestimate:**
- **Idle GPU cost.** A GPU at 10% utilisation costs the same as at 90%. **Utilisation, not raw price, determines whether self-hosting is cheaper.**
- Cold starts breaking autoscaling (Q447)
- On-call for GPU infrastructure
- Model updates, quantisation, and eval work you now own

**The answer to give:** *"Default to the API. Self-host when data residency requires it, or when sustained volume is high enough that the crossover math works — and I'd want the utilisation number before claiming it does."*

---

## 450. Cost model?

**API cost:**
```
cost = (input_tokens × input_rate) + (output_tokens × output_rate)
```
Purely variable. Zero at zero traffic. Output tokens typically cost 3–5× input tokens.

**Self-hosted cost:**
```
cost = GPU_hours × hourly_rate  (fixed, regardless of usage)
cost_per_token = GPU_hourly_rate / (tokens_per_second × 3600)
```
**Fixed. You pay for idle time.**

**The crossover calculation, which is the actual answer:**

An A100 at roughly $2–3/hour serving a 7B model might sustain ~2,000 output tokens/second at high batch. That's ~7.2M tokens/hour, giving a cost around $0.35 per million output tokens — considerably cheaper than most hosted APIs for comparable-size models.

**But that assumes near-full utilisation.** At 20% utilisation the effective cost is 5× higher, and the API wins comfortably.

**So the number that decides it is utilisation, not price.** Say that explicitly:

| Utilisation | Self-hosted effective cost | Verdict |
|---|---|---|
| 90% | Low | Self-host wins clearly |
| 50% | 1.8× | Marginal |
| 20% | 5× | API wins |
| Spiky/bursty | Very high | API wins decisively |

**What the calculation must include beyond GPU hours:** engineering time to build and operate, on-call burden, redundancy (you need N+1 for availability, so add a GPU), storage and network, and the eval work to validate any quantisation.

**The honest framing:** *"Self-hosting is cheaper per token at high sustained utilisation and more expensive at low or spiky utilisation. For a workload with a nightly batch and quiet days, the API is cheaper even at meaningful volume."*

---

## 451. Provider fallback?

**Definition.** Routing to a secondary model or provider when the primary fails.

**Why it's necessary:** provider outages happen, rate limits trigger, and specific models get deprecated. Without fallback, your product's availability equals your provider's.

**Implementation:**
```python
async def generate(messages, **kw):
    for provider in [primary, secondary, tertiary]:
        if breaker[provider].is_open():
            continue                                 # skip known-dead
        try:
            async with asyncio.timeout(provider.timeout):
                return await provider.call(messages, **kw)
        except (RateLimited, ProviderError, TimeoutError) as e:
            breaker[provider].record_failure()
            logger.warning("provider failed, falling back", provider=provider.name)
    raise AllProvidersUnavailable()
```

**The design points:**

1. **Circuit breaker per provider** (Q236), so you fail fast rather than waiting for a timeout on every request against a dead provider.
2. **A model gateway** — one place that owns routing, retries, budgets, and cost accounting. Without it, every service reimplements this badly (Q331).
3. **Normalise the interfaces.** Providers differ in tool-call format, stop reasons, and streaming events. The gateway should present one shape.
4. **Distinguish retryable from terminal.** 429 and 5xx → fall back. A content-policy refusal → do *not* retry on another provider; you'll get the same result and it may be the correct behaviour.

**The trap that catches people:** **fallback changes behaviour, not just availability.** A prompt tuned for one model may perform noticeably worse on another. Structured output formats differ. Tool-calling reliability differs. **Run your eval suite against the fallback model** (Document 10), or you've built a path that silently degrades quality during exactly the incidents you're least able to notice it.

**Track fallback rate as a metric.** A rising rate means your primary is degrading before it fully fails.

---

## 452. Rate limits?

**Providers limit both requests per minute (RPM) and tokens per minute (TPM), and TPM is usually what you hit first** for RAG or agent workloads with large contexts.

**Handling, layered:**

1. **Client-side limiter sized below the quota.** Token bucket, Redis-backed so it holds across all workers (Q189). **Per-worker limiting gives you N× the intended rate** — with 20 workers each allowing 20/sec, you're sending 400/sec (Q249).

2. **Estimate tokens before sending**, and reserve from the bucket. TPM limits need token-aware accounting, not request counting — a 200-token call and a 50,000-token call are not equivalent.

3. **Honour `Retry-After`** on 429. It overrides your backoff calculation.

4. **Exponential backoff with jitter** (Q228).

5. **Queue rather than fail.** For async work, a 429 should lengthen the queue, not error the job.

6. **Per-tenant fairness.** Without it, one tenant consumes the whole quota (Q336).

7. **Batch API** for latency-tolerant work — most providers offer a much cheaper, higher-limit batch endpoint. For nightly classification or bulk embedding, this is a large saving and often overlooked.

**The scaling trap to name:** autoscaling workers on queue depth when the bottleneck is the provider quota. More workers produce more 429s, not more throughput, while costing more. **The worker count should be sized to the rate limit, not to the queue** (Q204).

**Monitoring:** 429 rate, token consumption against quota, and time-to-quota-exhaustion. That last one is the leading indicator — knowing you'll exhaust TPM in 40 minutes at the current rate lets you shed load before you're rejected.

---

## 453. Prompt caching?

**Definition.** The provider caches the KV state for a prefix of your prompt, so repeated requests with the same prefix skip recomputing it. Cache reads are substantially cheaper and faster than fresh input tokens.

**Why it's the highest-leverage cost optimisation available in agent and RAG workloads:** because there's no session, every call resends the full context (Q271). In a 40-turn agent loop the system prompt and tool schemas are resent 40 times. Caching them turns most of that into cheap cache reads.

**The requirement that governs your prompt design: the cached prefix must be byte-identical.** A single changed character invalidates everything from that point onward.

**Which means: order your prompt by volatility.**
```
[ stable ]  system prompt
            tool definitions
            static context / few-shot examples
            ─── cache boundary ───
[ volatile ] retrieved chunks
             conversation history
             user message
```

**The own-goal to name explicitly:** putting a timestamp, a request ID, or a randomly-ordered tool list at the top of the system prompt. It invalidates the cache on every single call, and it's invisible unless you're watching cache hit rates. **Sort tool definitions deterministically; never inject dynamic values into the prefix.**

**Operational details:** caches have a TTL (typically minutes), so low-traffic endpoints may never hit. Some providers charge a small premium for cache *writes*, so caching a prefix used once is a net loss — cache prefixes that are genuinely reused.

**What to measure:** cache hit rate and the fraction of input tokens served from cache. In a well-structured agent loop this should be high, and a drop after a deploy usually means someone put something volatile in the prefix.

---

## 454. Streaming servers?

Covered from the client side at Q269. The serving-side mechanics:

**How it works:** the server emits each token as it's generated, over SSE. With continuous batching, tokens for many concurrent requests are produced each step and dispatched to their respective streams.

**What it costs the server:**
1. **Connections held open** for the full generation. A 60-second generation holds a connection for 60 seconds — for an async server this is cheap, for a thread-per-request server it is not.
2. **Per-connection buffering.** Slow clients accumulate unsent tokens in memory. **With thousands of slow mobile clients this is a real OOM risk** — bound the per-connection buffer and drop connections that exceed it (Q34).
3. **Client disconnect handling.** If you don't detect it, you keep generating and keep paying (Q89).

**The infrastructure requirements that catch people:**
- **Disable proxy buffering** — `X-Accel-Buffering: no`, or nginx holds your chunks and delivers them all at the end, which looks exactly like streaming being broken
- **Load balancer idle timeouts** must exceed your longest generation
- **Keepalive comments** so intermediaries don't close idle connections
- **Graceful shutdown** must handle in-flight streams — either drain them or emit a terminal event so clients reconnect elsewhere (Q84)

**The architectural recommendation for long generations:** don't stream directly from the inference server to the end client. The worker writes tokens to Redis/Postgres; the SSE endpoint reads from there. This decouples client connectivity from generation, so disconnects and API deploys don't kill work in progress (Q315).

---

## 455. Timeouts?

**Every model call needs a timeout, and the reasoning is Q219: without one, a hung provider blocks a worker indefinitely, and enough of those take down your service.**

**The layers:**

| Timeout | Typical | Purpose |
|---|---|---|
| Connect | 2–5 s | Host unreachable — fail fast |
| Time to first token | 10–30 s | Provider overloaded or queueing |
| Inter-token (stall detection) | 10–20 s | Stream stopped mid-generation |
| Total request | 60–300 s | Absolute bound |

**The inter-token timeout is the one people miss.** A stream that produces tokens then stalls will sit under a total timeout for the full duration. Detecting "no token for 15 seconds" catches it far sooner.

**Budget downward** (Q219): your timeout to the provider must be shorter than your caller's timeout to you, with room for a retry.

**Setting the values:** from measured p99, not round numbers. A timeout below p99 causes spurious failures on legitimately slow generations, which then get retried, which costs money and adds load.

**The ambiguity that follows:** a timed-out generation may have completed on the provider's side. You were billed for it. **You cannot know**, and if the request had side effects (a tool call in an agent), retrying duplicates them (Q286).

**Streaming changes the calculus favourably:** with streaming you get tokens continuously, so you can distinguish "slow" from "dead" precisely, and you can abandon a generation partway rather than waiting for a total timeout. That's an underrated operational argument for streaming beyond UX.

---

## 456. Load balancing GPUs?

**GPU load balancing differs from stateless HTTP balancing in ways that make naive strategies actively harmful.**

**Why round-robin is wrong:** requests have wildly different costs. One is 100 input tokens generating 20; another is 50,000 input tokens generating 2,000. Round-robin sends the expensive one to a busy replica while an idle one waits.

**What actually works:**

1. **Least-outstanding-requests** — route to the replica with the fewest in-flight requests. Simple and much better than round-robin.
2. **Queue-depth-aware routing** — route on the inference server's reported pending queue. Best available signal.
3. **Prefix-aware routing** — route requests sharing a prompt prefix to the same replica so its KV prefix cache hits (Q443). **This can be a large win for RAG or agent workloads with a common system prompt**, and it's the GPU-specific strategy worth naming.
4. **Session affinity** for multi-turn conversations, for the same reason.

**What to avoid:**
- **Round-robin** — ignores heterogeneous cost
- **CPU-based health signals** — GPU utilisation is what matters and CPU tells you nothing
- **Aggressive liveness probes** — a busy GPU responds slowly; killing it makes things worse (Q466)

**The architectural alternative that's usually simpler: put a queue in front.** Rather than balancing across replicas, have replicas pull from a shared queue. Each takes work when it has capacity, so load balances itself with no routing logic. **This is the right design for anything asynchronous** (Q465), and it also solves the cold-start problem by absorbing bursts.

**Kubernetes specifics:** GPUs are exclusive resources — a pod requests `nvidia.com/gpu: 1` and owns it. So replica count is bounded by physical GPUs, and autoscaling can't exceed them regardless of what HPA wants.

---

## 457. Why did you choose self-hosted?

> **Substitute your real reasoning.** The defensible answers, and the indefensible ones:

**Defensible justifications:**

1. **Data residency or contractual restriction.** "Health/financial data cannot leave our infrastructure." **This is the strongest answer** and requires no cost analysis to defend.
2. **A fine-tuned model** no provider hosts.
3. **Measured cost at measured utilisation** — with the crossover arithmetic (Q450) and a utilisation figure.
4. **Latency requirement** the network round trip can't meet.
5. **Provider stability** — no silent model updates, no deprecation timeline you don't control.

**Indefensible answers, and an interviewer is checking for these:**
- "It's cheaper" — without a utilisation number. At low utilisation it isn't (Q450).
- "We wanted control" — vague.
- "To avoid rate limits" — you've traded a rate limit for a capacity ceiling you now operate.

**What a strong answer includes:** the constraint that forced it, the cost comparison with actual numbers, the quality validation (did you run your evals against the self-hosted model and the quantisation you chose?), and **the costs you accepted** — cold starts breaking autoscaling, GPU on-call, the eval work to validate quantisation.

**The self-aware closing:** *"If the residency constraint went away, I'd re-evaluate. At our current utilisation the cost argument alone wouldn't justify the operational burden."*

**If you're honestly not self-hosting:** say so. *"We use hosted APIs — the volume doesn't justify GPU infrastructure and we have no residency constraint. I know the vLLM architecture and where the crossover is, but I'd be inventing experience if I claimed to have operated it."* **That answer is much stronger than a fabricated one**, and Q457 is often asked precisely to see whether you'll overclaim.

---

# L3 — Production failure

## 458. GPU OOM?

**What it looks like:** `CUDA out of memory`, and critically — **it usually kills the server process, not just the one request.** Every in-flight generation dies. That's what makes it more severe than an ordinary resource exhaustion.

**The causes:**

1. **Longer sequences than tested.** KV cache scales with sequence length (Q443). Testing with 500-token prompts and deploying against 8,000-token RAG contexts multiplies per-sequence cache 16×.
2. **Higher concurrency** than the memory budget allows.
3. **`gpu_memory_utilization` set too high**, leaving no headroom.
4. **Memory fragmentation** — less of an issue with PagedAttention, but real in naive servers.
5. **Another process on the same GPU** — a monitoring tool, a second container.

**The fixes, in order:**
```python
# hard bounds that make OOM structurally impossible
--max-model-len 8192          # caps per-sequence KV cache
--max-num-seqs 64             # caps batch size
--gpu-memory-utilization 0.85 # leaves headroom
```
**`max_model_len` is the most important**, because it converts an unbounded risk into a bounded one — long requests are rejected rather than accepted and then killing the server.

Then: quantise (Q448), enable KV cache quantisation, or use a bigger GPU / tensor parallelism.

**The prevention that matters:** **load-test at your p99 sequence length, not your median.** Capacity measured with short prompts is not capacity. This is the single most common cause of "it worked in staging."

**Operationally:** the process restart is a cold start (Q447), so a single OOM costs minutes of capacity. Set the bounds conservatively — rejecting a few oversized requests is far cheaper than a 15-minute outage.

---

## 459. Latency spike?

**Diagnose by which latency component moved** — TTFT or TPOT (Q446). They have different causes.

**TTFT spiked:**
- **Queue depth rising** — more requests than capacity. Check pending queue length.
- **Longer prompts** — prefill is roughly linear in input length. A change that increased retrieved chunks raises TTFT for everyone.
- **Prefill blocking decode** — a very long prompt stalls the batch. **Fix with chunked prefill**, which splits prefill across steps.
- **Cold start** — a replica restarted (Q447).
- **Prompt cache miss rate rose** — someone put a volatile value in the prefix (Q453).

**TPOT spiked:**
- **Larger batch size** — more sequences sharing bandwidth. This is the throughput/latency trade working as designed (Q446).
- **Longer sequences in the batch** — attention cost grows with context length.
- **GPU thermal throttling** — check clock speeds; real in dense deployments.
- **Memory pressure** causing KV cache eviction and recomputation.

**Both:**
- Replica lost, remaining ones overloaded
- Provider-side degradation (if using an API)
- Network

**The instrumentation you need:** TTFT and TPOT as separate metrics, plus queue depth, batch size, and GPU utilisation. **Without the TTFT/TPOT split, a latency alert has eight possible causes and you're guessing.**

**The immediate mitigations:** shed load (return 429 rather than queueing indefinitely), lower `max_num_seqs` to cap batch size and bound worst-case latency, and route interactive traffic away from the batch deployment (Q463).

---

## 460. Model version change?

**The failure: the provider updates a model behind a stable name, and your system's behaviour changes with no deploy on your side.**

**What breaks:**
- Prompts tuned for the old version underperform
- Structured output formatting shifts subtly
- Tool-calling reliability changes
- Refusal behaviour changes — previously-answered queries start being declined
- Token counts and therefore costs shift
- Latency characteristics change

**And you get no notification.** The first signal is a metric moving.

**Prevention:**

1. **Pin explicit versions.** Use dated or versioned model identifiers, never a floating alias. **This is the single most important control** and it costs nothing.
2. **Record the model version on every run** (Q327), so you can correlate a quality change with a version change.
3. **Run the eval suite against a new version before adopting it** (Q433). A model upgrade is a behaviour change and deserves the same gate as a prompt change.
4. **Canary** — route a percentage to the new version and compare metrics before switching.
5. **Keep the old version available** for rollback, and know the deprecation date.

**Detection when you couldn't prevent it:** monitor output-length distribution, refusal rate, citation validity, and cost per request. **These are free, computed on every response, and they move when the model does** (Q438).

**For self-hosted models this is fully under your control** — which is a legitimate argument in the self-host decision (Q449) and worth mentioning there.

**The framing:** *"A model version is a dependency version. Floating it in production is the same mistake as running `npm install` without a lockfile — except the failure is silent and probabilistic rather than a build error."*

---

## 461. Provider outage?

**Handling, layered:**

**1. Detect fast.** A circuit breaker per provider (Q236) means you fail in milliseconds rather than waiting for a timeout on every request. **Without it, every worker sits in a 30-second timeout and your service goes down because of someone else's outage.**

**2. Fall back to a secondary provider** (Q451) — with the caveat that quality differs and your evals should have covered it.

**3. Degrade rather than fail.** Options in order of preference:
- Serve cached responses for repeated queries
- Return retrieved documents *without* generation — for a RAG product this is a genuinely useful degraded mode: the user gets the source clauses without the summary
- Queue the work for later and tell the user
- Fail with a clear message and a retry hint

**That second option is worth calling out.** For a document-grounded product, "here are the three most relevant passages from your policy" is a real answer even when generation is unavailable. Most teams don't build it and it's cheap.

**4. Queue async work** rather than failing it. A background job should wait out the outage.

**5. Shed load at the edge.** During an outage, incoming requests pile up. Return 503 with `Retry-After` rather than accumulating an unbounded queue (Q237).

**6. Status communication.** A status page and an in-product banner. Users tolerate outages far better when told.

**The design principle:** **your availability is bounded by your dependencies unless you build degradation.** Five nines from a provider with three nines is impossible without a fallback path. **Decide per feature what "degraded" means**, and that's a product decision as much as a technical one (Q88).

---

## 462. Cost spike?

**Immediate response:**
1. **Check the kill switch works** and use it if the rate is severe (Q338).
2. **Identify the dimension** — which tenant, which endpoint, which model, which agent.
3. **Stop the bleeding** — disable the offending path or tenant.

**The causes, most likely first:**

| Cause | Signal |
|---|---|
| **Agent loop not terminating** | Turns-per-run distribution shifted (Q306) |
| **Prompt cache invalidated** | Cache hit rate dropped; input token cost jumped with no traffic change |
| **Retrieval returning more chunks** | Input tokens per request rose |
| **A prompt change made outputs longer** | Output tokens per request rose |
| **Retry storm** | Request count rose with success rate flat or falling (Q229) |
| **Routing sent everything to the expensive model** | Model mix shifted |
| **One tenant's traffic exploded** | Per-tenant spend |
| **A bug re-processing historical data** | Volume spike with no user activity |

**The prompt-cache one deserves emphasis** because it's invisible: someone adds a timestamp to the system prompt, cache hit rate goes from 85% to 0, and input costs multiply overnight with identical traffic (Q453).

**Prevention — the controls that should already exist:**
- Per-tenant daily budget with a circuit breaker (Q336)
- Per-run spend cap (Q338)
- Global spend alert and kill switch
- **Alert on cost per request**, not just total cost. Total cost rising with traffic is normal; cost *per request* rising is a bug.

**That last distinction is the one to state:** total spend is a business metric, cost-per-request is an engineering metric, and only the second one tells you something broke.

---

## 463. Batch vs interactive?

**Two workloads with opposite requirements, and the answer is that they should not share infrastructure.**

| | Interactive | Batch |
|---|---|---|
| Latency requirement | Low TTFT, seconds total | Minutes to hours acceptable |
| Batch size | Small — bounded latency | Large — maximise throughput |
| Scaling signal | Request rate, p99 latency | Queue depth |
| Cost sensitivity | Lower — user waiting | **Higher — optimise per token** |
| Traffic pattern | Diurnal, spiky | Schedulable |

**Why sharing hurts both:** a large batch job raises batch size, which raises TPOT for interactive users. Conversely, keeping batch size small for interactive latency wastes throughput on the batch work.

**The separations:**

1. **Separate deployments** with different `max_num_seqs` — small for interactive, large for batch.
2. **Separate queues** so batch work can't head-of-line-block interactive requests (Q204).
3. **Provider batch APIs** for the batch tier — most providers offer a much cheaper, higher-limit asynchronous batch endpoint with a turnaround of hours. **For nightly classification, bulk embedding, or backfills this is a large saving and consistently overlooked.**
4. **Schedule batch work off-peak**, using capacity that would otherwise idle.
5. **Cheaper or quantised models** for batch, where latency doesn't matter and you can afford the eval work to validate quality.

**The framing that lands:** *"Batch and interactive have opposite optimisation targets. Running them on the same deployment means picking a configuration that's wrong for both — so I'd separate them, and route batch to the provider's batch API where the discount is substantial."*

---

## 464. Multi-tenant serving?

**The requirements:** fair capacity allocation, cost attribution, isolation from noisy neighbours, and per-tenant limits.

**The controls:**

1. **Per-tenant rate limits** — RPM and TPM, Redis-backed so they hold across all workers (Q452). Without this, one tenant consumes your entire provider quota and everyone else gets 429s.

2. **Per-tenant spend budgets** with a circuit breaker (Q336). **This is an availability control, not a billing feature** — a tenant with a buggy integration can otherwise exhaust your quota and your budget overnight.

3. **Separate queues by tenant tier**, so a large customer's burst doesn't starve everyone (head-of-line blocking, Q204).

4. **Fair scheduling.** Round-robin across tenant queues rather than FIFO across all work, so a tenant enqueueing 10,000 items doesn't monopolise the workers.

5. **Cost attribution per tenant per request** — recorded, not estimated. This is what makes pricing and capacity conversations concrete.

6. **Reserved capacity for premium tiers** — a dedicated deployment or a guaranteed share.

**The data isolation concerns** are Document 07's (Q336): no cross-tenant context leakage, no shared caches without tenant in the key (Q391), and no prompt-cache prefix sharing that could expose one tenant's content to another.

**That last one is a genuine and non-obvious risk with self-hosted prefix caching** — if a shared prefix cache is keyed only on content, and tenants share a deployment, you must ensure the *tenant-specific* portion of the prompt is never in the cached prefix. Structure prompts so the cached prefix is tenant-independent.

**The metric to watch:** spend and token consumption per tenant, plotted over time. Order-of-magnitude variation between tenants is normal; a step change in one is either growth or a bug.

---

# L4 — System design

## 465. Design an inference platform.

**Requirements:** multiple models, interactive and batch workloads, multi-tenant, cost control, fallback, observability.

**Architecture:**
```
Clients
   │
Model Gateway ──── routing, auth, rate limits, budgets, fallback, caching,
   │                cost accounting, normalised interface
   ├──▶ Hosted provider APIs (primary for most traffic)
   ├──▶ Self-hosted vLLM cluster (interactive: small batch, low latency)
   ├──▶ Self-hosted vLLM cluster (batch: large batch, high throughput)
   └──▶ Provider batch API (async bulk work)

Async path: request → queue → workers → gateway → results store → SSE
```

**The gateway is the core design decision.** One component owning:
- Provider routing and fallback (Q451)
- Rate limiting, shared across all callers (Q452)
- Per-tenant budgets and kill switches (Q464)
- Cost accounting per request, tenant, and model
- Normalised request/response shape across providers
- Prompt cache structuring (Q453)
- Metrics: TTFT, TPOT, tokens, cost, error rates by provider

**Without it, every service reimplements retry, budget, and fallback logic — badly and inconsistently.** That's the argument.

**The queue in front of self-hosted capacity** (Q456) — replicas pull work rather than being routed to. This self-balances, absorbs bursts that cold starts can't (Q447), and gives you a natural scaling signal.

**Separate deployments for interactive and batch** (Q463).

**What I'd cut at small scale:** the self-hosted clusters entirely. A gateway in front of hosted APIs, with fallback and budgets, delivers most of the value at a fraction of the operational cost. **Add GPU infrastructure when a specific constraint forces it** (Q449).

---

## 466. Autoscaling model servers?

**The core difficulty: cold starts of 5–20 minutes make reactive autoscaling nearly useless** (Q447). By the time a replica is ready, the spike is over.

**What to do instead:**

1. **Queue as the burst absorber.** Asynchronous work queues rather than failing; the queue depth is your signal *and* your buffer. **This is the primary answer** — for anything not interactive, queuing beats scaling.

2. **Predictive scaling.** Scale on schedule for known diurnal patterns rather than reacting to load.

3. **Scale on leading indicators** — queue depth and its rate of change, not GPU utilisation which is already saturated by the time it's high.

4. **Warm pool.** Over-provision by N replicas. Expensive but the only way to absorb genuine interactive bursts.

5. **Aggressive scale-up, conservative scale-down.** Adding a replica costs 15 minutes; removing one and needing it back costs 15 minutes. **Asymmetric thresholds** — scale up quickly, scale down slowly.

6. **Hybrid: burst to hosted APIs.** Self-hosted for baseline, spill over to a provider API during spikes. **This is the elegant answer** — you get the cost benefit of self-hosting at baseline utilisation and the elasticity of an API for peaks.

**The probes, which are where people go wrong:**
```yaml
startupProbe:                     # allows a long warmup
  failureThreshold: 60
  periodSeconds: 20               # up to 20 minutes
livenessProbe:                    # only after startup succeeds
  periodSeconds: 30
  timeoutSeconds: 10              # generous — a busy GPU responds slowly
readinessProbe:
  periodSeconds: 5
```
**Without a startup probe, liveness kills the pod at 30 seconds for failing a check it was never going to pass**, and you get a crash-loop that looks like a broken image (Q85).

**Kubernetes constraint:** replicas are bounded by physical GPUs. HPA cannot conjure hardware.

---

## 467. Model routing?

**Definition.** Selecting which model handles each request based on its characteristics.

**Why it's usually the single largest cost win available** (Q290): most requests don't need your strongest model. Routing the simple 70% to a cheaper, faster model can cut costs several-fold with negligible quality loss — **but only if you can prove the loss is negligible**, which requires evals.

**Routing strategies:**

1. **Task-based** — the simplest and most reliable. Classification and extraction to a small model; synthesis and reasoning to a large one. No classifier needed; the code path already knows what it's doing.
2. **Classifier-based** — a cheap model judges difficulty first. Adds latency and a failure mode.
3. **Cascade** — try the cheap model, evaluate confidence, escalate if low. Effective, but you pay twice on escalation.
4. **Tenant tier** — premium customers get the better model.
5. **Load-based** — route to the secondary when the primary is saturated.

**The prerequisite: an eval set per route.** "Is the cheap model adequate for extraction?" is an empirical question with a number attached (Document 10). **Routing without evals is guessing about quality to save money**, which is the wrong trade to make blind.

**The implementation detail:** routing lives in the gateway (Q465), configured rather than coded, so route changes don't require deploys and can be canaried.

**What to measure:** quality per route (not aggregate — aggregate hides that the cheap route degraded), cost per route, escalation rate for cascades, and the traffic mix. A shift in the mix changes your cost profile without anything breaking.

**The trap:** routing on a proxy for difficulty (query length, keyword presence) that doesn't correlate with actual difficulty. Validate the router itself against labelled examples, not just the models it routes to.

---

## 468. Failover strategy?

**Layered, from cheapest to most drastic:**

**1. Retry the same provider.** Transient 5xx and timeouts, with backoff and jitter, capped at 2–3 attempts (Q220).

**2. Fall back to a different model at the same provider.** Often a rate limit is per-model, so a sibling model has capacity.

**3. Fall back to a different provider** (Q451). Requires normalised interfaces and evals against the fallback.

**4. Fall back to self-hosted**, or vice versa. The hybrid direction is genuinely useful — burst to the API when your GPUs are saturated (Q466).

**5. Serve degraded** — cached response, retrieval without generation, partial results (Q461).

**6. Queue for later** — for async work, wait out the outage.

**7. Fail with a clear message** and a retry hint.

**The controls throughout:** a circuit breaker per provider so you skip known-dead paths instantly (Q236), and a per-provider health signal driving the routing decision.

**The two things people get wrong:**

1. **Not testing the fallback path.** A fallback that's never exercised doesn't work. **Run game days** — deliberately break the primary in staging and verify the fallback carries the load at acceptable quality.

2. **Not evaluating fallback quality.** The fallback model may produce different structured output, worse tool calls, or different refusal behaviour. **You'll be running on it during an incident, which is the worst moment to discover it degrades your product** (Q451).

**The metric:** fallback rate. A rising rate is a leading indicator that your primary is degrading before it fully fails, and it's free to track.

---

## 469. Cost optimization at scale?

**In order of leverage, with the reasoning for each:**

**1. Model routing** (Q467). Usually the largest single win — often 3–5×. Requires evals to do responsibly.

**2. Prompt caching** (Q453). Free latency *and* cost improvement with zero quality cost, provided you structure prompts by volatility. In agent loops this is enormous because the stable prefix is resent every turn.

**3. Retrieve fewer, better chunks** (Q363). **Cheaper, faster, and more accurate simultaneously** — the rare optimisation with no trade-off. Reranking 30 candidates down to 5 cuts input tokens ~4×.

**4. Reduce output tokens.** Output typically costs 3–5× input. Instruct concision, set `max_tokens` sensibly, and avoid asking for verbose reasoning where it isn't needed.

**5. Batch API** for latency-tolerant work (Q463). Substantial provider discounts for asynchronous bulk processing.

**6. Semantic caching** (Q391) — largest possible saving on repeated queries, with a real correctness risk that requires calibration.

**7. Embedding cache** — never embed the same text twice (Q97). Free and deterministic.

**8. Self-hosting at high sustained utilisation** (Q450) — only with the utilisation number to back it.

**9. Quantisation** if self-hosting, with eval validation (Q448).

**10. Shorter system prompts.** Charged on every request; a 2,000-token system prompt across 10M requests is real money.

**The measurement discipline that makes any of this credible:** track **cost per successful request**, decomposed by input tokens, output tokens, and model. Total cost tells you nothing — it rises with traffic. Cost per successful request is the engineering metric, and the "successful" qualifier matters because failed and refused requests still cost money.

**The closing point:** every item above except #6 is either free or evaluated. **Cost optimisation in LLM systems is mostly not about paying less per token — it's about not sending tokens you didn't need to send.**

---

*End of Document 11. Next: Document 12 — Docker / Kubernetes / AWS (questions 470–504).*
