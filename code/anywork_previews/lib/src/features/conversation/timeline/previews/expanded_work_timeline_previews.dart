import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import 'expanded_work_timeline_fixture.dart';

// Each scene has 120 mixed tool/reasoning members, not 120 catalog entries.
// Production Chinese theme; 820×820 with scale 1.0 is the default capture setup.
// Landmarks: 成员 001 (first), 060 (middle), 120 (last).

@Preview(
  name: 'WG-history-120 · 历史 · 120成员完整展开',
  group: 'Timeline · 完整工作组',
  size: Size(820, 820),
)
Widget expandedWorkHistoryPreview() => const ExpandedWorkTimelineFixture();

@Preview(
  name: 'WG-live-120 · 实时底部 · 120成员完整展开',
  group: 'Timeline · 完整工作组',
  size: Size(820, 820),
)
Widget expandedWorkLivePreview() =>
    const ExpandedWorkTimelineFixture(location: WorkDisplayLocation.live);

@Preview(
  name: 'WG-history-120-scaled · 历史 · 150%字号',
  group: 'Timeline · 完整工作组',
  size: Size(820, 820),
)
Widget expandedWorkHistoryScaledPreview() =>
    const ExpandedWorkTimelineFixture(textScale: 1.5);

@Preview(
  name: 'WG-live-120-folded · 实时底部 · 折叠后展开',
  group: 'Timeline · 完整工作组',
  size: Size(820, 820),
)
Widget expandedWorkLiveFoldedPreview() => const ExpandedWorkTimelineFixture(
  location: WorkDisplayLocation.live,
  initiallyExpanded: false,
);
