import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart' show ConversationActivityView;
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';
import 'timeline_markdown.dart';
import 'timeline_reasoning_view.dart';

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
    DisplayBlockState? state,
    this.activity,
    this.now,
    super.key,
  }) : state =
           state ??
           (location == WorkDisplayLocation.history
               ? DisplayBlockState.sealed
               : DisplayBlockState.open);
  final String id;
  final WorkSummary summary;
  final bool executionPresent;
  final DisplayBlockState state;
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
    final live = widget.state == DisplayBlockState.open;
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
              state: widget.state,
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
                inset: live ? 15.5 : 9.5,
                contentInset: live ? 25.5 : 17.5,
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
    required this.state,
    required this.seconds,
    required this.expanded,
    this.activity,
  });

  final WorkSummary summary;
  final WorkDisplayLocation location;
  final bool executionPresent;
  final DisplayBlockState state;
  final int? seconds;
  final bool expanded;
  final ConversationActivityView? activity;

  @override
  Widget build(BuildContext context) {
    final live = state == DisplayBlockState.open;
    final cold = live && !executionPresent;
    final working = summary.running > 0 || summary.waiting > 0;
    final cleanIdle =
        !working &&
        summary.failed == 0 &&
        summary.cancelled == 0 &&
        summary.transferred == 0;
    final l10n = context.l10n;
    final fallback = cold
        ? l10n.timelineGroupUnrestored
        : activity != null
        ? context.conversationActivityLabel(activity!)
        : summary.waiting > 0
        ? l10n.conversationActivityWaitingTools
        : summary.running == 0
        ? l10n.timelineGroupWaitingForNext
        : l10n.timelineGroupWorking;
    final activeThought = live && !cold && (working || cleanIdle)
        ? [
                if (activity != null) activity!.thinkingSummary,
                summary.thinkingSummary,
              ]
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .firstOrNull
        : null;
    final rawSummary = live && !cold && (working || activity == null)
        ? activity?.summary?.trim()
        : null;
    final status =
        activeThought ??
        (rawSummary != null && rawSummary.isNotEmpty ? rawSummary : fallback);
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
      if (!live && (summary.running > 0 || summary.waiting > 0)) '封存时尚未结束',
      if (summary.unavailable > 0) '旧边界观察不可用',
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
        live && executionPresent && !issue && (working || activity != null);
    final icon = issue
        ? Icons.error_outline
        : cold
        ? Icons.history_outlined
        : summary.cancelled > 0
        ? Icons.stop_circle_outlined
        : summary.transferred > 0
        ? Icons.call_made
        : activity?.kind.icon ?? Icons.work_outline;
    final secondaryColor = context.colors.onSurfaceVariant;
    final indicatorColor = issue
        ? context.colors.error
        : active
        ? context.statusColors.activeIndicator
        : secondaryColor.withValues(alpha: .78);
    final titleStyle = context.text.bodySmall!.copyWith(
      color: live
          ? (active
                ? (working
                      ? context.colors.onSurface
                      : context.colors.onSurface.withValues(alpha: .92))
                : secondaryColor)
          : secondaryColor,
      fontSize: live ? TimelineActivityRow.headerFontSize : 13,
      fontWeight: FontWeight.w500,
      height: live ? 1.36 : 1.45,
    );
    final metaStyle = context.text.labelSmall!.copyWith(
      color: secondaryColor.withValues(alpha: .85),
      fontSize: TimelineActivityRow.headerMetaFontSize,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: description,
      excludeSemantics: true,
      child: Tooltip(
        message: description,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: live ? TimelineActivityRow.headerMinHeight : 30,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: live ? 2 : 3),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              heightFactor: 1,
              child: live
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: TimelineActivityRow.headerLogoSlotSize,
                          child: Center(
                            heightFactor: 1,
                            child: TimelineActivityIndicator(
                              icon: icon,
                              active: active,
                              style: activity?.isRunningExecTool == true
                                  ? TimelineActivityIndicatorStyle
                                        .circularProgress
                                  : TimelineActivityIndicatorStyle.restingCat,
                              catSize: TimelineActivityRow.headerLogoSlotSize,
                              writingSize:
                                  TimelineActivityRow.headerWritingSize,
                              zipSize: TimelineActivityRow.headerZipSize,
                              spinnerSize:
                                  TimelineActivityRow.headerSpinnerSize,
                              spinnerStrokeWidth: 2.2,
                              staticIconSize:
                                  TimelineActivityRow.headerStaticIconSize,
                              color: indicatorColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: TimelineActivityRow.headerGap),
                        Expanded(
                          child:
                              activeThought != null &&
                                  (timelineNeedsSafeMarkdown(activeThought) ||
                                      activeThought.contains('\n') ||
                                      activeThought.contains('\r'))
                              ? TimelineReasoningSummary(
                                  key: const ValueKey('work-header-title'),
                                  id: 'work-header-summary',
                                  text: activeThought,
                                  style: titleStyle,
                                  strutStyle:
                                      TimelineActivityRow.headerStrutStyle,
                                  inlineCodeBackgroundColor: context
                                      .colors
                                      .surfaceContainerHigh
                                      .withValues(alpha: .75),
                                )
                              : Text(
                                  label,
                                  key: const ValueKey('work-header-title'),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  strutStyle:
                                      TimelineActivityRow.headerStrutStyle,
                                  style: titleStyle,
                                ),
                        ),
                        if (duration != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            duration,
                            key: const ValueKey('work-header-elapsed'),
                            maxLines: 1,
                            softWrap: false,
                            style: metaStyle,
                          ),
                        ],
                        const SizedBox(width: 4),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.chevron_right_rounded,
                          size: TimelineActivityRow.headerChevronSize,
                          color: secondaryColor.withValues(alpha: .8),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: TimelineActivityRow.iconColumnWidth,
                          child: Center(
                            heightFactor: 1,
                            child: TimelineActivityIndicator(
                              icon: icon,
                              active: false,
                              staticIconSize: 16,
                              color: indicatorColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: TimelineActivityRow.gap),
                        Flexible(
                          child: Text(
                            label,
                            key: const ValueKey('work-header-title'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.chevron_right_rounded,
                          size: 16,
                          color: secondaryColor.withValues(alpha: .74),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
