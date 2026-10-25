import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

/// One successfully metered preview: the bounded item, its per-field ledger, the
/// synthesized omitted bytes and the conservative accounted total.
final class DemoTimelinePreview {
  const DemoTimelinePreview({
    required this.item,
    required this.details,
    required this.omittedBytes,
    required this.accountedBytes,
  });

  final ThreadItemView item;
  final List<StudioTimelineDetailRef> details;
  final int omittedBytes;

  /// Non-shrinkable structure + actually retained body bytes. Only this number
  /// is kept by a connection's continuity copy; no second body copy is stored.
  final int accountedBytes;
}

/// Product preview budget: body 32 KiB, tool arguments/results 4 KiB each.
const int demoBodyPreviewBytes = 32 * 1024;
const int demoToolPreviewBytes = 4 * 1024;

/// Per-item ceiling for structure + retained body.
const int demoItemPreviewLimitBytes = 256 * 1024;

/// Per-page ceiling, accumulated from the newest end; a cut page keeps its real
/// older cursor instead of pretending to be EOF.
const int demoPageLimitBytes = 2 * 1024 * 1024;

/// Continuity-copy ceiling: 100 items AND 8 MiB.
const int demoContinuityItemLimit = 100;
const int demoContinuityByteLimit = 8 * 1024 * 1024;

/// Detail block bounds: default 64 KiB, explicit 4..262144 bytes.
const int demoDefaultDetailBytes = 64 * 1024;
const int demoMaxDetailBytes = 256 * 1024;
const int demoMinDetailBytes = 4;

/// Typed resource limit for an item whose non-shrinkable facts alone overflow
/// the per-item ceiling. Not EOF, not a retryable pressure signal.
StudioFailure demoPreviewOverloaded() => const StudioFailure(
  code: StudioFailureCode.overloaded,
  message: 'The timeline item cannot fit the preview budget',
  retryable: false,
  correlationId: 'demo-timeline-item-overloaded',
);

/// Field identity -> full canonical body of that field.
///
/// Field existence comes from the canonical item, never from what survived
/// capping: a field without preview budget still exists with an empty preview, a
/// real total and a detail reference.
Map<ThreadContentFieldView, String> demoTimelineFieldsOf(ThreadItemView item) {
  final fields = <ThreadContentFieldView, String>{};
  switch (item.state) {
    case ThreadTextItemStateView(:final text):
      fields[const ThreadTextFieldView()] = text;
    case ThreadThinkingItemStateView(
      :final summary,
      :final content,
      :final summaryChunkBase,
      :final contentChunkBase,
    ):
      for (var index = 0; index < summary.length; index++) {
        fields[ThreadThinkingSummaryFieldView(summaryChunkBase + index)] =
            summary[index];
      }
      for (var index = 0; index < content.length; index++) {
        fields[ThreadThinkingContentFieldView(contentChunkBase + index)] =
            content[index];
      }
    case ThreadToolItemStateView(
      :final invocation,
      :final lifecycle,
      :final userInput,
      wait: _,
    ):
      fields[const ThreadToolArgumentsFieldView()] = invocation.arguments;
      fields[const ThreadToolResultFieldView()] = demoToolResultText(lifecycle);
      fields[const ThreadToolOutputArtifactsFieldView()] =
          demoToolArtifactsText(lifecycle);
      if (userInput != null) {
        for (var index = 0; index < userInput.questions.length; index++) {
          fields[ThreadToolUserInputFieldView(
            questionIndex: index,
            part: const ThreadUserInputHeaderFieldPartView(),
          )] = userInput.headerText(
            index,
          );
          fields[ThreadToolUserInputFieldView(
            questionIndex: index,
            part: const ThreadUserInputQuestionFieldPartView(),
          )] = userInput.questionText(
            index,
          );
          final options = userInput.questions[index].options.length;
          for (var option = 0; option < options; option++) {
            fields[ThreadToolUserInputFieldView(
              questionIndex: index,
              part: ThreadUserInputOptionLabelFieldPartView(option),
            )] = userInput.optionLabel(
              index,
              option,
            );
            fields[ThreadToolUserInputFieldView(
              questionIndex: index,
              part: ThreadUserInputOptionDescriptionFieldPartView(option),
            )] = userInput.optionDescription(
              index,
              option,
            );
          }
        }
        for (final answer in userInput.answers) {
          final questionIndex = userInput.questionIndex(answer.questionId);
          if (questionIndex == null) continue;
          for (var value = 0; value < answer.answers.length; value++) {
            fields[ThreadToolUserInputFieldView(
                  questionIndex: questionIndex,
                  part: ThreadUserInputAnswerFieldPartView(value),
                )] =
                answer.answers[value];
          }
        }
      }
    case ThreadRawItemStateView(:final payloads):
      for (var index = 0; index < payloads.length; index++) {
        fields[ThreadRawPayloadFieldView(index)] = payloads[index].content;
      }
    default:
      break;
  }
  return fields;
}

