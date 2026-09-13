import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// 把一条线段按 [pattern]（实线长 / 空白长交替）切成若干实线段。
///
/// 返回一串 `(起点, 终点)`，直接喂给 `Canvas.drawLine`。约定：
/// - [pattern] 为空、长度不足 2、或所有值都 `<= 0` → 原样返回 `[(from, to)]`
///   （也就是实线）。
/// - 长度为奇数时，按 SVG 语义把自己重复一遍补成偶数。
/// - 单个值 `<= 0` 当 `0` 处理（0 长的实线段会被丢掉、0 长的空白段不占距离）。
/// - [from] == [to]（零长线段）→ 返回空列表。
///
/// 切分在**屏幕坐标**下进行，所以虚线节奏不随缩放变化（画布当前就是在屏幕
/// 坐标下描线）。
///
/// 仅画布内部与需要自绘连线的宿主使用；普通使用 `SkillLinkStyle.dashPattern`
/// 即可。
List<(Offset, Offset)> dashSegments(
    Offset from, Offset to, List<double> pattern) {
  final delta = to - from;
  final totalLength = delta.distance;

  // 零长线段没有可切的东西。
  if (totalLength == 0) return const [];

  final normalized = [
    for (final value in pattern) value.isFinite && value > 0 ? value : 0.0,
  ];

  // 空、长度不足 2、或完全没有正数 → 实线。
  if (normalized.length < 2 || normalized.every((value) => value == 0)) {
    return [(from, to)];
  }

  // 奇数长度按 SVG 语义重复一遍补齐，这样「实线 / 空白」仍然交替。
  //
  // 注意：这一步对结果没有任何影响——下面的循环是 `cycle[index % cycle.length]`，
  // 而 `2n` 恒为 `n` 的倍数，补齐前后每个 index 取到的元素完全相同。写上它只是为了让
  // 「SVG 奇数长度自重复」这条语义在代码里显式可见（保留行为，不改判定）。
  final cycle =
      normalized.length.isOdd ? [...normalized, ...normalized] : normalized;

  final direction = delta / totalLength;
  final segments = <(Offset, Offset)>[];
  var travelled = 0.0;
  var index = 0;

  while (travelled < totalLength) {
    final step = cycle[index % cycle.length];
    final isDash = index.isEven;

    if (isDash) {
      final end = math.min(travelled + step, totalLength);
      // 0 长的实线段直接丢掉；否则记下这一段。
      if (end > travelled) {
        segments.add((from + direction * travelled, from + direction * end));
      }
      travelled = end;
    } else {
      travelled += step;
    }

    index++;
  }

  return segments;
}
