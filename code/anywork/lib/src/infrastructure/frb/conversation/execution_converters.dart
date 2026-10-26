import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/conversation/execution.dart' as native;
import '../../../rust/api/studio/types/runtime.dart' as runtime;
import '../../../rust/api/studio/types/thread_stream.dart' as stream;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'scalar_converters.dart';

ThreadExecutionFrame executionFrameFromBridge(
  native.BridgeExecutionFrame value,
) => switch (value) {
  native.BridgeExecutionFrame_Data(:final deliverySequence, :final event) =>
    ThreadExecutionFrame.data(
      deliverySequence: exactU64(
        deliverySequence,
        'execution delivery sequence',
      ),
      event: switch (event) {
        native.BridgeExecutionEvent_Baseline(
          :final identity,
          :final stamp,
          :final value,
        ) =>
          ThreadExecutionEvent.baseline(
            identity: feedIdentityFromBridge(identity),
            stamp: facetStampFromBridge(stamp),
            value: executionBaselineFromBridge(value),
          ),
        native.BridgeExecutionEvent_Change(
          :final stamp,
          :final baseRevision,
          :final value,
        ) =>
          ThreadExecutionEvent.change(
            stamp: facetStampFromBridge(stamp),
            baseRevision: exactU64(baseRevision, 'execution base revision'),
            value: executionChangeFromBridge(value),
          ),
      },
    ),
  native.BridgeExecutionFrame_ResyncRequired(:final identity, :final reason) =>
    ThreadExecutionFrame.resyncRequired(
      identity: feedIdentityFromBridge(identity),
      reason: resyncReasonFromBridge(reason),
    ),
  native.BridgeExecutionFrame_Failure(:final identity, :final error) =>
    ThreadExecutionFrame.failure(
      identity: feedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeExecutionFrame_Closed(:final identity, :final reason) =>
    ThreadExecutionFrame.closed(
      identity: feedIdentityFromBridge(identity),
      reason: closedReasonFromBridge(reason),
    ),
};

TurnBrief turnBriefFromBridge(native.BridgeTurnBrief value) => TurnBrief(
  reference: turnRefFromBridge(value.reference),
  revision: exactU64(value.revision, 'Turn revision'),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'Turn updated Unix seconds',
  ),
  state: switch (value.state) {
    native.BridgeTurnBriefState_Queued(:final queuedAt) =>
      TurnBriefState.queued(
        queuedAt: exactI64(BigInt.from(queuedAt), 'Turn queued Unix seconds'),
      ),
    native.BridgeTurnBriefState_Running(:final startedAt, :final phase) =>
      TurnBriefState.running(
        startedAt: exactI64(
          BigInt.from(startedAt),
          'Turn started Unix seconds',
        ),
        phase: turnPhaseFromBridge(phase),
      ),
    native.BridgeTurnBriefState_Completed(
      :final startedAt,
      :final completedAt,
      :final completion,
    ) =>
      TurnBriefState.completed(
        startedAt: nullableI64(
          startedAt == null ? null : BigInt.from(startedAt),
          'Turn started Unix seconds',
        ),
        completedAt: exactI64(
          BigInt.from(completedAt),
          'Turn completed Unix seconds',
        ),
        completion: turnCompletionFromBridge(completion),
      ),
    native.BridgeTurnBriefState_Cancelled(
      :final startedAt,
      :final requestedAt,
      :final completedAt,
      :final cause,
    ) =>
      TurnBriefState.cancelled(
        startedAt: nullableI64(
          startedAt == null ? null : BigInt.from(startedAt),
          'Turn started Unix seconds',
        ),
        requestedAt: exactI64(
          BigInt.from(requestedAt),
          'Turn cancellation Unix seconds',
        ),
        completedAt: exactI64(
          BigInt.from(completedAt),
          'Turn completed Unix seconds',
        ),
        cause: cancellationKindFromBridge(cause),
      ),
    native.BridgeTurnBriefState_Failed(
      :final startedAt,
      :final completedAt,
      :final category,
      :final providerKind,
      :final httpStatus,
      :final retry,
    ) =>
      TurnBriefState.failed(
        startedAt: nullableI64(
          startedAt == null ? null : BigInt.from(startedAt),
          'Turn started Unix seconds',
        ),
        completedAt: exactI64(
          BigInt.from(completedAt),
          'Turn completed Unix seconds',
        ),
        category: failureCategoryFromBridge(category),
        providerKind: providerKind == null
            ? null
            : providerKindFromBridge(providerKind),
        httpStatus: httpStatus,
        retry: retryDispositionFromBridge(retry),
      ),
    native.BridgeTurnBriefState_BudgetLimited(
      :final startedAt,
      :final completedAt,
      :final limit,
      :final rollover,
    ) =>
      TurnBriefState.budgetLimited(
        startedAt: nullableI64(
          startedAt == null ? null : BigInt.from(startedAt),
          'Turn started Unix seconds',
        ),
        completedAt: exactI64(
          BigInt.from(completedAt),
          'Turn completed Unix seconds',
        ),
        limit: budgetLimitFromBridge(limit),
        rollover: rolloverKindFromBridge(rollover),
      ),
  },
);

