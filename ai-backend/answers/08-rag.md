# Document 08 — RAG (Questions 340–393)

Answer format: **definition → why → implementation → failure → trade-off → real example**

> **Note on Section H.** Questions 371–380 and 590/599 ask for *measurements*, not descriptions. The answers below give the correct method and the numbers you should be able to produce — but the numbers themselves must be yours, from your corpus. "We measured recall@5 at 0.82 on a 30-question golden set" is an answer; "we evaluated retrieval quality" is not, and the follow-up will expose it.

---

# L1 — Foundation

## 340. What is RAG?

**Definition.** Retrieval-Augmented Generation — retrieve relevant documents from an external corpus at query time, put them in the model's context, and generate an answer grounded in them.

**The pipeline:**
```
Query → embed → search index → top-k chunks → rerank → assemble prompt
      → model generates with citations → validate grounding → respond
```

**Why it exists.** A model's knowledge is frozen at training time, doesn't include your private data, and can't be cited or updated. RAG addresses all three: current information, proprietary content, and attributable sources.

**The property that matters most: attribution.** A RAG answer can point at the document it came from. For an insurance, legal, or medical product, "here's the answer and here's the clause it's based on" is a fundamentally different product from "here's an answer, trust me." That's usually the real business justification, more than knowledge coverage.

**What RAG does not fix:**
- **Reasoning failures.** If the model reasons badly over correct context, retrieval didn't help.
- **Hallucination when retrieval fails.** The model will still answer confidently from an empty or irrelevant context unless you explicitly instruct refusal and *test* it (Q369).
- **Questions the corpus can't answer.**

**The framing worth having ready:** RAG is a search problem with a generation step attached. **Most RAG failures are retrieval failures**, and most teams spend their effort on prompting instead of on retrieval quality. That inversion is the single most common mistake in the field.

---

## 341. Why not put everything in the prompt?

**Four independent reasons, and the quality one is the least obvious and most important:**

**1. It doesn't fit.** A corpus of 50,000 documents is hundreds of millions of tokens. No context window holds it.

**2. Cost.** You pay per input token on every call (Q277). Even a 200k-token context, if you could fill it, costs orders of magnitude more per query than retrieving 5k tokens of relevant content — and in an agent loop it's resent every turn (Q271).

**3. Latency.** Prefill is roughly linear in input length. A 200k-token prompt has a materially worse time-to-first-token than a 5k one.

**4. Quality degrades — the counter-intuitive one.** The "lost in the middle" effect: models attend reliably to the beginning and end of long contexts and less reliably to the middle. **A 200k context window does not mean 200k tokens are used equally well.** Adding irrelevant content actively hurts — it's not neutral filler, it's distraction that competes for attention with the passage that actually answers the question.

**The consequence people get backwards:** more retrieved context is not monotonically better. Ten well-ranked chunks routinely beat fifty mediocre ones — cheaper, faster, *and* more accurate. This is why reranking is the highest-leverage single addition to a naive RAG pipeline (Q363).

**When long-context *is* the right answer:** a single document that must be reasoned over holistically — a 60-page contract where the answer depends on interactions between distant clauses. Chunking destroys that. **Long-context and RAG are complementary**, not competing; use retrieval to select the right document, then long-context to reason over it.

---

## 342. What is chunking?

**Definition.** Splitting documents into smaller pieces that are embedded and indexed independently.

**Why it's necessary:**
1. Embedding models have input limits (typically 512–8,192 tokens).
2. **Retrieval precision.** Embedding a whole 50-page document produces one vector averaging everything in it — semantically mushy and matching nothing well. A chunk about one topic produces a vector that actually represents that topic.
3. **Context budget.** You retrieve chunks, not documents, so you can fit several relevant passages instead of one large mostly-irrelevant one.

**The core tension — and this is the whole difficulty:**
- **Too small** → the chunk lacks the context needed to be understood or to answer. "The limit is ₹5 lakh" is useless without knowing which policy and which coverage.
- **Too large** → the embedding averages multiple topics, diluting the signal, and you waste context on irrelevant text.

**The strategies** (detail at Q351):
- Fixed-size with overlap — simple baseline
- Recursive character splitting on separators — respects paragraph and sentence boundaries
- Structure-aware — split on headings, sections, clauses
- Semantic — split where embedding similarity between adjacent sentences drops
- Sentence-window / parent-document — embed small, retrieve large (Q384)

**The rule that matters more than the size:** **respect document structure.** A chunk that splits mid-sentence or mid-table is damaged. Structure-aware chunking on a well-structured corpus beats any amount of fixed-size tuning.

**Failure.** Chunking a table across boundaries, so the header row is in one chunk and the data in another. Both become meaningless. Tables, code blocks, and lists need to be kept intact or handled specially.

---

## 343. Embedding model?

**Definition.** A model that maps text to a fixed-length dense vector where semantic similarity corresponds to geometric proximity (Q272).

**What to consider when choosing:**

| Factor | Why |
|---|---|
| **Retrieval quality on YOUR data** | MTEB leaderboard rank is a weak proxy; domain-specific performance varies enormously |
| **Dimensionality** | Storage and search cost. 768 vs 3,072 is a 4× difference |
| **Max input length** | Determines your chunk ceiling |
| **Multilingual support** | Critical for Indian-language corpora |
| **Cost** | Per-token, and you embed the entire corpus plus every query |
| **Self-hosted vs API** | Data residency, latency, cost at volume |
| **Asymmetric support** | Some models have separate query and document encodings — meaningfully better for retrieval |

**The properties that constrain your architecture:**
- **Deterministic** — cache aggressively on `hash(text) + model_version` (Q97). Never compute the same embedding twice.
- **Model-specific** — vectors from different models are incomparable even at the same dimensionality.
- **Changing the model requires re-embedding everything** (Q357). This is the migration nobody plans for.

**The evaluation point that separates a real answer from a recited one:** **choose the embedding model by measuring recall on your own labelled set**, not by leaderboard position. A model that tops MTEB on general English can underperform a smaller one on insurance policy language or Hinglish queries. This is a 30-minute experiment once you have a golden set, and almost nobody does it.

**The Indian-language angle worth raising:** most embedding models are English-dominated. For Hindi or mixed Hinglish content, evaluate multilingual models specifically — the quality gap can be dramatic and it won't show up in any leaderboard you'd think to check.

---

## 344. Vector store?

**Definition.** A database that stores embeddings and supports efficient nearest-neighbour search over them.

**The options and the honest trade-off:**

| | pgvector | Dedicated (Pinecone, Weaviate, Qdrant, Milvus) |
|---|---|---|
| Operational cost | **None extra — you already run Postgres** | Another stateful system |
| Transactional consistency with your data | **Yes** | No — dual-write problem (Q245) |
| Filtering + joins | Full SQL | Limited metadata filtering |
| Scale ceiling | Millions of vectors comfortably | Billions |
| Specialised features | Fewer | Hybrid search, multi-tenancy, sharding built in |

**The argument for pgvector, which is the one to make:** your chunks have metadata — tenant, document ID, permissions, date, status — and you need to filter on it. In pgvector that's a `WHERE` clause in the same query, with the same transactional guarantees as the rest of your data. In a separate vector database it's a dual-write problem plus limited filtering, and now you have two systems that can disagree about what documents exist.

**When a dedicated store earns its cost:** hundreds of millions of vectors, or you need features pgvector lacks and can't approximate. **Below roughly 10 million vectors, pgvector is usually the right answer**, and reaching for a specialised database first is premature (same reasoning as Q215 for Kafka).

**The thing to say if asked why you chose one:** "The chunk metadata and the permissions model live in Postgres, so putting the vectors anywhere else means keeping two systems in sync for no benefit at our scale."

---

## 345. Similarity search?

**Definition.** Given a query vector, find the k stored vectors closest to it under a distance metric — cosine, inner product, or L2 (Q274).

**Exact vs approximate:**
- **Exact (flat / brute force)** — compare against every vector. Perfect recall, O(n) per query. Fine up to tens of thousands of vectors.
- **Approximate (ANN)** — HNSW or IVFFlat. Sub-linear query time with a recall trade-off you control via parameters (Q399–401).

**The query in pgvector:**
```sql
SELECT id, content, 1 - (embedding <=> $1) AS similarity
FROM chunks
WHERE tenant_id = $2 AND deleted_at IS NULL
ORDER BY embedding <=> $1
LIMIT 20;
```
`<=>` is cosine distance, `<#>` negative inner product, `<->` L2. **The ordering must use the same operator as the index**, or the index is ignored and you get a sequential scan — a common and silent performance bug.

**The critical interaction: filtering plus ANN.** A `WHERE tenant_id = $2` combined with an HNSW index has a real failure mode — the index traverses the graph and *then* filters, so if the tenant's documents are a small fraction of the corpus, you can get far fewer than k results, or none. This is one of the genuinely hard problems in vector search (Q414). Mitigations: partitioned indexes per tenant, pre-filtering into a subset, or over-fetching then filtering.

**What similarity search does not give you: relevance.** Similar is not the same as answers-the-question. A chunk about "Python exception performance" is highly similar to "how do I handle Python exceptions" and useless for it. This is precisely why reranking exists (Q362).

---

## 346. Top-k?

**Definition.** The number of chunks retrieved and passed to the model.

**The trade-off:**
- **Too low** → the answer isn't in the context. Recall failure. **The most damaging error**, because the model then either refuses or hallucinates.
- **Too high** → cost, latency, and the lost-in-the-middle quality degradation (Q341).

**The two-stage pattern that resolves it, and this is the answer:**
```
retrieve k=20–50 (favour recall)  →  rerank  →  keep top 3–8 (favour precision)
```
Cast a wide net cheaply with vector search, then apply an expensive accurate model to a small candidate set. **You get high recall AND high precision**, which a single k cannot deliver (Q363).

**How to actually pick k.** Not by intuition — measure. Build a golden set, compute recall@k for k = 5, 10, 20, 50, and find where the curve flattens. That's your retrieval k. Then measure end-to-end answer quality across final-context sizes of 3, 5, 8, 10 and pick where *that* curve flattens. **Two different k values, two different measurements.**

**Adaptive k is a real improvement:** use a similarity threshold rather than a fixed count, so a query with two strongly-matching chunks gets two, and a broad query gets more. Requires a calibrated threshold (Q370).

**Failure.** Setting k=3 because it seemed reasonable, and never discovering that recall@3 is 0.61 while recall@10 is 0.89. That's a third of your queries silently failing to have the answer in context — and no amount of prompt engineering fixes it.

---

## 347. Reranking?

**Definition.** A second-stage model that scores query-document pairs directly and reorders the candidates from first-stage retrieval.

**Why it works better than embeddings.** A **bi-encoder** (the embedding model) encodes query and document *independently*, so the document vector is computed without ever seeing the query. A **cross-encoder** (the reranker) processes query and document *together*, with full attention between them — so it can judge whether this passage actually answers this question, not merely whether they're about the same topic.

