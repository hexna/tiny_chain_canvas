import 'package:flutter/material.dart';

import 'canvas_theme.dart';
import 'dash.dart';
import 'models.dart';

/// 节点卡片的基准尺寸（世界坐标，绘制时再乘缩放）。
const double kSkillNodeWidth = 116;
const double kSkillNodeHeight = 56;
const double kSkillNodeHighlightedWidth = 148;
const double kSkillNodeHighlightedHeight = 72;

/// 命中判定的半径（屏幕坐标，不随缩放变化）。
const double kSkillNodeHitRadius = 48;

/// 画布绘制：背景渐变 → 连线 → 节点卡片。
class SkillTreePainter extends CustomPainter {
  SkillTreePainter({
    required this.nodes,
    required this.links,
    required this.theme,
    required this.colorScheme,
    required this.offset,
    required this.scale,
    required this.positions,
    required this.highlightedId,
    required this.textDirection,
    this.showLevelBadge = true,
    super.repaint,
  }) : _nodeMap = {for (final node in nodes) node.id: node};

  final List<SkillNode> nodes;
  final List<SkillLink> links;
  final SkillTreeCanvasTheme theme;
  final ColorScheme colorScheme;

  /// 视图平移与缩放。
  final Offset offset;
  final double scale;

  /// 当前生效的世界坐标（含正在拖拽的节点）。
  final Map<int, Offset> positions;

  /// 高亮节点（悬停或拖拽中）：其余节点变灰、它的连线提亮。
  final int? highlightedId;
  final TextDirection textDirection;
  final bool showLevelBadge;

  final Map<int, SkillNode> _nodeMap;

  Offset _worldPosition(SkillNode node) =>
      positions[node.id] ?? node.position ?? Offset.zero;

  Offset _screenPosition(SkillNode node) =>
      offset + _worldPosition(node) * scale;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: theme.backgroundFor(colorScheme),
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    for (final link in links) {
      final parent = _nodeMap[link.parentId];
      final child = _nodeMap[link.childId];
      if (parent == null || child == null) continue;
      final connected = highlightedId == null ||
          link.parentId == highlightedId ||
          link.childId == highlightedId;
      final edgeLevel = highlightedId == null
          ? parent.level
          : _nodeMap[highlightedId]?.level ?? parent.level;
      final style = theme.linkStyleFor(link, colorScheme);
      final edgePaint = Paint()
        ..color = connected
            ? (style.color ?? theme.levelColor(edgeLevel))
                .withOpacity(highlightedId == null ? 0.38 : 0.9)
            : colorScheme.outlineVariant.withOpacity(0.22)
        ..strokeWidth = style.strokeWidth;
      final from = _screenPosition(parent);
      final to = _screenPosition(child);
      final dashPattern = style.dashPattern;
      if (dashPattern == null) {
        canvas.drawLine(from, to, edgePaint);
      } else {
        for (final segment in dashSegments(from, to, dashPattern)) {
          canvas.drawLine(segment.$1, segment.$2, edgePaint);
        }
      }
    }

    for (final node in nodes) {
      final isHighlighted = node.id == highlightedId;
      final dimmed = highlightedId != null && !isHighlighted;
      final style = theme.styleFor(node, colorScheme);
      final color = dimmed
          ? colorScheme.surfaceContainerHighest
          : isHighlighted
              ? theme.levelColor(node.level)
              : style.background;
      final foreground = dimmed
          ? colorScheme.onSurfaceVariant
          : isHighlighted
              ? colorScheme.onPrimary
              : style.foreground;

      final center = _screenPosition(node);
      final width =
          (isHighlighted ? kSkillNodeHighlightedWidth : kSkillNodeWidth) *
              scale;
      final height =
          (isHighlighted ? kSkillNodeHighlightedHeight : kSkillNodeHeight) *
              scale;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: width, height: height),
        Radius.circular((isHighlighted ? 22 : 18) * scale),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = color.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawRRect(rect, Paint()..color = color);
      canvas.drawRRect(
        rect,
        Paint()
          ..color =
              isHighlighted ? colorScheme.primary : colorScheme.outlineVariant
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlighted ? 2.5 : 1,
      );

      final text = TextPainter(
        text: TextSpan(
          text: showLevelBadge ? '${node.level}. ${node.label}' : node.label,
          style: (theme.labelStyle ?? const TextStyle()).copyWith(
            color: foreground,
            fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
            fontSize: (isHighlighted ? 13 : 12) * scale,
          ),
        ),
        textDirection: textDirection,
        maxLines: 2,
        textAlign: TextAlign.center,
      )..layout(maxWidth: width - 22);
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }
  }

  /// 画布是整块重绘的：模拟运行时本来就每帧重画，拖拽时也要立刻跟上，
  /// 所以不做增量比较。
  @override
  bool shouldRepaint(covariant SkillTreePainter oldDelegate) => true;
}
