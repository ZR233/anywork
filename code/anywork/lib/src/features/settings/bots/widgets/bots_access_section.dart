import 'package:anywork_client/bots.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_layout.dart';

/// Inbound authorization facts of one bot, in the same order and grouping as the
/// overview page: one collapsed "机器人授权" block holding "可信用户" (trusted
/// open ids plus pending pairing requests) and "授权群" (trusted chat ids).
///
/// Approving, revoking and clearing go through explicit callbacks; nothing here
/// decides trust, and a pending pairing request never grants itself.
class BotsAccessSection extends StatelessWidget {
  const BotsAccessSection({
    required this.bot,
    required this.editable,
    required this.onTrustUser,
    required this.onClearPairing,
    required this.onTrustChat,
    super.key,
  });

  final BotSnapshot bot;
  final bool editable;
  final void Function(String openId, bool trusted) onTrustUser;
  final ValueChanged<String> onClearPairing;
  final void Function(String chatId, bool trusted) onTrustChat;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const PageStorageKey<String>('bot-access-settings'),
    leading: const Icon(Icons.admin_panel_settings_outlined),
    title: Text(context.l10n.botsAccessTitle),
    subtitle: Text(context.l10n.botsAccessHint),
    initiallyExpanded: bot.pairing.isNotEmpty,
    children: [
      SettingsSectionPanel(
        title: context.l10n.settingsBotsTrustedUsers,
        children: [
          for (final openId in bot.trustedOpenIds)
            ListTile(
              key: StudioDriverKeys.botsApproveUser(openId),
              title: Text(openId, overflow: TextOverflow.ellipsis),
              trailing: TextButton(
                onPressed: editable ? () => onTrustUser(openId, false) : null,
                child: Text(context.l10n.settingsBotsRevoke),
              ),
            ),
          for (final pairing in bot.pairing)
            ListTile(
              title: Text(
                pairing.displayName ?? pairing.openId,
                overflow: TextOverflow.ellipsis,
              ),
              // 两个动作换行排布在副标题区，窄窗口下不挤占 trailing，也不会
              // 遮挡较长的显示名。
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.settingsBotsPairingHint),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonal(
                        key: StudioDriverKeys.botsApproveUser(pairing.openId),
                        onPressed: editable
                            ? () => onTrustUser(pairing.openId, true)
                            : null,
                        child: Text(context.l10n.settingsBotsApprove),
                      ),
                      TextButton(
                        key: StudioDriverKeys.botsClearPairing(pairing.openId),
                        onPressed: editable
                            ? () => onClearPairing(pairing.openId)
                            : null,
                        child: Text(context.l10n.settingsBotsClearPairing),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.settingsBotsClearPairingHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (bot.trustedOpenIds.isEmpty && bot.pairing.isEmpty)
            Text(context.l10n.settingsBotsNoTrustedUsers),
        ],
      ),
      SettingsSectionPanel(
        title: context.l10n.settingsBotsTrustedChats,
        children: [
          for (final chatId in bot.trustedChatIds)
            ListTile(
              title: Text(chatId, overflow: TextOverflow.ellipsis),
              trailing: TextButton(
                onPressed: editable ? () => onTrustChat(chatId, false) : null,
                child: Text(context.l10n.settingsBotsRevoke),
              ),
            ),
          // 群默认关闭；授权群来自会话列表的显式操作，不在配置页手填会话 ID。
          if (bot.trustedChatIds.isEmpty)
            Text(context.l10n.settingsBotsNoTrustedChats),
        ],
      ),
    ],
  );
}
