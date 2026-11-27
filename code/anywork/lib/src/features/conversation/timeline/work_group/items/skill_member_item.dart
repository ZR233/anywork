import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../shared/studio_code_block.dart';
import '../../tools/support/tool_detail_panel.dart';
import '../../tools/support/tool_detail_values.dart';
import '../../widgets/timeline_activity_row.dart';
import '../work_group_member_adapter.dart';

/// 渲染工作组内的技能激活条目。
class SkillMemberItem extends WorkGroupMemberAdapter {
  const SkillMemberItem();

  @override
  String get id => 'work_group.skill';

  @override
  WorkGroupMemberMatcher get matcher =>
      const WorkGroupMemberMatcher.kind(WorkGroupMemberKind.skill);

  @override
  Widget build(WorkGroupMemberContext context) {
    final l10n = context.l10n;
    final member = context.member as WorkGroupSkill;
    final parsed = _parseSkillPayload(member);
    final name = parsed.name ?? l10n.workGroupSkillTitle;
    final label = l10n.workGroupSkillActivated(name);

    final detailValues = <ToolDetailValue>[
      ToolDetailText(l10n.workGroupSkillTitle, name),
      if (parsed.description != null && parsed.description != name)
        ToolDetailText(l10n.timelineToolDetailDescription, parsed.description!),
      if (parsed.source != null)
        ToolDetailText(l10n.timelineToolDetailFile, parsed.source!),
    ];

    final expandedChildren = <Widget>[
      if (detailValues.isNotEmpty)
        TimelineToolDetailPanel(
          children: [TimelineToolSemanticBody(values: detailValues)],
        ),
      if (parsed.formattedJson != null && parsed.formattedJson != '{}')
        TimelineActivityTileTheme(
          child: TimelineActivityDisclosure(
            titleBuilder: (_, expanded) => TimelineActivityRow(
              icon: Icons.data_object_outlined,
              label: l10n.timelineOutcomeRawRecord,
              expanded: expanded,
            ),
            children: [
              StudioCodeBlock(
                text: parsed.formattedJson!,
                horizontalScroll: false,
              ),
            ],
          ),
        ),
    ];
    final expandable = expandedChildren.isNotEmpty;

    if (!expandable) {
      return TimelineActivityRow(
        icon: Icons.auto_awesome_outlined,
        label: label,
        expandable: false,
      );
    }

    return TimelineActivityTileTheme(
      child: TimelineActivityDisclosure(
        initiallyExpanded: context.initiallyExpanded,
        onExpansionChanged: context.onExpansionChanged,
        titleBuilder: (_, expanded) => TimelineActivityRow(
          icon: Icons.auto_awesome_outlined,
          label: label,
          expanded: expanded,
          expandable: true,
        ),
        children: expandedChildren,
      ),
    );
  }
}

class _ParsedSkill {
  const _ParsedSkill({
    this.name,
    this.description,
    this.source,
    this.formattedJson,
  });

  final String? name;
  final String? description;
  final String? source;
  final String? formattedJson;
}

_ParsedSkill _parseSkillPayload(WorkGroupSkill member) {
  Map<String, dynamic>? root;
  String? formattedJson;
  final raw = member.payloadJson.trim();
  if (raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        root = decoded;
        formattedJson = const JsonEncoder.withIndent('  ').convert(decoded);
      }
    } on FormatException {
      // Ignore malformed payload.
    }
  }
  final data = root?['data'] is Map<String, dynamic>
      ? root!['data'] as Map<String, dynamic>
      : root;
  final activation = data?['activation'] is Map<String, dynamic>
      ? data!['activation'] as Map<String, dynamic>
      : null;

  final name =
      _nonEmpty(activation?['name']) ??
      _nonEmpty(data?['name']) ??
      (member.name.trim().isNotEmpty && member.name.trim() != 'Skill'
          ? member.name.trim()
          : null);
  final description =
      _nonEmpty(activation?['summary']) ??
      _nonEmpty(activation?['description']) ??
      _nonEmpty(data?['summary']) ??
      (member.summary.trim().isNotEmpty && member.summary.trim() != 'Skill'
          ? member.summary.trim()
          : null);
  final source =
      _nonEmpty(activation?['path']) ??
      _nonEmpty(activation?['source']) ??
      _nonEmpty(activation?['scope']) ??
      _nonEmpty(data?['path']);

  return _ParsedSkill(
    name: name,
    description: description,
    source: source,
    formattedJson: formattedJson,
  );
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
