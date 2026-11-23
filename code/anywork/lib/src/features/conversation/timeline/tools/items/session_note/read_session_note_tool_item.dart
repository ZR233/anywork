import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.read_session_note@1`.
class ReadSessionNoteToolItem extends StructuredTimelineToolAdapter {
  const ReadSessionNoteToolItem();

  static const String contractId = 'builtin.read_session_note@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameReadSessionNote;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.menu_book_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolReadReading
        : failed
        ? l10n.timelineToolReadFailed
        : l10n.timelineToolReadCompleted;
  }

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) => (label: l10n.timelineSessionNoteName, tooltip: null);

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, result, {
        'startLine': l10n.timelineToolDetailStartLine,
        'endLine': l10n.timelineToolDetailEndLine,
        'content': l10n.timelineToolDetailNote,
        'text': l10n.timelineToolDetailNote,
        'lines': l10n.timelineToolDetailNote,
        'line': l10n.timelineToolDetailLine,
      });
}
