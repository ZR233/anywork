import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'workflow_result.dart';

final class WorkflowTransitionToolDisplay extends ToolDisplaySpec {
  const WorkflowTransitionToolDisplay()
    : super(
        'builtin.workflow_transition@1',
        ToolDisplayCategory.workflow,
        omitSuccessOutput: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWorkflowTransition;

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
  bool get requiresAcceptance => true;

  @override
  String rejectionLabel(AppLocalizations l10n) =>
      l10n.timelineToolWorkflowRejected;

  @override
  ToolAcceptanceProjection acceptanceFromResult(Object? result) =>
      toolWorkflowAcceptance(result);
}
