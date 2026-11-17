import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'plan_result.dart';

final class PlanNextToolDisplay extends ToolDisplaySpec {
  const PlanNextToolDisplay()
    : super('builtin.plan_next@1', ToolDisplayCategory.planRead);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNamePlanNext;

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolPlanResult(l10n, result);
}
