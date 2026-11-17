import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class ViewImageToolDisplay extends ToolDisplaySpec {
  const ViewImageToolDisplay()
    : super(
        'builtin.view_image@1',
        ToolDisplayCategory.image,
        kind: ToolDetailKind.image,
        omitSuccessOutput: true,
        targetFields: const ['path'],
        fileTarget: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameViewImage;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'path',
    l10n.timelineToolDetailFile,
    required: true,
  );

  @override
  String statusTitle(AppLocalizations l10n, TimelineToolPresentation item) =>
      switch (item.statusString) {
        'succeeded' => l10n.timelineViewImageRead,
        'failed' || 'denied' => l10n.timelineViewImageFailed,
        'cancelled' || 'interrupted' => l10n.timelineViewImageStopped,
        'queued' ||
        'running' ||
        'streaming' ||
        'approved' ||
        'started' => l10n.timelineViewImageReading,
        _ =>
          item.statusString.trim().isEmpty
              ? displayName(l10n, item)
              : l10n.timelineToolUnknownStatus(
                  displayName(l10n, item),
                  item.statusString,
                ),
      };
}
