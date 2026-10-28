part of 'settings_bots_tab.dart';

/// A registered destination consumes current read models, never the source
/// page's captured BotSnapshot or callbacks. AppGraph remains the content owner.
class BotChatPage extends ConsumerWidget {
  const BotChatPage({
    required this.botId,
    required this.chatId,
    required this.threadId,
    required this.activation,
    required this.onRetry,
    super.key,
  });

  final String botId;
  final String chatId;
  final String threadId;
  final ValueListenable<AsyncValue<String?>> activation;
  final VoidCallback onRetry;

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
    final selected = ref.watch(selectionStoreProvider);
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
            onPressed: () => StudioRoutes.openBotPlatformTools(
              context,
              botId: botId,
              chatId: chatId,
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<AsyncValue<String?>>(
        valueListenable: activation,
        builder: (context, value, _) => value.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _unavailable(context, error),
          data: (activeThreadId) {
            if (activeThreadId == null) return const SizedBox.shrink();
            if (activeThreadId != threadId ||
                selected.selectedThreadId != threadId ||
                selected.needsOpen) {
              return _unavailable(context, null);
            }
            return const AgentWorkspacePane();
          },
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context, Object? error) => Center(
    child: Column(
      key: const ValueKey('bot-conversation-unavailable'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.l10n.settingsBotsOperationFailed),
        if (error is StudioFailure) SelectableText(error.message),
        TextButton(
          onPressed: onRetry,
          child: Text(context.l10n.runtimeFatalRetry),
        ),
      ],
    ),
  );
}
