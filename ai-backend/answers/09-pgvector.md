# Document 09 — pgvector (Questions 394–417)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 394. What is pgvector?

**Definition.** A PostgreSQL extension adding a `vector` column type, distance operators, and approximate nearest-neighbour index types (HNSW and IVFFlat).

```sql
CREATE EXTENSION vector;

CREATE TABLE chunks (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL,
  document_id UUID NOT NULL,
  content TEXT NOT NULL,
  embedding vector(1536)
);

CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops);
```

**Why it matters architecturally.** It removes the need for a separate vector database. Your embeddings live beside the metadata, permissions, and documents they belong to — same transaction, same backup, same access control, same SQL.

**What it gives you that a dedicated store doesn't:**
- **Transactional consistency.** Insert a chunk and its embedding atomically. No dual-write problem (Q245).
- **Arbitrary filtering and joins.** `WHERE tenant_id = $1 AND effective_date <= now()` is ordinary SQL with ordinary indexes.
- **One system to operate** — backups, replication, monitoring, access control already exist.

**Types beyond `vector`:** `halfvec` (16-bit floats, half the storage), `bit` (binary quantised), and `sparsevec` (sparse vectors). `halfvec` in particular is a cheap win at scale — roughly half the memory with minimal recall loss on most workloads.

**Limits to know:** `vector` supports up to 2,000 dimensions for indexing (16,000 for storage); `halfvec` raises the indexable limit to 4,000. If your embedding model outputs 3,072 dimensions, you either use `halfvec`, or truncate (many modern models support Matryoshka truncation), or you can't index it.

---

## 395. Vector column type?

**Definition.** A fixed-length array of 4-byte floats with a declared dimension. `vector(1536)` stores 1,536 floats.

**Storage:** `4 × dimensions + 8` bytes. A 1,536-dimension vector is ~6.1 KB. **One million chunks is ~6 GB just for vectors**, before indexes — and the HNSW index adds substantially more.

**That arithmetic is the one to have ready**, because it drives every scaling decision in this section.

**The variants and when to use them:**

| Type | Storage | Use |
|---|---|---|
| `vector(n)` | 4n bytes | Default |
| `halfvec(n)` | 2n bytes | **Halves memory; minimal recall loss.** Worth testing at scale |
| `bit(n)` | n/8 bytes | Binary quantisation — 32× smaller, real recall cost, useful as a first-stage filter |
| `sparsevec` | Non-zero elements only | Sparse embeddings (SPLADE) |

**Constraints:**
- Dimension is fixed at declaration. Changing it means a new column, not an `ALTER` (Q357).
- Dimensions must match exactly on comparison, or you get an error — which is at least loud, unlike mixing vectors from different models at the *same* dimension, which fails silently.
- `NULL` embeddings are allowed and are skipped by index scans. Useful during a backfill: chunks exist and are text-searchable before they're embedded.

**Important:** pgvector does **not** normalise for you. If you intend to use inner product as a cosine equivalent, normalise at write time yourself (Q396). Assuming your embedding API returns normalised vectors without checking is a silent correctness bug.

---

## 396. Distance operators?

| Operator | Metric | Index opclass | Notes |
|---|---|---|---|
| `<->` | L2 (Euclidean) | `vector_l2_ops` | |
| `<=>` | Cosine **distance** | `vector_cosine_ops` | `1 - cosine_similarity`, range 0–2 |
| `<#>` | **Negative** inner product | `vector_ip_ops` | Negated so that smaller = more similar |
| `<+>` | L1 (Manhattan) | `vector_l1_ops` | Rarely used |

**All operators return a value where smaller means closer**, so `ORDER BY embedding <=> $1 LIMIT 10` gives nearest neighbours. `<#>` is negated specifically to preserve that convention — which is why an inner-product "distance" is negative, and why converting it to a similarity means negating it back.

**Converting to similarity for display:**
```sql
SELECT 1 - (embedding <=> $1) AS cosine_similarity   -- 0..1, higher is better
SELECT (embedding <#> $1) * -1  AS inner_product
```

**The rule that causes the most silent bugs: the operator in `ORDER BY` must match the index's opclass.** An index built with `vector_cosine_ops` will not be used by a query ordering on `<->`. There's no error — you just get a sequential scan over every row, and the query is slow in a way that looks like a capacity problem. **Check `EXPLAIN` for `Index Scan using ...` and not `Seq Scan`.**

**Which to choose:** cosine for most embedding models (Q274). **If your vectors are normalised, inner product gives identical ranking and is faster to compute** — normalise once at write time and use `<#>`. This is the standard production configuration and a legitimate performance win.

---

## 397. HNSW index?

**Definition.** Hierarchical Navigable Small World — a multi-layer proximity graph. Upper layers are sparse and used for long jumps; lower layers are dense and used for local refinement. Search descends from the top, greedily moving toward the query.

