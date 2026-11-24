import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_projection.dart';

part 'account_card_view_model.g.dart';

/// One list member's read-only projection and refresh intent. Search never owns
/// this resource; the visible list retains it independently of row widgets.
@riverpod
class AccountCardViewModel extends _$AccountCardViewModel {
  late AccountDisplayKey _key;
  late AccountsRepository _accounts;
  late AccountUsageRepository _usage;
  late AcpService _acp;
  AccountStrings _strings = const AccountStrings.empty();
  AccountDemand? _demand;
  AccountDemand? _installDemand;
  Observation? _installObservation;
  Object _generation = Object();
  Object _readScope = Object();
  String? _epoch;
  int? _revision;
  bool _stale = false;
  bool _initialStarted = false;
  bool _active = true;
  String? _authEpoch;
  bool _authStale = false;
  String? _verifiedServerVersion;
  bool _checkingUpdate = false;
  String? _upgradeError;
  String? _refreshError;
  AccountActionPresentation? _action;
  final List<Observation> _observations = [];
  final _usageRequests = Set<AcpUsageRefreshRequest>.identity();

  @override
  FutureOr<AccountRowPresentation?> build(AccountDisplayKey key) {
    final lifetime = ref;
    _active = true;
    _readScope = Object();
    _initialStarted = false;
    _verifiedServerVersion = null;
    _checkingUpdate = false;
    _upgradeError = null;
    _generation = Object();
    _refreshError = null;
    _action = null;
    _key = key;
    _accounts = ref.read(accountsRepositoryProvider);
    _usage = ref.read(accountUsageRepositoryProvider);
    _acp = ref.read(acpServiceProvider);
    final source = _accounts.state.value;
    final initialAccount = source.account(domainIdentity(key));
    _epoch = source.stamp?.ownerEpoch;
    _revision = _queryRevision(initialAccount);
    _stale = source.stale;
    _authEpoch = _acp.auth.value.stamp?.ownerEpoch;
    _authStale = _acp.auth.value.stale;
    _demand = key.kind == AccountKind.native
        ? _usage.observeAccount(NativeAccountIdentity(key.id))
        : _acp.observeAuth();
    _observations.add(_accounts.state.watch((_) => _sourceChanged()));
    if (key.kind == AccountKind.native) {
      _observations.addAll([
        _usage.state.watch((_) => _publish()),
        _usage.queryFailures.watch((_) => _publish()),
      ]);
    } else {
      _observations.add(_acp.auth.watch((_) => _authChanged()));
      _syncInstallSubscription(initialAccount);
    }
    ref.onDispose(cancellationForCurrentObservation());
    scheduleMicrotask(() {
      if (lifetime.mounted && identical(lifetime, ref)) _startInitialRefresh();
    });
    return _derive();
  }

  bool _canQueryAcpUsage(AccountSummary? account) =>
      account != null &&
      account.acpEnabled == true &&
      account.capabilities.queryUsage &&
      account.acpConnectionRevision != null;

  int? _queryRevision(AccountSummary? account) =>
      _key.kind == AccountKind.native
      ? account?.usageQueryRevision
      : (_canQueryAcpUsage(account) ? account?.acpConnectionRevision : null);

  void setStrings(AccountStrings strings) {
    _strings = strings;
    _publish();
  }

  /// Revoke unissued work immediately, rather than waiting for auto-disposal.
  /// Already admitted commands stay with their domain owner.
  void stop() {
    if (!_active) return;
    _active = false;
    final demand = _demand;
    _demand = null;
    final installDemand = _installDemand;
    _installDemand = null;
    final installObservation = _installObservation;
    _installObservation = null;
    installObservation?.cancel();
    final observations = _observations.toList();
    _observations.clear();
    for (final observation in observations) {
      observation.cancel();
    }
    // A pending-intent cancellation can reenter and rebuild this notifier.
    // All remaining work therefore uses only this retired scope's captures.
    _revokeRefreshes();
    releaseAccountDemand(demand);
    releaseAccountDemand(installDemand);
  }

  void _syncInstallSubscription(AccountSummary? account) {
    if (_key.kind == AccountKind.acp && account?.acpTemplate != null) {
      _installDemand ??= _acp.observeInstall();
      _installObservation ??= _acp.install.watch((_) {
        if (!ref.mounted || !_active) return;
        _publish();
      });
    } else if (_installDemand != null || _installObservation != null) {
      final demand = _installDemand;
      _installDemand = null;
      _installObservation?.cancel();
      _installObservation = null;
      releaseAccountDemand(demand);
    }
  }

  /// Whether this observation lease is still accepting work. This is not UI state.
  bool isObservationActive() => _active;

