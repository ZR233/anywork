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
  Object _generation = Object();
  Object _readScope = Object();
  String? _epoch;
  int? _revision;
  bool _stale = false;
  bool _initialStarted = false;
  bool _active = true;
  String? _authEpoch;
  bool _authStale = false;
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
    _generation = Object();
    _refreshError = null;
    _action = null;
    _key = key;
    _accounts = ref.read(accountsRepositoryProvider);
    _usage = ref.read(accountUsageRepositoryProvider);
    _acp = ref.read(acpServiceProvider);
    final source = _accounts.state.value;
    _epoch = source.stamp?.ownerEpoch;
    _revision = _queryRevision(source.account(domainIdentity(key)));
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
    }
    ref.onDispose(cancellationForCurrentObservation());
    scheduleMicrotask(() {
      if (lifetime.mounted && identical(lifetime, ref)) _startInitialRefresh();
    });
    return _derive();
  }

  int? _queryRevision(AccountSummary? account) =>
      _key.kind == AccountKind.native
      ? account?.usageQueryRevision
      : account?.acpConnectionRevision;

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
    final observations = _observations.toList();
    _observations.clear();
    for (final observation in observations) {
      observation.cancel();
    }
    // A pending-intent cancellation can reenter and rebuild this notifier.
    // All remaining work therefore uses only this retired scope's captures.
    _revokeRefreshes();
    releaseAccountDemand(demand);
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
    }
    _epoch = epoch ?? _epoch;
    _revision = revision;
    _stale = source.stale;
    _publish();
    _startInitialRefresh();
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
    final revision = account.acpConnectionRevision;
    if (_key.kind == AccountKind.acp && revision != null) {
      final resource = _acp.auth.value;
      final stale =
          resource.stale ||
          resource.stamp?.ownerEpoch != source.stamp?.ownerEpoch;
      if (!stale) {
        acpAuth = resource.value
            ?.account(_key.id, connectionRevision: revision)
            ?.state;
      }
      final projection = projectAcpUsage(
        snapshot: resource.value,
        stale: stale,
        accountId: _key.id,
        connectionRevision: revision,
        strings: _strings,
      );
      if (projection.queried || projection.busy) acpUsage = projection;
    }
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
                  _strings[switch (acpAuth) {
                    AcpCheckingState() => 'acp.checking',
                    AcpRequiredState() => 'acp.needsLogin',
                    AcpAuthenticatingState() => 'acp.authenticating',
                    AcpVerifyingState() => 'acp.verifying',
                    AcpVerifiedState() => 'acp.connected',
                    AcpCancellingState() => 'acp.cancelling',
                    AcpClosingState() => 'acp.closing',
                    AcpCancelledState() => 'acp.cancelled',
                    AcpFailedState() => 'acp.failed',
                    _ => 'acp',
                  }],
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
              if (account.capabilities.queryUsage ||
                  (_key.kind == AccountKind.acp && revision != null))
                AccountRowAction.refresh,
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
