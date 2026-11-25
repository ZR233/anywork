import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../support/web_artifacts_support.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.deepseek_web_search@1`.
class DeepseekWebSearchToolItem extends StructuredTimelineToolAdapter {
  const DeepseekWebSearchToolItem();

  static const String contractId = 'builtin.deepseek_web_search@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy =>
      const TimelineToolBodyPolicy(readsStructuredOutput: false);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameDeepseekWebSearch;

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
  List<ToolDetailValue> input(AppLocalizations l10n, String text) =>
      switch (toolArguments(l10n, text)) {
        {'queries': final List queries} => [
          for (final query in queries)
            switch (query) {
              final String value => ToolDetailText(
                l10n.timelineToolDetailQuery,
                value,
              ),
              _ => throw FormatException(l10n.timelineToolInvalidSearchQuery),
            },
        ],
        _ => throw FormatException(l10n.timelineToolMissingSearchQuery),
      };

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolTextResult(l10n, result);

  @override
  List<ToolDetailValue> artifacts(AppLocalizations l10n, String text) =>
      toolWebArtifacts(l10n, text);
}
