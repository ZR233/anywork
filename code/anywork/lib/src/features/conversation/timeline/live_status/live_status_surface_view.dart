import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../connectors/interaction_details_connector.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_activity_viewport.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/timeline_activity_clock.dart';
import '../widgets/timeline_activity_row.dart';
import '../widgets/timeline_activity_section.dart';
import '../widgets/timeline_markdown.dart';
import '../widgets/timeline_reasoning_view.dart';
import '../widgets/timeline_work_group_shell.dart';
import 'live_status_state.dart';

/// 实时状态栏唯一纯 UI 表面：直接消费扁平单状态 [LiveStatusState]。
///
/// 采用概念稿对齐的轻量卡片几何（固定 `32×32` 左侧图标槽与表格式等宽计时），
/// 用布局区分思考、工具折叠列表、文本流输出与异常状态，杜绝二级副标题与重复堆叠行。
class LiveStatusSurfaceView extends StatelessWidget {
  const LiveStatusSurfaceView({
    required this.state,
    this.viewportKey,
    this.liveWorkInitiallyExpanded = false,
    this.now,
    super.key,
  });

  final LiveStatusState state;
  final Key? viewportKey;
  final bool liveWorkInitiallyExpanded;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => switch (state) {
    LiveStatusHidden() => const SizedBox.shrink(),
    LiveStatusChildInteractionState(:final interactionId, :final payload) =>
      ConversationActivityViewport(
        key: viewportKey,
        children: [
          ReadOnlyInteractionDetails(
            key: ValueKey(interactionId),
            id: interactionId,
            payload: payload,
          ),
        ],
      ),
    final LiveStatusWorkingState working => ConversationActivityViewport(
      key: viewportKey,
      fixedActivity: ConversationActivityBar(
        children: [
          _WorkingCard(
            key: ValueKey(('live-work', working.threadId)),
            working: working,
            initiallyExpanded: liveWorkInitiallyExpanded,
            now: now,
          ),
        ],
      ),
      children: const [],
    ),
    final LiveStatusStreamingState streaming => ConversationActivityViewport(
      key: viewportKey,
      children: [
        ConversationActivityBar(
          children: [
            Flexible(
              key: ValueKey(('live-streaming', streaming.itemId)),
              fit: FlexFit.loose,
              child: ConversationResponseView(
                startedAt: streaming.startedAtMs == null
                    ? null
                    : streaming.startedAtMs! ~/ 1000,
                now: now,
                child: ConversationCurrentWindowView(
                  id: streaming.itemId,
                  text: streaming.text,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
    final LiveStatusCompactingState compacting => _SingleStatusCard(
      viewportKey: viewportKey,
      contentKey: const ValueKey('live-compacting'),
      child: _CompactingRow(compacting: compacting, now: now),
    ),
    final LiveStatusReconnectingState reconnecting => _SingleStatusCard(
      viewportKey: viewportKey,
      contentKey: const ValueKey('live-reconnecting'),
      child: _ReconnectingRow(reconnecting: reconnecting, now: now),
    ),
    final LiveStatusStoppingState stopping => _SingleStatusCard(
      viewportKey: viewportKey,
      contentKey: const ValueKey('live-stopping'),
      child: _StoppingRow(stopping: stopping, now: now),
    ),
    final LiveStatusAlertState alert => _SingleStatusCard(
      viewportKey: viewportKey,
      contentKey: ValueKey(('live-alert', alert.kind)),
      child: _AlertRow(alert: alert),
    ),
  };
}

class _SingleStatusCard extends StatelessWidget {
  const _SingleStatusCard({
    required this.viewportKey,
    required this.contentKey,
    required this.child,
  });

  final Key? viewportKey;
  final Key contentKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConversationActivityViewport(
    key: viewportKey,
    children: [
      ConversationActivityBar(
        children: [
          Flexible(
            key: contentKey,
            fit: FlexFit.loose,
            child: TimelineActivitySection(header: child),
          ),
        ],
      ),
    ],
  );
}

class _WorkingCard extends StatelessWidget {
  const _WorkingCard({
    required this.working,
    required this.initiallyExpanded,
    required this.now,
    super.key,
  });

  final LiveStatusWorkingState working;
  final bool initiallyExpanded;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    if (working.items.isEmpty) {
      return TimelineActivitySection(
        header: _buildHeader(context, expanded: false, expandable: false),
      );
    }

    return TimelineWorkGroupShell(
      scrollBody: true,
      railInset: 15.5,
      railContentInset: 25.5,
      initiallyExpanded: initiallyExpanded,
      disclosureKey: ValueKey('live-work-disclosure:${working.threadId}'),
      headerBuilder: (context, expanded) =>
          _buildHeader(context, expanded: expanded, expandable: true),
      bodyBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final member in working.items)
            _LiveWorkMemberRow(
              key: ValueKey(member.id),
              member: member,
              now: now,
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required bool expanded,
    required bool expandable,
  }) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TimelineActivityClock(
      startedAtMillis: working.startedAtMs,
      running: true,
      now: now,
      builder: (context, seconds) {
        final duration = seconds == null
            ? null
            : activityDurationLabel(
                context,
                seconds,
                kind: ActivityDurationKind.executing,
              );
        final preview = working.reasoningPreview?.trim();
        final hasSummary = preview != null && preview.isNotEmpty;
        final fallbackTitle = expandable
            ? context.l10n.timelineActivityTitle
            : context.l10n.timelineReasoningActive;
        final label = hasSummary ? preview : fallbackTitle;
        final titleStyle = context.text.bodySmall!.copyWith(
          color: context.colors.onSurface,
          fontSize: TimelineActivityRow.headerFontSize,
          fontWeight: FontWeight.w500,
          height: 1.36,
        );
        final labelWidget = hasSummary && timelineNeedsSafeMarkdown(preview)
            ? TimelineReasoningSummary(
                key: ValueKey('live-work-summary:${working.threadId}'),
                id: 'live-work-summary',
                text: preview,
                style: titleStyle,
                strutStyle: TimelineActivityRow.headerStrutStyle,
                inlineCodeBackgroundColor: context.colors.surfaceContainerHigh
                    .withValues(alpha: .75),
              )
            : null;
        final indicator = working.hasRunningCommand && !hasSummary
            ? TimelineActivityIndicatorStyle.circularProgress
            : TimelineActivityIndicatorStyle.restingCat;
        return TimelineActivityRow(
          key: ValueKey('live-work-header:${working.threadId}'),
          label: label,
          labelWidget: labelWidget,
          labelColor: titleStyle.color,
          icon: Icons.psychology_outlined,
          iconColor: StudioTone.active.indicator(context),
          indicatorStyle: indicator,
          active: !reducedMotion,
          emphasized: true,
          header: true,
          expandable: expandable,
          expanded: expanded,
          meta: duration,
          metaKey: const ValueKey('conversation-activity-trailing-meta'),
          tooltip: duration == null ? label : '$label，$duration',
          semanticsLabel: duration == null ? label : '$label，$duration',
        );
      },
    );
  }
}

class _LiveWorkMemberRow extends StatelessWidget {
  const _LiveWorkMemberRow({
    required this.member,
    required this.now,
    super.key,
  });

  final LiveWorkMember member;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final verb = _memberVerb(context, member);
    final summary = member.summary.trim();
    final label =
        summary.isEmpty || summary == verb || summary == member.toolName
        ? verb
        : '$verb · $summary';
    final (icon, iconColor, isIssue) = _memberVisual(context, member);

    return TimelineActivityClock(
      startedAtMillis: member.startedAtMs,
      finishedAtMillis: member.finishedAtMs,
      running: member.isActive,
      now: now,
      builder: (context, seconds) {
        final duration = seconds == null
            ? null
            : activityDurationLabel(
                context,
                seconds,
                kind: ActivityDurationKind.elapsed,
              );
        return TimelineActivityRow(
          label: label,
          icon: icon,
          iconColor: iconColor,
          isIssue: isIssue,
          active: member.isActive && !reducedMotion,
          indicatorStyle: TimelineActivityIndicatorStyle.circularProgress,
          expandable: false,
          meta: duration,
          tooltip: summary.isEmpty ? label : '$label ($summary)',
          semanticsLabel: duration == null ? label : '$label，$duration',
        );
      },
    );
  }

  static String _memberVerb(BuildContext context, LiveWorkMember member) {
    final l10n = context.l10n;
    return switch (member.kind) {
      'thinking' => l10n.liveWorkKindThinking,
      'read' || 'readImage' => l10n.liveWorkKindRead,
      'edit' => l10n.liveWorkKindEdit,
      'search' => l10n.liveWorkKindSearch,
      'command' => l10n.liveWorkKindExec,
      'wait' => l10n.liveWorkKindWait,
      'agent' => l10n.liveWorkKindAgent,
      _ => member.toolName.isNotEmpty ? member.toolName : l10n.liveWorkKindTool,
    };
  }

  static (IconData, Color, bool) _memberVisual(
    BuildContext context,
    LiveWorkMember member,
  ) {
    if (member.isFailed) {
      return (Icons.error_outline, context.colors.error, true);
    }
    if (member.isCancelled) {
      return (
        Icons.cancel_outlined,
        context.colors.onSurfaceVariant.withValues(alpha: .68),
        false,
      );
    }
    if (member.isCompleted) {
      return (
        Icons.check_circle_outline,
        StudioTone.success.indicator(context),
        false,
      );
    }
    final kindIcon = switch (member.kind) {
      'thinking' => Icons.psychology_outlined,
      'read' || 'readImage' => Icons.description_outlined,
      'edit' => Icons.edit_outlined,
      'search' => Icons.search,
      'command' => Icons.terminal,
      'wait' => Icons.hourglass_bottom_outlined,
      'agent' => Icons.hub_outlined,
      _ => Icons.build_outlined,
    };
    return (kindIcon, StudioTone.active.indicator(context), false);
  }
}

class _CompactingRow extends StatelessWidget {
  const _CompactingRow({required this.compacting, required this.now});

  final LiveStatusCompactingState compacting;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final label = context.l10n.conversationActivityCompacting;
    return TimelineActivityClock(
      startedAtMillis: compacting.startedAtMs,
      running: true,
      now: now,
      builder: (context, seconds) {
        final duration = seconds == null
            ? null
            : activityDurationLabel(
                context,
                seconds,
                kind: ActivityDurationKind.elapsed,
              );
        return TimelineActivityRow(
          label: label,
          icon: Icons.compress_outlined,
          iconColor: StudioTone.active.indicator(context),
          indicatorStyle: TimelineActivityIndicatorStyle.compactingZip,
          active: !reducedMotion,
          emphasized: true,
          header: true,
          expandable: false,
          meta: duration,
          metaKey: const ValueKey('conversation-activity-trailing-meta'),
          tooltip: duration == null ? label : '$label，$duration',
          semanticsLabel: duration == null ? label : '$label，$duration',
        );
      },
    );
  }
}

class _ReconnectingRow extends StatelessWidget {
  const _ReconnectingRow({required this.reconnecting, required this.now});

  final LiveStatusReconnectingState reconnecting;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final l10n = context.l10n;
    final label = reconnecting.maxAttempts > 0
        ? l10n.liveStatusModelReconnecting(
            reconnecting.attempt,
            reconnecting.maxAttempts,
          )
        : l10n.liveStatusConnectionReconnecting;
    final detail = reconnecting.message.trim();
    return _RetryCountdown(
      retryAfterMs: reconnecting.retryAfterMs,
      now: now,
      builder: (context, seconds) {
        final retryMeta = seconds == null
            ? null
            : l10n.timelineRetryAfterSeconds('$seconds');
        return TimelineActivityRow(
          label: label,
          icon: Icons.sync_outlined,
          iconColor: StudioTone.warning.indicator(context),
          indicatorStyle: TimelineActivityIndicatorStyle.circularProgress,
          active: !reducedMotion,
          emphasized: true,
          header: true,
          expandable: false,
          meta: retryMeta,
          metaKey: const ValueKey('conversation-activity-trailing-meta'),
          tooltip: detail.isEmpty ? label : detail,
          semanticsLabel: retryMeta == null ? label : '$label，$retryMeta',
        );
      },
    );
  }
}

class _StoppingRow extends StatelessWidget {
  const _StoppingRow({required this.stopping, required this.now});

  final LiveStatusStoppingState stopping;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final label = context.l10n.conversationActivityStopping;
    return TimelineActivityClock(
      startedAtMillis: stopping.startedAtMs,
      running: true,
      now: now,
      builder: (context, seconds) {
        final duration = seconds == null
            ? null
            : activityDurationLabel(
                context,
                seconds,
                kind: ActivityDurationKind.elapsed,
              );
        return TimelineActivityRow(
          label: label,
          icon: Icons.stop_circle_outlined,
          iconColor: StudioTone.warning.indicator(context),
          indicatorStyle: TimelineActivityIndicatorStyle.circularProgress,
          active: !reducedMotion,
          emphasized: true,
          header: true,
          expandable: false,
          meta: duration,
          metaKey: const ValueKey('conversation-activity-trailing-meta'),
          tooltip: duration == null ? label : '$label，$duration',
          semanticsLabel: duration == null ? label : '$label，$duration',
        );
      },
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final LiveStatusAlertState alert;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final detail = alert.detail;
    final (label, icon, iconColor, labelColor, isIssue) = switch (alert.kind) {
      LiveAlertKind.approval => (
        detail ?? l10n.statusInteractionToolApproval,
        Icons.verified_outlined,
        StudioTone.warning.indicator(context),
        context.colors.onSurface,
        false,
      ),
      LiveAlertKind.storageReady => (
        l10n.conversationActivityResumeReady,
        Icons.check_circle_outline,
        StudioTone.success.indicator(context),
        context.colors.onSurface,
        false,
      ),
      LiveAlertKind.storageWarning => (
        detail ??
            (alert.storage?.pressurePaused == true
                ? l10n.conversationActivityStoragePressure
                : alert.storage?.resumeRequired == true
                ? l10n.conversationActivityResumeRequired
                : l10n.conversationActivitySavePaused),
        alert.storage?.pressurePaused == true
            ? Icons.storage_outlined
            : alert.storage?.resumeRequired == true
            ? Icons.sync_problem_outlined
            : Icons.pause_circle_outline,
        StudioTone.warning.indicator(context),
        context.colors.onSurface,
        false,
      ),
      LiveAlertKind.storageFault => (
        detail ?? l10n.conversationActivitySaveFailed,
        Icons.error_outline,
        context.colors.error,
        context.colors.error,
        true,
      ),
      LiveAlertKind.disconnected => (
        detail ?? l10n.liveStatusConnectionDisconnected,
        Icons.cloud_off_outlined,
        context.colors.error,
        context.colors.error,
        true,
      ),
      LiveAlertKind.error => (
        detail ?? l10n.conversationActivityAttentionDefault,
        Icons.error_outline,
        context.colors.error,
        context.colors.error,
        true,
      ),
    };

    return TimelineActivityRow(
      label: label,
      icon: icon,
      iconColor: iconColor,
      labelColor: labelColor,
      isIssue: isIssue,
      active: false,
      emphasized: true,
      header: true,
      expandable: false,
      tooltip: label,
      semanticsLabel: label,
    );
  }
}

class _RetryCountdown extends StatefulWidget {
  const _RetryCountdown({
    required this.retryAfterMs,
    required this.now,
    required this.builder,
  });

  final int? retryAfterMs;
  final DateTime Function()? now;
  final Widget Function(BuildContext context, int? seconds) builder;

  @override
  State<_RetryCountdown> createState() => _RetryCountdownState();
}

class _RetryCountdownState extends State<_RetryCountdown> {
  Timer? _timer;
  DateTime? _targetAt;

  DateTime _currentTime() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _resetTarget();
  }

  @override
  void didUpdateWidget(covariant _RetryCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retryAfterMs != widget.retryAfterMs) {
      _resetTarget();
    }
  }

  void _resetTarget() {
    _timer?.cancel();
    _timer = null;
    final delayMs = widget.retryAfterMs;
    if (delayMs == null || delayMs <= 0) {
      _targetAt = null;
      return;
    }
    _targetAt = _currentTime().add(Duration(milliseconds: delayMs));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds() <= 0) {
        _timer?.cancel();
        _timer = null;
      }
      setState(() {});
    });
  }

  int _remainingSeconds() {
    final target = _targetAt;
    if (target == null) return 0;
    final remainingMs = target.difference(_currentTime()).inMilliseconds;
    if (remainingMs <= 0) return 0;
    return (remainingMs / 1000).ceil();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _targetAt == null ? null : _remainingSeconds();
    return widget.builder(context, seconds);
  }
}
