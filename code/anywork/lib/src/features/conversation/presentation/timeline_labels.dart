import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../timeline/presentation_item.dart';

String timelineToolLabel(BuildContext context, ThreadItemView item) {
  final name = item.tool?.name ?? context.l10n.timelineToolFallback;
  final l10n = context.l10n;
  return switch (item.status) {
    'succeeded' => l10n.timelineToolCompleted(name),
    'failed' || 'budgetLimited' => l10n.timelineToolFailed(name),
    'denied' => l10n.timelineToolDenied(name),
    'cancelled' => l10n.timelineToolCancelled(name),
    'awaitingApproval' => l10n.timelineToolAwaitingApproval(name),
    'running' ||
    'started' ||
    'streaming' ||
    'approved' => l10n.timelineToolRunning(name),
    'queued' => l10n.timelineToolQueued(name),
    'cancelling' => l10n.timelineToolCancelling(name),
    'interrupted' => l10n.timelineToolInterrupted(name),
    _ => l10n.timelineToolUnknownStatus(name, item.status),
  };
}

String timelineThinkingLabel(
  BuildContext context,
  Iterable<TimelineMessagePayload> members,
) {
  var active = false, failed = false, cancelled = false, unknown = false;
  var seconds = 0;
  for (final payload in members) {
    final item = payload.item;
    if (item.state is! ThreadThinkingItemStateView) continue;
    active = active || !item.isTerminal;
    failed = failed || item.status == 'failed';
    cancelled = cancelled || item.status == 'cancelled';
    final completedAt = item.completedAt;
    if (completedAt == null || completedAt < item.createdAt) {
      unknown = true;
    } else {
      seconds += completedAt - item.createdAt;
    }
  }
  final l10n = context.l10n;
  if (active) return l10n.timelineReasoningActive;
  if (failed) return l10n.timelineReasoningFailed;
  if (cancelled) return l10n.timelineReasoningCancelled;
  if (unknown) return l10n.timelineReasoningEnded;
  if (seconds == 0) return l10n.timelineReasoningElapsedUnderSecond;
  if (seconds < 60) return l10n.timelineReasoningElapsedSeconds(seconds);
  return seconds % 60 == 0
      ? l10n.timelineReasoningElapsedMinutes(seconds ~/ 60)
      : l10n.timelineReasoningElapsedMinutesSeconds(
          seconds ~/ 60,
          seconds % 60,
        );
}

String timelineGroupLabel(BuildContext context, TimelinePresentationItem item) {
  final l10n = context.l10n;
  if (item is TimelineRecoveryGroup) return item.latest.item.text;
  if (item is TimelineImageReadGroup) {
    return [
      if (item.imageCount > 0) l10n.timelineImagesViewed(item.imageCount),
      if (item.issueCount > 0)
        l10n.timelineViewImageFailed
      else if (item.activeCount > 0)
        l10n.timelineViewImageReading,
    ].join(' · ');
  }
  if (item.thinkingCount > 0 && item.toolCount == 0 && item.skillCount == 0) {
    return timelineThinkingLabel(context, item.payloads);
  }
  final counts = [
    if (item.toolCount > 0)
      switch ((item.issueCount > 0, item.runningToolCount > 0)) {
        (true, true) => l10n.timelineToolGroupSummaryRunningWithIssues(
          item.toolCount,
          item.runningToolCount,
          item.issueCount,
        ),
        (true, false) => l10n.timelineToolGroupSummaryIssues(
          item.toolCount,
          item.issueCount,
        ),
        (false, true) => l10n.timelineToolGroupSummaryRunning(
          item.toolCount,
          item.runningToolCount,
        ),
        (false, false) => l10n.timelineToolGroupSummary(item.toolCount),
      },
    if (item.skillCount > 0) l10n.statusSkillsCount(item.skillCount),
  ];
  if (item.toolCount == 0 && item.thinkingCount == 0 && counts.isNotEmpty) {
    return counts.join(' · ');
  }
  return [
    item.thinkingCount == 0
        ? l10n.timelineToolGroupTitle
        : l10n.timelineActivityTitle,
    ...counts,
  ].join(' · ');
}

IconData timelineGroupIcon(TimelinePresentationItem item) =>
    switch (item.kind) {
      TimelinePresentationKind.images ||
      TimelinePresentationKind.imageCard => Icons.image_outlined,
      TimelinePresentationKind.recovery => Icons.sync,
      _ when item.thinkingCount == 0 && item.toolCount == 0 =>
        Icons.extension_outlined,
      _ =>
        item.thinkingCount > 0
            ? Icons.psychology_alt_outlined
            : Icons.build_outlined,
    };
