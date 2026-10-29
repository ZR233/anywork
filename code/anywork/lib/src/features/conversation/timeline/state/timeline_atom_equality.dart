import 'package:anywork_client/models.dart';

/// Completion replay equality, including every header, descriptor and preview
/// field. These comparisons borrow payloads; no serialized copy or cache exists.
bool timelineAtomsEqual(ConversationItem left, ConversationItem right) =>
    (
          left.header.id,
          left.header.threadId,
          left.header.turnId,
          left.header.appendSeq,
          left.header.sourceEffectSeq,
          left.header.sealedAt,
        ) ==
        (
          right.header.id,
          right.header.threadId,
          right.header.turnId,
          right.header.appendSeq,
          right.header.sourceEffectSeq,
          right.header.sealedAt,
        ) &&
    switch ((left.source, right.source)) {
      (ConversationContentSource(), ConversationContentSource()) => true,
      (ConversationRecoverySource a, ConversationRecoverySource b) =>
        a.notice == b.notice,
      _ => false,
    } &&
    _list(
      left.fields,
      right.fields,
      (a, b) =>
          (a.field, a.text, a.totalBytes) == (b.field, b.text, b.totalBytes),
    ) &&
    _descriptor(left.descriptor, right.descriptor);

bool _list<T>(List<T> a, List<T> b, bool Function(T, T) equal) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!equal(a[i], b[i])) return false;
  }
  return true;
}

bool _attachments(List<ThreadAttachmentView> a, List<ThreadAttachmentView> b) =>
    _list(
      a,
      b,
      (a, b) =>
          (
            a.id,
            a.modality,
            a.mediaType,
            a.byteSize,
            a.filename,
            a.width,
            a.height,
          ) ==
          (
            b.id,
            b.modality,
            b.mediaType,
            b.byteSize,
            b.filename,
            b.width,
            b.height,
          ),
    );

Object _content(ConversationContentOutcome outcome) => switch (outcome) {
  ConversationContentCompleted(:final value) => (
    ConversationContentCompleted,
    value.completedAt,
  ),
  ConversationContentFailed(:final value) => (
    ConversationContentFailed,
    value.failedAt,
    value.error,
  ),
  ConversationContentCancelled(:final value) => (
    ConversationContentCancelled,
    value.cancelledAt,
    value.reason,
  ),
};

bool _descriptor(ConversationDescriptor a, ConversationDescriptor b) =>
    switch (a) {
      ConversationTextDescriptor() =>
        b is ConversationTextDescriptor &&
            a.channel == b.channel &&
            _content(a.outcome) == _content(b.outcome) &&
            _attachments(a.attachments, b.attachments),
      ConversationThinkingDescriptor() =>
        b is ConversationThinkingDescriptor &&
            _content(a.outcome) == _content(b.outcome),
      ConversationPlanDescriptor() =>
        b is ConversationPlanDescriptor &&
            (a.interactionId, a.documentVersion, a.contentHash, a.decision) ==
                (b.interactionId, b.documentVersion, b.contentHash, b.decision),
      ConversationRawDescriptor() =>
        b is ConversationRawDescriptor &&
            (a.origin, a.notice, a.recordedAt) ==
                (b.origin, b.notice, b.recordedAt) &&
            _list(
              a.payloads,
              b.payloads,
              (a, b) => (a.format, a.version) == (b.format, b.version),
            ),
      ConversationToolDescriptor() =>
        b is ConversationToolDescriptor &&
            _invocation(a.invocation) == _invocation(b.invocation) &&
            _toolState(a.state, b.state) &&
            _userInput(a.userInput, b.userInput) &&
            a.wait == b.wait,
      ConversationAgentDescriptor() =>
        b is ConversationAgentDescriptor &&
            _agentIdentity(a.identity) == _agentIdentity(b.identity) &&
            _agentOutcome(a.outcome) == _agentOutcome(b.outcome),
      ConversationTurnDescriptor() =>
        b is ConversationTurnDescriptor &&
            a.inputId == b.inputId &&
            _turn(a.outcome, b.outcome),
      ConversationInferenceDescriptor() =>
        b is ConversationInferenceDescriptor &&
            (a.inferenceId, a.model) == (b.inferenceId, b.model) &&
            _inference(a.outcome) == _inference(b.outcome),
      ConversationSkillDescriptor() =>
        b is ConversationSkillDescriptor && _skill(a.value) == _skill(b.value),
      ConversationFileDescriptor() =>
        b is ConversationFileDescriptor &&
            (a.value.path, a.value.mediaType, a.value.completedAt) ==
                (b.value.path, b.value.mediaType, b.value.completedAt),
      ConversationContextCompactionDescriptor() =>
        b is ConversationContextCompactionDescriptor &&
            (a.value.beforeTokens, a.value.afterTokens, a.value.compactedAt) ==
                (
                  b.value.beforeTokens,
                  b.value.afterTokens,
                  b.value.compactedAt,
                ),
    };

Object _invocation(ConversationToolInvocation value) => (
  value.toolCallId,
  value.name,
  value.callId,
  value.providerItemId,
  value.workingDirectory,
  value.taskId,
);

bool _output(
  ConversationToolOutputDescriptor? a,
  ConversationToolOutputDescriptor? b,
) {
  if (a == null || b == null) return a == null && b == null;
  return a.exitCode == b.exitCode && _attachments(a.attachments, b.attachments);
}

