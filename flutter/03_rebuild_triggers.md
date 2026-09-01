# All Ways Widgets Rebuild - Complete Guide

## Overview

A widget rebuilds when `markNeedsBuild()` is called on its element. There are multiple paths to this call.

---

## Trigger 1: setState()

### Code Path

**Source:** `framework.dart:1160-1220`

```dart
void setState(VoidCallback fn) {
  final Object? result = fn() as dynamic;
  _element!.markNeedsBuild();
}
```

### Example

```dart
class _CounterState extends State<Counter> {
  int _count = 0;

  void _increment() {
    setState(() {
      _count++;  // Modify state
    });
    // Element marked dirty, frame scheduled
  }
}
```

### Flow

```
setState()
  → markNeedsBuild()
  → _dirty = true
  → scheduleBuildFor()
  → Frame scheduled
  → build() called next frame
```

---

## Trigger 2: Parent Rebuilds with New Widget

### Code Path

**Source:** `framework.dart:3927-4020`

```dart
Element? updateChild(Element? child, Widget? newWidget, Object? newSlot) {
  if (child != null) {
    if (child.widget == newWidget) {
      return child;  // Same instance - NO rebuild
    }

    if (Widget.canUpdate(child.widget, newWidget)) {
      child.update(newWidget);  // REBUILD
      return child;
    }

    // Different type/key - destroy & recreate
    deactivateChild(child);
  }

  return inflateWidget(newWidget, newSlot);
}
```

### Example

```dart
class Parent extends StatefulWidget {
  @override
  State<Parent> createState() => _ParentState();
}

class _ParentState extends State<Parent> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$_counter'),        // New instance every rebuild
        Child(value: _counter),   // New instance every rebuild
      ],
    );
  }
}
```

### Flow

```
Parent.setState()
  → Parent.build() called
  → Returns new Child widget instance
  → updateChild(oldChildElement, newChildWidget)
  → Widget.canUpdate? YES (same type+key)
  → childElement.update(newWidget)
  → childElement.rebuild()
  → Child.build() called
```

### Widget.canUpdate

**Source:** `framework.dart:382-384`

```dart
static bool canUpdate(Widget oldWidget, Widget newWidget) {
  return oldWidget.runtimeType == newWidget.runtimeType
      && oldWidget.key == newWidget.key;
}
```

### Three Cases

```dart
// Case 1: Same instance - NO rebuild
final child = const Child();
Widget build(BuildContext context) {
  return child;  // Same instance every time
}

// Case 2: Same type+key - REBUILD
Widget build(BuildContext context) {
  return Child();  // New instance, but same type
}

// Case 3: Different type/key - DESTROY & RECREATE
Widget build(BuildContext context) {
  return condition
    ? Child(key: Key('a'))
    : Child(key: Key('b'));  // Different keys
}
```

---

## Trigger 3: InheritedWidget Changes

### How Dependencies Work

**When you call:**

```dart
final theme = Theme.of(context);
```

**What happens:**

**Source:** `framework.dart:4987-4995`

```dart
T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({Object? aspect}) {
  final InheritedElement? ancestor = _inheritedElements?[T];
  if (ancestor != null) {
    return dependOnInheritedElement(ancestor, aspect: aspect) as T;
  }
  return null;
}
```

**Source:** `framework.dart:4979-4984`

```dart
InheritedWidget dependOnInheritedElement(InheritedElement ancestor, {Object? aspect}) {
  _dependencies ??= HashSet<InheritedElement>();
  _dependencies!.add(ancestor);  // Register dependency
  ancestor.updateDependencies(this, aspect);  // Tell ancestor
  return ancestor.widget as InheritedWidget;
}
```

### Memory After Dependency

```
MediaQueryElement (InheritedElement) {
  _dependents: {
    yourElement: null,
    anotherElement: null,
  }
}

YourElement {
  _dependencies: {
    MediaQueryElement,
    ThemeElement,
  }
}
```

