import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart' show ConversationActivityView;
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';

enum WorkDisplayLocation { live, history }

/// One producer-defined Work header with bounded, explicitly requested members.
class CompletionRunView extends StatefulWidget {
  const CompletionRunView({
    required this.id,
    required this.summary,
    required this.childBuilder,
    required this.initiallyExpanded,
    required this.location,
    this.onExpandedChanged,
    this.executionPresent = false,
    this.closing = false,
    this.activity,
    this.now,
    super.key,
  });
  final String id;
  final WorkSummary summary;
  final bool executionPresent;
  final bool closing;
  final WorkDisplayLocation location;
  final ConversationActivityView? activity;
  final DateTime Function()? now;
  final WidgetBuilder childBuilder;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<CompletionRunView> createState() => _CompletionRunViewState();
}

class _CompletionRunViewState extends State<CompletionRunView> {
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
    final live = widget.location == WorkDisplayLocation.live;
    final runningClock =
        live && widget.executionPresent && summary.createdAt != null;
    final savedElapsed = summary.elapsedMs;
    final savedSeconds = savedElapsed != null && savedElapsed >= 0
        ? savedElapsed ~/ 1000
        : null;
    return Expansible(
      key: ValueKey('completion-run-disclosure:${widget.id}'),
      controller: _disclosure,
      maintainState: false,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      headerBuilder: (context, animation) => Semantics(
        button: true,
        expanded: _disclosure.isExpanded,
        child: InkWell(
          onTap: _disclosure.toggle,
          borderRadius: BorderRadius.circular(8),
          child: TimelineActivityClock(
            startedAt: runningClock ? summary.createdAt : null,
            running: runningClock,
            now: widget.now,
            builder: (context, seconds) => _WorkHeader(
              key: ValueKey('completion-run-header:${widget.id}'),
              summary: summary,
              location: widget.location,
              executionPresent: widget.executionPresent,
              closing: widget.closing,
              activity: widget.activity,
              seconds: runningClock ? seconds : savedSeconds,
              expanded: _disclosure.isExpanded,
            ),
          ),
        ),
      ),
      bodyBuilder: (context, animation) => !_disclosure.isExpanded
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 3),
              child: TimelineActivityRail(
                inset: 3,
                contentInset: 14,
                child: live
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 186),
                        child: SingleChildScrollView(
                          child: Builder(builder: widget.childBuilder),
                        ),
                      )
                    : Builder(builder: widget.childBuilder),
              ),
            ),
      expansibleBuilder: (context, header, body, animation) => LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (live && constraints.hasBoundedHeight)
              Flexible(fit: FlexFit.loose, child: body)
            else
              body,
          ],
        ),
      ),
    );
  }
}

/// Work alone has a strict single-line header. Other activity rows retain
/// their existing wrapping policy for questions, tools and reasoning.
class _WorkHeader extends StatelessWidget {
  const _WorkHeader({
    super.key,
    required this.summary,
    required this.location,
    required this.executionPresent,
    required this.closing,
    required this.seconds,
    required this.expanded,
    this.activity,
  });

  final WorkSummary summary;
  final WorkDisplayLocation location;
  final bool executionPresent;
  final bool closing;
  final int? seconds;
  final bool expanded;
  final ConversationActivityView? activity;

  @override
  Widget build(BuildContext context) {
    final live = location == WorkDisplayLocation.live;
    final cold = live && !executionPresent;
    final l10n = context.l10n;
    final fallback = cold
        ? l10n.timelineGroupUnrestored
        : closing
        ? l10n.timelineGroupClosing
        : activity != null
        ? context.conversationActivityLabel(activity!)
        : summary.waiting > 0
        ? l10n.conversationActivityWaitingTools
        : summary.running == 0
        ? l10n.timelineGroupWaitingForNext
        : l10n.timelineGroupWorking;
    final thought =
        [summary.thinkingSummary, activity?.thinkingSummary, activity?.summary]
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .firstOrNull;
    final status = live && !cold && thought?.isNotEmpty == true
        ? thought!
        : fallback;
    final duration = seconds == null
        ? null
        : activityDurationLabel(
            context,
            seconds!,
            kind: live
                ? ActivityDurationKind.executing
                : ActivityDurationKind.worked,
          );
    final label = live ? status : duration ?? l10n.timelineGroupRecord;
    final outcomes = <String>[
      if (summary.failed > 0) l10n.timelineGroupFailedCount(summary.failed),
      if (summary.cancelled > 0)
        l10n.timelineGroupStoppedCount(summary.cancelled),
      if (summary.transferred > 0)
        l10n.timelineGroupTransferredCount(summary.transferred),
    ];
    final description = [
      label,
      if (live && label != fallback) fallback,
      if (live && duration != null) duration,
      l10n.timelineGroupMemberCount(summary.total),
      ...outcomes,
    ].join('，');
    final issue = summary.failed > 0;
    final active =
        live &&
        executionPresent &&
        !issue &&
        (summary.running > 0 || summary.waiting > 0 || activity != null);
    final icon = issue
        ? Icons.error_outline
        : cold
        ? Icons.history_outlined
        : summary.cancelled > 0
        ? Icons.stop_circle_outlined
        : summary.transferred > 0
        ? Icons.call_made
        : activity?.kind.icon ?? Icons.work_outline;
    final style = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Semantics(
      label: description,
      excludeSemantics: true,
      child: Tooltip(
        message: description,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              TimelineActivityIndicator(
                icon: icon,
                active: active,
                color: issue
                    ? context.colors.error
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              if (live && duration != null) ...[
                const SizedBox(width: 8),
                Text(
                  duration,
                  key: const ValueKey('work-header-elapsed'),
                  maxLines: 1,
                  softWrap: false,
                  style: style,
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: context.colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
