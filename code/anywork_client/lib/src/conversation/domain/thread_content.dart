import 'package:freezed_annotation/freezed_annotation.dart';

import 'thread_content_changes.dart';
import 'thread_content_convergence.dart';
import 'thread_content_fields.dart';
import 'thread_content_nested.dart';
import 'thread_content_questions.dart';
import 'turn_values.dart';

export 'thread_content_fields.dart';
export 'thread_content_nested.dart';
export 'thread_content_questions.dart';

part 'thread_content.freezed.dart';

@Freezed(toStringOverride: false)
sealed class ThreadItemStateView with _$ThreadItemStateView {
  const ThreadItemStateView._();
  factory ThreadItemStateView.raw(
    List<RawHistoryPayload> payloads,
    String notice,
    int recordedAt,
  ) = ThreadRawItemStateView;
  factory ThreadItemStateView.text({
    required ThreadTextChannel channel,
    required String text,
    required List<ThreadAttachmentView> attachments,
    required ThreadContentLifecycleView lifecycle,
  }) = ThreadTextItemStateView;
  factory ThreadItemStateView.thinking({
    required List<String> summary,
    required List<String> content,
    required ThreadContentLifecycleView lifecycle,
    @Default(0) int summaryChunkBase,
    @Default(0) int contentChunkBase,
  }) = ThreadThinkingItemStateView;
  const factory ThreadItemStateView.tool({
    required ThreadToolInvocationView invocation,
    required ThreadToolLifecycleView lifecycle,
    ThreadToolUserInputView? userInput,
    ThreadWaitPresentationView? wait,
  }) = ThreadToolItemStateView;
  const factory ThreadItemStateView.agent({
    required ThreadAgentIdentityView identity,
    required ThreadAgentLifecycleView lifecycle,
  }) = ThreadAgentItemStateView;
  const factory ThreadItemStateView.turn(TurnState state, {String? inputId}) =
      ThreadTurnItemStateView;
  const factory ThreadItemStateView.inference({
    required String inferenceId,
    required String model,
    required ThreadInferenceLifecycleView lifecycle,
  }) = ThreadInferenceItemStateView;
  const factory ThreadItemStateView.skill({
    required String name,
    required String source,
    required String providerId,
    required SkillResourceBaseView resourceBase,
    required SkillActivationCauseView cause,
    required int activatedAt,
  }) = ThreadSkillItemStateView;
  const factory ThreadItemStateView.file(
    String path,
    String? mediaType,
    int completedAt,
  ) = ThreadFileItemStateView;
  const factory ThreadItemStateView.contextCompaction(
    int? beforeTokens,
    int? afterTokens,
    int compactedAt,
  ) = ThreadContextCompactionItemStateView;
}

@Freezed(toStringOverride: false)
final class ThreadRawItemStateView extends ThreadItemStateView
    with _$ThreadRawItemStateView {
  ThreadRawItemStateView(
    List<RawHistoryPayload> payloads,
    this.notice,
    this.recordedAt,
  ) : payloads = List.unmodifiable(payloads),
      super._();
  final List<RawHistoryPayload> payloads;
  final String notice;
  final int recordedAt;
}

@Freezed(toStringOverride: false)
final class ThreadTextItemStateView extends ThreadItemStateView
    with _$ThreadTextItemStateView {
  ThreadTextItemStateView({
    required this.channel,
    required this.text,
    required List<ThreadAttachmentView> attachments,
    required this.lifecycle,
  }) : attachments = List.unmodifiable(attachments),
       super._();
  final ThreadTextChannel channel;
  final String text;
  final List<ThreadAttachmentView> attachments;
  final ThreadContentLifecycleView lifecycle;
}

@Freezed(toStringOverride: false)
final class ThreadThinkingItemStateView extends ThreadItemStateView
    with _$ThreadThinkingItemStateView {
  ThreadThinkingItemStateView({
    required List<String> summary,
    required List<String> content,
    required this.lifecycle,
    this.summaryChunkBase = 0,
    this.contentChunkBase = 0,
  }) : summary = List.unmodifiable(summary),
       content = List.unmodifiable(content),
       super._();
  final List<String> summary;
  final List<String> content;
  final ThreadContentLifecycleView lifecycle;
  final int summaryChunkBase;
  final int contentChunkBase;
}

@Freezed(toStringOverride: false)
abstract class ThreadItemView with _$ThreadItemView {
  const ThreadItemView._();
  const factory ThreadItemView({
    required String id,
    required String threadId,
    required String turnId,
    required int ordinal,
    required int revision,
    required int createdAt,
    required int updatedAt,
    required ThreadItemStateView state,
    @Default(ThreadContextDisposition.active)
    ThreadContextDisposition contextDisposition,
    @Default(0) int bodyOmittedUnits,
    @Default(false) bool executionTerminal,
    @Default(true) bool saved,
  }) = _ThreadItemView;

