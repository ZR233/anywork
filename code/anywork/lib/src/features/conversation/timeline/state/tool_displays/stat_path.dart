import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class StatPathToolDisplay extends ToolDisplaySpec {
  const StatPathToolDisplay()
    : super(
        'builtin.stat_path@1',
        ToolDisplayCategory.read,
        targetFields: const ['path'],
        fileTarget: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameStatPath;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'path',
    l10n.timelineToolDetailFile,
    required: true,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) {
    return switch (result) {
      {'exists': final bool exists} && final Map<String, dynamic> stat => [
        ToolDetailText(
          l10n.timelineToolDetailExists,
          exists ? l10n.timelineToolDetailYes : l10n.timelineToolDetailNo,
        ),
        if (stat['type'] case final String type)
          ToolDetailText(l10n.timelineToolDetailType, switch (type) {
            'file' => l10n.timelineToolFileTypeFile,
            'directory' => l10n.timelineToolFileTypeDirectory,
            'other' => l10n.timelineToolFileTypeOther,
            _ => type,
          }),
        if (stat['len'] case final int len)
          ToolDetailText(l10n.timelineToolDetailBytes, '$len'),
        if (stat['readonly'] case final bool readonly)
          ToolDetailText(
            l10n.timelineToolDetailReadOnly,
            readonly ? l10n.timelineToolDetailYes : l10n.timelineToolDetailNo,
          ),
        if (stat['modifiedAt'] case final int modifiedAt)
          ToolDetailText(
            l10n.timelineToolDetailModifiedAt,
            DateTime.fromMillisecondsSinceEpoch(modifiedAt)
                .toLocal()
                .toString(),
          ),
      ],
      final Map<String, dynamic> diagnostic => toolResultFields(
        l10n,
        diagnostic,
        toolDiagnosticFields(l10n),
      ),
      _ => [ToolDetailUnavailable(l10n.timelineToolStatMalformed)],
    };
  }
}
