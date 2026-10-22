import 'package:flutter/material.dart';

import 'package:anywork_client/studio_client.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/account_brand.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';

/// 统一“添加账号”入口的模板选择器。
///
/// 选项来自两个 typed 目录：Native 模型账号模板与 ACP 接入模板。选择结果以 sealed
/// [AccountTemplateChoice] 返回，调用方按分支重建对应草稿，绝不按模板 ID 或显示名猜协议。
Future<AccountTemplateChoice?> showAccountTemplatePicker(
  BuildContext context, {
  required List<AccountTemplateChoice> templates,
}) {
  return showDialog<AccountTemplateChoice>(
    context: context,
    builder: (context) => _AccountTemplatePicker(templates: templates),
  );
}

class _AccountTemplatePicker extends StatefulWidget {
  const _AccountTemplatePicker({required this.templates});

  final List<AccountTemplateChoice> templates;

  @override
  State<_AccountTemplatePicker> createState() => _AccountTemplatePickerState();
}

class _AccountTemplatePickerState extends State<_AccountTemplatePicker> {
  /// 列表自己拥有滚动控制器：滚动条与列表共用同一真实 position。
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final acp = widget.templates
        .where((choice) => choice.isAcp)
        .toList(growable: false);
    final native = widget.templates
        .where((choice) => !choice.isAcp)
        .toList(growable: false);
    // `AlertDialog` 用 intrinsic 宽度测量内容，惰性列表必须拿到**确定尺寸**才能参与
    // intrinsic 计算（shrink-wrapping viewport 不支持 intrinsic，见 Flutter 文档）。
    // 因此这里给宽度与高度都具体值：窄窗口由父约束 enforce 收窄（不会溢出），高度按
    // 当前视口夹取，内容超出时列表自己滚动，固定操作区（取消）始终可达。
    final viewport = MediaQuery.sizeOf(context);
    final contentHeight = (viewport.height * 0.6)
        .clamp(220.0, 480.0)
        .toDouble();
    return AlertDialog(
      key: StudioDriverKeys.accountTemplatePicker,
      title: Text(l10n.acpAccountPickerTitle),
      content: SizedBox(
        width: 460,
        height: contentHeight,
        child: Scrollbar(
          controller: _scrollController,
          // 常显滚动条：内容超出视口时必须给出明确的滚动提示。
          thumbVisibility: true,
          child: ListView(
            key: StudioDriverKeys.accountTemplateList,
            controller: _scrollController,
            padding: EdgeInsets.zero,
            children: [
              // ACP 组前置：常规桌面窗口首屏即可发现 Antigravity，不被完整的
              // Native 长列表推到视口之外；Native 组内顺序保持不变。
              if (acp.isNotEmpty) ...[
                SettingsFieldLabel(label: l10n.acpAccountPickerAcpGroup),
                const SizedBox(height: 6),
                for (final choice in acp) _option(context, choice),
              ],
              if (native.isNotEmpty) ...[
                if (acp.isNotEmpty) const SizedBox(height: 12),
                SettingsFieldLabel(label: l10n.acpAccountPickerNativeGroup),
                const SizedBox(height: 6),
                for (final choice in native) _option(context, choice),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: StudioDriverKeys.accountCancel,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.settingsCancel),
        ),
      ],
    );
  }

  Widget _option(BuildContext context, AccountTemplateChoice choice) {
    final l10n = context.l10n;
    // 选项身份来自 typed 模板：Native 用模板 id，ACP 用 provider wire 值。
    final token = switch (choice) {
      NativeAccountTemplateChoice(:final template) => template.id,
      AcpAccountTemplateChoice(:final template) =>
        'acp-${template.provider.wire}',
    };
    final description = choice.isAcp
        ? l10n.acpAccountNoApiKeyHint
        : choice.description;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: StudioDriverKeys.accountTemplateOption(token),
          onTap: () => Navigator.of(context).pop(choice),
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccountBrandMark(
                  iconKey: choice.iconKey,
                  fallbackName: choice.displayName,
                  size: 34,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        choice.displayName,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (choice.isAcp)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: StudioPill(label: l10n.acpAccountProviderChip),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
