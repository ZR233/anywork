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
    required NativeAccountIdentity identity,
    required Iterable<AccountModelView> models,
    required ModelCatalogStatusView status,
  }) : this._(
         identity,
         List.unmodifiable(models.map(immutableModelDescriptor)),
         status,
         const {},
       );
  AccountModelCatalog._(
    this.identity,
    this._sourceModels,
    this.status,
    Map<String, bool> overrides,
  ) : models = List.unmodifiable([
        for (final model in _sourceModels)
          if (overrides[model.modelId] case final enabled?)
            model.copyWith(enabled: enabled)
          else
            model,
      ]);
  final NativeAccountIdentity identity;
  // Keep the received descriptors so a later configuration frame cannot turn
  // yesterday's explicit override into today's automatic backend default.
  final List<AccountModelView> _sourceModels;
  final List<AccountModelView> models;
  final ModelCatalogStatusView status;
  AccountModelCatalog withConfiguration(
    AccountModelConfiguration? configuration,
  ) => AccountModelCatalog._(
    identity,
    _sourceModels,
    status,
    configuration?.modelEnabledOverrides ?? const {},
  );
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
    Map<String, bool> modelEnabledOverrides = const {},
    Map<String, AccountConnectionMode> connections = const {},
    Map<String, int> autoCompactLimits = const {},
  }) : modelEnabledOverrides = Map.unmodifiable(modelEnabledOverrides),
       connections = Map.unmodifiable(connections),
       autoCompactLimits = Map.unmodifiable(autoCompactLimits);
  final Map<String, bool> modelEnabledOverrides;
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
