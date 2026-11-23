import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/timeline_display_models.dart';
import '../widgets/timeline_activity_clock.dart';
import '../widgets/timeline_activity_row.dart';
import '../widgets/timeline_markdown.dart';
import '../widgets/timeline_reasoning_view.dart';
import 'live_status_state.dart';

/// 将当前运行活动映射到顶行左侧统一的视觉指示样式（写作笔触、拉链、摆尾猫或进度环）。
TimelineActivityIndicatorStyle resolveLiveHeaderIndicatorStyle(
  ConversationActivityView? view, {
  bool displayingThinkingSummary = false,
}) {
  if (view == null) return TimelineActivityIndicatorStyle.restingCat;
  if (view.kind == ConversationActivityKind.responding) {
    return TimelineActivityIndicatorStyle.writing;
  }
  if (view.kind == ConversationActivityKind.compacting) {
    return TimelineActivityIndicatorStyle.compactingZip;
  }
  if (displayingThinkingSummary) {
    return TimelineActivityIndicatorStyle.restingCat;
  }
  if (view.kind == ConversationActivityKind.stopping ||
      (view.wait == null && view.isRunningExecTool)) {
    return TimelineActivityIndicatorStyle.circularProgress;
  }
  return TimelineActivityIndicatorStyle.restingCat;
}

/// 实时状态栏与工作组标题共用的顶行视觉与语义规格。
///
/// 统一收口图标、指示器动画、`StudioTone` 语义色、减少动态效果降级、单行标题/Markdown 与耗时文案，
/// 避免各状态卡片和折叠工作组分别拼装不一致的 `Row`。
@immutable
final class LiveStatusHeaderSpec {
  const LiveStatusHeaderSpec({
    required this.label,
    required this.icon,
    required this.indicatorStyle,
    required this.active,
    required this.tone,
    this.iconColor,
    this.labelColor,
    this.labelWidget,
    this.meta,
    this.tooltip,
    this.semanticsLabel,
    this.emphasized = false,
    this.isIssue = false,
  });

  final String label;
  final IconData? icon;
  final TimelineActivityIndicatorStyle indicatorStyle;
  final bool active;
  final StudioTone tone;
  final Color? iconColor;
  final Color? labelColor;
  final Widget? labelWidget;
  final String? meta;
  final String? tooltip;
  final String? semanticsLabel;
  final bool emphasized;
  final bool isIssue;

  Color resolvedIconColor(BuildContext context) =>
      iconColor ??
      (isIssue
          ? context.colors.error
          : tone == StudioTone.active || active
          ? StudioTone.active.indicator(context)
          : tone == StudioTone.neutral
          ? context.colors.onSurfaceVariant.withValues(alpha: .78)
          : tone.indicator(context));

  Color resolvedLabelColor(BuildContext context, {required bool header}) {
    if (labelColor != null) return labelColor!;
    if (!header) return context.colors.onSurfaceVariant;
    return active || emphasized
        ? context.colors.onSurface
        : context.colors.onSurfaceVariant;
  }

  /// 由后端 `ConversationActivityView` 派生统一顶行规格。
  factory LiveStatusHeaderSpec.forActivity(
    BuildContext context,
    ConversationActivityView view, {
    LiveStorageSeverity? storageSeverity,
    int? seconds,
    bool showTrailingMeta = true,
    Key? labelKey,
  }) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final baseLabel =
        view.errorMessage ?? context.conversationActivityLabel(view);
    final summary = _trimmed(view.summary);
    final thinkingThought = view.kind == ConversationActivityKind.thinking
        ? _trimmed(view.thinkingSummary)
        : null;