InteractionBrief interactionBriefFromBridge(
  native.BridgeInteractionBrief value,
) => InteractionBrief(
  reference: interactionRefFromBridge(value.reference),
  revision: exactU64(value.revision, 'interaction revision'),
  kind: interactionKindFromBridge(value.kind),
  status: interactionStatusFromBridge(value.status),
  createdAt: exactI64(
    BigInt.from(value.createdAt),
    'interaction created Unix seconds',
  ),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'interaction updated Unix seconds',
  ),
);

InteractionIndexHeader interactionIndexFromBridge(
  native.BridgeInteractionIndexHeader value,
) => InteractionIndexHeader(
  reference: interactionIndexRefFromBridge(value.reference),
  total: exactU64(value.total, 'interaction index total'),
  pending: exactU64(value.pending, 'interaction index pending'),
);

ActivityBrief activityBriefFromBridge(native.BridgeActivityBrief value) =>
    ActivityBrief(
      reference: activityRefFromBridge(value.reference),
      revision: exactU64(value.revision, 'activity revision'),
      kind: activityKindFromBridge(value.kind),
      toolCount: value.toolCount,
      backgroundCount: value.backgroundCount,
      activeCount: exactU64(value.activeCount, 'activity active count'),
      hasLatestStarted: value.hasLatestStarted,
    );

StorageBrief storageBriefFromBridge(native.BridgeStorageBrief value) =>
    StorageBrief(
      reference: storageRefFromBridge(value.reference),
      fault: value.fault == null ? null : historyFaultFromBridge(value.fault!),
      faultGeneration: exactU64(
        value.faultGeneration,
        'storage fault generation',
      ),
      acceptedSequence: nullableU64(
        value.acceptedSequence,
        'storage accepted sequence',
      ),
      durableSequence: nullableU64(
        value.durableSequence,
        'storage durable sequence',
      ),
      execution: storageExecutionFromBridge(value.execution),
      pressurePaused: value.pressurePaused,
      resumeRequired: value.resumeRequired,
      canResume: value.canResume,
      hasLastError: value.hasLastError,
    );

AgentExecution agentExecutionFromBridge(runtime.BridgeAgentExecution value) =>
    AgentExecution(
      id: value.id,
      phase: switch (value.phase) {
        runtime.BridgeAgentExecutionPhase.preparing =>
          AgentExecutionPhase.preparing,
        runtime.BridgeAgentExecutionPhase.awaitingStorage =>
          AgentExecutionPhase.awaitingStorage,
        runtime.BridgeAgentExecutionPhase.awaitingAdmission =>
          AgentExecutionPhase.awaitingAdmission,
        runtime.BridgeAgentExecutionPhase.running => AgentExecutionPhase.running,
        runtime.BridgeAgentExecutionPhase.stopping => AgentExecutionPhase.stopping,
      },
      turnId: value.turnId,
    );

