import 'dart:async';

import '../../../anywork_client.dart' show Observation, ReadModel;
import '../../../models.dart';
import '../anywork_client.dart';

class ModelDetailQuery {
  const ModelDetailQuery({
    required this.settingsRevision,
    required this.catalogRevision,
    this.loading = false,
    this.value,
    this.error,
  });
  final int settingsRevision;
  final int catalogRevision;
  final bool loading;
  final DelegationModelDetail? value;
  final StudioFailure? error;
}

/// On-demand references have their own lifetime, never enter global Settings.
class ModelDetailQueries
    extends ReadModel<Map<DelegationModelKey, ModelDetailQuery>> {
  ModelDetailQueries(this._client) : super(const {}) {
    _observation = _client.settings.source.watch((_) => _invalidateChanged());
  }
  final AnyworkClient _client;
  late final Observation _observation;
  final Map<DelegationModelKey, _DetailRequest> _current = {};
  final Set<_DetailRequest> _pending = {};
  bool _closed = false;

  Future<void> refresh(DelegationModelKey key) {
    if (_closed || _client.isClosed)
      return Future.error(StateError('Model detail queries are closed'));
    final identity = _identity();
    final previous = _current[key];
    if (previous != null && previous.identity == identity)
      return previous.done.future;
    final request = _DetailRequest(key, identity);
    _current[key] = request;
    _pending.add(request);
    _put(
      key,
      ModelDetailQuery(
        settingsRevision: identity.$1,
        catalogRevision: identity.$2,
        loading: true,
      ),
    );
    unawaited(
      _run(request)
          .then(request.done.complete, onError: request.done.completeError),
    );
    return request.done.future;
  }

  /// Only releases reference data for a dismissed detail; cannot close a Session.
  void forget(DelegationModelKey key) {
    _current.remove(key);
    if (!_closed) state = Map.unmodifiable({...state}..remove(key));
  }

  Future<void> _run(_DetailRequest request) async {
    try {
      final detail = await _client.transport.getDelegationModel(request.key);
      if (detail.key != request.key) throw _stale(request.key);
      if (_identity() != request.identity) throw _stale(request.key);
      if (_accepts(request))
        _put(
          request.key,
          ModelDetailQuery(
            settingsRevision: request.identity.$1,
            catalogRevision: request.identity.$2,
            value: detail,
          ),
        );
    } catch (error) {
      final failure = error is StudioFailure
          ? error
          : StudioFailure(
              code: StudioFailureCode.internal,
              message: error.toString(),
              retryable: true,
              correlationId:
                  'client-model-detail:${request.key.accountId}/${request.key.modelId}',
            );
      if (_accepts(request))
        _put(
          request.key,
          ModelDetailQuery(
            settingsRevision: request.identity.$1,
            catalogRevision: request.identity.$2,
            error: failure,
          ),
        );
      throw failure;
    } finally {
      if (identical(_current[request.key], request))
        _current.remove(request.key);
      _pending.remove(request);
    }
  }

  bool _accepts(_DetailRequest request) =>
      !_closed && identical(_current[request.key], request);
  (int, int) _identity() => (
    _client.settings.state.settingsRevision,
    _client.settings.state.modelCatalogRevision,
  );
  void _put(DelegationModelKey key, ModelDetailQuery value) =>
      state = Map.unmodifiable({...state, key: value});

  void _invalidateChanged() {
    if (_closed) return;
    final identity = _identity();
    final next = {...state};
    var changed = false;
    for (final entry in state.entries) {
      if ((entry.value.settingsRevision, entry.value.catalogRevision) ==
          identity)
        continue;
      next[entry.key] = ModelDetailQuery(
        settingsRevision: identity.$1,
        catalogRevision: identity.$2,
        error: _stale(entry.key),
      );
      changed = true;
    }
    if (changed) state = Map.unmodifiable(next);
  }

  Future<void> close() async {
    _closed = true;
    _observation.cancel();
    await Future.wait([
      for (final request in _pending.toList())
        request.done.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
    ]);
    _current.clear();
  }
}

StudioFailure _stale(DelegationModelKey key) => StudioFailure(
  code: StudioFailureCode.staleRevision,
  message: 'Model detail identity changed: ${key.accountId}/${key.modelId}',
  retryable: true,
  correlationId: 'client-model-detail-stale',
);

class _DetailRequest {
  _DetailRequest(this.key, this.identity);
  final DelegationModelKey key;
  final (int, int) identity;
  final Completer<void> done = Completer();
}
