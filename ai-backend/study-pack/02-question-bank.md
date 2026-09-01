# AI + Backend Interview Question Bank

## How to use

Answer aloud without Google. For each answer give:
**definition → why → implementation → failure → trade-off → real example.**

- **L1:** foundation
- **L2:** engineering
- **L3:** production/failure
- **L4:** system design
- **L5:** interviewer attack/follow-up

A resume skill should normally reach L4 for design-heavy topics and L3/L4 for implementation topics.

---

# A. Python

## L1
1. List vs tuple vs set vs dict?
2. What is mutability?
3. Why are dict lookups approximately O(1)?
4. What makes an object hashable?
5. `==` vs `is`?
6. What is a generator?
7. What is an iterator?
8. What is a decorator?
9. What is a context manager?
10. `def` vs `async def`?
11. What does `await` do?
12. What is a coroutine?
13. What is a task?
14. What is the GIL?
15. Thread vs process vs asyncio?
16. What is dependency injection?
17. Why type hints?
18. What does Pydantic add?
19. What is exception chaining?
20. What is a context manager useful for?

## L2
21. When would you use a generator?
22. How would you process a 10 GB file?
23. How does a decorator wrap a function?
24. What happens when `__exit__` sees an exception?
25. What happens when `time.sleep()` runs inside async code?
26. When are threads better than asyncio?
27. When are processes better?
28. Why doesn't asyncio speed up CPU-bound work?
29. What is a race condition?
30. How would you limit concurrency to an external API?
31. How do you cancel an asyncio task?
32. How do timeout and cancellation interact?
33. How do you prevent unbounded `gather()`?
34. What is backpressure?
35. How would you implement a bounded worker pool?

## L3
36. FastAPI is slow after one endpoint adds a blocking call. Diagnose it.
37. CPU is 100% with normal traffic. What do you inspect?
38. Memory grows every hour. How do you investigate?
39. One async task hangs forever. What do you do?
40. 500 requests hit a third party limited to 20/sec. Design the client.
41. A task is cancelled after DB commit but before publishing an event. What happens?
42. How do you make background work retry-safe?
43. How do you prevent task leaks?
44. How do you gracefully shut down workers?
45. What happens to in-flight work during SIGTERM?

---

# B. FastAPI / ASGI

## L1
46. What is FastAPI?
47. What is ASGI?
48. What is Uvicorn?
49. What is Starlette?
50. What is a path operation?
51. Path vs query parameter?
52. Request model vs response model?
53. What is Pydantic validation?
54. What is dependency injection?
55. What is middleware?
56. What is an exception handler?
57. What is OpenAPI?
58. What does `response_model` do?
59. What is APIRouter?
60. How do you manage configuration/secrets?

## L2
61. Walk through a request from Uvicorn to an endpoint.
62. When should an endpoint be `async def`?
63. When should it be normal `def`?
64. Why can a blocking DB driver hurt an async endpoint?
65. How does FastAPI resolve dependencies?
66. How do dependency chains work?
67. How do you create request-scoped resources?
68. Middleware vs dependency?
69. Where should authentication happen?
70. Where should authorization happen?
71. How do you structure a large FastAPI application?
72. Why separate router/service/repository?
73. Where should a transaction begin/end?
74. How do you centralize errors?
75. How do you return consistent API errors?

## L3
76. A request starts a 5-minute AI job. Why not hold HTTP open?
77. How do you return a run ID?
78. How does a client learn a job completed?
79. SSE vs WebSocket for progress?
80. FastAPI BackgroundTasks vs worker process?
81. What does increasing Uvicorn/Gunicorn workers do?
82. What happens if two workers have different in-memory state?
83. Why is an in-process background task not a durable queue?
84. How do you gracefully shut down?
85. How do you implement health/readiness?
86. How do you stop one expensive request exhausting DB connections?
87. How do you propagate request IDs?
88. How do you handle upstream timeouts?
89. How do you handle a client disconnect during streaming?
90. How do you protect an endpoint from floods?

## L4
91. Design FastAPI for 10k requests/sec.
92. Design a long-running AI job API.
93. Design multi-tenant FastAPI auth.
94. Design a 10 GB upload API.
95. Design an API calling five downstream services.
96. Where do retries live?
97. Where does caching live?
98. Where does authorization live?
99. How do you prevent retry storms?
100. How do API servers and workers scale independently?

