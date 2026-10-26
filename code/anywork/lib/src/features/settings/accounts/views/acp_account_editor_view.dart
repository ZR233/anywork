import 'package:anywork_client/acp.dart' show AcpInstallCancelled;
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../../../ui/branding/account_brand.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_pane.dart';
import '../state/acp_account_editor_state.dart';
import '../state/acp_account_save_state.dart';
import '../widgets/acp_install_preparation_panel.dart';

/// ACP 接入的新建/编辑表单。
///
/// 只呈现账号需要的字段：显示名，加上产品固定的受管服务器版本与准备动作。没有 API key、
/// base URL、模型目录、程序路径或 argv 控件——受管服务器由产品固定发行决定，客户端与用户
/// 都不选择 program/argv。
///
/// 主操作按 typed 阶段切换：安装未就绪时是“准备服务器”（失败可重试、取消后可重新开始），
/// 就绪后才是“保存并连接”。准备不创建账号，保存也不会撤销已完成的安装。已有账号的编辑只
/// 改显示名：不触发准备、不触发认证、不改连接身份。
class AcpAccountEditorView extends StatelessWidget {
  const AcpAccountEditorView({
    required this.state,
    required this.savePhase,
    required this.onCancel,
    required this.onPrepare,
    required this.onCancelPrepare,
    required this.onUsePrepared,
    required this.onName,
    required this.onOpenUrl,
    this.onSave,
    this.onRetryConnect,
    this.needsPreparation = false,
    this.error,
    super.key,
  });

  final AcpAccountEditorViewState state;

  /// 保存编排的 typed 阶段：区分保存中、已保存检查中、检查失败可重试与已连接。
  final AcpAccountSavePhase savePhase;

  /// 保存入口由调用方提供：账号写入属于配置领域，本视图不持有命令。
  final VoidCallback? onSave;

  /// 只重试连接检查的入口：只有“已保存且检查失败”时才可点，绝不重放保存。
  final VoidCallback? onRetryConnect;

  final VoidCallback onCancel;
  final VoidCallback onPrepare;
  final VoidCallback onCancelPrepare;
  final VoidCallback onUsePrepared;
  final ValueChanged<String> onName;

  /// 官方说明/条款入口的安全外链动作；只接受 http(s)。
  final ValueChanged<String> onOpenUrl;

  /// 已有账号的 canonical 回执明确“需要准备/安装不合格”：编辑表单也要给出显式准备动作，
  /// 不能只能靠新建表单。
  final bool needsPreparation;

  /// 保存失败或命令失败的就地说明；不再叠加 toast。
  final String? error;

  /// 配置写入在途（尚未结算）。
  bool get _saving => savePhase == AcpAccountSavePhase.saving;

  /// 表单仍处于草稿阶段：只有这时才能改名、准备与提交保存。
  bool get _drafting => savePhase == AcpAccountSavePhase.editing;

