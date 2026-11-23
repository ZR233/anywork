import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../support/workflow_result_support.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.workflow_restart@1`.
class WorkflowRestartToolItem extends StructuredTimelineToolAdapter {
  const WorkflowRestartToolItem();

  static const String contractId = 'builtin.workflow_restart@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy(
    omitSuccessOutput: true,
    requiresAcceptance: true,
  );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWorkflowRestart;

  @override
  String rejectionLabel(AppLocalizations l10n) =>
      l10n.timelineToolWorkflowRejected;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.route_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolWorkflowRunning
        : failed
        ? l10n.timelineToolWorkflowFailed
        : l10n.timelineToolWorkflowSucceeded;
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'reason',
    l10n.timelineToolDetailReason,
  );

  @override
  ToolAcceptanceProjection acceptanceFromResult(Object? result) =>
      toolWorkflowAcceptance(result);
}
