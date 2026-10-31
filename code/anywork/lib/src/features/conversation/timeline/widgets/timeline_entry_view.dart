import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_code_block.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/studio_driver_key_values.dart';
import '../state/timeline_entry.dart';
import 'timeline_activity_row.dart';
import 'timeline_activity_group_adapter.dart';
import 'timeline_activity_group_views.dart';
import 'timeline_plain_text.dart';
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
      return _group(context);
    },
  );

  Widget _group(BuildContext context) {
    final groupExpandable = entry.visibleLength > 0;
    final summary = switch (entry.kind) {
      TimelineEntryKind.images => '读取图片 · ${entry.length}',
      _ => [
        if (entry.elapsedDuration case final duration?)
          groupWorkedLabel(context, duration),
        if (entry.toolCount > 0)
          entry.issueCount > 0
              ? context.l10n.timelineToolGroupSummaryIssues(
                  entry.toolCount,
                  entry.issueCount,
                )
              : context.l10n.timelineToolGroupSummary(entry.toolCount),
        if (entry.skillCount > 0)
          context.l10n.statusSkillsCount(entry.skillCount),
        if (entry.hasThinking &&
            entry.elapsedDuration == null &&
            entry.toolCount == 0 &&
            entry.skillCount == 0)
          context.l10n.timelineReasoningEnded,
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
                icon: entry.kind == TimelineEntryKind.activity
                    ? null
                    : Icons.account_tree_outlined,
                label: summary,
                expandable: groupExpandable,
                expanded: entry.expanded,
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
                    return _observedMember(id);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _observedMember(String id) {
    final row = entry.member(id);
    return ListenableBuilder(
      key: ValueKey('timeline-member:$id'),
      listenable: row,
      builder: (context, _) => _member(context, row.item),
    );
  }

  Widget _member(BuildContext context, ConversationItem item) {
    final content = _memberContent(context, item);
    if (timelineAttachments(item).isEmpty) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [content, mediaBuilder(item)],
    );
  }

  Widget _memberContent(BuildContext context, ConversationItem item) {
    final descriptor = item.descriptor;
    if (descriptor is ConversationToolDescriptor && descriptor.wait != null) {
      final conversion = TimelineActivityGroupAdapter.convertItem(item);
      final diagnostics = switch (conversion) {
        TimelineActivityConverted(
          message: final TimelineToolGroupMessage tool,
        ) =>
          timelineActivityToolDiagnostics(
            item: tool,
            details: timelineActivityMessageDetailNotice(
              context,
              tool,
              onOpenDetail: onDetail,
            ),
          ),
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fields(item),
            TimelineDetailNotices(item: item, onDetail: onDetail),
          ],
        ),
      };
      return TimelineWaitPanel(
        identity: item.id,
        presentation: descriptor.wait!,
        diagnostics: diagnostics,
        initiallyExpanded: entry.isMemberExpanded(item.id),
        onExpansionChanged: (value) => entry.setMemberExpanded(item.id, value),
      );
    }
    if (entry.kind == TimelineEntryKind.activity) {
      final conversion = TimelineActivityGroupAdapter.convertItem(item);
      if (conversion is TimelineActivityConverted) {
        final pairedId = entry.pairedToolId(item.id);
        final paired = pairedId == null
            ? null
            : TimelineActivityGroupAdapter.convertItem(entry.item(pairedId)!);
        return KeyedSubtree(
          key: StudioDriverKeys.timelineBlock(item.id),
          child: TimelineActivityMemberView(
            message: conversion.message,
            initiallyExpanded: entry.isMemberExpanded(item.id),
            onExpansionChanged: (value) =>
                entry.setMemberExpanded(item.id, value),
            pairedTool:
                paired is TimelineActivityConverted &&
                    paired.message is TimelineToolGroupMessage
                ? paired.message as TimelineToolGroupMessage
                : null,
            onOpenDetail: onDetail,
            bodyBuilder: (id, text) => bodyBuilder(entry.item(id)!, text),
          ),
        );
      }
    }
    if (descriptor is ConversationPlanDescriptor) {
      if (descriptor.interactionId == pendingPlanInteractionId &&
          descriptor.decision != ConversationPlanDecision.cancelled &&
          descriptor.decision != ConversationPlanDecision.resolved) {
        return const SizedBox.shrink();
      }
      return TimelineQuestionReceipt(
        item: item,
        plan: true,
        bodyBuilder: bodyBuilder,
        onDetail: onDetail,
      );
    }
    if (descriptor is ConversationToolDescriptor &&
        descriptor.userInput != null) {
      return TimelineQuestionReceipt(
        item: item,
        input: item.userInput,
        plan: false,
        bodyBuilder: bodyBuilder,
        onDetail: onDetail,
      );
    }
    if (descriptor is ConversationToolDescriptor &&
        descriptor.invocation.name == 'show_image') {
      return _imageCard(context, item, descriptor);
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
                _thinkingFailure(descriptor.outcome) != null) ||
            (descriptor is ConversationRawDescriptor &&
                (descriptor.notice.isNotEmpty ||
                    descriptor.payloads.isNotEmpty)) ||
            descriptor is ConversationSkillDescriptor ||
            descriptor is ConversationAgentDescriptor);
    final expanded = entry.isMemberExpanded(item.id);
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
            child: bodyBuilder(item, _agentDetail(descriptor)),
          ),
        if (expanded &&
            descriptor is ConversationThinkingDescriptor &&
            _thinkingFailure(descriptor.outcome) != null)
          SelectionContainer.disabled(
            child: Text(
              _thinkingFailure(descriptor.outcome)!,
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
        if (!runtimeNotice)
          TimelineDetailNotices(item: item, onDetail: onDetail),
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
            child: item.descriptor is ConversationToolDescriptor
                ? StudioCodeBlock(text: field.text, maxHeight: 280)
                : bodyBuilder(item, field.text),
          ),
    ],
  );

  (IconData, String, bool) _label(
    BuildContext context,
    ConversationItem item,
  ) => switch (item.descriptor) {
    ConversationThinkingDescriptor(:final outcome) => (
      Icons.psychology_outlined,
      outcome is ConversationContentCancelled
          ? context.l10n.timelineReasoningCancelled
          : context.l10n.timelineReasoningElapsedSeconds(
              _thinkingElapsedSeconds(item, outcome),
            ),
      outcome is ConversationContentFailed,
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
    ConversationTurnDescriptor(:final outcome) => (
      outcome is ConversationTurnCancelled
          ? Icons.stop_circle_outlined
          : Icons.info_outline,
      _turnLabel(context, outcome),
      outcome is ConversationTurnFailed ||
          outcome is ConversationTurnBudgetLimited,
    ),
    ConversationAgentDescriptor(:final identity) => (
      Icons.account_tree_outlined,
      identity.path,
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
    ConversationToolBackgroundStarted() => '运行中',
    ConversationToolSucceeded() => '已完成',
    ConversationToolFailed(:final failure) => failure.message,
    ConversationToolDenied(:final reason) => reason,
    ConversationToolCancelled() || ConversationToolInterrupted() => '已停止',
  };

  String _agentDetail(ConversationAgentDescriptor descriptor) =>
      switch (descriptor.outcome) {
        ConversationAgentSucceeded(:final value) => value.summary,
        ConversationAgentDenied(:final value) => value.reason,
        ConversationAgentCancelled(:final value) => value.reason,
        ConversationAgentFailed(:final value) => value.error,
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
      final input = item.userInput;
      if (input == null) return false;
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
  ThreadPlanDocumentFieldView() => '计划正文',
  ThreadPlanFeedbackFieldView() => '修改意见',
};

class TimelineQuestionReceipt extends StatelessWidget {
  const TimelineQuestionReceipt({
    super.key,
    required this.item,
    this.input,
    required this.plan,
    required this.bodyBuilder,
    required this.onDetail,
  });
  final ConversationItem item;
  final ConversationUserInputDescriptor? input;
  final bool plan;
  final TimelineBodyBuilder bodyBuilder;
  final TimelineDetailAction onDetail;

  @override
  Widget build(BuildContext context) {
    final receipt = plan ? item.planReceipt : null;
    final status = receipt == null
        ? switch (input?.state) {
            ConversationUserInputCancelled() =>
              context.l10n.timelineUserInputCancelled,
            ConversationUserInputResolved() ||
            null => context.l10n.timelineUserInputAnswered,
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
    final subtitle =
        receipt?.title ??
        (item.userInputText(0, const ThreadUserInputHeaderFieldPartView()) ??
            context.l10n.timelineUserInputQuestionCount(
              input?.questions.length ?? 0,
            ));
    return Padding(
      key: plan
          ? StudioDriverKeys.timelinePlanReceipt(item.id)
          : StudioDriverKeys.timelineUserInput(item.id),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: context.colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadii.md),
          side: BorderSide(color: context.colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: ValueKey('timeline-input-expand:${item.id}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: const Border(),
          collapsedShape: const Border(),
          title: SelectionContainer.disabled(
            child: Text(status, style: context.text.titleSmall),
          ),
          subtitle: SelectionContainer.disabled(
            child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          children: [
            Column(
              key: StudioDriverKeys.timelineUserInputDetails(item.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (receipt != null)
                  _PlanReceiptBody(
                    item: item,
                    receipt: receipt,
                    bodyBuilder: bodyBuilder,
                  )
                else if (input != null) ...[
                  SelectionContainer.disabled(
                    child: Text(
                      context.l10n.timelineUserInputQuestionCount(
                        input!.questions.length,
                      ),
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < input!.questions.length; index++)
                    _QuestionReceiptBlock(
                      item: item,
                      input: input!,
                      index: index,
                      bodyBuilder: bodyBuilder,
                    ),
                ],
                TimelineDetailNotices(item: item, onDetail: onDetail),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanReceiptBody extends StatelessWidget {
  const _PlanReceiptBody({
    required this.item,
    required this.receipt,
    required this.bodyBuilder,
  });

  final ConversationItem item;
  final PlanConfirmationReceiptView receipt;
  final TimelineBodyBuilder bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final document =
        item.fieldFor(const ThreadPlanDocumentFieldView())?.text ?? '';
    final feedback = receipt.feedback
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (document.trim().isNotEmpty) bodyBuilder(item, document),
        if (feedback.isNotEmpty)
          Column(
            key: StudioDriverKeys.timelinePlanReceiptReply(item.id),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              SelectionContainer.disabled(
                child: Text(
                  context.l10n.planReceiptYourFeedback,
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (var index = 0; index < feedback.length; index++)
                TimelinePlainText(
                  id: '${item.id}-plan-feedback-$index',
                  text: feedback[index],
                  style: context.text.bodyMedium?.copyWith(height: 1.57),
                ),
            ],
          ),
      ],
    );
  }
}

class _QuestionReceiptBlock extends StatelessWidget {
  const _QuestionReceiptBlock({
    required this.item,
    required this.input,
    required this.index,
    required this.bodyBuilder,
  });

  final ConversationItem item;
  final ConversationUserInputDescriptor input;
  final int index;
  final TimelineBodyBuilder bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final question = input.questions[index];
    final header = item.userInputText(
      index,
      const ThreadUserInputHeaderFieldPartView(),
    );
    final prompt = item.userInputText(
      index,
      const ThreadUserInputQuestionFieldPartView(),
    );
    final answers = switch (input.state) {
      ConversationUserInputResolved(:final answers) =>
        answers
            .where((answer) => answer.questionId == question.id)
            .toList(growable: false),
      ConversationUserInputCancelled() =>
        const <ConversationAnswerDescriptor>[],
    };
    final selectedLabels = <String>{};
    for (final answer in answers) {
      if (answer.redacted || question.isSecret) continue;
      for (var part = 0; part < answer.answerCount; part++) {
        final text = item.userInputText(
          index,
          ThreadUserInputAnswerFieldPartView(part),
        );
        if (text != null && text.isNotEmpty) selectedLabels.add(text);
      }
    }
    final optionCount = question.optionCount ?? 0;
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
      child: Column(
        key: StudioDriverKeys.timelineUserInputQuestion(item.id, index),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null && header.isNotEmpty)
            SelectionContainer.disabled(
              child: Text(header, style: context.text.labelLarge),
            ),
          if (prompt != null && prompt.isNotEmpty) ...[
            if (header != null && header.isNotEmpty) const SizedBox(height: 4),
            bodyBuilder(item, prompt),
          ],
          if (optionCount > 0) ...[
            const SizedBox(height: 10),
            SelectionContainer.disabled(
              child: Text(
                context.l10n.timelineUserInputOptions,
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (var option = 0; option < optionCount; option++)
              _QuestionOptionTile(
                item: item,
                index: index,
                option: option,
                selectedLabels: selectedLabels,
                bodyBuilder: bodyBuilder,
              ),
          ],
          const SizedBox(height: 10),
          SelectionContainer.disabled(
            child: Text(
              context.l10n.timelineUserInputYourAnswer,
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (answers.isEmpty)
            SelectionContainer.disabled(
              child: Text(switch (input.state) {
                ConversationUserInputCancelled() =>
                  context.l10n.timelineUserInputCancelled,
                ConversationUserInputResolved() =>
                  context.l10n.timelineUserInputNoAnswer,
              }),
            )
          else
            for (final answer in answers)
              Column(
                key: StudioDriverKeys.timelineUserInputAnswer(item.id, index),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (answer.redacted || question.isSecret)
                    SelectionContainer.disabled(
                      child: Text(context.l10n.timelineUserInputSecretHidden),
                    )
                  else if (answer.answerCount == 0)
                    SelectionContainer.disabled(
                      child: Text(context.l10n.timelineUserInputNoAnswer),
                    )
                  else
                    for (var part = 0; part < answer.answerCount; part++)
                      bodyBuilder(
                        item,
                        item.userInputText(
                              index,
                              ThreadUserInputAnswerFieldPartView(part),
                            ) ??
                            '',
                      ),
                ],
              ),
        ],
      ),
    );
  }
}

class _QuestionOptionTile extends StatelessWidget {
  const _QuestionOptionTile({
    required this.item,
    required this.index,
    required this.option,
    required this.selectedLabels,
    required this.bodyBuilder,
  });

  final ConversationItem item;
  final int index;
  final int option;
  final Set<String> selectedLabels;
  final TimelineBodyBuilder bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final label = item.userInputText(
      index,
      ThreadUserInputOptionLabelFieldPartView(option),
    );
    final description = item.userInputText(
      index,
      ThreadUserInputOptionDescriptionFieldPartView(option),
    );
    final selected = label != null && selectedLabels.contains(label);
    final icon = selected ? Icons.check : Icons.remove;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 0,
        leading: Icon(
          icon,
          size: 18,
          color: selected
              ? context.colors.primary
              : context.colors.onSurfaceVariant,
        ),
        title: label == null || label.isEmpty ? null : bodyBuilder(item, label),
        subtitle: description == null || description.isEmpty
            ? null
            : bodyBuilder(item, description),
      ),
    );
  }
}

String? _thinkingFailure(ConversationContentOutcome outcome) =>
    switch (outcome) {
      ConversationContentFailed(:final value) => value.error,
      _ => null,
    };

int _thinkingElapsedSeconds(
  ConversationItem item,
  ConversationContentOutcome outcome,
) {
  final completed = switch (outcome) {
    ConversationContentCompleted(:final value) => value.completedAt,
    ConversationContentFailed(:final value) => value.failedAt,
    ConversationContentCancelled(:final value) => value.cancelledAt,
  };
  final startedSeconds = item.header.sourceEffectSeq ?? item.header.appendSeq;
  final started = DateTime.fromMillisecondsSinceEpoch(
    startedSeconds * 1000,
    isUtc: true,
  );
  final elapsed = completed.difference(started).inSeconds;
  return elapsed < 0 ? 0 : elapsed;
}

String _turnLabel(BuildContext context, ConversationTurnOutcome outcome) =>
    switch (outcome) {
      ConversationTurnCancelled() => context.l10n.timelineTurnStopped,
      ConversationTurnFailed(:final value) => value.failure.message,
      ConversationTurnBudgetLimited(:final value) =>
        value.reason ?? value.status.name,
      ConversationTurnCompleted(:final value) =>
        value.reason ?? value.status.name,
    };
