import 'package:flutter/material.dart';

import 'models.dart';

/// 节点的前景 / 背景配色。
@immutable
class SkillTreeNodeStyle {
  const SkillTreeNodeStyle({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

/// 节点配色钩子：想按「记忆度 / 掌握度 / 状态」上色时改写它。
typedef SkillTreeNodeStyleBuilder = SkillTreeNodeStyle Function(
  SkillNode node,
  ColorScheme scheme,
);

/// 一条连线的画法。颜色为空时按层级色板取色（也就是现在默认的行为）。
@immutable
class SkillLinkStyle {
  const SkillLinkStyle({
    this.color,
    this.strokeWidth = 1.5,
    this.dashPattern,
  });

  /// 为空 → 用 `SkillTreeCanvasTheme.levelColor(level)`。
  ///
  /// 两个隐含行为：
  /// - 连线处于「不相干 / 变暗」状态（当前高亮的是别的节点）时**始终**用
  ///   `colorScheme.outlineVariant.withOpacity(0.22)`，这里的自定义色会被忽略；
  /// - 连线相连 / 高亮时，自定义色仍会被套上透明度：无高亮 0.38、有高亮 0.9。
  final Color? color;

  /// 线宽，默认 1.5（与改动前的写死值一致）。任何状态下都原样使用。
  final double strokeWidth;

  /// 虚线节奏：实线长 / 空白长交替（如 `[6, 4]`）。为空或长度不足 / 全非正 → 实线。
  /// 奇数长度按 SVG 语义重复一遍补齐。
  final List<double>? dashPattern;
}

/// 连线配色 / 线型钩子：想按「连线状态」改画法时改写它。
///
/// 典型用法是「连续关系画实线、中断关系画虚线」：
/// ```dart
/// SkillLinkStyle myLinkStyle(SkillLink link, ColorScheme scheme) {
///   final broken = isBroken(link); // 由宿主自己判断
///   return broken
///       ? const SkillLinkStyle(dashPattern: [6, 4])
///       : const SkillLinkStyle(); // 实线，颜色仍走层级色板
/// }
/// ```
typedef SkillLinkStyleBuilder = SkillLinkStyle Function(
  SkillLink link,
  ColorScheme scheme,
);

/// 默认连线样式：实线、不覆盖颜色（即按层级色板取色）。
SkillLinkStyle defaultSkillLinkStyle(SkillLink link, ColorScheme scheme) =>
    const SkillLinkStyle();

/// 默认层级配色（level 1 起，超出范围的层级取最后一色）。
const List<Color> kSkillTreeLevelColors = [
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFB8C00),
  Color(0xFF8E24AA),
  Color(0xFF00ACC1),
  Color(0xFFD81B60),
  Color(0xFF6D4C41),
];

/// 默认节点配色：分组节点用 tertiaryContainer，普通节点用 surfaceContainerHighest。
/// 想「默认之外再加一种状态色」时可以直接复用它在分支里：
/// ```dart
/// SkillTreeNodeStyle myBuilder(SkillNode node, ColorScheme scheme) =>
///     shouldHighlight(node) ? myStyle : defaultSkillTreeNodeStyle(node, scheme);
/// ```
SkillTreeNodeStyle defaultSkillTreeNodeStyle(
  SkillNode node,
  ColorScheme scheme,
) =>
    node.kind == SkillNodeKind.group
        ? SkillTreeNodeStyle(
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
          )
        : SkillTreeNodeStyle(
            background: scheme.surfaceContainerHighest,
            foreground: scheme.onSurfaceVariant,
          );

/// 画布主题。默认全部跟随 [ColorScheme]，只覆盖需要改的部分即可。
@immutable
class SkillTreeCanvasTheme {
  const SkillTreeCanvasTheme({
    this.levelColors = kSkillTreeLevelColors,
    this.nodeStyleBuilder = defaultSkillTreeNodeStyle,
    this.linkStyleBuilder = defaultSkillLinkStyle,
    this.backgroundColors,
    this.labelStyle,
  });

  /// 连线与高亮节点用的层级色板。
  final List<Color> levelColors;

  /// 节点配色钩子。
  final SkillTreeNodeStyleBuilder nodeStyleBuilder;

  /// 连线样式钩子。默认 [defaultSkillLinkStyle]，与改动前的渲染完全一致
  /// （实线、层级色板取色、线宽 1.5）。
  final SkillLinkStyleBuilder linkStyleBuilder;

  /// 画布背景渐变（左上 → 右下）。为空时取 `surface → surfaceContainerLow`。
  final List<Color>? backgroundColors;

  /// 节点文字的基准样式。只用来带字体族 / 字重 / 字距这类设置，
  /// 颜色与字号由画布按缩放和高亮状态覆盖。
  final TextStyle? labelStyle;

  Color levelColor(int level) =>
      levelColors[(level - 1).clamp(0, levelColors.length - 1)];

  List<Color> backgroundFor(ColorScheme scheme) =>
      backgroundColors ?? [scheme.surface, scheme.surfaceContainerLow];

  SkillTreeNodeStyle styleFor(SkillNode node, ColorScheme scheme) =>
      nodeStyleBuilder(node, scheme);

  SkillLinkStyle linkStyleFor(SkillLink link, ColorScheme scheme) =>
      linkStyleBuilder(link, scheme);
}
