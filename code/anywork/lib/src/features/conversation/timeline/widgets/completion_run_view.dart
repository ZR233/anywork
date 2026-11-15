import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart' show ConversationActivityView;
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../live_status/live_status_state.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';
import 'timeline_markdown.dart';
import 'timeline_reasoning_view.dart';

enum WorkDisplayLocation { live, history }

/// One producer-defined Work header with bounded, explicitly requested members.
class CompletionRunView extends StatefulWidget {
  const CompletionRunView({
    required this.id,
    required this.timing,
    required this.childBuilder,
    required this.initiallyExpanded,
    required this.location,
    this.onExpandedChanged,
    this.executionPresent = false,
    DisplayBlockState? state,
    this.activity,
    this.thinkingSummary,
    this.hasUnfinishedMembers = false,
    this.now,
    super.key,
  }) : state =
           state ??
           (location == WorkDisplayLocation.history
               ? DisplayBlockState.sealed
               : DisplayBlockState.open);
  final String id;
  final WorkTiming timing;
  final bool executionPresent;
  final DisplayBlockState state;
  final WorkDisplayLocation location;
  final ConversationActivityView? activity;
  final String? thinkingSummary;
  final bool hasUnfinishedMembers;
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
    final live = widget.state == DisplayBlockState.open;
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
            startedAt: widget.timing.startedAt,
            finishedAt: widget.timing.finishedAt,
            running: live,
            now: widget.now,
            builder: (context, seconds) => _WorkHeader(
              key: ValueKey('completion-run-header:${widget.id}'),
              hasUnfinishedMembers: widget.hasUnfinishedMembers,
              thinkingSummary: widget.thinkingSummary,
              location: widget.location,
              executionPresent: widget.executionPresent,
              state: widget.state,
              activity: widget.activity,
              seconds:
                  widget.timing.startedAt == null ||
                      (!live && widget.timing.finishedAt == null)
                  ? null
                  : seconds ?? 0,
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
                child: _MemberViewport(childBuilder: widget.childBuilder),
              ),
            ),
      expansibleBuilder: (context, header, body, animation) => LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (constraints.hasBoundedHeight)
              Flexible(fit: FlexFit.loose, child: body)
            else
              body,
          ],
        ),
      ),
    );
  }
}

/// The group owns scrolling; its connector borrows only this UI interaction
/// channel. Member data and query qualification remain with the display lease.
class CompletionRunScrollScope extends InheritedWidget {
  const CompletionRunScrollScope({
    required this.controller,
    required this.notifications,
    required super.child,
    super.key,
  });
  final ScrollController controller;
  final ValueNotifier<ScrollNotification?> notifications;

  static CompletionRunScrollScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompletionRunScrollScope>();

  @override
  bool updateShouldNotify(CompletionRunScrollScope oldWidget) =>
      controller != oldWidget.controller ||
      notifications != oldWidget.notifications;
}

class _MemberViewport extends StatefulWidget {
  const _MemberViewport({required this.childBuilder});
  final WidgetBuilder childBuilder;
  @override
  State<_MemberViewport> createState() => _MemberViewportState();
}

class _MemberViewportState extends State<_MemberViewport> {
  final _scroll = ScrollController();
  final _notifications = ValueNotifier<ScrollNotification?>(null);

  @override
  void dispose() {
    _scroll.dispose();
    _notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: available.clamp(0, 420).toDouble(),
        ),
        child: CompletionRunScrollScope(
          controller: _scroll,
          notifications: _notifications,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) _notifications.value = notification;
              return false;
            },
            // Member pagination owns edge movement. A stretching overscroll
            // decoration would independently move the anchored page in paint
            // coordinates even after its content offset has been restored.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(overscroll: false),
              child: SingleChildScrollView(
                controller: _scroll,
                primary: false,
                child: Builder(builder: widget.childBuilder),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Work alone has a strict single-line header. Other activity rows retain
/// their existing wrapping policy for questions, tools and reasoning.
class _WorkHeader extends StatelessWidget {
  const _WorkHeader({
    super.key,
    required this.hasUnfinishedMembers,
    required this.thinkingSummary,
    required this.location,
    required this.executionPresent,
    required this.state,
    required this.seconds,
    required this.expanded,
    this.activity,
  });

  final bool hasUnfinishedMembers;
  final String? thinkingSummary;
  final WorkDisplayLocation location;
  final bool executionPresent;
  final DisplayBlockState state;
  final int? seconds;
  final bool expanded;
  final ConversationActivityView? activity;

  @override
  Widget build(BuildContext context) {
    final live = state == DisplayBlockState.open;
    final cold = live && !executionPresent && hasUnfinishedMembers;
    final active = live && executionPresent && activity != null;
    final l10n = context.l10n;
    final fallback = cold
        ? l10n.timelineGroupUnrestored
        : active
        ? context.conversationActivityLabel(activity!)
        : l10n.timelineGroupRecord;
    final thought = thinkingSummary?.trim();
    final activeThought = active && thought != null && thought.isNotEmpty
        ? thought
        : null;
    final rawSummary = active ? activity?.summary?.trim() : null;
    final status =
        activeThought ??
        (rawSummary != null && rawSummary.isNotEmpty ? rawSummary : fallback);
    final duration = seconds == null
        ? fallback
        : activityDurationLabel(
            context,
            seconds!,
            kind: live
                ? ActivityDurationKind.executing
                : ActivityDurationKind.worked,
          );
    final current = live && (cold || active);
    final label = live ? status : duration;
    final description = [
      label,
      if (live && current && label != fallback) fallback,
      if (live && label != duration) duration,
    ].join('，');
    final icon = cold
        ? Icons.history_outlined
        : activity?.kind.icon ?? Icons.work_outline;
    final secondaryColor = context.colors.onSurfaceVariant;
    final indicatorColor = active
        ? context.statusColors.activeIndicator
        : secondaryColor.withValues(alpha: .78);
    final titleStyle = context.text.bodySmall!.copyWith(
      color: live
          ? (active ? context.colors.onSurface : secondaryColor)
          : secondaryColor,
      fontSize: live ? TimelineActivityRow.headerFontSize : 12,
      fontWeight: live ? FontWeight.w500 : FontWeight.w400,
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
            minHeight: live ? TimelineActivityRow.headerMinHeight : 28,
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
                              style: resolveLiveHeaderIndicatorStyle(
                                activity,
                                displayingThinkingSummary:
                                    activeThought != null,
                              ),
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
                        if (label != duration) ...[
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
