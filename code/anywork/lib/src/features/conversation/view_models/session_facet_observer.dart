import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

/// Owns only these two observations, never a Session/demand. A same-ID Session
/// replacement rebinds by object identity; all callers consume the initial value
/// from the same synchronous registration boundary.
final class SessionFacetObserver<T> {
  SessionFacetObserver({
    required ConversationRepository repository,
    required String threadId,
    required ReadonlyLatestValue<T> Function(ConversationSession) source,
    required void Function(T) onValue,
  }) : _repository = repository, _threadId = threadId, _source = source, _onValue = onValue {
    final watched = repository.active.watchLatest(_activeChanged);
    _active = watched.observation;
    _bind(watched.value?.threadId == threadId ? watched.value : repository.existingSession(threadId), notify: false);
  }
  final ConversationRepository _repository;
  final String _threadId;
  final ReadonlyLatestValue<T> Function(ConversationSession) _source;
  final void Function(T) _onValue;
  Observation? _active;
  Observation? _facet;
  ConversationSession? session;
  T? value;
  int generation = 0;
  bool _closed = false;

  void _activeChanged(ConversationSession? active) {
    if (_closed) return;
    _bind(active?.threadId == _threadId ? active : _repository.existingSession(_threadId));
  }

  void _bind(ConversationSession? next, {bool notify = true}) {
    if (identical(next, session)) return;
    _facet?.cancel();
    _facet = null;
    session = next;
    generation++;
    if (next == null) return;
    final watched = _source(next).watchLatest((value) {
      if (_closed || !identical(session, next)) return;
      this.value = value;
      _onValue(value);
    });
    _facet = watched.observation;
    value = watched.value;
    if (notify) _onValue(watched.value);
  }

  void pause() => _facet?.pause();
  void resume() => _facet?.resume();
  void cancel() {
    if (_closed) return;
    _closed = true;
    _active?.cancel(); _active = null;
    _facet?.cancel(); _facet = null;
  }
}
