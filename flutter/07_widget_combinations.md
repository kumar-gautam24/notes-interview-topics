# Common Widget Combinations - Size & Constraint Flows

## Overview

This guide shows **exactly** what size every widget will be in common scenarios, with actual constraint flows.

---

## Case 1: Scaffold + Container (No Size)

### Code

```dart
Scaffold(
  body: Container(),
)
```

### Constraint Flow

```
Screen (400x800)
  ↓ constraints: tight(400, 800)  // Must be exactly 400x800

Scaffold.performLayout():
  body.layout(BoxConstraints.tight(Size(400, 800)))
  ↓ constraints: tight(400, 800)

Container (RenderProxyBox)
  No child, no explicit size
  ↓
  size = constraints.constrain(Size.zero)
  size = Size(400, 800)  ← Takes maximum from tight constraints
```

**Result:** Container fills entire screen (400x800)

### Why?

**Tight constraints force exact size.**

```dart
BoxConstraints.tight(Size(400, 800))
// minWidth = maxWidth = 400
// minHeight = maxHeight = 800
// Child MUST be 400x800
```

---

## Case 2: Scaffold + Container(width: 100, height: 50)

### Code

```dart
Scaffold(
  body: Container(
    width: 100,
    height: 50,
  ),
)
```

### Constraint Flow

```
Screen (400x800)
  ↓ tight(400, 800)

Scaffold
  ↓ tight(400, 800)

Container (RenderConstrainedBox)
  Receives: tight(400, 800)
  additionalConstraints: tightFor(width: 100, height: 50)

  Combined:
    Parent says: "MUST be 400x800"
    Child says: "I want to be 100x50"

  RenderConstrainedBox.performLayout():
    childConstraints = constraints.enforce(additionalConstraints)
    // enforce() makes child constraints win
    childConstraints = tight(100, 50)

    size = Size(100, 50)
```

**Result:** Container is 100x50

**But this causes layout error!** Scaffold expects tight constraints to be satisfied.

**Solution:** Use Center or other widget that loosens constraints.

---

## Case 3: Scaffold + Center + Container

### Code

```dart
Scaffold(
  body: Center(
    child: Container(
      width: 100,
      height: 50,
      color: Colors.red,
    ),
  ),
)
```

### Constraint Flow

```
Screen (400x800)
  ↓ tight(400, 800)

Scaffold
  ↓ tight(400, 800)

Center (RenderPositionedBox)
  Receives: tight(400, 800)

  performLayout():
    // LOOSEN constraints
    childConstraints = constraints.loosen()
    // loose(0-400, 0-800)

  ↓ loose(0-400, 0-800)

Container
  Receives: loose(0-400, 0-800)
  additionalConstraints: tight(100, 50)

  Combined: tight(100, 50)
  size = Size(100, 50)  ← SIZE UP

Center
  childSize = Size(100, 50)
  shrinkWrapWidth = false (widthFactor null)
  shrinkWrapHeight = false (heightFactor null)

  size = constraints.constrain(Size(infinity, infinity))
  size = Size(400, 800)  ← Takes max

  Position child:
    offset = Offset((400-100)/2, (800-50)/2)
    offset = Offset(150, 375)
```

**Result:**
- Center: 400x800 (fills screen)
- Container: 100x50 (positioned at center)

---

## Case 4: Column + Container (No Size)

### Code

```dart
Column(
  children: [
    Container(),
  ],
)
```

### The Problem

```
Parent (e.g., Scaffold body): tight(400, 800)
  ↓ tight(400, 800)

Column (RenderFlex)
  performLayout():
    // Column gives UNBOUNDED height to children!
    child.layout(BoxConstraints(
      minWidth: 0,
      maxWidth: 400,
      minHeight: 0,
      maxHeight: double.infinity,  ← UNBOUNDED!
    ))

  ↓ (0-400, 0-infinity)

Container
  Receives: (0-400, 0-infinity)
  No child, no explicit size

  size = constraints.constrain(Size.zero)
  size = Size(0, 0)  ← Width 0, height 0!
```

