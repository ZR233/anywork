import 'dart:async';

import '../../../accounts_ports.dart';
import '../../../acp_ports.dart';
import '../../accounts/data/account_observations.dart';
import '../../accounts/data/account_settings_mutations.dart';
import '../../accounts/domain/account_identity.dart';
import '../../accounts/domain/account_values.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../models/acp_models.dart';
import '../../models/acp_install_models.dart';
import '../../models/command_receipts.dart';
import '../../models/failure_models.dart';
import '../../observation/latest_value.dart';
import '../../studio/commands/command_lane.dart';
import '../../studio/stores/domain_sync.dart' show typedCommandFailure;
import '../domain/acp_service.dart';

/// The single client-side ACP owner; runtime installation/auth owners are intact.
final class AcpServiceImpl implements AcpService {
  AcpServiceImpl({
    required this.port,
    required this.observations,
    required this.mutations,
    required this.accounts,
    required this.board,
  });
  final AcpPort port;
  final AccountObservations observations;
  final AccountSettingsMutations mutations;
  final AccountsRepository accounts;
  final MutationBoard board;
  final LatestValue<AcpAccountCatalogView> _templates = LatestValue(
    const AcpAccountCatalogView.empty(),
  );
  final LatestValue<AccountResource<AcpAuthSnapshotView>> _auth = LatestValue(
    const AccountResource(),
  );
  final LatestValue<AccountResource<AcpInstallSnapshotView>> _install =
      LatestValue(const AccountResource());
  final CommandLane _starts = CommandLane();
  final CommandLane _cancels = CommandLane();
  final Map<Object, OperationId> _active = {};
  final Map<OperationId, _AuthBusiness> _authBusiness = {};
  final Map<OperationId, _InstallBusiness> _installBusiness = {};
  final Map<Completer<AcpAccountDetails>, Observation> _savedWaiters = {};
  bool _closed = false;
  @override
  ValueObservation<AcpAccountCatalogView> get templates => _templates;
  @override
  ValueObservation<AccountResource<AcpAuthSnapshotView>> get auth => _auth;
  @override
  ValueObservation<AccountResource<AcpInstallSnapshotView>> get install =>
      _install;
  @override
  Future<void> loadTemplates() => _starts.run(() async {
    final generation = observations.generation;
    final catalog = await port.loadAcpAccountCatalog();
    if (generation != observations.generation) return;
    _templates.publish(
      AcpAccountCatalogView(templates: List.unmodifiable(catalog.templates)),
    );
  });
  @override
  AccountDemand observeAuth() => observations.acquire(const AcpAuthTarget());
  @override
  AccountDemand observeInstall() =>
      observations.acquire(const AcpInstallTarget());

  void Function() prepareOwnerChange(bool Function() isCurrent) {
    final auth = _auth.value;
    final install = _install.value;
    // Operation notifications can admit a new lifecycle synchronously. Detach
    // only the retiring responsibilities before publishing any such outcome.
    final authBusiness = _authBusiness.values.toList();
    final installBusiness = _installBusiness.values.toList();
    final savedWaiters = _savedWaiters.entries.toList();
    _authBusiness.clear();
    _installBusiness.clear();
    _active.clear();
    _savedWaiters.clear();
    return () {
      for (final business in authBusiness) {
        _invalidateOperation(business.operation, business.issued);
        _releaseDemand(business.demand);
      }
      for (final business in installBusiness) {
        _invalidateOperation(business.operation, business.issued);
        _releaseDemand(business.demand);
      }
      for (final entry in savedWaiters) {
        entry.value.cancel();
        if (!entry.key.isCompleted)
          entry.key.completeError(
            StateError('ACP owner changed while observing save'),
          );
      }
      if (!isCurrent()) return;
      if (identical(auth, _auth.value))
        _auth.publish(
          AccountResource(
            stamp: auth.stamp,
            value: auth.value,
            stale: true,
            loading: true,
          ),
        );
      if (!isCurrent()) return;
      if (identical(install, _install.value))
        _install.publish(
          AccountResource(
            stamp: install.stamp,
            value: install.value,
            stale: true,
            loading: true,
          ),
        );
    };
  }

  void _invalidateOperation(OperationHandle operation, bool issued) {
    final error = StateError('ACP runtime owner changed');
    if (operation.state.value.receipt != null) {
      operation.syncFailed(error);
    } else if (issued) {
      operation.unknownOutcome(error);
    } else {
      operation.reject(error);
    }
  }