ContinuationView continuationFromBridge(stream.BridgeContinuationView value) =>
    ContinuationView(
      id: value.id,
      sourceTurnId: value.sourceTurnId,
      reason: value.reason == null
          ? null
          : switch (value.reason!) {
              stream.BridgeContinuationReason.userStop =>
                ContinuationReason.userStop,
              stream.BridgeContinuationReason.hostShutdown =>
                ContinuationReason.hostShutdown,
              stream.BridgeContinuationReason.processInterrupted =>
                ContinuationReason.processInterrupted,
              stream.BridgeContinuationReason.stepLimit =>
                ContinuationReason.stepLimit,
              stream.BridgeContinuationReason.executionFailed =>
                ContinuationReason.executionFailed,
            },
      createdAt: exactI64(
        BigInt.from(value.createdAt),
        'continuation created Unix seconds',
      ),
      claimed: value.claimed,
    );

ThreadExecutionBaseline executionBaselineFromBridge(
  native.BridgeExecutionBaseline value,
) => ThreadExecutionBaseline(
  status: threadStatusFromBridge(value.status),
  execution: value.execution == null
      ? null
      : agentExecutionFromBridge(value.execution!),
  continuation: value.continuation == null
      ? null
      : continuationFromBridge(value.continuation!),
  activeTurn: value.activeTurn == null
      ? null
      : turnBriefFromBridge(value.activeTurn!),
  recentTerminalTurn: value.recentTerminalTurn == null
      ? null
      : turnBriefFromBridge(value.recentTerminalTurn!),
  interactions: interactionIndexFromBridge(value.interactions),
  activity: value.activity == null
      ? null
      : activityBriefFromBridge(value.activity!),
  storage: value.storage == null
      ? null
      : storageBriefFromBridge(value.storage!),
);

ThreadExecutionChange executionChangeFromBridge(
  native.BridgeExecutionChange value,
) => ThreadExecutionChange(
  status: value.status == null ? null : threadStatusFromBridge(value.status!),
  execution: switch (value.execution) {
    native.BridgeExecutionReplacement_Unchanged() =>
      const ExecutionReplacement.unchanged(),
    native.BridgeExecutionReplacement_Replace(:final value) =>
      ExecutionReplacement.replace(
        value: value == null ? null : agentExecutionFromBridge(value),
      ),
  },
  continuation: switch (value.continuation) {
    native.BridgeContinuationReplacement_Unchanged() =>
      const ContinuationReplacement.unchanged(),
    native.BridgeContinuationReplacement_Replace(:final value) =>
      ContinuationReplacement.replace(
        value: value == null ? null : continuationFromBridge(value),
      ),
  },
  turns: value.turns == null
      ? null
      : TurnsReplacement(
          activeTurn: value.turns!.activeTurn == null
              ? null
              : turnBriefFromBridge(value.turns!.activeTurn!),
          recentTerminalTurn: value.turns!.recentTerminalTurn == null
              ? null
              : turnBriefFromBridge(value.turns!.recentTerminalTurn!),
        ),
  interactions: value.interactions == null
      ? null
      : InteractionDelta(
          baseIndexRevision: exactU64(
            value.interactions!.baseIndexRevision,
            'interaction base index revision',
          ),
          index: interactionIndexFromBridge(value.interactions!.index),
          upserted: List.unmodifiable(
            value.interactions!.upserted.map(interactionBriefFromBridge),
          ),
          removedEntries: List.unmodifiable(
            value.interactions!.removedEntries.map(
              (entry) => exactU64(entry, 'removed interaction entry'),
            ),
          ),
          terminalFacts: List.unmodifiable(
            value.interactions!.terminalFacts.map(interactionBriefFromBridge),
          ),
        ),
  activity: switch (value.activity) {
    native.BridgeActivityReplacement_Unchanged() =>
      const ActivityReplacement.unchanged(),
    native.BridgeActivityReplacement_Replace(:final value) =>
      ActivityReplacement.replace(
        value: value == null ? null : activityBriefFromBridge(value),
      ),
  },
  storage: switch (value.storage) {
    native.BridgeStorageReplacement_Unchanged() =>
      const StorageReplacement.unchanged(),
    native.BridgeStorageReplacement_Replace(:final value) =>
      StorageReplacement.replace(
        value: value == null ? null : storageBriefFromBridge(value),
      ),
  },
);
