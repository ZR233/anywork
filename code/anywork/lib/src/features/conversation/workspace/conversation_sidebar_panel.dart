import 'package:material_ui/material_ui.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../shared/studio_driver_keys.dart';
import 'conversation_sidebar_state.dart';

/// 全宽展开时底部交互/输入区的几何策略。
enum ConversationExpandedDockBehavior {
  /// 铺满整个工作区（直至状态栏顶部），适合工作流图、Markdown 与待办的沉浸阅读。
  coverAll,

  /// 保留底部交互/输入区在正文下方可见，适合待确认 Plan 阅读与批准。
  keepFooterBelow,
}

/// 传递给边栏组件的实时几何上下文。
final class ConversationSidebarPresentation {
  const ConversationSidebarPresentation({
    required this.sideBySideFeasible,
    required this.isExpandedFull,
  });

  final bool sideBySideFeasible;
  final bool isExpandedFull;
}

/// 统一右侧边栏可挂载的面板描述。
final class ConversationSidebarPanelEntry {
  const ConversationSidebarPanelEntry({
    required this.kind,
    required this.icon,
    required this.label,
    required this.builder,
    this.tooltip,
    this.badge,
    this.onDismiss,
    this.defaultLayoutMode = ConversationSidebarLayoutMode.split,
    this.expandedDockBehavior = ConversationExpandedDockBehavior.coverAll,
    this.defaultWidthBuilder,
  });

  final ConversationSidebarPanelKind kind;
  final IconData icon;
  final String label;
  final String? tooltip;
  final Widget? badge;
  final VoidCallback? onDismiss;
  final ConversationSidebarLayoutMode defaultLayoutMode;
  final ConversationExpandedDockBehavior expandedDockBehavior;
  final double Function(double containerWidth)? defaultWidthBuilder;
  final WidgetBuilder builder;
}

/// Native 与 ACP 共用的唯一右侧可收缩边栏组件。
///
/// 采用单行紧凑顶栏承载单面板标题或多面板页签切换，清理所有冗余二级描述；
/// 宽屏支持全宽/并排切换，始终提供收起动作，内容区与底部状态栏无缝衔接。
class ConversationRightSidebar extends StatelessWidget {
  const ConversationRightSidebar({
    required this.entries,
    required this.activeKind,
    required this.presentation,
    required this.onSelectKind,
    required this.onCollapse,
    this.onToggleLayoutMode,
    super.key,
  });

  final List<ConversationSidebarPanelEntry> entries;
  final ConversationSidebarPanelKind activeKind;
  final ConversationSidebarPresentation presentation;
  final ValueChanged<ConversationSidebarPanelKind> onSelectKind;
  final VoidCallback? onToggleLayoutMode;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    assert(entries.isNotEmpty, 'ConversationRightSidebar requires entries');
    final active = entries.firstWhere(
      (entry) => entry.kind == activeKind,
      orElse: () => entries.first,
    );
    final colors = context.colors;
    final l10n = context.l10n;

    final header = SelectionContainer.disabled(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
            child: Row(
              children: [
                if (entries.length == 1)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          active.icon,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 1,
                          child: Tooltip(
                            message: active.tooltip ?? active.label,
                            child: Text(
                              active.label,
                              key: StudioDriverKeys.rightSidebarTab(
                                active.kind.name,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (active.badge case final badge?) ...[
                          const SizedBox(width: 8),
                          Flexible(flex: 2, child: badge),
                        ],
                        if (active.onDismiss case final onDismiss?) ...[
                          const SizedBox(width: 4),
                          _FileDismissButton(
                            tooltip: l10n.rightSidebarCloseFile,
                            onDismiss: onDismiss,
                          ),
                        ],
                      ],
                    ),
                  )
                else ...[
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < entries.length; i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            _SidebarTabChip(
                              entry: entries[i],
                              selected: entries[i].kind == active.kind,
                              onTap: () => onSelectKind(entries[i].kind),
                              dismissTooltip: l10n.rightSidebarCloseFile,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (active.badge case final badge?) ...[
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 112),
                      child: badge,
                    ),
                  ],
                ],
                const SizedBox(width: 4),
                if (presentation.sideBySideFeasible &&
                    onToggleLayoutMode != null)
                  IconButton(
                    key: StudioDriverKeys.rightSidebarExpandMode,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 48,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: presentation.isExpandedFull
                        ? l10n.planRestoreSplit
                        : l10n.planExpandReading,
                    onPressed: onToggleLayoutMode,
                    icon: Icon(
                      presentation.isExpandedFull
                          ? Icons.vertical_split_outlined
                          : Icons.open_in_full,
                      size: 18,
                    ),
                  ),
                IconButton(
                  key: StudioDriverKeys.rightSidebarCollapse,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  visualDensity: VisualDensity.standard,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 48,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: l10n.rightSidebarCollapse,
                  onPressed: onCollapse,
                  icon: const Icon(Icons.keyboard_double_arrow_right, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return KeyedSubtree(
      key: StudioDriverKeys.rightSidebar,
      child: Material(
        color: colors.surfaceContainerLowest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('sidebar-panel-body:${active.kind.name}'),
                child: active.builder(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarTabChip extends StatelessWidget {
  const _SidebarTabChip({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.dismissTooltip,
  });

  final ConversationSidebarPanelEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final String dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    final background = selected
        ? colors.primaryContainer.withValues(alpha: 0.55)
        : Colors.transparent;
    final borderColor = selected
        ? colors.primary.withValues(alpha: 0.45)
        : Colors.transparent;

    return Tooltip(
      message: entry.tooltip ?? entry.label,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          key: StudioDriverKeys.rightSidebarTab(entry.kind.name),
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 30),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                8,
                4,
                entry.onDismiss != null ? 4 : 8,
                4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(entry.icon, size: 15, color: foreground),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (entry.onDismiss case final onDismiss?) ...[
                    const SizedBox(width: 3),
                    _FileDismissButton(
                      tooltip: dismissTooltip,
                      onDismiss: onDismiss,
                      color: foreground,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileDismissButton extends StatelessWidget {
  const _FileDismissButton({
    required this.tooltip,
    required this.onDismiss,
    this.color,
  });

  final String tooltip;
  final VoidCallback onDismiss;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        key: StudioDriverKeys.rightSidebarFileClose,
        radius: 12,
        onTap: onDismiss,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.close,
            size: 14,
            color: color ?? context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 底部状态栏最右侧的统一展开/收起右侧边栏开关。
class ConversationSidebarToggleButton extends StatelessWidget {
  const ConversationSidebarToggleButton({
    required this.available,
    required this.expanded,
    this.onPressed,
    super.key,
  });

  final bool available;
  final bool expanded;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();
    final l10n = context.l10n;
    final colors = context.colors;
    return IconButton(
      key: StudioDriverKeys.rightSidebarToggle,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      tooltip: expanded ? l10n.rightSidebarCollapse : l10n.rightSidebarExpand,
      onPressed: onPressed,
      icon: Icon(
        expanded ? Icons.view_sidebar : Icons.view_sidebar_outlined,
        color: expanded ? colors.primary : colors.onSurfaceVariant,
      ),
    );
  }
}
