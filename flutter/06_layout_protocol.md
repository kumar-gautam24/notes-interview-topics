# Flutter Layout Protocol - Complete Guide

## "Constraints go down. Sizes go up. Parent sets position."

This is the **fundamental layout algorithm** in Flutter's Render tree.

---

## The Three Trees

```
Widget Tree              Element Tree            Render Tree
(Configuration)          (Lifecycle)             (Layout & Paint)

Container                Element                 RenderDecoratedBox
  ↓                        ↓                       ↓
Column                   Element                 RenderFlex
  ↓                        ↓                       ↓
Text                     Element                 RenderParagraph
```

**The layout protocol operates on the RENDER TREE.**

---

## The Protocol

### 1. Constraints Go Down ⬇️

**Parent calls `child.layout(constraints)`**

**Source:** `object.dart:2649-2722`

```dart
void layout(Constraints constraints, {bool parentUsesSize = false}) {
  // Check if layout needed
  if (!_needsLayout && constraints == _constraints) {
    return;  // Already laid out with same constraints
  }

  // Store constraints from parent
  _constraints = constraints;

  // Do the actual layout
  performLayout();
}
```

### 2. Sizes Go Up ⬆️

**Child sets its own size**

**Source:** `box.dart:2306-2312`

```dart
Size? _size;

@protected
set size(Size value) {
  assert(sizedByParent || !debugDoingThisResize);
  _size = value;  // Child sets its own size
}
```

**Parent reads child's size:**

```dart
void performLayout() {
  child.layout(constraints);  // Pass constraints down
  final childSize = child.size;  // Read size up
}
```

### 3. Parent Sets Position 📍

**Parent writes to child's `ParentData`**

**Source:** `box.dart:963-969`

```dart
class BoxParentData extends ParentData {
  Offset offset = Offset.zero;  // Position in parent's coordinate system
}
```

```dart
void performLayout() {
  child.layout(constraints);

  final BoxParentData childParentData = child.parentData as BoxParentData;
  childParentData.offset = Offset(10, 20);  // Parent sets position
}
```

---

## BoxConstraints Structure

**Source:** `box.dart:100-150`

```dart
class BoxConstraints extends Constraints {
  const BoxConstraints({
    this.minWidth = 0.0,
    this.maxWidth = double.infinity,
    this.minHeight = 0.0,
    this.maxHeight = double.infinity,
  });

  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;
}
```

### Constraint Types

```dart
// 1. Tight constraints
BoxConstraints.tight(Size(100, 50))
// minWidth = maxWidth = 100
// minHeight = maxHeight = 50
// Child MUST be exactly 100x50

// 2. Loose constraints
BoxConstraints.loose(Size(200, 200))
// minWidth = minHeight = 0
// maxWidth = maxHeight = 200
// Child can be 0-200 wide, 0-200 tall

// 3. Unbounded constraints
BoxConstraints(
  minWidth: 0,
  maxWidth: double.infinity,
  minHeight: 0,
  maxHeight: double.infinity,
)
// Child can be any size (must have intrinsic size)
```

---

## Example: Column Layout

### Widget Code

```dart
Column(
  children: [
    Container(height: 50, color: Colors.red),
    Container(height: 100, color: Colors.blue),
  ],
)
```

### Render Tree

```
RenderFlex (Column)
  ├─ RenderDecoratedBox (Container 1)
  └─ RenderDecoratedBox (Container 2)
```

### Layout Code Path

**Source:** `flex.dart:1244-1307`

