import 'dart:convert';

import '../../../models.dart';
import '../domain/content_lifecycle.dart';
import 'descriptor_convergence.dart';

Never _invalid(String reason) => throw ConversationContinuityError(reason);
int _bytes(String? text) => text == null ? 0 : utf8.encode(text).length;

/// Admission precedes copying the batch or building its atomic candidate.
void validateConversationPatchBudget(ConversationPatch patch) {
  var bytes = 128 + _bytes(patch.subscriptionId);
  for (final change in patch.changes) {
    bytes += switch (change) {
      ConversationAdd(:final item) => conversationItemBytes(item),
      ConversationRemove(:final itemId) => 64 + _bytes(itemId),
      ConversationUpdateItem(
        :final itemId,
        :final header,
        :final descriptor,
        :final fields,
      ) =>
        128 +
            _bytes(itemId) +
            (header == null
                ? 0
                : 128 +
                      _bytes(header.id) +
                      _bytes(header.threadId) +
                      _bytes(header.turnId)) +
            (descriptor == null ? 0 : descriptorBytes(descriptor)) +
            fields.fold<int>(
              0,
              (sum, field) =>
                  sum +
                  96 +
                  switch (field.change) {
                    AppendThreadFieldChangeView(:final text) ||
                    ReplaceThreadFieldChangeView(:final text) => _bytes(text),
                    _ => 0,
                  },
            ),
    };
    if (bytes > 8 * 1024 * 1024) _invalid('patch exceeds batch budget');
  }
}

/// Conservative admission includes structure, identities and retained strings.
/// It is not wire size or a claim about allocator heap usage.
int conversationItemBytes(ConversationItem item) =>
    256 +
    _bytes(item.id) +
    _bytes(item.header.threadId) +
    _bytes(item.header.turnId) +
    descriptorBytes(item.descriptor) +
    (switch (item.source) {
      ConversationRecoverySource(:final attemptId) => 64 + _bytes(attemptId),
      _ => 32,
    }) +
    item.fields.fold(0, (sum, field) => sum + 96 + field.previewBytes);

int descriptorBytes(ConversationDescriptor descriptor) {
  int attachments(List<ThreadAttachmentView> values) => values.fold(
    0,
    (sum, a) =>
        sum + 128 + _bytes(a.id) + _bytes(a.mediaType) + _bytes(a.filename),
  );
  int content(ThreadContentLifecycleView value) =>
      64 +
      switch (value) {
        FailedThreadContentView(:final error) => _bytes(error),
        CancelledThreadContentView(:final reason) => _bytes(reason),
        _ => 0,
      };
  return 128 +
      switch (descriptor) {
        ConversationTextDescriptor(:final attachments, :final lifecycle) =>
          // Local helper has a different identifier to avoid hiding this field.
          attachments.fold<int>(
                0,
                (sum, a) =>
                    sum +
                    128 +
                    _bytes(a.id) +
                    _bytes(a.mediaType) +
                    _bytes(a.filename),
              ) +
              content(lifecycle),
        ConversationThinkingDescriptor(:final lifecycle) => content(lifecycle),
        ConversationRawDescriptor(:final payloads, :final notice) =>
          _bytes(notice) +
              payloads.fold<int>(0, (sum, p) => sum + 64 + _bytes(p.format)),
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
                ConversationToolSucceeded(:final output) => attachments(
                  output.attachments,
                ),
                ConversationToolFailed(:final failure, :final output) =>
                  _bytes(failure.message) +
                      attachments(output?.attachments ?? const []),
                ConversationToolInterrupted(:final reason) ||
                ConversationToolDenied(:final reason) ||
                ConversationToolCancelled(:final reason) => _bytes(reason),
                _ => 0,
              }) +
              (userInput == null
                  ? 0
                  : _bytes(userInput.interactionId) +
                        userInput.questions.fold<int>(
                          0,
                          (sum, q) => sum + 96 + _bytes(q.id),
                        ) +
                        (switch (userInput.state) {
                          ConversationUserInputResolved(:final answers) =>
                            answers.fold<int>(
                              0,
                              (sum, a) => sum + 64 + _bytes(a.questionId),
                            ),
                          _ => 0,
                        })) +
              (wait == null
                  ? 0
                  : 128 +
                        switch (wait.intent) {
                          ThreadWaitTimerIntentView() => 32,
                          ThreadWaitEventsIntentView(:final targets) =>
                            targets.fold<int>(
                              0,
                              (sum, target) =>
                                  sum +
                                  128 +
                                  _bytes(target.taskId) +
                                  _bytes(target.toolName) +
                                  _bytes(target.summary),
                            ),
                        }),
        ConversationAgentDescriptor(:final value) =>
          _bytes(value.identity.id) +
              _bytes(value.identity.path) +
              _bytes(value.identity.parentPath) +
              _bytes(value.identity.role) +
              _bytes(value.identity.task) +
              (switch (value.lifecycle) {
                SucceededThreadAgentView(:final summary) => _bytes(summary),
                DeniedThreadAgentView(:final reason) ||
                CancelledThreadAgentView(:final reason) => _bytes(reason),
                FailedThreadAgentView(:final error) => _bytes(error),
                _ => 0,
              }),
        ConversationTurnDescriptor(:final value) =>
          _bytes(value.inputId) + _bytes(value.state.reason) + 128,
        ConversationInferenceDescriptor(:final value) =>
          _bytes(value.inferenceId) +
              _bytes(value.model) +
              128 +
              switch (value.lifecycle) {
                FailedThreadInferenceView(:final error) => _bytes(error),
                CancelledThreadInferenceView(:final reason) => _bytes(reason),
                _ => 0,
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
}

