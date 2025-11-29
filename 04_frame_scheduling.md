# Frame Scheduling and VSYNC - Complete Guide

## Overview

Flutter does **NOT** poll for changes. It uses an event-driven architecture with VSYNC signals from the OS.

```
❌ NO polling loop:
while (true) {
  if (anyElementDirty()) rebuild();
}

✅ Event-driven:
platformDispatcher.onDrawFrame = callback;
platformDispatcher.scheduleFrame();
```

---

## The Architecture

```
Dart Code (Flutter)
      ↕
Native Engine (C++)
      ↕
OS Compositor
      ↕
Display Hardware (60Hz/120Hz)
```

---

## Complete Flow: From setState to Screen

### Step 1: Mark Dirty (Synchronous)

```dart
setState(() { _count++; })
  ↓
markNeedsBuild()
  ├─ _dirty = true
  └─ owner.scheduleBuildFor(this)
      ├─ _dirtyElements.add(element)
      └─ onBuildScheduled!()  ← CALLBACK
```

**Source:** `framework.dart:5245-5296`

```dart
void markNeedsBuild() {
  if (_lifecycleState != _ElementLifecycle.active) return;
  if (dirty) return;

  _dirty = true;
  owner!.scheduleBuildFor(this);
}
```

**Source:** `framework.dart:2661-2674`

```dart
void _scheduleBuildFor(Element element) {
  if (!element._inDirtyList) {
    _dirtyElements.add(element);
    element._inDirtyList = true;
  }

  if (!_buildScheduled && !_building) {
    _buildScheduled = true;
    scheduleRebuild?.call();  // Callback to binding
  }
}
```

### Step 2: Request Frame (Synchronous)

**Source:** `binding.dart:452-453`

```dart
void initInstances() {
  _buildOwner = BuildOwner();
  buildOwner!.onBuildScheduled = _handleBuildScheduled;  // Set callback
}
```

**Source:** `binding.dart:1118-1147`

```dart
void _handleBuildScheduled() {
  ensureVisualUpdate();
}
```

**Source:** `scheduler/binding.dart:908-919`

```dart
void ensureVisualUpdate() {
  switch (schedulerPhase) {
    case SchedulerPhase.idle:
    case SchedulerPhase.postFrameCallbacks:
      scheduleFrame();  // Request frame!
      return;
    case SchedulerPhase.transientCallbacks:
    case SchedulerPhase.midFrameMicrotasks:
    case SchedulerPhase.persistentCallbacks:
      return;  // Already in frame
  }
}
```

### Step 3: Register Native Callbacks

**Source:** `scheduler/binding.dart:948-961`

```dart
void scheduleFrame() {
  if (_hasScheduledFrame || !framesEnabled) {
    return;
  }

  // Register callbacks
  ensureFrameCallbacksRegistered();

  // TELL NATIVE ENGINE
  platformDispatcher.scheduleFrame();

  _hasScheduledFrame = true;
}
```

**Source:** `scheduler/binding.dart:890-893`

```dart
void ensureFrameCallbacksRegistered() {
  // Register BEGIN callback
  platformDispatcher.onBeginFrame ??= _handleBeginFrame;

  // Register DRAW callback
  platformDispatcher.onDrawFrame ??= _handleDrawFrame;
}
```

### What is platformDispatcher?

**It's `dart:ui.PlatformDispatcher`** - a bridge to native code (C++).

```dart
abstract class PlatformDispatcher {
  // Callback for animation phase
  VoidCallback? onBeginFrame;

  // Callback for build/layout/paint phase
  VoidCallback? onDrawFrame;

  // Tell native engine to call callbacks on next VSYNC
  void scheduleFrame();
}
```

---

## Native Engine (C++ Layer)

### What Happens in Native Code

```cpp
// Pseudo-code (actual implementation in engine/src)

class Shell {
  void ScheduleFrame() {
    // Register with OS compositor
    vsync_waiter_->ScheduleVSync([this](fml::TimePoint timestamp) {
      // When VSYNC arrives, call Dart callbacks
      OnVsync(timestamp);
    });
  }

  void OnVsync(fml::TimePoint timestamp) {
    // Call Dart's onBeginFrame
    DartInvoke(dart_on_begin_frame_, timestamp);

    // Call Dart's onDrawFrame
    DartInvoke(dart_on_draw_frame_);
  }
};
```

