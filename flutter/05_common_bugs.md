# Common Flutter Bugs - Real-World Issues

## Bug #1: Controller in StatelessWidget

### The Problem

```dart
// ❌ WRONG - Controller recreated every rebuild
class MyBottomSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();  // NEW INSTANCE!
    return TextField(controller: controller);
  }
}
```

### What Happens

```
Frame 1:
  MyBottomSheet.build() called
    ↓
  controller = TextEditingController()  // Instance #1 @ 0xABC123
    ↓
  TextField(controller: #1)

User types "A":
  TextField updates controller #1
  controller #1.text = "A"

Parent rebuilds (e.g., keyboard opens):
  MyBottomSheet.build() called AGAIN
    ↓
  controller = TextEditingController()  // Instance #2 @ 0xXYZ789
    ↓
  TextField(controller: #2)  ← NEW CONTROLLER!

  Instance #1 garbage collected
  Text "A" LOST!
```

### Memory Diagram

```
Frame 1:
  Stack:
    controller → TextEditingController@abc { text: "" }

After user types "A":
    controller → TextEditingController@abc { text: "A" }

After parent rebuild:
    controller → TextEditingController@xyz { text: "" }  ← NEW!

    @abc is now unreferenced → GC'd
```

### The Fix

```dart
// ✅ CORRECT
class MyBottomSheet extends StatefulWidget {
  @override
  State<MyBottomSheet> createState() => _MyBottomSheetState();
}

class _MyBottomSheetState extends State<MyBottomSheet> {
  late final controller = TextEditingController();  // Created ONCE

  @override
  void dispose() {
    controller.dispose();  // Clean up
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(controller: controller);  // Same instance
  }
}
```

### Memory Diagram (Fixed)

```
initState():
  State {
    controller: TextEditingController@abc { text: "" }
  }

User types "A":
  controller@abc { text: "A" }

Parent rebuild:
  build() called
  Returns TextField(controller: @abc)  ← SAME INSTANCE ✅
```

---

## Bug #2: Keyboard Opens → Everything Rebuilds

### The Problem

```dart
showModalBottomSheet(
  context: context,
  builder: (context) {
    return MyForm();  // StatelessWidget
  },
);
```

### What Happens

```
User taps TextField:
  ↓
OS shows keyboard
  ↓
Window metrics change
  ↓
platformDispatcher.onMetricsChanged()
  ↓
WidgetsBinding updates MediaQuery:
    viewInsets: EdgeInsets.zero
      → viewInsets: EdgeInsets.only(bottom: 336)  // Keyboard height
  ↓
MediaQuery widget changes
  ↓
MediaQuery.update() called
```

**Source:** `framework.dart:6045-6062`

```dart
void update(ProxyWidget newWidget) {
  final ProxyWidget oldWidget = widget as ProxyWidget;
  super.update(newWidget);
  updated(oldWidget);  // Notify dependents
  rebuild(force: true);
}
```

**Source:** `media_query.dart:1855`

```dart
bool updateShouldNotify(MediaQuery oldWidget) => data != oldWidget.data;
```

```
MediaQueryData changed? YES (viewInsets different)
  ↓
notifyClients() called
  ↓
For each dependent (widgets that called MediaQuery.of(context)):
  ↓
  didChangeDependencies()
    ↓
    markNeedsBuild()
```

### The Cascade

```dart
// Bottom sheet builder context might have MediaQuery dependency
// Even if YOUR code doesn't call MediaQuery.of(),
// widgets inside might!

showModalBottomSheet(
  builder: (context) {
    // This context depends on MediaQuery!
    return Column(
      children: [
        TextField(),  // Uses MediaQuery internally
        MyForm(),     // Stateless - controller recreated!
      ],
    );
  },
);
```

### Result

```
Keyboard opens
  → MediaQuery changes
  → builder() called again
  → MyForm() created (new widget instance)
  → MyForm.build() called
  → Controller recreated
  → TextField loses focus
  → Keyboard closes
  → Infinite loop!
```

### The Fix - Option 1: StatefulWidget

```dart
showModalBottomSheet(
  builder: (context) {
    return MyForm();  // StatefulWidget now
  },
);

class MyForm extends StatefulWidget {
  @override
  State<MyForm> createState() => _MyFormState();
}

class _MyFormState extends State<MyForm> {
  late final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return TextField(controller: _controller);
  }
}
```

### The Fix - Option 2: Break MediaQuery Dependency

```dart
showModalBottomSheet(
  builder: (context) {
    // Use MediaQuery.sizeOf instead of .of
    final size = MediaQuery.sizeOf(context);  // Only depends on size aspect
    return MyForm();
  },
);
```

**Source:** `media_query.dart:1864-1870`

