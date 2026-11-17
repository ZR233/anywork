import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import '../../../../../shared/typed_json.dart';

final class CopyPathToolDisplay extends ToolDisplaySpec {
  const CopyPathToolDisplay()
    : super(
        'builtin.copy_path@1',
        ToolDisplayCategory.copy,
        omitSuccessOutput: true,
        targetFields: const ['from', 'to'],
        fileTarget: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameCopyPath;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    return switch (toolArguments(l10n, text)) {
      {
        'from': final String from,
        'to': final String to,
        'collision': final String collision,
      } =>
        [
          ToolDetailText(l10n.timelineToolDetailFile, '$from → $to'),
          ToolDetailText(l10n.timelineToolDetailCollision, switch (collision) {
            'failIfExists' => l10n.timelineToolCollisionReject,
            'overwrite' => l10n.timelineToolCollisionOverwrite,
            _ => throw FormatException(l10n.timelineToolInvalidCollision),
          }),
        ],
      _ => throw FormatException(l10n.timelineToolMissingTransferPaths),
    };
  }

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) {
    final data = decodeJsonObject(item.arguments);
    final from = toolFirstLine(jsonStringValue(data['from']));
    final to = toolFirstLine(jsonStringValue(data['to']));
    if (from == null && to == null) return super.rowTarget(l10n, item);
    final names = [
      if (from != null) toolPathBasename(from),
      if (to != null) toolPathBasename(to),
    ].whereType<String>().join(' → ');
    return (
      label: names.isEmpty ? null : names,
      tooltip: [?from, if (to != null) '→ $to'].join('\n'),
    );
  }
}