/// Full body of one field, or null when the item has no such field.
String? demoTimelineFieldText(
  ThreadItemView item,
  ThreadContentFieldView field,
) => demoTimelineFieldsOf(item)[field];

/// Tool result body (`tool.result` field).
String demoToolResultText(ThreadToolLifecycleView lifecycle) =>
    switch (lifecycle) {
      RunningThreadToolView(:final streamedOutput) => streamedOutput,
      CancellingThreadToolView(:final streamedOutput) => streamedOutput,
      SucceededThreadToolView(:final output) => output.result,
      FailedThreadToolView(:final output) => output?.result ?? '',
      _ => '',
    };

/// Tool artifact body (`toolOutputArtifacts` field), encoded only at this
/// canonical boundary.
String demoToolArtifactsText(ThreadToolLifecycleView lifecycle) {
  final output = switch (lifecycle) {
    SucceededThreadToolView(:final output) => output,
    FailedThreadToolView(:final output) => output,
    _ => null,
  };
  if (output == null || output.outputArtifacts.isEmpty) return '';
  // Every artifact leaf stays opaque: join the original JSON objects instead of
  // decoding and re-encoding them, so the detail body keeps the exact bytes.
  return '[${output.outputArtifacts.map((artifact) => artifact.json).join(',')}]';
}

/// Build the bounded preview of a canonical item.
///
/// Structure is charged first; the remaining room takes the intersection of the
/// product body ceiling and the per-item ceiling. Detail references report the
/// real total per field, so omitted bodies stay readable on demand.
DemoTimelinePreview demoPreviewOf(ThreadItemView item) {
  final full = demoTimelineFieldsOf(item);
  final structure = _structureBytes(item, full);
  if (structure > demoItemPreviewLimitBytes) throw demoPreviewOverloaded();
  final room = demoItemPreviewLimitBytes - structure;
  final budget = _PreviewBudget(
    room < demoBodyPreviewBytes ? room : demoBodyPreviewBytes,
  );
  final capped = _withCappedFields(item, budget);
  final preview = demoTimelineFieldsOf(capped);
  final details = <StudioTimelineDetailRef>[
    for (final entry in full.entries)
      StudioTimelineDetailRef(
        field: entry.key,
        revision: item.revision,
        totalBytes: _byteLength(entry.value),
        previewBytes: _byteLength(preview[entry.key] ?? ''),
      ),
  ];
  var omitted = 0;
  var kept = 0;
  for (final ref in details) {
    omitted += ref.totalBytes - ref.previewBytes;
    kept += ref.previewBytes;
  }
  return DemoTimelinePreview(
    item: capped.copyWith(bodyOmittedUnits: omitted),
    details: List.unmodifiable(details),
    omittedBytes: omitted,
    accountedBytes: structure + kept,
  );
}

// ---- Conservative structure metering ----
//
// Demo has no core `meta` encoding. It estimates its own typed structure
// deterministically: real static string bytes plus fixed shells for typed
// containers. The numbers need not match core byte for byte; the per-item,
// page and continuity ceilings and the error classification must.

const int _itemShellBytes = 128;
const int _stringSlotBytes = 8;
const int _contentFieldSlotBytes = 24;
const int _containerSlotBytes = 16;
const int _attachmentSlotBytes = 24;

int _byteLength(String value) => utf8.encode(value).length;

int _stringBytes(String? value) =>
    value == null ? 0 : _stringSlotBytes + _byteLength(value);