### When InheritedWidget Updates

**Source:** `framework.dart:6045-6062`

```dart
void update(ProxyWidget newWidget) {
  final ProxyWidget oldWidget = widget as ProxyWidget;
  super.update(newWidget);

  // Notify dependents
  updated(oldWidget);
  rebuild(force: true);
}

void updated(covariant ProxyWidget oldWidget) {
  notifyClients(oldWidget);
}
```

**Source:** `framework.dart:6319-6334`

```dart
void notifyClients(InheritedWidget oldWidget) {
  for (final Element dependent in _dependents.keys) {
    notifyDependent(oldWidget, dependent);
  }
}
```

**Source:** `framework.dart:6277-6279`

```dart
void notifyDependent(covariant InheritedWidget oldWidget, Element dependent) {
  dependent.didChangeDependencies();
}
```

**Source:** `framework.dart:5096-5100`

```dart
void didChangeDependencies() {
  markNeedsBuild();  // Mark dirty!
}
```

### Complete Flow

```
MediaQuery widget changes (keyboard opens)
  ↓
MediaQueryElement.update(newWidget)
  ↓
notifyClients(oldWidget)
  ↓
for each dependent:
  ↓
  dependent.didChangeDependencies()
    ↓
    markNeedsBuild()
      ↓
      Rebuild scheduled
```

### Example

```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Creates dependency on MediaQuery
    final size = MediaQuery.of(context).size;

    return Container(
      width: size.width * 0.5,
      child: Text('Half screen'),
    );
  }
}

// When screen rotates:
// 1. MediaQuery gets new size
// 2. notifyClients() called
// 3. MyWidget.didChangeDependencies()
// 4. MyWidget.build() called again
```

### Common InheritedWidgets

- `Theme.of(context)` ✅
- `MediaQuery.of(context)` ✅
- `Navigator.of(context)` ✅
- `Localizations.of(context)` ✅
- `Provider.of<T>(context)` ✅
- Custom InheritedWidget ✅

### updateShouldNotify

**Source:** `media_query.dart:1855`

```dart
bool updateShouldNotify(MediaQuery oldWidget) => data != oldWidget.data;
```

**Only notifies if data actually changed.**

```dart
// MediaQuery before: viewInsets = EdgeInsets.zero
// MediaQuery after:  viewInsets = EdgeInsets.only(bottom: 336)
// data != oldWidget.data → true
// notifyClients() called
```

---

## Trigger 4: Controllers & Listenables

### How Controllers Work

**Source:** `change_notifier.dart:137-150`

```dart
mixin class ChangeNotifier implements Listenable {
  List<VoidCallback?> _listeners = [];

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void notifyListeners() {
    for (int i = 0; i < _listeners.length; i++) {
      _listeners[i]?.call();  // Call each listener
    }
  }
}
```

### ValueListenableBuilder

**Source:** `value_listenable_builder.dart:109-145`

```dart
class _ValueListenableBuilderState<T> extends State<ValueListenableBuilder<T>> {
  late T value;

  @override
  void initState() {
    super.initState();
    value = widget.valueListenable.value;
    widget.valueListenable.addListener(_valueChanged);  // Register listener
  }

  void _valueChanged() {
    setState(() {  // Trigger rebuild!
      value = widget.valueListenable.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, value, widget.child);
  }
}
```

### Flow

```
controller.value = newValue
  ↓
controller.notifyListeners()
  ↓
for each listener:
  ↓
  listener()  // _valueChanged()
    ↓
    setState(() {})
      ↓
      Normal rebuild flow
```

### Example

```dart
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Manual listener
    _controller.addListener(() {
      setState(() {});  // Rebuild when text changes
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(_controller.text);  // Shows current text
  }
}
```

### Common Controllers

- `TextEditingController` ✅
- `AnimationController` ✅
- `ScrollController` ✅
- `TabController` ✅
- Custom `ChangeNotifier` ✅

---

