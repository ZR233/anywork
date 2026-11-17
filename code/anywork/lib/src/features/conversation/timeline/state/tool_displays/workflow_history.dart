import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'workflow_result.dart';

final class WorkflowHistoryToolDisplay extends ToolDisplaySpec {
  const WorkflowHistoryToolDisplay()
    : super('builtin.workflow_history@1', ToolDisplayCategory.workflowRead);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWorkflowHistory;

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolWorkflowResult(l10n, result);
}
