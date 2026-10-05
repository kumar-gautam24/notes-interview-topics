# Python and OOP from Zero (for FastAPI)

## 1. Python basics

Python runs top to bottom, uses indentation instead of braces, and needs no semicolons. If you know Dart, most ideas map directly; this guide points out the differences.

### Running Python

```bash
python3 --version        # check it's installed (3.10+ for this guide)
python3 hello.py         # run a file
python3                  # interactive shell; exit() to quit
```

### Variables and types

No `var`, `final` or type keyword is required. You just assign.

```python
name = "Gautam"        # str
age = 27               # int
price = 99.5           # float
is_admin = False       # bool (capital F / T)
nothing = None         # like Dart's null
```

Python is dynamically typed: the value has a type, the variable doesn't. `age = "hello"` later is allowed (but a bad idea).

### Type hints

Hints describe the expected type. Python itself ignores them at runtime, but editors, linters and FastAPI read them. FastAPI uses hints to validate requests, so you will write them everywhere.

```python
name: str = "Gautam"
age: int = 27
token: str | None = None      # may be a string or None (Python 3.10+)

def greet(name: str) -> str:  # takes a str, returns a str
    return "Hi " + name
```

`str | None` is the same idea as Dart's `String?`. Older code writes it `Optional[str]` (from `typing import Optional`).

### f-strings

Put `f` before the quotes and variables inside `{}`:

```python
user = "gautam"
print(f"Hi {user}, you have {2 + 3} messages")   # Hi gautam, you have 5 messages
```

Same as Dart's `"Hi $user"`. You saw one in the cookie guide: `f"Bearer {token}"`.

### Indentation is the syntax

```python
if age > 18:
    print("adult")      # 4 spaces = inside the if
print("done")           # back to 0 = outside
```

Mixing tabs and spaces, or wrong indentation, is an error. Use 4 spaces.

### Comments

```python
# single line comment
"""A triple-quoted string at the top of a function
is a docstring: documentation for that function."""
```

### Truthy and falsy

These count as `False` in an `if`: `None`, `0`, `""`, `[]`, `{}`. Everything else is `True`. That's why the cookie code writes:

```python
if not access_token:        # catches None AND empty string
    raise HTTPException(status_code=401)
```

## 2. Collections

Four built-in containers cover almost everything: list, dict, tuple and set. In FastAPI, dicts are the most common because JSON objects become dicts.

| Type | Syntax | Ordered | Changeable | Duplicates | Dart equivalent |
| --- | --- | --- | --- | --- | --- |
| list | `[1, 2, 3]` | Yes | Yes | Yes | `List` |
| dict | `{"a": 1}` | Yes (insertion order) | Yes | Keys unique | `Map` |
| tuple | `(1, 2)` | Yes | No | Yes | Record |
| set | `{1, 2}` | No | Yes | No | `Set` |

### list

```python
runs = ["run-1", "run-2"]
runs.append("run-3")       # add to end
runs[0]                    # "run-1" (index from 0)
runs[-1]                   # "run-3" (negative = from the end)
runs[0:2]                  # ["run-1", "run-2"] (slice: start up to, not including, end)
len(runs)                  # 3
"run-2" in runs            # True
```

### dict

```python
user = {"sub": "gautam", "role": "admin"}
user["sub"]                # "gautam"
user["missing"]            # KeyError: crashes
user.get("missing")        # None: safe
user.get("missing", "x")   # "x": safe with a default
user["exp"] = 1727000900   # add or change a key
user.pop("role")           # remove and return it

for key, value in user.items():
    print(key, value)
```

This is why the cookie code uses `request.cookies.get("access_token")`: `.get` returns `None` instead of crashing when the cookie is missing. And `refresh_store.pop(hash, None)` removes and returns in one step, which is how rotation works.

### tuple

Like a list, but can't be changed. Often used to return several values.

```python
point = (10, 20)
x, y = point               # unpacking: x=10, y=20

header, payload, sig = token.split(".")   # unpacking a list the same way
```

### set

Unique values, very fast `in` checks.

```python
ALLOWED = {"https://app.x.com", "http://localhost:3000"}
if origin in ALLOWED:      # fast membership test
    ...
```