---

# C. PostgreSQL / SQL

## L1
101. Primary key?
102. Foreign key?
103. Normalization?
104. INNER vs LEFT JOIN?
105. WHERE vs HAVING?
106. GROUP BY?
107. What is an index?
108. Why can indexes slow writes?
109. What is a transaction?
110. ACID?
111. Constraints?
112. Unique constraint?
113. Partial index?
114. Composite index?
115. Offset vs cursor pagination?

## L2
116. How does a B-tree work conceptually?
117. When will PostgreSQL not use an index?
118. Why is `%abc%` expensive?
119. Why does composite-index column order matter?
120. What is selectivity?
121. What is cardinality?
122. Sequential scan?
123. Index scan?
124. Bitmap heap scan?
125. What does EXPLAIN show?
126. EXPLAIN vs EXPLAIN ANALYZE?
127. What does planner cost mean?
128. What is the query planner?
129. Why can a sequential scan beat an index?
130. Offset vs cursor pagination at scale?

## L3 — Transactions
131. Read Committed?
132. Repeatable Read?
133. Serializable?
134. Dirty read?
135. Non-repeatable read?
136. Phantom read?
137. Lost update?
138. What does `SELECT FOR UPDATE` do?
139. What is MVCC?
140. Why doesn't PostgreSQL lock everything?
141. What happens when two transactions update the same row?
142. How can deadlocks happen?
143. How do you prevent deadlocks?
144. Why keep transactions short?
145. Why is calling an external API inside a DB transaction dangerous?

## L3 — The atomic payment story
146. Explain the atomic credit deduction.
147. Why is read-check-write unsafe?
148. What condition belongs in the SQL UPDATE?
149. What happens with two simultaneous deductions?
150. How do you guarantee no negative balance?
151. What if the process crashes after deduction but before response?
152. What if the client retries?
153. What if a webhook arrives twice?
154. What if webhook B arrives before A?
155. Why use a state machine?
156. What if a webhook never arrives?
157. Why reconciliation?

## L4
158. Design a payment database.
159. Design order/payment states.
160. Design an idempotent payment endpoint.
161. Design a ledger.
162. How do you audit money movement?
163. How do you handle refunds?
164. How do you handle concurrent spending?
165. How would you migrate a huge table?
166. A query goes from 50ms to 8s. Diagnose.
167. How do you scale PostgreSQL reads?
168. When partition?
169. When use replicas?
170. What consistency do replicas sacrifice?

---

# D. Redis / Queues

## L1
171. What is Redis?
172. Why is it fast?
173. Redis data structures?
174. When use a hash?
175. When use a set?
176. When use a sorted set?
177. What is TTL?
178. What is cache-aside?
179. What is Pub/Sub?
180. What is a Stream?

## L2
181. Redis cache vs PostgreSQL?
182. Good cache-key design?
183. How invalidate cache?
184. What happens when TTL expires?
185. Cache stampede?
186. How prevent it?
187. Distributed lock?
188. What can go wrong with a Redis lock?
189. How would you implement rate limiting?
190. Token bucket vs fixed window?
191. What if Redis dies?
192. Should Redis be source of truth?

## L3
193. Producer?
194. Consumer?
195. Acknowledgement?
196. At-most-once?
197. At-least-once?
198. Dead-letter queue?
199. Poison message?
200. Duplicate processing?
201. Dead worker recovery?
202. Stuck-job detection?
203. How does job state survive worker death?
204. How do workers scale?

## Redis Streams
205. Consumer group?
206. Pending entry?
207. Why ACK?
208. What if worker dies after receiving?
209. How can another worker reclaim it?
210. What does ordering mean?
211. Can consumers process concurrently?
212. Can processing become out of order?
213. Streams vs Pub/Sub?
214. Streams vs Kafka?
215. When choose Kafka?

---

# E. Distributed systems

## L1
216. What is a distributed system?
217. Why are they hard?
218. What is network failure?
219. Why timeout?
220. Why retry?
221. Idempotency?
222. Eventual consistency?
223. CAP?
224. Queue?
225. Event?

