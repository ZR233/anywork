import 'dart:async';

/// A borrowed observation surface. Publishing and closing remain with its owner.
abstract interface class ValueObservation<T> {
  T get value;
  Observation watch(void Function(T) listener, {bool fireImmediately = false});
  LatestWatch<T> watchLatest(void Function(T) listener);
  Future<T> waitFor(bool Function(T) predicate);
}

/// A bounded display mirror. This is not a reliable event queue.
///
/// Registration and reading [value] are synchronous in the owning isolate. A
/// paused observer retains only the latest value and owns no business resource.
final class LatestValue<T> implements ValueObservation<T> {
  LatestValue(this._value);

  T _value;
  bool _closed = false;
  final Set<_Observation<T>> _observations = {};
  final Set<Completer<T>> _waiters = {};

  T get value => _value;
  int get observerCount => _observations.length;

  void publish(T next) {
    if (_closed) throw StateError('The display mirror is closed');
    _value = next;
    for (final observation in List.of(_observations)) {
      observation.deliver(next);
    }
  }

  Observation watch(void Function(T) listener, {bool fireImmediately = false}) {
    if (_closed) throw StateError('The display mirror is closed');
    final observation = _Observation<T>(this, listener);
    _observations.add(observation);
    if (fireImmediately) observation.deliver(_value);
    return observation;
  }

  /// Returns the snapshot from the same synchronous registration transaction.
  LatestWatch<T> watchLatest(void Function(T) listener) {
    final observation = watch(listener);
    return LatestWatch(value: _value, observation: observation);
  }

  Future<T> waitFor(bool Function(T) predicate) {
    if (predicate(_value)) return Future.value(_value);
    final completer = Completer<T>();
    _waiters.add(completer);
    late final Observation observation;
    observation = watch((next) {
      if (predicate(next) && !completer.isCompleted) {
        observation.cancel();
        _waiters.remove(completer);
        completer.complete(next);
      }
    });
    return completer.future;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final observation in List.of(_observations)) {
      observation.cancel();
    }
    for (final waiter in _waiters) {
      waiter.completeError(
        StateError('The display mirror closed while waiting'),
      );
    }
    _waiters.clear();
  }
}

final class LatestWatch<T> {
  const LatestWatch({required this.value, required this.observation});
  final T value;
  final Observation observation;
}

abstract interface class Observation {
  bool get isCancelled;
  bool get isPaused;
  void pause();
  void resume();
  void cancel();
}

final class _Observation<T> implements Observation {
  _Observation(this.owner, this.listener);

  final LatestValue<T> owner;
  final void Function(T) listener;
  @override
  bool isCancelled = false;
  @override
  bool isPaused = false;
  bool _hasPending = false;
  T? _pending;

  void deliver(T next) {
    if (isCancelled) return;
    if (isPaused) {
      _pending = next;
      _hasPending = true;
      return;
    }
    try {
      listener(next);
    } catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    }
  }

  @override
  void pause() {
    if (!isCancelled) isPaused = true;
  }

  @override
  void resume() {
    if (isCancelled || !isPaused) return;
    isPaused = false;
    if (_hasPending) {
      final pending = _pending as T;
      _pending = null;
      _hasPending = false;
      deliver(pending);
    }
  }

  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    _pending = null;
    _hasPending = false;
    owner._observations.remove(this);
  }
}
