import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.deepseek_web_fetch@1`.
class DeepseekWebFetchToolItem extends StructuredTimelineToolAdapter {
  const DeepseekWebFetchToolItem();

  static const String contractId = 'builtin.deepseek_web_fetch@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy =>
      const TimelineToolBodyPolicy(readsStructuredOutput: false);

  @override
  List<String> get targetFields => const ['url'];

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameDeepseekWebFetch;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.public);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolFetchRunning
        : failed
        ? l10n.timelineToolFetchFailed
        : l10n.timelineToolFetchSucceeded;
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) =>
      switch (toolArguments(l10n, text)) {
        {'url': final String url} => [
          ToolDetailLink(l10n.timelineToolDetailWebpage, url),
        ],
        _ => throw FormatException(l10n.timelineToolMissingWebUrl),
      };

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolTextResult(l10n, result);
}
