import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../shared/typed_json.dart';
import '../../../state/tool_presentation.dart';
import '../../support/agent_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/task_state_values_support.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.evaluate_agent@1` (and uncontracted live
/// `evaluate_agent` atoms).
class EvaluateAgentToolItem extends StructuredTimelineToolAdapter {
  const EvaluateAgentToolItem();

  static const String contractId = 'builtin.evaluate_agent@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName('evaluate_agent', requireEmptyContract: true),
  ]);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameEvaluateAgent;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.fact_check_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolEvaluateAgentRunning,
        failed: l10n.timelineToolEvaluateAgentFailed,
        succeeded: l10n.timelineToolEvaluateAgentSucceeded,
        backgroundStarted: l10n.timelineToolStateBackgroundStarted,
        backgrounded: l10n.timelineToolStateBackgrounded,
      );

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) {
    final targetLabel = toolAgentRowTarget(item).label;
    final arguments = decodeJsonObject(item.arguments);
    final output = decodeJsonObject(item.output);
    final evaluation = jsonObject(output['evaluation']);
    final rawComment =
        jsonStringValue(arguments['comment']) ??
        jsonStringValue(evaluation['comment']) ??
        jsonStringValue(output['summary']);
    final excerpt = toolCompactExcerpt(rawComment);
    final label = switch ((targetLabel, excerpt)) {
      (final who?, final note?) => '$who · $note',
      (final who?, null) => who,
      (null, final note?) => note,
      (null, null) => null,
    };
    final fullComment = toolFirstLine(rawComment);
    final tooltip = switch ((targetLabel, fullComment)) {
      (final who?, final note?) => '$who · $note',
      (final who?, null) => who,
      (null, final note?) => note,
      (null, null) => null,
    };
    return (label: label, tooltip: tooltip);
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    final rating = _formatRating(data);
    final outcome = jsonStringValue(data['outcome']);
    return [
      ...toolField(l10n, data, 'target', l10n.timelineToolDetailTarget),
      if (outcome != null)
        ToolDetailText(
          l10n.timelineToolDetailStatus,
          _outcomeLabel(l10n, outcome),
        ),
      if (rating != null) ToolDetailText(l10n.timelineToolDetailRating, rating),
      ...toolField(l10n, data, 'comment', l10n.timelineToolDetailComment),
    ];
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) {
    if (result is! Map<String, dynamic>) {
      return toolAgentResult(l10n, result);
    }
    final evaluation = jsonObject(result['evaluation']);
    final source = evaluation.isNotEmpty
        ? Map<String, dynamic>.from({...result, ...evaluation})
        : result;
    final values = <ToolDetailValue>[];
    final target =
        jsonStringValue(source['target']) ?? jsonStringValue(source['agentId']);
    if (target != null) {
      values.add(ToolDetailText(l10n.timelineToolDetailTarget, target));
    }
    final role =
        jsonStringValue(source['role']) ?? jsonStringValue(source['profileId']);
    if (role != null) {
      values.add(ToolDetailText(l10n.timelineToolDetailRole, role));
    }
    final outcome = jsonStringValue(source['outcome']);
    if (outcome != null) {
      values.add(
        ToolDetailText(
          l10n.timelineToolDetailStatus,
          _outcomeLabel(l10n, outcome),
        ),
      );
    }
    final rating = _formatRating(source);
    if (rating != null) {
      values.add(ToolDetailText(l10n.timelineToolDetailRating, rating));
    }
    final comment = jsonStringValue(source['comment']);
    if (comment != null) {
      values.add(ToolDetailText(l10n.timelineToolDetailComment, comment));
    }
    values.addAll(
      toolResultFields(l10n, toolTaskStateValues(l10n, source), {
        'status': l10n.timelineToolDetailStatus,
        'state': l10n.timelineToolDetailStatus,
        'summary': l10n.timelineToolDetailSummary,
        ...toolDiagnosticFields(l10n),
      }, unavailableWhenEmpty: false),
    );
    if (values.isEmpty && result.isNotEmpty) {
      return [ToolDetailUnavailable(l10n.timelineToolNoSemanticContent)];
    }
    return values;
  }

  static String? _formatRating(Map<String, Object?> data) {
    final direct = data['rating'];
    if (direct != null) {
      final text = jsonStringValue(direct);
      if (text != null) return text;
    }
    final quality = data['quality'];
    final instruction = data['instructionFollowing'];
    if (quality is num && instruction is num) {
      return '$quality/5 · $instruction/5';
    }
    if (quality is num) return '$quality/5';
    if (instruction is num) return '$instruction/5';
    return null;
  }

  static String _outcomeLabel(AppLocalizations l10n, String outcome) =>
      switch (outcome) {
        'passed' => l10n.timelineToolStateSucceeded,
        'failed' => l10n.timelineToolStateFailed,
        'notRated' => l10n.timelineToolDetailNone,
        _ => outcome,
      };
}