**Result:** Container has Size(0, 0) - invisible!

### Why?

Without explicit size and without child, Container takes minimum size (0, 0).

**But wait - why width 0?**

Because Container has no child and no width, it takes minWidth (0).

**Actually:** Most containers in Column take maxWidth:

```dart
// With RenderConstrainedBox and no child:
size = constraints.constrain(additionalConstraints.constrain(Size.zero))
// With no additionalConstraints:
size = constraints.constrain(Size.zero)
// = Size(0, 0)
```

---

## Case 5: Column + Container(height: 50)

### Code

```dart
Column(
  children: [
    Container(height: 50),
  ],
)
```

### Constraint Flow

```
Parent: tight(400, 800)
  ↓ tight(400, 800)

Column
  ↓ (0-400, 0-infinity)

Container(height: 50)
  Receives: (0-400, 0-infinity)
  additionalConstraints: tightFor(height: 50)

  Combined:
    minHeight = 50, maxHeight = 50
    minWidth = 0, maxWidth = 400

  No child:
    size = Size(maxWidth, 50)
    size = Size(400, 50)  ← Takes max width!
```

**Result:** Container is 400x50

**Why full width?**

When no child and no explicit width, Container takes maxWidth from constraints.

### To Make It Smaller

```dart
Container(
  width: 100,  // Specify width
  height: 50,
)
// Result: Size(100, 50)
```

---

## Case 6: Column + Expanded

### Code

```dart
Column(
  children: [
    Container(height: 100),  // Fixed
    Expanded(
      child: Container(color: Colors.blue),  // Fills remaining
    ),
    Container(height: 50),   // Fixed
  ],
)
```

### Constraint Flow

```
Parent: tight(400, 800)
  ↓ tight(400, 800)

Column.performLayout():

  Step 1: Layout non-flex children
    child1.layout((0-400, 0-infinity))
      → size = Size(400, 100)

    child3.layout((0-400, 0-infinity))
      → size = Size(400, 50)

  Step 2: Calculate remaining space
    usedSpace = 100 + 50 = 150
    remainingSpace = 800 - 150 = 650

  Step 3: Layout flex children
    Expanded has flex: 1, totalFlex: 1
    flexSpace = 650 / 1 = 650

    child2.layout(BoxConstraints.tightFor(
      width: 400,
      height: 650,
    ))
      → size = Size(400, 650)

  Step 4: Position children
    child1.offset = Offset(0, 0)
    child2.offset = Offset(0, 100)
    child3.offset = Offset(0, 750)

  Step 5: My size
    size = Size(400, 800)
```

**Result:**
- Container1: 400x100 at (0, 0)
- Container2: 400x650 at (0, 100)  ← Expanded
- Container3: 400x50 at (0, 750)

---

## Case 7: Padding + Container

### Code

```dart
Padding(
  padding: EdgeInsets.all(20),
  child: Container(color: Colors.red),
)
```

### Constraint Flow

```
Parent: tight(400, 800)
  ↓ tight(400, 800)

Padding.performLayout():
  padding = EdgeInsets.all(20)

  // DEFLATE constraints
  innerConstraints = constraints.deflate(padding)
  innerConstraints = tight(360, 760)
  // 400 - 20 - 20 = 360
  // 800 - 20 - 20 = 760

  ↓ tight(360, 760)

Container
  size = Size(360, 760)  ← SIZE UP

Padding
  child.offset = Offset(20, 20)  ← POSITION

  size = Size(
    padding.horizontal + child.size.width,
    padding.vertical + child.size.height,
  )
  size = Size(40 + 360, 40 + 760)
  size = Size(400, 800)
```

**Result:**
- Padding: 400x800
- Container: 360x760 (positioned at 20, 20)

---

## Case 8: Stack + Positioned

### Code

