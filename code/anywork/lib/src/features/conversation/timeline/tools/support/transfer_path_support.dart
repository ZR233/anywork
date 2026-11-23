import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/typed_json.dart';
import '../../state/tool_presentation.dart';
import 'tool_detail_values.dart';

/// Decodes canonical `copy_path` / `move_path` arguments.
List<ToolDetailValue> toolTransferInput(AppLocalizations l10n, String text) {
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

/// Formats compact basename transition for the collapsed row and full multi-line
/// paths as hover tooltip.
ToolRowTarget toolTransferRowTarget(
  TimelineToolPresentation item, {
  required ToolRowTarget fallback,
}) {
  final data = decodeJsonObject(item.arguments);
  final from = toolFirstLine(jsonStringValue(data['from']));
  final to = toolFirstLine(jsonStringValue(data['to']));
  if (from == null && to == null) return fallback;
  final names = [?toolPathBasename(from), ?toolPathBasename(to)].join(' → ');
  return (
    label: names.isEmpty ? null : names,
    tooltip: [?from, if (to != null) '→ $to'].join('\n'),
  );
}
