import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../support/workflow_result_support.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.workflow_transition@1`.
class WorkflowTransitionToolItem extends StructuredTimelineToolAdapter {
  const WorkflowTransitionToolItem();

  static const String contractId = 'builtin.workflow_transition@1';

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
      l10n.timelineToolNameWorkflowTransition;

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
  List<ToolDetailValue> input(AppLocalizations l10n, String text) =>
      switch (toolArguments(l10n, text)) {
        {
          'completion': {
            'reason': final String reason,
            'summary': final String summary,
            'evidence': final List evidence,
          },
        } =>
          [
            ToolDetailText(l10n.timelineToolDetailReason, reason),
            ToolDetailText(l10n.timelineToolDetailStageResult, summary),
            for (final record in evidence)
              switch (record) {
                final String value => ToolDetailText(
                  l10n.timelineToolDetailEvidence,
                  value,
                ),
                _ => throw FormatException(l10n.timelineToolInvalidEvidence),
              },
          ],
        _ => [ToolDetailUnavailable(l10n.timelineToolMissingCompletion)],
      };

  @override
  ToolAcceptanceProjection acceptanceFromResult(Object? result) =>
      toolWorkflowAcceptance(result);
}