```sql
CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

**Why it's the default choice:**
- **Best recall/speed trade-off** of the available methods
- **No training step** — unlike IVFFlat, it doesn't need representative data before building
- **Handles incremental inserts well** — new vectors are inserted into the graph directly
- **Query time is roughly logarithmic** in the number of vectors

**The parameters:**

| Parameter | Meaning | Effect |
|---|---|---|
| `m` | Max connections per node per layer (default 16) | Higher = better recall, more memory, slower build |
| `ef_construction` | Candidate list size during build (default 64) | Higher = better graph quality, much slower build |
| `hnsw.ef_search` | Candidate list size at query time (default 40) | **Higher = better recall, slower query. Tunable per query** |

**The property that makes HNSW practical:** `ef_search` is a *runtime* setting. You can trade recall for latency per query without rebuilding anything:
```sql
SET LOCAL hnsw.ef_search = 100;
```
That's a genuinely useful operational lever — raise it for a quality-sensitive path, lower it for an autocomplete.

**The costs to be honest about:**
- **Build time** is long. Millions of vectors take hours.
- **Memory.** The index should fit in `shared_buffers` or query latency degrades sharply. Roughly `(4 × dims + 8 × m + 8) × rows` bytes as a working estimate.
- **Deleted vectors leave dead graph nodes** until a reindex reclaims them (Q393).

---

## 398. IVFFlat index?

**Definition.** Inverted File with Flat compression. K-means clusters the vectors into `lists` partitions, each with a centroid. A query compares against centroids, then exhaustively searches the `probes` nearest partitions.

```sql
CREATE INDEX ON chunks USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 1000);
SET ivfflat.probes = 10;
```

**Parameters:**
- **`lists`** — number of clusters. Rule of thumb: `rows / 1000` for up to 1M rows, `sqrt(rows)` beyond that.
- **`ivfflat.probes`** — clusters searched per query. Higher = better recall, slower. Start at `sqrt(lists)`.

**Why it exists alongside HNSW:**
- **Much faster to build** — often 10× faster than HNSW
- **Much smaller** — roughly the size of the vectors themselves plus centroids
- **Lower memory** requirement

**The critical limitation, and the reason HNSW is usually preferred: IVFFlat requires training data.** The index must be built *after* representative vectors exist, because k-means needs them to find centroids. **Building it on an empty or small table produces useless clusters**, and it doesn't error — you just get bad recall forever.

Worse, the clustering is **static**. As data grows and its distribution shifts, the original centroids become progressively less representative and recall degrades silently. **IVFFlat needs periodic rebuilding**; HNSW does not.

**When IVFFlat is the right choice:** very large static corpora where build time and index size dominate, memory is constrained, and the data distribution is stable. Otherwise, HNSW.

---

## 399. HNSW vs IVFFlat?

| | HNSW | IVFFlat |
|---|---|---|
| Build time | **Slow** (hours at millions) | Fast |
| Index size | **Large** | Small |
| Memory | High — wants to fit in RAM | Moderate |
| Query speed | **Fast** | Moderate |
| Recall at equal speed | **Better** | Worse |
| Requires training data | **No** | **Yes** |
| Incremental inserts | **Handles well** | Degrades over time |
| Needs periodic rebuild | No | **Yes** |
| Runtime recall tuning | `ef_search` | `probes` |

**The decision rule:** **default to HNSW.** Choose IVFFlat only when you have a specific constraint — index size, memory ceiling, or a build-time window you can't exceed — and the corpus is large and static.

**The two facts that decide it in practice:**

1. **IVFFlat's training requirement is an operational trap.** You cannot create the index before loading data. In a pipeline that ingests incrementally, this means a separate "build the index once we have enough data" step, and if anyone rebuilds on a near-empty table the clusters are garbage and nothing tells you.

2. **HNSW's build cost is a one-time price; IVFFlat's degradation is recurring.** Hours of build time once beats a recall metric that quietly declines for months.

**The middle option worth mentioning:** for small tables (under ~10,000 vectors), use **no index at all**. Exact search over 10,000 vectors is a few milliseconds and gives perfect recall. **An ANN index on a small table adds approximation error for no meaningful speedup** — and people build them reflexively.

---

## 400. Index parameters?

**HNSW build parameters:**

| Parameter | Default | Raise it when |
|---|---|---|
| `m` | 16 | High dimensions, or recall is insufficient at high `ef_search`. 32–48 for demanding workloads |
| `ef_construction` | 64 | Recall matters more than build time. 128–256 typical for production |

Higher `m` costs memory permanently. Higher `ef_construction` costs build time only — **so raise `ef_construction` first**, since it improves graph quality at no runtime cost.

**Query-time:**
```sql
SET LOCAL hnsw.ef_search = 100;      -- default 40
```
Must be ≥ your `LIMIT`. **This is the primary recall/latency dial in production**, and being able to set it per query is HNSW's most useful operational property.

**IVFFlat:**
```sql
WITH (lists = <rows/1000 up to 1M, else sqrt(rows)>)
SET ivfflat.probes = <sqrt(lists) as a starting point>;
```

**Build performance settings that matter more than people expect:**
```sql
SET maintenance_work_mem = '8GB';     -- huge effect on build time
SET max_parallel_maintenance_workers = 7;
```
An HNSW build that spills out of `maintenance_work_mem` is dramatically slower. This is the single most impactful build-time setting.

**How to tune, and this is the answer:** **measure recall against exact search on your own data.** Build a small ground-truth set by running exact queries (`SET enable_indexscan = off`), then sweep `ef_search` and compare:
```python
recall = len(set(ann_results) & set(exact_results)) / len(exact_results)
```
Plot recall against latency and pick your operating point. **Defaults are a starting guess, not a configuration** — and "I measured recall against exact search at ef_search of 40/80/120" is a much stronger answer than quoting parameter values.

---

## 401. Approximate vs exact search?

**Exact (flat)** — compare the query against every vector. Perfect recall, O(n).
**Approximate (ANN)** — traverse an index structure. Sub-linear, with recall < 1.

**The trade-off in numbers:** on a million vectors, exact search is hundreds of milliseconds to seconds; HNSW at `ef_search=40` is single-digit milliseconds at perhaps 95% recall. **You give up ~5% recall for a 100× speedup.**

**When exact is correct:**
- **Under ~10,000 vectors** — it's already fast, and an index adds error for nothing
- After a selective filter reduces candidates to a small set (Q414)
- When building ground truth to measure ANN recall (Q400)
- When 100% recall is a hard requirement

**Forcing exact search:**
```sql
SET LOCAL enable_indexscan = off;      -- or drop the index
```

**The point most people miss, and it's worth making:** the recall loss from ANN is usually **irrelevant compared to the recall loss from your chunking and embedding choices.** If recall@5 against your golden set is 0.82, the ANN index contributing 0.97 of its own recall is not your bottleneck. **Tuning `ef_search` from 40 to 200 to chase the last 2% is optimising the wrong thing** while chunking strategy sits untested (Q378).

Say that in an interview. It shows you can distinguish a real bottleneck from a tunable knob.

---

# L2 — Engineering

## 402. When is ANN acceptable?

**Almost always in RAG**, and the reasoning is what matters:

1. **The downstream consumer is a reranker or an LLM**, both of which tolerate imperfect candidate ordering. Missing the 8th-best result out of 30 candidates that get reranked to 5 has essentially no effect.
2. **Your two-stage architecture already absorbs it.** Retrieve 30 with ANN, rerank to 5 — the reranker fixes ordering errors, and 95% recall at k=30 means the relevant chunk is almost certainly in the pool (Q346).
3. **The larger error sources dominate.** Chunking, embedding model choice, and query formulation each cost more recall than ANN approximation (Q401).

**When ANN is *not* acceptable:**
- **Exhaustive requirements** — legal discovery, compliance sweeps, "find every document mentioning X." Missing one is a failure, and here you should use lexical search anyway.
- **Deduplication** — finding near-duplicates requires reliable nearest-neighbour results.
- **Small corpora** where exact is free.
- **Highly filtered queries** where the filter has already reduced candidates to hundreds (Q414).

**The way to make the decision defensible:** measure ANN recall against exact on your own data (Q400), and compare that number to your end-to-end recall@k. If ANN recall is 0.97 and pipeline recall@5 is 0.82, ANN contributes ~3% of a 18% shortfall. **That comparison tells you it isn't the problem**, and it takes twenty minutes to produce.

**Compensate cheaply** by over-fetching: request k=30 when you need 5. ANN recall at k=30 is much higher than at k=5, and the reranker discards the excess anyway.

---

## 403. Index build cost?

**HNSW build is expensive and it surprises people.**

**What drives it:** `rows × dimensions × ef_construction × m`, roughly. A million 1,536-dimension vectors with default parameters takes on the order of an hour; with `ef_construction=256` it can be several hours.

**The settings that dominate build time:**
```sql
SET maintenance_work_mem = '8GB';           -- the biggest lever
SET max_parallel_maintenance_workers = 7;   -- plus max_parallel_workers
```
**If the build spills out of `maintenance_work_mem` it becomes dramatically slower.** Sizing this correctly is the difference between one hour and six.

**Build strategy that matters operationally:**
- **Load data first, then build the index.** Building incrementally as you insert is far slower than one bulk build.
- **`CREATE INDEX CONCURRENTLY`** to avoid blocking writes — roughly 2–3× slower and takes two table passes, but it doesn't take an `ACCESS EXCLUSIVE` lock (Q165).
- **`CONCURRENTLY` can fail and leave an `INVALID` index.** Check `pg_index.indisvalid` afterwards; an invalid index is silently unused.

**Index size:** roughly `(4 × dims + 8 × m + 8) × rows`. For a million 1,536-dim vectors at `m=16`: ~6.3 GB of vectors plus ~2 GB of graph structure. **Both should fit in memory** or query latency degrades badly.

**The planning consequence:** re-embedding and re-indexing a corpus (Q392) is a multi-hour operation requiring double the storage during transition. **This is why you build the new index concurrently, evaluate, and only then switch** — and why "just change the embedding model" is a project, not a config change.

---

## 404. Query performance?

**The checklist, in the order you should check it:**

**1. Is the index actually being used?**
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id FROM chunks ORDER BY embedding <=> $1 LIMIT 10;
```
Look for `Index Scan using chunks_embedding_idx`. **`Seq Scan` means the index was ignored**, and the usual causes are:
- Operator/opclass mismatch (Q396) — the single most common cause
- No `ORDER BY` on the distance expression
- No `LIMIT` (ANN indexes require one)
- A filter that made the planner prefer a scan

