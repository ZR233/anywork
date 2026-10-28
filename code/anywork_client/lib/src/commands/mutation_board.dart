import '../contracts/stamps.dart';
import '../lifecycle/resource_budget.dart';
import '../observation/latest_value.dart';

enum CommitDisposition { applied, noChange }

enum EffectPoint { immediate, nextTurn, futureSession }

enum OperationPhase {
  submitting,
  accepted,
  awaitingObservation,
  observed,
  effective,
  durable,
  rejected,
  unknownOutcome,
  syncFailed,
}

/// A local owner's concrete lifetime, independent of wire epoch spelling.
/// The owner supplies this immutable qualification at operation admission.
abstract interface class OperationObservationOwner {
  /// Retirement is permanent for this admitted lifetime; matching wire epoch
  /// text in a replacement lifetime must not make this true again.
  bool get isCurrent;
}

final class CommitReceipt {
  CommitReceipt({
    required this.operationId,
    required this.disposition,
    required Iterable<ObservationStamp> targets,
    required this.effect,
    this.effective = false,
    this.durable = false,
    this.requiresIdentityObservation = false,
  }) : targets = List.unmodifiable(targets);

  final OperationId operationId;
  final CommitDisposition disposition;
  final List<ObservationStamp> targets;
  final EffectPoint effect;
  final bool effective;
  final bool durable;
  final bool requiresIdentityObservation;
}

/// Accepted, observed, effective and durable are independent facts.
final class OperationState {
  const OperationState({
    required this.id,
    required this.target,
    this.draft,
    this.receipt,
    this.observed = false,
    this.effective = false,
    this.durable = false,
    this.failurePhase,
    this.error,
  });

  final OperationId id;
  final String target;
  final DraftStamp? draft;
  final CommitReceipt? receipt;
  final bool observed;
  final bool effective;
  final bool durable;
  final OperationPhase? failurePhase;
  final Object? error;

  OperationPhase get phase {
    if (failurePhase case final failure?) return failure;
    if (receipt != null && !observed) return OperationPhase.awaitingObservation;
    if (durable) return OperationPhase.durable;
    if (effective) return OperationPhase.effective;
    if (observed) return OperationPhase.observed;
    return OperationPhase.submitting;
  }

  bool get isPending => !observed && failurePhase != OperationPhase.rejected;
}

/// A bounded operation registry. Latest intent is separate from old outcomes.
final class MutationBoard {
  MutationBoard({
    required this.clientId,
    ResourceBudget? budget,
    this.maxRetained = 128,
    this.maxObservedResources = 1024,
  }) : budget = budget ?? ResourceBudget() {
    if (maxRetained < 1) throw ArgumentError.value(maxRetained, 'maxRetained');
    if (maxObservedResources < 1)
      throw ArgumentError.value(maxObservedResources, 'maxObservedResources');
  }

  final String clientId;
  final ResourceBudget budget;
  final int maxRetained;
  final int maxObservedResources;
  final Map<OperationId, OperationHandle> _operations = {};
  final Map<String, OperationId> _latest = {};
  final Map<String, ObservationStamp> _observed = {};
  int _sequence = 0;

  OperationHandle begin({
    required String target,
    DraftStamp? draft,
    OperationObservationOwner? observationOwner,
  }) {
    final id = OperationId('$clientId:${++_sequence}');
    final permit = budget.acquire(
      ResourceKind.pendingOperation,
      owner: id.value,
    );
    final operation = OperationHandle._(
      this,
      OperationState(id: id, target: target, draft: draft),
      permit,
      observationOwner,
    );
    _operations[id] = operation;
    _latest[target] = id;
    _prune();
    return operation;
  }

  OperationHandle? lookup(OperationId id) => _operations[id];
  OperationHandle? latest(String target) => _operations[_latest[target]];
  List<OperationState> get operations => List.unmodifiable([
    for (final handle in _operations.values) handle.state.value,
  ]);

  void observe(ObservationStamp stamp) {
    final current = _observed[stamp.resourceKey];
    if (current != null && current.covers(stamp)) return;
    // A new epoch replaces this resource's observed watermark. It cannot satisfy
    // a receipt from the previous owner because covers also checks the epoch.
    _observed.remove(stamp.resourceKey);
    _observed[stamp.resourceKey] = stamp;
    for (final operation in List.of(_operations.values)) {
      operation._mergeObservation();
    }
    final protected = {
      for (final operation in _operations.values)
        if (operation.state.value.isPending)
          for (final target
              in operation.state.value.receipt?.targets ??
                  const <ObservationStamp>[])
            target.resourceKey,
    };
    for (final key in List.of(_observed.keys)) {
      if (_observed.length <= maxObservedResources) break;
      if (!protected.contains(key)) _observed.remove(key);
    }
  }

