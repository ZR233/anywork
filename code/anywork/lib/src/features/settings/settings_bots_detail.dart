part of 'settings_bots_tab.dart';

class _BotDetail extends StatelessWidget {
  const _BotDetail({
    required this.bot,
    this.platformOnly = false,
    required this.model,
    required this.onOpenConversation,
    required this.view,
    required this.canOpenFeishu,
    required this.selectedChatId,
    required this.sendController,
    required this.busy,
    required this.onSelectChat,
    required this.onEnabled,
    required this.onRetry,
    required this.onTools,
    required this.onTrustUser,
    required this.onClearPairingRequest,
    required this.onTrustChat,
    required this.onLoadConversations,
    required this.onCreateThread,
    required this.onSend,
    required this.onEdit,
    required this.onLoadMessages,
    required this.onDraftChanged,
    required this.onOpenConsole,
    required this.onOpenBot,
    required this.onOpenBotBrowser,
  });

  final BotSnapshot bot;
  final bool platformOnly;
  final Widget model;
  final ValueChanged<BotConversation> onOpenConversation;
  final SettingsBotsView view;
  final bool canOpenFeishu;
  final String? selectedChatId;
  final TextEditingController sendController;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<String> onDraftChanged;
  final ValueChanged<String> onSelectChat;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onRetry;
  final ValueChanged<bool> onTools;
  final void Function(String openId, bool trusted) onTrustUser;

  /// 清理单条本地配对请求。它只清本地请求，不改变该用户当前信任值，
  /// 也不表示授权远程执行或重放旧消息。
  final void Function(String openId) onClearPairingRequest;
  final void Function(String chatId, bool trusted) onTrustChat;
  final void Function(String? cursor) onLoadConversations;
  final void Function(String? cursor) onLoadMessages;
  final ValueChanged<BotConversation> onCreateThread;
  final VoidCallback onSend;
  final VoidCallback onOpenConsole;
  final VoidCallback onOpenBot;
  final VoidCallback onOpenBotBrowser;

