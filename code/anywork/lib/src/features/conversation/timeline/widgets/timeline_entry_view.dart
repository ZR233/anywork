import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../domain/models/plan_confirmation_ownership.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/studio_driver_key_values.dart';
import '../state/timeline_entry.dart';
import 'timeline_activity_row.dart';
import 'timeline_wait_blocks.dart';

typedef TimelineDetailAction = void Function(
  String itemId,
  ThreadContentFieldView field,
);
typedef TimelineBodyBuilder = Widget Function(
  ConversationItem item,
  String text,
);

class TimelineEntryView extends StatelessWidget {
  const TimelineEntryView({
    super.key,
    required this.entry,
    required this.bodyBuilder,
    required this.onDetail,
    required this.mediaBuilder,
    this.pendingPlanInteractionId,
  });
  final TimelineEntry entry;
  final TimelineBodyBuilder bodyBuilder;
  final TimelineDetailAction onDetail;
  final Widget Function(ConversationItem) mediaBuilder;
  final String? pendingPlanInteractionId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: entry,
    builder: (context, _) {
      if (entry.length == 0 || entry.kind == TimelineEntryKind.hidden) {
        return const SizedBox.shrink();
      }
      if (entry.kind == TimelineEntryKind.single) {
        return _observedMember(entry.first.id);
      }
      if (entry.visibleLength == 1) {
        final row = entry.member(entry.visibleIdAt(0));
        if (row.item.descriptor is ConversationThinkingDescriptor) {
          return ListenableBuilder(
            listenable: row,
            builder: (context, _) => _group(context),
          );
        }
      }
      return _group(context);
    },
  );

  Widget _group(BuildContext context) {
    final soleItem = entry.visibleLength == 1
        ? entry.item(entry.visibleIdAt(0))
        : null;
    final groupExpandable =
        soleItem?.descriptor is! ConversationThinkingDescriptor ||
        _thinkingHasContent(soleItem!);
    final summary = switch (entry.kind) {
      TimelineEntryKind.images => '读取图片 · ${entry.length}',
      TimelineEntryKind.recovery => entry.recoveryText,
      _ => [
        if (entry.toolCount > 0) '${entry.toolCount} 个工具',
        if (entry.skillCount > 0) '${entry.skillCount} 个技能',
        if (entry.hasThinking) '思考过程',
      ].join(' · '),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionContainer.disabled(
            child: InkWell(
              key: StudioDriverKeys.timelineActivitySummary(entry.id),
              onTap: groupExpandable ? entry.toggle : null,
              child: TimelineActivityRow(
                icon: Icons.account_tree_outlined,
                label: summary,
                expandable: groupExpandable,
                expanded: entry.expanded,
                active: entry.activeCount > 0,
              ),
            ),
          ),
          if (entry.expanded && groupExpandable)
            Container(
              margin: const EdgeInsetsDirectional.only(
                start: TimelineActivityRow.groupIndent,
              ),
              padding: const EdgeInsetsDirectional.only(start: 12),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: context.colors.outlineVariant),
                ),
              ),
              child: SizedBox(
                height: (entry.visibleLength * 48.0).clamp(96.0, 360.0),
                child: ListView.builder(
                  primary: false,
                  itemCount: entry.visibleLength,
                  itemBuilder: (context, index) {
                    final id = entry.visibleIdAt(index);
                    final item = entry.item(id)!;
                    return entry.visibleLength == 1 &&
                            item.descriptor is ConversationThinkingDescriptor
                        ? _singleThinking(item)
                        : _observedMember(id);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _thinkingHasContent(ConversationItem item) =>
      (item.descriptor as ConversationThinkingDescriptor).lifecycle.failure !=
          null ||
      item.fields.any((field) => field.text.trim().isNotEmpty) ||
      item.details.any((detail) => detail.truncated);

  Widget _observedMember(String id) {
    final row = entry.member(id);
    return ListenableBuilder(
      key: ValueKey('timeline-member:$id'),
      listenable: row,
      builder: (context, _) => _member(context, row.item),
    );
  }

  Widget _member(BuildContext context, ConversationItem item) {
    final descriptor = item.descriptor;
    if (descriptor is ConversationToolDescriptor &&
        descriptor.userInput != null) {
      final input = item.userInput!;
      if (ownsPlanConfirmation(descriptor.invocation.name) &&
          input.interactionId == pendingPlanInteractionId &&
          input.state is ConversationUserInputPending) {
        return const SizedBox.shrink();
      }
      return TimelineQuestionReceipt(
        item: item,
        input: input,
        plan: ownsPlanConfirmation(descriptor.invocation.name),
        bodyBuilder: bodyBuilder,
        onDetail: onDetail,
      );
    }
    if (descriptor is ConversationToolDescriptor &&
        descriptor.invocation.name == 'show_image') {
      return _imageCard(context, item, descriptor);
    }
    if (descriptor is ConversationToolDescriptor &&
        descriptor.invocation.name == 'read_file') {
      return _readFileRow(context, item, descriptor);
    }
    if (descriptor is ConversationToolDescriptor && descriptor.wait != null) {
      return TimelineWaitPanel(
        identity: item.id,
        presentation: descriptor.wait!,
        diagnostics: _fields(item),
      );
    }
    final (icon, label, issue) = _label(context, item);
    final runtimeNotice =
        descriptor is ConversationRawDescriptor &&
        descriptor.origin == ThreadRawItemOrigin.runtimeControl;
    final expandable =
        !runtimeNotice &&
        (item.fields.any((field) => field.text.trim().isNotEmpty) ||
            item.details.any((detail) => detail.truncated) ||
            (descriptor is ConversationThinkingDescriptor &&
                descriptor.lifecycle.failure != null) ||
            (descriptor is ConversationRawDescriptor &&
                (descriptor.notice.isNotEmpty ||
                    descriptor.payloads.isNotEmpty)) ||
            descriptor is ConversationSkillDescriptor ||
            descriptor is ConversationAgentDescriptor);
    final expanded = entry.expandedMembers.contains(item.id);
    return Column(
      key: StudioDriverKeys.timelineBlock(item.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionContainer.disabled(
          child: InkWell(
            onTap: expandable ? () => entry.toggleMember(item.id) : null,
            child: TimelineActivityRow(
              icon: icon,
              label: label,
              isIssue: issue,
              expandable: expandable,
              expanded: expanded,
              active: !item.terminal,
            ),
          ),
        ),
        if (runtimeNotice)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28, bottom: 4),
            child: SelectionContainer.disabled(
              child: Text(
                context.l10n.timelineRuntimeNoticeDetail,
                style: context.text.bodySmall,
              ),
            ),
          ),
        if (descriptor is ConversationRawDescriptor &&
            !runtimeNotice &&
            descriptor.notice.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28, bottom: 4),
            child: bodyBuilder(item, descriptor.notice),
          ),
        if (expanded && descriptor is ConversationSkillDescriptor)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28),
            child: Text(
              '${descriptor.value.source} · ${descriptor.value.providerId}',
              style: context.text.bodySmall,
            ),
          ),
        if (expanded && descriptor is ConversationAgentDescriptor)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28),
            child: bodyBuilder(item, _agentDetail(descriptor.value)),
          ),
        if (expanded &&
            descriptor is ConversationThinkingDescriptor &&
            descriptor.lifecycle.failure != null)
          SelectionContainer.disabled(
            child: Text(
              descriptor.lifecycle.failure!,
              style: TextStyle(color: context.colors.error),
            ),
          ),
        if (expanded &&
            descriptor is ConversationRawDescriptor &&
            !runtimeNotice)
          for (final payload in descriptor.payloads)
            SelectionContainer.disabled(
              child: Text(
                '${payload.format} · v${payload.version}',
                style: context.text.bodySmall,
              ),
            ),
        if (expanded &&
            !runtimeNotice &&
            descriptor is! ConversationSkillDescriptor &&
            descriptor is! ConversationAgentDescriptor)
          _fields(item),
        if (expanded && descriptor is ConversationSkillDescriptor)
          if (entry.pairedToolId(item.id) case final pairedId?)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fields(entry.item(pairedId)!),
                TimelineDetailNotices(
                  item: entry.item(pairedId)!,
                  onDetail: onDetail,
                ),
              ],
            ),
        if (entry.kind == TimelineEntryKind.images) mediaBuilder(item),
        if (!runtimeNotice)
          TimelineDetailNotices(item: item, onDetail: onDetail),
      ],
    );
  }

  Widget _singleThinking(ConversationItem item) {
    final row = entry.member(item.id);
    return ListenableBuilder(
      key: ValueKey('timeline-thinking:${item.id}'),
      listenable: row,
      builder: (context, _) => Column(
        key: StudioDriverKeys.timelineBlock(item.id),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (row.item.descriptor
              case ConversationThinkingDescriptor(:final lifecycle)
              when lifecycle.failure != null)
            SelectionContainer.disabled(
              child: Text(
                lifecycle.failure!,
                style: TextStyle(color: context.colors.error),
              ),
            ),
          _fields(row.item),
          TimelineDetailNotices(item: row.item, onDetail: onDetail),
        ],
      ),
    );
  }

  Widget _readFileRow(
    BuildContext context,
    ConversationItem item,
    ConversationToolDescriptor descriptor,
  ) {
    final path = item.readFilePath;
    final slash = path?.lastIndexOf('/') ?? -1;
    final backslash = path?.lastIndexOf('\\') ?? -1;
    final separator = slash > backslash ? slash : backslash;
    final basename = path == null || separator == path.length - 1
        ? null
        : path.substring(separator + 1);
    final expanded = entry.expandedMembers.contains(item.id);
    final expandable =
        item.fields.any((field) => field.text.trim().isNotEmpty) ||
        item.details.any((detail) => detail.truncated);
    return Column(
      key: StudioDriverKeys.timelineBlock(item.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionContainer.disabled(
          child: InkWell(
            onTap: expandable ? () => entry.toggleMember(item.id) : null,
            child: TimelineActivityRow(
              icon: Icons.menu_book_outlined,
              label:
                  '${basename ?? descriptor.invocation.name} · ${_toolStatus(descriptor.state)}',
              tooltip: path,
              expandable: expandable,
              expanded: expanded,
              active: !item.terminal,
              isIssue:
                  descriptor.state is ConversationToolFailed ||
                  descriptor.state is ConversationToolDenied,
            ),
          ),
        ),
        if (expanded) ...[
          _fields(item),
          TimelineDetailNotices(item: item, onDetail: onDetail),
        ],
      ],
    );
  }

  Widget _imageCard(
    BuildContext context,
    ConversationItem item,
    ConversationToolDescriptor descriptor,
  ) {
    final image = timelineAttachments(item)
        .where(
          (attachment) => attachment.modality == AttachmentModalityView.image,
        )
        .firstOrNull;
    final caption = item.imageCardCaption;
    final issue =
        descriptor.state is ConversationToolFailed ||
        descriptor.state is ConversationToolDenied;
    return Column(
      key: StudioDriverKeys.timelineBlock(item.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelineActivityRow(
          icon: Icons.image_outlined,
          label: context.l10n.timelineImageCardTitle,
          expandable: false,
          isIssue: issue,
          active: !item.terminal,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 28, bottom: 4),
          child: SelectionContainer.disabled(
            child: Text(
              _toolStatus(descriptor.state),
              style: context.text.bodySmall,
            ),
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28, bottom: 6),
            child: bodyBuilder(item, caption),
          ),
        if (image == null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28, bottom: 6),
            child: SelectionContainer.disabled(
              child: Text(context.l10n.timelineImageCardEmpty),
            ),
          ),
      ],
    );
  }

  Widget _fields(ConversationItem item) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final field in item.fields)
        if (field.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 28,
              top: 4,
              bottom: 6,
            ),
            child: bodyBuilder(item, field.text),
          ),
    ],
  );

  (IconData, String, bool) _label(
    BuildContext context,
    ConversationItem item,
  ) => switch (item.descriptor) {
    ConversationThinkingDescriptor(:final lifecycle) => (
      Icons.psychology_outlined,
      lifecycle is CancelledThreadContentView
          ? context.l10n.timelineReasoningCancelled
          : item.terminal
          ? context.l10n.timelineReasoningElapsedSeconds(
              lifecycle.terminalAt == null
                  ? 0
                  : lifecycle.terminalAt!
                        .difference(item.header.createdAt)
                        .inSeconds,
            )
          : context.l10n.timelineReasoningActive,
      lifecycle is FailedThreadContentView,
    ),
    ConversationSkillDescriptor(:final value) => (
      Icons.auto_awesome_outlined,
      value.name,
      false,
    ),
    ConversationToolDescriptor(:final invocation, :final state) => (
      Icons.terminal_outlined,
      '${invocation.name} · ${_toolStatus(state)}',
      state is ConversationToolFailed || state is ConversationToolDenied,
    ),
    ConversationRawDescriptor(:final origin) => (
      Icons.info_outline,
      origin == ThreadRawItemOrigin.runtimeControl
          ? context.l10n.timelineRuntimeNotice
          : context.l10n.timelineRawRecord,
      false,
    ),
    ConversationTurnDescriptor(:final value) => (
      value.state is CancelledStudioTurnState
          ? Icons.stop_circle_outlined
          : Icons.info_outline,
      value.state is CancelledStudioTurnState
          ? context.l10n.timelineTurnStopped
          : value.state.reason ?? value.state.status.name,
      value.state is FailedStudioTurnState ||
          value.state is BudgetLimitedStudioTurnState,
    ),
    ConversationAgentDescriptor(:final value) => (
      Icons.account_tree_outlined,
      value.identity.path,
      false,
    ),
    ConversationContextCompactionDescriptor(:final value) => (
      Icons.compress,
      '上下文压缩 · ${value.beforeTokens ?? "—"} → ${value.afterTokens ?? "—"}',
      false,
    ),
    _ => (Icons.info_outline, '', false),
  };

  String _toolStatus(ConversationToolState state) => switch (state) {
    ConversationToolQueued() => '排队中',
    ConversationToolStarted() => '已开始',
    ConversationToolStreaming() || ConversationToolRunning() => '运行中',
    ConversationToolAwaitingApproval() => '等待授权',
    ConversationToolApproved() => '已授权',
    ConversationToolCancelling() => '停止中',
    ConversationToolSucceeded() => '已完成',
    ConversationToolFailed(:final failure) => failure.message,
    ConversationToolDenied(:final reason) => reason,
    ConversationToolCancelled() || ConversationToolInterrupted() => '已停止',
  };
  String _agentDetail(ThreadAgentItemStateView agent) =>
      switch (agent.lifecycle) {
        QueuedThreadAgentView() ||
        RunningThreadAgentView() => agent.identity.task,
        SucceededThreadAgentView(:final summary) => summary,
        DeniedThreadAgentView(:final reason) ||
        CancelledThreadAgentView(:final reason) => reason,
        FailedThreadAgentView(:final error) => error,
      };
}