    final (
      IconData icon,
      StudioTone tone,
      bool active,
      TimelineActivityIndicatorStyle style,
      bool isIssue,
      bool emphasized,
    ) = switch (view.kind) {
      ConversationActivityKind.stopping => (
        Icons.stop_circle_outlined,
        StudioTone.neutral,
        !reducedMotion,
        TimelineActivityIndicatorStyle.circularProgress,
        false,
        false,
      ),
      ConversationActivityKind.awaitingApproval => (
        Icons.verified_outlined,
        StudioTone.warning,
        false,
        TimelineActivityIndicatorStyle.restingCat,
        false,
        true,
      ),
      ConversationActivityKind.awaitingInput => (
        Icons.help_outline,
        StudioTone.warning,
        false,
        TimelineActivityIndicatorStyle.restingCat,
        false,
        true,
      ),
      ConversationActivityKind.storageBlocked => _storageStyle(
        storageSeverity ?? _inferStorageSeverity(view.storage),
      ),
      ConversationActivityKind.responding => (
        view.kind.icon,
        StudioTone.active,
        true,
        TimelineActivityIndicatorStyle.writing,
        false,
        true,
      ),
      ConversationActivityKind.compacting => (
        view.kind.icon,
        StudioTone.active,
        true,
        TimelineActivityIndicatorStyle.compactingZip,
        false,
        false,
      ),
      ConversationActivityKind.planning => (
        view.kind.icon,
        StudioTone.active,
        true,
        TimelineActivityIndicatorStyle.restingCat,
        false,
        true,
      ),
      ConversationActivityKind.runningTool => (
        view.kind.icon,
        StudioTone.active,
        true,
        resolveLiveHeaderIndicatorStyle(view),
        false,
        true,
      ),
      ConversationActivityKind.preparing ||
      ConversationActivityKind.thinking => (
        view.kind.icon,
        StudioTone.active,
        true,
        TimelineActivityIndicatorStyle.restingCat,
        false,
        false,
      ),
    };

    final runningToolSummary =
        view.kind == ConversationActivityKind.runningTool &&
            view.wait == null &&
            view.errorMessage == null
        ? (summary ??
              view.activeTools
                  .where((t) => t.state == ThreadActivityToolState.running)
                  .map((t) => _trimmed(t.summary))
                  .nonNulls
                  .lastOrNull)
        : null;

    final displayLabel = switch (view.kind) {
      ConversationActivityKind.thinking
          when thinkingThought != null && view.errorMessage == null =>
        thinkingThought,
      ConversationActivityKind.runningTool when runningToolSummary != null =>
        runningToolSummary,
      ConversationActivityKind.awaitingApproval ||
      ConversationActivityKind.awaitingInput
          when summary != null &&
              view.errorMessage == null &&
              view.wait == null =>
        '$baseLabel · $summary',
      _ => baseLabel,
    };

    final effectiveMeta = !showTrailingMeta
        ? null
        : seconds != null
        ? activityDurationLabel(
            context,
            seconds,
            kind: ActivityDurationKind.executing,
          )
        : view.kind == ConversationActivityKind.thinking &&
              view.thinkingSeconds != null
        ? activityDurationLabel(
            context,
            view.thinkingSeconds!,
            kind: ActivityDurationKind.executing,
          )
        : null;

    final tooltip =
        view.errorMessage ??
        thinkingThought ??
        runningToolSummary ??
        summary ??
        baseLabel;
    final headerTextColor = active || emphasized
        ? context.colors.onSurface
        : context.colors.onSurfaceVariant;
    final labelStyle = context.text.bodySmall!.copyWith(
      color: headerTextColor,
      fontSize: TimelineActivityRow.headerFontSize,
      fontWeight: FontWeight.w500,
      height: 1.36,
    );
    final Widget? labelWidget =
        thinkingThought != null &&
            view.errorMessage == null &&
            (timelineNeedsSafeMarkdown(thinkingThought) ||
                thinkingThought.contains('\n') ||
                thinkingThought.contains('\r'))
        ? TimelineReasoningSummary(
            key: labelKey,
            id: 'live-activity-thinking-summary',
            text: thinkingThought,
            style: labelStyle,
            strutStyle: TimelineActivityRow.headerStrutStyle,
            inlineCodeBackgroundColor: context.colors.surfaceContainerHigh
                .withValues(alpha: .75),
          )
        : null;

