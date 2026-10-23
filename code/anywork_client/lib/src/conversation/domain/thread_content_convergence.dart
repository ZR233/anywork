import 'thread_content.dart';

ThreadItemView? convergeThreadContent(ThreadItemView current, ThreadItemView incoming, {required int omittedBytes}) {
  if (omittedBytes < 0) throw ArgumentError.value(omittedBytes, 'omittedBytes');
  if (current.id != incoming.id || current.threadId != incoming.threadId ||
      current.ordinal != incoming.ordinal || current.revision != incoming.revision) return null;
  final state = convergeThreadState(current.state, incoming.state);
  return state == null ? null : incoming.copyWith(state: state, bodyOmittedUnits: omittedBytes,
    executionTerminal: current.executionTerminal || incoming.executionTerminal, saved: current.saved || incoming.saved);
}
ThreadItemStateView? convergeThreadState(ThreadItemStateView current, ThreadItemStateView incoming) {
  switch ((current, incoming)) {
    case (ThreadTextItemStateView a, ThreadTextItemStateView b):
      if (a.channel != b.channel) return null;
      final text = convergeThreadText(a.text, b.text);
      return text == null ? null : b.copyWith(text: text,
        attachments: a.attachments.length <= b.attachments.length ? b.attachments : a.attachments,
        lifecycle: convergeThreadLifecycle(a.lifecycle, b.lifecycle));
    case (ThreadThinkingItemStateView a, ThreadThinkingItemStateView b):
      if (a.summaryChunkBase != b.summaryChunkBase || a.contentChunkBase != b.contentChunkBase) return null;
      final summary = convergeThreadChunks(a.summary, b.summary);
      final content = convergeThreadChunks(a.content, b.content);
      return summary == null || content == null ? null : b.copyWith(summary: summary, content: content,
        lifecycle: convergeThreadLifecycle(a.lifecycle, b.lifecycle));
    case (ThreadToolItemStateView a, ThreadToolItemStateView b):
      if (a.invocation.toolCallId != b.invocation.toolCallId || a.invocation.name != b.invocation.name ||
          a.invocation.callId != b.invocation.callId || a.invocation.providerItemId != b.invocation.providerItemId ||
          a.invocation.taskId != b.invocation.taskId || a.invocation.workingDirectory != b.invocation.workingDirectory) return null;
      final arguments = convergeThreadText(a.invocation.arguments, b.invocation.arguments);
      if (arguments == null) return null;
      final input = convergeThreadUserInput(a.userInput, b.userInput);
      if (!input.compatible) return null;
      return b.copyWith(invocation: b.invocation.withArguments(arguments),
        lifecycle: convergeThreadToolLifecycle(a.lifecycle, b.lifecycle), userInput: input.value, wait: b.wait ?? a.wait);
    case (ThreadRawItemStateView a, ThreadRawItemStateView b):
      final common = a.payloads.length < b.payloads.length ? a.payloads.length : b.payloads.length;
      final payloads = <RawHistoryPayload>[];
      for (var i = 0; i < common; i++) {
        final x = a.payloads[i]; final y = b.payloads[i];
        if (x.format != y.format || x.version != y.version) return null;
        final text = convergeThreadText(x.content, y.content);
        if (text == null) return null;
        payloads.add(y.copyWith(content: text));
      }
      payloads.addAll((a.payloads.length >= b.payloads.length ? a.payloads : b.payloads).skip(common));
      final notice = convergeThreadText(a.notice, b.notice);
      return notice == null ? null : b.copyWith(payloads: payloads, notice: notice);
    case (ThreadFileItemStateView a, ThreadFileItemStateView b): return a.path == b.path ? b : null;
    case (ThreadSkillItemStateView a, ThreadSkillItemStateView b): return a.name == b.name ? b : null;
    case (ThreadAgentItemStateView a, ThreadAgentItemStateView b): return a.identity.id == b.identity.id ? b : null;
    case (ThreadTurnItemStateView a, ThreadTurnItemStateView b): return a.inputId == b.inputId ? b : null;
    case (ThreadInferenceItemStateView a, ThreadInferenceItemStateView b): return a.inferenceId == b.inferenceId ? b : null;
    case (ThreadContextCompactionItemStateView(), ThreadContextCompactionItemStateView()): return incoming;
    default: return null;
  }
}
String? convergeThreadText(String a, String b) => b.startsWith(a) ? b : a.startsWith(b) ? a : null;
List<String>? convergeThreadChunks(List<String> a, List<String> b) {
  final common = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < common - 1; i++) { if (a[i] != b[i]) return null; }
  if (common == 0) return a.length >= b.length ? a : b;
  final last = convergeThreadText(a[common - 1], b[common - 1]);
  if (last == null) return null;
  return [...a.take(common - 1), last, ...(a.length >= b.length ? a : b).skip(common)];
}
ThreadContentLifecycleView convergeThreadLifecycle(ThreadContentLifecycleView a, ThreadContentLifecycleView b) =>
    a is StreamingThreadContentView && b is! StreamingThreadContentView ? b : a;

