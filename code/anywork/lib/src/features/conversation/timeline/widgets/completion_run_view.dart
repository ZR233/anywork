import 'package:anywork_client/models.dart' show ConversationActivityView;
import 'package:material_ui/material_ui.dart';

import '../live_status/live_status_header_spec.dart';
import '../state/timeline_display_models.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';
import 'timeline_work_group_shell.dart';

enum WorkDisplayLocation { live, history }

/// One Work header with a bounded member viewport in the live status bar.
class CompletionRunView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final live = state == DisplayBlockState.open;
    return TimelineWorkGroupShell(
      disclosureKey: ValueKey('completion-run-disclosure:$id'),
      initiallyExpanded: initiallyExpanded,
      onExpandedChanged: onExpandedChanged,
      scrollBody: location == WorkDisplayLocation.live,
      railInset: live ? 15.5 : 9.5,
      railContentInset: live ? 25.5 : 17.5,
      headerBuilder: (context, expanded) => TimelineActivityClock(
        startedAtMillis: timing.startedAtMillis,
        finishedAtMillis: timing.finishedAtMillis,
        running: live,
        now: now,
        builder: (context, seconds) => _WorkHeader(
          key: ValueKey('completion-run-header:$id'),
          hasUnfinishedMembers: hasUnfinishedMembers,
          thinkingSummary: thinkingSummary,
          location: location,
          executionPresent: executionPresent,
          state: state,
          activity: activity,
          seconds: seconds,
          expanded: expanded,
        ),
      ),
      bodyBuilder: childBuilder,
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
