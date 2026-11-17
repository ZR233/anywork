import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'workflow_result.dart';

final class WorkflowCurrentToolDisplay extends ToolDisplaySpec {
  const WorkflowCurrentToolDisplay()
    : super('builtin.workflow_current@1', ToolDisplayCategory.workflowRead);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWorkflowCurrent;

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolWorkflowResult(l10n, result);
}
