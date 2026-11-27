import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';
import 'timeline_content_range_view.dart';
import 'timeline_markdown.dart';

/// 将思考摘要中的换行与常见 Markdown 标记剥离为适合 Tooltip 与无障碍朗读的单行纯文本。
String timelineMarkdownPlainText(String text) {
  final collapsedLines = text
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll('****', ' ');
  final withoutLinks = collapsedLines.replaceAllMapped(
    RegExp(r'!?\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  final stripped = withoutLinks
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll('~~', '')
      .replaceAll('*', '')
      .replaceAll('`', '');
  return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 思考成员只有一行入口：概要优先，正文存在时才提供展开能力。
/// 读取、订阅和展开资格由连接层持有，实时和历史复用此视图。
class TimelineReasoningView extends StatelessWidget {
  const TimelineReasoningView({
    this.summary,
    this.summaryBuilder,
    this.body,
    this.startedAt,
    this.finishedAt,
    this.startedAtMs,
    this.finishedAtMs,
    this.now,
    this.running = false,
    this.outcome,
    this.diagnostic,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    super.key,
  });

  final String? summary;
  final Widget Function(String fallback)? summaryBuilder;
  final Widget? body;
  final int? startedAt;
  final int? finishedAt;
  final int? startedAtMs;
  final int? finishedAtMs;
  final DateTime Function()? now;
  final bool running;
  final String? outcome;
  final String? diagnostic;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isRunning = running || outcome == 'running';
    final effectiveStartedAtMs =
        startedAtMs ??
        (startedAt == null
            ? null
            : startedAt! * Duration.millisecondsPerSecond);
    final effectiveFinishedAtMs =
        finishedAtMs ??
        (finishedAt == null
            ? null
            : finishedAt! * Duration.millisecondsPerSecond);
    return TimelineActivityClock(
      startedAtMillis: effectiveStartedAtMs,
      finishedAtMillis: effectiveFinishedAtMs,
      running: isRunning,
      now: now,
      builder: (context, seconds) {
        final hasSummary = summary?.trim().isNotEmpty ?? false;
        final failed = outcome == 'failed' || outcome == 'budgetLimited';
        final fallback = switch (outcome) {
          'failed' => context.l10n.timelineReasoningFailed,
          'cancelled' => context.l10n.timelineReasoningCancelled,
          'budgetLimited' => context.l10n.timelineReasoningBudgetLimited,
          _ when seconds != null => activityDurationLabel(
            context,
            seconds,
            kind: ActivityDurationKind.reasoning,
          ),
          _ =>
            isRunning
                ? context.l10n.timelineReasoningActive
                : context.l10n.timelineReasoningEnded,
        };
        final plainSummary = hasSummary
            ? timelineMarkdownPlainText(summary!)
            : '';
        final label = hasSummary && plainSummary.isNotEmpty
            ? plainSummary
            : fallback;
        final meta = hasSummary && seconds != null
            ? activityDurationLabel(
                context,
                seconds,
                kind: ActivityDurationKind.elapsed,
              )
            : null;
        final semantics = meta == null ? label : '$label，$meta';
        Widget title(BuildContext context, bool expanded) =>
            TimelineActivityRow(
              icon: outcome == 'cancelled'
                  ? Icons.stop_circle_outlined
                  : Icons.psychology_alt_outlined,
              isIssue: failed,
              active: isRunning && !reducedMotion,
              indicatorStyle: TimelineActivityIndicatorStyle.circularProgress,
              label: label,
              labelWidget:
                  summaryBuilder?.call(fallback) ??
                  (hasSummary
                      ? TimelineReasoningSummary(text: summary!)
                      : null),
              meta: meta,
              tooltip: diagnostic,
              semanticsLabel: semantics,
              expanded: expanded,
              expandable: body != null,
            );

        if (body == null) return title(context, false);
        return TimelineActivityDisclosure(
          initiallyExpanded: initiallyExpanded,
          onExpansionChanged: onExpansionChanged,
          titleBuilder: title,
          children: [TimelineBodyReadIntent(child: body!)],
        );
      },
    );
  }
}

/// 概要只在一行内排版；复用正文解析器，关闭链接和媒体动作。
class TimelineReasoningSummary extends StatelessWidget {
  const TimelineReasoningSummary({
    required this.text,
    this.id = 'reasoning-summary',
    this.style,
    this.strutStyle,
    this.inlineCodeBackgroundColor,
    super.key,
  });

  final String text;
  final String id;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final Color? inlineCodeBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        style ??
        context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          height: 1.5,
        );
    final singleLine = text
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll('****', '** **');
    if (!timelineNeedsSafeMarkdown(singleLine)) {
      return Text(
        singleLine,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        strutStyle: strutStyle,
        style: effectiveStyle,
      );
    }
    final base = GptMarkdownTheme.of(context);
    final headingStyle = effectiveStyle?.copyWith(fontWeight: FontWeight.w600);
    return GptMarkdownTheme(
      gptThemeData: base.copyWith(
        h1: headingStyle,
        h2: headingStyle,
        h3: headingStyle,
        h4: headingStyle,
        h5: headingStyle,
        h6: headingStyle,
        autoAddDividerLineAfterH1: false,
      ),
      child: TimelineMarkdown(
        id: id,
        text: singleLine,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: effectiveStyle,
        inlineCodeBackgroundColor:
            inlineCodeBackgroundColor ??
            context.colors.surfaceContainerHigh.withValues(alpha: .75),
        onLink: (_) {},
        isSafeLink: (_) => false,
        imageBuilder: (_, url) => Text(
          url,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: effectiveStyle,
        ),
      ),
    );
  }
}
