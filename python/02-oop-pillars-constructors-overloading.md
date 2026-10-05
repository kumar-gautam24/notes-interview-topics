# OOP in Python: Constructors, Comparison, Overloading and the Four Pillars

## 1. The four OOP pillars, Python style

Python supports all four classic OOP pillars, but it relies on convention and duck typing more than on keywords. There's no `private`, no `interface`, and no method overloading; instead there are underscores, abstract base classes, protocols and default arguments.

| Pillar | Idea in one line | Python's way | Dart / Java way |
| --- | --- | --- | --- |
| Encapsulation | Hide internal details behind a clear interface | `_name` convention, `@property` | `private`, `_name` (Dart), getters/setters |
| Abstraction | Expose what an object does, not how | Abstract base classes (`ABC`), `Protocol` | `abstract class`, `interface` |
| Inheritance | Reuse and extend a parent class | `class Child(Parent)`, `super()`, multiple inheritance allowed | `extends`, single inheritance plus mixins |
| Polymorphism | Same call, different behavior per type | Overriding plus duck typing | Overriding plus interfaces |

### The running example

As in the Deep Dive guide, every section uses runs:

```python
class Run:
    def __init__(self, run_id: int, name: str, status: str = "pending"):
        self.id = run_id
        self.name = name
        self.status = status
```

Each pillar gets its own section, with examples first in isolation, then on `Run`, then in FastAPI: encapsulation in section 7, abstraction and polymorphism in section 8, inheritance in sections 8 and 9.

### Duck typing: the idea underneath everything

"If it walks like a duck and quacks like a duck, it's a duck." Python doesn't check an object's type before calling a method; it just calls it. If the method exists, it works.

```python
class MemoryStore:
    def get(self, run_id): return f"memory run {run_id}"

class SqlStore:
    def get(self, run_id): return f"sql run {run_id}"

def show(store, run_id):          # no type check: anything with .get works
    print(store.get(run_id))

show(MemoryStore(), 1)            # memory run 1
show(SqlStore(), 1)               # sql run 1
```

The two classes share no parent, yet `show` treats them the same. That's polymorphism without inheritance, and it's the most Pythonic form. Type hints (`Protocol`, section 8) let tools check it.

## 2. Defining a class vs creating objects: what runs when

Defining a class runs only the class body, once. `__init__` and every other method run only when called: `__init__` when you create an object, other methods when you call them. If you define a class but never create an object, `__init__` never runs.

### Example 1: class only, no object

```python
# runs.py
print("1. file starts")

class Run:
    print("2. class body runs now")      # executes during the class definition
    kind = "eval"                         # class attribute: created now

    def __init__(self, name):
        print("   __init__ runs")          # NOT now: only when an object is created
        self.name = name

    def start(self):
        print("   start runs")             # NOT now: only when called

print("3. file ends")
```

Output of `python3 runs.py`:

```
1. file starts
2. class body runs now
3. file ends
```

`__init__` and `start` never printed. `def` inside a class only creates the function object and attaches it to the class; the code inside waits until someone calls it.

### Example 2: now create objects

Add these lines at the end of the same file:

```python
a = Run("eval-1")        # __init__ runs
b = Run("eval-2")        # __init__ runs again, for b
a.start()                # start runs, for a
```

New output lines:

```
   __init__ runs
   __init__ runs
   start runs
```

### What runs when: the full table

| Code | When it runs | How many times |
| --- | --- | --- |
| Top-level statements in a module | First import (or running the file) | Once per process |
| `class Run:` body (class attributes, `print` in the body) | When the `class` line is reached, at import | Once per process |
| `def` lines inside the class | Same moment, but only create the function; the body doesn't run | Once |
| `__init__` body | Every time you write `Run(...)` | Once per object |
| Other method bodies | Every time you call `obj.method()` | Per call |
| Decorators on methods (`@property`, `@classmethod`) | At class definition | Once |

### Combined with imports

```python
# main.py
from runs import Run      # runs.py executes: prints 1, 2, 3, class is defined
# no objects yet, so no __init__ output

def create():
    return Run("eval-1")  # __init__ runs only when create() is called
```

This is the whole trick for "don't run it at import": put the work inside a function or `__init__` or a method, and call it when needed. The Foundations guide, section 1, lists the patterns for this.

### Dart comparison

In Dart, a class declaration never executes code; there's no class body to run. In Python, the class body is ordinary code that runs once. That's why you shouldn't put slow work (like reading files or connecting to a DB) directly in a class body or at module level.

## 3. Constructors

