# Document 01 — Python (Questions 1–45)

Answer format: **definition → why → implementation → failure → trade-off → real example**

---

# L1 — Foundation

## 1. List vs tuple vs set vs dict?

**Definition.** Four built-in collections with different guarantees:

| Type | Ordered | Mutable | Duplicates | Lookup cost | Underlying structure |
|---|---|---|---|---|---|
| `list` | yes | yes | yes | O(n) by value, O(1) by index | dynamic array |
| `tuple` | yes | no | yes | O(n) by value, O(1) by index | fixed array |
| `set` | insertion-ordered in CPython but *not guaranteed semantically* | yes | no | O(1) average | hash table |
| `dict` | insertion-ordered (guaranteed since 3.7) | yes | keys unique | O(1) average | hash table |

**Why it matters.** Choosing wrong turns an O(n) algorithm into O(n²). The classic: checking `if item in big_list` inside a loop over another list. Swap the list for a set and a 40-second job becomes 0.2 seconds.

**Implementation.** `list` is a contiguous array of pointers that reallocates (roughly 1.125× growth) when full — which is why `append` is *amortised* O(1), not strictly O(1). `dict` and `set` are open-addressing hash tables. `tuple` is a fixed-size array with no over-allocation, so it is smaller in memory and can be cached/interned by the interpreter.

**Failure.** Using a `set` where you needed stable ordering, then relying on iteration order in a test that passes locally and fails elsewhere. Or using a `list` as a membership check in a hot path.

**Trade-off.** Hash-based structures buy O(1) lookup with memory overhead (they keep the table sparse — typically under ~2/3 full) and a hashability requirement on elements. Arrays are compact but linear to search.

**Real example.** Deduplicating 500k webhook event IDs. A `set` of seen IDs is the only sane choice; a list turns the job quadratic.

---

## 2. What is mutability?

**Definition.** Whether an object's internal state can change after creation. `list`, `dict`, `set`, and most custom classes are mutable. `int`, `str`, `tuple`, `frozenset`, and `bytes` are immutable.

**Why it matters.** Python passes references, not copies. Mutating an argument inside a function changes the caller's object. Most Python bugs that feel like "spooky action at a distance" are this.

**Implementation.** Immutable objects can be safely shared, cached, and hashed because their identity-to-value mapping never breaks. Python interns small ints (−5 to 256) and some strings precisely because immutability makes sharing safe.

**Failure — the interview classic:**

```python
def add_item(item, bucket=[]):     # BUG
    bucket.append(item)
    return bucket

add_item("a")   # ['a']
add_item("b")   # ['a', 'b']  ← same list, still there
```

The default argument is evaluated **once**, at function definition time. Fix:

```python
def add_item(item, bucket=None):
    if bucket is None:
        bucket = []
    bucket.append(item)
    return bucket
```

**Trade-off.** Immutability gives safety and hashability at the cost of allocation churn — building a string in a loop with `+=` is O(n²) because each concatenation allocates a new string. Use `"".join(parts)`.

**Real example.** A shared config dict passed into request handlers. One handler mutates it for its own convenience; every subsequent request now sees the mutation. Fix is to freeze it or hand out copies.

---

## 3. Why are dict lookups approximately O(1)?

**Definition.** A dict computes `hash(key)`, uses the low bits of that hash to index directly into a table slot, and jumps straight there — no scanning.

**Why "approximately".** Two keys can collide into the same slot. CPython uses open addressing with a probing sequence that perturbs using higher hash bits. With a good hash function and a load factor kept below ~2/3, the expected probe count is close to 1. Worst case is O(n) when every key collides.

**Implementation.** Since Python 3.6 the dict is split into a compact index array plus a dense entries array. This is what made dicts both smaller and insertion-ordered — the ordering was originally an *implementation side-effect* that was later promoted to a language guarantee in 3.7.

**Failure.** Adversarial input crafted to collide (hash-DoS). Python mitigates this with hash randomisation for strings and bytes, seeded per process via `PYTHONHASHSEED`. This is also why `hash("abc")` differs between runs, and why you must never persist a Python string hash to disk or use it as a stable shard key.

**Trade-off.** O(1) average lookup costs memory (sparse table) and requires keys to be hashable and stable.

**Real example.** An in-memory idempotency cache keyed by request ID. Constant-time lookup is the whole point; a list would make every request scan every prior request.

---

## 4. What makes an object hashable?

**Definition.** An object is hashable if it implements `__hash__` and its hash never changes during its lifetime, and it implements `__eq__` consistently with that hash.

**The contract:** if `a == b` then `hash(a) == hash(b)`. The reverse need not hold — unequal objects may share a hash (a collision), and that's fine.

**Why it matters.** Only hashable objects can be dict keys or set members.

**Implementation.** By default, a user class inherits `object.__hash__`, which is derived from `id()` — so instances hash by identity. **The trap:** if you define `__eq__` and don't define `__hash__`, Python sets `__hash__ = None` and your class becomes unhashable. This is deliberate, because value-equality with identity-hash would silently break dicts.

```python
@dataclass(frozen=True)   # frozen=True gives you __hash__ for free
class Money:
    amount: int
    currency: str
```

**Failure.** Mutating an object after using it as a dict key. Its hash bucket no longer matches its stored position, and it becomes unfindable — the dict still contains it but `key in d` returns False.

**Trade-off.** `frozen=True` dataclasses are hashable and safe but require constructing a new object to "change" a field.

**Real example.** Using a tuple `(tenant_id, document_id)` as a composite cache key. Tuples of hashables are hashable; a list of the same values is not.

---

## 5. `==` vs `is`?

**Definition.** `==` compares *value* (calls `__eq__`). `is` compares *identity* — whether both names point to the exact same object in memory.

**Why it matters.** They coincide often enough by accident that people conflate them, then get burned.

**Implementation.**
```python
a = [1, 2]; b = [1, 2]
a == b   # True
a is b   # False

x = 256; y = 256
x is y   # True — small int cache

x = 257; y = 257
x is y   # False in a fresh interpreter — but often True in a single
         # script because the compiler folds constants per code object
```

That last inconsistency is exactly why you never use `is` for value comparison.

**Correct uses of `is`:** comparing against singletons — `is None`, `is True`, `is False`, and sentinel objects. Nothing else.

**Failure.** `if x is 0:` or `if name is "admin":` — works in testing, fails in production when the value arrives from JSON parsing or a database driver rather than a literal.

**Trade-off.** None, really. `is` is faster (pointer compare) but the speed is irrelevant compared to the correctness risk.

**Real example.** Distinguishing "field not provided" from "field explicitly set to null" in a PATCH endpoint. You need a sentinel:

```python
UNSET = object()

def update(name=UNSET):
    if name is not UNSET:
        ...  # caller actually sent it, even if they sent None
```

---

## 6. What is a generator?

**Definition.** A function containing `yield`. Calling it does not run the body — it returns a generator object. Each `next()` runs until the next `yield`, produces a value, and freezes the frame with all local state intact.

**Why.** Lazy evaluation. Memory stays constant regardless of how many items you produce.

**Implementation.**
```python
def read_lines(path):
    with open(path) as f:
        for line in f:
            yield line.strip()
```
The function's stack frame is heap-allocated and kept alive between calls. Locals, the instruction pointer, and the exception state all persist.

**Failure.** Generators are single-pass and exhaust silently:
```python
g = (x for x in range(3))
list(g)   # [0, 1, 2]
list(g)   # []  ← no error, just empty
```
Second failure: a generator holding an open file or DB cursor never releases it if the consumer abandons it early. The `with` inside only closes when the generator is garbage-collected or `.close()` is called.

**Trade-off.** Constant memory and early-exit ability, at the cost of no `len()`, no indexing, no re-iteration, and harder debugging (the traceback shows the generator frame, not the consumer).

**Real example.** Streaming an LLM response to a client. You cannot buffer the whole completion before sending — you yield each chunk as it arrives.

---

## 7. What is an iterator?

**Definition.** Any object implementing `__next__()` (return next item or raise `StopIteration`) and `__iter__()` (return self).

**Iterable vs iterator** — the distinction interviewers probe. An *iterable* implements `__iter__` and can produce a *fresh* iterator each time. A *list* is iterable but not an iterator. A *generator* is both: its `__iter__` returns itself, which is precisely why it exhausts.

