import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'workflow_result.dart';

final class WorkflowNextToolDisplay extends ToolDisplaySpec {
  const WorkflowNextToolDisplay()
    : super('builtin.workflow_next@1', ToolDisplayCategory.workflowRead);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWorkflowNext;

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolWorkflowResult(l10n, result);
}
