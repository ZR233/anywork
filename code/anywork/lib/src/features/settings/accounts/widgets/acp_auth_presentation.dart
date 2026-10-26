import 'package:anywork_client/acp.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../state/acp_auth_labels.dart';

/// 认证状态的图标与语气映射：状态永远同时用图标 + 文本表达，不只依赖颜色。
///
/// 这里是 UI 侧唯一一份映射，列表行、详情页与认证区共用；业务结论仍只来自 canonical
/// [AcpAuthState]，不从本地标志合成。

IconData acpAuthIcon(AcpAuthState state) => switch (state) {
  AcpAuthUnchecked() => Icons.link_off,
  AcpAuthChecking() => Icons.sync,
  AcpAuthRequired() => Icons.lock_outline,
  AcpAuthAuthenticating() => Icons.login,
  AcpAuthVerifying() => Icons.verified_outlined,
  AcpAuthClosing() => Icons.hourglass_bottom,
  AcpAuthVerified() => Icons.check_circle_outline,
  AcpAuthCancelling() => Icons.stop_circle_outlined,
  AcpAuthCancelled() => Icons.cancel_outlined,
  AcpAuthFailed() => Icons.error_outline,
};

/// 列表行的紧凑语气：`required`/`cancelling` 需要用户注意，`verified` 才是成功。
StudioTone acpAuthRowTone(AcpAuthState state) => switch (state) {
  AcpAuthVerified() => StudioTone.success,
  AcpAuthFailed() => StudioTone.error,
  AcpAuthRequired() || AcpAuthCancelling() => StudioTone.warning,
  AcpAuthChecking() ||
  AcpAuthAuthenticating() ||
  AcpAuthVerifying() ||
  AcpAuthClosing() => StudioTone.brand,
  AcpAuthUnchecked() || AcpAuthCancelled() => StudioTone.neutral,
};

/// 认证区提示卡的语气。
StudioNoticeTone acpAuthNoticeTone(AcpAuthState state) => switch (state) {
  AcpAuthVerified() => StudioNoticeTone.success,
  AcpAuthFailed() => StudioNoticeTone.danger,
  AcpAuthRequired() || AcpAuthCancelled() => StudioNoticeTone.warning,
  AcpAuthChecking() ||
  AcpAuthAuthenticating() ||
  AcpAuthVerifying() ||
  AcpAuthClosing() ||
  AcpAuthCancelling() => StudioNoticeTone.info,
  AcpAuthUnchecked() => StudioNoticeTone.neutral,
};

/// 列表行的状态徽标三元组：图标、本地化文案与语气。
(IconData, String, StudioTone) acpAuthBadge(
  AppLocalizations l10n,
  AcpAuthState state,
) => (acpAuthIcon(state), acpAuthRowLabel(l10n, state), acpAuthRowTone(state));
