import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.create_directory@1`.
class CreateDirectoryToolItem extends StructuredTimelineToolAdapter {
  const CreateDirectoryToolItem();

  static const String contractId = 'builtin.create_directory@1';

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
      l10n.timelineToolNameCreateDirectory;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.create_new_folder_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolCreateRunning
        : failed
        ? l10n.timelineToolCreateFailed
        : l10n.timelineToolCreateSucceeded;
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'path',
    l10n.timelineToolDetailFile,
    required: true,
  );
}
