import '../../../resources_ports.dart';

/// Charges observers to the same budget without storing a second canonical value.
final class ConversationMirror<T> {
  ConversationMirror(
    T initial, {
    required ResourceBudget budget,
    required String owner,
  }) : _source = LatestValue(initial),
       _budget = budget,
       _owner = owner;

  final LatestValue<T> _source;
  final ResourceBudget _budget;
  final String _owner;
  final Set<_MirrorObservation> _observations = {};
  bool _closed = false;

  T get value => _source.value;
  int get observerCount => _source.observerCount;
  late final ReadonlyLatestValue<T> readonly = _ReadonlyConversationMirror(
    this,
  );

  void publish(T next) => _source.publish(next);

  Observation watch(void Function(T) listener, {bool fireImmediately = false}) {
    if (_closed) throw _closedFailure;
    final ResourcePermit permit;
    try {
      permit = _budget.acquire(ResourceKind.observer, owner: _owner);
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    final lease = _MirrorObservation(permit, _observations.remove);
    _observations.add(lease);
    try {
      lease.attach(_source.watch(listener, fireImmediately: fireImmediately));
      return lease;
    } catch (_) {
      lease.cancel();
      rethrow;
    }
  }

  LatestWatch<T> watchLatest(void Function(T) listener) {
    final observation = watch(listener);
    return LatestWatch(value: value, observation: observation);
  }

  Future<T> waitFor(bool Function(T) predicate) {
    if (_closed) return Future.error(_closedFailure);
    final ResourcePermit permit;
    try {
      permit = _budget.acquire(ResourceKind.observer, owner: _owner);
    } catch (error, stack) {
      return Future.error(
        error is ResourceBudgetExceeded ? error.failure : error,
        stack,
      );
    }
    return _source.waitFor(predicate).whenComplete(permit.release);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final observation in List.of(_observations)) {
      observation.cancel();
    }
    _source.close();
  }

  static const _closedFailure = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'The conversation mirror is closed.',
    retryable: false,
    correlationId: 'conversation-mirror-closed',
  );
}

final class _ReadonlyConversationMirror<T> implements ReadonlyLatestValue<T> {
  const _ReadonlyConversationMirror(this._owner);
  final ConversationMirror<T> _owner;
  @override
  T get value => _owner.value;
  @override
  int get observerCount => _owner.observerCount;
  @override
  Observation watch(
    void Function(T) listener, {
    bool fireImmediately = false,
  }) => _owner.watch(listener, fireImmediately: fireImmediately);
  @override
  LatestWatch<T> watchLatest(void Function(T) listener) =>
      _owner.watchLatest(listener);
  @override
  Future<T> waitFor(bool Function(T) predicate) => _owner.waitFor(predicate);
}

final class _MirrorObservation implements Observation {
  _MirrorObservation(this._permit, this._remove);
  final ResourcePermit _permit;
  final bool Function(_MirrorObservation) _remove;
  Observation? _source;
  bool _cancelled = false;

  void attach(Observation source) {
    _source = source;
    if (_cancelled) source.cancel();
  }

  @override
  bool get isCancelled => _cancelled;
  @override
  bool get isPaused => _source?.isPaused ?? false;
  @override
  void pause() => _source?.pause();
  @override
  void resume() => _source?.resume();
  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _source?.cancel();
    _remove(this);
    _permit.release();
  }
}
