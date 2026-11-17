import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class DeletePathToolDisplay extends ToolDisplaySpec {
  const DeletePathToolDisplay()
    : super(
        'builtin.delete_path@1',
        ToolDisplayCategory.delete,
        omitSuccessOutput: true,
        targetFields: const ['path'],
        fileTarget: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameDeletePath;

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
