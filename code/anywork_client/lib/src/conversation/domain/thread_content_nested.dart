import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../drafts.dart' show AttachmentModality;
import 'activity_read_values.dart' show ThreadWaitState, ThreadWaitTargetStatus;
import 'thread_content_fields.dart';
import 'thread_content_questions.dart';

part 'thread_content_nested.freezed.dart';

enum ThreadTextChannel { user, parentAgent, commentary, finalAnswer }

enum AgentMessageChannel { commentary, finalAnswer }

enum ThreadContextDisposition { active, rolledBack }

enum ThreadItemKind {
  raw,
  userMessage,
  parentAgentMessage,
  agentMessage,
  reasoning,
  toolCall,
  agent,
  turn,
  inference,
  skill,
  file,
  contextCompaction,
}

enum SkillResourceBaseKind { directory, url, opaque }

enum SkillActivationCauseKind { tool, userGesture }

enum ThreadToolFailureKindView { execution, timedOut, budgetLimited }

@Freezed(toStringOverride: false)
abstract class ThreadAttachmentView with _$ThreadAttachmentView {
  const factory ThreadAttachmentView({
    required String id,
    required AttachmentModality modality,
    required String mediaType,
    required int byteSize,
    String? filename,
    int? width,
    int? height,
  }) = _ThreadAttachmentView;
}

@Freezed(toStringOverride: false)
abstract class SkillResourceBaseView with _$SkillResourceBaseView {
  const factory SkillResourceBaseView(
    SkillResourceBaseKind kind,
    String value,
  ) = _SkillResourceBaseView;
}

@Freezed(toStringOverride: false)
abstract class SkillActivationCauseView with _$SkillActivationCauseView {
  const factory SkillActivationCauseView(
    SkillActivationCauseKind kind,
    String id,
  ) = _SkillActivationCauseView;
}

@Freezed(toStringOverride: false)
sealed class ThreadContentLifecycleView with _$ThreadContentLifecycleView {
  const ThreadContentLifecycleView._();
  const factory ThreadContentLifecycleView.streaming() =
      StreamingThreadContentView;
  const factory ThreadContentLifecycleView.completed(int completedAt) =
      CompletedThreadContentView;
  const factory ThreadContentLifecycleView.failed(int failedAt, String error) =
      FailedThreadContentView;
  const factory ThreadContentLifecycleView.cancelled(
    int cancelledAt,
    String reason,
  ) = CancelledThreadContentView;
  bool get isTerminal => this is! StreamingThreadContentView;
  String get status => switch (this) {
    StreamingThreadContentView() => 'streaming',
    CompletedThreadContentView() => 'completed',
    FailedThreadContentView() => 'failed',
    CancelledThreadContentView() => 'cancelled',
  };
  int? get terminalAt => switch (this) {
    StreamingThreadContentView() => null,
    CompletedThreadContentView(:final completedAt) => completedAt,
    FailedThreadContentView(:final failedAt) => failedAt,
    CancelledThreadContentView(:final cancelledAt) => cancelledAt,
  };
  String? get failure => switch (this) {
    FailedThreadContentView(:final error) => error,
    _ => null,
  };
}

@Freezed(toStringOverride: false)
abstract class ThreadToolInvocationView with _$ThreadToolInvocationView {
  const ThreadToolInvocationView._();
  const factory ThreadToolInvocationView({
    required String toolCallId,
    required String name,
    required String arguments,
    String? callId,
    String? providerItemId,
    String? workingDirectory,
    String? taskId,
  }) = _ThreadToolInvocationView;
  ThreadToolInvocationView withArguments(String raw) =>
      copyWith(arguments: raw);
}

@Freezed(toStringOverride: false)
final class ThreadToolOutput with _$ThreadToolOutput {
  ThreadToolOutput({
    required this.result,
    required List<ThreadAttachmentView> attachments,
    required List<OpaqueArtifactJson> outputArtifacts,
    this.exitCode,
  }) : attachments = List.unmodifiable(attachments),
       outputArtifacts = List.unmodifiable(outputArtifacts);
  final String result;
  final List<ThreadAttachmentView> attachments;
  final List<OpaqueArtifactJson> outputArtifacts;
  final int? exitCode;
}

