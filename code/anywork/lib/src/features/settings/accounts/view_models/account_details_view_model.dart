import 'dart:async';

import 'package:anywork_client/accounts.dart' hide AccountAuthenticationMethod;
import 'package:anywork_client/accounts.dart'
    as account_domain
    show AccountAuthenticationMethod;
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/studio_client.dart' show OperationPhase;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_projection.dart';
import 'account_operation_result.dart';
import 'accounts_view_model.dart';

part 'account_details_view_model.g.dart';

@riverpod
class AccountDetailsViewModel extends _$AccountDetailsViewModel {
  late AccountsRepository _accounts;
  late AccountUsageRepository _usage;
  late ValueObservation<AccountResource<AccountDetails>> _details;
  late AccountDisplayKey _key;
  AccountStrings _strings = const AccountStrings.empty();
  String? _error;
  bool _billingSaving = false;
  AccountDemand? _detailDemand;
  AccountDemand? _usageDemand;
  ({String ownerEpoch, int revision})? _usageSource;
  ({String ownerEpoch, int revision})? _automaticUsage;
  Object _usageGeneration = Object();
  String? _usageError;
  Object _owner = Object();
  Object? _billingAttempt;
  String? _ownerEpoch;
  bool _wasStale = false;
  final List<Observation> _operations = [];

  @override
  FutureOr<AccountDetailsViewState> build(AccountDisplayKey key) {
    final lifetime = ref;
    _key = key;
    _accounts = ref.read(accountsRepositoryProvider);
    _usage = ref.read(accountUsageRepositoryProvider);
    _detailDemand = _accounts.observeDetails(domainIdentity(key));
    _details = _accounts.details(domainIdentity(key));
    _ownerEpoch = _details.value.stamp?.ownerEpoch;
    _wasStale = _details.value.stale || _accounts.state.value.stale;
    _usageSource = _currentUsageSource();
    _automaticUsage = null;
    _usageGeneration = Object();
    _usageError = null;
    _usageDemand = key.kind == AccountKind.native
        ? _usage.observeAccount(NativeAccountIdentity(key.id))
        : null;
    // Header commands remain owned by AccountsViewModel. Listen to its full
    // immutable action projection, not a row which search may have filtered out.
    ref.listen(accountsViewModelProvider, (_, _) => _publish());
    final observations = [
      _details.watch((_) => _sourceChanged()),
      _accounts.state.watch((_) => _sourceChanged()),
      _usage.state.watch((_) => _publish()),
      _usage.queryFailures.watch((_) => _publish()),
    ];
    ref.onDispose(() {
      _usageGeneration = Object();
      releaseAccountDemand(_detailDemand);
      releaseAccountDemand(_usageDemand);
      for (final observation in [...observations, ..._operations]) {
        observation.cancel();
      }
    });
    scheduleMicrotask(() {
      if (lifetime.mounted && identical(lifetime, ref)) {
        _startAutomaticUsage();
      }
    });
    return _derive();
  }

  /// Driver reads only a VM which already exists. No new detail slot is opened.
  AccountResource<AccountDetails> readObservedDetails() => _details.value;
  void setStrings(AccountStrings strings) {
    _strings = strings;
    _publish();
  }

  void retryObservation() {
    releaseAccountDemand(_detailDemand);
    _detailDemand = _accounts.observeDetails(domainIdentity(_key));
  }

  AccountDetailsPresentation presentation({
    AccountCatalogPresentation? catalog,
    AcpAccountPresentation? acp,
  }) {
    final details = _derive().details;
    return details.copyWith(
      content: switch (details.content) {
        NativeAccountDetailsContent(:final value) =>
          AccountDetailsContent.native(
            value.copyWith(catalog: catalog ?? value.catalog),
          ),
        AcpAccountDetailsContent(:final value) => AccountDetailsContent.acp(
          acp ?? value,
        ),
      },
    );
  }