ThreadToolLifecycleView convergeThreadToolLifecycle(ThreadToolLifecycleView a, ThreadToolLifecycleView b) {
  if (a is RunningThreadToolView && b is RunningThreadToolView) return RunningThreadToolView(convergeThreadText(a.streamedOutput, b.streamedOutput) ?? a.streamedOutput);
  if (a is CancellingThreadToolView && b is CancellingThreadToolView) return CancellingThreadToolView(convergeThreadText(a.streamedOutput, b.streamedOutput) ?? a.streamedOutput);
  if (a is SucceededThreadToolView && b is SucceededThreadToolView) {
    return SucceededThreadToolView(a.completedAt, a.output.copyWith(
      result: convergeThreadText(a.output.result, b.output.result) ?? a.output.result,
      attachments: a.output.attachments.length <= b.output.attachments.length ? b.output.attachments : a.output.attachments,
      outputArtifacts: a.output.outputArtifacts.length <= b.output.outputArtifacts.length ? b.output.outputArtifacts : a.output.outputArtifacts,
      exitCode: b.output.exitCode ?? a.output.exitCode));
  }
  if (a.runtimeType == b.runtimeType) return a;
  return _toolRank(b) > _toolRank(a) ? b : a;
}
int _toolRank(ThreadToolLifecycleView lifecycle) => switch (lifecycle) {
  QueuedThreadToolView() => 0, StartedThreadToolView() => 1, StreamingThreadToolView() => 2,
  AwaitingApprovalThreadToolView() => 3, ApprovedThreadToolView() => 4,
  RunningThreadToolView() => 5, CancellingThreadToolView() => 6, _ => 7,
};
({bool compatible, ThreadToolUserInputView? value}) convergeThreadUserInput(ThreadToolUserInputView? a, ThreadToolUserInputView? b) {
  if (a == null) return (compatible: true, value: b);
  if (b == null) return (compatible: true, value: a);
  if (a.interactionId != b.interactionId) return (compatible: false, value: null);
  var merged = b.withTextsFrom(a);
  if (a.isResolved && !merged.isResolved) merged = merged.copyWith(state: a.state).withTextsFrom(a);
  for (var index = 0; index < b.questions.length; index++) {
    merged = _preferPart(merged, index, const ThreadUserInputHeaderFieldPartView(), b.headerText(index));
    merged = _preferPart(merged, index, const ThreadUserInputQuestionFieldPartView(), b.questionText(index));
    for (var option = 0; option < b.questions[index].options.length; option++) {
      merged = _preferPart(merged, index, ThreadUserInputOptionLabelFieldPartView(option), b.optionLabel(index, option));
      merged = _preferPart(merged, index, ThreadUserInputOptionDescriptionFieldPartView(option), b.optionDescription(index, option));
    }
  }
  for (final answer in b.answers) {
    if (answer.redacted) continue;
    final index = merged.questionIndex(answer.questionId);
    if (index == null) continue;
    for (var value = 0; value < answer.answers.length; value++) {
      merged = _preferPart(merged, index, ThreadUserInputAnswerFieldPartView(value), answer.answers[value]);
    }
  }
  return (compatible: true, value: merged);
}
ThreadToolUserInputView _preferPart(ThreadToolUserInputView view, int index, ThreadUserInputFieldPartView part, String candidate) {
  final current = switch (part) {
    ThreadUserInputHeaderFieldPartView() => view.headerText(index), ThreadUserInputQuestionFieldPartView() => view.questionText(index),
    ThreadUserInputOptionLabelFieldPartView(:final optionIndex) => view.optionLabel(index, optionIndex),
    ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) => view.optionDescription(index, optionIndex),
    ThreadUserInputAnswerFieldPartView(:final answerIndex) => view.answerText(index, answerIndex),
  };
  return current == candidate || !candidate.startsWith(current) ? view : view.withText(index, part, candidate);
}
