import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class WriteSessionNoteToolDisplay extends ToolDisplaySpec {
  const WriteSessionNoteToolDisplay()
    : super(
        'builtin.write_session_note@1',
        ToolDisplayCategory.edit,
        omitSuccessOutput: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWriteSessionNote;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'content',
    l10n.timelineToolDetailContent,
    code: true,
    required: true,
  );

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) => (label: l10n.timelineSessionNoteName, tooltip: null);
}
