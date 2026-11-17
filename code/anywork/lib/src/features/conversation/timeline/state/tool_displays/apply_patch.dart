import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class ApplyPatchToolDisplay extends ToolDisplaySpec {
  const ApplyPatchToolDisplay()
    : super(
        'builtin.apply_patch@1',
        ToolDisplayCategory.edit,
        kind: ToolDetailKind.patch,
        inputBody: ToolInputBody.patch,
        omitSuccessOutput: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameApplyPatch;
}
