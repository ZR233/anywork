import 'package:anywork_client/acp.dart';

import '../../../../l10n/app_localizations.dart';
import 'acp_failure_labels.dart';

/// 认证状态的产品文案：标题、正文、列表摘要与 Driver 阶段 token。
///
/// 所有分支都只读 canonical `AcpAuthState` 的 typed 事实：不从本地布尔值推断登录成功，
/// 也不把 `closing`/`cancelling` 当成终态。后端安全 `message` 不作为产品文案，只在折叠的
/// 技术详情里出现。阶段 token 只用于 Driver 定位与截图命名，不是第二套业务状态。

/// 阶段 token：`unchecked`/`checking`/`required`/`authenticating`/`verifying`/`closing`/
/// `verified`/`cancelling`/`cancelled`/`failed`。
String acpAuthPhaseToken(AcpAuthState state) => switch (state) {
  AcpAuthUnchecked() => 'unchecked',
  AcpAuthChecking() => 'checking',
  AcpAuthRequired() => 'required',
  AcpAuthAuthenticating() => 'authenticating',
  AcpAuthVerifying() => 'verifying',
  AcpAuthClosing() => 'closing',
  AcpAuthVerified() => 'verified',
  AcpAuthCancelling() => 'cancelling',
  AcpAuthCancelled() => 'cancelled',
  AcpAuthFailed() => 'failed',
};

/// 列表行的紧凑状态摘要：同时配图标与语气，状态不只依赖颜色。
String acpAuthRowLabel(AppLocalizations l10n, AcpAuthState state) =>
    switch (state) {
      AcpAuthUnchecked() => l10n.acpAuthRowUnchecked,
      AcpAuthChecking() => l10n.acpAuthRowChecking,
      AcpAuthRequired() => l10n.acpAuthRowRequired,
      AcpAuthAuthenticating() => l10n.acpAuthRowAuthenticating,
      AcpAuthVerifying() => l10n.acpAuthRowVerifying,
      AcpAuthClosing() => l10n.acpAuthRowClosing,
      AcpAuthVerified() => l10n.acpAuthRowVerified,
      AcpAuthCancelling() => l10n.acpAuthRowCancelling,
      AcpAuthCancelled() => l10n.acpAuthRowCancelled,
      AcpAuthFailed() => l10n.acpAuthRowFailed,
    };

/// 认证区的标题。
///
/// `required` 分支保留服务端实际宣告的方法事实：有 agent 方法、没有任何方法、只有
/// terminal 方法、只有未知方法是四种不同的可登录性结论。
String acpAuthTitle(AppLocalizations l10n, AcpAuthState state) =>
    switch (state) {
      AcpAuthUnchecked() => l10n.acpAuthRowUnchecked,
      AcpAuthChecking() => l10n.acpAuthChecking,
      AcpAuthRequired() => _requiredTitle(l10n, state),
      AcpAuthAuthenticating() => l10n.acpAuthAuthenticatingTitle,
      AcpAuthVerifying() => l10n.acpAuthVerifyingTitle,
      AcpAuthClosing() => l10n.acpAuthClosingTitle,
      AcpAuthVerified() => l10n.acpAuthVerifiedTitle,
      AcpAuthCancelling() => l10n.acpAuthCancelling,
      AcpAuthCancelled() => l10n.acpAuthRowCancelled,
      AcpAuthFailed() => l10n.acpAuthFailedTitle,
    };

/// 需要登录时的四种可登录性结论：只有第一种给出登录动作。
String _requiredTitle(AppLocalizations l10n, AcpAuthRequired state) {
  if (state.agentMethods.isNotEmpty) return l10n.acpAuthRequiredTitle;
  if (state.hasNoMethods) return l10n.acpAuthNoMethods;
  if (state.terminalOnly) return l10n.acpAuthTerminalOnly;
  return l10n.acpAuthUnsupportedOnly;
}

/// 认证区的正文：只使用 typed 事实；失败正文是 code + stage 的本地化摘要。
String acpAuthBody(AppLocalizations l10n, AcpAuthState state) {
  final serverHint = switch (state) {
    AcpAuthRequired(:final server) => _serverHint(l10n, server),
    AcpAuthVerified(:final server) => _serverHint(l10n, server),
    _ => '',
  };
  return switch (state) {
    AcpAuthUnchecked() => l10n.acpAuthUnchecked,
    AcpAuthChecking() => l10n.acpAuthChecking,
    AcpAuthRequired() => _requiredBody(l10n, state, serverHint),
    AcpAuthAuthenticating() => l10n.acpAuthAuthenticatingBody,
    AcpAuthVerifying() => l10n.acpAuthVerifyingTitle,
    // 收束说明保持本地化正文；失败摘要与后端原文分别在错误卡与技术详情里。
    AcpAuthClosing() => l10n.acpAuthClosingBody,
    AcpAuthVerified(:final checkedAt) => [
      if (serverHint.isNotEmpty) serverHint,
      l10n.acpAuthVerifiedAt(acpVerifiedAt(checkedAt)),
    ].join('\n'),
    AcpAuthCancelling() => l10n.acpAuthCancellingBody,
    AcpAuthCancelled() => l10n.acpAuthCancelledBody,
    AcpAuthFailed(:final failure) => acpAuthFailureSummary(l10n, failure),
  };
}

/// 需要登录的正文：可登录时说明动作与服务端身份，不可登录时说明具体原因。
String _requiredBody(
  AppLocalizations l10n,
  AcpAuthRequired state,
  String serverHint,
) {
  final reason = _requiredTitle(l10n, state);
  if (state.agentMethods.isNotEmpty) {
    return [
      l10n.acpAuthRequiredBody,
      if (serverHint.isNotEmpty) serverHint,
    ].join('\n');
  }
  return [reason, if (serverHint.isNotEmpty) serverHint].join('\n');
}

/// 服务端观察身份；对端未提供时不伪造名称或版本。
String _serverHint(AppLocalizations l10n, AcpServerInfo? server) =>
    server == null
    ? l10n.acpAuthServerUnknown
    : '${server.displayName} ${server.version}';

/// Unix 秒的紧凑本地时间（`M/d HH:mm`）。
///
/// 只表达观察时刻，不参与任何“凭据长期有效”的判断。
String acpVerifiedAt(int unixSeconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.month}/${value.day} $hour:$minute';
}
