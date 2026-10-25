import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

typedef SessionFacetCapture<T> = ({
  ConversationSession session,
  ReadonlyLatestValue<T> source,
  int generation,
});

/// Owns only these two observations, never a Session/demand. A same-ID Session
/// replacement rebinds by object identity; all callers consume the initial value
/// from the same synchronous registration boundary.
final class SessionFacetObserver<T> {
  SessionFacetObserver({
    required ConversationRepository repository,
    required String threadId,
    required this._source,
    required this._onValue,
    this._onBindingInvalidated,
  }) : _repository = repository,
       _threadId = threadId {
    final before = _activeVersion;
    final watched = repository.active.watchLatest(_activeChanged);
    if (_closed) {
      _cancelHandle(watched.observation);
      return;
    }
    _active = watched.observation;
    if (before == _activeVersion) {
      _bind(
        watched.value?.threadId == threadId
            ? watched.value
            : repository.existingSession(threadId),
        notify: false,
      );
    }
  }
  final ConversationRepository _repository;
  final String _threadId;
  final ReadonlyLatestValue<T> Function(ConversationSession) _source;
  final void Function(T) _onValue;
  final void Function()? _onBindingInvalidated;
  Observation? _active;
  Observation? _facet;
  ReadonlyLatestValue<T>? _boundSource;
  final List<Observation> _unreleased = [];
  final Map<Observation, ({Object error, StackTrace stack})> _cancelFailures =
      Map.identity();
  int _activeVersion = 0;
  int _intent = 0;
  ConversationSession? _desired;
  bool _notifyDesired = true;
  bool _binding = false;
  bool _releasing = false;
  ConversationSession? session;
  T? value;
  int generation = 0;
  bool _closed = false;

  SessionFacetCapture<T>? capture() {
    final owner = session;
    final source = _boundSource;
    return _closed || owner == null || source == null
        ? null
        : (session: owner, source: source, generation: generation);
  }

  bool matches(SessionFacetCapture<T> original, {bool requireActive = false}) =>
      !_closed &&
      generation == original.generation &&
      identical(session, original.session) &&
      identical(_boundSource, original.source) &&
      (!requireActive || identical(_repository.active.value, original.session));

  void _activeChanged(ConversationSession? active) {
    if (_closed) return;
    final activeVersion = ++_activeVersion;
    _onBindingInvalidated?.call();
    if (_closed || activeVersion != _activeVersion) return;
    _bind(
      active?.threadId == _threadId
          ? active
          : _repository.existingSession(_threadId),
    );
  }

  void _bind(ConversationSession? next, {bool notify = true}) {
    _desired = next;
    _notifyDesired = notify;
    _intent++;
    if (_closed || _binding) return;
    _binding = true;
    try {
      while (!_closed) {
        final intent = _intent;
        final target = _desired;
        final shouldNotify = _notifyDesired;
        if (identical(target, session) &&
            _unreleased.isEmpty &&
            (target == null && _facet == null ||
                target != null && _facet != null && _boundSource != null)) {
          return;
        }
        final old = _facet;
        _facet = null;
        _boundSource = null;
        final binding = ++generation;
        if (old != null) _unreleased.add(old);
        _onBindingInvalidated?.call();
        // Reentrant selection only changes the desired target. It cannot open
        // another watch while cancellation of the original one is in progress.
        _releaseUnresolved();
        if (_closed) return;
        if (intent != _intent) continue;
        session = target;
        if (target == null) return;
        final source = _source(target);
        if (_closed || intent != _intent) continue;
        _boundSource = source;
        var delivered = false;
        late final LatestWatch<T> watched;
        try {
          watched = source.watchLatest((value) {
            if (_closed ||
                generation != binding ||
                !identical(_boundSource, source) ||
                !identical(_desired, target)) {
              return;
            }
            delivered = true;
            this.value = value;
            _onValue(value);
          });
        } catch (_) {
          _boundSource = null;
          rethrow;
        }
        if (_closed ||
            intent != _intent ||
            generation != binding ||
            !identical(_boundSource, source)) {
          _boundSource = null;
          _cancelHandle(watched.observation);
          continue;
        }
        _facet = watched.observation;
        if (!delivered) {
          value = watched.value;
          if (shouldNotify) _onValue(watched.value);
        }
        if (intent == _intent) return;
      }
    } finally {
      _binding = false;
    }
  }

  void _cancelHandle(Observation observation) {
    _unreleased.add(observation);
    _releaseUnresolved();
  }

  void _releaseUnresolved() {
    if (_releasing) return;
    _releasing = true;
    final attempted = Set<Observation>.identity();
    Object? failure;
    StackTrace? failureStack;
    try {
      while (true) {
        final pending = _unreleased
            .where((handle) => !attempted.contains(handle))
            .toList();
        if (pending.isEmpty) break;
        for (final observation in pending) {
          attempted.add(observation);
          try {
            observation.cancel();
            _unreleased.removeWhere((handle) => identical(handle, observation));
            _cancelFailures.remove(observation);
          } catch (error, stack) {
            _cancelFailures[observation] = (error: error, stack: stack);
            failure ??= error;
            failureStack ??= stack;
          }
        }
      }
    } finally {
      _releasing = false;
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  void pause() => _facet?.pause();
  void resume() => _facet?.resume();
  void cancel() {
    _closed = true;
    _intent++;
    _boundSource = null;
    _unreleased.addAll([?_active, ?_facet]);
    _active = null;
    _facet = null;
    _releaseUnresolved();
  }
}
