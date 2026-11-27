import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../shared/typed_json.dart';
import '../../../state/tool_presentation.dart';
import '../../support/agent_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.send_message@1` (and uncontracted live `send_message`
/// atoms).
class SendMessageToolItem extends StructuredTimelineToolAdapter {
  const SendMessageToolItem();

  static const String contractId = 'builtin.send_message@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName('send_message', requireEmptyContract: true),
  ]);

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
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolMessageRunning,
        failed: l10n.timelineToolMessageFailed,
        succeeded: l10n.timelineToolMessageSucceeded,
        backgroundStarted: l10n.timelineToolStateBackgroundStarted,
        backgrounded: l10n.timelineToolStateBackgrounded,
      );

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) {
    final recipient = toolAgentRowTarget(item).label;
    final arguments = decodeJsonObject(item.arguments);
    final rawMessage = jsonStringValue(arguments['message']);
    final excerpt = toolCompactExcerpt(rawMessage);
    final label = switch ((recipient, excerpt)) {
      (final who?, final what?) => '$who · $what',
      (final who?, null) => who,
      (null, final what?) => what,
      (null, null) => null,
    };
    final fullMessage = toolFirstLine(rawMessage);
    final tooltip = switch ((recipient, fullMessage)) {
      (final who?, final what?) => '$who · $what',
      (final who?, null) => who,
      (null, final what?) => what,
      (null, null) => null,
    };
    return (label: label, tooltip: tooltip);
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    return [
      ...toolField(l10n, data, 'target', l10n.timelineToolDetailTarget),
      ...toolField(l10n, data, 'message', l10n.timelineToolDetailMessage),
    ];
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolAgentResult(l10n, result);
}