**2. Is the index in memory?** `BUFFERS` showing `shared read` rather than `shared hit` means disk I/O. **Vector indexes are large and random-access; a cold index is orders of magnitude slower.** `effective_cache_size` and `shared_buffers` matter more here than for typical workloads.

**3. Is `ef_search` too high?** It's a direct latency multiplier. Measure whether the recall it buys is worth it (Q400).

**4. Is a filter degrading it?** (Q414) — the hardest case.

**5. Is the returned payload large?** `SELECT *` returns the 6 KB embedding for every row. **Select only what you need** — this alone can dominate query time for larger `LIMIT` values.

```sql
SELECT id, content FROM chunks         -- not SELECT *
ORDER BY embedding <=> $1 LIMIT 10;
```

**6. Bloat.** Heavy deletion leaves dead graph nodes; `REINDEX CONCURRENTLY` reclaims them.

**Typical healthy latency:** single-digit milliseconds for a million vectors with a warm HNSW index. If you're seeing hundreds of milliseconds, one of the six above is the cause — almost always #1 or #2.

---

## 405. Filtering with vector search?

**The core problem: pgvector's ANN indexes and your `WHERE` clause don't compose cleanly.**

PostgreSQL has two strategies and picks one:

**A. Index scan on the vector index, then filter.** Traverses the HNSW graph, applies the `WHERE` to what it finds. **If the filter is selective, most graph nodes are discarded and you may get far fewer than `LIMIT` results — or none.** The index has no knowledge of your filter.

