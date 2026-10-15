import '../../../anywork_client.dart';
import '../../../models.dart';
import '../anywork_client.dart';
import '../thread_session_state.dart';

/// Input acceptance and Turn observation belong to their own input identity;
/// neither a Thread revision nor a receipt cursor is a durability proof.
Observation observeSubmittedInput({
  required AnyworkClient client,
  required OperationHandle operation,
  required SubmitPromptReceipt receipt,
}) {
  final stamp = ResourceStamp(
    resourceKey: 'input:${receipt.threadId}:${receipt.inputId}',
    ownerEpoch: receipt.threadId,
    revision: receipt.cursor,
  );
  // Keep the operation state alive while its separate effect/durability
  // observer remains attached, including after the observation barrier passes.
  final retainedOperation = operation.state.watch((_) {});
  ResourcePermit? permit;
  Observation? attached;
  late final _InputObservation observation;
  void merge(ThreadSessionState state) {
    if (observation.isCancelled || state.threadId != receipt.threadId) return;
    final turn = state.activeTurn?.inputId == receipt.inputId
        ? state.activeTurn
        : state.workspace?.latestTurn?.inputId == receipt.inputId
        ? state.workspace?.latestTurn
        : null;
    final contentTurns = <ThreadItemView>[
      for (final item in state.items)
        if (item.threadId == receipt.threadId &&
            item.state is ThreadTurnItemStateView &&
            (item.state as ThreadTurnItemStateView).inputId == receipt.inputId)
          item,
    ];
    final contentObserved = contentTurns.isNotEmpty;
    if (turn == null && !contentObserved) return;
    client.mutations.observe(stamp);
    if (contentTurns.any(
          (item) =>
              (item.state as ThreadTurnItemStateView).state.status !=
              StudioTurnStatus.queued,
        ) ||
        (turn != null && turn.state.status != StudioTurnStatus.queued)) {
      operation.markEffective();
    }
    // `cursor` is an input-acceptance cursor, not a ChatView or storage clock.
    // Only the matching Turn item's authoritative saved flag proves durable
    // history here; terminal/completed alone cannot satisfy this condition.
    if (contentTurns.any((item) => item.saved)) operation.markDurable();
    if (operation.state.value.effective && operation.state.value.durable) {
      observation.cancel();
    }
  }

  try {
    operation.accept(
      CommitReceipt(
        operationId: operation.id,
        disposition: CommitDisposition.applied,
        targets: [stamp],
        effect: EffectPoint.nextTurn,
      ),
    );
    permit = client.budget.acquire(
      ResourceKind.observer,
      owner: 'input:${operation.id.value}',
    );
    observation = _InputObservation(permit, retainedOperation);
    attached = observation;
    final source = client.session(receipt.threadId).source;
    final watched = source.watchLatest(merge);
    observation.source = watched.observation;
    merge(watched.value);
    return observation;
  } catch (_) {
    attached?.cancel();
    permit?.release();
    retainedOperation.cancel();
    rethrow;
  }
}

/// Owns the source listener, the operation retention and its explicit budget.
final class _InputObservation implements Observation {
  _InputObservation(this.permit, this.operation);
  final ResourcePermit permit;
  final Observation operation;
  Observation? source;
  @override
  bool isCancelled = false;
  @override
  bool get isPaused => source?.isPaused ?? false;
  @override
  void pause() {
    source?.pause();
  }

  @override
  void resume() {
    source?.resume();
  }

  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    source?.cancel();
    operation.cancel();
    permit.release();
  }
}

bool isKnownSubmissionRejection(Object error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.notFound ||
      StudioFailureCode.busy ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.overloaded => true,
      _ => false,
    };
