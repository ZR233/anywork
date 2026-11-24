import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/task_state_values_support.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../support/wait_presentation_support.dart';
import '../../tool_item_adapter.dart';

/// Unified adapter for `builtin.wait@1` (and uncontracted live `wait` atoms
/// carrying a `ThreadWaitPresentationView` payload).
class WaitToolItem extends StructuredTimelineToolAdapter {
  const WaitToolItem();

  static const String contractId = 'builtin.wait@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName(
      'wait',
      requireEmptyContract: true,
      requireWaitPayload: true,
    ),
  ]);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWait;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.hourglass_empty);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolWaitRunning
        : failed
        ? l10n.timelineToolWaitFailed
        : l10n.timelineToolWaitSucceeded;
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, toolTaskStateValues(l10n, result), {
        'tasks': l10n.timelineToolDetailTaskStatus,
        'timedOut': l10n.timelineToolDetailWaitTimedOut,
        'messagesReady': l10n.timelineToolDetailMessagesReady,
        'status': l10n.timelineToolDetailStatus,
        'state': l10n.timelineToolDetailStatus,
      });

  @override
  TimelineToolRowSummary buildRowSummary(TimelineToolItemContext context) =>
      buildWaitToolRowSummary(context, fallbackSummary: super.buildRowSummary);

  @override
  List<Widget> buildExpandedChildren(
    TimelineToolItemContext context,
    TimelineToolExpandedSlots slots,
  ) => buildWaitToolExpandedChildren(context, slots);
}