    return LiveStatusHeaderSpec(
      label: displayLabel,
      icon: icon,
      indicatorStyle: style,
      active: active,
      tone: tone,
      iconColor: switch (tone) {
        StudioTone.active =>
          active ? context.statusColors.activeIndicator : null,
        StudioTone.neutral =>
          active
              ? StudioTone.neutral.indicator(context)
              : context.colors.onSurfaceVariant.withValues(alpha: .78),
        StudioTone.error => context.colors.error,
        StudioTone.brand ||
        StudioTone.success ||
        StudioTone.warning => tone.indicator(context),
      },
      labelColor: headerTextColor,
      labelWidget: labelWidget,
      meta: effectiveMeta,
      tooltip: tooltip,
      semanticsLabel: tooltip,
      emphasized: emphasized,
      isIssue: isIssue,
    );
  }

  /// 由实时/历史工作组信息派生与时间线完全一致的组标题规格。
  factory LiveStatusHeaderSpec.forWorkGroup(
    BuildContext context, {
    required DisplayBlockState state,
    required bool executionPresent,
    ConversationActivityView? activity,
    String? thinkingSummary,
    int? seconds,
    Key? titleKey,
  }) {
    final live = state == DisplayBlockState.open;
    final l10n = context.l10n;

    if (!live) {
      final label = seconds == null
          ? l10n.timelineGroupRecord
          : activityDurationLabel(
              context,
              seconds,
              kind: ActivityDurationKind.worked,
            );
      return LiveStatusHeaderSpec(
        label: label,
        icon: null,
        indicatorStyle: TimelineActivityIndicatorStyle.restingCat,
        active: false,
        tone: StudioTone.neutral,
        iconColor: context.colors.onSurfaceVariant.withValues(alpha: .78),
        labelColor: context.colors.onSurfaceVariant,
        tooltip: label,
        semanticsLabel: label,
        emphasized: false,
        isIssue: false,
      );
    }

    final duration = seconds == null
        ? null
        : activityDurationLabel(
            context,
            seconds,
            kind: ActivityDurationKind.executing,
          );

    if (executionPresent && activity != null) {
      final base = LiveStatusHeaderSpec.forActivity(
        context,
        activity,
        seconds: seconds,
        labelKey: titleKey,
      );
      final allowThoughtOverride = switch (activity.kind) {
        ConversationActivityKind.preparing ||
        ConversationActivityKind.thinking ||
        ConversationActivityKind.planning ||
        ConversationActivityKind.runningTool => true,
        _ => false,
      };
      final thought = allowThoughtOverride ? _trimmed(thinkingSummary) : null;
      if (thought == null) {
        final description = [
          base.label,
          if (base.meta != null) base.meta!,
        ].join('，');
        return LiveStatusHeaderSpec(
          label: base.label,
          icon: base.icon,
          indicatorStyle: base.indicatorStyle,
          active: base.active,
          tone: base.tone,
          iconColor: base.iconColor,
          labelColor: base.labelColor,
          labelWidget: base.labelWidget,
          meta: base.meta,
          tooltip: description,
          semanticsLabel: description,
          emphasized: base.emphasized,
          isIssue: base.isIssue,
        );
      }

      final titleStyle = context.text.bodySmall!.copyWith(
        color: base.labelColor ?? context.colors.onSurface,
        fontSize: TimelineActivityRow.headerFontSize,
        fontWeight: FontWeight.w500,
        height: 1.36,
      );
      final Widget? labelWidget =
          timelineNeedsSafeMarkdown(thought) ||
              thought.contains('\n') ||
              thought.contains('\r')
          ? TimelineReasoningSummary(
              key: titleKey,
              id: 'work-header-summary',
              text: thought,
              style: titleStyle,
              strutStyle: TimelineActivityRow.headerStrutStyle,
              inlineCodeBackgroundColor: context.colors.surfaceContainerHigh
                  .withValues(alpha: .75),
            )
          : null;
      final fallbackLabel = context.conversationActivityLabel(activity);
      final description = [
        thought,
        if (thought != fallbackLabel) fallbackLabel,
        ?base.meta,
      ].join('，');
      return LiveStatusHeaderSpec(
        label: thought,
        icon: base.icon,
        indicatorStyle: TimelineActivityIndicatorStyle.restingCat,
        active: base.active,
        tone: base.tone,
        iconColor: base.iconColor,
        labelColor: titleStyle.color,
        labelWidget: labelWidget,
        meta: base.meta,
        tooltip: description,
        semanticsLabel: description,
        emphasized: base.emphasized,
        isIssue: base.isIssue,
      );
    }

    final fallback = l10n.timelineGroupRecord;
    final description = [fallback, ?duration].join('，');
    return LiveStatusHeaderSpec(
      label: fallback,
      icon: Icons.work_outline,
      indicatorStyle: TimelineActivityIndicatorStyle.restingCat,
      active: false,
      tone: StudioTone.neutral,
      iconColor: context.colors.onSurfaceVariant.withValues(alpha: .78),
      labelColor: context.colors.onSurfaceVariant,
      meta: duration,
      tooltip: description,
      semanticsLabel: description,
      emphasized: false,
      isIssue: false,
    );
  }

  /// 由并发关注条状态（控制、审批、存储、断连、错误）派生单行规格。
  factory LiveStatusHeaderSpec.forAttention(
    BuildContext context,
    LiveStatusAttention attention,
  ) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final l10n = context.l10n;
    return switch (attention) {
      LiveStoppingAttention(:final activity) =>
        LiveStatusHeaderSpec.forActivity(context, activity),
      LiveApprovalAttention(:final activity) =>
        LiveStatusHeaderSpec.forActivity(context, activity),
      LiveStorageAttention(:final activity, :final severity) =>
        LiveStatusHeaderSpec.forActivity(
          context,
          activity,
          storageSeverity: severity,
        ),
      LiveConnectionAttention(:final status, :final detail) => switch (status) {
        LiveConnectionStatus.disconnected => LiveStatusHeaderSpec(
          label: detail ?? l10n.liveStatusConnectionDisconnected,
          icon: Icons.cloud_off_outlined,
          indicatorStyle: TimelineActivityIndicatorStyle.restingCat,
          active: false,
          tone: StudioTone.error,
          iconColor: context.colors.error,
          tooltip: detail ?? l10n.liveStatusConnectionDisconnected,
          semanticsLabel: detail ?? l10n.liveStatusConnectionDisconnected,
          isIssue: true,
        ),
        LiveConnectionStatus.reconnecting => LiveStatusHeaderSpec(
          label: detail ?? l10n.liveStatusConnectionReconnecting,
          icon: Icons.sync_outlined,
          indicatorStyle: TimelineActivityIndicatorStyle.circularProgress,
          active: !reducedMotion,
          tone: StudioTone.warning,
          iconColor: StudioTone.warning.indicator(context),
          tooltip: detail ?? l10n.liveStatusConnectionReconnecting,
          semanticsLabel: detail ?? l10n.liveStatusConnectionReconnecting,
        ),
        LiveConnectionStatus.connected => throw StateError(
          'connected status must not produce LiveConnectionAttention',
        ),
      },
      LiveErrorAttention(:final message) => LiveStatusHeaderSpec(
        label: message,
        icon: Icons.error_outline,
        indicatorStyle: TimelineActivityIndicatorStyle.restingCat,
        active: false,
        tone: StudioTone.error,
        iconColor: context.colors.error,
        tooltip: message,
        semanticsLabel: message,
        isIssue: true,
      ),
    };
  }

  static (
    IconData,
    StudioTone,
    bool,
    TimelineActivityIndicatorStyle,
    bool,
    bool,
  )
  _storageStyle(LiveStorageSeverity severity) => switch (severity) {
    LiveStorageSeverity.resumeReady => (
      Icons.check_circle_outline,
      StudioTone.success,
      false,
      TimelineActivityIndicatorStyle.restingCat,
      false,
      true,
    ),
    LiveStorageSeverity.fault => (
      Icons.error_outline,
      StudioTone.error,
      false,
      TimelineActivityIndicatorStyle.restingCat,
      true,
      true,
    ),
    LiveStorageSeverity.pressure => (
      Icons.storage_outlined,
      StudioTone.warning,
      false,
      TimelineActivityIndicatorStyle.restingCat,
      false,
      true,
    ),
    LiveStorageSeverity.resumeRequired => (
      Icons.sync_problem_outlined,
      StudioTone.warning,
      false,
      TimelineActivityIndicatorStyle.restingCat,
      false,
      true,
    ),
    LiveStorageSeverity.paused => (
      Icons.pause_circle_outline,
      StudioTone.neutral,
      false,
      TimelineActivityIndicatorStyle.restingCat,
      false,
      false,
    ),
  };

  static LiveStorageSeverity _inferStorageSeverity(
    ThreadStorageStateView? storage,
  ) {
    if (storage == null) return LiveStorageSeverity.fault;
    if (storage.resumeRequired && storage.canResume) {
      return LiveStorageSeverity.resumeReady;
    }
    if (storage.hasFault) return LiveStorageSeverity.fault;
    if (storage.pressurePaused) return LiveStorageSeverity.pressure;
    if (storage.resumeRequired) return LiveStorageSeverity.resumeRequired;
    return LiveStorageSeverity.paused;
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed != null && trimmed.isNotEmpty ? trimmed : null;
  }
}
