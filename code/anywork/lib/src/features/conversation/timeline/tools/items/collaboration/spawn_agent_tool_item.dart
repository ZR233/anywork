import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/agent_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.spawn_agent@1`.
class SpawnAgentToolItem extends StructuredTimelineToolAdapter {
  const SpawnAgentToolItem();

  static const String contractId = 'builtin.spawn_agent@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy(
    omitSuccessOutput: true,
    requiresAcceptance: true,
  );

  @override
  List<String> get targetFields => const ['taskSummary'];

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameSpawnAgent;

  @override
  String rejectionLabel(AppLocalizations l10n) =>
      l10n.timelineToolSpawnRejected;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.account_tree_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolAgentRunning,
        failed: l10n.timelineToolAgentFailed,
        succeeded: l10n.timelineToolAgentSucceeded,
      );

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    return [
      ...toolField(
        l10n,
        data,
        'taskSummary',
        l10n.timelineToolDetailTask,
        required: true,
      ),
      ...toolField(
        l10n,
        data,
        'profileId',
        l10n.timelineToolDetailProfile,
        required: true,
      ),
      ...toolField(
        l10n,
        data,
        'message',
        l10n.timelineToolDetailTaskDescription,
        required: true,
      ),
    ];
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolAgentResult(l10n, result);

  @override
  ToolAcceptanceProjection acceptanceFromResult(Object? result) =>
      switch (result) {
        {'messageAccepted': true} => const ToolAcceptanceProjection(
          ToolAcceptance.accepted,
        ),
        {'messageAccepted': false} => const ToolAcceptanceProjection(
          ToolAcceptance.rejected,
        ),
        _ => const ToolAcceptanceProjection(ToolAcceptance.pending),
      };
}
