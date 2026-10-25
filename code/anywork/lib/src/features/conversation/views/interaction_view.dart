import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/interaction_view_state.dart';
import '../widgets/raw_text_input.dart';
import 'interaction_dock_shell.dart';
import 'question_progress.dart';
import 'question_step.dart';

/// Unified visual height and horizontal padding of the Plan decision actions.
///
/// Both actions share one size, the group keeps the shared footer's 8px gap and
/// its right edge follows the input above. Standard density plus a padded tap
/// target keeps the visual 40 / layout 48 box on desktop themes that default to
/// `shrinkWrap` and a compact app density.
const double _planActionMinHeight = 40;
const EdgeInsets _planActionPadding = EdgeInsets.symmetric(horizontal: 14);
const VisualDensity _planActionVisualDensity = VisualDensity.standard;
const MaterialTapTargetSize _planActionTapTargetSize =
    MaterialTapTargetSize.padded;

class InteractionView extends StatelessWidget {
  const InteractionView({
    required this.state,
    required this.onShowQuestion,
    required this.onLoadQuestions,
    required this.onLoadOptions,
    required this.onLoadAnswerEntries,
    required this.onLoadAnswerValues,
    required this.onLoadText,
    required this.onCompleteRead,
    required this.onRetryRead,
    required this.onQuestionText,
    required this.onOption,
    required this.onFallback,
    required this.onReason,
    required this.onPlanFeedback,
    this.onSubmitAnswers,
    this.onApproveTool,
    this.onDenyTool,
    this.onApprovePlan,
    this.onRequestPlanRevision,
    this.onRetrySubmissionRead,
    this.trailing,
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
  final Future<void> Function()? onRetrySubmissionRead;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final header = state.header;
    final pendingEditor = header?.state is PendingInteractionRead;
    final decisionPending = state.submission?.isPending == true;
    final decisionConfirmed =
        state.submission?.receipt != null ||
        state.submission?.acknowledged == true;
    final editable =
        state.enabled &&
        state.sourceCurrent &&
        !state.closing &&
        pendingEditor &&
        !decisionPending &&
        !decisionConfirmed;
    final allowed = editable && state.submitBlock == null;
    final canRevisePlan = allowed && state.planFeedback.trim().isNotEmpty;
    final unknown =
        state.submission?.failurePhase == OperationFailurePhase.unknownOutcome;
    final content = header?.content;
    final isPlan = header?.purpose is PlanConfirmationPurposeRead;
    final isApproval = content is ToolApprovalContentRead;
    final questionCount = content is UserInputContentRead
        ? content.questionCount
        : 0;
    final kind = isPlan
        ? InteractionDockKind.plan
        : isApproval
        ? InteractionDockKind.permission
        : InteractionDockKind.question;
    final index = state.currentQuestionIndex;
    // HEAD只有“最后一题/还有后续”两种可编辑问题态；无问题文本走独立 dock，
    // 不参与该判定。
    final isLast = questionCount != 0 && index >= questionCount - 1;
    final answered = state.answers.values
        .where(
          (draft) =>
              draft.selectedLabels.isNotEmpty || draft.text.trim().isNotEmpty,
        )
        .length;
    final unanswered = questionCount - answered < 0
        ? 0
        : questionCount - answered;
    final title = switch (kind) {
      InteractionDockKind.plan => context.l10n.interactionPlanConfirmTitle,
      InteractionDockKind.permission => context.l10n.interactionPermissionTitle,
      InteractionDockKind.question =>
        questionCount == 0
            ? context.l10n.interactionNeedInputTitle
            : context.l10n.interactionQuestionsTitle,
    };
    final subtitle = switch (kind) {
      InteractionDockKind.plan => context.l10n.interactionPlanConfirmSubtitle,
      InteractionDockKind.permission =>
        context.l10n.interactionPermissionSubtitle,
      InteractionDockKind.question =>
        questionCount == 0
            ? context.l10n.interactionContinueAfterAnswer
            : !isLast
            ? context.l10n.interactionContinueAfterAnswer
            : context.l10n.interactionLastQuestion,
    };
    final footerHint = switch (kind) {
      InteractionDockKind.plan => context.l10n.interactionPlanFeedbackHint,
      InteractionDockKind.permission =>
        context.l10n.interactionPermissionFooterHint,
      InteractionDockKind.question =>
        questionCount == 0
            ? context.l10n.interactionAnswerHint
            : isLast
            ? context.l10n.interactionSubmitEmptyAnswersHint
            : context.l10n.interactionAnsweredPendingHint(answered, unanswered),
    };
    final footer = pendingEditor
        ? DockActions(
            children: [
              if (isPlan) ...[
                OutlinedButton.icon(
                  key: StudioDriverKeys.planSubmitRevision,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, _planActionMinHeight),
                    padding: _planActionPadding,
                    visualDensity: _planActionVisualDensity,
                    tapTargetSize: _planActionTapTargetSize,
                  ),
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text(context.l10n.interactionPlanAdjustSubmit),
                  onPressed: canRevisePlan && onRequestPlanRevision != null
                      ? () => onRequestPlanRevision!().ignore()
                      : null,
                ),
                FilledButton.icon(
                  key: StudioDriverKeys.planApprove,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, _planActionMinHeight),
                    padding: _planActionPadding,
                    visualDensity: _planActionVisualDensity,
                    tapTargetSize: _planActionTapTargetSize,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(context.l10n.interactionPlanConfirmAction),
                  onPressed: allowed && onApprovePlan != null
                      ? () => onApprovePlan!().ignore()
                      : null,
                ),
              ] else if (isApproval) ...[
                TextButton.icon(
                  key: StudioDriverKeys.toolDeny,
                  icon: const Icon(Icons.close),
                  label: Text(context.l10n.interactionReject),
                  onPressed: allowed && onDenyTool != null
                      ? () => onDenyTool!().ignore()
                      : null,
                ),
                FilledButton.icon(
                  key: StudioDriverKeys.toolApprove,
                  icon: const Icon(Icons.check),
                  label: Text(context.l10n.interactionApprove),
                  onPressed: allowed && onApproveTool != null
                      ? () => onApproveTool!().ignore()
                      : null,
                ),
              ] else if (questionCount == 0)
                FilledButton.icon(
                  key: StudioDriverKeys.fallbackUserInputSubmit,
                  icon: const Icon(Icons.reply),
                  label: Text(context.l10n.interactionAnswerButton),
                  onPressed:
                      allowed &&
                          state.fallbackText.trim().isNotEmpty &&
                          onSubmitAnswers != null
                      ? () => onSubmitAnswers!().ignore()
                      : null,
                )
              else ...[
                if (index > 0)
                  TextButton.icon(
                    icon: const Icon(Icons.chevron_left),
                    label: Text(context.l10n.interactionPreviousQuestion),
                    onPressed: () => onShowQuestion(index - 1).ignore(),
                  ),
                FilledButton.icon(
                  key: StudioDriverKeys.userInputSubmit,
                  icon: Icon(isLast ? Icons.check : Icons.chevron_right),
                  label: Text(
                    isLast
                        ? context.l10n.interactionSubmitAnswers
                        : context.l10n.interactionNextQuestion,
                  ),
                  onPressed: !allowed || onSubmitAnswers == null
                      ? null
                      : isLast
                      ? () => onSubmitAnswers!().ignore()
                      : state.questions.containsKey(index + 1)
                      ? () => onShowQuestion(index + 1).ignore()
                      : null,
                ),
              ],
            ],
          )
        : null;
    return InteractionDockShell(
      kind: kind,
      title: title,
      subtitle: subtitle,
      footerHint: footerHint,
      trailing: trailing,
      footer: footer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header == null)
            const LinearProgressIndicator()
          else if (header.purpose is PlanConfirmationPurposeRead &&
              pendingEditor) ...[
            // The dock header owns the title; the body is only the editable
            // feedback surface whose right edge the footer actions follow.
            RawTextInput(
              raw: state.planFeedback,
              onChanged: onPlanFeedback,
              enabled: editable,
              inputKey: StudioDriverKeys.planFeedbackInput,
              decoration: InputDecoration(
                labelText: context.l10n.interactionPlanAdjust,
                hintText: context.l10n.interactionPlanAdjustHint,
              ),
              onSubmit: onRequestPlanRevision == null
                  ? null
                  : () => onRequestPlanRevision!().ignore(),
              canSubmit: canRevisePlan,
            ),
          ] else ...[
            if (header.content case ToolApprovalContentRead(
              :final name,
              :final arguments,
              :final workingDirectory,
            )) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _label(context, name, Icons.build_outlined),
                  if (workingDirectory != null)
                    _label(context, workingDirectory, Icons.folder_outlined),
                ],
              ),
              if (_toolArguments(context, arguments) case final block?) ...[
                const SizedBox(height: 10),
                block,
              ],
              if (pendingEditor) ...[
                const SizedBox(height: 10),
                RawTextInput(
                  raw: state.approvalReason,
                  onChanged: onReason,
                  enabled: editable,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: context.l10n.interactionReasonLabel,
                  ),
                ),
              ],
            ],
            if (header.content case UserInputContentRead(
              :final questionCount,
            )) ...[
              if (questionCount == 0 && pendingEditor)
                RawTextInput(
                  raw: state.fallbackText,
                  onChanged: onFallback,
                  enabled: editable,
                  inputKey: StudioDriverKeys.fallbackUserInput,
                  decoration: InputDecoration(
                    labelText: context.l10n.interactionAnswerLabel,
                    prefixIcon: const Icon(Icons.short_text_outlined),
                  ),
                ),
              if (questionCount > 0) ...[
                QuestionProgress(
                  total: questionCount,
                  currentIndex: index,
                  answeredCount: answered,
                  indices: state.questions.keys.toList()..sort(),
                  answered: _answered,
                  onSelected: (value) => onShowQuestion(value).ignore(),
                ),
                const SizedBox(height: 12),
                if (state.questions[index] case final progress?)
                  _question(context, progress, editable, pendingEditor),
              ],
              if (state.nextQuestionOffset != null)
                TextButton(
                  onPressed: state.questionPageLoading
                      ? null
                      : () => onLoadQuestions().ignore(),
                  child: Text(context.l10n.timelineItemBodyLoad),
                ),
            ],
            if (!pendingEditor) _terminal(context, header),
          ],
          if (state.readIssues.isNotEmpty) ...[
            for (final issue in state.readIssues)
              Text(
                issue.error.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextButton(
              onPressed: () => onRetryRead().ignore(),
              child: Text(context.l10n.sidebarRetry),
            ),
          ],
          if (state.completingRead)
            const LinearProgressIndicator()
          else if (state.header == null ||
              state.nextQuestionOffset != null ||
              state.questions.values.any((q) => q.nextOptionOffset != null) ||
              state.texts.values.any((text) => !text.complete))
            TextButton(
              onPressed: () => onCompleteRead().ignore(),
              child: Text(context.l10n.timelineItemBodyLoad),
            ),
          // 在途状态只用禁用表达：HEAD 的决定栏没有常驻进度条，而
          // “已受理但尚未被 canonical 观察”会持续到交互被移除，视觉上不能让
          // 用户一直看到不确定进度动画。
          if (unknown) Text(context.l10n.settingsBotsSendUnknown),
          if (state.submissionError != null)
            // The real command failure keeps its own line with an error mark and
            // body text; the draft above stays untouched so it can be edited and
            // sent again.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 15,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    state.submissionError!.message,
                    key: header?.purpose is PlanConfirmationPurposeRead
                        ? StudioDriverKeys.planFeedbackError
                        : null,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
          if (unknown ||
              state.submission?.failurePhase ==
                  OperationFailurePhase.syncFailed)
            TextButton(
              onPressed: onRetrySubmissionRead == null
                  ? null
                  : () => onRetrySubmissionRead!().ignore(),
              child: Text(context.l10n.modelDetailRetry),
            ),
        ],
      ),
    );
  }

  Widget _question(
    BuildContext context,
    QuestionReadProgress progress,
    bool editable,
    bool pendingEditor,
  ) {
    final question = progress.question;
    final draft = state.answers[question.index] ?? const QuestionAnswerDraft();
    final header = state.textOf(question.header);
    return QuestionStep(
      header: header == null
          ? _text(context, question.header)
          : Text(
              header.isEmpty
                  ? context.l10n.interactionQuestionFallback
                  : header,
              style: Theme.of(context).textTheme.labelLarge,
            ),
      question: _questionText(context, question.question),
      options: [
        for (final option in progress.options)
          if (state.textOf(option.label) case final label?)
            Padding(
              key: question.index == 0 && option.index == 0
                  ? StudioDriverKeys.userInputFirstOption
                  : StudioDriverKeys.userInputOption(
                      '${question.index}',
                      option.index,
                    ),
              padding: const EdgeInsets.only(bottom: 7),
              child: QuestionOptionRow(
                label: label,
                description: _optionDescription(context, option.description),
                selected: draft.selectedLabels.contains(label),
                onPressed: editable
                    ? () => onOption(
                        question.index,
                        label,
                        !draft.selectedLabels.contains(label),
                      )
                    : null,
              ),
            )
          else
            _text(context, option.label),
        if (progress.nextOptionOffset != null)
          TextButton(
            onPressed: progress.optionsLoading
                ? null
                : () => onLoadOptions(question.index).ignore(),
            child: Text(context.l10n.timelineItemBodyLoad),
          ),
      ],
      input:
          pendingEditor &&
              (question.isOther || (question.optionsCount ?? 0) == 0)
          ? RawTextInput(
              key: ValueKey((state.key, question.index)),
              raw: draft.text,
              secret: question.isSecret,
              enabled: editable,
              onChanged: (raw) => onQuestionText(question.index, raw),
              inputKey: question.index == 0
                  ? StudioDriverKeys.userInputFirstText
                  : StudioDriverKeys.userInputText('${question.index}'),
              decoration: InputDecoration(
                labelText: question.isOther
                    ? context.l10n.interactionOtherLabel
                    : context.l10n.interactionAnswerLabel,
                hintText: question.isSecret
                    ? context.l10n.interactionSecretHint
                    : context.l10n.interactionTextHint,
                prefixIcon: Icon(
                  question.isSecret
                      ? Icons.password_outlined
                      : Icons.short_text_outlined,
                ),
              ),
            )
          : null,
    );
  }

  /// Deferred option text stays a load action; a materialized one becomes the
  /// row's secondary line exactly as the pre-refactor dock rendered it.
  Widget? _optionDescription(BuildContext context, ReadText description) {
    final value = state.textOf(description);
    if (value == null) return _text(context, description);
    if (value.isEmpty) return null;
    return Text(
      value,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  /// An empty question text renders nothing at all (no 4px gap, no line); a
  /// deferred read keeps its own load action.
  Widget? _questionText(BuildContext context, ReadText text) {
    final value = state.textOf(text);
    if (value == null) return _text(context, text);
    return value.isEmpty ? null : Text(value);
  }

  /// Approval facts render as monospaced chips; a deferred read keeps its own
  /// load action instead of an invented placeholder.
  Widget _label(BuildContext context, ReadText text, IconData icon) {
    final value = state.textOf(text);
    return value == null
        ? _text(context, text)
        : InfoChip(icon: icon, label: value);
  }

  Widget? _toolArguments(BuildContext context, ReadText arguments) {
    final value = state.textOf(arguments);
    if (value == null) return _text(context, arguments);
    return value.isEmpty ? null : InteractionCodeBlock(text: value);
  }

  bool _answered(int index) {
    final draft = state.answers[index];
    return draft != null &&
        (draft.selectedLabels.isNotEmpty || draft.text.trim().isNotEmpty);
  }

  Widget _text(BuildContext context, ReadText text) {
    final value = state.textOf(text);
    if (value != null) return Text(value);
    final deferred = text as DeferredReadText;
    final progress = state.texts[deferred.fieldId];
    return TextButton(
      onPressed: progress?.loading == true
          ? null
          : () => onLoadText(deferred.fieldId).ignore(),
      child: Text(
        '${context.l10n.timelineItemBodyLoad} · ${progress?.loadedUtf8Bytes ?? 0}/${deferred.utf8Bytes} B',
      ),
    );
  }

  Widget _terminal(BuildContext context, InteractionReadHeader header) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header.state case ResolvedApprovalRead(
            :final decision,
            :final reason,
          )) ...[
            Text(decision.name),
            if (reason != null) _text(context, reason),
          ],
          if (header.state case CancelledInteractionRead(:final reason))
            _text(context, reason),
          for (final entry in state.answerEntries) ...[
            _text(context, entry.questionId),
            for (final value
                in state.answerValues[entry.index] ??
                    const <AnswerValueReadItem>[])
              _historicalAnswer(context, entry, value),
            if (state.nextAnswerValueOffsets[entry.index] != null)
              TextButton(
                onPressed: () => onLoadAnswerValues(entry.index).ignore(),
                child: Text(context.l10n.timelineItemBodyLoad),
              ),
          ],
          if (state.nextAnswerEntryOffset != null)
            TextButton(
              onPressed: () => onLoadAnswerEntries().ignore(),
              child: Text(context.l10n.timelineItemBodyLoad),
            ),
        ],
      );

  Widget _historicalAnswer(
    BuildContext context,
    AnswerEntryReadItem entry,
    AnswerValueReadItem answer,
  ) {
    final id = state.textOf(entry.questionId);
    final question = state.questions.values
        .where((q) => state.textOf(q.question.id) == id)
        .firstOrNull;
    // An unmaterialized/unknown question cannot prove its answer is non-secret.
    if (question == null || question.question.isSecret) {
      return const Text('••••');
    }
    return _text(context, answer.value);
  }
}
