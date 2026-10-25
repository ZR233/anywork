import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/startup_values.dart';

/// Per-observation budget, not another state owner.
final class StartupStateView implements ReadonlyLatestValue<StartupState> {
  StartupStateView(this.source, this.budget);

  final LatestValue<StartupState> source;
  final ResourceBudget budget;
  final Set<_StartupObservation> _leases = {};
  bool _closed = false;

  @override
  StartupState get value => source.value;
  @override
  int get observerCount => source.observerCount;

  ResourcePermit _acquire() {
    if (_closed) {
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'Startup observation is closed.',
        retryable: false,
        correlationId: '',
      );
    }
    try {
      return budget.acquire(ResourceKind.observer, owner: 'startup-state');
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
  }

  @override
  Observation watch(
    void Function(StartupState) listener, {
    bool fireImmediately = false,
  }) {
    final permit = _acquire();
    final lease = _StartupObservation(
      permit,
      () => _leases.removeWhere((item) => identical(item.permit, permit)),
    );
    try {
      lease.delegate = source.watch(listener);
      _leases.add(lease);
      if (fireImmediately) {
        // Preserve LatestValue's listener error isolation and synchronous value.
        try {
          listener(source.value);
        } catch (error, stack) {
          final zone = Zone.current;
          scheduleMicrotask(() => zone.handleUncaughtError(error, stack));
        }
      }
      return lease;
    } catch (_) {
      lease.cancel();
      rethrow;
    }
  }

  @override
  LatestWatch<StartupState> watchLatest(void Function(StartupState) listener) {
    final observation = watch(listener);
    return LatestWatch(value: value, observation: observation);
  }

  @override
  Future<StartupState> waitFor(bool Function(StartupState) predicate) {
    final permit = _acquire();
    try {
      return source.waitFor(predicate).whenComplete(permit.release);
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final lease in List.of(_leases)) {
      lease.cancel();
    }
    source.close();
  }
}

final class _StartupObservation implements Observation {
  _StartupObservation(this.permit, this.onCancel);
  final ResourcePermit permit;
  final void Function() onCancel;
  Observation? delegate;

  @override
  bool get isCancelled => permit.isReleased;
  @override
  bool get isPaused => delegate?.isPaused ?? false;
  @override
  void pause() => delegate?.pause();
  @override
  void resume() => delegate?.resume();
  @override
  void cancel() {
    if (isCancelled) return;
    delegate?.cancel();
    permit.release();
    onCancel();
  }
}
