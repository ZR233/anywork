import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'plan_result.dart';

final class PlanRestartToolDisplay extends ToolDisplaySpec {
  const PlanRestartToolDisplay()
    : super('builtin.plan_restart@1', ToolDisplayCategory.plan);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNamePlanRestart;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'reason',
    l10n.timelineToolDetailReason,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolPlanResult(l10n, result);
}
