import '../../../models.dart';

/// Static, typed reading descriptors. Dynamic values exist only in fields.
sealed class ConversationDescriptor {
  const ConversationDescriptor();
}

/// The decision sealed into this historical Plan, not the current live Plan.
enum ConversationPlanDecision {
  approved,
  revisionRequested,
  cancelled,
  resolved,
}

final class ConversationPlanDescriptor extends ConversationDescriptor {
  const ConversationPlanDescriptor({
    required this.interactionId,
    required this.decision,
    this.documentVersion,
    this.contentHash,
  });

  final String interactionId;
  final int? documentVersion;
  final String? contentHash;
  final ConversationPlanDecision decision;
}

final class ConversationTextDescriptor extends ConversationDescriptor {
  ConversationTextDescriptor({
    required this.channel,
    required List<ThreadAttachmentView> attachments,
    required this.outcome,
  }) : attachments = List.unmodifiable(attachments);
  final ThreadTextChannel channel;
  final List<ThreadAttachmentView> attachments;
  final ConversationContentOutcome outcome;
}

final class ConversationThinkingDescriptor extends ConversationDescriptor {
  const ConversationThinkingDescriptor({required this.outcome});
  final ConversationContentOutcome outcome;
}

sealed class ConversationContentOutcome {
  const ConversationContentOutcome();
}

final class ConversationContentCompleted extends ConversationContentOutcome {
  const ConversationContentCompleted(this.value);
  final CompletedThreadContentView value;
}

final class ConversationContentFailed extends ConversationContentOutcome {
  const ConversationContentFailed(this.value);
  final FailedThreadContentView value;
}

final class ConversationContentCancelled extends ConversationContentOutcome {
  const ConversationContentCancelled(this.value);
  final CancelledThreadContentView value;
}

final class ConversationRawPayloadDescriptor {
  const ConversationRawPayloadDescriptor({
    required this.format,
    required this.version,
  });
  final String format;
  final int version;
}

final class ConversationRawDescriptor extends ConversationDescriptor {
  ConversationRawDescriptor({
    required this.origin,
    required List<ConversationRawPayloadDescriptor> payloads,
    required this.notice,
    required this.recordedAt,
  }) : payloads = List.unmodifiable(payloads);
  final ThreadRawItemOrigin origin;
  final List<ConversationRawPayloadDescriptor> payloads;
  final String notice;
  final DateTime recordedAt;
}

final class ConversationToolDescriptor extends ConversationDescriptor {
  const ConversationToolDescriptor({
    required this.invocation,
    required this.state,
    this.userInput,
    this.wait,
  });
  final ConversationToolInvocation invocation;
  final ConversationToolState state;
  final ConversationUserInputDescriptor? userInput;
  final ThreadWaitPresentationView? wait;
}

final class ConversationToolInvocation {
  const ConversationToolInvocation({
    required this.toolCallId,
    required this.name,
    this.callId,
    this.providerItemId,
    this.workingDirectory,
    this.taskId,
  });
  final String toolCallId;
  final String name;
  final String? callId;
  final String? providerItemId;
  final String? workingDirectory;
  final String? taskId;
}

final class ConversationToolOutputDescriptor {
  ConversationToolOutputDescriptor({
    required List<ThreadAttachmentView> attachments,
    this.exitCode,
  }) : attachments = List.unmodifiable(attachments);
  final List<ThreadAttachmentView> attachments;
  final int? exitCode;
}

sealed class ConversationToolState {
  const ConversationToolState();
}

final class ConversationToolBackgroundStarted extends ConversationToolState {
  const ConversationToolBackgroundStarted({required this.startedAt});
  final DateTime startedAt;
}

final class ConversationToolInterrupted extends ConversationToolState {
  const ConversationToolInterrupted({
    required this.interruptedAt,
    required this.reason,
  });
  final DateTime interruptedAt;
  final String reason;
}

final class ConversationToolSucceeded extends ConversationToolState {
  const ConversationToolSucceeded({
    required this.completedAt,
    required this.output,
  });
  final DateTime completedAt;
  final ConversationToolOutputDescriptor output;
}

final class ConversationToolFailed extends ConversationToolState {
  const ConversationToolFailed({
    required this.failedAt,
    required this.failure,
    this.output,
  });
  final DateTime failedAt;
  final ThreadToolFailureView failure;
  final ConversationToolOutputDescriptor? output;
}

final class ConversationToolDenied extends ConversationToolState {
  const ConversationToolDenied({required this.deniedAt, required this.reason});
  final DateTime deniedAt;
  final String reason;
}

final class ConversationToolCancelled extends ConversationToolState {
  const ConversationToolCancelled({
    required this.cancelledAt,
    required this.reason,
  });
  final DateTime cancelledAt;
  final String reason;
}