bool _toolState(ConversationToolState a, ConversationToolState b) =>
    switch (a) {
      ConversationToolBackgroundStarted() =>
        b is ConversationToolBackgroundStarted && a.startedAt == b.startedAt,
      ConversationToolSucceeded() =>
        b is ConversationToolSucceeded &&
            a.completedAt == b.completedAt &&
            _output(a.output, b.output),
      ConversationToolFailed() =>
        b is ConversationToolFailed &&
            (a.failedAt, a.failure.kind, a.failure.message) ==
                (b.failedAt, b.failure.kind, b.failure.message) &&
            _output(a.output, b.output),
      ConversationToolDenied() =>
        b is ConversationToolDenied &&
            (a.deniedAt, a.reason) == (b.deniedAt, b.reason),
      ConversationToolCancelled() =>
        b is ConversationToolCancelled &&
            (a.cancelledAt, a.reason) == (b.cancelledAt, b.reason),
      ConversationToolInterrupted() =>
        b is ConversationToolInterrupted &&
            (a.interruptedAt, a.reason) == (b.interruptedAt, b.reason),
    };

bool _userInput(
  ConversationUserInputDescriptor? a,
  ConversationUserInputDescriptor? b,
) {
  if (a == null || b == null) return a == null && b == null;
  return a.interactionId == b.interactionId &&
      _list(
        a.questions,
        b.questions,
        (a, b) =>
            (a.id, a.isOther, a.isSecret, a.optionCount) ==
            (b.id, b.isOther, b.isSecret, b.optionCount),
      ) &&
      switch ((a.state, b.state)) {
        (ConversationUserInputCancelled(), ConversationUserInputCancelled()) =>
          true,
        (ConversationUserInputResolved a, ConversationUserInputResolved b) =>
          _list(
            a.answers,
            b.answers,
            (a, b) =>
                (a.questionId, a.answerCount, a.redacted) ==
                (b.questionId, b.answerCount, b.redacted),
          ),
        _ => false,
      };
}

Object _agentIdentity(ThreadAgentIdentityView value) => (
  value.id,
  value.path,
  value.parentPath,
  value.role,
  value.task,
  value.depth,
);

Object _agentOutcome(ConversationAgentOutcome value) => switch (value) {
  ConversationAgentSucceeded(:final value) => (
    ConversationAgentSucceeded,
    value.completedAt,
    value.summary,
  ),
  ConversationAgentFailed(:final value) => (
    ConversationAgentFailed,
    value.failedAt,
    value.error,
  ),
  ConversationAgentDenied(:final value) => (
    ConversationAgentDenied,
    value.deniedAt,
    value.reason,
  ),
  ConversationAgentCancelled(:final value) => (
    ConversationAgentCancelled,
    value.cancelledAt,
    value.reason,
  ),
};

bool _turn(ConversationTurnOutcome a, ConversationTurnOutcome b) => switch ((
  a,
  b,
)) {
  (ConversationTurnCompleted a, ConversationTurnCompleted b) =>
    a.value == b.value,
  (ConversationTurnFailed a, ConversationTurnFailed b) => a.value == b.value,
  (ConversationTurnBudgetLimited a, ConversationTurnBudgetLimited b) =>
    (
          a.value.startedAt,
          a.value.completedAt,
          a.value.limit,
          _rollover(a.value.rollover),
        ) ==
        (
          b.value.startedAt,
          b.value.completedAt,
          b.value.limit,
          _rollover(b.value.rollover),
        ),
  (ConversationTurnCancelled a, ConversationTurnCancelled b) =>
    (
          a.value.startedAt,
          a.value.requestedAt,
          a.value.completedAt,
          _cause(a.value.cause),
        ) ==
        (
          b.value.startedAt,
          b.value.requestedAt,
          b.value.completedAt,
          _cause(b.value.cause),
        ),
  _ => false,
};

Object _rollover(StudioTurnRolloverOutcome value) => switch (value) {
  RolloverNotAttempted() => RolloverNotAttempted,
  RolloverSucceeded() => RolloverSucceeded,
  RolloverFailed(:final error) => (RolloverFailed, error),
};

Object _cause(StudioTurnCancellationCause value) => switch (value) {
  UnspecifiedTurnCancellation() => UnspecifiedTurnCancellation,
  UserRequestedTurnCancellation() => UserRequestedTurnCancellation,
  RuntimeShutdownTurnCancellation() => RuntimeShutdownTurnCancellation,
  AgentClosedTurnCancellation() => AgentClosedTurnCancellation,
  InterruptedTurnCancellation() => InterruptedTurnCancellation,
  RecoveryTurnCancellation() => RecoveryTurnCancellation,
  CoalescedTurnCancellation(:final targetTurnId) => (
    CoalescedTurnCancellation,
    targetTurnId,
  ),
};

Object _inference(ConversationInferenceOutcome outcome) => switch (outcome) {
  ConversationInferenceCompleted(:final value) => (
    ConversationInferenceCompleted,
    value.completedAt,
    value.usage.promptTokens,
    value.usage.completionTokens,
    value.usage.cachedPromptTokens,
    value.usage.totalTokens,
  ),
  ConversationInferenceFailed(:final value) => (
    ConversationInferenceFailed,
    value.failedAt,
    value.error,
  ),
  ConversationInferenceCancelled(:final value) => (
    ConversationInferenceCancelled,
    value.cancelledAt,
    value.reason,
  ),
};

Object _skill(ThreadSkillItemStateView value) => (
  value.name,
  value.source,
  value.providerId,
  value.resourceBase.kind,
  value.resourceBase.value,
  value.cause.kind,
  value.cause.id,
  value.activatedAt,
);