void validateConversationItems(
  List<ConversationItem> items, {
  required String threadId,
  int maxItems = 100,
}) {
  if (items.length > maxItems) _invalid('page exceeds item budget');
  final ids = <String>{};
  var bytes = 0;
  ConversationItem? previous;
  for (final item in items) {
    if (item.header.threadId != threadId ||
        item.id.isEmpty ||
        item.revision < 0 ||
        item.header.ordinal < 0 ||
        !ids.add(item.id))
      _invalid('invalid item identity');
    if (previous != null && compareConversationItems(previous, item) >= 0) {
      _invalid('page order is not strict');
    }
    previous = item;
    validateConversationItem(item);
    bytes += conversationItemBytes(item);
  }
  if (bytes > 2 * 1024 * 1024) _invalid('page exceeds byte budget');
}

void validateConversationItem(ConversationItem item) {
  final fields = <ThreadContentFieldView>{};
  var bodyBytes = 0;
  for (final value in item.fields) {
    if (!validConversationField(item.descriptor, value.field))
      _invalid('field does not belong to descriptor');
    if (!fields.add(value.field) ||
        value.totalBytes < value.previewBytes ||
        value.totalBytes < 0)
      _invalid('invalid or duplicate field preview');
    if ((value.field is ThreadToolArgumentsFieldView ||
            value.field is ThreadToolResultFieldView) &&
        value.previewBytes > 4096) {
      _invalid('tool preview exceeds domain budget');
    }
    bodyBytes += value.previewBytes;
  }
  if (bodyBytes > 32 * 1024 || conversationItemBytes(item) > 256 * 1024) {
    _invalid('item exceeds preview budget');
  }
}

int compareConversationItems(ConversationItem a, ConversationItem b) {
  final order = a.header.ordinal.compareTo(b.header.ordinal);
  return order == 0 ? a.id.compareTo(b.id) : order;
}

Map<String, ConversationItem> boundConversationTail(
  Iterable<ConversationItem> values, {
  int maxBytes = 8 * 1024 * 1024,
}) {
  final sorted = values.toList()..sort(compareConversationItems);
  var bytes = 0;
  final result = <String, ConversationItem>{};
  for (final item in sorted.reversed) {
    final size = conversationItemBytes(item);
    if (result.length >= 100 || bytes + size > maxBytes) break;
    result[item.id] = item;
    bytes += size;
  }
  return result;
}

ConversationItem _copy(
  ConversationItem value, {
  ConversationItemHeader? header,
  int? revision,
  ConversationDescriptor? descriptor,
  bool? saved,
  ConversationLifecycle? lifecycle,
  List<ConversationFieldPreview>? fields,
}) => ConversationItem(
  header: header ?? value.header,
  revision: revision ?? value.revision,
  descriptor: descriptor == null
      ? value.descriptor
      : immutableConversationDescriptor(descriptor),
  source: value.source,
  saved: saved ?? value.saved,
  lifecycle: lifecycle ?? value.lifecycle,
  fields: List.unmodifiable(fields ?? value.fields),
);

void _sameIdentity(ConversationItem current, ConversationItemHeader header) {
  if (current.id != header.id ||
      current.header.threadId != header.threadId ||
      current.header.ordinal != header.ordinal ||
      current.header.createdAt != header.createdAt) {
    _invalid('stable item identity changed');
  }
}

