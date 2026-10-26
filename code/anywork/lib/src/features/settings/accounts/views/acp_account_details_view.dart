import 'package:anywork_client/acp.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/badges/studio_badges.dart';
import '../../../../ui/branding/account_brand.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_layout.dart';
import '../widgets/acp_auth_panel.dart';

/// 已保存 ACP 接入的详情：身份、认证状态区与折叠的连接信息。
///
/// 认证状态区是唯一焦点：状态与主操作在前，程序路径/argv 等连接技术信息收进默认折叠的
/// 官方 `ExpansionTile`（可复制）。删除接入明确说明不等于注销；本版本不提供聊天或模型
/// 选择控件。
class AcpAccountDetailsView extends StatelessWidget {
  const AcpAccountDetailsView({
    required this.account,
    required this.auth,
    required this.busy,
    required this.cancelBusy,
    required this.onBack,
    required this.onEdit,
    required this.onRemove,
    required this.onCheck,
    required this.onCancel,
    required this.onLogin,
    required this.onRetry,
    this.template,
    this.errors = const [],
    this.noticeSummary,
    this.noticeDetail,
    super.key,
  });

  final AcpAccountSettings account;

  /// canonical 认证观察里与账号身份 + 连接身份同时匹配的条目。
  final AcpAuthState auth;

  /// 目录里仍可解析的模板；目录未加载时为 null，据此省略品牌与安装说明。
  final AcpAccountTemplate? template;

  /// start/check/login 命令在途（尚未收到 canonical 回应）。
  final bool busy;

  /// 取消命令自身在途；取消不因 [busy] 被禁用。
  final bool cancelBusy;

  /// 命令层的就地失败摘要（已本地化，例如保存冲突或取消时机已过）。
  final String? noticeSummary;

  /// 该失败的后端安全原文；只作折叠的技术详情，不占据主信息位。
  final String? noticeDetail;

  final VoidCallback onBack;
  final VoidCallback onEdit;
  final Future<void> Function() onRemove;
  final Future<void> Function() onCheck;
  final Future<void> Function() onCancel;
  final Future<void> Function(String methodId) onLogin;

  /// 观察/命令证据失败的本地化说明；命令拒绝另由 [noticeSummary] 表达。
  final List<String> errors;

  /// 显式重连观察；不重放任何已受理命令。
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final secondary = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return SingleChildScrollView(
      key: StudioDriverKeys.acpAccountDetail(account.accountId),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
            leading: IconButton(
              key: StudioDriverKeys.acpAccountBack,
              tooltip: l10n.settingsBack,
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
            title: account.name,
            // 产品短摘要随当前 locale；后端 catalog 描述不作界面文案。
            subtitle: l10n.acpAccountDetailsSummary,
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: StudioDriverKeys.accountEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.settingsEdit),
                  onPressed: busy ? null : onEdit,
                ),
                OutlinedButton.icon(
                  key: StudioDriverKeys.acpAccountRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.settingsDeleteAccount),
                  onPressed: busy ? null : () => onRemove(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (errors.isNotEmpty) ...[
            SettingsInlineError(message: errors.join('\n')),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onRetry(),
                child: Text(l10n.runtimeFatalRetry),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (noticeSummary case final noticeSummary?) ...[
            SettingsInlineError(
              // 与列表行同一键位家族：断言/诊断只认目标账号是否显示通知。
              key: StudioDriverKeys.acpAccountNotice(account.accountId),
              message: noticeSummary,
            ),
            if (noticeDetail case final detail?) ...[
              const SizedBox(height: 4),
              // 后端安全原文默认折叠在技术详情里，不占据主信息位。
              _NoticeDetail(detail: detail),
            ],
            const SizedBox(height: 10),
          ],
          // 认证状态与主操作先出现：技术连接信息默认折叠在下方。
          AcpAuthPanel(
            state: auth,
            busy: busy,
            cancelBusy: cancelBusy,
            onCheck: onCheck,
            onCancel: onCancel,
            onLogin: onLogin,
            onDone: onBack,
            onEditConfig: onEdit,
          ),
          const SizedBox(height: 12),
          _ConnectionInfo(account: account, template: template),
          const SizedBox(height: 8),
          Text(l10n.acpAccountRemoveNotLogout, style: secondary),
        ],
      ),
    );
  }
}

/// 命令失败的安全原文：官方 `ExpansionTile` 默认折叠，可复制。
class _NoticeDetail extends StatelessWidget {
  const _NoticeDetail({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final secondary = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: StudioDriverKeys.acpAccountNoticeDetail,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(l10n.acpAuthDiagnostics, style: secondary),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(detail, style: secondary),
          ),
        ],
      ),
    );
  }
}

/// 连接技术信息：官方 `ExpansionTile` 默认折叠，保留品牌标识与 provider 身份。
///
/// 受管 program/argv 属于产品固定发行与安装事实，不是账号配置，因此这里只呈现接入身份；
/// 展开态是官方组件自己的事实，不自造第二份状态。
class _ConnectionInfo extends StatelessWidget {
  const _ConnectionInfo({required this.account, required this.template});

  final AcpAccountSettings account;
  final AcpAccountTemplate? template;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final secondary = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: StudioDriverKeys.acpAccountConnectionInfo,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Row(
          children: [
            AccountBrandMark(
              iconKey: template?.iconKey,
              fallbackName: account.name,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.acpAccountConnectionInfoTitle)),
            StudioPill(icon: Icons.terminal, label: account.provider.name),
          ],
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              '${l10n.acpAccountProviderLabel}: ${account.provider.name}',
              style: secondary,
            ),
          ),
        ],
      ),
    );
  }
}
