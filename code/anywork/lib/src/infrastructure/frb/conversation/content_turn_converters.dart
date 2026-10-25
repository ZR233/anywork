import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/types/thread_stream.dart' as native;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'scalar_converters.dart';

/// The existing Timeline's full Turn DTO is not a TurnBrief or a replacement
/// for the independent complete-history read scope.
TurnState contentTurnFromBridge(native.BridgeTurnState value) =>
    switch (value) {
      native.BridgeTurnState_Queued(:final queuedAt) => TurnState.queued(
        queuedAt: exactI64(BigInt.from(queuedAt), 'Turn queued Unix seconds'),
      ),
      native.BridgeTurnState_Running(:final startedAt, :final phase) =>
        TurnState.running(
          startedAt: exactI64(
            BigInt.from(startedAt),
            'Turn started Unix seconds',
          ),
          phase: turnPhaseFromBridge(phase),
        ),
      native.BridgeTurnState_Completed(
        :final startedAt,
        :final completedAt,
        :final completion,
      ) =>
        TurnState.completed(
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
      native.BridgeTurnState_Cancelled(
        :final startedAt,
        :final requestedAt,
        :final completedAt,
        :final cause,
      ) =>
        TurnState.cancelled(
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
            native.BridgeTurnCancellationCause_Unspecified() =>
              const TurnCancellationCause.unspecified(),
            native.BridgeTurnCancellationCause_UserRequested() =>
              const TurnCancellationCause.userRequested(),
            native.BridgeTurnCancellationCause_RuntimeShutdown() =>
              const TurnCancellationCause.runtimeShutdown(),
            native.BridgeTurnCancellationCause_AgentClosed() =>
              const TurnCancellationCause.agentClosed(),
            native.BridgeTurnCancellationCause_Interrupted() =>
              const TurnCancellationCause.interrupted(),
            native.BridgeTurnCancellationCause_Recovery() =>
              const TurnCancellationCause.recovery(),
            native.BridgeTurnCancellationCause_Coalesced(:final targetTurnId) =>
              TurnCancellationCause.coalesced(targetTurnId: targetTurnId),
          },
        ),
      native.BridgeTurnState_Failed(
        :final startedAt,
        :final completedAt,
        :final failure,
      ) =>
        TurnState.failed(
          startedAt: nullableI64(
            startedAt == null ? null : BigInt.from(startedAt),
            'Turn started Unix seconds',
          ),
          completedAt: exactI64(
            BigInt.from(completedAt),
            'Turn completed Unix seconds',
          ),
          failure: _failure(failure),
        ),
      native.BridgeTurnState_BudgetLimited(
        :final startedAt,
        :final completedAt,
        :final limit,
        :final rollover,
      ) =>
        TurnState.budgetLimited(
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
            native.BridgeTurnRolloverOutcome_NotAttempted() =>
              const TurnRolloverOutcome.notAttempted(),
            native.BridgeTurnRolloverOutcome_Succeeded() =>
              const TurnRolloverOutcome.succeeded(),
            native.BridgeTurnRolloverOutcome_Failed(:final error) =>
              TurnRolloverOutcome.failed(error: error),
          },
        ),
    };

TurnFailure _failure(native.BridgeTurnFailureDto value) {
  return TurnFailure(
    // Timeline and the independent Execution/read DTOs share the same native
    // failure vocabulary. No legacy Debug labels or spelling fallbacks remain.
    category: failureCategoryFromBridge(value.category),
    providerKind: value.providerKind == null
        ? null
        : providerKindFromBridge(value.providerKind!),
    code: value.code,
    httpStatus: value.httpStatus,
    message: value.message,
    retry: retryDispositionFromBridge(value.retry),
  );
}
