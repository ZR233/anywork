import 'package:anywork_client/acp.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';
import 'acp_account_target.dart';

part 'acp_account_editor_state.freezed.dart';

/// ACP 接入新建/编辑表单的展示状态。
///
/// 草稿只保存表单意图：显示名与本表单对一次准备操作的认领。受管服务器的
/// program/argv 由产品固定发行与安装事实决定，不是账号配置；认证状态、安装事实与保存
/// 结果也都不写进草稿，避免把“已登录”“已安装”写成本地事实。
///
/// 安装事实只来自 canonical `acpInstall` 观察（[install]）；本状态不从进度推断就绪，
/// 也不把开始受理的 `pending` 当成完成。
@Freezed(toStringOverride: false)
abstract class AcpAccountEditorViewState with _$AcpAccountEditorViewState {
  const AcpAccountEditorViewState._();

  const factory AcpAccountEditorViewState({
    required AcpAccountEditorTarget target,
    required String name,
    required AcpPreparationIntent intent,
    required AcpInstallState install,
    @Default(0) int draftRevision,
    @Default(false) bool visible,
    @Default(0) int latestIntent,
    SettingsAction? prepareAction,
    SettingsAction? cancelAction,

    /// 取消目标的安装 operation 身份，不是取消命令票据自身的 id。
    String? cancelTargetOperationId,
    StudioFailure? observationError,
  }) = _AcpAccountEditorViewState;

  bool get create => target.create;

  String get accountId => target.accountId;

  AcpAccountTemplate get template => target.template;

  AcpProvider get provider => target.template.provider;

  /// 该模板是否声明了自动准备资格（当前宿主平台是否受支持）。
  bool get canPrepareAutomatically => template.automaticInstall.isAvailable;

  /// 表单初始显示名：新建取模板显示名，编辑取 canonical 名称。
  String get initialName => switch (target) {
    AcpAccountCreateTarget(:final template) => template.displayName,
    AcpAccountEditTarget(:final account) => account.name,
  };

  bool get dirty => name != initialName;

  /// 属于本草稿意图的就绪结果（provider 与 operation 都匹配）。
  AcpInstalledServer? get prepared =>
      intent.resolve(install, provider: provider);

  /// 同一 provider 已就绪、但属于另一个操作的结果；只能由用户显式认领。
  AcpInstalledServer? get availableElsewhere =>
      intent.availableElsewhere(install, provider: provider);

  /// 本表单的 start 请求仍在途（尚未收到受理回执）。
  bool get preparing => prepareAction?.pending == true;

  /// 回执已受理但 canonical 状态尚未给出 operation。
  bool get admissionPending => preparing && install.operationId == null;

  /// 只有当前 canonical operation 的取消动作参与呈现；provider 由本表单的 target 固定。
  SettingsAction? get currentCancelAction =>
      cancelTargetOperationId != null &&
          cancelTargetOperationId == install.operationId
      ? cancelAction
      : null;

  /// 当前 operation 的取消命令自身在途；取消**不受** [preparing] 影响。
  bool get cancelPending => currentCancelAction?.pending == true;

  /// 准备主操作的门控：阶段在途或本表单 start 未回执时不再发起第二个 start。
  bool get prepareBlocked =>
      preparing ||
      (prepareAction?.preventsResubmission ?? false) ||
      install.isBusy;

  /// 新建必须准备到 Ready 才能保存；编辑只改名字，不要求重新准备。
  bool get saveAdmitted => !create || prepared != null;
}
