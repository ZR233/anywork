import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:anywork_client/studio_client.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../platform/external_url_launcher.dart';
import '../../shared/account_brand.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_acp_account_draft.dart';
import 'settings_acp_server_preparation.dart';
import 'settings_common.dart';

/// ACP 接入的新建/编辑表单。
///
/// 只呈现账号需要的字段：显示名，加上固定的受管服务器版本与准备动作。没有 API
/// key、base URL、模型目录、程序路径或 argv 控件——受管服务器由产品固定发行决定，
/// 客户端与用户都不选择 program/argv。
///
/// 主操作按 typed 阶段切换：安装未就绪时是“准备 1.4.1 服务器”（失败可重试、取消
/// 后可重新开始），就绪后才是“保存并连接”。准备不创建账号，保存也不会撤销已完成
/// 的安装。已有账号的编辑只改显示名：不触发准备、不触发认证、不改连接身份。
class AcpAccountEditor extends StatelessWidget {
  const AcpAccountEditor({
    super.key,
    required this.formKey,
    required this.draft,
    required this.installState,
    required this.prepared,
    required this.availableElsewhere,
    this.needsPreparation = false,
    required this.saving,
    required this.preparePending,
    required this.admissionPending,
    required this.cancelPending,
    required this.error,
    required this.onCancel,
    required this.onSave,
    required this.onPrepare,
    required this.onCancelPrepare,
    required this.onUsePrepared,
    required this.onUpdate,
  });

  final GlobalKey<FormState> formKey;
  final AcpAccountDraft draft;

  /// 该 provider 的 canonical 准备状态。
  final AcpInstallStateView installState;

  /// 属于本草稿意图的就绪结果。
  final AcpInstalledServerView? prepared;

  /// 同 provider 已就绪但属于另一操作的结果（需显式认领）。
  final AcpInstalledServerView? availableElsewhere;

  /// 已有账号的 canonical 回执明确“需要准备/安装不合格”：编辑表单也要给出
  /// 显式准备动作，不能只能靠新建表单。
  final bool needsPreparation;

  final bool saving;

  /// 本表单的 start 请求仍在途（尚未拿到回执）。
  final bool preparePending;

  /// 回执已受理但 canonical 状态尚未给出 operation。
  final bool admissionPending;

  final bool cancelPending;

  /// 保存失败或“已保存但连接未完成”的就地说明；不再叠加 toast。
  final String? error;

  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onPrepare;
  final VoidCallback onCancelPrepare;
  final VoidCallback onUsePrepared;
  final ValueChanged<AcpAccountDraft Function(AcpAccountDraft)> onUpdate;

