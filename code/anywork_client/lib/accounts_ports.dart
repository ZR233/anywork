/// Adapter and composition surfaces. UI consumers import domain entrypoints.
library;

import 'accounts.dart';
import 'model_directory.dart';
import 'models.dart' show SettingsCommandReply, OperationId;
import 'src/accounts/account_frames.dart';

export 'src/accounts/account_frames.dart';
export 'src/settings/data/settings_write_coordinator.dart';
export 'src/accounts/data/account_domain_resources.dart';

abstract interface class AccountDomainObservation {
  Future<AccountDomainFrame?> next();
  void requestClose();
  Future<void> close();
}

abstract interface class AccountFeedPort {
  Future<AccountDomainObservation> openAccountObservation(
    AccountObservationTarget target,
  );
  Future<AccountDomainFrame> readAccountDomain(AccountObservationTarget target);
}

abstract interface class AccountConfigurationPort {
  Future<AccountCatalogView> loadAccountCatalog();
  Future<SettingsCommandReply> createAccount(
    int revision,
    CreateAccountCommand command, {
    required OperationId operationId,
  });
  Future<SettingsCommandReply> patchAccount(
    int revision,
    PatchAccountCommand command, {
    required OperationId operationId,
  });
  Future<SettingsCommandReply> removeAccount(
    int revision,
    String accountId, {
    String? replacementAccountId,
    required OperationId operationId,
  });
  Future<SettingsCommandReply> setDefaultAccount(
    int revision,
    String accountId, {
    required OperationId operationId,
  });
  Future<SettingsCommandReply> setAccountBillingKind(
    int revision,
    String accountId,
    BillingKind? billingKind, {
    required OperationId operationId,
  });
  Future<ChatGptLoginCommandReply> startChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  });
  Future<ChatGptLoginCommandReply> cancelChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  });
}

abstract interface class AccountModelsPort {
  Future<SettingsCommandReply> setAccountModelEnabled(
    int revision,
    String accountId,
    String modelId,
    bool enabled, {
    required OperationId operationId,
  });
  Future<SettingsCommandReply> setAccountModelAutoCompact(
    int revision,
    AccountModelIdentity identity,
    AutoCompactIntent intent, {
    required OperationId operationId,
  });
  Future<SettingsCommandReply> setAccountModelConnection(
    int revision,
    AccountModelIdentity identity,
    ModelConnectionIntent intent, {
    required OperationId operationId,
  });
  Future<SettingsCommandReply> removeAccountModel(
    int revision,
    String accountId,
    String modelId, {
    required OperationId operationId,
  });
  Future<ModelSyncAdmission> syncAccountModels(
    NativeAccountIdentity identity, {
    required OperationId operationId,
  });
  Future<DelegationModelDetail> getDelegationModel(DelegationModelKey key);
}

abstract interface class AccountUsagePort {
  Future<AccountUsageFrame> queryAccountUsage(NativeAccountIdentity identity);
}
