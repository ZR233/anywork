import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'plan_result.dart';

final class PlanSubmitToolDisplay extends ToolDisplaySpec {
  const PlanSubmitToolDisplay()
    : super('builtin.plan_submit@1', ToolDisplayCategory.plan);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNamePlanSubmit;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    return toolField(
      l10n,
      toolArguments(l10n, text),
      'plan',
      l10n.timelineToolDetailPlanContent,
      required: true,
    );
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolPlanResult(l10n, result);
}
