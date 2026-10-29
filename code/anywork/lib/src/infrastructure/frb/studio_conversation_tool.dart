part of 'studio_api.dart';

ConversationToolDescriptor _toolDescriptorFromFrb(
  frb_descriptor.BridgeTimelineToolDescriptor value,
) => ConversationToolDescriptor(
  invocation: ConversationToolInvocation(
    toolCallId: value.invocation.toolCallId,
    callId: value.invocation.callId,
    providerItemId: value.invocation.providerItemId,
    name: value.invocation.name,
    workingDirectory: value.invocation.workingDirectory,
    taskId: value.invocation.taskId,
  ),
  state: value.state.when(
    queued: () => const ConversationToolQueued(),
    cancelling: () => const ConversationToolCancelling(),
    started: () => const ConversationToolStarted(),
    streaming: () => const ConversationToolStreaming(),
    awaitingApproval: () => const ConversationToolAwaitingApproval(),
    approved: () => const ConversationToolApproved(),
    running: () => const ConversationToolRunning(),
    interrupted: (at, reason) => ConversationToolInterrupted(
      interruptedAt: _dateFromUnix(at),
      reason: reason,
    ),
    succeeded: (at, output) => ConversationToolSucceeded(
      completedAt: _dateFromUnix(at),
      output: _toolOutputDescriptorFromFrb(output),
    ),
    failed: (at, failure, output) => ConversationToolFailed(
      failedAt: _dateFromUnix(at),
      failure: ThreadToolFailureView(
        kind: switch (failure.kind) {
          frb_item.BridgeThreadToolFailureKind.execution =>
            ThreadToolFailureKindView.execution,
          frb_item.BridgeThreadToolFailureKind.timedOut =>
            ThreadToolFailureKindView.timedOut,
          frb_item.BridgeThreadToolFailureKind.budgetLimited =>
            ThreadToolFailureKindView.budgetLimited,
        },
        message: failure.message,
      ),
      output: output == null ? null : _toolOutputDescriptorFromFrb(output),
    ),
    denied: (at, reason) =>
        ConversationToolDenied(deniedAt: _dateFromUnix(at), reason: reason),
    cancelled: (at, reason) => ConversationToolCancelled(
      cancelledAt: _dateFromUnix(at),
      reason: reason,
    ),
  ),
  userInput: value.userInput == null
      ? null
      : _userInputDescriptorFromFrb(value.userInput!),
  wait: value.wait == null ? null : _waitFromFrb(value.wait!),
);

ConversationToolOutputDescriptor _toolOutputDescriptorFromFrb(
  frb_descriptor.BridgeTimelineToolOutputDescriptor value,
) => ConversationToolOutputDescriptor(
  attachments: List.unmodifiable(value.attachments.map(_attachmentFromFrb)),
  exitCode: value.exitCode,
);

ConversationUserInputDescriptor _userInputDescriptorFromFrb(
  frb_descriptor.BridgeTimelineUserInputDescriptor value,
) => ConversationUserInputDescriptor(
  interactionId: value.interactionId,
  questions: List.unmodifiable(
    value.questions.map(
      (question) => ConversationQuestionDescriptor(
        id: question.id,
        isOther: question.isOther,
        isSecret: question.isSecret,
        optionCount: question.optionCount,
      ),
    ),
  ),
  state: value.state.when(
    pending: () => const ConversationUserInputPending(),
    cancelled: () => const ConversationUserInputCancelled(),
    resolved: (answers) => ConversationUserInputResolved(
      answers: List.unmodifiable(
        answers.map(
          (answer) => ConversationAnswerDescriptor(
            questionId: answer.questionId,
            answerCount: answer.answerCount,
            redacted: answer.redacted,
          ),
        ),
      ),
    ),
  ),
);