A Python class has exactly one `__init__`. If you don't write one, it inherits a default that takes no arguments. For "several constructors", use default arguments or class methods, which are Python's version of Dart's named and factory constructors.

### Case 1: no `__init__` at all, the default constructor

```python
class Empty:
    pass

e = Empty()          # works: uses object.__init__, which takes no arguments
Empty(1)             # TypeError: Empty() takes no arguments
```

Every class ultimately inherits from `object`, and `object.__init__` does nothing. That's Python's "default constructor".

### Case 2: one `__init__` with defaults, the flexible constructor

```python
class Run:
    def __init__(self, run_id: int, name: str = "untitled", status: str = "pending"):
        self.id = run_id
        self.name = name
        self.status = status

Run(1)                              # id=1, name=untitled, status=pending
Run(2, "eval-2")                    # id=2, name=eval-2
Run(3, status="done")               # keyword: skip name, set status
```

One `__init__` with defaults covers what Java would do with three overloaded constructors.

### Case 3: writing two `__init__` methods, the trap

```python
class Run:
    def __init__(self, name):
        self.name = name

    def __init__(self, run_id, name):   # replaces the first one completely
        self.id = run_id
        self.name = name

Run("eval-1")        # TypeError: missing 1 required positional argument: 'name'
```

A class body is ordinary code: the second `def __init__` rebinds the name `__init__`, exactly like assigning a variable twice. The first is gone. No error at definition; the error appears when you call it the "old" way.

### Case 4: alternative constructors with `@classmethod`

When objects can be built from different kinds of input, give each way its own named class method. Each one prepares values, then calls the single `__init__` through `cls(...)`.

```python
import json

class Run:
    def __init__(self, run_id: int, name: str, status: str = "pending"):
        self.id = run_id
        self.name = name
        self.status = status

    @classmethod
    def from_dict(cls, data: dict) -> "Run":
        return cls(data["id"], data["name"], data.get("status", "pending"))

    @classmethod
    def from_json(cls, text: str) -> "Run":
        return cls.from_dict(json.loads(text))        # reuses from_dict

    @classmethod
    def new(cls, name: str) -> "Run":
        return cls(run_id=0, name=name)               # a "not saved yet" run

r1 = Run(1, "eval-1")                                 # main constructor
r2 = Run.from_dict({"id": 2, "name": "eval-2"})
r3 = Run.from_json('{"id": 3, "name": "eval-3", "status": "done"}')
r4 = Run.new("draft")
```

Why `cls` instead of `Run`: if a subclass `PriorityRun(Run)` calls `PriorityRun.from_dict(...)`, `cls` is `PriorityRun`, so you get the right type back. Hard-coding `Run(...)` would always return the parent.

| Dart | Python equivalent |
| --- | --- |
| `Run(this.id, this.name)` | `def __init__(self, run_id, name)` |
| `Run({this.status = 'pending'})` named optional | Keyword argument with a default |
| `Run.fromJson(Map json)` named constructor | `@classmethod def from_dict(cls, data)` |
| `factory Run(...)` | `@classmethod` or a plain function that decides what to return |
| `const Run(...)` | No direct equivalent; `@dataclass(frozen=True)` for immutability |

### Case 5: keyword-only arguments for clarity

```python
class Run:
    def __init__(self, run_id: int, *, name: str, status: str = "pending"):
        ...                                   # everything after * must be passed by name

Run(1, name="eval-1")        # ok
Run(1, "eval-1")             # TypeError: takes 2 positional arguments
```

Useful when a constructor has several similar arguments that are easy to mix up.

### Case 6: generated constructors

```python
from dataclasses import dataclass, field

@dataclass
class Run:
    id: int
    name: str
    status: str = "pending"
    tags: list[str] = field(default_factory=list)

    def __post_init__(self):                  # runs right after the generated __init__
        if not self.name:
            raise ValueError("name required")
```

`@dataclass` writes `__init__` for you from the fields. `__post_init__` is where validation goes. Pydantic's `BaseModel` does the same, plus type validation.

### Case 7: a parent's constructor with a child

```python
class PriorityRun(Run):
    def __init__(self, run_id, name, priority: int):
        super().__init__(run_id, name)       # parent sets id, name, status
        self.priority = priority
```

If the child defines no `__init__`, it simply uses the parent's. If it does, it must call `super().__init__(...)` to get the parent's setup.

## 4. Many objects, many constructors

Each object has its own instance data, set by whichever constructor built it; all objects share the class's methods and class attributes. Mixing constructors is fine, because every one ends in the same `__init__`, so every object has the same shape.

### Example 1: several objects from several constructors

