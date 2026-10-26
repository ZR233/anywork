import 'dart:async';

import '../../../accounts_ports.dart';
import '../../accounts/data/account_observations.dart';
import '../../accounts/data/account_settings_mutations.dart';
import '../../accounts/domain/account_identity.dart';
import '../../accounts/domain/account_intents.dart';
import '../../accounts/domain/account_values.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../models/delegation_models.dart';
import '../../models/failure_models.dart';
import '../../observation/latest_value.dart';
import '../../studio/commands/command_lane.dart';
import '../domain/model_directory.dart';
import '../domain/immutable_model.dart';

final class ModelsRepositoryImpl implements ModelsRepository {
  ModelsRepositoryImpl({
    required this.port,
    required this.observations,
    required this.mutations,
    required this.board,
  });
  final AccountModelsPort port;
  final AccountObservations observations;
  final AccountSettingsMutations mutations;
  final MutationBoard board;
  final LatestValue<ModelDirectoryState> _state = LatestValue(
    ModelDirectoryState(),
  );
  final CommandLane _queries = CommandLane();
  final Map<AccountModelIdentity, Future<DelegationModelDetail>> _performance =
      {};
  final Map<_SyncQueryIdentity, Future<ModelSyncAdmission>> _sync = {};
  final Map<OperationId, (NativeAccountIdentity, int?, AccountDemand)>
  _syncDemands = {};
  int _syncSequence = 0;
  bool _closed = false;
  AccountDemand Function()? directoryDemand;

  @override
  ValueObservation<ModelDirectoryState> get state => _state;

  void Function() prepareOwnerChange(bool Function() isCurrent) {
    final oldAccounts = _state.value.accounts;
    final oldConfigurations = _state.value.configurations;
    _performance.clear(); // Actual futures remain joined by _queries.
    final retiring = _syncDemands.values.toList();
    _syncDemands.clear();
    return () {
      for (final business in retiring) {
        unawaited(
          business.$3.release().then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        );
      }
      if (!isCurrent()) return;
      final current = _state.value;
      final accounts = {...current.accounts};
      final configurations = {...current.configurations};
      var changed = false;
      for (final entry in oldAccounts.entries) {
        if (!identical(current.accounts[entry.key], entry.value)) continue;
        changed = true;
        accounts[entry.key] = AccountResource(
          stamp: entry.value.stamp,
          value: entry.value.value,
          stale: true,
          loading: true,
        );
      }
      for (final entry in oldConfigurations.entries) {
        if (!identical(current.configurations[entry.key], entry.value))
          continue;
        changed = true;
        configurations[entry.key] = AccountResource(
          stamp: entry.value.stamp,
          value: entry.value.value,
          stale: true,
          loading: true,
        );
      }
      if (!changed) return;
      _state.publish(
        ModelDirectoryState(accounts: accounts, configurations: configurations),
      );
    };
  }