  void apply(AccountDomainFrame frame) {
    final generation = observations.generation;
    switch (frame) {
      case AcpAuthFrame(:final stamp, :final snapshot):
        _auth.publish(
          AccountResource(stamp: stamp, value: _immutableAuth(snapshot)),
        );
        if (generation != observations.generation) return;
        _settleAuth(stamp, snapshot);
      case AcpInstallFrame(:final stamp, :final snapshot):
        _install.publish(
          AccountResource(stamp: stamp, value: _immutableInstall(snapshot)),
        );
        if (generation != observations.generation) return;
        _settleInstall(stamp, snapshot);
      default:
        throw ArgumentError('Not ACP operation content');
    }
  }

  void fail(AccountObservationTarget target, StudioFailure failure) {
    if (target is AcpAuthTarget) {
      final value = _auth.value;
      _auth.publish(
        AccountResource(
          stamp: value.stamp,
          value: value.value,
          failure: failure,
          stale: value.stale,
        ),
      );
    } else if (target is AcpInstallTarget) {
      final value = _install.value;
      _install.publish(
        AccountResource(
          stamp: value.stamp,
          value: value.value,
          failure: failure,
          stale: value.stale,
        ),
      );
    }
  }

  void _releaseDemand(AccountDemand? demand) {
    if (demand != null)
      unawaited(
        demand.release().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
  }

  void _releaseAuth(OperationId id) =>
      _releaseDemand(_authBusiness.remove(id)?.demand);
  void _releaseInstall(OperationId id) =>
      _releaseDemand(_installBusiness.remove(id)?.demand);

  void _settleAuth(ResourceStamp stamp, AcpAuthSnapshotView snapshot) {
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    for (final business in _authBusiness.values.toList()) {
      if (!owner.isCurrent || generation != observations.generation) return;
      if (!business.owner.isCurrent ||
          business.generation != generation ||
          business.connectionRevision == null)
        continue;
      final row = snapshot.account(
        business.identity.accountId,
        connectionRevision: business.connectionRevision!,
      );
      if (row == null) continue; // Absence is not configuration deletion proof.
      final stateOperation = row.state.operationId;
      if (stateOperation == business.operation.id.value) {
        business.witness = stamp;
        if (!row.state.isBusy) _releaseAuth(business.operation.id);
      } else {
        final proof = business.witness ?? business.admitted;
        if (proof == null || !stamp.covers(proof)) continue;
        // Auth terminal DTOs do not retain operationId. A matching busy frame
        // or this start's authoritative receipt must precede that terminal.
        if (!row.state.isBusy ||
            stamp.revision > proof.revision && stateOperation != null)
          _releaseAuth(business.operation.id);
      }
    }
  }

  void _settleInstall(ResourceStamp stamp, AcpInstallSnapshotView snapshot) {
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    for (final business in _installBusiness.values.toList()) {
      if (!owner.isCurrent || generation != observations.generation) return;
      if (!business.owner.isCurrent || business.generation != generation)
        continue;
      final state = snapshot.entry(business.provider)?.state;
      if (state == null || state.operationId != business.operation.id.value)
        continue;
      if (!state.isBusy) _releaseInstall(business.operation.id);
    }
  }

  void accountChanged(AccountDetailFrame frame) {
    if (frame.identity is! AcpAccountIdentity) return;
    final detail = frame.account;
    for (final business in _authBusiness.values.toList()) {
      if (business.identity != frame.identity ||
          business.connectionRevision == null ||
          !business.owner.isCurrent ||
          business.generation != observations.generation)
        continue;
      if (detail == null ||
          detail is AcpAccountDetails &&
              detail.account.connectionRevision != business.connectionRevision)
        _releaseAuth(business.operation.id);
    }
  }

  void _requireOwner(SettingsWriteOwner owner, int generation) {
    mutations.coordinator.requireOwner(owner);
    if (generation != observations.generation)
      throw SettingsWriteOwnerChanged();
  }

  OperationHandle _begin(
    Object reservation,
    String target, {
    required SettingsWriteOwner owner,
    required int generation,
  }) {
    _requireOwner(owner, generation);
    if (_active.containsKey(reservation)) throw _busy;
    final operation = board.begin(target: target, observationOwner: owner);
    try {
      _requireOwner(owner, generation);
    } catch (error) {
      operation.reject(error);
      rethrow;
    }
    _active[reservation] = operation.id;
    return operation;
  }

  void _finish(Object reservation, OperationHandle operation) {
    if (_active[reservation] == operation.id) _active.remove(reservation);
  }

  AccountDemand _acquire(
    Object reservation,
    OperationHandle operation,
    AccountDemand Function() acquire, {
    required SettingsWriteOwner owner,
    required int generation,
  }) {
    AccountDemand? demand;
    try {
      _requireOwner(owner, generation);
      demand = acquire();
      if (_closed) throw StateError('ACP service closed during admission');
      _requireOwner(owner, generation);
      return demand;
    } catch (error) {
      _finish(reservation, operation);
      _releaseDemand(demand);
      operation.reject(error);
      rethrow;
    }
  }

  @override
  Future<OperationState> save(
    AcpAccountUpdateView account, {
    DraftStamp? draft,
  }) => mutations.run(
    key: 'account:acp:${account.accountId}',
    draft: draft,
    targets: {
      'settings': AccountDetailTarget(AcpAccountIdentity(account.accountId)),
    },
    request: (revision, operation) =>
        port.saveAcpAccount(revision, account, operationId: operation),
  );
  @override
  Future<OperationState> remove(AcpAccountIdentity identity) => mutations.run(
    key: 'account:acp:${identity.accountId}',
    targets: {'settings': AccountDetailTarget(identity)},
    request: (revision, operation) => port.removeAcpAccount(
      revision,
      identity.accountId,
      operationId: operation,
    ),
  );

  @override
  Future<AcpSaveAndConnectResult> saveAndConnect(
    AcpAccountUpdateView account, {
    DraftStamp? draft,
  }) => _starts.run(() async {
    final identity = AcpAccountIdentity(account.accountId);
    final operation = await save(account, draft: draft);
    final stamp = operation.receipt?.targets
        .whereType<ResourceStamp>()
        .where((stamp) => stamp.resourceKey == 'settings')
        .single;
    if (stamp == null)
      throw StateError('ACP save returned no settings observation target');
    final detail = await _awaitSaved(identity, stamp);
    try {
      await check(identity);
      return AcpSaveAndConnectResult(saved: detail.account);
    } catch (error) {
      return AcpSaveAndConnectResult(
        saved: detail.account,
        checkFailure: typedCommandFailure(error, correlationId: 'acp-connect'),
      );
    }
  });

  Future<AcpAccountDetails> _awaitSaved(
    AcpAccountIdentity identity,
    ResourceStamp target,
  ) {
    if (_closed) return Future.error(StateError('ACP save observation closed'));
    final done = Completer<AcpAccountDetails>();
    void check(AccountResource<AccountDetails> value) {
      if (done.isCompleted ||
          !_savedWaiters.containsKey(done) ||
          value.stamp?.covers(target) != true)
        return;
      final detail = value.value;
      if (detail is AcpAccountDetails) {
        done.complete(detail);
      } else {
        done.completeError(StateError('Saved ACP account was removed'));
      }
      _savedWaiters.remove(done)?.cancel();
    }

    final watched = accounts.details(identity).watchLatest(check);
    _savedWaiters[done] = watched.observation;
    check(watched.value);
    return done.future;
  }

  @override
  Future<AcpAuthSnapshotView> check(AcpAccountIdentity identity) =>
      _startAuth(identity, const AcpCheckActionView());
  @override
  Future<AcpAuthSnapshotView> login(
    AcpAccountIdentity identity, {
    required String methodId,
  }) {
    if (methodId.trim().isEmpty)
      return Future.error(
        ArgumentError.value(
          methodId,
          'methodId',
          'Authentication method is required',
        ),
      );
    return _startAuth(identity, AcpAuthenticateActionView(methodId));
  }

  Future<AcpAccountDetails> _details(AcpAccountIdentity identity) async {
    if (!accounts.details(identity).value.loaded)
      await observations.refresh(AccountDetailTarget(identity));
    final value = accounts.details(identity).value.value;
    if (!accounts.details(identity).value.loaded || value is! AcpAccountDetails)
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'ACP account is unavailable',
        retryable: false,
        correlationId: 'acp-account',
      );
    return value;
  }