```python
class Run:
    created = 0                                   # class attribute: shared counter

    def __init__(self, run_id: int, name: str, status: str = "pending"):
        self.id = run_id
        self.name = name
        self.status = status
        Run.created += 1                          # update the shared counter

    @classmethod
    def from_dict(cls, data: dict) -> "Run":
        return cls(data["id"], data["name"], data.get("status", "pending"))

    def __repr__(self):
        return f"Run({self.id}, {self.name!r}, {self.status!r})"

runs = [
    Run(1, "eval-1"),
    Run.from_dict({"id": 2, "name": "eval-2", "status": "done"}),
    Run(3, "eval-3", status="running"),
]

print(runs)          # [Run(1, 'eval-1', 'pending'), Run(2, 'eval-2', 'done'), Run(3, 'eval-3', 'running')]
print(Run.created)   # 3: every path went through __init__
```

Three objects, two constructors, one `__init__`. Because `from_dict` calls `cls(...)`, it also passes through `__init__`, so the counter counted all three.

### What each object owns vs shares

|  | Lives on | Example | Changing it affects |
| --- | --- | --- | --- |
| Instance attribute | Each object (`self.x`) | `self.status` | Only that object |
| Class attribute | The class (`Run.x`) | `Run.created` | Every object's view |
| Method | The class | `start`, `__repr__` | Nothing; code is shared, data isn't |

### Example 2: changing one object

```python
runs[0].status = "running"
print(runs[0].status, runs[1].status)   # running done
```

Only `runs[0]` changed. Each object's `__dict__` is separate.

### Example 3: the class attribute shadowing trap

```python
r = runs[0]
r.created = 100          # creates an INSTANCE attribute on r only
print(r.created)         # 100
print(Run.created)       # 3: the class attribute is untouched
```

Writing `self.x = ...` or `obj.x = ...` always writes to the object, even if the class has an `x`. To change the shared value, write `Run.created` (or `type(self).created`), as `__init__` does.

### Example 4: working with collections of objects

```python
pending = [r for r in runs if r.status == "pending"]      # filter
names = [r.name for r in runs]                            # extract
by_id = {r.id: r for r in runs}                           # index by id: fast lookup
by_id[2].name                                             # 'eval-2'

from collections import defaultdict
by_status = defaultdict(list)
for r in runs:
    by_status[r.status].append(r)                         # group
```

This is exactly how `RunStore` keeps its runs: a dict from id to object.

### Example 5: objects inside objects (composition)

```python
class Owner:
    def __init__(self, username: str):
        self.username = username

class Run:
    def __init__(self, run_id: int, name: str, owner: Owner):
        self.id = run_id
        self.name = name
        self.owner = owner                  # a reference to another object

g = Owner("gautam")
a = Run(1, "eval-1", g)
b = Run(2, "eval-2", g)
g.username = "gautam.k"
print(a.owner.username, b.owner.username)   # gautam.k gautam.k  (same Owner object)
```

Both runs point to one `Owner`. That's usually what you want (one real owner), and it's exactly how ORM relationships like `run.owner` behave.

## 5. Comparing objects

By default, two separate objects are never equal, even with identical data, because `==` falls back to identity. Define `__eq__` to compare by value, `__hash__` to use objects in sets or as dict keys, and `__lt__` (or `@total_ordering`) to sort them.

### Step 1: the default behavior

```python
class Run:
    def __init__(self, run_id, name):
        self.id = run_id
        self.name = name

a = Run(1, "eval-1")
b = Run(1, "eval-1")
c = a

print(a == b)    # False: different objects, default == means "is"
print(a is b)    # False
print(a == c)    # True: same object
print(a is c)    # True
```

### Step 2: equality by value with `__eq__`

Decide what "the same run" means. Here: same id.

```python
class Run:
    def __init__(self, run_id, name):
        self.id = run_id
        self.name = name

    def __eq__(self, other):
        if not isinstance(other, Run):
            return NotImplemented          # let Python try the other side, then give False
        return self.id == other.id

print(Run(1, "eval-1") == Run(1, "renamed"))   # True: same id
print(Run(1, "x") == Run(2, "x"))              # False
print(Run(1, "x") == "x")                      # False (NotImplemented handled for us)
```

`!=` automatically uses the opposite of `__eq__`.

### Step 3: the hash rule, and why sets break

```python
runs = {Run(1, "eval-1")}     # TypeError: unhashable type: 'Run'
```

When you define `__eq__`, Python sets `__hash__` to `None`, making the object unusable in sets and as dict keys. The rule behind it: objects that are equal must have equal hashes, otherwise sets and dicts would lose them. Fix by hashing the same fields you compare:

