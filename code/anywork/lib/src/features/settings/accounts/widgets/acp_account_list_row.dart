import 'package:anywork_client/configuration.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/badges/studio_badges.dart';
import '../../../../ui/branding/account_brand.dart';
import 'acp_auth_presentation.dart';

/// ACP 接入行：品牌、名称、接入协议与认证状态摘要。
///
/// 状态同时用图标与文本表达，不只依赖颜色。列表行只显示 canonical 认证观察的摘要与该
/// 目标行自己的命令失败通知；后端安全原文留在详情页折叠诊断里。
class AcpAccountListRow extends StatelessWidget {
  const AcpAccountListRow({
    required this.entry,
    required this.selected,
    required this.onOpen,
    required this.onEdit,
    this.noticeSummary,
    this.onRemove,
    super.key,
  });

  final AcpAccountEntryView entry;
  final bool selected;

  /// 该行自己的命令失败摘要（已本地化）；安全原文只在详情页折叠诊断里。
  final String? noticeSummary;

  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final account = entry.account;
    final (icon, label, tone) = acpAuthBadge(l10n, entry.auth);
    return Material(
      key: StudioDriverKeys.acpAccountRow(account.accountId),
      color: selected ? context.colors.surfaceContainer : Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountBrandMark(
                iconKey: entry.template?.iconKey,
                fallbackName: account.name,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: context.colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StudioPill(
                          icon: Icons.hub_outlined,
                          label: l10n.acpAccountProviderChip,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: tone == StudioTone.error
                              ? context.colors.error
                              : context.colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (noticeSummary case final noticeSummary?) ...[
                      const SizedBox(height: 6),
                      Row(
                        key: StudioDriverKeys.acpAccountNotice(
                          account.accountId,
                        ),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 14,
                            color: context.colors.error,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              noticeSummary,
                              style: context.text.bodySmall?.copyWith(
                                color: context.colors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                    case 'remove':
                      onRemove?.call();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text(l10n.settingsEdit),
                  ),
                  if (onRemove != null)
                    PopupMenuItem<String>(
                      value: 'remove',
                      child: Text(l10n.settingsDeleteAccount),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
