import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class DeepseekWebFetchToolDisplay extends ToolDisplaySpec {
  const DeepseekWebFetchToolDisplay()
    : super(
        'builtin.deepseek_web_fetch@1',
        ToolDisplayCategory.fetch,
        outputFormat: ToolOutputFormat.text,
        targetFields: const ['url'],
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameDeepseekWebFetch;

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
