import 'package:anywork_client/acp.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';
import 'acp_account_target.dart';
import 'acp_command_notice.dart';

part 'acp_account_auth_state.freezed.dart';

/// 一个已保存接入的认证区展示状态。
///
/// [auth] 是 canonical `acpAuth` 观察里与账号身份 + 连接身份同时匹配的条目；没有匹配条目
/// 时是 [AcpAuthUnchecked]，绝不推断为成功。[checkAction] / [cancelAction] 只记录命令层
/// 受理与结果，业务状态永远来自 canonical 观察：`closing`/`cancelling` 是忙而不是终态，
/// 取消入口只由 canonical 的 operation 身份决定是否可达。
@Freezed(toStringOverride: false)
abstract class AcpAccountAuthViewState with _$AcpAccountAuthViewState {
  const AcpAccountAuthViewState._();

  const factory AcpAccountAuthViewState({
    required AcpAccountTarget target,
    required AcpAuthState auth,
    @Default(false) bool visible,
    @Default(0) int latestIntent,
    SettingsAction? checkAction,
    SettingsAction? cancelAction,
    AcpCommandNotice? notice,
    StudioFailure? observationError,
  }) = _AcpAccountAuthViewState;

  String get accountId => target.accountId;

  /// 检查/登录命令在途（尚未收到 canonical 回应），不是业务状态。
  bool get busy => checkAction?.pending == true;

  /// 取消命令自身在途；取消**不受** [busy] 影响，否则迟到的 start 会锁死取消。
  bool get cancelBusy => cancelAction?.pending == true;

  /// 取消入口可用的唯一依据：canonical 观察给出了当前 operation 身份。
  bool get canCancel => auth.operationId != null && !cancelBusy;

  /// 该账号当前可见的命令失败通知（账号 + 连接身份 + 意图类别 + 在途操作）。
  AcpCommandNotice? get visibleNotice => visibleAcpCommandNotice(
    notice: notice,
    accountId: target.accountId,
    connectionRevision: target.connectionRevision,
    auth: auth,
  );
}