## L2
226. Why can retries be dangerous?
227. Why exponential backoff?
228. Why jitter?
229. Retry storm?
230. Duplicate delivery?
231. Out-of-order delivery?
232. Exactly-once?
233. Why is exactly-once hard?
234. Effectively-once?
235. Distributed lock?
236. Circuit breaker?
237. Backpressure?
238. Outbox pattern?
239. When use a queue?
240. What guarantees does your queue actually provide?

## L3
241. Worker writes DB then crashes. Message arrives again. What happens?
242. Webhook arrives twice?
243. Webhook arrives out of order?
244. DB succeeds but response is lost?
245. Redis succeeds but DB fails?
246. DB succeeds but event publish fails?
247. How do you make the workflow reliable?
248. When use outbox?
249. What changes when scaling horizontally?
250. Where can duplicate work occur?
251. Where can data be lost?
252. Where can ordering break?
253. What cost did your design add?

## L4
254. Design event-driven payments.
255. Design notifications.
256. Design a distributed job scheduler.
257. Design file processing.
258. Design a multi-tenant backend.
259. Design a long-running AI workflow.
260. Design 100k jobs/hour.
261. Design a system with 30-minute jobs.
262. What would you remove if traffic were 1/100th?

---

# F. LLM fundamentals

## L1
263. What is a token?
264. Context window?
265. Temperature?
266. What does higher temperature generally do?
267. Top-p?
268. System/user/tool messages?
269. Streaming?
270. Structured output?
271. Session?
272. Embedding?
273. Vector?
274. Cosine similarity?

## L2
275. Why doesn't temperature mean answer length?
276. Why can low temperature still be wrong?
277. Why does context affect cost/latency?
278. Causes of hallucination?
279. Why structured output?
280. Why validate model output?
281. Why should LLM output not directly mutate DB?
282. What is tool calling?
283. What is a tool schema?
284. Why typed tools?
285. What if a tool fails?
286. What if a tool times out?
287. What if a tool is called twice?
288. What if the model invents a tool?
289. How do you authorize tools?
290. Accuracy vs latency vs cost?

---

# G. Agents / MCP / tool calling

## L1
291. What is an agent?
292. Chatbot vs agent?
293. What is a tool?
294. Agent loop?
295. State machine?
296. Turn?
297. Termination condition?
298. What is MCP?
299. What problem does MCP solve?
300. What is an MCP tool?
301. Why standardize tool interfaces?

## L2
302. Explain your multi-turn agentic workflow — phases, turn budget, tool boundaries.
303. Why persist state between turns?
304. Why validate every output?
305. Why not let the model write DB directly?
306. How prevent infinite loops?
307. Tool errors?
308. Tool retries?
309. Model failure vs tool failure?
310. Tool idempotency?
311. Tool authorization?
312. Dangerous tool protection?
313. Why Redis workers?
314. Why run ID?
315. Why SSE?
316. When WebSocket?
317. How resume failed agent run?
318. Why typed MCP tools?
319. What makes a good tool error contract?

## L3
320. Malformed JSON on turn 17?
321. Tool succeeds, worker dies before persistence?
322. Model repeats tool five times?
323. Agent loops forever?
324. Tool becomes slow?
325. Unauthorized tool arguments?
326. Sensitive personal data exposure?
327. How audit an agent run?
328. How replay a run?
329. How version prompts/tools?
330. How evaluate an agent after code changes?

## L4
331. Design an agent platform.
332. Durable agent execution engine?
333. Agent state persistence?
334. Tool authorization service?
335. Human approval for dangerous tools?
336. Multi-tenant agent execution?
337. Agent observability?
338. Agent cost controls?
339. 10k concurrent agent runs?

---

# H. RAG

## L1
340. What is RAG?
341. Why not put all documents in prompt?
342. Chunking?
343. Embedding?
344. Vector search?
345. Top-k?
346. Metadata filtering?
347. Reranking?
348. Hybrid retrieval?
349. RRF?

## L2
350. How choose chunk size?
351. Why can chunks be too small?
352. Why can chunks be too large?
353. Useful chunk metadata?
354. Heading-aware chunking?
355. Tables?
356. Duplicate documents?
357. Embedding model changes?
358. Dense retrieval?
359. Lexical retrieval?
360. Why combine them?
361. RRF concept?
362. Why rerank?
363. Why retrieve 20 and rerank 5?
364. Cross-encoder?
365. Bi-encoder vs cross-encoder?

