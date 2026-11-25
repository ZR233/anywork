import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../shared/studio_driver_keys.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.view_image@1`.
class ViewImageToolItem extends StructuredTimelineToolAdapter {
  const ViewImageToolItem();

  static const String contractId = 'builtin.view_image@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy =>
      const TimelineToolBodyPolicy(omitSuccessOutput: true);

  @override
  List<String> get targetFields => const ['path'];

  @override
  bool get fileTarget => true;

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameViewImage;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.image_outlined);

  @override
  Key buildCardKey(TimelineToolItemContext context) =>
      StudioDriverKeys.viewImageTool(context.item.toolCallId);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineViewImageReading,
        failed: l10n.timelineViewImageFailed,
        succeeded: l10n.timelineViewImageRead,
      );

  @override
  String statusTitle(AppLocalizations l10n, TimelineToolPresentation item) =>
      switch (item.statusString) {
        'succeeded' => l10n.timelineViewImageRead,
        'failed' || 'denied' => l10n.timelineViewImageFailed,
        'cancelled' || 'interrupted' => l10n.timelineViewImageStopped,
        'queued' ||
        'running' ||
        'streaming' ||
        'approved' ||
        'started' => l10n.timelineViewImageReading,
        _ =>
          item.statusString.trim().isEmpty
              ? displayName(l10n, item)
              : l10n.timelineToolUnknownStatus(
                  displayName(l10n, item),
                  item.statusString,
                ),
      };

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'path',
    l10n.timelineToolDetailFile,
    required: true,
  );
}
