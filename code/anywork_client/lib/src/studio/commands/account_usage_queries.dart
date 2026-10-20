import 'dart:async';

import '../../../anywork_client.dart' show ReadModel;
import '../../../models.dart';
import '../../../studio_ports.dart';
import '../anywork_client.dart';

/// Client-owned per-instance usage query coordination.
///
/// Canonical usage facts still enter only through [AnyworkClient.accountUsage].
/// This owner tracks in-flight identities, transport diagnostics and close/join.
class AccountUsageQueries extends ReadModel<AccountUsageQueryState> {
  AccountUsageQueries(this._client) : super(const AccountUsageQueryState());

  final AnyworkClient _client;
  final Map<String, _InFlightUsageQuery> _inFlight = {};
  bool _closed = false;

  StudioTransport get _api => _client.transport;

  Future<void> refresh(String accountId) {
    if (_closed) {
      return Future.error(StateError('Account usage queries are closed'));
    }
    final identity = _identityFor(accountId);
    if (identity == null) {
      return Future.error(
        ArgumentError.value(
          accountId,
          'accountId',
          'is not in canonical accounts',
        ),
      );
    }
    final existing = _inFlight[accountId];
    if (existing != null && existing.identity == identity) {
      return existing.future;
    }
    final generation = (existing?.generation ?? 0) + 1;
    existing?.invalidate();
    final operation = _InFlightUsageQuery(
      identity: identity,
      generation: generation,
    );
    _inFlight[accountId] = operation;
    _publish(
      loading: {...state.loadingAccountIds, accountId},
      errors: _withoutError(accountId),
    );
    operation.completeWith(_run(operation));
    return operation.future;
  }

  Future<void> refreshAll() {
    if (_closed) {
      return Future.error(StateError('Account usage queries are closed'));
    }
    final tasks = [
      for (final account in _canonicalAccounts())
        refresh(account.id)
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ];
    if (tasks.isEmpty) return Future<void>.value();
    return Future.wait(tasks);
  }

  /// Drop a deleted instance so late ACKs cannot resurrect it.
  void forget(String accountId) {
    final existing = _inFlight.remove(accountId);
    existing?.invalidate();
    _publish(
      loading: Set<String>.from(state.loadingAccountIds)..remove(accountId),
      errors: _withoutError(accountId),
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
    final accountId = operation.identity.accountId;
    try {
      final snapshot = await _api.checkAccountUsage(accountId);
      if (!_accepts(operation)) return;
      _client.accountUsage.apply(snapshot);
      _finish(operation, error: null);
    } catch (error) {
      if (!_accepts(operation)) return;
      _finish(operation, error: error.toString());
      rethrow;
    }
  }

  bool _accepts(_InFlightUsageQuery operation) {
    if (!identical(_inFlight[operation.identity.accountId], operation)) {
      return false;
    }
    if (_closed) return false;
    return _identityFor(operation.identity.accountId) == operation.identity;
  }

  void _finish(_InFlightUsageQuery operation, {required String? error}) {
    final accountId = operation.identity.accountId;
    if (!identical(_inFlight[accountId], operation)) return;
    _inFlight.remove(accountId);
    final loading = Set<String>.from(state.loadingAccountIds)
      ..remove(accountId);
    final errors = Map<String, String>.from(state.errorsByAccountId);
    if (error == null) {
      errors.remove(accountId);
    } else {
      errors[accountId] = error;
    }
    _publish(loading: loading, errors: errors);
  }

  _UsageIdentity? _identityFor(String accountId) {
    for (final account in _canonicalAccounts()) {
      if (account.id == accountId) {
        return _UsageIdentity(account.id, account.usageQueryRevision);
      }
    }
    return null;
  }

  List<AccountSettingsView> _canonicalAccounts() {
    return _client.settings.state.canonical?.accounts ?? const [];
  }

  Map<String, String> _withoutError(String accountId) {
    if (!state.errorsByAccountId.containsKey(accountId)) {
      return state.errorsByAccountId;
    }
    return Map<String, String>.from(state.errorsByAccountId)..remove(accountId);
  }

  void _publish({
    required Set<String> loading,
    required Map<String, String> errors,
  }) {
    final next = AccountUsageQueryState(
      loadingAccountIds: Set<String>.unmodifiable(loading),
      errorsByAccountId: Map<String, String>.unmodifiable(errors),
    );
    if (next == state) return;
    state = next;
  }
}

class AccountUsageQueryState {
  const AccountUsageQueryState({
    this.loadingAccountIds = const {},
    this.errorsByAccountId = const {},
  });

  final Set<String> loadingAccountIds;
  final Map<String, String> errorsByAccountId;

  AccountUsageQueryState copyWith({
    Set<String>? loadingAccountIds,
    Map<String, String>? errorsByAccountId,
  }) {
    return AccountUsageQueryState(
      loadingAccountIds: loadingAccountIds ?? this.loadingAccountIds,
      errorsByAccountId: errorsByAccountId ?? this.errorsByAccountId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountUsageQueryState &&
          _setEquals(loadingAccountIds, other.loadingAccountIds) &&
          _mapEquals(errorsByAccountId, other.errorsByAccountId);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(loadingAccountIds),
    Object.hashAll(errorsByAccountId.entries),
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
  const _UsageIdentity(this.accountId, this.usageQueryRevision);
  final String accountId;
  final int usageQueryRevision;

  @override
  bool operator ==(Object other) =>
      other is _UsageIdentity &&
      accountId == other.accountId &&
      usageQueryRevision == other.usageQueryRevision;

  @override
  int get hashCode => Object.hash(accountId, usageQueryRevision);
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