**B. Filter first, then exact search.** If the planner estimates the filter is very selective, it uses a B-tree on `tenant_id`, gets a small set, and does exact distance computation. **This is correct and often fast** — and it's what you want for a selective filter.

**The failure is when the planner chooses A with a selective filter.** You ask for 10 results and get 2, silently. No error. Your RAG answer is worse and nothing indicates why.

**pgvector's mitigation: iterative index scans** (0.8+):
```sql
SET hnsw.iterative_scan = relaxed_order;   -- or strict_order
SET hnsw.max_scan_tuples = 20000;
```
The scan continues past the initial candidate set until enough rows survive the filter. **This largely solves the problem** and is the modern answer — worth knowing that it exists, because pre-0.8 advice on this is everywhere and now outdated.

**The other approaches:**
- **Partial indexes per tenant** — `CREATE INDEX ... WHERE tenant_id = $x`. Filter is implicit; recall is unaffected. Best isolation, doesn't scale past a modest tenant count.
- **Partitioned tables** by tenant, each with its own index. Scales further.
- **Over-fetch** — request 5–10× and filter in the application. Crude but effective.

**Always verify with `EXPLAIN` which strategy you actually got**, and check that you're getting the number of rows you asked for. A query returning fewer rows than `LIMIT` is the signal (Q414).

---

## 406. Hybrid queries?

**Combining vector similarity with lexical search in one SQL statement** — the pgvector advantage, since both live in the same database (Q348).

```sql
WITH vec AS (
  SELECT id, row_number() OVER (ORDER BY embedding <=> $1) AS rank
  FROM chunks
  WHERE tenant_id = $3 AND deleted_at IS NULL
  ORDER BY embedding <=> $1
  LIMIT 50
),
lex AS (
  SELECT id, row_number() OVER (ORDER BY ts_rank_cd(tsv, q) DESC) AS rank
  FROM chunks, plainto_tsquery('english', $2) q
  WHERE tsv @@ q AND tenant_id = $3 AND deleted_at IS NULL
  LIMIT 50
)
SELECT c.id, c.content,
       COALESCE(1.0/(60 + vec.rank), 0) + COALESCE(1.0/(60 + lex.rank), 0) AS rrf
FROM vec
FULL OUTER JOIN lex USING (id)
JOIN chunks c USING (id)
ORDER BY rrf DESC
LIMIT 20;
```