```dart
Stack(
  children: [
    Container(color: Colors.red),  // Non-positioned
    Positioned(
      top: 50,
      left: 50,
      width: 100,
      height: 100,
      child: Container(color: Colors.blue),
    ),
  ],
)
```

### Constraint Flow

```
Parent: tight(400, 800)
  ↓ tight(400, 800)

Stack.performLayout():

  Step 1: Layout non-positioned children with loose constraints
    child1.layout(constraints.loosen())
    ↓ loose(0-400, 0-800)

    Container (no size, no child)
      size = Size(400, 800)  ← Takes max

  Step 2: Stack sizes itself based on non-positioned children
    size = Size(400, 800)

  Step 3: Layout positioned children
    Positioned constraints calculated from position values:

    childConstraints = BoxConstraints.tight(Size(100, 100))

    child2.layout(tight(100, 100))
      → size = Size(100, 100)

  Step 4: Position children
    child1.offset = Offset(0, 0)
    child2.offset = Offset(50, 50)  ← From Positioned(top, left)
```

**Result:**
- Stack: 400x800
- Container1: 400x800 at (0, 0)
- Container2: 100x100 at (50, 50)

---

## Case 9: SizedBox vs Container

### SizedBox

```dart
SizedBox(
  width: 100,
  height: 50,
  child: MyWidget(),
)
```

**Creates:**
```
RenderConstrainedBox
  → child
```

**1 RenderObject**

### Container

```dart
Container(
  width: 100,
  height: 50,
  child: MyWidget(),
)
```

**Creates:**
```
RenderDecoratedBox (if decoration)
  → RenderPadding (if padding)
    → RenderConstrainedBox (if constraints)
      → child
```

**1-3 RenderObjects**

### Performance

**SizedBox is more efficient when you only need size constraints!**

---

## Case 10: Center with widthFactor

### Code

```dart
Center(
  widthFactor: 1.5,
  child: Container(width: 100, height: 50),
)
```

### Constraint Flow

```
Parent: tight(400, 800)
  ↓ tight(400, 800)

Center.performLayout():
  child.layout(loose(0-400, 0-800))
    ↓
    Container
      size = Size(100, 50)  ← SIZE UP

  shrinkWrapWidth = true (widthFactor not null)
  shrinkWrapHeight = false (heightFactor null)

  size = constraints.constrain(Size(
    100 * 1.5,  // child.width * widthFactor
    double.infinity,
  ))
  size = Size(150, 800)

  Position child:
    offset = Offset((150-100)/2, (800-50)/2)
    offset = Offset(25, 375)
```

**Result:**
- Center: 150x800
- Container: 100x50 (centered within 150x800)

---

## Decision Tree: What Size Will My Widget Be?

```
1. Does it have tight constraints from parent?
   └─ YES → Must be that exact size
      Example: Scaffold body → tight(screen size)

2. Does it have explicit size (width/height)?
   └─ YES → That size (within parent constraints)
      Example: Container(width: 100) → 100 wide

3. Does it have a child?
   ├─ YES → Wraps child size
   │    Example: Container(child: Text('Hi')) → text size
   └─ NO → Takes max from constraints
        Example: Container() in Center → max available

4. Is it in unbounded constraints?
   ├─ Has intrinsic size → That size
   │    Example: Text('Hi') in Column → text size
   └─ No intrinsic size → ERROR!
        Example: Container() in Column → Size(0, 0)
```

---

## Common Patterns

### Pattern 1: Fill Parent

```dart
// Child fills parent
Container()  // In tight constraints

// Result: Parent size
```

### Pattern 2: Wrap Content

```dart
// Child wraps content
Container(
  child: Text('Hello'),
)

// Result: Text size
```

### Pattern 3: Fixed Size

```dart
// Child has fixed size
Container(
  width: 100,
  height: 50,
)

// Result: 100x50 (unless parent has tighter constraints)
```

### Pattern 4: Flexible Size

