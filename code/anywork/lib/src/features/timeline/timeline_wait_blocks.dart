import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_keys.dart';
import 'timeline_wait_indicator.dart';

/// Shared wait/sleep presentation for the live activity bar and historical tool cards.
class TimelineWaitPanel extends StatelessWidget {
  const TimelineWaitPanel({
    required this.presentation,
    required this.identity,
    this.diagnostics,
    super.key,
  });

  final ThreadWaitPresentationView presentation;
  final String identity;
  final Widget? diagnostics;

  @override
  Widget build(BuildContext context) {
    final title = _waitTitle(context, presentation);
    final subtitle = timelineWaitSubtitle(context, presentation);
    final waiting = presentation.state == ThreadWaitStateView.waiting;
    final panel = StudioPanel(
      key: StudioDriverKeys.waitingCard(identity),
      backgroundColor: context.colors.surfaceContainerLow,
      radius: StudioRadii.md,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('wait-expand:$identity'),
          maintainState: true,
          initiallyExpanded: false,
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (waiting)
                const TimelineWaitIndicator(
                  key: ValueKey('timeline-wait-pulse'),
                )
              else
                Icon(
                  _waitStateIcon(presentation.state),
                  size: 16,
                  color: _waitStateColor(context, presentation.state),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          subtitle: subtitle == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
          children: [
            TimelineWaitDetails(
              presentation: presentation,
              identity: identity,
              diagnostics: diagnostics,
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: subtitle == null ? title : '$title · $subtitle',
      child: panel,
    );
  }
}

class TimelineWaitDetails extends StatelessWidget {
  const TimelineWaitDetails({
    required this.presentation,
    required this.identity,
    this.diagnostics,
    super.key,
  });

  final ThreadWaitPresentationView presentation;
  final String identity;
  final Widget? diagnostics;

  @override
  Widget build(BuildContext context) {
    final sources = _waitSources(context, presentation);
    return Column(
      key: StudioDriverKeys.waitingDetails(identity),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final source in sources) ...[
          _WaitSourceRow(source: source),
          const SizedBox(height: 8),
        ],
        Text(
          _waitRule(context, presentation),
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        _WaitDiagnostics(
          identity: identity,
          presentation: presentation,
          diagnostics: diagnostics,
        ),
      ],
    );
  }
}

class _WaitSourceRow extends StatelessWidget {
  const _WaitSourceRow({required this.source});

  final _WaitSource source;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          source.icon,
          size: 16,
          color: context.statusColors.activeIndicator,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.title,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                source.status,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaitDiagnostics extends StatelessWidget {
  const _WaitDiagnostics({
    required this.identity,
    required this.presentation,
    this.diagnostics,
  });

  final String identity;
  final ThreadWaitPresentationView presentation;
  final Widget? diagnostics;

  @override
  Widget build(BuildContext context) {
    final text = _waitDiagnosticsText(presentation);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: StudioDriverKeys.waitingDiagnostics(identity),
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: Text(
          context.l10n.timelineWaitDiagnostics,
          style: context.text.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              text,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.4,
                fontFamily: 'monospace',
              ),
            ),
          ),
          ?diagnostics,
        ],
      ),
    );
  }
}