**The details that matter:**

1. **`FULL OUTER JOIN`**, not inner — a document found by only one retriever must still appear. An inner join silently discards exactly the results hybrid search exists to capture.
2. **`row_number()`, not raw scores.** RRF fuses ranks precisely because BM25 and cosine scores are on incomparable scales (Q361).
3. **`LIMIT` inside each CTE**, so each retriever produces a bounded candidate set.
4. **The same filters in both branches** — a filter applied to only one is a security hole.
5. **`ORDER BY` repeated inside the vector CTE** alongside the window function, or the index isn't used.

**Required indexes:**
```sql
CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops);
CREATE INDEX ON chunks USING gin (tsv);
CREATE INDEX ON chunks (tenant_id) WHERE deleted_at IS NULL;
```

**Maintain `tsv` as a generated column** so it can't drift from `content`:
```sql
tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
```

**The value:** one query, one round trip, one transaction, consistent filtering. Doing this across a separate vector database and a separate search engine means three systems and a fusion step in application code.

---

## 407. Index maintenance?

**What degrades over time:**

1. **Dead tuples from deletes and updates.** MVCC means an updated row creates a new version; the old graph node remains until vacuumed (Q139). Heavy churn inflates the index.
2. **HNSW graph quality.** Nodes deleted from the graph leave gaps in connectivity. Unlike a B-tree, HNSW doesn't rebalance, so recall degrades gradually.
3. **IVFFlat centroid drift** — the k-means clustering is static and becomes unrepresentative as the distribution shifts (Q398).

**Maintenance operations:**
```sql
VACUUM ANALYZE chunks;                        -- routine
REINDEX INDEX CONCURRENTLY chunks_embedding_idx;   -- rebuild, non-blocking
```

**`REINDEX CONCURRENTLY` is the important one.** It rebuilds without an exclusive lock, at the cost of temporarily holding both indexes — so you need double the index storage available. Schedule it after significant deletion or on a periodic cadence for high-churn tables.

**Autovacuum tuning for vector tables:**
```sql
ALTER TABLE chunks SET (autovacuum_vacuum_scale_factor = 0.05);
```
The default of 0.2 means vacuum waits until 20% of rows are dead. For a large chunks table that's a lot of bloat in a large index.

**What to monitor:**
```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables WHERE relname = 'chunks';

SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes WHERE relname = 'chunks';
```
**`idx_scan = 0` on your vector index means it's never being used** — almost certainly an operator mismatch (Q396), and a genuinely common silent failure.

**Also monitor recall over time** against a fixed ground-truth set. It's the only way to detect gradual graph degradation, and nothing else will tell you.

---

## 408. Storage growth?

**The arithmetic to have ready:**

| Component | Per row (1,536 dims) |
|---|---|
| Vector | ~6.1 KB |
| HNSW graph | ~2.1 KB (at `m=16`) |
| Chunk text (~600 tokens) | ~2.4 KB |
| `tsvector` | ~1–2 KB |
| Metadata + row overhead | ~0.3 KB |
| **Total** | **~12–14 KB per chunk** |

**One million chunks ≈ 13 GB. Ten million ≈ 130 GB.** And that's before indexes on metadata, WAL, and replicas.

**The growth drivers:**
- Documents × chunks per document
- **Overlap** — 20% overlap is 20% more chunks (Q353)
- Multiple embedding versions coexisting during migration — **doubles vector storage** (Q392)
- Soft-deleted rows awaiting purge

**Reduction options:**

| Technique | Saving | Cost |
|---|---|---|
| `halfvec` | **50% of vector storage** | Minimal recall loss — test it |
| Lower-dimension model (or Matryoshka truncation) | Proportional | Some quality loss — measure |
| Binary quantisation | 32× | Substantial recall loss; use as a first-stage filter with re-ranking on full vectors |
| Reduce overlap | Proportional | Boundary fragmentation |
| Partition and archive old documents | Large | Complexity |
| IVFFlat instead of HNSW | Index only | Worse recall/speed (Q399) |

**`halfvec` is the first thing to try** — half the vector storage with usually negligible recall impact. Measure it against your golden set and it's often free.

**The constraint that actually binds: memory, not disk.** Vector index performance depends on the index being cached. 130 GB of index on a machine with 64 GB of RAM means constant disk reads and latency measured in hundreds of milliseconds. **Plan RAM, not disk** — that's the number that determines when pgvector stops being viable for you.

---

## 409. Backup considerations?

**pgvector data is backed up by your existing PostgreSQL backups** — that's the main advantage over a separate vector store, and it's worth stating plainly. No second backup system, no risk of the two diverging.

**The practical considerations:**

1. **Size.** Vector data dominates backup size and duration. A 130 GB database backs up and restores slowly.