int _structureBytes(
  ThreadItemView item,
  Map<ThreadContentFieldView, String> fields,
) {
  var total = _itemShellBytes;
  total += _stringBytes(item.id);
  total += _stringBytes(item.threadId);
  total += _stringBytes(item.turnId);
  total += fields.length * _contentFieldSlotBytes;
  switch (item.state) {
    case ThreadTextItemStateView(:final attachments, :final lifecycle):
      total += _attachmentBytes(attachments);
      total += _contentLifecycleBytes(lifecycle);
    case ThreadThinkingItemStateView(
      :final summary,
      :final content,
      :final lifecycle,
    ):
      total += (summary.length + content.length) * _containerSlotBytes;
      total += _contentLifecycleBytes(lifecycle);
    case ThreadSkillItemStateView(
      :final name,
      :final source,
      :final providerId,
      :final resourceBase,
      :final cause,
    ):
      total += _stringBytes(name);
      total += _stringBytes(source);
      total += _stringBytes(providerId);
      total += _stringBytes(resourceBase.value);
      total += _stringBytes(cause.id);
    case ThreadToolItemStateView(
      :final invocation,
      :final lifecycle,
      :final userInput,
      :final wait,
    ):
      total += _stringBytes(invocation.toolCallId);
      total += _stringBytes(invocation.callId);
      total += _stringBytes(invocation.providerItemId);
      total += _stringBytes(invocation.name);
      total += _stringBytes(invocation.workingDirectory);
      total += _stringBytes(invocation.taskId);
      total += _toolLifecycleBytes(lifecycle);
      total += _userInputBytes(userInput);
      total += _waitBytes(wait);
    case ThreadAgentItemStateView(:final identity, :final lifecycle):
      total += _stringBytes(identity.id);
      total += _stringBytes(identity.path);
      total += _stringBytes(identity.parentPath);
      total += _stringBytes(identity.role);
      total += _stringBytes(identity.task);
      total += switch (lifecycle) {
        SucceededThreadAgentView(:final summary) => _stringBytes(summary),
        DeniedThreadAgentView(:final reason) => _stringBytes(reason),
        CancelledThreadAgentView(:final reason) => _stringBytes(reason),
        FailedThreadAgentView(:final error) => _stringBytes(error),
        QueuedThreadAgentView() || RunningThreadAgentView() => 0,
      };
    case ThreadTurnItemStateView(:final state, :final inputId):
      total += _stringBytes(inputId);
      total += _turnStateBytes(state);
    case ThreadInferenceItemStateView(
      :final inferenceId,
      :final model,
      :final lifecycle,
    ):
      total += _stringBytes(inferenceId);
      total += _stringBytes(model);
      total += switch (lifecycle) {
        FailedThreadInferenceView(:final error) => _stringBytes(error),
        CancelledThreadInferenceView(:final reason) => _stringBytes(reason),
        RunningThreadInferenceView() || CompletedThreadInferenceView() => 0,
      };
    case ThreadRawItemStateView(:final payloads, :final notice):
      // `notice` is canonical static text, not a trimmable body domain: it is
      // charged in full and never capped into an empty string.
      total += _stringBytes(notice);
      for (final payload in payloads) {
        total += _stringBytes(payload.format);
      }
    case ThreadFileItemStateView(:final path, :final mediaType):
      total += _stringBytes(path);
      total += _stringBytes(mediaType);
    case ThreadContextCompactionItemStateView():
      break;
  }
  return total;
}

int _contentLifecycleBytes(ThreadContentLifecycleView lifecycle) =>
    switch (lifecycle) {
      FailedThreadContentView(:final error) => _stringBytes(error),
      CancelledThreadContentView(:final reason) => _stringBytes(reason),
      StreamingThreadContentView() || CompletedThreadContentView() => 0,
    };

/// Any String metadata that travels with the turn item is charged in full: the
/// derived reason plus the failure category/provider/code and any rollover
/// error. A fixed shell cannot exempt an unbounded String.
int _turnStateBytes(TurnState state) {
  var total = _stringBytes(state.reason);
  total += switch (state) {
    FailedTurn(:final failure) =>
      _stringBytes(failure.category.name) +
          _stringBytes(failure.providerKind?.name) +
          _stringBytes(failure.code),
    BudgetLimitedTurn(:final rollover) => switch (rollover) {
      TurnRolloverFailed(:final error) => _stringBytes(error),
      TurnRolloverSucceeded() || TurnRolloverNotAttempted() => 0,
    },
    QueuedTurn() || RunningTurn() || CompletedTurn() || CancelledTurn() => 0,
  };
  return total;
}

int _attachmentBytes(List<ThreadAttachmentView> attachments) {
  var total = 0;
  for (final attachment in attachments) {
    total += _attachmentSlotBytes;
    total += _stringBytes(attachment.id);
    total += _stringBytes(attachment.mediaType);
    total += _stringBytes(attachment.filename);
  }
  return total;
}

