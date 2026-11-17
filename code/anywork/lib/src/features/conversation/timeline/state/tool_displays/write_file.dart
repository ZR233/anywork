import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class WriteFileToolDisplay extends ToolDisplaySpec {
  const WriteFileToolDisplay()
    : super(
        'builtin.write_file@1',
        ToolDisplayCategory.edit,
        inputBody: ToolInputBody.fileContent,
        omitSuccessOutput: true,
        targetFields: const ['path'],
        fileTarget: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWriteFile;

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
      ToolDetailText(l10n.timelineToolDetailWriteMode, switch (data['mode']) {
        'create' => l10n.timelineToolWriteCreate,
        'overwrite' => l10n.timelineToolWriteOverwrite,
        'append' => l10n.timelineToolWriteAppend,
        _ => throw FormatException(l10n.timelineToolInvalidWriteMode),
      }),
      ...toolField(
        l10n,
        data,
        'content',
        l10n.timelineToolDetailContent,
        code: true,
        required: true,
      ),
    ];
  }
}
