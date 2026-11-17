import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'execution_result.dart';

final class WriteStdinToolDisplay extends ToolDisplaySpec {
  const WriteStdinToolDisplay()
    : super('builtin.write_stdin@1', ToolDisplayCategory.stdin);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWriteStdin;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'chars',
    l10n.timelineToolDetailStdin,
    code: true,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolExecutionResult(l10n, result);
}
