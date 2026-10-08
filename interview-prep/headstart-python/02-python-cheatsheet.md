# 02 · Python Cheatsheet (interview edition)

What a Python backend interviewer probes: the language model (mutability, references, scope), the "advanced" features (decorators, generators, context managers), OOP, exceptions, and concurrency. Each item gives the one-line explanation first, then the minimum code. Concurrency and big data are only summarised here; the long versions are in [04-theory-answers.md §6](04-theory-answers.md#6-weak-areas-deep-dive).

---

## 1. Core data model

**Everything is an object; variables are names bound to objects.** Assignment never copies.

| Type | Mutable? | Ordered? | Notes |
|---|---|---|---|
| `int, float, bool, str, tuple, frozenset, bytes` | No | — | Hashable (if contents are), can be dict keys |
| `list` | Yes | Yes | Dynamic array: append O(1) amortised, insert/pop(0) O(n) |
| `dict` | Yes | Insertion order (3.7+) | Hash table: get/set/in O(1) average |
| `set` | Yes | No | Hash table: `in` O(1) average |
| `deque` | Yes | Yes | O(1) append/pop at both ends; use for queues |

- `==` compares values; `is` compares identity (same object). Use `is` only for `None`, `True`, `False`.
- Small ints (−5..256) and some strings are cached, so `a is b` can be True by accident. Never rely on it.

```python
a = [1, 2]; b = a; b.append(3)   # a is now [1, 2, 3] — same object
import copy
shallow = copy.copy(nested)      # new outer list, inner objects shared
deep = copy.deepcopy(nested)     # everything copied
```

**Mutable default argument trap** (very common question):
```python
def add(item, bucket=[]):        # BUG: one list created at def time, shared by all calls
    bucket.append(item); return bucket

def add(item, bucket=None):      # fix
    bucket = [] if bucket is None else bucket
    bucket.append(item); return bucket
```

**Arguments are passed by object reference** ("pass by assignment"): mutating a passed list is visible to the caller; rebinding the name isn't.

## 2. Scope, closures, functions

- **LEGB** lookup order: Local → Enclosing → Global → Built-in. `global x` / `nonlocal x` to rebind outer names.
- **Closure:** inner function that remembers variables of the enclosing scope after it returns.
- `*args` collects extra positional args into a tuple; `**kwargs` collects keyword args into a dict. Keyword-only args go after `*`: `def f(a, *, b)`.
- `lambda x: x * 2` is a one-expression anonymous function; good for `key=` in `sorted`.

```python
def counter():
    count = 0
    def inc():
        nonlocal count
        count += 1
        return count
    return inc

c = counter(); c(); c()          # 2

sorted(users, key=lambda u: (u["age"], u["name"]))
```

## 3. Comprehensions

```python
squares = [x * x for x in nums if x > 0]           # list
index   = {u.id: u for u in users}                  # dict
unique  = {e.lower() for e in emails}               # set
total   = sum(x * x for x in nums)                  # generator expression: no list built
```
Comprehensions are faster than equivalent `for` + `append` and read better; don't nest more than two levels.

## 4. Decorators

A decorator takes a function and returns a new one. `@d` above `def f` means `f = d(f)`. Use `functools.wraps` to keep the original name and docstring.

```python
import functools, time

def timed(fn):
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        try:
            return fn(*args, **kwargs)
        finally:
            print(f"{fn.__name__}: {(time.perf_counter() - start) * 1000:.1f}ms")
    return wrapper

def retry(times=3):              # decorator WITH arguments = one extra level
    def deco(fn):
        @functools.wraps(fn)
        def wrapper(*a, **kw):
            for attempt in range(times):
                try:
                    return fn(*a, **kw)
                except ConnectionError:
                    if attempt == times - 1:
                        raise
        return wrapper
    return deco
```
Built-in ones to name: `@property`, `@staticmethod`, `@classmethod`, `@functools.lru_cache`, `@dataclass`, `@abstractmethod`; framework ones: `@app.get`, `@field_validator`, `@app.task`.

## 5. Iterators and generators

- **Iterable:** has `__iter__` (list, dict, file). **Iterator:** has `__next__`, raises `StopIteration` when done. A `for` loop calls `iter()` then `next()` repeatedly.
- **Generator:** a function with `yield`. Calling it returns a lazy iterator; it pauses at each `yield` and resumes on the next `next()`. Memory is O(1) per item, which is the whole point for big data.
- `yield from sub()` delegates to another generator.

```python
def read_in_batches(path, size=1000):
    batch = []
    with open(path) as f:
        for line in f:                 # files are lazy iterators too
            batch.append(line.rstrip("\n"))
            if len(batch) == size:
                yield batch
                batch = []
    if batch:
        yield batch

for batch in read_in_batches("leads.csv"):
    save(batch)                        # never more than 1000 lines in memory
```
`itertools` to know: `islice` (take n lazily), `chain`, `groupby` (needs sorted input), `count`, `product`, `batched` (3.12+).

## 6. Context managers

`with` guarantees cleanup (close file, release lock, commit/rollback) even if an exception happens. Implemented by `__enter__` / `__exit__`, or more simply with `@contextmanager`.

```python
from contextlib import contextmanager

@contextmanager
def transaction(conn):
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
```
Async version: `async with` + `@asynccontextmanager` (used for FastAPI `lifespan` and asyncpg pools).

## 7. OOP

**Four pillars in one line each:**
- **Encapsulation:** bundle data + behaviour, hide internals (`_internal` by convention; `__x` name-mangles to `_Class__x`).
- **Abstraction:** expose *what* not *how*: `abc.ABC` + `@abstractmethod`.
- **Inheritance:** reuse/extend a parent; `super()` calls the next class in the MRO.
- **Polymorphism:** same interface, different implementations (duck typing: "if it has `.send()`, it's a notifier").

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass

class Notifier(ABC):
    @abstractmethod
    def send(self, to: str, msg: str) -> None: ...

class EmailNotifier(Notifier):
    def send(self, to, msg): print(f"email {to}: {msg}")

class SmsNotifier(Notifier):
    def send(self, to, msg): print(f"sms {to}: {msg}")

def notify_all(notifiers: list[Notifier], to, msg):
    for n in notifiers:
        n.send(to, msg)              # polymorphism

class Account:
    interest = 0.04                  # class attribute, shared
    def __init__(self, owner, balance=0):
        self.owner = owner           # instance attribute
        self._balance = balance

    @property
    def balance(self):               # read like an attribute, computed/validated
        return self._balance

    @classmethod
    def from_dict(cls, d):           # alternative constructor, gets the class
        return cls(d["owner"], d.get("balance", 0))

    @staticmethod
    def is_valid_amount(x):          # no self/cls; utility grouped with the class
        return x > 0

    def __repr__(self):
        return f"Account({self.owner!r}, {self._balance})"

@dataclass(frozen=True)
class Money:                         # auto __init__, __repr__, __eq__; frozen = immutable
    paise: int                       # store money as integer paise, never float
```

- **Dunder methods:** `__init__`, `__repr__` (for devs), `__str__` (for users), `__eq__` + `__hash__`, `__len__`, `__getitem__`, `__iter__`, `__enter__/__exit__`, `__call__`.
- **`__new__` vs `__init__`:** `__new__` creates the instance, `__init__` initialises it. Override `__new__` only for immutables/singletons.
- **MRO (multiple inheritance):** C3 linearisation; check `Class.__mro__`. Diamond problem solved by cooperative `super()`.
- **Composition over inheritance:** "has-a" (service *has a* repository) beats deep "is-a" chains. Your Clean Architecture repositories are composition + dependency injection.
- **SOLID** quick: Single responsibility · Open/closed · Liskov substitution · Interface segregation · Dependency inversion (depend on `Notifier`, not `EmailNotifier`).

## 8. Exceptions

```python
class AppError(Exception):           # custom hierarchy
    status = 500
class NotFoundError(AppError):
    status = 404
class InsufficientCredits(AppError):
    status = 402

try:
    charge(user, amount)
except InsufficientCredits:          # specific first
    ...
except (TimeoutError, ConnectionError) as e:
    raise AppError("payment provider down") from e   # keep the cause chain
else:
    log.info("charged")              # runs only if no exception
finally:
    release_lock()                   # always runs
```
Rules: never bare `except:` (it catches `KeyboardInterrupt`/`SystemExit`); catch the narrowest type; log with `log.exception(...)` to include the traceback; re-raise what you can't handle; `BaseException` → `Exception` → everything you normally catch.

## 9. Memory and performance

- **Reference counting** frees objects when the count hits 0; a **cyclic garbage collector** cleans up reference cycles. `del x` removes a name, not necessarily the object.
- `__slots__ = ("a", "b")` removes the per-instance `__dict__`, saving memory for millions of small objects.
- Strings are immutable: building with `+=` in a loop is O(n²) worst case; use `"".join(parts)`.
- `in` on a list is O(n); on a set/dict O(1). Convert once if you test membership repeatedly.
- Profile before optimising: `cProfile`, `timeit`, `tracemalloc` for memory.
- `functools.lru_cache` for memoising pure functions (the Python answer to the Fibonacci question).

## 10. Concurrency in 30 seconds

- **GIL:** one thread runs Python bytecode at a time per process; released during I/O.
- **I/O-bound** (DB, HTTP, Redis) → `asyncio` (or threads for blocking libraries).
- **CPU-bound** (parsing, image work, heavy maths) → `multiprocessing` / `ProcessPoolExecutor`, one GIL per process.
- **Blocking call inside `async def`** freezes the whole event loop → use an async driver, `await asyncio.to_thread(fn)`, or move it to a worker.

```python
import asyncio

async def fetch_all(urls):
    sem = asyncio.Semaphore(20)                     # cap concurrency
    async def one(u):
        async with sem:
            return await fetch(u)
    return await asyncio.gather(*(one(u) for u in urls))
```
`gather` runs coroutines concurrently; `asyncio.create_task` schedules one in the background; `asyncio.wait_for(coro, timeout)` adds a timeout; `TaskGroup` (3.11+) is the structured version of `gather`.

## 11. Typing and Pydantic (quick)

- Type hints are not enforced at runtime by Python; tools (mypy, IDEs) and libraries (Pydantic, FastAPI) use them.
- `list[int]`, `dict[str, int]`, `X | None` (3.10+), `Optional[X]`, `Literal["a", "b"]`, `TypedDict`, `Protocol` (structural interface, duck typing with type checks).
- Pydantic v2: `BaseModel` validates and parses at runtime; `Field(gt=0, max_length=50)`, `@field_validator`, `model_dump()`, `model_validate()`, `ConfigDict(from_attributes=True)` to build from ORM objects.

## 12. Rapid-fire Q&A

| Question | Answer |
|---|---|
| list vs tuple | List mutable; tuple immutable, hashable, slightly faster, used for fixed records |
| `@staticmethod` vs `@classmethod` | Static gets nothing implicit; classmethod gets `cls` (alt constructors, works with subclasses) |
| `__str__` vs `__repr__` | `str` for end users; `repr` unambiguous for devs, falls back if no `__str__` |
| What is `if __name__ == "__main__"` | Code runs only when the file is executed directly, not imported (also required for multiprocessing on spawn) |
| Shallow vs deep copy | Shallow copies the container only; deep copies recursively |
| `append` vs `extend` | `append(x)` adds one item; `extend(iter)` adds each item |
| `range` in Python 3 | Lazy sequence object, O(1) memory |
| `dict.get(k, default)` | Avoids `KeyError`; `collections.defaultdict` for auto-init |
| `Counter` | `Counter(words).most_common(3)` |
| Is Python compiled? | Compiled to bytecode (`.pyc`), interpreted by the CPython VM |
| `pass` / `...` | Placeholder statements |
| Monkey patching | Replacing attributes at runtime; used in tests (`unittest.mock.patch`) |
| Virtual env | Isolated dependencies per project: `python -m venv .venv`; pin with `requirements.txt` / `uv` / `poetry` |
| PEP 8 | Style guide: snake_case functions, PascalCase classes, 4-space indent; enforce with `ruff`/`black` |
