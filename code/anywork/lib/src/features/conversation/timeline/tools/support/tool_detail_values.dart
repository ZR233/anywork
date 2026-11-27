import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../../../../l10n/app_localizations.dart';
import '../../../../../l10n/studio_l10n.dart';

/// Semantic acceptance state for mutating/collaborative tool executions.
enum ToolAcceptance { pending, accepted, rejected }

/// Structured acceptance projection decoded from tool output receipts.
final class ToolAcceptanceProjection {
  const ToolAcceptanceProjection(this.state, {this.code, this.reason});

  final ToolAcceptance state;
  final String? code;
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is ToolAcceptanceProjection &&
      other.state == state &&
      other.code == code &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(state, code, reason);
}

/// Strongly-typed value rendered by [TimelineToolSemanticBody].
sealed class ToolDetailValue {
  const ToolDetailValue();
}

final class ToolDetailText extends ToolDetailValue {
  const ToolDetailText(this.title, this.text, {this.code = false});

  final String title;
  final String text;
  final bool code;
}

final class ToolDetailLink extends ToolDetailValue {
  const ToolDetailLink(this.title, this.url);

  final String title;
  final String url;
}

final class ToolDetailUnavailable extends ToolDetailValue {
  const ToolDetailUnavailable(this.reason);

  final String reason;
}

/// Parses structured JSON arguments as a map or throws a localized [FormatException].
Map<String, dynamic> toolArguments(AppLocalizations l10n, String text) {
  return switch (jsonDecode(text)) {
    final Map<String, dynamic> result => result,
    _ => throw FormatException(l10n.timelineToolExpectedObject),
  };
}

/// Extracts a required or optional string field from decoded [data].
///
/// Empty strings are preserved only for `'content'`.
List<ToolDetailValue> toolField(
  AppLocalizations l10n,
  Map<String, dynamic> data,
  String key,
  String title, {
  bool code = false,
  bool required = false,
}) => switch (data[key]) {
  final String value when value.trim().isNotEmpty || key == 'content' => [
    ToolDetailText(title, value, code: code),
  ],
  null || '' when !required => const [],
  _ => throw FormatException(l10n.timelineToolInvalidField(title)),
};

/// Standard diagnostic field labels projected from structured tool results.
Map<String, String> toolDiagnosticFields(AppLocalizations l10n) => {
  'error': l10n.timelineToolDetailError,
  'message': l10n.timelineToolDetailDescription,
  'reason': l10n.timelineToolDetailReason,
  'diagnostic': l10n.timelineToolDetailDiagnostic,
  'detail': l10n.timelineToolDetailDiagnosticDetail,
  'code': l10n.timelineToolDetailDiagnosticCode,
};

/// Wraps plain non-empty String [result] into a single [ToolDetailText] entry.
List<ToolDetailValue> toolTextResult(AppLocalizations l10n, Object? result) =>
    switch (result) {
      final String text when text.trim().isNotEmpty => [
        ToolDetailText(l10n.timelineToolDetailResult, text),
      ],
      null || '' => const [],
      _ => throw FormatException(l10n.timelineToolExpectedText),
    };

/// Projects [result] using [fields] plus standard [toolDiagnosticFields].
List<ToolDetailValue> toolProject(
  AppLocalizations l10n,
  Object? result,
  Map<String, String> fields,
) => toolResultFields(l10n, result, {...fields, ...toolDiagnosticFields(l10n)});

/// Recursively projects JSON structures into labeled [ToolDetailValue] rows
/// without leaking unmapped internal transport keys.
List<ToolDetailValue> toolResultFields(
  AppLocalizations l10n,
  Object? result,
  Map<String, String> fields, {
  bool unavailableWhenEmpty = true,
}) {
  if (result == null) return const [];
  if (result is String) return toolTextResult(l10n, result);
  if (result is List) {
    return [
      for (final entry in result) ...toolResultFields(l10n, entry, fields),
    ];
  }
  if (result is! Map<String, dynamic>) {
    return [ToolDetailUnavailable(l10n.timelineToolResultMalformed)];
  }
  final values = <ToolDetailValue>[];
  for (final MapEntry(key: key, value: title) in fields.entries) {
    switch (result[key]) {
      case final String text when text.trim().isNotEmpty:
        values.add(
          key == 'url'
              ? ToolDetailLink(title, text)
              : ToolDetailText(title, text),
        );
      case final num number:
        values.add(ToolDetailText(title, '$number'));
      case final bool flag:
        values.add(
          ToolDetailText(
            title,
            flag ? l10n.timelineToolDetailYes : l10n.timelineToolDetailNo,
          ),
        );
      case final List entries:
        if (entries.isEmpty) {
          values.add(ToolDetailText(title, l10n.timelineToolDetailNone));
        }
        for (final entry in entries) {
          values.addAll(toolResultFields(l10n, entry, fields));
        }
      case final Map<String, dynamic> nested:
        values.addAll(toolResultFields(l10n, nested, fields));
      case null:
        break;
      default:
        values.add(
          ToolDetailUnavailable(l10n.timelineToolFieldMalformed(title)),
        );
    }
  }
  if (unavailableWhenEmpty && values.isEmpty && result.isNotEmpty) {
    values.add(ToolDetailUnavailable(l10n.timelineToolNoSemanticContent));
  }
  return values;
}

/// Strictly parses a complete JSON object or list, throwing rather than
/// leaking truncated JSON fragments.
Object toolStructuredResult(AppLocalizations l10n, String text) {
  final Object? result;
  try {
    result = jsonDecode(text);
  } on FormatException {
    throw FormatException(l10n.timelineToolStructuredUnavailable);
  }
  if (result is Map<String, dynamic> || result is List) return result!;
  throw FormatException(l10n.timelineToolExpectedStructured);
}

/// Executes [decode], catching malformed format/number bounds and returning
/// an unmodifiable list of [ToolDetailValue] items.
List<ToolDetailValue> decodeToolValues(
  AppLocalizations l10n,
  List<ToolDetailValue> Function() decode,
) {
  try {
    return List.unmodifiable(decode());
  } on FormatException catch (error) {
    return [
      ToolDetailUnavailable(l10n.timelineToolContentMalformed(error.message)),
    ];
  } on RangeError {
    return [ToolDetailUnavailable(l10n.timelineToolNumberOutOfRange)];
  }
}

/// Decodes LSP text strictly as JSON when valid, falling back to raw text.
Object? decodeLspResultOrText(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

String? toolFirstLine(String? value) {
  final line = value?.split('\n').first.trim();
  return line == null || line.isEmpty ? null : line;
}

String? toolPathBasename(String? value) {
  if (value == null) return null;
  // A remote Windows path must remain readable on a Linux display host.
  final segment = (value.contains(r'\') ? p.windows : p.posix)
      .basename(value)
      .trim();
  return segment.isEmpty ? value : segment;
}

String timelineFormatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String timelineAttachmentDescription(
  BuildContext context,
  ThreadAttachmentView attachment,
) {
  final dimensions = attachment.width != null && attachment.height != null
      ? ' · ${attachment.width}×${attachment.height}'
      : '';
  final label = attachment.filename ?? context.l10n.attachmentFallback;
  return '$label$dimensions · ${timelineFormatBytes(attachment.byteSize)}';
}