```dart
class RenderFlex extends RenderBox {
  @override
  void performLayout() {
    // STEP 1: Get MY constraints from MY parent
    final BoxConstraints constraints = this.constraints;
    // e.g., tight(400, 800)

    // STEP 2: Calculate sizes and layout children
    final _LayoutSizes sizes = _computeSizes(
      constraints: constraints,
      layoutChild: ChildLayoutHelper.layoutChild,
    );

    // Inside _computeSizes:
    // for each child:
    //   child.layout(BoxConstraints(
    //     minWidth: 0,
    //     maxWidth: 400,
    //     minHeight: 0,
    //     maxHeight: double.infinity,  ← Unbounded!
    //   ))

    // STEP 3: Set MY size
    size = sizes.axisSize.toSize(direction);
    // e.g., Size(400, 150)

    // STEP 4: Position children
    double childMainPosition = leadingSpace;

    for (RenderBox? child = topLeftChild; child != null; child = nextChild(child)) {
      final double childCrossPosition = /* calculate */;

      // Get child's ParentData
      final FlexParentData childParentData = child.parentData! as FlexParentData;

      // SET POSITION
      childParentData.offset = switch (direction) {
        Axis.horizontal => Offset(childMainPosition, childCrossPosition),
        Axis.vertical => Offset(childCrossPosition, childMainPosition),
      };

      // Move to next position
      childMainPosition += _getMainSize(child.size) + betweenSpace;
    }
  }
}
```

### Complete Flow

```
Screen (Root): 400x800
  ↓ constraints: tight(400, 800)

Column.performLayout():
  ↓
  STEP 1: CONSTRAINTS GO DOWN
    child1.layout(BoxConstraints(0-400, 0-infinity))
      ↓
      Container1.performLayout():
        additionalConstraints: tightFor(height: 50)
        size = Size(400, 50)  ← SIZE UP

    child2.layout(BoxConstraints(0-400, 0-infinity))
      ↓
      Container2.performLayout():
        additionalConstraints: tightFor(height: 100)
        size = Size(400, 100)  ← SIZE UP

  STEP 2: SIZES GO UP
    totalHeight = child1.size.height + child2.size.height
    totalHeight = 50 + 100 = 150

    size = Size(400, 150)  ← Column's size

  STEP 3: PARENT SETS POSITION
    child1.parentData.offset = Offset(0, 0)
    child2.parentData.offset = Offset(0, 50)

Result:
  Column: 400x150
    Container1 at (0, 0):  400x50
    Container2 at (0, 50): 400x100
```

### Visual Representation

```
┌────────────────────────────────┐
│ Column (400x150)               │
│ ┌────────────────────────────┐ │
│ │ Container1 (400x50)        │ │ ← offset: (0, 0)
│ │ Red                        │ │
│ └────────────────────────────┘ │
│ ┌────────────────────────────┐ │
│ │ Container2 (400x100)       │ │ ← offset: (0, 50)
│ │ Blue                       │ │
│ │                            │ │
│ └────────────────────────────┘ │
└────────────────────────────────┘
```

---

## Example: Center Layout

### Widget Code

```dart
Center(
  child: Container(width: 100, height: 50),
)
```

### Layout Code Path

**Source:** `shifted_box.dart:459-478`

```dart
class RenderPositionedBox extends RenderAligningShiftedBox {
  @override
  void performLayout() {
    final constraints = this.constraints;
    // e.g., tight(400, 800) from Scaffold

    if (child != null) {
      // STEP 1: LOOSEN constraints
      child!.layout(constraints.loosen(), parentUsesSize: true);
      // loose(0-400, 0-800)

      // STEP 2: Child reports size
      final childSize = child!.size;  // Size(100, 50)

      // STEP 3: Set MY size
      size = constraints.constrain(
        Size(
          shrinkWrapWidth ? childSize.width : double.infinity,
          shrinkWrapHeight ? childSize.height : double.infinity,
        ),
      );
      // shrinkWrapWidth = false (widthFactor is null)
      // shrinkWrapHeight = false (heightFactor is null)
      // size = Size(400, 800)  ← Takes max

      // STEP 4: POSITION child (center it)
      alignChild();
      // offset = Offset((400-100)/2, (800-50)/2) = Offset(150, 375)
    }
  }
}
```

### Complete Flow

```
Scaffold: 400x800
  ↓ tight(400, 800)

Center.performLayout():
  ↓
  STEP 1: LOOSEN & PASS DOWN
    constraints.loosen() = loose(0-400, 0-800)
    child.layout(loose(0-400, 0-800))
      ↓
      Container.performLayout():
        additionalConstraints: tight(100, 50)
        size = Size(100, 50)  ← SIZE UP

  STEP 2: SIZE UP
    childSize = Size(100, 50)

  STEP 3: MY SIZE
    size = constraints.constrain(Size(infinity, infinity))
    size = Size(400, 800)  ← Takes max

  STEP 4: POSITION
    offset = Offset(150, 375)  ← Centered

Result:
  Center: 400x800 (fills screen)
    Container at (150, 375): 100x50
```

