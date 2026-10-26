import 'package:anywork_client/bots.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_layout.dart';
import '../widgets/bot_labels.dart';

/// Recent platform conversations of one bot, in the native page order.
///
/// The row itself opens the chat; the row menu holds the platform tools entry,
/// the group authorization action and the explicit local session creation. No
/// action here decides trust or opens anything by itself.
class BotsConversationsView extends StatelessWidget {
  const BotsConversationsView({
    required this.page,
    required this.loading,
    required this.error,
    required this.busy,
    required this.trustedChatIds,
    required this.selectedChatId,
    required this.onRefresh,
    required this.onNext,
    required this.onOpenConversation,
    required this.onOpenPlatformTools,
    required this.onTrustChat,
    required this.onCreateThread,
    super.key,
  });

  final BotConversationPage? page;
  final bool loading;
  final String? error;
  final bool busy;
  final List<String> trustedChatIds;
  final String? selectedChatId;
  final VoidCallback onRefresh;
  final VoidCallback onNext;
  final ValueChanged<BotConversation> onOpenConversation;
  final ValueChanged<String> onOpenPlatformTools;
  final void Function(String chatId, bool trusted) onTrustChat;
  final ValueChanged<BotConversation> onCreateThread;

  @override
  Widget build(BuildContext context) => SettingsSectionPanel(
    title: context.l10n.settingsBotsConversations,
    trailing: TextButton(
      key: StudioDriverKeys.botsRefreshConversations,
      onPressed: busy ? null : onRefresh,
      child: Text(context.l10n.settingsBotsRefreshConversations),
    ),
    children: [
      if (error case final message?) SettingsInlineError(message: message),
      if (loading) const LinearProgressIndicator(),
      for (final conversation
          in page?.conversations ?? const <BotConversation>[])
        ListTile(
          key: StudioDriverKeys.botsConversation(conversation.chatId),
          selected: conversation.chatId == selectedChatId,
          title: Text(
            conversation.name ??
                botConversationSourceLabel(context, conversation),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: conversation.name == null
              ? null
              : Text(botConversationSourceLabel(context, conversation)),
          onTap: () => onOpenConversation(conversation),
          trailing: PopupMenuButton<String>(
            key: StudioDriverKeys.botsConversationActions(conversation.chatId),
            enabled: !busy,
            onSelected: (action) {
              switch (action) {
                case 'platform':
                  onOpenPlatformTools(conversation.chatId);
                case 'new':
                  onCreateThread(conversation);
                case 'trust':
                  onTrustChat(conversation.chatId, true);
                case 'revoke':
                  onTrustChat(conversation.chatId, false);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'platform',
                child: Text(context.l10n.botsPlatformTools),
              ),
              if (conversation.kind == BotConversationKind.group)
                PopupMenuItem(
                  value: trustedChatIds.contains(conversation.chatId)
                      ? 'revoke'
                      : 'trust',
                  child: Text(
                    trustedChatIds.contains(conversation.chatId)
                        ? context.l10n.settingsBotsRevoke
                        : context.l10n.settingsBotsApproveGroup,
                  ),
                ),
              PopupMenuItem(
                value: 'new',
                child: Text(context.l10n.settingsBotsNewThread),
              ),
            ],
          ),
        ),
      if (page?.nextCursor != null)
        TextButton(
          key: StudioDriverKeys.botsNextConversations,
          onPressed: busy || loading ? null : onNext,
          child: Text(context.l10n.settingsBotsNextPage),
        ),
    ],
  );
}
