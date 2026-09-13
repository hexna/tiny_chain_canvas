import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skill_tree_canvas/skill_tree_canvas.dart';

const _nodes = [
  SkillNode(id: 1, label: '根节点', level: 1),
  SkillNode(id: 2, label: '子节点 A', level: 2),
  SkillNode(id: 3, label: '子节点 B', level: 2),
];

const _links = [
  SkillLink(parentId: 1, childId: 2),
  SkillLink(parentId: 1, childId: 3),
];

Widget _host({
  SkillTreeCanvasController? controller,
  SkillTreeSettingsStore? store,
  SkillTreeCanvasTheme theme = const SkillTreeCanvasTheme(),
  ValueChanged<SkillNode>? onNodeTap,
  VoidCallback? onBackgroundTap,
  ValueChanged<Map<int, Offset>>? onNodeDragEnd,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SkillTreeCanvas(
        nodes: _nodes,
        links: _links,
        controller: controller,
        theme: theme,
        settingsStore: store,
        onNodeTap: onNodeTap,
        onBackgroundTap: onBackgroundTap,
        onNodeDragEnd: onNodeDragEnd,
      ),
    ),
  );
}

Future<void> _runFrames(WidgetTester tester, int frames) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 只记录 `drawLine` 的假画布：其余绘制调用一律忽略。
/// 连线段是画布里唯一会调用 `drawLine` 的东西，所以拿它验连线画法最省事。
class _RecordingCanvas implements Canvas {
  final List<(Offset, Offset, Paint)> lines = [];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((p1, p2, paint));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('模拟跑一阵后画面稳定，没有异常', (tester) async {
    await tester.pumpWidget(_host());
    await _runFrames(tester, 400);

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('拖动空白处平移视图（重置后回原点）', (tester) async {
    final controller = SkillTreeCanvasController();
    await tester.pumpWidget(_host(controller: controller));
    await _runFrames(tester, 2);

    await tester.dragFrom(const Offset(700, 550), const Offset(-120, -60));
    await tester.pump(const Duration(milliseconds: 16));

    expect(controller.offset.dx, closeTo(-120, 0.01));
    expect(controller.offset.dy, closeTo(-60, 0.01));

    controller.resetView();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.scale, 1);
    expect(controller.offset, Offset.zero);
  });

  testWidgets('双击放大到 2x，再双击回到 1x', (tester) async {
    final controller = SkillTreeCanvasController();
    await tester.pumpWidget(_host(controller: controller));
    await _runFrames(tester, 2);

    await tester.tapAt(const Offset(700, 550));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(700, 550));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.scale, 2.0);

    await tester.tapAt(const Offset(700, 550));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(700, 550));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.scale, 1.0);
  });

  testWidgets('单击节点回调 onNodeTap，空白处回调 onBackgroundTap', (tester) async {
    SkillNode? tapped;
    var background = 0;
    await tester.pumpWidget(_host(
      onNodeTap: (node) => tapped = node,
      onBackgroundTap: () => background++,
    ));
    await _runFrames(tester, 2);

    // 根节点按初始播种位置画在 (220, 300) 附近。
    await tester.tapAt(const Offset(220, 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tapped?.id, 1);
    expect(background, 0);

    await tester.tapAt(const Offset(760, 40));
    await tester.pump(const Duration(milliseconds: 300));
    expect(background, 1);
  });

  testWidgets('窗口小于双击阈值时只认单击', (tester) async {
    SkillNode? tapped;
    await tester.pumpWidget(_host(onNodeTap: (node) => tapped = node));
    await _runFrames(tester, 2);

    await tester.tapAt(const Offset(220, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(220, 300));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tapped?.id, 1);
  });

  testWidgets('改物理参数会写回 store', (tester) async {
    final controller = SkillTreeCanvasController();
    final store = InMemorySkillTreeSettingsStore();
    await tester.pumpWidget(_host(controller: controller, store: store));
    await _runFrames(tester, 2);

    await controller.applySettings(const SkillTreeCanvasSettings(
      repulsion: 8000,
      collisionDistance: 70,
      damping: 0.9,
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(controller.settings.repulsion, 8000);
    expect(store.settings.repulsion, 8000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开启拖动模式后可以拖走节点，并交出最终坐标', (tester) async {
    final controller = SkillTreeCanvasController();
    Map<int, Offset>? moved;
    await tester.pumpWidget(_host(
      controller: controller,
      onNodeDragEnd: (positions) => moved = positions,
    ));
    await _runFrames(tester, 2);

    expect(controller.dragNodesEnabled, isFalse);
    controller.setDragNodesEnabled(true);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.dragNodesEnabled, isTrue);

    await tester.dragFrom(const Offset(220, 300), const Offset(90, 0));
    await tester.pump(const Duration(milliseconds: 16));

    expect(moved, isNotNull);
    expect(moved!.containsKey(1), isTrue);
    // 拖动节点时不该把视图也平移走。
    expect(controller.offset, Offset.zero);
  });

  testWidgets('relayout 把所有节点按层级重新播种', (tester) async {
    final controller = SkillTreeCanvasController();
    await tester.pumpWidget(_host(controller: controller));
    await _runFrames(tester, 120);

    controller.relayout();
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });

  test('默认主题的连线画法与改动前一致（实线 / 层级色 0.38 / 线宽 1.5）', () {
    const theme = SkillTreeCanvasTheme();
    const scheme = ColorScheme.light();
    final canvas = _RecordingCanvas();

    SkillTreePainter(
      nodes: _nodes,
      links: _links,
      theme: theme,
      colorScheme: scheme,
      offset: Offset.zero,
      scale: 1,
      positions: const {
        1: Offset(200, 200),
        2: Offset(320, 160),
        3: Offset(320, 260),
      },
      highlightedId: null,
      textDirection: TextDirection.ltr,
    ).paint(canvas, const Size(600, 480));

    // 两条连线各画一笔，没有因为虚线被切开。
    expect(canvas.lines, hasLength(2));
    for (final line in canvas.lines) {
      expect(line.$1, isNot(line.$2));
      expect(line.$3.strokeWidth, 1.5);
    }
    // 父节点是 level 1，取色板第一色；无高亮时透明度 0.38。
    expect(canvas.lines.first.$3.color,
        kSkillTreeLevelColors[0].withOpacity(0.38));
  });

  test('自定义 linkStyleBuilder 的颜色与线宽真的落到连线 Paint 上', () {
    const customColor = Color(0xFF123456);
    final canvas = _RecordingCanvas();

    SkillTreePainter(
      nodes: _nodes,
      links: _links,
      theme: SkillTreeCanvasTheme(
        linkStyleBuilder: (link, scheme) => const SkillLinkStyle(
          color: customColor,
          strokeWidth: 3,
        ),
      ),
      colorScheme: const ColorScheme.light(),
      offset: Offset.zero,
      scale: 1,
      positions: const {
        1: Offset(200, 200),
        2: Offset(320, 160),
        3: Offset(320, 260),
      },
      highlightedId: null,
      textDirection: TextDirection.ltr,
    ).paint(canvas, const Size(600, 480));

    // 实线：每条连线仍然只画一笔。
    expect(canvas.lines, hasLength(2));
    for (final line in canvas.lines) {
      // 自定义线宽必须原样落到 Paint 上（不能被写死的 1.5 覆盖）。
      expect(line.$3.strokeWidth, 3);
      // 自定义色必须被采用；无高亮时仍套 0.38 透明度。
      expect(line.$3.color, customColor.withOpacity(0.38));
    }
  });

  test('dashPattern 生效时逐段描线，为空时仍是一笔', () {
    int drawLineCount(SkillLinkStyle style) {
      final canvas = _RecordingCanvas();
      SkillTreePainter(
        nodes: _nodes,
        links: const [SkillLink(parentId: 1, childId: 2)],
        theme: SkillTreeCanvasTheme(
          linkStyleBuilder: (link, scheme) => style,
        ),
        colorScheme: const ColorScheme.light(),
        offset: Offset.zero,
        scale: 1,
        positions: const {1: Offset(200, 200), 2: Offset(320, 160)},
        highlightedId: null,
        textDirection: TextDirection.ltr,
      ).paint(canvas, const Size(600, 480));
      return canvas.lines.length;
    }

    expect(drawLineCount(const SkillLinkStyle()), 1);
    expect(
      drawLineCount(const SkillLinkStyle(dashPattern: [6, 4])),
      greaterThan(1),
    );
  });

  test('默认主题的 linkStyleBuilder 返回实线样式', () {
    const theme = SkillTreeCanvasTheme();
    final style = theme.linkStyleBuilder(
      const SkillLink(parentId: 1, childId: 2),
      const ColorScheme.light(),
    );

    expect(style.dashPattern, isNull);
    expect(style.color, isNull);
    expect(style.strokeWidth, 1.5);
  });

  testWidgets('带 dashPattern 的 linkStyleBuilder 能正常渲染，不抛异常', (tester) async {
    await tester.pumpWidget(_host(
      theme: SkillTreeCanvasTheme(
        linkStyleBuilder: (link, scheme) =>
            const SkillLinkStyle(dashPattern: [6, 4]),
      ),
    ));
    await _runFrames(tester, 240);

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('按连线状态切换实线 / 虚线也能量好', (tester) async {
    await tester.pumpWidget(_host(
      theme: SkillTreeCanvasTheme(
        linkStyleBuilder: (link, scheme) => link.childId == 2
            ? const SkillLinkStyle(dashPattern: [6, 4])
            : const SkillLinkStyle(
                color: Color(0xFF00ACC1),
                strokeWidth: 2.5,
              ),
      ),
    ));
    await _runFrames(tester, 240);

    expect(tester.takeException(), isNull);
    expect(find.byType(SkillTreeCanvas), findsOneWidget);
  });
}