```dart
bool updateShouldNotifyDependent(MediaQuery oldWidget, Set<Object> dependencies) {
  return dependencies.any((dependency) =>
    dependency is _MediaQueryAspect &&
    switch (dependency) {
      _MediaQueryAspect.size => data.size != oldWidget.data.size,
      // Only notifies if SIZE changed, not viewInsets!
    }
  );
}
```

---

## Bug #3: RepaintBoundary Misunderstanding

### The Myth

"RepaintBoundary prevents child rebuilds"

### The Reality

**RepaintBoundary affects RENDER tree, not WIDGET tree!**

```dart
// ❌ DOESN'T PREVENT REBUILDS
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
        Text('$_counter'),
        RepaintBoundary(
          child: ExpensiveWidget(),  // STILL REBUILDS!
        ),
      ],
    );
  }
}
```

### What Actually Happens

```
setState() in Parent:
  ↓
Parent.build() called:
  ↓
Returns Column(children: [
  Text('$_counter'),           // New instance
  RepaintBoundary(             // New instance
    child: ExpensiveWidget(),  // New instance
  ),
])
  ↓
updateChild() called for each:
  ↓
RepaintBoundary element:
  Widget.canUpdate? YES (same type + key)
  element.update(newWidget)
  rebuild()
    ↓
ExpensiveWidget element:
  Widget.canUpdate? YES
  element.update(newWidget)
  rebuild()  ← EXPENSIVE BUILD STILL RUNS!
```

### The Three Trees

```
Widget Tree:        Element Tree:         Render Tree:

Column              Element               RenderFlex
  ↓                   ↓                     ↓
RepaintBoundary     Element               RenderRepaintBoundary ← NEW LAYER
  ↓                   ↓                     ↓
ExpensiveWidget     Element               RenderBox
  ↓                   ↓                     ↓
build() called! ←   rebuild()             (no repaint needed)
```

**RepaintBoundary creates a layer in RENDER tree.**
**It does NOT prevent build() in WIDGET tree.**

### What RepaintBoundary Actually Does

```dart
// Without RepaintBoundary:
Parent changes color
  → markNeedsPaint() on parent
  → Walks up to root
  → ENTIRE TREE repaints
  → GPU receives full frame

// With RepaintBoundary:
Parent changes color
  → markNeedsPaint() on parent
  → Walks up to RepaintBoundary, STOPS
  → Only parent layer repaints
  → Child layer reused from cache
  → GPU composites layers (faster)
```

### The Actual Fix for Rebuilds

```dart
// ✅ PREVENT REBUILDS - Use const or cache instance
class _ParentState extends State<Parent> {
  int _counter = 0;

  // Option 1: const widget
  static const _expensiveChild = ExpensiveWidget();

  // Option 2: Cache instance
  late final _cachedChild = ExpensiveWidget();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$_counter'),       // Rebuilds
        _expensiveChild,         // NEVER rebuilds (same instance)
      ],
    );
  }
}
```

**Source:** `framework.dart:3959-3966`

```dart
if (child.widget == newWidget) {  // operator== check
  // Same instance!
  return child;  // NO rebuild, NO update, NOTHING
}
```

---

## Bug #4: Hidden MediaQuery Dependencies

### The Problem

```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextField();  // Looks innocent!
  }
}
```

**TextField internally:**

```dart
// In TextField's build():
Widget build(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);  // DEPENDENCY!
  final keyboardHeight = mediaQuery.viewInsets.bottom;
  // ...
}
```

**Now MyWidget rebuilds when keyboard opens!**

### Widgets with Hidden Dependencies

```dart
// These create MediaQuery dependencies:
TextField()          ✅ (checks viewInsets)
Scaffold()           ✅ (uses viewInsets for body)
SafeArea()           ✅ (uses viewInsets/viewPadding)
MaterialApp()        ✅ (many media query uses)

// These DON'T:
Container()          ❌
Text()               ❌
Column/Row()         ❌
```

### How to Debug

```dart
class DebugWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final element = context as Element;

    print('Dependencies:');
    if (element._dependencies != null) {
      for (final dep in element._dependencies!) {
        print('  - ${dep.widget.runtimeType}');
      }
    }

    return MyWidget();
  }
}

// Output:
// Dependencies:
//   - MediaQuery
//   - Theme
//   - Directionality
```

### The Fix

```dart
// Option 1: Use StatefulWidget with controller
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return TextField(controller: _controller);
  }
}

// Option 2: Break dependency with specific aspect
Widget build(BuildContext context) {
  // Only depend on size, not viewInsets
  final size = MediaQuery.sizeOf(context);
  return MyWidget();
}
```

---

## Bug #5: setState After dispose()

### The Problem

```dart
class _MyWidgetState extends State<MyWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(seconds: 5), () {
      setState(() {});  // Might be called after dispose!
    });
  }

  @override
  void dispose() {
    // Forgot to cancel timer!
    super.dispose();
  }
}
```