```python
class Run:
    ...
    def __eq__(self, other):
        return isinstance(other, Run) and self.id == other.id

    def __hash__(self):
        return hash(self.id)

unique = {Run(1, "a"), Run(1, "b"), Run(2, "c")}
print(len(unique))            # 2: the two id=1 runs count as one
```

Only hash fields that never change after creation. If `id` changed while the object sat in a set, the set could no longer find it.

### Step 4: ordering with `__lt__` and `@total_ordering`

```python
from functools import total_ordering

@total_ordering
class Run:
    def __init__(self, run_id, name):
        self.id = run_id
        self.name = name

    def __eq__(self, other):
        return isinstance(other, Run) and self.id == other.id

    def __lt__(self, other):
        return self.id < other.id

    def __hash__(self):
        return hash(self.id)

print(Run(1, "a") < Run(2, "b"))      # True
print(Run(3, "a") >= Run(2, "b"))     # True: generated by @total_ordering
print(sorted([Run(3, "c"), Run(1, "a")]))  # sorted by id
```

You write `__eq__` and `__lt__`; `@total_ordering` fills in `<=`, `>`, `>=`.

### Step 5: often you don't need ordering methods at all

For sorting by different fields at different times, pass a `key`:

```python
runs = [Run(3, "c"), Run(1, "b"), Run(2, "a")]
by_id = sorted(runs, key=lambda r: r.id)
by_name = sorted(runs, key=lambda r: r.name)
newest_first = sorted(runs, key=lambda r: r.id, reverse=True)
latest = max(runs, key=lambda r: r.id)
```

This is usually better than a built-in `__lt__`, because a run has no single natural order.

### Step 6: let dataclasses write it all

```python
from dataclasses import dataclass

@dataclass(frozen=True, order=True)
class RunKey:
    project: str
    run_id: int

a = RunKey("vaidya", 1)
b = RunKey("vaidya", 1)
print(a == b)                     # True: compares all fields
print(len({a, b}))                # 1: frozen=True makes it hashable
print(RunKey("a", 2) < RunKey("b", 1))   # True: compares fields in order
a.run_id = 5                      # FrozenInstanceError: immutable
```

| Option | Generates |
| --- | --- |
| `@dataclass` | `__init__`, `__repr__`, `__eq__` (all fields) |
| `eq=False` | Keeps identity comparison |
| `order=True` | `<`, `<=`, `>`, `>=`, comparing fields in order |
| `frozen=True` | Immutable fields, plus `__hash__` |

Pydantic models also compare by field values with `==`.

### Summary

| You want | Write |
| --- | --- |
| Same object? | `a is b` |
| Same value? | `__eq__` (or `@dataclass`) |
| Use in sets or dict keys | `__hash__` on immutable fields (or `frozen=True`) |
| Sort one natural way | `__lt__` + `@total_ordering` (or `order=True`) |
| Sort different ways | `sorted(items, key=...)` |

## 6. Overloading

Python has no method overloading: defining a method twice keeps only the last one. You get the same effect with default arguments, `*args`, named class methods, or `singledispatchmethod`. Operator overloading, however, is fully supported through dunder methods.

### Why method overloading doesn't exist

```python
class RunService:
    def find(self, run_id: int):
        return f"by id {run_id}"

    def find(self, name: str):           # replaces the first find
        return f"by name {name}"

RunService().find(1)                     # 'by name 1': the int version is gone
```

In Java, the compiler picks a method by argument types. Python has no compile step that chooses; a class body just binds names, so the second `def find` overwrites the first. Type hints don't help, because Python doesn't use them at runtime.

### Alternative 1: default and optional arguments (most common)

```python
def find(self, run_id: int | None = None, name: str | None = None):
    if run_id is not None:
        return self.store.get(run_id)
    if name is not None:
        return self.store.get_by_name(name)
    raise ValueError("give run_id or name")
```

This is what FastAPI routes do all the time: optional query parameters instead of several routes.

### Alternative 2: separate, clearly named methods (often clearest)

```python
def find_by_id(self, run_id: int): ...
def find_by_name(self, name: str): ...
```

The name documents the intent, and there's no branching. Alternative constructors (`from_dict`, `from_json`) are this same idea.

### Alternative 3: accept any number of arguments

```python
def add_tags(self, *tags: str):
    self.tags.extend(tags)

run.add_tags("urgent")
run.add_tags("urgent", "nightly", "gpu")
```

### Alternative 4: dispatch on type with `singledispatchmethod`

