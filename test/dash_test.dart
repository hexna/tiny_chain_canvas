import 'package:flutter_test/flutter_test.dart';
import 'package:skill_tree_canvas/skill_tree_canvas.dart';

/// 求出若干实线段的总长（屏幕坐标）。
double _totalLength(List<(Offset, Offset)> segments) => segments.fold(
      0,
      (sum, segment) => sum + (segment.$2 - segment.$1).distance,
    );

/// 把一条实线段按向量拆成起止点对，便于断言数值。
void _expectSegment(
  (Offset, Offset) segment,
  Offset from,
  Offset to, {
  double tolerance = 1e-6,
}) {
  expect((segment.$1 - from).distance, lessThan(tolerance));
  expect((segment.$2 - to).distance, lessThan(tolerance));
}

void main() {
  group('dashSegments', () {
    test('零长线段返回空列表', () {
      expect(dashSegments(Offset.zero, Offset.zero, const [6, 4]), isEmpty);
      expect(
        dashSegments(const Offset(3, 5), const Offset(3, 5), const [6, 4]),
        isEmpty,
      );
    });

    test('空 pattern / 长度不足 2 退化成实线', () {
      const from = Offset(1, 2);
      const to = Offset(9, 8);
      for (final pattern in <List<double>>[
        <double>[],
        <double>[6],
        <double>[0],
        <double>[-8],
      ]) {
        final segments = dashSegments(from, to, pattern);
        expect(segments, hasLength(1), reason: 'pattern = $pattern');
        _expectSegment(segments.single, from, to);
      }
    });

    test('非正 pattern 退化成实线', () {
      const from = Offset(0, 0);
      const to = Offset(10, 0);
      for (final pattern in <List<double>>[
        <double>[0, 0],
        <double>[-3, -4],
        <double>[0, -2],
      ]) {
        final segments = dashSegments(from, to, pattern);
        expect(segments, hasLength(1), reason: 'pattern = $pattern');
        _expectSegment(segments.single, from, to);
      }
    });

    test('[6, 4] 切分后的点位、总长守恒且不超过原长', () {
      const from = Offset(0, 0);
      const to = Offset(35, 0);
      final segments = dashSegments(from, to, const [6, 4]);

      expect(segments, hasLength(4));
      _expectSegment(segments[0], const Offset(0, 0), const Offset(6, 0));
      _expectSegment(segments[1], const Offset(10, 0), const Offset(16, 0));
      _expectSegment(segments[2], const Offset(20, 0), const Offset(26, 0));
      // 最后一段被原线段终点截断。
      _expectSegment(segments[3], const Offset(30, 0), const Offset(35, 0));

      final total = _totalLength(segments);
      expect(total, closeTo(23, 1e-9));
      expect(total, lessThanOrEqualTo(35));
    });

    test('首段一定从 from 出发，方向与原线段一致', () {
      const from = Offset(1, 2);
      const to = Offset(4, 6); // 3-4-5 直角三角形，长度 5。
      final segments = dashSegments(from, to, const [2, 3]);

      expect(segments, hasLength(1));
      _expectSegment(segments.first, from, const Offset(2.2, 3.6));
      // 首段方向 = 原线段方向。
      final segmentDirection = segments.first.$2 - segments.first.$1;
      final lineDirection = to - from;
      final cross = segmentDirection.dx * lineDirection.dy -
          segmentDirection.dy * lineDirection.dx;
      expect(cross, closeTo(0, 1e-9));
      expect(
        segmentDirection.dx * lineDirection.dx +
            segmentDirection.dy * lineDirection.dy,
        greaterThan(0),
      );
    });

    test('斜线（负方向）切分正确', () {
      // 从 (10, 0) 往左走到 (0, 0)，长度 10。
      final segments = dashSegments(
        const Offset(10, 0),
        Offset.zero,
        const [3, 2],
      );

      expect(segments, hasLength(2));
      _expectSegment(segments[0], const Offset(10, 0), const Offset(7, 0));
      _expectSegment(segments[1], const Offset(5, 0), const Offset(2, 0));
      expect(_totalLength(segments), closeTo(6, 1e-9));
    });

    test('反斜线（左下方向）切分正确', () {
      // 从 (8, 6) 往左下走到 (0, 0)，长度 10。
      final segments = dashSegments(
        const Offset(8, 6),
        Offset.zero,
        const [4, 1],
      );

      // 依次是 0~4、5~9、10 处正好结束。
      expect(segments, hasLength(2));
      _expectSegment(segments[0], const Offset(8, 6), const Offset(4.8, 3.6));
      _expectSegment(segments[1], const Offset(4, 3), const Offset(0.8, 0.6));
      expect(_totalLength(segments), closeTo(8, 1e-9));
    });

    test('奇数长度 pattern 按 SVG 语义补齐（自身重复一遍）', () {
      const from = Offset(0, 0);
      const to = Offset(20, 0);
      final segments = dashSegments(from, to, const [6, 4, 2]);

      // 补齐后周期 = [6, 4, 2, 6, 4, 2]，总周期 24。
      expect(segments, hasLength(3));
      _expectSegment(segments[0], const Offset(0, 0), const Offset(6, 0));
      _expectSegment(segments[1], const Offset(10, 0), const Offset(12, 0));
      _expectSegment(segments[2], const Offset(18, 0), const Offset(20, 0));
      expect(_totalLength(segments), closeTo(10, 1e-9));
    });

    test('pattern 里含 0 或负数时按 0 处理', () {
      const from = Offset(0, 0);
      const to = Offset(24, 0);
      final segments = dashSegments(from, to, const [6, 0, -4, 4]);

      // [6, 0, 0, 4]：6 实线、0 空白、0 长实线丢弃、4 空白，周期 10。
      expect(segments, hasLength(3));
      _expectSegment(segments[0], const Offset(0, 0), const Offset(6, 0));
      _expectSegment(segments[1], const Offset(10, 0), const Offset(16, 0));
      // 最后一段被原线段终点截断（20 起、本该到 26）。
      _expectSegment(segments[2], const Offset(20, 0), const Offset(24, 0));
    });

    test('pattern 比线段还长时只产出一段', () {
      final segments = dashSegments(
        const Offset(0, 0),
        const Offset(5, 0),
        const [100, 50],
      );
      expect(segments, hasLength(1));
      _expectSegment(segments.single, const Offset(0, 0), const Offset(5, 0));
    });

    test('所有实线段都落在线段范围内，且空白不产生线段', () {
      const from = Offset(-7, 3);
      const to = Offset(11, -9);
      final segments = dashSegments(from, to, const [5, 3, 1, 2, 4]);
      final lineLength = (to - from).distance;

      var covered = 0.0;
      for (final segment in segments) {
        expect(segment.$1, isNot(segment.$2));
        covered += (segment.$2 - segment.$1).distance;
        // 段上任意点到 from 的距离不超过全长，方向也不反向。
        final alongFrom = (segment.$1 - from).distance;
        final alongTo = (segment.$2 - from).distance;
        expect(alongFrom, lessThanOrEqualTo(lineLength + 1e-9));
        expect(alongTo, lessThanOrEqualTo(lineLength + 1e-9));
        expect(alongTo, greaterThanOrEqualTo(alongFrom - 1e-9));
      }
      expect(covered, lessThanOrEqualTo(lineLength + 1e-9));
    });
  });
}
