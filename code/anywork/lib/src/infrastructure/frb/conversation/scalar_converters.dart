import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart' show ThreadStatus;

import '../../../rust/api/studio/conversation/execution.dart' as execution;
import '../../../rust/api/studio/types/settings.dart' as settings;
import '../../../rust/api/studio/types/thread_activity.dart' as activity;
import '../../../rust/api/studio/types/thread_stream.dart' as native;
import '../../../rust/api/studio/types/thread_stream/item.dart' as content;
import '../../../rust/api/studio/types/turn_failure.dart' as failures;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';

ThreadStatus threadStatusFromBridge(native.BridgeThreadStatus value) => switch (value) {
  native.BridgeThreadStatus.idle => ThreadStatus.idle,
  native.BridgeThreadStatus.queued => ThreadStatus.queued,
  native.BridgeThreadStatus.running => ThreadStatus.running,
  native.BridgeThreadStatus.waitingTool => ThreadStatus.waitingTool,
  native.BridgeThreadStatus.waitingInteraction => ThreadStatus.waitingInteraction,
  native.BridgeThreadStatus.cancelling => ThreadStatus.cancelling,
  native.BridgeThreadStatus.closing => ThreadStatus.closing,
  native.BridgeThreadStatus.closed => ThreadStatus.closed,
  native.BridgeThreadStatus.faulted => ThreadStatus.faulted,
};

TurnPhase turnPhaseFromBridge(native.BridgeTurnPhase value) => switch (value) {
  native.BridgeTurnPhase.preparing => TurnPhase.preparing,
  native.BridgeTurnPhase.thinking => TurnPhase.thinking,
  native.BridgeTurnPhase.responding => TurnPhase.responding,
  native.BridgeTurnPhase.planning => TurnPhase.planning,
  native.BridgeTurnPhase.runningTool => TurnPhase.runningTool,
  native.BridgeTurnPhase.persisting => TurnPhase.persisting,
};

TurnCompletion turnCompletionFromBridge(native.BridgeTurnCompletion value) => switch (value) {
  native.BridgeTurnCompletion.normal => TurnCompletion.normal,
  native.BridgeTurnCompletion.interactionRequested => TurnCompletion.interactionRequested,
};

BudgetLimitSnapshot budgetLimitFromBridge(native.BridgeTurnBudgetLimit value) => BudgetLimitSnapshot(
  kind: switch (value.kind) {
    native.BridgeTurnBudgetLimitKind.modelStep => BudgetLimitKind.modelStep,
    native.BridgeTurnBudgetLimitKind.toolCall => BudgetLimitKind.toolCall,
    native.BridgeTurnBudgetLimitKind.wait => BudgetLimitKind.wait,
    native.BridgeTurnBudgetLimitKind.wallClock => BudgetLimitKind.wallClock,
    native.BridgeTurnBudgetLimitKind.agentCount => BudgetLimitKind.agentCount,
    native.BridgeTurnBudgetLimitKind.agentDepth => BudgetLimitKind.agentDepth,
    native.BridgeTurnBudgetLimitKind.finalization => BudgetLimitKind.finalization,
  },
  usage: BudgetUsage(
    modelSteps: value.usage.modelSteps,
    toolCalls: value.usage.toolCalls,
    waitCalls: value.usage.waitCalls,
    elapsedMs: exactU64(value.usage.elapsedMs, 'budget elapsed milliseconds'),
  ),
);

TurnCancellationKind cancellationKindFromBridge(execution.BridgeTurnCancellationKind value) => switch (value) {
  execution.BridgeTurnCancellationKind.unspecified => TurnCancellationKind.unspecified,
  execution.BridgeTurnCancellationKind.userRequested => TurnCancellationKind.userRequested,
  execution.BridgeTurnCancellationKind.runtimeShutdown => TurnCancellationKind.runtimeShutdown,
  execution.BridgeTurnCancellationKind.agentClosed => TurnCancellationKind.agentClosed,
  execution.BridgeTurnCancellationKind.interrupted => TurnCancellationKind.interrupted,
  execution.BridgeTurnCancellationKind.recovery => TurnCancellationKind.recovery,
  execution.BridgeTurnCancellationKind.coalesced => TurnCancellationKind.coalesced,
};

TurnFailureCategory failureCategoryFromBridge(failures.BridgeTurnFailureCategory value) => switch (value) {
  failures.BridgeTurnFailureCategory.provider => TurnFailureCategory.provider,
  failures.BridgeTurnFailureCategory.providerCapacity => TurnFailureCategory.providerCapacity,
  failures.BridgeTurnFailureCategory.tool => TurnFailureCategory.tool,
  failures.BridgeTurnFailureCategory.validation => TurnFailureCategory.validation,
  failures.BridgeTurnFailureCategory.protocol => TurnFailureCategory.protocol,
  failures.BridgeTurnFailureCategory.internal => TurnFailureCategory.internal,
};

