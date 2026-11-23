import '../../../../../l10n/app_localizations.dart';
import 'tool_detail_values.dart';

/// Collects up to 6 external HTTP/HTTPS artifact links without leaking internal
/// transport metadata such as `taskId`.
List<ToolDetailValue> toolWebArtifacts(AppLocalizations l10n, String text) {
  final links = <String>{};
  void collect(Object? value) {
    if (links.length >= 6) return;
    switch (value) {
      case final String url
          when const {'http', 'https'}.contains(Uri.tryParse(url)?.scheme):
        links.add(url);
      case final List entries:
        for (final entry in entries) {
          collect(entry);
        }
      case final Map<String, dynamic> object:
        for (final entry in object.values) {
          collect(entry);
        }
      default:
        break;
    }
  }

  try {
    collect(toolStructuredResult(l10n, text));
  } on FormatException {
    if (const {'http', 'https'}.contains(Uri.tryParse(text)?.scheme)) {
      links.add(text);
    }
  }
  return List.unmodifiable([
    for (final url in links) ToolDetailLink(l10n.timelineToolDetailSource, url),
  ]);
}
