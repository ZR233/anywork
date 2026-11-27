import 'dart:convert';
import 'dart:math' as math;

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../app/theme/studio_tokens.dart';
import '../../../../../shared/studio_badges.dart';
import '../../../../../shared/studio_code_block.dart';
import '../../state/timeline_outcome_presentation.dart';
import '../../tools/support/tool_detail_panel.dart';
import '../../tools/support/tool_detail_values.dart';
import '../../widgets/timeline_activity_clock.dart';
import '../../widgets/timeline_activity_row.dart';
import '../../widgets/timeline_outcome_card.dart';
import '../work_group_member_adapter.dart';

/// 渲染工作组内的子智能体条目，避免裸露内部 `thread-...` ID。
class AgentMemberItem extends WorkGroupMemberAdapter {
  const AgentMemberItem();

  @override
  String get id => 'work_group.agent';

  @override
  WorkGroupMemberMatcher get matcher =>
      const WorkGroupMemberMatcher.kind(WorkGroupMemberKind.agent);

  @override
  Widget build(WorkGroupMemberContext context) {
    final l10n = context.l10n;
    final buildContext = context.buildContext;
    final member = context.member as WorkGroupAgent;
    final reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(buildContext) ?? false;

    final parsed = _parseAgentPayload(member);
    final isRunning =
        member.status == 'running' ||
        member.status == 'queued' ||
        member.status == 'active' ||
        (context.isLive &&
            member.finishedAtMs == null &&
            member.status != 'completed' &&
            member.status != 'succeeded' &&
            member.status != 'failed' &&
            member.status != 'denied' &&
            member.status != 'cancelled' &&
            member.status != 'interrupted');
    final isFailed = member.status == 'failed' || member.status == 'denied';
    final isCancelled =
        member.status == 'cancelled' || member.status == 'interrupted';

    final roleBadge = parsed.role ?? parsed.displayName;
    final taskHeadline = parsed.taskSummary;
    final fallbackName = roleBadge ?? l10n.liveWorkKindAgent;

    final String plainLabel;
    if (roleBadge != null &&
        taskHeadline != null &&
        taskHeadline != roleBadge) {
      plainLabel = '$roleBadge · $taskHeadline';
    } else if (taskHeadline != null) {
      plainLabel = taskHeadline;
    } else if (isFailed) {
      plainLabel = l10n.workGroupAgentFailed(fallbackName);
    } else if (isCancelled) {
      plainLabel = l10n.workGroupAgentCancelled(fallbackName);
    } else if (isRunning) {
      plainLabel = l10n.workGroupAgentRunning(fallbackName);
    } else {
      plainLabel = l10n.workGroupAgentCompleted(fallbackName);
    }

    final labelStyle = buildContext.text.bodySmall?.copyWith(
      color: buildContext.colors.onSurfaceVariant,
      height: 1.5,
    );
    final Widget? labelWidget =
        roleBadge != null && taskHeadline != null && taskHeadline != roleBadge
        ? LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth.isFinite && constraints.maxWidth < 120) {
                return Text(
                  plainLabel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                );
              }
              final chipMaxWidth = constraints.maxWidth.isFinite
                  ? math.min(140.0, math.max(0.0, constraints.maxWidth - 68))
                  : 140.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  StudioCompactChip(
                    label: roleBadge,
                    maxWidth: chipMaxWidth,
                    tone: isFailed ? StudioTone.error : StudioTone.neutral,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      taskHeadline,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                  ),
                ],
              );
            },
          )
        : null;

    final detailRows = <ToolDetailValue>[
      if (parsed.role != null)
        ToolDetailText(l10n.workGroupAgentRole, parsed.role!),
      if (parsed.displayName != null && parsed.displayName != parsed.role)
        ToolDetailText(l10n.timelineToolDetailAgent, parsed.displayName!),
      if (parsed.taskSummary != null)
        ToolDetailText(l10n.workGroupAgentTask, parsed.taskSummary!),
      ToolDetailText(
        l10n.workGroupAgentStatus,
        localizedOutcomeStatus(buildContext, member.status),
      ),
      if (member.agentId.trim().isNotEmpty &&
          member.agentId.trim() != parsed.displayName)
        ToolDetailText(
          l10n.timelineToolDetailTarget,
          member.agentId.trim(),
          code: true,
        ),
    ];

    final outcomeNotice = TimelineOutcomeNotice(
      summary: parsed.outcomeSummary,
      isIssue: isFailed,
    );
    final hasNotice =
        !parsed.outcomeSummary.isTerminalNormal &&
        ((parsed.outcomeSummary.primaryText?.isNotEmpty ?? false) ||
            parsed.outcomeSummary.failure != null ||
            parsed.outcomeSummary.cancellation != null);
    final hasRawJson =
        parsed.formattedJson != null && parsed.formattedJson != '{}';

    final expandedChildren = <Widget>[
      if (hasNotice) outcomeNotice,
      if (detailRows.isNotEmpty)
        TimelineToolDetailPanel(
          children: [TimelineToolSemanticBody(values: detailRows)],
        ),
      if (hasRawJson)
        TimelineActivityTileTheme(
          child: TimelineActivityDisclosure(
            titleBuilder: (ctx, expanded) => TimelineActivityRow(
              icon: Icons.data_object_outlined,
              label: l10n.timelineOutcomeRawRecord,
              expanded: expanded,
            ),
            children: [
              StudioCodeBlock(
                text: parsed.formattedJson!,
                horizontalScroll: false,
              ),
            ],
          ),
        ),
    ];
    final expandable = expandedChildren.isNotEmpty;

    return TimelineActivityClock(
      startedAtMillis: member.startedAtMs,
      finishedAtMillis: member.finishedAtMs,
      running: isRunning,
      now: context.now,
      builder: (ctx, seconds) {
        final duration = seconds == null
            ? null
            : activityDurationLabel(
                ctx,
                seconds,
                kind: ActivityDurationKind.elapsed,
              );
        final semantics = duration == null
            ? plainLabel
            : '$plainLabel，$duration';

        Widget row(BuildContext rowCtx, bool expanded) => TimelineActivityRow(
          icon: isCancelled
              ? Icons.stop_circle_outlined
              : Icons.smart_toy_outlined,
          isIssue: isFailed,
          active: isRunning && context.isLive && !reducedMotion,
          indicatorStyle: TimelineActivityIndicatorStyle.circularProgress,
          label: plainLabel,
          labelWidget: labelWidget,
          meta: duration,
          semanticsLabel: semantics,
          expanded: expanded,
          expandable: expandable,
        );

        if (!expandable) return row(ctx, false);
        return TimelineActivityTileTheme(
          child: TimelineActivityDisclosure(
            initiallyExpanded: context.initiallyExpanded,
            onExpansionChanged: context.onExpansionChanged,
            titleBuilder: row,
            children: expandedChildren,
          ),
        );
      },
    );
  }
}