That's the whole distinction, and it's why reranking gives a large quality jump: embeddings measure topical similarity, rerankers measure relevance.

**Why not use a cross-encoder for everything:** it's O(n) in corpus size — you'd score every document per query. Bi-encoders allow pre-computation and indexing. **Retrieve cheaply, rerank expensively, on a small candidate set.**

**Implementation:**
```python
candidates = await vector_search(query, k=30)
scores = await reranker.score([(query, c.content) for c in candidates])
top = [c for _, c in sorted(zip(scores, candidates), reverse=True)[:5]]
```

**The options:** hosted rerankers (Cohere Rerank, Voyage), open-source cross-encoders (BGE-reranker, mxbai-rerank), or an LLM prompted to score relevance (accurate, slow, expensive).

**The claim to make carefully:** reranking is typically the single highest-value addition to a naive RAG pipeline — but **quantify it on your data**. "Adding a reranker moved recall@5 from 0.74 to 0.88 on our 30-question set" is an answer. "Reranking improves quality" is a claim anyone can make.

**The cost:** 50–200ms added latency and a per-query charge. Nearly always worth it, and partially offset because you pass *fewer* chunks to the generator (Q363).

---

## 348. Hybrid search?

**Definition.** Combining lexical search (BM25/full-text) with vector search, and fusing the results.

**Why both are needed — they fail in opposite directions:**

| | Vector search | Lexical (BM25) |
|---|---|---|
| Paraphrases, synonyms | **Strong** | Weak |
| Exact terms, IDs, codes | **Weak** | Strong |
| Rare/technical terms | Weak (poorly represented in embeddings) | Strong |
| Typos | Moderate | Weak |
| Conceptual queries | Strong | Weak |

**The failure that makes the case concretely:** a user searches for policy number `LIC-2024-88371`. Vector search returns semantically similar policies — completely wrong. BM25 returns the exact match instantly. Conversely, "what happens if I miss a premium payment" finds nothing lexically but retrieves the grace-period clause semantically.

**Fusion via Reciprocal Rank Fusion (RRF)** — the standard method:
```
score(d) = Σ over rankers  1 / (k + rank_r(d))        # k ≈ 60
```
RRF uses *ranks*, not scores, which is the key property: BM25 scores and cosine similarities are on incomparable scales, and normalising them is fragile. Ranks are directly comparable, so RRF needs no tuning and is remarkably robust.

**In PostgreSQL you get both in one system:**
```sql
WITH vec AS (SELECT id, row_number() OVER (ORDER BY embedding <=> $1) rank
             FROM chunks WHERE tenant_id=$3 ORDER BY embedding <=> $1 LIMIT 50),
     lex AS (SELECT id, row_number() OVER (ORDER BY ts_rank_cd(tsv, q) DESC) rank
             FROM chunks, plainto_tsquery('english',$2) q
             WHERE tsv @@ q AND tenant_id=$3 LIMIT 50)
SELECT id, COALESCE(1.0/(60+vec.rank),0) + COALESCE(1.0/(60+lex.rank),0) AS score
FROM vec FULL OUTER JOIN lex USING (id) ORDER BY score DESC LIMIT 20;
```

**Hybrid + reranking is the production standard**, and being able to say why — because the two retrievers fail on different query types and RRF fuses them without scale calibration — is the L2 answer.

---

## 349. Metadata filter?

**Definition.** Constraining retrieval to chunks matching structured criteria — tenant, document type, date range, permission, status — alongside the semantic search.

**Why it's not optional:**

1. **Multi-tenancy.** `WHERE tenant_id = $x` is a hard security boundary. Retrieving another tenant's chunk is a data breach, and semantic similarity has no concept of ownership (Q385).
2. **Permissions.** A user must not retrieve documents they can't read. Filtering *after* retrieval leaks existence and wastes k slots (Q386).
3. **Recency.** "What's the current premium rate" must not return a 2019 document.
4. **Correctness.** Filtering to the right policy type prevents a motor-insurance clause answering a health-insurance question.
5. **Precision.** Narrowing the candidate pool improves ranking quality within it.

**The implementation advantage of pgvector**: filters are ordinary SQL predicates with real indexes, composable with joins, in the same transaction as your data (Q344).

**The hard problem — filtering interacts badly with ANN indexes** (Q414). HNSW traverses the graph and applies the filter to what it finds, so a highly selective filter can return far fewer than k results. Approaches:
- **Partitioned indexes** — one index per tenant, so the filter is implicit in which index you query. Best for isolation.
- **Pre-filter to a subset** and use exact search when the subset is small.
- **Over-fetch** (request 5–10× k) and filter, accepting the extra work.

**The rule to state clearly:** security filters must be applied **in the query**, never after retrieval. Post-filtering means the vector store returned data the user shouldn't see, and now correctness depends on your application code not leaking it. Same principle as Q70.

---

## 350. Citation?

**Definition.** An explicit reference from a generated claim to the source chunk that supports it.

**Why it's the highest-value feature in a RAG product:**
1. **Verifiability.** The user can check the claim. For insurance, legal, or medical content this converts an unverifiable assertion into a usable answer.
2. **Trust.** "Per Section 4.2 of your policy document" is qualitatively different from an unsourced statement.
3. **Hallucination detection.** If a claim has no citation, or cites a chunk that doesn't contain it, you can catch it programmatically (Q368).
4. **Debuggability.** When an answer is wrong, citations tell you whether retrieval or generation failed. **That single distinction directs all your debugging effort.**

**Implementation:**
```python
context = "\n\n".join(
    f"[{i+1}] (source: {c.doc_title}, section {c.section})\n{c.content}"
    for i, c in enumerate(chunks))
# instruct: cite the bracketed number after each claim; if not supported, say so
```

**Then verify** (Q368) — do not trust the citations:
- Every cited index must exist in the provided context (models invent `[7]` when you gave 5 chunks)
- Quoted text must actually appear in the cited chunk
- Claims without citations should be flagged or removed

**The failure to name:** a model will produce a plausibly-formatted citation for content it invented. Fake section numbers, fake clause references, fake document titles — all well-formed and all wrong (Q278). **Never display a generated identifier without validating it against the source.** This is the single most important validation in a RAG product.

---

# L2 — Engineering

## 351. Chunking strategy?

**The strategies, in the order you should consider them:**

**1. Structure-aware (best where structure exists).** Split on the document's own boundaries — headings, sections, clauses, articles. For insurance policies, legal contracts, or technical documentation, the document already tells you where the semantic boundaries are. **Use them.** Every other strategy is a heuristic approximation of what the structure states explicitly.

**2. Recursive character splitting.** Try paragraph breaks, then sentences, then words, splitting at the largest boundary that fits the size limit. A good general default when structure is weak.

**3. Fixed-size with overlap.** Simple, predictable, structure-blind. The baseline you should beat.

**4. Semantic chunking.** Embed sentences, split where similarity between adjacent sentences drops below a threshold. Elegant; expensive to compute; in practice rarely beats good structure-aware chunking by enough to justify the cost.

**5. Sentence-window / parent-document.** Embed small units for precision, return larger surrounding context for the generator (Q384). This decouples the retrieval unit from the generation unit and is often the single best structural improvement.

**Rules that matter more than the strategy:**
- **Never split tables, code blocks, or lists.** Handle them atomically or with special extraction.
- **Prepend context to each chunk** — document title, section heading, breadcrumb. A chunk reading "The limit is ₹5 lakh" is useless; "Health Policy XYZ > Section 4: Coverage Limits > The limit is ₹5 lakh" is retrievable and answerable. **This is cheap and dramatically improves both retrieval and generation.**
- **Keep metadata on every chunk** — document ID, section, page, tenant, date, permissions.

**How to choose:** build a golden set, then measure recall@k across two or three strategies. It's a few hours of work and it replaces an argument with a number.

---

## 352. Chunk size?

**There is no universal answer, and the honest response is "I measured it" rather than a number.** But the reasoning:

**Typical ranges:**
- **200–400 tokens** — precise, good for fact lookup, risks losing context
- **500–800 tokens** — common default, balances both
- **1,000–1,500 tokens** — more context per chunk, dilutes embeddings, fewer chunks fit in the final context

**The trade-off restated:**
- **Smaller** → sharper embeddings, higher precision, more chunks fit, but each may lack the context needed to be understood or to fully answer
- **Larger** → more self-contained, but the embedding averages more topics and matches less sharply

**The factors that should drive your choice:**
1. **Document structure.** If your policies have 300-token clauses, chunk on clauses. The natural unit beats any tuned size.
2. **Query type.** Fact lookup favours small; "explain how X works" favours larger.
3. **Embedding model input limit.**
4. **Generation context budget** — k × chunk_size must fit comfortably.

**Overlap:** 10–20% (50–100 tokens) so a sentence spanning a boundary appears intact in at least one chunk. Costs storage and creates near-duplicate retrievals; deduplicate overlapping chunks before assembling context.

**The technique that sidesteps the whole question — and this is what to say:** decouple the units. Embed 200-token chunks for retrieval precision; return the surrounding 1,000-token parent for generation (Q384). You stop having to choose.

**How to measure:** golden set, sweep chunk sizes, compute recall@5 and end-to-end answer quality for each. **"We tested 300/600/1000 and 600 gave the best recall@5 on our policy corpus"** is the answer that ends the question.

---

## 353. Overlap?

**Definition.** Including the last N tokens of one chunk at the start of the next.

**Why:** a sentence or idea spanning a chunk boundary is fragmented in both. With overlap, at least one chunk contains it intact. Also softens the arbitrariness of any boundary.

**Typical:** 10–20% of chunk size. 100 tokens on a 600-token chunk.

**The costs, which people underestimate:**
1. **Storage and embedding cost** scale with overlap — 20% overlap means 20% more chunks to embed and store.
2. **Duplicate retrieval.** Overlapping chunks are near-identical, so top-5 can return three variants of the same passage, wasting slots that should hold different information. **This is the real problem** — it silently reduces your effective k.
3. **Redundant context** at generation, wasting tokens.

**Mitigation is required, not optional:** deduplicate after retrieval. Merge chunks that overlap substantially, or filter by content similarity before assembling context:
```python
def dedupe(chunks, threshold=0.85):
    kept = []
    for c in chunks:
        if not any(overlap_ratio(c.content, k.content) > threshold for k in kept):
            kept.append(c)
    return kept
```

**Where overlap isn't needed:** structure-aware chunking on well-delimited units (clauses, sections). If chunks align with real semantic boundaries, nothing is being cut mid-thought, and overlap adds cost for no benefit. **Overlap is a patch for boundary-blind chunking** — if you're using it heavily, consider whether better chunking would serve you better.

---

## 354. Why is retrieval quality more important than generation?

