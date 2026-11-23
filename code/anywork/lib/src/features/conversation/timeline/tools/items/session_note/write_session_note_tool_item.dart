import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.write_session_note@1`.
class WriteSessionNoteToolItem extends StructuredTimelineToolAdapter {
  const WriteSessionNoteToolItem();

  static const String contractId = 'builtin.write_session_note@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy =>
      const TimelineToolBodyPolicy(omitSuccessOutput: true);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWriteSessionNote;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.edit_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolEditRunning
        : failed
        ? l10n.timelineToolEditFailed
        : l10n.timelineToolEditSucceeded;
  }

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) => (label: l10n.timelineSessionNoteName, tooltip: null);

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'content',
    l10n.timelineToolDetailContent,
    code: true,
    required: true,
  );
}
