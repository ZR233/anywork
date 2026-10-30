import 'dart:async';

import '../../../accounts_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../../models/failure_models.dart';
import '../../observation/latest_value.dart' show Observation;
import '../domain/accounts_repository.dart';

/// Owns exact open/next/consumer/close lifetimes. It stores clocks, not content.
final class AccountObservations {
  AccountObservations({
    required this.feed,
    required this.budget,
    required this.owner,
    required this.consume,
    required this.failed,
  });
  final AccountFeedPort feed;
  final ResourceBudget budget;
  final String owner;
  final void Function(AccountDomainFrame) consume;
  final void Function(AccountObservationTarget, StudioFailure) failed;
  final Map<AccountObservationTarget, _AccountObservationSlot> _slots = {};
  final Set<_AccountObservationSlot> _retiring = {};
  final Map<AccountObservationTarget, Observation> _budgetWaiters = {};
  final Map<AccountObservationTarget, int> _demand = {};
  final Map<AccountObservationTarget, ResourceStamp> _observed = {};
  final Set<void Function()> _listeners = {};
  final Map<String, String> _epochs = {};
  bool _sealed = false;
  int _generation = 0;
  int get generation => _generation;
  String? _authorizedEpoch;
  String? get ownerEpoch => _authorizedEpoch;

  bool accepts(ResourceStamp stamp) => _authorizedEpoch == null
      ? _epochs[stamp.resourceKey] == null ||
            _epochs[stamp.resourceKey] == stamp.ownerEpoch
      : _authorizedEpoch == stamp.ownerEpoch;

  /// Only the runtime/bootstrap composition boundary may authorize a new owner.
  /// Retired native owners remain registered even when replacement is admitted.
  ({int generation, void Function() commit}) prepareOwnerEpoch(String epoch) {
    if (_sealed) throw StateError('Account observations are closed');
    if (epoch.isEmpty) throw ArgumentError.value(epoch, 'epoch');
    if (_authorizedEpoch == epoch)
      return (generation: _generation, commit: () {});
    _authorizedEpoch = epoch;
    final generation = ++_generation;
    _epochs.clear();
    _observed.clear();
    // Detach exactly the retiring slots before native close can synchronously
    // reenter admission. No old tail may remove a replacement by target key.
    final retiring = _slots.values.toList();
    _slots.clear();
    _retiring.addAll(retiring);
    final listeners = List.of(_listeners);
    final targets = _demand.keys.toList();
    return (
      generation: generation,
      commit: () {
        for (final slot in retiring) {
          slot.requestClose();
          unawaited(
            slot.retire().then<void>(
              (_) {},
              onError: (Object _, StackTrace _) {},
            ),
          );
        }
        for (final listener in listeners) {
          if (generation != _generation) return;
          listener();
        }
        for (final target in targets) {
          if (generation != _generation) return;
          _ensure(target, waitForBudget: true);
        }
      },
    );
  }

  ResourceStamp? stamp(AccountObservationTarget target) => _observed[target];
  Iterable<AccountObservationTarget> get targets => {
    ..._slots.keys,
    ..._observed.keys,
  };
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void apply(AccountDomainFrame frame, {int? connectionGeneration}) {
    final generation = _generation;
    if (connectionGeneration != null && connectionGeneration != _generation)
      return;
    final resource = switch (frame.target) {
      AccountSummariesTarget() || AccountDetailTarget() => 'settings',
      AccountModelsTarget() => 'model-catalog',
      AccountUsageTarget() => 'account-usage',
      AcpAuthTarget() => 'acp-auth',
      AcpInstallTarget() => 'acp-install',
      ChatGptLoginTarget(:final key) => key,
    };
    if (frame.stamp.resourceKey != resource)
      throw StateError('Account frame source mismatch');
    if (!accepts(frame.stamp)) return;
    _epochs[resource] = frame.stamp.ownerEpoch;
    final previous = _observed[frame.target];
    if (previous != null &&
        previous.ownerEpoch == frame.stamp.ownerEpoch &&
        previous.revision >= frame.stamp.revision)
      return;
    consume(frame);
    // Consumption publishes synchronously. Reconnection during that delivery
    // retires this frame; it cannot restore clocks cleared by the new owner.
    if (generation != _generation) return;
    _observed[frame.target] = frame.stamp;
    for (final listener in List.of(_listeners)) {
      if (generation != _generation) return;
      listener();
    }
  }

  AccountDemand acquire(AccountObservationTarget target) {
    if (_sealed) throw StateError('Account observations are closed');
    final previous = _demand[target] ?? 0;
    _demand[target] = previous + 1;
    try {
      _ensure(target);
    } catch (_) {
      if (previous == 0) {
        _demand.remove(target);
      } else {
        _demand[target] = previous;
      }
      rethrow;
    }
    return _AccountDemand(() => _release(target));
  }