### OS Compositor

```
Display refresh: 60Hz (every 16.67ms)
                or 120Hz (every 8.33ms)

Timeline:
0ms     VSYNC signal
16.67ms VSYNC signal
33.34ms VSYNC signal
...

Flutter engine registers to receive these signals.
```

---

## Step 4: Wait for VSYNC (Asynchronous)

```
Time = 0ms: setState() called
Time = 0ms: scheduleFrame() called
Time = 0ms: Return to app code

... App continues running ...
... Engine waits for VSYNC ...

Time = 16.67ms: VSYNC signal from OS!
```

---

## Step 5: Begin Frame (Animation Phase)

**Source:** `scheduler/binding.dart:1170-1180`

```dart
void _handleBeginFrame(Duration rawTimeStamp) {
  handleBeginFrame(rawTimeStamp);
}
```

**Source:** `scheduler/binding.dart:1228-1276`

```dart
void handleBeginFrame(Duration? rawTimeStamp) {
  _hasScheduledFrame = false;
  _currentFrameTimeStamp = rawTimeStamp;

  // Set phase
  _schedulerPhase = SchedulerPhase.transientCallbacks;

  // Run animation callbacks
  final Map<int, _FrameCallbackEntry> callbacks = _transientCallbacks;
  _transientCallbacks = <int, _FrameCallbackEntry>{};

  callbacks.forEach((int id, _FrameCallbackEntry callbackEntry) {
    _invokeFrameCallback(
      callbackEntry.callback,
      _currentFrameTimeStamp!,
    );
  });

  _schedulerPhase = SchedulerPhase.midFrameMicrotasks;
}
```

**Animation callbacks:**
- `AnimationController.tick()`
- Custom frame callbacks

**NO REBUILDING YET!**

---

## Step 6: Draw Frame (Build/Layout/Paint Phase)

**Source:** `scheduler/binding.dart:1182-1201`

```dart
void _handleDrawFrame() {
  handleDrawFrame();
}
```

**Source:** `scheduler/binding.dart:1340-1380`

```dart
void handleDrawFrame() {
  _schedulerPhase = SchedulerPhase.persistentCallbacks;

  // Run persistent callbacks
  for (final FrameCallback callback in List<FrameCallback>.of(_persistentCallbacks)) {
    _invokeFrameCallback(callback, _currentFrameTimeStamp!);
  }

  // Post-frame callbacks
  _schedulerPhase = SchedulerPhase.postFrameCallbacks;
  final List<FrameCallback> localPostFrameCallbacks =
      List<FrameCallback>.of(_postFrameCallbacks);
  _postFrameCallbacks.clear();

  for (final FrameCallback callback in localPostFrameCallbacks) {
    _invokeFrameCallback(callback, _currentFrameTimeStamp!);
  }

  _schedulerPhase = SchedulerPhase.idle;
}
```

### Persistent Callbacks

**WidgetsBinding registers itself:**

```dart
void initInstances() {
  // Register drawFrame as persistent callback
  addPersistentFrameCallback(_handlePersistentFrameCallback);
}

void _handlePersistentFrameCallback(Duration timeStamp) {
  drawFrame();  // Build/layout/paint
}
```

---

## Step 7: WidgetsBinding.drawFrame

**Source:** `binding.dart:1224-1285`

```dart
@override
void drawFrame() {
  try {
    // BUILD PHASE
    if (rootElement != null) {
      buildOwner!.buildScope(rootElement!);  // Rebuild dirty elements
    }

    // LAYOUT & PAINT PHASE
    super.drawFrame();  // RenderView.compositeFrame()

    // FINALIZE
    buildOwner!.finalizeTree();
  }
}
```

### Build Phase

**Source:** `framework.dart:3001-3065`

