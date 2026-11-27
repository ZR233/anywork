import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/typed_json.dart';
import '../../state/tool_presentation.dart';
import 'task_state_values_support.dart';
import 'tool_detail_values.dart';

final RegExp _rawThreadHashWithTag = RegExp(
  r'^thread-[0-9a-fA-F]{6,}-([A-Za-z0-9_]{1,8})$',
);
final RegExp _rawThreadHash = RegExp(r'^thread-[0-9a-fA-F]{6,}$');

/// Default readable label keys checked before raw agent/thread identifiers.
const List<String> defaultAgentReadableKeys = [
  'agentName',
  'targetName',
  'displayName',
  'name',
  'role',
  'profileId',
  'title',
];

/// Default identifier fallback keys when no human-readable label is available.
const List<String> defaultAgentIdKeys = ['target', 'agentId', 'threadId', 'id'];

/// Returns `true` when [value] looks like an opaque `thread-...` identifier
/// that should never be displayed verbatim on a collapsed primary row.
bool isRawThreadIdentifier(String value) {
  final trimmed = value.trim();
  return trimmed.startsWith('thread-') &&
      (_rawThreadHashWithTag.hasMatch(trimmed) ||
          _rawThreadHash.hasMatch(trimmed) ||
          trimmed.length >= 16);
}

/// Condenses an opaque `thread-<hash>-<tag>` identifier into `#<tag>` for
/// primary-row display, or returns `null` when only an un-tagged hash exists.
String? compactAgentTargetLabel(String? raw) {
  final line = toolFirstLine(raw);
  if (line == null) return null;
  if (!line.startsWith('thread-')) return line;
  final match = _rawThreadHashWithTag.firstMatch(line);
  if (match != null) {
    return '#${match.group(1)}';
  }
  return isRawThreadIdentifier(line) ? null : line;
}

/// Extracts a human-readable collaboration target label from [item] arguments
/// and output without exposing raw `thread-xxxx` IDs on the collapsed row.
ToolRowTarget toolAgentRowTarget(
  TimelineToolPresentation item, {
  List<String> readableKeys = defaultAgentReadableKeys,
  List<String> idKeys = defaultAgentIdKeys,
}) {
  final arguments = decodeJsonObject(item.arguments);
  final output = decodeJsonObject(item.output);
  final sources = [
    arguments,
    output,
    jsonObject(output['evaluation']),
    jsonObject(output['agent']),
    jsonObject(output['identity']),
  ];

  for (final key in readableKeys) {
    for (final map in sources) {
      final value = toolFirstLine(jsonStringValue(map[key]));
      if (value != null && !isRawThreadIdentifier(value)) {
        return (label: value, tooltip: value);
      }
    }
  }

  for (final key in idKeys) {
    for (final map in sources) {
      final raw = toolFirstLine(jsonStringValue(map[key]));
      if (raw == null) continue;
      final compact = compactAgentTargetLabel(raw);
      if (compact != null) {
        return (label: compact, tooltip: compact);
      }
    }
  }
  return (label: null, tooltip: null);
}

/// Truncates a single-line excerpt for compact primary-row display.
String? toolCompactExcerpt(String? raw, {int maxChars = 48}) {
  final line = toolFirstLine(raw);
  if (line == null) return null;
  if (line.length <= maxChars) return line;
  return '${line.substring(0, maxChars - 1)}…';
}

/// Projects collaboration agent / message results without leaking internal task IDs.
List<ToolDetailValue> toolAgentResult(AppLocalizations l10n, Object? result) =>
    toolProject(l10n, toolTaskStateValues(l10n, result), {
      'messageAccepted': l10n.timelineToolDetailInputAccepted,
      'status': l10n.timelineToolDetailStatus,
      'state': l10n.timelineToolDetailStatus,
      'report': l10n.timelineToolDetailReport,
      'text': l10n.timelineToolDetailContent,
      'summary': l10n.timelineToolDetailSummary,
    });
