import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../support/transfer_path_support.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.move_path@1`.
class MovePathToolItem extends StructuredTimelineToolAdapter {
  const MovePathToolItem();

  static const String contractId = 'builtin.move_path@1';

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
      l10n.timelineToolNameMovePath;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.drive_file_move_outline);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolMoveRunning,
        failed: l10n.timelineToolMoveFailed,
        succeeded: l10n.timelineToolMoveSucceeded,
      );

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) =>
      toolTransferInput(l10n, text);

  @override
  String? rowTarget(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolTransferRowTarget(item, fallback: super.rowTarget(l10n, item));
}
