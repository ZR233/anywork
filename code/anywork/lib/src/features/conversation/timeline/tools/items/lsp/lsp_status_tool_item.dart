import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/lsp_presentation.dart';
import '../../../state/tool_presentation.dart';
import '../../../widgets/timeline_lsp_tool_view.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.lsp_status@1`.
class LspStatusToolItem extends StructuredTimelineToolAdapter {
  const LspStatusToolItem();

  static const String contractId = 'builtin.lsp_status@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy =>
      const TimelineToolBodyPolicy(readsStructuredOutput: false);

  @override
  bool get showsDeclaredPrefixInput => false;

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineLspStatusTitle;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.code);

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

  @override
  Widget? buildInlineBody(
    TimelineToolItemContext context, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final presentation = parseTimelineLspStatus(context.item.output);
    if (!presentation.hasOutput) return null;
    return TimelineLspToolView(
      itemId: context.item.id,
      presentation: presentation,
      markdownBuilder: context.markdownBuilder,
    );
  }

  @override
  Widget buildWindowBody(
    TimelineToolItemContext context,
    String windowText, {
    required bool isInput,
    ToolAcceptanceProjection? acceptance,
  }) {
    if (isInput) {
      return super.buildWindowBody(
        context,
        windowText,
        isInput: true,
        acceptance: acceptance,
      );
    }
    final presentation = parseTimelineLspStatus(windowText);
    return TimelineLspToolView(
      itemId: context.item.id,
      presentation: presentation,
      markdownBuilder: context.markdownBuilder,
    );
  }
}
