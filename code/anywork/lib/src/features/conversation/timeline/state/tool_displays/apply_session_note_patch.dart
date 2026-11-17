import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class ApplySessionNotePatchToolDisplay extends ToolDisplaySpec {
  const ApplySessionNotePatchToolDisplay()
    : super(
        'builtin.apply_session_note_patch@1',
        ToolDisplayCategory.edit,
        omitSuccessOutput: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameApplySessionNotePatch;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'patch',
    l10n.timelineToolDetailPatch,
    code: true,
    required: true,
  );

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) => (label: l10n.timelineSessionNoteName, tooltip: null);
}