  bool get bodyPreviewed => bodyOmittedUnits > 0;
  ThreadItemKind get kind => switch (state) {
    ThreadTextItemStateView(:final channel) =>
      channel == ThreadTextChannel.user
          ? ThreadItemKind.userMessage
          : channel == ThreadTextChannel.parentAgent
          ? ThreadItemKind.parentAgentMessage
          : ThreadItemKind.agentMessage,
    ThreadThinkingItemStateView() => ThreadItemKind.reasoning,
    ThreadToolItemStateView() => ThreadItemKind.toolCall,
    ThreadAgentItemStateView() => ThreadItemKind.agent,
    ThreadTurnItemStateView() => ThreadItemKind.turn,
    ThreadInferenceItemStateView() => ThreadItemKind.inference,
    ThreadSkillItemStateView() => ThreadItemKind.skill,
    ThreadRawItemStateView() => ThreadItemKind.raw,
    ThreadFileItemStateView() => ThreadItemKind.file,
    ThreadContextCompactionItemStateView() => ThreadItemKind.contextCompaction,
  };
  String get status => switch (state) {
    ThreadTextItemStateView(:final lifecycle) ||
    ThreadThinkingItemStateView(:final lifecycle) => lifecycle.status,
    ThreadToolItemStateView(:final lifecycle) => lifecycle.status,
    ThreadAgentItemStateView(:final lifecycle) => switch (lifecycle) {
      QueuedThreadAgentView() => 'queued',
      RunningThreadAgentView() => 'running',
      SucceededThreadAgentView() => 'succeeded',
      DeniedThreadAgentView() => 'denied',
      CancelledThreadAgentView() => 'cancelled',
      FailedThreadAgentView() => 'failed',
    },
    ThreadTurnItemStateView(:final state) => state.status.name,
    ThreadInferenceItemStateView(:final lifecycle) => switch (lifecycle) {
      RunningThreadInferenceView() => 'running',
      CompletedThreadInferenceView() => 'completed',
      FailedThreadInferenceView() => 'failed',
      CancelledThreadInferenceView() => 'cancelled',
    },
    _ => 'completed',
  };
  bool get isTerminal => switch (state) {
    ThreadTextItemStateView(:final lifecycle) ||
    ThreadThinkingItemStateView(:final lifecycle) => lifecycle.isTerminal,
    ThreadToolItemStateView(:final lifecycle) => lifecycle.isTerminal,
    ThreadAgentItemStateView(:final lifecycle) =>
      lifecycle is! QueuedThreadAgentView &&
          lifecycle is! RunningThreadAgentView,
    ThreadTurnItemStateView(:final state) => state.isTerminal,
    ThreadInferenceItemStateView(:final lifecycle) =>
      lifecycle is! RunningThreadInferenceView,
    _ => true,
  };
  int? get completedAt => switch (state) {
    ThreadTextItemStateView(:final lifecycle) ||
    ThreadThinkingItemStateView(:final lifecycle) => lifecycle.terminalAt,
    ThreadToolItemStateView(:final lifecycle) => switch (lifecycle) {
      InterruptedThreadToolView(:final interruptedAt) => interruptedAt,
      SucceededThreadToolView(:final completedAt) => completedAt,
      FailedThreadToolView(:final failedAt) => failedAt,
      DeniedThreadToolView(:final deniedAt) => deniedAt,
      CancelledThreadToolView(:final cancelledAt) => cancelledAt,
      _ => null,
    },
    ThreadAgentItemStateView(:final lifecycle) => switch (lifecycle) {
      SucceededThreadAgentView(:final completedAt) => completedAt,
      DeniedThreadAgentView(:final deniedAt) => deniedAt,
      CancelledThreadAgentView(:final cancelledAt) => cancelledAt,
      FailedThreadAgentView(:final failedAt) => failedAt,
      _ => null,
    },
    ThreadTurnItemStateView(:final state) => switch (state) {
      CompletedTurn(:final completedAt) ||
      CancelledTurn(:final completedAt) ||
      FailedTurn(:final completedAt) ||
      BudgetLimitedTurn(:final completedAt) => completedAt,
      _ => null,
    },
    ThreadInferenceItemStateView(:final lifecycle) => switch (lifecycle) {
      CompletedThreadInferenceView(:final completedAt) => completedAt,
      FailedThreadInferenceView(:final failedAt) => failedAt,
      CancelledThreadInferenceView(:final cancelledAt) => cancelledAt,
      _ => null,
    },
    ThreadSkillItemStateView(:final activatedAt) => activatedAt,
    ThreadRawItemStateView(:final recordedAt) => recordedAt,
    ThreadFileItemStateView(:final completedAt) => completedAt,
    ThreadContextCompactionItemStateView(:final compactedAt) => compactedAt,
  };
  String? get error => switch (state) {
    ThreadTextItemStateView(:final lifecycle) ||
    ThreadThinkingItemStateView(:final lifecycle) => lifecycle.failure,
    ThreadToolItemStateView(:final lifecycle) => switch (lifecycle) {
      FailedThreadToolView(:final failure) => failure.message,
      InterruptedThreadToolView(:final reason) => reason,
      _ => null,
    },
    ThreadAgentItemStateView(lifecycle: FailedThreadAgentView(:final error)) =>
      error,
    ThreadTurnItemStateView(:final state) => state.reason,
    ThreadInferenceItemStateView(
      lifecycle: FailedThreadInferenceView(:final error),
    ) =>
      error,
    _ => null,
  };
  String get text => switch (state) {
    ThreadRawItemStateView(:final notice) => notice,
    ThreadTextItemStateView(:final text) => text,
    ThreadAgentItemStateView(:final lifecycle) => switch (lifecycle) {
      SucceededThreadAgentView(:final summary) => summary,
      DeniedThreadAgentView(:final reason) ||
      CancelledThreadAgentView(:final reason) => reason,
      FailedThreadAgentView(:final error) => error,
      _ => '',
    },
    ThreadSkillItemStateView(:final name) => name,
    _ => '',
  };
  AgentMessageChannel? get channel => switch (state) {
    ThreadTextItemStateView(channel: ThreadTextChannel.commentary) =>
      AgentMessageChannel.commentary,
    ThreadTextItemStateView(channel: ThreadTextChannel.finalAnswer) =>
      AgentMessageChannel.finalAnswer,
    _ => null,
  };
  List<ThreadAttachmentView> get attachments => switch (state) {
    ThreadTextItemStateView(:final attachments) => attachments,
    _ => const [],
  };
  List<String> get reasoningSummary => switch (state) {
    ThreadThinkingItemStateView(:final summary) => summary,
    _ => const [],
  };
  List<String> get reasoningContent => switch (state) {
    ThreadThinkingItemStateView(:final content) => content,
    _ => const [],
  };
  String? get filePath => switch (state) {
    ThreadFileItemStateView(:final path) => path,
    _ => null,
  };
  String? get mediaType => switch (state) {
    ThreadFileItemStateView(:final mediaType) => mediaType,
    _ => null,
  };
  ThreadSkillItemStateView? get skill => switch (state) {
    final ThreadSkillItemStateView skill => skill,
    _ => null,
  };
  TimelineToolPart? get tool => threadItemTool(this);