  void _ensure(AccountObservationTarget target, {bool waitForBudget = false}) {
    if (_sealed || (_demand[target] ?? 0) == 0) return;
    final existing = _slots[target];
    if (existing != null) {
      if (existing._stop)
        unawaited(
          existing.retire().then<void>((_) {
            _ensure(target);
          }, onError: (Object _, StackTrace _) {}),
        );
      return;
    }
    ResourcePermit permit;
    try {
      permit = budget.acquire(
        ResourceKind.observer,
        owner: '$owner:account:${target.key}',
        phase: ResourcePhase.opening,
      );
    } on ResourceBudgetExceeded {
      if (!waitForBudget) rethrow;
      _budgetWaiters.putIfAbsent(
        target,
        () => budget.watchAvailability(ResourceKind.observer, () {
          _budgetWaiters.remove(target)?.cancel();
          _ensure(target, waitForBudget: true);
        }),
      );
      return;
    }
    _budgetWaiters.remove(target)?.cancel();
    final slot = _AccountObservationSlot(
      target: target,
      owner: this,
      generation: _generation,
      permit: permit,
    );
    _slots[target] = slot;
    slot.start();
  }

  Future<void> _release(AccountObservationTarget target) async {
    final count = _demand[target] ?? 0;
    if (count <= 1) {
      _demand.remove(target);
      _budgetWaiters.remove(target)?.cancel();
      final slot = _slots[target];
      if (slot != null) await slot.retire();
    } else {
      _demand[target] = count - 1;
    }
  }

  void _settled(_AccountObservationSlot slot) {
    if (identical(_slots[slot.target], slot)) _slots.remove(slot.target);
    _retiring.remove(slot);
    slot.permit.release();
    if (!slot.failed) _ensure(slot.target);
  }

  Future<void> refresh(AccountObservationTarget target) async {
    if (_sealed) throw StateError('Account observations are closed');
    final generation = _generation;
    final frame = await feed.readAccountDomain(target);
    if (generation != _generation || !accepts(frame.stamp))
      throw StateError('Account owner changed during read');
    if (frame.target != target)
      throw StateError('Account read target mismatch');
    apply(frame);
  }

  Future<CloseReport> close({required DateTime deadline}) async {
    _sealed = true;
    _demand.clear();
    for (final waiter in _budgetWaiters.values) {
      waiter.cancel();
    }
    _budgetWaiters.clear();
    final slots = [..._slots.values, ..._retiring];
    // Broadcast before waiting for any individual late open or native read.
    for (final slot in slots) {
      slot.requestClose();
    }
    final unresolved = <UnresolvedResource>[];
    await Future.wait([
      for (final slot in slots)
        () async {
          try {
            final remaining = deadline.difference(DateTime.now());
            await slot.retire().timeout(
              remaining > Duration.zero
                  ? remaining
                  : const Duration(microseconds: 1),
            );
          } catch (error) {
            slot.permit.mark(ResourcePhase.unresolved);
            unresolved.add(
              UnresolvedResource(
                owner: '$owner:account:${slot.target.key}',
                attemptId: const AttemptId(0),
                reason: error,
              ),
            );
          }
        }(),
    ]);
    return CloseReport(unresolved: unresolved);
  }
}

final class _AccountDemand implements AccountDemand {
  _AccountDemand(this._release);
  final Future<void> Function() _release;
  Future<void>? _releasing;
  @override
  Future<void> release() => _releasing ??= _release();
}

final class _AccountObservationSlot {
  _AccountObservationSlot({
    required this.target,
    required this.owner,
    required this.permit,
    required this.generation,
  });
  final AccountObservationTarget target;
  final AccountObservations owner;
  final ResourcePermit permit;
  final int generation;
  AccountDomainObservation? _handle;
  final Completer<void> _consumer = Completer<void>();
  Future<void>? _closing;
  bool _stop = false;
  bool _settled = false;
  bool failed = false;

  void start() {
    // A failed consumer always retires its source. No successor next is issued
    // after a frame failed reduction or its identity could not be verified.
    unawaited(
      _run().then<void>(
        (_) {
          _consumer.complete();
        },
        onError: (Object error, StackTrace stack) {
          failed = true;
          _consumer.complete();
          if (generation == owner.generation)
            owner.failed(
              target,
              error is StudioFailure
                  ? error
                  : const StudioFailure(
                      code: StudioFailureCode.internal,
                      message: 'Account observation failed',
                      retryable: true,
                      correlationId: 'accounts-observation',
                    ),
            );
          unawaited(
            retire().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          );
        },
      ),
    );
  }

  Future<void> _run() async {
    final handle = await owner.feed.openAccountObservation(target);
    _handle = handle;
    if (_stop) {
      handle.requestClose();
      return;
    }
    permit.mark(ResourcePhase.active);
    while (!_stop) {
      final frame = await handle.next();
      if (frame == null) {
        if (!_stop) throw StateError('Account observation ended without close');
        return;
      }
      if (frame.target != target)
        throw StateError('Account observation target mismatch');
      // Even a completed next racing release is consumed before close. Dropping
      // it then continuing the same source would lose the native baseline.
      owner.apply(frame, connectionGeneration: generation);
    }
  }

  void requestClose() {
    _stop = true;
    if (!_settled) permit.mark(ResourcePhase.retiring);
    _handle?.requestClose();
  }

  Future<void> retire() {
    if (_settled) return Future.value();
    final existing = _closing;
    if (existing != null) return existing;
    requestClose();
    final result = () async {
      await _consumer.future;
      final handle = _handle;
      if (handle != null) await handle.close();
      _settled = true;
      owner._settled(this);
    }();
    _closing = result;
    unawaited(
      result.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          // Retain the exact handle and budget; the next close retries that owner.
          _closing = null;
          permit.mark(ResourcePhase.unresolved);
        },
      ),
    );
    return result;
  }
}
