import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.delete_path@1`.
class DeletePathToolItem extends StructuredTimelineToolAdapter {
  const DeletePathToolItem();

  static const String contractId = 'builtin.delete_path@1';

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
      l10n.timelineToolNameDeletePath;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.delete_outline);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolDeleteRunning
        : failed
        ? l10n.timelineToolDeleteFailed
        : l10n.timelineToolDeleteSucceeded;
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    return [
      ...toolField(
        l10n,
        data,
        'path',
        l10n.timelineToolDetailFile,
        required: true,
      ),
      ToolDetailText(
        l10n.timelineToolDetailDeleteObject,
        switch (data['mode']) {
          'file' => l10n.timelineToolDetailFile,
          'emptyDirectory' => l10n.timelineToolDeleteEmptyDirectory,
          'recursiveDirectory' => l10n.timelineToolDeleteRecursiveDirectory,
          _ => throw FormatException(l10n.timelineToolInvalidDeleteMode),
        },
      ),
    ];
  }
}
