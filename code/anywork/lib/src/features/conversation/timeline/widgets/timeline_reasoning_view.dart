import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';
import 'timeline_content_range_view.dart';
import 'timeline_markdown.dart';

/// 思考成员只有一行入口：概要优先，正文存在时才提供展开能力。
/// 读取、订阅和展开资格由连接层持有，实时和历史复用此视图。
class TimelineReasoningView extends StatelessWidget {
  const TimelineReasoningView({
    this.summary,
    this.summaryWidget,
    this.body,
    this.startedAt,
    this.finishedAt,
    this.running = false,
    this.outcome,
    this.diagnostic,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    super.key,
  });

  final String? summary;
  final Widget? summaryWidget;
  final Widget? body;
  final int? startedAt;
  final int? finishedAt;
  final bool running;
  final String? outcome;
  final String? diagnostic;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) => TimelineActivityClock(
    startedAt: startedAt,
    finishedAt: finishedAt,
    running: running,
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
          running
              ? context.l10n.timelineReasoningActive
              : context.l10n.timelineReasoningEnded,
      };
      final label = hasSummary ? summary! : fallback;
      Widget title(BuildContext context, bool expanded) => TimelineActivityRow(
        icon: outcome == 'cancelled'
            ? Icons.stop_circle_outlined
            : Icons.psychology_alt_outlined,
        isIssue: failed,
        active: running,
        label: label,
        labelWidget:
            summaryWidget ??
            (hasSummary ? TimelineReasoningSummary(text: summary!) : null),
        tooltip: diagnostic == null ? label : '$label\n$diagnostic',
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

/// 概要只在一行内排版；复用正文解析器，关闭链接和媒体动作。
class TimelineReasoningSummary extends StatelessWidget {
  const TimelineReasoningSummary({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) => TimelineMarkdown(
    id: 'reasoning-summary',
    text: text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
      height: 1.5,
    ),
    onLink: (_) {},
    isSafeLink: (_) => false,
    imageBuilder: (_, url) => Text(url, maxLines: 1),
  );
}
