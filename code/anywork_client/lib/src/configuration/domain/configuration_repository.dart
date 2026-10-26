import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import '../../../models.dart' show BillingKind;
import '../../../resources.dart';
import '../../../acp.dart' show AcpAccountUpdate;
import 'account_entries.dart';
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

  /// 沿既有配置读取作用域，固定原配置目标分页读取 ACP 接入目录。
  ///
  /// 首次需求先同步既有 configuration 源并真实 pin 原目标；目录行按页、文本按块读取，
  /// 页身份/进展/续页与重复身份都校验后才返回。返回值的 revision/time 来自与材料引用
  /// 同一快照的配置 header，不用读取后的 latest 回填；查询结果不写入 canonical 投影。
  /// 同一快照还给出读取来源（原 owner 与材料引用），调用方可据此判断材料是否仍属于
  /// 当前 owner；未读取用 null 表达，不构造零值目录。
  /// 只读取既有事实，不联网、不启动进程、不检查凭据；认证状态仍只来自 `acpAuth`，
  /// 安装事实只来自 `acpInstall`。
  Future<AcpAccountDirectory> loadAcpAccounts();
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

  /// 保存（新增或更新）一条 ACP 接入；与 Native 账号同一 Settings CAS 提交边界。
  ///
  /// 成功只证明配置事实成立：不验证也不等待受管安装，不触发认证；保存成功后连接
  /// 失败不撤销已保存配置。名称编辑不改变连接代次。
  OperationTicket<Unit> saveAcpAccount(AcpAccountUpdate intent);

  /// 删除一条 ACP 接入；不注销官方账号、不删除其凭据，也不取消共享安装。
  OperationTicket<Unit> removeAcpAccount(String accountId);
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