class TimelineDetailNotices extends StatelessWidget {
  const TimelineDetailNotices({
    super.key,
    required this.item,
    required this.onDetail,
  });
  final ConversationItem item;
  final TimelineDetailAction onDetail;

  bool _canShow(ThreadContentFieldView field) {
    if (field case ThreadToolUserInputFieldView(
      :final questionIndex,
      part: ThreadUserInputAnswerFieldPartView(),
    )) {
      final input = item.userInput!;
      final question = input.questions[questionIndex];
      if (question.isSecret) return false;
      if (input.state case ConversationUserInputResolved(:final answers)) {
        return !answers.any(
          (answer) => answer.questionId == question.id && answer.redacted,
        );
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Column(
      key: StudioDriverKeys.timelineItemBodyNotice(item.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final detail in item.details)
          if (detail.truncated && _canShow(detail.field))
            InkWell(
              key: StudioDriverKeys.timelineDetailOpen(
                item.id,
                StudioDriverKeyValues.timelineDetailField(detail.field),
              ),
              onTap: () => onDetail(item.id, detail.field),
              child: TimelineActivityRow(
                icon: Icons.subject,
                label: timelineFieldLabel(detail.field),
              ),
            ),
      ],
    ),
  );
}

String timelineFieldLabel(ThreadContentFieldView field) => switch (field) {
  ThreadTextFieldView() => '完整正文',
  ThreadThinkingSummaryFieldView() => '思考摘要',
  ThreadThinkingContentFieldView() => '思考正文',
  ThreadToolArgumentsFieldView() => '工具参数',
  ThreadToolResultFieldView() => '工具结果',
  ThreadToolOutputArtifactsFieldView() => '工具产物',
  ThreadRawPayloadFieldView() => '原始记录',
  ThreadToolUserInputFieldView() => '完整问答',
};

class TimelineQuestionReceipt extends StatelessWidget {
  const TimelineQuestionReceipt({
    super.key,
    required this.item,
    required this.input,
    required this.plan,
    required this.bodyBuilder,
    required this.onDetail,
  });
  final ConversationItem item;
  final ConversationUserInputDescriptor input;
  final bool plan;
  final TimelineBodyBuilder bodyBuilder;
  final TimelineDetailAction onDetail;
  @override
  Widget build(BuildContext context) {
    final receipt = plan ? item.planReceipt : null;
    final status = receipt == null
        ? switch (input.state) {
            ConversationUserInputPending() =>
              context.l10n.timelineUserInputAwaiting,
            ConversationUserInputCancelled() =>
              context.l10n.timelineUserInputCancelled,
            ConversationUserInputResolved() =>
              context.l10n.timelineUserInputAnswered,
          }
        : switch (receipt.decision) {
            PlanConfirmationDecisionView.pending =>
              context.l10n.interactionPlanAwaitingConfirmation,
            PlanConfirmationDecisionView.approved =>
              context.l10n.planReceiptApproved,
            PlanConfirmationDecisionView.revisionRequested =>
              context.l10n.planReceiptRevisionRequested,
            PlanConfirmationDecisionView.cancelled =>
              context.l10n.planReceiptCancelled,
            PlanConfirmationDecisionView.resolved =>
              context.l10n.planReceiptAnswered,
          };
    return Padding(
      key: plan
          ? StudioDriverKeys.timelinePlanReceipt(item.id)
          : StudioDriverKeys.timelineUserInput(item.id),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        key: ValueKey('timeline-input-expand:${item.id}'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsetsDirectional.only(start: 28, top: 8),
        shape: const Border(),
        collapsedShape: const Border(),
        title: SelectionContainer.disabled(child: Text(status)),
        subtitle: SelectionContainer.disabled(
          child: Text(
            receipt?.title ??
                (item.userInputText(
                      0,
                      const ThreadUserInputHeaderFieldPartView(),
                    ) ??
                    context.l10n.timelineUserInputQuestionCount(
                      input.questions.length,
                    )),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        children: [
          Column(
            key: StudioDriverKeys.timelineUserInputDetails(item.id),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!plan)
                SelectionContainer.disabled(
                  child: Text(
                    context.l10n.timelineUserInputQuestionCount(
                      input.questions.length,
                    ),
                  ),
                ),
              if (receipt != null) ...[
                bodyBuilder(item, receipt.title),
                if (receipt.feedback.isNotEmpty ||
                    receipt.decision == PlanConfirmationDecisionView.approved)
                  Column(
                    key: StudioDriverKeys.timelinePlanReceiptReply(item.id),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final feedback in receipt.feedback)
                        SelectableText(feedback),
                      if (receipt.feedback.isEmpty &&
                          receipt.decision ==
                              PlanConfirmationDecisionView.approved)
                        Text(context.l10n.planReceiptApproveReply),
                    ],
                  ),
              ] else
                for (var index = 0; index < input.questions.length; index++)
                  Column(
                    key: StudioDriverKeys.timelineUserInputQuestion(
                      item.id,
                      index,
                    ),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      bodyBuilder(
                        item,
                        item.userInputText(
                              index,
                              const ThreadUserInputHeaderFieldPartView(),
                            ) ??
                            '',
                      ),
                      bodyBuilder(
                        item,
                        item.userInputText(
                              index,
                              const ThreadUserInputQuestionFieldPartView(),
                            ) ??
                            '',
                      ),
                      for (
                        var option = 0;
                        option < (input.questions[index].optionCount ?? 0);
                        option++
                      ) ...[
                        bodyBuilder(
                          item,
                          item.userInputText(
                                index,
                                ThreadUserInputOptionLabelFieldPartView(option),
                              ) ??
                              '',
                        ),
                        bodyBuilder(
                          item,
                          item.userInputText(
                                index,
                                ThreadUserInputOptionDescriptionFieldPartView(
                                  option,
                                ),
                              ) ??
                              '',
                        ),
                      ],
                      if (input.state case ConversationUserInputResolved(
                        :final answers,
                      ))
                        for (final answer in answers)
                          if (answer.questionId == input.questions[index].id)
                            Column(
                              key: StudioDriverKeys.timelineUserInputAnswer(
                                item.id,
                                index,
                              ),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (answer.redacted ||
                                    input.questions[index].isSecret)
                                  SelectionContainer.disabled(
                                    child: Text(
                                      context
                                          .l10n
                                          .timelineUserInputSecretHidden,
                                    ),
                                  )
                                else
                                  for (
                                    var part = 0;
                                    part < answer.answerCount;
                                    part++
                                  )
                                    bodyBuilder(
                                      item,
                                      item.userInputText(
                                            index,
                                            ThreadUserInputAnswerFieldPartView(
                                              part,
                                            ),
                                          ) ??
                                          '',
                                    ),
                              ],
                            ),
                    ],
                  ),
              TimelineDetailNotices(item: item, onDetail: onDetail),
            ],
          ),
        ],
      ),
    );
  }
}
