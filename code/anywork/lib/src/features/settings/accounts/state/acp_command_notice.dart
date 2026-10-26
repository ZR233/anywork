import 'package:anywork_client/acp.dart';
import 'package:anywork_client/resources.dart';

import '../../../../l10n/app_localizations.dart';
import 'acp_failure_labels.dart';

/// 命令失败通知的意图类别。
///
/// 只有 [AcpCommandNoticeKind.authentication] 的通知可以被后续同账号认证进展/终态取代；
/// [AcpCommandNoticeKind.configuration] / [AcpCommandNoticeKind.remove] 属于配置命令错误，
/// 必须保留到明确重试成功、目标移除或对应连接身份失效——**不会**因为该账号已 Verified
/// 而消失。
enum AcpCommandNoticeKind { authentication, configuration, remove }

/// 命令层就地失败的 typed 通知：ViewState 只保存事实，本地化在展示层完成。
///
/// 通知**绑定目标接入与连接身份**：列表里的删除失败只会出现在目标行/目标详情，不会挂到
/// 另一个被选中的账号上；[operationId] 记录拒绝发生时该账号 canonical 的在途操作，用于
/// 在后续进展/终态取代旧拒绝后不再呈现。
///
/// [failure] 是命令回执给出的 typed `StudioFailure`；null 表示非 typed 的意外错误，展示层
/// 用通用文案。`failure.message` 是后端安全原文（不是 raw stderr），只作次级技术详情，
/// 不参与摘要本地化。
final class AcpCommandNotice {
  const AcpCommandNotice({
    required this.kind,
    required this.accountId,
    required this.connectionRevision,
    this.failure,
    this.operationId,
    this.connectIncomplete = false,
  });

  final AcpCommandNoticeKind kind;
  final String accountId;

  /// 发起该命令时的连接身份（在 await 之前冻结）；identity 变化即为过时。
  final int connectionRevision;

  /// typed 命令失败；null 表示无法归类的意外错误。
  final StudioFailure? failure;

  /// 拒绝发生时该接入 canonical 的在途操作；null 表示当时没有在途操作。
  final String? operationId;

  /// 该通知来自“账号已保存、连接未完成”的编排：摘要使用专门的完成度文案，
  /// 而不是普通命令失败文案。
  final bool connectIncomplete;

  /// 后端安全原文（可为空）；只作折叠的技术详情。
  String? get detail {
    final message = failure?.message ?? '';
    return message.isEmpty ? null : message;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpCommandNotice &&
          other.kind == kind &&
          other.accountId == accountId &&
          other.connectionRevision == connectionRevision &&
          other.failure == failure &&
          other.operationId == operationId &&
          other.connectIncomplete == connectIncomplete;

  @override
  int get hashCode => Object.hash(
    kind,
    accountId,
    connectionRevision,
    failure,
    operationId,
    connectIncomplete,
  );
}

/// 通知的本地化摘要：typed code → 产品文案；非 typed 错误用通用不可用文案。
String acpCommandNoticeSummary(
  AppLocalizations l10n,
  AcpCommandNotice notice, {
  String? fallback,
}) {
  final failure = notice.failure;
  if (failure == null) return fallback ?? l10n.acpAuthCommandUnavailable;
  final reason = acpStudioFailureCodeText(l10n, failure.code);
  return notice.connectIncomplete
      ? l10n.acpAccountSavedConnectIncomplete(reason)
      : l10n.acpAuthCommandFailure(reason);
}

/// 通知是否应呈现（账号 + 连接身份 + 意图类别 + 认证在途操作）。
///
/// - 账号或连接身份变化 → 过时（任何类别）；
/// - [AcpCommandNoticeKind.authentication]：只在同一在途操作仍当前、或尚未进入新尝试/成功
///   时显示；
/// - [AcpCommandNoticeKind.configuration] / [AcpCommandNoticeKind.remove]：与认证进展无关，
///   **不因该账号已 Verified 而隐藏**，只由明确重试成功、目标移除或身份失效清除。
AcpCommandNotice? visibleAcpCommandNotice({
  required AcpCommandNotice? notice,
  required String accountId,
  required int connectionRevision,
  required AcpAuthState auth,
}) {
  if (notice == null) return null;
  if (notice.accountId != accountId) return null;
  if (notice.connectionRevision != connectionRevision) return null;
  if (notice.kind != AcpCommandNoticeKind.authentication) return notice;
  final operationId = notice.operationId;
  if (operationId != null) {
    return auth.operationId == operationId ? notice : null;
  }
  if (auth.isBusy) return null;
  return auth is AcpAuthVerified ? null : notice;
}

/// 认证命令的 typed `busy` 是否只是**重复输入**。
///
/// 三类事实必须同时成立才吞掉这次失败：后端给的是 `busy`、响应时该接入仍是发起请求时的
/// 连接身份、且该接入 canonical 已有在途操作——进度由 canonical 状态承接，不需要红色
/// 失败。当前连接身份已前进（旧请求的失败不能算重复输入）、非 `busy` 或没有在途操作都
/// 必须照常呈现。
bool isAcpAuthDuplicateWhileInFlight({
  required Object error,
  required int requestConnectionRevision,
  required int currentConnectionRevision,
  required AcpAuthState auth,
}) {
  if (error is! StudioFailure || error.code != StudioFailureCode.busy) {
    return false;
  }
  if (currentConnectionRevision != requestConnectionRevision) return false;
  return auth.isBusy;
}