  @override
  AccountDemand observeAccount(NativeAccountIdentity identity) {
    final catalog = observations.acquire(AccountModelsTarget(identity));
    try {
      return _ModelAccountDemand(
        catalog,
        observations.acquire(AccountDetailTarget(identity)),
      );
    } catch (_) {
      unawaited(
        catalog.release().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      rethrow;
    }
  }

  @override
  AccountDemand observeDirectory() {
    final demand = directoryDemand;
    if (demand == null)
      throw StateError('Model directory observation is not assembled');
    return demand();
  }

  void apply(AccountModelsFrame frame) {
    if (frame.catalog != null && frame.catalog!.identity != frame.identity)
      throw StateError('Model catalog identity mismatch');
    final generation = observations.generation;
    _state.publish(
      ModelDirectoryState(
        accounts: {
          ..._state.value.accounts,
          frame.identity: AccountResource(
            stamp: frame.stamp,
            value: frame.catalog,
          ),
        },
        configurations: _state.value.configurations,
      ),
    );
    if (generation != observations.generation) return;
    _settleSync(frame);
  }

  void _settleSync(AccountModelsFrame frame) {
    final status = frame.catalog?.status;
    for (final entry in _syncDemands.entries.toList()) {
      final (identity, generation, demand) = entry.value;
      if (identity != frame.identity) continue;
      final matchingTerminal =
          status != null &&
          !status.probing &&
          status.operationId == entry.key.value &&
          (generation == null || status.queryGeneration == generation);
      final superseded =
          generation != null &&
          status != null &&
          status.queryGeneration > generation;
      if (frame.catalog != null && !matchingTerminal && !superseded) continue;
      _syncDemands.remove(entry.key);
      unawaited(
        demand.release().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
  }

  void applyConfiguration(
    NativeAccountIdentity identity,
    ResourceStamp stamp,
    AccountModelConfiguration? configuration,
  ) {
    _state.publish(
      ModelDirectoryState(
        accounts: _state.value.accounts,
        configurations: {
          ..._state.value.configurations,
          identity: AccountResource(stamp: stamp, value: configuration),
        },
      ),
    );
  }

  void fail(AccountObservationTarget target, StudioFailure failure) {
    if (target is! AccountModelsTarget) return;
    final current = _state.value.accounts[target.identity];
    _state.publish(
      ModelDirectoryState(
        accounts: {
          ..._state.value.accounts,
          target.identity: AccountResource(
            stamp: current?.stamp,
            value: current?.value,
            failure: failure,
            stale: current?.stale ?? false,
          ),
        },
        configurations: _state.value.configurations,
      ),
    );
  }

  Map<String, AccountObservationTarget> _targets(
    AccountModelIdentity identity,
  ) => {
    'settings': AccountDetailTarget(identity.account),
    'model-catalog': AccountModelsTarget(identity.account),
  };
  @override
  Future<OperationState> setEnabled(
    AccountModelIdentity identity,
    bool enabled,
  ) => mutations.run(
    key:
        'model:enabled:${identity.accountId.length}:${identity.accountId}:${identity.modelId}',
    targets: _targets(identity),
    request: (revision, operation) => port.setAccountModelEnabled(
      revision,
      identity.accountId,
      identity.modelId,
      enabled,
      operationId: operation,
    ),
  );
  @override
  Future<OperationState> setAutoCompact(
    AccountModelIdentity identity,
    AutoCompactIntent intent, {
    DraftStamp? draft,
  }) => mutations.run(
    key:
        'model:compact:${identity.accountId.length}:${identity.accountId}:${identity.modelId}',
    draft: draft,
    targets: _targets(identity),
    request: (revision, operation) => port.setAccountModelAutoCompact(
      revision,
      identity,
      intent,
      operationId: operation,
    ),
  );
  @override
  Future<OperationState> setConnection(
    AccountModelIdentity identity,
    ModelConnectionIntent intent,
  ) => mutations.run(
    key:
        'model:connection:${identity.accountId.length}:${identity.accountId}:${identity.modelId}',
    targets: _targets(identity),
    request: (revision, operation) => port.setAccountModelConnection(
      revision,
      identity,
      intent,
      operationId: operation,
    ),
  );
  @override
  Future<OperationState> removeManual(
    AccountModelIdentity identity,
  ) => mutations.run(
    key:
        'model:remove:${identity.accountId.length}:${identity.accountId}:${identity.modelId}',
    targets: _targets(identity),
    request: (revision, operation) => port.removeAccountModel(
      revision,
      identity.accountId,
      identity.modelId,
      operationId: operation,
    ),
  );

  @override
  Future<ModelSyncAdmission> sync(NativeAccountIdentity identity) {
    if (_closed) return Future.error(StateError('Models are closed'));
    final catalog = _state.value.accounts[identity];
    // An unobserved query has no merge identity. A unique token keeps it out
    // of every other unobserved/canonical generation; the Rust owner may join.
    final key = _SyncQueryIdentity(
      identity,
      observations.generation,
      catalog?.stamp?.ownerEpoch,
      catalog?.value?.status.queryGeneration,
      catalog?.stamp == null || catalog?.value == null || catalog!.stale
          ? Object()
          : null,
    );
    final existing = _sync[key];
    if (existing != null) return existing;
    final demand = observeAccount(identity);
    if (_closed) {
      unawaited(
        demand.release().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      return Future.error(StateError('Models closed during admission'));
    }
    final operationId = OperationId(
      '${board.clientId}:model-sync:${++_syncSequence}',
    );
    final work = _queries.run(() async {
      try {
        final admission = await port.syncAccountModels(
          identity,
          operationId: operationId,
        );
        if (admission.account != identity ||
            (!admission.joinedExisting && admission.operationId != operationId))
          throw StateError('Model sync admission identity mismatch');
        if (key.connectionGeneration != observations.generation) {
          await demand.release();
          return admission;
        }
        // No synthetic settings receipt: this is acceptance only. Completion
        // remains the matching query generation's canonical catalog status.
        final previous = _syncDemands[admission.operationId];
        if (previous == null) {
          _syncDemands[admission.operationId] = (
            identity,
            admission.queryGeneration,
            demand,
          );
          final current = _state.value.accounts[identity];
          if (current?.stamp case final stamp?)
            _settleSync(AccountModelsFrame(stamp, identity, current?.value));
        } else {
          await demand.release();
        }
        return admission;
      } catch (error) {
        if (isKnownAccountRejection(error)) {
          await demand.release();
        } else if (key.connectionGeneration == observations.generation) {
          _syncDemands[operationId] = (identity, null, demand);
        } else {
          await demand.release();
        }
        rethrow;
      }
    });
    _sync[key] = work;
    unawaited(
      work.then<void>(
        (_) {
          if (identical(_sync[key], work)) _sync.remove(key)?.ignore();
        },
        onError: (Object _, StackTrace _) {
          if (identical(_sync[key], work)) _sync.remove(key)?.ignore();
        },
      ),
    );
    return work;
  }

  @override
  Future<DelegationModelDetail> performance(AccountModelIdentity identity) {
    if (_closed) return Future.error(StateError('Models are closed'));
    final existing = _performance[identity];
    if (existing != null) return existing;
    final stamp = observations.stamp(AccountModelsTarget(identity.account));
    final generation = observations.generation;
    final settingsStamp = observations.stamp(
      AccountDetailTarget(identity.account),
    );
    final work = _queries.run(() async {
      final detail = await port.getDelegationModel(
        DelegationModelKey(
          accountId: identity.accountId,
          modelId: identity.modelId,
        ),
      );
      if (generation != observations.generation ||
          detail.key.accountId != identity.accountId ||
          detail.key.modelId != identity.modelId ||
          observations.stamp(AccountModelsTarget(identity.account)) != stamp) {
        throw const StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'Model detail identity changed',
          retryable: true,
          correlationId: 'model-performance',
        );
      }
      if (observations.stamp(AccountDetailTarget(identity.account)) !=
          settingsStamp)
        throw const StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'Model settings identity changed',
          retryable: true,
          correlationId: 'model-performance-settings',
        );
      return immutableModelDetail(detail);
    });
    _performance[identity] = work;
    unawaited(
      work.then<void>(
        (_) {
          if (identical(_performance[identity], work))
            _performance.remove(identity)?.ignore();
        },
        onError: (Object _, StackTrace _) {
          if (identical(_performance[identity], work))
            _performance.remove(identity)?.ignore();
        },
      ),
    );
    return work;
  }

  Future<void> close() {
    _closed = true;
    _queries.seal();
    return _queries.join();
  }
}

final class _ModelAccountDemand implements AccountDemand {
  _ModelAccountDemand(this.catalog, this.configuration);
  final AccountDemand catalog;
  final AccountDemand configuration;
  Future<void>? _releasing;
  @override
  Future<void> release() =>
      _releasing ??= Future.wait([catalog.release(), configuration.release()])
          .then<void>((_) {});
}

final class _SyncQueryIdentity {
  const _SyncQueryIdentity(
    this.account,
    this.connectionGeneration,
    this.ownerEpoch,
    this.queryGeneration,
    this.unbound,
  );
  final NativeAccountIdentity account;
  final int connectionGeneration;
  final String? ownerEpoch;
  final int? queryGeneration;
  final Object? unbound;
  @override
  bool operator ==(Object other) =>
      other is _SyncQueryIdentity &&
      account == other.account &&
      connectionGeneration == other.connectionGeneration &&
      ownerEpoch == other.ownerEpoch &&
      queryGeneration == other.queryGeneration &&
      identical(unbound, other.unbound);
  @override
  int get hashCode => Object.hash(
    account,
    connectionGeneration,
    ownerEpoch,
    queryGeneration,
    identityHashCode(unbound),
  );
}