### What Happens

```
Widget mounted:
  initState() → Timer starts

Widget removed from tree:
  dispose() called
  Element._lifecycleState = defunct

5 seconds later:
  Timer fires
  setState() called
  _element!.markNeedsBuild()
    ↓
```

**Source:** `framework.dart:5247-5249`

```dart
void markNeedsBuild() {
  if (_lifecycleState != _ElementLifecycle.active) {
    return;  // ❌ Not active, skip!
  }
  // ...
}
```

**No crash, but setState() is ignored.**

### Better Error Message

If you try to access context after dispose:

```dart
void _handleTimer() {
  if (mounted) {  // Check first!
    setState(() {});
  }
}
```

**Source:** `framework.dart:973`

```dart
bool get mounted => _element != null;
```

### The Fix

```dart
class _MyWidgetState extends State<MyWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(seconds: 5), () {
      if (mounted) {  // Check if still mounted
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();  // Cancel timer!
    super.dispose();
  }
}
```

---

## Bug #6: Keys Misunderstanding

### The Problem

```dart
class Parent extends StatefulWidget {
  @override
  State<Parent> createState() => _ParentState();
}

class _ParentState extends State<Parent> {
  bool _showFirst = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_showFirst)
          Counter()  // State lost when toggled!
        else
          Counter(),
      ],
    );
  }
}
```

### What Happens

```
Frame 1: _showFirst = true
  build() returns: Counter()
  Element created: CounterElement { _state: { _count: 5 } }

Frame 2: _showFirst = false
  build() returns: Counter()
  updateChild(element, newWidget):
    Widget.canUpdate(old, new)?
      runtimeType: Counter == Counter ✅
      key: null == null ✅
    element.update(newWidget)  ← REUSES ELEMENT

Result: SAME element, _count still 5 ✅
```

**This works because same position in tree!**

### When It Breaks

```dart
Widget build(BuildContext context) {
  return Column(
    children: _showFirst
      ? [Counter(), OtherWidget()]
      : [OtherWidget(), Counter()],  // Counter moved position!
  );
}
```

```
Frame 1:
  children[0]: Counter (element@abc, _count: 5)
  children[1]: OtherWidget (element@xyz)

Frame 2:
  children[0]: OtherWidget
  children[1]: Counter

updateChild(element@abc, OtherWidget):
  Widget.canUpdate(Counter, OtherWidget)?
    runtimeType different ❌
  deactivateChild(element@abc)  ← STATE LOST!
  inflateWidget(OtherWidget)

updateChild(element@xyz, Counter):
  Widget.canUpdate(OtherWidget, Counter)?
    runtimeType different ❌
  deactivateChild(element@xyz)
  inflateWidget(Counter)  ← NEW ELEMENT, _count = 0
```

### The Fix

```dart
Widget build(BuildContext context) {
  return Column(
    children: _showFirst
      ? [
          Counter(key: Key('counter')),  // Add key!
          OtherWidget(),
        ]
      : [
          OtherWidget(),
          Counter(key: Key('counter')),
        ],
  );
}
```

**Now Flutter can track the element even when position changes!**

---

## Bug #7: Infinite Rebuild Loop

### The Problem

```dart
class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    setState(() {});  // ❌ Infinite loop!
    return Container();
  }
}
```

### What Happens

```
build() called
  → setState()
  → markNeedsBuild()
  → Frame scheduled
  → Next frame
  → build() called
  → setState()
  → ...forever
```

**App freezes, CPU at 100%!**

### Common Variations

```dart
// Variation 1: In build with controller
@override
Widget build(BuildContext context) {
  controller.addListener(() {
    setState(() {});  // Adds listener every build!
  });
  return TextField(controller: controller);
}

// Variation 2: Depending on own size
@override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      setState(() {});  // Infinite loop!
      return Container();
    },
  );
}
```

### The Fix

```dart
// Put side effects in lifecycle methods
@override
void initState() {
  super.initState();
  controller.addListener(_handleChange);  // Once!
}

void _handleChange() {
  setState(() {});  // OK here
}
```

---

## Debugging Checklist

### For controller issues:

```dart
✅ Is controller created in initState()?
✅ Is controller disposed in dispose()?
✅ Is widget StatefulWidget (not Stateless)?
```

### For rebuild issues:

```dart
✅ Print build count
✅ Check dependencies (element._dependencies)
✅ Use const widgets where possible
✅ Cache widget instances in State
```

### For MediaQuery issues:

```dart
✅ Use MediaQuery.sizeOf() instead of .of()
✅ Move MediaQuery.of() to specific widgets
✅ Use StatefulWidget for forms with TextFields
```

### For key issues:

```dart
✅ Add keys when widgets swap positions
✅ Use ValueKey for data-driven lists
✅ Use GlobalKey sparingly (expensive)
```
