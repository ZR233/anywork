import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'web_artifacts.dart';

final class DeepseekWebSearchToolDisplay extends ToolDisplaySpec {
  const DeepseekWebSearchToolDisplay()
    : super(
        'builtin.deepseek_web_search@1',
        ToolDisplayCategory.search,
        outputFormat: ToolOutputFormat.text,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameDeepseekWebSearch;

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