## L3
366. Retrieval returns irrelevant chunks. Debug.
367. Retrieval good but answer wrong. Where failed?
368. Correct answer but no citation. What failed?
369. System answers unsupported questions. Fix.
370. How set refusal threshold?
371. Retrieval evaluation?
372. Recall@K?
373. Hit@K?
374. MRR?
375. Golden set?
376. Unanswerable evaluation?
377. Citation correctness?
378. Faithfulness?
379. How test chunk-size changes?
380. How test embedding-model changes?

## L4
381. Design production RAG.
382. Multi-tenant RAG?
383. 100M chunks?
384. Strict tenant isolation?
385. Citation-backed RAG?
386. Refusal-first RAG?
387. RAG evaluation in CI?
388. Document ingestion?
389. Document deletion/update?
390. Embedding re-indexing?
391. Provider outage?
392. Vector store outage?
393. PostgreSQL/pgvector vs dedicated vector DB?

---

# I. pgvector

## L1
394. Why store embeddings?
395. Dimensionality?
396. Cosine/L2/inner product?
397. Exact nearest-neighbor?
398. Approximate nearest-neighbor?

## L2
399. HNSW?
400. IVFFlat?
401. HNSW vs IVFFlat?
402. Recall?
403. ANN trade-off?
404. `ef_search`?
405. `ef_construction`?
406. IVFFlat lists/probes?
407. Why can filters hurt ANN recall?
408. Tenant indexing?
409. Multiple embedding models?

## L3/L4
410. Design multi-tenant pgvector.
411. Measure ANN recall.
412. Why did recall drop after HNSW?
413. Filtered vector search returns too few results. Why?
414. Tune HNSW.
415. When IVFFlat?
416. When HNSW?
417. When switch away from PostgreSQL?

---

# J. Evaluation

## L1
418. Why evaluate LLM systems?
419. Golden dataset?
420. Regression test?
421. LLM-as-judge?
422. Retrieval evaluation?
423. Answer evaluation?

## L2
424. Build 100 golden questions.
425. Include unanswerable cases.
426. Measure retrieval.
427. Measure correctness.
428. Measure groundedness.
429. Measure refusal.
430. Evaluate tool selection.
431. Evaluate tool arguments.
432. Problems with LLM-as-judge?
433. How gate AI deployment in CI?

## L3
434. Accuracy rises but cost doubles. Ship?
435. Retrieval improves but answer quality drops?
436. Hallucination drops but refusal doubles?
437. Select operating threshold.
438. Evaluate catastrophic rare failures.
439. Compare two models fairly.
440. Detect prompt regressions.

---

# K. Model serving

## L1
441. What is inference?
442. Model weights?
443. Tokenizer?
444. CPU vs GPU?
445. Quantization?
446. OpenAI-compatible API?
447. Ollama?
448. vLLM?

## L2
449. What happens when a model loads?
450. Why does model memory matter?
451. KV cache?
452. Batching?
453. Continuous batching?
454. Throughput vs latency?
455. Why can batching improve throughput?
456. Why can batching increase latency?
457. What does vLLM provide?
458. Why an OpenAI-compatible endpoint?
459. Model warm-up?
460. Why persist model weights?

## L3
461. Model latency doubles. Diagnose.
462. GPU OOM. Diagnose.
463. Low throughput + low GPU utilization?
464. Requests queue before inference?
465. Weights disappear after Pod restart?
466. Readiness probes?
467. Model Pod dies during request?
468. Horizontal inference scaling?
469. Cost of multiple GPU replicas?

---

# L. Docker/Kubernetes/AWS

470. Image vs container?
471. Dockerfile?
472. Layers?
473. Multi-stage build?
474. Compose?
475. Kubernetes Pod?
476. Deployment?
477. Service?
478. ConfigMap?
479. Secret?
480. Readiness vs liveness?
481. EC2?
482. RDS?
483. S3?
484. IAM?
485. SSM?
486. Why not bake secrets into image?
487. How does container reach PostgreSQL?
488. What happens when a container exits?
489. Why health checks?
490. Why use a Deployment?
491. Why use a Service?
492. What happens when Pod dies?
493. IAM role vs access key?
494. Why RDS instead of PostgreSQL on EC2?
495. Why S3 instead of DB blobs?
496. Why SSM instead of open SSH?
497. Design AWS FastAPI deployment.
498. Design FastAPI + Redis + worker + Postgres.
499. Design private RDS access.
500. Design S3 file storage.
501. Zero-downtime deployment?
502. EC2 dies?
503. RDS unavailable?
504. Redis unavailable?

