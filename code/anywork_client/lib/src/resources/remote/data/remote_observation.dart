import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

/// Private-to-remote publishing capability with independently charged leases.
final class RemoteValue<T> {
  RemoteValue(T initial, this.budget, this.owner) : _source = LatestValue(initial);
  final ResourceBudget budget;
  final String owner;
  final LatestValue<T> _source;
  final Set<_RemoteObservation> _leases = {};
  bool _closed = false;
  late final ReadonlyLatestValue<T> readonly = _RemoteReadonly(this);

  T get value => _source.value;
  void publish(T next) => _source.publish(next);

  ResourcePermit _permit() {
    if (_closed) throw remoteCancelled();
    try {
      return budget.acquire(ResourceKind.observer, owner: owner);
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
  }

  Observation watch(void Function(T) listener, {bool fireImmediately = false}) {
    final permit = _permit();
    final lease = _RemoteObservation(permit, _leases);
    try {
      lease.delegate = _source.watch(listener);
      _leases.add(lease);
      if (fireImmediately) {
        try {
          listener(value);
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

  Future<T> waitFor(bool Function(T) predicate) {
    final permit = _permit();
    return _source.waitFor(predicate).whenComplete(permit.release);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final lease in List.of(_leases)) {
      lease.cancel();
    }
    _source.close();
  }
}

final class _RemoteReadonly<T> implements ReadonlyLatestValue<T> {
  _RemoteReadonly(this.owner);
  final RemoteValue<T> owner;
  @override
  T get value => owner.value;
  @override
  int get observerCount => owner._source.observerCount;
  @override
  Observation watch(void Function(T) listener, {bool fireImmediately = false}) =>
      owner.watch(listener, fireImmediately: fireImmediately);
  @override
  LatestWatch<T> watchLatest(void Function(T) listener) {
    final observation = watch(listener);
    return LatestWatch(value: value, observation: observation);
  }
  @override
  Future<T> waitFor(bool Function(T) predicate) => owner.waitFor(predicate);
}

final class _RemoteObservation implements Observation {
  _RemoteObservation(this.permit, this.leases);
  final ResourcePermit permit;
  final Set<_RemoteObservation> leases;
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
    leases.remove(this);
  }
}

StudioFailure remoteCancelled() => const StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'Remote admission is sealed.',
  retryable: false,
  correlationId: '',
);

StudioFailure remoteProtocol(String message) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: message,
  retryable: false,
  correlationId: '',
);

FeedCloseIssue remoteIssue(
  Object error,
  String stage,
  CleanupRecovery recovery,
) => FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: stage,
    code: error is StudioFailure ? error.code.name : 'remoteOwnerFailed',
    message: error is StudioFailure ? error.message : 'Remote owner cleanup failed.',
    retryable: error is StudioFailure && error.retryable,
    correlationId: error is StudioFailure ? error.correlationId : '',
  ),
  recovery: recovery,
);
