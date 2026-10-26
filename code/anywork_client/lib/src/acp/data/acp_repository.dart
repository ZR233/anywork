import 'dart:async';

import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../domain/acp_auth_repository.dart';
import '../domain/acp_auth_state.dart';
import '../domain/acp_install_repository.dart';
import '../domain/acp_install_state.dart';
import '../domain/acp_observation_lease.dart';
import '../domain/acp_values.dart';
import 'acp_frames.dart';
import 'acp_port.dart';
import 'acp_reads.dart';

/// 认证回执绑定的资源身份；与 `acpAuth` topic 的 `resourceKey` 一致。
const _authKey = 'acp-auth';

/// 安装回执绑定的资源身份；与 `acpInstall` topic 的 `resourceKey` 一致。
const _installKey = 'acp-install';

/// 纯装配：不打开订阅，也不发起任何原生调用。
///
/// 两个资源各有自己的 revision、owner epoch、准入与关闭责任，因此各自独立装配：
/// 共享同一个 [AcpPort] 不表示共享状态或水位。
AcpAuthRepository createAcpAuthRepository({
  required AcpPort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _AcpAuthRepository(port, budget, operations);

AcpInstallRepository createAcpInstallRepository({
  required AcpPort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _AcpInstallRepository(port, budget, operations);

// ---------------------------------------------------------------------------
// `acpAuth` owner
// ---------------------------------------------------------------------------

final class _AcpAuthRepository implements AcpAuthRepository {
  _AcpAuthRepository(
    AcpPort port,
    ResourceBudget budget,
    OperationRecorder operations,
  ) : lifetime = ResourceLifetime(budget) {
    mirror = _AcpAuthMirror(port, lifetime, operations);
    actions = _AcpAuthActions(port, mirror, lifetime, operations);
  }

  final ResourceLifetime lifetime;
  late final _AcpAuthMirror mirror;
  late final _AcpAuthActions actions;
  bool _sourceClosed = false;

  @override
  ReadonlyLatestValue<AcpAuthObservation> get state => mirror.source.readonly;
  @override
  Future<void> synchronize() => mirror.synchronize();
  @override
  Future<void> retrySync() => mirror.retrySync();
  @override
  AcpObservationLease<AcpAuthObservation> observe({
    void Function(AcpAuthObservation state)? onState,
    bool fireImmediately = true,
  }) => mirror.lease(onState: onState, fireImmediately: fireImmediately);
  @override
  Future<AcpAuthSnapshot> readCanonical() => mirror.readCanonical();
  @override
  Future<AcpAccountCatalog> readCatalog() => mirror.readCatalog();
  @override
  OperationTicket<AcpAuthSnapshot> check({
    required String accountId,
    required int expectedConnectionRevision,
  }) => actions.check(
    accountId: accountId,
    expectedConnectionRevision: expectedConnectionRevision,
  );
  @override
  OperationTicket<AcpAuthSnapshot> authenticate({
    required String accountId,
    required int expectedConnectionRevision,
    required String methodId,
  }) => actions.authenticate(
    accountId: accountId,
    expectedConnectionRevision: expectedConnectionRevision,
    methodId: methodId,
  );
  @override
  OperationTicket<AcpAuthSnapshot> cancel({
    required String accountId,
    required String targetOperationId,
  }) => actions.cancel(
    accountId: accountId,
    targetOperationId: targetOperationId,
  );

  @override
  void seal() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final report = await lifetime.close(deadline: deadline, retry: retry);
    if (report.complete && !_sourceClosed) {
      _sourceClosed = true;
      final current = mirror.source.value;
      mirror.source.publish(
        AcpAuthObservation(
          projection: current.projection.copyWith(
            sync: const ResourceSyncState(
              phase: ResourceSyncPhase.closed,
              error: null,
              retryExhausted: false,
            ),
          ),
          snapshot: current.snapshot,
        ),
      );
      mirror.source.close();
    }
    return report;
  }
}

/// One canonical publisher for `acpAuth`; command return values never enter it.
final class _AcpAuthMirror implements _AcpCanonicalSource {
  _AcpAuthMirror(this.port, this.lifetime, this.operations)
    : source = ResourceSource(
        AcpAuthObservation.idle,
        lifetime.budget,
        'acp-auth:observer',
      ) {
    lifetime.onSeal(source.seal);
  }

  final AcpPort port;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final ResourceSource<AcpAuthObservation> source;

  ProductFeedOwner<AcpAuthFrame>? _feed;
  ProductProjectionStamp? _feedStamp;
  Future<void>? _restarting;
  int _recoveries = 0;

  @override
  ProductReadOrigin? get origin => _feedStamp?.origin;

  Future<void> synchronize() {
    lifetime.admit();
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
    }
    return lifetime.run('acp-auth:synchronize', () async {
      await ready();
    });
  }

  Future<void> retrySync() {
    lifetime.admit();
    _recoveries = 0;
    final feed = _feed;
    if (feed == null) return synchronize();
    return lifetime.run('acp-auth:explicit-sync', () async {
      await _restart(feed, retry: true);
      await ready();
    });
  }

  /// Starts the shared subscription on first demand and waits for its baseline.
  Future<AcpAuthObservation> ready() async {
    lifetime.admit();
    if (_feed == null) _start();
    return source.waitFor((value) {
      final sync = value.projection.sync;
      if (sync.phase == ResourceSyncPhase.failed) throw sync.error!;
      if (sync.phase == ResourceSyncPhase.closed) throw resourceCancelled;
      return sync.phase == ResourceSyncPhase.ready;
    });
  }

  AcpObservationLease<AcpAuthObservation> lease({
    void Function(AcpAuthObservation state)? onState,
    required bool fireImmediately,
  }) {
    lifetime.admit();
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
    }
    final observation = source.watch(
      onState ?? _ignoreAuthState,
      fireImmediately: fireImmediately,
    );
    return _AcpObservationLease<AcpAuthObservation>(
      latest: source.readonly,
      observation: observation,
    );
  }

  /// Named bounded read; it never starts a process and never publishes state.
  ///
  /// The subscription is the only writer of this mirror, so a diagnostic read
  /// can never relabel canonical state with a late or foreign observation.
  Future<AcpAuthSnapshot> readCanonical() =>
      lifetime.run('acp-auth:canonical-read', () async {
        final snapshot = await port.readAuthState();
        validateAcpAuthSnapshot(snapshot);
        return snapshot;
      });

  /// Named bounded catalog read; templates are product defaults, not facts.
  Future<AcpAccountCatalog> readCatalog() =>
      lifetime.run('acp-auth:catalog-read', () async {
        final catalog = await port.readAccountCatalog();
        validateAcpAccountCatalog(catalog);
        return catalog;
      });

  /// Waits until the canonical mirror covers the accepted command's watermark.
  ///
  /// Observing a receipt may open the subscription on demand; that never starts
  /// an ACP process, a probe or a download — those stay explicit commands.
  @override
  Future<void> observe(CommitReceipt receipt) async {
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
    }
    await source.waitFor((value) {
      final sync = value.projection.sync;
      if (sync.phase == ResourceSyncPhase.failed) throw sync.error!;
      if (sync.phase == ResourceSyncPhase.closed) throw resourceCancelled;
      final stamp = value.projection.stamp;
      final header = value.projection.header;
      if (stamp == null || header == null) return false;
      final target = receipt.targets.single as ResourceStamp;
      if (stamp.ownerEpoch != target.ownerEpoch) {
        throw const StudioFailure(
          code: StudioFailureCode.superseded,
          message:
              'The original ACP authentication command source was replaced.',
          retryable: false,
          correlationId: 'acp-auth',
        );
      }
      return header.revision >= target.revision;
    });
  }

  void _sync(
    ResourceSyncPhase phase, {
    StudioFailure? error,
    bool exhausted = false,
  }) {
    final current = source.value;
    source.publish(
      AcpAuthObservation(
        projection: current.projection.copyWith(
          sync: ResourceSyncState(
            phase: phase,
            error: error,
            retryExhausted: exhausted,
          ),
        ),
        snapshot: current.snapshot,
      ),
    );
  }

  void _start() {
    lifetime.admit();
    _feedStamp = null;
    late final ProductFeedOwner<AcpAuthFrame> feed;
    feed = ProductFeedOwner<AcpAuthFrame>(
      lifetime: lifetime,
      owner: 'acp-auth:feed',
      open: port.openAcpAuth,
      sequence: (frame) => frame is AcpAuthData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (lifetime.sealed || !identical(_feed, feed)) {
          return frame is AcpAuthData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case AcpAuthData(:final deliverySequence, :final event):
            switch (event) {
              case AcpAuthBaseline(
                :final identity,
                :final stamp,
                :final snapshot,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.acpAuth ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol(
                    'The acpAuth baseline has another feed identity.',
                  );
                }
                feed.bindIdentity(identity);
                _adopt(stamp, snapshot);
                _feedStamp = stamp;
              case AcpAuthChanged(
                :final stamp,
                :final baseRevision,
                :final snapshot,
              ):
                final prior = _feedStamp;
                if (prior == null ||
                    stamp.origin != prior.origin ||
                    baseRevision != prior.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol(
                    'The acpAuth product projection has a revision gap.',
                  );
                }
                _adopt(stamp, snapshot);
                _feedStamp = stamp;
            }
            return deliverySequence;
          case AcpAuthResyncRequired(:final identity):
            _control(feed, identity);
            _recover(feed);
          case AcpAuthFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case AcpAuthClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _recover(feed);
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.runtimeStopped,
                  message: 'The acpAuth source has closed.',
                  retryable: false,
                  correlationId: 'acp-auth',
                ),
              );
            }
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _sync(ResourceSyncPhase.connecting);
  }

  void _control(
    ProductFeedOwner<AcpAuthFrame> feed,
    ProductFeedIdentity identity,
  ) {
    final stamp = _feedStamp;
    if (identity.resource != ProductResource.acpAuth ||
        stamp != null &&
            (identity.ownerEpoch != stamp.ownerEpoch ||
                identity.incarnation != stamp.incarnation)) {
      throw resourceProtocol(
        'An acpAuth control frame belongs to another source.',
      );
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<AcpAuthFrame> feed, StudioFailure error) {
    if (lifetime.sealed || !identical(_feed, feed)) return;
    if (error.retryable && _recoveries < 2) {
      _recover(feed, failure: error);
      return;
    }
    _sync(ResourceSyncPhase.failed, error: error, exhausted: _recoveries >= 2);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _recover(ProductFeedOwner<AcpAuthFrame> feed, {StudioFailure? failure}) {
    if (lifetime.sealed || !identical(_feed, feed) || _restarting != null) {
      return;
    }
    if (_recoveries >= 2) {
      _failed(
        feed,
        failure ??
            const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The acpAuth feed recovery budget is exhausted.',
              retryable: false,
              correlationId: 'acp-auth',
            ),
      );
      return;
    }
    ++_recoveries;
    unawaited(
      _restart(feed).then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  Future<void> _restart(
    ProductFeedOwner<AcpAuthFrame> feed, {
    bool retry = false,
  }) {
    lifetime.admit();
    final pending = _restarting;
    if (pending != null) return pending;
    final done = Completer<void>();
    _restarting = done.future;
    _sync(ResourceSyncPhase.reconnecting);
    feed.requestClose();
    unawaited(
      Future<void>.sync(
        () => lifetime.run('acp-auth:resync', () async {
          await feed.cleanup(retry: retry);
          lifetime.admit();
          if (!feed.released) {
            throw const StudioFailure(
              code: StudioFailureCode.busy,
              message: 'The original acpAuth feed retains unresolved cleanup.',
              retryable: true,
              correlationId: 'acp-auth',
            );
          }
        }),
      ).then<void>(
        (_) {
          _restarting = null;
          if (!lifetime.sealed && identical(_feed, feed)) {
            try {
              _start();
            } catch (error, stack) {
              lifetime.lastCause = error;
              lifetime.lastStack = stack;
              _sync(ResourceSyncPhase.failed, error: resourceFailure(error));
              done.completeError(resourceFailure(error), stack);
              return;
            }
          }
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          _restarting = null;
          if (!lifetime.sealed) {
            _sync(
              ResourceSyncPhase.failed,
              error: resourceFailure(error),
              exhausted: _recoveries >= 2,
            );
          }
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  void _adopt(ProductProjectionStamp stamp, AcpAuthSnapshot snapshot) {
    validateAcpAuthSnapshot(snapshot);
    if (stamp.revision < 0 ||
        stamp.incarnation < 0 ||
        stamp.revision != snapshot.revision) {
      throw resourceProtocol(
        'The acpAuth projection stamp disagrees with its snapshot revision.',
      );
    }
    final current = source.value;
    final previous = current.projection;
    if (previous.stamp?.ownerEpoch == stamp.ownerEpoch) {
      if (previous.stamp!.origin == stamp.origin &&
          previous.stamp!.revision > stamp.revision) {
        throw resourceProtocol(
          'The acpAuth source moved backwards within one owner.',
        );
      }
      final known = current.snapshot;
      if (known != null &&
          known.reference.ownerEpoch == stamp.ownerEpoch &&
          known.value.revision == snapshot.revision &&
          known.value != snapshot) {
        throw resourceProtocol(
          'An acpAuth domain revision changed its immutable value.',
        );
      }
    }
    final reference = ResourceStamp(
      resourceKey: _authKey,
      ownerEpoch: stamp.ownerEpoch,
      revision: snapshot.revision,
    );
    source.publish(
      AcpAuthObservation(
        projection: ProductProjection<AcpAuthHeader>(
          stamp: stamp,
          header: AcpAuthHeader(
            revision: snapshot.revision,
            updatedAt: snapshot.updatedAt,
          ),
          sync: const ResourceSyncState(
            phase: ResourceSyncPhase.ready,
            error: null,
            retryExhausted: false,
          ),
        ),
        snapshot: Materialized<AcpAuthSnapshot, ResourceStamp>(
          origin: stamp.origin,
          reference: reference,
          value: snapshot,
        ),
      ),
    );
    operations.observe(reference);
  }
}

void _ignoreAuthState(AcpAuthObservation _) {}

final class _AcpAuthActions {
  _AcpAuthActions(this.port, this.mirror, this.lifetime, this.operations);

  final AcpPort port;
  final _AcpAuthMirror mirror;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;

  /// 每个接入至多一个已受理的认证操作。
  final Map<String, OperationId> _active = {};

  /// 每个接入至多一个在途取消意图；取消不排队在 start 之后。
  final Map<String, OperationId> _cancelling = {};

  OperationTicket<AcpAuthSnapshot> check({
    required String accountId,
    required int expectedConnectionRevision,
  }) => _start(
    accountId,
    expectedConnectionRevision,
    const AcpAuthAction.check(),
  );

  OperationTicket<AcpAuthSnapshot> authenticate({
    required String accountId,
    required int expectedConnectionRevision,
    required String methodId,
  }) => _start(
    accountId,
    expectedConnectionRevision,
    AcpAuthAction.authenticate(methodId: methodId),
  );

  OperationTicket<AcpAuthSnapshot> _start(
    String accountId,
    int connectionRevision,
    AcpAuthAction action,
  ) => _runAction<AcpAuthSnapshot>(
    lifetime: lifetime,
    operations: operations,
    canonical: mirror,
    resourceKey: _authKey,
    target: 'acp-auth:$accountId',
    validate: validateAcpAuthSnapshot,
    action: (owner) async {
      _requireIdentifier(accountId, 'ACP account id');
      _requireRevision(connectionRevision, 'Connection revision');
      if (action case AcpAuthAuthenticate(:final methodId)) {
        _requireIdentifier(methodId, 'ACP authentication method');
      }
      if (_active.containsKey(accountId)) {
        throw StudioFailure(
          code: StudioFailureCode.busy,
          message:
              'An ACP authentication operation is already active for '
              '$accountId.',
          retryable: false,
          correlationId: _authKey,
        );
      }
      final admission = owner.id;
      _active[accountId] = admission;
      owner.onSettled(() {
        if (identical(_active[accountId], admission)) _active.remove(accountId);
      });
      final reply = await owner.invoke(
        () => port.startAuth(
          AcpAuthStartRequest(
            operationId: owner.id,
            accountId: accountId,
            expectedConnectionRevision: connectionRevision,
            action: action,
          ),
        ),
      );
      owner.confirmReceipt(reply.receipt, revision: reply.snapshot.revision);
      _acceptance(
        reply.snapshot,
        accountId: accountId,
        connectionRevision: connectionRevision,
        operationId: owner.id.value,
      );
      await owner.commit(reply.snapshot);
    },
  );

  OperationTicket<AcpAuthSnapshot> cancel({
    required String accountId,
    required String targetOperationId,
  }) => _runAction<AcpAuthSnapshot>(
    lifetime: lifetime,
    operations: operations,
    canonical: mirror,
    resourceKey: _authKey,
    target: 'acp-auth:cancel:$accountId',
    validate: validateAcpAuthSnapshot,
    action: (owner) async {
      _requireIdentifier(accountId, 'ACP account id');
      _requireIdentifier(targetOperationId, 'ACP target operation');
      if (_cancelling.containsKey(accountId)) {
        throw StudioFailure(
          code: StudioFailureCode.busy,
          message:
              'An ACP authentication cancel is already in flight for '
              '$accountId.',
          retryable: false,
          correlationId: _authKey,
        );
      }
      final admission = owner.id;
      _cancelling[accountId] = admission;
      owner.onSettled(() {
        if (identical(_cancelling[accountId], admission)) {
          _cancelling.remove(accountId);
        }
      });
      final reply = await owner.invoke(
        () => port.cancelAuth(
          AcpAuthCancelRequest(
            operationId: owner.id,
            accountId: accountId,
            targetOperationId: OperationId(targetOperationId),
          ),
        ),
      );
      owner.confirmReceipt(reply.receipt, revision: reply.snapshot.revision);
      _acceptance(
        reply.snapshot,
        accountId: accountId,
        operationId: targetOperationId,
      );
      await owner.commit(reply.snapshot);
    },
  );
}

/// The acceptance snapshot must name the operation this command accepted.
void _acceptance(
  AcpAuthSnapshot snapshot, {
  required String accountId,
  required String operationId,
  int? connectionRevision,
}) {
  final account = connectionRevision == null
      ? snapshot.accountById(accountId)
      : snapshot.account(accountId, connectionRevision: connectionRevision);
  if (account == null || account.state.operationId != operationId) {
    throw resourceProtocol(
      'The ACP authentication acceptance does not carry this operation.',
    );
  }
}

// ---------------------------------------------------------------------------
// `acpInstall` owner
// ---------------------------------------------------------------------------

final class _AcpInstallRepository implements AcpInstallRepository {
  _AcpInstallRepository(
    AcpPort port,
    ResourceBudget budget,
    OperationRecorder operations,
  ) : lifetime = ResourceLifetime(budget) {
    mirror = _AcpInstallMirror(port, lifetime, operations);
    actions = _AcpInstallActions(port, mirror, lifetime, operations);
  }

  final ResourceLifetime lifetime;
  late final _AcpInstallMirror mirror;
  late final _AcpInstallActions actions;
  bool _sourceClosed = false;

  @override
  ReadonlyLatestValue<AcpInstallObservation> get state =>
      mirror.source.readonly;
  @override
  Future<void> synchronize() => mirror.synchronize();
  @override
  Future<void> retrySync() => mirror.retrySync();
  @override
  AcpObservationLease<AcpInstallObservation> observe({
    void Function(AcpInstallObservation state)? onState,
    bool fireImmediately = true,
  }) => mirror.lease(onState: onState, fireImmediately: fireImmediately);
  @override
  Future<AcpInstallSnapshot> readCanonical() => mirror.readCanonical();
  @override
  OperationTicket<AcpInstallSnapshot> prepare(AcpProvider provider) =>
      actions.prepare(provider);
  @override
  OperationTicket<AcpInstallSnapshot> cancel(
    AcpProvider provider, {
    required String targetOperationId,
  }) => actions.cancel(provider, targetOperationId: targetOperationId);

  @override
  void seal() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final report = await lifetime.close(deadline: deadline, retry: retry);
    if (report.complete && !_sourceClosed) {
      _sourceClosed = true;
      final current = mirror.source.value;
      mirror.source.publish(
        AcpInstallObservation(
          projection: current.projection.copyWith(
            sync: const ResourceSyncState(
              phase: ResourceSyncPhase.closed,
              error: null,
              retryExhausted: false,
            ),
          ),
          snapshot: current.snapshot,
        ),
      );
      mirror.source.close();
    }
    return report;
  }
}

/// One canonical publisher for `acpInstall`; install progress enters only here.
final class _AcpInstallMirror implements _AcpCanonicalSource {
  _AcpInstallMirror(this.port, this.lifetime, this.operations)
    : source = ResourceSource(
        AcpInstallObservation.idle,
        lifetime.budget,
        'acp-install:observer',
      ) {
    lifetime.onSeal(source.seal);
  }

  final AcpPort port;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final ResourceSource<AcpInstallObservation> source;

  ProductFeedOwner<AcpInstallFrame>? _feed;
  ProductProjectionStamp? _feedStamp;
  Future<void>? _restarting;
  int _recoveries = 0;

  @override
  ProductReadOrigin? get origin => _feedStamp?.origin;

  Future<void> synchronize() {
    lifetime.admit();
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
    }
    return lifetime.run('acp-install:synchronize', () async {
      await ready();
    });
  }

  Future<void> retrySync() {
    lifetime.admit();
    _recoveries = 0;
    final feed = _feed;
    if (feed == null) return synchronize();
    return lifetime.run('acp-install:explicit-sync', () async {
      await _restart(feed, retry: true);
      await ready();
    });
  }

  Future<AcpInstallObservation> ready() async {
    lifetime.admit();
    if (_feed == null) _start();
    return source.waitFor((value) {
      final sync = value.projection.sync;
      if (sync.phase == ResourceSyncPhase.failed) throw sync.error!;
      if (sync.phase == ResourceSyncPhase.closed) throw resourceCancelled;
      return sync.phase == ResourceSyncPhase.ready;
    });
  }

  AcpObservationLease<AcpInstallObservation> lease({
    void Function(AcpInstallObservation state)? onState,
    required bool fireImmediately,
  }) {
    lifetime.admit();
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
    }
    final observation = source.watch(
      onState ?? _ignoreInstallState,
      fireImmediately: fireImmediately,
    );
    return _AcpObservationLease<AcpInstallObservation>(
      latest: source.readonly,
      observation: observation,
    );
  }

  /// Named bounded read; it never downloads, scans or publishes state.
  Future<AcpInstallSnapshot> readCanonical() =>
      lifetime.run('acp-install:canonical-read', () async {
        final snapshot = await port.readInstallState();
        validateAcpInstallSnapshot(snapshot);
        return snapshot;
      });

  @override
  Future<void> observe(CommitReceipt receipt) async {
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
    }
    await source.waitFor((value) {
      final sync = value.projection.sync;
      if (sync.phase == ResourceSyncPhase.failed) throw sync.error!;
      if (sync.phase == ResourceSyncPhase.closed) throw resourceCancelled;
      final stamp = value.projection.stamp;
      final header = value.projection.header;
      if (stamp == null || header == null) return false;
      final target = receipt.targets.single as ResourceStamp;
      if (stamp.ownerEpoch != target.ownerEpoch) {
        throw const StudioFailure(
          code: StudioFailureCode.superseded,
          message: 'The original ACP preparation command source was replaced.',
          retryable: false,
          correlationId: 'acp-install',
        );
      }
      return header.revision >= target.revision;
    });
  }

  void _sync(
    ResourceSyncPhase phase, {
    StudioFailure? error,
    bool exhausted = false,
  }) {
    final current = source.value;
    source.publish(
      AcpInstallObservation(
        projection: current.projection.copyWith(
          sync: ResourceSyncState(
            phase: phase,
            error: error,
            retryExhausted: exhausted,
          ),
        ),
        snapshot: current.snapshot,
      ),
    );
  }

  void _start() {
    lifetime.admit();
    _feedStamp = null;
    late final ProductFeedOwner<AcpInstallFrame> feed;
    feed = ProductFeedOwner<AcpInstallFrame>(
      lifetime: lifetime,
      owner: 'acp-install:feed',
      open: port.openAcpInstall,
      sequence: (frame) =>
          frame is AcpInstallData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (lifetime.sealed || !identical(_feed, feed)) {
          return frame is AcpInstallData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case AcpInstallData(:final deliverySequence, :final event):
            switch (event) {
              case AcpInstallBaseline(
                :final identity,
                :final stamp,
                :final snapshot,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.acpInstall ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol(
                    'The acpInstall baseline has another feed identity.',
                  );
                }
                feed.bindIdentity(identity);
                _adopt(stamp, snapshot);
                _feedStamp = stamp;
              case AcpInstallChanged(
                :final stamp,
                :final baseRevision,
                :final snapshot,
              ):
                final prior = _feedStamp;
                if (prior == null ||
                    stamp.origin != prior.origin ||
                    baseRevision != prior.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol(
                    'The acpInstall product projection has a revision gap.',
                  );
                }
                _adopt(stamp, snapshot);
                _feedStamp = stamp;
            }
            return deliverySequence;
          case AcpInstallResyncRequired(:final identity):
            _control(feed, identity);
            _recover(feed);
          case AcpInstallFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case AcpInstallClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _recover(feed);
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.runtimeStopped,
                  message: 'The acpInstall source has closed.',
                  retryable: false,
                  correlationId: 'acp-install',
                ),
              );
            }
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _sync(ResourceSyncPhase.connecting);
  }

  void _control(
    ProductFeedOwner<AcpInstallFrame> feed,
    ProductFeedIdentity identity,
  ) {
    final stamp = _feedStamp;
    if (identity.resource != ProductResource.acpInstall ||
        stamp != null &&
            (identity.ownerEpoch != stamp.ownerEpoch ||
                identity.incarnation != stamp.incarnation)) {
      throw resourceProtocol(
        'An acpInstall control frame belongs to another source.',
      );
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<AcpInstallFrame> feed, StudioFailure error) {
    if (lifetime.sealed || !identical(_feed, feed)) return;
    if (error.retryable && _recoveries < 2) {
      _recover(feed, failure: error);
      return;
    }
    _sync(ResourceSyncPhase.failed, error: error, exhausted: _recoveries >= 2);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _recover(
    ProductFeedOwner<AcpInstallFrame> feed, {
    StudioFailure? failure,
  }) {
    if (lifetime.sealed || !identical(_feed, feed) || _restarting != null) {
      return;
    }
    if (_recoveries >= 2) {
      _failed(
        feed,
        failure ??
            const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The acpInstall feed recovery budget is exhausted.',
              retryable: false,
              correlationId: 'acp-install',
            ),
      );
      return;
    }
    ++_recoveries;
    unawaited(
      _restart(feed).then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  Future<void> _restart(
    ProductFeedOwner<AcpInstallFrame> feed, {
    bool retry = false,
  }) {
    lifetime.admit();
    final pending = _restarting;
    if (pending != null) return pending;
    final done = Completer<void>();
    _restarting = done.future;
    _sync(ResourceSyncPhase.reconnecting);
    feed.requestClose();
    unawaited(
      Future<void>.sync(
        () => lifetime.run('acp-install:resync', () async {
          await feed.cleanup(retry: retry);
          lifetime.admit();
          if (!feed.released) {
            throw const StudioFailure(
              code: StudioFailureCode.busy,
              message:
                  'The original acpInstall feed retains unresolved cleanup.',
              retryable: true,
              correlationId: 'acp-install',
            );
          }
        }),
      ).then<void>(
        (_) {
          _restarting = null;
          if (!lifetime.sealed && identical(_feed, feed)) {
            try {
              _start();
            } catch (error, stack) {
              lifetime.lastCause = error;
              lifetime.lastStack = stack;
              _sync(ResourceSyncPhase.failed, error: resourceFailure(error));
              done.completeError(resourceFailure(error), stack);
              return;
            }
          }
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          _restarting = null;
          if (!lifetime.sealed) {
            _sync(
              ResourceSyncPhase.failed,
              error: resourceFailure(error),
              exhausted: _recoveries >= 2,
            );
          }
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  void _adopt(ProductProjectionStamp stamp, AcpInstallSnapshot snapshot) {
    validateAcpInstallSnapshot(snapshot);
    if (stamp.revision < 0 ||
        stamp.incarnation < 0 ||
        stamp.revision != snapshot.revision) {
      throw resourceProtocol(
        'The acpInstall projection stamp disagrees with its snapshot revision.',
      );
    }
    final current = source.value;
    final previous = current.projection;
    if (previous.stamp?.ownerEpoch == stamp.ownerEpoch) {
      if (previous.stamp!.origin == stamp.origin &&
          previous.stamp!.revision > stamp.revision) {
        throw resourceProtocol(
          'The acpInstall source moved backwards within one owner.',
        );
      }
      final known = current.snapshot;
      if (known != null &&
          known.reference.ownerEpoch == stamp.ownerEpoch &&
          known.value.revision == snapshot.revision &&
          known.value != snapshot) {
        throw resourceProtocol(
          'An acpInstall domain revision changed its immutable value.',
        );
      }
    }
    final reference = ResourceStamp(
      resourceKey: _installKey,
      ownerEpoch: stamp.ownerEpoch,
      revision: snapshot.revision,
    );
    source.publish(
      AcpInstallObservation(
        projection: ProductProjection<AcpInstallHeader>(
          stamp: stamp,
          header: AcpInstallHeader(
            revision: snapshot.revision,
            updatedAt: snapshot.updatedAt,
          ),
          sync: const ResourceSyncState(
            phase: ResourceSyncPhase.ready,
            error: null,
            retryExhausted: false,
          ),
        ),
        snapshot: Materialized<AcpInstallSnapshot, ResourceStamp>(
          origin: stamp.origin,
          reference: reference,
          value: snapshot,
        ),
      ),
    );
    operations.observe(reference);
  }
}

void _ignoreInstallState(AcpInstallObservation _) {}

final class _AcpInstallActions {
  _AcpInstallActions(this.port, this.mirror, this.lifetime, this.operations);

  final AcpPort port;
  final _AcpInstallMirror mirror;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;

  /// 每个 provider 至多一个已受理的准备意图。
  final Map<AcpProvider, OperationId> _active = {};

  /// 在途取消以 provider + 目标 operation 为键：同一目标重复取消是 busy，
  /// 不同目标允许并行（旧回执不阻塞新的 canonical 操作）。
  final Map<(AcpProvider, String), OperationId> _cancelling = {};

  OperationTicket<AcpInstallSnapshot> prepare(AcpProvider provider) =>
      _runAction<AcpInstallSnapshot>(
        lifetime: lifetime,
        operations: operations,
        canonical: mirror,
        resourceKey: _installKey,
        target: 'acp-install:${provider.name}',
        validate: validateAcpInstallSnapshot,
        action: (owner) async {
          if (_active.containsKey(provider)) {
            throw StudioFailure(
              code: StudioFailureCode.busy,
              message:
                  'An ACP server preparation is already active for '
                  '${provider.name}.',
              retryable: false,
              correlationId: _installKey,
            );
          }
          final admission = owner.id;
          _active[provider] = admission;
          owner.onSettled(() {
            if (identical(_active[provider], admission)) {
              _active.remove(provider);
            }
          });
          final reply = await owner.invoke(
            () => port.startInstall(
              AcpInstallStartRequest(operationId: owner.id, provider: provider),
            ),
          );
          owner.confirmReceipt(
            reply.receipt,
            revision: reply.snapshot.revision,
          );
          _installAcceptance(
            reply.snapshot,
            provider: provider,
            operationId: owner.id.value,
          );
          await owner.commit(reply.snapshot);
        },
      );

  OperationTicket<AcpInstallSnapshot> cancel(
    AcpProvider provider, {
    required String targetOperationId,
  }) => _runAction<AcpInstallSnapshot>(
    lifetime: lifetime,
    operations: operations,
    canonical: mirror,
    resourceKey: _installKey,
    target: 'acp-install:cancel:${provider.name}:$targetOperationId',
    validate: validateAcpInstallSnapshot,
    action: (owner) async {
      _requireIdentifier(targetOperationId, 'ACP target operation');
      final key = (provider, targetOperationId);
      if (_cancelling.containsKey(key)) {
        throw StudioFailure(
          code: StudioFailureCode.busy,
          message:
              'An ACP preparation cancel for $targetOperationId is '
              'already in flight.',
          retryable: false,
          correlationId: _installKey,
        );
      }
      final admission = owner.id;
      _cancelling[key] = admission;
      owner.onSettled(() {
        if (identical(_cancelling[key], admission)) _cancelling.remove(key);
      });
      final reply = await owner.invoke(
        () => port.cancelInstall(
          AcpInstallCancelRequest(
            operationId: owner.id,
            provider: provider,
            targetOperationId: OperationId(targetOperationId),
          ),
        ),
      );
      owner.confirmReceipt(reply.receipt, revision: reply.snapshot.revision);
      _installAcceptance(
        reply.snapshot,
        provider: provider,
        operationId: targetOperationId,
      );
      await owner.commit(reply.snapshot);
    },
  );
}

/// The acceptance snapshot must name the preparation operation it accepted.
void _installAcceptance(
  AcpInstallSnapshot snapshot, {
  required AcpProvider provider,
  required String operationId,
}) {
  if (snapshot.stateOf(provider).operationId != operationId) {
    throw resourceProtocol(
      'The ACP preparation acceptance does not carry this operation.',
    );
  }
}

// ---------------------------------------------------------------------------
// Snapshot validation
// ---------------------------------------------------------------------------

/// The canonical snapshot must be internally consistent before it is published.
void validateAcpAuthSnapshot(AcpAuthSnapshot value) {
  if (value.revision < 0 || value.updatedAt < 0) {
    throw resourceProtocol('The acpAuth snapshot has a negative revision.');
  }
  final accounts = <String>{};
  for (final account in value.accounts) {
    if (account.accountId.isEmpty ||
        account.connectionRevision < 0 ||
        !accounts.add(account.accountId)) {
      throw resourceProtocol(
        'An acpAuth snapshot row has an invalid or duplicate identity.',
      );
    }
    _validateAuthState(account.state);
  }
}

void _validateAuthState(AcpAuthState state) {
  switch (state) {
    case AcpAuthChecking(:final operationId) ||
        AcpAuthVerifying(:final operationId) ||
        AcpAuthCancelling(:final operationId):
      _requireIdentifier(operationId, 'ACP auth operation id');
    case AcpAuthAuthenticating(:final operationId, :final methodId):
      _requireIdentifier(operationId, 'ACP auth operation id');
      _requireIdentifier(methodId, 'ACP authentication method');
    case AcpAuthClosing(:final operationId, :final failure):
      _requireIdentifier(operationId, 'ACP auth operation id');
      if (failure != null) _validateAuthFailure(failure);
    case AcpAuthVerified(:final checkedAt):
      _requireRevision(checkedAt, 'ACP verification time');
    case AcpAuthFailed(:final failure):
      _validateAuthFailure(failure);
    case AcpAuthRequired(:final methods):
      final ids = <String>{};
      for (final method in methods) {
        // The id is the identity we would send back; the display name is
        // cosmetic and stays whatever the server advertised.
        if (method.id.isEmpty || !ids.add(method.id)) {
          throw resourceProtocol(
            'The acpAuth server advertised an invalid or duplicate method.',
          );
        }
      }
    case AcpAuthUnchecked() || AcpAuthCancelled():
      break;
  }
}

void _validateAuthFailure(AcpAuthFailure failure) {
  if (failure.message.isEmpty) {
    throw resourceProtocol('An acpAuth failure has no safe message.');
  }
}

/// The install snapshot must be internally consistent before it is published.
void validateAcpInstallSnapshot(AcpInstallSnapshot value) {
  if (value.revision < 0 || value.updatedAt < 0) {
    throw resourceProtocol('The acpInstall snapshot has a negative revision.');
  }
  final providers = <AcpProvider>{};
  for (final entry in value.installations) {
    if (!providers.add(entry.provider)) {
      throw resourceProtocol(
        'An acpInstall snapshot row has a duplicate provider.',
      );
    }
    _validateInstallState(entry.state);
  }
}

void _validateInstallState(AcpInstallState state) {
  final operationId = state.operationId;
  if (operationId != null) {
    _requireIdentifier(operationId, 'ACP install operation id');
  }
  switch (state) {
    case AcpInstallIdleState():
      return;
    case AcpInstallReady(:final server):
      _requireIdentifier(server.installationId, 'ACP installation id');
      if (server.program.isEmpty || server.readyAt < 0) {
        throw resourceProtocol('An acpInstall ready row has no usable server.');
      }
      _validateRelease(server.release);
    case AcpInstallFailed(:final failure):
      _validateInstallFailure(failure);
    case AcpInstallClosing(:final failure):
      if (failure != null) _validateInstallFailure(failure);
    case AcpInstallDownloading(
      :final release,
      :final progress,
      :final retryCount,
    ):
      _validateRelease(release);
      _validateProgress(progress);
      _requireRevision(retryCount, 'ACP preparation retry count');
    case AcpInstallVerifying(:final release, :final progress):
      _validateRelease(release);
      _validateProgress(progress);
    case AcpInstallExtracting(:final release, :final progress):
      _validateRelease(release);
      _validateProgress(progress);
    case AcpInstallWaiting(:final release) ||
        AcpInstallPublishing(:final release):
      _validateRelease(release);
    case AcpInstallResolving() ||
        AcpInstallCancelling() ||
        AcpInstallCancelled():
      break;
  }
}

void _validateRelease(AcpInstallRelease release) {
  if (release.version.isEmpty ||
      release.target.isEmpty ||
      release.archiveUrl.isEmpty) {
    throw resourceProtocol('An acpInstall row has an incomplete release.');
  }
}

void _validateProgress(AcpInstallProgress progress) {
  final total = progress.totalBytes;
  final speed = progress.bytesPerSecond;
  if (progress.completedBytes < 0 ||
      (total != null && total < 0) ||
      (speed != null && speed < 0)) {
    throw resourceProtocol('An acpInstall progress row is negative.');
  }
}

void _validateInstallFailure(AcpInstallFailure failure) {
  if (failure.message.isEmpty) {
    throw resourceProtocol('An acpInstall failure has no safe message.');
  }
}

/// The template catalog carries only product defaults; duplicates are a
/// protocol error rather than a silent "last one wins".
void validateAcpAccountCatalog(AcpAccountCatalog catalog) {
  final providers = <AcpProvider>{};
  for (final template in catalog.templates) {
    if (template.displayName.isEmpty ||
        template.supportedVersion.isEmpty ||
        !providers.add(template.provider)) {
      throw resourceProtocol(
        'The ACP account catalog has an invalid or duplicate template.',
      );
    }
    if (template.automaticInstall case AcpInstallAvailable(:final target)) {
      _requireIdentifier(target, 'ACP install target');
    }
  }
}

void _requireIdentifier(String value, String label) {
  if (value.trim().isEmpty) {
    throw resourceProtocol('$label must not be empty.');
  }
}

void _requireRevision(int value, String label) {
  if (value < 0) {
    throw resourceProtocol('$label must not be negative.');
  }
}

// ---------------------------------------------------------------------------
// Shared observation lease and command action
// ---------------------------------------------------------------------------

/// A canonical mirror capability the shared command action may use.
abstract interface class _AcpCanonicalSource {
  /// Current transport origin; null before the first baseline.
  ProductReadOrigin? get origin;

  /// Waits until the canonical mirror covers the accepted receipt watermark.
  Future<void> observe(CommitReceipt receipt);
}

final class _AcpObservationLease<T> implements AcpObservationLease<T> {
  const _AcpObservationLease({
    required this.latest,
    required Observation observation,
  }) : _observation = observation;

  @override
  final ReadonlyLatestValue<T> latest;
  final Observation _observation;

  @override
  bool get isCancelled => _observation.isCancelled;
  @override
  bool get isPaused => _observation.isPaused;
  @override
  void pause() => _observation.pause();
  @override
  void resume() => _observation.resume();
  @override
  void cancel() => _observation.cancel();
  @override
  void release() => _observation.cancel();
}

OperationTicket<T> _runAction<T>({
  required ResourceLifetime lifetime,
  required OperationRecorder operations,
  required _AcpCanonicalSource canonical,
  required String resourceKey,
  required String target,
  required void Function(T value) validate,
  required Future<void> Function(_AcpAction<T> action) action,
}) {
  lifetime.admit();
  // ACP receipts use their native whole-domain ResourceStamp; no fabricated
  // additional identity-observation obligation is added here.
  final writer = operations.begin<T>(target: target);
  final owner = _AcpAction<T>(
    lifetime: lifetime,
    writer: writer,
    canonical: canonical,
    resourceKey: resourceKey,
    validate: validate,
    action: action,
  );
  try {
    lifetime.register(owner);
    owner.start();
  } catch (error, stack) {
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
    // No native invocation can exist before start has entered its work.
    owner.notStarted(error, stack);
  }
  return writer.ticket;
}

/// One accepted ACP command: it owns the single invocation and the watermark
/// observation. It cannot be restarted, and cleanup only joins this work.
final class _AcpAction<T> implements ResourceOwner {
  _AcpAction({
    required this.lifetime,
    required this.writer,
    required this.canonical,
    required this.resourceKey,
    required void Function(T value) validate,
    required Future<void> Function(_AcpAction<T> action) action,
  }) : attempt = lifetime.nextAttempt(),
       _validate = validate,
       _action = action;

  final ResourceLifetime lifetime;
  final OperationWriter<T> writer;
  final _AcpCanonicalSource canonical;
  final String resourceKey;
  final void Function(T value) _validate;
  Future<void> Function(_AcpAction<T>)? _action;

  @override
  final int attempt;

  OperationId get id => writer.ticket.id;

  @override
  String get owner => 'acp:action:${id.value}';

  final Completer<void> _settled = Completer<void>();
  final List<(Object, StackTrace)> _causes = [];
  final List<void Function()> _settleCallbacks = [];
  bool _dispatched = false;
  bool _confirmed = false;
  bool _unknown = false;
  bool _observed = false;
  bool _released = false;
  bool _closing = false;
  CommitReceipt? _receipt;
  StudioFailure? _failure;
  T? _value;

  /// Registers an admission release that runs when this action settles.
  void onSettled(void Function() callback) {
    if (_settled.isCompleted) {
      callback();
      return;
    }
    _settleCallbacks.add(callback);
  }

  void start() {
    unawaited(
      lifetime.accepted<void>(this, () async {
        try {
          await _action!(this);
        } catch (error, stack) {
          _fail(error, stack);
        } finally {
          // No request, secret or intent value outlives a settled action.
          _action = null;
          for (final callback in List.of(_settleCallbacks)) {
            callback();
          }
          _settleCallbacks.clear();
          _released = !_unknown && (!_confirmed || _observed);
          if (!_settled.isCompleted) _settled.complete();
        }
      }),
    );
  }

  void notStarted(Object error, StackTrace stack) {
    _remember(error, stack);
    _action = null;
    writer.rejected(_failure!);
    _released = true;
    for (final callback in List.of(_settleCallbacks)) {
      callback();
    }
    _settleCallbacks.clear();
    if (!_settled.isCompleted) _settled.complete();
  }

  Future<R> invoke<R>(Future<R> Function() send) {
    lifetime.admit();
    if (_closing) throw resourceCancelled;
    _dispatched = true;
    return Future<R>.sync(send);
  }

  void confirmReceipt(CommitReceipt receipt, {int? revision}) {
    if (receipt.operationId != id ||
        receipt.targets.length != 1 ||
        receipt.targets.single is! ResourceStamp ||
        receipt.requiresIdentityObservation) {
      throw resourceProtocol(
        'The ACP reply has another operation or observation contract.',
      );
    }
    final target = receipt.targets.single as ResourceStamp;
    // Before the first baseline the owner epoch is unknown; the watermark still
    // has to be the revision the acceptance snapshot reported.
    final origin = canonical.origin;
    if (target.resourceKey != resourceKey ||
        target.revision < 0 ||
        revision != null && target.revision != revision ||
        origin != null && target.ownerEpoch != origin.ownerEpoch) {
      throw resourceProtocol(
        'The ACP receipt belongs to another frozen resource owner.',
      );
    }
    _receipt = receipt;
    _confirmed = true;
  }

  /// Settles the accepted value, then waits for the watermark it covers.
  Future<void> commit(T value) async {
    // The acceptance snapshot is native evidence: validate it before it may
    // become canonical. A malformed snapshot keeps the committed receipt as
    // unresolved evidence instead of publishing it as accepted.
    _validate(value);
    _value = value;
    writer.accepted(value, _receipt!);
    await canonical.observe(_receipt!);
    // Connection, credential or install availability never proves the effect;
    // only the native receipt's own evidence does.
    writer.identityObserved();
    _observed = true;
  }

  void _remember(Object error, StackTrace stack) {
    _causes.add((error, stack));
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
    _failure ??= error is CommandDispatchFailure
        ? error.failure
        : resourceFailure(error);
  }

  void _fail(Object error, StackTrace stack) {
    _remember(error, stack);
    if (!_confirmed) {
      switch (error) {
        case CommittedButUnobservedCommandDispatchFailure(:final receipt):
          // This path also validates the source/OperationId. A malformed
          // committed reply remains confirmed, but cannot acquire that receipt.
          try {
            confirmReceipt(receipt);
          } catch (mismatch, mismatchStack) {
            _remember(mismatch, mismatchStack);
            _confirmed = true;
          }
        case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
          _confirmed = true;
        case RejectedCommandDispatchFailure():
          break;
        case UnknownOutcomeCommandDispatchFailure():
          _unknown = _dispatched;
        default:
          _unknown = _dispatched;
      }
    }
    final failure = _failure!;
    if (writer.ticket.state.value.observed) {
      writer.evidenceFailed(failure);
      _observed = true;
    } else if (_confirmed) {
      final receipt = _receipt;
      if (receipt == null) {
        writer.acknowledgedSynchronizationFailed(failure, value: _value);
      } else {
        writer.synchronizationFailed(failure, value: _value, receipt: receipt);
      }
      writer.evidenceFailed(failure);
    } else if (_unknown) {
      writer.unknownOutcome(failure);
    } else {
      writer.rejected(failure);
    }
  }

  @override
  bool get released =>
      _released ||
      _settled.isCompleted &&
          !_unknown &&
          _confirmed &&
          writer.ticket.state.value.observed;

  @override
  void requestClose() {
    // Closing observations is not cancellation of an accepted native command.
    // The shared source seal ends the wait, while this invocation is joined.
    _closing = true;
  }

  @override
  Future<void> cleanup({required bool retry}) async {
    await _settled.future;
  }

  @override
  List<FeedCloseIssue> get issues {
    if (!_settled.isCompleted) {
      return [resourcePendingIssue('acpActionPending')];
    }
    if (released) return const [];
    return [
      resourceCleanupIssue(
        _failure ??
            const StudioFailure(
              code: StudioFailureCode.unavailable,
              message:
                  'The original ACP command has unresolved outcome or '
                  'observation evidence.',
              retryable: false,
              correlationId: 'acp',
            ),
        CleanupRecovery.terminal,
      ),
    ];
  }
}
