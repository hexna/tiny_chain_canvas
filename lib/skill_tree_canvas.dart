/// 技能树画布：力导向布局 + 层级重力分列 + 平移缩放的纯 UI 实现。
///
/// 不依赖任何状态管理、数据库或网络库，只有 Flutter 本身。
library;

export 'src/canvas_controller.dart';
export 'src/canvas_settings.dart';
export 'src/canvas_theme.dart';
export 'src/dash.dart';
export 'src/drag_group.dart';
export 'src/force_layout.dart';
export 'src/layout.dart';
export 'src/models.dart';
export 'src/physics_dialog.dart';
export 'src/tree_canvas.dart';
export 'src/tree_painter.dart'
    show
        SkillTreePainter,
        kSkillNodeWidth,
        kSkillNodeHeight,
        kSkillNodeHighlightedWidth,
        kSkillNodeHighlightedHeight,
        kSkillNodeHitRadius;
