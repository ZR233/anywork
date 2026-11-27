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

/// Adapter for `builtin.close_agent@1` (and uncontracted live `close_agent`
/// atoms).
class CloseAgentToolItem extends StructuredTimelineToolAdapter {
  const CloseAgentToolItem();

  static const String contractId = 'builtin.close_agent@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName('close_agent', requireEmptyContract: true),
  ]);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameCloseAgent;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.stop_circle_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolCloseAgentRunning,
        failed: l10n.timelineToolCloseAgentFailed,
        succeeded: l10n.timelineToolCloseAgentSucceeded,
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
    return [...toolField(l10n, data, 'target', l10n.timelineToolDetailTarget)];
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) {
    if (result is! Map<String, dynamic>) {
      return toolAgentResult(l10n, result);
    }
    final values = <ToolDetailValue>[];
    final target = jsonStringValue(result['target']);
    if (target != null) {
      values.add(ToolDetailText(l10n.timelineToolDetailTarget, target));
    }
    if (result['agents'] case final List agents) {
      values.add(
        ToolDetailText(l10n.timelineToolDetailCount, '${agents.length}'),
      );
      for (final agent in agents) {
        final map = jsonObject(agent);
        final agentId = jsonStringValue(map['agentId']);
        if (agentId != null) {
          values.add(ToolDetailText(l10n.timelineToolDetailAgent, agentId));
        }
        if (map['executionClosed'] case final bool closed) {
          values.add(
            ToolDetailText(
              l10n.timelineToolDetailStatus,
              closed ? l10n.timelineToolStateClosed : l10n.timelineToolDetailNo,
            ),
          );
        }
      }
    }
    values.addAll(
      toolResultFields(l10n, toolTaskStateValues(l10n, result), {
        'status': l10n.timelineToolDetailStatus,
        'state': l10n.timelineToolDetailStatus,
        'summary': l10n.timelineToolDetailSummary,
        ...toolDiagnosticFields(l10n),
      }, unavailableWhenEmpty: false),
    );
    if (values.isEmpty && result.isNotEmpty) {
      return [ToolDetailUnavailable(l10n.timelineToolNoSemanticContent)];
    }
    return values;
  }
}
