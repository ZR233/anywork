import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../tools/support/tool_detail_panel.dart';
import '../../tools/support/tool_detail_values.dart';
import '../../widgets/timeline_activity_row.dart';
import '../work_group_member_adapter.dart';

/// 未知或未专门适配的工作组成员兜底展示。
class FallbackWorkGroupMemberItem extends WorkGroupMemberAdapter {
  const FallbackWorkGroupMemberItem();

  @override
  String get id => 'work_group.fallback';

  @override
  WorkGroupMemberMatcher get matcher =>
      const WorkGroupMemberMatcher.kind(WorkGroupMemberKind.fallback);

  @override
  Widget build(WorkGroupMemberContext context) {
    final member = context.member;
    if (member is! WorkGroupFallback) {
      return TimelineActivityRow(
        icon: Icons.info_outline,
        label: member.id,
        expandable: false,
      );
    }

    final l10n = context.l10n;
    final reason = member.reason.trim();
    final eventKind = member.eventKind.trim();
    final label = reason.isNotEmpty
        ? (eventKind.isNotEmpty ? '$eventKind · $reason' : reason)
        : (eventKind.isNotEmpty ? eventKind : member.id);

    final details = <ToolDetailValue>[
      if (eventKind.isNotEmpty)
        ToolDetailText(l10n.timelineDetailCategory, eventKind),
      if (reason.isNotEmpty)
        ToolDetailText(l10n.timelineToolDetailReason, reason),
      if (member.eventId.trim().isNotEmpty)
        ToolDetailText('Event ID', member.eventId.trim(), code: true),
    ];

    if (details.isEmpty) {
      return TimelineActivityRow(
        icon: Icons.info_outline,
        label: label,
        expandable: false,
      );
    }

    return TimelineActivityTileTheme(
      child: TimelineActivityDisclosure(
        initiallyExpanded: context.initiallyExpanded,
        onExpansionChanged: context.onExpansionChanged,
        titleBuilder: (_, expanded) => TimelineActivityRow(
          icon: Icons.info_outline,
          label: label,
          expanded: expanded,
          expandable: true,
        ),
        children: [
          TimelineToolDetailPanel(
            children: [TimelineToolSemanticBody(values: details)],
          ),
        ],
      ),
    );
  }
}