  Future<void> refreshUsage() async {
    final source = _currentUsageSource();
    if (!ref.mounted || source == null) return;
    final lifetime = ref;
    final owner = _owner;
    final generation = _usageGeneration;
    _usageError = null;
    _publish();
    try {
      await _usage.refresh(NativeAccountIdentity(_key.id));
    } catch (error) {
      if (lifetime.mounted &&
          identical(lifetime, ref) &&
          identical(owner, _owner) &&
          identical(generation, _usageGeneration) &&
          source == _currentUsageSource()) {
        _usageError = safeAccountError(error, _strings);
        _publish();
      }
    }
  }

  ({String ownerEpoch, int revision})? _currentUsageSource() {
    if (_key.kind != AccountKind.native) return null;
    final source = _accounts.state.value;
    final revision = source.account(domainIdentity(_key))?.usageQueryRevision;
    if (!source.loaded || source.stale || revision == null) return null;
    return (ownerEpoch: source.stamp!.ownerEpoch, revision: revision);
  }

  void _startAutomaticUsage() {
    if (!ref.mounted) return;
    final source = _currentUsageSource();
    if (source == null || source == _automaticUsage) return;
    // One initial intent per current query identity. A summary arriving after
    // the detail owner, or a changed query revision, can make it queryable.
    // Rebuilds, manual refreshes and list visibility do not reset this identity.
    _automaticUsage = source;
    unawaited(refreshUsage());
  }

  Future<void> setBilling(AccountBilling? billing) async {
    if (_billingSaving ||
        !_details.value.loaded ||
        _key.kind != AccountKind.native) {
      return;
    }
    _billingSaving = true;
    final owner = _owner;
    final attempt = Object();
    _billingAttempt = attempt;
    _error = null;
    _publish();
    try {
      if (!_ownsBilling(owner, attempt)) return;
      final result = await _accounts.setBillingKind(
        NativeAccountIdentity(_key.id),
        billing == null ? null : domainBilling(billing),
      );
      if (!_ownsBilling(owner, attempt)) return;
      void apply(operation) {
        if (!_ownsBilling(owner, attempt)) return;
        _error = operationMessage(operation, _strings);
        _billingSaving =
            operation.failurePhase != OperationPhase.rejected &&
            !operationSaved(operation);
        _publish();
      }

      trackAccountOperation(ref, result, _operations, apply);
    } catch (error) {
      if (_ownsBilling(owner, attempt)) {
        _billingSaving = false;
        _error = safeAccountError(error, _strings);
        _publish();
      }
    }
  }

