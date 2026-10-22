import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../platform/external_url_launcher.dart';
import '../../shared/account_brand.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_acp_account_draft.dart';
import 'settings_common.dart';

/// ACP 接入的新建/编辑表单。
///
/// 只呈现接入需要的最少字段：名称、官方 server 程序路径与默认折叠的高级 argv。
/// 没有 API key、base URL、默认账号或模型目录控件——那些属于 Native 账号语义。
/// 主操作是“保存并连接”，取消保持次级；连接失败后的说明由调用方就地显示。
class AcpAccountEditor extends StatelessWidget {
  const AcpAccountEditor({
    super.key,
    required this.formKey,
    required this.draft,
    required this.saving,
    required this.error,
    required this.onCancel,
    required this.onSave,
    required this.onUpdate,
    required this.onPickProgram,
  });

  final GlobalKey<FormState> formKey;
  final AcpAccountDraft draft;
  final bool saving;

  /// 保存失败或“已保存但连接未完成”的就地说明；不再叠加 toast。
  final String? error;

  final VoidCallback onCancel;
  final VoidCallback onSave;
  final ValueChanged<AcpAccountDraft Function(AcpAccountDraft)> onUpdate;

  /// 打开原生文件选择并把结果写回草稿；失败说明由调用方就地显示。
  final Future<void> Function() onPickProgram;

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
                    const SizedBox(height: 12),
                    _ProgramField(
                      draft: draft,
                      saving: saving,
                      onPickProgram: onPickProgram,
                      onUpdate: onUpdate,
                      onSubmitted: saving ? null : onSave,
                    ),
                    if (template.installUrl.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // 官方安装说明：走既有安全外链入口，只接受 http(s)，不打开
                      // 进程输出里出现的任意 URL。
                      _InstallGuideLink(url: template.installUrl),
                    ],
                    const SizedBox(height: 12),
                    _AdvancedArgs(
                      draft: draft,
                      saving: saving,
                      onUpdate: onUpdate,
                    ),
                  ],
                ),
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
                  FilledButton.icon(
                    // 通用“添加账号”入口的保存语义：同一个主操作键覆盖两种账号类型。
                    key: StudioDriverKeys.accountSave,
                    icon: const Icon(Icons.link),
                    label: Text(l10n.acpAccountSaveAndConnect),
                    onPressed: saving ? null : onSave,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 官方安装说明入口：只显示并打开后端模板给出的安全 http(s) 地址。
class _InstallGuideLink extends ConsumerWidget {
  const _InstallGuideLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final safe = safeExternalWebUrl(url);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: url,
        child: TextButton.icon(
          key: StudioDriverKeys.acpAccountInstallOpen,
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(
            l10n.acpAccountInstallOpen,
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

class _ProgramField extends StatelessWidget {
  const _ProgramField({
    required this.draft,
    required this.saving,
    required this.onPickProgram,
    required this.onUpdate,
    required this.onSubmitted,
  });

  final AcpAccountDraft draft;
  final bool saving;

  /// 打开原生文件选择并把结果写回草稿；失败说明由调用方就地显示。
  final Future<void> Function() onPickProgram;
  final ValueChanged<AcpAccountDraft Function(AcpAccountDraft)> onUpdate;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsTextEdit(
      key: StudioDriverKeys.acpAccountProgram,
      inputKey: StudioDriverKeys.acpAccountProgramInput,
      label: l10n.acpAccountProgramLabel,
      value: draft.program,
      enabled: !saving,
      // 长路径换行显示，保持可读与可复制，而不是横向裁切。
      maxLines: 3,
      helperText: l10n.acpAccountProgramHint,
      onSubmitted: onSubmitted,
      suffixIcon: IconButton(
        key: StudioDriverKeys.acpAccountProgramBrowse,
        tooltip: l10n.acpAccountProgramBrowse,
        icon: const Icon(Icons.folder_open),
        onPressed: saving ? null : () => onPickProgram(),
      ),
      onChanged: (value) =>
          onUpdate((current) => current.copyWith(program: value)),
    );
  }
}

class _AdvancedArgs extends StatelessWidget {
  const _AdvancedArgs({
    required this.draft,
    required this.saving,
    required this.onUpdate,
  });

  final AcpAccountDraft draft;
  final bool saving;
  final ValueChanged<AcpAccountDraft Function(AcpAccountDraft)> onUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: StudioDriverKeys.acpAccountArgs,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: false,
        // 真实标题行：Driver 只点这一行；展开态从官方 `Expansible.controller.isExpanded`
        // 读取（既有 ToolProbe `observe` 的公开事实），不引入第二份展开状态。
        title: Text(
          l10n.acpAccountArgsTitle,
          key: StudioDriverKeys.acpAccountArgsHeader,
        ),
        subtitle: Text(
          l10n.acpAccountArgsHelp,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        // 添加按钮留在标题行：折叠时也能直接添加，行为与之前一致。
        trailing: TextButton.icon(
          key: StudioDriverKeys.acpAccountArgsAdd,
          icon: const Icon(Icons.add),
          label: Text(l10n.acpAccountArgsAdd),
          onPressed: saving
              ? null
              : () => onUpdate(
                  (current) => current.copyWith(args: [...current.args, '']),
                ),
        ),
        children: [
          Padding(
            key: StudioDriverKeys.acpAccountArgsBody,
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (draft.args.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.acpAccountArgsEmpty,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  for (var index = 0; index < draft.args.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SettingsTextEdit(
                              key: StudioDriverKeys.acpAccountArg(index),
                              inputKey: StudioDriverKeys.acpAccountArgInput(
                                index,
                              ),
                              label: 'argv[$index]',
                              value: draft.args[index],
                              enabled: !saving,
                              onChanged: (value) => onUpdate((current) {
                                final args = [...current.args];
                                args[index] = value;
                                return current.copyWith(args: args);
                              }),
                            ),
                          ),
                          IconButton(
                            key: StudioDriverKeys.acpAccountArgRemove(index),
                            tooltip: l10n.acpAccountArgsRemove,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: saving
                                ? null
                                : () => onUpdate((current) {
                                    final args = [...current.args];
                                    if (index >= args.length) return current;
                                    args.removeAt(index);
                                    return current.copyWith(args: args);
                                  }),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