**Because generation cannot recover from bad retrieval.** If the answer isn't in the context, the model has two options: refuse (best case, and only if you instructed and tested it) or hallucinate (default). Neither is an answer.

**The asymmetry:**
- **Good retrieval + adequate generation** → correct, grounded answer
- **Bad retrieval + excellent generation** → fluent, confident, wrong answer

The second is *worse than an error*, because it's convincing.

**Where teams misallocate effort.** Prompting is visible and iterable — you change a sentence and see the output change. Retrieval is invisible: you don't see what *wasn't* retrieved. So teams spend weeks on prompt wording while recall@5 sits at 0.6 and a third of their queries never had a chance.

**The diagnostic that settles it:** for a failing query, check whether the correct chunk was in the retrieved context.
- **Not retrieved** → retrieval problem. Prompting cannot fix it.
- **Retrieved but the answer is wrong** → generation problem.

**Run this on 20 failures and the split tells you where to work.** In most immature RAG systems it's 70–80% retrieval. This diagnostic is the single most useful thing in this document and takes an hour.

**The corollary:** measure retrieval separately from end-to-end quality (Q371, Q419). An end-to-end score conflates the two and can't tell you which to fix. Recall@k measured against a golden set is the number that directs your effort.

---

## 355. Why is BM25 useful?

**Because embeddings are systematically weak at exactly what BM25 is strong at: exact lexical matching of rare terms.**

**BM25** scores a document by term frequency and inverse document frequency, with saturation and length normalisation. Terms that are rare across the corpus but frequent in a document score highly.

**Where it wins decisively:**
- **Identifiers** — policy numbers, SKUs, error codes, case references. `LIC-2024-88371` has no meaningful embedding; it's a token the model has never seen. Vector search returns semantically similar policies, which is exactly wrong.
- **Rare technical terms** — a term appearing three times in the corpus is poorly represented in embedding space but is BM25's ideal signal.
- **Exact phrase requirements** — legal or regulatory language where the precise wording matters.
- **Names** — proper nouns, especially non-Western ones the embedding model saw rarely.
- **Out-of-domain vocabulary** the embedding model wasn't trained on.

**The structural reason:** embedding models compress meaning into a fixed vector. Rare tokens contribute little to that compression — they're literally averaged away. BM25's IDF weighting does the opposite: rarity *increases* the score. **The two methods have inverted biases**, which is precisely why fusing them works (Q348).

**In PostgreSQL:** `tsvector` + GIN index + `ts_rank_cd` gives you BM25-like ranking natively, or `pg_trgm` for fuzzy matching. No extra infrastructure.

**The practical point:** if your users search by identifier at all — and in an insurance product they will — pure vector search will fail on those queries in a way that looks baffling until you understand why. Hybrid isn't an optimisation there; it's a correctness requirement.

---

## 356. Why does metadata filtering matter?

Covered at Q349. The three points to emphasise:

**1. It's a security boundary, not a relevance feature.** Tenant and permission filters must be in the query and enforced structurally — ideally with RLS as a backstop (Q385). Semantic similarity has no notion of who owns a document; nothing in the vector space prevents retrieving another tenant's contract.

**2. It's often the difference between a right and a wrong answer.** A query about premium payment retrieving the 2019 version of the policy gives a confidently wrong answer with a real citation. Filtering to `effective_date <= now() AND (superseded_at IS NULL OR superseded_at > now())` prevents an entire class of failures that no amount of reranking would catch — because the old document *is* the most semantically relevant match for the question.

**3. It improves precision within the candidate pool.** Narrowing to the right document type before ranking means the top-k is drawn from a relevant population.

**The metadata worth carrying on every chunk:** `tenant_id`, `document_id`, `document_type`, `section_path`, `page`, `effective_date`, `superseded_at`, `access_level`, `language`, `source_uri`, `embedding_model_version`, `content_hash`.

**That last pair matters operationally** — `embedding_model_version` makes migration possible (Q357), and `content_hash` makes incremental re-indexing possible (Q358).

**The ANN interaction** remains the hard part (Q414): selective filters degrade approximate search. Partition indexes by tenant where isolation matters most.

---

## 357. How update embeddings when the model changes?

**The constraint: vectors from different models are not comparable.** You cannot mix them in one index — similarity scores become meaningless and retrieval quality collapses in a way that's genuinely hard to diagnose, because nothing errors.

**So the whole corpus must be re-embedded. The question is how to do it without downtime.**

**The expand/contract migration:**

1. **Add a column or table for the new vectors**, with `embedding_model_version` on every row.
```sql
ALTER TABLE chunks ADD COLUMN embedding_v2 vector(1536);
```
2. **Backfill in batches**, rate-limited to respect the embedding API and to avoid saturating the database. Checkpoint progress so a crash resumes.
3. **Build the new index concurrently** — `CREATE INDEX CONCURRENTLY` so writes aren't blocked (Q165).
4. **Evaluate before switching.** Run your golden set against the new index and compare recall@k. **A newer or higher-ranked embedding model is not automatically better on your data** — measure it, and be willing to abandon the migration.
5. **Shadow or canary** — route a percentage of queries to the new index and compare quality metrics in production.
6. **Switch reads** via config, not a deploy, so rollback is instant.
7. **Drop the old column and index** after a soak period.

**The costs to plan for:** re-embedding a million chunks is a real API bill and hours of wall time; you carry both indexes simultaneously (double the vector storage, and vector indexes are large); and dimensionality changes mean a new column, not an in-place update.

**The design decision that makes this tractable:** store `embedding_model_version` on every chunk from day one, and keep the chunk *text* as the source of truth so you can always re-embed. If you only stored vectors, you cannot migrate at all.

**The trap:** silently changing model versions on a hosted API. Some providers update models behind a stable name. Pin the version explicitly, or your index quietly becomes a mixture.

---

## 358. How handle document updates?

**The requirement:** a document changes, and the index must reflect it without stale chunks lingering and without re-embedding unchanged content.

**The mechanism — content-hash-based incremental re-indexing:**

```sql
CREATE TABLE chunks (
  id UUID PRIMARY KEY,
  document_id UUID NOT NULL,
  document_version INT NOT NULL,
  chunk_index INT NOT NULL,
  content TEXT NOT NULL,
  content_hash TEXT NOT NULL,         -- sha256 of content
  embedding vector(1536),
  deleted_at TIMESTAMPTZ,
  UNIQUE (document_id, document_version, chunk_index)
);
```

**The update flow:**
1. Re-chunk the new document version.
2. Compute `content_hash` per chunk.
3. **Reuse embeddings for chunks whose hash already exists** — this is the saving, and for a small edit to a large document it can be 95%+.
4. Embed only the new/changed chunks.
5. **Atomically swap versions in one transaction** — insert new chunks, soft-delete old ones. A search must never see a partially-updated document.

```sql
BEGIN;
  INSERT INTO chunks (...) VALUES (... version = $new ...);
  UPDATE chunks SET deleted_at = now()
    WHERE document_id = $1 AND document_version = $old;
COMMIT;
```

**Soft delete, not hard delete**, so in-flight queries don't error and you can roll back. Purge on a schedule.

**The chunk-boundary problem people miss:** if the document changed enough that chunk boundaries shift, hashes won't match even for semantically unchanged text — an inserted paragraph near the top shifts every subsequent boundary. Structure-aware chunking mitigates this substantially (boundaries anchor to headings rather than to character offsets), which is another argument for Q351.

**Deletions:** soft-delete the chunks and filter `deleted_at IS NULL` in every query. For GDPR erasure you need genuine deletion, plus removal from any cached embeddings and any derived indexes (Q393).

---

## 359. How handle document permissions?

**The rule: filter at query time, in the query, using the requesting user's permissions. Never after retrieval.**

**Why post-filtering is wrong:** the vector store returned chunks the user cannot see. Now correctness depends on your application code discarding them, and any bug is a breach. It also wastes k slots — you asked for 10, five were filtered out, and the user gets a worse answer than if you'd filtered first.

**Implementation:**
```sql
SELECT id, content FROM chunks c
WHERE c.tenant_id = $tenant
  AND c.deleted_at IS NULL
  AND (c.access_level = 'public'
       OR c.access_level = ANY($user_access_levels)
       OR EXISTS (SELECT 1 FROM document_grants g
                  WHERE g.document_id = c.document_id AND g.user_id = $user))
ORDER BY c.embedding <=> $qvec
LIMIT 20;
```

**Layered enforcement**, same as everywhere else in this bank:
1. Permission predicate in the retrieval query
2. **PostgreSQL RLS as the backstop** — a forgotten filter returns zero rows rather than everyone's documents (Q385)
3. Permissions denormalised onto chunks for query efficiency, with a re-sync job when they change
4. A CI test attempting cross-permission retrieval on every path

**The permission-change problem:** if permissions are denormalised onto chunks, revoking access requires updating chunk rows. Until that job runs, the user can still retrieve. Either accept a bounded staleness window with a fast sync, or join to a live permissions table at query time (correct, slower).

**The subtle leak worth naming:** even without returning content, retrieval *behaviour* leaks information. If a user's query returns nothing when a document exists but they can't see it, versus something when it doesn't exist, the difference is observable. Return the same shape either way — the same reasoning as returning 404 rather than 403 (Q70).

---

## 360. How prevent stale answers?

**Staleness enters at four points, and each needs a different fix:**

**1. The document itself is outdated.** The corpus contains a 2019 policy and a 2024 policy; the 2019 one is semantically the better match. **Filter by effective date in the query**, don't rely on ranking:
```sql
AND effective_date <= now()
AND (superseded_at IS NULL OR superseded_at > now())
```
This is the most common and most damaging staleness failure, and it's invisible in your metrics — the answer is fluent, cited, and wrong.

**2. The index lags the source.** A document was updated but not re-indexed. Fix with event-driven re-indexing (CDC or an outbox on document changes, Q238) rather than nightly batch, and **monitor index lag** — the age of the oldest unindexed change. A stalled indexer is silent otherwise.

**3. The response cache is stale.** A cached answer from before the document changed. Include a corpus or document version in the cache key, or invalidate on document update (Q183).

**4. The embedding cache is stale.** Keyed on `hash(text) + model_version`, so content changes produce a new key automatically. This one is self-correcting if you key it correctly.

**Additional controls:**
- **Surface dates in the answer.** "According to your policy effective 1 April 2024..." lets the user catch it when your filters don't.
- **Include the document date in the chunk text**, so the model can reason about recency.
- **Prefer recency in ranking** as a tiebreaker among similarly-relevant chunks.
- **Alert on retrieval of superseded documents** — it indicates a filtering bug.

**The framing:** staleness in RAG is uniquely dangerous because the answer carries a *citation*. The user sees a real source and reasonably concludes the answer is current. **A stale cited answer is more convincing and more harmful than an uncited one.**

---

