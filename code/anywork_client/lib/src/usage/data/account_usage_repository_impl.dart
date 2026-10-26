import 'dart:async';

import '../../../accounts_ports.dart';
import '../../accounts/data/account_observations.dart';
import '../../accounts/data/account_settings_mutations.dart'
    show isKnownAccountRejection;
import '../../accounts/domain/account_identity.dart';
import '../../accounts/domain/account_values.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../models/failure_models.dart';
import '../../observation/latest_value.dart';
import '../domain/account_usage.dart';

final class AccountUsageRepositoryImpl implements AccountUsageRepository {
  AccountUsageRepositoryImpl({
    required this.port,
    required this.observations,
    required this.accounts,
  }) {
    _accountObservation = accounts.watch((_) => _accountsChanged());
  }
  final AccountUsagePort port;
  final AccountObservations observations;
  final ValueObservation<AccountsState> accounts;
  late final Observation _accountObservation;
  final LatestValue<
    AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>
  >
  _state = LatestValue(const AccountResource());
  int? _valueGeneration;
  final Map<(int, NativeAccountIdentity, int), Future<void>> _current = {};
  final Set<Future<void>> _pending = {};
  final Set<(NativeAccountIdentity, int)> _attempted = {};
  final LatestValue<Map<NativeAccountIdentity, StudioFailure>> _queryFailures =
      LatestValue(const {});
  final Map<(int, NativeAccountIdentity, int), _UsageQueryFailure> _failures =
      {};
  final Map<(int, NativeAccountIdentity, int), _UnknownUsageQuery> _unknown =
      {};
  int _visible = 0;
  bool _closed = false;

  @override
  ValueObservation<
    AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>
  >
  get state => _state;
  @override
  ValueObservation<Map<NativeAccountIdentity, StudioFailure>>
  get queryFailures => _queryFailures;

  void Function() prepareOwnerChange(bool Function() isCurrent) {
    final current = _state.value;
    final queryFailures = _queryFailures.value;
    _attempted.clear();
    final retiring = _unknown.values.toList();
    _unknown.clear();
    _failures.clear();
    return () {
      for (final query in retiring) {
        unawaited(
          query.demand.release().then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        );
      }
      if (!isCurrent()) return;
      if (identical(queryFailures, _queryFailures.value))
        _queryFailures.publish(
          Map.unmodifiable({
            for (final entry in _failures.entries)
              entry.key.$2: entry.value.failure,
          }),
        );
      if (!isCurrent() || !identical(current, _state.value)) return;
      _state.publish(
        AccountResource(
          stamp: current.stamp,
          value: current.value,
          stale: true,
          loading: true,
        ),
      );
    };
  }

  Map<NativeAccountIdentity, int> _identities() => !accounts.value.loaded
      ? const {}
      : {
          for (final account in accounts.value.accounts)
            if (account.identity case final NativeAccountIdentity identity)
              if (account.usageQueryRevision case final revision?)
                identity: revision,
        };

  void apply(AccountUsageFrame frame) {
    final generation = observations.generation;
    final identities = _identities();
    final staleQueries = {
      for (final account in frame.accounts)
        if (identities[account.identity] != account.queryRevision)
          account.identity,
    };
    final values = <NativeAccountIdentity, AccountUsageObservation>{
      // A late old-query result is not an authoritative deletion of the new
      // query. Preserve its whole already-observed value, never splice lastGood.
      for (final entry
          in _state.value.value?.entries ??
              const <
                MapEntry<NativeAccountIdentity, AccountUsageObservation>
              >[])
        if (!_state.value.stale &&
            staleQueries.contains(entry.key) &&
            identities[entry.key] == entry.value.queryRevision)
          entry.key: entry.value,
    };
    for (final account in frame.accounts) {
      // The Rust owner alone binds last-good to a query. Never splice in a
      // previous success, fill money with zero, or reinterpret billing health.
      if (!accounts.value.loaded ||
          identities[account.identity] == account.queryRevision) {
        values[account.identity] = account;
        if (account.phase != AccountUsagePhase.unchecked)
          _attempted.add((account.identity, account.queryRevision));
      }
    }
    _valueGeneration = generation;
    _state.publish(
      AccountResource(stamp: frame.stamp, value: Map.unmodifiable(values)),
    );
    if (generation != observations.generation) return;
    _settleUnknown();
    if (generation != observations.generation) return;
    _automaticallyQuery();
  }

  void fail(StudioFailure failure) {
    final current = _state.value;
    _state.publish(
      AccountResource(
        stamp: current.stamp,
        value: current.value,
        failure: failure,
        stale: current.stale || _valueGeneration != observations.generation,
      ),
    );
  }

  void _accountsChanged() {
    if (accounts.value.stale) return;
    final generation = observations.generation;
    final identities = _identities();
    final current = _state.value;
    final retained = {
      for (final entry
          in current.value?.entries ??
              const <
                MapEntry<NativeAccountIdentity, AccountUsageObservation>
              >[])
        if (identities[entry.key] == entry.value.queryRevision)
          entry.key: entry.value,
    };
    _attempted.removeWhere(
      (identity) => identities[identity.$1] != identity.$2,
    );
    _state.publish(
      AccountResource(
        stamp: current.stamp,
        value: Map.unmodifiable(retained),
        failure: current.failure,
        stale: current.stale || _valueGeneration != observations.generation,
      ),
    );
    if (generation != observations.generation) return;
    _settleUnknown();
    if (generation != observations.generation) return;
    _automaticallyQuery();
  }