  bool _covers(CommitReceipt receipt) =>
      !receipt.requiresIdentityObservation &&
      receipt.targets.every(
        (target) => _observed[target.resourceKey]?.covers(target) ?? false,
      );

  void _prune() {
    if (_operations.length <= maxRetained) return;
    for (final entry in List.of(_operations.entries)) {
      if (_operations.length <= maxRetained) break;
      final state = entry.value.state.value;
      if (!state.isPending && entry.value.state.observerCount == 0) {
        _operations.remove(entry.key);
        if (_latest[state.target] == state.id) _latest.remove(state.target);
        entry.value.state.close();
      }
    }
  }
}

final class OperationHandle {
  OperationHandle._(
    this._board,
    OperationState initial,
    this._permit,
    this._observationOwner,
  ) : state = LatestValue(initial);

  final MutationBoard _board;
  final ResourcePermit _permit;
  final OperationObservationOwner? _observationOwner;
  final LatestValue<OperationState> state;
  OperationId get id => state.value.id;

  void accept(CommitReceipt receipt) {
    if (receipt.operationId != id) {
      throw ArgumentError('A receipt cannot complete another operation');
    }
    final current = state.value;
    if (current.failurePhase == OperationPhase.rejected) {
      throw StateError('A rejected operation cannot subsequently be accepted');
    }
    final canObserve = _observationOwner?.isCurrent ?? true;
    _publish(
      OperationState(
        id: id,
        target: current.target,
        draft: current.draft,
        receipt: receipt,
        observed: current.observed || canObserve && _board._covers(receipt),
        effective: current.effective || receipt.effective,
        durable: current.durable || receipt.durable,
        failurePhase: canObserve ? null : current.failurePhase,
        error: canObserve ? null : current.error,
      ),
    );
  }

  void _mergeObservation() {
    final current = state.value;
    final receipt = current.receipt;
    if (receipt == null ||
        current.observed ||
        !(_observationOwner?.isCurrent ?? true) ||
        !_board._covers(receipt))
      return;
    _publish(
      OperationState(
        id: id,
        target: current.target,
        draft: current.draft,
        receipt: receipt,
        observed: true,
        effective: current.effective,
        durable: current.durable,
        failurePhase: current.failurePhase,
        error: current.error,
      ),
    );
  }

  void markEffective() => _mark(effective: true);
  void markDurable() => _mark(durable: true);

  /// Resource clocks cannot prove an identity predicate. Only the command's
  /// pre-registered owner observer may explicitly confirm this receipt.
  void markObserved() {
    final current = state.value;
    if (current.receipt?.requiresIdentityObservation != true) {
      throw StateError('Only an identity receipt can be explicitly observed');
    }
    if (!(_observationOwner?.isCurrent ?? true)) return;
    if (current.observed) return;
    _publish(
      OperationState(
        id: id,
        target: current.target,
        draft: current.draft,
        receipt: current.receipt,
        observed: true,
        effective: current.effective,
        durable: current.durable,
        failurePhase: current.failurePhase,
        error: current.error,
      ),
    );
  }

  void _mark({bool effective = false, bool durable = false}) {
    final current = state.value;
    if (current.receipt == null) {
      throw StateError(
        'Effect and durability require an authoritative receipt',
      );
    }
    _publish(
      OperationState(
        id: id,
        target: current.target,
        draft: current.draft,
        receipt: current.receipt,
        observed: current.observed,
        effective: current.effective || effective,
        durable: current.durable || durable,
        failurePhase: current.failurePhase,
        error: current.error,
      ),
    );
  }

  OperationState reject(Object error) => _fail(OperationPhase.rejected, error);
  OperationState unknownOutcome(Object error) =>
      _fail(OperationPhase.unknownOutcome, error);
  OperationState syncFailed(Object error) =>
      _fail(OperationPhase.syncFailed, error);

  OperationState _fail(OperationPhase phase, Object error) {
    final current = state.value;
    final next = OperationState(
      id: id,
      target: current.target,
      draft: current.draft,
      receipt: current.receipt,
      observed: current.observed,
      effective: current.effective,
      durable: current.durable,
      failurePhase: phase,
      error: error,
    );
    _publish(next);
    // Synchronous observers may have advanced the live handle during publish.
    return next;
  }

  void _publish(OperationState next) {
    state.publish(next);
    if (!next.isPending) _permit.release();
    _board._prune();
  }
}