---

# M. Security

505. Authentication vs authorization?
506. JWT?
507. Access vs refresh token?
508. RBAC?
509. SQL injection?
510. Rate limiting?
511. HMAC?
512. Webhook signature verification?
513. TLS?
514. Secret management?
515. Why JWT logout is hard?
516. Refresh-token rotation?
517. Replay protection for webhooks?
518. Secure file downloads?
519. Presigned URLs?
520. Tenant data isolation?
521. Prompt injection?
522. Indirect prompt injection?
523. Malicious RAG document?
524. Agent secret leakage?
525. Least-privilege tools?
526. Tool argument validation?
527. Why not allow arbitrary SQL tools?
528. Protect sensitive personal data (PII/PHI)?

---

# N. Observability/debugging

529. Logs vs metrics vs traces?
530. p50/p95/p99?
531. Throughput?
532. Error rate?
533. SLI/SLO?
534. Debug high API latency?
535. Debug DB latency?
536. Debug Redis latency?
537. Debug worker backlog?
538. Correlate one request?
539. What should you log?
540. What should you never log?
541. Walk through an outage caused by a configuration mistake.
542. Walk through a login/auth failure you diagnosed in production.
543. Walk through a data-model bug that had a security consequence.
544. Walk through a blocking-call bug in an async service.
545. Walk through a capacity limit you hit and how you found it.
546. Walk through a latency improvement you measured end to end.
547. What would you monitor proactively?

---

# O. System design

Use this order every time:

**requirements → scale → APIs → data model → core flow → failure → consistency → idempotency → scaling → observability → security → trade-off**

548. URL shortener.
549. Notification service.
550. File upload.
551. Login system.
552. Rate limiter.
553. Payment API.
554. Webhook processor.
555. Background job system.
556. Email service.
557. Document processing.
558. Chat backend.
559. Long-running AI workflow.
560. RAG platform.
561. Multi-tenant RAG.
562. Agent platform.
563. AI inference gateway.
564. Payment/subscription system.
565. Health-data synchronization.
566. 100k concurrent AI runs.
567. Multi-region AI platform.
568. Enterprise RAG with tenant isolation.
569. Self-hosted model serving.
570. Model fallback/routing.
571. Human-approved AI actions.

---

# P. Resume defense

572. Tell me about yourself.
573. Why are you changing specialisation?
574. Why AI engineering?
575. What exactly do you own in your current role?
576. What did you personally build?
577. What did your teammates build, versus you?
578. Hardest production bug?
579. Most consequential incident?
580. Why FastAPI?
581. Why PostgreSQL?
582. Why Redis?
583. Why SSE?
584. Why queue?
585. Why structured LLM output?
586. Why MCP?
587. What is an agent?
588. What is RAG?
589. Why pgvector?
590. How do you evaluate RAG?
591. What do you know about vLLM?
592. What did you personally configure on AWS?
593. What is your weakest area?
594. What would you learn next?

---

# Q. Interviewer attack

595. You say "idempotency." Show me exactly where.
596. You say "distributed system." Where is the distribution?
597. You say "agent." Why isn't it just a workflow?
598. You say "AI engineer." What did you build beyond API calls?
599. You say "RAG." How did you measure it?
600. You say "vector DB." Why PostgreSQL?
601. You say "Redis queue." What if Redis dies?
602. You say "exactly once." Prove it.
603. You say "scalable." What is the bottleneck?
604. You say "async." Where is concurrency?
605. You say "AWS." What did you personally configure?
606. You say "Kubernetes." What happens when a Pod dies?
607. You say "vLLM." Why can it improve throughput?
608. You say "MCP." What problem does it solve?
609. You say "structured output." What if the model violates it?
610. You say "observability." Show me how it found an outage.
611. You claim production ownership. What would you change now?
612. You list a technology learned recently. What did you actually build with it?
