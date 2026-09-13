# Design notes

[中文](design.md) | English

For anyone who wants to read or reshape this canvas. It follows the path a single piece of data takes
from a `Map` to a card on screen, and every point maps to a concrete file or function, so you can jump
around while reading.

## 1. Layering: pure-function physics + one StatefulWidget + one CustomPainter

| File | Responsibility | Needs BuildContext |
| --- | --- | --- |
| `force_layout.dart` | one force-directed step, mutates positions in place | no |
| `layout.dart` | initial seeding: one column per level | no |
| `drag_group.dart` | drag groups (descendants / connected component / translate) | no |
| `tree_canvas.dart` | world coordinates, gesture translation, driving the simulation | yes |
| `tree_painter.dart` | paints from read-only data | no |

The physics is a pure function — `SkillForceLayout.step` takes positions and velocities and advances one
frame, with no widgets and no `BuildContext` — which makes it directly testable.
`test/force_layout_test.dart` runs 400 frames and asserts each level converges on its column anchor,
without pumping a single widget.

**Why one big `CustomPaint` instead of a widget per node:**

1. Nodes and edges must zoom in the same coordinate space; the widget approach means reimplementing the
   transform and hit testing by hand.
2. With a few dozen nodes on screen, laying out and painting dozens of RenderObjects costs more than a
   single paint pass that draws rounded rectangles in a loop.
3. Labels have to scale with the zoom, and changing `fontSize` inside a `CustomPainter` is the most
   direct way to do it.

The cost: accessibility, text selection and keyboard operation are all on you (this package does not do
them). For a full-bleed canvas surface, that trade is worth it.

## 2. Coordinate systems: world and screen differ by one transform

```
screen = offset + world * scale
world  = (screen - offset) / scale
```

- **Pan**: `offset += pointer delta` (screen pixels, not divided by scale).
- **Zoom**: to keep anchor `A` fixed on screen, first compute `worldAtA = (A - offset) / scale`, then
  `offset = A - worldAtA * newScale`. For a pinch the anchor is the midpoint of the two fingers; for a
  double tap it is the tap point.
- **Hit testing**: convert the screen point to world and compare distances, with the radius kept in
  screen pixels (`kSkillNodeHitRadius = 48`), so hit areas do not grow when you zoom in.

Painting and hit testing read the same `Map<int, Offset> positions` (world coordinates); screen
coordinates are derived on the fly.

## 3. What happens in one frame

```dart
_onLayoutTick(elapsed) {
  SkillForceLayout.step(positions, velocities, links, bounds,
      pinned, dt, repulsion, collisionDistance, damping, levels, levelGravity);
  _layoutRepaint.value++;              // repaint the CustomPaint only, no setState
  if (barely moving && 8 frames in a row) stop the ticker;   // see section 6
}
```

