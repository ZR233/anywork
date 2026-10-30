import '../../contracts/stamps.dart';
import '../../models/account_models.dart';
import '../../models/acp_models.dart';
import '../../models/delegation_models.dart';
import '../../models/failure_models.dart';
import '../../models/studio_commands.dart';
import 'account_identity.dart';
import 'account_authentication.dart';

final class AccountCapabilities {
  const AccountCapabilities({
    required this.setDefault,
    required this.edit,
    required this.remove,
    required this.queryUsage,
    required this.syncModels,
    required this.editModels,
    required this.acpAuth,
  });
  final bool setDefault;
  final bool edit;
  final bool remove;
  final bool queryUsage;
  final bool syncModels;
  final bool editModels;
  final bool acpAuth;
}

final class AccountSummary {
  const AccountSummary({
    required this.identity,
    required this.name,
    this.brandKey,
    this.displayEndpoint,
    required this.isDefault,
    this.billingKind,
    this.billingKindOverride,
    this.credentialReady,
    this.usageQueryRevision,
    this.acpConnectionRevision,
    required this.capabilities,
  });
  final AccountIdentity identity;
  final String name;
  final String? brandKey;

  /// Display-only canonical origin; never a source for saved connection settings.
  final String? displayEndpoint;
  final bool isDefault;
  final BillingKind? billingKind;
  final BillingKind? billingKindOverride;
  final bool? credentialReady;
  final int? usageQueryRevision;

  /// Native is null; ACP carries its canonical owner's connection revision.
  final int? acpConnectionRevision;
  final AccountCapabilities capabilities;
}

/// A target-local value. A loaded null means deleted, not an empty account.
final class AccountResource<T> {
  const AccountResource({
    this.stamp,
    this.value,
    this.loading = false,
    this.failure,
    this.stale = false,
  });
  final ResourceStamp? stamp;
  final T? value;
  final bool loading;
  final StudioFailure? failure;
  final bool stale;
  bool get loaded => stamp != null && !stale;
}

sealed class AccountDetails {
  const AccountDetails();
  AccountIdentity get identity;
}

/// Editable configuration only; effective models live in the Models domain.
final class NativeAccountDetails extends AccountDetails {
  NativeAccountDetails({
    required this.identity,
    required this.name,
    this.authentication = AccountAuthenticationMethod.apiKey,
    this.chatgptAccount,
    required this.protocol,
    this.templateId,
    required this.baseUrl,
    required this.hasBearerToken,
    required this.credentialRequired,
    required this.usageQueryRevision,
    required Iterable<AccountModelCommand> customModels,
  }) : customModels = List.unmodifiable(customModels);

  @override
  final NativeAccountIdentity identity;
  final String name;
  final AccountAuthenticationMethod authentication;
  final ChatGptAccountInfo? chatgptAccount;
  final String protocol;
  final String? templateId;
  final String baseUrl;
  final bool hasBearerToken;
  final bool credentialRequired;
  final int usageQueryRevision;
  final List<AccountModelCommand> customModels;
}

final class AcpAccountDetails extends AccountDetails {
  const AcpAccountDetails(this.account);
  final AcpAccountSettingsView account;
  @override
  AcpAccountIdentity get identity => AcpAccountIdentity(account.accountId);
}

final class AccountsState {
  AccountsState({
    this.stamp,
    Iterable<AccountSummary> accounts = const [],
    this.templates = const AccountCatalogView.empty(),
    this.loading = false,
    this.failure,
    this.stale = false,
  }) : accounts = List.unmodifiable(accounts);
  final ResourceStamp? stamp;
  final List<AccountSummary> accounts;
  final AccountCatalogView templates;
  final bool loading;
  final StudioFailure? failure;
  final bool stale;
  bool get loaded => stamp != null && !stale;
  AccountSummary? account(AccountIdentity identity) =>
      accounts.where((value) => value.identity == identity).firstOrNull;
}