  Future<AcpAuthSnapshotView> _startAuth(
    AcpAccountIdentity identity,
    AcpAuthActionView action,
  ) {
    if (_closed) return Future.error(StateError('ACP service is closed'));
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    final ownerEpoch = observations.ownerEpoch;
    if (_active.containsKey(identity)) return Future.error(_busy);
    final operation = _begin(
      identity,
      'acp-auth:${identity.accountId}',
      owner: owner,
      generation: generation,
    );
    final demand = _acquire(
      identity,
      operation,
      () {
        final auth = observeAuth();
        try {
          return _AuthDemand(auth, accounts.observeDetails(identity));
        } catch (_) {
          _releaseDemand(auth);
          rethrow;
        }
      },
      owner: owner,
      generation: generation,
    );
    final business = _AuthBusiness(
      identity,
      operation,
      demand,
      generation,
      owner,
    );
    _authBusiness[operation.id] = business;
    return _starts.run(() async {
      try {
        _requireOwner(owner, generation);
        final detail = await _details(identity);
        _requireOwner(owner, generation);
        final revision = detail.account.connectionRevision;
        business.connectionRevision = revision;
        if (_authBusiness.values.any(
          (other) =>
              !identical(other, business) &&
              other.generation == business.generation &&
              other.identity == identity &&
              other.connectionRevision == revision,
        )) {
          throw _busy;
        }
        business.issued = true;
        final reply = await port.startAcpAuth(
          operationId: operation.id,
          accountId: identity.accountId,
          expectedConnectionRevision: revision,
          action: action,
        );
        _validate(operation, reply.receipt);
        final target = reply.snapshot.account(
          identity.accountId,
          connectionRevision: revision,
        );
        if (target == null)
          throw StateError('ACP auth reply is missing its target identity');
        final stamp = _stamp(reply.receipt, 'acp-auth', ownerEpoch);
        _recordReceipt(operation, reply.receipt);
        _requireOwner(owner, generation);
        business.admitted = stamp;
        observations.apply(AcpAuthFrame(stamp, reply.snapshot));
        _requireOwner(owner, generation);
        if (_auth.value.stamp case final currentStamp?)
          _settleAuth(currentStamp, _auth.value.value!);
        _markObserved(operation, stamp, owner, generation);
        return _immutableAuth(reply.snapshot);
      } catch (error) {
        _reject(operation, error, issued: business.issued);
        if (!business.issued || isKnownAccountRejection(error)) {
          _releaseAuth(operation.id);
        }
        rethrow;
      } finally {
        _finish(identity, operation);
      }
    });
  }

