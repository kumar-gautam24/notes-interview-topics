# Flutter Rebuild Mechanism - Complete Code Flow

## Overview

When you call `setState()`, a chain reaction occurs that ends with your `build()` method being called again. Let's trace the **exact code path**.

---

## Step 1: setState() Called

**Source:** `framework.dart:1160-1220`

```dart
@protected
void setState(VoidCallback fn) {
  // Line 1199: Execute your callback
  final Object? result = fn() as dynamic;

  // Line 1219: Mark element as needing rebuild
  _element!.markNeedsBuild();
}
```

**Example:**

```dart
class _CounterState extends State<Counter> {
  int _count = 0;

  void _increment() {
    setState(() {
      _count++;  // This runs first (line 1199)
    });
    // Then markNeedsBuild() is called (line 1219)
  }
}
```

---

## Step 2: markNeedsBuild()

**Source:** `framework.dart:5245-5297`

```dart
void markNeedsBuild() {
  // Line 5247: Check if element is active
  if (_lifecycleState != _ElementLifecycle.active) {
    return;  // Not mounted, bail out
  }

  // Line 5292: Already dirty? Skip
  if (dirty) {
    return;
  }

  // Line 5295: Set dirty flag
  _dirty = true;

  // Line 5296: Schedule build
  owner!.scheduleBuildFor(this);
}
```

**State after execution:**

```
Element {
  _dirty: true,           ← Flag set
  _inDirtyList: false,    ← Not yet in list
  _lifecycleState: active
}
```

---

## Step 3: scheduleBuildFor()

**Source:** `framework.dart:2881-2941`

```dart
void scheduleBuildFor(Element element) {
  // Line 2908: Get element's build scope
  final BuildScope buildScope = element.buildScope;

  // Line 2930: First element marked dirty?
  if (!_scheduledFlushDirtyElements && onBuildScheduled != null) {
    _scheduledFlushDirtyElements = true;
    onBuildScheduled!();  // Line 2932: CALLBACK TO BINDING
  }

  // Line 2934: Add to dirty list
  buildScope._scheduleBuildFor(element);
}
```

### _scheduleBuildFor Implementation

**Source:** `framework.dart:2661-2674`

```dart
void _scheduleBuildFor(Element element) {
  // Line 2663: Not in list yet?
  if (!element._inDirtyList) {
    _dirtyElements.add(element);  // Add to dirty list
    element._inDirtyList = true;  // Mark as added
  }

  // Line 2667: Schedule rebuild if needed
  if (!_buildScheduled && !_building) {
    _buildScheduled = true;
    scheduleRebuild?.call();  // Trigger frame
  }
}
```

**State after execution:**

```
BuildScope {
  _dirtyElements: [elem1, elem2, yourElement],  ← Added here
  _buildScheduled: true,
  _building: false
}

Element {
  _dirty: true,
  _inDirtyList: true  ← Now in list
}
```

---

## Step 4: Frame Scheduling

### onBuildScheduled Callback

**Source:** `binding.dart:452-453`

```dart
void initInstances() {
  _buildOwner = BuildOwner();
  buildOwner!.onBuildScheduled = _handleBuildScheduled;  // Function pointer
}
```

**Source:** `binding.dart:1118-1147`

```dart
void _handleBuildScheduled() {
  // Line 1147: Request frame from scheduler
  ensureVisualUpdate();
}
```

### ensureVisualUpdate

**Source:** `scheduler/binding.dart:908-919`

```dart
void ensureVisualUpdate() {
  switch (schedulerPhase) {
    case SchedulerPhase.idle:
    case SchedulerPhase.postFrameCallbacks:
      scheduleFrame();  // Request frame
      return;
    case SchedulerPhase.transientCallbacks:
    case SchedulerPhase.midFrameMicrotasks:
    case SchedulerPhase.persistentCallbacks:
      return;  // Already in frame, will process later
  }
}
```

### scheduleFrame

**Source:** `scheduler/binding.dart:948-961`

```dart
void scheduleFrame() {
  if (_hasScheduledFrame || !framesEnabled) {
    return;
  }

  // Line 958: Register callbacks
  ensureFrameCallbacksRegistered();

  // Line 959: Tell native engine!
  platformDispatcher.scheduleFrame();

  _hasScheduledFrame = true;
}
```

**Source:** `scheduler/binding.dart:890-893`