**Implementation.** `for x in items:` desugars to:
```python
it = iter(items)
while True:
    try:
        x = next(it)
    except StopIteration:
        break
    ...
```

**Failure.** Writing a custom class whose `__iter__` returns `self` while keeping cursor state on the instance — now nested loops over the same object interfere with each other.

**Trade-off.** Iterators decouple "how to produce" from "how to consume", which is why the same `for` loop works over files, DB cursors, HTTP streams, and lists. Cost: no random access.

**Real example.** A paginated API client that yields records while transparently fetching page N+1 — the consumer writes a plain `for` loop and never knows pagination exists.

---

## 8. What is a decorator?

**Definition.** A callable that takes a function and returns a replacement, applied with `@` syntax. `@deco def f(): ...` is exactly `f = deco(f)`.

**Why.** Cross-cutting concerns — timing, retries, auth, caching, logging — without editing every function.

**Implementation.**
```python
import functools, time

def timed(fn):
    @functools.wraps(fn)          # ← not optional
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        try:
            return fn(*args, **kwargs)
        finally:
            print(f"{fn.__name__} took {time.perf_counter()-start:.3f}s")
    return wrapper
```

**Failure — the one interviewers check for:** omitting `functools.wraps`. Without it the wrapper's `__name__` becomes `"wrapper"`, the docstring vanishes, and `__wrapped__` isn't set. This silently breaks FastAPI (which reads signatures via `inspect` to build dependency injection and OpenAPI schemas), pytest fixtures, and Sphinx docs.

Second failure: decorating an `async def` with a *sync* wrapper. `fn(*args)` returns a coroutine that is never awaited, so the wrapper's timing measures coroutine *creation* — microseconds — not execution. You need a separate async wrapper:

```python
def timed_async(fn):
    @functools.wraps(fn)
    async def wrapper(*args, **kwargs):
        start = time.perf_counter()
        try:
            return await fn(*args, **kwargs)
        finally:
            ...
    return wrapper
```

**Trade-off.** Decorators reduce duplication but add a stack frame to every traceback and make control flow non-local — the reader of `def charge_card()` cannot see that it retries three times.

**Real example.** A `@retry(attempts=3, backoff=exponential)` decorator on every outbound LLM provider call.

---

## 9. What is a context manager?

**Definition.** An object implementing `__enter__` and `__exit__`, used with `with`. It guarantees cleanup runs even if the body raises.

**Why.** Resource lifetimes tied to a lexical block rather than to programmer discipline.

**Implementation.** Two ways:
```python
class Timer:
    def __enter__(self):
        self.start = time.perf_counter()
        return self
    def __exit__(self, exc_type, exc, tb):
        self.elapsed = time.perf_counter() - self.start
        return False        # do not suppress

from contextlib import contextmanager

@contextmanager
def timer():
    start = time.perf_counter()
    try:
        yield
    finally:
        print(time.perf_counter() - start)
```

**Failure.** Returning a truthy value from `__exit__` — this *swallows the exception*. Almost always a bug, and a nasty one because errors disappear silently.

**Trade-off.** Deterministic cleanup vs. rigid lexical scoping. If a resource's lifetime doesn't match a block (a connection held across several functions), you need `contextlib.ExitStack` or explicit management.

**Real example.** A database transaction: `__enter__` begins, `__exit__` commits on clean exit and rolls back if `exc_type` is not None.

---

## 10. `def` vs `async def`?

**Definition.** `def` creates a normal function that runs to completion when called. `async def` creates a **coroutine function** — calling it returns a coroutine object and executes nothing. It only runs when awaited or scheduled on an event loop.

**Why.** `async def` bodies can contain `await`, which yields control back to the event loop so other work proceeds during I/O waits.

**Implementation.** Under the hood a coroutine is a generator-like object with `send`/`throw`/`close`. `await` suspends the coroutine and hands the awaited object to the loop.

**Failure.** Calling an async function without awaiting:
```python
result = fetch_user(1)     # coroutine object, not a user
```
Python emits `RuntimeWarning: coroutine 'fetch_user' was never awaited` — but only at garbage collection, often long after and sometimes suppressed entirely in production logging.

**Trade-off.** Async gives high concurrency for I/O with one thread and no lock contention, at the cost of an entire parallel ecosystem (`asyncpg` vs `psycopg2`, `httpx` vs `requests`) and colour-function contagion — an async caller can await sync code, but sync code cannot await async code.

**Real example.** A FastAPI endpoint that awaits three downstream services concurrently — 300ms total instead of 900ms sequential.

---

## 11. What does `await` do?

**Definition.** `await expr` suspends the current coroutine until `expr` completes, and yields control to the event loop meanwhile. `expr` must be awaitable — a coroutine, Task, Future, or an object with `__await__`.

**Why.** It marks the exact points where the function can be interrupted. This is the key property: between two `await`s your code is atomic with respect to other coroutines on the same loop.

**Implementation.** The coroutine returns control up the chain to the loop, which resumes some other ready callback. When the awaited operation completes, the loop resumes this coroutine at the `await` line with the result.

**Failure.** `await` does not create concurrency by itself. This is sequential:
```python
a = await fetch(1)
b = await fetch(2)      # starts only after (1) finishes
```
Concurrency needs explicit scheduling:
```python
a, b = await asyncio.gather(fetch(1), fetch(2))
```

**Trade-off.** Explicit suspension points make reasoning about interleaving tractable (unlike threads), but every await is also a *cancellation point* — a `CancelledError` can be raised there.

**Real example.** In an agent loop, `await` on the model call is where 90% of wall-clock time goes and where other agent runs get to make progress.

---

## 12. What is a coroutine?

**Definition.** A function that can suspend and resume, preserving its local state. In Python, the object returned by calling an `async def` function.

**Why.** It is the unit of cooperative multitasking — cheap (a few hundred bytes), unlike a thread (megabytes of stack).

**Implementation.** Coroutines are built on the generator machinery: `send()` resumes, `throw()` injects an exception, `close()` triggers `GeneratorExit`. `await` is roughly `yield from` with type restrictions.

**Failure.** A coroutine object is inert. Storing a list of coroutines and never awaiting them means nothing runs, silently. Also: awaiting the *same* coroutine object twice raises `RuntimeError: cannot reuse already awaited coroutine`.

**Trade-off.** Cooperative scheduling means one badly-behaved coroutine that never awaits blocks everything — there is no preemption. Threads are preemptive; coroutines are not.

**Real example.** 10,000 concurrent SSE connections. As coroutines that's feasible on one process; as threads it is not.

---

## 13. What is a task?

**Definition.** A coroutine wrapped and scheduled on the event loop, via `asyncio.create_task()` or `asyncio.TaskGroup`. A Task is a Future subclass — it runs independently and you can await its result later, or cancel it.

**Coroutine vs Task** — the distinction interviewers want: a coroutine does nothing until awaited. A Task starts making progress the moment the loop gets control, whether or not anyone is awaiting it.

**Implementation.**
```python
task = asyncio.create_task(long_job())
...                                   # runs concurrently here
result = await task
```

**Failure — task garbage collection.** The loop holds only a *weak* reference to tasks. If you don't keep a strong reference, your task can be collected mid-flight and vanish:
```python
asyncio.create_task(background_work())   # may disappear
```
Fix — keep a reference, or prefer `TaskGroup`:
```python
_running = set()
t = asyncio.create_task(background_work())
_running.add(t)
t.add_done_callback(_running.discard)
```

Second failure: an exception inside a fire-and-forget task is stored on the Task and only surfaces when awaited. Never awaited means never seen — except a "Task exception was never retrieved" message at GC time.

**Trade-off.** Tasks give real concurrency but you now own their lifecycle: cancellation, exception retrieval, and shutdown.

**Real example.** Kicking off an audit-log write without blocking the response — but registered in a set so shutdown can await it.

---

## 14. What is the GIL?

**Definition.** The Global Interpreter Lock — a mutex in CPython ensuring only one thread executes Python bytecode at a time.

**Why it exists.** CPython's memory management uses non-atomic reference counting. Without a global lock, every `Py_INCREF`/`Py_DECREF` would need its own atomic operation or lock, which historically made single-threaded code substantially slower.

