import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'execution_result.dart';

final class ExecToolDisplay extends ToolDisplaySpec {
  const ExecToolDisplay()
    : super(
        'builtin.exec@2',
        ToolDisplayCategory.command,
        targetFields: const ['command'],
        elapsed: true,
        circularProgress: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameExec;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'command',
    l10n.timelineToolDetailProgram,
    code: true,
    required: true,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolExecutionResult(l10n, result);
}