@Freezed(toStringOverride: false)
abstract class ThreadToolFailureView with _$ThreadToolFailureView {
  const factory ThreadToolFailureView({
    required ThreadToolFailureKindView kind,
    required String message,
  }) = _ThreadToolFailureView;
}

@Freezed(toStringOverride: false)
sealed class ThreadToolLifecycleView with _$ThreadToolLifecycleView {
  const ThreadToolLifecycleView._();
  const factory ThreadToolLifecycleView.queued() = QueuedThreadToolView;
  const factory ThreadToolLifecycleView.started() = StartedThreadToolView;
  const factory ThreadToolLifecycleView.streaming() = StreamingThreadToolView;
  const factory ThreadToolLifecycleView.awaitingApproval() =
      AwaitingApprovalThreadToolView;
  const factory ThreadToolLifecycleView.approved() = ApprovedThreadToolView;
  const factory ThreadToolLifecycleView.running(String streamedOutput) =
      RunningThreadToolView;
  const factory ThreadToolLifecycleView.cancelling(String streamedOutput) =
      CancellingThreadToolView;
  const factory ThreadToolLifecycleView.interrupted(
    int interruptedAt,
    String reason,
  ) = InterruptedThreadToolView;
  const factory ThreadToolLifecycleView.succeeded(
    int completedAt,
    ThreadToolOutput output,
  ) = SucceededThreadToolView;
  const factory ThreadToolLifecycleView.failed(
    int failedAt,
    ThreadToolFailureView failure,
    ThreadToolOutput? output,
  ) = FailedThreadToolView;
  const factory ThreadToolLifecycleView.denied(int deniedAt, String reason) =
      DeniedThreadToolView;
  const factory ThreadToolLifecycleView.cancelled(
    int cancelledAt,
    String reason,
  ) = CancelledThreadToolView;
  String get status => switch (this) {
    QueuedThreadToolView() => 'queued',
    StartedThreadToolView() => 'started',
    StreamingThreadToolView() => 'streaming',
    AwaitingApprovalThreadToolView() => 'awaitingApproval',
    ApprovedThreadToolView() => 'approved',
    RunningThreadToolView() => 'running',
    CancellingThreadToolView() => 'cancelling',
    InterruptedThreadToolView() => 'interrupted',
    SucceededThreadToolView() => 'succeeded',
    FailedThreadToolView() => 'failed',
    DeniedThreadToolView() => 'denied',
    CancelledThreadToolView() => 'cancelled',
  };
  bool get isTerminal => switch (this) {
    InterruptedThreadToolView() ||
    SucceededThreadToolView() ||
    FailedThreadToolView() ||
    DeniedThreadToolView() ||
    CancelledThreadToolView() => true,
    _ => false,
  };
}

@Freezed(toStringOverride: false)
abstract class ThreadAgentIdentityView with _$ThreadAgentIdentityView {
  const factory ThreadAgentIdentityView({
    required String id,
    required String path,
    String? parentPath,
    required String role,
    required String task,
    required int depth,
  }) = _ThreadAgentIdentityView;
}

@Freezed(toStringOverride: false)
sealed class ThreadAgentLifecycleView with _$ThreadAgentLifecycleView {
  const factory ThreadAgentLifecycleView.queued() = QueuedThreadAgentView;
  const factory ThreadAgentLifecycleView.running() = RunningThreadAgentView;
  const factory ThreadAgentLifecycleView.succeeded(
    int completedAt,
    String summary,
  ) = SucceededThreadAgentView;
  const factory ThreadAgentLifecycleView.denied(int deniedAt, String reason) =
      DeniedThreadAgentView;
  const factory ThreadAgentLifecycleView.cancelled(
    int cancelledAt,
    String reason,
  ) = CancelledThreadAgentView;
  const factory ThreadAgentLifecycleView.failed(int failedAt, String error) =
      FailedThreadAgentView;
}