**Implementation.** A thread holds the GIL, executes bytecode, and releases it every few milliseconds (`sys.setswitchinterval`, default 5ms) or when it blocks on I/O or calls into C code that explicitly releases it.

**What the GIL does NOT block:**
- I/O — `socket.recv`, file reads, and DB drivers release the GIL while waiting
- NumPy, Pandas, and other C extensions release it during heavy computation
- `multiprocessing` — separate processes, separate GILs

**Failure.** Assuming `ThreadPoolExecutor` will speed up a CPU-bound loop. It will not; it will be slightly *slower* due to switching overhead.

**Trade-off.** Simpler C extension authoring and fast single-thread performance, paid for with no in-process CPU parallelism.

**Current state (worth mentioning in interviews).** PEP 703 introduced an officially supported free-threaded build (no GIL) starting with Python 3.13, still optional and maturing. Saying "the GIL is being removed, optionally, via the free-threaded build, but the default build still has it" signals you follow the language.

**Real example.** Tokenising 50k documents. Threads won't help; `ProcessPoolExecutor` will.

---

## 15. Thread vs process vs asyncio?

| | Thread | Process | Asyncio |
|---|---|---|---|
| Memory | shared | isolated | shared |
| Cost each | ~8 MB stack | ~10–50 MB | ~KB |
| Practical count | hundreds | ~CPU count | tens of thousands |
| CPU parallelism | no (GIL) | yes | no |
| Switching | preemptive, OS | preemptive, OS | cooperative, at `await` |
| Communication | shared memory + locks | IPC / pickling | shared memory, no locks needed |
| Best for | blocking I/O with sync-only libraries | CPU-bound work | high-concurrency I/O |

**Decision rule:**
- CPU-bound → processes
- I/O-bound with async libraries available → asyncio
- I/O-bound but the library is sync-only and unavoidable → threads
- Blocking call inside async code → `await asyncio.to_thread(...)`

**Failure.** Mixing models carelessly — spawning threads from coroutines that touch loop objects. Loop objects are not thread-safe; you need `loop.call_soon_threadsafe`.

**Trade-off.** Processes give true parallelism but pay serialisation costs at every boundary; asyncio is cheapest but demands an all-async stack.

**Real example.** API layer async; PDF parsing (CPU-heavy, C library) dispatched to a process pool; a legacy sync SDK wrapped in `to_thread`.

---

## 16. What is dependency injection?

**Definition.** Passing a component's dependencies in from outside rather than constructing them internally.

**Why.** Testability and lifecycle control. A function that constructs its own DB connection cannot be tested without a database.

**Implementation.**
```python
# Not injected
def get_user(uid):
    conn = psycopg.connect(DSN)      # untestable, unpoolable
    ...

# Injected
def get_user(uid, conn):
    ...
```
FastAPI formalises this with `Depends`, resolving the graph per request and caching results within a request.

**Failure.** Injecting too much — every function taking eight parameters. Or over-abstracting behind protocols that have exactly one implementation forever.

**Trade-off.** Flexibility and testability vs. indirection; reading the code no longer tells you what concrete class you get.

**Real example.** Injecting an `LLMClient` protocol so tests use a deterministic fake and production uses the real provider — and so provider fallback is a wiring change, not a code change.

---

## 17. Why type hints?

**Definition.** Optional annotations (`def f(x: int) -> str:`) that the interpreter stores in `__annotations__` but **does not enforce at runtime**.

**Why.** Static checking (mypy, pyright), IDE autocomplete, self-documentation, and — crucially — runtime frameworks that *read* them: Pydantic, FastAPI, dataclasses, SQLAlchemy 2.0.

**Implementation.** Annotations are evaluated at definition time unless deferred (`from __future__ import annotations` or PEP 649 lazy evaluation in 3.14). This matters for forward references and import cycles.

**Failure.** Believing they enforce anything. `def f(x: int)` happily accepts `f("hello")` and fails 200 lines later. Enforcement requires either a checker in CI or a runtime validator like Pydantic.

**Trade-off.** Better tooling and refactor safety vs. verbosity and occasional fights with the type checker over legitimate dynamic patterns.

**Real example.** A FastAPI endpoint where the type hint *is* the validation, the OpenAPI schema, and the editor contract simultaneously.

---

## 18. What does Pydantic add?

**Definition.** Runtime validation, coercion, and serialisation driven by type hints. v2's core is written in Rust (`pydantic-core`), making it roughly 5–20× faster than v1.

**Why.** Type hints alone are advisory. Pydantic makes the boundary of your system enforce them — which is exactly where untrusted data enters.

**Implementation.**
```python
from pydantic import BaseModel, Field, field_validator

class ChargeRequest(BaseModel):
    amount_cents: int = Field(gt=0)
    currency: str = Field(pattern="^[A-Z]{3}$")

    @field_validator("currency")
    @classmethod
    def supported(cls, v):
        if v not in {"INR", "USD"}:
            raise ValueError("unsupported currency")
        return v
```
Invalid input raises `ValidationError` with a structured, per-field error list — which FastAPI turns into a 422 automatically.

**Failure.** Relying on lax mode's coercion in surprising places — `"1"` becoming `1`. Use `model_config = ConfigDict(strict=True)` where that matters. Also: v1 and v2 APIs differ substantially (`.dict()` → `.model_dump()`, `@validator` → `@field_validator`), and mixing them in one codebase causes real pain.

**Trade-off.** Validation cost per request and a heavy dependency, in exchange for eliminating an entire class of "None where an int was expected" production bugs.

**Real example — the AI-specific one.** Parsing LLM structured output. The model returns JSON that *looks* right. Pydantic is what decides whether it actually conforms before it reaches your database. This is the answer to question 280 and it is worth rehearsing.

---

## 19. What is exception chaining?

**Definition.** Preserving the original exception when raising a new one. Explicit via `raise NewError() from original`; implicit when an exception is raised inside an `except` block.

**Why.** Without it, the root cause vanishes and you debug the symptom.

**Implementation.**
```python
try:
    resp = httpx.get(url)
except httpx.TimeoutException as e:
    raise UpstreamUnavailable("pricing service timeout") from e
```
Sets `__cause__`, and the traceback shows "The above exception was the direct cause of...".

`raise ... from None` suppresses the chain — legitimate when the inner exception is noise (e.g. a `KeyError` used for control flow).

