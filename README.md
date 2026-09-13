# skill_tree_canvas

[![CI](https://github.com/hexna/skill_tree_canvas/actions/workflows/ci.yml/badge.svg)](https://github.com/hexna/skill_tree_canvas/actions/workflows/ci.yml)

English | [中文](README.zh-CN.md)

A force-directed skill-tree canvas in pure Flutter, with **zero third-party dependencies**.

![preview](doc/preview.png)

Higher levels sit further right: level gravity scales linearly with `level` and pulls every node
back toward its own column anchor, so different levels separate into non-overlapping columns on
their own — while positions *within* a level are left to the simulation. Edges take the colour of
their parent's level; hovering a node dims the rest and brightens its own edges.

> Source comments are written in Chinese.

## What it does / doesn't do

**Does**: canvas rendering, force-directed layout, level-gravity columns, pan / pinch / double-tap
zoom, hover highlighting, node dragging (dragging a parent flings its descendants outward through
the physics), and a tunable physics panel.

**Doesn't**: mastery or memory algorithms, question banks, AI generation, persistence, routing,
state management. You supply the nodes, a callback decides the colours, and you decide whether
positions get persisted.

## Quick start

```dart
SkillTreeCanvas(
  nodes: const [
    SkillNode(id: 1, label: 'Foundations', level: 1, kind: SkillNodeKind.group),
    SkillNode(id: 2, label: 'Algebra', level: 2),
  ],
  links: const [SkillLink(parentId: 1, childId: 2)],
  onNodeTap: (node) => debugPrint('tapped ${node.label}'),
  onNodeDragEnd: (positions) => savePositions(positions), // up to you
)
```

The widget is only the canvas — toolbars are your job. View operations go through the controller:

```dart
final controller = SkillTreeCanvasController();

SkillTreeCanvas(controller: controller, nodes: nodes, links: links);

controller.resetView();                          // back to 1:1, no offset
controller.zoomTo(2, focalPoint: somePoint);     // zoom around a screen point
controller.setDragNodesEnabled(true);            // switch to "drag nodes" mode
controller.relayout();                           // drop positions, re-seed by level
await controller.openSettingsDialog(context);    // show the physics panel
controller.addListener(() => print(controller.scale));
```

## API

### `SkillTreeCanvas`

| Parameter | Description |
| --- | --- |
| `nodes` / `links` | The graph; `id` just has to be unique |
| `controller` | Optional remote control for the view |
| `theme` | Colours (level palette, node style hook, link style hook, background gradient, label style) |
| `settings` / `settingsStore` | Physics; pass a store and it is read/written for you |
| `showLevelBadge` | Prefix node labels with `level.` |
| `initialDragNodesEnabled` | Start in node-dragging mode |
| `minScale` / `maxScale` | Zoom range, defaults 0.3–4.0 |
| `onNodeTap` / `onBackgroundTap` | Tap callbacks (double-tap zoom never fires them by accident) |
| `onNodeDragEnd` | Fires when a drag ends, with the final world positions of the dragged group |

### `SkillNode` / `SkillLink`

```dart
SkillNode(id: 1, label: 'Algebra', level: 2, x: 480, y: 300, kind: SkillNodeKind.skill)
SkillLink(parentId: 1, childId: 2)   // directed: parent → child
```

`x` / `y` are coordinates you saved yourself; leave them null and the node is seeded by level.

### `SkillTreeCanvasTheme`

| Field | Description |
| --- | --- |
| `levelColors` | Palette for edges and highlighted nodes (8 colours by default) |
| `nodeStyleBuilder` | **The node colour hook** — use it for mastery / memory / progress colours |
| `linkStyleBuilder` | **The link style hook** — use it for continuous-solid / interrupted-dashed edges |
| `backgroundColors` | Canvas gradient, defaults to `surface → surfaceContainerLow` |
| `labelStyle` | Base label style (font family, weight, letter spacing; colour and size are overridden) |

```dart
SkillTreeCanvasTheme(
  nodeStyleBuilder: (node, scheme) => node.memory < 0.5
      ? SkillTreeNodeStyle(background: scheme.errorContainer, foreground: scheme.onErrorContainer)
      : defaultSkillTreeNodeStyle(node, scheme),
)
```

#### Per-link styling (continuous solid / interrupted dashed)

`linkStyleBuilder` returns a `SkillLinkStyle` per link. Leave `color` null to keep the level
palette, and set `dashPattern` for a dashed edge (`[dash, gap, …]`, odd-length patterns repeat
once, SVG style):

```dart
SkillTreeCanvasTheme(
  linkStyleBuilder: (link, scheme) => isBroken(link)
      ? const SkillLinkStyle(dashPattern: [6, 4])          // interrupted
      : const SkillLinkStyle(),                            // continuous (default look)
)
```

Dashes are measured in screen pixels, so the rhythm does not change with zoom. Purely additive:
with `const SkillTreeCanvasTheme()` the canvas renders exactly as before.

One gotcha: a pattern whose dashed part is zero (`dashPattern: [0, 6]`) draws an **invisible
edge** — that matches SVG semantics and is deliberately not special-cased back to a solid line.
`color` is likewise ignored while the canvas is dimming unrelated edges (it uses
`outlineVariant` then), and is still multiplied by the 0.38 / 0.9 highlight opacity otherwise.

### `SkillTreeCanvasSettings`

| Parameter | Default | Feel |
| --- | --- | --- |
| `repulsion` | 2500 | Higher spreads nodes further apart |
| `collisionDistance` | 50 | Gap kept between card rectangles (px) |
| `damping` | 0.78 | Higher means longer-lasting inertia, "heavier" |
| `levelGravity` | 0.0025 | Higher snaps levels harder to their columns; 0 disables it |

`SkillTreeSettingsStore` is a two-method interface (`load` / `save`) — implement it to remember the
user's tuning. An `InMemorySkillTreeSettingsStore` ships with the package.

## Interactions

| Gesture | Behaviour |
| --- | --- |
| Drag empty space | Pan the view |
| Two-finger pinch | Zoom (clamped to `minScale`–`maxScale`) |
| Double tap | 1x ⇄ 2x, anchored on the tap point |
| Single tap on a node | `onNodeTap` (after a 260 ms double-tap window, so it never races the double tap) |
| Mouse hover | Highlight that node, dim the rest |
| Drag mode + drag a node | The node follows your finger; descendants get flung first and spring back |

While dragging, the dragged node is "pinned" (`pinned`) and the rest keep simulating; after
release the pinned node is the one you dragged.

## Layout

```
lib/
├── skill_tree_canvas.dart      # single entry point, exports everything
└── src/
    ├── models.dart             # SkillNode / SkillLink
    ├── layout.dart             # initial seeding: one column per level
    ├── force_layout.dart       # one force-directed step (repulsion / collision / springs / level gravity / centering)
    ├── drag_group.dart         # drag groups (descendants / connected component / translate)
    ├── canvas_settings.dart    # physics settings + persistence interface
    ├── canvas_theme.dart       # colours and the colour hooks
    ├── dash.dart               # pure dash splitting helper
    ├── canvas_controller.dart  # view remote control
    ├── physics_dialog.dart     # the "canvas physics" panel
    ├── tree_canvas.dart        # the widget: gestures, simulation, hit testing
    └── tree_painter.dart       # CustomPainter
```

## Running it

```bash
flutter pub get
flutter test                       # 22 tests: physics / groups / seeding / gestures / persistence

cd example && flutter pub get
flutter create --platforms=linux . # platform shells are not committed; generate what you need
flutter run -d linux               # or any connected device
```

## Docs

- [Design notes](docs/design.en.md): coordinate systems, the five forces, why level gravity
  is written the way it is, gesture arbitration, repaint strategy, extension points, known trade-offs.
- [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

When the tuning feels off:

| Symptom | Turn this |
| --- | --- |
| Nodes clump together | Increase `repulsion` or `collisionDistance` |
| Levels don't separate | Increase `levelGravity`, or fix your `level` values |
| Jitter that never settles | Decrease `damping` (around 0.5 settles fastest) |
| Everything flies away at start | Seed `x` / `y` instead of relying on the layout |

## Porting

- Want the code only: copy `lib/` into your project — there is nothing else to depend on.
- Want package management: use a `path` dependency, or vendor this directory.
- This package was extracted from the skill-tree canvas of SkillGrove (卡片大师), a Flutter app.
  The FIRe memory algorithm, question bank, AI generation, database and Riverpod state were left
  behind — only the canvas is here.

## License

[MIT](LICENSE)
