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

/// Adapter for `builtin.wait_agent@1` (and uncontracted live `wait_agent` atoms).
class WaitAgentToolItem extends StructuredTimelineToolAdapter {
  const WaitAgentToolItem();

  static const String contractId = 'builtin.wait_agent@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName('wait_agent', requireEmptyContract: true),
  ]);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWaitAgent;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.hourglass_bottom_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolWaitAgentRunning,
        failed: l10n.timelineToolWaitAgentFailed,
        succeeded: l10n.timelineToolWaitAgentSucceeded,
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
    final timeoutMs = data['timeoutMs'];
    return [
      ...toolField(l10n, data, 'target', l10n.timelineToolDetailTarget),
      ...toolField(l10n, data, 'after', l10n.timelineToolDetailCursor),
      if (timeoutMs is num)
        ToolDetailText(
          l10n.timelineToolDetailWait,
          l10n.timelineToolSeconds(timeoutMs / 1000),
        ),
    ];
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
    final cursor = jsonStringValue(result['cursor']);
    if (cursor != null) {
      values.add(ToolDetailText(l10n.timelineToolDetailCursor, cursor));
    }
    values.addAll(
      toolResultFields(l10n, toolTaskStateValues(l10n, result), {
        'reports': l10n.timelineToolDetailReport,
        'report': l10n.timelineToolDetailReport,
        'timedOut': l10n.timelineToolDetailWaitTimedOut,
        'status': l10n.timelineToolDetailStatus,
        'state': l10n.timelineToolDetailStatus,
        'summary': l10n.timelineToolDetailSummary,
        'text': l10n.timelineToolDetailContent,
        ...toolDiagnosticFields(l10n),
      }, unavailableWhenEmpty: false),
    );
    if (values.isEmpty && result.isNotEmpty) {
      return [ToolDetailUnavailable(l10n.timelineToolNoSemanticContent)];
    }
    return values;
  }
}
