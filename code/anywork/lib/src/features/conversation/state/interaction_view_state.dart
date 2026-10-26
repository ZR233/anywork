import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'editor_keys.dart';
import 'read_progress.dart';

export 'read_progress.dart';

part 'interaction_view_state.freezed.dart';

enum InteractionReadSection {
  header,
  questions,
  options,
  answerEntries,
  answerValues,
  text,
}

enum InteractionSubmitBlock {
  readIncomplete,
  readFailed,
  sourceChanged,
  noLongerPending,
  operationPending,
  unknownOutcome,
  closing,
  disabled,
}

@Freezed(toStringOverride: false)
abstract class QuestionReadProgress with _$QuestionReadProgress {
  const factory QuestionReadProgress({
    required QuestionReadItem question,
    @Default([]) List<OptionReadItem> options,
    int? nextOptionOffset,
    @Default(false) bool optionsLoading,
    StudioFailure? optionsError,
  }) = _QuestionReadProgress;
}

@Freezed(toStringOverride: false)
abstract class QuestionAnswerDraft with _$QuestionAnswerDraft {
  const factory QuestionAnswerDraft({
    @Default([]) List<String> selectedLabels,
    @Default('') String text,
  }) = _QuestionAnswerDraft;
}

@Freezed(toStringOverride: false)
abstract class InteractionReadIssue with _$InteractionReadIssue {
  const factory InteractionReadIssue({
    required InteractionReadSection section,
    int? index,
    int? fieldId,
    required StudioFailure error,
  }) = _InteractionReadIssue;
}

@Freezed(toStringOverride: false)
abstract class InteractionViewState with _$InteractionViewState {
  const InteractionViewState._();
  const factory InteractionViewState({
    required InteractionEditorKey key,
    ReadScopeIdentity? scope,
    InteractionReadHeader? header,
    @Default({}) Map<int, QuestionReadProgress> questions,
    int? nextQuestionOffset,
    @Default([]) List<AnswerEntryReadItem> answerEntries,
    int? nextAnswerEntryOffset,
    @Default(false) bool answerEntriesLoading,
    @Default({}) Map<int, List<AnswerValueReadItem>> answerValues,
    @Default({}) Map<int, int?> nextAnswerValueOffsets,
    @Default({}) Set<int> answerValueLoading,
    @Default({}) Map<int, TextReadProgress> texts,
    @Default(0) int currentQuestionIndex,
    @Default(false) bool questionPageLoading,
    @Default([]) List<InteractionReadIssue> readIssues,
    @Default(false) bool completingRead,
    @Default({}) Map<int, QuestionAnswerDraft> answers,
    @Default('') String fallbackText,
    @Default('') String approvalReason,
    @Default('') String planFeedback,
    @Default(true) bool enabled,
    @Default(false) bool sourceCurrent,
    @Default(false) bool closing,
    @Default(0) int latestIntent,
    OperationState? submission,
    InteractionSubmitBlock? submitBlock,
    StudioFailure? submissionError,
  }) = _InteractionViewState;

  String? textOf(ReadText? value) => switch (value) {
    null => null,
    InlineReadText(:final text) => text,
    DeferredReadText(:final fieldId) =>
      texts[fieldId]?.complete == true ? texts[fieldId]!.text : null,
  };

  // Preserve even whitespace-only raw edits until an explicit discard. This is
  // presentation dirtiness, not answer completeness or response admission.
  bool get hasDraftEdits =>
      fallbackText.isNotEmpty ||
      approvalReason.isNotEmpty ||
      planFeedback.isNotEmpty ||
      answers.values.any(
        (answer) => answer.text.isNotEmpty || answer.selectedLabels.isNotEmpty,
      );
  bool get canCloseEditor =>
      !closing &&
      submission?.isPending != true &&
      submission?.failurePhase != OperationFailurePhase.unknownOutcome;
}
