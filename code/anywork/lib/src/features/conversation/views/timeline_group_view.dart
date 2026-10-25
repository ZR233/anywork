import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../widgets/activity_row.dart';
import 'timeline_activity_section.dart';

/// Receives only visible UI geometry and a Smart row builder. It never reads a
/// Message, presentation payload, query scope or display owner.
class TimelineGroupView extends StatelessWidget {
  const TimelineGroupView({
    required this.id,
    required this.label,
    required this.icon,
    required this.expanded,
    required this.onExpanded,
    required this.contents,
    this.active = false,
    this.isIssue = false,
    this.activityIndent = true,
    super.key,
  });
  final String id;
  final String label;
  final IconData icon;
  final bool expanded;
  final bool active;
  final bool isIssue;
  final bool activityIndent;
  final ValueChanged<bool> onExpanded;
  final Widget contents;

  @override
  Widget build(BuildContext context) => Padding(
    key: StudioDriverKeys.timelineRow(id),
    padding: const EdgeInsets.only(bottom: 6),
    child: TimelineActivitySection(
      label: label,
      icon: icon,
      expanded: expanded,
      onExpanded: onExpanded,
      active: active,
      isIssue: isIssue,
      indent: false,
      labelKey: StudioDriverKeys.timelineActivitySummary(id),
      child: Padding(
        padding: EdgeInsets.only(
          left: activityIndent ? TimelineActivityRow.groupIndent : 7,
        ),
        child: contents,
      ),
    ),
  );
}

class TimelineGroupMembersView extends StatelessWidget {
  const TimelineGroupMembersView({
    required this.memberCount,
    required this.memberBuilder,
    super.key,
  });
  final int memberCount;
  final IndexedWidgetBuilder memberBuilder;
  @override
  Widget build(BuildContext context) => memberCount <= 10
      ? ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < memberCount; i++) memberBuilder(context, i),
              ],
            ),
          ),
        )
      : SizedBox(
          height: math.min(320, MediaQuery.sizeOf(context).height * .45),
          child: ListView.builder(
            primary: false,
            itemCount: memberCount,
            itemBuilder: memberBuilder,
          ),
        );
}
