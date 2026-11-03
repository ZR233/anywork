part of 'studio_sidebar.dart';

/// 侧栏紧凑单行条目：标题单行省略，前导槽位对齐项目与会话层级，右侧固定状态区与按需快捷操作区。
///
/// 快捷操作在悬停或选中时可见，并通过 [Visibility] 保持占位，避免出现
/// 与消失挤动标题；支持将已置顶等操作设为 [leadingActionsAlwaysVisible] 常显。
/// 触控输入模式下（最近指针输入为触摸/触笔，
/// 见 `_SidebarState` 的输入模式检测）所有行的操作常显并放大命中区，
/// 整个侧栏使用同一种输入模式，不做逐行切换。选中使用拿铁底色与
/// [StudioSelectionMarker] 的细蓝标记。本组件不承载业务状态；状态指示
/// 由调用方在 [leading] 与 [trailing] 中以各自的 canonical 事实组装。
class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.selected,
    required this.title,
    required this.onTap,
    required this.trailing,
    this.leading,
    this.leadingPadding = 8,
    this.leadingActions,
    this.leadingActionsAlwaysVisible = false,
    this.actions,
    this.emphasized = false,
    this.touchMode = false,
  });

  final bool selected;
  final String title;
  final bool emphasized;
  final VoidCallback? onTap;

  /// 右侧常驻状态区（例如会话工作树标识与恢复告警）。
  final Widget trailing;
  final Widget? leading;

  /// 行左侧内边距；项目行传 0 使折叠箭头贴齐第一列，会话行传 8 使前导状态槽位对齐项目图标列。
  final double leadingPadding;

  /// 位于 [trailing] 左侧的快捷操作（如置顶按钮）；可配合 [leadingActionsAlwaysVisible] 在已置顶时常显。
  final Widget? leadingActions;
  final bool leadingActionsAlwaysVisible;

  /// 最右侧在悬停或选中时出现的快捷操作（如更多菜单）；为 null 时不占位。
  final Widget? actions;

  /// 触控输入模式：操作常显，行高与命中区按触控密度放大。
  final bool touchMode;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.selected
        ? context.colors.onPrimaryContainer
        : context.colors.onSurface;
    final leadingActions = widget.leadingActions;
    final actions = widget.actions;
    final showActions =
        widget.touchMode || widget.selected || _hovering || _focused;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Material(
            color: widget.selected
                ? context.colors.surfaceContainerHigh
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StudioRadii.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: StudioSelectionMarker(
              selected: widget.selected,
              child: InkWell(
                onTap: widget.onTap,
                hoverColor: context.colors.surface.withValues(alpha: 0.72),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.leadingPadding,
                    widget.touchMode ? 0 : 1,
                    4,
                    widget.touchMode ? 0 : 1,
                  ),
                  child: Row(
                    children: [
                      ?widget.leading,
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: widget.selected || widget.emphasized
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (leadingActions != null)
                        Visibility(
                          visible:
                              widget.leadingActionsAlwaysVisible || showActions,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          maintainFocusability: true,
                          child: IconTheme.merge(
                            data: IconThemeData(
                              color: context.colors.onSurfaceVariant,
                            ),
                            child: leadingActions,
                          ),
                        ),
                      IconTheme.merge(
                        data: IconThemeData(
                          color: context.colors.onSurfaceVariant,
                        ),
                        child: widget.trailing,
                      ),
                      if (actions != null)
                        Visibility(
                          visible: showActions,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          maintainFocusability: true,
                          child: IconTheme.merge(
                            data: IconThemeData(
                              color: context.colors.onSurfaceVariant,
                            ),
                            child: actions,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
