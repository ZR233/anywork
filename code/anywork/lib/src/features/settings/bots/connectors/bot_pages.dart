import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/feishu_app_links.dart';
import '../../../conversation/conversation.dart';
import 'bot_console_link.dart';
import 'bots_settings_connector.dart';

/// The detail route of one bot: a full page above the overview, so the list,
/// its filter and its scroll position survive the round trip.
class BotDetailsPage extends StatelessWidget {
  const BotDetailsPage({required this.botId, this.chatId, super.key});

  final String botId;

  /// Non-null opens that conversation's platform tools page instead of the
  /// configuration detail.
  final String? chatId;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: BotsSettingsConnector(botId: botId, chatId: chatId),
    ),
  );
}

/// The chat route of one conversation: the established conversation surface
/// under a bar that goes back, opens the platform client, or moves to that
/// conversation's platform tools.
class BotChatPage extends ConsumerWidget {
  const BotChatPage({
    required this.botId,
    required this.chatId,
    required this.threadId,
    required this.title,
    super.key,
  });

  final String botId;
  final String chatId;
  final String threadId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      leading: BackButton(key: StudioDriverKeys.botsChatBack),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: context.l10n.settingsBotsOpenChat,
          icon: const Icon(Icons.open_in_new),
          onPressed: () => unawaited(_openChat(context, ref)),
        ),
        IconButton(
          key: StudioDriverKeys.botsPlatformTools,
          tooltip: context.l10n.botsPlatformTools,
          icon: const Icon(Icons.more_horiz),
          onPressed: () => unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => BotDetailsPage(botId: botId, chatId: chatId),
              ),
            ),
          ),
        ),
      ],
    ),
    body: ConversationScreen(
      key: ValueKey(('bot-chat', threadId)),
      threadId: threadId,
    ),
  );

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failure = context.l10n.settingsBotsOpenLinkFailed;
    final link = feishuChatAppLink(
      chatId,
      browser: ref.read(feishuClientAvailableProvider).asData?.value != true,
    );
    if (await openBotAppLink(ref, link)) return;
    messenger?.showSnackBar(SnackBar(content: Text(failure)));
  }
}

/// Opens the detail route of [botId] above the current page.
Future<void> openBotDetails(BuildContext context, String botId) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => BotDetailsPage(botId: botId)));

/// Opens the platform tools route (message history and manual send) of one
/// conversation.
Future<void> openBotPlatformTools(
  BuildContext context,
  String botId,
  String chatId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => BotDetailsPage(botId: botId, chatId: chatId),
  ),
);
