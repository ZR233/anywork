import 'package:freezed_annotation/freezed_annotation.dart';

import 'thread_content_fields.dart';

part 'thread_content_questions.freezed.dart';

const agentSessionPlanConfirmationQuestionId = 'plan_confirmation';
const agentSessionPlanApproveAnswer = 'Approve';
const agentSessionPlanReviseAnswer = 'Revise';

@Freezed(toStringOverride: false)
abstract class UserQuestionOptionView with _$UserQuestionOptionView {
  const factory UserQuestionOptionView({
    required String label,
    required String description,
  }) = _UserQuestionOptionView;
}

@Freezed(toStringOverride: false)
final class UserQuestionView with _$UserQuestionView {
  UserQuestionView({
    required this.id,
    required this.header,
    required this.question,
    required this.isOther,
    required this.isSecret,
    required List<UserQuestionOptionView> options,
  }) : options = List.unmodifiable(options);
  final String id;
  final String header;
  final String question;
  final bool isOther;
  final bool isSecret;
  // The Timeline history projection has a concrete list. Interaction reads keep
  // None/Some(0) separately in their own QuestionReadItem.optionsCount.
  final List<UserQuestionOptionView> options;
}

@Freezed(toStringOverride: false)
final class ThreadUserInputAnswerView with _$ThreadUserInputAnswerView {
  ThreadUserInputAnswerView({
    required this.questionId,
    List<String> answers = const [],
    this.redacted = false,
  }) : answers = List.unmodifiable(answers);
  final String questionId;
  final List<String> answers;
  final bool redacted;
  ThreadUserInputAnswerView withAnswers(List<String> values) =>
      copyWith(answers: values);
  ThreadUserInputAnswerView withAnswer(int index, String text) {
    if (redacted || index < 0 || index >= answers.length) return this;
    final next = [...answers];
    next[index] = text;
    return withAnswers(next);
  }
}

@Freezed(toStringOverride: false)
sealed class ThreadToolUserInputStateView with _$ThreadToolUserInputStateView {
  const ThreadToolUserInputStateView._();
  const factory ThreadToolUserInputStateView.pending() =
      PendingThreadToolUserInputView;
  factory ThreadToolUserInputStateView.resolved(
    List<ThreadUserInputAnswerView> answers,
  ) = ResolvedThreadToolUserInputView;
  const factory ThreadToolUserInputStateView.cancelled() =
      CancelledThreadToolUserInputView;
}

@Freezed(toStringOverride: false)
final class ResolvedThreadToolUserInputView extends ThreadToolUserInputStateView
    with _$ResolvedThreadToolUserInputView {
  ResolvedThreadToolUserInputView(List<ThreadUserInputAnswerView> answers)
    : answers = List.unmodifiable(answers),
      super._();
  final List<ThreadUserInputAnswerView> answers;
}

@Freezed(toStringOverride: false)
final class ThreadToolUserInputView with _$ThreadToolUserInputView {
  ThreadToolUserInputView({
    required this.interactionId,
    required List<UserQuestionView> questions,
    required this.state,
  }) : questions = List.unmodifiable(questions);
  final String interactionId;
  final List<UserQuestionView> questions;
  final ThreadToolUserInputStateView state;
  bool get isResolved => state is ResolvedThreadToolUserInputView;
  List<ThreadUserInputAnswerView> get answers => switch (state) {
    ResolvedThreadToolUserInputView(:final answers) => answers,
    _ => const [],
  };
  UserQuestionView? questionAt(int index) =>
      index >= 0 && index < questions.length ? questions[index] : null;
  int? questionIndex(String id) {
    for (var i = 0; i < questions.length; i++) {
      if (questions[i].id == id) return i;
    }
    return null;
  }

  ThreadUserInputAnswerView? answerAt(int index) {
    final question = questionAt(index);
    if (question == null) return null;
    for (final answer in answers) {
      if (answer.questionId == question.id) return answer;
    }
    return null;
  }

  String headerText(int index) => questionAt(index)?.header ?? '';
  String questionText(int index) => questionAt(index)?.question ?? '';
  String optionLabel(int index, int option) {
    final values = questionAt(index)?.options;
    return values != null && option >= 0 && option < values.length
        ? values[option].label
        : '';
  }

  String optionDescription(int index, int option) {
    final values = questionAt(index)?.options;
    return values != null && option >= 0 && option < values.length
        ? values[option].description
        : '';
  }

  String answerText(int index, int answerIndex) {
    final answer = answerAt(index);
    if (answer == null ||
        answer.redacted ||
        answerIndex < 0 ||
        answerIndex >= answer.answers.length)
      return '';
    return answer.answers[answerIndex];
  }

