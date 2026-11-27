import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../shared/typed_json.dart';
import '../../../state/tool_presentation.dart';
import '../../support/agent_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/task_state_values_support.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.read_agent_session@1` (and uncontracted live
/// `read_agent_session` atoms).
class ReadAgentSessionToolItem extends StructuredTimelineToolAdapter {
  const ReadAgentSessionToolItem();

  static const String contractId = 'builtin.read_agent_session@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName(
      'read_agent_session',
      requireEmptyContract: true,
    ),
  ]);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameReadAgentSession;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.forum_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolReadAgentSessionRunning,
        failed: l10n.timelineToolReadAgentSessionFailed,
        succeeded: l10n.timelineToolReadAgentSessionSucceeded,
        backgroundStarted: l10n.timelineToolStateBackgroundStarted,
        backgrounded: l10n.timelineToolStateBackgrounded,
      );

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) => toolAgentRowTarget(item);

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    final limit = data['limit'];
    return [
      ...toolField(l10n, data, 'target', l10n.timelineToolDetailTarget),
      ...toolField(l10n, data, 'cursor', l10n.timelineToolDetailCursor),
      if (limit is num)
        ToolDetailText(l10n.timelineToolDetailCount, '$limit')
      else
        ...toolField(l10n, data, 'limit', l10n.timelineToolDetailCount),
    ];
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) {
    if (result is! Map<String, dynamic>) {
      return toolAgentResult(l10n, result);
    }
    final values = <ToolDetailValue>[];
    final items = result['items'];
    if (items is List) {
      values.add(
        ToolDetailText(l10n.timelineToolDetailCount, '${items.length}'),
      );
      for (final entry in items) {
        values.addAll(_projectSessionEntry(l10n, entry));
      }
    }
    final messages = result['messages'];
    if (messages is List) {
      if (items is! List) {
        values.add(
          ToolDetailText(l10n.timelineToolDetailCount, '${messages.length}'),
        );
      }
      for (final entry in messages) {
        values.addAll(_projectSessionEntry(l10n, entry));
      }
    }
    final nextCursor = jsonStringValue(result['nextCursor']);
    if (nextCursor != null) {
      values.add(ToolDetailText(l10n.timelineToolDetailCursor, nextCursor));
    }
    values.addAll(
      toolResultFields(l10n, toolTaskStateValues(l10n, result), {
        'status': l10n.timelineToolDetailStatus,
        'state': l10n.timelineToolDetailStatus,
        'summary': l10n.timelineToolDetailSummary,
        'text': l10n.timelineToolDetailContent,
        'message': l10n.timelineToolDetailMessage,
        'report': l10n.timelineToolDetailReport,
        ...toolDiagnosticFields(l10n),
      }, unavailableWhenEmpty: false),
    );
    if (values.isEmpty && result.isNotEmpty) {
      return [ToolDetailUnavailable(l10n.timelineToolNoSemanticContent)];
    }
    return values;
  }

  static List<ToolDetailValue> _projectSessionEntry(
    AppLocalizations l10n,
    Object? entry,
  ) {
    if (entry is String) {
      return toolTextResult(l10n, entry);
    }
    if (entry is! Map) {
      return const [];
    }
    final map = jsonObject(entry);
    final localized = toolTaskStateValues(l10n, Map<String, dynamic>.from(map));
    final localizedMap = localized is Map<String, dynamic>
        ? localized
        : Map<String, dynamic>.from(map);
    final results = <ToolDetailValue>[];
    final payloadJson = jsonStringValue(map['payloadJson']);
    if (payloadJson != null) {
      final envelope = decodeJsonObject(payloadJson);
      final data = jsonObject(envelope['data']);
      final summary = jsonStringValue(data['summary']);
      if (summary != null) {
        results.add(ToolDetailText(l10n.timelineToolDetailSummary, summary));
      }
      final bodies = envelope['bodies'];
      if (bodies is List) {
        for (final body in bodies) {
          final bodyMap = jsonObject(body);
          final text = jsonStringValue(bodyMap['inlineText']);
          if (text != null) {
            results.add(ToolDetailText(l10n.timelineToolDetailMessage, text));
          }
        }
      }
    }
    for (final (key, label) in [
      ('message', l10n.timelineToolDetailMessage),
      ('text', l10n.timelineToolDetailContent),
      ('content', l10n.timelineToolDetailContent),
      ('summary', l10n.timelineToolDetailSummary),
      ('status', l10n.timelineToolDetailStatus),
      ('state', l10n.timelineToolDetailStatus),
    ]) {
      final value = jsonStringValue(localizedMap[key]);
      if (value != null) {
        results.add(ToolDetailText(label, value));
      }
    }
    return results;
  }
}
