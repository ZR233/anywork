import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../ui/badges/studio_badges.dart';

/// 侧栏紧凑单行条目：标题单行省略，右侧固定状态区与按需快捷操作区。
///
/// 快捷操作在悬停或选中时可见，并通过 [Visibility] 保持占位，避免出现
/// 与消失挤动标题。触控输入模式下所有行的操作常显并放大命中区，整个侧栏
/// 使用同一种输入模式，不做逐行切换。选中使用拿铁底色与
/// [StudioSelectionMarker] 的细蓝标记。本组件不承载业务状态；状态指示
/// 由调用方在 [trailing] 中以各自的 canonical 事实组装。
class SidebarCompactTile extends StatefulWidget {
  const SidebarCompactTile({
    required this.selected,
    required this.title,
    required this.onTap,
    required this.trailing,
    this.actions,
    this.touchMode = false,
    super.key,
  });

  final bool selected;
  final String title;
  final VoidCallback? onTap;

  /// 右侧常驻状态区（例如会话工作树标识与行级运行状态）。
  final Widget trailing;

  /// 悬停或选中时出现的快捷操作；为 null 时不占位。
  final Widget? actions;

  /// 触控输入模式：操作常显，行高与命中区按触控密度放大。
  final bool touchMode;

  @override
  State<SidebarCompactTile> createState() => _SidebarCompactTileState();
}

class _SidebarCompactTileState extends State<SidebarCompactTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.selected
        ? context.colors.onPrimaryContainer
        : context.colors.onSurface;
    final actions = widget.actions;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
                  10,
                  widget.touchMode ? 12 : 7,
                  4,
                  widget.touchMode ? 12 : 7,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconTheme.merge(
                      data: IconThemeData(
                        color: context.colors.onSurfaceVariant,
                      ),
                      child: widget.trailing,
                    ),
                    if (actions != null)
                      Visibility(
                        visible:
                            widget.touchMode || widget.selected || _hovering,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
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
    );
  }
}

/// 侧栏行内快捷操作按钮：桌面 32px、触控 44px 真实命中区。
///
/// 全局主题是 `VisualDensity.compact`，这里显式 standard 防止 constraints
/// 被每边减 4（compact 会把 44 缩到 36/40、32 缩到 24）；shrinkWrap 不
/// 膨胀到默认 48，保持单行密度与标题宽度稳定。
Widget sidebarTileIconButton({
  Key? key,
  required String tooltip,
  required IconData icon,
  double iconSize = 16,
  double minTarget = 32,
  VoidCallback? onPressed,
}) {
  return IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: iconSize),
    visualDensity: VisualDensity.standard,
    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    padding: EdgeInsets.zero,
    constraints: BoxConstraints(minWidth: minTarget, minHeight: minTarget),
  );
}
