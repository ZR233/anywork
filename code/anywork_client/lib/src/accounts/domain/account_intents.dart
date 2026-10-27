import '../../models/studio_commands.dart';
import '../../models/delegation_models.dart';
import 'account_identity.dart';

sealed class AccountTextPatch {
  const AccountTextPatch();
  const factory AccountTextPatch.keep() = AccountTextKeep;
  const factory AccountTextPatch.set(String value) = AccountTextSet;
  const factory AccountTextPatch.restore() = AccountTextRestore;
}

final class AccountTextKeep extends AccountTextPatch {
  const AccountTextKeep();
}

final class AccountTextSet extends AccountTextPatch {
  const AccountTextSet(this.value);
  final String value;
}

final class AccountTextRestore extends AccountTextPatch {
  const AccountTextRestore();
}

sealed class AccountModelsPatch {
  const AccountModelsPatch();
  const factory AccountModelsPatch.keep() = AccountModelsKeep;
  factory AccountModelsPatch.set(Iterable<AccountModelCommand> models) =
      AccountModelsSet;
  const factory AccountModelsPatch.restore() = AccountModelsRestore;
}

final class AccountModelsKeep extends AccountModelsPatch {
  const AccountModelsKeep();
}

final class AccountModelsSet extends AccountModelsPatch {
  AccountModelsSet(Iterable<AccountModelCommand> models)
    : models = List.unmodifiable(models);
  final List<AccountModelCommand> models;
}

final class AccountModelsRestore extends AccountModelsPatch {
  const AccountModelsRestore();
}

final class CreateAccountCommand {
  CreateAccountCommand({
    required this.identity,
    required this.name,
    required this.protocol,
    this.templateId,
    required this.baseUrl,
    required this.secret,
    this.initialBillingKind,
    Iterable<AccountModelCommand> customModels = const [],
    Iterable<AccountModelConnectionCommand> modelConnectionModes = const [],
    Iterable<AccountModelAutoCompactCommand> modelAutoCompactLimits = const [],
  }) : customModels = List.unmodifiable(customModels),
       modelConnectionModes = List.unmodifiable(modelConnectionModes),
       modelAutoCompactLimits = List.unmodifiable(modelAutoCompactLimits);
  final NativeAccountIdentity identity;
  final String name;
  final String protocol;
  final String? templateId;
  final String baseUrl;
  final AccountSecretCommand secret;
  final BillingKind? initialBillingKind;
  final List<AccountModelCommand> customModels;
  final List<AccountModelConnectionCommand> modelConnectionModes;
  final List<AccountModelAutoCompactCommand> modelAutoCompactLimits;
}

final class PatchAccountCommand {
  const PatchAccountCommand({
    required this.identity,
    this.name = const AccountTextPatch.keep(),
    this.protocol = const AccountTextPatch.keep(),
    this.templateId = const AccountTextPatch.keep(),
    this.baseUrl = const AccountTextPatch.keep(),
    this.secret = const AccountSecretCommand.preserve(),
    this.customModels = const AccountModelsPatch.keep(),
  });
  final NativeAccountIdentity identity;
  final AccountTextPatch name;
  final AccountTextPatch protocol;
  final AccountTextPatch templateId;
  final AccountTextPatch baseUrl;
  final AccountSecretCommand secret;
  final AccountModelsPatch customModels;
}

sealed class AutoCompactIntent {
  const AutoCompactIntent();
  factory AutoCompactIntent.set(int limit) = SetAutoCompactLimit;
  const factory AutoCompactIntent.clear() = ClearAutoCompactLimit;
}

final class SetAutoCompactLimit extends AutoCompactIntent {
  SetAutoCompactLimit(this.limit) {
    if (limit <= 0)
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
  }
  final int limit;
}

final class ClearAutoCompactLimit extends AutoCompactIntent {
  const ClearAutoCompactLimit();
}

enum AccountConnectionMode { http, webSocket }

sealed class ModelConnectionIntent {
  const ModelConnectionIntent();
  const factory ModelConnectionIntent.set(AccountConnectionMode mode) =
      SetModelConnection;
  const factory ModelConnectionIntent.clear() = ClearModelConnection;
}

final class SetModelConnection extends ModelConnectionIntent {
  const SetModelConnection(this.mode);
  final AccountConnectionMode mode;
}

final class ClearModelConnection extends ModelConnectionIntent {
  const ClearModelConnection();
}