ConversationItem reduceConversationItem(
  ConversationItem current,
  ConversationUpdateItem update,
) {
  if (current.id != update.itemId ||
      current.revision != update.expectedRevision ||
      update.revision < current.revision)
    _invalid('item revision is not continuous');
  final header = update.header ?? current.header;
  _sameIdentity(current, header);
  if (current.terminal &&
      update.lifecycle != ConversationLifecycle.terminal &&
      current.revision != update.revision) {
    _invalid('independent item facts regressed');
  }
  final sameRevision = current.revision == update.revision;
  final descriptor = sameRevision
      ? mergeConversationDescriptor(
          current.descriptor,
          update.descriptor ?? current.descriptor,
        )
      : update.descriptor ?? current.descriptor;
  final fields = {for (final field in current.fields) field.field: field};
  final changed = <ThreadContentFieldView>{};
  for (final updateField in update.fields) {
    if (!changed.add(updateField.field)) _invalid('duplicate field update');
    final old = fields[updateField.field];
    final change = updateField.change;
    if (change is RemoveThreadFieldChangeView) {
      if (update.revision == current.revision && old != null) {
        _invalid('same revision removed a field');
      }
      if (updateField.totalBytes != 0 || updateField.previewBytes != 0)
        _invalid('remove declared nonzero length');
      fields.remove(updateField.field);
      continue;
    }
    final text = switch (change) {
      AppendThreadFieldChangeView(:final text) =>
        old == null
            ? _invalid('append without a field baseline')
            : '${old.text}$text',
      ReplaceThreadFieldChangeView(:final text) => text,
      UnchangedThreadFieldChangeView() =>
        old == null ? _invalid('unchanged without a field baseline') : old.text,
      RemoveThreadFieldChangeView() => _invalid('unreachable remove'),
    };
    if (_bytes(text) != updateField.previewBytes ||
        updateField.totalBytes < updateField.previewBytes) {
      _invalid('field lengths do not match UTF-8 content');
    }
    if (update.revision == current.revision &&
        (old == null ||
            updateField.totalBytes != old.totalBytes ||
            !text.startsWith(old.text))) {
      _invalid('same revision field completeness regressed');
    }
    fields[updateField.field] = ConversationFieldPreview(
      field: updateField.field,
      text: text,
      totalBytes: updateField.totalBytes,
    );
  }
  final candidate = _copy(
    current,
    header: header,
    revision: update.revision,
    descriptor: descriptor,
    saved: sameRevision ? current.saved || update.saved : update.saved,
    lifecycle:
        sameRevision && (current.terminal || descriptorTerminal(descriptor))
        ? ConversationLifecycle.terminal
        : update.lifecycle,
    fields: fields.values.toList(growable: false),
  );
  validateConversationItem(candidate);
  return candidate;
}

ConversationItem mergeConversationItem(
  ConversationItem current,
  ConversationItem incoming,
) {
  _sameIdentity(current, incoming.header);
  validateConversationItem(incoming);
  if (incoming.revision < current.revision) return current;
  if (incoming.revision > current.revision) {
    if (current.terminal && !incoming.terminal) {
      _invalid('authoritative add regressed item facts');
    }
    return immutableConversationItem(incoming);
  }
  final descriptor = mergeConversationDescriptor(
    current.descriptor,
    incoming.descriptor,
  );
  final fields = {for (final field in current.fields) field.field: field};
  if (fields.length != incoming.fields.length)
    _invalid('same revision field membership changed');
  for (final field in incoming.fields) {
    final old = fields[field.field];
    if (old == null || old.totalBytes != field.totalBytes)
      _invalid('same revision field identity changed');
    if (field.text.startsWith(old.text)) {
      fields[field.field] = field;
    } else if (!old.text.startsWith(field.text)) {
      _invalid('same revision previews conflict');
    }
  }
  final candidate = _copy(
    incoming,
    descriptor: descriptor,
    saved: current.saved || incoming.saved,
    lifecycle:
        current.terminal || incoming.terminal || descriptorTerminal(descriptor)
        ? ConversationLifecycle.terminal
        : incoming.lifecycle,
    fields: fields.values.toList(growable: false),
  );
  validateConversationItem(candidate);
  return candidate;
}

ConversationItem immutableConversationItem(ConversationItem item) =>
    ConversationItem(
      header: item.header,
      revision: item.revision,
      descriptor: immutableConversationDescriptor(item.descriptor),
      source: item.source,
      saved: item.saved,
      lifecycle: item.lifecycle,
      fields: List.unmodifiable(item.fields),
    );