ProviderFailureKind providerKindFromBridge(failures.BridgeProviderFailureKind value) => switch (value) {
  failures.BridgeProviderFailureKind.authentication => ProviderFailureKind.authentication,
  failures.BridgeProviderFailureKind.authorization => ProviderFailureKind.authorization,
  failures.BridgeProviderFailureKind.capacity => ProviderFailureKind.capacity,
  failures.BridgeProviderFailureKind.configuration => ProviderFailureKind.configuration,
  failures.BridgeProviderFailureKind.transport => ProviderFailureKind.transport,
  failures.BridgeProviderFailureKind.protocol => ProviderFailureKind.protocol,
  failures.BridgeProviderFailureKind.unknown => ProviderFailureKind.unknown,
};

RetryDisposition retryDispositionFromBridge(failures.BridgeRetryDisposition value) => switch (value) {
  failures.BridgeRetryDisposition_Retryable(:final retryAfterMs) =>
    RetryDisposition.retryable(retryAfterMs: nullableU64(retryAfterMs, 'retry delay milliseconds')),
  failures.BridgeRetryDisposition_Permanent() => const RetryDisposition.permanent(),
};

TurnRolloverKind rolloverKindFromBridge(execution.BridgeTurnRolloverKind value) => switch (value) {
  execution.BridgeTurnRolloverKind.notAttempted => TurnRolloverKind.notAttempted,
  execution.BridgeTurnRolloverKind.succeeded => TurnRolloverKind.succeeded,
  execution.BridgeTurnRolloverKind.failed => TurnRolloverKind.failed,
};

InteractionKind interactionKindFromBridge(execution.BridgeInteractionKind value) => switch (value) {
  execution.BridgeInteractionKind.userInput => InteractionKind.userInput,
  execution.BridgeInteractionKind.toolApproval => InteractionKind.toolApproval,
};

InteractionStatus interactionStatusFromBridge(execution.BridgeInteractionStatus value) => switch (value) {
  execution.BridgeInteractionStatus.pending => InteractionStatus.pending,
  execution.BridgeInteractionStatus.resolved => InteractionStatus.resolved,
  execution.BridgeInteractionStatus.cancelled => InteractionStatus.cancelled,
  execution.BridgeInteractionStatus.expired => InteractionStatus.expired,
};

ThreadActivityKind activityKindFromBridge(activity.BridgeThreadActivityKind value) => switch (value) {
  activity.BridgeThreadActivityKind.preparing => ThreadActivityKind.preparing,
  activity.BridgeThreadActivityKind.waitingApi => ThreadActivityKind.waitingApi,
  activity.BridgeThreadActivityKind.thinking => ThreadActivityKind.thinking,
  activity.BridgeThreadActivityKind.responding => ThreadActivityKind.responding,
  activity.BridgeThreadActivityKind.planning => ThreadActivityKind.planning,
  activity.BridgeThreadActivityKind.runningTool => ThreadActivityKind.runningTool,
  activity.BridgeThreadActivityKind.awaitingApproval => ThreadActivityKind.awaitingApproval,
  activity.BridgeThreadActivityKind.awaitingInput => ThreadActivityKind.awaitingInput,
  activity.BridgeThreadActivityKind.stopping => ThreadActivityKind.stopping,
};

HistoryFault historyFaultFromBridge(activity.BridgeHistoryFault value) => switch (value) {
  activity.BridgeHistoryFault.queueFull => HistoryFault.queueFull,
  activity.BridgeHistoryFault.writeFailed => HistoryFault.writeFailed,
  activity.BridgeHistoryFault.writerUnavailable => HistoryFault.writerUnavailable,
  activity.BridgeHistoryFault.noProgress => HistoryFault.noProgress,
  activity.BridgeHistoryFault.checkpointFailed => HistoryFault.checkpointFailed,
  activity.BridgeHistoryFault.blobFailed => HistoryFault.blobFailed,
};

ThreadStorageExecution storageExecutionFromBridge(activity.BridgeThreadStorageExecution value) => switch (value) {
  activity.BridgeThreadStorageExecution.running => ThreadStorageExecution.running,
  activity.BridgeThreadStorageExecution.pausing => ThreadStorageExecution.pausing,
  activity.BridgeThreadStorageExecution.paused => ThreadStorageExecution.paused,
};

TurnObservationState observationStateFromBridge(native.BridgeThreadRuntimeUsageState value) => switch (value) {
  native.BridgeThreadRuntimeUsageState.live => TurnObservationState.live,
  native.BridgeThreadRuntimeUsageState.authoritative => TurnObservationState.authoritative,
};

