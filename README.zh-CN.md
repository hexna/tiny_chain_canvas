# skill_tree_canvas

[![CI](https://github.com/hexna/tiny_chain_canvas/actions/workflows/ci.yml/badge.svg)](https://github.com/hexna/tiny_chain_canvas/actions/workflows/ci.yml)

[English](README.md) | 中文

力导向技能树画布，纯 Flutter UI，**零第三方依赖**。

![预览](doc/preview.png)

层级越高越靠右：层级重力按 `level` 线性放大，把节点吸回自己的列锚点，
不同层级的节点自动分成互不重叠的竖列；层内的位置交给力导向模拟自己演化。
连线按父节点的层级上色，悬停某个节点时其余节点变灰、它的连线提亮。

## 它做什么 / 不做什么

**做**：画布渲染、力导向布局、层级重力分列、平移 / 捏合缩放 / 双击放大、
悬停高亮、节点拖拽（连同后代一起被物理甩出去）、可调的物理参数面板。

**不做**：记忆度 / 掌握度算法、题库、AI 生成、数据持久化、路由、状态管理。
节点长什么样由你给，颜色由回调决定，位置由你决定要不要存。

## 快速上手

```dart
SkillTreeCanvas(
  nodes: const [
    SkillNode(id: 1, label: '数学基础', level: 1, kind: SkillNodeKind.group),
    SkillNode(id: 2, label: '代数', level: 2),
  ],
  links: const [SkillLink(parentId: 1, childId: 2)],
  onNodeTap: (node) => debugPrint('点了 ${node.label}'),
  onNodeDragEnd: (positions) => savePositions(positions), // 要不要存由你决定
)
```

组件本身只有画布，工具栏是你的事；视图操作走控制器：

```dart
final controller = SkillTreeCanvasController();

SkillTreeCanvas(controller: controller, nodes: nodes, links: links);

controller.resetView();                          // 回到 1:1 且不偏移
controller.zoomTo(2, focalPoint: somePoint);     // 按屏幕点缩放
controller.setDragNodesEnabled(true);            // 切到「拖动节点」模式
controller.relayout();                           // 丢掉位置，按层级重新播种
await controller.openSettingsDialog(context);    // 弹出物理参数面板
controller.addListener(() => print(controller.scale));
```

## API

### `SkillTreeCanvas`

| 参数 | 说明 |
| --- | --- |
| `nodes` / `links` | 图数据，`id` 唯一即可 |
| `controller` | 可选，视图遥控器 |
| `theme` | 配色（层级色板、节点配色钩子、连线样式钩子、背景渐变、文字样式） |
| `settings` / `settingsStore` | 物理参数；给了 store 就自动读改写 |
| `showLevelBadge` | 节点文字是否带 `层级.` 前缀 |
| `initialDragNodesEnabled` | 初始是否处于拖动节点模式 |
| `minScale` / `maxScale` | 缩放范围，默认 0.3–4.0 |
| `onNodeTap` / `onBackgroundTap` | 单击回调（双击缩放不会误触发） |
| `onNodeDragEnd` | 拖拽结束，交出分组内每个节点的最终世界坐标 |

### `SkillNode` / `SkillLink`

```dart
SkillNode(id: 1, label: '代数', level: 2, x: 480, y: 300, kind: SkillNodeKind.skill)
SkillLink(parentId: 1, childId: 2)   // 有向：parent → child
```

`x` / `y` 是你自己存回来的坐标，为空时按层级播种。

### `SkillTreeCanvasTheme`

| 字段 | 说明 |
| --- | --- |
| `levelColors` | 连线与高亮节点用的层级色板（默认 8 色） |
| `nodeStyleBuilder` | **节点配色钩子**，改它就能按记忆度 / 掌握度 / 完成度上色 |
| `linkStyleBuilder` | **连线样式钩子**，改它就能按连线状态画实线 / 虚线 |
| `backgroundColors` | 画布背景渐变，默认 `surface → surfaceContainerLow` |
| `labelStyle` | 节点文字基准样式（字体族 / 字重 / 字距；颜色与字号由画布覆盖） |

```dart
SkillTreeCanvasTheme(
  nodeStyleBuilder: (node, scheme) => node.memory < 0.5
      ? SkillTreeNodeStyle(background: scheme.errorContainer, foreground: scheme.onErrorContainer)
      : defaultSkillTreeNodeStyle(node, scheme),
)
```

#### 按状态改连线（连续实线 / 中断虚线）

`linkStyleBuilder` 对每条连线返回一个 `SkillLinkStyle`。`color` 留空就仍按层级色板取色；
`dashPattern` 是虚线节奏（`[实线长, 空白长, …]`，奇数长度按 SVG 语义重复一遍补齐）：

```dart
SkillTreeCanvasTheme(
  linkStyleBuilder: (link, scheme) => isBroken(link)
      ? const SkillLinkStyle(dashPattern: [6, 4])          // 中断：虚线
      : const SkillLinkStyle(),                            // 连续：实线（默认观感）
)
```

虚线按屏幕像素切分，所以节奏不随缩放变化。这个钩子是纯增量的：
`const SkillTreeCanvasTheme()` 下的渲染结果与 0.1.0 完全一致。

一个坑：虚线的实线部分为 0 时（如 `dashPattern: [0, 6]`）会画出「看不见的连线」——
这与 SVG 语义一致，不会回退成实线。同理，当画布正在变暗「不相干」的连线时 `color` 会被忽略
（改用 `outlineVariant`）；其余情况下自定义色仍会被乘上 0.38 / 0.9 的高亮透明度。

### `SkillTreeCanvasSettings`

| 参数 | 默认 | 手感 |
| --- | --- | --- |
| `repulsion` | 2500 | 越大节点越分散 |
| `collisionDistance` | 50 | 矩形碰撞留的空隙（px） |
| `damping` | 0.78 | 越大惯性越持久、越重 |
| `levelGravity` | 0.0025 | 越大各层越紧地吸附在竖列里，0 为关闭 |

`SkillTreeSettingsStore` 是个两方法的接口（`load` / `save`），想记住用户调过的参数就实现它；
示例里有个 `InMemorySkillTreeSettingsStore` 可以直接用。

## 交互

| 手势 | 行为 |
| --- | --- |
| 拖空白处 | 平移视图 |
| 双指捏合 | 缩放（钳在 `minScale`–`maxScale`） |
| 双击 | 1x ⇄ 2x，以落点为锚 |
| 单击节点 | `onNodeTap`（等一个 260ms 双击窗口再回调，避免和双击抢手势） |
| 鼠标悬停 | 高亮该节点，其余变灰 |
| 拖动模式 + 拖节点 | 节点跟手，后代先被甩出去再被弹簧拉回来 |

拖动模式下被拖的节点会「钉住」（`pinned`），其余节点照常受力；松手后钉住的是被拖的那个。

## 目录

```
lib/
├── skill_tree_canvas.dart      # 唯一入口，全部导出
└── src/
    ├── models.dart             # SkillNode / SkillLink
    ├── layout.dart             # 初始播种：按层级分列
    ├── force_layout.dart       # 力导向一步迭代（斥力 / 碰撞 / 弹簧 / 层级重力 / 中心聚拢）
    ├── drag_group.dart         # 拖拽分组（后代 / 连通分量 / 整组平移）
    ├── canvas_settings.dart    # 物理参数 + 持久化接口
    ├── canvas_theme.dart       # 配色与配色钩子
    ├── canvas_controller.dart  # 视图遥控器
    ├── physics_dialog.dart     # 「画布物理参数」面板
    ├── tree_canvas.dart        # 画布组件：手势、模拟、命中判定
    └── tree_painter.dart       # CustomPainter
```

## 跑起来

```bash
flutter pub get
flutter test                       # 22 个测试：力导向 / 分组 / 播种 / 手势 / 持久化

cd example && flutter pub get
flutter run -d linux               # 或任意已连接设备
```

## 文档

- [实现思路](docs/design.md)：坐标系、五股力的公式、层级重力为什么这么写、手势仲裁、
  重绘策略、扩展点与已知取舍。想改造这个画布先看它。
- [变更日志](CHANGELOG.md) · [参与开发](CONTRIBUTING.md)

参数调不顺时的速查：

| 现象 | 调什么 |
| --- | --- |
| 节点挤成一坨 | 调大 `repulsion` 或 `collisionDistance` |
| 各层分不开 | 调大 `levelGravity`，或让 `level` 填对 |
| 抖个不停 | 调小 `damping`（0.5 附近最容易停） |
| 一开始就飞很远 | 初始坐标填 `x` / `y`，别全靠播种 |

## 移植

- 只想要代码：把 `lib/` 整个拷进你的工程即可，没有别的依赖。
- 想要包管理：`path` 依赖，或把本目录当 vendor 子包。
- 这个目录是从卡片大师（SkillGrove / Flutter 版）的技能树里剥出来的，剔除了 FIRe 记忆算法、
  题库、AI 生成、数据库与 Riverpod 状态管理，只留画布本身。

## 许可

[MIT](LICENSE)
