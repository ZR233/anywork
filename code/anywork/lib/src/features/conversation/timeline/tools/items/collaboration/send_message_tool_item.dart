import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/agent_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.send_message@1`.
class SendMessageToolItem extends StructuredTimelineToolAdapter {
  const SendMessageToolItem();

  static const String contractId = 'builtin.send_message@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy =>
      const TimelineToolBodyPolicy(omitSuccessOutput: true);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameSendMessage;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.send_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolMessageRunning
        : failed
        ? l10n.timelineToolMessageFailed
        : l10n.timelineToolMessageSucceeded;
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'message',
    l10n.timelineToolDetailMessage,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolAgentResult(l10n, result);
}
