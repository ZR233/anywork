import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../connectors/timeline_feed_body_connector.dart';
import '../../widgets/content_layout_witness.dart';
import '../../widgets/timeline_plain_text.dart';
import '../../widgets/timeline_reasoning_view.dart';
import '../work_group_member_adapter.dart';

/// 渲染工作组内的思考条目，直接复用 [TimelineReasoningView]。
class ReasoningMemberItem extends WorkGroupMemberAdapter {
  const ReasoningMemberItem();

  @override
  String get id => 'work_group.reasoning';

  @override
  WorkGroupMemberMatcher get matcher =>
      const WorkGroupMemberMatcher.kind(WorkGroupMemberKind.reasoning);

  @override
  Widget build(WorkGroupMemberContext context) {
    final member = context.member as WorkGroupReasoning;
    final trimmedSummary = member.summary.trim();
    final hasSummary = trimmedSummary.isNotEmpty;
    final running =
        member.outcome == 'running' ||
        (context.isLive &&
            member.finishedAtMs == null &&
            member.outcome != 'completed' &&
            member.outcome != 'failed' &&
            member.outcome != 'cancelled');

    final body = _buildBody(context, member);

    return TimelineReasoningView(
      summary: hasSummary ? trimmedSummary : null,
      body: body,
      startedAtMs: member.startedAtMs,
      finishedAtMs: member.finishedAtMs,
      now: context.now,
      running: running,
      outcome: member.outcome,
      initiallyExpanded: context.initiallyExpanded,
      onExpansionChanged: context.onExpansionChanged,
    );
  }

  Widget? _buildBody(
    WorkGroupMemberContext context,
    WorkGroupReasoning member,
  ) {
    final bodyId = '${member.id}:body';
    Widget renderText(String text) =>
        context.bodyBuilder?.call(bodyId, text) ??
        TimelinePlainText(id: bodyId, text: text);

    Widget witness(String text, Widget child) {
      final clock = context.monotonicMicros;
      final onLayout = context.onContentLayout;
      if (text.trim().isEmpty || clock == null || onLayout == null) {
        return child;
      }
      return ContentLayoutWitness(
        itemId: member.id,
        monotonicMicros: clock,
        onContentLayout: onLayout,
        isDisplayActive: context.isDisplayActive,
        child: child,
      );
    }

    final ref = member.bodyRef;
    if (ref != null) {
      final inline = ref.inlineText;
      if (inline != null) {
        if (inline.trim().isEmpty) return null;
        return witness(inline, renderText(inline));
      }
      return TimelineFeedBodyConnector(
        itemId: member.id,
        reference: ref,
        label: context.l10n.timelineReasoningContent,
        disclosed: true,
        showCopy: false,
        bodyBuilder: renderText,
        witness: witness,
      );
    }

    if (member.text.trim().isNotEmpty) {
      return witness(member.text, renderText(member.text));
    }
    return null;
  }
}
