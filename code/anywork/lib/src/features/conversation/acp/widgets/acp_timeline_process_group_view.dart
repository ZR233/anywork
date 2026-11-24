import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../timeline/tools/items/acp/acp_tool_item.dart';
import '../../timeline/widgets/timeline_activity_row.dart';
import '../../timeline/widgets/timeline_reasoning_view.dart';
import '../../timeline/widgets/timeline_work_group_shell.dart';
import '../state/acp_timeline_row.dart';
import '../views/acp_conversation_content_view.dart';
import 'acp_content_block_view.dart';

/// ACP 连续过程区间的共享折叠分组视图，复用普通会话的 [TimelineWorkGroupShell]、
/// [TimelineActivityRow] 与 [TimelineActivityRail]，并按 ACP 原生协议形状与状态呈现标题。
class AcpTimelineProcessGroupView extends StatelessWidget {
  const AcpTimelineProcessGroupView({
    super.key,
    required this.row,
    this.initiallyExpanded = false,
    this.isSafeLink,
    this.onOpenLink,
    this.imageBuilder,
    this.onOpenMarkdownResource,
  });

  final AcpTimelineProcessRow row;
  final bool initiallyExpanded;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;
  final void Function(String uri, String text)? onOpenMarkdownResource;

  @override
  Widget build(BuildContext context) {
    final active = row.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TimelineWorkGroupShell(
        storageKey: PageStorageKey<String>(row.id),
        disclosureKey: ValueKey('acp-process-group-disclosure:${row.id}'),
        initiallyExpanded: initiallyExpanded,
        railInset: active ? 15.5 : 9.5,
        railContentInset: active ? 25.5 : 17.5,
        headerBuilder: (context, expanded) =>
            _AcpProcessGroupHeader(row: row, expanded: expanded),
        bodyBuilder: (context) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in row.items)
                AcpTimelineEntryView(
                  key: ValueKey(item.id),
                  item: item,
                  padding: const EdgeInsets.only(bottom: 2),
                  isSafeLink: isSafeLink,
                  onOpenLink: onOpenLink,
                  imageBuilder: imageBuilder,
                  onOpenMarkdownResource: onOpenMarkdownResource,
                ),
            ],
          );
          return SelectionContainer.maybeOf(context) == null
              ? SelectionArea(child: details)
              : details;
        },
      ),
    );
  }
}

class _AcpProcessGroupHeader extends StatelessWidget {
  const _AcpProcessGroupHeader({required this.row, required this.expanded});

  final AcpTimelineProcessRow row;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (row.active) {
      return _buildActiveHeader(context, l10n);
    }
    return _buildCompletedHeader(context, l10n);
  }

  Widget _buildActiveHeader(BuildContext context, AppLocalizations l10n) {
    final activeTool = row.activeTool;
    if (activeTool != null) {
      final kindLabel = acpToolKindLocalizedLabel(l10n, activeTool.kindLabel);
      final label = activeTool.tool.name.trim().isNotEmpty
          ? activeTool.tool.name.trim()
          : (kindLabel ?? l10n.acpToolKindOther);
      final meta = row.toolCount > 0
          ? l10n.acpProcessGroupRunningToolsMeta(row.toolCount)
          : l10n.acpProcessGroupRunningActivitiesMeta(row.items.length);
      final style = activeTool.kindLabel == 'execute'
          ? TimelineActivityIndicatorStyle.circularProgress
          : TimelineActivityIndicatorStyle.restingCat;
      return TimelineActivityRow(
        icon: acpToolKindIcon(activeTool.kindLabel),
        indicatorStyle: style,
        label: label,
        meta: meta,
        tooltip: '$label\n$meta',
        active: true,
        emphasized: true,
        header: true,
        expandable: true,
        expanded: expanded,
      );
    }

    final activeCompaction = row.activeCompaction;
    if (activeCompaction != null) {
      final label = l10n.acpUpdateCompaction(activeCompaction.statusLabel);
      final meta = row.items.length > 1
          ? l10n.acpProcessGroupRunningActivitiesMeta(row.items.length)
          : null;
      return TimelineActivityRow(
        icon: Icons.compress_rounded,
        indicatorStyle: TimelineActivityIndicatorStyle.compactingZip,
        label: label,
        meta: meta,
        tooltip: '$label\n$meta',
        active: true,
        header: true,
        expandable: true,
        expanded: expanded,
      );
    }

    final thought = row.activeThought ?? row.latestThought;
    final thoughtText = thought == null
        ? ''
        : AcpTimelineProcessRow.thoughtSummaryText(thought);
    final label = thoughtText.isNotEmpty
        ? thoughtText
        : l10n.timelineReasoningActive;
    final headerTextStyle = context.text.bodySmall!.copyWith(
      color: context.colors.onSurface.withValues(alpha: .92),
      fontSize: TimelineActivityRow.headerFontSize,
      fontWeight: FontWeight.w500,
      height: 1.36,
    );
    final meta = row.items.length <= 1
        ? null
        : row.toolCount > 0
        ? l10n.acpProcessGroupRunningToolsMeta(row.toolCount)
        : l10n.acpProcessGroupRunningActivitiesMeta(row.items.length);

    return TimelineActivityRow(
      icon: Icons.psychology_alt_outlined,
      indicatorStyle: TimelineActivityIndicatorStyle.restingCat,
      label: label,
      labelWidget: thoughtText.isNotEmpty
          ? TimelineReasoningSummary(
              id: '${row.id}:header-thought',
              text: thoughtText,
              style: headerTextStyle,
              strutStyle: TimelineActivityRow.headerStrutStyle,
              inlineCodeBackgroundColor: context.colors.surfaceContainerHigh
                  .withValues(alpha: .75),
            )
          : null,
      meta: meta,
      tooltip: [label, ?meta].join('\n'),
      active: true,
      header: true,
      expandable: true,
      expanded: expanded,
    );
  }

  Widget _buildCompletedHeader(BuildContext context, AppLocalizations l10n) {
    final IconData icon;
    final String summary;
    if (row.hasOnlyThoughts) {
      icon = Icons.psychology_alt_outlined;
      summary = l10n.acpProcessGroupThoughtsOnly(row.thoughtCount);
    } else if (row.hasOnlyTools) {
      icon = Icons.work_outline;
      summary = l10n.acpProcessGroupToolsOnly(row.toolCount);
    } else if (row.toolCount > 0) {
      icon = Icons.work_outline;
      summary = l10n.acpProcessGroupSummary(row.items.length, row.toolCount);
    } else {
      icon = Icons.tune_rounded;
      summary = l10n.acpProcessGroupActivitiesOnly(row.items.length);
    }

    return TimelineActivityRow(
      icon: icon,
      label: summary,
      active: false,
      isIssue: false,
      header: false,
      expandable: true,
      expanded: expanded,
      tooltip: summary,
    );
  }
}
