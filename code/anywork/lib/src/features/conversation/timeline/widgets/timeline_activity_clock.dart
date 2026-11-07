import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';

/// 只格式化已有时间事实；未知或倒序时间不构造耗时。
String activityDurationLabel(
  BuildContext context,
  int seconds, {
  bool worked = false,
}) {
  final l10n = context.l10n;
  if (seconds <= 0) {
    return worked
        ? l10n.timelineGroupWorkedUnderSecond
        : l10n.timelineToolElapsedUnderSecond;
  }
  if (seconds < 60) {
    return worked
        ? l10n.timelineGroupWorkedSeconds(seconds)
        : l10n.timelineToolElapsedSeconds(seconds);
  }
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  if (remainder == 0) {
    return worked
        ? l10n.timelineGroupWorkedMinutes(minutes)
        : l10n.timelineToolElapsedMinutes(minutes);
  }
  return worked
      ? l10n.timelineGroupWorkedMinutesSeconds(minutes, remainder)
      : l10n.timelineToolElapsedMinutesSeconds(minutes, remainder);
}

/// 标题共用的显示时钟。终态停止计时，隐藏子树不保持周期唤醒。
class TimelineActivityClock extends StatefulWidget {
  const TimelineActivityClock({
    required this.builder,
    this.startedAt,
    this.finishedAt,
    this.running = false,
    super.key,
  });
  final int? startedAt;
  final int? finishedAt;
  final bool running;
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
        widget.startedAt != null &&
        widget.finishedAt == null &&
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
    final start = widget.startedAt;
    final end =
        widget.finishedAt ??
        (widget.running ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : null);
    return widget.builder(
      context,
      start == null || end == null || end < start ? null : end - start,
    );
  }
}