That's why the WebSocket code does `ALLOWED = set(ALLOWED_ORIGINS)`.

### Comprehensions

A one-line way to build a new collection from an old one. Read it as "give me X for each item in Y, if condition".

```python
nums = [1, 2, 3, 4]
squares = [n * n for n in nums]              # [1, 4, 9, 16]
evens = [n for n in nums if n % 2 == 0]      # [2, 4]
by_id = {u["id"]: u for u in users}          # dict comprehension
```

The long form of `squares` is:

```python
squares = []
for n in nums:
    squares.append(n * n)
```

### Copy vs reference

```python
a = [1, 2]
b = a            # same list, two names
b.append(3)
print(a)         # [1, 2, 3]  (a changed too)
c = a.copy()     # a real copy
```

Same behavior as Dart objects: variables hold references.

## 3. Functions

A function is defined with `def`, takes arguments, and returns a value with `return`. Python's argument system (defaults, keyword arguments, `*args`, `**kwargs`) is what makes FastAPI's route signatures work.

### Defining and calling

```python
def add(a: int, b: int) -> int:
    return a + b

add(2, 3)          # 5
```

No `return` means the function returns `None`.

### Positional vs keyword arguments

```python
def create_user(name: str, role: str):
    ...

create_user("gautam", "admin")             # positional: by order
create_user(role="admin", name="gautam")   # keyword: by name, any order
```

This is like Dart's named parameters, except in Python any parameter can be passed by name.

### Default values

```python
def set_cookie(name: str, value: str, max_age: int = 900, path: str = "/"):
    ...

set_cookie("access_token", token)               # uses defaults
set_cookie("access_token", token, path="/auth") # override just one
```

That's exactly how `response.set_cookie(...)` works: many optional keyword arguments, and you pass only the ones you need.

One trap: never use a mutable default like `def f(items=[])`. The same list is shared across calls. Use `items=None` and create the list inside.

### `*args`: any number of positional arguments

```python
def total(*args):
    return sum(args)      # args is a tuple

total(1, 2, 3)            # 6
```

### `**kwargs`: any number of keyword arguments

```python
def show(**kwargs):
    print(kwargs)         # kwargs is a dict

show(httponly=True, secure=True)   # {'httponly': True, 'secure': True}
```

The names `args` and `kwargs` are only convention. The stars do the work.

### Unpacking with `*` and `**` when calling

The reverse also works: stars spread a collection into arguments.

```python
nums = [1, 2, 3]
add(*nums[:2])                   # same as add(1, 2)

COOKIE_FLAGS = {"httponly": True, "secure": True, "samesite": "lax"}
response.set_cookie("access_token", token, **COOKIE_FLAGS)
# same as:
response.set_cookie("access_token", token, httponly=True, secure=True, samesite="lax")
```

This is the `**COOKIE_FLAGS` from the project's login code. It also merges dicts: `{**a, **b}` makes a new dict with `b`'s values winning.

### Order of parameters

When mixing kinds, Python requires this order:

```python
def f(a, b=2, *args, c, d=4, **kwargs):
    ...
#   positional, defaults, *args, keyword-only, **kwargs
```

Anything after `*args` (or a bare `*`) must be passed by name.

### Functions are values

You can store a function in a variable, pass it to another function, or return it. This is what makes decorators (section 8) and `Depends(get_current_user)` possible: you pass the function itself, without calling it.

```python
def shout(text): return text.upper()
f = shout            # no () : the function itself
f("hi")              # "HI"
```

### Lambda: a tiny unnamed function

```python
square = lambda x: x * x
sorted(users, key=lambda u: u["age"])    # sort by a field
```

## 4. Control flow and errors

Python has `if`, `for` and `while` like Dart, plus `try`/`except` for errors. In FastAPI, raising an exception is the normal way to return an error response.

### if / elif / else

```python
if status == 200:
    print("ok")
elif status == 401:          # elif, not "else if"
    print("unauthorized")
else:
    print("other")

label = "adult" if age >= 18 else "minor"   # one-line version (ternary)
```