**Failure.** `except Exception: raise ServiceError("failed")` with no `from`. You get implicit chaining via `__context__` (so it isn't fully lost), but intent is unclear and the message carries no diagnostic value.

**Trade-off.** Chained tracebacks are long. But long and complete beats short and useless.

**Real example.** An agent tool wrapper that converts every underlying failure into a typed `ToolError` the model can act on, while chaining the original so your logs still show the actual `asyncpg.UniqueViolationError`.

---

## 20. What is a context manager useful for? (applied)

Question 9 covered the mechanism; this asks for judgement. The recurring uses:

1. **Transactions** — begin/commit/rollback bound to a block.
2. **Connection pooling** — acquire on enter, return to pool on exit, even on exception.
3. **Locks** — `with lock:` cannot leak a held lock.
4. **Temporary state** — changing a setting and guaranteeing restoration.
5. **Timing/tracing spans** — a span that always closes.
6. **`ExitStack`** — dynamic numbers of resources.

```python
async with asyncio.timeout(30):        # 3.11+
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(...)
```

**The judgement point for interviews:** a context manager is the right tool whenever "this must happen even if something explodes" is true. If you find yourself writing `try/finally` more than once for the same pair of operations, that's a context manager.

---

# L2 — Engineering

## 21. When would you use a generator?

Use one when **any** of these hold:

- The dataset doesn't fit in memory
- You may not consume everything (early exit / `take(10)`)
- Items arrive over time (a stream)
- You're building a pipeline of transformations and want to avoid materialising every intermediate stage

```python
def pipeline(path):
    lines   = read_lines(path)                        # lazy
    parsed  = (json.loads(l) for l in lines)          # lazy
    valid   = (r for r in parsed if r.get("id"))      # lazy
    return valid                                       # nothing has run yet
```
Memory is constant regardless of file size, and if the consumer stops after 10 records, only ~10 records were ever parsed.

**Do NOT use one when:** you need the length, you need to iterate twice, the collection is small and clarity matters more, or you need to hold a DB transaction open across consumption (see failure in Q6).

**Trade-off.** Laziness moves work to consumption time, which moves *exceptions* to consumption time too — a bug in `read_lines` surfaces in the consumer's stack frame, not the producer's.

---

## 22. How would you process a 10 GB file?

**Never load it.** The structured answer:

1. **Stream line by line.** Python file objects are already lazy iterators — `for line in f:` reads in buffered chunks, not all at once. `f.read()` or `f.readlines()` is the mistake.
2. **Process in a generator pipeline** so memory stays flat.
3. **Batch writes**, don't write per record — accumulate 1,000 rows and bulk insert.
4. **Make it resumable.** 10 GB means minutes-to-hours. Checkpoint byte offset or line number so a crash doesn't restart from zero.
5. **Make it idempotent** so a resume doesn't double-insert. Natural key + `ON CONFLICT DO NOTHING`.
6. **Parallelise only if needed** — split by byte ranges aligned to newlines, one process per chunk.

```python
def process(path, batch_size=1000):
    batch = []
    with open(path) as f:
        for line in f:
            batch.append(transform(line))
            if len(batch) >= batch_size:
                bulk_insert(batch)
                batch.clear()
    if batch:
        bulk_insert(batch)
```

**Format-specific notes.** CSV → `pandas.read_csv(chunksize=...)` or `polars.scan_csv` (lazy). JSON → a single 10 GB JSON array cannot be streamed by `json.loads`; you need `ijson` or, better, insist on JSONL. Parquet → columnar, read only needed columns via row groups.

**Failure.** Holding one DB transaction open for the whole run. It bloats WAL, blocks vacuum, and one error at 90% loses everything. Commit per batch.

**Trade-off.** Batching improves throughput but widens the window of "how much do I redo on crash". 1,000 rows is usually the right order of magnitude.

**Real example.** Ingesting a document corpus for RAG: stream → chunk → embed in batches of 96 → upsert to pgvector with checkpointing on document ID.

---

## 23. How does a decorator wrap a function?

**Mechanically.** At *definition* time — not call time — Python evaluates the decorator expression and rebinds the name:

```python
@timed
def charge(): ...

# is exactly:
def charge(): ...
charge = timed(charge)
```

`timed` receives the original function object, creates a closure capturing it, and returns the closure. The name `charge` now points to `wrapper`. The original is only reachable via the closure cell (or `charge.__wrapped__` if you used `functools.wraps`).

**With arguments** — one extra layer:
```python
def retry(attempts=3):              # decorator factory
    def decorator(fn):              # actual decorator
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            for i in range(attempts):
                try:
                    return fn(*args, **kwargs)
                except TransientError:
                    if i == attempts - 1:
                        raise
                    time.sleep(2 ** i)
        return wrapper
    return decorator
```
`@retry(attempts=5)` calls `retry(5)` first, then applies the returned `decorator`.

**Stacking order.** Bottom-up application, top-down execution:
```python
@a
@b
def f(): ...      # f = a(b(f)); a's wrapper runs first
```

**Failure.** Order matters and bites people — `@app.get(...)` must be outermost in FastAPI, because it registers whatever function object it receives. Put a caching decorator above it and you register the wrong thing.

**Trade-off.** Definition-time application means decorators cannot see runtime config unless you defer the lookup inside the wrapper.

---

## 24. What happens when `__exit__` sees an exception?

**Mechanically.** `__exit__(exc_type, exc_value, traceback)` is called with the three exception details instead of three `None`s. Then:

- Return **falsy** (including implicit `None`) → the exception propagates normally. **This is what you want.**
- Return **truthy** → the exception is suppressed. Execution continues after the `with` block as if nothing happened.

```python
def __exit__(self, exc_type, exc, tb):
    if exc_type is None:
        self.conn.commit()
    else:
        self.conn.rollback()
    self.conn.close()
    return False          # explicit: do not swallow
```

**Guarantees.** `__exit__` runs on normal exit, on exception, and on `return`/`break`/`continue` out of the block. It does **not** run on `os._exit()`, `SIGKILL`, or a hard interpreter crash.

**Failure.** Accidentally returning truthy. `return self.conn.close()` looks harmless but if `close()` returns anything truthy, you've silently swallowed every exception in the block. Also: raising *inside* `__exit__` replaces the original exception, hiding the real cause — guard cleanup with its own try/except.

**Trade-off.** Suppression is occasionally legitimate — `contextlib.suppress(FileNotFoundError)` is exactly this — but it must be explicit and narrow.

**Real example.** `async with conn.transaction():` — this is how asyncpg decides commit vs rollback, purely from `exc_type`.

---

## 25. What happens when `time.sleep()` runs inside async code?

**It blocks the entire event loop.** Not just that coroutine — every coroutine, every request, every task on that loop.

**Why.** `time.sleep()` is a blocking syscall that does not release control to the loop. The loop is a single thread running callbacks; while it sits in `sleep`, it cannot run anything else.

**Demonstration.**
```python
@app.get("/slow")
async def slow():
    time.sleep(5)          # every other request also waits 5s
    return {"ok": True}
```
With 10 concurrent requests, the last one waits 50 seconds. Health checks time out. The container gets killed by the liveness probe. This is not theoretical — it's one of the most common production incidents in async Python.

**Fix.** `await asyncio.sleep(5)` — registers a timer and yields to the loop.

**The general principle.** `time.sleep` is a stand-in for *any* blocking call: `requests.get`, `psycopg2` queries, `open().read()` on a slow disk, `boto3` calls, CPU-heavy loops, `subprocess.run`. If it doesn't `await`, it blocks.

**Fix for unavoidable blocking code:**
```python
result = await asyncio.to_thread(legacy_sync_sdk.call, arg)
```
Or make the endpoint plain `def` — FastAPI then runs it in its threadpool automatically, which is the correct choice for a fully-sync dependency.

**Detection.** `asyncio.get_event_loop().set_debug(True)` logs callbacks exceeding 100ms. In production, watch for latency on *unrelated* endpoints rising together — that's the signature.

**Trade-off.** `to_thread` costs a thread and a context switch per call, and the default threadpool is bounded (`min(32, cpu_count + 4)`); saturate it and you're back to queuing.

---

## 26. When are threads better than asyncio?

Threads win when:

1. **The library is sync-only and you can't replace it.** A vendor SDK, a legacy driver, `boto3`. Rewriting isn't an option; `to_thread` is.
2. **Concurrency is modest** (tens, not thousands). The per-thread cost is irrelevant at that scale and the code is simpler.
3. **The codebase is sync** and going async means colouring every caller up the stack.
4. **The blocking is in C code that releases the GIL** — compression, hashing, NumPy. Threads then give real parallelism.
5. **You need preemption.** A misbehaving thread doesn't freeze everything; a misbehaving coroutine does.

**Failure.** Using threads for 5,000 concurrent connections. At ~8 MB of stack each that's 40 GB of virtual address space, plus scheduler thrash.

**Trade-off.** Threads bring shared mutable state, so you need locks, and you get race conditions at *arbitrary* bytecode boundaries rather than only at `await` points. Asyncio's explicit suspension points make concurrency bugs much easier to reason about.

**Real example.** Wrapping a synchronous OCR library in `asyncio.to_thread` inside an otherwise-async FastAPI service — 20 concurrent OCR jobs, sync library, no rewrite.

---

## 27. When are processes better?

Processes win when:

1. **The work is CPU-bound in pure Python.** The GIL makes threads useless here.
2. **You need fault isolation.** A segfault in a C extension kills one worker, not the service.
3. **You need memory isolation** — one job leaking doesn't grow the whole service.
4. **You want to use all cores** on one machine.

**Implementation.**
```python
from concurrent.futures import ProcessPoolExecutor
with ProcessPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(cpu_heavy, items))
```
From async code: `await loop.run_in_executor(process_pool, cpu_heavy, item)`.

**Failure.** Ignoring serialisation cost. Every argument and return value is pickled and copied through a pipe. Sending a 500 MB DataFrame to a worker costs more than the computation. Send a file path or an ID, not the data. Also: unpicklable objects (open sockets, lambdas, DB connections) fail at submission.

**Trade-off.** True parallelism vs. IPC overhead, higher memory, slower startup, and harder debugging (tracebacks cross process boundaries).

**Real example.** Batch-embedding documents locally, or parsing 10k PDFs. Also: this is why Gunicorn runs multiple Uvicorn worker *processes* rather than threads.

---

## 28. Why doesn't asyncio speed up CPU-bound work?

**Because asyncio has no parallelism at all.** It has *concurrency* — interleaving — achieved by coroutines voluntarily yielding at `await`. A CPU-bound loop has nothing to await. It never yields. The loop is stuck in it.

**Concurrency vs parallelism** — the distinction being tested:
- **Concurrency**: multiple tasks in progress, interleaved. One core is enough.
- **Parallelism**: multiple tasks executing simultaneously. Requires multiple cores.

Asyncio gives concurrency only, and only for work that waits. CPU work doesn't wait — it computes.

```python
async def compute():
    return sum(i*i for i in range(10**8))   # never yields; loop frozen

# gather() of ten of these takes 10× as long as one. Zero speedup.
```

Even sprinkling `await asyncio.sleep(0)` inside the loop only lets other tasks interleave — total wall-clock time gets *worse*, not better, since you added switching overhead to the same total work.

**Fix.** `run_in_executor` with a `ProcessPoolExecutor`, or move the work out of Python entirely (NumPy, Rust extension, a dedicated service).

**Real example.** Computing cosine similarity over 100k vectors in pure Python inside an async endpoint. The fix isn't async — it's pushing the computation into pgvector or NumPy.

---

## 29. What is a race condition?

**Definition.** When correctness depends on the relative timing of concurrent operations, and some interleavings produce wrong results.

**The canonical shape — read-modify-write:**
```python
balance = await db.fetch("SELECT balance FROM accounts WHERE id=$1", uid)
if balance >= amount:                    # T1 and T2 both read 100
    await db.execute("UPDATE accounts SET balance=$1 ...", balance - amount)
```
Two concurrent 100-unit deductions from a 100 balance: both read 100, both pass the check, both write 0. One deduction vanished. Money was created.

**Where races occur in async Python.** Between `await` points — that's the key insight. Code between two awaits is atomic w.r.t. other coroutines on the same loop. So this is safe:
```python
counter += 1                             # no await; atomic here
```
And this is not:
```python
current = counter
await something()                        # ← other coroutine runs
counter = current + 1                    # stale
```

**Fixes, in order of preference:**
1. **Make it atomic in the database** — `UPDATE ... SET balance = balance - $1 WHERE id = $2 AND balance >= $1`, then check `rowcount`.
2. **Pessimistic lock** — `SELECT ... FOR UPDATE`.
3. **Optimistic concurrency** — version column, `WHERE version = $expected`, retry on zero rows.
4. **Serialise through a single owner** — one worker per key, or an `asyncio.Lock` (single-process only!).

**Failure.** Using `asyncio.Lock` or `threading.Lock` in a multi-worker deployment. It protects one process. Four Gunicorn workers means four independent locks and zero protection.

**Trade-off.** Locks cost throughput and can deadlock. Database-level atomic updates are cheaper and correct across all workers — prefer them.

**Real example.** This is exactly questions 146–150 in your bank. The atomic-UPDATE-with-condition answer is the one to rehearse.

---

## 30. How would you limit concurrency to an external API?

**Semaphore — the standard tool:**
```python
sem = asyncio.Semaphore(20)

async def fetch(client, url):
    async with sem:
        return await client.get(url)

await asyncio.gather(*(fetch(client, u) for u in urls))
```
The semaphore permits 20 in flight; the rest wait at `async with`.

**Important subtlety.** This limits *concurrency*, not *rate*. 20 concurrent requests each taking 10ms is 2,000 req/sec. If the limit is "20 per second", you need a rate limiter, not a semaphore:

```python
# token bucket, roughly
class RateLimiter:
    def __init__(self, rate):
        self.rate = rate
        self.updated = time.monotonic()
        self.tokens = rate
    async def acquire(self):
        while True:
            now = time.monotonic()
            self.tokens = min(self.rate, self.tokens + (now - self.updated) * self.rate)
            self.updated = now
            if self.tokens >= 1:
                self.tokens -= 1
                return
            await asyncio.sleep((1 - self.tokens) / self.rate)
```

**Also required in a real client:**
- Connection pool limits: `httpx.Limits(max_connections=20)`
- Timeouts on every request (connect, read, total)
- Retry with exponential backoff **and jitter**
- Honour `Retry-After` on 429
- Circuit breaker so a dead upstream fails fast instead of consuming your capacity

**Multi-process caveat.** A per-process semaphore of 20 across 4 workers is 80 in flight. Distributed limits need Redis.

**Trade-off.** Lower concurrency means longer wall-clock; higher risks 429s and bans. Tune to the documented limit, then leave headroom.

**Real example.** Question 40 in your bank is this exact scenario with numbers — 500 requests against a 20/sec cap.

---

## 31. How do you cancel an asyncio task?

```python
task = asyncio.create_task(work())
task.cancel()
try:
    await task
except asyncio.CancelledError:
    pass       # expected
```

**Mechanically.** `cancel()` doesn't stop anything immediately. It *schedules* a `CancelledError` to be raised inside the coroutine at its next suspension point. A coroutine that never awaits can never be cancelled.

**Critical detail — `CancelledError` inherits from `BaseException`, not `Exception`,** since Python 3.8. So `except Exception:` does not catch it, which is deliberate — it prevents broad handlers from silently swallowing cancellation. But it also means your cleanup must use `finally`, not `except Exception`.

**Correct cleanup:**
```python
async def work():
    conn = await pool.acquire()
    try:
        await long_query(conn)
    finally:
        await pool.release(conn)       # runs on cancellation too
```

**Shielding critical sections:**
```python
await asyncio.shield(commit_transaction())   # not interrupted mid-commit
```

**Failure.** Catching and suppressing `CancelledError` — the task becomes uncancellable, `TaskGroup` and shutdown hang. If you catch it for cleanup, re-raise.

**Trade-off.** Cancellation is cooperative, so a task doing sync work is uninterruptible. That's the price of no preemption.

---

## 32. How do timeout and cancellation interact?

**Timeout is implemented as cancellation.** `asyncio.timeout()` starts a timer; on expiry it calls `cancel()` on the enclosed task, catches the resulting `CancelledError`, and converts it into `TimeoutError`.

```python
async with asyncio.timeout(5):      # 3.11+, preferred
    await slow_operation()
# raises TimeoutError

result = await asyncio.wait_for(slow_operation(), timeout=5)   # older style
```

**Consequences that trip people:**

1. **A non-yielding operation cannot be timed out.** `time.sleep(60)` inside a 5-second timeout runs the full 60 seconds. The timer fires, but there's no suspension point to raise at.

2. **Nested timeouts:** the innermost expiring wins. An outer 30s and inner 5s means the inner raises at 5s. But if the *outer* fires first, the inner block sees `CancelledError`, not `TimeoutError` — so a bare `except TimeoutError` inside won't catch outer cancellation. Correct, but surprising.

3. **Cleanup still runs** — `finally` executes during timeout unwinding, so releasing connections works.

4. **The operation may have already had an effect.** A timed-out HTTP POST may well have been processed by the server; you only lost the response. This is why timeout + retry requires **idempotency keys**. This is the bridge to questions 221, 244, and 595 in your bank — worth connecting explicitly in an interview.

**Trade-off.** Aggressive timeouts free resources fast but cause spurious retries and duplicate side effects. Loose ones tie up connections. Set them from measured p99, not intuition, and always shorter than the caller's timeout above you.

---

## 33. How do you prevent unbounded `gather()`?

**The problem.** `await asyncio.gather(*(fetch(u) for u in urls))` with 100k URLs creates 100k tasks immediately — memory spike, 100k simultaneous connections, upstream flooded, likely OOM.

**Four fixes, in order of preference:**

**1. Semaphore** (keeps gather, bounds in-flight work):
```python
sem = asyncio.Semaphore(50)
async def bounded(u):
    async with sem:
        return await fetch(u)
results = await asyncio.gather(*(bounded(u) for u in urls))
```
Note: 100k *task objects* still get created — memory is bounded only in terms of connections. For very large N, use chunking too.

**2. Chunking:**
```python
for chunk in batched(urls, 100):
    results.extend(await asyncio.gather(*(fetch(u) for u in chunk)))
```
Simpler, but each batch runs at the speed of its slowest member.

**3. Worker pool with a queue** — best for large or streaming input:
```python
queue = asyncio.Queue(maxsize=1000)     # maxsize gives you backpressure
async def worker():
    while (item := await queue.get()) is not None:
        try:
            await process(item)
        finally:
            queue.task_done()
workers = [asyncio.create_task(worker()) for _ in range(50)]
```

**4. `TaskGroup`** (3.11+) — better error semantics than gather:
```python
async with asyncio.TaskGroup() as tg:
    for u in urls:
        tg.create_task(bounded(u))
```

**gather vs TaskGroup — the error behaviour difference.** By default `gather` with `return_exceptions=False` propagates the first exception but **leaves the other tasks running**. `TaskGroup` cancels all siblings on first failure and raises an `ExceptionGroup`. TaskGroup is almost always what you actually wanted.

**Trade-off.** Bounded concurrency is slower in the best case and survivable in the worst. Always bound it.

---

## 34. What is backpressure?

**Definition.** A mechanism by which a slow consumer signals a fast producer to slow down, rather than letting work accumulate without limit.

**Why it matters.** Without backpressure, a queue grows until memory is exhausted, and the whole system dies at once instead of degrading gracefully. Unbounded queues turn a throughput problem into an outage.

**Implementations by layer:**
- **In-process**: `asyncio.Queue(maxsize=N)` — `put()` blocks when full.
- **TCP**: the receive-window mechanism is backpressure built into the protocol.
- **HTTP**: return 429 with `Retry-After`. Load-shedding is backpressure.
- **Queues**: bounded queues, consumer-driven prefetch limits, Kafka consumer lag as the signal.
- **Databases**: a bounded connection pool — waiters block rather than opening unlimited connections.

**Failure.** `queue = asyncio.Queue()` with no maxsize. Producer reads a 10 GB file at disk speed, consumer writes to a database at network speed. The queue absorbs the difference until the process is OOM-killed. The logs show nothing useful; the container just dies.

**The subtler failure:** backpressure that only *moves* the problem. Bounding your queue makes the producer block — but if the producer is an HTTP handler, now requests hang instead of the queue growing. You must decide explicitly: block, drop, or reject. Silence is not one of the options.

**Trade-off.** Backpressure trades throughput and latency for stability. Rejecting work feels worse than accepting it, but accepting work you cannot do is a lie that surfaces later as a crash.

**Real example.** SSE streaming to a slow mobile client. Without backpressure, generated tokens buffer in memory per connection; with 1,000 slow clients you OOM. Bound the per-connection buffer and drop the connection when it overflows.

---

## 35. How would you implement a bounded worker pool?

```python
import asyncio
from dataclasses import dataclass

@dataclass
class Pool:
    concurrency: int = 10
    queue_size: int = 1000

    async def run(self, items, handler):
        queue = asyncio.Queue(maxsize=self.queue_size)   # backpressure
        results, errors = [], []

        async def worker():
            while True:
                item = await queue.get()
                try:
                    if item is None:              # shutdown sentinel
                        return
                    results.append(await handler(item))
                except Exception as e:
                    errors.append((item, e))      # one failure ≠ pool death
                finally:
                    queue.task_done()

        workers = [asyncio.create_task(worker()) for _ in range(self.concurrency)]
        try:
            for item in items:
                await queue.put(item)             # blocks when full — this is the point
            await queue.join()                    # wait for drain
        finally:
            for _ in workers:
                await queue.put(None)
            await asyncio.gather(*workers, return_exceptions=True)

        return results, errors
```

**The design decisions worth defending in an interview:**

1. **`maxsize` on the queue** — this is where backpressure lives. Without it the pool is unbounded.
2. **Exceptions collected, not raised** — one bad item must not kill the pool. Failed items go to an error list (in production: a dead-letter queue).
3. **`task_done()` in `finally`** — otherwise `queue.join()` hangs forever on any exception.
4. **Sentinel shutdown** — workers exit cleanly rather than being cancelled mid-item.
5. **`finally` around the whole thing** — an exception in the producer still shuts down workers instead of leaking them.

**Production additions:** per-item timeout (`asyncio.timeout`), retry with backoff before dead-lettering, metrics on queue depth (the single best early-warning signal you have), and graceful SIGTERM handling that stops accepting and drains in-flight work.

**Trade-off.** More concurrency isn't free — the optimal number is bounded by the *downstream* constraint (DB pool size, upstream rate limit), not by your CPU. Setting concurrency above the DB pool size just moves queuing from your queue into the pool.

---

# L3 — Production / failure

## 36. FastAPI is slow after one endpoint adds a blocking call. Diagnose it.

**The signature that identifies this instantly:** *all* endpoints slow down, not just the new one. Health checks time out. Latency rises with concurrency rather than with request complexity. That pattern means event-loop blocking, not a slow query.

**Diagnosis, in order:**

1. **Confirm the shape.** Is p99 on unrelated endpoints elevated? Blocking affects everyone; a slow query affects one route.
2. **Read the diff.** Look for a sync call in an `async def`: `requests`, `psycopg2`, `boto3`, `time.sleep`, `open().read()`, `subprocess.run`, a CPU loop, `bcrypt.hashpw`, `PIL` image work.
3. **Instrument.** `loop.set_debug(True)` logs any callback exceeding 100ms with its source location. In production, `py-spy dump --pid <pid>` shows where the loop thread actually is, with no restart and near-zero overhead.
4. **Confirm the mechanism.** One event loop per worker process; a blocking call occupies it entirely. With 4 workers and 4 blocked requests, the service is fully down.

**Fixes, in preference order:**

| Situation | Fix |
|---|---|
| Async library exists | Swap it — `httpx` for `requests`, `asyncpg` for `psycopg2` |
| Sync-only, I/O-bound | `await asyncio.to_thread(fn, ...)` |
| Whole endpoint is sync | Declare it `def`, not `async def` — FastAPI runs it in the threadpool |
| CPU-bound | `run_in_executor` with a process pool, or move to a worker |
| Long-running | Don't do it in the request at all — enqueue it (see Q76) |

**The counter-intuitive point worth stating in an interview:** in FastAPI, `def` is often *safer* than `async def`. A sync endpoint is dispatched to a threadpool and cannot block the loop. An `async def` endpoint containing one blocking call takes down the entire worker. Wrong `async` is far more dangerous than no `async`.

**Prevention.** Lint rules (`flake8-async`, `ruff` ASYNC rules) that ban known-blocking calls inside async functions, plus a loop-lag metric alert.

---

## 37. CPU is 100% with normal traffic. What do you inspect?

**Step 1 — Is it actually your process?** `top`/`htop`. Could be a sidecar, a log shipper, or a noisy neighbour. In Kubernetes, check whether you're being CPU-throttled (`container_cpu_cfs_throttled_seconds_total`) — throttling looks like slowness, not high CPU.

**Step 2 — Profile the live process without restarting it.**
```bash
py-spy top --pid <pid>              # live function-level CPU
py-spy dump --pid <pid>             # stack of every thread right now
py-spy record -o out.svg --pid <pid> --duration 30   # flamegraph
```
`py-spy` reads memory externally; it needs no code changes and no restart. This is the single most valuable production Python debugging tool and worth naming explicitly in an interview.

**Step 3 — Match against the usual causes:**

| Cause | Signature |
|---|---|
| Accidental O(n²) | CPU scales superlinearly with data size, not request count |
| JSON serialisation of huge payloads | Time in `json.dumps` / `model_dump` |
| Pydantic validation on large nested models | Time in `pydantic_core` |
| Regex catastrophic backtracking | One request pinning one core indefinitely |
| Logging at DEBUG in production | Time in formatting and I/O |
| Tight retry loop with no backoff | CPU high *and* network high |
| Busy-wait / `while True` without await | One core at exactly 100% |
| GC pressure | `gc.get_stats()`, many long-lived objects |
| Crypto — bcrypt, JWT signing | Expected; check cost factor isn't misconfigured |

**Step 4 — Correlate.** Did CPU rise with a deploy (code), with data growth (algorithmic), or with traffic (capacity)? Three different answers.

**The trap to avoid:** scaling out before diagnosing. If it's an O(n²) bug, doubling replicas doubles cost and fixes nothing.

---

## 38. Memory grows every hour. How do you investigate?

**First, distinguish three different things:**

1. **A real leak** — objects referenced forever. RSS grows without bound.
2. **Fragmentation** — memory freed by Python but not returned to the OS. RSS plateaus high.
3. **Legitimate growth** — a cache that's still filling. Plateaus at its bound.

Watch the shape of the curve: unbounded linear growth = leak; sawtooth = GC working normally; step-then-plateau = cache warming.

**Tooling:**
```python
import tracemalloc
tracemalloc.start(25)
# ... later
snap = tracemalloc.take_snapshot()
for stat in snap.statistics("lineno")[:10]:
    print(stat)
```
Better: take two snapshots an hour apart and diff with `compare_to()`. That shows *growth*, which is what you care about.

Also: `objgraph.show_growth()` for object-count deltas by type; `py-spy dump` to check for a runaway thread count; `gc.get_objects()` for a raw census.

**The usual culprits in a FastAPI/async service:**

| Cause | Detail |
|---|---|
| Unbounded cache | A module-level `dict` with no eviction. Use `functools.lru_cache(maxsize=N)` — never `maxsize=None` on user input |
| `lru_cache` on a method | Caches `self`, so instances are never freed |
| Task leak | `create_task` without tracking; tasks accumulate. Check `len(asyncio.all_tasks())` |
| Unclosed clients | A new `httpx.AsyncClient` per request instead of one shared client |
| Connection pool per request | Same problem, worse |
| Accumulating logs/lists | Appending to a module-level list for "metrics" |
| Reference cycles with `__del__` | Historically uncollectable; much better in modern Python but still worth checking |
| Exception objects holding tracebacks | A traceback references every frame and every local in it. Storing exceptions in a list retains entire call stacks |
| Fragmentation | Many differently-sized allocations. `MALLOC_ARENA_MAX=2` sometimes helps |

**The FastAPI-specific one worth naming:** a module-level `dict` used as a per-user cache, keyed by user ID, with no TTL. Works fine at 100 users, kills the pod at 100k.

**Production practice.** Set a container memory limit so a leak causes a restart rather than a node-wide OOM, alert on RSS trend not absolute value, and treat "we restart it nightly" as a bug ticket, not a solution.

---

## 39. One async task hangs forever. What do you do?

**Immediate diagnosis:**
```bash
py-spy dump --pid <pid>
```
This prints every thread and every coroutine's stack. The hung task's stack tells you exactly what it's waiting on. Also:
```python
for t in asyncio.all_tasks():
    t.print_stack()
```

**Then classify the wait:**

| Symptom in the stack | Cause |
|---|---|
| Blocked in a socket read | No timeout on an HTTP/DB call |
| Waiting on `Lock.acquire` | Deadlock or a lock never released |
| Waiting on `Queue.get` | Producer died; nothing will ever arrive |
| Waiting on `Queue.put` | Queue full; consumer died |
| Waiting on a Future | Nothing will ever resolve it |
| Not in the loop at all | Blocking sync call — the loop itself is stuck |
| Waiting on `pool.acquire` | Connection pool exhausted (see Q86) |

**The root cause is almost always a missing timeout.** Default behaviour for most network libraries is to wait forever. `httpx` has no total timeout by default beyond its 5s connect; `asyncpg` queries have none unless you set one.

**The structural fixes:**
1. **Timeout on every external call**, no exceptions. `async with asyncio.timeout(n)` around anything that leaves the process.
2. **Watchdog** — if a task should finish in 30s, wrap it and alert at 60s.
3. **Heartbeats** for long jobs — a job that hasn't updated `last_heartbeat_at` in N minutes is stuck; a reaper requeues it.
4. **Track your tasks** so you can enumerate and inspect them.
5. **TaskGroup** — a hung child prevents the group exiting, which is at least *visible*, unlike a silently leaked task.

**Failure to avoid.** "It resolves on restart" is not a diagnosis. If you restart without capturing `py-spy dump` first, you have destroyed the only evidence.

**Trade-off.** Aggressive timeouts cause spurious failures on legitimately slow operations. Set them from measured p99 plus headroom, and make retries idempotent so a false timeout is harmless.

---

## 40. 500 requests hit a third party limited to 20/sec. Design the client.

**Requirements:** never exceed 20/sec, complete all 500 (~25s minimum), survive 429s and transient errors, don't lose work, don't melt down under retry.

**The layered design:**

**Layer 1 — Rate limiting (token bucket, Redis-backed if multi-process):**
```python
class TokenBucket:
    def __init__(self, rate, capacity=None):
        self.rate = rate
        self.capacity = capacity or rate
        self.tokens = self.capacity
        self.updated = time.monotonic()
        self.lock = asyncio.Lock()

    async def acquire(self):
        async with self.lock:
            while True:
                now = time.monotonic()
                self.tokens = min(self.capacity,
                                  self.tokens + (now - self.updated) * self.rate)
                self.updated = now
                if self.tokens >= 1:
                    self.tokens -= 1
                    return
                await asyncio.sleep((1 - self.tokens) / self.rate)
```
Token bucket over fixed window because a fixed window allows a 2× burst at the boundary — 20 at 0.999s and 20 at 1.001s is 40 in 2ms.

**Layer 2 — Concurrency bound.** Semaphore sized to `rate × p99_latency`. If p99 is 500ms, ~10 concurrent sustains 20/sec. Higher just queues.

**Layer 3 — Retry with exponential backoff and jitter:**
```python
delay = min(base * 2**attempt, cap)
delay = random.uniform(0, delay)      # full jitter
```
Jitter is not optional — without it, all 500 retry in lockstep and you get a thundering herd. Honour `Retry-After` when present; it overrides your calculation.

**Layer 4 — Circuit breaker.** After N consecutive failures, open the circuit and fail fast for 30s. Prevents burning your rate budget on a dead upstream.

**Layer 5 — Durability.** For 500 items over 25+ seconds, this belongs in a queue, not an HTTP request. Persist the work, process asynchronously, return a job ID.

**Layer 6 — Idempotency.** Retries mean duplicates. Send an idempotency key so the upstream deduplicates, and make your own persistence upsert-based.

**Multi-worker caveat, worth raising unprompted:** all of the above is per-process. With 4 Gunicorn workers you have 4 buckets and an effective 80/sec. Real limits need a Redis-backed counter or a single dedicated worker owning the upstream.

**Trade-off.** This is a lot of machinery for one integration. Justified when the upstream is critical and expensive; over-engineering when it's a nightly report. Say that out loud — interviewers score judgement, not maximalism.

---

## 41. A task is cancelled after DB commit but before publishing an event. What happens?

**What happens:** the database has the new state; the rest of the system does not. The order is created but no confirmation email is sent, no downstream service is notified, no search index is updated. **Silent, permanent inconsistency** — no error is logged because nothing failed, it just stopped.

**Why this is unavoidable in the naive design:**
```python
await db.commit()          # ← succeeded
# ← cancellation, crash, OOM kill, or network partition here
await broker.publish(evt)  # ← never runs
```
There is no way to make two separate systems commit atomically without a distributed transaction protocol, and two-phase commit is generally not worth its cost and failure modes.

**The correct fix — the transactional outbox pattern:**

1. Write the business change **and** the event row in the **same transaction**:
```sql
BEGIN;
  INSERT INTO orders (...) VALUES (...);
  INSERT INTO outbox (id, topic, payload, created_at)
    VALUES (gen_random_uuid(), 'order.created', $1, now());
COMMIT;
```
Now they are atomic — both or neither.

2. A **separate relay process** polls the outbox (or reads the WAL via CDC/Debezium), publishes, and marks rows dispatched.

3. Because the relay can crash after publishing but before marking, delivery is **at-least-once**. Consumers must therefore be **idempotent** — dedupe on event ID.

**Partial mitigations, and why they are inferior:**
- `asyncio.shield(publish)` — shields against *cancellation*, not against SIGKILL, OOM, or node failure. It narrows the window; it does not close it.
- Publish first, then commit — now you can publish an event for an order that never existed. Strictly worse.
- Retry in `finally` — the process may not survive to run it.

**The honest framing for an interview:** "You cannot make this atomic across two systems. You can only choose which failure you prefer. The outbox chooses at-least-once delivery plus idempotent consumers, because duplicate processing is recoverable and lost events are not."

That framing — *choosing a failure mode rather than pretending to eliminate it* — is what separates an L3 answer from an L1 one. This directly answers questions 238, 246, and 248 in your bank.

---

## 42. How do you make background work retry-safe?

**The requirement:** running the job twice must produce the same end state as running it once. Retries are inevitable — timeouts, crashes, redeliveries — so this is not optional.

**Techniques, in order of applicability:**

**1. Natural idempotency.** Design the operation so repetition is harmless. `SET status = 'processed'` is idempotent; `SET count = count + 1` is not.

**2. Idempotency keys.**
```sql
CREATE TABLE processed_jobs (
    idempotency_key TEXT PRIMARY KEY,
    result JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);
```
```python
async def handle(job):
    try:
        async with conn.transaction():
            await conn.execute(
                "INSERT INTO processed_jobs (idempotency_key) VALUES ($1)",
                job.key)
            result = await do_work(job)
            await conn.execute(
                "UPDATE processed_jobs SET result=$1 WHERE idempotency_key=$2",
                result, job.key)
            return result
    except UniqueViolationError:
        return await fetch_existing_result(job.key)
```
The unique constraint is the dedupe mechanism, and it works across processes because the database is the arbiter.

**3. Upserts.** `INSERT ... ON CONFLICT (natural_key) DO UPDATE` — no read-then-write race.

**4. Conditional updates / state machines.** `UPDATE jobs SET status='done' WHERE id=$1 AND status='processing'`. Zero rows affected means someone else did it. This makes illegal transitions impossible rather than merely unlikely.

**5. Outbox for side effects** (see Q41) so DB writes and external notifications don't diverge.

**6. Fencing tokens** for external systems that can't dedupe. Include a monotonic version; the receiver rejects anything stale.

**What you cannot make idempotent — and must handle differently:**
- Charging a card → the payment provider's idempotency key is mandatory
- Sending an email → dedupe before sending; an email cannot be unsent
- Calling a non-idempotent third-party API → wrap in your own dedupe table

**Operational requirements:** bounded retries, exponential backoff with jitter, a dead-letter queue after max attempts, and an alert on DLQ depth. Infinite retry on a poison message is a self-inflicted outage.

**Trade-off.** Idempotency costs a table, an index, and a write per job. Retention on that table is a real operational concern — partition it or TTL it, or it becomes your largest table.

---

## 43. How do you prevent task leaks?

**What a leak looks like.** Tasks created and forgotten: memory grows, connections stay open, and — worst — exceptions inside them are never retrieved, so failures are completely invisible.

**The mechanisms:**

**1. Prefer `TaskGroup` (3.11+).** Structured concurrency: the block cannot exit until every child finishes, and a failure cancels siblings.
```python
async with asyncio.TaskGroup() as tg:
    tg.create_task(a())
    tg.create_task(b())
# guaranteed: both done or both cancelled
```

**2. If you must fire-and-forget, hold a strong reference** (see Q13 — the loop only holds a weak one):
```python
_background: set[asyncio.Task] = set()

def spawn(coro):
    t = asyncio.create_task(coro)
    _background.add(t)
    t.add_done_callback(_background.discard)
    t.add_done_callback(_log_exception)     # otherwise failures vanish
    return t
```

**3. Always retrieve exceptions.** A done-callback that logs `task.exception()` is the difference between a visible error and a silent one.

**4. Timeout every task.** A leaked task that would have finished is a smaller problem than one that waits forever.

**5. Drain on shutdown:**
```python
@app.on_event("shutdown")           # or a lifespan context manager
async def drain():
    await asyncio.gather(*_background, return_exceptions=True)
```

**6. Monitor.** Export `len(asyncio.all_tasks())` as a gauge. A monotonically rising task count is an unambiguous leak signal and one of the cheapest metrics you can add.

**The FastAPI-specific trap:** `BackgroundTasks` runs *after the response is sent but inside the same process*. If the process dies, the work is lost silently — the client already got a 200. It is not durable and must never be used for anything that matters. That's question 83 in your bank.

---

## 44. How do you gracefully shut down workers?

**The goal:** stop accepting new work, finish in-flight work, release resources, exit before the platform's kill timeout.

**The sequence:**

```python
import signal, asyncio

class Worker:
    def __init__(self):
        self.shutdown = asyncio.Event()
        self.in_flight: set[asyncio.Task] = set()

    async def run(self):
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self.shutdown.set)

        while not self.shutdown.is_set():
            job = await self.poll()                 # returns None on shutdown
            if job:
                t = asyncio.create_task(self.handle(job))
                self.in_flight.add(t)
                t.add_done_callback(self.in_flight.discard)

        # drain, bounded
        if self.in_flight:
            done, pending = await asyncio.wait(self.in_flight, timeout=25)
            for t in pending:
                t.cancel()                          # over budget; give up
            await asyncio.gather(*pending, return_exceptions=True)

        await self.close_resources()
```

**The phases, stated explicitly:**
1. **Signal received** (SIGTERM from Kubernetes or Docker).
2. **Fail readiness immediately** — so the load balancer stops routing. Liveness must still pass, or you get killed mid-drain.
3. **Stop accepting** — stop polling the queue, stop accepting connections.
4. **Drain with a deadline** shorter than `terminationGracePeriodSeconds` (default 30s in Kubernetes). If your drain budget is 25s and the grace period is 30s, you exit cleanly. Reverse those numbers and you get SIGKILL'd mid-write.
5. **Cancel what's over budget** — and because your jobs are idempotent and re-queueable (Q42), that's survivable.
6. **Close resources** — DB pool, HTTP clients, flush metrics and logs.

**The Kubernetes detail people miss:** SIGTERM and endpoint removal happen *concurrently*, not in order. For a few hundred milliseconds after SIGTERM you may still receive new requests. A `sleep 5` in a `preStop` hook before shutdown begins is the standard workaround.

**Trade-off.** A long drain means slow deploys; a short one means killed work. The right answer is a short drain *plus* idempotent, re-queueable jobs — then a killed job is a retry, not a loss.

---

## 45. What happens to in-flight work during SIGTERM?

**Default Python behaviour:** SIGTERM's default disposition terminates the process immediately. In-flight work dies. No `finally`, no `__exit__`, no cleanup. Uncommitted transactions roll back (the DB notices the dropped connection eventually), open files may lose buffered writes, and queue messages that were received but not acknowledged stay unacknowledged.

**With a handler installed,** you control the outcome — that's Q44.

**What survives and what doesn't, by layer:**

| | Outcome |
|---|---|
| Committed DB transactions | Safe — durability guaranteed |
| Uncommitted transactions | Rolled back when the connection drops. Safe, but the work is lost |
| Unacknowledged queue messages | Redelivered after visibility timeout / pending-entry reclaim. Safe if idempotent |
| Acknowledged but unfinished work | **Lost.** This is why you ACK *after* processing, not before |
| In-memory state | Lost |
| FastAPI `BackgroundTasks` | Lost silently — client already got 200 |
| HTTP responses in flight | Client gets a connection reset; will likely retry |

**SIGTERM vs SIGKILL — the distinction to state clearly:** SIGTERM is catchable and is a *request* to stop. SIGKILL (signal 9) cannot be caught, blocked, or ignored — the kernel destroys the process. Kubernetes sends SIGTERM, waits `terminationGracePeriodSeconds`, then sends SIGKILL. You cannot handle SIGKILL, which is precisely why durability must live in the database and the queue, not in your shutdown handler.

**The design principle this leads to:** *assume the process can vanish at any instant without warning.* That assumption forces the right architecture — durable queues, at-least-once delivery, idempotent consumers, ACK-after-processing, heartbeat-based stuck-job detection. Every one of those exists because SIGKILL, OOM kills, and hardware failure are real.

**Real example.** A Kubernetes node preemption during a 40-turn agent run. If turn state lives in memory, the run is lost. If each turn's result is persisted with a run ID, a new worker resumes from turn 23. That's question 317 in your bank, and this is why the answer to it is "persist every turn".

---

*End of Document 01. Next: Document 02 — FastAPI / ASGI (questions 46–100).*
