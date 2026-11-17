import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';

final class LspCapabilitiesToolDisplay extends ToolDisplaySpec {
  const LspCapabilitiesToolDisplay()
    : super(
        'builtin.lsp_capabilities@1',
        ToolDisplayCategory.lsp,
        kind: ToolDetailKind.lspCapabilities,
        outputFormat: ToolOutputFormat.lsp,
        targetFields: const ['languageId'],
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineLspCapabilitiesTitle;

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      switch (item.statusString) {
        'running' ||
        'streaming' ||
        'approved' ||
        'started' => l10n.timelineLspCapabilitiesRunning,
        'failed' => l10n.timelineLspCapabilitiesFailed,
        'succeeded' => l10n.timelineLspCapabilitiesSucceeded,
        _ => null,
      };
}
