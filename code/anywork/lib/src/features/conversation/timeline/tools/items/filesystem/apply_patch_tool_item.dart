import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../../widgets/timeline_patch_diff_view.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_panel.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.apply_patch@1` rendering structured multi-file diff hunks.
class ApplyPatchToolItem extends StructuredTimelineToolAdapter {
  const ApplyPatchToolItem();

  static const String contractId = 'builtin.apply_patch@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy(
    requiresJsonObjectArguments: false,
    readsArgumentsWindow: true,
    omitSuccessOutput: true,
  );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameApplyPatch;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.edit_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolEditRunning,
        failed: l10n.timelineToolEditFailed,
        succeeded: l10n.timelineToolEditSucceeded,
      );

  @override
  Widget? buildInlineBody(
    TimelineToolItemContext context, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final item = context.item;
    final patchWidget = timelineApplyPatchBody(item.arguments);
    final outputValues =
        readsOutput(
          item.statusString,
          output: item.output,
          toolData: context.controller.toolData,
        )
        ? decodeOutputData(
            context.l10n,
            item.output,
            context.controller.toolData,
          )
        : const <ToolDetailValue>[];
    if (patchWidget == null && outputValues.isEmpty) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?patchWidget,
        if (outputValues.isNotEmpty)
          TimelineToolSemanticBody(values: outputValues),
      ],
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
      return timelineApplyPatchWindowBody(windowText);
    }
    return super.buildWindowBody(
      context,
      windowText,
      isInput: false,
      acceptance: acceptance,
    );
  }
}
