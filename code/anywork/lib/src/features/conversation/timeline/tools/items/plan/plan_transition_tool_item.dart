import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/plan_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.plan_transition@1`.
class PlanTransitionToolItem extends StructuredTimelineToolAdapter {
  const PlanTransitionToolItem();

  static const String contractId = 'builtin.plan_transition@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNamePlanTransition;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.checklist_rtl);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolPlanRunning,
        failed: l10n.timelineToolPlanFailed,
        succeeded: l10n.timelineToolPlanSucceeded,
      );

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final arguments = toolArguments(l10n, text);
    final force = arguments['force'] == true;
    return [
      ...toolField(
        l10n,
        arguments,
        'targetState',
        l10n.timelineToolDetailTargetPhase,
      ),
      if (force) ToolDetailText(l10n.timelineToolDetailForceTransition, 'true'),
      ...toolField(l10n, arguments, 'reason', l10n.timelineToolDetailReason),
      ...toolField(
        l10n,
        arguments,
        'content',
        l10n.timelineToolDetailPlanContent,
      ),
    ];
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolPlanResult(l10n, result);
}
