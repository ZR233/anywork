import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart' show AttachmentModality;

import '../../../rust/api/studio/types/attachment.dart' as attachment;
import '../../../rust/api/studio/types/thread_stream/item.dart' as native;
import '../shared/exact_numbers.dart';
import 'scalar_converters.dart';

ThreadAttachmentView attachmentFromBridge(native.BridgeThreadAttachment value) => ThreadAttachmentView(
  id: value.id,
  modality: switch (value.modality) {
    attachment.BridgeAttachmentModality.image => AttachmentModality.image,
    attachment.BridgeAttachmentModality.video => AttachmentModality.video,
    attachment.BridgeAttachmentModality.file => AttachmentModality.file,
  },
  mediaType: value.mediaType,
  filename: value.filename,
  width: value.width,
  height: value.height,
  byteSize: exactU64(value.byteSize, 'attachment bytes'),
);

ThreadContentLifecycleView contentLifecycleFromBridge(native.BridgeThreadContentLifecycle value) => switch (value) {
  native.BridgeThreadContentLifecycle_Streaming() => const ThreadContentLifecycleView.streaming(),
  native.BridgeThreadContentLifecycle_Completed(:final completedAt) => ThreadContentLifecycleView.completed(exactI64(completedAt, 'content completed Unix seconds')),
  native.BridgeThreadContentLifecycle_Failed(:final failedAt, :final error) => ThreadContentLifecycleView.failed(exactI64(failedAt, 'content failed Unix seconds'), error),
  native.BridgeThreadContentLifecycle_Cancelled(:final cancelledAt, :final reason) => ThreadContentLifecycleView.cancelled(exactI64(cancelledAt, 'content cancelled Unix seconds'), reason),
};

ThreadToolInvocationView toolInvocationFromBridge(native.BridgeThreadToolInvocation value) => ThreadToolInvocationView(
  toolCallId: value.toolCallId, name: value.name,
  arguments: value.arguments, callId: value.callId,
  providerItemId: value.providerItemId, workingDirectory: value.workingDirectory,
  taskId: value.taskId,
);

ThreadToolOutput toolOutputFromBridge(native.BridgeThreadToolOutput value) => ThreadToolOutput(
  result: value.result,
  attachments: List.unmodifiable(value.attachments.map(attachmentFromBridge)),
  // Each value is an intentionally open artifact, already serialized by Rust.
  // Do not decode, normalize, stringify or infer a known business schema here.
  outputArtifacts: List.unmodifiable([
    for (final json in value.outputArtifactsJson) OpaqueArtifactJson(json: json),
  ]),
  exitCode: value.exitCode,
);

ThreadToolFailureView _toolFailure(native.BridgeThreadToolFailure value) => ThreadToolFailureView(
  kind: switch (value.kind) {
    native.BridgeThreadToolFailureKind.execution => ThreadToolFailureKindView.execution,
    native.BridgeThreadToolFailureKind.timedOut => ThreadToolFailureKindView.timedOut,
    native.BridgeThreadToolFailureKind.budgetLimited => ThreadToolFailureKindView.budgetLimited,
  },
  message: value.message,
);

ThreadToolLifecycleView toolLifecycleFromBridge(native.BridgeThreadToolState value) => switch (value) {
  native.BridgeThreadToolState_Queued() => const ThreadToolLifecycleView.queued(),
  native.BridgeThreadToolState_Started() => const ThreadToolLifecycleView.started(),
  native.BridgeThreadToolState_Streaming() => const ThreadToolLifecycleView.streaming(),
  native.BridgeThreadToolState_AwaitingApproval() => const ThreadToolLifecycleView.awaitingApproval(),
  native.BridgeThreadToolState_Approved() => const ThreadToolLifecycleView.approved(),
  native.BridgeThreadToolState_Running(:final streamedOutput) => ThreadToolLifecycleView.running(streamedOutput),
  native.BridgeThreadToolState_Cancelling(:final streamedOutput) => ThreadToolLifecycleView.cancelling(streamedOutput),
  native.BridgeThreadToolState_Interrupted(:final interruptedAt, :final reason) => ThreadToolLifecycleView.interrupted(exactI64(interruptedAt, 'tool interrupted Unix seconds'), reason),
  native.BridgeThreadToolState_Succeeded(:final completedAt, :final output) => ThreadToolLifecycleView.succeeded(exactI64(completedAt, 'tool completed Unix seconds'), toolOutputFromBridge(output)),
  native.BridgeThreadToolState_Failed(:final failedAt, :final failure, :final output) => ThreadToolLifecycleView.failed(exactI64(failedAt, 'tool failed Unix seconds'), _toolFailure(failure), output == null ? null : toolOutputFromBridge(output)),
  native.BridgeThreadToolState_Denied(:final deniedAt, :final reason) => ThreadToolLifecycleView.denied(exactI64(deniedAt, 'tool denied Unix seconds'), reason),
  native.BridgeThreadToolState_Cancelled(:final cancelledAt, :final reason) => ThreadToolLifecycleView.cancelled(exactI64(cancelledAt, 'tool cancelled Unix seconds'), reason),
};

