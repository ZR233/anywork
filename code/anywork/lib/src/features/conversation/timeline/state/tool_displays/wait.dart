import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'task_state_values.dart';

final class WaitToolDisplay extends ToolDisplaySpec {
  const WaitToolDisplay() : super('builtin.wait@1', ToolDisplayCategory.wait);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWait;

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, toolTaskStateValues(l10n, result), {
        'tasks': l10n.timelineToolDetailTaskStatus,
        'timedOut': l10n.timelineToolDetailWaitTimedOut,
        'messagesReady': l10n.timelineToolDetailMessagesReady,
        'status': l10n.timelineToolDetailStatus,
        'state': l10n.timelineToolDetailStatus,
      });
}
