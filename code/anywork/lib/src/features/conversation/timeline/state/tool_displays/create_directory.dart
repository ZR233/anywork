import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class CreateDirectoryToolDisplay extends ToolDisplaySpec {
  const CreateDirectoryToolDisplay()
    : super(
        'builtin.create_directory@1',
        ToolDisplayCategory.create,
        omitSuccessOutput: true,
        targetFields: const ['path'],
        fileTarget: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameCreateDirectory;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'path',
    l10n.timelineToolDetailFile,
    required: true,
  );
}