@Freezed(toStringOverride: false)
abstract class ThreadInferenceUsageView with _$ThreadInferenceUsageView {
  const factory ThreadInferenceUsageView({
    required int promptTokens,
    required int completionTokens,
    required int cachedPromptTokens,
    required int totalTokens,
  }) = _ThreadInferenceUsageView;
}

@Freezed(toStringOverride: false)
sealed class ThreadInferenceLifecycleView with _$ThreadInferenceLifecycleView {
  const factory ThreadInferenceLifecycleView.running() =
      RunningThreadInferenceView;
  const factory ThreadInferenceLifecycleView.completed(
    int completedAt,
    ThreadInferenceUsageView usage,
  ) = CompletedThreadInferenceView;
  const factory ThreadInferenceLifecycleView.failed(
    int failedAt,
    String error,
  ) = FailedThreadInferenceView;
  const factory ThreadInferenceLifecycleView.cancelled(
    int cancelledAt,
    String reason,
  ) = CancelledThreadInferenceView;
}

@Freezed(toStringOverride: false)
abstract class RawHistoryPayload with _$RawHistoryPayload {
  const factory RawHistoryPayload(String format, int version, String content) =
      _RawHistoryPayload;
}

@Freezed(toStringOverride: false)
abstract class ThreadWaitPresentationView with _$ThreadWaitPresentationView {
  const factory ThreadWaitPresentationView({
    required ThreadWaitIntentView intent,
    required ThreadWaitState state,
    bool? messagesReady,
  }) = _ThreadWaitPresentationView;
}

@Freezed(toStringOverride: false)
sealed class ThreadWaitIntentView with _$ThreadWaitIntentView {
  const ThreadWaitIntentView._();
  factory ThreadWaitIntentView.events({
    required List<ThreadWaitTargetView> targets,
    required int timeoutMs,
  }) = ThreadWaitEventsIntentView;
  const factory ThreadWaitIntentView.timer({required int durationMs}) =
      ThreadWaitTimerIntentView;
}

@Freezed(toStringOverride: false)
final class ThreadWaitEventsIntentView extends ThreadWaitIntentView
    with _$ThreadWaitEventsIntentView {
  ThreadWaitEventsIntentView({
    required List<ThreadWaitTargetView> targets,
    required this.timeoutMs,
  }) : targets = List.unmodifiable(targets),
       super._();
  final List<ThreadWaitTargetView> targets;
  final int timeoutMs;
}

@Freezed(toStringOverride: false)
abstract class ThreadWaitTargetView with _$ThreadWaitTargetView {
  const factory ThreadWaitTargetView({
    required String taskId,
    String? toolName,
    String? summary,
    @Default(false) bool summaryTruncated,
    ThreadWaitTargetStatus? status,
  }) = _ThreadWaitTargetView;
}

@Freezed(toStringOverride: false)
final class TimelineToolPart with _$TimelineToolPart {
  TimelineToolPart({
    required this.toolCallId,
    required this.name,
    this.callId,
    this.providerItemId,
    this.arguments = '',
    this.result,
    List<ThreadAttachmentView> attachments = const [],
    List<OpaqueArtifactJson> outputArtifacts = const [],
    this.exitCode,
    this.timedOut = false,
    this.workingDirectory,
    this.denialReason,
    this.taskId,
    this.userInput,
    this.wait,
  }) : attachments = List.unmodifiable(attachments),
       outputArtifacts = List.unmodifiable(outputArtifacts);
  final String toolCallId;
  final String name;
  final String? callId;
  final String? providerItemId;
  final String arguments;
  final String? result;
  final List<ThreadAttachmentView> attachments;
  final List<OpaqueArtifactJson> outputArtifacts;
  final int? exitCode;
  final bool timedOut;
  final String? workingDirectory;
  final String? denialReason;
  final String? taskId;
  final ThreadToolUserInputView? userInput;
  final ThreadWaitPresentationView? wait;
}
