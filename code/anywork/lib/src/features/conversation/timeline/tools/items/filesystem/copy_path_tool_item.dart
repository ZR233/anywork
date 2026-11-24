import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../support/transfer_path_support.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.copy_path@1`.
class CopyPathToolItem extends StructuredTimelineToolAdapter {
  const CopyPathToolItem();

  static const String contractId = 'builtin.copy_path@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy =>
      const TimelineToolBodyPolicy(omitSuccessOutput: true);

  @override
  List<String> get targetFields => const ['from', 'to'];

  @override
  bool get fileTarget => true;

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameCopyPath;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.content_copy_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolCopyRunning
        : failed
        ? l10n.timelineToolCopyFailed
        : l10n.timelineToolCopySucceeded;
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) =>
      toolTransferInput(l10n, text);

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) => toolTransferRowTarget(item, fallback: super.rowTarget(l10n, item));
}