## Trigger 5: LayoutBuilder - Constraints Change

### Code Path

**Source:** `layout_builder.dart:109-200`

```dart
class _LayoutBuilderElement<LayoutInfoType> extends RenderObjectElement {
  @override
  void markNeedsBuild() {
    // Schedule layout callback, not normal build
    renderObject.scheduleLayoutCallback();
    _needsBuild = true;
  }
}
```

### When It Rebuilds

```dart
// In RenderObject.performLayout():
if (constraints != _previousConstraints) {
  invokeLayoutCallback((constraints) {
    _rebuildWithConstraints(constraints);
  });
}
```

### Example

```dart
LayoutBuilder(
  builder: (context, constraints) {
    print('Constraints: $constraints');

    if (constraints.maxWidth > 600) {
      return WideLayout();
    }
    return NarrowLayout();
  },
)

// Only rebuilds when:
// 1. Constraints change (parent size changes)
// 2. NOT when parent just rebuilds with same size
```

### Flow

```
Parent layout changes
  ↓
Parent calls child.layout(newConstraints)
  ↓
if (constraints != _previousConstraints)
  ↓
  invokeLayoutCallback()
    ↓
    _rebuildWithConstraints()
      ↓
      builder(context, constraints) called
```

---

## Trigger 6: StreamBuilder / FutureBuilder

### StreamBuilder

**Source:** Built-in widget that listens to streams

```dart
class _StreamBuilderBaseState<T, S> extends State<StreamBuilderBase<T, S>> {
  StreamSubscription<T>? _subscription;
  S _summary = widget.initial;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _subscription = widget.stream?.listen((T data) {
      setState(() {  // Rebuild on stream event
        _summary = widget.afterData(_summary, data);
      });
    });
  }
}
```

### Example

```dart
StreamBuilder<int>(
  stream: myStream,
  builder: (context, snapshot) {
    return Text('Value: ${snapshot.data}');
  },
)

// Flow:
// myStream.add(5)
//   → listener called
//   → setState()
//   → builder() called with new snapshot
```

---

## Trigger 7: Hot Reload (Debug Only)

### Code Path

```dart
void reassemble(Element root) {
  root.reassemble();  // Recursively marks all dirty
}

void reassemble() {
  markNeedsBuild();  // This element
  visitChildren((Element child) {
    child.reassemble();  // All children
  });
}
```

### Flow

```
You save file in IDE
  ↓
Flutter CLI detects change
  ↓
Sends reassemble command
  ↓
BuildOwner.reassemble()
  ↓
ALL elements marked dirty
  ↓
ALL widgets rebuild
```

---

## Trigger 8: Element.activate() with GlobalKey

### Code Path

```dart
void activate() {
  _lifecycleState = _ElementLifecycle.active;
  _dirty = true;  // Mark dirty on activation
  // ...
}
```

### Example

```dart
GlobalKey key = GlobalKey();

// Widget moves in tree:
if (condition) {
  Container(key: key, child: MyWidget());
} else {
  Positioned(
    child: Container(key: key, child: MyWidget()),
  );
}

// When condition changes:
// 1. Element deactivated from old location
// 2. Element reactivated in new location
// 3. activate() sets _dirty = true
// 4. Rebuild triggered
```

---

## The ONLY Ways to Mark Dirty

At the core, only 3 functions set `_dirty = true`:

```dart
// 1. markNeedsBuild() - Called by everything
void markNeedsBuild() {
  _dirty = true;
  owner!.scheduleBuildFor(this);
}

// 2. Element constructor - Initial state
Element(Widget widget) : _widget = widget {
  _dirty = true;  // Starts dirty
}

// 3. activate() - When element reused
void activate() {
  _dirty = true;
}
```

**Everything else is a path to calling markNeedsBuild()!**

---

## Summary Table