  @override
  Future<AcpAuthSnapshotView> cancelAuth(AcpAccountIdentity identity) {
    if (_closed) return Future.error(StateError('ACP service is closed'));
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    final ownerEpoch = observations.ownerEpoch;
    // Target is frozen synchronously. A cancelling intent never waits behind a
    // start request (including its slow adapter admission future).
    final detail = accounts.details(identity).value.value;
    if (!accounts.details(identity).value.loaded ||
        detail is! AcpAccountDetails)
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.notFound,
          message: 'ACP connection identity is unavailable',
          retryable: false,
          correlationId: 'acp-auth-cancel',
        ),
      );
    final revision = detail.account.connectionRevision;
    final target = _auth.value.value
        ?.account(identity.accountId, connectionRevision: revision)
        ?.state
        .operationId;
    if (target == null)
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.notFound,
          message: 'No ACP authentication operation is active',
          retryable: false,
          correlationId: 'acp-auth-cancel',
        ),
      );
    final key = (identity, target);
    if (_active.containsKey(key)) return Future.error(_busy);
    final operation = _begin(
      key,
      'acp-auth:${identity.accountId}',
      owner: owner,
      generation: generation,
    );
    var issued = false;
    return _cancels.run(() async {
      try {
        _requireOwner(owner, generation);
        issued = true;
        final reply = await port.cancelAcpAuth(
          operationId: operation.id,
          accountId: identity.accountId,
          targetOperationId: OperationId(target),
        );
        _validate(operation, reply.receipt);
        if (reply.snapshot.account(
              identity.accountId,
              connectionRevision: revision,
            ) ==
            null)
          throw StateError('ACP cancel reply identity mismatch');
        final stamp = _stamp(reply.receipt, 'acp-auth', ownerEpoch);
        _recordReceipt(operation, reply.receipt);
        _requireOwner(owner, generation);
        observations.apply(AcpAuthFrame(stamp, reply.snapshot));
        _markObserved(operation, stamp, owner, generation);
        return _immutableAuth(reply.snapshot);
      } catch (error) {
        _reject(operation, error, issued: issued);
        rethrow;
      } finally {
        _finish(key, operation);
      }
    });
  }

  @override
  Future<AcpInstallSnapshotView> prepare(AcpProviderView provider) {
    if (_closed) return Future.error(StateError('ACP service is closed'));
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    final ownerEpoch = observations.ownerEpoch;
    if (_active.containsKey(provider)) return Future.error(_busy);
    final operation = _begin(
      provider,
      'acp-install:${provider.wire}',
      owner: owner,
      generation: generation,
    );
    final demand = _acquire(
      provider,
      operation,
      observeInstall,
      owner: owner,
      generation: generation,
    );
    if (_installBusiness.values.any(
      (business) =>
          business.provider == provider &&
          business.generation == observations.generation,
    )) {
      _finish(provider, operation);
      operation.reject(_busy);
      unawaited(
        demand.release().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      return Future.error(_busy);
    }
    final business = _InstallBusiness(
      provider,
      operation,
      demand,
      generation,
      owner,
    );
    _installBusiness[operation.id] = business;
    return _starts.run(() async {
      try {
        _requireOwner(owner, generation);
        business.issued = true;
        final reply = await port.startAcpInstall(
          operationId: operation.id,
          provider: provider,
        );
        _validate(operation, reply.receipt);
        if (reply.snapshot.entry(provider) == null)
          throw StateError('ACP preparation reply identity mismatch');
        final stamp = _stamp(reply.receipt, 'acp-install', ownerEpoch);
        _recordReceipt(operation, reply.receipt);
        _requireOwner(owner, generation);
        observations.apply(AcpInstallFrame(stamp, reply.snapshot));
        _markObserved(operation, stamp, owner, generation);
        return _immutableInstall(reply.snapshot);
      } catch (error) {
        _reject(operation, error, issued: business.issued);
        if (!business.issued || isKnownAccountRejection(error))
          _releaseInstall(operation.id);
        rethrow;
      } finally {
        _finish(provider, operation);
      }
    });
  }

  @override
  Future<AcpInstallSnapshotView> cancelPreparation(AcpProviderView provider) {
    if (_closed) return Future.error(StateError('ACP service is closed'));
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    final ownerEpoch = observations.ownerEpoch;
    final target = _install.value.value?.stateOf(provider).operationId;
    if (target == null)
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.notFound,
          message: 'No ACP preparation operation is active',
          retryable: false,
          correlationId: 'acp-install-cancel',
        ),
      );
    final key = (provider, target);
    if (_active.containsKey(key)) return Future.error(_busy);
    final operation = _begin(
      key,
      'acp-install:${provider.wire}',
      owner: owner,
      generation: generation,
    );
    var issued = false;
    return _cancels.run(() async {
      try {
        _requireOwner(owner, generation);
        issued = true;
        final reply = await port.cancelAcpInstall(
          operationId: operation.id,
          provider: provider,
          targetOperationId: OperationId(target),
        );
        _validate(operation, reply.receipt);
        if (reply.snapshot.entry(provider) == null)
          throw StateError('ACP preparation cancel identity mismatch');
        final stamp = _stamp(reply.receipt, 'acp-install', ownerEpoch);
        _recordReceipt(operation, reply.receipt);
        _requireOwner(owner, generation);
        observations.apply(AcpInstallFrame(stamp, reply.snapshot));
        _markObserved(operation, stamp, owner, generation);
        return _immutableInstall(reply.snapshot);
      } catch (error) {
        _reject(operation, error, issued: issued);
        rethrow;
      } finally {
        _finish(key, operation);
      }
    });
  }

  void _validate(OperationHandle operation, StudioCommandReceipt receipt) {
    if (receipt.operationId != operation.id)
      throw StateError('ACP receipt operation mismatch');
  }

  ResourceStamp _stamp(
    StudioCommandReceipt receipt,
    String resource,
    String? ownerEpoch,
  ) {
    if (receipt.targets.length != 1 ||
        receipt.targets.single.resourceKey != resource)
      throw StateError('ACP receipt source mismatch');
    final stamp = receipt.targets.single;
    // Validate against the wire owner frozen at admission, not a replacement
    // runtime. A late valid receipt is still a real effective/durable fact.
    if (ownerEpoch != null && ownerEpoch != stamp.ownerEpoch)
      throw StateError('ACP receipt owner epoch mismatch');
    return stamp;
  }

  void _recordReceipt(OperationHandle operation, StudioCommandReceipt receipt) {
    operation.accept(
      CommitReceipt(
        operationId: receipt.operationId,
        disposition: receipt.disposition,
        targets: receipt.targets,
        effect: receipt.effect,
        effective: receipt.effective,
        durable: receipt.durable,
        requiresIdentityObservation: true,
      ),
    );
  }

  void _markObserved(
    OperationHandle operation,
    ResourceStamp stamp,
    SettingsWriteOwner owner,
    int generation,
  ) {
    _requireOwner(owner, generation);
    final proof = observations.stamp(
      stamp.resourceKey == 'acp-auth'
          ? const AcpAuthTarget()
          : const AcpInstallTarget(),
    );
    if (proof?.covers(stamp) != true) {
      throw StateError('ACP receipt target was not observed by its owner');
    }
    operation.markObserved();
    _requireOwner(owner, generation);
  }

  void _reject(
    OperationHandle operation,
    Object error, {
    required bool issued,
  }) {
    if (operation.state.value.failurePhase == OperationPhase.rejected) return;
    if (operation.state.value.receipt != null) {
      if (operation.state.value.failurePhase != OperationPhase.syncFailed)
        operation.syncFailed(error);
    } else if (!issued || isKnownAccountRejection(error)) {
      operation.reject(error);
    } else {
      operation.unknownOutcome(error);
    }
  }

  Future<void> close() {
    _closed = true;
    _starts.seal();
    _cancels.seal();
    for (final entry in _savedWaiters.entries.toList()) {
      entry.value.cancel();
      entry.key.completeError(StateError('ACP save observation closed'));
    }
    _savedWaiters.clear();
    return Future.wait([_starts.join(), _cancels.join()]);
  }
}

