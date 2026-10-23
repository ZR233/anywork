import 'thread_content.dart';

ThreadItemView? applyThreadContentChanges(ThreadItemView item, {
  required List<ThreadFieldUpdateView> fields, required int expectedRevision,
  required int revision, required int omittedUnits, required bool saved,
  required bool terminal, ThreadItemView? itemShell,
}) {
  if (item.revision != expectedRevision || revision < item.revision || omittedUnits < 0 ||
      (item.executionTerminal && !terminal) || (revision == item.revision &&
        (omittedUnits > item.bodyOmittedUnits || (item.saved && !saved)))) return null;
  var state = item.state;
  if (itemShell != null) {
    if (itemShell.id != item.id || itemShell.threadId != item.threadId ||
        itemShell.ordinal != item.ordinal || itemShell.revision != revision) return null;
    final seeded = seedThreadContent(state, itemShell.state);
    if (seeded == null) return null;
    state = seeded;
  }
  for (final update in fields) {
    if (update.field is ThreadToolOutputArtifactsFieldView &&
        update.change is! RemoveThreadFieldChangeView && update.change is! UnchangedThreadFieldChangeView) {
      if (itemShell == null || state is! ThreadToolItemStateView ||
          (state.lifecycle is! SucceededThreadToolView &&
            !(state.lifecycle is FailedThreadToolView && (state.lifecycle as FailedThreadToolView).output != null))) return null;
      // The same validated typed shell, not the opaque field text, owns artifacts.
      continue;
    }
    // The typed raw shell already installs membership; these removes retire old
    // field positions, not a second member of the newly installed list.
    if (itemShell != null && state is ThreadRawItemStateView && update.field is ThreadRawPayloadFieldView &&
        update.change is RemoveThreadFieldChangeView) continue;
    if (itemShell != null && update.field is ThreadToolResultFieldView &&
        update.change is RemoveThreadFieldChangeView && state is ThreadToolItemStateView &&
        state.lifecycle is! RunningThreadToolView && state.lifecycle is! CancellingThreadToolView) continue;
    final next = applyThreadContentField(state, update.field, update.change);
    if (next == null) return null;
    state = next;
  }
  return item.copyWith(turnId: itemShell?.turnId ?? item.turnId, revision: revision,
    updatedAt: itemShell?.updatedAt ?? item.updatedAt, state: state,
    contextDisposition: itemShell?.contextDisposition ?? item.contextDisposition,
    bodyOmittedUnits: omittedUnits, saved: saved, executionTerminal: terminal);
}

ThreadItemStateView? seedThreadContent(ThreadItemStateView current, ThreadItemStateView shell) => switch ((current, shell)) {
  (ThreadTextItemStateView a, ThreadTextItemStateView b) => b.copyWith(text: a.text),
  (ThreadThinkingItemStateView a, ThreadThinkingItemStateView b) => b.copyWith(summary: a.summary,
    content: a.content, summaryChunkBase: a.summaryChunkBase, contentChunkBase: a.contentChunkBase),
  (ThreadRawItemStateView a, ThreadRawItemStateView b) => b.copyWith(payloads: [
    for (var index = 0; index < b.payloads.length; index++) b.payloads[index].copyWith(
      content: index < a.payloads.length ? a.payloads[index].content : b.payloads[index].content),
  ]),
  (ThreadToolItemStateView a, ThreadToolItemStateView b) => b.copyWith(
    invocation: b.invocation.withArguments(a.invocation.arguments),
    lifecycle: switch ((a.lifecycle, b.lifecycle)) {
      (RunningThreadToolView(:final streamedOutput) || CancellingThreadToolView(:final streamedOutput), RunningThreadToolView()) => RunningThreadToolView(streamedOutput),
      (RunningThreadToolView(:final streamedOutput) || CancellingThreadToolView(:final streamedOutput), CancellingThreadToolView()) => CancellingThreadToolView(streamedOutput),
      _ => b.lifecycle,
    }, userInput: b.userInput == null ? null : a.userInput == null ? b.userInput : b.userInput!.withTextsFrom(a.userInput!),
    wait: b.wait ?? a.wait),
  _ when current.runtimeType == shell.runtimeType => shell,
  _ => null,
};