## 361. How combine keyword + vector?

Mechanically covered at Q348. The engineering detail:

**Reciprocal Rank Fusion is the default, and the reason is important:**
```
RRF(d) = Σ_r  1 / (k + rank_r(d)),   k ≈ 60
```

**Why rank-based fusion beats score-based.** BM25 scores are unbounded and corpus-dependent; cosine similarities are bounded in a narrow band. Normalising them to a common scale requires calibration that shifts whenever your corpus or embedding model changes. **Ranks are inherently comparable across any retriever**, so RRF needs no tuning and stays correct as components change. The constant k=60 damps the influence of top ranks slightly; it's remarkably insensitive and rarely worth tuning.

**Weighted fusion** if you have evidence one retriever is better for your domain:
```
score = w_vec / (60 + rank_vec) + w_lex / (60 + rank_lex)
```
**Only set the weights from measurement.** Guessing them is worse than 1:1.

**Alternatives worth knowing:**
- **Convex combination** of normalised scores — needs calibration, more brittle
- **Learned fusion** — train a model on relevance labels. Best quality, needs labelled data
- **Rerank the union** — skip fusion entirely: take the top 30 from each retriever, deduplicate, and let a cross-encoder rank all 60. **Often the best-performing option**, since the reranker is a better judge than any fusion formula, and the fusion step exists only to produce candidates.

That last point is worth saying: **if you have a reranker, fusion matters less** — you're just assembling a recall-oriented candidate pool, and precision is the reranker's job.

**Query-dependent routing** as a refinement: detect identifier-shaped queries and weight lexical higher; conceptual queries weight semantic. Adds complexity; measure whether it beats plain RRF before adopting it.

---

## 362. Why rerank?

Covered at Q347. The three arguments to have ready:

**1. Bi-encoders lose information by construction.** The document is encoded before the query is known, so the embedding must represent the passage for *all possible queries*. A cross-encoder sees both together and can attend across them. **Independent encoding is the fundamental limitation, and reranking is the fix.**

**2. Similarity ≠ relevance.** Vector search finds chunks *about* the same topic. Reranking finds chunks that *answer the question*. A chunk discussing "exclusions to health coverage" and one stating "the coverage limit is ₹5 lakh" are both similar to "what's my health coverage" — only one answers it.

**3. It's simultaneously cheaper and better.** Retrieve 30, rerank, pass 5. You send fewer tokens to the generator than passing 20 unranked, *and* the 5 are better ordered. **This is the rare optimisation with no trade-off** (Q363).

**The measurement to bring:** reranking typically produces the largest single quality jump in a naive pipeline. But quantify it on your data — "recall@5 went from 0.74 to 0.88" beats any general claim, and an interviewer asking Q599 is specifically checking whether you have a number.

**When it's not worth it:** very small corpora where the top-k is nearly always right; extreme latency requirements where 100ms matters more than quality; queries where lexical exactness is all that matters.

---

## 363. Why does fewer context sometimes beat more?

**Three mechanisms, and the first is the one most people don't know:**

**1. Lost in the middle.** Models attend reliably to the start and end of a context and less reliably to the middle. Adding chunks 6–20 pushes the answer-bearing chunk from position 3 (well attended) toward the middle (poorly attended). **The information is present and the model doesn't use it.**

**2. Distraction.** Irrelevant but topically-similar content actively competes. A chunk about motor insurance exclusions in a health insurance query doesn't sit inertly — it offers plausible-sounding content the model may draw on. **Adding a mediocre chunk is not neutral; it's negative.**

**3. Conflicting information.** More chunks means a higher chance of including contradictory passages (an old and a new policy version). The model must adjudicate, and it often picks wrong or blends them.

**The empirical shape:** answer quality typically rises with k up to some point (3–8 for most tasks), plateaus, then *declines*. The declining region is where naive implementations sit, because "retrieve more to be safe" is the intuitive instinct.

**The resolution is the two-stage pattern** (Q346): retrieve wide for recall, rerank, pass narrow for precision. You get the answer in context (high k at stage one) without the distraction (low k at stage two).

**How to find your number:** hold retrieval fixed, sweep the final context size across 3/5/8/10/15, and measure end-to-end answer quality. The curve tells you where to stop. **This is a two-hour experiment that most teams never run**, and the answer is usually lower than they expect.

**The one-line version:** *"More context is not more information. Past the answer, it's more distraction — and it costs money to distract yourself."*

---

## 364. How measure retrieval?

**Retrieval metrics require a golden set — question paired with the chunk(s) that answer it.** There is no way around building one, and it's the reason most teams can't answer this question.

**The metrics and what each tells you:**

| Metric | Definition | Use for |
|---|---|---|
| **Recall@k** | Fraction of queries where ≥1 relevant chunk is in the top k | **The primary metric.** If the answer isn't retrieved, nothing downstream can fix it |
| **Precision@k** | Fraction of retrieved chunks that are relevant | Context efficiency |
| **MRR** | Mean of 1/rank of the first relevant result | Is the right chunk near the top? |
| **NDCG@k** | Rank-weighted, supports graded relevance | Best single ranking-quality metric |
| **Hit rate** | Recall@k with k = your production k | Direct proxy for production behaviour |

**Recall@k is the one to lead with**, because retrieval failure is unrecoverable and generation failure is not (Q354).

**Building the golden set** (Q371): 30–50 questions is enough to be useful, 100+ to be confident. Sources: real user queries from logs (best), questions written by domain experts, or LLM-generated questions from chunks with human review. **Label which chunk(s) actually answer each question.** That labelling is the work, and it's a few hours.

**Run it as a script, in CI:**
```python
def evaluate(golden, retriever, k=5):
    hits = sum(1 for q in golden
               if set(q.relevant_chunk_ids) & set(c.id for c in retriever(q.question, k)))
    return hits / len(golden)
```

**What this unlocks:** you can now compare chunking strategies, embedding models, hybrid weights, rerankers, and k values by *number* instead of by argument. Every tuning decision in this document becomes an experiment rather than an opinion.

**The answer to Q599 lives here.** "We measured recall@5 at 0.82 on a 30-question golden set; adding a reranker took it to 0.91" is a complete answer. Anything without a number is not.

---

## 365. How measure grounding?

**Definition.** Grounding (or faithfulness) measures whether the generated answer is supported by the retrieved context — distinct from whether it's *correct*.

**The distinction that matters:** an answer can be correct but ungrounded (the model knew it from training, not from your documents) or grounded but wrong (the retrieved document was wrong). **You need both metrics; they fail differently.**

**How to measure:**

**1. Claim-level entailment (the rigorous method).** Decompose the answer into atomic claims, and for each, ask a judge model whether the context entails it.
```
grounding = (# claims supported by context) / (total claims)
```
This is what RAGAS calls faithfulness, and it's the most defensible number.

**2. Citation verification (cheap and mechanical).** If you require citations (Q350):
- Does every cited index exist in the provided context?
- Does the cited chunk actually contain support for the claim?
- What fraction of claims carry a citation at all?

**The first two are pure code, no judge needed**, and catch the most common failure — invented citations.

**3. LLM-as-judge with a rubric**, scoring the whole answer for support. Faster, noisier (Q432).

**The companion metrics from the RAGAS framing:**
- **Context precision** — are the retrieved chunks relevant? (retrieval quality)
- **Context recall** — does the context contain everything needed? (retrieval quality)
- **Faithfulness** — is the answer supported by the context? (generation quality)
- **Answer relevance** — does the answer address the question?

**Why the decomposition matters:** low faithfulness with high context recall means a generation problem — the model isn't using what it was given. Low context recall means a retrieval problem. **The metrics tell you which half of the pipeline to fix**, which is the entire value of measuring separately (Q354).

**Include unanswerable questions in the set** (Q369). Grounding on answerable questions doesn't test the failure mode you most care about.

---

# L3 — Failure modes

## 366. Query has no relevant documents?

**The default behaviour is the problem: the model will answer anyway.** Vector search always returns k results — it returns the *closest* vectors regardless of whether they're close at all. The model receives five irrelevant chunks with no signal that they're irrelevant, and produces a confident answer.

**The layered fix:**

**1. Similarity threshold.** Below a calibrated score, treat as no result:
```python
results = [c for c in candidates if c.rerank_score > THRESHOLD]
if not results:
    return no_answer_response()
```
**Use the reranker's score, not the raw cosine similarity** — reranker scores are far better calibrated for relevance and more stable across query types (Q370).

**2. Explicit refusal instruction:**
```
Answer ONLY from the provided context. If the context does not contain the
information needed, respond exactly: "I don't have information about that in
your policy documents." Do not use general knowledge.
```

**3. Test the refusal.** Include unanswerable questions in your eval set and measure the refusal rate (Q369). **Untested refusal instructions frequently don't work**, and you'll never know without measuring.

**4. Post-generation grounding check** (Q365). Low faithfulness → suppress the answer.

**5. Degrade usefully rather than dead-ending.** "I don't have that in your documents. I can help with coverage limits, claims process, or premium schedules — or you can contact support." A bare refusal is a bad product.

**The product decision to name:** what's the cost of a wrong answer versus a refusal? For insurance advice, a wrong answer has regulatory and financial consequences and refusal is clearly better. For internal search, over-refusal makes the tool useless. **Set the threshold from that judgement, then calibrate it against labelled data.**

---

## 367. Query is ambiguous?

**Ambiguity types, each needing a different response:**

| Type | Example | Response |
|---|---|---|
| **Missing referent** | "What's my coverage?" (which policy?) | Ask, or use context |
| **Multiple senses** | "premium" — amount or plan tier? | Retrieve both, present both |
| **Underspecified scope** | "claims process" for which product? | Clarify or cover both |
| **Pronoun/anaphora** | "and what about that one?" | Resolve from history |
| **Vague intent** | "help with my policy" | Ask |

**The strategies:**

**1. Query rewriting with conversation context.** Before retrieving, resolve the query against history:
```
History: "Tell me about my health policy" / [answer]
User: "What's the waiting period?"
Rewritten: "What is the waiting period for the health policy?"
```
**This is essential in multi-turn RAG** — embedding "what's the waiting period?" alone retrieves waiting periods from every product (Q383).

**2. Multi-query retrieval.** Generate 2–3 interpretations, retrieve for each, fuse with RRF. Covers the ambiguity rather than guessing at it. Costs an extra model call and more retrieval.

**3. Use available context to disambiguate.** If the user has exactly one health policy, "my coverage" is unambiguous — resolve it from their account, not from the query text. **This is usually better than asking**, and it's a product advantage over generic search.

**4. Ask, when the interpretations diverge materially.** Better one clarifying question than a confident answer to the wrong question — particularly where the answer affects a financial decision.

**5. Answer both, labelled.** "For your health policy the waiting period is X; for your motor policy it's Y." Often the best UX — no round trip, and the user self-selects.

