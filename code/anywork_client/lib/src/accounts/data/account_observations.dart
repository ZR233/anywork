import 'dart:async';

import '../../../accounts_ports.dart';
import '../../../lifecycle.dart';
import '../../contracts/stamps.dart';
import '../../models/failure_models.dart';
import '../domain/accounts_repository.dart';

/// Pools account demand and admits frames; the scope owns source lifetimes.
final class AccountObservations {
  AccountObservations({
    required this.feed,
    required this.owner,
    required this.scope,
    required this.consume,
    required this.failed,
  });
  final AccountFeedPort feed;
  final String owner;
  final ClientScope scope;
  final void Function(AccountDomainFrame) consume;
  final void Function(AccountObservationTarget, StudioFailure) failed;
  final Map<AccountObservationTarget, _AccountObservationSession> _slots = {};
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
    // Keep the old identity at its target until cleanup ACK. A new generation
    // changes frame admission, not ownership of an unsuccessfully closed source.
    final retiring = _slots.values.toList();
    for (final session in retiring) {
      session.retiring = true;
    }
    final listeners = List.of(_listeners);
    final targets = _demand.keys.toList();
    return (
      generation: generation,
      commit: () {
        for (final session in retiring) {
          _joinRetirement(session);
        }
        for (final listener in listeners) {
          if (generation != _generation) return;
          listener();
        }
        for (final target in targets) {
          if (generation != _generation) return;
          _ensure(target);
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
      AcpLocalDetectionTarget() => 'acp-local-detection',
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
    return _AccountDemand(this, target);
  }

  void _ensure(AccountObservationTarget target) {
    if (_sealed || (_demand[target] ?? 0) == 0) return;
    final existing = _slots[target];
    if (existing != null) {
      if (existing.retiring) _joinRetirement(existing, resumeDemand: true);
      return;
    }
    final session = _AccountObservationSession(
      target: target,
      owner: this,
      generation: _generation,
    );
    _slots[target] = session;
    try {
      session.start();
    } catch (_) {
      if (identical(_slots[target], session)) _slots.remove(target);
      rethrow;
    }
  }

  _AccountObservationSession? _release(AccountObservationTarget target) {
    final count = _demand[target] ?? 0;
    if (count <= 1) {
      _demand.remove(target);
      final session = _slots[target];
      if (session != null) session.retiring = true;
      return session;
    } else {
      _demand[target] = count - 1;
    }
    return null;
  }

  void _joinRetirement(
    _AccountObservationSession session, {
    bool resumeDemand = false,
  }) {
    unawaited(
      _retire(session).then<void>((_) {
        if (resumeDemand) _ensure(session.target);
      }, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> _retire(
    _AccountObservationSession session, {
    bool retry = false,
  }) {
    session.retiring = true;
    Future<void> closeSource() {
      final acquisition = session.acquisition!;
      acquisition.requestClose();
      return retry ? acquisition.retryClose() : acquisition.close();
    }

    // The factory may synchronously release demand before open returns its
    // already registered acquisition. Only this callback is deferred; creation,
    // consumer completion and cleanup remain held by the scope entry.
    final closing = session.acquisition == null
        ? Future<void>.microtask(closeSource)
        : closeSource();
    return closing.then<void>((_) {
      if (!identical(_slots[session.target], session)) return;
      _slots.remove(session.target);
      if (!session.failed || session.generation != _generation) {
        _ensure(session.target);
      }
    });
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

  Future<CloseReport> close({required ClientCloseBudget budget}) {
    _sealed = true;
    _demand.clear();
    return scope.close(budget: budget);
  }

  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) async {
    final report = await scope.retryCleanup(budget: budget);
    // Cleanup remains entirely in the scope. Resume business demand only after
    // its old acquisition can join the actual owner's successful ACK.
    for (final target in _demand.keys.toList()) {
      _ensure(target);
    }
    return report;
  }
}

final class _AccountDemand implements AccountDemand {
  _AccountDemand(this._owner, this._target);
  final AccountObservations _owner;
  final AccountObservationTarget _target;
  bool _released = false;
  _AccountObservationSession? _retirement;
  List<ClientResourceId> _retirementResourceIds = const [];
  Future<void>? _releasing;

  @override
  List<ClientResourceId> get retirementResourceIds => _retirementResourceIds;

  @override
  Future<void> release() {
    final existing = _releasing;
    if (existing != null) return existing;
    final retry = _released;
    if (!_released) {
      _released = true;
      _retirement = _owner._release(_target);
      final resourceId = _retirement?.resourceId;
      _retirementResourceIds = List.unmodifiable([
        if (resourceId != null && _retirement?.acquisition?.isClosed != true)
          resourceId,
      ]);
    }
    // Install the result before invoking requestClose, which may reenter release.
    final completion = Completer<void>();
    _releasing = completion.future;
    final session = _retirement;
    completion.complete(
      session == null
          ? Future<void>.value()
          : _owner._retire(session, retry: retry),
    );
    unawaited(
      completion.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) => _releasing = null,
      ),
    );
    return completion.future;
  }
}

final class _AccountObservationSession {
  _AccountObservationSession({
    required this.target,
    required this.owner,
    required this.generation,
  });
  final AccountObservationTarget target;
  final AccountObservations owner;
  final int generation;
  ClientAcquisition<AccountDomainObservation>? acquisition;
  ClientResourceId? resourceId;
  bool retiring = false;
  bool failed = false;

  void start() {
    acquisition = owner.scope.open<AccountDomainObservation>(
      '${owner.owner}:account:${target.key}',
      (operation) {
        resourceId = operation.resourceId;
        return owner.feed.openAccountObservation(
          target,
          resourceId: operation.resourceId,
        );
      },
      ownership: ClientOwnership.proxy,
      consume: _consume,
      onFailure: (error, stack) {
        failed = true;
        retiring = true;
        try {
          if (generation == owner.generation) {
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
          }
        } finally {
          owner._joinRetirement(this);
        }
      },
    );
    if (retiring) owner._joinRetirement(this);
  }

  Future<void> _consume(
    AccountDomainObservation handle,
    ClientOperation operation,
  ) async {
    while (!operation.closeRequested) {
      final frame = await handle.next();
      if (frame == null) {
        if (!operation.closeRequested) {
          throw StateError('Account observation ended without close');
        }
        return;
      }
      if (frame.target != target)
        throw StateError('Account observation target mismatch');
      // Even a completed next racing release is consumed before close. Dropping
      // it then continuing the same source would lose the native baseline.
      owner.apply(frame, connectionGeneration: generation);
    }
  }
}
