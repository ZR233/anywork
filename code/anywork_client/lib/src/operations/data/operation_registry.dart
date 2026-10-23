import 'dart:async';

import '../../resources/data/latest_value.dart';
import '../../resources/data/resource_budget.dart';
import '../../resources/domain/budgets.dart';
import '../../resources/domain/failures.dart';
import '../../resources/domain/identity.dart';
import '../../resources/domain/observation.dart';
import '../domain/operation_models.dart';
import '../domain/operations.dart';
import 'operation_recorder.dart';

enum _ObservationDomain { resource, view }
typedef _ObservationKey = (_ObservationDomain, String, String, String?);

_ObservationKey _observationKey(ObservationStamp stamp) => switch (stamp) {
  ResourceStamp(:final resourceKey, :final ownerEpoch) =>
    (_ObservationDomain.resource, resourceKey, ownerEpoch, null),
  ViewStamp(:final threadId, :final viewId, :final viewEpoch) =>
    (_ObservationDomain.view, threadId, viewId, viewEpoch),
};

/// The application-local operation registry. Only ports expose this writer.
final class OperationRegistry implements OperationRecorder {
  OperationRegistry({
    required this.clientId,
    required this.budget,
    this.maxRetained = 128,
    this.maxObservedResources = 1024,
  }) {
    if (maxRetained < 1) throw ArgumentError.value(maxRetained, 'maxRetained');
    if (maxObservedResources < 1) {
      throw ArgumentError.value(maxObservedResources, 'maxObservedResources');
    }
  }

  final String clientId;
  final ResourceBudget budget;
  final int maxRetained;
  final int maxObservedResources;
  final Map<OperationId, _RecordedOperation> _entries = {};
  final Map<String, OperationId> _latest = {};
  final Map<_ObservationKey, ObservationStamp> _observed = {};
  final LatestValue<List<OperationState>> _records = LatestValue(const []);
  int _sequence = 0;
  bool _sealed = false;

  @override
  late final Operations observations = _Operations(this);
  late final ReadonlyLatestValue<List<OperationState>> _recordView =
      _BudgetedLatest(_records.readonly, budget, 'operations:records');

  @override
  OperationWriter<T> begin<T>({required String target, DraftStamp? draft}) {
    if (_sealed) {
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'The operation registry is sealed.',
        retryable: false,
        correlationId: '',
      );
    }
    final id = OperationId('$clientId:${++_sequence}');
    final ResourcePermit permit;
    try {
      permit = budget.acquire(ResourceKind.pendingOperation, owner: id.value);
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    final writer = _OperationWriter<T>(
      this,
      OperationState(id: id, target: target, draft: draft),
      permit,
    );
    _entries[id] = writer;
    _latest[target] = id;
    _changed();
    return writer;
  }

  @override
  void observe(ObservationStamp stamp) {
    final key = _observationKey(stamp);
    final current = _observed[key];
    if (current != null && current.covers(stamp)) return;
    _observed.remove(key);
    _observed[key] = stamp;
    for (final entry in List.of(_entries.values)) {
      entry.mergeObservation();
    }
    final protected = {
      for (final entry in _entries.values)
        if (entry.current.isPending)
          for (final target in entry.current.receipt?.targets ??
              const <ObservationStamp>[])
            _observationKey(target),
    };
    for (final key in List.of(_observed.keys)) {
      if (_observed.length <= maxObservedResources) break;
      if (!protected.contains(key)) _observed.remove(key);
    }
    _changed();
  }

  bool _covers(CommitReceipt receipt) => receipt.targets.every(
    (target) => _observed[_observationKey(target)]?.covers(target) ?? false,
  );

  void _changed() {
    for (final entry in List.of(_entries.entries)) {
      if (_entries.length <= maxRetained) break;
      final operation = entry.value;
      if (operation.current.isPending || operation.observerCount != 0) continue;
      _entries.remove(entry.key);
      if (_latest[operation.current.target] == entry.key) {
        _latest.remove(operation.current.target);
      }
      operation.retire();
    }
    _records.publish(List.unmodifiable([
      for (final entry in _entries.values) entry.current,
    ]));
  }

  @override
  void seal() => _sealed = true;
}

abstract interface class _RecordedOperation {
  OperationObservation get observation;
  OperationState get current;
  int get observerCount;
  void mergeObservation();
  void retire();
}

final class _Operations implements Operations {
  const _Operations(this._registry);
  final OperationRegistry _registry;

  @override
  OperationObservation? lookup(OperationId id) =>
      _registry._entries[id]?.observation;
  @override
  OperationObservation? latest(String target) =>
      _registry._entries[_registry._latest[target]]?.observation;
  @override
  ReadonlyLatestValue<List<OperationState>> get records =>
      _registry._recordView;
}

final class _Ticket<T> implements OperationTicket<T> {
  const _Ticket(this.id, this.state, this.result);
  @override
  final OperationId id;
  @override
  final ReadonlyLatestValue<OperationState> state;
  @override
  final Future<CommandResult<T>> result;
}

