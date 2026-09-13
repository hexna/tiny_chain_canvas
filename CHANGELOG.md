# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号用 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.2.0] - 2026-09-13

### Added

- `SkillLinkStyle`：单条连线的画法（颜色、线宽、虚线节奏 `dashPattern`）。
- `SkillLinkStyleBuilder` 与 `SkillTreeCanvasTheme.linkStyleBuilder`：连线样式钩子，
  可以按连线状态改画法（例如「连续关系实线、中断关系虚线」）。
- `dashSegments`：把线段按虚线节奏切成若干实线段的纯函数，按屏幕坐标切分，
  节奏不随缩放变化。

**向后兼容：默认主题渲染不变**——`const SkillTreeCanvasTheme()` 仍走实线、层级色板取色、
线宽 1.5，与 0.1.0 完全一致。

## [0.1.0] - 2026-09-12

首个版本，从卡片大师（SkillGrove）Flutter 版的技能树画布中剥离。

### Added

- `SkillTreeCanvas`：力导向技能树画布，支持平移、捏合缩放、双击放大与悬停高亮。
- 层级重力：按 `level` 线性放大，把不同层级的节点自动分成互不重叠的竖列。
- 节点拖拽：拖动父节点时后代被物理甩出去再回弹，结束时通过 `onNodeDragEnd` 交出最终坐标。
- `SkillTreeCanvasController`：重置视图、按锚点缩放、切换拖动模式、重新播种、弹出参数面板。
- `SkillTreeCanvasTheme`：层级色板、节点配色钩子、背景渐变与文字样式。
- `SkillTreeSettingsStore`：物理参数持久化接口，附内存实现。
- `showSkillTreePhysicsDialog`：斥力 / 碰撞距离 / 阻尼 / 层级重力的可视化调节面板。
- 示例工程（`example/`）与 22 个单测 / Widget 测试。

### 相对原实现的改动

- 拖拽改为直接写坐标 + 整块重绘，修掉原版依赖 ticker 重绘通知、模拟停稳后拖动不跟手的问题。
- 单击节点增加 260ms 双击窗口，避免与双击缩放抢手势。
- 抽出宿主接缝：控制器、参数 store、拖拽回调；移除 Riverpod / drift / 路由依赖。