  /// Scope of this build. A reused notifier changes it on the next build.
  Object currentObservationScope() => _readScope;

  /// Binds cancellation to this read scope, not the reusable notifier object.
  /// It detaches display observations and unissued intents only.
  void Function() cancellationForCurrentObservation() {
    final scope = _readScope;
    return () {
      if (identical(scope, _readScope)) stop();
    };
  }

  /// Read-only intake for the list owner's action projection. The closure is
  /// bound to this build: a rebuilt scope ignores a delivery captured earlier.
  void Function(AccountActionPresentation? action)
  actionSinkForCurrentObservation() {
    final scope = _readScope;
    final lifetime = ref;
    return (action) {
      if (!lifetime.mounted ||
          !identical(lifetime, ref) ||
          !_active ||
          !identical(scope, _readScope) ||
          _action == action) {
        return;
      }
      _action = action;
      _publish();
    };
  }

  void _revokeRefreshes() {
    _generation = Object();
    final requests = _usageRequests.toList();
    _usageRequests.clear();
    for (final request in requests) {
      request.cancelPending();
    }
  }

  void _authChanged() {
    if (!ref.mounted || !_active) return;
    final resource = _acp.auth.value;
    final epoch = resource.stamp?.ownerEpoch;
    if ((resource.stale && !_authStale) ||
        (epoch != null && epoch != _authEpoch)) {
      _revokeRefreshes();
      _refreshError = null;
    }
    _authEpoch = epoch ?? _authEpoch;
    _authStale = resource.stale;
    final source = _accounts.state.value;
    final summary = source.account(domainIdentity(_key));
    final revision = summary?.acpConnectionRevision;
    if (!resource.stale && revision != null) {
      final row = resource.value?.account(
        _key.id,
        connectionRevision: revision,
      );
      final runningVersion = switch (row?.state) {
        AcpVerifiedState(:final server) ||
        AcpRequiredState(:final server) => server?.version,
        _ => null,
      };
      if (row?.connection is AcpConnectionReadyState &&
          row?.state is AcpVerifiedState &&
          runningVersion != null) {
        if (_verifiedServerVersion != null &&
            _verifiedServerVersion != runningVersion) {
          _initialStarted = false;
        }
        _verifiedServerVersion = runningVersion;
      }
    }
    _publish();
    _startInitialRefresh();
  }

  void _sourceChanged() {
    if (!ref.mounted || !_active) return;
    final source = _accounts.state.value;
    final summary = source.account(domainIdentity(_key));
    final epoch = source.stamp?.ownerEpoch;
    final revision = _queryRevision(summary);
    if ((epoch != null && epoch != _epoch) ||
        revision != _revision ||
        (source.stale && !_stale) ||
        (source.loaded && summary == null)) {
      _revokeRefreshes();
      _refreshError = null;
      _verifiedServerVersion = null;
    }
    _epoch = epoch ?? _epoch;
    _revision = revision;
    _stale = source.stale;
    _syncInstallSubscription(summary);
    _publish();
    _startInitialRefresh();
  }

  Future<void> upgrade() async {
    final account = _accounts.state.value.account(domainIdentity(_key));
    final template = account?.acpTemplate;
    if (!ref.mounted || !_active || template == null) return;
    final lifetime = ref;
    final generation = _generation;
    _upgradeError = null;
    _publish();
    try {
      await _acp.prepare(template);
    } catch (error) {
      if (_ownsRefresh(lifetime, generation)) {
        _upgradeError = safeAccountError(error, _strings);
        _publish();
      }
    }
  }

  Future<void> cancelUpgrade() async {
    final account = _accounts.state.value.account(domainIdentity(_key));
    final template = account?.acpTemplate;
    if (!ref.mounted || !_active || template == null) return;
    final lifetime = ref;
    final generation = _generation;
    try {
      await _acp.cancelPreparation(template);
    } catch (error) {
      if (_ownsRefresh(lifetime, generation)) {
        _upgradeError = safeAccountError(error, _strings);
        _publish();
      }
    }
  }

  Future<void> checkUpdate() async {
    final account = _accounts.state.value.account(domainIdentity(_key));
    final template = account?.acpTemplate;
    if (!ref.mounted || !_active || template == null || _checkingUpdate) return;
    final lifetime = ref;
    final generation = _generation;
    _checkingUpdate = true;
    _upgradeError = null;
    _publish();
    try {
      await _acp.checkUpdate(template);
    } catch (error) {
      if (_ownsRefresh(lifetime, generation)) {
        _upgradeError = safeAccountError(error, _strings);
      }
    } finally {
      if (_ownsRefresh(lifetime, generation)) {
        _checkingUpdate = false;
        _publish();
      }
    }
  }

