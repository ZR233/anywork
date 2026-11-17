import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class LspStatusToolDisplay extends ToolDisplaySpec {
  const LspStatusToolDisplay()
    : super(
        'builtin.lsp_status@1',
        ToolDisplayCategory.lsp,
        kind: ToolDetailKind.lspStatus,
        outputFormat: ToolOutputFormat.lsp,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineLspStatusTitle;

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      switch (item.statusString) {
        'running' ||
        'streaming' ||
        'approved' ||
        'started' => l10n.timelineLspStatusRunning,
        'failed' => l10n.timelineLspStatusFailed,
        'succeeded' => l10n.timelineLspStatusSucceeded,
        _ => null,
      };
}
