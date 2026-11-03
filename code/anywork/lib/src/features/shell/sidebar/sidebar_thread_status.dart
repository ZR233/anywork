part of 'studio_sidebar.dart';

/// 侧栏会话行前导状态槽位（与项目图标列垂直对齐）的单行状态指示。
///
/// 每行只消费自己的 canonical [ThreadStatusView]，不用选中会话的忙碌
/// 状态替代：排队、执行、等待工具、停止中与关闭中显示 15px 小型活动圈；
/// 等待用户确认是静态待确认标识，失败是错误标识，空闲与已关闭保持 16px 前导槽位
/// 留白而不渲染图形以维持标题左边界对齐且避免噪音。等待用户确认绝不转圈冒充模型工作。
///
/// 减少动画偏好下活动圈改以静态弧呈现，但 [Semantics] 与 [Tooltip] 仍
/// 说明该会话正在工作，不伪装成空闲。
class _ThreadStatusBadge extends StatelessWidget {
  const _ThreadStatusBadge({required this.status});

  final ThreadStatusView status;

  @override
  Widget build(BuildContext context) {
    final label = context.threadStatusLabel(status);
    final Widget indicator = switch (status) {
      ThreadStatusView.queued ||
      ThreadStatusView.running ||
      ThreadStatusView.waitingTool ||
      ThreadStatusView.cancelling ||
      ThreadStatusView.closing => const _ActiveStatusRing(),
      ThreadStatusView.waitingInteraction => Icon(
        Icons.help_outline,
        size: 16,
        color: context.statusColors.warning,
      ),
      ThreadStatusView.faulted => Icon(
        Icons.error_outline,
        size: 16,
        color: context.colors.error,
      ),
      ThreadStatusView.idle ||
      ThreadStatusView.closed => const SizedBox.shrink(),
    };
    if (status == ThreadStatusView.idle || status == ThreadStatusView.closed) {
      return indicator;
    }
    return Semantics(
      container: true,
      label: label,
      child: Tooltip(message: label, child: indicator),
    );
  }
}

/// 15px 小型活动圈（居中于 16px 前导槽位内）：始终保持 270° 固定弧长旋转，
/// 避免默认不确定态在周期起点收缩成单像素圆点；`disableAnimations` 时静止呈现，
/// 颜色使用主题的眼眸蓝活动指示语义，不引入第二份状态色。
class _ActiveStatusRing extends StatefulWidget {
  const _ActiveStatusRing();

  @override
  State<_ActiveStatusRing> createState() => _ActiveStatusRingState();
}

class _ActiveStatusRingState extends State<_ActiveStatusRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = SizedBox.square(
      dimension: 15,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        value: 0.75,
        color: context.statusColors.activeIndicator,
        strokeCap: StrokeCap.round,
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return ring;
    }
    return RotationTransition(turns: _controller, child: ring);
  }
}