const _busy = StudioFailure(
  code: StudioFailureCode.busy,
  message: 'An ACP intent is already in flight',
  retryable: false,
  correlationId: 'acp-admission',
);

final class _AuthBusiness {
  _AuthBusiness(
    this.identity,
    this.operation,
    this.demand,
    this.generation,
    this.owner,
  );
  final AcpAccountIdentity identity;
  final OperationHandle operation;
  final AccountDemand demand;
  final int generation;
  final SettingsWriteOwner owner;
  int? connectionRevision;
  ResourceStamp? witness;
  ResourceStamp? admitted;
  bool issued = false;
}

final class _InstallBusiness {
  _InstallBusiness(
    this.provider,
    this.operation,
    this.demand,
    this.generation,
    this.owner,
  );
  final AcpProviderView provider;
  final OperationHandle operation;
  final AccountDemand demand;
  final int generation;
  final SettingsWriteOwner owner;
  bool issued = false;
}

final class _AuthDemand implements AccountDemand {
  _AuthDemand(this.auth, this.configuration);
  final AccountDemand auth;
  final AccountDemand configuration;
  Future<void>? _releasing;
  @override
  Future<void> release() =>
      _releasing ??= Future.wait([auth.release(), configuration.release()])
          .then<void>((_) {});
}

AcpAuthSnapshotView _immutableAuth(AcpAuthSnapshotView snapshot) =>
    AcpAuthSnapshotView(
      revision: snapshot.revision,
      updatedAt: snapshot.updatedAt,
      accounts: List.unmodifiable([
        for (final account in snapshot.accounts)
          AcpAuthAccountView(
            accountId: account.accountId,
            connectionRevision: account.connectionRevision,
            state: account.state is AcpRequiredState
                ? AcpRequiredState(
                    server: (account.state as AcpRequiredState).server,
                    methods: List.unmodifiable(
                      (account.state as AcpRequiredState).methods,
                    ),
                  )
                : account.state,
          ),
      ]),
    );
AcpInstallSnapshotView _immutableInstall(AcpInstallSnapshotView snapshot) =>
    AcpInstallSnapshotView(
      revision: snapshot.revision,
      updatedAt: snapshot.updatedAt,
      installations: List.unmodifiable(snapshot.installations),
    );
