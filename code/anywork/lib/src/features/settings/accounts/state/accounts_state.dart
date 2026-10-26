import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';
import '../state/acp_account_target.dart';
import '../state/acp_command_notice.dart';

part 'accounts_state.freezed.dart';

enum AccountsReadField {
  accounts,
  models,
  templates,
  defaultAccount,
  usage,
  configurationSource,
  modelSource,
  usageSource,

  /// Settings canonical 快照里的 ACP 接入集合与接入模板目录。
  acpAccounts,
}

enum AccountRowAction { setDefault, remove }

@freezed
abstract class AccountUsageCheckPresentation
    with _$AccountUsageCheckPresentation {
  const factory AccountUsageCheckPresentation({
    required AccountUsageQueryIdentity? identity,
    required OperationState operation,
    required bool preparing,
    StudioFailure? observationError,
  }) = _AccountUsageCheckPresentation;
}

/// 账号面板的展示状态：Native 模型账号与 ACP 接入共享同一入口，各自保留封闭语义。
///
/// ACP 部分只保存 canonical 投影与命令在途事实：[acpAccounts] 是 Settings 快照的有界读取，
/// [acpAuth] 是 `acpAuth` 观察里最近的快照，[directory] 是两者加模板目录的组合投影。认证
/// 结果不从本地写入，删除/保存失败只以 typed [AcpCommandNotice] 绑定目标接入。
@freezed
abstract class AccountsViewState with _$AccountsViewState {
  const factory AccountsViewState({
    required ConfigurationState source,
    required ModelsState modelSource,
    required TemplatesState templateSource,
    required AccountUsageState usageSource,
    AccountTemplatesValue? templates,
    @Default('') String query,
    @Default([]) List<String> matchingAccountIds,

    /// 与查询匹配的 ACP 接入身份；与 [matchingAccountIds] 各自独立的顺序来源。
    @Default([]) List<String> matchingAcpAccountIds,

    String? selectedAccountId,
    @Default(false) bool showDetails,
    AccountEditorKey? editor,
    String? editorAccountId,
    @Default(0) int navigationIntent,
    @Default(0) int latestIntent,
    @Default({}) Map<(String, AccountRowAction), SettingsAction> rowActions,
    @Default({}) Set<String> preparingRemovalIds,
    @Default({}) Map<(String, String), SettingsAction> modelActions,
    @Default({}) Map<String, SettingsAction> usageActions,
    @Default({}) Map<String, OperationId> usageActionIds,
    @Default({}) Map<String, AccountUsageCheckPresentation> usageChecks,
    @Default(false) bool refreshingAll,
    @Default({}) Map<AccountsReadField, StudioFailure> readIssues,
    @Default({}) Set<AccountsReadField> reading,
    StudioFailure? editorError,

    /// Settings canonical 快照里的 ACP 接入集合；null 表示尚未读到事实。
    AcpAccountDirectory? acpAccounts,

    /// ACP 接入模板目录；null 表示尚未读取，空目录表示后端未声明模板。
    AcpAccountCatalog? acpCatalog,

    /// `acpAuth` 最近一次 canonical 快照；null 表示领域尚未观察。
    AcpAuthSnapshot? acpAuth,

    /// Native + ACP 的 typed 目录投影；null 表示素材尚未齐备。
    AccountDirectoryView? directory,

    /// 当前选中的 ACP 接入身份（与 Native 选择互斥）。
    String? selectedAcpAccountId,

    /// 当前 ACP 编辑目标（新建/编辑）；null 表示没有 ACP 表单。
    AcpAccountEditorTarget? acpEditor,

    /// 已保存接入的 canonical 回执明确“需要准备/安装不合格”：编辑表单要给出准备动作。
    @Default(false) bool acpNeedsPreparation,

    /// 按目标接入记账的命令失败通知：只出现在目标行/目标详情。
    @Default({}) Map<String, AcpCommandNotice> acpNotices,

    /// 按目标接入记账的删除受理与结果。
    @Default({}) Map<String, SettingsAction> acpRemovals,
  }) = _AccountsViewState;
}
