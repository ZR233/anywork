import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/agent_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.spawn_agent@1` (and uncontracted live `spawn_agent`
/// atoms).
class SpawnAgentToolItem extends StructuredTimelineToolAdapter {
  const SpawnAgentToolItem();

  static const String contractId = 'builtin.spawn_agent@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName('spawn_agent', requireEmptyContract: true),
  ]);

  @override
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy(
    omitSuccessOutput: true,
    requiresAcceptance: true,
  );

  @override
  List<String> get targetFields => const [
    'taskSummary',
    'role',
    'profileId',
    'name',
    'agentName',
  ];

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
        backgroundStarted: l10n.timelineToolStateBackgroundStarted,
        backgrounded: l10n.timelineToolStateBackgrounded,
      );

  @override
  String? rowTarget(AppLocalizations l10n, TimelineToolPresentation item) {
    final direct = super.rowTarget(l10n, item);
    if (direct != null && !isRawThreadIdentifier(direct)) {
      return direct;
    }
    return toolAgentRowTarget(
      item,
      readableKeys: targetFields,
      idKeys: const ['agentId', 'target', 'threadId'],
    );
  }

  @override
  String rowLabel(
    AppLocalizations l10n,
    TimelineToolPresentation item,
    String? target, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final resolved = acceptance ?? decodeAcceptance(item.output);
    if (resolved.state == ToolAcceptance.rejected) {
      return [rejectionLabel(l10n), ?target].join(' ');
    }
    final isTerminalSuccess =
        item.statusString == 'succeeded' || item.statusString == 'completed';
    if (resolved.state == ToolAcceptance.pending &&
        isTerminalSuccess &&
        item.output.trim().isNotEmpty) {
      return [l10n.timelineToolResultPending, ?target].join(' ');
    }
    final action = verb(l10n, item);
    if (action == null) {
      return [
        statusTitle(l10n, item),
        if (target != null && target.isNotEmpty) target,
      ].join(' · ');
    }
    return target == null || target.isEmpty ? action : '$action $target';
  }

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
