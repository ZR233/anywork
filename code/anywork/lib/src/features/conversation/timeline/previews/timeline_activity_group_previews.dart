import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../widgets/timeline_activity_group_views.dart';
import 'timeline_activity_group_preview_host.dart';

@Preview(
  name: 'Activity Group / Collapsed (8s · 2 tools, no leading icon)',
  group: 'Timeline · Activity Group',
  size: Size(760, 220),
)
Widget timelineActivityGroupCollapsedPreview() =>
    timelineActivityGroupPreviewHost(
      (record) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StudioLayout.conversationWidth,
            ),
            child: TimelineActivityGroupBlock(
              controller: TimelineActivityGroupPreviewFixtures.buildMixedGroup(
                id: 'preview-collapsed-group',
              ),
              onOpenDetail: (itemId, field) =>
                  record('open detail: $itemId / ${field.runtimeType}'),
            ),
          ),
        ],
      ),
      scenarioIdentity: 'activity-group-collapsed',
    );

@Preview(
  name: 'Activity Group / Expanded (summary-only vs expandable thinking)',
  group: 'Timeline · Activity Group',
  size: Size(760, 520),
)
Widget timelineActivityGroupExpandedPreview() =>
    timelineActivityGroupPreviewHost(
      (record) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StudioLayout.conversationWidth,
            ),
            child: TimelineActivityGroupBlock(
              controller: TimelineActivityGroupPreviewFixtures.buildMixedGroup(
                id: 'preview-expanded-group',
                expanded: true,
              ),
              onOpenDetail: (itemId, field) =>
                  record('open detail: $itemId / ${field.runtimeType}'),
            ),
          ),
        ],
      ),
      scenarioIdentity: 'activity-group-expanded',
    );

@Preview(
  name: 'Activity Group / Pure Thinking (Worked 3s, summary-only item)',
  group: 'Timeline · Activity Group',
  size: Size(760, 280),
)
Widget timelineActivityGroupPureThinkingPreview() =>
    timelineActivityGroupPreviewHost(
      (record) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StudioLayout.conversationWidth,
            ),
            child: TimelineActivityGroupBlock(
              controller:
                  TimelineActivityGroupPreviewFixtures.buildPureThinkingGroup(
                    expanded: true,
                  ),
              onOpenDetail: (itemId, field) =>
                  record('open detail: $itemId / ${field.runtimeType}'),
            ),
          ),
        ],
      ),
      scenarioIdentity: 'activity-group-pure-thinking',
    );

@Preview(
  name: 'Activity Group / Interactive Continuous Append',
  group: 'Timeline · Activity Group',
  size: Size(820, 640),
)
Widget timelineActivityGroupInteractivePreview() =>
    timelineActivityGroupPreviewHost(
      (record) => TimelineActivityGroupInteractivePreview(record: record),
      scenarioIdentity: 'activity-group-interactive',
    );
