import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import '../../models/domain/model_values.dart';
import '../../models/domain/models_state.dart';
import '../../resources/domain/identity.dart';
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
    required this.pricingEnabled,
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
  final bool pricingEnabled;
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
