import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import '../../models/domain/model_values.dart';
import '../../models/domain/models_state.dart';
import '../../resources/domain/identity.dart';
// ACP 接入值由该库定义；窄 `show` 会让生成的 `$AcpAccountUpdateCopyWith` 不可见。
import '../../acp/domain/acp_values.dart';
import '../domain/account_edits.dart';
import '../domain/configuration_state.dart';
import '../domain/profile_values.dart';
import '../domain/settings_updates.dart';

part 'configuration_commands.freezed.dart';

@Freezed(toStringOverride: false)
final class AccountSettingsUpdate with _$AccountSettingsUpdate {
  AccountSettingsUpdate({
    required this.accountId,
    required this.templateId,
    required this.protocol,
    required this.name,
    required this.baseUrl,
    required this.secret,
    required this.initialBillingKind,
    required List<AccountModelUpdate> customModels,
    required List<AccountModelConnectionUpdate> modelConnectionModes,
    required List<AccountModelAutoCompactUpdate> modelAutoCompactLimits,
  }) : customModels = List.unmodifiable(customModels),
       modelConnectionModes = List.unmodifiable(modelConnectionModes),
       modelAutoCompactLimits = List.unmodifiable(modelAutoCompactLimits);
  final String accountId;
  final String? templateId;
  final String protocol;
  final String name;
  final String baseUrl;
  final AccountSecretUpdate secret;

  /// 仅创建时携带的初始计费类别；编辑已有账号必须为 null。
  final BillingKind? initialBillingKind;
  final List<AccountModelUpdate> customModels;
  final List<AccountModelConnectionUpdate> modelConnectionModes;
  final List<AccountModelAutoCompactUpdate> modelAutoCompactLimits;
}

@freezed
abstract class AccountModelConnectionUpdate
    with _$AccountModelConnectionUpdate {
  const factory AccountModelConnectionUpdate({
    required String modelId,
    required String connectionMode,
  }) = _AccountModelConnectionUpdate;
}

@freezed
abstract class AccountModelAutoCompactUpdate
    with _$AccountModelAutoCompactUpdate {
  const factory AccountModelAutoCompactUpdate({
    required String modelId,
    required int limit,
  }) = _AccountModelAutoCompactUpdate;
}

@Freezed(toStringOverride: false)
abstract class UpdateAccountRequest with _$UpdateAccountRequest {
  const factory UpdateAccountRequest({
    required OperationId operationId,
    required int expectedRevision,
    required AccountSettingsUpdate account,
  }) = _UpdateAccountRequest;
}

@freezed
abstract class SetDefaultAccountRequest with _$SetDefaultAccountRequest {
  const factory SetDefaultAccountRequest({
    required OperationId operationId,
    required int expectedRevision,
    required String accountId,
  }) = _SetDefaultAccountRequest;
}

@freezed
abstract class RemoveAccountRequest with _$RemoveAccountRequest {
  const factory RemoveAccountRequest({
    required OperationId operationId,
    required int expectedRevision,
    required String accountId,
    required String? replacementAccountId,
  }) = _RemoveAccountRequest;
}

/// 保存（新增或更新）一条 ACP 接入；与 Native 账号共用 Settings CAS 边界。
///
/// 只有稳定 ID、名称与 provider：受管 server 的 program/argv 属于产品固定发行，
/// 客户端、HTTP 与配置文件都不能提交或恢复任意执行路径。
@freezed
abstract class UpdateAcpAccountRequest with _$UpdateAcpAccountRequest {
  const factory UpdateAcpAccountRequest({
    required OperationId operationId,
    required int expectedRevision,
    required AcpAccountUpdate account,
  }) = _UpdateAcpAccountRequest;
}

/// 删除一条 ACP 接入；只移除本地接入，不注销官方账号或删除其凭据。
@freezed
abstract class RemoveAcpAccountRequest with _$RemoveAcpAccountRequest {
  const factory RemoveAcpAccountRequest({
    required OperationId operationId,
    required int expectedRevision,
    required String accountId,
  }) = _RemoveAcpAccountRequest;
}