```dart
void ensureFrameCallbacksRegistered() {
  // Register callback for VSYNC BEGIN
  platformDispatcher.onBeginFrame ??= _handleBeginFrame;

  // Register callback for VSYNC DRAW
  platformDispatcher.onDrawFrame ??= _handleDrawFrame;
}
```

**At this point:**
- `_dirty = true`
- Element in `_dirtyElements` list
- Native engine callback registered
- **Waiting for VSYNC signal...**

---

## Step 5: VSYNC Arrives - Frame Callbacks

### handleBeginFrame (Animation Phase)

**Source:** `scheduler/binding.dart:1228-1276`

```dart
void handleBeginFrame(Duration? rawTimeStamp) {
  _hasScheduledFrame = false;

  // Line 1260: Set phase
  _schedulerPhase = SchedulerPhase.transientCallbacks;

  // Line 1261: Run animation callbacks
  final Map<int, _FrameCallbackEntry> callbacks = _transientCallbacks;
  _transientCallbacks = <int, _FrameCallbackEntry>{};
  callbacks.forEach((int id, _FrameCallbackEntry callbackEntry) {
    _invokeFrameCallback(callbackEntry.callback, _currentFrameTimeStamp!);
  });

  // Line 1274: Move to next phase
  _schedulerPhase = SchedulerPhase.midFrameMicrotasks;
}
```

**No rebuilding yet!** This just runs animations.

### handleDrawFrame (Build/Layout/Paint Phase)

**Source:** `scheduler/binding.dart:1340-1380`

```dart
void handleDrawFrame() {
  // Line 1345: Set phase
  _schedulerPhase = SchedulerPhase.persistentCallbacks;

  // Line 1346: Run persistent callbacks
  for (final FrameCallback callback in List<FrameCallback>.of(_persistentCallbacks)) {
    _invokeFrameCallback(callback, _currentFrameTimeStamp!);
  }

  // Line 1351: Post-frame callbacks
  _schedulerPhase = SchedulerPhase.postFrameCallbacks;
  // ...

  // Line 1369: Done
  _schedulerPhase = SchedulerPhase.idle;
}
```

---

## Step 6: WidgetsBinding.drawFrame

**Source:** `binding.dart:1224-1285`

```dart
@override
void drawFrame() {
  try {
    if (rootElement != null) {
      // Line 1259: REBUILD DIRTY ELEMENTS!
      buildOwner!.buildScope(rootElement!);
    }

    // Line 1261: Paint and composite
    super.drawFrame();

    // Line 1266: Finalize
    buildOwner!.finalizeTree();
  }
}
```

---

## Step 7: buildScope

**Source:** `framework.dart:3001-3065`

```dart
void buildScope(Element context, [VoidCallback? callback]) {
  final BuildScope buildScope = context.buildScope;

  // Line 3003: Nothing to do?
  if (callback == null && buildScope._dirtyElements.isEmpty) {
    return;
  }

  try {
    _scheduledFlushDirtyElements = true;
    buildScope._building = true;

    // Line 3054: REBUILD ALL DIRTY ELEMENTS
    buildScope._flushDirtyElements(debugBuildRoot: context);
  } finally {
    _scheduledFlushDirtyElements = false;
    buildScope._building = false;
  }
}
```

---

## Step 8: _flushDirtyElements - The Rebuild Loop

**Source:** `framework.dart:2743-2789`

```dart
void _flushDirtyElements({required Element debugBuildRoot}) {
  // Line 2745: Sort by depth (parent before child)
  _dirtyElements.sort(Element._sort);
  _dirtyElementsNeedsResorting = false;

  try {
    // Line 2748: THE LOOP - process each dirty element
    for (int index = 0; index < _dirtyElements.length;
         index = _dirtyElementIndexAfter(index)) {
      final Element element = _dirtyElements[index];

      if (identical(element.buildScope, this)) {
        // Line 2752: Rebuild this element
        _tryRebuild(element);
      }
    }
  } finally {
    // Line 2780: Clear dirty flags
    for (final Element element in _dirtyElements) {
      if (identical(element.buildScope, this)) {
        element._inDirtyList = false;
      }
    }

    // Line 2785: Clear the list
    _dirtyElements.clear();
    _dirtyElementsNeedsResorting = null;
    _buildScheduled = false;
  }
}
```

**_tryRebuild just calls `element.rebuild()`**

---

## Step 9: rebuild()

**Source:** `framework.dart:5409-5445`