int _toolLifecycleBytes(ThreadToolLifecycleView lifecycle) =>
    switch (lifecycle) {
      InterruptedThreadToolView(:final reason) => _stringBytes(reason),
      DeniedThreadToolView(:final reason) => _stringBytes(reason),
      CancelledThreadToolView(:final reason) => _stringBytes(reason),
      FailedThreadToolView(:final failure, :final output) =>
        _stringBytes(failure.message) + _toolOutputBytes(output),
      SucceededThreadToolView(:final output) => _toolOutputBytes(output),
      QueuedThreadToolView() ||
      CancellingThreadToolView() ||
      StartedThreadToolView() ||
      StreamingThreadToolView() ||
      AwaitingApprovalThreadToolView() ||
      ApprovedThreadToolView() ||
      RunningThreadToolView() => 0,
    };

int _toolOutputBytes(ThreadToolOutput? output) {
  if (output == null) return 0;
  // The preview artifact array is always empty: artifact text is an independent
  // content field. Meter only what the preview actually retains.
  return _attachmentBytes(output.attachments) + _containerSlotBytes;
}

int _waitBytes(ThreadWaitPresentationView? wait) {
  if (wait == null) return 0;
  var total = _containerSlotBytes;
  switch (wait.intent) {
    case ThreadWaitEventsIntentView(:final targets):
      for (final target in targets) {
        total += _stringBytes(target.taskId);
        total += _stringBytes(target.toolName);
        total += _stringBytes(target.summary);
      }
    case ThreadWaitTimerIntentView():
      total += _containerSlotBytes;
  }
  return total;
}

int _userInputBytes(ThreadToolUserInputView? userInput) {
  if (userInput == null) return 0;
  var total = _containerSlotBytes + _stringBytes(userInput.interactionId);
  for (final question in userInput.questions) {
    total += _containerSlotBytes;
    total += _stringBytes(question.id);
    total += question.options.length * _containerSlotBytes;
  }
  for (final answer in userInput.answers) {
    total += _containerSlotBytes;
    total += _stringBytes(answer.questionId);
    total += answer.answers.length * _containerSlotBytes;
    if (userInput.questionIndex(answer.questionId) == null) {
      for (final value in answer.answers) {
        total += _stringBytes(value);
      }
    }
  }
  return total;
}

/// Cap every body domain by the shared product budget.
///
/// Body (including questions and raw records) shares 32 KiB; tool arguments and
/// results take at most 4 KiB each from that same allowance. Field existence and
/// structure never disappear: an empty preview plus the real total keeps the
/// field addressable and pushes the body to detail reads.
ThreadItemView _withCappedFields(ThreadItemView item, _PreviewBudget budget) {
  switch (item.state) {
    case ThreadTextItemStateView(
      :final channel,
      :final text,
      :final attachments,
      :final lifecycle,
    ):
      return item.copyWith(
        state: ThreadTextItemStateView(
          channel: channel,
          text: budget.cap(text, demoBodyPreviewBytes),
          attachments: attachments,
          lifecycle: lifecycle,
        ),
      );
    case ThreadThinkingItemStateView(
      :final summary,
      :final content,
      :final lifecycle,
      :final summaryChunkBase,
      :final contentChunkBase,
    ):
      return item.copyWith(
        state: ThreadThinkingItemStateView(
          summary: _cappedChunks(summary, budget),
          content: _cappedChunks(content, budget),
          lifecycle: lifecycle,
          summaryChunkBase: summaryChunkBase,
          contentChunkBase: contentChunkBase,
        ),
      );
    case ThreadToolItemStateView(
      :final invocation,
      :final lifecycle,
      :final userInput,
      :final wait,
    ):
      return item.copyWith(
        state: ThreadToolItemStateView(
          invocation: invocation.withArguments(
            budget.cap(invocation.arguments, demoToolPreviewBytes),
          ),
          lifecycle: _cappedToolLifecycle(lifecycle, budget),
          userInput: _cappedUserInput(userInput, budget),
          wait: wait,
        ),
      );
    case ThreadRawItemStateView(
      :final payloads,
      :final notice,
      :final recordedAt,
    ):
      return item.copyWith(
        state: ThreadRawItemStateView(
          [
            for (final payload in payloads)
              // Each payload is an independent stable identity: no budget keeps
              // the segment as an empty preview instead of dropping it.
              RawHistoryPayload(
                payload.format,
                payload.version,
                budget.cap(payload.content, demoBodyPreviewBytes),
              ),
          ],
          notice,
          recordedAt,
        ),
      );
    default:
      return item;
  }
}

