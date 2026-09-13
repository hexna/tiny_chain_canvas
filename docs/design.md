# 实现思路

[中文](design.md) | [English](design.en.md)

面向想读懂或动手改造这套画布的人。按「一条数据怎么从 Map 变成屏幕上的卡片」的顺序讲，
每条都对应到具体文件和函数，可以边读边跳。

## 1. 分层：纯函数物理 + 一个 StatefulWidget + 一个 CustomPainter

| 文件 | 职责 | 是否依赖 BuildContext |
| --- | --- | --- |
| `force_layout.dart` | 一帧力导向迭代，原地改坐标 | 否 |
| `layout.dart` | 初始播种：按 level 分列 | 否 |
| `drag_group.dart` | 拖拽分组（后代 / 连通分量 / 整组平移） | 否 |
| `tree_canvas.dart` | 世界坐标、手势翻译、按帧驱动模拟 | 是 |
| `tree_painter.dart` | 只读数据画图 | 否 |

物理是纯函数（`SkillForceLayout.step` 给一组坐标和速度，更新一帧，没有 Widget、没有 `BuildContext`），
所以能直接单测：`test/force_layout_test.dart` 里跑 400 帧断言各层收敛到列锚点，不需要 pump 任何界面。

**为什么整块 `CustomPaint`，而不是一个节点一个 Widget：**

1. 节点和连线必须在同一坐标系里缩放；Widget 方案要自己再实现一遍 transform 和命中判定。
2. 一屏几十个节点时，几十个 RenderObject 的 layout/paint 比一次 paint 里循环画圆角矩形贵。
3. 缩放时文字要跟着缩，`CustomPainter` 里改 `fontSize` 最直接。

代价：可访问性、文字选中、键盘操作都要自己补（本仓库没做）。这类「整块画布」界面值得换。

## 2. 坐标系：world 与 screen 只差一次变换

```
screen = offset + world * scale
world  = (screen - offset) / scale
```

- **平移**：`offset += 指针位移`（屏幕像素，不除 scale）。
- **缩放**：要让锚点 `A` 在屏幕上不动 → 先算 `worldAtA = (A - offset) / scale`，
  再 `offset = A - worldAtA * newScale`。捏合时锚点是两指中点，双击时是落点。
- **命中判定**：把屏幕点转成 world 再比距离，半径用屏幕像素（`kSkillNodeHitRadius = 48`），
  这样放大后热区不会跟着变大。

绘制和命中都只读 `Map<int, Offset> positions`（world 坐标），屏幕坐标是现算的。

## 3. 一帧里发生什么

```dart
_onLayoutTick(elapsed) {
  SkillForceLayout.step(positions, velocities, links, bounds,
      pinned, dt, repulsion, collisionDistance, damping, levels, levelGravity);
  _layoutRepaint.value++;              // 只通知 CustomPaint 重绘，不 setState
  if (几乎不动 && 连续 8 帧) 停 ticker;  // 见第 6 节
}
```

节点集合变化时 `_syncLayout()` 负责对齐：删掉已消失的 id、给新 id 播种（有 `x/y` 就用宿主的，
否则按层级分列），边的签名变了就重置稳定计数。

## 4. 五股力

| 力 | 公式要点 | 作用 |
| --- | --- | --- |
| 两两斥力 | `d̂ * repulsion / d²` | 铺开整张图，`repulsion` 控制疏密 |
| 矩形碰撞 | 比较 `\|dx\|` 与 `\|dy\|` 的重叠量，往重叠小的方向推 | 卡片是矩形不是圆，按矩形算才不会叠 |
| 弹簧 | 只作用于有连边的节点对，`d̂ * (d - 190) * 0.018` | 把父子拉在可读距离 |
| 层级重力 | `(anchorX - x) * g * level`（只作用 x） | 自动分列，见第 5 节 |
| 中心聚拢 | `(中心 - 位置) * 0.00035` | 防止整张图飘出屏幕 |

另外两条保险：速度上限 30、每帧位移上限 18。参数调崩时画面会变难看，但不会瞬间炸飞。
碰撞在受力之后还有一次 `_resolveCollisions` 硬分离，避免两个节点卡在一起互相推不动。

## 5. 层级重力为什么这么写

```dart
forces[id] += Offset((anchorX - position.dx) * levelGravity * level, 0);
// anchorX = originX + (level - 1) * levelColumnGap
```

三个设计点：

1. **乘 `level`**：层级越深拉力越强。深层节点数量多、挤在一起时更容易被带偏，需要更硬的列。
2. **只作用 x**：y 完全交给斥力和碰撞，同一层内部自己排开；否则会被压成一条直线。
3. **`levelGravity = 0` 即关闭**，退化成普通力导向。

