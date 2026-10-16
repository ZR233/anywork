import 'dart:async';

import '../../../anywork_client.dart' show ReadModel;
import '../../../models.dart';
import '../../../studio_ports.dart';
import '../anywork_client.dart';

/// Client-owned per-instance usage query coordination.
///
/// Canonical usage facts still enter only through [AnyworkClient.providerUsage].
/// This owner tracks in-flight identities, transport diagnostics and close/join.
class ProviderUsageQueries extends ReadModel<ProviderUsageQueryState> {
  ProviderUsageQueries(this._client) : super(const ProviderUsageQueryState());

  final AnyworkClient _client;
  final Map<String, _InFlightUsageQuery> _inFlight = {};
  bool _closed = false;

  StudioTransport get _api => _client.transport;

  Future<void> refresh(String providerId) {
    if (_closed) {
      return Future.error(StateError('Provider usage queries are closed'));
    }
    final identity = _identityFor(providerId);
    if (identity == null) {
      return Future.error(
        ArgumentError.value(
          providerId,
          'providerId',
          'is not in canonical providers',
        ),
      );
    }
    final existing = _inFlight[providerId];
    if (existing != null && existing.identity == identity) {
      return existing.future;
    }
    final generation = (existing?.generation ?? 0) + 1;
    existing?.invalidate();
    final operation = _InFlightUsageQuery(
      identity: identity,
      generation: generation,
    );
    _inFlight[providerId] = operation;
    _publish(
      loading: {...state.loadingProviderIds, providerId},
      errors: _withoutError(providerId),
    );
    operation.completeWith(_run(operation));
    return operation.future;
  }

  Future<void> refreshAll() {
    if (_closed) {
      return Future.error(StateError('Provider usage queries are closed'));
    }
    final tasks = [
      for (final provider in _canonicalProviders())
        refresh(provider.id)
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ];
    if (tasks.isEmpty) return Future<void>.value();
    return Future.wait(tasks);
  }

  /// Drop a deleted instance so late ACKs cannot resurrect it.
  void forget(String providerId) {
    final existing = _inFlight.remove(providerId);
    existing?.invalidate();
    _publish(
      loading: Set<String>.from(state.loadingProviderIds)..remove(providerId),
      errors: _withoutError(providerId),
    );
  }

  Future<void> close() {
    _closed = true;
    return Future.wait([
      for (final operation in List<_InFlightUsageQuery>.of(_inFlight.values))
        operation.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
    ]);
  }

  Future<void> _run(_InFlightUsageQuery operation) async {
    final providerId = operation.identity.providerId;
    try {
      final snapshot = await _api.checkProviderUsage(providerId);
      if (!_accepts(operation)) return;
      _client.providerUsage.apply(snapshot);
      _finish(operation, error: null);
    } catch (error) {
      if (!_accepts(operation)) return;
      _finish(operation, error: error.toString());
      rethrow;
    }
  }

  bool _accepts(_InFlightUsageQuery operation) {
    if (!identical(_inFlight[operation.identity.providerId], operation)) {
      return false;
    }
    if (_closed) return false;
    return _identityFor(operation.identity.providerId) == operation.identity;
  }

  void _finish(_InFlightUsageQuery operation, {required String? error}) {
    final providerId = operation.identity.providerId;
    if (!identical(_inFlight[providerId], operation)) return;
    _inFlight.remove(providerId);
    final loading = Set<String>.from(state.loadingProviderIds)
      ..remove(providerId);
    final errors = Map<String, String>.from(state.errorsByProviderId);
    if (error == null) {
      errors.remove(providerId);
    } else {
      errors[providerId] = error;
    }
    _publish(loading: loading, errors: errors);
  }

  _UsageIdentity? _identityFor(String providerId) {
    for (final provider in _canonicalProviders()) {
      if (provider.id == providerId) {
        return _UsageIdentity(provider.id, provider.usageQueryRevision);
      }
    }
    return null;
  }

  List<ProviderSettingsView> _canonicalProviders() {
    return _client.settings.state.canonical?.providers ?? const [];
  }

  Map<String, String> _withoutError(String providerId) {
    if (!state.errorsByProviderId.containsKey(providerId)) {
      return state.errorsByProviderId;
    }
    return Map<String, String>.from(state.errorsByProviderId)
      ..remove(providerId);
  }

  void _publish({
    required Set<String> loading,
    required Map<String, String> errors,
  }) {
    final next = ProviderUsageQueryState(
      loadingProviderIds: Set<String>.unmodifiable(loading),
      errorsByProviderId: Map<String, String>.unmodifiable(errors),
    );
    if (next == state) return;
    state = next;
  }
}

class ProviderUsageQueryState {
  const ProviderUsageQueryState({
    this.loadingProviderIds = const {},
    this.errorsByProviderId = const {},
  });

  final Set<String> loadingProviderIds;
  final Map<String, String> errorsByProviderId;

  ProviderUsageQueryState copyWith({
    Set<String>? loadingProviderIds,
    Map<String, String>? errorsByProviderId,
  }) {
    return ProviderUsageQueryState(
      loadingProviderIds: loadingProviderIds ?? this.loadingProviderIds,
      errorsByProviderId: errorsByProviderId ?? this.errorsByProviderId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderUsageQueryState &&
          _setEquals(loadingProviderIds, other.loadingProviderIds) &&
          _mapEquals(errorsByProviderId, other.errorsByProviderId);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(loadingProviderIds),
    Object.hashAll(errorsByProviderId.entries),
  );
}

bool _setEquals(Set<String> a, Set<String> b) {
  return a.length == b.length && a.containsAll(b);
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

class _UsageIdentity {
  const _UsageIdentity(this.providerId, this.usageQueryRevision);
  final String providerId;
  final int usageQueryRevision;

  @override
  bool operator ==(Object other) =>
      other is _UsageIdentity &&
      providerId == other.providerId &&
      usageQueryRevision == other.usageQueryRevision;

  @override
  int get hashCode => Object.hash(providerId, usageQueryRevision);
}

class _InFlightUsageQuery {
  _InFlightUsageQuery({required this.identity, required this.generation});

  final _UsageIdentity identity;
  final int generation;
  final Completer<void> _completer = Completer<void>();
  bool _invalidated = false;

  Future<void> get future => _completer.future;

  void invalidate() {
    _invalidated = true;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void completeWith(Future<void> work) {
    unawaited(
      work.then<void>(
        (_) {
          if (!_completer.isCompleted && !_invalidated) {
            _completer.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_completer.isCompleted && !_invalidated) {
            _completer.completeError(error, stackTrace);
          }
        },
      ),
    );
  }
}
