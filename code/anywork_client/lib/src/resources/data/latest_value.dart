import 'dart:async';

import '../domain/failures.dart';
import '../domain/observation.dart';

/// A publishing capability; paused observers retain latest state, not events.
final class LatestValue<T> {
  LatestValue(this._value);

  T _value;
  bool _closed = false;
  int _publication = 0;
  final Set<_Observation<T>> _observations = {};
  final Set<_Waiter<T>> _waiters = {};

  T get value => _value;
  int get observerCount => _observations.length + _waiters.length;

  /// This object cannot be cast back to the publishing capability.
  late final ReadonlyLatestValue<T> readonly = _ReadonlyLatestValue<T>(this);

  static const _closedFailure = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'The observation source is closed.',
    retryable: false,
    correlationId: '',
  );

  void _ensureOpen() {
    if (_closed) throw _closedFailure;
  }

  void publish(T next) {
    _ensureOpen();
    _value = next;
    final publication = ++_publication;
    for (final waiter in List.of(_waiters)) {
      _evaluate(waiter, next);
      if (_closed || publication != _publication) return;
    }
    for (final observation in List.of(_observations)) {
      observation.deliver(next);
      // A synchronous nested publication already delivered the newer snapshot.
      if (_closed || publication != _publication) return;
    }
  }

  Observation watch(void Function(T) listener, {bool fireImmediately = false}) {
    _ensureOpen();
    final observation = _Observation<T>(this, listener, Zone.current);
    _observations.add(observation);
    if (fireImmediately) observation.deliver(_value);
    return observation;
  }

  LatestWatch<T> watchLatest(void Function(T) listener) {
    final observation = watch(listener);
    return LatestWatch(value: _value, observation: observation);
  }

  Future<T> waitFor(bool Function(T) predicate) {
    if (_closed) return Future.error(_closedFailure, StackTrace.current);
    final waiter = _Waiter<T>(predicate);
    // Register before running user code: a predicate may synchronously reenter.
    _waiters.add(waiter);
    _evaluate(waiter, _value);
    return waiter.completion.future;
  }

  void _evaluate(_Waiter<T> waiter, T next) {
    if (!_waiters.contains(waiter)) return;
    final publication = _publication;
    try {
      final matches = waiter.predicate(next);
      if (_closed || publication != _publication) return;
      if (matches && _waiters.remove(waiter)) waiter.completion.complete(next);
    } catch (error, stack) {
      if (_closed || publication != _publication) return;
      if (_waiters.remove(waiter)) waiter.completion.completeError(error, stack);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final observation in List.of(_observations)) {
      observation.cancel();
    }
    final waiters = List.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.completion.completeError(_closedFailure, StackTrace.current);
    }
  }
}

final class _ReadonlyLatestValue<T> implements ReadonlyLatestValue<T> {
  const _ReadonlyLatestValue(this._owner);

  final LatestValue<T> _owner;

  @override
  T get value => _owner.value;
  @override
  int get observerCount => _owner.observerCount;
  @override
  Observation watch(void Function(T) listener, {bool fireImmediately = false}) =>
      _owner.watch(listener, fireImmediately: fireImmediately);
  @override
  LatestWatch<T> watchLatest(void Function(T) listener) =>
      _owner.watchLatest(listener);
  @override
  Future<T> waitFor(bool Function(T) predicate) => _owner.waitFor(predicate);
}

final class _Waiter<T> {
  _Waiter(this.predicate);

  final bool Function(T) predicate;
  final Completer<T> completion = Completer<T>();
}

final class _Observation<T> implements Observation {
  _Observation(this._owner, this._listener, this._zone);

  final LatestValue<T> _owner;
  final void Function(T) _listener;
  final Zone _zone;
  bool _cancelled = false;
  bool _paused = false;
  bool _hasPending = false;

  @override
  bool get isCancelled => _cancelled;
  @override
  bool get isPaused => _paused;

  void deliver(T next) {
    if (_cancelled) return;
    if (_paused) {
      _hasPending = true;
      return;
    }
    try {
      _zone.runUnary(_listener, next);
    } catch (error, stack) {
      // Preserve the actual cause/stack until the observing zone receives it.
      // Even a throwing zone handler cannot interrupt the remaining listeners
      // or the publisher's cleanup in this synchronous call.
      scheduleMicrotask(() => _zone.handleUncaughtError(error, stack));
    }
  }

  @override
  void pause() {
    if (!_cancelled) _paused = true;
  }

  @override
  void resume() {
    if (_cancelled || !_paused) return;
    _paused = false;
    if (_hasPending) {
      _hasPending = false;
      deliver(_owner.value);
    }
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _hasPending = false;
    _owner._observations.remove(this);
  }
}