播种时列锚点用的是同一组常量（`SkillTreeLayout.columnAnchor`），所以初始位置和重力目标是同一个，
一开始就不会出现「播种在一列、重力想拉去另一列」的抖动。实测 `0.0025` 手感最好，
`0.01` 会把图明显抻成柱子。

## 6. 什么时候停下来

```
maxMovement < 0.35 && maxVelocity < 0.35 连续 8 帧 → 速度清零 + 停 ticker
```

中心聚拢这一项永远不为 0，所以模拟不会自然静止；不停 ticker 就是白白烧帧、耗电。
连续 8 帧是防止某一帧恰好过零造成误判。恢复的时机：节点集合/参数变化、拖拽开始或结束。

## 7. 手势仲裁

| 事件 | 分支 |
| --- | --- |
| 单指按下 | 只有「拖动模式」才去找节点，否则一律当平移 |
| 第二指按下 | 立刻放弃节点拖拽，进入捏合；锚点固定为两指中点 |
| 移动 > 8px | 标记 `_gestureMoved`，抬起时不再判定为点击 |
| 抬起 | 缩放中或有位移 → 直接返回 |
| 单击 | **等 260ms**，窗口内没有第二次点击才回调 `onNodeTap` |
| 双击 | `> 1.5x` 回 1x，否则到 2x，以落点为锚 |

单击延迟是为了不和双击抢手势：原来的写法是「第一次点击立刻打开详情弹窗，
第二次点击再判定为双击」，体验上会闪一下。代价是单击有 260ms 延迟——画布型界面可以接受。

## 8. 拖拽的语义

- 被拖的节点进 `pinned`：`step()` 跳过它的受力计算（只保留 0.98 的速度衰减），
  位置由指针直接写。松手后钉住的是被拖的那个节点。
- **后代不跟着硬移**：只给一次冲量 `-pointerDelta * 0.35`，之后交给弹簧和碰撞。
  所以拖起来是「整块被甩出去 → 回弹稳定」，不是刚性平移，视觉上更像有质量的东西。
- 分组语义在 `SkillDragGroup`：`descendants`（拖父带子）和 `component`（不分方向的连通块），
  默认用前者。
- 碰撞解算里 `pinned` 的节点不参与位移，只把对方推开（`_resolveCollisions` 的三个分支）。
- 松手通过 `onNodeDragEnd` 把分组内每个节点的最终坐标交出去，**存不存、存哪里是宿主的事**。

## 9. 重绘策略

- 模拟每帧改的是同一个 `Map`，用 `ValueNotifier<int>` 挂到 `CustomPainter.repaint` 上触发重绘，
  **不走 setState**——每帧重建整棵 Widget 树是这里最该避免的开销。
- 拖拽、缩放、悬停这类低频变化走 `setState`。
- `SkillTreePainter.shouldRepaint` 直接返回 `true`：画布本来就是整块重绘，
  省掉一堆「哪些字段变了」的比较，也避免漏比导致画面不跟手。

## 10. 不改进源码就能改的东西

| 想改什么 | 用什么 |
| --- | --- |
| 节点按记忆度 / 掌握度上色 | `theme.nodeStyleBuilder` |
| 字体族、字距 | `theme.labelStyle` |
| 按状态改连线（实线 / 虚线） | `theme.linkStyleBuilder` |
| 层级色板 | `theme.levelColors` |
| 画布背景 | `theme.backgroundColors` |
| 参数持久化 | `settingsStore` |
| 位置持久化 | `onNodeDragEnd` |
| 工具栏 / 缩放百分比 | `SkillTreeCanvasController` |
| 只要物理，不要 UI | 直接 `import 'package:skill_tree_canvas/src/force_layout.dart'` |

## 11. 已知取舍

- **复杂度是 O(n²)**：每帧两两算一次。200 个节点以内流畅；再大要换 Barnes–Hut 四叉树近似，
  接口上只需替换 `SkillForceLayout.step` 内部。
- **节点尺寸是常量**（`kSkillNodeWidth` 等）：只有缩放是变量。要支持不同大小的节点，
  碰撞和命中判定都得改成按节点取尺寸。
- **id 是 `int`**：要换成 `String` / UUID，改的是几个 `Map<int, ...>` 的类型。
- **不做持久化**：这是刻意的，画布只负责算和画。
- **没有可访问性与键盘操作**：`CustomPaint` 里画的东西对读屏软件是不存在的。
- **极端参数下不会自动停**：阻尼 ≥ 0.95 时动能衰减太慢，稳定判定可能一直不满足。

## 12. 出处

从卡片大师（SkillGrove）Flutter 版的技能树画布里剥出来的：去掉了 FIRe 记忆度算法、题库、
AI 生成、数据库与 Riverpod 状态管理，只留画布本身。本仓库即它的开源版本，MIT 授权。
