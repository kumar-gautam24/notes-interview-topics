# OOP Concepts — Complete Session Summary

---

## 1. Five Class Relationships

### IS-A (`extends`)
- Specialized version of parent
- Gets parent's code for free, override what you want
- **Test:** Can you substitute child for parent everywhere?
- `Dog extends Animal` — anywhere you need an Animal, Dog works

### CAN-DO (`with` / mixin)
- Shared capability, no identity
- Exists because of the **Diamond Problem** — two parents with same method = compiler can't decide
- Dart allows only one `extends`, mixins solve the multi-behavior need
- Linear order resolves conflicts: `with A, B, C` → C wins over B wins over A
- Example: `SingleTickerProviderStateMixin` — a capability, not an identity

### IMPLEMENTS (pure contract)
- "I promise to have this shape"
- **Zero inherited code** — you rewrite everything, even if parent has working methods
- **Decision:** `extends` = I want your code. `implements` = I just want your shape.

### HAS-A: Composition (owns it)
- Parent **creates** the child internally
- Parent dies → child dies
- `final Engine engine = Engine();` — Car creates engine, scrapped together

### HAS-A: Aggregation (borrows it)
- Child is **passed in** from outside
- Parent dies → child lives on
- `Team(this.players)` — players exist independently
- **Dependency Injection is just aggregation with a fancy name**

---

## 2. Abstract Classes vs Interfaces

| | Abstract Class | Interface (`implements`) |
|---|---|---|
| **What it is** | Partial implementation + contract | Pure contract |
| **Can have working methods?** | Yes | Doesn't matter — you rewrite everything |
| **Can be instantiated?** | No — abstract methods have no body, nothing to execute | N/A |
| **When to use** | Share common code + force some methods | Force a shape, no shared code |

**Key correction:** Abstract class ≠ "just a contract." It CAN have fully implemented methods. Only methods without a body must be overridden.

---

## 3. `super()` vs `super.method()`

### `super()` in constructor — birth order
```dart
Dog(String name, this.breed) : super(name);
// "Parent, initialize yourself first, then I'll set up my stuff"
```

### `super.method()` inside a method — calling parent's version
```dart
@override
void initState() {
  super.initState(); // framework does its bookkeeping
  // then your setup code
}
```

**Different moments in an object's life.** One is construction, other is execution.

---

## 4. Four OOP Pillars

### Polymorphism
- Same method, different behavior depending on implementation
- **Runtime (overriding):** parent says `speak()`, Dog barks, Cat meows — decided at runtime based on actual object
- **Compile time (overloading):** same method name, different parameters — compiler picks at compile time. Dart doesn't really support this.

### Encapsulation
- Isolate fields and methods, only expose what's needed
- Not just "make things private" — it's about controlling access to internals

### Abstraction
- Hide complexity, expose simple interface
- Abstract classes, interfaces — caller doesn't need to know internals

### Inheritance
- IS-A relationship, code reuse through parent-child hierarchy

---

## 5. SOLID Principles

### S — Single Responsibility
One class, one reason to change.

### O — Open/Closed
Open to extension, closed to modification. Add new behavior by adding new classes, not editing existing ones.

### L — Liskov Substitution
Child should be assignable to parent everywhere. The IS-A test.

### I — Interface Segregation
Don't force a class to implement methods it doesn't need. Many small interfaces > one fat interface.

### D — Dependency Inversion
High-level modules depend on **abstractions**, not concrete classes.
- **Inversion** = the design decision (code against abstract `DatabaseClient`, not concrete `PostgresClient`)
- **Injection** = the delivery method (pass it via constructor)
- These are related but different things

---

## 6. Design Patterns Covered

### Singleton
Single instance throughout the app. Global managers, shared state.

### Factory
"Tell me WHAT you want, I'll decide WHICH class to build."
- Caller doesn't know which concrete class is returned
- `factory` keyword in Dart: runs logic first, then returns instance
- `fromJson` — takes raw material, figures out how to build the object

### Observer
"When I change, notify everyone watching me."
- `setState()` → marks dirty → framework rebuilds
- `StreamBuilder` → stream emits → builder rebuilds
- `ChangeNotifier` → `notifyListeners()` → UI rebuilds
- All the same pattern: **data changes → notify → react**

### Repository
Hides where data comes from. UI calls `repository.getBooks()` — doesn't know if it's cache, API, or local DB.

---

## 7. Generics

### Core idea
`T` is a variable for types. Write once, works with any type.

### Constraints
```dart
class MathBox<T extends num> { }
// T must be a subtype of num — compiler knows T has number operations
```

### Reified Generics (Dart advantage)
Dart keeps type info at runtime. `is Box<String>` check works. Java erases types at runtime.

### Generic method
```dart
T fold<T>(...) // T is scoped to this method, not the class
```

---

## 8. Either<L, R> — Full Implementation

```dart
abstract class Either<L, R> {
  T fold<T>(T Function(L) onLeft, T Function(R) onRight);
}

class Left<L, R> extends Either<L, R> {
  final L value;
  Left(this.value);
  @override
  T fold<T>(T Function(L) onLeft, T Function(R) onRight) => onLeft(value);
}

class Right<L, R> extends Either<L, R> {
  final R value;
  Right(this.value);
  @override
  T fold<T>(T Function(L) onLeft, T Function(R) onRight) => onRight(value);
}
```

- **Left = failure, Right = success** ("Right" = "correct")
- `fold` forces handling both cases — compiler won't let you ignore one
- Each subclass's `fold` calls the correct function — **that's polymorphism**

---

## 9. UseCase Pattern — Full Chain

```
Repository creates Either → UseCase passes it through → UI folds it
```

### Abstract UseCase
```dart
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}
```

### Concrete UseCase
```dart
class GetUser extends UseCase<User, int> {
  final UserRepository repository;
  GetUser(this.repository); // aggregation — passed in

  @override
  Future<Either<Failure, User>> call(int userId) {
    return repository.getUserById(userId);
  }
}
```

### NoParams (dummy class for no-input UseCases)
```dart
class NoParams {}
class GetAllBooks extends UseCase<List<Book>, NoParams> { ... }
```

### Repository — where Either is born
```dart
Future<Either<Failure, User>> getUserById(int id) async {
  try {
    final user = await api.fetchUser(id);
    return Right(user);
  } catch (e) {
    return Left(Failure(e.toString()));
  }
}
```

**try/catch lives in ONE place (repository). Everything above uses fold.**

### Concepts inside UseCase pattern
1. **IS-A** — GetUser extends UseCase
2. **Generics** — `<User, int>`, `<Failure, User>`
3. **Abstract class** — UseCase is abstract, forces `call()` implementation
4. **Aggregation** — repository passed via constructor
5. **Dependency Inversion** — depends on `UserRepository` abstraction, not concrete impl
6. **Polymorphism** — `fold` calls correct override (Left or Right)
7. **Either** — error handling without exceptions flowing up

---

## 10. Future & Stream Mental Model

### Future
A **box** that's empty now, will contain a value later. `await` = wait for the box to fill. `Future<String>` and `String` are different types — one is the box, other is the contents.

### Stream
A **conveyor belt** of boxes. They keep coming until the belt stops.