/// ACP 账号写入的真实结果：一次 Settings 写入，不是 configuration+models 双目标事务。
///
/// [receipt] 是真实 Settings 回执（唯一目标为 `settings` 资源）；[configuration] 是本次
/// 提交捕获的配置读取目标，用于在调用关闭前从原目标完整读取 ACP 账号目录。
/// 这里不携带整份账号目录、不伪造模型目录目标，也不把材料版本当成 Settings revision。
@Freezed(toStringOverride: false)
abstract class AcpAccountCommandReply with _$AcpAccountCommandReply {
  const factory AcpAccountCommandReply({
    required CommitReceipt receipt,
    required ConfigurationReadTarget configuration,
  }) = _AcpAccountCommandReply;
}

@freezed
abstract class RemoveAccountModelRequest with _$RemoveAccountModelRequest {
  const factory RemoveAccountModelRequest({
    required OperationId operationId,
    required int expectedRevision,
    required String accountId,
    required String modelId,
  }) = _RemoveAccountModelRequest;
}

@freezed
abstract class SetAccountModelEnabledRequest
    with _$SetAccountModelEnabledRequest {
  const factory SetAccountModelEnabledRequest({
    required OperationId operationId,
    required int expectedRevision,
    required String accountId,
    required String modelId,
    required bool enabled,
  }) = _SetAccountModelEnabledRequest;
}

@freezed
abstract class SetAccountBillingKindRequest
    with _$SetAccountBillingKindRequest {
  const factory SetAccountBillingKindRequest({
    required OperationId operationId,
    required int expectedRevision,
    required String accountId,
    required BillingKind? billingKind,
  }) = _SetAccountBillingKindRequest;
}

@Freezed(toStringOverride: false)
abstract class UpdateSettingsFieldRequest with _$UpdateSettingsFieldRequest {
  const factory UpdateSettingsFieldRequest({
    required OperationId operationId,
    required int expectedRevision,
    required SettingsFieldUpdate update,
  }) = _UpdateSettingsFieldRequest;
}

@freezed
abstract class UpdatePermissionSettingsRequest
    with _$UpdatePermissionSettingsRequest {
  const factory UpdatePermissionSettingsRequest({
    required OperationId operationId,
    required int expectedRevision,
    required String mode,
  }) = _UpdatePermissionSettingsRequest;
}

@Freezed(toStringOverride: false)
abstract class SaveProfileRequest with _$SaveProfileRequest {
  const factory SaveProfileRequest({
    required OperationId operationId,
    required int expectedSettingsRevision,
    required AgentProfileEdit profile,
  }) = _SaveProfileRequest;
}

@freezed
abstract class SetSystemProfileEnabledRequest
    with _$SetSystemProfileEnabledRequest {
  const factory SetSystemProfileEnabledRequest({
    required OperationId operationId,
    required int expectedSettingsRevision,
    required String profileId,
    required bool enabled,
  }) = _SetSystemProfileEnabledRequest;
}

@freezed
abstract class ConfigurationReloadRequest with _$ConfigurationReloadRequest {
  const factory ConfigurationReloadRequest({
    required OperationId operationId,
    required int expectedRevision,
  }) = _ConfigurationReloadRequest;
}

@freezed
abstract class ConfigurationCommandReply with _$ConfigurationCommandReply {
  const factory ConfigurationCommandReply({
    required CommitReceipt receipt,
    required ConfigurationReadTarget configuration,
    required ModelCatalogReadTarget models,
  }) = _ConfigurationCommandReply;
}

@freezed
abstract class ProfileCommandReply with _$ProfileCommandReply {
  const factory ProfileCommandReply({
    required CommitReceipt receipt,
    required ConfigurationReadTarget configuration,
    required ModelCatalogReadTarget models,
    required AgentProfilesReadTarget profiles,
  }) = _ProfileCommandReply;
}

/// Explicit disk import has three native targets but no native receipt.
@freezed
abstract class ConfigurationReloadResult with _$ConfigurationReloadResult {
  const factory ConfigurationReloadResult({
    required ConfigurationReadTarget configuration,
    required ModelCatalogReadTarget models,
    required AgentProfilesReadTarget profiles,
  }) = _ConfigurationReloadResult;
}
