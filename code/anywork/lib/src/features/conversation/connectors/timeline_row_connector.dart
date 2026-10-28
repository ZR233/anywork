import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart' show AttachmentModality;
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/content/studio_code_block.dart';
import '../presentation/artifact_links.dart';
import '../presentation/timeline_labels.dart';
import '../state/plan_confirmation_ownership.dart';
import '../timeline/display_binding.dart';
import '../timeline/presentation_item.dart';
import '../views/timeline_activity_section.dart';
import '../views/timeline_group_view.dart';
import '../views/timeline_image_card_view.dart';
import '../views/timeline_row_frame.dart';
import '../views/timeline_turn_outcome_view.dart';
import '../widgets/activity_row.dart';
import '../widgets/conversation_markdown.dart';
import '../widgets/plan_receipt.dart';
import '../widgets/user_input_receipt.dart';
import '../widgets/wait_panel.dart';
import 'markdown_connector.dart';
import 'timeline_attachment_connector.dart';
import 'timeline_detail_connector.dart';
import 'timeline_image_card_media_connector.dart';

/// Smart only: reads the existing group/member listenables in stock Message
/// metadata. It creates neither a second body collection nor a query owner.
class TimelineRowConnector extends StatelessWidget {
  const TimelineRowConnector({
    required this.message,
    required this.display,
    super.key,
  });
  final Message message;
  final TimelineDisplayBinding display;

  @override
  Widget build(BuildContext context) {
    final item = timelinePresentationOf(message);
    if (item == null) return const SizedBox.shrink();
    if (item is TimelineSingleItem || item is TimelineImageCardGroup) {
      return ListenableBuilder(
        listenable: item,
        builder: (context, _) {
          if (item.length == 0 || display.retired) {
            return const SizedBox.shrink();
          }
          return _TimelineMemberConnector(
            display: display,
            group: item,
            memberId: item.memberIds.first,
            imageCard: item is TimelineImageCardGroup,
          );
        },
      );
    }
    return ListenableBuilder(
      listenable: item,
      child: _TimelineGroupContentsConnector(display: display, group: item),
      builder: (context, contents) {
        if (item.length == 0 || display.retired) return const SizedBox.shrink();
        return TimelineGroupView(
          id: item.id,
          label: timelineGroupLabel(context, item),
          icon: timelineGroupIcon(item),
          expanded: item.expanded,
          onExpanded: item.setExpanded,
          active: item.activeCount > 0,
          isIssue: item.issueCount > 0,
          activityIndent: item is TimelineActivityGroup,
          contents: contents!,
        );
      },
    );
  }
}

class _TimelineGroupContentsConnector extends StatelessWidget {
  const _TimelineGroupContentsConnector({
    required this.display,
    required this.group,
  });
  final TimelineDisplayBinding display;
  final TimelinePresentationItem group;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: group.structure,
    builder: (context, version, _) => TimelineGroupMembersView(
      memberCount: group.visibleMemberIds.length,
      memberBuilder: (context, index) => _TimelineMemberConnector(
        key: ValueKey(group.visibleMemberIds[index]),
        display: display,
        group: group,
        memberId: group.visibleMemberIds[index],
        inGroup: true,
        embeddedThinking:
            group is TimelineActivityGroup &&
            group.thinkingCount == 1 &&
            group.toolCount == 0 &&
            group.skillCount == 0 &&
            group.visibleMemberIds.length == 1,
      ),
    ),
  );
}

class _TimelineMemberConnector extends StatelessWidget {
  const _TimelineMemberConnector({
    required this.display,
    required this.group,
    required this.memberId,
    this.imageCard = false,
    this.inGroup = false,
    this.embeddedThinking = false,
    super.key,
  });
  final TimelineDisplayBinding display;
  final TimelinePresentationItem group;
  final String memberId;
  final bool imageCard;
  final bool inGroup;
  final bool embeddedThinking;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TimelineMessagePayload>(
        valueListenable: group.member(memberId),
        builder: (context, payload, _) {
          final pairedId = group.pairedToolId(memberId);
          if (pairedId == null) return _build(context, payload, null);
          return ValueListenableBuilder<TimelineMessagePayload>(
            valueListenable: group.member(pairedId),
            builder: (context, paired, _) => _build(context, payload, paired),
          );
        },
      );