final class ConversationUserInputDescriptor {
  ConversationUserInputDescriptor({
    required this.interactionId,
    required List<ConversationQuestionDescriptor> questions,
    required this.state,
  }) : questions = List.unmodifiable(questions);
  final String interactionId;
  final List<ConversationQuestionDescriptor> questions;
  final ConversationUserInputState state;
}

final class ConversationQuestionDescriptor {
  const ConversationQuestionDescriptor({
    required this.id,
    required this.isOther,
    required this.isSecret,
    this.optionCount,
  });
  final String id;
  final bool isOther;
  final bool isSecret;
  final int? optionCount;
}

sealed class ConversationUserInputState {
  const ConversationUserInputState();
}

final class ConversationUserInputCancelled extends ConversationUserInputState {
  const ConversationUserInputCancelled();
}

final class ConversationUserInputResolved extends ConversationUserInputState {
  ConversationUserInputResolved({
    required List<ConversationAnswerDescriptor> answers,
  }) : answers = List.unmodifiable(answers);
  final List<ConversationAnswerDescriptor> answers;
}

final class ConversationAnswerDescriptor {
  const ConversationAnswerDescriptor({
    required this.questionId,
    required this.answerCount,
    required this.redacted,
  });
  final String questionId;
  final int answerCount;
  final bool redacted;
}

final class ConversationAgentDescriptor extends ConversationDescriptor {
  const ConversationAgentDescriptor({
    required this.identity,
    required this.outcome,
  });
  final ThreadAgentIdentityView identity;
  final ConversationAgentOutcome outcome;
}

sealed class ConversationAgentOutcome {
  const ConversationAgentOutcome();
}

final class ConversationAgentSucceeded extends ConversationAgentOutcome {
  const ConversationAgentSucceeded(this.value);
  final SucceededThreadAgentView value;
}

final class ConversationAgentDenied extends ConversationAgentOutcome {
  const ConversationAgentDenied(this.value);
  final DeniedThreadAgentView value;
}

final class ConversationAgentCancelled extends ConversationAgentOutcome {
  const ConversationAgentCancelled(this.value);
  final CancelledThreadAgentView value;
}

final class ConversationAgentFailed extends ConversationAgentOutcome {
  const ConversationAgentFailed(this.value);
  final FailedThreadAgentView value;
}

final class ConversationTurnDescriptor extends ConversationDescriptor {
  const ConversationTurnDescriptor({this.inputId, required this.outcome});
  final String? inputId;
  final ConversationTurnOutcome outcome;
}

sealed class ConversationTurnOutcome {
  const ConversationTurnOutcome();
}

final class ConversationTurnCompleted extends ConversationTurnOutcome {
  const ConversationTurnCompleted(this.value);
  final CompletedStudioTurnState value;
}

final class ConversationTurnFailed extends ConversationTurnOutcome {
  const ConversationTurnFailed(this.value);
  final FailedStudioTurnState value;
}

final class ConversationTurnCancelled extends ConversationTurnOutcome {
  const ConversationTurnCancelled(this.value);
  final CancelledStudioTurnState value;
}

final class ConversationTurnBudgetLimited extends ConversationTurnOutcome {
  const ConversationTurnBudgetLimited(this.value);
  final BudgetLimitedStudioTurnState value;
}

final class ConversationInferenceDescriptor extends ConversationDescriptor {
  const ConversationInferenceDescriptor({
    required this.inferenceId,
    required this.model,
    required this.outcome,
  });
  final String inferenceId;
  final String model;
  final ConversationInferenceOutcome outcome;
}

sealed class ConversationInferenceOutcome {
  const ConversationInferenceOutcome();
}

final class ConversationInferenceCompleted
    extends ConversationInferenceOutcome {
  const ConversationInferenceCompleted(this.value);
  final CompletedThreadInferenceView value;
}

final class ConversationInferenceFailed extends ConversationInferenceOutcome {
  const ConversationInferenceFailed(this.value);
  final FailedThreadInferenceView value;
}

final class ConversationInferenceCancelled
    extends ConversationInferenceOutcome {
  const ConversationInferenceCancelled(this.value);
  final CancelledThreadInferenceView value;
}

final class ConversationSkillDescriptor extends ConversationDescriptor {
  const ConversationSkillDescriptor(this.value);
  final ThreadSkillItemStateView value;
}

final class ConversationFileDescriptor extends ConversationDescriptor {
  const ConversationFileDescriptor(this.value);
  final ThreadFileItemStateView value;
}

final class ConversationContextCompactionDescriptor
    extends ConversationDescriptor {
  const ConversationContextCompactionDescriptor(this.value);
  final ThreadContextCompactionItemStateView value;
}