**Detection:** low top-score with a flat distribution across candidates (nothing clearly matches), or retrieved chunks spanning multiple documents with similar scores. Both are signals the query didn't resolve to one thing.

---

## 368. Model cites wrong source?

**Two distinct failures — diagnose which:**

**A. The cited chunk exists but doesn't support the claim.** The model attributed to chunk [3] something it got from chunk [1], or from training knowledge.

**B. The citation is fabricated** — `[7]` when you supplied five chunks, or an invented section number, clause reference, or document title.

**Detection (all mechanical, no judge required):**
```python
def verify_citations(answer, chunks):
    cited = extract_citation_indices(answer)
    invalid = [i for i in cited if i < 1 or i > len(chunks)]      # case B
    unsupported = []
    for claim, idx in extract_claims_with_citations(answer):
        if not supports(chunks[idx-1].content, claim):            # case A
            unsupported.append((claim, idx))
    return invalid, unsupported
```
For quoted text, verify the quote appears verbatim in the cited chunk — a pure string check that catches a large fraction of fabrication.

**Handling:**
1. **Invalid index** → regenerate, or strip the citation and flag the claim as unsupported.
2. **Unsupported claim** → either suppress the claim or present the answer with a low-confidence marker.
3. **Never display an unverified generated identifier.** This is the rule (Q350). A fabricated clause number in an insurance answer, presented as real, is a serious product failure — the user acts on it.

**Prevention:**
- Number chunks explicitly and clearly in the prompt
- Require a citation on every factual claim
- Lower temperature (Q266)
- Fewer chunks reduces confusion about which is which (Q363)
- Instruct the model to quote the supporting phrase, which makes verification trivial

**Track citation validity as a production metric.** A rising rate of invalid citations after a prompt or model change is one of the earliest quality-regression signals available, and it costs nothing to compute.

---

## 369. Model answers without retrieval?

**The failure:** the model answers from parametric (training) knowledge rather than the provided context. The answer may even be correct — which makes it *harder* to detect and no less dangerous, because it isn't grounded in the user's actual documents.

**Why it's serious in a document-grounded product:** a user asks about their coverage limit. The model answers with a typical industry figure from training rather than their policy's actual figure. It sounds authoritative, may carry a citation, and is wrong for *this user*.

**Detection:**
1. **Grounding/faithfulness measurement** (Q365) — claims unsupported by context.
2. **Unanswerable questions in the eval set** — questions whose answers are *not* in the corpus but *are* plausibly in training data. If the model answers them, it's using parametric knowledge. **This is the definitive test**, and it must be part of your eval set.
3. **Citation coverage** — the fraction of claims with valid citations.

**Prevention:**
- **Explicit instruction:** "Answer only from the provided context. Do not use prior knowledge. If the context is insufficient, say so."
- **Require citations on every claim.** A claim from training knowledge has nothing to cite, which makes it visible.
- **Post-generation grounding check**, suppressing ungrounded output.
- **Adversarial eval cases** where training knowledge and the corpus *disagree* — a policy with a deliberately unusual term. If the model gives the common industry answer instead of the document's, it's ignoring your context. **This is the sharpest possible test** and takes ten minutes to construct.

**The trade-off to acknowledge:** strict grounding reduces helpfulness. The model won't answer reasonable questions the corpus doesn't cover. That's usually correct for a compliance-sensitive domain and wrong for a general assistant — **it's a product decision, and you should say so rather than treating it as purely technical.**

---

## 370. Similarity threshold fails?

**The problem: absolute similarity thresholds are unreliable**, and a threshold that works in testing fails in production.

**Why:**
1. **Score distributions vary by embedding model.** A cosine of 0.75 means different things across models.
2. **They vary by query length.** Short queries produce systematically different score ranges than long ones.
3. **They vary by domain and corpus.** A homogeneous corpus produces uniformly high similarities — everything looks relevant.
4. **Cosine similarities compress into a narrow band** (often 0.6–0.9), so small differences carry a lot of signal and a fixed cut-off is brittle.
5. **They drift** when you change the model, the chunking, or the corpus composition — silently.

**The failures:** threshold too high → over-refusal on answerable questions. Too low → irrelevant chunks pass and the model hallucinates from them (Q366).

**Better approaches, in order:**

**1. Threshold on the reranker score, not the embedding similarity.** Cross-encoder scores are trained to express relevance directly and are much better calibrated. **This alone fixes most of the problem.**

**2. Relative thresholding.** Use the gap between the top score and the rest, or keep chunks within X% of the top score. Adapts to per-query score distributions automatically.

**3. Calibrate against labelled data.** Take your golden set plus unanswerable questions, sweep the threshold, and plot precision against recall of *refusal*. Pick the operating point that matches your product's cost asymmetry. **This is the only defensible way to set the number.**

**4. Let a model judge sufficiency.** A cheap call: "Does this context contain enough to answer the question?" More robust, adds latency and cost.

**5. Monitor drift.** Track the distribution of top-1 scores in production. A shift means something changed — corpus, model, or query mix.

**The answer to give:** *"I don't use an absolute cosine threshold. I threshold on the reranker score, calibrated against a labelled set including unanswerable questions, and I monitor the score distribution for drift."*

---

## 371. How would you evaluate your RAG?

> **This must be your real numbers.** The method below is what to do; the results must be measured.

**The structure of a strong answer — three layers, measured separately:**

**Layer 1 — Retrieval, in isolation.**
- Golden set of 30–100 questions with labelled relevant chunks
- **Recall@k** (the primary number), MRR, NDCG@k
- Report: "recall@5 = 0.82, recall@20 = 0.94" — the gap tells you reranking has room to work

**Layer 2 — Generation, given correct context.**
- Feed the *known-correct* chunks and measure answer quality. This isolates generation from retrieval.
- Faithfulness/grounding (Q365), answer correctness, citation validity

**Layer 3 — End-to-end.**
- The full pipeline on the same questions
- Plus **unanswerable questions** measuring refusal rate (Q369)
- Plus adversarial cases where training knowledge contradicts the corpus

**Why three layers rather than one number:** an end-to-end score of 0.7 doesn't tell you what to fix. Retrieval 0.85 / generation-given-context 0.95 / end-to-end 0.70 tells you immediately that retrieval is the bottleneck (Q354).

**Operational metrics alongside:** p50/p95 latency by stage, cost per query, cache hit rate.

**Production signals:** thumbs up/down, follow-up rate (a proxy for unsatisfying answers), refusal rate, citation-click rate.

**Running it:** a script, in CI, gating changes to chunking, embedding model, prompts, or k (Q329, Q433).

**The sentence that answers Q599 properly:** *"Thirty-question golden set built from real user queries, labelled by which chunk answers each. Recall@5 was 0.74 with pure vector search; hybrid plus a reranker took it to 0.91. End-to-end faithfulness measured at X on the same set, with a Y% refusal rate on fifteen deliberately unanswerable questions."* Numbers, method, and the delta from a specific change.

---

## 372. What is your recall@k?

> **Your number.** What matters is that you have one and can explain it.

**How to compute:**
```python
def recall_at_k(golden, retrieve, k):
    return sum(
        1 for q in golden
        if set(q.relevant_chunk_ids) & {c.id for c in retrieve(q.question, k)}
    ) / len(golden)
```

**What to report, and why the shape matters:**
- **recall@5 and recall@20 together.** If recall@5 = 0.74 and recall@20 = 0.93, the answer is usually in the candidate pool but ranked badly — **reranking will help a lot**. If recall@20 = 0.76 too, the answer often isn't retrieved at all — reranking won't help; **fix chunking, embeddings, or add lexical search**.
- **The confidence interval.** On 30 questions, recall@5 = 0.80 has roughly a ±0.14 interval. Reporting 0.80 as precise is overclaiming; saying "0.80 on 30 questions, so I'd want 100+ before treating a 5-point difference as real" is the answer that shows statistical literacy.
- **Per-query-type breakdown** — identifier lookups vs conceptual questions. Aggregate recall hides that identifier queries are at 0.4 and everything else at 0.9, which points straight at hybrid search (Q355).

**What to do with a low number:** the recall@5 vs recall@20 diagnostic above tells you which half of the pipeline to work on. That's the entire value of measuring it.

**The honest thing to say if you don't have one:** *"I haven't measured recall formally — I'd build a golden set of 30 questions from production logs and measure it, because without that number I'm tuning retrieval by intuition."* **That answer is far better than a fabricated figure**, and an interviewer who asks Q372 is often testing exactly that.

---

## 373. How did you measure precision?

**Precision@k** = the fraction of retrieved chunks that are actually relevant.

```python
def precision_at_k(golden, retrieve, k):
    return mean(
        len(set(q.relevant_chunk_ids) & {c.id for c in retrieve(q.question, k)}) / k
        for q in golden
    )
```

**The important caveat, and this is the substance of the answer: precision@k is a weak metric for RAG.** Most questions have one or two relevant chunks. With k=10, perfect retrieval gives precision@10 = 0.2 — a low number that means you did everything right. Optimising it directly leads you to reduce k, which hurts recall, which is the thing that actually matters.

**Use instead:**
- **Recall@k** as the primary retrieval metric (Q372)
- **NDCG@k** for ranking quality — rank-weighted and handles graded relevance, so it captures "the right chunk should be first" which recall ignores
- **MRR** for "is the best result at the top"
- **Context precision** in the RAGAS sense — of the chunks passed to the generator, what fraction contributed to the answer. This is the version of precision that's actually actionable, because it measures wasted context

**Where precision genuinely matters:** the *final* context after reranking, because that's where distraction hurts (Q363). Precision@5 after reranking is a meaningful number; precision@50 at the retrieval stage is not.

**The framing to use:** *"I track recall at the retrieval stage and context precision at the generation stage, because the first stage should optimise for recall and the second for precision. Measuring precision on the wide retrieval stage would push me toward a smaller k, which is the wrong direction."* That shows you understand *why* the two-stage architecture exists.

---

## 374. Chunk size tested?

> **Your numbers.** The method:

**The experiment:**
1. Fix everything else — embedding model, k, retrieval method.
2. Re-chunk and re-embed the corpus at each candidate size (300 / 600 / 1000 tokens, say).
3. Measure recall@5 and recall@20 on the golden set for each.
4. Then measure end-to-end answer quality, because the best retrieval chunk size isn't automatically the best generation chunk size.

**What you typically observe:**
- Small chunks → higher precision, better recall on specific factual queries, worse on questions needing surrounding context
- Large chunks → better for "explain how X works", worse for "what is the limit for Y"
- **The optimum depends on your query mix**, which is why the answer is empirical

**The cost to state:** each variant requires a full re-embed of the corpus. For a large corpus that's a real API bill and hours of compute, so run it on a representative sample rather than everything.

