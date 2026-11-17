import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'plan_result.dart';

final class PlanCurrentToolDisplay extends ToolDisplaySpec {
  const PlanCurrentToolDisplay()
    : super('builtin.plan_current@1', ToolDisplayCategory.planRead);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNamePlanCurrent;

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolPlanResult(l10n, result);
}