class _WaitSource {
  const _WaitSource({
    required this.icon,
    required this.title,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String status;
}

String _waitTitle(BuildContext context, ThreadWaitPresentationView wait) {
  final l10n = context.l10n;
  return switch ((wait.intent, wait.state)) {
    (ThreadWaitTimerIntentView(), ThreadWaitStateView.waiting) =>
      l10n.timelineWaitTimerTitle,
    (ThreadWaitTimerIntentView(), ThreadWaitStateView.elapsed) =>
      l10n.timelineWaitTimerElapsed,
    (ThreadWaitTimerIntentView(), ThreadWaitStateView.cancelled) =>
      l10n.timelineWaitCancelled,
    (ThreadWaitTimerIntentView(), ThreadWaitStateView.failed) =>
      l10n.timelineWaitFailed,
    (ThreadWaitTimerIntentView(), ThreadWaitStateView.interrupted) =>
      l10n.timelineWaitInterrupted,
    (ThreadWaitEventsIntentView(:final targets), ThreadWaitStateView.waiting)
        when targets.isEmpty =>
      l10n.timelineWaitMessagesTitle,
    (ThreadWaitEventsIntentView(), ThreadWaitStateView.waiting) =>
      l10n.timelineWaitToolsTitle,
    (ThreadWaitEventsIntentView(), ThreadWaitStateView.ready)
        when wait.messagesReady == true =>
      l10n.timelineWaitMessagesReady,
    (ThreadWaitEventsIntentView(), ThreadWaitStateView.ready) =>
      l10n.timelineWaitReady,
    (ThreadWaitEventsIntentView(), ThreadWaitStateView.timedOut) =>
      l10n.timelineWaitTimedOut,
    (ThreadWaitEventsIntentView(), ThreadWaitStateView.cancelled) =>
      l10n.timelineWaitCancelled,
    (ThreadWaitEventsIntentView(), ThreadWaitStateView.failed) =>
      l10n.timelineWaitFailed,
    (ThreadWaitEventsIntentView(), ThreadWaitStateView.interrupted) =>
      l10n.timelineWaitInterrupted,
    _ => l10n.timelineWaitToolsTitle,
  };
}

String? timelineWaitSubtitle(
  BuildContext context,
  ThreadWaitPresentationView wait,
) {
  final l10n = context.l10n;
  return switch (wait.intent) {
    ThreadWaitEventsIntentView(:final targets, :final timeoutMs) => () {
      String? primary;
      for (final target in targets) {
        final value = _waitTargetLabel(context, target);
        if (value.isNotEmpty) {
          primary = value;
          break;
        }
      }
      final count = targets.isEmpty
          ? l10n.timelineWaitMessageSource
          : l10n.timelineWaitTargetCount(targets.length);
      final duration = l10n.timelineWaitMaxDuration(_formatDuration(timeoutMs));
      final wake = l10n.timelineWaitMessagesMayWake;
      return [
        count,
        ?primary,
        duration,
        if (wait.state == ThreadWaitStateView.waiting) wake,
      ].join(' · ');
    }(),
    ThreadWaitTimerIntentView(:final durationMs) =>
      l10n.timelineWaitTimerDuration(_formatDuration(durationMs)),
  };
}

String _waitRule(BuildContext context, ThreadWaitPresentationView wait) {
  final l10n = context.l10n;
  return switch (wait.intent) {
    ThreadWaitEventsIntentView(:final timeoutMs) =>
      '${l10n.timelineWaitAnyReadyRule} · ${l10n.timelineWaitMaxDuration(_formatDuration(timeoutMs))}',
    ThreadWaitTimerIntentView(:final durationMs) =>
      l10n.timelineWaitTimerDuration(_formatDuration(durationMs)),
  };
}

List<_WaitSource> _waitSources(
  BuildContext context,
  ThreadWaitPresentationView wait,
) {
  final l10n = context.l10n;
  return switch (wait.intent) {
    ThreadWaitEventsIntentView(:final targets) => [
      for (final target in targets)
        _WaitSource(
          icon: _waitTargetIcon(target.toolName),
          title: _waitTargetLabel(context, target),
          status: _waitTargetStatus(context, target.status),
        ),
      _WaitSource(
        icon: Icons.chat_bubble_outline,
        title: l10n.timelineWaitMessageSource,
        status: wait.messagesReady == true
            ? l10n.timelineWaitMessagesReady
            : l10n.timelineWaitMessagesMayWake,
      ),
    ],
    ThreadWaitTimerIntentView(:final durationMs) => [
      _WaitSource(
        icon: Icons.timer_outlined,
        title: l10n.timelineWaitTimerTitle,
        status: l10n.timelineWaitTimerDuration(_formatDuration(durationMs)),
      ),
    ],
  };
}

String _waitTargetLabel(BuildContext context, ThreadWaitTargetView target) {
  final summary = target.summary?.trim();
  if (summary != null && summary.isNotEmpty) {
    return target.summaryTruncated ? '$summary…' : summary;
  }
  final toolName = target.toolName?.trim();
  if (toolName != null && toolName.isNotEmpty) return toolName;
  return context.l10n.timelineWaitTargetCount(1);
}

String _waitTargetStatus(
  BuildContext context,
  ThreadWaitTargetStatusView? status,
) {
  final l10n = context.l10n;
  return switch (status) {
    ThreadWaitTargetStatusView.running => l10n.timelineWaitStatusRunning,
    ThreadWaitTargetStatusView.succeeded => l10n.timelineWaitStatusSucceeded,
    ThreadWaitTargetStatusView.failed => l10n.timelineWaitStatusFailed,
    ThreadWaitTargetStatusView.cancelled => l10n.timelineWaitStatusCancelled,
    ThreadWaitTargetStatusView.interrupted =>
      l10n.timelineWaitStatusInterrupted,
    null => l10n.timelineWaitUnknownStatus,
  };
}

IconData _waitTargetIcon(String? toolName) {
  return switch (toolName) {
    'exec' || 'write_stdin' => Icons.terminal,
    'spawn_agent' || 'send_message' => Icons.account_tree_outlined,
    'sleep' => Icons.timer_outlined,
    _ => Icons.build_outlined,
  };
}

IconData _waitStateIcon(ThreadWaitStateView state) {
  return switch (state) {
    ThreadWaitStateView.waiting => Icons.schedule,
    ThreadWaitStateView.ready ||
    ThreadWaitStateView.elapsed => Icons.check_rounded,
    ThreadWaitStateView.timedOut => Icons.hourglass_bottom,
    ThreadWaitStateView.cancelled => Icons.remove_rounded,
    ThreadWaitStateView.failed => Icons.error_outline,
    ThreadWaitStateView.interrupted => Icons.stop_circle_outlined,
  };
}

Color _waitStateColor(BuildContext context, ThreadWaitStateView state) {
  return switch (state) {
    ThreadWaitStateView.waiting => context.statusColors.activeIndicator,
    ThreadWaitStateView.ready ||
    ThreadWaitStateView.elapsed => context.statusColors.success,
    ThreadWaitStateView.timedOut => context.statusColors.warning,
    ThreadWaitStateView.cancelled => context.colors.onSurfaceVariant,
    ThreadWaitStateView.failed ||
    ThreadWaitStateView.interrupted => context.colors.error,
  };
}

String _waitDiagnosticsText(ThreadWaitPresentationView wait) {
  final buffer = StringBuffer()
    ..writeln('state=${wait.state.name}')
    ..writeln('messagesReady=${wait.messagesReady}');
  switch (wait.intent) {
    case ThreadWaitEventsIntentView(:final targets, :final timeoutMs):
      buffer.writeln('timeoutMs=$timeoutMs');
      for (final target in targets) {
        buffer.writeln(
          [
            target.taskId,
            target.toolName,
            if (target.summaryTruncated) 'summaryTruncated',
            target.status?.name,
          ].whereType<String>().join(' '),
        );
      }
    case ThreadWaitTimerIntentView(:final durationMs):
      buffer.writeln('durationMs=$durationMs');
  }
  return buffer.toString().trim();
}

String _formatDuration(int milliseconds) {
  if (milliseconds < 1000) return '${milliseconds}ms';
  final seconds = milliseconds / 1000;
  if (seconds < 60) {
    return seconds == seconds.roundToDouble()
        ? '${seconds.round()}s'
        : '${seconds.toStringAsFixed(1)}s';
  }
  final minutes = seconds / 60;
  if (minutes < 60) {
    return minutes == minutes.roundToDouble()
        ? '${minutes.round()}m'
        : '${minutes.toStringAsFixed(1)}m';
  }
  final hours = minutes / 60;
  return hours == hours.roundToDouble()
      ? '${hours.round()}h'
      : '${hours.toStringAsFixed(1)}h';
}