**What to report:** *"Tested 300/600/1000 on a 40-question golden set. 600 gave recall@5 of 0.84 versus 0.79 and 0.76. But identifier-style questions did better at 300, which is part of why we added BM25."*

**The better answer, if you have it:** *"Rather than tuning one size, we moved to sentence-window retrieval — embed 200-token units, return the 800-token parent. That removed the trade-off and beat every fixed size we tested"* (Q384). Showing you resolved the trade-off rather than optimised within it is a stronger answer.

**If you haven't tested it:** say so and say what you'd do. Claiming a tuned value you didn't measure is the failure mode Q374 exists to detect.

---

## 375. Retrieval failure vs generation failure?

**The single most useful diagnostic in RAG, and it takes an hour to run.**

**The method:**
1. Collect 20–30 failed queries (thumbs-down, escalations, or known-wrong answers).
2. For each, check: **was a chunk containing the correct answer in the retrieved context?**
3. Bucket accordingly:

| Correct chunk retrieved? | Answer correct? | Diagnosis |
|---|---|---|
| No | No | **Retrieval failure** |
| Yes | No | **Generation failure** |
| Yes | Yes | Not a failure — or an evaluation problem |
| No | Yes | Model answered from training knowledge (Q369) — **also a failure**, even though correct |

**That last row matters and is easy to miss.** A correct answer that didn't come from your documents is a grounding failure. It will be wrong for the next user whose policy differs.

**What the split tells you:**
- **Mostly retrieval** (typical: 70–80% in immature systems) → work on chunking, hybrid search, reranking, k. **Prompt engineering will not help and you should stop doing it.**
- **Mostly generation** → work on the prompt, the model, context ordering, and the citation requirement.

**Sub-diagnoses within retrieval failure:**
- Right document, wrong chunk → chunking problem
- Document not retrieved at all → embedding or query-understanding problem
- Document filtered out → metadata or permissions bug
- Document not in the corpus → an ingestion gap, not a retrieval problem at all

**The answer to give:** *"I sampled 25 failures and classified them. Eighteen were retrieval — the answer chunk was never in context. That's why I added hybrid search and a reranker rather than iterating on the prompt."* **That sentence demonstrates a method, a measurement, and a decision derived from it**, which is exactly what the question is testing.

---

## 376. Latency budget?

**Decompose it by stage — that's the answer.**

| Stage | Typical | Notes |
|---|---|---|
| Query embedding | 20–80 ms | Cacheable for repeated queries |
| Vector search | 5–50 ms | Depends on index type and params |
| BM25 search | 5–30 ms | Parallel with vector search |
| Fusion | <5 ms | Negligible |
| Reranking | 50–200 ms | The main added cost |
| Prompt assembly | <10 ms | |
| **Time to first token** | 300 ms–2 s | **Usually dominates** |
| Full generation | 2–20 s | Scales with output length |

**The framing that matters:** for a streaming interface, **time to first token is the number the user experiences**, and retrieval is a small fraction of it. Optimising vector search from 40ms to 15ms is invisible next to a 1.2-second TTFT.

**Where the real wins are:**
1. **Streaming** — transforms perceived latency for free (Q269)
2. **Parallel retrieval** — vector and lexical concurrently, not sequentially
3. **Prompt caching** for the stable system prompt (Q277)
4. **Semantic caching** for repeated queries — enormous when it hits, with a real correctness risk (Q391)
5. **Smaller/faster model** where quality permits
6. **Fewer chunks** — shorter prompt, faster prefill *and* better quality (Q363)

**Set the budget from the product**, then allocate: an interactive assistant might target 800ms to first token, which means retrieval + rerank must fit in ~250ms, leaving the rest for the model.

**Measure per stage in production**, not just end-to-end. An end-to-end p95 regression could be any of seven stages; per-stage traces tell you which in seconds (Q337).

---

## 377. Cost per query?

**Decompose it:**

| Component | Driver |
|---|---|
| Query embedding | ~1 embedding call per query (cacheable) |
| Vector search | Compute/storage, amortised |
| Reranking | Per candidate scored — k candidates per query |
| **Generation input** | (system prompt + k chunks + query) tokens — **usually dominant** |
| Generation output | Output tokens |
| Corpus embedding | One-time + incremental on updates, amortised across queries |

**The dominant term is almost always generation input tokens**, because retrieved context is large and it's charged on every query.

**Which makes the highest-leverage cost lever counter-intuitive: retrieve fewer, better chunks.** Going from 20 chunks to 5 after reranking cuts input tokens roughly 4× *and* improves quality (Q363). **This is the rare optimisation that's better on both axes**, and it's worth leading with.

**The other levers, in order:**
1. **Prompt caching** for the stable prefix (Q277)
2. **Semantic caching** for repeated queries — the largest possible saving, with a correctness risk (Q391)
3. **Model routing** — a cheaper model for simple lookups, the stronger one for synthesis (Q290)
4. **Embedding cache** — never embed the same text twice (Q97)
5. **Shorter system prompts** — they're charged on every query

**What to track:** cost per query, per tenant, and **per successful query**. That last one is the honest metric — queries that fail or get refused still cost money, and a system with a 20% refusal rate has a 25% higher effective cost per useful answer than the raw number suggests.

**The number to bring:** "₹X per query at p50, dominated by input tokens; reranking down to 5 chunks cut it roughly 60% with no quality loss measured on the golden set." Specific, decomposed, and tied to a decision.

---

## 378. What did you tune first?

**The answer should demonstrate a method, not a list of tweaks.**

**The correct order, and the reasoning:**

**1. Measure before tuning.** Build the golden set and get a recall@k baseline (Q371). Without it every subsequent change is unverifiable.

**2. Run the failure diagnostic** (Q375). Classify 25 failures as retrieval vs generation. This tells you where to work, and it's usually retrieval.

**3. Then, in expected-value order:**

| Change | Typical effort | Typical impact |
|---|---|---|
| Add a reranker | Low | **High** |
| Add BM25 / hybrid | Low | High if you have identifier queries |
| Fix chunking to respect structure | Medium | High |
| Prepend section context to chunks | **Very low** | **Medium–high** |
| Tune k (up for retrieval, down for generation) | Very low | Medium |
| Metadata filters (date, type) | Low | High if staleness is a failure mode |
| Change embedding model | Medium (re-embed) | Variable — measure |
| Prompt engineering | Low | Low, if retrieval is the bottleneck |

**The two cheapest high-impact wins**, worth naming explicitly:
- **Prepending document title and section heading to each chunk.** An hour of work; often a large recall improvement, because it turns context-free fragments into self-describing ones (Q351).
- **Adding a reranker.** A few lines and an API call; usually the single largest quality jump (Q362).

**The answer to give:** *"First I built a golden set, because I couldn't tell whether anything I changed helped. Then I classified 25 failures — 18 were retrieval. So I added a reranker and hybrid search before touching the prompt, and recall@5 went from 0.74 to 0.91."*

**That's a strong answer because it shows the order of operations**, not because of the numbers. An engineer who tunes prompts first has revealed they didn't measure.

---

## 379. Where did quality break?

> **Your specifics.** The categories of real breakage, so you can recognise yours:

**Retrieval-side:**
- Chunk boundaries splitting tables or clauses mid-structure
- Identifier queries failing entirely (pure vector search, Q355)
- Stale documents outranking current ones (no date filter, Q360)
- Overlapping chunks consuming k slots with near-duplicates (Q353)
- Multi-turn queries embedded without context resolution (Q383)
- Selective metadata filters degrading ANN recall (Q414)

**Generation-side:**
- Answering from training knowledge instead of context (Q369)
- Fabricated citations and clause numbers (Q368)
- Not refusing when context was insufficient (Q366)
- Blending contradictory chunks from different policy versions

**Operational:**
- Index lag after document updates (Q360)
- Embedding model version drift on a hosted API (Q357)
- Cache serving stale answers after a document change

**How to answer well:** pick one real failure, describe how you *detected* it (a metric, a user report, a sampled review), what the root cause was, what you changed, and what the measurement showed afterwards. **The detection step is what makes it credible** — anyone can describe a fix; describing how you found it proves you were operating the system.

**A good template:** *"Users reported wrong premium figures. Sampling showed we were retrieving the superseded 2023 policy — it was semantically the better match because the wording was nearly identical. Added effective-date filtering, and added five superseded-document cases to the eval set so it can't regress."*

That last clause — adding the failure to the eval set — is what separates a fix from a process.

---

## 380. What is still wrong?

**This question rewards honesty and punishes polish.** An engineer who claims their RAG system is fine has not measured it.

**The limitations that are genuinely true of most production RAG systems:**

1. **Multi-hop questions.** "Which of my policies has the shortest waiting period?" requires retrieving and comparing across documents. Single-shot retrieval can't do it; you need query decomposition or an agentic loop, and both add latency and failure modes (Q382).

2. **Aggregation and counting.** "How many claims did I file last year?" is a database query, not a retrieval problem. RAG will retrieve some claims and the model will miscount. **The fix is routing to SQL, not better retrieval** — and knowing when a question isn't a RAG question is the insight.

3. **Negation and absence.** "What isn't covered?" is poorly served by similarity search — exclusions and inclusions are semantically adjacent.

4. **Tables and structured content.** Chunking damages them; embeddings represent them poorly.

5. **Recall ceiling.** Whatever your recall@5 is, `1 − recall@5` of queries structurally cannot be answered correctly.

6. **Threshold calibration drift** (Q370).

7. **Long-tail and code-mixed queries.** Hinglish, transliterated Hindi, and colloquial phrasing are underrepresented in embedding training.

8. **No feedback loop.** Most systems don't learn from thumbs-down. The failures repeat.

**How to close:** name the one you'd fix next and why. *"Multi-hop is the biggest gap — about 15% of our queries compare across documents and we fail most of them. I'd add query decomposition next, and I'd want to measure whether the added latency is acceptable before committing to it."*

**Naming a real limitation with a plan is a stronger signal than claiming completeness.** Interviewers ask Q380 precisely to see whether you'll overclaim.

---

# L4 — Design

## 381. Design production RAG.

**Architecture:**
```
INGESTION (async)
  source → extract → chunk (structure-aware) → enrich metadata
        → dedupe by content_hash → embed (batched, cached) → upsert
        → build tsvector → index

QUERY (sync)
  query → rewrite w/ history → embed (cached)
        → [vector search ‖ BM25]  (parallel, both filtered)
        → RRF fusion → rerank → threshold → assemble (top 5)
        → generate w/ citations (streamed)
        → verify citations & grounding → respond
```

**The decisions to defend:**