  ThreadItemView? applyFieldUpdates({
    required List<ThreadFieldUpdateView> fields,
    required int expectedRevision,
    required int revision,
    required int omittedUnits,
    required bool saved,
    required bool terminal,
    ThreadItemView? itemShell,
  }) => applyThreadContentChanges(
    this,
    fields: fields,
    expectedRevision: expectedRevision,
    revision: revision,
    omittedUnits: omittedUnits,
    saved: saved,
    terminal: terminal,
    itemShell: itemShell,
  );
  ThreadItemView? convergeWith(
    ThreadItemView incoming, {
    required int omittedBytes,
  }) => convergeThreadContent(this, incoming, omittedBytes: omittedBytes);
}

TimelineToolPart? threadItemTool(ThreadItemView item) {
  final state = item.state;
  if (state is! ThreadToolItemStateView) return null;
  final lifecycle = state.lifecycle;
  final output = switch (lifecycle) {
    SucceededThreadToolView(:final output) => output,
    FailedThreadToolView(:final output) => output,
    _ => null,
  };
  return TimelineToolPart(
    toolCallId: state.invocation.toolCallId,
    name: state.invocation.name,
    callId: state.invocation.callId,
    providerItemId: state.invocation.providerItemId,
    arguments: state.invocation.arguments,
    workingDirectory: state.invocation.workingDirectory,
    taskId: state.invocation.taskId,
    userInput: state.userInput,
    wait: state.wait,
    result: switch (lifecycle) {
      RunningThreadToolView(:final streamedOutput) ||
      CancellingThreadToolView(:final streamedOutput) => streamedOutput,
      _ => output?.result,
    },
    attachments: output?.attachments ?? const [],
    outputArtifacts: output?.outputArtifacts ?? const [],
    exitCode: output?.exitCode,
    timedOut:
        lifecycle is FailedThreadToolView &&
        lifecycle.failure.kind == ThreadToolFailureKindView.timedOut,
    denialReason: switch (lifecycle) {
      DeniedThreadToolView(:final reason) => reason,
      _ => null,
    },
  );
}