```dart
@mustCallSuper
void rebuild({bool force = false}) {
  // Line 5411: Check if should rebuild
  if (_lifecycleState != _ElementLifecycle.active || (!_dirty && !force)) {
    return;
  }

  try {
    // Line 5435: Call the subclass method
    performRebuild();
  } finally {
    // Cleanup
  }

  // Line 5444: No longer dirty
  assert(!_dirty);
}
```

---

## Step 10: performRebuild() - StatefulElement

**Source:** `framework.dart:5879-5885`

```dart
@override
void performRebuild() {
  // Line 5880: Dependencies changed?
  if (_didChangeDependencies) {
    state.didChangeDependencies();
    _didChangeDependencies = false;
  }

  // Call parent (ComponentElement)
  super.performRebuild();
}
```

### ComponentElement.performRebuild

**Source:** `framework.dart:5716-5748`

```dart
@override
void performRebuild() {
  Widget? built;

  try {
    // Line 5723: CALL BUILD - YOUR CODE RUNS HERE!
    built = build();
  } catch (e, stack) {
    // Error handling
  }

  // Line 5744: Clear dirty flag
  super.performRebuild();

  // Line 5747: Reconcile children
  _child = updateChild(_child, built, slot);
}
```

### StatefulElement.build

**Source:** `framework.dart:5833`

```dart
@override
Widget build() => state.build(this);  // Call YOUR State.build()
```

**YOUR CODE FINALLY RUNS:**

```dart
@override
Widget build(BuildContext context) {
  return Text('Count: $_count');  // ← THIS EXECUTES
}
```

---

## Step 11: updateChild() - Tree Reconciliation

**Source:** `framework.dart:3927-4020`

```dart
Element? updateChild(Element? child, Widget? newWidget, Object? newSlot) {
  // Line 3928: No new widget?
  if (newWidget == null) {
    if (child != null) {
      deactivateChild(child);
    }
    return null;
  }

  final Element newChild;

  // Line 3936: Child exists?
  if (child != null) {
    // Line 3959: Same instance? (operator==)
    if (hasSameSuperclass && child.widget == newWidget) {
      if (child.slot != newSlot) {
        updateSlotForChild(child, newSlot);
      }
      newChild = child;  // REUSE - no rebuild!
    }
    // Line 3967: Can update? (same type + key)
    else if (hasSameSuperclass && Widget.canUpdate(child.widget, newWidget)) {
      if (child.slot != newSlot) {
        updateSlotForChild(child, newSlot);
      }
      // Line 3982: UPDATE existing element
      child.update(newWidget);
      newChild = child;  // REUSE element, new widget
    }
    // Line 3992: Can't update
    else {
      deactivateChild(child);
      newChild = inflateWidget(newWidget, newSlot);  // CREATE NEW
    }
  }
  // Line 4000: No child
  else {
    newChild = inflateWidget(newWidget, newSlot);
  }

  return newChild;
}
```

---

## Complete Call Stack

```
User Action
  ↓
setState(() { _count++; })                         framework.dart:1199
  ↓
_element!.markNeedsBuild()                         framework.dart:1219
  ↓
markNeedsBuild()                                   framework.dart:5245
  ├─ _dirty = true                                 framework.dart:5295
  └─ owner!.scheduleBuildFor(this)                framework.dart:5296
      ↓
scheduleBuildFor(element)                          framework.dart:2881
  ├─ onBuildScheduled!()                          framework.dart:2932
  └─ _scheduleBuildFor(element)                   framework.dart:2934
      ↓
_scheduleBuildFor(element)                         framework.dart:2661
  ├─ _dirtyElements.add(element)                  framework.dart:2664
  ├─ element._inDirtyList = true                  framework.dart:2665
  └─ scheduleRebuild?.call()                      framework.dart:2669
      ↓
_handleBuildScheduled()                            binding.dart:1118
  ↓
ensureVisualUpdate()                               scheduler.dart:908
  ↓
scheduleFrame()                                    scheduler.dart:948
  ├─ ensureFrameCallbacksRegistered()             scheduler.dart:958
  └─ platformDispatcher.scheduleFrame()           scheduler.dart:959

═══════════════════════════════════════════════════════════
        WAITING FOR VSYNC FROM OS...
═══════════════════════════════════════════════════════════

VSYNC signal arrives!
  ↓
platformDispatcher.onBeginFrame()
  ↓
_handleBeginFrame()                                scheduler.dart:1170
  ↓
handleBeginFrame()                                 scheduler.dart:1228
  └─ Run animation callbacks                       scheduler.dart:1261
  ↓
platformDispatcher.onDrawFrame()
  ↓
_handleDrawFrame()                                 scheduler.dart:1182
  ↓
handleDrawFrame()                                  scheduler.dart:1340
  ↓
WidgetsBinding.drawFrame()                         binding.dart:1224
  ↓
buildOwner!.buildScope(rootElement!)              binding.dart:1259
  ↓
buildScope(context)                                framework.dart:3001
  ↓
_flushDirtyElements()                             framework.dart:2743
  ├─ _dirtyElements.sort()                        framework.dart:2745
  └─ for each element:                            framework.dart:2748
      ↓
      _tryRebuild(element)
        ↓
        element.rebuild()                          framework.dart:5409
          ↓
          performRebuild()                         framework.dart:5879
            ↓
            ComponentElement.performRebuild()      framework.dart:5716
              ├─ built = build()                   framework.dart:5723
              │   └─ state.build(this)            framework.dart:5833
              │       └─ YOUR BUILD METHOD ← HERE
              └─ updateChild(_child, built)       framework.dart:5747
                  ↓
                  updateChild()                    framework.dart:3927
                    ├─ Widget.canUpdate?
                    ├─ child.update() if can update
                    └─ inflateWidget() if new
```

