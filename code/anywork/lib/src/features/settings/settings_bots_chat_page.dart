import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/studio_l10n.dart';
import '../../platform/external_url_launcher.dart';
import '../../platform/feishu_app_links.dart';
import '../../presentation/providers/client_provider.dart';
import '../../shared/studio_driver_keys.dart';
import '../shell/studio_shell.dart' show AgentWorkspacePane;

/// 一个 bot 会话的独立会话页（`bot-chat` 路由）。
///
/// 进入前调用方已执行 `directoryCommands.selectThread`；`title` 是调用方
/// 从当前会话数据计算的显示名（会话按需分页读取，不在全局快照中），
/// `AgentWorkspacePane` 消费全局选中会话。
class BotChatPage extends ConsumerWidget {
  const BotChatPage({
    super.key,
    required this.botId,
    required this.chatId,
    this.title,
  });

  final String botId;
  final String chatId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedTitle = _resolveTitle(ref);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(key: StudioDriverKeys.botsChatBack),
        title: Text(
          resolvedTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.settingsBotsOpenChat,
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openBotLink(context, ref),
          ),
          IconButton(
            key: StudioDriverKeys.botsPlatformTools,
            tooltip: context.l10n.botsPlatformTools,
            icon: const Icon(Icons.more_horiz),
            onPressed: () => context.pushNamed(
              'bot-details',
              pathParameters: {'botId': botId},
              queryParameters: {'chatId': chatId},
            ),
          ),
        ],
      ),
      body: const AgentWorkspacePane(),
    );
  }

  String _resolveTitle(WidgetRef ref) {
    if (title != null && title!.isNotEmpty) return title!;
    final snapshot = ref.read(
      anyworkClientProvider.select((client) => client.bots.state.value),
    );
    final bot = snapshot?.bots.where((bot) => bot.id == botId).firstOrNull;
    return bot?.name ?? chatId;
  }

  Future<void> _openBotLink(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final url = feishuChatAppLink(
      chatId,
      browser: ref.read(feishuClientAvailableProvider).asData?.value != true,
    );
    try {
      await ref.read(externalUrlLauncherProvider)(url);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsBotsOpenLinkFailed)),
      );
    }
  }
}
