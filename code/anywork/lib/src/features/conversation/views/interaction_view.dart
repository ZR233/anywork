import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/content/studio_code_block.dart';
import '../state/interaction_view_state.dart';
import '../widgets/raw_text_input.dart';

class InteractionView extends StatelessWidget {
  const InteractionView({
    required this.state, required this.onShowQuestion, required this.onLoadQuestions,
    required this.onLoadOptions, required this.onLoadAnswerEntries,
    required this.onLoadAnswerValues, required this.onLoadText,
    required this.onCompleteRead, required this.onRetryRead,
    required this.onQuestionText, required this.onOption,
    required this.onFallback, required this.onReason, required this.onPlanFeedback,
    this.onSubmitAnswers, this.onApproveTool, this.onDenyTool,
    this.onApprovePlan, this.onRequestPlanRevision, this.trailing,
    super.key,
  });
  final InteractionViewState state;
  final Future<void> Function(int) onShowQuestion;
  final Future<void> Function() onLoadQuestions;
  final Future<void> Function(int) onLoadOptions;
  final Future<void> Function() onLoadAnswerEntries;
  final Future<void> Function(int) onLoadAnswerValues;
  final Future<void> Function(int) onLoadText;
  final Future<void> Function() onCompleteRead;
  final Future<void> Function() onRetryRead;
  final void Function(int, String) onQuestionText;
  final void Function(int, String, bool) onOption;
  final ValueChanged<String> onFallback;
  final ValueChanged<String> onReason;
  final ValueChanged<String> onPlanFeedback;
  final Future<void> Function()? onSubmitAnswers;
  final Future<void> Function()? onApproveTool;
  final Future<void> Function()? onDenyTool;
  final Future<void> Function()? onApprovePlan;
  final Future<void> Function()? onRequestPlanRevision;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final header = state.header;
    final pendingEditor = header?.state is PendingInteractionRead;
    final editable = state.enabled && state.sourceCurrent && !state.closing && pendingEditor;
    final allowed = state.submitBlock == null;
    return Padding(padding: const EdgeInsets.all(12), child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header == null)
          const LinearProgressIndicator()
        else if (header.purpose is PlanConfirmationPurposeRead && pendingEditor) ...[
          Text(context.l10n.interactionPlanConfirmTitle,
            style: Theme.of(context).textTheme.titleSmall),
          RawTextInput(raw: state.planFeedback, onChanged: onPlanFeedback,
            enabled: editable, inputKey: StudioDriverKeys.planFeedbackInput,
            decoration: InputDecoration(labelText: context.l10n.interactionPlanAdjust),
            onSubmit: onRequestPlanRevision == null ? null : () => onRequestPlanRevision!().ignore(),
            canSubmit: allowed),
          Wrap(spacing: 8, children: [
            OutlinedButton(key: StudioDriverKeys.planSubmitRevision,
              onPressed: allowed && onRequestPlanRevision != null
                  ? () => onRequestPlanRevision!().ignore() : null,
              child: Text(context.l10n.interactionPlanAdjustSubmit)),
            FilledButton(key: StudioDriverKeys.planApprove,
              onPressed: allowed && onApprovePlan != null ? () => onApprovePlan!().ignore() : null,
              child: Text(context.l10n.interactionPlanConfirmAction)),
          ]),
        ] else ...[
          if (header.content case ToolApprovalContentRead(:final name, :final arguments,
              :final workingDirectory, :final parentAgentId)) ...[
            _text(context, name),
            _text(context, arguments, code: true),
            if (workingDirectory != null) _text(context, workingDirectory),
            if (parentAgentId != null) _text(context, parentAgentId),
            if (pendingEditor) ...[
              RawTextInput(raw: state.approvalReason, onChanged: onReason, enabled: editable),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: allowed && onDenyTool != null
                    ? () => onDenyTool!().ignore() : null, child: Text(context.l10n.interactionReject)),
                FilledButton(onPressed: allowed && onApproveTool != null
                    ? () => onApproveTool!().ignore() : null, child: Text(context.l10n.interactionApprove)),
              ]),
            ],
          ],
          if (header.content case UserInputContentRead(:final questionCount)) ...[
            if (questionCount == 0 && pendingEditor)
              RawTextInput(raw: state.fallbackText, onChanged: onFallback,
                enabled: editable, inputKey: StudioDriverKeys.userInputFirstText),
            if (state.questions[state.currentQuestionIndex] case final progress?)
              _question(context, progress, editable, pendingEditor),
            if (state.questions.length > 1)
              Wrap(spacing: 4, children: [
                for (final index in state.questions.keys)
                  TextButton(onPressed: () => onShowQuestion(index).ignore(), child: Text('${index + 1}')),
              ]),
            if (state.nextQuestionOffset != null)
              TextButton(onPressed: state.questionPageLoading ? null : () => onLoadQuestions().ignore(),
                child: Text(context.l10n.timelineItemBodyLoad)),
            if (editable && header.purpose is! PlanConfirmationPurposeRead)
              FilledButton(key: StudioDriverKeys.userInputSubmit,
                onPressed: allowed && onSubmitAnswers != null ? () => onSubmitAnswers!().ignore() : null,
                child: Text(context.l10n.interactionSubmitAnswers)),
          ],
          if (!pendingEditor) _terminal(context, header),
        ],
        if (state.readIssues.isNotEmpty) ...[
          for (final issue in state.readIssues)
            Text(issue.error.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: () => onRetryRead().ignore(), child: Text(context.l10n.sidebarRetry)),
        ],
        if (state.completingRead)
          const LinearProgressIndicator()
        else if (state.header == null || state.nextQuestionOffset != null ||
            state.questions.values.any((q) => q.nextOptionOffset != null) ||
            state.texts.values.any((text) => !text.complete))
          TextButton(onPressed: () => onCompleteRead().ignore(), child: Text(context.l10n.timelineItemBodyLoad)),
        if (header != null) _metadata(context, header),
        if (state.submissionError != null) Text(state.submissionError!.message),
        if (trailing != null) trailing!,
      ],
    ));
  }

  Widget _question(BuildContext context, QuestionReadProgress progress, bool editable, bool pendingEditor) {
    final question = progress.question;
    final draft = state.answers[question.index] ?? const QuestionAnswerDraft();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _text(context, question.header), _text(context, question.question),
      for (final option in progress.options)
        if (state.textOf(option.label) case final label?)
          CheckboxListTile(
            key: question.index == 0 && option.index == 0 ? StudioDriverKeys.userInputFirstOption
                : StudioDriverKeys.userInputOption('${question.index}', option.index),
            title: Text(label), subtitle: _text(context, option.description),
            value: draft.selectedLabels.contains(label),
            onChanged: editable ? (selected) => onOption(question.index, label, selected == true) : null,
            controlAffinity: ListTileControlAffinity.leading,
          )
        else
          _text(context, option.label),
      if (progress.nextOptionOffset != null)
        TextButton(onPressed: progress.optionsLoading ? null : () => onLoadOptions(question.index).ignore(),
          child: Text(context.l10n.timelineItemBodyLoad)),
      if (pendingEditor && (question.isOther || (question.optionsCount ?? 0) == 0))
        RawTextInput(key: ValueKey((state.key, question.index)),
          raw: draft.text, secret: question.isSecret, enabled: editable,
          onChanged: (raw) => onQuestionText(question.index, raw),
          inputKey: question.index == 0 ? StudioDriverKeys.userInputFirstText
              : StudioDriverKeys.userInputText('${question.index}'),
          decoration: InputDecoration(labelText: question.isOther
              ? context.l10n.interactionOtherLabel : context.l10n.interactionAnswerLabel)),
    ]);
  }

  Widget _text(BuildContext context, ReadText text, {bool code = false}) {
    final value = state.textOf(text);
    if (value != null) return code ? StudioCodeBlock(text: value, maxHeight: 260) : Text(value);
    final deferred = text as DeferredReadText;
    final progress = state.texts[deferred.fieldId];
    return TextButton(onPressed: progress?.loading == true ? null : () => onLoadText(deferred.fieldId).ignore(),
      child: Text('${context.l10n.timelineItemBodyLoad} · ${progress?.loadedUtf8Bytes ?? 0}/${deferred.utf8Bytes} B'));
  }

  Widget _terminal(BuildContext context, InteractionReadHeader header) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
    children: [
      if (header.state case ResolvedApprovalRead(:final decision, :final reason)) ...[
        Text(decision.name), if (reason != null) _text(context, reason),
      ],
      if (header.state case CancelledInteractionRead(:final reason)) _text(context, reason),
      for (final entry in state.answerEntries) ...[
        _text(context, entry.questionId),
        for (final value in state.answerValues[entry.index] ?? const <AnswerValueReadItem>[])
          _historicalAnswer(context, entry, value),
        if (state.nextAnswerValueOffsets[entry.index] != null)
          TextButton(onPressed: () => onLoadAnswerValues(entry.index).ignore(),
            child: Text(context.l10n.timelineItemBodyLoad)),
      ],
      if (state.nextAnswerEntryOffset != null)
        TextButton(onPressed: () => onLoadAnswerEntries().ignore(), child: Text(context.l10n.timelineItemBodyLoad)),
    ],
  );

  Widget _historicalAnswer(BuildContext context, AnswerEntryReadItem entry, AnswerValueReadItem answer) {
    final id = state.textOf(entry.questionId);
    final question = state.questions.values.where((q) => state.textOf(q.question.id) == id).firstOrNull;
    // An unmaterialized/unknown question cannot prove its answer is non-secret.
    if (question == null || question.question.isSecret) return const Text('••••');
    return _text(context, answer.value);
  }

  Widget _metadata(BuildContext context, InteractionReadHeader header) => ExpansionTile(
    key: ValueKey(('interaction-metadata', state.key)), title: const Text('Interaction'),
    children: [
      _text(context, header.interactionId), _text(context, header.threadId), _text(context, header.turnId),
      if (header.itemId != null) _text(context, header.itemId!),
      if (header.toolId != null) _text(context, header.toolId!),
      if (header.agentPath != null) _text(context, header.agentPath!),
      Text('revision=${header.revision} · created_at=${header.createdAt} · updated_at=${header.updatedAt}'),
      if (header.purpose case PlanConfirmationPurposeRead(:final expectedRevision,
          :final operationId, :final argumentHash, :final planHash)) ...[
        Text('planConfirmation · expectedRevision=$expectedRevision'),
        _text(context, operationId), _text(context, argumentHash), _text(context, planHash),
      ],
      if (header.continuation case QuestionContinuationRead(:final questionId, :final presentation)) ...[
        Text('question · ${presentation.name}'), _text(context, questionId),
      ],
      if (header.continuation case ResolutionContinuationRead(:final presentation)) Text('resolution · ${presentation.name}'),
      switch (header.state) {
        PendingInteractionRead(:final operationId) => _text(context, operationId),
        ResolvedUserInputRead(:final operationId, :final resolvedAt, :final answerEntryCount) => Column(children: [
          _text(context, operationId), Text('resolved_at=$resolvedAt · answers=$answerEntryCount')]),
        ResolvedApprovalRead(:final operationId, :final resolvedAt, :final decision) => Column(children: [
          _text(context, operationId), Text('resolved_at=$resolvedAt · ${decision.name}')]),
        CancelledInteractionRead(:final operationId, :final cancelledAt) => Column(children: [
          _text(context, operationId), Text('cancelled_at=$cancelledAt')]),
        ExpiredInteractionRead(:final operationId, :final expiredAt) => Column(children: [
          _text(context, operationId), Text('expired_at=$expiredAt')]),
      },
    ],
  );
}
