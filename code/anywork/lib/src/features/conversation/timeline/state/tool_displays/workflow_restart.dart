import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'workflow_result.dart';

final class WorkflowRestartToolDisplay extends ToolDisplaySpec {
  const WorkflowRestartToolDisplay()
    : super(
        'builtin.workflow_restart@1',
        ToolDisplayCategory.workflow,
        omitSuccessOutput: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWorkflowRestart;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'reason',
    l10n.timelineToolDetailReason,
  );

  @override
  bool get requiresAcceptance => true;

  @override
  String rejectionLabel(AppLocalizations l10n) =>
      l10n.timelineToolWorkflowRejected;

  @override
  ToolAcceptanceProjection acceptanceFromResult(Object? result) =>
      toolWorkflowAcceptance(result);
}