---

## How Flutter Knows When to Build - NO MAGIC

### The Question

**"I marked dirty, but how does Flutter KNOW it's time to build?"**

### The Answer: Function Pointers (Callbacks)

Flutter uses **function pointers** (callbacks) - just like C++ callbacks. No magic, no polling.

---

## The Callback Chain - Core Mechanism

### Step 1: Setup During App Initialization

**Source:** `binding.dart:315-330`

```dart
@override
void initInstances() {
  super.initInstances();

  // CREATE BUILD OWNER
  _buildOwner = BuildOwner();

  // Line 324: SET CALLBACK - FUNCTION POINTER!
  buildOwner!.onBuildScheduled = _handleBuildScheduled;

  // This is like C++:
  // buildOwner->onBuildScheduled = &WidgetsBinding::_handleBuildScheduled;
}
```

**Memory state after init:**

```
WidgetsBinding {
  _buildOwner: BuildOwner@0x1234 {
    onBuildScheduled: → WidgetsBinding._handleBuildScheduled  ← FUNCTION POINTER
    _dirtyElements: [],
    _buildScheduled: false
  }
}
```

### Step 2: When setState() Marks Dirty

**Source:** `framework.dart:2661-2674`

```dart
void _scheduleBuildFor(Element element) {
  // Add to dirty list
  if (!element._inDirtyList) {
    _dirtyElements.add(element);
    element._inDirtyList = true;
  }

  // Line 2669: CHECK - first dirty element?
  if (!_buildScheduled && !_building) {
    _buildScheduled = true;

    // Line 2671: CALL THE FUNCTION POINTER!
    scheduleRebuild?.call();
    //             ^^^^^^^^^ This is the callback
  }
}
```

**What is `scheduleRebuild`?**

**Source:** `framework.dart:2602-2604`

```dart
class BuildScope {
  // Function pointer to trigger frame
  VoidCallback? scheduleRebuild;
}
```

**Who sets it?**

**Source:** `framework.dart:2896-2900`

```dart
void scheduleBuildFor(Element element) {
  final BuildScope buildScope = element.buildScope;

  // This callback is set to call onBuildScheduled
  if (!_scheduledFlushDirtyElements && onBuildScheduled != null) {
    _scheduledFlushDirtyElements = true;
    onBuildScheduled!();  // ← CALLS WidgetsBinding._handleBuildScheduled
  }

  buildScope._scheduleBuildFor(element);
}
```

### Step 3: The Callback Executes

**Source:** `binding.dart:1118-1147`

```dart
void _handleBuildScheduled() {
  // This function was called via function pointer!
  // No polling, no checking - direct call

  ensureVisualUpdate();
}
```

**Source:** `scheduler/binding.dart:908-919`

```dart
void ensureVisualUpdate() {
  switch (schedulerPhase) {
    case SchedulerPhase.idle:
    case SchedulerPhase.postFrameCallbacks:
      // Line 910: Tell scheduler to request frame
      scheduleFrame();
      return;
    case SchedulerPhase.transientCallbacks:
    case SchedulerPhase.midFrameMicrotasks:
    case SchedulerPhase.persistentCallbacks:
      // Already in frame, will process after
      return;
  }
}
```