2. **Indexes are not in logical backups.** `pg_dump` stores index *definitions*, not their contents. **On restore, every HNSW index is rebuilt from scratch** — which can take hours (Q403). Your restore time is dominated by index builds, not data loading. **Measure your actual restore time**, because "we have backups" and "we can be back in 20 minutes" are very different claims.

3. **Physical backups (`pg_basebackup`, WAL archiving, snapshots) include the index files**, so restore is far faster. **For a large vector database, physical backups are strongly preferred** for exactly this reason.

4. **Point-in-time recovery** works normally, since vector writes go through WAL like everything else.

5. **Replicas** carry the index. A replica is your fastest recovery path.

**The mitigation worth mentioning:** you can always rebuild embeddings from chunk text if you have the text (Q392). So the *irreplaceable* data is the source documents and the chunk text; the vectors are derived and reconstructible. **That means a corrupted index is recoverable and a lost document corpus is not** — which should shape what you protect most carefully.

**Test the restore.** An untested backup of a 130 GB vector database is a hypothesis, and the index-rebuild step is exactly the thing that surprises people during an actual incident.

---

# L3 — Failure and scale

## 410. Slow vector queries?

**Diagnose in this order:**

**1. Confirm the index is used.**
```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ... ORDER BY embedding <=> $1 LIMIT 10;
```
`Seq Scan` → operator/opclass mismatch (Q396), missing `LIMIT`, missing `ORDER BY` on the distance expression, or a filter changed the plan. **This is the most common cause and the easiest to miss** because there's no error.

**2. Check `BUFFERS` for disk reads.** `shared read` high means the index isn't cached. Vector index access is random, so a cold index is catastrophically slower than a warm one. Increase `shared_buffers`, add RAM, or reduce index size with `halfvec` (Q408).

**3. Check `ef_search`.** It's a direct latency multiplier. If someone raised it to 400 chasing recall, that's your answer.

**4. Check the payload.** `SELECT *` ships a 6 KB embedding per row. Select only needed columns.

**5. Check for filter interaction** (Q405, Q414) — a selective filter can force excessive graph traversal, especially with iterative scans enabled and a high `max_scan_tuples`.

**6. Check bloat.** `n_dead_tup` high → `VACUUM`, then `REINDEX CONCURRENTLY` if the graph is degraded.

**7. Check concurrency.** Vector search is CPU-intensive. Many concurrent queries saturate CPU in a way that ordinary OLTP queries don't. Watch for CPU saturation and consider a read replica dedicated to search (Q169).

**The realistic target:** single-digit milliseconds for a million vectors with a warm index and default `ef_search`. Anything in the hundreds means one of the above, and it's usually #1 or #2.

---

## 411. Index not used?

**The causes, most common first:**

**1. Operator doesn't match the opclass.** Index built with `vector_cosine_ops`, query orders by `<->`. **Silent — no error, just a sequential scan.** Fix: match them, or build multiple indexes if you genuinely need multiple metrics.

**2. No `ORDER BY` on the distance expression.** ANN indexes only serve ordered nearest-neighbour queries. `WHERE embedding <=> $1 < 0.3` cannot use the index — it's a range predicate, not a nearest-neighbour search.

**3. No `LIMIT`.** Without one, the planner must produce all rows ordered by distance, which the ANN index can't do — it returns approximate top-k, not a full sort.

**4. The distance expression isn't identical.** `ORDER BY (embedding <=> $1) * 2` or an expression wrapped in a function defeats index matching.

**5. Selective filter changed the plan** — the planner chose filter-then-exact, which may be correct (Q405).

**6. Small table.** With few rows, a sequential scan genuinely is cheaper and the planner is right (Q129).

**7. Invalid index** from a failed `CREATE INDEX CONCURRENTLY`:
```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```
**An invalid index is silently ignored.** Always check after a concurrent build.

**8. Stale statistics.** `ANALYZE chunks;`

**The diagnostic habit:** `idx_scan` in `pg_stat_user_indexes` should be climbing. **If your vector index shows `idx_scan = 0` in production, it has never been used** — and that's a one-query check worth running today.

---

## 412. Recall degradation?

**Recall can drop over time without any code change**, which makes it insidious.

**The causes:**

1. **Graph degradation from deletes.** HNSW doesn't rebalance; deleted nodes leave gaps in connectivity. High-churn tables degrade gradually. **Fix: `REINDEX CONCURRENTLY` periodically.**

2. **IVFFlat centroid drift.** Static clustering becomes unrepresentative as data grows and shifts (Q398). Fix: rebuild.

3. **Data distribution shift.** New documents in a different domain occupy a different region of the space; the graph built on the old distribution navigates it poorly.

4. **`ef_search` too low relative to grown corpus size.** What gave 95% recall at 100k vectors may give 88% at 2M.

