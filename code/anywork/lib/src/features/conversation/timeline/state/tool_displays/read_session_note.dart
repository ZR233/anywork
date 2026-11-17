import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class ReadSessionNoteToolDisplay extends ToolDisplaySpec {
  const ReadSessionNoteToolDisplay()
    : super('builtin.read_session_note@1', ToolDisplayCategory.read);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameReadSessionNote;

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

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) => (label: l10n.timelineSessionNoteName, tooltip: null);
}