```dart
// Child takes available space
Expanded(
  child: Container(),
)

// Result: Remaining space in Column/Row
```

---

## Constraint Reference Table

| Parent Widget | Constraints to Child | Own Size |
|--------------|---------------------|----------|
| `Scaffold` body | Tight (screen size) | Screen size |
| `Center` | Loose (0 to parent max) | Max unless widthFactor/heightFactor |
| `Align` | Loose (0 to parent max) | Max unless widthFactor/heightFactor |
| `Padding` | Deflated (parent - padding) | Parent size |
| `SizedBox(w, h)` | Tight (w, h) | w x h |
| `Container(w, h)` | Tight (w, h) | w x h |
| `Container()` no size | Pass through | Child size or max |
| `Column` | Unbounded height | Sum of children |
| `Row` | Unbounded width | Sum of children |
| `Expanded` in Column | Tight (remaining space) | Assigned flex space |
| `Flexible` in Column | Max (remaining space) | Child decides within remaining |
| `Stack` | Loose | Largest non-positioned child |
| `Positioned` in Stack | Calculated from position values | Specified or child size |
| `FractionallySizedBox` | Fraction of parent | Parent size * factor |
| `AspectRatio` | Maintains aspect ratio | Based on constraints & ratio |

---

## Common Mistakes

### Mistake 1: Container in Column without size

```dart
// ❌ WRONG
Column(
  children: [
    Container(),  // Size(0, 0) - invisible!
  ],
)

// ✅ CORRECT
Column(
  children: [
    Container(height: 50),  // Has size
    // OR
    Container(child: Text('Hi')),  // Has child
  ],
)
```

### Mistake 2: Expecting Container to wrap content by default

```dart
// ❌ ASSUMPTION
Container(
  child: Text('Hi'),
)  // Will wrap text ✅

Container()  // Will NOT be small - takes max! ❌
```

### Mistake 3: Using Container when SizedBox is enough

```dart
// ❌ INEFFICIENT
Container(
  width: 100,
  height: 50,
  child: MyWidget(),
)

// ✅ BETTER
SizedBox(
  width: 100,
  height: 50,
  child: MyWidget(),
)
```

### Mistake 4: Forgetting about tight constraints

```dart
// ❌ WILL CAUSE ERROR
Scaffold(
  body: Container(width: 100, height: 50),  // Error!
)

// ✅ CORRECT
Scaffold(
  body: Center(  // Loosens constraints
    child: Container(width: 100, height: 50),
  ),
)
```

---

## Debugging Tips

### Use LayoutBuilder

```dart
LayoutBuilder(
  builder: (context, constraints) {
    print('Constraints: $constraints');
    print('  minWidth: ${constraints.minWidth}');
    print('  maxWidth: ${constraints.maxWidth}');
    print('  minHeight: ${constraints.minHeight}');
    print('  maxHeight: ${constraints.maxHeight}');
    return MyWidget();
  },
)
```

### Check actual size

```dart
class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject() as RenderBox;
      print('Size: ${box.size}');
      print('Position: ${box.localToGlobal(Offset.zero)}');
    });
    return Container();
  }
}
```

### Use Flutter Inspector

- Select widget
- See "Constraints" panel
- See "Size" panel
- Use "Show Guidelines" to visualize layout

---

## Summary

### Golden Rules

1. **Tight constraints force exact size**
2. **Loose constraints allow child to decide**
3. **Unbounded constraints need intrinsic size**
4. **No size + no child = takes max**
5. **Column gives unbounded height**
6. **Row gives unbounded width**
7. **Center loosens constraints**
8. **Padding deflates constraints**
9. **Expanded/Flexible use remaining space**
10. **Stack sizes to non-positioned children**

### The Flow

```
Constraints go down ⬇️
  Parent → child.layout(constraints)

Sizes go up ⬆️
  Child → size = Size(w, h)
  Parent ← child.size

Parent sets position 📍
  Parent → child.parentData.offset = Offset(x, y)
```
