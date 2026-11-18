import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';

enum ActivityDurationKind { elapsed, worked, reasoning, executing }

/// 只格式化已有时间事实；未知或倒序时间不构造耗时。
String activityDurationLabel(
  BuildContext context,
  int seconds, {
  ActivityDurationKind kind = ActivityDurationKind.elapsed,
}) {
  final l10n = context.l10n;
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return switch (kind) {
    ActivityDurationKind.executing => switch (seconds) {
      <= 0 => l10n.timelineGroupExecutingUnderSecond,
      < 60 => l10n.timelineGroupExecutingSeconds(seconds),
      _ when remainder == 0 => l10n.timelineGroupExecutingMinutes(minutes),
      _ => l10n.timelineGroupExecutingMinutesSeconds(minutes, remainder),
    },
    ActivityDurationKind.worked => switch (seconds) {
      <= 0 => l10n.timelineGroupWorkedUnderSecond,
      < 60 => l10n.timelineGroupWorkedSeconds(seconds),
      _ when remainder == 0 => l10n.timelineGroupWorkedMinutes(minutes),
      _ => l10n.timelineGroupWorkedMinutesSeconds(minutes, remainder),
    },
    ActivityDurationKind.reasoning => switch (seconds) {
      <= 0 => l10n.timelineReasoningElapsedUnderSecond,
      < 60 => l10n.timelineReasoningElapsedSeconds(seconds),
      _ when remainder == 0 => l10n.timelineReasoningElapsedMinutes(minutes),
      _ => l10n.timelineReasoningElapsedMinutesSeconds(minutes, remainder),
    },
    ActivityDurationKind.elapsed => switch (seconds) {
      <= 0 => l10n.timelineToolElapsedUnderSecond,
      < 60 => l10n.timelineToolElapsedSeconds(seconds),
      _ when remainder == 0 => l10n.timelineToolElapsedMinutes(minutes),
      _ => l10n.timelineToolElapsedMinutesSeconds(minutes, remainder),
    },
  };
}

/// 标题共用的显示时钟。终态停止计时，隐藏子树不保持周期唤醒。
class TimelineActivityClock extends StatefulWidget {
  const TimelineActivityClock({
    required this.builder,
    this.startedAtMillis,
    this.finishedAtMillis,
    this.running = false,
    this.now,
    super.key,
  });

  /// 原子活动沿用生产者的 Unix 秒时间戳。
  const TimelineActivityClock.fromUnixSeconds({
    required this.builder,
    int? startedAt,
    int? finishedAt,
    this.running = false,
    super.key,
  }) : startedAtMillis = startedAt == null
           ? null
           : startedAt * Duration.millisecondsPerSecond,
       finishedAtMillis = finishedAt == null
           ? null
           : finishedAt * Duration.millisecondsPerSecond,
       now = null;

  final int? startedAtMillis;
  final int? finishedAtMillis;
  final bool running;
  final DateTime Function()? now;
  final Widget Function(BuildContext, int?) builder;
  @override
  State<TimelineActivityClock> createState() => _ClockState();
}

class _ClockState extends State<TimelineActivityClock> {
  Timer? _timer;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TimelineActivityClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.running &&
        widget.startedAtMillis != null &&
        widget.finishedAtMillis == null &&
        TickerMode.valuesOf(context).enabled) {
      _timer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startedAtMillis;
    final end =
        widget.finishedAtMillis ??
        (widget.running
            ? (widget.now ?? DateTime.now)().millisecondsSinceEpoch
            : null);
    final seconds = start == null || end == null || end < start
        ? null
        : (end - start) ~/ Duration.millisecondsPerSecond;
    return widget.builder(context, seconds);
  }
}