  ThreadToolUserInputView withText(
    int index,
    ThreadUserInputFieldPartView part,
    String text,
  ) {
    final question = questionAt(index);
    if (question == null) return this;
    var nextQuestion = question;
    switch (part) {
      case ThreadUserInputHeaderFieldPartView():
        nextQuestion = question.copyWith(header: text);
      case ThreadUserInputQuestionFieldPartView():
        nextQuestion = question.copyWith(question: text);
      case ThreadUserInputOptionLabelFieldPartView(:final optionIndex):
        if (optionIndex < 0 || optionIndex >= question.options.length)
          return this;
        final options = [...question.options];
        options[optionIndex] = options[optionIndex].copyWith(label: text);
        nextQuestion = question.copyWith(options: options);
      case ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex):
        if (optionIndex < 0 || optionIndex >= question.options.length)
          return this;
        final options = [...question.options];
        options[optionIndex] = options[optionIndex].copyWith(description: text);
        nextQuestion = question.copyWith(options: options);
      case ThreadUserInputAnswerFieldPartView(:final answerIndex):
        if (!isResolved) return this;
        return copyWith(
          state: ResolvedThreadToolUserInputView([
            for (final answer in answers)
              answer.questionId == question.id
                  ? answer.withAnswer(answerIndex, text)
                  : answer,
          ]),
        );
    }
    final next = [...questions];
    next[index] = nextQuestion;
    return copyWith(questions: next);
  }

  ThreadToolUserInputView withTextsFrom(ThreadToolUserInputView previous) {
    var next = this;
    for (var index = 0; index < questions.length; index++) {
      if (previous.questionAt(index)?.id != questions[index].id) continue;
      next = next
          .withText(
            index,
            const ThreadUserInputHeaderFieldPartView(),
            previous.headerText(index),
          )
          .withText(
            index,
            const ThreadUserInputQuestionFieldPartView(),
            previous.questionText(index),
          );
      for (var option = 0; option < questions[index].options.length; option++) {
        next = next
            .withText(
              index,
              ThreadUserInputOptionLabelFieldPartView(option),
              previous.optionLabel(index, option),
            )
            .withText(
              index,
              ThreadUserInputOptionDescriptionFieldPartView(option),
              previous.optionDescription(index, option),
            );
      }
    }
    for (final answer in previous.answers) {
      if (answer.redacted) continue;
      final index = next.questionIndex(answer.questionId);
      if (index == null) continue;
      for (var value = 0; value < answer.answers.length; value++) {
        next = next.withText(
          index,
          ThreadUserInputAnswerFieldPartView(value),
          answer.answers[value],
        );
      }
    }
    return next;
  }
}

enum PlanConfirmationDecisionView {
  pending,
  approved,
  revisionRequested,
  cancelled,
  resolved,
}

@Freezed(toStringOverride: false)
final class PlanConfirmationReceiptView with _$PlanConfirmationReceiptView {
  PlanConfirmationReceiptView({
    required this.interactionId,
    required this.title,
    required this.decision,
    Iterable<String> feedback = const [],
  }) : feedback = List.unmodifiable(feedback);
  final String interactionId;
  final String title;
  final PlanConfirmationDecisionView decision;
  final List<String> feedback;
  bool get isResolved => decision != PlanConfirmationDecisionView.pending;
}

extension ThreadToolUserInputPlanReceipt on ThreadToolUserInputView {
  PlanConfirmationReceiptView? get planReceipt {
    if (questions.length != 1 ||
        questions.single.id != agentSessionPlanConfirmationQuestionId)
      return null;
    final question = questions.single;
    final answer = answerAt(0);
    final decision = switch (state) {
      PendingThreadToolUserInputView() => PlanConfirmationDecisionView.pending,
      CancelledThreadToolUserInputView() =>
        PlanConfirmationDecisionView.cancelled,
      ResolvedThreadToolUserInputView() =>
        answer?.answers.contains(agentSessionPlanApproveAnswer) == true
            ? PlanConfirmationDecisionView.approved
            : answer?.answers.contains(agentSessionPlanReviseAnswer) == true
            ? PlanConfirmationDecisionView.revisionRequested
            : PlanConfirmationDecisionView.resolved,
    };
    return PlanConfirmationReceiptView(
      interactionId: interactionId,
      title: planDocumentTitle(question.question, fallback: question.header),
      decision: decision,
      feedback:
          answer == null ||
              answer.redacted ||
              question.isSecret ||
              decision != PlanConfirmationDecisionView.revisionRequested
          ? const []
          : [
              for (final text in answer.answers)
                if (text != agentSessionPlanApproveAnswer &&
                    text != agentSessionPlanReviseAnswer &&
                    text.trim().isNotEmpty)
                  text,
            ],
    );
  }
}

String planDocumentTitle(String markdown, {String fallback = ''}) {
  for (final line in markdown.split('\n')) {
    final value = line.trim();
    if (value.startsWith('# ') && value.substring(2).trim().isNotEmpty)
      return value.substring(2).trim();
  }
  return fallback.trim();
}