---

## The Native Engine Integration - How VSYNC Works

### Step 4: Register Native Callbacks

**Source:** `scheduler/binding.dart:948-961`

```dart
void scheduleFrame() {
  // Guard against multiple calls
  if (_hasScheduledFrame || !framesEnabled) {
    return;
  }

  // Line 958: Register callbacks with native engine
  ensureFrameCallbacksRegistered();

  // Line 959: TELL NATIVE ENGINE - IPC call!
  platformDispatcher.scheduleFrame();
  //                  ^^^^^^^^^^^^^^^ This goes to C++ engine

  _hasScheduledFrame = true;
}
```

**What is `platformDispatcher.scheduleFrame()`?**

It's a **native method call** - goes to C++ engine code!

**Source:** `dart:ui` (native binding)

```dart
// This is implemented in C++, not Dart
abstract class PlatformDispatcher {
  // Native method - implemented in engine/src/lib/ui/window/platform_dispatcher.cc
  void scheduleFrame() native 'PlatformDispatcher_scheduleFrame';
}
```

### Step 5: Native Engine Registers with OS

**Pseudo-code of what happens in C++ engine:**

```cpp
// engine/src/lib/ui/window/platform_dispatcher.cc

void PlatformDispatcher::ScheduleFrame() {
  // Tell the shell to request VSYNC from OS
  shell_->ScheduleFrame();
}

// engine/src/shell/common/shell.cc

void Shell::ScheduleFrame() {
  // Register callback with OS compositor
  vsync_waiter_->AsyncWaitForVsync(
    [this](fml::TimePoint timestamp) {
      // This callback will fire when VSYNC arrives
      OnVsync(timestamp);
    }
  );
}
```

**At this point:**
- OS compositor knows Flutter wants next VSYNC
- Flutter returns to idle, waiting
- **NO POLLING, NO CHECKING, JUST WAITING FOR CALLBACK**

---

## Step 6: VSYNC Callback Fires

### When Display Sends VSYNC Signal

```
Display Hardware (60Hz):
  Every 16.67ms: Send VSYNC signal

OS Compositor:
  Receives VSYNC → Notifies registered apps

Flutter Engine (C++):
  OnVsync() callback fires

Dart VM:
  platformDispatcher.onBeginFrame() called  ← CALLBACK!
  platformDispatcher.onDrawFrame() called   ← CALLBACK!
```

### The Callbacks Were Registered Earlier

**Source:** `scheduler/binding.dart:890-906`

```dart
void ensureFrameCallbacksRegistered() {
  // Line 891: Register BEGIN frame callback (animations)
  platformDispatcher.onBeginFrame ??= _handleBeginFrame;
  //                 ^^^^^^^^^^^^^^ FUNCTION POINTER SET

  // Line 899: Register DRAW frame callback (build/layout/paint)
  platformDispatcher.onDrawFrame ??= _handleDrawFrame;
  //                 ^^^^^^^^^^^^^^ FUNCTION POINTER SET
}
```

**This is exactly like C++:**
```cpp
platformDispatcher->onBeginFrame = &SchedulerBinding::_handleBeginFrame;
platformDispatcher->onDrawFrame = &SchedulerBinding::_handleDrawFrame;
```

---

## Step 7: Persistent Frame Callbacks

**Who calls buildScope()?**

**During app initialization:**

**Source:** `binding.dart:315-330`

```dart
@override
void initInstances() {
  super.initInstances();
  _buildOwner = BuildOwner();
  buildOwner!.onBuildScheduled = _handleBuildScheduled;

  // Line 327: Register PERSISTENT frame callback
  addPersistentFrameCallback(_handlePersistentFrameCallback);
}
```

**Source:** `binding.dart:1115-1117`

```dart
void _handlePersistentFrameCallback(Duration timeStamp) {
  drawFrame();  // This calls buildScope()
}
```

**What is persistent callback?**

**Source:** `scheduler/binding.dart:1031-1038`

```dart
void addPersistentFrameCallback(FrameCallback callback) {
  _persistentCallbacks.add(callback);
  // This callback runs EVERY frame (if frame scheduled)
}
```

**When does it run?**

**Source:** `scheduler/binding.dart:1340-1380`