class _ParsedAgentPayload {
  const _ParsedAgentPayload({
    this.role,
    this.displayName,
    this.taskSummary,
    this.outcomeSummary = const TimelineOutcomeSummary(),
    this.formattedJson,
  });

  final String? role;
  final String? displayName;
  final String? taskSummary;
  final TimelineOutcomeSummary outcomeSummary;
  final String? formattedJson;
}

_ParsedAgentPayload _parseAgentPayload(WorkGroupAgent member) {
  Map<String, dynamic>? root;
  String? formattedJson;
  final raw = member.payloadJson.trim();
  if (raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        root = decoded;
        formattedJson = const JsonEncoder.withIndent('  ').convert(decoded);
      }
    } on FormatException {
      // Malformed payload falls back to structured member fields.
    }
  }

  final data = root?['data'] is Map<String, dynamic>
      ? root!['data'] as Map<String, dynamic>
      : root;
  final identity = data?['identity'] is Map<String, dynamic>
      ? data!['identity'] as Map<String, dynamic>
      : null;
  final outcome = data?['outcome'];
  final outcomeData =
      outcome is Map<String, dynamic> && outcome['data'] is Map<String, dynamic>
      ? outcome['data'] as Map<String, dynamic>
      : null;

  final role =
      _readableLabel(identity?['role']) ?? _readableLabel(data?['role']);
  final displayName =
      _readableLabel(identity?['name']) ??
      _readableLabel(identity?['displayName']) ??
      _readableLabel(data?['name']) ??
      _readableLabel(member.name);
  final taskSummary =
      _readableLabel(identity?['taskSummary']) ??
      _readableLabel(identity?['task_summary']) ??
      _readableLabel(identity?['task']) ??
      _readableLabel(data?['taskSummary']) ??
      _readableLabel(data?['task_summary']) ??
      _readableLabel(data?['summary']) ??
      _readableLabel(outcomeData?['summary']) ??
      _readableLabel(outcomeData?['reason']) ??
      _readableLabel(member.summary);

  return _ParsedAgentPayload(
    role: role,
    displayName: displayName,
    taskSummary: taskSummary,
    outcomeSummary: parseTimelineOutcome(outcome),
    formattedJson: formattedJson,
  );
}

String? _readableLabel(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'Agent' || _looksLikeThreadId(trimmed)) {
    return null;
  }
  return trimmed;
}

bool _looksLikeThreadId(String value) =>
    RegExp(r'^thread-[a-zA-Z0-9_-]{6,}$').hasMatch(value);