When the node set changes, `_syncLayout()` reconciles: it drops ids that are gone, seeds new ones (the
host's `x`/`y` if present, otherwise one column per level), and resets the stability counter whenever the
edge signature changes.

## 4. The five forces

| Force | Formula | Purpose |
| --- | --- | --- |
| Pairwise repulsion | `d̂ * repulsion / d²` | spreads the graph out; `repulsion` sets the density |
| Rectangle collision | compare the `\|dx\|` and `\|dy\|` overlaps, push along the smaller one | cards are rectangles, not circles — rectangle maths is what keeps them from stacking |
| Springs | across links only, `d̂ * (d - 190) * 0.018` | keeps parents and children at a readable distance |
| Level gravity | `(anchorX - x) * g * level` (x axis only) | automatic columns, see section 5 |
| Centering | `(center - position) * 0.00035` | stops the whole graph from drifting off screen |

Two more guard rails: velocity is capped at 30 and per-frame displacement at 18. With badly tuned
parameters the picture gets ugly, but it never explodes. After the force pass a hard `_resolveCollisions`
step runs, so two nodes cannot wedge against each other and stall.

## 5. Why level gravity is written that way

```dart
forces[id] += Offset((anchorX - position.dx) * levelGravity * level, 0);
// anchorX = originX + (level - 1) * levelColumnGap
```

Three deliberate choices:

1. **Multiplied by `level`**: the deeper the level, the stronger the pull. Deep levels hold more nodes and
   are easier to knock off course, so their columns have to be stiffer.
2. **Only the x axis**: y is left entirely to repulsion and collision, so nodes within a level spread out
   on their own. Applying gravity on both axes would squash every level into a single line.
3. **`levelGravity = 0` disables it**, degrading gracefully to a plain force-directed layout.

Seeding uses the same constants (`SkillTreeLayout.columnAnchor`), so the initial column and the gravity
target are the same thing — there is no "seeded in one column, gravity pulling toward another" jitter at
startup. In practice `0.0025` feels best; `0.01` visibly stretches the graph into pillars.

## 6. When it stops

```
maxMovement < 0.35 && maxVelocity < 0.35 for 8 consecutive frames → zero velocities, stop the ticker
```

Centering is never exactly zero, so the simulation never comes to rest on its own; leaving the ticker
running would just burn frames and battery. Eight consecutive frames guards against a single
zero-crossing frame being mistaken for rest. It restarts when the node set or settings change, or when a
drag begins or ends.

## 7. Gesture arbitration

| Event | Branch |
| --- | --- |
| First pointer down | Only look for a node in "drag mode"; otherwise treat it as a pan |
| Second pointer down | Abandon any node drag immediately and switch to pinch; the anchor is the midpoint of the two fingers |
| Movement > 8px | Set `_gestureMoved`, and no longer treat the release as a tap |
| Pointer up | If we were scaling, or the gesture moved, return early |
| Single tap | **Wait 260 ms**; only call `onNodeTap` if no second tap arrives in that window |
| Double tap | `> 1.5x` goes back to 1x, otherwise to 2x, anchored on the tap point |

The single-tap delay exists so it does not race the double tap. The original code opened the detail
sheet on the first tap and only recognised the double tap on the second one, which flashed. The price is
a 260 ms delay on single taps — acceptable for a canvas surface.

## 8. Drag semantics

- The dragged node is `pinned`: `step()` skips its force integration (keeping only a 0.98 velocity decay)
  and the pointer writes its position directly. After release, the pinned node is the one you dragged.
- **Descendants are not translated rigidly**: they get a single impulse of `-pointerDelta * 0.35`, and the
  springs and collisions do the rest. So a drag reads as "fling the subtree, let it spring back" rather
  than as a rigid translation — it feels like it has mass.
- Group semantics live in `SkillDragGroup`: `descendants` (drag a parent, take its children) and
  `component` (the connected block, direction-agnostic). The default is `descendants`.
- In collision resolution, `pinned` nodes never move; they only push the other node away (the three
  branches in `_resolveCollisions`).
- On release, `onNodeDragEnd` hands over the final world positions of the whole group. **Whether and
  where to persist them is the host's decision.**

## 9. Repaint strategy

- Each simulation frame mutates the same `Map` and bumps a `ValueNotifier<int>` wired to
  `CustomPainter.repaint`. It deliberately **does not go through setState** — rebuilding the whole widget
  tree every frame is the single biggest cost to avoid here.
- Low-frequency changes (dragging, zooming, hover) go through `setState`.
- `SkillTreePainter.shouldRepaint` simply returns `true`: the canvas repaints as a whole anyway, and this
  avoids a pile of fragile field comparisons — including the ones that would silently skip a repaint and
  make dragging feel laggy.

## 10. Things you can change without touching the source

| Want to change | Use |
| --- | --- |
| Node colours by memory / mastery / progress | `theme.nodeStyleBuilder` |
| Font family, letter spacing | `theme.labelStyle` |
| Per-link solid / dashed edges | `theme.linkStyleBuilder` |
| Level palette | `theme.levelColors` |
| Canvas background | `theme.backgroundColors` |
| Persisting physics settings | `settingsStore` |
| Persisting positions | `onNodeDragEnd` |
| Toolbars, zoom percentage | `SkillTreeCanvasController` |
| Physics only, no UI | `import 'package:skill_tree_canvas/src/force_layout.dart'` directly |

## 11. Known trade-offs

- **O(n²)**: every frame compares every pair. Smooth up to roughly 200 nodes; beyond that you want a
  Barnes–Hut quadtree approximation, which only means replacing the internals of `SkillForceLayout.step`.
- **Node size is a constant** (`kSkillNodeWidth` and friends); only the zoom varies. Supporting
  differently sized nodes means changing both the collision maths and hit testing.
- **Ids are `int`**: switching to `String` or UUIDs means changing the type of a handful of
  `Map<int, ...>` fields.
- **No persistence by design**: the canvas only computes and paints.
- **No accessibility or keyboard support**: anything painted inside a `CustomPaint` does not exist as far
  as screen readers are concerned.
- **Extreme settings never settle**: with damping ≥ 0.95 kinetic energy decays too slowly and the
  stability test may never be satisfied.

## 12. Where this came from

Extracted from the skill-tree canvas of SkillGrove (卡片大师), a Flutter app. The FIRe memory algorithm,
the question bank, AI generation, the database and Riverpod state management were all left behind; only
the canvas is here. This repository is its open-source release, under MIT.