  void _startInitialRefresh() {
    if (!ref.mounted || !_active || _initialStarted) return;
    final source = _accounts.state.value;
    final account = source.account(domainIdentity(_key));
    if (!source.loaded ||
        source.stale ||
        source.stamp == null ||
        account == null) {
      return;
    }
    if (_queryRevision(account) == null) return;
    if (_key.kind == AccountKind.acp) {
      final auth = _acp.auth.value;
      if (!auth.loaded ||
          auth.stale ||
          auth.stamp?.ownerEpoch != source.stamp?.ownerEpoch) {
        return;
      }
      final row = auth.value?.account(
        _key.id,
        connectionRevision: account.acpConnectionRevision!,
      );
      if (row?.usage != null ||
          row?.activeOperation?.action is AcpQueryUsageActionView) {
        _initialStarted = true;
        return;
      }
    }
    _initialStarted = true;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final source = _accounts.state.value;
    final account = source.account(domainIdentity(_key));
    if (!ref.mounted ||
        !_active ||
        !source.loaded ||
        source.stale ||
        account == null ||
        _queryRevision(account) == null) {
      return;
    }
    final lifetime = ref;
    final generation = _generation;
    AcpUsageRefreshRequest? request;
    _refreshError = null;
    _publish();
    try {
      if (_key.kind == AccountKind.native) {
        // Let the shared owner classify unsupported and missing credentials.
        await _usage.refresh(NativeAccountIdentity(_key.id));
      } else {
        request = _acp.requestUsageRefresh(
          AcpAccountIdentity(_key.id),
          connectionRevision: account.acpConnectionRevision!,
        );
        if (_ownsRefresh(lifetime, generation)) {
          _usageRequests.add(request);
        } else {
          // A reentrant source change may occur while the service registers.
          request.cancelPending();
        }
        // This settles only registration/join/cancellation, not account quota.
        // The authoritative auth observation continues to supply all readouts.
        await request.result;
      }
    } catch (error) {
      if (_ownsRefresh(lifetime, generation)) {
        _refreshError = safeAccountError(error, _strings);
        _publish();
      }
    } finally {
      if (request != null) _usageRequests.remove(request);
    }
  }

  bool _ownsRefresh(Ref lifetime, Object generation) =>
      lifetime.mounted &&
      identical(lifetime, ref) &&
      _active &&
      identical(generation, _generation);