  /// 新建必须准备到 Ready 才能保存；编辑只改名字，不要求重新准备。
  bool get _canSave => _drafting && state.saveAdmitted && onSave != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final template = state.template;
    return Column(
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
                title: state.create
                    ? template.displayName
                    : (state.name.trim().isEmpty
                          ? template.displayName
                          : state.name.trim()),
                subtitle: l10n.acpAccountNoApiKeyHint,
              ),
              if (error case final message?) ...[
                const SizedBox(height: 12),
                SettingsInlineError(message: message),
              ],
              SettingsSection(
                title: l10n.settingsAccountConnectionTitle,
                children: [
                  SettingsFormField(
                    key: StudioDriverKeys.acpAccountName,
                    value: state.name,
                    label: l10n.settingsDisplayName,
                    // 账号已保存时名字已落在 canonical 配置里；此处只等连接结果。
                    enabled: _drafting,
                    onChanged: onName,
                  ),
                  if (template.termsUrl.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    // 官方条款与说明都只来自后端模板；为空时不渲染入口。
                    _PolicyLink(
                      key: StudioDriverKeys.acpAccountTermsOpen,
                      url: template.termsUrl,
                      label: l10n.acpAccountTermsOpen,
                      tooltip: l10n.acpAccountTermsTitle,
                      onOpen: onOpenUrl,
                    ),
                  ],
                ],
              ),
              AcpInstallPreparationPanel(
                template: template,
                state: state.install,
                prepared: state.prepared,
                availableElsewhere: state.availableElsewhere,
                admissionPending: state.admissionPending,
                cancelPending: state.cancelPending,
                preparePending: state.preparing,
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
                  onOpen: onOpenUrl,
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
                  // 只有配置写入在途时不能离开（写入不可撤回）；已保存/检查中仍可取消，
                  // 取消会把“已保存但未连接”的事实交回调用方，而不是假装什么都没发生。
                  onPressed: _saving ? null : onCancel,
                ),
                ..._primaryActions(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _primaryActions(BuildContext context) {
    final l10n = context.l10n;
    if (savePhase == AcpAccountSavePhase.savedChecking) {
      // 配置已保存、连接检查在途：显示进度，重试入口保持可见但禁用（不夸大、不空点）。
      return [
        FilledButton.icon(
          key: StudioDriverKeys.acpAccountCheck,
          icon: const Icon(Icons.sync),
          label: Text(l10n.acpAuthRecheck),
          onPressed: null,
        ),
        Text(
          l10n.acpAuthChecking,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    if (savePhase == AcpAccountSavePhase.savedCheckFailed) {
      // 配置已保存、连接检查失败：不再提交保存，只允许重新检查连接。
      return [
        FilledButton.icon(
          key: StudioDriverKeys.acpAccountCheck,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.acpAuthRecheck),
          onPressed: onRetryConnect,
        ),
      ];
    }
    if (savePhase != AcpAccountSavePhase.editing) {
      // 已连接：调用方正在离开表单，不再提供新的提交入口。
      return const [];
    }
    // 新建是“保存并连接”（保存后由调用方立即检查）；编辑只改名保存，不暗中发起检查。
    final saveLabel = state.create
        ? l10n.acpAccountSaveAndConnect
        : l10n.settingsSave;
    if (!state.create && needsPreparation && state.prepared == null) {
      // 缺安装：主操作是准备，改名保存仍可用但不再是主路径。
      return [
        FilledButton.icon(
          key: StudioDriverKeys.acpInstallPrepare,
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.acpInstallStart),
          onPressed: _prepareAdmitted ? onPrepare : null,
        ),
        FilledButton.icon(
          key: StudioDriverKeys.accountSave,
          icon: const Icon(Icons.link),
          label: Text(saveLabel),
          onPressed: _canSave ? onSave : null,
        ),
      ];
    }
    if (state.prepared != null || !state.create) {
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
    final failure = state.install.failure;
    final retryable = failure != null && failure.retryable;
    final cancelled = state.install is AcpInstallCancelled;
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
        onPressed: _prepareAdmitted ? onPrepare : null,
      ),
    ];
  }

  /// 准备动作准入：本表单 start 在途、阶段在途或平台不支持时如实禁用。
  bool get _prepareAdmitted =>
      _drafting && !state.prepareBlocked && state.canPrepareAutomatically;
}

/// 官方说明/条款入口：只显示并打开后端模板给出的安全 http(s) 地址。
///
/// 不安全或缺失的地址渲染成禁用态，不自行拼接厂商链接；打开动作由调用方提供，视图不读
/// provider。
class _PolicyLink extends StatelessWidget {
  const _PolicyLink({
    required this.url,
    required this.label,
    required this.tooltip,
    required this.onOpen,
    super.key,
  });

  final String url;
  final String label;
  final String tooltip;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final safe = safeExternalWebUrl(url);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: tooltip,
        child: TextButton.icon(
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(label),
          onPressed: safe == null ? null : () => onOpen(safe),
        ),
      ),
    );
  }
}
