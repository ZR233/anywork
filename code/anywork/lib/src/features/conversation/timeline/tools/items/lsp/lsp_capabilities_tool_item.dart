import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/lsp_presentation.dart';
import '../../../state/tool_data_artifact.dart';
import '../../../state/tool_presentation.dart';
import '../../../widgets/timeline_lsp_tool_view.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.lsp_capabilities@1`.
class LspCapabilitiesToolItem extends StructuredTimelineToolAdapter {
  const LspCapabilitiesToolItem();

  static const String contractId = 'builtin.lsp_capabilities@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy =>
      const TimelineToolBodyPolicy(readsStructuredOutput: true);

  @override
  bool get showsDeclaredPrefixInput => false;

  @override
  List<String> get targetFields => const ['languageId'];

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineLspCapabilitiesTitle;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.code);

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

  @override
  Widget? buildToolDataBody(
    TimelineToolItemContext context, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final data = context.controller.toolData;
    if (data is! ToolDataArtifactPresent) {
      return super.buildToolDataBody(context, acceptance: acceptance);
    }
    final presentation = parseTimelineLspCapabilities(jsonEncode(data.value));
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
    return super.buildWindowBody(
      context,
      windowText,
      isInput: false,
      acceptance: acceptance,
    );
  }
}