| Trigger | Direct Cause | Code Path |
|---------|-------------|-----------|
| `setState()` | User code | `setState()` → `markNeedsBuild()` |
| Parent rebuild | New widget instance | `updateChild()` → `update()` → `rebuild()` |
| InheritedWidget | Dependency change | `notifyClients()` → `didChangeDependencies()` |
| Controllers | Listener callback | `notifyListeners()` → `listener()` → `setState()` |
| LayoutBuilder | Constraints change | `performLayout()` → callback → rebuild |
| StreamBuilder | Stream event | `listen()` → `setState()` |
| Hot reload | Dev tool | `reassemble()` → `markNeedsBuild()` |
| GlobalKey move | Element reactivated | `activate()` → `_dirty = true` |

---

## Decision Tree: Will My Widget Rebuild?

```
1. Did I call setState()?
   └─ YES → ✅ REBUILDS

2. Did parent's build() return new widget instance?
   ├─ NO (const or same instance) → ❌ NO REBUILD
   ├─ YES, but different type/key → ❌ DESTROYED & RECREATED
   └─ YES, same type+key → ✅ REBUILDS

3. Did I call MediaQuery.of() / Theme.of() etc?
   ├─ YES, and that InheritedWidget changed → ✅ REBUILDS
   └─ NO dependency → ❌ NO REBUILD

4. Am I wrapped in ValueListenableBuilder?
   ├─ YES, and listenable changed → ✅ REBUILDS
   └─ NO → ❌ NO REBUILD

5. Am I a LayoutBuilder and constraints changed?
   └─ YES → ✅ REBUILDS

6. Otherwise → ❌ NO REBUILD
```

---

## Debugging Rebuilds

### Track all rebuild triggers

```dart
class DebugElement extends StatefulElement {
  @override
  void markNeedsBuild() {
    print('markNeedsBuild: ${StackTrace.current}');
    super.markNeedsBuild();
  }

  @override
  void didChangeDependencies() {
    print('didChangeDependencies called');
    super.didChangeDependencies();
  }

  @override
  void update(Widget newWidget) {
    print('update: old=${widget.runtimeType}, new=${newWidget.runtimeType}');
    super.update(newWidget);
  }
}
```

### Print dependencies

```dart
@override
Widget build(BuildContext context) {
  final element = context as Element;
  if (element._dependencies != null) {
    print('Dependencies:');
    for (final dep in element._dependencies!) {
      print('  - ${dep.widget.runtimeType}');
    }
  }
  return MyWidget();
}
```

### Count rebuilds

```dart
class _MyWidgetState extends State<MyWidget> {
  static int _buildCount = 0;

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    print('Build #$_buildCount');
    return Container();
  }
}
```

---

## Common Mistakes

### Mistake 1: Expecting rebuild without dependency

```dart
// ❌ WRONG
Widget build(BuildContext context) {
  // Reads MediaQuery but doesn't create dependency
  final element = context.getElementForInheritedWidgetOfExactType<MediaQuery>();
  final size = element?.widget.data.size;
  return Container(width: size?.width);
}

// ✅ CORRECT
Widget build(BuildContext context) {
  // Creates dependency
  final size = MediaQuery.of(context).size;
  return Container(width: size.width);
}
```

### Mistake 2: Controller without listener

```dart
// ❌ WRONG
final controller = TextEditingController();

Widget build(BuildContext context) {
  return Text(controller.text);  // Won't update!
}

// ✅ CORRECT
final controller = TextEditingController();

@override
void initState() {
  super.initState();
  controller.addListener(() {
    setState(() {});
  });
}

// OR use ValueListenableBuilder
```

### Mistake 3: Assuming RepaintBoundary prevents rebuilds

```dart
// ❌ WRONG ASSUMPTION
RepaintBoundary(
  child: ExpensiveWidget(),  // Still rebuilds!
)

// RepaintBoundary only affects PAINT, not BUILD

// ✅ TO PREVENT REBUILDS
final expensiveChild = const ExpensiveWidget();

Widget build(BuildContext context) {
  return expensiveChild;  // Same instance
}
```
