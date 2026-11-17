import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class SearchSessionNoteToolDisplay extends ToolDisplaySpec {
  const SearchSessionNoteToolDisplay()
    : super(
        'builtin.search_session_note@1',
        ToolDisplayCategory.search,
        targetFields: const ['query'],
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameSearchSessionNote;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'query',
    l10n.timelineToolDetailQuery,
    required: true,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, result, {
        'responses': l10n.timelineToolDetailSearchResults,
        'response': l10n.timelineToolDetailSearchResults,
        'output': l10n.timelineToolDetailSearchResults,
        'preview': l10n.timelineToolDetailSearchResults,
        'results': l10n.timelineToolDetailSearchResults,
        'sources': l10n.timelineToolDetailSource,
        'matches': l10n.timelineToolDetailMatches,
        'items': l10n.timelineToolDetailResult,
        'title': l10n.timelineToolDetailTitle,
        'url': l10n.timelineToolDetailLink,
        'snippet': l10n.timelineToolDetailSummary,
        'content': l10n.timelineToolDetailContent,
        'text': l10n.timelineToolDetailContent,
        'line': l10n.timelineToolDetailLine,
        'column': l10n.timelineToolDetailColumn,
        'before': l10n.timelineToolDetailBefore,
        'after': l10n.timelineToolDetailAfter,
        'path': l10n.timelineToolDetailFile,
        'markdown': l10n.timelineToolDetailContent,
      });
}
