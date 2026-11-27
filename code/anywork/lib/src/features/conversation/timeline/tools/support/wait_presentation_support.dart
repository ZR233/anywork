import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../shared/studio_driver_keys.dart';
import '../../widgets/timeline_activity_row.dart';
import '../../widgets/timeline_wait_blocks.dart';
import '../tool_item_adapter.dart';

/// Builds collapsed single-line row summary for unified `wait` / `sleep` tool
/// items using shared [ThreadWaitPresentationView] formatting when a live or
/// canonical wait presentation is present, or delegating to [fallbackSummary]
/// otherwise.
TimelineToolRowSummary buildWaitToolRowSummary(
  TimelineToolItemContext context, {
  required TimelineToolRowSummary Function(TimelineToolItemContext context)
  fallbackSummary,
}) {
  final wait = context.item.wait;
  if (wait == null) {
    return fallbackSummary(context);
  }

  final title = waitTitle(context.buildContext, wait);
  final rowLabel = waitRowLabel(context.buildContext, wait);
  final subtitle = timelineWaitSubtitle(context.buildContext, wait);
  final waiting = wait.state == ThreadWaitStateView.waiting;
  final failed = wait.state == ThreadWaitStateView.failed;
  return TimelineToolRowSummary(
    icon: TimelineToolIcon.data(
      waitStateIcon(wait.state),
      color: waiting ? null : waitStateColor(context.buildContext, wait.state),
      activeIndicatorStyle: TimelineActivityIndicatorStyle.rotating,
      preserveWhenStopped: true,
    ),
    label: rowLabel,
    active: waiting && !context.staticObservation,
    isIssue: failed,
    isStopped: false,
    cardKey: StudioDriverKeys.waitingCard(context.item.id),
    disclosureKey: ValueKey('wait-expand:${context.item.id}'),
    semanticsLabel: subtitle == null ? title : '$title · $subtitle',
  );
}

/// Builds expanded disclosure children for `wait` / `sleep` items, preserving
/// lazy diagnostics disclosure (so `tool.result` is not read until diagnostics
/// itself is expanded) when `wait != null`, and standard detail panel otherwise.
List<Widget> buildWaitToolExpandedChildren(
  TimelineToolItemContext context,
  TimelineToolExpandedSlots slots,
) {
  final wait = context.item.wait;
  if (wait == null) {
    return slots.standardPanel == null ? const [] : [slots.standardPanel!];
  }
  return [
    TimelineWaitDetails(
      presentation: wait,
      identity: context.item.id,
      diagnostics: slots.standardPanel,
    ),
  ];
}