```dart
void handleDrawFrame() {
  _schedulerPhase = SchedulerPhase.persistentCallbacks;

  // Line 1346: Run ALL persistent callbacks
  for (final FrameCallback callback in List<FrameCallback>.of(_persistentCallbacks)) {
    _invokeFrameCallback(callback, _currentFrameTimeStamp!);
    // This calls WidgetsBinding._handlePersistentFrameCallback
    // Which calls drawFrame()
    // Which calls buildScope()
  }

  _schedulerPhase = SchedulerPhase.postFrameCallbacks;
  // ...
}
```

---

## The Complete Callback Chain

```
┌─────────────────────────────────────────────────────────────┐
│ 1. SETUP PHASE (App Initialization)                        │
└─────────────────────────────────────────────────────────────┘

BuildOwner {
  onBuildScheduled: → WidgetsBinding._handleBuildScheduled
}

SchedulerBinding {
  _persistentCallbacks: [
    WidgetsBinding._handlePersistentFrameCallback  ← Registered
  ]
}

PlatformDispatcher {
  onBeginFrame: → SchedulerBinding._handleBeginFrame
  onDrawFrame: → SchedulerBinding._handleDrawFrame
}

┌─────────────────────────────────────────────────────────────┐
│ 2. TRIGGER PHASE (setState called)                         │
└─────────────────────────────────────────────────────────────┘

setState()
  ↓
markNeedsBuild()
  ↓ _dirty = true
scheduleBuildFor()
  ↓ if first dirty element:
onBuildScheduled()  ← CALLBACK INVOKED
  ↓
_handleBuildScheduled()
  ↓
ensureVisualUpdate()
  ↓
scheduleFrame()
  ↓
platformDispatcher.scheduleFrame()  ← IPC TO NATIVE
  ↓ (C++ code)
shell->ScheduleFrame()
  ↓
OS compositor: Register for VSYNC

┌─────────────────────────────────────────────────────────────┐
│ 3. WAIT PHASE                                               │
└─────────────────────────────────────────────────────────────┘

App idle, waiting...
NO POLLING
NO CHECKING
NO LOOPS
Just waiting for OS callback

┌─────────────────────────────────────────────────────────────┐
│ 4. VSYNC ARRIVES (Display sends signal)                    │
└─────────────────────────────────────────────────────────────┘

Display: VSYNC signal (every 16.67ms @ 60Hz)
  ↓
OS Compositor: Notifies registered apps
  ↓ (C++ code)
engine->OnVsync(timestamp)
  ↓ (IPC to Dart)
platformDispatcher.onBeginFrame()  ← CALLBACK INVOKED
  ↓
_handleBeginFrame()
  ↓
handleBeginFrame()
  ↓ Run animations

platformDispatcher.onDrawFrame()  ← CALLBACK INVOKED
  ↓
_handleDrawFrame()
  ↓
handleDrawFrame()
  ↓
FOR EACH persistent callback:  ← LOOP OVER CALLBACKS
  ↓
  _handlePersistentFrameCallback()
    ↓
    drawFrame()
      ↓
      buildScope()
        ↓
        _flushDirtyElements()
          ↓
          FOR EACH dirty element:
            element.rebuild()
              ↓
              performRebuild()
                ↓
                build()  ← YOUR CODE RUNS
```

---

## Key Insight: NO Build Every Frame

### Question: "Is build() called every frame?"

**NO!** Build is only called when:
1. **setState() was called** → element marked dirty → frame requested
2. **InheritedWidget changed** → dependents marked dirty → frame requested
3. **Parent rebuilt with new widget** → child marked dirty

### If No setState()

```dart
// Scenario: App idle, user not interacting

Frame 1: Nothing happens
  → No setState() called
  → _dirtyElements list is empty
  → buildScope() checks list: empty
  → Returns immediately, NO build() calls

Frame 2: Still nothing
  → No frames even scheduled!
  → scheduleFrame() not called
  → NO VSYNC requested
  → CPU idle
```

**Source:** `framework.dart:3001-3010`

```dart
void buildScope(Element context, [VoidCallback? callback]) {
  final BuildScope buildScope = context.buildScope;

  // Line 3003: CHECK - anything dirty?
  if (callback == null && buildScope._dirtyElements.isEmpty) {
    return;  // ← EXIT IMMEDIATELY, NO WORK
  }

  // Only continues if dirty elements exist
  // ...
}
```

### Only Builds When Needed