5. **Filter selectivity increased.** More tenants means each tenant's filter is more selective, worsening the ANN+filter interaction (Q414).

6. **Silent embedding model change** — a hosted provider updating a model behind a stable name, so new vectors are subtly incompatible with old ones (Q357). **Pin versions explicitly.**

**Detection — and this is the part that requires forethought:** you cannot detect gradual recall decline without measuring it. Keep a **fixed ground-truth set**: a few hundred queries with exact-search results computed once, and re-measure ANN recall against them on a schedule.
```python
recall = len(set(ann_ids) & set(exact_ids)) / len(exact_ids)
```
Alert on a drop.

**Also monitor the top-1 score distribution** in production (Q388). A shift in that distribution indicates something changed in the corpus or the embeddings, and it's a leading indicator that costs nothing to track.

---

## 413. Memory pressure?

**Vector workloads are memory-hungry in a way that surprises teams coming from ordinary OLTP.**

**What consumes memory:**
- The HNSW index — should be resident for acceptable latency
- Vector data pages in `shared_buffers`
- `maintenance_work_mem` during index builds (can be many GB)
- `work_mem` per sort/hash operation, multiplied by concurrency

**The symptom of insufficient memory:** query latency jumps from milliseconds to hundreds of milliseconds, with `BUFFERS` showing high `shared read`. **It's not gradual — it's a cliff**, because once the index doesn't fit, every graph traversal hop becomes a potential disk read, and HNSW traversal is inherently random-access.

**Mitigations, in order:**

1. **`halfvec`** — halves vector storage and index size for usually-negligible recall loss (Q408). **The cheapest real win.**
2. **More RAM.** Boring and effective; usually cheaper than the engineering alternative.
3. **Lower-dimension embeddings** — a 768-dim model is half a 1,536-dim one. Measure the quality cost.
4. **Partition by tenant or date**, so only active partitions stay hot.
5. **Dedicated read replica** for search, so vector queries don't evict the OLTP working set (Q169).
6. **Binary quantisation as a first stage**, re-ranking survivors on full vectors — 32× smaller index, real recall cost.
7. **Archive old documents** out of the hot index.

**During index builds:** `maintenance_work_mem` set high dramatically improves build time (Q403), but it's allocated per parallel worker. Seven workers at 8 GB each is 56 GB — enough to trigger the OOM killer on a machine sized for steady state. **Set it for the build session, not globally.**

**The planning number to state:** budget RAM as roughly `1.5 × (vectors + index)`, and recognise that this is what determines when pgvector stops scaling for you — not disk, not CPU.

---

## 414. Filtered search performance?

**The hardest problem in production pgvector, and the one Q349, Q385, and Q405 all point at.**

**The mechanism.** HNSW is a graph built over *all* vectors. It has no knowledge of your filter. Search traverses toward the query vector and returns the nearest nodes it finds. Those are then filtered. **If your filter matches 1% of rows, roughly 99% of what the traversal finds is discarded** — and you may get 1 result when you asked for 10.

**No error. Just fewer, worse results.** This is why it's dangerous: the failure is silent and looks like poor retrieval quality rather than an index problem.

**The solutions:**

**1. Iterative index scans (pgvector 0.8+) — the modern answer:**
```sql
SET hnsw.iterative_scan = relaxed_order;   -- or strict_order
SET hnsw.max_scan_tuples = 20000;
SET hnsw.ef_search = 100;
```
The scan continues past the initial candidate set until enough rows survive the filter. `relaxed_order` is faster; `strict_order` guarantees correct distance ordering. **This largely solves the problem for moderate selectivity**, and knowing it exists distinguishes current knowledge from advice written two years ago.

**2. Partial indexes per tenant** — the filter becomes implicit:
```sql
CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops)
  WHERE tenant_id = 'abc';
```
**Perfect recall within the tenant**, no filter interaction. Doesn't scale past a modest number of tenants (each index has fixed overhead and build cost).

**3. Table partitioning by tenant**, each partition with its own index. Scales further; more operational complexity.

**4. Pre-filter to a subset and search exactly.** If the filter leaves a few thousand rows, exact search over them is fast and perfectly accurate:
```sql
WITH candidates AS (
  SELECT * FROM chunks WHERE tenant_id = $1 AND effective_date <= now()
)
SELECT * FROM candidates ORDER BY embedding <=> $2 LIMIT 10;
```
Force it with `SET LOCAL enable_indexscan = off` if the planner won't cooperate.

**5. Over-fetch and filter in the application.** Crude, effective, wasteful.

**The detection you should build:** **alert when a query returns fewer rows than its `LIMIT`.** That's the signature of this failure, it's trivial to instrument, and almost nobody does it.

---

## 415. Concurrent writes?

**What happens during concurrent inserts into an HNSW index:**