```python
from functools import singledispatchmethod

class RunService:
    @singledispatchmethod
    def find(self, arg):
        raise TypeError(f"unsupported: {type(arg)}")

    @find.register
    def _(self, arg: int):
        return f"by id {arg}"

    @find.register
    def _(self, arg: str):
        return f"by name {arg}"

s = RunService()
s.find(1)          # by id 1
s.find("eval-1")   # by name eval-1
```

This chooses by the type of the first argument after `self`, at runtime. It's the closest thing to true overloading, but it's rare in application code; alternatives 1 and 2 are clearer.

### `typing.overload`: for type checkers only

```python
from typing import overload

class RunService:
    @overload
    def find(self, key: int) -> Run: ...
    @overload
    def find(self, key: str) -> list[Run]: ...
    def find(self, key):                     # the one real implementation
        ...
```

The `@overload` stubs tell editors "an int returns one run, a str returns a list". Only the last, undecorated `find` exists at runtime.

### Operator overloading: fully supported

Operators are method calls in disguise: `a + b` runs `a.__add__(b)`. Define the dunder, and the operator works on your objects.

```python
class RunBatch:
    def __init__(self, runs: list[Run]):
        self.runs = runs

    def __len__(self):                       # len(batch)
        return len(self.runs)

    def __getitem__(self, i):                # batch[0], and makes it iterable
        return self.runs[i]

    def __contains__(self, run):             # run in batch
        return run in self.runs

    def __add__(self, other: "RunBatch"):    # batch1 + batch2
        return RunBatch(self.runs + other.runs)

    def __bool__(self):                      # if batch:
        return bool(self.runs)

    def __repr__(self):                      # shown in the shell and debugger
        return f"RunBatch({len(self)} runs)"

b1 = RunBatch([Run(1, "a")])
b2 = RunBatch([Run(2, "b"), Run(3, "c")])
both = b1 + b2
print(both, len(both), both[0].name)       # RunBatch(3 runs) 3 a
for run in both: print(run.id)             # 1 2 3
```

| Operator or call | Method |
| --- | --- |
| `a + b`, `a - b`, `a * b` | `__add__`, `__sub__`, `__mul__` |
| `a == b`, `a < b` | `__eq__`, `__lt__` |
| `len(a)` | `__len__` |
| `a[i]`, `a[k] = v` | `__getitem__`, `__setitem__` |
| `x in a` | `__contains__` |
| `for x in a` | `__iter__` (or `__getitem__`) |
| `if a:` | `__bool__` (else `__len__`) |
| `str(a)`, `print(a)` | `__str__` |
| `repr(a)`, the shell | `__repr__` |
| `a()` | `__call__` |
| `with a:` | `__enter__`, `__exit__` |

Use operator overloading when the meaning is obvious (adding two batches); avoid it when it would surprise a reader.

### Overloading vs overriding

Interviewers often ask this pair. Overloading means same name, different parameter lists, in one class; Python doesn't support it for methods. Overriding means a child class redefines a parent's method with the same name; Python fully supports it (section 8).

## 7. Encapsulation

Encapsulation means an object controls its own state: outsiders use its methods and never poke its internals. Python enforces nothing; it uses naming conventions plus properties, and trusts developers to respect them.

### Three levels of "privacy"

| Name | Meaning | Enforced? |
| --- | --- | --- |
| `status` | Public: part of the object's interface | n/a |
| `_status` | Internal: "don't use from outside" | No, pure convention (linters warn) |
| `__status` | Name-mangled to `_Run__status` | Partly: avoids accidental clashes in subclasses |

```python
class Run:
    def __init__(self):
        self._status = "pending"
        self.__secret = "x"

r = Run()
r._status              # works, but you're breaking the contract
r.__secret             # AttributeError
r._Run__secret         # works: the mangled name
```

Use single underscore for internals. Double underscore is for the rare case where a subclass might accidentally reuse the same name.

### Why encapsulate: the broken-state problem

```python
r = Run(1, "eval-1")
r.status = "finished"     # typo: not a valid status, nothing stops it
r.status = "done"         # skipped "running": a rule was broken
```

If any code can set `status` freely, the rules ("valid values only", "pending then running then done") live nowhere. Encapsulation puts the rules inside the class.

### Step 1: methods that guard transitions

```python
class Run:
    _TRANSITIONS = {"pending": {"running"}, "running": {"done", "failed"}}

    def __init__(self, run_id: int, name: str):
        self.id = run_id
        self.name = name
        self._status = "pending"           # internal

    def _move(self, new: str):             # internal helper
        if new not in self._TRANSITIONS.get(self._status, set()):
            raise ValueError(f"can't go {self._status} -> {new}")
        self._status = new

    def start(self):  self._move("running")
    def finish(self, ok: bool = True):  self._move("done" if ok else "failed")
```

