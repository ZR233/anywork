import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'task_state_values.dart';

final class ShowFilesToolDisplay extends ToolDisplaySpec {
  const ShowFilesToolDisplay()
    : super('builtin.show_files@1', ToolDisplayCategory.image);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameShowFiles;

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) => null;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'caption',
    l10n.timelineToolDetailDescription,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, toolTaskStateValues(l10n, result), {
        'caption': l10n.timelineToolDetailDescription,
        'files': l10n.timelineToolDetailFile,
        'filename': l10n.timelineToolDetailFile,
        'outcome': l10n.timelineToolDetailResult,
        'status': l10n.timelineToolDetailStatus,
      });
}
