import 'package:anywork_client/models.dart' show ConversationActivityView;
import 'package:material_ui/material_ui.dart';

import '../live_status/live_status_header_spec.dart';
import '../state/timeline_display_models.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';

enum WorkDisplayLocation { live, history }

/// One producer-defined Work header with naturally sized complete members.
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
            startedAtMillis: widget.timing.startedAtMillis,
            finishedAtMillis: widget.timing.finishedAtMillis,
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
              seconds: seconds,
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
                child: Builder(builder: widget.childBuilder),
              ),
            ),
      expansibleBuilder: (context, header, body, animation) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, body],
      ),
    );
  }
}

/// Work has its own header geometry, independent of the compact member rows.
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
    final spec = LiveStatusHeaderSpec.forWorkGroup(
      context,
      state: state,
      executionPresent: executionPresent,
      activity: activity,
      thinkingSummary: thinkingSummary,
      seconds: seconds,
      titleKey: const ValueKey('work-header-title'),
    );
    return TimelineActivityRow(
      label: spec.label,
      labelKey: const ValueKey('work-header-title'),
      labelWidget: spec.labelWidget,
      labelColor: spec.labelColor,
      icon: spec.icon,
      iconColor: spec.iconColor,
      indicatorStyle: spec.indicatorStyle,
      active: spec.active,
      isIssue: spec.isIssue,
      emphasized: spec.emphasized,
      header: live,
      expandable: true,
      expanded: expanded,
      meta: spec.meta,
      metaKey: const ValueKey('work-header-elapsed'),
      tooltip: spec.tooltip,
      semanticsLabel: spec.semanticsLabel,
    );
  }
}