  @override
  Widget build(BuildContext context) {
    final send = view.sends.latestFor(bot.id, selectedChatId ?? '');
    final conversationPage = view.queries.selectedConversationBotId == bot.id
        ? view.queries.conversationPage
        : null;
    final messagePage =
        view.queries.selectedMessageBotId == bot.id &&
            view.queries.selectedChatId == selectedChatId
        ? view.queries.messagePage
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!platformOnly) ...[
          Row(
            children: [
              Icon(
                bot.connection is BotConnectionConnected
                    ? Icons.check_circle_outline
                    : Icons.circle_outlined,
                size: 18,
                color: bot.connection is BotConnectionConnected
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_botConnectionLabel(context, bot.connection)),
              ),
              Switch(
                key: StudioDriverKeys.botsEnabled,
                value: bot.enabled,
                onChanged: busy ? null : onEnabled,
              ),
            ],
          ),
          if (bot.connection case BotConnectionFailed(
            :final message,
            :final platformCode,
          )) ...[
            SettingsInlineError(
              message: platformCode == '21001'
                  ? context.l10n.settingsBotsPolicyDenied
                  : message,
            ),
            if (platformCode != null)
              Text(context.l10n.settingsBotsPlatformCode(platformCode)),
            if (platformCode == '21001') ...[
              const SizedBox(height: 8),
              Text(context.l10n.settingsBotsPolicyDeniedHint),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenConsole,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(context.l10n.settingsBotsOpenConsole),
                ),
              ),
            ],
          ],
          // 已发布的机器人安全诊断（如配对清理未完成）单独呈现，不被连接状态
          // 或连接失败覆盖，也不据此推断本地业务动作。
          if (bot.diagnostic case final diagnostic?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SettingsInlineError(
                key: StudioDriverKeys.botsDiagnostic(bot.id),
                message: diagnostic.message,
              ),
            ),
          if (conversationPage != null &&
              conversationPage.conversations.isEmpty &&
              conversationPage.nextCursor == null)
            Text(context.l10n.settingsBotsFirstMessageGuide),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canOpenFeishu)
                FilledButton.tonalIcon(
                  key: StudioDriverKeys.botsOpenChat,
                  onPressed: busy ? null : onOpenBot,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(context.l10n.settingsBotsOpenChat),
                ),
              TextButton(
                key: StudioDriverKeys.botsOpenChatBrowser,
                onPressed: busy ? null : onOpenBotBrowser,
                child: Text(context.l10n.settingsBotsOpenChatBrowser),
              ),
            ],
          ),
          const SizedBox(height: 20),
          model,
          const SizedBox(height: 20),
          SettingsSectionPanel(
            title: context.l10n.settingsBotsConversations,
            trailing: TextButton(
              key: StudioDriverKeys.botsRefreshConversations,
              onPressed: busy ? null : () => onLoadConversations(null),
              child: Text(context.l10n.settingsBotsRefreshConversations),
            ),
            children: [
              if (view.queries.conversationError case final error?
                  when view.queries.selectedConversationBotId == bot.id)
                SettingsInlineError(message: error.message),
              if (view.queries.selectedConversationBotId == bot.id &&
                  view.queries.conversationsLoading)
                const LinearProgressIndicator(),
              for (final conversation
                  in conversationPage?.conversations ??
                      const <BotConversation>[])
                ListTile(
                  key: StudioDriverKeys.botsConversation(conversation.chatId),
                  selected: conversation.chatId == selectedChatId,
                  title: Text(
                    conversation.name ?? _sourceLabel(context, conversation),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: conversation.name == null
                      ? null
                      : Text(_sourceLabel(context, conversation)),
                  onTap: () => onOpenConversation(conversation),
                  trailing: PopupMenuButton<String>(
                    key: StudioDriverKeys.botsConversationActions(
                      conversation.chatId,
                    ),
                    enabled: !busy,
                    onSelected: (action) {
                      if (action == 'platform') {
                        onSelectChat(conversation.chatId);
                      }
                      if (action == 'new') onCreateThread(conversation);
                      if (action == 'trust') {
                        onTrustChat(conversation.chatId, true);
                      }
                      if (action == 'revoke') {
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
                          value:
                              bot.trustedChatIds.contains(conversation.chatId)
                              ? 'revoke'
                              : 'trust',
                          child: Text(
                            bot.trustedChatIds.contains(conversation.chatId)
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
              if (conversationPage?.nextCursor case final cursor?)
                TextButton(
                  key: StudioDriverKeys.botsNextConversations,
                  onPressed: busy || view.queries.conversationsLoading
                      ? null
                      : () => onLoadConversations(cursor),
                  child: Text(context.l10n.settingsBotsNextPage),
                ),
            ],
          ),
          ExpansionTile(
            key: const PageStorageKey('bot-access-settings'),
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
                      title: Text(openId, overflow: TextOverflow.ellipsis),
                      trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () => onTrustUser(openId, false),
                        child: Text(context.l10n.settingsBotsRevoke),
                      ),
                    ),
                  for (final pairing in bot.pairing)
                    ListTile(
                      title: Text(
                        pairing.displayName ?? pairing.openId,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 两个动作换行排布在副标题区，窄窗口下不挤占 trailing，
                      // 也不会遮挡较长的显示名。
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
                                key: StudioDriverKeys.botsApproveUser(
                                  pairing.openId,
                                ),
                                onPressed: busy
                                    ? null
                                    : () => onTrustUser(pairing.openId, true),
                                child: Text(context.l10n.settingsBotsApprove),
                              ),
                              TextButton(
                                key: StudioDriverKeys.botsClearPairing(
                                  pairing.openId,
                                ),
                                onPressed: busy
                                    ? null
                                    : () =>
                                          onClearPairingRequest(pairing.openId),
                                child: Text(
                                  context.l10n.settingsBotsClearPairing,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.l10n.settingsBotsClearPairingHint,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
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
                        onPressed: busy
                            ? null
                            : () => onTrustChat(chatId, false),
                        child: Text(context.l10n.settingsBotsRevoke),
                      ),
                    ),
                  if (bot.trustedChatIds.isEmpty)
                    Text(context.l10n.settingsBotsNoTrustedChats),
                ],
              ),
            ],
          ),
          ExpansionTile(
            key: const PageStorageKey('bot-connection-settings'),
            leading: const Icon(Icons.settings_outlined),
            title: Text(context.l10n.botsConnectionSettings),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    key: StudioDriverKeys.botsEdit,
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(Icons.key_outlined),
                    label: Text(context.l10n.settingsBotsEdit),
                  ),
                  TextButton(
                    key: StudioDriverKeys.botsRetry,
                    onPressed: busy ? null : onRetry,
                    child: Text(context.l10n.settingsBotsRetryConnection),
                  ),
                  TextButton.icon(
                    onPressed: onOpenConsole,
                    icon: const Icon(Icons.open_in_new),
                    label: Text(context.l10n.settingsBotsOpenConsole),
                  ),
                ],
              ),
              SettingsToggleRow(
                icon: Icons.build_outlined,
                title: context.l10n.settingsBotsTools,
                subtitle: context.l10n.settingsBotsToolsHint,
                value: bot.toolsEnabled,
                onChanged: busy ? (_) {} : onTools,
              ),
              SettingsReadout(
                label: context.l10n.settingsBotsAppId,
                value: bot.appId,
              ),
              SettingsReadout(
                label: context.l10n.botsWorkspace,
                value: bot.workspacePath,
              ),
            ],
          ),
        ],
        if (selectedChatId != null) ...[
          SettingsSectionPanel(
            title: context.l10n.settingsBotsMessages,
            children: [
              Text(context.l10n.settingsBotsHistoryPermissions),
              const SizedBox(height: 8),
              Text(
                context.l10n.settingsBotsOpenConsoleHint,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: StudioDriverKeys.botsOpenConsole,
                  onPressed: onOpenConsole,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(context.l10n.settingsBotsOpenConsole),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: StudioDriverKeys.botsRefreshMessages,
                onPressed: busy ? null : () => onLoadMessages(null),
                child: Text(context.l10n.settingsBotsRefreshMessages),
              ),
              if (view.queries.messageError case final error?
                  when view.queries.selectedMessageBotId == bot.id &&
                      view.queries.selectedChatId == selectedChatId)
                SettingsInlineError(message: error.message),
              if (view.queries.selectedMessageBotId == bot.id &&
                  view.queries.selectedChatId == selectedChatId &&
                  view.queries.messagesLoading)
                const LinearProgressIndicator(),
              for (final message
                  in messagePage?.messages ?? const <BotMessage>[])
                ExpansionTile(
                  title: Text(
                    _messageText(message),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${message.senderOpenId ?? message.messageId} · ${DateTime.fromMillisecondsSinceEpoch(message.createdAt * 1000).toLocal()}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(_messageText(message)),
                    ),
                  ],
                ),
              if (messagePage?.nextCursor case final cursor?)
                TextButton(
                  key: StudioDriverKeys.botsNextMessages,
                  onPressed: busy || view.queries.messagesLoading
                      ? null
                      : () => onLoadMessages(cursor),
                  child: Text(context.l10n.settingsBotsNextPage),
                ),
              TextField(
                key: StudioDriverKeys.botsSendInput,
                controller: sendController,
                onChanged: onDraftChanged,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsBotsSendHint,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  key: StudioDriverKeys.botsSend,
                  onPressed: busy ? null : onSend,
                  child: Text(context.l10n.settingsBotsSend),
                ),
              ),
              if (send != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.l10n.settingsBotsSendStatus(
                      _sendStatus(context, send.status),
                    ),
                  ),
                ),
              if (send != null) ...[
                SelectableText(
                  '${context.l10n.settingsBotsSendOperation}: ${send.operationId}',
                ),
                if (send.status == BotSendStatus.partial ||
                    send.status == BotSendStatus.unknown)
                  Text(context.l10n.settingsBotsNoReplay),
                for (final segment in send.segments)
                  Text(
                    '${segment.index + 1}: ${_sendStatus(context, segment.status)}${segment.diagnostic == null ? '' : ' · ${segment.diagnostic!.message}'}',
                  ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  String _sendStatus(BuildContext context, BotSendStatus status) =>
      switch (status) {
        BotSendStatus.succeeded => context.l10n.settingsBotsSendSucceeded,
        BotSendStatus.partial => context.l10n.settingsBotsSendPartial,
        BotSendStatus.rejected => context.l10n.settingsBotsSendRejected,
        BotSendStatus.unknown => context.l10n.settingsBotsSendUnknown,
      };

  String _sourceLabel(BuildContext context, BotConversation conversation) {
    final source = switch (conversation.source) {
      BotConversationSource.remoteGroup => context.l10n.settingsBotsSourceGroup,
      BotConversationSource.observedDirect =>
        context.l10n.settingsBotsSourceDirect,
    };
    return source;
  }

  String _messageText(BotMessage message) {
    return switch (message.body) {
      BotTextMessageBody(:final text) => text,
      BotPostMessageBody(:final text) => text,
      BotUnsupportedMessageBody(:final notice) => notice,
    };
  }
}
