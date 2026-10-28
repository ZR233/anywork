part of 'settings_bots_tab.dart';

/// A registered destination consumes current read models, never the source
/// page's captured BotSnapshot or callbacks. AppGraph remains the content owner.
class BotChatPage extends ConsumerWidget {
  const BotChatPage({
    required this.botId,
    required this.chatId,
    required this.threadId,
    super.key,
  });

  final String botId;
  final String chatId;
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(settingsBotsViewProvider);
    final bot = view.snapshot?.bot(botId);
    final queries = view.queries;
    final conversation = queries.selectedConversationBotId == botId
        ? queries.conversationPage?.conversations
              .where((chat) => chat.chatId == chatId)
              .firstOrNull
        : null;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          key: StudioDriverKeys.botsChatBack,
          onPressed: () => context.pop(),
        ),
        title: Text(
          conversation?.name ?? bot?.name ?? chatId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.settingsBotsOpenChat,
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              final url = feishuChatAppLink(
                chatId,
                browser:
                    ref.read(feishuClientAvailableProvider).asData?.value !=
                    true,
              );
              try {
                await ref.read(externalUrlLauncherProvider)(url);
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.settingsBotsOpenLinkFailed),
                  ),
                );
              }
            },
          ),
          IconButton(
            key: StudioDriverKeys.botsPlatformTools,
            tooltip: context.l10n.botsPlatformTools,
            icon: const Icon(Icons.more_horiz),
            onPressed: () => BotPlatformToolsRoute(
              botId: botId,
              chatId: chatId,
            ).push(context),
          ),
        ],
      ),
      body: AgentWorkspacePane(threadId: threadId),
    );
  }
}