1. **pgvector, not a separate vector DB** — chunk metadata, permissions, and documents already live in Postgres; a separate store means dual writes and weaker filtering (Q344).
2. **Hybrid + rerank**, because vector and lexical fail on opposite query types and the reranker fixes ranking that neither gets right alone (Q348, Q362).
3. **Filters in the query**, with RLS as the backstop (Q385).
4. **Structure-aware chunking with section context prepended** — the cheapest large win (Q351).
5. **Content-hash incremental re-indexing** so a document edit re-embeds only changed chunks (Q358).
6. **Citations required and verified** (Q368).
7. **Refusal threshold on reranker score**, calibrated against labelled data (Q370).

**Operational layer:**
- Event-driven re-indexing via outbox/CDC; monitor index lag
- Embedding cache keyed on `hash(text) + model_version`
- Eval suite in CI gating chunking, model, prompt, and k changes (Q371)
- Per-stage latency traces and cost per query
- Feedback capture feeding the golden set

**What I'd cut at small scale:** the reranker (if recall@5 is already high), hybrid search (if there are no identifier queries), and the async ingestion pipeline (a cron job re-indexing everything is fine under a few thousand documents). **Naming what you'd remove is as valuable as naming what you'd build** (Q262).

---

## 382. Multi-hop RAG?

**The problem:** "Which of my policies has the shortest waiting period, and what does it exclude?" requires retrieving from multiple documents, comparing, then retrieving again based on the comparison. Single-shot retrieval cannot express this.

**The approaches:**

**1. Query decomposition.** Break the question into sub-questions, retrieve for each, synthesise:
```
"Which policy has the shortest waiting period and what does it exclude?"
 → "waiting period health policy"
 → "waiting period motor policy"
 → [compare] → "exclusions for <winning policy>"
```
Predictable and debuggable, but the final step depends on earlier answers, so it's partly sequential.

**2. Iterative / agentic retrieval.** A loop where the model decides what to retrieve next based on what it has (Document 07). Most flexible, most expensive, hardest to bound — and it needs every control in Q306.

**3. Step-back prompting.** Generate a more general question first, retrieve broadly, then narrow.

**4. Graph-based retrieval.** Build a knowledge graph of entities and relations; traverse it for multi-hop connections. Powerful for genuinely relational corpora; substantial ingestion complexity.

**5. Pre-computed aggregates — the underrated one.** If "which policy has the shortest waiting period" is a common question, the answer is a **SQL query over structured extractions**, not retrieval. Extract structured fields at ingestion time and query them. **Faster, cheaper, and correct**, where RAG would be slow, expensive, and probabilistic.

**The judgement to demonstrate:** most multi-hop questions in a well-defined domain are actually structured queries wearing a natural-language costume. **Extract structure at ingestion and route those queries to SQL.** Reserve the agentic loop for genuinely open-ended cases. Reaching for iterative retrieval first is the expensive mistake.

---

## 383. Conversational RAG?

**The core problem: follow-up queries are unretrievable in isolation.**
```
User: "Tell me about my health policy"
User: "What's the waiting period?"     ← embedding this alone is useless
```
It retrieves waiting periods from every product, or nothing coherent.

**The fix — query rewriting before retrieval:**
```python
standalone = await model.call([
  {"role": "system", "content":
   "Rewrite the user's latest message as a standalone question using the "
   "conversation history. Output only the rewritten question."},
  *history[-6:],
  {"role": "user", "content": latest},
])
chunks = await retrieve(standalone)
```
**This is the single most important component of conversational RAG**, and omitting it is why naive multi-turn RAG degrades sharply after turn two.

**The other design decisions:**

1. **Rewrite for retrieval; generate with full history.** The rewritten query goes to the retriever; the model still sees the conversation for tone and continuity.
2. **Detect topic changes.** If the new query is unrelated, don't contaminate it with prior context. A cheap classifier or a similarity check against the previous query.
3. **Manage context growth** — history plus retrieved chunks per turn grows fast (Q271). Summarise older turns; keep retrieved chunks only for the turn that used them, or you resend stale context forever.
4. **Cache retrieved chunks per turn** so a follow-up on the same topic can reuse them rather than re-retrieving.
5. **Handle "what about the other one?"** — genuine anaphora needs the rewriter to resolve referents from what was retrieved, not just what was said.

**The cost:** one extra model call per turn. Use a small fast model — rewriting is an easy task and doesn't need your strongest model.

**Evaluation implication:** your golden set must include **multi-turn cases**, not just standalone questions. A system that scores 0.9 on single-turn questions can collapse on turn three, and a single-turn eval set will never show it.

---

## 384. Hierarchical retrieval?

**The idea: decouple the retrieval unit from the generation unit.** Embed small for precision; return large for context.

**Sentence-window retrieval:** embed individual sentences or 200-token units; when one matches, return it plus surrounding sentences.

**Parent-document retrieval:** embed small child chunks; retrieve the parent chunk or full section they belong to.

```sql
CREATE TABLE chunks (
  id UUID PRIMARY KEY,
  parent_id UUID REFERENCES parent_chunks(id),
  content TEXT,                  -- small, embedded
  embedding vector(1536)
);
CREATE TABLE parent_chunks (
  id UUID PRIMARY KEY,
  document_id UUID,
  content TEXT                   -- large, returned
);
```
```python
children = await vector_search(query, k=20)
parents = dedupe([c.parent for c in children])[:5]     # dedupe is essential
```

**Why it works:** small chunks produce sharp embeddings that match specific queries precisely. Large chunks give the generator enough surrounding context to answer completely. **You stop having to choose a chunk size** (Q352).

**Multi-level summarisation** is the other hierarchical form: index summaries of documents *and* detailed chunks. Retrieve at the summary level to identify relevant documents, then at the chunk level within them. Good for large corpora where you need to narrow before searching in detail.

**The details that matter:**
- **Deduplicate parents.** Multiple children from one parent must not return the parent five times — that's the overlap problem again (Q353), consuming your k.
- **Parents can be large**, so k must be smaller. Three parents may be 3,000 tokens.
- **Reranking should score the child** (precise, what matched) while you return the parent (context).

**The trade-off:** more storage, a two-step retrieval, and more complex ingestion. Usually worth it, and it's a strong answer to "how did you choose chunk size" — *"I stopped choosing"* (Q374).

---

## 385. Multi-tenant retrieval?

**Isolation is a hard security requirement, and semantic search provides none of it** — nothing in vector space distinguishes tenants.

**The layers:**

**1. `tenant_id` on every chunk**, non-null, indexed, and in every query. Never optional.

**2. Injected server-side from the authenticated session** — never accepted from a request parameter or, in an agent context, from the model's tool arguments (Q325).

**3. Row-Level Security as the backstop:**
```sql
ALTER TABLE chunks ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON chunks
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```
**A forgotten `WHERE` returns zero rows instead of everyone's documents.** Application bugs stop being breaches. Note the PgBouncer interaction — use `SET LOCAL` inside the transaction (Q93).

**4. Partitioned or per-tenant indexes** where isolation matters most. This also solves the ANN filtering problem (Q414) — the filter is implicit in which index you query, so recall doesn't degrade.

**5. A CI test attempting cross-tenant retrieval on every path.** Claiming isolation and testing it are different things.

**The scaling decision — three models:**

| Model | Isolation | Cost | When |
|---|---|---|---|
| Shared index + `tenant_id` filter | Logical | Lowest | Most SaaS |
| Partitioned index per tenant | Stronger, better ANN recall | Medium | Many tenants with uneven sizes |
| Separate index/database per tenant | Strongest | Highest | Regulated, few large tenants |

**The operational concerns beyond isolation:**
- **Per-tenant embedding cost attribution** — a tenant with a million documents costs far more to index
- **Noisy neighbour** — a tenant re-indexing their corpus shouldn't degrade everyone's query latency. Separate ingestion queues (Q336).
- **Deletion must be complete** — chunks, embeddings, caches, and any derived indexes. GDPR erasure is where most designs are incomplete (Q393).

---

## 386. Permission-aware retrieval?

Q359 covers the mechanism. The architectural decision:

**Two models, and the trade-off is the answer:**

**A. Denormalised permissions on chunks.** Copy `access_level` and grant lists onto each chunk row. Fast — the filter is a local predicate. **But permission changes require updating chunks**, so there's a staleness window during which a revoked user can still retrieve.

**B. Join to live permissions at query time.** Always correct, no staleness. Slower, and the join interacts badly with ANN indexes.

**The hybrid that's usually right:** denormalise coarse levels (public / internal / restricted) for fast filtering, join for fine-grained per-document grants, and make revocation trigger an immediate targeted chunk update rather than waiting for a batch job.

**The failure modes specific to permission-aware RAG:**

1. **Post-filtering** — retrieving 10 and discarding 6 leaves the user with 4 results and a worse answer. **Filter in the query** (Q349).
2. **Existence leakage.** If a query about a restricted document returns "I don't have information" while a query about a nonexistent one returns the same, you're fine. If they differ observably — in latency, in phrasing, in a "0 of 3 results filtered" message — that's an information leak.
3. **Cached answers ignoring permissions.** A response cache keyed only on the query text will serve one user's permitted answer to another. **The cache key must include the permission context** — this is the classic cache-poisoning leak (Q97).
4. **Citations to inaccessible documents.** Even if content is filtered, a citation revealing a document title the user can't see is a leak.

**The audit requirement:** log every retrieval with user, query, and the document IDs returned. For regulated data, retrieval *is* access, and the agent's queries are accesses that must be auditable (Q326).

---

## 387. Incremental index updates?

Q358 covers the mechanism. The pipeline design:

**Event-driven, not batch:**
```
document change → outbox row (same txn) → relay → index queue → indexer worker
```
Using the outbox (Q238) means the index update can't be lost when the document write succeeds — the dual-write problem applied to search.

**The indexer's steps:**
1. Fetch the current document version
2. Chunk (structure-aware)
3. Compute `content_hash` per chunk
4. **Diff against existing chunks** — reuse embeddings where the hash matches
5. Embed only new/changed chunks, batched
6. Atomic version swap in one transaction (Q358)
7. Mark indexed, record `indexed_at`

**Why incremental rather than full re-index:** a one-line edit to a 200-page document should not cost 400 embedding calls. Hash-based diffing typically reuses 90%+ for small edits.

**The operational requirements:**
- **Idempotency** on `(document_id, version)` — at-least-once delivery means duplicates (Q234)
- **Index lag monitoring** — the age of the oldest unindexed change. **A stalled indexer is completely silent otherwise**: the application works, search works, and the results are just quietly stale.
- **Ordering per document.** Two rapid edits must not apply out of order. Partition by `document_id`, or guard with a version check: `WHERE version < $new`.
- **Backpressure.** A bulk import of 10,000 documents must not saturate the embedding API and starve interactive re-indexing. Separate queues by priority.
- **Rate limiting** on the embedding provider, shared across workers (Q249).

**The boundary-shift caveat** (Q358): if chunk boundaries move, hashes miss even for unchanged text. Structure-aware chunking anchors boundaries to headings rather than offsets, which makes diffing far more effective — a practical argument for Q351 beyond retrieval quality.

