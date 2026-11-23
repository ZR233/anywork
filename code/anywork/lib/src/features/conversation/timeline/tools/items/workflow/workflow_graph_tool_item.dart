import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/workflow_result_support.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.workflow_graph@1`.
class WorkflowGraphToolItem extends StructuredTimelineToolAdapter {
  const WorkflowGraphToolItem();

  static const String contractId = 'builtin.workflow_graph@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWorkflowGraph;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.route_outlined);

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolWorkflowResult(l10n, result);
}
