import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../shared/studio_code_block.dart';
import '../../connectors/timeline_feed_body_connector.dart';
import '../../tools/support/tool_detail_panel.dart';
import '../../tools/support/tool_detail_values.dart';
import '../../widgets/content_layout_witness.dart';
import '../../widgets/timeline_activity_row.dart';
import '../../widgets/timeline_plain_text.dart';
import '../work_group_member_adapter.dart';

/// 渲染工作组内的文件变更条目。
class FileChangeMemberItem extends WorkGroupMemberAdapter {
  const FileChangeMemberItem();

  @override
  String get id => 'work_group.file_change';

  @override
  WorkGroupMemberMatcher get matcher =>
      const WorkGroupMemberMatcher.kind(WorkGroupMemberKind.fileChange);

  @override
  Widget build(WorkGroupMemberContext context) {
    final l10n = context.l10n;
    final member = context.member as WorkGroupFileChange;
    final parsed = _parseFileChangePayload(member);
    final path = parsed.path;
    final label = path != null
        ? l10n.workGroupFileChanged(path)
        : l10n.workGroupFileChangeTitle;

    final detailValues = <ToolDetailValue>[
      if (path != null) ToolDetailText(l10n.timelineToolDetailFile, path),
      if (parsed.action != null)
        ToolDetailText(l10n.timelineToolDetailStatus, parsed.action!),
    ];

    final bodyWidgets = <Widget>[
      for (final ref in member.bodies) _buildBodyRef(context, member, ref),
    ];

    final expandedChildren = <Widget>[
      if (detailValues.isNotEmpty)
        TimelineToolDetailPanel(
          children: [
            TimelineToolSemanticBody(values: detailValues),
            ...bodyWidgets,
          ],
        )
      else
        ...bodyWidgets,
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
        icon: Icons.description_outlined,
        label: label,
        expandable: false,
      );
    }

    return TimelineActivityTileTheme(
      child: TimelineActivityDisclosure(
        initiallyExpanded: context.initiallyExpanded,
        onExpansionChanged: context.onExpansionChanged,
        titleBuilder: (_, expanded) => TimelineActivityRow(
          icon: Icons.description_outlined,
          label: label,
          expanded: expanded,
          expandable: true,
        ),
        children: expandedChildren,
      ),
    );
  }

  Widget _buildBodyRef(
    WorkGroupMemberContext context,
    WorkGroupFileChange member,
    BodyRef ref,
  ) {
    final id = '${member.id}:${ref.bodyKey}';
    Widget render(String text) =>
        context.bodyBuilder?.call(id, text) ??
        TimelinePlainText(id: id, text: text);
    Widget witness(String text, Widget child) {
      final clock = context.monotonicMicros;
      final onLayout = context.onContentLayout;
      if (text.trim().isEmpty || clock == null || onLayout == null) {
        return child;
      }
      return ContentLayoutWitness(
        itemId: member.id,
        monotonicMicros: clock,
        onContentLayout: onLayout,
        isDisplayActive: context.isDisplayActive,
        child: child,
      );
    }

    if (ref.inlineText != null) {
      return witness(ref.inlineText!, render(ref.inlineText!));
    }
    return TimelineFeedBodyConnector(
      itemId: member.id,
      reference: ref,
      label: '${ref.bodyKey} · ${ref.byteLength} 字节',
      disclosed: true,
      bodyBuilder: render,
      witness: witness,
    );
  }
}

class _ParsedFileChange {
  const _ParsedFileChange({this.path, this.action, this.formattedJson});

  final String? path;
  final String? action;
  final String? formattedJson;
}

_ParsedFileChange _parseFileChangePayload(WorkGroupFileChange member) {
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
      // Ignore malformed payload and fall back to member summary.
    }
  }
  final data = root?['data'] is Map<String, dynamic>
      ? root!['data'] as Map<String, dynamic>
      : root;
  final path =
      _nonEmpty(data?['path']) ??
      _nonEmpty(data?['summary']) ??
      (member.summary.trim().isNotEmpty &&
              member.summary.trim() != 'File change'
          ? member.summary.trim()
          : null);
  final action =
      _nonEmpty(data?['action']) ??
      _nonEmpty(data?['changeKind']) ??
      _nonEmpty(data?['operation']) ??
      _nonEmpty(data?['kind']);
  return _ParsedFileChange(
    path: path,
    action: action,
    formattedJson: formattedJson,
  );
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
