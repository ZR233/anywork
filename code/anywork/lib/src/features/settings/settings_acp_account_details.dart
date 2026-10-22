import 'package:flutter/material.dart';

import 'package:anywork_client/studio_client.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/account_brand.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_acp_auth_panel.dart';
import 'settings_common.dart';

/// 命令失败通知的意图类别。
///
/// 只有 [authentication] 的通知可以被后续同账号认证进展/终态取代；
/// [configuration] / [remove] 属于配置命令错误，必须保留到明确重试成功、目标移除
/// 或对应连接身份失效——**不会**因为该账号已 Verified 而消失。
enum AcpCommandNoticeKind { authentication, configuration, remove }

/// 命令层就地失败的通知：本地化摘要为主，后端安全原文只作次级技术详情。
///
/// 通知**绑定目标接入与连接身份**：列表里的删除失败只会出现在目标行/目标详情，
/// 不会挂到另一个被选中的账号上；[operationId] 记录拒绝发生时该账号 canonical 的
/// 在途操作，用于在后续进展/终态取代旧拒绝后不再呈现。
///
/// [detail] 是后端给出的安全 message（不是 raw stderr），可以为空；它不是产品文案，
/// 因此不参与摘要本地化，只在折叠的技术详情里呈现。
class AcpCommandNotice {
  const AcpCommandNotice({
    required this.kind,
    required this.summary,
    this.detail,
    required this.accountId,
    required this.connectionRevision,
    this.operationId,
  });

  final AcpCommandNoticeKind kind;
  final String summary;
  final String? detail;
  final String accountId;

  /// 发起该命令时的连接身份（在 await 之前冻结）；identity 变化即为过时。
  final int connectionRevision;
  final String? operationId;
}

/// 通知是否应呈现（账号 + 连接身份 + 意图类别 + 认证在途操作）。
///
/// - 连接身份变化 → 过时（任何类别）；
/// - [AcpCommandNoticeKind.authentication]：只在同一在途操作仍当前、或尚未进入新尝试/成功时显示；
/// - [AcpCommandNoticeKind.configuration] / [AcpCommandNoticeKind.remove]：与认证进展无关，
///   **不因该账号已 Verified 而隐藏**，只由明确重试成功、目标移除或身份失效清除。
AcpCommandNotice? visibleAcpCommandNotice(
  AcpCommandNotice? notice,
  AcpAccountEntryView entry,
) {
  if (notice == null) return null;
  if (notice.accountId != entry.id) return null;
  if (notice.connectionRevision != entry.account.connectionRevision) {
    return null;
  }
  if (notice.kind != AcpCommandNoticeKind.authentication) {
    return notice;
  }
  final operationId = notice.operationId;
  if (operationId != null) {
    return entry.auth.operationId == operationId ? notice : null;
  }
  if (entry.auth.isBusy) return null;
  return entry.auth is AcpVerifiedState ? null : notice;
}

/// 认证命令的 typed `busy` 是否只是**重复输入**。
///
/// 三类事实必须同时成立才吞掉这次失败：后端给的是 `busy`、响应时该接入仍是发起
/// 请求时的连接身份、且该接入 canonical 已有在途操作——进度由 canonical 状态承接，
/// 不需要红色失败。当前连接身份已前进（旧请求的失败不能算重复输入）、目标不是该
/// 账号、非 `busy` 或没有在途操作都必须照常呈现。
bool isAcpAuthDuplicateWhileInFlight({
  required Object error,
  required String accountId,
  required int requestConnectionRevision,
  required AcpAccountEntryView? entry,
}) {
  if (error is! StudioFailure || error.code != StudioFailureCode.busy) {
    return false;
  }
  if (entry == null || entry.id != accountId) return false;
  if (entry.account.connectionRevision != requestConnectionRevision) {
    return false;
  }
  return entry.auth.isBusy;
}

/// 已保存 ACP 接入的详情：身份、认证状态区与折叠的连接信息。
///
/// 认证状态区是唯一焦点：状态与主操作在前，程序路径/argv 等连接技术信息收进默认
/// 折叠的官方 `ExpansionTile`（可复制、长行换行）。删除接入明确说明不等于注销；
/// 本版本不提供聊天或模型选择控件。
class AcpAccountDetails extends StatelessWidget {
  const AcpAccountDetails({
    super.key,
    required this.entry,
    required this.busy,
    required this.cancelBusy,
    required this.authNotice,
    required this.onBack,
    required this.onEdit,
    required this.onRemove,
    required this.onCheck,
    required this.onCancel,
    required this.onLogin,
  });

  final AcpAccountEntryView entry;

  /// start/check/login 命令在途（尚未收到 canonical 回应）。
  final bool busy;

  /// 取消命令自身在途；取消不因 [busy] 被禁用。
  final bool cancelBusy;

  /// 命令层的就地失败通知（例如保存冲突或取消时机已过）。
  final AcpCommandNotice? authNotice;

  final VoidCallback onBack;
  final VoidCallback onEdit;
  final Future<void> Function() onRemove;
  final Future<void> Function() onCheck;
  final Future<void> Function() onCancel;
  final Future<void> Function(String methodId) onLogin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final account = entry.account;
    final notice = authNotice;
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
          if (notice != null) ...[
            SettingsInlineError(
              // 与列表行同一键位家族：断言/诊断只认目标账号是否显示通知。
              key: StudioDriverKeys.acpAccountNotice(account.accountId),
              message: notice.summary,
            ),
            if (notice.detail case final detail?) ...[
              const SizedBox(height: 4),
              // 后端安全原文默认折叠在技术详情里，不占据主信息位。
              _NoticeDetail(detail: detail),
            ],
            const SizedBox(height: 10),
          ],
          // 认证状态与主操作先出现：技术连接信息默认折叠在下方。
          AcpAuthPanel(
            state: entry.auth,
            busy: busy,
            cancelBusy: cancelBusy,
            onCheck: onCheck,
            onCancel: onCancel,
            onLogin: onLogin,
            onDone: onBack,
            onEditConfig: onEdit,
          ),
          const SizedBox(height: 12),
          _ConnectionInfo(account: account, template: entry.template),
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

/// 连接技术信息：官方 `ExpansionTile` 默认折叠，保留品牌标识、provider 与可复制的
/// 程序路径/argv；展开态是官方组件自己的事实，不自造第二份状态。
class _ConnectionInfo extends StatelessWidget {
  const _ConnectionInfo({required this.account, required this.template});

  final AcpAccountSettingsView account;
  final AcpAccountTemplateView? template;

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
            StudioPill(icon: Icons.terminal, label: account.provider.wire),
          ],
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              '${l10n.acpAccountProviderLabel}: ${account.provider.wire}',
              style: secondary,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              '${l10n.acpAccountProgramLabel}: ${account.program}',
              style: secondary,
            ),
          ),
          if (account.args.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                '${l10n.acpAccountArgsTitle}: ${account.args.join(' ')}',
                style: secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
