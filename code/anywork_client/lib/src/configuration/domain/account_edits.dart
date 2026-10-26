import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../models.dart' show BillingKind;

part 'account_edits.freezed.dart';

@freezed
sealed class FieldEdit<T> with _$FieldEdit<T> {
  const factory FieldEdit.keep() = KeepField<T>;
  const factory FieldEdit.set(T value) = SetField<T>;
}

/// Secret commands are write-only, are not serializable by the SDK and never
/// participate in generated diagnostic output.
@Freezed(toStringOverride: false)
sealed class AccountSecretUpdate with _$AccountSecretUpdate {
  const factory AccountSecretUpdate.preserve() = PreserveAccountSecret;
  const factory AccountSecretUpdate.replace(String value) =
      ReplaceAccountSecret;
  const factory AccountSecretUpdate.clear() = ClearAccountSecret;
}

@Freezed(toStringOverride: false)
final class AccountEdit with _$AccountEdit {
  AccountEdit({
    required this.accountId,
    required this.create,
    required this.templateId,
    required this.protocol,
    required this.name,
    required this.baseUrl,
    required this.secret,
    required this.initialBillingKind,
    required this.rebuildModelConfiguration,
    required List<CustomModelChange> customModels,
    required List<ModelConnectionChange> connections,
    required List<ModelLimitChange> autoCompactLimits,
  }) : customModels = List.unmodifiable(customModels),
       connections = List.unmodifiable(connections),
       autoCompactLimits = List.unmodifiable(autoCompactLimits);

  final String accountId;
  final bool create;
  final FieldEdit<String?> templateId;
  final FieldEdit<String> protocol;
  final FieldEdit<String> name;
  final FieldEdit<String> baseUrl;
  final AccountSecretUpdate secret;

  /// 新账号的初始计费类别；只在 [create] 为 true 时提交。
  ///
  /// 编辑已有账号不得用它改写计费类别（改写走 setAccountBillingKind 窄命令）；
  /// `BillingKind.unknown` 表示“未指定”，不会作为初始值提交。
  final BillingKind? initialBillingKind;
  final bool rebuildModelConfiguration;
  final List<CustomModelChange> customModels;
  final List<ModelConnectionChange> connections;
  final List<ModelLimitChange> autoCompactLimits;
}

@freezed
sealed class CustomModelChange with _$CustomModelChange {
  const factory CustomModelChange.upsert({
    required String? originalModelId,
    required AccountModelUpdate value,
  }) = UpsertCustomModel;
  const factory CustomModelChange.remove({required String modelId}) =
      RemoveCustomModel;
}

@freezed
abstract class AccountModelUpdate with _$AccountModelUpdate {
  const factory AccountModelUpdate({
    required String modelId,
    required String displayName,
    required String wireApi,
    required int? contextWindow,
    required int? maxOutputTokens,
  }) = _AccountModelUpdate;
}

@freezed
abstract class ModelConnectionChange with _$ModelConnectionChange {
  const factory ModelConnectionChange({
    required String modelId,
    required String connectionMode,
  }) = _ModelConnectionChange;
}

@freezed
abstract class ModelLimitChange with _$ModelLimitChange {
  const factory ModelLimitChange({
    required String modelId,
    required int? overrideLimit,
  }) = _ModelLimitChange;
}