  AccountDetailsViewState _derive() {
    final resource = _details.value;
    final detail = resource.value;
    final source = _accounts.state.value;
    final summary = source.account(domainIdentity(_key));
    final native = detail is NativeAccountDetails ? detail : null;
    final acp = detail is AcpAccountDetails ? detail : null;
    final stale = resource.stale || source.stale;
    final candidate = ref
        .read(accountsViewModelProvider)
        .asData
        ?.value
        .actions[_key];
    // The action owner qualifies its concrete local lifecycle/attempt before
    // publication. Details still require the currently observed typed target.
    // A deletion belongs to that account owner, not its original ACP connection;
    // other action feedback keeps the original connection qualification.
    final action =
        resource.loaded &&
            source.loaded &&
            detail?.identity == domainIdentity(_key) &&
            candidate != null &&
            candidate.ownerEpoch == resource.stamp?.ownerEpoch &&
            candidate.ownerEpoch == source.stamp?.ownerEpoch &&
            (_key.kind == AccountKind.native ||
                (acp != null &&
                    acp.account.connectionRevision ==
                        summary?.acpConnectionRevision &&
                    (candidate.removing ||
                        candidate.acpConnectionRevision ==
                            acp.account.connectionRevision)))
        ? candidate
        : null;
    final pending = action?.pending == true;
    return AccountDetailsViewState(
      observed: resource.stamp != null,
      stale: stale,
      acpKey: acp == null
          ? null
          : AccountAcpKey(
              target: _key,
              templateId: acp.account.template?.wire,
              connectionRevision: acp.account.connectionRevision,
            ),
      details: AccountDetailsPresentation(
        key: _key,
        name: summary?.name ?? native?.name ?? acp?.account.name ?? _key.id,
        iconKey: summary?.brandKey,
        endpoint: native?.baseUrl,
        canEdit:
            resource.loaded &&
            !stale &&
            !pending &&
            summary?.capabilities.edit == true,
        canDelete:
            resource.loaded &&
            !stale &&
            !pending &&
            summary?.capabilities.remove == true,
        canSetDefault:
            resource.loaded &&
            !stale &&
            !pending &&
            summary?.capabilities.setDefault == true &&
            summary?.isDefault != true,
        loading:
            pending || (resource.stamp == null && resource.failure == null),
        error: stale
            ? _strings['stale']
            : action?.message ??
                  _error ??
                  _usageError ??
                  resource.failure?.message ??
                  (resource.loaded && detail == null
                      ? _strings['notFound']
                      : null),
        content: _key.kind == AccountKind.native
            ? AccountDetailsContent.native(
                NativeAccountDetailsPresentation(
                  identityLabel:
                      native?.chatgptAccount?.email ??
                      native?.chatgptAccount?.codex?.accountId,
                  authentication:
                      native?.authentication ==
                          account_domain.AccountAuthenticationMethod.chatGpt
                      ? AccountAuthenticationMethod.chatGpt
                      : AccountAuthenticationMethod.apiKey,
                  credentialReady:
                      native?.authentication ==
                          account_domain.AccountAuthenticationMethod.chatGpt
                      ? summary?.credentialReady == true
                      : native?.hasBearerToken == true,
                  billing: AccountBillingPresentation(
                    effective: displayBilling(summary?.billingKind),
                    billingKindOverride: summary?.billingKindOverride == null
                        ? null
                        : displayBilling(summary?.billingKindOverride),
                    allowedOverrides: resource.loaded && !stale
                        ? AccountBilling.values
                        : const [],
                    saving: _billingSaving,
                    error: _error,
                  ),
                  catalog: const AccountCatalogPresentation(),
                  usage: summary == null
                      ? const AccountUsagePresentation()
                      : projectUsage(
                          summary,
                          _usage.state.value,
                          _usage.queryFailures.value,
                          _strings,
                        ),
                  advanced: [
                    AccountDisplayFact(
                      label: _strings['accountId'],
                      value: _key.id,
                    ),
                    if (native != null)
                      AccountDisplayFact(
                        label: _strings['protocol'],
                        value: native.protocol,
                      ),
                  ],
                ),
              )
            : AccountDetailsContent.acp(
                AcpAccountPresentation(
                  phase: AcpPresentationPhase.idle,
                  status: _strings['acp.idle'],
                ),
              ),
      ),
    );
  }

  bool _ownsBilling(Object owner, Object attempt) =>
      ref.mounted &&
      identical(owner, _owner) &&
      identical(attempt, _billingAttempt);
  void _sourceChanged() {
    final resource = _details.value;
    final stale = resource.stale || _accounts.state.value.stale;
    final epoch = resource.stamp?.ownerEpoch;
    if ((stale && !_wasStale) ||
        (epoch != null && epoch != _ownerEpoch) ||
        (resource.loaded && resource.value == null)) {
      _owner = Object();
      _billingAttempt = null;
      _billingSaving = false;
      _error = null;
      _usageError = null;
      for (final observation in _operations) {
        observation.cancel();
      }
      _operations.clear();
    }
    _ownerEpoch = epoch ?? _ownerEpoch;
    _wasStale = stale;
    final usageSource = _currentUsageSource();
    if (usageSource != _usageSource) {
      _usageGeneration = Object();
      _usageError = null;
      _usageSource = usageSource;
    }
    final accounts = _accounts.state.value;
    if (accounts.loaded && accounts.account(domainIdentity(_key)) == null) {
      _automaticUsage = null;
    }
    _publish();
    _startAutomaticUsage();
  }

  void _publish() {
    if (ref.mounted) state = AsyncData(_derive());
  }
}