Now the only way to change status is through `start` and `finish`, and invalid moves raise.

### Step 2: read access with `@property`

Callers still need to read the status. A property gives read-only access that looks like a normal attribute:

```python
class Run:
    ...
    @property
    def status(self) -> str:
        return self._status

r = Run(1, "eval-1")
print(r.status)           # pending: reads like an attribute
r.status = "done"         # AttributeError: property has no setter
r.start(); print(r.status)   # running
```

### Step 3: a setter with validation

For values that may change but must stay valid:

```python
class Run:
    def __init__(self, run_id: int, name: str):
        self.id = run_id
        self.name = name                   # goes through the setter below, even here

    @property
    def name(self) -> str:
        return self._name

    @name.setter
    def name(self, value: str):
        value = value.strip()
        if not value:
            raise ValueError("name required")
        self._name = value

r = Run(1, "  eval-1 ")
print(r.name)             # eval-1 (cleaned by the setter)
r.name = ""               # ValueError
```

Notice `self.name = name` in `__init__` calls the setter, so the same validation protects construction and later changes.

### Step 4: computed properties

```python
import time

class Run:
    ...
    @property
    def is_active(self) -> bool:
        return self._status == "running"

    @property
    def age_seconds(self) -> float:
        return time.time() - self.created_at
```

Values derived from state stay correct automatically, with no extra field to keep in sync.

### A Pythonic note

Don't wrap every attribute in a property "just in case", as in Java. Start with plain public attributes. If you later need validation, turn the attribute into a property: callers' code (`r.name`) doesn't change. That's why Python doesn't need getters and setters by default.

## 8. Inheritance, abstraction and polymorphism

Inheritance reuses a parent's code, abstraction defines what methods an object must have, and polymorphism lets one piece of code work with any object that has those methods. In Python, polymorphism works through overriding or through duck typing, and `ABC` or `Protocol` make the contract explicit.

### Overriding: same method, child's version

```python
class Run:
    def __init__(self, run_id, name):
        self.id, self.name = run_id, name

    def cost(self) -> float:
        return 1.0

    def describe(self) -> str:
        return f"{self.name}: {self.cost()} credits"   # calls whichever cost() the object has

class GpuRun(Run):
    def cost(self) -> float:                  # override
        return 5.0

class BatchRun(Run):
    def __init__(self, run_id, name, size: int):
        super().__init__(run_id, name)
        self.size = size

    def cost(self) -> float:
        return super().cost() * self.size     # extend the parent's version

runs = [Run(1, "a"), GpuRun(2, "b"), BatchRun(3, "c", size=10)]
for r in runs:
    print(r.describe())
```

Output:

```
a: 1.0 credits
b: 5.0 credits
c: 10.0 credits
```

`describe` is written once, in `Run`, yet gives three different results. That's polymorphism: `self.cost()` looks up `cost` on the actual object's class first.

### Abstraction with `ABC`: a contract enforced at creation

```python
from abc import ABC, abstractmethod

class Notifier(ABC):
    @abstractmethod
    def send(self, user: str, message: str) -> None: ...

class EmailNotifier(Notifier):
    def send(self, user, message):
        print(f"email to {user}: {message}")

class SlackNotifier(Notifier):
    def send(self, user, message):
        print(f"slack to {user}: {message}")

class BrokenNotifier(Notifier):
    pass                                    # forgot send

Notifier()          # TypeError: can't instantiate abstract class
BrokenNotifier()    # TypeError: abstract method send not implemented
```

The error comes when you create the object, not later when `send` is missing mid-request.

### Abstraction with `Protocol`: a contract without inheritance

```python
from typing import Protocol

class Notifies(Protocol):
    def send(self, user: str, message: str) -> None: ...

class SmsNotifier:                      # no parent class at all
    def send(self, user: str, message: str) -> None:
        print(f"sms to {user}: {message}")

def notify_done(n: Notifies, run: Run):
    n.send("gautam", f"{run.name} finished")

notify_done(SmsNotifier(), Run(1, "eval-1"))   # works; a type checker also approves
```

|  | `ABC` | `Protocol` |
| --- | --- | --- |
| Classes must inherit from it | Yes | No |
| Checked at runtime | Yes, on creation | No (only by mypy or pyright) |
| Works with classes you don't own | No | Yes |
| Good for | Your own class families | Typing third-party or loosely coupled code |

### Multiple inheritance and the MRO

