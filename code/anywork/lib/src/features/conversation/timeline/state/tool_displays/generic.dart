import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class GenericToolDisplay extends ToolDisplaySpec {
  const GenericToolDisplay()
    : super(
        'generic@1',
        ToolDisplayCategory.generic,
        outputFormat: ToolOutputFormat.text,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      item.name.trim().isEmpty || item.name == 'Tool'
      ? l10n.timelineToolFallback
      : item.name;

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolTextResult(l10n, result);
}
