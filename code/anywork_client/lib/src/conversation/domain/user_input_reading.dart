import 'dart:convert';

import '../../../models.dart';

const int _maxImageCardCaptionRunes = 240;
const String _planSubmitToolName = 'plan_submit';

String? _completeKnownToolStringArgument(
  ConversationItem item, {
  required String toolName,
  required String argumentName,
}) {
  final descriptor = item.descriptor;
  if (descriptor is! ConversationToolDescriptor ||
      descriptor.invocation.name != toolName) {
    return null;
  }
  final arguments = item.fieldFor(const ThreadToolArgumentsFieldView());
  if (arguments == null || arguments.previewBytes != arguments.totalBytes) {
    return null;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(arguments.text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final value = decoded[argumentName];
  return value is String ? value : null;
}

/// Presentation facts derived from the same typed descriptor/field source.
/// No reconstructed persisted item or raw JSON recovery model is involved.
extension ConversationUserInputReading on ConversationItem {
  /// Optional display caption for the known `show_image` tool schema.
  ///
  /// This derives only from the current bounded arguments preview. It does not
  /// read details, inspect outputs or expose a general raw-JSON interface.
  String? get imageCardCaption {
    final rawCaption = _completeKnownToolStringArgument(
      this,
      toolName: 'show_image',
      argumentName: 'caption',
    );
    if (rawCaption == null) return null;
    final caption = rawCaption.trim();
    if (caption.isEmpty) return null;
    final runes = caption.runes;
    return runes.length <= _maxImageCardCaptionRunes
        ? caption
        : String.fromCharCodes(runes.take(_maxImageCardCaptionRunes));
  }

  ConversationUserInputDescriptor? get userInput => switch (descriptor) {
    ConversationToolDescriptor(:final userInput) => userInput,
    _ => null,
  };

  String? userInputText(int questionIndex, ThreadUserInputFieldPartView part) =>
      fieldFor(
        ThreadToolUserInputFieldView(questionIndex: questionIndex, part: part),
      )?.text;

  PlanConfirmationReceiptView? get planReceipt {
    final tool = descriptor;
    if (tool is! ConversationToolDescriptor ||
        tool.invocation.name != _planSubmitToolName) {
      return null;
    }
    final input = tool.userInput;
    if (input == null ||
        input.questions.length != 1 ||
        input.questions.single.id != agentSessionPlanConfirmationQuestionId)
      return null;
    final question = input.questions.single;
    final answer = switch (input.state) {
      ConversationUserInputResolved(:final answers) =>
        answers.where((value) => value.questionId == question.id).firstOrNull,
      _ => null,
    };
    final values = <String>[
      if (answer != null && !answer.redacted && !question.isSecret)
        for (var index = 0; index < answer.answerCount; index++)
          if (userInputText(0, ThreadUserInputAnswerFieldPartView(index))
              case final text?)
            text,
    ];
    final decision = switch (input.state) {
      ConversationUserInputPending() => PlanConfirmationDecisionView.pending,
      ConversationUserInputCancelled() =>
        PlanConfirmationDecisionView.cancelled,
      ConversationUserInputResolved() =>
        values.contains(agentSessionPlanApproveAnswer)
            ? PlanConfirmationDecisionView.approved
            : values.contains(agentSessionPlanReviseAnswer)
            ? PlanConfirmationDecisionView.revisionRequested
            : PlanConfirmationDecisionView.resolved,
    };
    return PlanConfirmationReceiptView(
      interactionId: input.interactionId,
      title: planDocumentTitle(
        userInputText(0, const ThreadUserInputQuestionFieldPartView()) ?? '',
        fallback:
            userInputText(0, const ThreadUserInputHeaderFieldPartView()) ?? '',
      ),
      decision: decision,
      feedback: decision == PlanConfirmationDecisionView.revisionRequested
          ? values.where(
              (value) =>
                  value != agentSessionPlanApproveAnswer &&
                  value != agentSessionPlanReviseAnswer &&
                  value.trim().isNotEmpty,
            )
          : const [],
    );
  }
}
