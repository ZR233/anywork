import '../../../models.dart';

/// Static, typed reading descriptors. Dynamic values exist only in fields.
sealed class ConversationDescriptor {
  const ConversationDescriptor();
}

final class ConversationTextDescriptor extends ConversationDescriptor {
  const ConversationTextDescriptor({
    required this.channel,
    required this.attachments,
    required this.lifecycle,
  });
  final ThreadTextChannel channel;
  final List<ThreadAttachmentView> attachments;
  final ThreadContentLifecycleView lifecycle;
}

final class ConversationThinkingDescriptor extends ConversationDescriptor {
  const ConversationThinkingDescriptor({required this.lifecycle});
  final ThreadContentLifecycleView lifecycle;
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
  const ConversationRawDescriptor({
    required this.origin,
    required this.payloads,
    required this.notice,
    required this.recordedAt,
  });
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
  const ConversationToolOutputDescriptor({
    required this.attachments,
    this.exitCode,
  });
  final List<ThreadAttachmentView> attachments;
  final int? exitCode;
}

sealed class ConversationToolState {
  const ConversationToolState();
  bool get isTerminal => switch (this) {
    ConversationToolInterrupted() ||
    ConversationToolSucceeded() ||
    ConversationToolFailed() ||
    ConversationToolDenied() ||
    ConversationToolCancelled() => true,
    _ => false,
  };
}

final class ConversationToolQueued extends ConversationToolState {
  const ConversationToolQueued();
}

final class ConversationToolCancelling extends ConversationToolState {
  const ConversationToolCancelling();
}

final class ConversationToolStarted extends ConversationToolState {
  const ConversationToolStarted();
}

final class ConversationToolStreaming extends ConversationToolState {
  const ConversationToolStreaming();
}

final class ConversationToolAwaitingApproval extends ConversationToolState {
  const ConversationToolAwaitingApproval();
}

final class ConversationToolApproved extends ConversationToolState {
  const ConversationToolApproved();
}

final class ConversationToolRunning extends ConversationToolState {
  const ConversationToolRunning();
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
  const ConversationUserInputDescriptor({
    required this.interactionId,
    required this.questions,
    required this.state,
  });
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

final class ConversationUserInputPending extends ConversationUserInputState {
  const ConversationUserInputPending();
}

final class ConversationUserInputCancelled extends ConversationUserInputState {
  const ConversationUserInputCancelled();
}

final class ConversationUserInputResolved extends ConversationUserInputState {
  const ConversationUserInputResolved({required this.answers});
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
  const ConversationAgentDescriptor(this.value);
  final ThreadAgentItemStateView value;
}

final class ConversationTurnDescriptor extends ConversationDescriptor {
  const ConversationTurnDescriptor(this.value);
  final ThreadTurnItemStateView value;
}

final class ConversationInferenceDescriptor extends ConversationDescriptor {
  const ConversationInferenceDescriptor(this.value);
  final ThreadInferenceItemStateView value;
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