/// Authority decision markers of a plan confirmation are discriminated facts:
/// reserve their bytes first, then trim free text with whatever remains.
ThreadToolUserInputView? _cappedUserInput(
  ThreadToolUserInputView? userInput,
  _PreviewBudget budget,
) {
  if (userInput == null) return null;
  for (final answer in userInput.answers) {
    for (final value in answer.answers) {
      if (value == agentSessionPlanApproveAnswer ||
          value == agentSessionPlanReviseAnswer) {
        budget.reserve(_byteLength(value));
      }
    }
  }
  var capped = userInput;
  for (var index = 0; index < userInput.questions.length; index++) {
    capped = capped
        .withText(
          index,
          const ThreadUserInputHeaderFieldPartView(),
          budget.cap(userInput.headerText(index), demoBodyPreviewBytes),
        )
        .withText(
          index,
          const ThreadUserInputQuestionFieldPartView(),
          budget.cap(userInput.questionText(index), demoBodyPreviewBytes),
        );
    final options = userInput.questions[index].options.length;
    for (var option = 0; option < options; option++) {
      capped = capped
          .withText(
            index,
            ThreadUserInputOptionLabelFieldPartView(option),
            budget.cap(
              userInput.optionLabel(index, option),
              demoBodyPreviewBytes,
            ),
          )
          .withText(
            index,
            ThreadUserInputOptionDescriptionFieldPartView(option),
            budget.cap(
              userInput.optionDescription(index, option),
              demoBodyPreviewBytes,
            ),
          );
    }
  }
  for (final answer in userInput.answers) {
    final index = userInput.questionIndex(answer.questionId);
    if (index == null) continue;
    for (var value = 0; value < answer.answers.length; value++) {
      final text = userInput.answerText(index, value);
      final keepVerbatim =
          text == agentSessionPlanApproveAnswer ||
          text == agentSessionPlanReviseAnswer;
      capped = capped.withText(
        index,
        ThreadUserInputAnswerFieldPartView(value),
        keepVerbatim ? text : budget.cap(text, demoBodyPreviewBytes),
      );
    }
  }
  return capped;
}

ThreadToolLifecycleView _cappedToolLifecycle(
  ThreadToolLifecycleView lifecycle,
  _PreviewBudget budget,
) {
  return switch (lifecycle) {
    RunningThreadToolView(:final streamedOutput) => RunningThreadToolView(
      budget.cap(streamedOutput, demoToolPreviewBytes),
    ),
    CancellingThreadToolView(:final streamedOutput) => CancellingThreadToolView(
      budget.cap(streamedOutput, demoToolPreviewBytes),
    ),
    SucceededThreadToolView(:final completedAt, :final output) =>
      SucceededThreadToolView(completedAt, _cappedToolOutput(output, budget)),
    FailedThreadToolView(:final failedAt, :final failure, :final output) =>
      FailedThreadToolView(
        failedAt,
        failure,
        output == null ? null : _cappedToolOutput(output, budget),
      ),
    _ => lifecycle,
  };
}

ThreadToolOutput _cappedToolOutput(
  ThreadToolOutput output,
  _PreviewBudget budget,
) => ThreadToolOutput(
  result: budget.cap(output.result, demoToolPreviewBytes),
  attachments: output.attachments,
  // Artifact text is an independent content field: the preview array may be
  // empty while the detail reference still carries the real total.
  outputArtifacts: const [],
  exitCode: output.exitCode,
);

/// Chunk preview: every canonical chunk keeps its identity; a chunk without
/// budget becomes an empty preview instead of a fake removal.
List<String> _cappedChunks(List<String> chunks, _PreviewBudget budget) => [
  for (final chunk in chunks) budget.cap(chunk, demoBodyPreviewBytes),
];

/// Shared per-item body allowance. Only the bytes actually retained are charged,
/// so short or empty fields leave room for later ones.
final class _PreviewBudget {
  _PreviewBudget(this.remaining);

  int remaining;

  String cap(String text, int max) {
    if (remaining <= 0 || max <= 0) return '';
    final granted = max < remaining ? max : remaining;
    final bytes = utf8.encode(text);
    if (bytes.length <= granted) {
      remaining -= bytes.length;
      return text;
    }
    var end = granted;
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end -= 1;
    }
    if (end == 0) return '';
    remaining -= end;
    return utf8.decode(bytes.sublist(0, end));
  }

  /// Reserve bytes for a small discriminator marker before free text is capped.
  void reserve(int bytes) {
    if (bytes <= 0) return;
    if (bytes > remaining) throw demoPreviewOverloaded();
    remaining -= bytes;
  }
}