```dart
void buildScope(Element context, [VoidCallback? callback]) {
  final BuildScope buildScope = context.buildScope;

  if (callback == null && buildScope._dirtyElements.isEmpty) {
    return;  // Nothing to do
  }

  _scheduledFlushDirtyElements = true;
  buildScope._building = true;

  // REBUILD ALL DIRTY ELEMENTS
  buildScope._flushDirtyElements(debugBuildRoot: context);

  _scheduledFlushDirtyElements = false;
  buildScope._building = false;
}
```

**Source:** `framework.dart:2743-2789`

```dart
void _flushDirtyElements({required Element debugBuildRoot}) {
  // Sort by depth (parent before child)
  _dirtyElements.sort(Element._sort);

  // THE REBUILD LOOP
  for (int index = 0; index < _dirtyElements.length;
       index = _dirtyElementIndexAfter(index)) {
    final Element element = _dirtyElements[index];

    if (identical(element.buildScope, this)) {
      _tryRebuild(element);  // Rebuild this element
    }
  }

  // Cleanup
  for (final Element element in _dirtyElements) {
    element._inDirtyList = false;
  }
  _dirtyElements.clear();
}
```

### Layout Phase

```dart
// In RenderView:
void compositeFrame() {
  // Walk render tree and layout
  for (RenderObject child in _children) {
    if (child._needsLayout) {
      child.layout(constraints);
    }
  }

  // Walk render tree and paint
  for (RenderObject child in _children) {
    if (child._needsPaint) {
      child.paint(context, offset);
    }
  }

  // Send to GPU
  scene.toImage();
}
```

---

## Complete Timeline

```
Time = 0ms
  User taps button
    ↓
  setState(() { _count++; })
    ↓
  markNeedsBuild()
    ├─ _dirty = true
    ├─ _dirtyElements.add(element)
    └─ scheduleFrame()
        └─ platformDispatcher.scheduleFrame()

Time = 0-16.67ms
  App continues running normally
  Native engine waiting for VSYNC
  Display showing previous frame

Time = 16.67ms
  VSYNC signal arrives!
    ↓
  platformDispatcher.onBeginFrame() called
    ↓
  handleBeginFrame()
    └─ Run animation callbacks

Time = 17ms
  platformDispatcher.onDrawFrame() called
    ↓
  handleDrawFrame()
    └─ Run persistent callbacks
        ↓
        WidgetsBinding.drawFrame()
          ↓
          buildScope()
            └─ _flushDirtyElements()
                ↓
                element.rebuild()
                  ↓
                  performRebuild()
                    ↓
                    build()  ← YOUR CODE RUNS

Time = 18ms
  Layout phase
    └─ RenderObject.layout() for dirty objects

Time = 19ms
  Paint phase
    └─ RenderObject.paint() for dirty objects

Time = 20ms
  Composite to GPU
    └─ scene.toImage()

Time = 33.34ms
  Frame displayed on screen!
```

---

## Scheduler Phases

**Source:** `scheduler/binding.dart`

```dart
enum SchedulerPhase {
  idle,                    // No frame being processed
  transientCallbacks,      // Animations
  midFrameMicrotasks,      // Micro-tasks between phases
  persistentCallbacks,     // Build/layout/paint
  postFrameCallbacks,      // After frame
}
```

### Phase Diagram

```
Frame N:
  idle
    ↓ VSYNC
  transientCallbacks      ← Animations
    ↓
  midFrameMicrotasks
    ↓
  persistentCallbacks     ← Build/layout/paint
    ↓
  postFrameCallbacks      ← Cleanup
    ↓
  idle

Frame N+1:
  ...
```

---

## Frame Callbacks

### Transient Callbacks (Animations)

```dart
SchedulerBinding.instance.scheduleFrameCallback((Duration timestamp) {
  print('Animation frame: $timestamp');
});
```

**Runs once, then removed.**

### Persistent Callbacks (Build)

```dart
SchedulerBinding.instance.addPersistentFrameCallback((Duration timestamp) {
  print('Every frame: $timestamp');
});
```

**Runs every frame forever.**

### Post-Frame Callbacks

```dart
SchedulerBinding.instance.addPostFrameCallback((Duration timestamp) {
  print('After frame: $timestamp');
});
```

**Runs once after current frame, then removed.**

---

## Multiple setState() Calls - Batching

### Example

