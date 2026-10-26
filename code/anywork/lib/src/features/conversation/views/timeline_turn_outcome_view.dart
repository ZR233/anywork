import 'package:flutter/material.dart';

import '../widgets/activity_row.dart';

enum TimelineTurnOutcomeKind { stopped, failed }

/// The connector owns typed Turn interpretation and localization. This view
/// only renders the control outcome or the original real failure diagnostic.
class TimelineTurnOutcomeView extends StatelessWidget {
  const TimelineTurnOutcomeView({
    required this.itemId,
    required this.kind,
    required this.label,
    super.key,
  });

  final String itemId;
  final TimelineTurnOutcomeKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outcomeKey = ValueKey('timeline-turn-outcome:$itemId');
    return Semantics(
      liveRegion: true,
      child: kind == TimelineTurnOutcomeKind.stopped
          ? TimelineActivityRow(
              key: outcomeKey,
              icon: Icons.stop_circle_outlined,
              label: label,
              expandable: false,
            )
          : Text(
              label,
              key: outcomeKey,
              style: TextStyle(color: colors.error),
            ),
    );
  }
}
