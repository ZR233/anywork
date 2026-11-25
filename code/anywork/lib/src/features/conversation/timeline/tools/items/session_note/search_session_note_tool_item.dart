import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.search_session_note@1`.
class SearchSessionNoteToolItem extends StructuredTimelineToolAdapter {
  const SearchSessionNoteToolItem();

  static const String contractId = 'builtin.search_session_note@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  List<String> get targetFields => const ['query'];

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameSearchSessionNote;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.search);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolSearchRunning,
        failed: l10n.timelineToolSearchFailed,
        succeeded: l10n.timelineToolSearchSucceeded,
      );

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