  void _settleUnknown() {
    final identities = _identities();
    for (final entry in _failures.entries.toList()) {
      final (generation, identity, queryRevision) = entry.key;
      final current = _state.value.value?[identity];
      final invalidated =
          generation != observations.generation ||
          accounts.value.loaded && identities[identity] != queryRevision;
      final terminal =
          _valueGeneration == observations.generation &&
          !_state.value.stale &&
          current != null &&
          current.queryRevision == queryRevision &&
          current.revision > entry.value.beforeRevision &&
          current.phase != AccountUsagePhase.unchecked &&
          current.phase != AccountUsagePhase.querying;
      if (!invalidated && !terminal) continue;
      _failures.remove(entry.key);
      final unknown = _unknown.remove(entry.key);
      if (unknown != null)
        unawaited(
          unknown.demand.release().then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        );
    }
    _queryFailures.publish(
      Map.unmodifiable({
        for (final entry in _failures.entries)
          entry.key.$2: entry.value.failure,
      }),
    );
  }

  @override
  AccountDemand observeVisible() {
    if (_closed) throw StateError('Account usage is closed');
    final summaries = observations.acquire(const AccountSummariesTarget());
    late final AccountDemand usage;
    try {
      usage = observations.acquire(const AccountUsageTarget());
    } catch (_) {
      unawaited(summaries.release());
      rethrow;
    }
    _visible++;
    _automaticallyQuery();
    return _UsageDemand(() async {
      _visible--;
      await Future.wait([summaries.release(), usage.release()]);
    });
  }

  void _automaticallyQuery() {
    if (_closed || _visible == 0 || !accounts.value.loaded) return;
    for (final account in accounts.value.accounts) {
      if (account.identity case final NativeAccountIdentity identity) {
        final revision = account.usageQueryRevision;
        // Remote-query capability does not gate the owner's local
        // Unsupported/MissingCredential classification for this query identity.
        if (revision == null || _attempted.contains((identity, revision)))
          continue;
        unawaited(
          refresh(identity)
              .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      }
    }
  }

  @override
  Future<void> refresh(NativeAccountIdentity identity) {
    if (_closed) return Future.error(StateError('Account usage is closed'));
    final revision = _identities()[identity];
    if (revision == null)
      return Future.error(
        ArgumentError.value(
          identity.accountId,
          'identity',
          'Account is unavailable',
        ),
      );
    final generation = observations.generation;
    final key = (generation, identity, revision);
    final existing = _current[key];
    if (existing != null) return existing;
    _attempted.add((identity, revision));
    final demand = observations.acquire(const AccountUsageTarget());
    final beforeRevision = _valueGeneration == generation
        ? (_state.value.value?[identity]?.revision ?? -1)
        : -1;
    var retained = false;
    // Register the real lifetime before invoking any reentrant adapter code.
    final completion = Completer<void>();
    final work = completion.future;
    _current[key] = work;
    _pending.add(work);
    unawaited(() async {
      try {
        final frame = await port.queryAccountUsage(identity);
        observations.apply(frame, connectionGeneration: generation);
        completion.complete();
      } catch (error, stack) {
        if (generation == observations.generation &&
            _identities()[identity] == revision) {
          _failures.putIfAbsent(
            key,
            () => _UsageQueryFailure(
              error is StudioFailure
                  ? error
                  : const StudioFailure(
                      code: StudioFailureCode.internal,
                      message: 'Usage query transport failed',
                      retryable: true,
                      correlationId: 'account-usage',
                    ),
              beforeRevision,
            ),
          );
          if (!isKnownAccountRejection(error)) {
            // A retry of an unknown result does not transfer or overwrite the
            // original observation responsibility. Release this extra demand.
            if (!_unknown.containsKey(key)) {
              retained = true;
              _unknown[key] = _UnknownUsageQuery(demand);
            }
          }
          _settleUnknown();
        }
        completion.completeError(error, stack);
      } finally {
        if (identical(_current[key], work)) _current.remove(key)?.ignore();
        _pending.remove(work);
        // Failed native close keeps ownership in AccountObservations.
        if (!retained)
          await demand.release().then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          );
      }
    }());
    return work;
  }

  Future<void> close() async {
    _closed = true;
    _accountObservation.cancel();
    await Future.wait([
      for (final work in _pending.toList())
        work.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ]);
  }
}

final class _UnknownUsageQuery {
  const _UnknownUsageQuery(this.demand);
  final AccountDemand demand;
}

final class _UsageQueryFailure {
  const _UsageQueryFailure(this.failure, this.beforeRevision);
  final StudioFailure failure;
  final int beforeRevision;
}

final class _UsageDemand implements AccountDemand {
  _UsageDemand(this._release);
  final Future<void> Function() _release;
  Future<void>? _releasing;
  @override
  Future<void> release() => _releasing ??= _release();
}
