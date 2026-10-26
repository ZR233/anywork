import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import '../state/interaction_view_state.dart';

/// Completeness is read admission, not a new requirement to answer every row.
InteractionSubmitBlock? interactionSubmitBlock(InteractionViewState state) {
  if (state.closing) return InteractionSubmitBlock.closing;
  if (!state.enabled) return InteractionSubmitBlock.disabled;
  if (!state.sourceCurrent) return InteractionSubmitBlock.sourceChanged;
  if (state.submission?.failurePhase == OperationFailurePhase.unknownOutcome) {
    return InteractionSubmitBlock.unknownOutcome;
  }
  if (state.submission?.isPending == true) {
    return InteractionSubmitBlock.operationPending;
  }
  // The pinned editor may still show Pending after the command is observed.
  // A confirmed decision is never permission to send the same response twice.
  if (state.submission?.receipt != null ||
      state.submission?.acknowledged == true) {
    return InteractionSubmitBlock.noLongerPending;
  }
  final header = state.header;
  if (header == null) return InteractionSubmitBlock.readIncomplete;
  if (state.key.isHosted && header.purpose is PlanConfirmationPurposeRead) {
    return InteractionSubmitBlock.disabled;
  }
  if (header.state is! PendingInteractionRead) {
    return InteractionSubmitBlock.noLongerPending;
  }
  if (state.readIssues.isNotEmpty ||
      state.texts.values.any((text) => text.error != null) ||
      state.questions.values.any((question) => question.optionsError != null)) {
    return InteractionSubmitBlock.readFailed;
  }
  final fields = requiredInteractionTexts(state);
  if (fields.any((field) => state.textOf(field) == null)) {
    return InteractionSubmitBlock.readIncomplete;
  }
  if (state.textOf(header.interactionId) != state.key.interactionId ||
      state.textOf(header.threadId) != state.key.target ||
      header.revision != state.key.revision ||
      header.scope.runtimeEpoch != state.key.runtimeEpoch ||
      header.scope.incarnation != state.key.incarnation) {
    return InteractionSubmitBlock.sourceChanged;
  }
  final content = header.content;
  if (content is UserInputContentRead) {
    if (state.questions.length != content.questionCount ||
        state.nextQuestionOffset != null) {
      return InteractionSubmitBlock.readIncomplete;
    }
    for (var index = 0; index < content.questionCount; index++) {
      final progress = state.questions[index];
      if (progress == null ||
          progress.nextOptionOffset != null ||
          progress.optionsLoading ||
          progress.options.length != (progress.question.optionsCount ?? 0)) {
        return InteractionSubmitBlock.readIncomplete;
      }
    }
  }
  return null;
}

Iterable<ReadText> requiredInteractionTexts(InteractionViewState state) sync* {
  final header = state.header;
  if (header == null) return;
  yield header.interactionId;
  yield header.threadId;
  yield header.turnId;
  if (header.itemId case final item?) yield item;
  if (header.toolId case final tool?) yield tool;
  if (header.agentPath case final path?) yield path;
  switch (header.purpose) {
    case GeneralInteractionPurposeRead():
      break;
    case PlanConfirmationPurposeRead(
      :final operationId,
      :final argumentHash,
      :final planHash,
    ):
      yield operationId;
      yield argumentHash;
      yield planHash;
  }
  switch (header.continuation) {
    case QuestionContinuationRead(:final questionId):
      yield questionId;
    case ResolutionContinuationRead() || null:
      break;
  }
  switch (header.content) {
    case ToolApprovalContentRead(
      :final name,
      :final arguments,
      :final workingDirectory,
      :final parentAgentId,
    ):
      yield name;
      yield arguments;
      if (workingDirectory != null) yield workingDirectory;
      if (parentAgentId != null) yield parentAgentId;
    case UserInputContentRead():
      break;
  }
  switch (header.state) {
    case PendingInteractionRead(:final operationId) ||
        ResolvedUserInputRead(:final operationId) ||
        ExpiredInteractionRead(:final operationId):
      yield operationId;
    case ResolvedApprovalRead(:final operationId, :final reason):
      yield operationId;
      if (reason != null) yield reason;
    case CancelledInteractionRead(:final operationId, :final reason):
      yield operationId;
      yield reason;
  }
  for (final progress in state.questions.values) {
    yield progress.question.id;
    yield progress.question.header;
    yield progress.question.question;
    for (final option in progress.options) {
      yield option.label;
      yield option.description;
    }
  }
}

List<UserInputAnswerCommand> answersForSubmission(InteractionViewState state) {
  final content = state.header!.content as UserInputContentRead;
  if (content.questionCount == 0) {
    final text = state.fallbackText.trim();
    if (text.isEmpty) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Enter an answer',
        retryable: false,
        correlationId: 'interaction-empty-fallback',
      );
    }
    return [
      UserInputAnswerCommand(questionId: 'answer', answers: [text]),
    ];
  }
  return [
    for (var index = 0; index < content.questionCount; index++)
      _questionAnswer(state, index),
  ];
}

UserInputAnswerCommand _questionAnswer(InteractionViewState state, int index) {
  final progress = state.questions[index]!;
  final rawId = state.textOf(progress.question.id)!;
  final draft = state.answers[index] ?? const QuestionAnswerDraft();
  final permitted = {
    for (final option in progress.options) state.textOf(option.label)!,
  };
  final selected = <String>[];
  for (final label in draft.selectedLabels) {
    if (permitted.contains(label) && !selected.contains(label)) {
      selected.add(label);
    }
  }
  final free = draft.text.trim();
  if ((progress.question.isOther || progress.options.isEmpty) &&
      free.isNotEmpty) {
    selected.add(free);
  }
  return UserInputAnswerCommand(
    // Preserve nonblank canonical IDs byte-for-byte, including surrounding space.
    questionId: rawId.trim().isEmpty ? 'answer_$index' : rawId,
    answers: selected,
  );
}
