import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';
import 'timeline_activity_section.dart';
import 'timeline_cat_tail.dart';
import 'timeline_reasoning_view.dart';

/// 实时与历史共用的纯工作组视图，不读取成员或持有领域资源。
class TimelineWorkGroupView extends StatefulWidget {
  const TimelineWorkGroupView({
    required this.id,
    required this.summary,
    required this.live,
    required this.executionPresent,
    required this.admissionClosed,
    required this.childBuilder,
    required this.initiallyExpanded,
    this.onExpandedChanged,
    super.key,
  });
  final String id;
  final TimelineGroupSummary? summary;
  final bool live;
  final bool executionPresent;
  final bool admissionClosed;
  final bool initiallyExpanded;
  final WidgetBuilder childBuilder;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  State<TimelineWorkGroupView> createState() => _WorkGroupState();
}

class _WorkGroupState extends State<TimelineWorkGroupView> {
  final ExpansibleController _disclosure = ExpansibleController();
  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) _disclosure.expand();
    _disclosure.addListener(_changed);
  }

  void _changed() {
    widget.onExpandedChanged?.call(_disclosure.isExpanded);
    setState(() {});
  }

  @override
  void dispose() {
    _disclosure.removeListener(_changed);
    _disclosure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final active =
        widget.live &&
        widget.executionPresent &&
        (summary?.activeCount ?? 0) > 0;
    return Expansible(
      controller: _disclosure,
      maintainState: false,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      headerBuilder: (context, animation) => TimelineActivityClock(
        startedAt: summary?.startedAt,
        finishedAt: summary?.finishedAt,
        running: active,
        builder: (context, elapsed) {
          final l10n = context.l10n;
          final thinkingSummary = widget.live
              ? summary?.latestThinkingSummary?.trim()
              : null;
          final label = active
              ? l10n.timelineGroupWorking
              : widget.live && (summary?.activeCount ?? 0) > 0
              ? l10n.timelineGroupUnfinished
              : widget.live &&
                    !widget.admissionClosed &&
                    widget.executionPresent
              ? l10n.timelineReasoningActive
              : elapsed == null
              ? l10n.timelineGroupRecord
              : activityDurationLabel(
                  context,
                  elapsed,
                  kind: ActivityDurationKind.worked,
                );
          final meta = [
            if (summary != null) ...[
              if (widget.live && widget.executionPresent) ...[
                l10n.timelineGroupCompletedCount(
                  summary.memberCount -
                      summary.activeCount -
                      summary.failedCount -
                      summary.cancelledCount,
                ),
                if (summary.activeCount > 0)
                  l10n.timelineGroupActiveCount(summary.activeCount),
              ] else
                l10n.timelineGroupMemberCount(summary.memberCount),
            ],
            if ((summary?.failedCount ?? 0) > 0)
              l10n.timelineGroupFailedCount(summary!.failedCount),
            if ((summary?.cancelledCount ?? 0) > 0)
              l10n.timelineGroupStoppedCount(summary!.cancelledCount),
            if (active && elapsed != null)
              activityDurationLabel(context, elapsed),
          ].join(' · ');
          return Semantics(
            container: true,
            button: true,
            expanded: _disclosure.isExpanded,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _disclosure.toggle,
                borderRadius: BorderRadius.circular(8),
                child: TimelineActivityRow(
                  key: ValueKey('source-unit-header:${widget.id}'),
                  label: thinkingSummary == null || thinkingSummary.isEmpty
                      ? label
                      : thinkingSummary,
                  labelWidget:
                      thinkingSummary == null || thinkingSummary.isEmpty
                      ? null
                      : TimelineReasoningSummary(text: thinkingSummary),
                  meta: meta.isEmpty ? null : meta,
                  header: true,
                  emphasized: widget.live,
                  expanded: _disclosure.isExpanded,
                  active: active,
                  // 标题动画跟随会话执行资格；成员终态不结束会话的活动指示，
                  // 组自身的工作计时仍只取真实活动成员。
                  leading: widget.live && !active
                      ? widget.executionPresent
                            ? TimelineActivityIndicator(
                                icon: null,
                                active: true,
                                color: context.statusColors.activeIndicator,
                              )
                            : TimelineCatTail(
                                progress: const AlwaysStoppedAnimation(0),
                                color: context.colors.onSurfaceVariant
                                    .withValues(alpha: .78),
                                size: TimelineActivityRow.iconSize,
                              )
                      : null,
                  summaryWidget:
                      widget.live ||
                          summary == null ||
                          summary.categories.isEmpty
                      ? null
                      : Wrap(
                          spacing: 8,
                          runSpacing: 3,
                          children: [
                            for (final category in summary.categories)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(switch (category.category) {
                                    TimelineCategory.thinking =>
                                      Icons.psychology_alt_outlined,
                                    TimelineCategory.read =>
                                      Icons.description_outlined,
                                    TimelineCategory.image =>
                                      Icons.image_outlined,
                                    TimelineCategory.command => Icons.terminal,
                                    TimelineCategory.search => Icons.search,
                                    TimelineCategory.edit =>
                                      Icons.edit_outlined,
                                    TimelineCategory.wait =>
                                      Icons.hourglass_empty,
                                    TimelineCategory.other => Icons.more_horiz,
                                  }, size: 12),
                                  const SizedBox(width: 3),
                                  Text('${category.count}'),
                                ],
                              ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
      bodyBuilder: (context, animation) => !_disclosure.isExpanded
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 3),
              child: TimelineActivityRail(
                inset: 3,
                contentInset: 14,
                child: Builder(builder: widget.childBuilder),
              ),
            ),
      expansibleBuilder: (context, header, body, animation) => widget.live
          ? TimelineActivitySection(header: header, body: body)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, body],
            ),
    );
  }
}