ThreadAgentIdentityView agentIdentityFromBridge(native.BridgeThreadAgentIdentity value) => ThreadAgentIdentityView(
  id: value.id, path: value.path, parentPath: value.parentPath, role: value.role, task: value.task, depth: value.depth,
);

ThreadAgentLifecycleView agentLifecycleFromBridge(native.BridgeThreadAgentState value) => switch (value) {
  native.BridgeThreadAgentState_Queued() => const ThreadAgentLifecycleView.queued(),
  native.BridgeThreadAgentState_Running() => const ThreadAgentLifecycleView.running(),
  native.BridgeThreadAgentState_Succeeded(:final completedAt, :final summary) => ThreadAgentLifecycleView.succeeded(exactI64(completedAt, 'Agent completed Unix seconds'), summary),
  native.BridgeThreadAgentState_Denied(:final deniedAt, :final reason) => ThreadAgentLifecycleView.denied(exactI64(deniedAt, 'Agent denied Unix seconds'), reason),
  native.BridgeThreadAgentState_Cancelled(:final cancelledAt, :final reason) => ThreadAgentLifecycleView.cancelled(exactI64(cancelledAt, 'Agent cancelled Unix seconds'), reason),
  native.BridgeThreadAgentState_Failed(:final failedAt, :final error) => ThreadAgentLifecycleView.failed(exactI64(failedAt, 'Agent failed Unix seconds'), error),
};

ThreadInferenceLifecycleView inferenceLifecycleFromBridge(native.BridgeThreadInferenceState value) => switch (value) {
  native.BridgeThreadInferenceState_Running() => const ThreadInferenceLifecycleView.running(),
  native.BridgeThreadInferenceState_Completed(:final completedAt, :final usage) => ThreadInferenceLifecycleView.completed(
    exactI64(completedAt, 'inference completed Unix seconds'),
    ThreadInferenceUsageView(
      promptTokens: exactU64(usage.promptTokens, 'inference prompt tokens'), completionTokens: exactU64(usage.completionTokens, 'inference completion tokens'),
      cachedPromptTokens: exactU64(usage.cachedPromptTokens, 'inference cached tokens'), totalTokens: exactU64(usage.totalTokens, 'inference total tokens'),
    ),
  ),
  native.BridgeThreadInferenceState_Failed(:final failedAt, :final error) => ThreadInferenceLifecycleView.failed(exactI64(failedAt, 'inference failed Unix seconds'), error),
  native.BridgeThreadInferenceState_Cancelled(:final cancelledAt, :final reason) => ThreadInferenceLifecycleView.cancelled(exactI64(cancelledAt, 'inference cancelled Unix seconds'), reason),
};

ThreadWaitPresentationView contentWaitFromBridge(native.BridgeThreadWaitPresentation value) => ThreadWaitPresentationView(
  intent: switch (value.intent) {
    native.BridgeThreadWaitIntent_Events(:final targets, :final timeoutMs) => ThreadWaitIntentView.events(
      targets: List.unmodifiable([
        for (final target in targets) ThreadWaitTargetView(
          taskId: target.taskId, toolName: target.toolName, summary: target.summary,
          summaryTruncated: target.summaryTruncated,
          status: target.status == null ? null : waitTargetStatusFromBridge(target.status!),
        ),
      ]),
      timeoutMs: exactU64(timeoutMs, 'wait timeout milliseconds'),
    ),
    native.BridgeThreadWaitIntent_Timer(:final durationMs) => ThreadWaitIntentView.timer(durationMs: exactU64(durationMs, 'timer duration milliseconds')),
  },
  state: waitStateFromBridge(value.state), messagesReady: value.messagesReady,
);