ConversationDescriptor immutableConversationDescriptor(
  ConversationDescriptor descriptor,
) => switch (descriptor) {
  ConversationTextDescriptor(
    :final channel,
    :final attachments,
    :final lifecycle,
  ) =>
    ConversationTextDescriptor(
      channel: channel,
      attachments: List.unmodifiable(attachments),
      lifecycle: lifecycle,
    ),
  ConversationRawDescriptor(
    :final origin,
    :final payloads,
    :final notice,
    :final recordedAt,
  ) =>
    ConversationRawDescriptor(
      origin: origin,
      payloads: List.unmodifiable(payloads),
      notice: notice,
      recordedAt: recordedAt,
    ),
  ConversationToolDescriptor(
    :final invocation,
    :final state,
    :final userInput,
    :final wait,
  ) =>
    ConversationToolDescriptor(
      invocation: invocation,
      state: immutableToolState(state),
      userInput: userInput == null
          ? null
          : ConversationUserInputDescriptor(
              interactionId: userInput.interactionId,
              questions: List.unmodifiable(userInput.questions),
              state: switch (userInput.state) {
                ConversationUserInputResolved(:final answers) =>
                  ConversationUserInputResolved(
                    answers: List.unmodifiable(answers),
                  ),
                final other => other,
              },
            ),
      wait: wait == null
          ? null
          : ThreadWaitPresentationView(
              intent: switch (wait.intent) {
                ThreadWaitEventsIntentView(:final targets, :final timeoutMs) =>
                  ThreadWaitEventsIntentView(
                    targets: List.unmodifiable(targets),
                    timeoutMs: timeoutMs,
                  ),
                final other => other,
              },
              state: wait.state,
              messagesReady: wait.messagesReady,
            ),
    ),
  final other => other,
};
ConversationToolOutputDescriptor _immutableOutput(
  ConversationToolOutputDescriptor output,
) => ConversationToolOutputDescriptor(
  attachments: List.unmodifiable(output.attachments),
  exitCode: output.exitCode,
);
ConversationToolState immutableToolState(ConversationToolState state) =>
    switch (state) {
      ConversationToolSucceeded(:final completedAt, :final output) =>
        ConversationToolSucceeded(
          completedAt: completedAt,
          output: _immutableOutput(output),
        ),
      ConversationToolFailed(:final failedAt, :final failure, :final output) =>
        ConversationToolFailed(
          failedAt: failedAt,
          failure: failure,
          output: output == null ? null : _immutableOutput(output),
        ),
      final other => other,
    };

bool validConversationField(
  ConversationDescriptor descriptor,
  ThreadContentFieldView field,
) {
  return switch (field) {
    ThreadTextFieldView() => descriptor is ConversationTextDescriptor,
    ThreadThinkingSummaryFieldView(:final chunkIndex) ||
    ThreadThinkingContentFieldView(
      :final chunkIndex,
    ) => descriptor is ConversationThinkingDescriptor && chunkIndex >= 0,
    ThreadToolArgumentsFieldView() ||
    ThreadToolResultFieldView() ||
    ThreadToolOutputArtifactsFieldView() =>
      descriptor is ConversationToolDescriptor,
    ThreadRawPayloadFieldView(:final payloadIndex) =>
      descriptor is ConversationRawDescriptor &&
          payloadIndex >= 0 &&
          payloadIndex < descriptor.payloads.length,
    ThreadToolUserInputFieldView(:final questionIndex, :final part) =>
      descriptor is ConversationToolDescriptor &&
          validQuestionField(descriptor.userInput, questionIndex, part),
  };
}

bool validQuestionField(
  ConversationUserInputDescriptor? input,
  int questionIndex,
  ThreadUserInputFieldPartView part,
) {
  if (input == null ||
      questionIndex < 0 ||
      questionIndex >= input.questions.length)
    return false;
  final question = input.questions[questionIndex];
  return switch (part) {
    ThreadUserInputHeaderFieldPartView() ||
    ThreadUserInputQuestionFieldPartView() => true,
    ThreadUserInputOptionLabelFieldPartView(:final optionIndex) ||
    ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) =>
      optionIndex >= 0 &&
          question.optionCount != null &&
          optionIndex < question.optionCount!,
    ThreadUserInputAnswerFieldPartView(:final answerIndex) =>
      switch (input.state) {
        ConversationUserInputResolved(:final answers) =>
          answerIndex >= 0 &&
              answers.any(
                (answer) =>
                    answer.questionId == question.id &&
                    answerIndex < answer.answerCount,
              ),
        _ => false,
      },
  };
}

ConversationPatch immutableConversationPatch(ConversationPatch patch) =>
    ConversationPatch(
      subscriptionId: patch.subscriptionId,
      from: patch.from,
      to: patch.to,
      priority: patch.priority,
      changes: List.unmodifiable(
        patch.changes.map(
          (change) => switch (change) {
            ConversationAdd(:final item) => ConversationAdd(
              immutableConversationItem(item),
            ),
            ConversationUpdateItem(
              :final itemId,
              :final expectedRevision,
              :final revision,
              :final saved,
              :final lifecycle,
              :final header,
              :final descriptor,
              :final fields,
            ) =>
              ConversationUpdateItem(
                itemId: itemId,
                expectedRevision: expectedRevision,
                revision: revision,
                saved: saved,
                lifecycle: lifecycle,
                header: header,
                descriptor: descriptor == null
                    ? null
                    : immutableConversationDescriptor(descriptor),
                fields: List.unmodifiable(fields),
              ),
            ConversationRemove() => change,
          },
        ),
      ),
    );