```dart
void _handleTap() {
  setState(() { _a = 1; });  // Schedules frame
  setState(() { _b = 2; });  // Already scheduled, skips
  setState(() { _c = 3; });  // Already scheduled, skips
}
```

### Code Path

**Source:** `framework.dart:5292-5296`

```dart
void markNeedsBuild() {
  if (dirty) {
    return;  // Already dirty, skip!
  }

  _dirty = true;
  owner!.scheduleBuildFor(this);
}
```

**Source:** `scheduler/binding.dart:948-961`

```dart
void scheduleFrame() {
  if (_hasScheduledFrame || !framesEnabled) {
    return;  // Already scheduled, skip!
  }

  ensureFrameCallbacksRegistered();
  platformDispatcher.scheduleFrame();
  _hasScheduledFrame = true;
}
```

### Result

```
setState() #1:
  markNeedsBuild() → _dirty = true
  scheduleFrame() → request frame

setState() #2:
  markNeedsBuild() → dirty? YES → return
  (No frame request)

setState() #3:
  markNeedsBuild() → dirty? YES → return
  (No frame request)

Next frame:
  All three changes in ONE rebuild
  build() called ONCE with _a=1, _b=2, _c=3
```

**This is why setState is efficient!**

---

## Skipping Frames

### If Frame Scheduled During Frame

```dart
// During build phase:
setState(() {});  // Schedules another frame

// Current frame completes
// Next VSYNC: New frame starts
```

### If Too Many setState() Calls

```dart
while (true) {
  setState(() {});  // DON'T DO THIS!
}

// Creates infinite rebuild loop
// App will freeze/janky
// DevTools will show warnings
```

---

## Frame Budget

```
60Hz display: 16.67ms per frame

Budget breakdown:
  Build:      ~2-5ms
  Layout:     ~2-5ms
  Paint:      ~2-5ms
  Composite:  ~2-3ms
  Total:      ~10-20ms

If total > 16.67ms: Frame dropped!
```

### Detecting Dropped Frames

```dart
void initInstances() {
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final timing in timings) {
      final duration = timing.totalSpan;
      if (duration.inMilliseconds > 16) {
        print('Frame dropped! ${duration.inMilliseconds}ms');
      }
    }
  });
}
```

---

## No Frame = No CPU Usage

**Important:** If no `setState()` called, no frames scheduled!

```dart
// App idle:
  No setState()
    → No markNeedsBuild()
    → No scheduleFrame()
    → No VSYNC callbacks
    → CPU idle
    → Battery saved!

// This is why Flutter is efficient
```

---

## Debugging Frame Scheduling

### Print frame timing

```dart
void drawFrame() {
  final start = DateTime.now();
  super.drawFrame();
  final duration = DateTime.now().difference(start);
  print('Frame took: ${duration.inMilliseconds}ms');
}
```

### Track scheduleFrame calls

```dart
void scheduleFrame() {
  print('scheduleFrame: ${StackTrace.current}');
  super.scheduleFrame();
}
```

### Monitor scheduler phase

```dart
void logPhase() {
  print('Phase: ${SchedulerBinding.instance.schedulerPhase}');
}
```

### Use Flutter DevTools

- Performance tab shows frame timeline
- Frame chart shows build/layout/paint times
- Janky frames highlighted in red

---

## Summary

### Key Points

1. **Event-driven, not polling** - No while loop checking dirty flags
2. **VSYNC-based** - Synchronized with display refresh
3. **Batched rebuilds** - Multiple setState() = one rebuild
4. **Single-pass** - Each element rebuilt once per frame
5. **Idle efficiency** - No frames = no CPU usage

### The Flow

```
setState()
  → markNeedsBuild()
  → scheduleFrame()
  → platformDispatcher.scheduleFrame()
  → Wait for VSYNC...
  → onBeginFrame() (animations)
  → onDrawFrame() (build/layout/paint)
  → Display updated
```

### Member Variables

```dart
// Element
bool _dirty = false;
bool _inDirtyList = false;

// BuildScope
List<Element> _dirtyElements = [];
bool _buildScheduled = false;

// SchedulerBinding
bool _hasScheduledFrame = false;
SchedulerPhase _schedulerPhase = SchedulerPhase.idle;
```
