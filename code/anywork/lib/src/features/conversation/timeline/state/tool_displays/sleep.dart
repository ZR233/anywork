import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class SleepToolDisplay extends ToolDisplaySpec {
  const SleepToolDisplay()
    : super(
        'builtin.sleep@1',
        ToolDisplayCategory.wait,
        outputFormat: ToolOutputFormat.text,
        omitSuccessOutput: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameSleep;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) =>
      switch (toolArguments(l10n, text)) {
        {'durationMs': final num ms} => [
          ToolDetailText(
            l10n.timelineToolDetailWait,
            l10n.timelineToolSeconds(ms / 1000),
          ),
        ],
        _ => throw FormatException(l10n.timelineToolMissingDuration),
      };

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolTextResult(l10n, result);
}
