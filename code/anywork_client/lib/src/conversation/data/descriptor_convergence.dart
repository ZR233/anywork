import '../../../models.dart';
import '../domain/content_lifecycle.dart';

Never _conflict() => throw const ConversationContinuityError(
  'same revision typed descriptors conflict',
);
bool _list<T>(List<T> a, List<T> b, bool Function(T, T) equal) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => equal(a[i], b[i]));
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
bool _content(ThreadContentLifecycleView a, ThreadContentLifecycleView b) =>
    switch (a) {
      StreamingThreadContentView() => b is StreamingThreadContentView,
      CompletedThreadContentView() =>
        b is CompletedThreadContentView && a.completedAt == b.completedAt,
      FailedThreadContentView() =>
        b is FailedThreadContentView &&
            (a.failedAt, a.error) == (b.failedAt, b.error),
      CancelledThreadContentView() =>
        b is CancelledThreadContentView &&
            (a.cancelledAt, a.reason) == (b.cancelledAt, b.reason),
    };

bool _output(
  ConversationToolOutputDescriptor? a,
  ConversationToolOutputDescriptor? b,
) => a == null
    ? b == null
    : b != null &&
          a.exitCode == b.exitCode &&
          _attachments(a.attachments, b.attachments);
bool _tool(ConversationToolState a, ConversationToolState b) => switch (a) {
  ConversationToolQueued() => b is ConversationToolQueued,
  ConversationToolCancelling() => b is ConversationToolCancelling,
  ConversationToolStarted() => b is ConversationToolStarted,
  ConversationToolStreaming() => b is ConversationToolStreaming,
  ConversationToolAwaitingApproval() => b is ConversationToolAwaitingApproval,
  ConversationToolApproved() => b is ConversationToolApproved,
  ConversationToolRunning() => b is ConversationToolRunning,
  ConversationToolInterrupted() =>
    b is ConversationToolInterrupted &&
        (a.interruptedAt, a.reason) == (b.interruptedAt, b.reason),
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
};
bool _questions(
  ConversationUserInputDescriptor? a,
  ConversationUserInputDescriptor? b,
) => a == null
    ? b == null
    : b != null &&
          a.interactionId == b.interactionId &&
          _list(
            a.questions,
            b.questions,
            (a, b) =>
                (a.id, a.isOther, a.isSecret, a.optionCount) ==
                (b.id, b.isOther, b.isSecret, b.optionCount),
          );
bool _answers(
  ConversationUserInputDescriptor? a,
  ConversationUserInputDescriptor? b,
) {
  if (a == null || b == null) return a == b;
  final state = a.state;
  final other = b.state;
  return switch (state) {
    ConversationUserInputPending() => other is ConversationUserInputPending,
    ConversationUserInputCancelled() => other is ConversationUserInputCancelled,
    ConversationUserInputResolved() =>
      other is ConversationUserInputResolved &&
          _list(
            state.answers,
            other.answers,
            (a, b) =>
                (a.questionId, a.answerCount, a.redacted) ==
                (b.questionId, b.answerCount, b.redacted),
          ),
  };
}

bool _agent(ThreadAgentLifecycleView a, ThreadAgentLifecycleView b) =>
    switch (a) {
      QueuedThreadAgentView() => b is QueuedThreadAgentView,
      RunningThreadAgentView() => b is RunningThreadAgentView,
      SucceededThreadAgentView() =>
        b is SucceededThreadAgentView &&
            (a.completedAt, a.summary) == (b.completedAt, b.summary),
      DeniedThreadAgentView() =>
        b is DeniedThreadAgentView &&
            (a.deniedAt, a.reason) == (b.deniedAt, b.reason),
      CancelledThreadAgentView() =>
        b is CancelledThreadAgentView &&
            (a.cancelledAt, a.reason) == (b.cancelledAt, b.reason),
      FailedThreadAgentView() =>
        b is FailedThreadAgentView &&
            (a.failedAt, a.error) == (b.failedAt, b.error),
    };
bool _inference(
  ThreadInferenceLifecycleView a,
  ThreadInferenceLifecycleView b,
) => switch (a) {
  RunningThreadInferenceView() => b is RunningThreadInferenceView,
  CompletedThreadInferenceView() =>
    b is CompletedThreadInferenceView &&
        a.completedAt == b.completedAt &&
        (
              a.usage.promptTokens,
              a.usage.completionTokens,
              a.usage.cachedPromptTokens,
              a.usage.totalTokens,
            ) ==
            (
              b.usage.promptTokens,
              b.usage.completionTokens,
              b.usage.cachedPromptTokens,
              b.usage.totalTokens,
            ),
  FailedThreadInferenceView() =>
    b is FailedThreadInferenceView &&
        (a.failedAt, a.error) == (b.failedAt, b.error),
  CancelledThreadInferenceView() =>
    b is CancelledThreadInferenceView &&
        (a.cancelledAt, a.reason) == (b.cancelledAt, b.reason),
};