  AccountRowPresentation? _derive() {
    final source = _accounts.state.value;
    final account = source.account(domainIdentity(_key));
    if (account == null) return null;
    final applicableAction = _applicableAction(account, source);
    AcpUsagePresentation? acpUsage;
    AcpAuthStateView? acpAuth;
    AcpConnectionStateView? acpConnection;
    final revision = account.acpConnectionRevision;
    if (_key.kind == AccountKind.acp && revision != null) {
      final resource = _acp.auth.value;
      final stale =
          resource.stale ||
          resource.stamp?.ownerEpoch != source.stamp?.ownerEpoch;
      if (!stale) {
        acpConnection = resource.value
            ?.account(_key.id, connectionRevision: revision)
            ?.connection;
        acpAuth = resource.value
            ?.account(_key.id, connectionRevision: revision)
            ?.state;
      }
      if (account.capabilities.queryUsage) {
        final projection = projectAcpUsage(
          snapshot: resource.value,
          stale: stale,
          accountId: _key.id,
          connectionRevision: revision,
          strings: _strings,
        );
        if (projection.queried || projection.busy) acpUsage = projection;
      }
    }
    final acpPhase = switch ((acpConnection, acpAuth)) {
      (AcpConnectionRetryingState(), _) => AcpPresentationPhase.reconnecting,
      (AcpConnectionStartingState(), _) => AcpPresentationPhase.checking,
      (AcpConnectionStoppingState(), _) => AcpPresentationPhase.closing,
      (AcpConnectionBlockedState(), _) => AcpPresentationPhase.failed,
      (_, AcpCheckingState()) => AcpPresentationPhase.checking,
      (_, AcpRequiredState()) => AcpPresentationPhase.needsLogin,
      (_, AcpAuthenticatingState()) => AcpPresentationPhase.authenticating,
      (_, AcpVerifyingState()) => AcpPresentationPhase.verifying,
      (_, AcpVerifiedState()) => AcpPresentationPhase.connected,
      (_, AcpCancellingState()) => AcpPresentationPhase.cancelling,
      (_, AcpClosingState()) => AcpPresentationPhase.closing,
      (_, AcpCancelledState()) => AcpPresentationPhase.idle,
      (_, AcpFailedState()) => AcpPresentationPhase.failed,
      _ => AcpPresentationPhase.idle,
    };
    final runningVersion = switch (acpAuth) {
      AcpVerifiedState(:final server) ||
      AcpRequiredState(:final server) => server?.version,
      _ => null,
    };
    final isManaged = account.acpTemplate != null;
    final installResource = _acp.install.value;
    final acpUpgrade = _key.kind == AccountKind.acp
        ? projectAcpUpgrade(
            snapshot: installResource.value,
            installStale: installResource.stale,
            template: account.acpTemplate,
            connection: acpConnection,
            runningVersion: runningVersion,
            strings: _strings,
            busyCheck: _checkingUpdate,
            commandError: _upgradeError,
          )
        : null;
    final displayVersion = acpUpgrade?.installedVersion ?? runningVersion;
    final sourceLabel = _key.kind == AccountKind.acp
        ? (isManaged
              ? '${_strings['acp.managed']} · Antigravity'
              : _strings['acp.local'])
        : null;
    final versionLabel = displayVersion != null && displayVersion.isNotEmpty
        ? 'v$displayVersion'
        : null;
    return AccountRowPresentation(
      key: _key,
      name: account.name,
      iconKey: account.brandKey,
      isDefault: account.isDefault,
      content: _key.kind == AccountKind.native
          ? AccountRowContent.native(
              billing: displayBilling(account.billingKind),
              displayEndpoint: account.displayEndpoint,
              accountLabel:
                  account.chatgptAccount?.email ??
                  account.chatgptAccount?.codex?.accountId,
              usage: projectUsage(
                account,
                _usage.state.value,
                _usage.queryFailures.value,
                _strings,
              ),
            )
          : AccountRowContent.acp(
              status:
                  _strings[switch ((acpConnection, acpAuth)) {
                    (AcpConnectionRetryingState(), _) => 'acp.reconnecting',
                    (AcpConnectionStartingState(), _) => 'acp.checking',
                    (AcpConnectionStoppingState(), _) => 'acp.closing',
                    (AcpConnectionBlockedState(), _) => 'acp.failed',
                    (_, AcpCheckingState()) => 'acp.checking',
                    (_, AcpRequiredState()) => 'acp.needsLogin',
                    (_, AcpAuthenticatingState()) => 'acp.authenticating',
                    (_, AcpVerifyingState()) => 'acp.verifying',
                    (_, AcpVerifiedState()) => 'acp.connected',
                    (_, AcpCancellingState()) => 'acp.cancelling',
                    (_, AcpClosingState()) => 'acp.closing',
                    (_, AcpCancelledState()) => 'acp.cancelled',
                    (_, AcpFailedState()) => 'acp.failed',
                    _ => 'acp',
                  }],
              phase: acpPhase,
              isManaged: isManaged,
              sourceLabel: sourceLabel,
              versionLabel: versionLabel,
              upgrade: acpUpgrade,
              usage: acpUsage,
            ),
      operationError:
          applicableAction?.message ??
          _refreshError ??
          (acpAuth is AcpFailedState ? acpAuth.failure.message : null) ??
          (_key.kind == AccountKind.acp &&
                  !_acp.auth.value.stale &&
                  (_acp.auth.value.stamp == null ||
                      _acp.auth.value.stamp?.ownerEpoch ==
                          source.stamp?.ownerEpoch)
              ? _acp.auth.value.failure?.message
              : null),
      actions:
          applicableAction?.pending == true ||
              !source.loaded ||
              (_key.kind == AccountKind.acp && revision == null)
          ? const []
          : [
              if ((_key.kind == AccountKind.native &&
                      account.capabilities.queryUsage) ||
                  _canQueryAcpUsage(account))
                AccountRowAction.refresh,
              if (_key.kind == AccountKind.acp &&
                  acpUpgrade?.canCheck == true &&
                  !_checkingUpdate)
                AccountRowAction.checkUpdate,
              if (account.capabilities.setDefault && !account.isDefault)
                AccountRowAction.setDefault,
              if (account.capabilities.edit) AccountRowAction.edit,
              if (account.capabilities.remove) AccountRowAction.delete,
            ],
    );
  }

  /// Deletion stays with the account owner across connection replacement.
  /// Other feedback still has to match the connection it was admitted on.
  AccountActionPresentation? _applicableAction(
    AccountSummary account,
    AccountsState source,
  ) {
    final action = _action;
    if (action == null || action.ownerEpoch != source.stamp?.ownerEpoch) {
      return null;
    }
    if (action.removing || _key.kind == AccountKind.native) return action;
    return action.acpConnectionRevision == account.acpConnectionRevision
        ? action
        : null;
  }

  void _publish() {
    if (!ref.mounted || !_active) return;
    final next = _derive();
    if (state.asData?.value != next) state = AsyncData(next);
  }
}
