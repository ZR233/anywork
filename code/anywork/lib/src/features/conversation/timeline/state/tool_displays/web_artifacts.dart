import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';

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
    // 该字段也允许直接引用一个来源 URL，但不公开其它原始信封。
    if (const {'http', 'https'}.contains(Uri.tryParse(text)?.scheme)) {
      links.add(text);
    }
  }
  return List.unmodifiable([
    for (final url in links) ToolDetailLink(l10n.timelineToolDetailSource, url),
  ]);
}
