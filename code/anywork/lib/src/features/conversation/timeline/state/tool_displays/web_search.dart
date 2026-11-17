import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import '../../../../../shared/typed_json.dart';
import 'web_artifacts.dart';

final class WebSearchToolDisplay extends ToolDisplaySpec {
  const WebSearchToolDisplay()
    : super(
        'builtin.web_search@1',
        ToolDisplayCategory.search,
        kind: ToolDetailKind.web,
        outputFormat: ToolOutputFormat.text,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWebSearch;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    final values = <ToolDetailValue>[];
    for (final MapEntry(:key, :value) in data.entries) {
      if (value is! List) continue;
      for (final command in value) {
        values.addAll(switch ((key, command)) {
          ('search_query' || 'image_query', {'q': final String query}) => [
            ToolDetailText(l10n.timelineToolDetailQuery, query),
          ],
          ('open', {'ref_id': final String url}) => [
            ToolDetailLink(l10n.timelineToolDetailWebpage, url),
          ],
          (
            'find',
            {'ref_id': final String url, 'pattern': final String query},
          ) =>
            [
              ToolDetailLink(l10n.timelineToolDetailWebpage, url),
              ToolDetailText(l10n.timelineToolDetailFind, query),
            ],
          ('weather', {'location': final String location}) => [
            ToolDetailText(l10n.timelineToolDetailWeather, location),
          ],
          ('click', {'ref_id': final String ref, 'id': final int link}) => [
            ToolDetailText(
              l10n.timelineToolDetailOpenPageLink,
              l10n.timelineToolWebLinkReference(ref, link),
            ),
          ],
          ('finance', {'ticker': final String ticker}) => [
            ToolDetailText(l10n.timelineToolDetailFinance, ticker),
          ],
          ('sports', {'league': final String league}) => [
            ToolDetailText(l10n.timelineToolDetailSports, league),
          ],
          ('time', {'utc_offset': final String offset}) => [
            ToolDetailText(l10n.timelineToolDetailTimezone, offset),
          ],
          (
            'screenshot',
            {'ref_id': final String ref, 'pageno': final int page},
          ) =>
            [
              ToolDetailText(
                l10n.timelineToolDetailScreenshot,
                l10n.timelineToolWebPageReference(ref, page + 1),
              ),
            ],
          _ => throw FormatException(l10n.timelineToolUnknownWebQuery),
        });
      }
    }
    return values.isEmpty
        ? [ToolDetailUnavailable(l10n.timelineToolNoWebQuery)]
        : values;
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolTextResult(l10n, result);

  @override
  List<ToolDetailValue> artifacts(AppLocalizations l10n, String text) =>
      toolWebArtifacts(l10n, text);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = const {
      'running',
      'streaming',
      'approved',
      'started',
    }.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return switch (decodeJsonObject(item.arguments)) {
      {'find': final List entries} when entries.isNotEmpty =>
        running
            ? l10n.timelineWebSearchFinding
            : failed
            ? l10n.timelineWebSearchFindFailed
            : l10n.timelineWebSearchFound,
      {'open': final List entries} when entries.isNotEmpty =>
        running
            ? l10n.timelineWebSearchOpening
            : failed
            ? l10n.timelineWebSearchOpenFailed
            : l10n.timelineWebSearchOpened,
      _ =>
        running
            ? l10n.timelineWebSearchSearching
            : failed
            ? l10n.timelineWebSearchFailed
            : l10n.timelineWebSearchSearched,
    };
  }
}