ThreadItemStateView? applyThreadContentField(ThreadItemStateView state, ThreadContentFieldView field, ThreadFieldChangeView change) {
  switch (state) {
    case ThreadTextItemStateView():
      return field is ThreadTextFieldView ? state.copyWith(text: applyThreadText(state.text, change)) : null;
    case ThreadThinkingItemStateView():
      final (summary, index) = switch (field) {
        ThreadThinkingSummaryFieldView(:final chunkIndex) => (true, chunkIndex),
        ThreadThinkingContentFieldView(:final chunkIndex) => (false, chunkIndex), _ => (false, -1),
      };
      if (index < 0) return null;
      final chunks = applyThreadChunks(summary ? state.summary : state.content,
        summary ? state.summaryChunkBase : state.contentChunkBase, index, change);
      return chunks == null ? null : summary ? state.copyWith(summary: chunks) : state.copyWith(content: chunks);
    case ThreadToolItemStateView():
      switch (field) {
        case ThreadToolArgumentsFieldView(): return state.copyWith(invocation: state.invocation.withArguments(applyThreadText(state.invocation.arguments, change)));
        case ThreadToolResultFieldView(): return state.copyWith(lifecycle: applyThreadToolResult(state.lifecycle, change));
        case ThreadToolOutputArtifactsFieldView():
          // Artifact JSON is never decoded here. Add/Replace previews arrive on
          // the typed shell; only Remove clears the already-delivered preview.
          return change is RemoveThreadFieldChangeView ? state.copyWith(lifecycle: removeThreadToolArtifacts(state.lifecycle))
              : change is UnchangedThreadFieldChangeView ? state : null;
        case ThreadToolUserInputFieldView(:final questionIndex, :final part):
          final input = state.userInput;
          if (input == null || input.questionAt(questionIndex) == null) return null;
          final String current;
          switch (part) {
            case ThreadUserInputHeaderFieldPartView(): current = input.headerText(questionIndex);
            case ThreadUserInputQuestionFieldPartView(): current = input.questionText(questionIndex);
            case ThreadUserInputOptionLabelFieldPartView(:final optionIndex):
              if (optionIndex < 0 || optionIndex >= input.questions[questionIndex].options.length) return null;
              current = input.optionLabel(questionIndex, optionIndex);
            case ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex):
              if (optionIndex < 0 || optionIndex >= input.questions[questionIndex].options.length) return null;
              current = input.optionDescription(questionIndex, optionIndex);
            case ThreadUserInputAnswerFieldPartView(:final answerIndex):
              final answer = input.answerAt(questionIndex);
              if (answer == null || answer.redacted || answerIndex < 0 || answerIndex >= answer.answers.length) {
                return change is RemoveThreadFieldChangeView ? state : null;
              }
              current = input.answerText(questionIndex, answerIndex);
          }
          return state.copyWith(userInput: input.withText(questionIndex, part, applyThreadText(current, change)));
        default: return null;
      }
    case ThreadRawItemStateView():
      if (field is! ThreadRawPayloadFieldView || field.payloadIndex < 0 || field.payloadIndex >= state.payloads.length) return null;
      final payloads = [...state.payloads];
      if (change is RemoveThreadFieldChangeView) {
        payloads.removeAt(field.payloadIndex);
      } else {
        final payload = payloads[field.payloadIndex];
        payloads[field.payloadIndex] = payload.copyWith(content: applyThreadText(payload.content, change));
      }
      return state.copyWith(payloads: payloads);
    default: return null;
  }
}

String applyThreadText(String current, ThreadFieldChangeView change) => switch (change) {
  UnchangedThreadFieldChangeView() => current, AppendThreadFieldChangeView(:final text) => '$current$text',
  ReplaceThreadFieldChangeView(:final text) => text, RemoveThreadFieldChangeView() => '',
};
List<String>? applyThreadChunks(List<String> chunks, int base, int logical, ThreadFieldChangeView change) {
  if (change is UnchangedThreadFieldChangeView) return chunks;
  final index = logical - base;
  if (index < 0) return chunks;
  if (index > chunks.length) return null;
  if (index == chunks.length) return switch (change) {
    AppendThreadFieldChangeView(:final text) || ReplaceThreadFieldChangeView(:final text) => [...chunks, text], _ => chunks,
  };
  final next = [...chunks]; next[index] = applyThreadText(chunks[index], change);
  return next;
}
ThreadToolLifecycleView applyThreadToolResult(ThreadToolLifecycleView lifecycle, ThreadFieldChangeView change) {
  if (change is UnchangedThreadFieldChangeView) return lifecycle;
  return switch (lifecycle) {
    RunningThreadToolView(:final streamedOutput) => RunningThreadToolView(applyThreadText(streamedOutput, change)),
    CancellingThreadToolView(:final streamedOutput) => CancellingThreadToolView(applyThreadText(streamedOutput, change)),
    SucceededThreadToolView(:final completedAt, :final output) => SucceededThreadToolView(completedAt,
      output.copyWith(result: applyThreadText(output.result, change))),
    FailedThreadToolView(:final failedAt, :final failure, :final output) => FailedThreadToolView(failedAt, failure,
      (output ?? ThreadToolOutput(result: '', attachments: [], outputArtifacts: [])).copyWith(result: applyThreadText(output?.result ?? '', change))),
    _ => change is RemoveThreadFieldChangeView ? lifecycle : RunningThreadToolView(applyThreadText('', change)),
  };
}
ThreadToolLifecycleView removeThreadToolArtifacts(ThreadToolLifecycleView lifecycle) => switch (lifecycle) {
  SucceededThreadToolView(:final completedAt, :final output) => SucceededThreadToolView(completedAt, output.copyWith(outputArtifacts: [])),
  FailedThreadToolView(:final failedAt, :final failure, :final output) => FailedThreadToolView(failedAt, failure, output?.copyWith(outputArtifacts: [])),
  _ => lifecycle,
};