1. **Inserts are supported and index-consistent** — pgvector maintains the graph transactionally. No rebuild needed.
2. **Inserts are slower than plain table inserts** — each new vector must be connected into the graph, requiring a traversal similar to a search. Insert cost scales with `m` and `ef_construction`.
3. **Concurrent inserts contend** on the graph's upper layers, which every insert must traverse. Heavy write concurrency causes lock contention.
4. **MVCC applies** — an update creates a new row version, hence a new graph node, and the old one is dead until vacuumed (Q139).

**The practical guidance:**

- **Batch inserts.** One transaction inserting 500 chunks is far better than 500 transactions. Amortises the overhead and reduces WAL.
- **Bulk load before building the index** when possible (Q403).
- **Separate ingestion from query workload.** A bulk re-index saturating the primary degrades interactive search latency. Rate-limit the ingestion pipeline (Q387), or run heavy re-indexing during low-traffic windows.
- **Watch WAL volume.** Vector inserts generate substantial WAL (the vector plus the graph updates), which means replication lag and larger backups.
- **`UPDATE` on a row with an embedding is expensive** even if the embedding didn't change — MVCC rewrites the whole row and re-inserts into the index. **Store embeddings in a separate table from frequently-updated metadata** if your update pattern warrants it. This is a real and non-obvious design lever.

**The failure to watch for:** a bulk re-embedding job (Q392) running at full speed against production, driving replication lag into minutes and evicting the hot index from cache. **Rate-limit it and monitor lag**, exactly as you would any large backfill (Q165).

---

## 416. Sharding vectors?

**When you'd need it:** beyond what a single PostgreSQL instance handles — realistically hundreds of millions of vectors, or when the index no longer fits in any affordable amount of RAM (Q413).

**Say the honest thing first: most systems never reach this.** Ten million vectors is roughly 130 GB and fits comfortably on a large instance. Reaching for sharding before measuring is the same mistake as reaching for Kafka at 1,000 messages/second (Q215).

**The approaches:**

**1. Partition by tenant** — the natural boundary for multi-tenant systems. Each tenant's data in its own partition with its own index. **Also solves the filtered-search problem** (Q414), which is a significant secondary benefit. Uneven tenant sizes are the challenge.

**2. Partition by time** — recent data hot, old data cold. Works when queries are recency-biased; poor when they aren't, since you scan every partition.

**3. Hash partitioning** — even distribution, but **every query must search every partition** and merge results. That's a scatter-gather with k results from each of N partitions, merged. Works, but the query cost scales with partition count.

**4. Separate databases per tenant** — strongest isolation, heaviest operations.

**5. Move to a distributed vector database** — Milvus, Qdrant, or a managed service designed for horizontal scale.

**The honest recommendation:** **at the point where you genuinely need sharded vector search, a purpose-built vector database is likely the better answer.** pgvector's advantage is co-location with your relational data and operational simplicity; sharding it destroys the simplicity while keeping only part of the co-location benefit.

**What to do first:** `halfvec`, dimension reduction, archiving old data, and a dedicated replica. Those buy a lot of headroom before you need to restructure anything.

---

## 417. When move to a dedicated vector DB?

**The decision criteria — and the answer should demonstrate judgement, not preference:**

**Move when:**
1. **Scale exceeds a single instance** — hundreds of millions of vectors, or the index can't fit in affordable RAM (Q413, Q416)
2. **You need horizontal scaling** with automatic sharding and rebalancing
3. **You need features pgvector lacks** and can't reasonably approximate — advanced quantisation, multi-vector search, native hybrid with learned fusion
4. **Query volume saturates PostgreSQL's CPU** and a read replica isn't enough
5. **Index rebuild windows are unacceptable** and you need online reindexing with zero degradation

**Stay with pgvector when:**
1. **Under ~10 million vectors** — comfortable territory
2. **You need transactional consistency** between vectors and relational data (Q344)
3. **You need rich filtering and joins** — the killer feature, and where dedicated stores are weakest
4. **Operational simplicity matters** — one system to back up, replicate, monitor, and secure
5. **The team is small.** Another stateful system is a permanent tax on someone's attention

**The argument to lead with:** your chunks have tenant IDs, permissions, effective dates, and document relationships. In pgvector those are `WHERE` clauses with real indexes and RLS backstops in the same transaction (Q385). In a separate vector store they're limited metadata filters, plus a dual-write problem keeping two systems in sync about what documents exist and who can see them (Q245).

**The migration cost if you do move:** re-embedding is unnecessary (you keep the vectors), but you take on dual writes, a new consistency model, a new failure domain, and reimplemented filtering and permissions. **Plan it as a project, not a swap.**

**The closing sentence for an interview:** *"I'd stay on pgvector until I measured a specific limit — index memory, query latency under concurrency, or a filtering pattern it can't serve. Moving before that trades real operational simplicity for hypothetical scale."*

---

*End of Document 09. Next: Document 10 — Evaluation (questions 418–440).*