bool descriptorTerminal(ConversationDescriptor descriptor) =>
    switch (descriptor) {
      ConversationTextDescriptor(:final lifecycle) ||
      ConversationThinkingDescriptor(:final lifecycle) => lifecycle.isTerminal,
      ConversationToolDescriptor(:final state) => state.isTerminal,
      ConversationAgentDescriptor(:final value) =>
        value.lifecycle is! QueuedThreadAgentView &&
            value.lifecycle is! RunningThreadAgentView,
      ConversationTurnDescriptor(:final value) => value.state.isTerminal,
      ConversationInferenceDescriptor(:final value) =>
        value.lifecycle is! RunningThreadInferenceView,
      _ => false,
    };

/// No runtimeType-only or serialization comparison: each closed variant has an
/// explicit static identity and complete typed-state comparison. A terminal
/// winner is retained whole, including its output/failure/attachments.
ConversationDescriptor mergeConversationDescriptor(
  ConversationDescriptor a,
  ConversationDescriptor b,
) {
  bool staticEqual;
  bool valueEqual;
  switch (a) {
    case ConversationTextDescriptor():
      if (b is! ConversationTextDescriptor) return _conflict();
      staticEqual =
          a.channel == b.channel && _attachments(a.attachments, b.attachments);
      valueEqual = _content(a.lifecycle, b.lifecycle);
    case ConversationThinkingDescriptor():
      if (b is! ConversationThinkingDescriptor) return _conflict();
      staticEqual = true;
      valueEqual = _content(a.lifecycle, b.lifecycle);
    case ConversationToolDescriptor():
      if (b is! ConversationToolDescriptor) return _conflict();
      final x = a.invocation, y = b.invocation;
      staticEqual =
          (
                x.toolCallId,
                x.callId,
                x.providerItemId,
                x.name,
                x.workingDirectory,
                x.taskId,
              ) ==
              (
                y.toolCallId,
                y.callId,
                y.providerItemId,
                y.name,
                y.workingDirectory,
                y.taskId,
              ) &&
          _questions(a.userInput, b.userInput) &&
          a.wait?.intent == b.wait?.intent;
      valueEqual =
          _tool(a.state, b.state) &&
          _answers(a.userInput, b.userInput) &&
          a.wait == b.wait;
    case ConversationRawDescriptor():
      if (b is! ConversationRawDescriptor) return _conflict();
      staticEqual =
          (a.origin, a.notice, a.recordedAt) ==
              (b.origin, b.notice, b.recordedAt) &&
          _list(
            a.payloads,
            b.payloads,
            (a, b) => (a.format, a.version) == (b.format, b.version),
          );
      valueEqual = staticEqual;
    case ConversationAgentDescriptor():
      if (b is! ConversationAgentDescriptor) return _conflict();
      final x = a.value.identity, y = b.value.identity;
      staticEqual =
          (x.id, x.path, x.parentPath, x.role, x.task, x.depth) ==
          (y.id, y.path, y.parentPath, y.role, y.task, y.depth);
      valueEqual = _agent(a.value.lifecycle, b.value.lifecycle);
    case ConversationTurnDescriptor():
      if (b is! ConversationTurnDescriptor) return _conflict();
      staticEqual = a.value.inputId == b.value.inputId;
      valueEqual = a.value.state == b.value.state;
    case ConversationInferenceDescriptor():
      if (b is! ConversationInferenceDescriptor) return _conflict();
      staticEqual =
          (a.value.inferenceId, a.value.model) ==
          (b.value.inferenceId, b.value.model);
      valueEqual = _inference(a.value.lifecycle, b.value.lifecycle);
    case ConversationSkillDescriptor():
      if (b is! ConversationSkillDescriptor) return _conflict();
      final x = a.value, y = b.value;
      staticEqual =
          (
            x.name,
            x.source,
            x.providerId,
            x.resourceBase.kind,
            x.resourceBase.value,
            x.cause.kind,
            x.cause.id,
            x.activatedAt,
          ) ==
          (
            y.name,
            y.source,
            y.providerId,
            y.resourceBase.kind,
            y.resourceBase.value,
            y.cause.kind,
            y.cause.id,
            y.activatedAt,
          );
      valueEqual = staticEqual;
    case ConversationFileDescriptor():
      if (b is! ConversationFileDescriptor) return _conflict();
      staticEqual =
          (a.value.path, a.value.mediaType, a.value.completedAt) ==
          (b.value.path, b.value.mediaType, b.value.completedAt);
      valueEqual = staticEqual;
    case ConversationContextCompactionDescriptor():
      if (b is! ConversationContextCompactionDescriptor) return _conflict();
      staticEqual =
          (a.value.beforeTokens, a.value.afterTokens, a.value.compactedAt) ==
          (b.value.beforeTokens, b.value.afterTokens, b.value.compactedAt);
      valueEqual = staticEqual;
  }
  if (!staticEqual) return _conflict();
  final terminalA = descriptorTerminal(a), terminalB = descriptorTerminal(b);
  if (terminalA != terminalB) return terminalA ? a : b;
  if (!valueEqual) return _conflict();
  return a;
}
