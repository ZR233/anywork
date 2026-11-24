import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/plan_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.plan_next@1`.
class PlanNextToolItem extends StructuredTimelineToolAdapter {
  const PlanNextToolItem();

  static const String contractId = 'builtin.plan_next@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNamePlanNext;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.checklist_rtl);

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolPlanResult(l10n, result);
}