---

## 388. Retrieval observability?

**What to instrument — the point is that retrieval is invisible without it, which is why teams misdiagnose their systems** (Q354).

**Per-query trace, one span per stage:**
```
rag.query
├── rewrite_query        (latency, tokens)
├── embed_query          (latency, cache_hit)
├── vector_search        (latency, k, top_score, filter)
├── bm25_search          (latency, k, top_score)
├── fuse                 (candidates_in, candidates_out)
├── rerank               (latency, score_delta, reordering)
├── threshold            (passed, refused)
└── generate             (ttft, tokens, cost, citations_valid)
```

**The metrics that actually change decisions:**

| Metric | Signals |
|---|---|
| Top-1 and top-k score distribution | Drift in corpus or model (Q370) |
| Refusal rate | Threshold miscalibration, or a corpus gap |
| Chunks retrieved per query | Filter behaviour |
| **Rerank reordering magnitude** | How much value the reranker adds |
| Citation validity rate | Generation quality regression (Q368) |
| Zero-result rate | Filter bugs, ANN + filter interaction (Q414) |
| Per-stage latency p50/p95 | Where the budget goes (Q376) |
| Cost per query | (Q377) |
| Index lag | Staleness (Q387) |
| Cache hit rate | Embedding and semantic caches |

**Log the retrieved chunk IDs per query.** This is what makes the retrieval-vs-generation diagnostic possible after the fact (Q375) — without it, you cannot answer "was the right chunk in context?" for a query that failed last Tuesday.

**Feedback capture.** Thumbs up/down, tied to the query, the retrieved chunk IDs, and the answer. **This is how the golden set grows** — negative feedback with the retrieval trace attached is a labelled failure case, ready to add to the eval suite (Q371).

**Alert on:** refusal rate shifting, citation validity dropping, index lag rising, zero-result rate spiking. Each maps to a specific bug class, which is what makes them worth alerting on rather than merely charting.

---

## 389. Evaluation pipeline?

Full treatment in Document 10. The RAG-specific pipeline:

**The three-layer structure** (Q371): retrieval in isolation, generation given correct context, end-to-end. Measured separately because a single number can't tell you what to fix.

**The datasets:**
1. **Golden set** — 50–100 questions with labelled relevant chunks and reference answers
2. **Unanswerable set** — 15–20 questions the corpus can't answer, measuring refusal (Q369)
3. **Adversarial set** — cases where training knowledge contradicts the corpus
4. **Regression set** — every production failure you've fixed, so it can't come back

**That fourth one is the most valuable over time** and the one teams skip. Every bug becomes a permanent test.

**Running it:**
```python
def run_eval(config) -> EvalReport:
    return EvalReport(
        recall_at_5   = recall_at_k(golden, config.retriever, 5),
        recall_at_20  = recall_at_k(golden, config.retriever, 20),
        ndcg_at_5     = ndcg(golden, config.retriever, 5),
        faithfulness  = faithfulness(golden, config.pipeline),
        citation_validity = citation_check(golden, config.pipeline),
        refusal_rate  = refusal_rate(unanswerable, config.pipeline),
        cost_per_query = ..., p95_latency = ...,
    )
```

**Gate changes in CI.** Any change to chunking, embedding model, k, retrieval method, reranker, or prompt runs the suite and blocks on regression against the current baseline (Q329, Q433).

**Report deltas, not absolutes.** "recall@5: 0.84 → 0.91 (+0.07)" against the baseline is what a reviewer needs.

**Handle non-determinism:** run generation-dependent metrics N times and report the mean and spread. A single run on a non-deterministic system produces noise you'll mistake for signal (Q439).

**Version everything in the report** — prompt hash, model version, chunking config, index version. A number without its configuration is uninterpretable three weeks later.

---

## 390. Ingestion pipeline?

**Stages, each independently queued, scaled, and retried** — because their resource profiles differ by orders of magnitude (Q257):

```
source (S3/upload/API/crawl)
  → extract text (PDF, DOCX, HTML, OCR)
  → normalise & clean (whitespace, boilerplate, encoding)
  → chunk (structure-aware)
  → enrich (title, section path, dates, entities, permissions)
  → dedupe (content_hash)
  → embed (batched, cached, rate-limited)
  → index (upsert chunks + tsvector, atomic version swap)
```

**The design decisions:**

1. **Separate queues per stage.** Extraction of a 500-page PDF is CPU-heavy; embedding is external-API-bound and rate-limited; indexing is database-bound. One queue means the slowest stage blocks everything.
2. **Persist each stage's output** so a failure resumes rather than restarts (Q257, Q303).
3. **Idempotent on `(document_id, version, stage)`** — at-least-once delivery guarantees duplicates.
4. **Batch embeddings** — most APIs accept 100+ texts per call, which is dramatically cheaper and faster than one at a time.
5. **Shared rate limiter** across workers against the embedding provider (Q249).
6. **Dead-letter with the document reference**, so a parse failure can be replayed after a parser fix without re-uploading.

**Extraction is where quality is actually determined**, and it's underrated: a badly-extracted PDF — lost table structure, jumbled multi-column text, missing headings — produces bad chunks that no amount of retrieval tuning recovers. **Invest here first.** OCR quality for scanned documents is a genuine ceiling on the whole system.

**Poison documents:** a malformed PDF that crashes the parser will retry forever and consume a worker permanently. Classify parse errors as terminal, dead-letter immediately, alert (Q199).

**Monitoring:** documents pending per stage, oldest pending age, extraction failure rate by file type, embedding cost per document, index lag.

---

## 391. Caching in RAG?

**Four distinct caches, with very different risk profiles — the point is that they're not interchangeable.**

**1. Embedding cache.** Key: `hash(text) + model_version`. **Zero risk** — embeddings are deterministic, so a hit is exactly correct. Cache indefinitely. Applies to corpus chunks and repeated queries alike. **Always do this.**

**2. Retrieval cache.** Key: `hash(query) + filters + corpus_version`. Caches the retrieved chunk IDs. Low risk if the corpus version is in the key. Short TTL.

**3. Response cache (exact match).** Key: `hash(query) + user_permission_context + corpus_version`. Low risk. **The permission context in the key is mandatory** — without it you serve one user's answer to another, which is the classic cache-poisoning leak (Q386).

**4. Semantic cache.** Embed the query; if a cached query is similar above a threshold, return its answer. **Enormous savings, and genuinely dangerous.**

**Why semantic caching deserves the warning:**
```
Cached: "What is the waiting period for my health policy?" → "30 days"
Query:  "What is the waiting period for my motor policy?"  → similarity 0.94
```
A threshold of 0.90 returns a confidently wrong answer with a real citation. **The similarity threshold is doing the job of a correctness check, and it isn't one.**

**If you use semantic caching:**
- Set the threshold high (0.95+) and **calibrate it against labelled pairs**, not intuition
- Include tenant and permission context in the key
- **Exclude any query containing an identifier** — policy numbers, dates, amounts. Those are exactly where near-miss matches are catastrophic
- Measure the false-hit rate on your golden set before enabling it
- Short TTL

**The honest framing:** the first three caches are engineering. Semantic caching is a quality/cost trade-off that requires evaluation to justify, and it's the one place in a RAG pipeline where an optimisation can silently make answers *wrong* rather than merely stale.

---

## 392. Reindexing strategy?

**Three distinct triggers, three different procedures — conflating them is why re-indexing goes badly:**

**1. Document changed** → incremental, hash-diffed (Q358, Q387). Routine, event-driven, seconds to minutes.

**2. Chunking strategy changed** → full re-chunk and re-embed. All content hashes change because boundaries moved.

**3. Embedding model changed** → full re-embed, but chunk text is unchanged (Q357).

**The zero-downtime procedure for 2 and 3:**

1. **New column or new table**, versioned. Never mutate in place.
2. **Backfill in rate-limited batches**, checkpointed and resumable. Monitor replication lag and dead-tuple accumulation (Q165).
3. **Build the index `CONCURRENTLY`** so writes aren't blocked.
4. **Evaluate against the golden set before switching.** A new configuration is not automatically better — **be willing to abandon the migration**, which is the whole reason to evaluate before cutting over.
5. **Canary** a percentage of production traffic, comparing quality metrics.
6. **Switch via config, not deploy**, so rollback is instant.
7. **Soak, then drop** the old column and index.

**The costs to plan:** double vector storage during migration (vector indexes are large), a real embedding API bill, hours to days of wall time, and continued incremental updates against *both* indexes during the transition — which is the part people forget and which causes divergence.

**The prerequisite that makes any of this possible:** store chunk *text* as the source of truth and `embedding_model_version` on every row. If you only stored vectors, you cannot re-embed and you cannot migrate. **Design for this on day one**, because by the time you need it, retrofitting means re-ingesting from source.

---

## 393. Deletion in RAG?

**Deletion is harder in RAG than in a normal database because content propagates into more places than you'd expect.**

**Everywhere a deleted document's content can persist:**
1. `chunks` rows and their embeddings
2. The vector index (HNSW graphs don't reclaim deleted nodes immediately)
3. The full-text `tsvector` index
4. Embedding cache entries
5. Response and semantic caches containing generated text from it
6. Conversation history where it was retrieved and quoted
7. Logs and traces containing chunk content
8. Eval sets and golden data built from it
9. Database backups
10. Any derived summaries or knowledge graphs

**Soft delete for operational deletion:**
```sql
UPDATE chunks SET deleted_at = now() WHERE document_id = $1;
-- every query: AND deleted_at IS NULL
```
Reversible, doesn't disturb the index, safe for in-flight queries.

**Hard delete for GDPR/erasure**, which must be a durable multi-step workflow, not a single statement:
```
mark for deletion → delete chunks → rebuild/vacuum vector index
→ purge embedding cache by content hash → invalidate response caches
→ purge from conversation histories → scrub logs (or rely on retention)
→ record completion in an audit log
```

**Model it as a workflow with verification**, because partial deletion is the failure mode: each step idempotent, tracked, and a final verification pass that searches for the content and confirms it's unreachable. **A deletion you didn't verify is a hypothesis.**

**The parts people miss:**
- **Conversation history.** If a chunk was quoted in a past answer, that content persists in the message log. It must be scrubbed or the history deleted.
- **Backups.** You usually cannot delete from backups. The defensible position is a documented retention window after which backups expire, disclosed in your privacy policy.
- **Index bloat.** Deleted vectors leave dead entries in HNSW graphs. Periodic `REINDEX CONCURRENTLY` reclaims the space (Q116).

**Multi-tenancy:** tenant offboarding is bulk deletion across all of the above, and it's a compliance commitment. **Build and test it before you need it** — discovering during an offboarding request that your deletion path is incomplete is a bad time to find out (Q385).

---

*End of Document 08. Next: Document 09 — pgvector (questions 394–417).*
