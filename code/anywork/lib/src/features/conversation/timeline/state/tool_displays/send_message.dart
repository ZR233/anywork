import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'agent_result.dart';

final class SendMessageToolDisplay extends ToolDisplaySpec {
  const SendMessageToolDisplay()
    : super(
        'builtin.send_message@1',
        ToolDisplayCategory.message,
        omitSuccessOutput: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameSendMessage;

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