final class _OperationWriter<T> implements OperationWriter<T>, _RecordedOperation {
  _OperationWriter(this._registry, OperationState initial, this._permit)
    : _state = LatestValue(initial);

  final OperationRegistry _registry;
  final ResourcePermit _permit;
  final LatestValue<OperationState> _state;
  final Completer<CommandResult<T>> _completion = Completer();
  CommandResult<T>? _resolution;
  T? _value;
  bool _hasValue = false;
  bool _identityEvidence = false;
  bool _effectEvidence = false;
  bool _durableEvidence = false;
  bool _retired = false;

  @override
  late final OperationTicket<T> ticket =
      _Ticket(current.id, _BudgetedLatest(_state.readonly, _registry.budget,
          'operation:${current.id.value}'), _completion.future);
  @override
  OperationObservation get observation => ticket;
  @override
  OperationState get current => _state.value;
  @override
  int get observerCount => _state.observerCount;

  void _ensureLive() {
    if (_retired) throw StateError('The operation record has retired');
  }

  void _ensureNotRejected() {
    _ensureLive();
    if (current.failurePhase == OperationFailurePhase.rejected) {
      throw StateError('Known rejection contradicts success evidence');
    }
  }

  void _validateReceipt(CommitReceipt receipt) {
    _ensureNotRejected();
    if (receipt.operationId != current.id) {
      throw ArgumentError('A receipt cannot settle another operation');
    }
    if (current.acknowledged ||
        (current.receipt != null && current.receipt != receipt)) {
      throw StateError('The receipt contradicts existing operation evidence');
    }
  }

  void _validateNoReceipt() {
    _ensureNotRejected();
    if (current.receipt != null) {
      throw StateError('Acknowledgement cannot replace an authoritative receipt');
    }
  }

  void _validateValue(T value) {
    if (_hasValue && _value != value) {
      throw StateError('The result contradicts the original operation value');
    }
  }

  bool _isObserved(CommitReceipt receipt) =>
      _registry._covers(receipt) &&
      (!receipt.requiresIdentityObservation || _identityEvidence);

  OperationState _knownState({CommitReceipt? receipt, bool acknowledged = false}) {
    final old = current;
    final knownReceipt = receipt ?? old.receipt;
    final wasUnknown = old.failurePhase == OperationFailurePhase.unknownOutcome;
    return old.copyWith(
      receipt: knownReceipt,
      acknowledged: old.acknowledged || acknowledged,
      observed: old.observed || (knownReceipt == null
          ? _identityEvidence
          : _isObserved(knownReceipt)),
      effective: old.effective || _effectEvidence || (knownReceipt?.effective ?? false),
      durable: old.durable || _durableEvidence || (knownReceipt?.durable ?? false),
      failurePhase: wasUnknown ? null : old.failurePhase,
      error: wasUnknown ? null : old.error,
    );
  }

  CommandResult<T>? _committed(OperationState next) =>
      next.receipt != null && next.observed && _hasValue
          ? CommandResult.committed(value: _value as T, receipt: next.receipt!)
          : null;

  @override
  void accepted(T value, CommitReceipt receipt) {
    _validateReceipt(receipt);
    _validateValue(value);
    _value = value;
    _hasValue = true;
    final next = _knownState(receipt: receipt);
    _publish(next, _committed(next));
  }

  @override
  void acknowledged(T value) {
    _validateNoReceipt();
    _validateValue(value);
    _value = value;
    _hasValue = true;
    _publish(_knownState(acknowledged: true), CommandResult.acknowledged(value: value));
  }

  @override
  void identityObserved() => _evidence(identity: true);
  @override
  void effective() => _evidence(effect: true);
  @override
  void durable() => _evidence(durable: true);

  @override
  void evidenceFailed(StudioFailure error) {
    _ensureLive();
    _publish(current.copyWith(evidenceError: error), null);
  }

  void _evidence({bool identity = false, bool effect = false, bool durable = false}) {
    _ensureNotRejected();
    _identityEvidence |= identity;
    _effectEvidence |= effect;
    _durableEvidence |= durable;
    // Predicates can fire during synchronous pre-dispatch registration. Retain
    // evidence without presenting it as native acceptance before reply.
    if (current.receipt == null && !current.acknowledged) return;
    final next = _knownState();
    _publish(next, _committed(next));
  }

  @override
  void rejected(StudioFailure error) {
    _ensureLive();
    if (current.receipt != null || current.acknowledged) {
      throw StateError('Known success cannot become a rejection');
    }
    if (current.failurePhase == OperationFailurePhase.rejected) {
      if (current.error == error) return;
      throw StateError('A rejection cannot replace the original rejection');
    }
    _publish(
      current.copyWith(failurePhase: OperationFailurePhase.rejected, error: error),
      CommandResult.rejected(error: error),
    );
  }