Logic words are English: `and`, `or`, `not` (not `&&`, `||`, `!`). Compare values with `==`, compare with `None` using `is`: `if token is None:`.

### for loops

```python
for run in runs:                        # each item
    print(run)

for i in range(3):                      # 0, 1, 2
    print(i)

for i, run in enumerate(runs):          # index and item
    print(i, run)

for name, path in COOKIE_PATHS.items(): # dict key and value
    print(name, path)
```

The last one is exactly the loop in the project's `_start_session`.

### while, break, continue

```python
while True:
    msg = get_message()
    if msg == "stop":
        break          # leave the loop
    if not msg:
        continue       # skip to the next round
    handle(msg)
```

The WebSocket handler uses `while True:` with `break` the same way.

### match (Python 3.10+)

```python
match status:
    case 200: print("ok")
    case 401 | 403: print("auth problem")
    case _: print("other")   # _ = default
```

### try / except: catching errors

```python
try:
    payload = jwt.decode(token, SECRET, algorithms=["HS256"])
except jwt.ExpiredSignatureError:
    print("expired")
except jwt.PyJWTError as e:        # catch a family of errors; e is the error object
    print("invalid:", e)
else:
    print("valid")                 # runs only if no error
finally:
    print("always runs")           # cleanup
```

Put the most specific `except` first. Avoid a bare `except:`; it hides real bugs.

### raise: throwing errors

```python
if not access_token:
    raise HTTPException(status_code=401, detail="Not logged in")
```

`raise` stops the function immediately, like Dart's `throw`. In FastAPI, raising `HTTPException` anywhere (in a route or a dependency) turns into an HTTP error response. You don't need to return anything.

### Converting one error into another

```python
try:
    payload = jwt.decode(token, SECRET, algorithms=["HS256"])
except jwt.PyJWTError:
    raise HTTPException(status_code=401, detail="Invalid or expired token")
```

This is the pattern in `get_current_user`: catch a library error, raise an HTTP error the client understands.

### Custom exceptions

```python
class TokenReuseError(Exception):
    pass

raise TokenReuseError("refresh token used twice")
```

An exception is just a class that inherits from `Exception` (inheritance is in section 6).

## 5. Classes, objects, `__init__` and `self`

A class is a blueprint; an object (instance) is one thing built from it. `__init__` sets up each new object, and `self` is the object itself. These three ideas are the core of OOP in Python.

### Class vs object

- Class: the blueprint, like the design of a car.
- Object / instance: one actual car built from that design. You can build many.

```python
class User:
    pass              # empty class for now

a = User()            # create an object: call the class like a function
b = User()            # a second, separate object
```

No `new` keyword. Calling the class creates the object.

### `__init__`: the initializer (constructor)

`__init__` runs automatically every time you create an object. Its job is to set up the object's starting data.

```python
class User:
    def __init__(self, name: str, role: str = "viewer"):
        self.name = name      # store the argument on this object
        self.role = role

u = User("gautam", "admin")
print(u.name)                 # gautam
print(u.role)                 # admin

v = User("surya")
print(v.role)                 # viewer (the default)
```

What happens step by step when you write `User("gautam", "admin")`:

1. Python creates a new, empty User object.
2. It calls `__init__` and passes that new object as the first argument, `self`.
3. Your arguments follow: `name="gautam"`, `role="admin"`.
4. `__init__` stores them with `self.name = name`.
5. Python returns the finished object, and it lands in `u`.

`__init__` never returns anything. Technically the object is created a moment earlier by `__new__`, so `__init__` is the initializer, but everyone calls it the constructor. You will almost never touch `__new__`.

### `self`: the object itself

`self` is the specific object the code is working on. When you call a method on `u`, `self` is `u`; on `v`, `self` is `v`.

```python
class User:
    def __init__(self, name: str):
        self.name = name

    def greet(self) -> str:
        return f"Hi, I'm {self.name}"

u = User("gautam")
u.greet()            # "Hi, I'm gautam"
User.greet(u)        # exactly the same call, written out
```

The second call shows the trick: `u.greet()` is shorthand for `User.greet(u)`. Python passes the object in as `self` for you.

Rules for `self`:

1. Every normal method's first parameter is `self`. You write it in the definition, never in the call.
2. To reach the object's data inside a method, always write `self.name`. Plain `name` would be a local variable.
3. `self` is only a naming convention, but always use it.

Dart comparison: Dart's `this` is implicit; you usually write just `name`. Python's `self` is explicit; you must write `self.name`. Forgetting `self.` is the most common beginner bug.

### Instance attributes vs class attributes

```python
class User:
    count = 0                    # class attribute: shared by ALL users

    def __init__(self, name):
        self.name = name         # instance attribute: one per user
        User.count += 1

User("a"); User("b")
print(User.count)                # 2
```

Put constants and shared config on the class. Put per-object data on `self`. Don't put a mutable list or dict as a class attribute unless you really want it shared.

### A realistic example

```python
import time

class Session:
    def __init__(self, user: str, ttl_seconds: int = 900):
        self.user = user
        self.created_at = time.time()           # computed, not passed in
        self.expires_at = self.created_at + ttl_seconds

    def is_expired(self) -> bool:
        return time.time() > self.expires_at

s = Session("gautam")
s.is_expired()     # False for the next 15 minutes
```

`__init__` can do more than copy arguments: it can compute values, like `expires_at` here. Keep it light, though; no network calls or heavy work inside it.

### Common mistakes

| Mistake | What happens | Fix |
| --- | --- | --- |
| Forgot `self` in the method definition | `TypeError: takes 0 positional arguments but 1 was given` | `def greet(self):` |
| Wrote `name` instead of `self.name` | `NameError`, or a local variable that disappears | `self.name` |
| Passed `self` when calling | Extra argument error | `u.greet()`, not `u.greet(u)` |
| Misspelled `__init__` as `__int__` or `_init_` | Arguments are rejected; the object has no data | Two underscores on each side |

## 6. Methods, inheritance and `super()`

Python has three kinds of methods (instance, class, static) plus properties. Inheritance lets one class reuse another, and `super().__init__()` runs the parent's setup.

### The three method kinds

| Kind | Decorator | First parameter | Can access | Use for |
| --- | --- | --- | --- | --- |
| Instance method | none | `self` (the object) | This object's data | Almost everything |
| Class method | `@classmethod` | `cls` (the class) | Class attributes; can create objects | Alternative constructors |
| Static method | `@staticmethod` | none | Neither | Helper that belongs with the class |

```python
class Session:
    DEFAULT_TTL = 900

    def __init__(self, user: str, ttl: int):
        self.user = user
        self.ttl = ttl

    def describe(self) -> str:                  # instance method
        return f"{self.user} for {self.ttl}s"

    @classmethod
    def short(cls, user: str) -> "Session":     # class method: another way to build one
        return cls(user, cls.DEFAULT_TTL)

    @staticmethod
    def hash_token(t: str) -> str:              # static method: no self, no cls
        import hashlib
        return hashlib.sha256(t.encode()).hexdigest()

s = Session.short("gautam")      # called on the class
s.describe()                      # "gautam for 900s"
Session.hash_token("abc")         # works without any object
```

### Alternative constructors

Python has only one `__init__` per class; there's no overloading. When you need several ways to build an object, use class methods. Dart uses named constructors like `User.fromJson(...)`; Python writes the same idea as:

```python
class User:
    def __init__(self, name: str, role: str):
        self.name = name
        self.role = role

    @classmethod
    def from_dict(cls, data: dict) -> "User":
        return cls(data["name"], data.get("role", "viewer"))

u = User.from_dict({"name": "gautam"})
```

