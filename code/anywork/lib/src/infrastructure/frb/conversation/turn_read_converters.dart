import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/conversation/read/execution.dart' as native;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'execution_converters.dart';
import 'identity_converters.dart';
import 'scalar_converters.dart';

TurnReadHeader turnHeaderFromBridge(
  native.BridgeTurnReadHeader value, {
  required ReadScopeIdentity expectedScope,
}) => TurnReadHeader(
  scope: checkedReadScope(value.scope, expectedScope),
  inputId: nullableReadText(value.inputId),
  id: readTextFromBridge(value.id),
  threadId: readTextFromBridge(value.threadId),
  revision: exactU64(value.revision, 'Turn read revision'),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'Turn updated Unix seconds',
  ),
  state: switch (value.state) {
    native.BridgeTurnReadState_Queued(:final queuedAt) => TurnReadState.queued(
      queuedAt: exactI64(BigInt.from(queuedAt), 'Turn queued Unix seconds'),
    ),
    native.BridgeTurnReadState_Running(:final startedAt, :final phase) =>
      TurnReadState.running(
        startedAt: exactI64(
          BigInt.from(startedAt),
          'Turn started Unix seconds',
        ),
        phase: turnPhaseFromBridge(phase),
      ),
    native.BridgeTurnReadState_Completed(
      :final startedAt,
      :final completedAt,
      :final completion,
    ) =>
      TurnReadState.completed(
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
    native.BridgeTurnReadState_Cancelled(
      :final startedAt,
      :final requestedAt,
      :final completedAt,
      :final cause,
    ) =>
      TurnReadState.cancelled(
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
        cause: switch (cause) {
          native.BridgeTurnReadCancellationCause_Unspecified() =>
            const TurnReadCancellationCause.unspecified(),
          native.BridgeTurnReadCancellationCause_UserRequested() =>
            const TurnReadCancellationCause.userRequested(),
          native.BridgeTurnReadCancellationCause_RuntimeShutdown() =>
            const TurnReadCancellationCause.runtimeShutdown(),
          native.BridgeTurnReadCancellationCause_AgentClosed() =>
            const TurnReadCancellationCause.agentClosed(),
          native.BridgeTurnReadCancellationCause_Interrupted() =>
            const TurnReadCancellationCause.interrupted(),
          native.BridgeTurnReadCancellationCause_Recovery() =>
            const TurnReadCancellationCause.recovery(),
          native.BridgeTurnReadCancellationCause_Coalesced(
            :final targetTurnId,
          ) =>
            TurnReadCancellationCause.coalesced(
              targetTurnId: readTextFromBridge(targetTurnId),
            ),
        },
      ),
    native.BridgeTurnReadState_Failed(
      :final startedAt,
      :final completedAt,
      :final failure,
    ) =>
      TurnReadState.failed(
        startedAt: nullableI64(
          startedAt == null ? null : BigInt.from(startedAt),
          'Turn started Unix seconds',
        ),
        completedAt: exactI64(
          BigInt.from(completedAt),
          'Turn completed Unix seconds',
        ),
        failure: TurnFailureRead(
          category: failureCategoryFromBridge(failure.category),
          providerKind: failure.providerKind == null
              ? null
              : providerKindFromBridge(failure.providerKind!),
          code: nullableReadText(failure.code),
          httpStatus: failure.httpStatus,
          message: readTextFromBridge(failure.message),
          retry: retryDispositionFromBridge(failure.retry),
        ),
      ),
    native.BridgeTurnReadState_BudgetLimited(
      :final startedAt,
      :final completedAt,
      :final limit,
      :final rollover,
    ) =>
      TurnReadState.budgetLimited(
        startedAt: nullableI64(
          startedAt == null ? null : BigInt.from(startedAt),
          'Turn started Unix seconds',
        ),
        completedAt: exactI64(
          BigInt.from(completedAt),
          'Turn completed Unix seconds',
        ),
        limit: budgetLimitFromBridge(limit),
        rollover: switch (rollover) {
          native.BridgeTurnReadRolloverOutcome_NotAttempted() =>
            const TurnReadRolloverOutcome.notAttempted(),
          native.BridgeTurnReadRolloverOutcome_Succeeded() =>
            const TurnReadRolloverOutcome.succeeded(),
          native.BridgeTurnReadRolloverOutcome_Failed(:final error) =>
            TurnReadRolloverOutcome.failed(error: readTextFromBridge(error)),
        },
      ),
  },
);

InteractionIndexReadHeader interactionIndexHeaderFromBridge(
  native.BridgeInteractionIndexReadHeader value, {
  required ReadScopeIdentity expectedScope,
}) => InteractionIndexReadHeader(
  scope: checkedReadScope(value.scope, expectedScope),
  total: exactU64(value.total, 'interaction index count'),
  pending: exactU64(value.pending, 'interaction pending count'),
);

InteractionBriefPage interactionBriefPageFromBridge(
  native.BridgeInteractionBriefPage value, {
  required ReadScopeIdentity expectedScope,
}) => InteractionBriefPage(
  scope: checkedReadScope(value.scope, expectedScope),
  offset: exactU64(value.offset, 'interaction brief page offset'),
  total: exactU64(value.total, 'interaction brief page total'),
  items: List.unmodifiable(value.items.map(interactionBriefFromBridge)),
  nextOffset: nullableU64(
    value.nextOffset,
    'next interaction brief page offset',
  ),
);

StorageReadHeader storageHeaderFromBridge(
  native.BridgeStorageReadHeader value, {
  required ReadScopeIdentity expectedScope,
}) => StorageReadHeader(
  scope: checkedReadScope(value.scope, expectedScope),
  fault: value.fault == null ? null : historyFaultFromBridge(value.fault!),
  faultGeneration: exactU64(value.faultGeneration, 'storage fault generation'),
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
  lastError: nullableReadText(value.lastError),
);
