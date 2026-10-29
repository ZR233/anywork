import 'dart:convert';

import '../../../models.dart';
import '../domain/content_lifecycle.dart';

const completionItemBudgetBytes = 256 * 1024;
const completionBatchBudgetBytes = 2 * 1024 * 1024;

int _bytes(String? value) => value == null ? 0 : utf8.encode(value).length;
int _attachments(List<ThreadAttachmentView> values) => values.fold(
  0,
  (n, a) => n + 128 + _bytes(a.id) + _bytes(a.mediaType) + _bytes(a.filename),
);
int _content(ConversationContentOutcome outcome) =>
    64 +
    switch (outcome) {
      ConversationContentCompleted() => 0,
      ConversationContentFailed(:final value) => _bytes(value.error),
      ConversationContentCancelled(:final value) => _bytes(value.reason),
    };
int _wait(ThreadWaitPresentationView? value) {
  if (value == null) return 0;
  return 128 +
      switch (value.intent) {
        ThreadWaitTimerIntentView() => 32,
        ThreadWaitEventsIntentView(:final targets) => targets.fold<int>(
          0,
          (n, t) =>
              n +
              128 +
              _bytes(t.taskId) +
              _bytes(t.toolName) +
              _bytes(t.summary),
        ),
      };
}

int _descriptor(ConversationDescriptor descriptor) =>
    128 +
    switch (descriptor) {
      ConversationTextDescriptor(:final attachments, :final outcome) =>
        _attachments(attachments) + _content(outcome),
      ConversationThinkingDescriptor(:final outcome) => _content(outcome),
      ConversationRawDescriptor(:final notice, :final payloads) =>
        _bytes(notice) +
            payloads.fold<int>(0, (n, p) => n + 64 + _bytes(p.format)),
      ConversationPlanDescriptor(:final interactionId, :final contentHash) =>
        _bytes(interactionId) + _bytes(contentHash),
      ConversationToolDescriptor(
        :final invocation,
        :final state,
        :final userInput,
        :final wait,
      ) =>
        _bytes(invocation.toolCallId) +
            _bytes(invocation.callId) +
            _bytes(invocation.providerItemId) +
            _bytes(invocation.name) +
            _bytes(invocation.workingDirectory) +
            _bytes(invocation.taskId) +
            (switch (state) {
              ConversationToolBackgroundStarted() => 0,
              ConversationToolSucceeded(:final output) => _attachments(
                output.attachments,
              ),
              ConversationToolFailed(:final failure, :final output) =>
                _bytes(failure.message) +
                    _attachments(output?.attachments ?? const []),
              ConversationToolInterrupted(:final reason) ||
              ConversationToolDenied(:final reason) ||
              ConversationToolCancelled(:final reason) => _bytes(reason),
            }) +
            (userInput == null
                ? 0
                : 128 +
                      _bytes(userInput.interactionId) +
                      userInput.questions.fold<int>(
                        0,
                        (n, q) => n + 96 + _bytes(q.id),
                      ) +
                      switch (userInput.state) {
                        ConversationUserInputCancelled() => 0,
                        ConversationUserInputResolved(:final answers) =>
                          answers.fold<int>(
                            0,
                            (n, a) => n + 64 + _bytes(a.questionId),
                          ),
                      }) +
            _wait(wait),
      ConversationAgentDescriptor(:final identity, :final outcome) =>
        _bytes(identity.id) +
            _bytes(identity.path) +
            _bytes(identity.parentPath) +
            _bytes(identity.role) +
            _bytes(identity.task) +
            switch (outcome) {
              ConversationAgentSucceeded(:final value) => _bytes(value.summary),
              ConversationAgentDenied(:final value) => _bytes(value.reason),
              ConversationAgentCancelled(:final value) => _bytes(value.reason),
              ConversationAgentFailed(:final value) => _bytes(value.error),
            },
      ConversationTurnDescriptor(:final inputId, :final outcome) =>
        _bytes(inputId) +
            128 +
            switch (outcome) {
              ConversationTurnCompleted(:final value) => _bytes(value.reason),
              ConversationTurnFailed(:final value) =>
                _bytes(value.failure.message) +
                    _bytes(value.failure.category) +
                    _bytes(value.failure.providerKind) +
                    _bytes(value.failure.code),
              ConversationTurnCancelled(:final value) => _bytes(value.reason),
              ConversationTurnBudgetLimited(:final value) =>
                _bytes(value.reason) +
                    switch (value.rollover) {
                      RolloverFailed(:final error) => _bytes(error),
                      RolloverNotAttempted() || RolloverSucceeded() => 0,
                    },
            },
      ConversationInferenceDescriptor(
        :final inferenceId,
        :final model,
        :final outcome,
      ) =>
        _bytes(inferenceId) +
            _bytes(model) +
            128 +
            switch (outcome) {
              ConversationInferenceCompleted() => 0,
              ConversationInferenceFailed(:final value) => _bytes(value.error),
              ConversationInferenceCancelled(:final value) => _bytes(
                value.reason,
              ),
            },
      ConversationSkillDescriptor(:final value) =>
        _bytes(value.name) +
            _bytes(value.source) +
            _bytes(value.providerId) +
            _bytes(value.resourceBase.value) +
            _bytes(value.cause.id),
      ConversationFileDescriptor(:final value) =>
        _bytes(value.path) + _bytes(value.mediaType),
      ConversationContextCompactionDescriptor() => 64,
    };

/// Conservative content admission estimate, not an exact wire/heap measurement.
void validateCompletionBudget(List<ConversationItem> items) {
  var total = 128;
  for (final item in items) {
    var bytes =
        256 +
        _bytes(item.header.id) +
        _bytes(item.header.threadId) +
        _bytes(item.header.turnId) +
        _descriptor(item.descriptor);
    var previewBytes = 0;
    for (final field in item.fields) {
      final fieldBytes = field.previewBytes;
      previewBytes += fieldBytes;
      if ((field.field is ThreadToolArgumentsFieldView ||
              field.field is ThreadToolResultFieldView) &&
          fieldBytes > 4 * 1024) {
        throw const ConversationContinuityError('tool preview exceeds budget');
      }
      bytes += 96 + fieldBytes;
    }
    if (previewBytes > 32 * 1024) {
      throw const ConversationContinuityError('item preview exceeds budget');
    }
    if (bytes > completionItemBudgetBytes)
      throw const ConversationContinuityError('completed item exceeds budget');
    total += bytes;
    if (total > completionBatchBudgetBytes)
      throw const ConversationContinuityError('completed batch exceeds budget');
  }
}
