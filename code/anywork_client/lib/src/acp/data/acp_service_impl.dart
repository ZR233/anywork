import 'dart:async';
import 'dart:convert';

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
import '../../models/acp_local_detection_models.dart';
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
  final CommandLane _detectionStarts = CommandLane();
  final CommandLane _detectionCancels = CommandLane();
  final LatestValue<AccountResource<AcpLocalDetectionSnapshotView>>
  _localDetection = LatestValue(const AccountResource());
  @override
  ValueObservation<AccountResource<AcpLocalDetectionSnapshotView>>
  get localDetection => _localDetection;
  @override
  AccountDemand observeLocalDetection() =>
      observations.acquire(const AcpLocalDetectionTarget());

  @override
  Future<AcpLocalDetectionCommandReply> startLocalDetection(
    OperationId operationId,
  ) => _detectionCommand(
    _detectionStarts,
    operationId,
    () => port.startAcpLocalDetection(operationId: operationId),
  );
  @override
  Future<AcpLocalDetectionCommandReply> cancelLocalDetection({
    required OperationId operationId,
    required OperationId targetOperationId,
  }) => _detectionCommand(
    _detectionCancels,
    operationId,
    () => port.cancelAcpLocalDetection(
      operationId: operationId,
      targetOperationId: targetOperationId,
    ),
  );

  Future<AcpLocalDetectionCommandReply> _detectionCommand(
    CommandLane lane,
    OperationId operationId,
    Future<AcpLocalDetectionCommandReply> Function() request,
  ) {
    if (_closed) return Future.error(StateError('ACP owner closed'));
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    return lane.run(() async {
      _requireOwner(owner, generation);
      final reply = await request();
      _requireOwner(owner, generation);
      if (reply.receipt.operationId != operationId)
        throw StateError('Detection receipt identity mismatch');
      final stamp = reply.receipt.targets.single;
      if (stamp.resourceKey != 'acp-local-detection' ||
          stamp.revision != reply.snapshot.revision) {
        throw StateError('Detection receipt resource mismatch');
      }
      observations.apply(AcpLocalDetectionFrame(stamp, reply.snapshot));
      return reply;
    });
  }

  final CommandLane _cancels = CommandLane();
  final CommandLane _continuations = CommandLane();
  final Map<Object, OperationId> _active = {};
  final Map<OperationId, _AuthBusiness> _authBusiness = {};
  final Map<OperationId, _InstallBusiness> _installBusiness = {};
  final Map<
    Completer<({AcpAccountDetails? detail, OperationState operation})>,
    List<Observation>
  >
  _savedWaiters = {};
  bool _closed = false;
  static const int _maxUsageRefreshAdmissions = 4;
  final Map<AcpAccountIdentity, _UsageRefreshQueue> _usageRefreshes = {};
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
    final detection = _localDetection.value;
    // Operation notifications can admit a new lifecycle synchronously. Detach
    // only the retiring responsibilities before publishing any such outcome.
    final authBusiness = _authBusiness.values.toList();
    final installBusiness = _installBusiness.values.toList();
    final savedWaiters = _savedWaiters.entries.toList();
    _authBusiness.clear();
    _installBusiness.clear();
    _active.clear();
    _savedWaiters.clear();
    final usageQueues = _usageRefreshes.values.toList();
    for (final queue in usageQueues) {
      queue.notify();
      unawaited(_driveUsageRefresh(queue));
    }
    return () {
      if (isCurrent() && identical(detection, _localDetection.value)) {
        _localDetection.publish(
          AccountResource(
            stamp: detection.stamp,
            value: detection.value,
            stale: true,
            loading: true,
          ),
        );
      }
      for (final business in authBusiness) {
        _invalidateOperation(business.operation, business.issued);
        _releaseDemand(business.demand);
      }
      for (final business in installBusiness) {
        _invalidateOperation(business.operation, business.issued);
        _releaseDemand(business.demand);
      }
      for (final entry in savedWaiters) {
        for (final observation in entry.value) {
          observation.cancel();
        }
        if (!entry.key.isCompleted)
          entry.key.completeError(
            StateError('ACP owner changed while observing save'),
          );
      }
      for (final queue in usageQueues) {
        queue.notify();
        unawaited(_driveUsageRefresh(queue));
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
      case AcpLocalDetectionFrame(:final stamp, :final snapshot):
        _localDetection.publish(AccountResource(stamp: stamp, value: snapshot));
      case AcpAuthFrame(:final stamp, :final snapshot):
        _auth.publish(
          AccountResource(stamp: stamp, value: _immutableAuth(snapshot)),
        );
        _notifyUsageRefreshFrames();
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
    if (target is AcpLocalDetectionTarget) {
      final value = _localDetection.value;
      _localDetection.publish(
        AccountResource(
          stamp: value.stamp,
          value: value.value,
          failure: failure,
          stale: value.stale,
        ),
      );
      return;
    }
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
      _notifyUsageRefreshFrames();
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

  void _releaseAuth(OperationId id) {
    final business = _authBusiness.remove(id);
    if (business == null) return;
    _releaseDemand(business.demand);
    _notifyUsageRefresh(business.identity);
  }

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
    final identity = frame.identity;
    if (identity is! AcpAccountIdentity) return;
    final detail = frame.account;
    for (final business in _authBusiness.values.toList()) {
      if (business.identity != identity ||
          business.connectionRevision == null ||
          !business.owner.isCurrent ||
          business.generation != observations.generation)
        continue;
      if (detail == null ||
          detail is AcpAccountDetails &&
              detail.account.connectionRevision != business.connectionRevision)
        _releaseAuth(business.operation.id);
    }
    _notifyUsageRefresh(identity);
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
    if (_active[reservation] != operation.id) return;
    _active.remove(reservation);
    if (reservation is AcpAccountIdentity) _notifyUsageRefresh(reservation);
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
    required BigInt? expectedDocumentRevision,
    DraftStamp? draft,
  }) => _save(
    account,
    expectedDocumentRevision: expectedDocumentRevision,
    draft: draft,
  );

  Future<OperationState> _save(
    AcpAccountUpdateView account, {
    required BigInt? expectedDocumentRevision,
    DraftStamp? draft,
    void Function(OperationHandle operation)? onAdmitted,
  }) {
    final frozen = AcpAccountUpdateView(
      accountId: account.accountId,
      name: account.name,
      template: account.template,
      command: account.command,
      args: account.args == null ? null : List.unmodifiable(account.args!),
      env: Map.unmodifiable(account.env),
      enabled: account.enabled,
    );
    return mutations.run(
      key: 'account:acp:${account.accountId}',
      draft: draft,
      targets: {
        'settings': AccountDetailTarget(AcpAccountIdentity(account.accountId)),
      },
      request: (revision, operation) => port.saveAcpAccount(
        revision,
        frozen,
        operationId: operation,
        expectedDocumentRevision: expectedDocumentRevision,
      ),
      onAdmitted: onAdmitted,
    );
  }

  @override
  Future<OperationState> remove(AcpAccountIdentity identity) async {
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    final baseline = await _details(identity);
    _requireOwner(owner, generation);
    final documentRevision = baseline.account.documentRevision;
    return mutations.run(
      key: 'account:acp:${identity.accountId}',
      targets: {'settings': AccountDetailTarget(identity)},
      request: (revision, operation) => port.removeAcpAccount(
        revision,
        identity.accountId,
        operationId: operation,
        expectedDocumentRevision: documentRevision,
      ),
    );
  }

  @override
  Future<AcpSaveAndConnectResult> saveAndConnect(
    AcpAccountUpdateView account, {
    required BigInt? expectedDocumentRevision,
    DraftStamp? draft,
  }) => _starts.run(() async {
    final identity = AcpAccountIdentity(account.accountId);
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    OperationHandle? admitted;
    Observation? retained;
    try {
      final saved = await _save(
        account,
        expectedDocumentRevision: expectedDocumentRevision,
        draft: draft,
        onAdmitted: (operation) {
          admitted = operation;
          // Keep this exact handle alive even when a newer intent is admitted.
          retained = operation.state.watch((_) {});
        },
      );
      if (saved.failurePhase != null)
        return AcpSaveAndConnectResult(operation: saved);
      final operation = admitted!;
      late final AcpAccountDetails detail;
      try {
        _requireOwner(owner, generation);
        final stamp = operation.state.value.receipt?.targets
            .whereType<ResourceStamp>()
            .where((stamp) => stamp.resourceKey == 'settings')
            .single;
        if (stamp == null)
          throw StateError('ACP save returned no settings observation target');
        final confirmation = await _awaitSaved(operation, identity, stamp);
        if (confirmation.operation.failurePhase != null)
          return AcpSaveAndConnectResult(operation: confirmation.operation);
        detail = confirmation.detail!;
        _requireOwner(owner, generation);
      } catch (error) {
        final current = operation.state.value;
        final snapshot = current.failurePhase == null
            ? operation.syncFailed(error)
            : current;
        return AcpSaveAndConnectResult(operation: snapshot);
      }
      final snapshot = operation.state.value;
      if (snapshot.failurePhase != null)
        return AcpSaveAndConnectResult(operation: snapshot);
      try {
        await check(identity);
        return AcpSaveAndConnectResult(
          operation: snapshot,
          saved: detail.account,
        );
      } catch (error) {
        return AcpSaveAndConnectResult(
          operation: snapshot,
          saved: detail.account,
          checkFailure: typedCommandFailure(
            error,
            correlationId: 'acp-connect',
          ),
        );
      }
    } finally {
      retained?.cancel();
    }
  });

  Future<({AcpAccountDetails? detail, OperationState operation})> _awaitSaved(
    OperationHandle operation,
    AcpAccountIdentity identity,
    ResourceStamp target,
  ) {
    if (_closed) return Future.error(StateError('ACP save observation closed'));
    final done =
        Completer<({AcpAccountDetails? detail, OperationState operation})>();
    final subscriptions = <Observation>[];
    _savedWaiters[done] = subscriptions;
    final details = accounts.details(identity);
    void release() {
      for (final subscription
          in _savedWaiters.remove(done) ?? <Observation>[]) {
        subscription.cancel();
      }
    }

    void check([OperationState? snapshot]) {
      if (done.isCompleted || !_savedWaiters.containsKey(done)) return;
      final state = snapshot ?? operation.state.value;
      final value = details.value;
      if (state.failurePhase != null) {
        done.complete((detail: null, operation: state));
        release();
        return;
      }
      if (value.failure case final failure?) {
        done.completeError(failure);
        release();
        return;
      }
      if (state.receipt == null ||
          !state.observed ||
          !state.durable ||
          value.stamp?.covers(target) != true)
        return;
      final detail = value.value;
      if (detail is AcpAccountDetails && detail.identity == identity) {
        done.complete((detail: detail, operation: state));
      } else {
        done.completeError(StateError('Saved ACP account was removed'));
      }
      release();
    }

    try {
      subscriptions.add(details.watchLatest((_) => check()).observation);
      subscriptions.add(operation.state.watchLatest(check).observation);
      check();
    } catch (error) {
      release();
      if (!done.isCompleted) done.completeError(error);
    }
    return done.future;
  }

  @override
  Future<AcpAuthSnapshotView> check(AcpAccountIdentity identity) =>
      _startAuth(identity, const AcpCheckActionView());
  @override
  Future<AcpAuthSnapshotView> queryUsage(AcpAccountIdentity identity) =>
      _startAuth(identity, const AcpQueryUsageActionView());
  @override
  Future<AcpAuthSnapshotView> login(
    AcpAccountIdentity identity, {
    required String methodId,
  }) {
    if (_closed) return Future.error(StateError('ACP service is closed'));
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    final ownerEpoch = observations.ownerEpoch;
    final detail = accounts.details(identity).value.value;
    if (!accounts.details(identity).value.loaded ||
        detail is! AcpAccountDetails) {
      return Future.error(StateError('ACP connection identity is unavailable'));
    }
    final revision = detail.account.connectionRevision;
    final state = _auth.value.value
        ?.account(identity.accountId, connectionRevision: revision)
        ?.state;
    if (_auth.value.stale ||
        state is! AcpRequiredState ||
        !state.agentMethods.any((method) => method.id == methodId)) {
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.conflict,
          message:
              'The current ACP connection is not waiting for this login method',
          retryable: false,
          correlationId: 'acp-auth-continue',
        ),
      );
    }
    final target = state.operationId;
    final key = ('continue', identity, target);
    if (_active.containsKey(key)) return Future.error(_busy);
    final operation = _begin(
      key,
      'acp-auth:${identity.accountId}',
      owner: owner,
      generation: generation,
    );
    return _continuations.run(() async {
      var issued = false;
      try {
        _requireOwner(owner, generation);
        issued = true;
        final reply = await port.continueAcpAuth(
          operationId: operation.id,
          accountId: identity.accountId,
          expectedConnectionRevision: revision,
          targetOperationId: OperationId(target),
          methodId: methodId,
        );
        _validate(operation, reply.receipt);
        if (reply.snapshot.account(
              identity.accountId,
              connectionRevision: revision,
            ) ==
            null) {
          throw StateError('ACP continue reply identity mismatch');
        }
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

  /// 协调准入自有的详情等待：只登记本意图的详情镜像监听，撤销时立即取消。
  ///
  /// `watchLatest` 在同一次同步登记中返回当前值。登记前留在镜像上的失败属于
  /// 已退役观察，即使 stamp 为空或仍是当前 owner，也不能当成新 feed 的失败，
  /// 更不能因此释放刚建立的需求。已加载且属于当前 owner 与身份的详情可以
  /// 直接使用。登记之后新发布的失败必须原样收束。未就绪时不调用
  /// `observations.refresh`。
  Future<AcpAccountDetails> _awaitAdmissionDetails(
    AcpAccountIdentity identity,
    _UsageAdmissionWait admission, {
    required SettingsWriteOwner owner,
    required int generation,
  }) {
    if (admission.withdrawn || _closed) {
      return Future.error(const _UsageRefreshWithdrawn());
    }
    final done = Completer<AcpAccountDetails>();
    var settled = false;
    Observation? subscription;

    void settle(void Function() complete) {
      if (settled) return;
      settled = true;
      final current = subscription;
      subscription = null;
      current?.cancel();
      if (!done.isCompleted) complete();
    }

    void withdraw() =>
        settle(() => done.completeError(const _UsageRefreshWithdrawn()));

    bool stampCurrent(ResourceStamp? stamp) {
      final epoch = observations.ownerEpoch;
      return epoch == null || stamp == null || stamp.ownerEpoch == epoch;
    }

    AcpAccountDetails? readyDetail(AccountResource<AccountDetails> resource) {
      if (!stampCurrent(resource.stamp) || !resource.loaded) return null;
      final value = resource.value;
      if (value is AcpAccountDetails && value.identity == identity) {
        return value;
      }
      return null;
    }

    void consider(
      AccountResource<AccountDetails> resource, {
      required bool registrationSnapshot,
    }) {
      if (settled) return;
      if (admission.withdrawn || _closed) {
        withdraw();
        return;
      }
      if (!owner.isCurrent || generation != observations.generation) {
        settle(() => done.completeError(SettingsWriteOwnerChanged()));
        return;
      }
      // fail() 会保留旧 stamp 和旧 value。登记后的发布才是这次观察的失败；
      // 它必须先于残留的已加载详情收束，不能被旧值吞掉。
      if (!registrationSnapshot) {
        if (resource.failure case final failure?) {
          settle(() => done.completeError(failure));
          return;
        }
      }
      if (readyDetail(resource) case final detail?) {
        settle(() => done.complete(detail));
        return;
      }
      // 登记切面里的旧失败、未加载值或旧 owner 详情都不是新 feed 的首帧。
      if (registrationSnapshot ||
          !resource.loaded ||
          !stampCurrent(resource.stamp)) {
        return;
      }
      settle(
        () => done.completeError(
          const StudioFailure(
            code: StudioFailureCode.notFound,
            message: 'ACP account is unavailable',
            retryable: false,
            correlationId: 'acp-account',
          ),
        ),
      );
    }

    try {
      final watched = accounts
          .details(identity)
          .watchLatest(
            (resource) => consider(resource, registrationSnapshot: false),
          );
      subscription = watched.observation;
      consider(watched.value, registrationSnapshot: true);
    } catch (error, stackTrace) {
      settle(() => done.completeError(error, stackTrace));
    }
    unawaited(admission.future.then<void>((_) => withdraw()));
    return done.future;
  }

  Future<AcpAuthSnapshotView> _startAuth(
    AcpAccountIdentity identity,
    AcpAuthActionView action, {
    int? expectedConnectionRevision,
    void Function(_AuthBusiness business)? onBusiness,
    bool Function()? shouldIssue,
    _UsageAdmissionWait? admission,
  }) {
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
      action,
      operation,
      demand,
      generation,
      owner,
    );
    _authBusiness[operation.id] = business;
    if (expectedConnectionRevision != null) {
      // 冻结意图的连接身份从创建时即可见：详情确认仍在途时，同连接的等待者
      // 也能加入这一次真实尝试并共享其结算。
      business.connectionRevision = expectedConnectionRevision;
    }
    onBusiness?.call(business);
    return _starts.run(() async {
      try {
        _requireOwner(owner, generation);
        final detail = admission == null
            ? await _details(identity)
            : await _awaitAdmissionDetails(
                identity,
                admission,
                owner: owner,
                generation: generation,
              );
        _requireOwner(owner, generation);
        final revision = detail.account.connectionRevision;
        if (expectedConnectionRevision != null &&
            revision != expectedConnectionRevision) {
          throw const _UsageRefreshWithdrawn();
        }
        if (shouldIssue != null && !shouldIssue()) {
          throw const _UsageRefreshWithdrawn();
        }
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

  /// 账号卡片的额度刷新协调入口（§28.9）。
  ///
  /// 本地队列只做 join / 至多一次在途提交与撤销；权威事实仍由
  /// `_authBusiness` 与运行期认证所有者持有，本地预留不伪装为 canonical。
  @override
  AcpUsageRefreshRequest requestUsageRefresh(
    AcpAccountIdentity identity, {
    required int connectionRevision,
  }) {
    if (connectionRevision < 0)
      throw ArgumentError.value(connectionRevision, 'connectionRevision');
    final waiter = _UsageRefreshWaiter(connectionRevision);
    if (_closed) {
      waiter.fail(StateError('ACP service is closed'));
      return waiter;
    }
    final owner = mutations.coordinator.captureOwner();
    final generation = observations.generation;
    final detail = accounts.details(identity).value;
    if (detail.loaded) {
      final value = detail.value;
      if (value is! AcpAccountDetails ||
          value.account.connectionRevision != connectionRevision) {
        waiter.revoke();
        return waiter;
      }
    }
    var queue = _usageRefreshes[identity];
    if (queue != null &&
        (queue.released ||
            queue.generation != generation ||
            !queue.owner.isCurrent)) {
      _retireUsageQueue(queue);
      queue = null;
    }
    if (queue == null) {
      queue = _UsageRefreshQueue(identity, generation, owner);
      _usageRefreshes[identity] = queue;
    }
    queue.waiters.add(waiter);
    waiter._service = this;
    waiter._queue = queue;
    queue.notify();
    unawaited(_driveUsageRefresh(queue));
    return waiter;
  }

  Future<void> _driveUsageRefresh(_UsageRefreshQueue queue) async {
    if (queue.driving || queue.released) return;
    queue.driving = true;
    try {
      while (!queue.released) {
        queue.waiters.removeWhere((waiter) => waiter.settled);
        _withdrawAbandonedUsageAdmissions(queue);
        queue.waiters.removeWhere((waiter) => waiter.settled);
        if (queue.waiters.isEmpty) break;
        if (_closed ||
            !queue.owner.isCurrent ||
            queue.generation != observations.generation) {
          for (final waiter in queue.waiters.toList()) {
            waiter.revoke();
          }
          break;
        }
        final pending = queue.waiters
            .where((waiter) => waiter.attempt == null)
            .toList();
        if (pending.isEmpty) {
          await queue.waitSignal();
          continue;
        }
        final targetRevision = pending.first.connectionRevision;
        final detail = accounts.details(queue.identity).value;
        if (detail.loaded) {
          final value = detail.value;
          if (value is! AcpAccountDetails ||
              value.account.connectionRevision != targetRevision) {
            for (final waiter in pending) {
              if (waiter.connectionRevision == targetRevision) {
                waiter.revoke();
              }
            }
            continue;
          }
        }
        final joinable = _joinableUsageBusiness(queue, targetRevision);
        if (joinable != null) {
          if (_usageBusinessAdmitted(joinable)) {
            for (final waiter in pending) {
              if (waiter.connectionRevision == targetRevision) {
                waiter.settleJoined();
              }
            }
          } else {
            _bindUsageAttempt(queue, joinable, [
              for (final waiter in pending)
                if (waiter.connectionRevision == targetRevision) waiter,
            ], targetRevision);
          }
          continue;
        }
        if (queue.evidence case final evidence?) {
          if (_auth.value.failure != null) {
            // 认证观察已失败：终止证据不可能到达，撤销未发出的意图。
            for (final waiter in queue.waiters.toList()) {
              waiter.revoke();
            }
            break;
          }
          if (!_usageEvidenceSettled(evidence)) {
            _acquireUsageEvidenceDemand(queue);
            await queue.waitSignal();
            continue;
          }
          queue.evidence = null;
        }
        if (_active.containsKey(queue.identity) ||
            _authBusiness.values.any(
              (business) =>
                  business.identity == queue.identity &&
                  business.generation == queue.generation &&
                  business.connectionRevision == targetRevision,
            )) {
          await queue.waitSignal();
          continue;
        }
        final candidates = [
          for (final waiter in pending)
            if (waiter.connectionRevision == targetRevision &&
                waiter.attempts < _maxUsageRefreshAdmissions)
              waiter,
        ];
        if (candidates.isEmpty) {
          final error = queue.deferredError ?? _busy;
          for (final waiter in pending) {
            if (waiter.connectionRevision == targetRevision) {
              waiter.fail(error);
            }
          }
          continue;
        }
        _issueUsageAttempt(queue, candidates, targetRevision);
      }
    } finally {
      queue.driving = false;
    }
    _drainUsageQueue(queue);
  }

  void _drainUsageQueue(_UsageRefreshQueue queue) {
    queue.waiters.removeWhere((waiter) => waiter.settled);
    if (queue.waiters.isNotEmpty) return;
    if (identical(_usageRefreshes[queue.identity], queue)) {
      _usageRefreshes.remove(queue.identity);
    }
    _releaseDemand(queue.demand);
    queue.demand = null;
    queue.released = true;
  }

  /// 撤销已无有效等待者、或冻结连接已被权威详情证明替换的自有未发出准入。
  ///
  /// 只作用于本队列自有的详情等待；直接消费者发起的业务不受影响。
  void _withdrawAbandonedUsageAdmissions(_UsageRefreshQueue queue) {
    if (queue.attempts.isEmpty) return;
    final resource = accounts.details(queue.identity).value;
    int? authoritativeRevision;
    if (resource.loaded && resource.value is AcpAccountDetails) {
      authoritativeRevision =
          (resource.value as AcpAccountDetails).account.connectionRevision;
    }
    for (final attempt in queue.attempts.values.toList()) {
      if (attempt.finished || attempt.business.issued) continue;
      if (attempt.admission == null) continue;
      final stillWanted = attempt.participants.any((waiter) => !waiter.settled);
      final replaced =
          authoritativeRevision != null &&
          authoritativeRevision != attempt.targetRevision;
      if (stillWanted && !replaced) continue;
      _withdrawUsageAdmission(attempt);
    }
  }

  /// 同步撤销一次自有的未发出准入：终止详情等待并释放槽位与自身观察。
  ///
  /// 原详情读取迟到时只被丢弃：不复活槽位、不触达 port、不影响新尝试。
  void _withdrawUsageAdmission(_UsageAttempt attempt) {
    if (attempt.finished || attempt.business.issued) return;
    attempt.finished = true;
    attempt.observation?.cancel();
    attempt.observation = null;
    final queue = attempt.queue;
    if (identical(queue.attempts[attempt.business.operation.id], attempt)) {
      queue.attempts.remove(attempt.business.operation.id);
    }
    attempt.admission?.withdraw();
    final participants = attempt.participants.toList();
    for (final waiter in participants) {
      if (identical(waiter.attempt, attempt)) waiter.attempt = null;
    }
    if (attempt.business.operation.state.value.failurePhase == null) {
      attempt.business.operation.reject(const _UsageRefreshWithdrawn());
    }
    _releaseAuth(attempt.business.operation.id);
    _finish(queue.identity, attempt.business.operation);
    for (final waiter in participants) {
      waiter.revoke();
    }
    _notifyUsageRefresh(queue.identity);
  }

  void _retireUsageQueue(_UsageRefreshQueue queue) {
    queue.released = true;
    for (final attempt in queue.attempts.values.toList()) {
      attempt.admission?.withdraw();
      attempt.finished = true;
      attempt.observation?.cancel();
      attempt.observation = null;
    }
    queue.attempts.clear();
    for (final waiter in queue.waiters.toList()) {
      if (waiter.settled) continue;
      final attempt = waiter.attempt;
      if (attempt != null && attempt.business.issued) {
        waiter.fail(StateError('ACP runtime owner changed'));
      } else {
        waiter.revoke();
      }
    }
    queue.waiters.clear();
    _releaseDemand(queue.demand);
    queue.demand = null;
    if (identical(_usageRefreshes[queue.identity], queue)) {
      _usageRefreshes.remove(queue.identity);
    }
    queue.notify();
  }

  void _settleUsageQueueClosed(_UsageRefreshQueue queue) {
    queue.released = true;
    for (final attempt in queue.attempts.values.toList()) {
      attempt.admission?.withdraw();
      attempt.finished = true;
      attempt.observation?.cancel();
      attempt.observation = null;
    }
    queue.attempts.clear();
    for (final waiter in queue.waiters.toList()) {
      if (waiter.settled) continue;
      final attempt = waiter.attempt;
      if (attempt != null && attempt.business.issued) {
        waiter.fail(StateError('ACP service closed during usage refresh'));
      } else {
        waiter.revoke();
      }
    }
    queue.waiters.clear();
    _releaseDemand(queue.demand);
    queue.demand = null;
    queue.notify();
  }

  _AuthBusiness? _joinableUsageBusiness(
    _UsageRefreshQueue queue,
    int connectionRevision,
  ) {
    for (final business in _authBusiness.values) {
      if (business.identity != queue.identity ||
          business.generation != queue.generation ||
          !business.owner.isCurrent ||
          business.connectionRevision != connectionRevision ||
          business.action is! AcpQueryUsageActionView) {
        continue;
      }
      // 已发布失败的业务继续持有原观察；等待者排在它后面，不加入失败事实。
      if (business.operation.state.value.failurePhase != null) continue;
      return business;
    }
    return null;
  }

  bool _usageBusinessAdmitted(_AuthBusiness business) {
    final state = business.operation.state.value;
    return state.receipt != null && state.failurePhase == null;
  }

  void _bindUsageAttempt(
    _UsageRefreshQueue queue,
    _AuthBusiness business,
    List<_UsageRefreshWaiter> participants,
    int targetRevision, {
    _UsageAdmissionWait? admission,
  }) {
    if (participants.isEmpty) return;
    final attempt = queue.attempts.putIfAbsent(
      business.operation.id,
      () => _UsageAttempt(
        queue: queue,
        business: business,
        targetRevision: targetRevision,
        // 只有本队列真正发出的提交才有 leader；加入其他来源的业务时
        // 全部参与者按 joined 结算。
        leader: admission == null ? null : participants.first,
        admission: admission,
      ),
    );
    if (attempt.observation == null) {
      attempt.observation = business.operation.state.watch(
        (state) => _onUsageAttemptState(attempt, state),
      );
    }
    for (final waiter in participants) {
      if (waiter.attempt != null) continue;
      waiter.attempt = attempt;
      attempt.participants.add(waiter);
    }
    _onUsageAttemptState(attempt, business.operation.state.value);
  }

  void _onUsageAttemptState(_UsageAttempt attempt, OperationState state) {
    if (attempt.finished) return;
    if (state.receipt != null && state.failurePhase == null) {
      _finishUsageAttempt(attempt);
      final leader = attempt.leader;
      if (leader != null) leader.settleStarted();
      for (final waiter in attempt.participants.toList()) {
        if (!identical(waiter, leader)) waiter.settleJoined();
      }
      _notifyUsageRefresh(attempt.queue.identity);
      return;
    }
    if (state.failurePhase != null) {
      final error = state.error;
      _finishUsageAttempt(attempt);
      if (error != null &&
          identical(error, _busy) &&
          !attempt.business.issued) {
        // 本地占用拒绝：意图未到达传输层，等待者回到待发池继续协调。
        _notifyUsageRefresh(attempt.queue.identity);
        return;
      }
      _handleUsageAttemptError(
        attempt,
        error ?? StateError('ACP usage refresh attempt failed'),
      );
    }
  }

  void _finishUsageAttempt(_UsageAttempt attempt) {
    attempt.finished = true;
    attempt.observation?.cancel();
    attempt.observation = null;
    final queue = attempt.queue;
    if (identical(queue.attempts[attempt.business.operation.id], attempt)) {
      queue.attempts.remove(attempt.business.operation.id);
    }
    if (attempt.business.issued) {
      for (final waiter in attempt.participants) {
        if (!waiter.settled) waiter.attempts += 1;
      }
    }
    for (final waiter in attempt.participants) {
      if (identical(waiter.attempt, attempt)) waiter.attempt = null;
    }
  }

  void _handleUsageAttemptError(_UsageAttempt attempt, Object error) {
    final queue = attempt.queue;
    if (!attempt.business.issued &&
        (error is _UsageRefreshWithdrawn ||
            _closed ||
            !queue.owner.isCurrent ||
            queue.generation != observations.generation)) {
      // 意图从未到达传输层：按契约撤销为 cancelled。直接 check()/queryUsage()
      // 的公开错误语义不受此分类影响。
      for (final waiter in attempt.participants.toList()) {
        waiter.revoke();
      }
      _notifyUsageRefresh(queue.identity);
      return;
    }
    if (attempt.business.issued &&
        error is StudioFailure &&
        error.code == StudioFailureCode.busy) {
      final facet = _decodeAcpAuthBusyFacet(error.detailsJson);
      final sourceCurrent =
          !_closed &&
          queue.owner.isCurrent &&
          queue.generation == observations.generation;
      if (facet != null &&
          sourceCurrent &&
          facet.accountId == queue.identity.accountId) {
        if (facet.connectionRevision != attempt.targetRevision) {
          // 运行时连接身份已前进：冻结的旧意图撤销，不复用旧查询结果。
          for (final waiter in attempt.participants.toList()) {
            waiter.revoke();
          }
          _notifyUsageRefresh(queue.identity);
          return;
        }
        if (facet.activeAction is AcpQueryUsageActionView &&
            facet.activeConnectionRevision == attempt.targetRevision) {
          // 当前连接上已有真实额度查询：观察它即可，即使 busy 帧被跳过。
          for (final waiter in attempt.participants.toList()) {
            waiter.settleJoined();
          }
          _notifyUsageRefresh(queue.identity);
          return;
        }
        // 其他动作或旧连接占用：等待该操作在同 owner 观察中终止后再准入。
        queue.deferredError = error;
        queue.evidence = _UsageEvidence(
          accountId: facet.accountId,
          operationId: facet.activeOperationId,
          snapshotRevision: facet.snapshotRevision,
          ownerEpoch: observations.ownerEpoch,
        );
        _notifyUsageRefresh(queue.identity);
        return;
      }
      // busy 切面缺失或格式错误：保留原错误并停止，不猜测、不盲重试。
    }
    for (final waiter in attempt.participants.toList()) {
      waiter.fail(error);
    }
    _notifyUsageRefresh(queue.identity);
  }

  void _issueUsageAttempt(
    _UsageRefreshQueue queue,
    List<_UsageRefreshWaiter> participants,
    int targetRevision,
  ) {
    _AuthBusiness? business;
    Object? admissionError;
    Future<AcpAuthSnapshotView>? submitted;
    final admission = _UsageAdmissionWait();
    try {
      submitted = _startAuth(
        queue.identity,
        const AcpQueryUsageActionView(),
        expectedConnectionRevision: targetRevision,
        onBusiness: (created) => business = created,
        shouldIssue: () {
          final current = business;
          return current != null && _usageAttemptStillWanted(queue, current);
        },
        admission: admission,
      );
    } catch (error) {
      admissionError = error;
    }
    final failure = admissionError;
    if (failure != null) {
      for (final waiter in participants) {
        waiter.fail(failure);
      }
      _notifyUsageRefresh(queue.identity);
      return;
    }
    final created = business;
    if (created != null) {
      _bindUsageAttempt(
        queue,
        created,
        participants,
        targetRevision,
        admission: admission,
      );
    }
    // 业务操作状态驱动本次尝试的一切决策；命令 future 只证明提交已收束。
    unawaited(
      submitted!.then<void>(
        (_) => _notifyUsageRefresh(queue.identity),
        onError: (Object error, StackTrace _) {
          _notifyUsageRefresh(queue.identity);
          if (created != null) return;
          if (identical(error, _busy)) return;
          for (final waiter in participants.toList()) {
            waiter.fail(error);
          }
        },
      ),
    );
  }

  /// 该尝试是否仍值得真正提交：仍有未结算等待者，且来源、连接与环境有效。
  ///
  /// 闸门在详情确认之后、`port.startAcpAuth` 之前的同步段执行；最后
  /// 一位等待者取消时撤销尚未发出的意图，不启动受管进程。
  bool _usageAttemptStillWanted(
    _UsageRefreshQueue queue,
    _AuthBusiness business,
  ) {
    if (_closed || queue.released) return false;
    if (!queue.owner.isCurrent || queue.generation != observations.generation) {
      return false;
    }
    final attempt = queue.attempts[business.operation.id];
    if (attempt == null || attempt.finished) return false;
    final detail = accounts.details(queue.identity).value;
    if (detail.loaded) {
      final value = detail.value;
      if (value is! AcpAccountDetails ||
          value.account.connectionRevision != attempt.targetRevision) {
        return false;
      }
    }
    for (final waiter in attempt.participants) {
      if (!waiter.settled) return true;
    }
    return false;
  }

  bool _usageEvidenceSettled(_UsageEvidence evidence) {
    final resource = _auth.value;
    final stamp = resource.stamp;
    final snapshot = resource.value;
    if (stamp == null || snapshot == null) return false;
    // 换代后残留的旧 owner 快照无论 revision 多高，都不能充当本次 Busy 的
    // 终止证据；证据必须来自记录切面时同一授权 owner 的观察。
    final ownerEpoch = evidence.ownerEpoch;
    if (ownerEpoch != null && stamp.ownerEpoch != ownerEpoch) return false;
    if (stamp.revision < evidence.snapshotRevision) return false;
    for (final account in snapshot.accounts) {
      if (account.accountId != evidence.accountId) continue;
      if (account.activeOperation?.operationId == evidence.operationId) {
        return false;
      }
      if (account.state.isBusy &&
          account.state.operationId == evidence.operationId) {
        return false;
      }
    }
    return true;
  }

  void _acquireUsageEvidenceDemand(_UsageRefreshQueue queue) {
    if (queue.demand != null) return;
    try {
      queue.demand = observations.acquire(const AcpAuthTarget());
    } catch (error) {
      queue.evidence = null;
      for (final waiter in queue.waiters.toList()) {
        if (waiter.attempt == null && !waiter.settled) waiter.fail(error);
      }
    }
  }

  void _notifyUsageRefresh(AcpAccountIdentity identity) {
    final queue = _usageRefreshes[identity];
    if (queue == null) return;
    queue.notify();
    unawaited(_driveUsageRefresh(queue));
  }

  void _notifyUsageRefreshFrames() {
    for (final queue in _usageRefreshes.values.toList()) {
      queue.notify();
      unawaited(_driveUsageRefresh(queue));
    }
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
    _continuations.seal();
    _detectionStarts.seal();
    _detectionCancels.seal();
    for (final entry in _savedWaiters.entries.toList()) {
      for (final observation in entry.value) {
        observation.cancel();
      }
      entry.key.completeError(StateError('ACP save observation closed'));
    }
    _savedWaiters.clear();
    for (final queue in _usageRefreshes.values.toList()) {
      _settleUsageQueueClosed(queue);
    }
    _usageRefreshes.clear();
    return Future.wait([
      _starts.join(),
      _cancels.join(),
      _continuations.join(),
      _detectionStarts.join(),
      _detectionCancels.join(),
    ]);
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
    this.action,
    this.operation,
    this.demand,
    this.generation,
    this.owner,
  );
  final AcpAccountIdentity identity;

  /// 本进程真实提交的启动动作；等待者据此区分可加入的额度查询。
  final AcpAuthActionView action;
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
            usage: _immutableUsage(account.usage),
            activeOperation: account.activeOperation,
            state: account.state is AcpRequiredState
                ? AcpRequiredState(
                    operationId:
                        (account.state as AcpRequiredState).operationId,
                    server: (account.state as AcpRequiredState).server,
                    methods: List.unmodifiable(
                      (account.state as AcpRequiredState).methods,
                    ),
                  )
                : account.state,
          ),
      ]),
    );

AcpUsageObservationView? _immutableUsage(AcpUsageObservationView? usage) =>
    usage == null
    ? null
    : AcpUsageObservationView(
        checkedAt: usage.checkedAt,
        state: switch (usage.state) {
          AcpUsageReadyView(:final groups) => AcpUsageReadyView(
            groups: List.unmodifiable([
              for (final group in groups)
                AcpQuotaGroupView(
                  name: group.name,
                  limits: List.unmodifiable(group.limits),
                ),
            ]),
          ),
          final state => state,
        },
      );
AcpInstallSnapshotView _immutableInstall(AcpInstallSnapshotView snapshot) =>
    AcpInstallSnapshotView(
      revision: snapshot.revision,
      updatedAt: snapshot.updatedAt,
      installations: List.unmodifiable(snapshot.installations),
    );

/// 终止一个占用操作所需的同 owner 观察证据（§28.9）。
final class _UsageEvidence {
  const _UsageEvidence({
    required this.accountId,
    required this.operationId,
    required this.snapshotRevision,
    required this.ownerEpoch,
  });

  final String accountId;
  final String operationId;
  final int snapshotRevision;

  /// 记录 Busy 切面时 acpAuth topic 的授权 owner；终止证据必须同源。
  final String? ownerEpoch;
}

/// 协调入口在意图到达传输层前撤销该次提交（无有效等待者或连接已替换）。
final class _UsageRefreshWithdrawn implements Exception {
  const _UsageRefreshWithdrawn();

  @override
  String toString() =>
      'The ACP usage refresh intent was withdrawn before it was issued';
}

/// Busy 拒绝在同一准入锁内生成的结构化切面。
final class _AcpAuthBusyFacet {
  const _AcpAuthBusyFacet({
    required this.accountId,
    required this.connectionRevision,
    required this.snapshotRevision,
    required this.activeOperationId,
    required this.activeConnectionRevision,
    required this.activeAction,
  });

  final String accountId;

  /// 拒绝时该账号的当前连接修订；与等待者冻结的修订不一致表示连接已替换。
  final int connectionRevision;
  final int snapshotRevision;
  final String activeOperationId;
  final int activeConnectionRevision;
  final AcpAuthActionView activeAction;
}

/// 一个可撤销的额度刷新等待者；result 只做本地准入/加入结算。
final class _UsageRefreshWaiter implements AcpUsageRefreshRequest {
  _UsageRefreshWaiter(this.connectionRevision);

  final int connectionRevision;
  final Completer<AcpUsageRefreshDisposition> _result =
      Completer<AcpUsageRefreshDisposition>();
  AcpServiceImpl? _service;
  _UsageRefreshQueue? _queue;
  _UsageAttempt? attempt;
  int attempts = 0;
  bool settled = false;

  @override
  Future<AcpUsageRefreshDisposition> get result => _result.future;

  @override
  void cancelPending() {
    if (settled) return;
    _settle(AcpUsageRefreshDisposition.cancelled);
    // 外部取消可能落在 driver 的等待点上：必须唤醒协调，否则最后一位等待者
    // 离开会让队列与本地观察 demand 无限保留。
    final service = _service;
    final queue = _queue;
    if (service != null && queue != null) {
      service._notifyUsageRefresh(queue.identity);
    }
  }

  void settleStarted() => _settle(AcpUsageRefreshDisposition.started);

  void settleJoined() => _settle(AcpUsageRefreshDisposition.joined);

  /// 环境撤销只作用于尚未随真实尝试发出的意图；已发出的尝试按原错误结算。
  void revoke() {
    final attempt = this.attempt;
    if (attempt != null && !attempt.finished) return;
    _settle(AcpUsageRefreshDisposition.cancelled);
  }

  void fail(Object error) {
    if (settled) return;
    settled = true;
    _result.completeError(error);
  }

  void _settle(AcpUsageRefreshDisposition disposition) {
    if (settled) return;
    settled = true;
    _result.complete(disposition);
  }
}

/// 一次绑定到真实 `_AuthBusiness` 的提交/加入尝试。
final class _UsageAttempt {
  _UsageAttempt({
    required this.queue,
    required this.business,
    required this.targetRevision,
    required this.leader,
    this.admission,
  });

  final _UsageRefreshQueue queue;
  final _AuthBusiness business;
  final int targetRevision;

  /// 触发本次真实提交的等待者；仅本队列发出的提交非空，准入时结算
  /// started。加入其他来源的业务时为 null，所有参与者结算 joined。
  final _UsageRefreshWaiter? leader;

  /// 本队列自有详情等待的撤销信号；加入外部业务时为 null。
  final _UsageAdmissionWait? admission;
  final List<_UsageRefreshWaiter> participants = [];
  Observation? observation;
  bool finished = false;
}

/// 协调准入自有详情等待的终止信号：撤销后迟到的详情帧只被丢弃。
final class _UsageAdmissionWait {
  final Completer<void> _withdrawn = Completer<void>();
  bool _done = false;

  bool get withdrawn => _done;

  void withdraw() {
    if (_done) return;
    _done = true;
    if (!_withdrawn.isCompleted) _withdrawn.complete();
  }

  Future<void> get future => _withdrawn.future;
}

/// 单账号额度刷新协调队列；不同账号互不阻塞。
final class _UsageRefreshQueue {
  _UsageRefreshQueue(this.identity, this.generation, this.owner);

  final AcpAccountIdentity identity;
  final int generation;
  final SettingsWriteOwner owner;
  final List<_UsageRefreshWaiter> waiters = [];
  final Map<OperationId, _UsageAttempt> attempts = {};
  _UsageEvidence? evidence;

  /// 证据链耗尽准入次数时保留的最后 Busy 原错误。
  Object? deferredError;
  AccountDemand? demand;
  bool driving = false;
  bool released = false;
  bool _signaled = false;
  Completer<void>? _signal;

  void notify() {
    if (_signaled) return;
    _signaled = true;
    final signal = _signal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<void> waitSignal() {
    if (_signaled) {
      _signaled = false;
      return Future<void>.value();
    }
    final signal = _signal = Completer<void>();
    return signal.future.then((_) {
      _signal = null;
      _signaled = false;
    });
  }
}

/// 严格解码 `acpAuthBusy` 结构化切面；缺失或类型不符一律返回 null。
_AcpAuthBusyFacet? _decodeAcpAuthBusyFacet(String? detailsJson) {
  if (detailsJson == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(detailsJson);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final facet = decoded['acpAuthBusy'];
  if (facet is! Map<String, dynamic>) return null;
  final accountId = facet['accountId'];
  if (accountId is! String || accountId.isEmpty) return null;
  final connectionRevision = facet['connectionRevision'];
  if (connectionRevision is! int || connectionRevision < 0) return null;
  final snapshotRevision = facet['snapshotRevision'];
  if (snapshotRevision is! int || snapshotRevision < 0) return null;
  final activeOperation = facet['activeOperation'];
  if (activeOperation is! Map<String, dynamic>) return null;
  final operationId = activeOperation['operationId'];
  if (operationId is! String || operationId.isEmpty) return null;
  final activeConnectionRevision = activeOperation['connectionRevision'];
  if (activeConnectionRevision is! int || activeConnectionRevision < 0) {
    return null;
  }
  final action = activeOperation['action'];
  if (action is! Map<String, dynamic>) return null;
  final actionKind = action['action'];
  final AcpAuthActionView activeAction;
  if (actionKind == 'check') {
    activeAction = const AcpCheckActionView();
  } else if (actionKind == 'queryUsage') {
    activeAction = const AcpQueryUsageActionView();
  } else {
    return null;
  }
  return _AcpAuthBusyFacet(
    accountId: accountId,
    connectionRevision: connectionRevision,
    snapshotRevision: snapshotRevision,
    activeOperationId: operationId,
    activeConnectionRevision: activeConnectionRevision,
    activeAction: activeAction,
  );
}
