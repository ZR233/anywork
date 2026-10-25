import 'dart:async';

import '../domain/budgets.dart';
import '../domain/observation.dart';
import 'latest_value.dart';
import 'resource_budget.dart';
import 'resource_errors.dart';

/// A repository's sole LatestValue publisher, with budgeted observer ownership.
/// T must already be immutable at the domain's materialization boundary.
final class ResourceSource<T> implements ReadonlyLatestValue<T> {
  ResourceSource(T initial, this.budget, this.owner)
    : _source = LatestValue(initial);

  final ResourceBudget budget;
  final String owner;
  final LatestValue<T> _source;
  final Set<_ResourceObservation> _observations = {};
  final Set<void Function()> _cancelWaiters = {};
  bool _sealed = false;
  int _publication = 0;
  late final ReadonlyLatestValue<T> readonly = _ResourceReadonly(this);

  @override
  T get value => _source.value;
  @override
  int get observerCount => _source.observerCount;

  void publish(T next) {
    ++_publication;
    _source.publish(next);
  }

  void _admit() {
    if (_sealed) throw resourceCancelled;
  }

  @override
  Observation watch(void Function(T) listener, {bool fireImmediately = false}) {
    _admit();
    final ResourcePermit permit;
    try {
      permit = budget.acquire(ResourceKind.observer, owner: owner);
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    try {
      final raw = _source.watch(listener, fireImmediately: fireImmediately);
      late final _ResourceObservation observation;
      observation = _ResourceObservation(
        raw,
        permit,
        () => _observations.remove(observation),
      );
      _observations.add(observation);
      if (_sealed) observation.cancel();
      return observation;
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  @override
  LatestWatch<T> watchLatest(void Function(T) listener) {
    final observation = watch(listener);
    return LatestWatch(value: value, observation: observation);
  }

  @override
  Future<T> waitFor(bool Function(T) predicate) {
    _admit();
    final result = Completer<T>();
    void evaluate(T next) {
      if (result.isCompleted || _sealed) return;
      final publication = _publication;
      try {
        final matches = predicate(next);
        if (_sealed || publication != _publication || result.isCompleted)
          return;
        if (matches) result.complete(next);
      } catch (error, stack) {
        if (_sealed || publication != _publication || result.isCompleted)
          return;
        result.completeError(error, stack);
      }
    }

    void cancelled() {
      if (!result.isCompleted) {
        result.completeError(resourceCancelled, StackTrace.current);
      }
    }

    final observation = watch(evaluate);
    _cancelWaiters.add(cancelled);
    // No await between registration and consuming its current snapshot.
    evaluate(value);
    return result.future.whenComplete(() {
      _cancelWaiters.remove(cancelled);
      observation.cancel();
    });
  }

  /// Stops observation admission without discarding admitted domain work.
  void seal() {
    if (_sealed) return;
    _sealed = true;
    for (final cancel in List.of(_cancelWaiters)) {
      cancel();
    }
    _cancelWaiters.clear();
    for (final observation in List.of(_observations)) {
      observation.cancel();
    }
  }

  void close() {
    seal();
    _source.close();
  }
}

final class _ResourceReadonly<T> implements ReadonlyLatestValue<T> {
  const _ResourceReadonly(this._source);
  final ResourceSource<T> _source;
  @override
  T get value => _source.value;
  @override
  int get observerCount => _source.observerCount;
  @override
  Observation watch(
    void Function(T) listener, {
    bool fireImmediately = false,
  }) => _source.watch(listener, fireImmediately: fireImmediately);
  @override
  LatestWatch<T> watchLatest(void Function(T) listener) =>
      _source.watchLatest(listener);
  @override
  Future<T> waitFor(bool Function(T) predicate) => _source.waitFor(predicate);
}

final class _ResourceObservation implements Observation {
  const _ResourceObservation(this._raw, this._permit, this._remove);
  final Observation _raw;
  final ResourcePermit _permit;
  final void Function() _remove;
  @override
  bool get isCancelled => _raw.isCancelled;
  @override
  bool get isPaused => _raw.isPaused;
  @override
  void pause() => _raw.pause();
  @override
  void resume() => _raw.resume();
  @override
  void cancel() {
    try {
      _raw.cancel();
    } finally {
      _permit.release();
      _remove();
    }
  }
}
