import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/agent_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.interrupt_agent@1` (and uncontracted live
/// `interrupt_agent` atoms).
class InterruptAgentToolItem extends StructuredTimelineToolAdapter {
  const InterruptAgentToolItem();

  static const String contractId = 'builtin.interrupt_agent@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName('interrupt_agent', requireEmptyContract: true),
  ]);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameInterruptAgent;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.pause_circle_outline);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolInterruptAgentRunning,
        failed: l10n.timelineToolInterruptAgentFailed,
        succeeded: l10n.timelineToolInterruptAgentSucceeded,
        backgroundStarted: l10n.timelineToolStateBackgroundStarted,
        backgrounded: l10n.timelineToolStateBackgrounded,
      );

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) => toolAgentRowTarget(item);

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    return [
      ...toolField(l10n, data, 'target', l10n.timelineToolDetailTarget),
      ...toolField(l10n, data, 'reason', l10n.timelineToolDetailReason),
    ];
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, result, {
        'target': l10n.timelineToolDetailTarget,
        'interrupted': l10n.timelineToolStateInterrupted,
        'status': l10n.timelineToolDetailStatus,
        'state': l10n.timelineToolDetailStatus,
        'summary': l10n.timelineToolDetailSummary,
      });
}