  Widget _build(
    BuildContext context,
    TimelineMessagePayload payload,
    TimelineMessagePayload? paired,
  ) {
    final item = payload.item;
    if (!timelinePayloadIsVisible(payload)) return const SizedBox.shrink();
    final prompt =
        item.kind == ThreadItemKind.userMessage ||
        item.kind == ThreadItemKind.parentAgentMessage;
    final content = _content(context, payload, paired);
    if (content == null) return const SizedBox.shrink();
    return TimelineRowFrame(
      id: item.id,
      prompt: prompt,
      parentAgent: item.kind == ThreadItemKind.parentAgentMessage,
      accepted: prompt && item.turnId.isEmpty,
      rolledBack:
          item.contextDisposition == ThreadContextDisposition.rolledBack,
      compact: !prompt && item.state is! ThreadTextItemStateView,
      inGroup: inGroup,
      child: content,
    );
  }

  Widget? _content(
    BuildContext context,
    TimelineMessagePayload payload,
    TimelineMessagePayload? paired,
  ) {
    final item = payload.item;
    final state = item.state;
    final details = _details(context, payload);
    switch (state) {
      case ThreadTextItemStateView(
        :final channel,
        :final text,
        :final attachments,
      ):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MarkdownConnector(
              id: item.id,
              text: text,
              surface:
                  channel == ThreadTextChannel.user ||
                      channel == ThreadTextChannel.parentAgent
                  ? MarkdownSurface.user
                  : payloadHasIssue(payload)
                  ? MarkdownSurface.error
                  : MarkdownSurface.assistant,
            ),
            ..._attachments(item.id, attachments),
            ?details,
          ],
        );
      case ThreadThinkingItemStateView(:final summary, :final content):
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (summary.any((chunk) => chunk.trim().isNotEmpty))
              Text(context.l10n.timelineReasoningSummary),
            for (final (index, chunk) in summary.indexed)
              MarkdownConnector(
                id: '${item.id}:summary:$index',
                text: chunk,
                surface: MarkdownSurface.reasoning,
              ),
            if (content.any((chunk) => chunk.trim().isNotEmpty))
              Text(context.l10n.timelineReasoningContent),
            for (final (index, chunk) in content.indexed)
              MarkdownConnector(
                id: '${item.id}:content:$index',
                text: chunk,
                surface: MarkdownSurface.reasoning,
              ),
            ?details,
          ],
        );
        return embeddedThinking
            ? body
            : _section(
                payload,
                label: timelineThinkingLabel(context, [payload]),
                icon: Icons.psychology_alt_outlined,
                child: body,
              );
      case ThreadRawItemStateView(
        :final notice,
        :final payloads,
        :final origin,
      ):
        if (origin == ThreadRawItemOrigin.runtimeControl) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TimelineActivityRow(
              key: ValueKey('runtime-notice-${item.id}'),
              icon: Icons.info_outline,
              label: context.l10n.timelineRuntimeNotice,
              tooltip: context.l10n.timelineRuntimeNoticeDetail,
              expandable: false,
            ),
          );
        }
        return _section(
          payload,
          label: context.l10n.timelineRawRecord,
          icon: Icons.history,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(notice),
              for (final raw in payloads)
                StudioCodeBlock(
                  text: raw.content,
                  language: '${raw.format} · v${raw.version}',
                  maxHeight: 280,
                ),
              ?details,
            ],
          ),
        );
      case ThreadToolItemStateView(:final userInput, :final lifecycle):
        final history = userInput ?? item.tool?.userInput;
        if (history != null) {
          final receipt = ownsPlanConfirmation(item.tool?.name)
              ? history.planReceipt
              : null;
          if (receipt != null) {
            if (!receipt.isResolved) return null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PlanConfirmationReceipt(
                  itemId: item.id,
                  receipt: receipt,
                  expanded: group.memberExpanded(memberId),
                  onExpanded: _expanded,
                ),
                ?details,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UserInputReceipt(
                itemId: item.id,
                history: history,
                expanded: group.memberExpanded(memberId),
                onExpanded: _expanded,
              ),
              ?details,
            ],
          );
        }
        if (imageCard) {
          final tool = item.tool;
          final attachment = tool?.attachments
              .where(
                (attachment) => attachment.modality == AttachmentModality.image,
              )
              .firstOrNull;
          final callId = tool?.callId ?? tool?.toolCallId ?? item.id;
          final entryId = attachment == null
              ? null
              : StudioDriverKeys.toolImageEntryId(callId, attachment.id);
          return TimelineImageCardView(
            key: entryId == null ? null : StudioDriverKeys.imageCard(entryId),
            statusLabel: context.toolStatusLabel(lifecycle.status),
            isIssue: payloadHasIssue(payload),
            statusIcon: timelineImageStatusIcon(lifecycle),
            media: attachment == null || entryId == null
                ? null
                : TimelineImageCardMediaConnector(
                    key: ValueKey((
                      display,
                      display.generation,
                      callId,
                      attachment.id,
                    )),
                    display: display,
                    attachment: attachment,
                    callId: callId,
                    entryId: entryId,
                  ),
            diagnostics: _section(
              payload,
              label: timelineToolLabel(context, item),
              icon: Icons.image_outlined,
              child: _toolBody(context, payload, includeAttachments: false),
            ),
          );
        }
        final body = _toolBody(context, payload);
        if (item.tool?.wait case final wait?) {
          return TimelineWaitPanel(
            presentation: wait,
            identity: item.id,
            expanded: group.memberExpanded(memberId),
            onExpanded: _expanded,
            diagnostics: body,
          );
        }
        final imageRead = item.tool?.name == 'view_image';
        return _section(
          payload,
          label: timelineToolLabel(context, item),
          icon: imageRead
              ? timelineImageStatusIcon(lifecycle)
              : item.tool?.name == 'web_search'
              ? Icons.travel_explore
              : Icons.build_outlined,
          // Image status retains its broken/stop icon rather than substituting
          // the activity row's generic error icon. Counts still use the payload.
          isIssue: imageRead ? false : null,
          iconColor: imageRead
              ? payloadHasIssue(payload)
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant
              : null,
          child: body,
        );
      case ThreadAgentItemStateView(:final identity, :final lifecycle):
        final detail = switch (lifecycle) {
          QueuedThreadAgentView() || RunningThreadAgentView() => identity.task,
          SucceededThreadAgentView(:final summary) => summary,
          DeniedThreadAgentView(:final reason) ||
          CancelledThreadAgentView(:final reason) => reason,
          FailedThreadAgentView(:final error) => error,
        };
        return _section(
          payload,
          label:
              '${context.l10n.timelineAgentSubagent} · ${identity.path} · ${context.toolStatusLabel(item.status)}',
          icon: Icons.account_tree_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text(identity.task), Text(detail), ?details],
          ),
        );
      case ThreadSkillItemStateView(
        :final name,
        :final source,
        :final resourceBase,
        :final cause,
      ):
        return _section(
          payload,
          label: cause.kind == SkillActivationCauseKind.tool
              ? context.l10n.timelineSkillAgentActivated(name)
              : context.l10n.timelineSkillUserActivated(name),
          labelKey: StudioDriverKeys.timelineSkillActivation(item.id),
          icon: Icons.extension_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(source),
              Text(resourceBase.value),
              if (paired != null) _toolBody(context, paired),
              ?details,
            ],
          ),
        );
      case ThreadContextCompactionItemStateView(
        :final beforeTokens,
        :final afterTokens,
      ):
        return TimelineActivityRow(
          key: StudioDriverKeys.timelineBlock(item.id),
          icon: Icons.compress_outlined,
          label: context.l10n.timelineContextCompacted,
          expandable: details != null,
          tooltip: beforeTokens != null && afterTokens != null
              ? context.l10n.timelineCompactionDetail(beforeTokens, afterTokens)
              : null,
        );
      case ThreadTurnItemStateView(:final state):
        if (!item.isTerminal) return null;
        switch (state) {
          case CancelledTurn(:final cause):
            return TimelineTurnOutcomeView(
              itemId: item.id,
              kind: TimelineTurnOutcomeKind.stopped,
              label: timelineTurnCancellationLabel(context, cause),
            );
          case FailedTurn() || BudgetLimitedTurn():
            final reason = item.error;
            if (reason == null || reason.isEmpty) return null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TimelineTurnOutcomeView(
                  itemId: item.id,
                  kind: TimelineTurnOutcomeKind.failed,
                  label: reason,
                ),
                ?details,
              ],
            );
          case QueuedTurn() || RunningTurn() || CompletedTurn():
            return null;
        }
      case ThreadInferenceItemStateView() || ThreadFileItemStateView():
        return null;
    }
  }

  void _expanded(bool value) => group.setMemberExpanded(memberId, value);

  Widget _section(
    TimelineMessagePayload payload, {
    required String label,
    required IconData icon,
    required Widget child,
    Key? labelKey,
    bool? isIssue,
    Color? iconColor,
  }) => TimelineActivitySection(
    key: ValueKey(('timeline-member-section', memberId)),
    label: label,
    icon: icon,
    iconColor: iconColor,
    labelKey: labelKey ?? StudioDriverKeys.timelineActivitySummary(payload.id),
    active: !payload.item.isTerminal,
    isIssue: isIssue ?? payloadHasIssue(payload),
    expanded: group.memberExpanded(memberId),
    onExpanded: _expanded,
    child: child,
  );

  Widget _toolBody(
    BuildContext context,
    TimelineMessagePayload payload, {
    bool includeAttachments = true,
  }) {
    final item = payload.item;
    final tool = item.tool;
    final state = item.state;
    if (tool == null || state is! ThreadToolItemStateView) {
      return const SizedBox.shrink();
    }
    final diagnostic = switch (state.lifecycle) {
      CancelledThreadToolView(:final reason) ||
      InterruptedThreadToolView(:final reason) => reason,
      _ => item.error,
    };
    final diagnosticColor = timelineToolDiagnosticColor(
      context,
      state.lifecycle,
    );
    final hidePayload =
        item.status == 'succeeded' &&
        const {'workflow_transition', 'workflow_restart'}.contains(tool.name);
    final links = _artifactLinks(context, tool.outputArtifacts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tool.workingDirectory != null) Text(tool.workingDirectory!),
        if (tool.taskId != null) Text(tool.taskId!),
        if (tool.exitCode != null)
          Text(context.l10n.timelineToolExitCode(tool.exitCode!)),
        if (tool.timedOut) Text(context.l10n.timelineToolTimedOut),
        if (tool.denialReason != null)
          Text(
            tool.denialReason!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: diagnosticColor),
          ),
        if (tool.name == 'exec' &&
            item.completedAt != null &&
            item.completedAt! >= item.createdAt)
          Text(
            context.l10n.timelineToolElapsedSeconds(
              item.completedAt! - item.createdAt,
            ),
          ),
        if (!hidePayload && tool.arguments.isNotEmpty)
          StudioCodeBlock(
            text: tool.arguments,
            language: context.l10n.timelineToolArguments,
            maxHeight: 200,
          ),
        if (!hidePayload && tool.result?.isNotEmpty == true)
          StudioCodeBlock(
            text: tool.result!,
            language: context.l10n.timelineToolOutput,
            maxHeight: 280,
          ),
        if (diagnostic != null &&
            diagnostic.isNotEmpty &&
            diagnostic != tool.result)
          Text(
            diagnostic,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: diagnosticColor),
          ),
        if (includeAttachments) ..._attachments(item.id, tool.attachments),
        ?links,
        ?_details(context, payload),
      ],
    );
  }

  Widget? _artifactLinks(
    BuildContext context,
    List<OpaqueArtifactJson> artifacts,
  ) {
    if (artifacts.isEmpty) return null;
    try {
      final links = extractArtifactLinks(artifacts);
      return links.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.l10n.timelineWebSearchResults),
                for (final link in links) SelectableText(link),
              ],
            );
    } on ArtifactLinksDecodeFailure {
      return Text(
        'Artifact links could not be decoded',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
  }

  Iterable<Widget> _attachments(
    String callId,
    List<ThreadAttachmentView> attachments,
  ) sync* {
    final occurrences = <String, int>{};
    for (final attachment in attachments) {
      final base = StudioDriverKeys.toolImageEntryId(callId, attachment.id);
      final occurrence = occurrences.update(
        base,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      final id = occurrence == 0 ? base : '$base#$occurrence';
      yield TimelineAttachmentConnector(
        key: ValueKey((display.generation, id)),
        display: display,
        attachment: attachment,
        entryId: id,
      );
    }
  }

  Widget? _details(BuildContext context, TimelineMessagePayload payload) {
    final truncated = payload.details.where(
      (detail) => detail.truncated && _readableField(payload, detail.field),
    );
    if (truncated.isEmpty) {
      return payload.hasOmittedBody
          ? Text(
              context.l10n.timelineDetailUnavailable,
              key: StudioDriverKeys.timelineItemBodyNotice(payload.id),
            )
          : null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final detail in truncated)
          TextButton.icon(
            key: ValueKey(('timeline-detail', payload.id, detail.field)),
            onPressed: display.retired
                ? null
                : () => openTimelineDetail(
                    context,
                    display: display,
                    itemId: payload.id,
                    reference: detail,
                  ).ignore(),
            icon: const Icon(Icons.article_outlined),
            label: Text(
              '${context.l10n.timelineItemBodyLoad} · ${_fieldLabel(context, detail.field)}',
            ),
          ),
      ],
    );
  }

  bool _readableField(
    TimelineMessagePayload payload,
    ThreadContentFieldView field,
  ) {
    // The typed receipt is the only answer boundary. Do not offer a raw tool
    // result/arguments back door that could reveal a secret or unknown answer.
    if (payload.item.tool?.userInput != null &&
        (field is ThreadToolArgumentsFieldView ||
            field is ThreadToolResultFieldView ||
            field is ThreadToolOutputArtifactsFieldView)) {
      return false;
    }
    if (field case ThreadToolUserInputFieldView(
      :final questionIndex,
      part: ThreadUserInputAnswerFieldPartView(),
    )) {
      final questions = payload.item.tool?.userInput?.questions;
      return questions != null &&
          questionIndex >= 0 &&
          questionIndex < questions.length &&
          !questions[questionIndex].isSecret;
    }
    return true;
  }

  String _fieldLabel(BuildContext context, ThreadContentFieldView field) =>
      switch (field) {
        ThreadTextFieldView() => context.l10n.timelineReasoningContent,
        ThreadThinkingSummaryFieldView(:final chunkIndex) =>
          '${context.l10n.timelineReasoningSummary} ${chunkIndex + 1}',
        ThreadThinkingContentFieldView(:final chunkIndex) =>
          '${context.l10n.timelineReasoningContent} ${chunkIndex + 1}',
        ThreadToolArgumentsFieldView() => context.l10n.timelineToolArguments,
        ThreadToolResultFieldView() ||
        ThreadToolOutputArtifactsFieldView() => context.l10n.timelineToolOutput,
        ThreadRawPayloadFieldView(:final payloadIndex) =>
          '${context.l10n.timelineRawRecord} ${payloadIndex + 1}',
        ThreadToolUserInputFieldView(:final questionIndex) =>
          '${context.l10n.timelineUserInputAwaiting} ${questionIndex + 1}',
      };
}