  @override
  void unknownOutcome(StudioFailure error) {
    _ensureNotRejected();
    if (current.receipt != null || current.acknowledged) {
      throw StateError('Known success cannot become unknown');
    }
    if (current.failurePhase == OperationFailurePhase.unknownOutcome) {
      if (current.error == error) return;
      throw StateError('Unknown outcome cannot discard its original diagnostic');
    }
    _publish(
      current.copyWith(failurePhase: OperationFailurePhase.unknownOutcome, error: error),
      CommandResult.unknownOutcome(error: error),
    );
  }

  void _validateSyncFailure(StudioFailure error) {
    if (_resolution is CommittedCommandResult<T> ||
        _resolution is AcknowledgedCommandResult<T>) {
      throw StateError('Synchronization must finish before settling success');
    }
    if (current.failurePhase == OperationFailurePhase.syncFailed && current.error != error) {
      throw StateError('A sync failure cannot discard its original diagnostic');
    }
  }

  @override
  void synchronizationFailed(StudioFailure error, {T? value, CommitReceipt? receipt}) {
    _ensureNotRejected();
    final knownReceipt = receipt ?? current.receipt;
    if (knownReceipt == null) {
      throw StateError('Synchronization failure requires a real receipt');
    }
    _validateReceipt(knownReceipt);
    _validateSyncFailure(error);
    if (value != null) _validateValue(value);
    if (value != null) {
      _value = value;
      _hasValue = true;
    }
    final next = _knownState(receipt: knownReceipt).copyWith(
      failurePhase: OperationFailurePhase.syncFailed, error: error);
    _publish(next, CommandResult.syncFailed(
      value: _value, receipt: knownReceipt, error: error));
  }

  @override
  void acknowledgedSynchronizationFailed(StudioFailure error, {T? value}) {
    _validateNoReceipt();
    _validateSyncFailure(error);
    if (value != null) _validateValue(value);
    if (value != null) {
      _value = value;
      _hasValue = true;
    }
    final next = _knownState(acknowledged: true).copyWith(
      failurePhase: OperationFailurePhase.syncFailed, error: error);
    _publish(next, CommandResult.acknowledgedSyncFailed(value: _value, error: error));
  }

  @override
  void mergeObservation() {
    if (_retired || current.receipt == null || current.observed) return;
    final next = _knownState();
    if (next == current) return;
    _publish(next, _committed(next));
  }

  void _publish(OperationState next, CommandResult<T>? result) {
    // Resolve once, before invoking observers which can synchronously reenter.
    if (result != null && !_completion.isCompleted) {
      _resolution = result;
      _completion.complete(result);
    }
    if (next == current) return;
    if (next.isPending) {
      _permit.mark(next.failurePhase == null
          ? ResourcePhase.active : ResourcePhase.unresolved);
    }
    _state.publish(next);
    // Release notifications can synchronously begin another operation. Publish
    // the settled state first so those callbacks never see the old pending one.
    if (!current.isPending) _permit.release();
    _registry._changed();
  }

  @override
  void retire() {
    if (_retired) return;
    _retired = true;
    _state.close();
  }
}

/// The operation owner charges observation admission before registering it.
/// Cancelling this lease only releases its own observation, never the operation.
final class _BudgetedLatest<T> implements ReadonlyLatestValue<T> {
  const _BudgetedLatest(this._source, this._budget, this._owner);
  final ReadonlyLatestValue<T> _source;
  final ResourceBudget _budget;
  final String _owner;

  @override
  T get value => _source.value;
  @override
  int get observerCount => _source.observerCount;

  ResourcePermit _reserve() {
    try {
      return _budget.acquire(ResourceKind.observer, owner: _owner);
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
  }

  @override
  Observation watch(void Function(T) listener, {bool fireImmediately = false}) {
    final permit = _reserve();
    try {
      return _PermitObservation(
        _source.watch(listener, fireImmediately: fireImmediately), permit);
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  @override
  LatestWatch<T> watchLatest(void Function(T) listener) {
    final permit = _reserve();
    try {
      final watch = _source.watchLatest(listener);
      return LatestWatch(value: watch.value,
        observation: _PermitObservation(watch.observation, permit));
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  @override
  Future<T> waitFor(bool Function(T) predicate) {
    final permit = _reserve();
    try {
      return _source.waitFor(predicate).whenComplete(permit.release);
    } catch (_) {
      permit.release();
      rethrow;
    }
  }
}

final class _PermitObservation implements Observation {
  const _PermitObservation(this._inner, this._permit);
  final Observation _inner;
  final ResourcePermit _permit;

  @override
  bool get isCancelled => _inner.isCancelled;
  @override
  bool get isPaused => _inner.isPaused;
  @override
  void pause() => _inner.pause();
  @override
  void resume() => _inner.resume();
  @override
  void cancel() {
    try {
      _inner.cancel();
    } finally {
      _permit.release();
    }
  }
}
