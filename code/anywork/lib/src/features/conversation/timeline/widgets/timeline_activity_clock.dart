import 'dart:async';

import 'package:duration/duration.dart';
import 'package:duration/locale.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';

enum ActivityDurationKind { elapsed, worked, reasoning, executing }

/// 只格式化已有时间事实；未知或倒序时间不构造耗时。
/// 使用 `package:duration` 完成按日/时/分/秒的分段进位与本地化单位拼接。
String activityDurationLabel(
  BuildContext context,
  int seconds, {
  ActivityDurationKind kind = ActivityDurationKind.elapsed,
}) {
  final l10n = context.l10n;
  if (seconds <= 0) {
    return switch (kind) {
      ActivityDurationKind.executing => l10n.timelineGroupExecutingUnderSecond,
      ActivityDurationKind.worked => l10n.timelineGroupWorkedUnderSecond,
      ActivityDurationKind.reasoning =>
        l10n.timelineReasoningElapsedUnderSecond,
      ActivityDurationKind.elapsed => l10n.timelineToolElapsedUnderSecond,
    };
  }
  final locale = Localizations.maybeLocaleOf(context);
  final durationLocale = switch (locale?.languageCode) {
    'zh' when locale?.scriptCode == 'Hant' => chineseTraditionalLocale,
    'zh' => chineseSimplifiedDurationLocale,
    final code? => DurationLocale.fromLanguageCode(code) ?? englishLocale,
    null => englishLocale,
  };
  final isChinese = locale?.languageCode == 'zh';
  final formatted = prettyDuration(
    Duration(seconds: seconds),
    tersity: DurationTersity.second,
    upperTersity: DurationTersity.day,
    locale: durationLocale,
    abbreviated: !isChinese,
    spacer: isChinese ? ' ' : '',
    delimiter: ' ',
  );
  return switch (kind) {
    ActivityDurationKind.executing => l10n.timelineGroupExecutingDuration(
      formatted,
    ),
    ActivityDurationKind.worked => l10n.timelineGroupWorkedDuration(formatted),
    ActivityDurationKind.reasoning => l10n.timelineReasoningElapsedDuration(
      formatted,
    ),
    ActivityDurationKind.elapsed => l10n.timelineToolElapsedDuration(formatted),
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
    this.now,
    super.key,
  }) : startedAtMillis = startedAt == null
           ? null
           : startedAt * Duration.millisecondsPerSecond,
       finishedAtMillis = finishedAt == null
           ? null
           : finishedAt * Duration.millisecondsPerSecond;

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
