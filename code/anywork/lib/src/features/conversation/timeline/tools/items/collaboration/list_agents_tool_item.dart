import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../shared/typed_json.dart';
import '../../../state/tool_data_artifact.dart';
import '../../../state/tool_presentation.dart';
import '../../support/agent_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/task_state_values_support.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.list_agents@1` (and uncontracted live `list_agents`
/// atoms).
class ListAgentsToolItem extends StructuredTimelineToolAdapter {
  const ListAgentsToolItem();

  static const String contractId = 'builtin.list_agents@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName('list_agents', requireEmptyContract: true),
  ]);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameListAgents;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.groups_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolListAgentsRunning,
        failed: l10n.timelineToolListAgentsFailed,
        succeeded: l10n.timelineToolListAgentsSucceeded,
        backgroundStarted: l10n.timelineToolStateBackgroundStarted,
        backgrounded: l10n.timelineToolStateBackgrounded,
      );

  @override
  String? rowTarget(AppLocalizations l10n, TimelineToolPresentation item) {
    final result = switch (item.toolData) {
      ToolDataArtifactPresent(:final value) => value,
      _ => null,
    };
    final count = _extractAgentCount(result);
    if (count == null) return null;
    return '($count)';
  }

  static int? _extractAgentCount(Object? decoded) {
    if (decoded is List) return decoded.length;
    if (decoded is Map) {
      if (decoded['agents'] case final List agents) return agents.length;
      if (decoded['items'] case final List items) return items.length;
      if (decoded['count'] case final int count) return count;
    }
    return null;
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) {
    if (result is List) {
      return _projectAgentEntries(l10n, result);
    }
    if (result is Map<String, dynamic>) {
      final entries = result['agents'] ?? result['items'];
      if (entries is List) {
        return [
          ..._projectAgentEntries(l10n, entries),
          ...toolResultFields(
            l10n,
            toolTaskStateValues(l10n, result),
            toolDiagnosticFields(l10n),
            unavailableWhenEmpty: false,
          ),
        ];
      }
      return toolAgentResult(l10n, result);
    }
    return toolAgentResult(l10n, result);
  }

  static List<ToolDetailValue> _projectAgentEntries(
    AppLocalizations l10n,
    List<dynamic> entries,
  ) {
    final values = <ToolDetailValue>[
      ToolDetailText(l10n.timelineToolDetailCount, '${entries.length}'),
    ];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final map = jsonObject(entry);
      final name =
          jsonStringValue(map['name']) ??
          jsonStringValue(map['displayName']) ??
          jsonStringValue(map['agentName']) ??
          compactAgentTargetLabel(jsonStringValue(map['id'])) ??
          jsonStringValue(map['id']);
      if (name != null) {
        values.add(ToolDetailText(l10n.timelineToolDetailAgent, name));
      }
      final role =
          jsonStringValue(map['role']) ?? jsonStringValue(map['profileId']);
      if (role != null) {
        values.add(ToolDetailText(l10n.timelineToolDetailRole, role));
      }
      final lifecycle = jsonObject(map['lifecycle']);
      final statusRaw =
          jsonStringValue(map['status']) ??
          jsonStringValue(map['state']) ??
          jsonStringValue(lifecycle['kind']);
      if (statusRaw != null) {
        final localized = toolTaskStateValues(l10n, {'status': statusRaw});
        final statusText = localized is Map && localized['status'] is String
            ? localized['status'] as String
            : statusRaw;
        values.add(ToolDetailText(l10n.timelineToolDetailStatus, statusText));
      }
      final lastCompleted = jsonObject(map['lastCompleted']);
      final summary =
          jsonStringValue(map['summary']) ??
          jsonStringValue(lastCompleted['summary']);
      if (summary != null) {
        values.add(ToolDetailText(l10n.timelineToolDetailSummary, summary));
      }
    }
    return values;
  }
}