Python lets a class have several parents. The method resolution order decides which parent's method wins: left to right, and each class appears only once.

```python
class A:
    def hello(self): return "A"

class B(A):
    def hello(self): return "B then " + super().hello()

class C(A):
    def hello(self): return "C then " + super().hello()

class D(B, C):
    pass

print(D().hello())                 # B then C then A
print([k.__name__ for k in D.__mro__])   # ['D', 'B', 'C', 'A', 'object']
```

`super()` means "the next class in the MRO", not necessarily the direct parent. Inside `B`, `super()` for a `D` object is `C`. This "diamond" is why `super()` exists instead of calling parents by name.

### Mixins: small reusable abilities

A mixin is a small class that adds one capability, meant to be combined with others:

```python
import json, time

class JsonMixin:
    def to_json(self) -> str:
        return json.dumps(self.__dict__, default=str)

class TimestampMixin:
    def touch(self):
        self.updated_at = time.time()

class Run(JsonMixin, TimestampMixin):
    def __init__(self, run_id, name):
        self.id, self.name = run_id, name

r = Run(1, "eval-1"); r.touch()
print(r.to_json())       # {"id": 1, "name": "eval-1", "updated_at": ...}
```

Rules: mixins don't define `__init__` (or they call `super().__init__()`), don't hold much state, and are named `...Mixin`. It's the same idea as Dart's `with`.

### `isinstance` vs `type`, and when to avoid both

```python
isinstance(GpuRun(1, "x"), Run)     # True: subclasses count
type(GpuRun(1, "x")) is Run         # False: exact class only
```

If you find yourself writing `if isinstance(x, GpuRun): ... elif isinstance(x, BatchRun): ...`, that's a sign to move the behavior into an overridden method instead. That's polymorphism doing its job.

## 9. Composition vs inheritance, and SOLID

Prefer composition (an object holds other objects) over inheritance (an object is a kind of another) unless the "is a" relationship is genuinely true and stable. SOLID is five design guidelines that mostly say the same thing: small focused classes, wired together through constructors.

### The test: "is a" vs "has a"

| Relationship | Sounds right? | Use |
| --- | --- | --- |
| A `GpuRun` is a `Run` | Yes | Inheritance |
| A `RunService` has a store | Yes | Composition |
| A `RunService` is a `RunStore` | No | Not inheritance |
| A `RunService` has a notifier | Yes | Composition |

### The same feature both ways

Goal: a service that stores runs and sends a notification when one finishes.

```python
# Inheritance: the service becomes a store AND a notifier
class RunService(MemoryRunStore, EmailNotifier):
    def finish(self, run_id):
        run = self.get(run_id)
        run.finish()
        self.send("gautam", f"{run.name} done")
```

Problems: to use SQL instead of memory, or Slack instead of email, you need a new subclass for every combination (four combinations, four classes). Tests can't swap parts.

```python
# Composition: the service holds a store and a notifier
class RunService:
    def __init__(self, store: BaseRunStore, notifier: Notifies):
        self.store = store
        self.notifier = notifier

    def finish(self, run_id: int):
        run = self.store.get(run_id)
        run.finish()
        self.notifier.send("gautam", f"{run.name} done")

prod = RunService(SqlRunStore(db), SlackNotifier())
test = RunService(MemoryRunStore(), FakeNotifier())
```

Any store with any notifier, chosen at construction. This is constructor injection again, and it's exactly what FastAPI's `Depends` produces.

### SOLID, each with the runs example

1. **Single responsibility:** a class has one reason to change. `Run` holds run state and rules; `RunStore` handles persistence; `RunService` coordinates. Changing the database touches only the store.
2. **Open/closed:** open to extension, closed to modification. Add `GpuRun(Run)` with its own `cost()` instead of editing `Run.cost` with `if` branches.
3. **Liskov substitution:** a subclass must work anywhere the parent works. If `BatchRun.start()` suddenly required an extra argument, code expecting a `Run` would break. Keep overridden method signatures compatible.
4. **Interface segregation:** small contracts beat big ones. `Notifies` has one method; a notifier shouldn't be forced to implement `get_run` too.
5. **Dependency inversion:** depend on abstractions, not concrete classes. `RunService` accepts a `BaseRunStore` or anything with `get` and `add`, not specifically `SqlRunStore`.

Interview tip: you don't need to recite SOLID. Showing one refactor, from inheritance to composition with injection, demonstrates all five.

## 10. OOP inside FastAPI, and interview questions

A FastAPI project uses every idea in this guide: Pydantic models are generated constructors with validation, exception families use inheritance, services use composition, and `Depends` does the constructor injection for you.