Pydantic (FastAPI's data library) uses exactly this style: `User.model_validate(data)`.

### Properties: methods that look like attributes

```python
class Session:
    def __init__(self, expires_at: float):
        self.expires_at = expires_at

    @property
    def is_expired(self) -> bool:
        return time.time() > self.expires_at

s.is_expired        # no () : reads like a field, runs like a method
```

Same as a Dart getter.

### Private by convention

Python has no `private` keyword.

- `_name`: one underscore means "internal, don't touch from outside". Only a convention.
- `__name`: two underscores trigger name mangling, making accidental access harder. Rarely needed.

The project's `_start_session` uses one underscore: a helper meant for use inside its module.

### Inheritance

A child class gets everything from its parent and can add or change behavior.

```python
class User:
    def __init__(self, name: str):
        self.name = name

    def permissions(self) -> list[str]:
        return ["read"]

class Admin(User):                       # Admin inherits from User
    def permissions(self) -> list[str]:  # override: replace the parent's version
        return ["read", "write", "delete"]

Admin("gautam").permissions()   # ["read", "write", "delete"]
Admin("gautam").name            # "gautam" (inherited __init__)
```

### `super()`: calling the parent

When a child defines its own `__init__`, the parent's `__init__` no longer runs automatically. Call it with `super().__init__(...)`.

```python
class Admin(User):
    def __init__(self, name: str, level: int):
        super().__init__(name)     # let User set self.name
        self.level = level         # then add Admin's own data

    def permissions(self) -> list[str]:
        return super().permissions() + ["write"]   # extend, don't replace
```

Forgetting `super().__init__(name)` means `self.name` is never set, and you get `AttributeError` later. Dart does the same with `: super(name)`.

### Checking types

```python
isinstance(a, User)     # True for User and any subclass like Admin
type(a) is Admin        # exact type only
```

### Where you'll see inheritance in FastAPI

```python
from pydantic import BaseModel

class LoginIn(BaseModel):     # inherits validation, JSON parsing, and more
    username: str
    password: str
```

`LoginIn` has no `__init__`, yet `LoginIn(username="a", password="b")` works. `BaseModel` provides the constructor and reads your type-hinted fields. Custom exceptions work the same way: `class TokenReuseError(Exception)`.

## 7. Dunder methods and dataclasses

Dunder (double underscore) methods like `__init__` are hooks Python calls for you on certain actions. Dataclasses and Pydantic write the boring ones automatically.

### Common dunder methods

| Method | Python calls it when you... | Example |
| --- | --- | --- |
| `__init__(self, ...)` | Create an object | `User("a")` |
| `__str__(self)` | `print(obj)` or `str(obj)` | Friendly text |
| `__repr__(self)` | Inspect in the shell or debugger | Developer text |
| `__eq__(self, other)` | Compare with `==` | Equality by value |
| `__len__(self)` | Call `len(obj)` | Size |
| `__call__(self, ...)` | Call the object like a function: `obj()` | Callable objects |
| `__enter__` / `__exit__` | Use it in a `with` block | Section 9 |

```python
class User:
    def __init__(self, name):
        self.name = name

    def __repr__(self):
        return f"User(name={self.name!r})"

    def __eq__(self, other):
        return isinstance(other, User) and self.name == other.name

print(User("a"))               # User(name='a')
User("a") == User("a")         # True (without __eq__ it would be False)
```

Without `__eq__`, `==` checks whether both are the same object in memory, like Dart without `operator ==`.

### `__call__`: objects that act like functions

```python
class RoleChecker:
    def __init__(self, role: str):
        self.role = role

    def __call__(self, user_role: str) -> bool:
        return user_role == self.role

is_admin = RoleChecker("admin")   # __init__ runs
is_admin("admin")                  # __call__ runs -> True
```

FastAPI uses this pattern for configurable dependencies: `Depends(RoleChecker("admin"))`. The object holds the setting, and FastAPI calls it on every request.

### Dataclasses: `__init__` written for you

Writing `__init__`, `__repr__` and `__eq__` by hand gets repetitive. `@dataclass` generates them from type-hinted fields.

```python
from dataclasses import dataclass, field

@dataclass
class Session:
    user: str
    ttl: int = 900
    scopes: list[str] = field(default_factory=list)   # safe mutable default

s = Session("gautam")      # __init__ was generated
print(s)                   # Session(user='gautam', ttl=900, scopes=[])
```

Need extra setup after the generated `__init__`? Add `__post_init__(self)`; it runs right after.

### Pydantic: dataclasses plus validation

Pydantic's `BaseModel` looks like a dataclass but also validates and converts types. This is what FastAPI uses for request and response bodies.

```python
from pydantic import BaseModel

class LoginIn(BaseModel):
    username: str
    password: str
    remember: bool = False

LoginIn(username="gautam", password="pass")   # ok
LoginIn(username="gautam")                    # ValidationError: password missing
LoginIn(username="g", password="p", remember="true")   # "true" converted to True

body = LoginIn(username="g", password="p")
body.model_dump()          # {'username': 'g', 'password': 'p', 'remember': False}
```

`session.user.model_dump()` in the project's login code turns a Pydantic model into a dict so it can be sent as JSON.

|  | Plain class | `@dataclass` | Pydantic `BaseModel` |
| --- | --- | --- | --- |
| `__init__` | You write it | Generated | Generated |
| Validates types | No | No | Yes |
| Converts `"5"` to `5` | No | No | Yes |
| To dict / JSON | Manual | `asdict()` | `model_dump()` / `model_dump_json()` |
| Use for | Behavior-heavy objects | Internal data holders | API input and output |

## 8. Decorators: the `@` behind `@app.get`

A decorator is a function that takes your function and returns a changed or registered version of it. `@something` above a `def` is shorthand for `func = something(func)`.

### Step 1: functions can wrap functions

```python
def log_calls(func):
    def wrapper(*args, **kwargs):
        print(f"calling {func.__name__}")
        result = func(*args, **kwargs)    # run the original
        print("done")
        return result
    return wrapper                        # hand back the new version

def greet(name):
    return f"Hi {name}"

greet = log_calls(greet)    # replace greet with the wrapped version
greet("gautam")             # prints "calling greet", then "done"
```

`*args, **kwargs` (section 3) let the wrapper accept any arguments and pass them straight through.

### Step 2: the `@` shorthand

```python
@log_calls
def greet(name):
    return f"Hi {name}"
```

This is exactly the same as `greet = log_calls(greet)` written after the function. Nothing more.

### Step 3: decorators with arguments

`@app.get("/me")` has arguments. That means `app.get("/me")` runs first and returns the real decorator, which then receives your function.

```python
def route(path):                 # takes the argument
    def decorator(func):         # takes the function
        ROUTES[path] = func      # register it
        return func              # return it unchanged
    return decorator

ROUTES = {}

@route("/me")
def me():
    return {"user": "gautam"}

# same as: me = route("/me")(me)
ROUTES["/me"]()                  # {'user': 'gautam'}
```

### What `@app.get` really does

FastAPI's `@app.get("/me")` is a registering decorator like `route` above:

1. `app.get("/me")` creates a decorator that remembers the path and the HTTP method GET.
2. The decorator receives your function and reads its parameters and type hints.
3. It stores the path, method and function in the app's route table.
4. When a `GET /me` request arrives, FastAPI finds your function, builds its arguments from the request, and calls it.

```python
@app.get("/me")
def me(user: str = Depends(get_current_user)):
    return {"user": user}
```

The function is still yours and unchanged; FastAPI just knows about it now.

### Decorators you've already met

| Decorator | What it does |
| --- | --- |
| `@app.get`, `@app.post`, `@app.websocket` | Register a route |
| `@classmethod`, `@staticmethod` | Change how the method receives its first argument |
| `@property` | Make a method readable like an attribute |
| `@dataclass` | Generate `__init__`, `__repr__`, `__eq__` |
| `@functools.wraps(func)` | Inside your own wrappers: keep the original function's name and docstring |

Stacked decorators apply bottom-up: the one closest to `def` wraps first.

## 9. Context managers and `yield`

`with` guarantees cleanup (closing a file, a DB session) even if an error happens. `yield` pauses a function and resumes it later. FastAPI combines both for dependencies that open and close resources per request.

### `with`: automatic cleanup

```python
with open("notes.txt") as f:     # open
    data = f.read()              # use
# file is closed here, even if read() raised an error
```

The long version it replaces:

```python
f = open("notes.txt")
try:
    data = f.read()
finally:
    f.close()
```

### How `with` works: `__enter__` and `__exit__`

```python
class Timer:
    def __enter__(self):
        self.start = time.time()
        return self                      # becomes the "as" variable

    def __exit__(self, exc_type, exc, tb):
        print(f"took {time.time() - self.start:.2f}s")   # always runs

with Timer():
    do_work()
```

### `yield`: a function that pauses

`return` ends a function. `yield` hands back a value and pauses; the function continues from that point next time.

```python
def count_up():
    yield 1
    yield 2
    yield 3

for n in count_up():
    print(n)          # 1, 2, 3
```

A function containing `yield` is a generator. Useful for streaming large results without loading everything into memory.

### The shortcut: `@contextmanager`

Code before `yield` is setup, code after is cleanup:

```python
from contextlib import contextmanager

@contextmanager
def db_session():
    session = SessionLocal()   # setup
    try:
        yield session          # hand it to the with block
    finally:
        session.close()        # cleanup

with db_session() as db:
    db.query(...)
```

### In FastAPI: dependencies with `yield`

FastAPI uses the same shape without needing `@contextmanager`:

```python
def get_db():
    db = SessionLocal()
    try:
        yield db               # FastAPI passes db into the route
    finally:
        db.close()             # runs after the response is sent

@app.get("/runs")
def list_runs(db = Depends(get_db)):
    return db.query(Run).all()
```

Every request gets its own DB session, and it always closes, even if the route raises an error. The FastAPI Part 1 guide covers this in detail.

## 10. Modules, imports, venv and pip

Every `.py` file is a module, a folder of modules is a package, and a virtual environment keeps each project's installed libraries separate.

### Modules and imports

```python
# auth.py
SECRET = "change-me"
def create_token(user): ...

# main.py
import auth                          # use as auth.create_token(...)
from auth import create_token        # use as create_token(...)
from auth import create_token as ct  # rename
```

Avoid `from auth import *`; it hides where names come from.

### Packages

```
app/
  __init__.py        # marks the folder as a package (can be empty)
  main.py
  auth/
    __init__.py
    service.py
```

```python
from app.auth.service import create_token   # absolute import (preferred)
from .service import create_token           # relative: same folder
```

### `if __name__ == "__main__":`

```python
if __name__ == "__main__":
    main()
```

`__name__` is `"__main__"` only when the file is run directly (`python file.py`), not when it's imported. Code inside this block doesn't run on import.

### Virtual environments

Each project gets its own isolated set of libraries, so two projects can use different versions.

```bash
python3 -m venv .venv            # create (once per project)
source .venv/bin/activate        # activate (macOS/Linux)
.venv\Scripts\activate           # activate (Windows)
deactivate                       # leave
```

Add `.venv/` to `.gitignore`.

### pip and requirements

```bash
pip install fastapi uvicorn pyjwt          # install into the active venv
pip freeze > requirements.txt              # save exact versions
pip install -r requirements.txt            # reinstall them elsewhere
```

Comparable to `pubspec.yaml` plus `flutter pub get`. Newer tools like `uv` or Poetry do the same faster, with a `pyproject.toml` file.

### Environment variables

```python
import os
SECRET = os.getenv("SECRET", "dev-only")                  # second arg = default
ORIGINS = os.getenv("ALLOWED_ORIGINS", "").split(",")
```

`os.getenv` always returns a string (or the default). Convert yourself: `os.getenv("SECURE") == "true"`, `int(os.getenv("MAX_AGE_DAYS", "30"))`. That's how values like `SESSION_COOKIE_SECURE=true` become Python booleans.

## 11. `async` and `await`

`async def` makes a function that can pause while waiting (for a network call, a DB, a WebSocket message) so the server can handle other requests meanwhile. It works like Dart's `Future` and `await`.

### The idea

A server spends most of its time waiting: for the database, another API, or a client message. With `async`, one worker pauses a waiting request and serves others instead of sitting idle.

```python
import asyncio

async def fetch_user():         # coroutine function
    await asyncio.sleep(1)      # pause here; others can run
    return {"user": "gautam"}

async def main():
    user = await fetch_user()   # wait for the result
    print(user)

asyncio.run(main())             # start the event loop (FastAPI does this for you)
```

### Rules

1. `await` only works inside an `async def`.
2. Calling an async function without `await` returns a coroutine object, not the result. It's like a Dart `Future` you never awaited.
3. Only await things that are awaitable: async libraries such as `httpx.AsyncClient`, `asyncpg`, or `websocket.receive_text()`.
4. Never put blocking calls (`time.sleep`, `requests.get`, a sync DB driver) inside `async def`. They freeze every request on that worker. Use `await asyncio.sleep`, `httpx.AsyncClient`, or a sync route.

### Running several things at once

```python
user, runs = await asyncio.gather(fetch_user(), fetch_runs())   # both in parallel
```

Like Dart's `Future.wait`.

### async vs sync routes in FastAPI

```python
@app.get("/a")
async def a():                   # runs on the event loop
    data = await async_client.get(url)
    return data.json()

@app.get("/b")
def b():                         # FastAPI runs it in a thread pool
    return requests.get(url).json()
```

| Your code uses | Write the route as |
| --- | --- |
| Async libraries (`httpx.AsyncClient`, async DB drivers) | `async def` |
| Blocking libraries (`requests`, sync SQLAlchemy) | Plain `def` |
| No I/O at all | Either; `async def` is slightly lighter |

FastAPI handles both correctly. The only real mistake is blocking code inside `async def`. WebSocket handlers are always `async def`, which is why you saw `await websocket.accept()` in the cookie guide.

## 12. Map: where each concept shows up in FastAPI

Every line of a typical FastAPI route uses a concept from this guide. Read this block, then the table, and you can read any FastAPI code.

```python
from fastapi import FastAPI, Depends, HTTPException, Cookie   # 10 imports
from pydantic import BaseModel                                # 7 Pydantic

app = FastAPI()                                # 5 create an object; __init__ runs

class LoginIn(BaseModel):                      # 6 inheritance
    username: str                              # 1 type hints become validation
    password: str

def get_current_user(access_token: str | None = Cookie(default=None)) -> str:  # 3 defaults
    if not access_token:                       # 1 truthy/falsy
        raise HTTPException(status_code=401)   # 4 raise becomes an HTTP error
    return decode(access_token)["sub"]         # 2 dict access

@app.post("/login")                            # 8 decorator registers the route
async def login(body: LoginIn):                # 11 async; 7 body parsed into LoginIn
    return {"ok": True}                        # 2 dict becomes JSON

@app.get("/me")
def me(user: str = Depends(get_current_user)): # 3 function passed as a value
    return {"user": user}
```

| Concept | Section | Where in FastAPI |
| --- | --- | --- |
| Type hints | 1 | Path, query and body validation; docs generation |
| Truthy / falsy | 1 | `if not token:` checks |
| dict, `.get`, `.pop` | 2 | JSON bodies and responses, `request.cookies.get(...)` |
| Default and keyword arguments | 3 | `set_cookie(..., httponly=True)`, optional query params |
| `**kwargs` unpacking | 3 | `**COOKIE_FLAGS`, `Model(**data)` |
| Functions as values | 3 | `Depends(get_current_user)` |
| `raise` | 4 | `HTTPException` becomes an error response |
| Class, `__init__`, `self` | 5 | `app = FastAPI()`, services, repositories |
| Class methods | 6 | `Model.model_validate(data)` |
| Inheritance | 6 | `BaseModel`, custom exceptions, `APIRouter` |
| `__call__` | 7 | Configurable dependencies: `Depends(RoleChecker("admin"))` |
| Pydantic | 7 | Request and response models, settings |
| Decorators | 8 | `@app.get`, `@app.post`, `@app.websocket`, `@router.get` |
| `yield` dependencies | 9 | DB sessions opened and closed per request |
| Modules, venv, env vars | 10 | Project structure, settings, `.env` |
| `async` / `await` | 11 | Async routes, WebSockets, async DB and HTTP clients |

### Practice before moving to FastAPI

1. Write a `Session` class with `__init__`, an `is_expired` property and a `from_dict` class method.
2. Write a `log_calls` decorator and put it on two functions.
3. Call a function with `**{"a": 1, "b": 2}` and explain what happened.
4. Write a generator with `try` / `yield` / `finally` and watch the `finally` run.
5. Write an `async def` that awaits `asyncio.sleep(1)` twice with `asyncio.gather` and time it: about 1 second, not 2.