---

## Example: Padding Layout

### Widget Code

```dart
Padding(
  padding: EdgeInsets.all(20),
  child: Container(),
)
```

### Layout Code Path

**Source:** `shifted_box.dart:235-249`

```dart
class RenderPadding extends RenderShiftedBox {
  @override
  void performLayout() {
    final constraints = this.constraints;  // tight(400, 800)
    final padding = _resolvedPadding;      // EdgeInsets.all(20)

    if (child == null) {
      size = constraints.constrain(Size(padding.horizontal, padding.vertical));
      return;
    }

    // STEP 1: DEFLATE constraints by padding
    final innerConstraints = constraints.deflate(padding);
    // innerConstraints = tight(360, 760)
    // 400 - 20 - 20 = 360
    // 800 - 20 - 20 = 760

    // STEP 2: PASS DOWN deflated constraints
    child!.layout(innerConstraints, parentUsesSize: true);

    // STEP 3: SIZE UP
    // (child.size = Size(360, 760))

    // STEP 4: POSITION child (offset by padding)
    final BoxParentData childParentData = child!.parentData! as BoxParentData;
    childParentData.offset = Offset(padding.left, padding.top);
    // offset = Offset(20, 20)

    // STEP 5: MY SIZE (includes padding)
    size = constraints.constrain(
      Size(
        padding.horizontal + child!.size.width,
        padding.vertical + child!.size.height,
      ),
    );
    // size = Size(40 + 360, 40 + 760) = Size(400, 800)
  }
}
```

### Complete Flow

```
Parent: 400x800
  ↓ tight(400, 800)

Padding.performLayout():
  ↓
  STEP 1: DEFLATE
    innerConstraints = tight(400, 800).deflate(EdgeInsets.all(20))
    innerConstraints = tight(360, 760)

  STEP 2: PASS DOWN
    child.layout(tight(360, 760))
      ↓
      Container.performLayout():
        size = Size(360, 760)  ← SIZE UP

  STEP 3: POSITION
    child.offset = Offset(20, 20)

  STEP 4: MY SIZE
    size = Size(360 + 40, 760 + 40) = Size(400, 800)

Result:
  Padding: 400x800
    Container at (20, 20): 360x760
```

---

## Common Patterns

### Pattern 1: Pass-Through (Proxy)

```dart
// RenderProxyBox - just passes constraints through
void performLayout() {
  if (child != null) {
    child!.layout(constraints, parentUsesSize: true);
    size = child!.size;  // Take child's size
  } else {
    size = constraints.smallest;  // No child, take minimum
  }
}
```

**Examples:** `Opacity`, `IgnorePointer`, `DecoratedBox`

### Pattern 2: Constrain Child

```dart
// RenderConstrainedBox - adds additional constraints
void performLayout() {
  if (child != null) {
    // Combine parent constraints with additional constraints
    final childConstraints = constraints.enforce(additionalConstraints);
    child!.layout(childConstraints, parentUsesSize: true);
    size = constraints.constrain(child!.size);
  } else {
    size = constraints.constrain(additionalConstraints.constrain(Size.zero));
  }
}
```

**Examples:** `SizedBox`, `ConstrainedBox`, `Container`

### Pattern 3: Loosen Constraints

```dart
// Center/Align - loosens constraints
void performLayout() {
  if (child != null) {
    child!.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(Size(
      shrinkWrapWidth ? child!.size.width : double.infinity,
      shrinkWrapHeight ? child!.size.height : double.infinity,
    ));
  }
}
```

**Examples:** `Center`, `Align`

### Pattern 4: Multi-Child Layout