ModelContextUnavailable contextUnavailableFromBridge(settings.BridgeModelContextUnavailable value) => switch (value) {
  settings.BridgeModelContextUnavailable.windowUnknown => ModelContextUnavailable.windowUnknown,
  settings.BridgeModelContextUnavailable.invalidParameters => ModelContextUnavailable.invalidParameters,
  settings.BridgeModelContextUnavailable.inputBudgetExhausted => ModelContextUnavailable.inputBudgetExhausted,
};

ModelContextAdjustment contextAdjustmentFromBridge(settings.BridgeModelContextAdjustment value) => switch (value) {
  settings.BridgeModelContextAdjustment.safetyLimit => ModelContextAdjustment.safetyLimit,
};

PromptPrefixChangedReason prefixReasonFromBridge(native.BridgePromptPrefixChangedReason value) => switch (value) {
  native.BridgePromptPrefixChangedReason.initial => PromptPrefixChangedReason.initial,
  native.BridgePromptPrefixChangedReason.promptScopeChanged => PromptPrefixChangedReason.promptScopeChanged,
  native.BridgePromptPrefixChangedReason.accountChanged => PromptPrefixChangedReason.accountChanged,
  native.BridgePromptPrefixChangedReason.modelChanged => PromptPrefixChangedReason.modelChanged,
  native.BridgePromptPrefixChangedReason.baseInstructionsChanged => PromptPrefixChangedReason.baseInstructionsChanged,
  native.BridgePromptPrefixChangedReason.globalInstructionsChanged => PromptPrefixChangedReason.globalInstructionsChanged,
  native.BridgePromptPrefixChangedReason.modeRoleChanged => PromptPrefixChangedReason.modeRoleChanged,
  native.BridgePromptPrefixChangedReason.skillCatalogChanged => PromptPrefixChangedReason.skillCatalogChanged,
  native.BridgePromptPrefixChangedReason.workspaceInstructionsChanged => PromptPrefixChangedReason.workspaceInstructionsChanged,
  native.BridgePromptPrefixChangedReason.requestPropertiesChanged => PromptPrefixChangedReason.requestPropertiesChanged,
  native.BridgePromptPrefixChangedReason.fixedPrefixChanged => PromptPrefixChangedReason.fixedPrefixChanged,
  native.BridgePromptPrefixChangedReason.toolSchemaChanged => PromptPrefixChangedReason.toolSchemaChanged,
  native.BridgePromptPrefixChangedReason.contextCompacted => PromptPrefixChangedReason.contextCompacted,
  native.BridgePromptPrefixChangedReason.contextAppended => PromptPrefixChangedReason.contextAppended,
  native.BridgePromptPrefixChangedReason.contextRecovered => PromptPrefixChangedReason.contextRecovered,
};

PlanPhase planPhaseFromBridge(native.BridgePlanPhase value) => switch (value) {
  native.BridgePlanPhase.drafting => PlanPhase.drafting,
  native.BridgePlanPhase.awaitingConfirmation => PlanPhase.awaitingConfirmation,
  native.BridgePlanPhase.revisionRequested => PlanPhase.revisionRequested,
  native.BridgePlanPhase.approved => PlanPhase.approved,
};

WorkflowLifecycle workflowLifecycleFromBridge(native.BridgeWorkflowRunLifecycle value) => switch (value) {
  native.BridgeWorkflowRunLifecycle.active => WorkflowLifecycle.active,
  native.BridgeWorkflowRunLifecycle.terminal => WorkflowLifecycle.terminal,
};

ThreadWaitState waitStateFromBridge(content.BridgeThreadWaitState value) => switch (value) {
  content.BridgeThreadWaitState.waiting => ThreadWaitState.waiting,
  content.BridgeThreadWaitState.ready => ThreadWaitState.ready,
  content.BridgeThreadWaitState.timedOut => ThreadWaitState.timedOut,
  content.BridgeThreadWaitState.elapsed => ThreadWaitState.elapsed,
  content.BridgeThreadWaitState.cancelled => ThreadWaitState.cancelled,
  content.BridgeThreadWaitState.failed => ThreadWaitState.failed,
  content.BridgeThreadWaitState.interrupted => ThreadWaitState.interrupted,
};

ThreadWaitTargetStatus waitTargetStatusFromBridge(content.BridgeThreadWaitTargetStatus value) => switch (value) {
  content.BridgeThreadWaitTargetStatus.running => ThreadWaitTargetStatus.running,
  content.BridgeThreadWaitTargetStatus.succeeded => ThreadWaitTargetStatus.succeeded,
  content.BridgeThreadWaitTargetStatus.failed => ThreadWaitTargetStatus.failed,
  content.BridgeThreadWaitTargetStatus.cancelled => ThreadWaitTargetStatus.cancelled,
  content.BridgeThreadWaitTargetStatus.interrupted => ThreadWaitTargetStatus.interrupted,
};
