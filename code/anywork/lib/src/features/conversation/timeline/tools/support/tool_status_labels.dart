import 'package:material_ui/material_ui.dart';

import '../../../../../app/theme/studio_tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../l10n/studio_l10n.dart';
import '../../state/tool_presentation.dart';
import 'tool_detail_values.dart';

const Set<String> timelineToolRunningStatuses = {
  'running',
  'streaming',
  'approved',
  'started',
};

const Set<String> timelineToolActiveStatuses = {
  'queued',
  ...timelineToolRunningStatuses,
  'waiting',
  'cancelling',
  'awaitingApproval',
  'waitingApproval',
};

/// Real failures, denials, and budget limits: icon becomes error_outline while
/// cancelled/interrupted keep neutral secondary tone.
const Set<String> timelineIssueStatuses = {'failed', 'denied', 'budgetLimited'};

const Set<String> timelineStoppedStatuses = {'cancelled', 'interrupted'};

bool isTimelineToolActive(String status) =>
    timelineToolActiveStatuses.contains(status);

bool isTimelineToolIssue(String status) =>
    timelineIssueStatuses.contains(status);

bool isTimelineToolStopped(String status) =>
    timelineStoppedStatuses.contains(status);

/// Selects a tool's action wording without treating queued, stopped or unknown
/// states as successful completion. Those states use the full status title.
String? toolLifecycleVerb(
  String status, {
  required String running,
  required String failed,
  required String succeeded,
  String? backgroundStarted,
  String? backgrounded,
}) => switch (status) {
  final status when timelineToolRunningStatuses.contains(status) => running,
  'failed' => failed,
  'succeeded' || 'completed' => succeeded,
  'backgroundStarted' => backgroundStarted,
  'backgrounded' => backgrounded,
  _ => null,
};

String toolStatusTitle(AppLocalizations l10n, String status, String name) {
  final label = name.trim().isEmpty ? l10n.timelineToolFallback : name;
  return switch (status) {
    'queued' => l10n.timelineToolQueued(label),
    'waiting' => l10n.timelineToolWaiting(label),
    'cancelling' => l10n.timelineToolCancelling(label),
    'interrupted' => l10n.timelineToolInterrupted(label),
    'succeeded' || 'completed' => l10n.timelineToolCompleted(label),
    'failed' => l10n.timelineToolFailed(label),
    'denied' => l10n.timelineToolDenied(label),
    'cancelled' => l10n.timelineToolCancelled(label),
    'awaitingApproval' ||
    'waitingApproval' => l10n.timelineToolAwaitingApproval(label),
    'backgroundStarted' => l10n.timelineToolBackgroundStarted(label),
    'backgrounded' => l10n.timelineToolBackgrounded(label),
    'running' ||
    'streaming' ||
    'approved' ||
    'started' => l10n.timelineToolRunning(label),
    _ =>
      status.trim().isEmpty
          ? label
          : l10n.timelineToolUnknownStatus(label, status),
  };
}

/// Computes elapsed execution duration only from creation and canonical terminal
/// timestamps (never saved/updated timestamps).
Duration? toolElapsed(TimelineToolPresentation item) {
  final createdAt = item.createdAt;
  final completedAt = item.completedAt;
  if (createdAt == null || completedAt == null) return null;
  final elapsed = completedAt.difference(createdAt);
  return elapsed.isNegative ? null : elapsed;
}

/// Colour used for trailing diagnostic error text in expanded panels.
Color toolDiagnosticColor(
  BuildContext context,
  TimelineToolPresentation item,
) => switch (item.statusString) {
  'cancelled' || 'interrupted' => context.colors.onSurfaceVariant,
  _ => context.colors.error,
};

/// Expanded diagnostics containing exit code, timeout flag, and attachments,
/// never repeating raw target or internal task identities.
List<String> toolDiagnostics(
  BuildContext context,
  TimelineToolPresentation item,
) {
  return [
        if (item.exitCode != null)
          context.l10n.timelineToolExitCode(item.exitCode!),
        if (item.timedOut) context.l10n.timelineToolTimedOut,
        _attachmentDetail(context, item),
      ]
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .toList();
}

String? _attachmentDetail(BuildContext context, TimelineToolPresentation item) {
  final attachments = item.attachments;
  if (attachments.isEmpty) return null;
  return attachments
      .map((attachment) => timelineAttachmentDescription(context, attachment))
      .join('\n');
}