  /// 新建必须准备到 Ready 才能保存；编辑只改名字，不要求重新准备。
  bool get _canSave => !saving && (!draft.isCreate || prepared != null);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final template = draft.template;
    return Form(
      key: formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              key: StudioDriverKeys.accountEditorScroll,
              children: [
                SettingsHeader(
                  leading: AccountBrandMark(
                    iconKey: template.iconKey.isEmpty ? null : template.iconKey,
                    fallbackName: template.displayName,
                    size: 44,
                  ),
                  title: draft.isCreate
                      ? template.displayName
                      : (draft.name.trim().isEmpty
                            ? template.displayName
                            : draft.name.trim()),
                  subtitle: l10n.acpAccountNoApiKeyHint,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  SettingsInlineError(message: error!),
                ],
                SettingsSectionPanel(
                  title: l10n.settingsAccountConnectionTitle,
                  children: [
                    SettingsTextEdit(
                      key: StudioDriverKeys.acpAccountName,
                      label: l10n.settingsDisplayName,
                      value: draft.name,
                      enabled: !saving,
                      onChanged: (value) =>
                          onUpdate((current) => current.copyWith(name: value)),
                    ),
                    if (template.termsUrl.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      // 官方条款与说明都只来自后端模板；为空时不渲染入口。
                      _PolicyLink(
                        key: StudioDriverKeys.acpAccountTermsOpen,
                        url: template.termsUrl,
                        label: l10n.acpAccountTermsOpen,
                        tooltip: l10n.acpAccountTermsTitle,
                      ),
                    ],
                  ],
                ),
                AcpServerPreparationPanel(
                  template: template,
                  state: installState,
                  prepared: prepared,
                  availableElsewhere: availableElsewhere,
                  admissionPending: admissionPending,
                  cancelPending: cancelPending,
                  preparePending: preparePending,
                  onUsePrepared: onUsePrepared,
                  onCancel: onCancelPrepare,
                ),
                if (template.installUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // 官方安装说明：走既有安全外链入口，只接受 http(s)。
                  _PolicyLink(
                    key: StudioDriverKeys.acpAccountInstallOpen,
                    url: template.installUrl,
                    label: l10n.acpAccountInstallOpen,
                    tooltip: l10n.acpAccountInstallOpen,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    key: StudioDriverKeys.accountCancel,
                    icon: const Icon(Icons.close),
                    label: Text(l10n.settingsCancel),
                    onPressed: saving ? null : onCancel,
                  ),
                  ..._primaryActions(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _primaryActions(BuildContext context) {
    final l10n = context.l10n;
    // 新建是“保存并连接”（保存后立即检查）；编辑只改名保存，不暗中发起检查。
    final saveLabel = draft.isCreate
        ? l10n.acpAccountSaveAndConnect
        : l10n.settingsSave;
    if (!draft.isCreate && needsPreparation && prepared == null) {
      // 缺安装：主操作是准备（复用通用按键），改名保存仍可用但不再是主路径。
      final busy = installState.isBusy || preparePending;
      return [
        FilledButton.icon(
          key: StudioDriverKeys.acpInstallPrepare,
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.acpInstallStart),
          onPressed: busy || saving || !draft.canPrepareAutomatically
              ? null
              : onPrepare,
        ),
        FilledButton.icon(
          key: StudioDriverKeys.accountSave,
          icon: const Icon(Icons.link),
          label: Text(saveLabel),
          onPressed: _canSave ? onSave : null,
        ),
      ];
    }
    if (prepared != null || !draft.isCreate) {
      return [
        FilledButton.icon(
          // 通用“添加账号”入口的保存语义：同一个主操作键覆盖两种账号类型。
          key: StudioDriverKeys.accountSave,
          icon: const Icon(Icons.link),
          label: Text(saveLabel),
          onPressed: _canSave ? onSave : null,
        ),
      ];
    }
    final failure = installState.failure;
    final retryable = failure != null && failure.retryable;
    final cancelled = installState is AcpInstallCancelledState;
    final busy = installState.isBusy || preparePending;
    return [
      FilledButton.icon(
        key: StudioDriverKeys.acpInstallPrepare,
        icon: Icon(retryable ? Icons.refresh : Icons.download_outlined),
        label: Text(
          retryable
              ? l10n.acpInstallFailureRetry
              : cancelled
              ? l10n.acpInstallRestart
              : l10n.acpInstallStart,
        ),
        // 阶段主操作保持唯一：准备中禁用，取消入口在准备面板里独立可达。
        onPressed: busy || saving || !draft.canPrepareAutomatically
            ? null
            : onPrepare,
      ),
    ];
  }
}

/// 官方说明/条款入口：只显示并打开后端模板给出的安全 http(s) 地址。
///
/// 不安全或缺失的地址渲染成禁用态，不自行拼接厂商链接。
class _PolicyLink extends ConsumerWidget {
  const _PolicyLink({
    super.key,
    required this.url,
    required this.label,
    required this.tooltip,
  });

  final String url;
  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safe = safeExternalWebUrl(url);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: tooltip,
        child: TextButton.icon(
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(
            label,
            style: context.text.bodySmall?.copyWith(
              color: safe == null
                  ? context.colors.onSurfaceVariant
                  : context.colors.primary,
            ),
          ),
          onPressed: safe == null
              ? null
              : () => ref.read(externalUrlLauncherProvider)(safe),
        ),
      ),
    );
  }
}
