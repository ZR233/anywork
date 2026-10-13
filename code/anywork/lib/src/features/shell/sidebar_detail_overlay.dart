part of 'studio_shell.dart';

/// 详情卡期望宽度；超过可用宽度时由框架按真实安全区收敛，
/// 窄抽屉中自动收窄。
const double _sidebarDetailCardWidth = 300.0;

/// 侧栏行的按需悬浮/键盘详情宿主。
///
/// 详情卡是直接架在 Material [MenuAnchor] 上的自由内容面板：锚定、窗口
/// 收敛、祖先滚动/窗口变化关闭、外点关闭、Escape 与面板内有界滚动都是
/// 框架行为。`MenuStyle.alignment` 让卡片贴行**侧向**展开（LTR 优先文字
/// 尾侧），不覆盖同列相邻行，空间不足换侧并按安全区收敛。本组件只内联
/// 悬停/聚焦显示与延迟收起的业务交互，并把行本体**真实的焦点节点**交给
/// 行内容：不叠加额外可聚焦包装层，因此第一焦点停点仍是行本体（Enter
/// 选择会话、聚焦即显示详情）。
class _SidebarHoverDetail extends StatefulWidget {
  const _SidebarHoverDetail({
    required this.childBuilder,
    required this.detailBuilder,
  });

  /// 构建行本体，并把共享焦点节点交给它挂到真实可聚焦控件上。
  /// [focusNode] 挂到真实可聚焦控件；[onMenuOpenChanged] 由行内更多菜单接到
  /// `onOpen`/`onClose`，仅在真实打开时暂停重开（`onClose` 复位，不自动重开）；
  /// [onMenuBeforeOpen] 由菜单触发器在打开**之前**同步调用，收起父详情，
  /// 避免详情卡与菜单浮层同时可见、互相遮挡。
  final Widget Function(
    BuildContext context,
    FocusNode focusNode,
    ValueChanged<bool> onMenuOpenChanged,
    VoidCallback onMenuBeforeOpen,
  )
  childBuilder;

  final WidgetBuilder detailBuilder;

  @override
  State<_SidebarHoverDetail> createState() => _SidebarHoverDetailState();
}

class _SidebarHoverDetailState extends State<_SidebarHoverDetail> {
  final MenuController _controller = MenuController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'sidebar-row-trigger');
  Timer? _hideTimer;
  bool _focused = false;

  /// 行内更多菜单是否正打开。菜单打开前详情已同步收起；打开期间暂停
  /// hover/聚焦重开，避免详情卡盖住菜单项、拦截菜单点击。
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  /// 键盘聚焦/离开行本体：聚焦立即展示详情，离开后延迟收起。
  void _handleFocusChange() {
    // 只有行本体自己拿到主焦点才展开详情：行内后代控件（快捷操作、更多菜单
    // 触发按钮）聚焦不应自动开详情，否则打开菜单时详情会盖住菜单项。
    final focused = _focusNode.hasPrimaryFocus;
    if (focused == _focused) return;
    _focused = focused;
    if (focused) {
      _cancelHide();
      _show();
    } else {
      _scheduleHide();
    }
  }

  void _handleHover(bool hovering) {
    if (hovering) {
      _show();
    } else {
      _scheduleHide();
    }
  }

  void _show() {
    _cancelHide();
    if (!mounted || _menuOpen) return;
    _controller.open();
  }

  /// 行内更多菜单真实开合通知：`onOpen` 置暂停重开 flag，`onClose` 复位。
  /// 不在此处收起父详情——菜单触发器已在打开前同步收起；`open` 时只取消
  /// 待收起延时，`close` 只清 flag，不自动重开（交给后续 hover/聚焦）。
  void _handleMenuOpenChanged(bool open) {
    _menuOpen = open;
    if (open) _cancelHide();
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _scheduleHide() {
    _cancelHide();
    if (_focused) return;
    _hideTimer = Timer(const Duration(milliseconds: 120), _hide);
  }

  void _hide() {
    _cancelHide();
    _controller.close();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      // 不传 childFocusNode：hover 打开不迁移输入焦点，聚焦行本体时焦点
      // 已在行上，Escape 由锚点在菜单打开期间注册的 Dismiss 动作关闭。
      style: const MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(_sidebarDetailCardWidth, 0)),
        maximumSize: WidgetStatePropertyAll(
          Size(_sidebarDetailCardWidth, double.infinity),
        ),
        // 侧向放置：卡片贴行尾侧展开，空间不足时框架换侧并按安全区收敛。
        alignment: AlignmentDirectional.topEnd,
      ),
      alignmentOffset: const Offset(6, 6),
      onClose: _cancelHide,
      menuChildren: [_buildContent(context)],
      child: MouseRegion(
        onEnter: (_) => _handleHover(true),
        onExit: (_) => _handleHover(false),
        child: widget.childBuilder(
          context,
          _focusNode,
          _handleMenuOpenChanged,
          _hide,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _cancelHide(),
      onExit: (_) => _scheduleHide(),
      child: Padding(
        // 详情卡内容使用明确的内缩网格。框架负责卡片外框与有界滚动，
        // 这里负责内容本身的留白，使标题、前置图标和复制按钮共用
        // 同一组左右边界。
        padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
        child: widget.detailBuilder(context),
      ),
    );
  }
}

/// 详情卡中的一行：前置标识（图标或状态点）+ 值，可选尾部动作。
class _SidebarDetailRow extends StatelessWidget {
  const _SidebarDetailRow({
    required this.leading,
    required this.value,
    this.trailing,
  });

  final Widget leading;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: 18, child: Center(child: leading)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              value,
              style: context.text.bodySmall?.copyWith(height: 1.3),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// 相对更新时间：一分钟内、分钟、小时、天内使用本地化相对文案，
/// 更早的更新回退为既有列表的绝对时间写法（月/日 时:分），不引入新的
/// 日期格式化依赖。
String _relativeUpdatedLabel(BuildContext context, DateTime updatedAt) {
  final age = DateTime.now().difference(updatedAt);
  if (age.isNegative || age.inSeconds < 60) {
    return context.l10n.sidebarDetailUpdatedNow;
  }
  if (age.inMinutes < 60) {
    return context.l10n.sidebarDetailUpdatedMinutesAgo(age.inMinutes);
  }
  if (age.inHours < 24) {
    return context.l10n.sidebarDetailUpdatedHoursAgo(age.inHours);
  }
  if (age.inDays <= 7) {
    return context.l10n.sidebarDetailUpdatedDaysAgo(age.inDays);
  }
  final hour = updatedAt.hour.toString().padLeft(2, '0');
  final minute = updatedAt.minute.toString().padLeft(2, '0');
  return '${updatedAt.month}/${updatedAt.day} $hour:$minute';
}
