import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import '../../../models.dart' show BillingKind;
import '../../../resources.dart';
import 'account_configuration_read_source.dart';
import 'account_edits.dart';
import 'configuration_state.dart';
import 'configuration_values.dart';
import 'profile_values.dart';
import 'settings_updates.dart';
import 'start_route_values.dart';

part 'configuration_repository.freezed.dart';

abstract interface class ConfigurationRepository
    implements AccountConfigurationReadSource {
  ReadonlyLatestValue<ProfilesState> get profiles;
  Future<void> loadSourceStatus();
  Future<void> loadProfilesSourceStatus();
  Future<void> loadAccountsPage({int limit = 32});
  Future<void> loadProfilesPage({int limit = 32});
  Future<String?> loadDefaultAccountId();
  Future<List<ModeModelRoute>> loadModeRoutes();
  Future<List<RoleModelRoute>> loadRoleRoutes();

  /// Read the exact Rust-issued pair; null roleRead is unknown, not absence.
  Future<RoleRouteRead> roleRoute({
    required ConfigurationRoleReadTarget target,
    required String roleId,
  });

  /// Pure Start resolution/editing suggestion over the supplied original pair.
  /// Results retain sources/query; callers still verify their current draft.
  Future<StartRouteRead> readStartRoute({
    required ConfigurationRoleReadTarget sources,
    required StartRouteQuery query,
  });
  Future<String> loadPermissionMode();
  Future<List<McpConfiguration>> loadMcpConfigurations();
  Future<List<ProfileDiagnostic>> loadProfileDiagnostics();
  Future<InstructionsSettings> loadInstructions();
  Future<SkillsSettings> loadSkillsSettings();
  Future<GeneralSettings> loadGeneralSettings();
  Future<DelegationSettings> loadDelegationSettings();
  Future<WebSearchConfiguration> loadWebSearchSettings();
  Future<DeepSeekSearchConfiguration> loadDeepSeekSettings();
  Future<AgentProfileSnapshot> loadProfile(String profileId);
  OperationTicket<Unit> saveAccount(AccountEdit intent);
  OperationTicket<Unit> setDefaultAccount(String accountId);
  OperationTicket<Unit> removeAccount(
    String accountId, {
    String? replacementAccountId,
  });
  OperationTicket<Unit> removeAccountModel(String accountId, String modelId);
  OperationTicket<Unit> setAccountModelEnabled(
    String accountId,
    String modelId,
    bool enabled,
  );

  /// null clears the override; BillingKind.unknown is an explicit override.
  OperationTicket<Unit> setAccountBillingKind(
    String accountId,
    BillingKind? billingKind,
  );
  OperationTicket<Unit> applyField(SettingsFieldUpdate update);
  SettingsWriteBatch applyFields(List<SettingsFieldUpdate> updates);
  OperationTicket<Unit> setPermissionMode(PermissionMode mode);
  OperationTicket<Unit> saveProfile(AgentProfileEdit profile);
  OperationTicket<Unit> setSystemProfileEnabled(String profileId, bool enabled);
  OperationTicket<Unit> reload();
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

/// Borrowed observation of repository-owned steps, not a transaction or a new
/// parent operation. The repository retains all queued/in-flight work.
abstract interface class SettingsWriteBatch {
  List<OperationObservation> get operations;
  Future<SettingsBatchResult> get result;
}

@Freezed(toStringOverride: false)
final class SettingsBatchResult with _$SettingsBatchResult {
  SettingsBatchResult({required List<SettingsFieldResult> steps})
    : steps = List.unmodifiable(steps);
  final List<SettingsFieldResult> steps;
}

@Freezed(toStringOverride: false)
sealed class SettingsFieldResult with _$SettingsFieldResult {
  const factory SettingsFieldResult.finished({
    required int index,
    required OperationId operationId,
    required CommandResult<Unit> result,
  }) = FinishedSettingsField;
  const factory SettingsFieldResult.notStarted({
    required int index,
    required OperationId operationId,
    required StudioFailure error,
  }) = NotStartedSettingsField;
}
