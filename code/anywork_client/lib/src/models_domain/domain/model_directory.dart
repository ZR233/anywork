import '../../accounts/domain/account_identity.dart';
import '../../accounts/domain/account_intents.dart';
import '../../accounts/domain/account_values.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../models/account_models.dart';
import '../../models/delegation_models.dart';
import '../../models/model_catalog.dart';
import '../../observation/latest_value.dart';
import 'immutable_model.dart';

final class AccountModelCatalog {
  AccountModelCatalog({
    required this.identity,
    required Iterable<AccountModelView> models,
    required this.status,
  }) : models = List.unmodifiable(models.map(immutableModelDescriptor));
  final NativeAccountIdentity identity;
  final List<AccountModelView> models;
  final ModelCatalogStatusView status;
  AccountModelView? model(String id) =>
      models.where((model) => model.modelId == id).firstOrNull;
}

final class ModelDirectoryState {
  ModelDirectoryState({
    Map<NativeAccountIdentity, AccountResource<AccountModelCatalog>> accounts =
        const {},
    Map<NativeAccountIdentity, AccountResource<AccountModelConfiguration>>
        configurations =
        const {},
  }) : accounts = Map.unmodifiable(accounts),
       configurations = Map.unmodifiable(configurations);
  final Map<NativeAccountIdentity, AccountResource<AccountModelCatalog>>
  accounts;
  final Map<NativeAccountIdentity, AccountResource<AccountModelConfiguration>>
  configurations;
  AccountModelView? model(AccountModelIdentity identity) =>
      accounts[identity.account]?.loaded == true
      ? accounts[identity.account]?.value?.model(identity.modelId)
      : null;
}

/// Raw model override intent is settings-owned, while effective descriptors use
/// model-catalog stamps. These clocks are deliberately not collapsed.
final class AccountModelConfiguration {
  AccountModelConfiguration({
    Iterable<String> disabledModels = const [],
    Map<String, AccountConnectionMode> connections = const {},
    Map<String, int> autoCompactLimits = const {},
  }) : disabledModels = List.unmodifiable(disabledModels),
       connections = Map.unmodifiable(connections),
       autoCompactLimits = Map.unmodifiable(autoCompactLimits);
  final List<String> disabledModels;
  final Map<String, AccountConnectionMode> connections;
  final Map<String, int> autoCompactLimits;
}

/// A read-only join used by route pickers, never an account configuration card.
final class ModelSelectionAccount {
  ModelSelectionAccount({
    required this.id,
    required this.name,
    this.brandKey,
    required this.billingKind,
    required Iterable<AccountModelView> models,
  }) : models = List.unmodifiable(models);
  final String id;
  final String name;
  final String? brandKey;
  final BillingKind? billingKind;
  final List<AccountModelView> models;
  Iterable<AccountModelView> modelsFor({ModelType? type}) => models.where(
    (model) => model.enabled && (type == null || model.matchesType(type)),
  );
  String? get iconKey => brandKey;
}

List<ModelSelectionAccount> modelSelectionAccounts(
  AccountsState accounts,
  ModelDirectoryState models,
) => List.unmodifiable([
  for (final account in accounts.accounts)
    if (account.identity case final NativeAccountIdentity identity)
      ModelSelectionAccount(
        id: identity.accountId,
        name: account.name,
        brandKey: account.brandKey,
        billingKind: account.billingKind,
        models: !accounts.stale && models.accounts[identity]?.loaded == true
            ? models.accounts[identity]?.value?.models ?? const []
            : const [],
      ),
]);

final class ModelSyncAdmission {
  const ModelSyncAdmission({
    required this.operationId,
    required this.account,
    required this.queryGeneration,
    required this.joinedExisting,
  });
  final OperationId operationId;
  final NativeAccountIdentity account;
  final int queryGeneration;
  final bool joinedExisting;
}

abstract interface class ModelsRepository {
  ValueObservation<ModelDirectoryState> get state;
  AccountDemand observeAccount(NativeAccountIdentity identity);
  AccountDemand observeDirectory();
  Future<OperationState> setEnabled(
    AccountModelIdentity identity,
    bool enabled,
  );
  Future<OperationState> setAutoCompact(
    AccountModelIdentity identity,
    AutoCompactIntent intent, {
    DraftStamp? draft,
  });
  Future<OperationState> setConnection(
    AccountModelIdentity identity,
    ModelConnectionIntent intent,
  );
  Future<OperationState> removeManual(AccountModelIdentity identity);
  Future<ModelSyncAdmission> sync(NativeAccountIdentity identity);
  Future<DelegationModelDetail> performance(AccountModelIdentity identity);
}