```dart
// RenderFlex - layouts multiple children
void performLayout() {
  // Layout non-flex children first
  for (child in nonFlexChildren) {
    child.layout(BoxConstraints(0, maxWidth, 0, infinity));
    totalSize += child.size;
  }

  // Calculate remaining space
  remainingSpace = maxHeight - totalSize;

  // Layout flex children
  for (child in flexChildren) {
    final flexSpace = remainingSpace * child.flex / totalFlex;
    child.layout(BoxConstraints.tightFor(height: flexSpace));
  }

  // Position all children
  double position = 0;
  for (child in allChildren) {
    child.parentData.offset = Offset(0, position);
    position += child.size.height;
  }
}
```

**Examples:** `Column`, `Row`, `Flex`

---

## The Rules

### Rule 1: Child Decides Size (Within Constraints)

```dart
// Parent says: "Be between 100-200 wide"
child.layout(BoxConstraints(minWidth: 100, maxWidth: 200));

// Child decides: "I'll be 150"
size = Size(150, 50);
```

### Rule 2: Child Cannot Know Position

```dart
// ❌ Child cannot know its position
void performLayout() {
  // position is set by PARENT, not self
}

// ✅ Child can only set size
void performLayout() {
  size = Size(100, 50);
}
```

### Rule 3: Parent Cannot Force Size (Except with Tight Constraints)

```dart
// ❌ Parent cannot directly set child size
child.size = Size(100, 50);  // Error!

// ✅ Parent can only pass constraints
child.layout(BoxConstraints.tight(Size(100, 50)));
// Now child MUST be 100x50
```

### Rule 4: Layout is Single-Pass

```dart
// NO back-and-forth:
// ❌ Parent: "What size do you want?"
// ❌ Child: "100"
// ❌ Parent: "OK, I'll give you 100"

// YES, single-pass:
// ✅ Parent: "You can be 0-200"
// ✅ Child: "I'll be 100"
// ✅ Done
```

---

## Constraint Helpers

### constraints.loosen()

```dart
BoxConstraints(minWidth: 100, maxWidth: 200, minHeight: 50, maxHeight: 100)
  .loosen()
// = BoxConstraints(minWidth: 0, maxWidth: 200, minHeight: 0, maxHeight: 100)
```

### constraints.tighten()

```dart
BoxConstraints(minWidth: 0, maxWidth: 200, minHeight: 0, maxHeight: 100)
  .tighten(width: 150)
// = BoxConstraints(minWidth: 150, maxWidth: 150, minHeight: 0, maxHeight: 100)
```

### constraints.deflate()

```dart
BoxConstraints.tight(Size(400, 800))
  .deflate(EdgeInsets.all(20))
// = BoxConstraints.tight(Size(360, 760))
```

### constraints.enforce()

```dart
BoxConstraints(minWidth: 0, maxWidth: 400, minHeight: 0, maxHeight: 800)
  .enforce(BoxConstraints.tightFor(width: 100, height: 50))
// = BoxConstraints(minWidth: 100, maxWidth: 100, minHeight: 50, maxHeight: 50)
```

---

## Debugging Layout

### Print constraints and size

```dart
class DebugRenderBox extends RenderBox {
  @override
  void performLayout() {
    print('Constraints: $constraints');
    super.performLayout();
    print('Size: $size');
  }
}
```

### Use Flutter Inspector

- Select widget
- See "Constraints" in details panel
- See "Size" in details panel
- Use "Show Baselines" to see layout

### Add LayoutBuilder

```dart
LayoutBuilder(
  builder: (context, constraints) {
    print('Constraints: $constraints');
    return MyWidget();
  },
)
```

---

## Summary

### The Protocol

```
1. Constraints go down ⬇️
   Parent: child.layout(constraints)

2. Sizes go up ⬆️
   Child: size = Size(w, h)
   Parent: childSize = child.size

3. Parent sets position 📍
   Parent: child.parentData.offset = Offset(x, y)
```

### Who Uses It

✅ ALL RenderObjects
✅ Column, Row, Flex
✅ Container, SizedBox, ConstrainedBox
✅ Center, Align, Padding
✅ Stack, Positioned
✅ Every layout widget in Flutter

### Key Points

- **Single-pass** - No negotiation
- **Child decides size** - Within constraints
- **Parent sets position** - Absolute control
- **Efficient** - No redundant calculations
