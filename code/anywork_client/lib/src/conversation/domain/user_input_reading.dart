import 'dart:convert';

import '../../../models.dart';

const int _maxImageCardCaptionRunes = 240;

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
    final plan = descriptor;
    if (plan is! ConversationPlanDescriptor) return null;
    final document = fieldFor(const ThreadPlanDocumentFieldView())?.text ?? '';
    final feedback = fieldFor(const ThreadPlanFeedbackFieldView())?.text;
    final decision = switch (plan.decision) {
      ConversationPlanDecision.approved =>
        PlanConfirmationDecisionView.approved,
      ConversationPlanDecision.revisionRequested =>
        PlanConfirmationDecisionView.revisionRequested,
      ConversationPlanDecision.cancelled =>
        PlanConfirmationDecisionView.cancelled,
      ConversationPlanDecision.resolved =>
        PlanConfirmationDecisionView.resolved,
    };
    return PlanConfirmationReceiptView(
      interactionId: plan.interactionId,
      title: planDocumentTitle(document, fallback: ''),
      decision: decision,
      feedback: feedback == null ? const [] : [feedback],
    );
  }
}