```
Scenario: Button press every 5 seconds

Time = 0s:     User presses button
               → setState() → scheduleFrame() → VSYNC → build()

Time = 0-5s:   App idle
               → No frames scheduled
               → No VSYNC requests
               → CPU idle, battery saved

Time = 5s:     User presses button again
               → setState() → scheduleFrame() → VSYNC → build()

Time = 5-10s:  App idle again
               → No frames
               → No CPU usage
```

---

## Why No Polling?

### Bad (Polling) - What Flutter Does NOT Do

```dart
// ❌ Flutter does NOT do this:

void main() {
  while (true) {  // Infinite loop
    if (_dirtyElements.isNotEmpty) {
      buildScope();
    }
    // Wastes CPU even when idle!
  }
}
```

### Good (Event-Driven) - What Flutter Actually Does

```dart
// ✅ Flutter does this:

void main() {
  // Set up callbacks
  buildOwner.onBuildScheduled = _handleBuildScheduled;
  platformDispatcher.onDrawFrame = _handleDrawFrame;

  // Wait for events (OS handles waiting, no CPU)
  // Callbacks fire when events occur
}
```

**Result:**
- **When idle:** 0% CPU usage
- **When setState():** Callback chain → single frame → idle again
- **Battery efficient**
- **No polling overhead**

---

## Timeline with Real Times

```
Time = 0ms: User taps button
Time = 0ms: setState() called
Time = 0ms: markNeedsBuild() → _dirty = true
Time = 0ms: scheduleBuildFor() → add to dirty list
Time = 0ms: onBuildScheduled() callback fired
Time = 0ms: scheduleFrame() → tell native engine
Time = 0ms: Native engine registers with OS
Time = 0ms: Return to app code (idle)

... App idle, no CPU usage, waiting for VSYNC callback ...

Time = 16.67ms: VSYNC signal arrives (60Hz display)
Time = 16.67ms: onBeginFrame() callback fired → animations
Time = 17ms: onDrawFrame() callback fired
Time = 17ms: _handlePersistentFrameCallback() called
Time = 17ms: drawFrame() called
Time = 17ms: buildScope() called
Time = 17ms: _flushDirtyElements() called
Time = 17ms: YOUR build() method called
Time = 18ms: updateChild() → reconcile tree
Time = 19ms: Layout phase
Time = 20ms: Paint phase
Time = 21ms: Composite to GPU

Time = 33.34ms: Frame displayed on screen
Time = 33.34ms: Back to idle (no CPU usage until next setState)
```

---

## Member Variables Involved

```dart
// State class
class State<T> {
  T? _widget;                    // Current widget config
  StatefulElement? _element;     // Pointer to element (context)
}

// Element class
class Element {
  Widget _widget;                // Current widget
  Element? _parent;              // Parent element
  bool _dirty = true;            // Needs rebuild?
  bool _inDirtyList = false;     // In dirty list?
  _ElementLifecycle _lifecycleState;  // Lifecycle state
}

// BuildScope class
class BuildScope {
  final List<Element> _dirtyElements = [];  // THE dirty list
  bool? _dirtyElementsNeedsResorting;
  bool _buildScheduled = false;
  bool _building = false;
}

// SchedulerBinding
class SchedulerBinding {
  bool _hasScheduledFrame = false;
  SchedulerPhase _schedulerPhase = SchedulerPhase.idle;
  Map<int, _FrameCallbackEntry> _transientCallbacks = {};
  List<FrameCallback> _persistentCallbacks = [];
}
```

---

## Key Points

1. **No polling loop** - Event-driven with callbacks
2. **Dirty list batches** - Multiple setState() calls in one frame
3. **Single-pass rebuild** - Each element rebuilt once per frame
4. **Parent-first sorting** - Parents rebuild before children
5. **VSYNC-driven** - Rebuilds synchronized with display refresh

---

## Debugging

### Print rebuild count

```dart
class _CounterState extends State<Counter> {
  int _buildCount = 0;

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    print('Build count: $_buildCount');
    return Text('Count: $_count');
  }
}
```

### Track setState calls

```dart
@override
void setState(VoidCallback fn) {
  print('setState called: ${StackTrace.current}');
  super.setState(fn);
}
```

### Monitor dirty list

```dart
// In framework:
void _flushDirtyElements() {
  print('Dirty elements: ${_dirtyElements.length}');
  for (final element in _dirtyElements) {
    print('  - ${element.widget.runtimeType}');
  }
  // ...
}
```