### Where each concept appears

| Concept | Section | In a FastAPI project |
| --- | --- | --- |
| Class body runs once, `__init__` per object | 2 | Routers and models defined at import; services built per request |
| One `__init__`, alternative constructors | 3 | `Model.model_validate(data)`, `Settings()` |
| Many objects, shared class data | 4 | One engine per process, one session per request |
| `__eq__` and hashing | 5 | Pydantic models compare by fields; frozen models as cache keys |
| No overloading, optional parameters instead | 6 | Optional query parameters instead of several routes |
| Encapsulation, properties | 7 | Private `_session` in repositories, computed fields |
| Inheritance, ABC, Protocol | 8 | `BaseModel`, `AppError` families, `BaseRunStore` |
| Composition, dependency inversion | 9 | `RunService(store, notifier)` built by `Depends` |

### The whole picture in one file

```python
from typing import Annotated
from fastapi import FastAPI, Depends
from pydantic import BaseModel

class RunIn(BaseModel):                          # generated constructor + validation
    name: str

class RunOut(RunIn):                             # inheritance of fields
    id: int
    status: str

store = MemoryRunStore()                         # module level: one per process

def get_notifier() -> Notifies:
    return SlackNotifier()

def get_service(notifier: Annotated[Notifies, Depends(get_notifier)]) -> RunService:
    return RunService(store, notifier)           # composition, injected per request

app = FastAPI()

@app.post("/runs", response_model=RunOut, status_code=201)
def create(body: RunIn, service: Annotated[RunService, Depends(get_service)]):
    run = service.create(body.name)              # encapsulated rules inside Run
    return RunOut(id=run.id, name=run.name, status=run.status)

# In tests: swap one part, keep the rest
# app.dependency_overrides[get_notifier] = lambda: FakeNotifier()
```

### Interview questions

1. **What are the four pillars, and how does Python implement each?** Encapsulation with `_` naming and properties; abstraction with `ABC` and `Protocol`; inheritance with subclasses, `super()` and multiple inheritance; polymorphism with overriding and duck typing.
2. **Can a Python class have multiple constructors?** Only one `__init__`; a second definition replaces the first. Use default arguments or `@classmethod` alternative constructors like `from_dict`.
3. **What happens if you don't define `__init__`?** The class inherits `object.__init__`, which takes no arguments.
4. **Does defining a class run `__init__`?** No. The class body runs once at definition; `__init__` runs only when an object is created.
5. **Does Python support method overloading?** No, the last definition wins. Use optional arguments, separate names, `*args`, or `singledispatchmethod`. Operator overloading is supported via dunder methods.
6. **Overloading vs overriding?** Overloading: same name, different parameters, one class (not supported). Overriding: a subclass redefines a parent method (supported).
7. **How do you compare two objects by value?** Define `__eq__`; also define `__hash__` on immutable fields if they go in sets or dict keys, or use `@dataclass(frozen=True)`.
8. **Why does defining `__eq__` make an object unhashable?** Python sets `__hash__` to `None` to protect the rule that equal objects must have equal hashes.
9. **What is the MRO?** The order Python searches classes for attributes; `super()` follows it, which makes multiple inheritance work predictably.
10. **Class method vs static method vs instance method?** Instance gets `self`; class method gets `cls` (used for alternative constructors); static gets neither (a helper grouped with the class).
11. **Is there `private` in Python?** No. `_name` is a convention, `__name` triggers name mangling; neither is true privacy.
12. **Composition vs inheritance, which would you choose?** Composition by default for flexibility and testability; inheritance for true, stable "is a" relationships. Example: `RunService(store, notifier)` instead of inheriting from both.
13. **What's duck typing?** Using an object by its methods, not its declared type; `Protocol` adds static checking to it.
14. **What does `@property` give you over a getter method?** Attribute-style access with validation or computation, and you can add it later without changing callers.

### Exercises

1. Give `Run` three constructors (`__init__`, `from_dict`, `from_json`) and a class counter; create one object from each and print the count.
2. Make `Run` compare by id, put duplicates in a set, then sort a list by name with `key=`.
3. Try defining `find` twice, observe the result, then rewrite it with optional arguments and with `singledispatchmethod`.
4. Encapsulate `status` behind `start()` and `finish()` with a read-only property; try an invalid transition.
5. Build `Notifier` as an `ABC` with two implementations, then as a `Protocol` with an unrelated class, and use each in `RunService` through constructor injection.
6. Refactor the inheritance version of `RunService` from section 9 into the composition version, and write one test that uses a fake notifier.
