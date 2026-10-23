import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class TimelineScrollIntentAction extends ScrollAction {
  TimelineScrollIntentAction({
    required this.controller,
    required this.onUserIntent,
    required this.onNoMovement,
  });

  final ScrollController controller;
  final VoidCallback onUserIntent;
  final VoidCallback onNoMovement;

  @override
  void invoke(ScrollIntent intent, [BuildContext? context]) {
    if (context == null) {
      super.invoke(intent, context);
      return;
    }
    if (axisDirectionToAxis(intent.direction) != Axis.vertical) {
      super.invoke(intent, context);
      return;
    }
    final target = Scrollable.maybeOf(context);
    if (target != null) {
      // 焦点在某个滚动视图内：只有它就是本代次的滚动视图时才算本 Timeline 的阅读意图。
      if (controller.hasClients &&
          identical(target.position, controller.position)) {
        _invokeAndPrune(intent, context);
      } else {
        super.invoke(intent, context);
      }
      return;
    }
    if (!controller.hasClients) return;
    // 焦点在滚动视图之外（选择区域）：仍是本 Timeline 的键盘滚动，官方动作会通过
    // 本子树提供的 PrimaryScrollController 找到代次的滚动位置。
    _invokeAndPrune(intent, context);
  }

  /// 登记意图 → 交给官方动作 → 若实际没有位移也没进入滚动活动，立刻撤回意图。
  ///
  /// 这覆盖“已在底端按 PageDown/Home/End”等无位移动作：官方不会发 Start/Update/End，
  /// 悬挂的意图会让之后的布局修正被误判成阅读意图（design/26 §26.3）。
  void _invokeAndPrune(ScrollIntent intent, BuildContext context) {
    final before = controller.hasClients ? controller.position.pixels : null;
    onUserIntent();
    super.invoke(intent, context);
    if (!controller.hasClients) {
      onNoMovement();
      return;
    }
    final position = controller.position;
    if (before != null &&
        position.pixels == before &&
        !position.isScrollingNotifier.value) {
      onNoMovement();
    }
  }
}

/// 标准滚动条的薄适配：只把“轨道点击”这一真实用户动作登记为意图。
///
/// `RawScrollbarState.handleTrackTapDown` 是官方 `@protected @mustCallSuper` 扩展点：它自己
/// 用 `position.moveTo(...)` 分页，我们只在其前登记意图并调用 `super`，不重算像素、不复制
/// 命中测试（design/26 §26.4）。thumb 拖动本来就走 `position.drag`（带 dragDetails），
/// 不在此处理。
class TimelineScrollbar extends RawScrollbar {
  const TimelineScrollbar({
    required super.controller,
    required super.thumbVisibility,
    required super.child,
    required this.onTrackTap,
    required this.onNoMovement,
  });

  final VoidCallback onTrackTap;
  final VoidCallback onNoMovement;

  @override
  RawScrollbarState<RawScrollbar> createState() => TimelineScrollbarState();
}

class TimelineScrollbarState extends RawScrollbarState<RawScrollbar> {
  @override
  void handleTrackTapDown(TapDownDetails details) {
    // 该 state 只由 [TimelineScrollbar] 创建，回调来自它自己的 widget 字段。
    final scrollbar = widget as TimelineScrollbar;
    final controller = scrollbar.controller;
    final before = controller != null && controller.hasClients
        ? controller.position.pixels
        : null;
    scrollbar.onTrackTap();
    super.handleTrackTapDown(details);
    if (before == null || controller == null || !controller.hasClients) {
      scrollbar.onNoMovement();
      return;
    }
    final position = controller.position;
    if (position.pixels == before && !position.isScrollingNotifier.value) {
      scrollbar.onNoMovement();
    }
  }
}
