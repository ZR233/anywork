import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../support/wait_presentation_support.dart';
import '../../tool_item_adapter.dart';

/// Unified adapter for `builtin.sleep@1` (and uncontracted live `sleep` atoms
/// carrying a `ThreadWaitPresentationView` payload).
class SleepToolItem extends StructuredTimelineToolAdapter {
  const SleepToolItem();

  static const String contractId = 'builtin.sleep@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName(
      'sleep',
      requireEmptyContract: true,
      requireWaitPayload: true,
    ),
  ]);

  @override
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy(
    omitSuccessOutput: true,
    readsStructuredOutput: false,
  );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameSleep;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.hourglass_empty);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolWaitRunning,
        failed: l10n.timelineToolWaitFailed,
        succeeded: l10n.timelineToolWaitSucceeded,
      );

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) =>
      switch (toolArguments(l10n, text)) {
        {'durationMs': final num ms} => [
          ToolDetailText(
            l10n.timelineToolDetailWait,
            l10n.timelineToolSeconds(ms / 1000),
          ),
        ],
        _ => throw FormatException(l10n.timelineToolMissingDuration),
      };

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolTextResult(l10n, result);

  @override
  TimelineToolRowSummary buildRowSummary(TimelineToolItemContext context) =>
      buildWaitToolRowSummary(context, fallbackSummary: super.buildRowSummary);

  @override
  List<Widget> buildExpandedChildren(
    TimelineToolItemContext context,
    TimelineToolExpandedSlots slots,
  ) => buildWaitToolExpandedChildren(context, slots);
}
