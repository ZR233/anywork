import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/client_provider.dart';

import '../../features/modes/modes.dart';
import '../../features/settings/accounts/connectors/account_navigation.dart';
import '../../features/settings/settings.dart';
import '../../features/settings/settings_bots_tab.dart';
import '../../features/shell/studio_shell.dart';

part 'app_route.g.dart';

/// 应用唯一页面树。官方生成器负责参数编解码、地址和导航 API。
@TypedGoRoute<StudioRoute>(
  path: '/',
  name: StudioRoute.name,
  routes: [
    TypedGoRoute<SettingsRoute>(
      path: 'settings',
      name: SettingsRoute.name,
      routes: [
        TypedGoRoute<ModeWorkspaceRoute>(
          path: 'modes/:modeId',
          name: ModeWorkspaceRoute.name,
          routes: [
            TypedGoRoute<ModeDetailRoute>(
              path: 'details',
              name: ModeDetailRoute.name,
            ),
          ],
        ),
      ],
    ),
    TypedGoRoute<BotDetailsRoute>(
      path: 'bots/:botId',
      name: BotDetailsRoute.name,
    ),
    TypedGoRoute<BotConversationRoute>(
      path: 'bots/:botId/chats/:chatId/threads/:threadId',
      name: BotConversationRoute.name,
    ),
    TypedGoRoute<BotPlatformToolsRoute>(
      path: 'bots/:botId/chats/:chatId/platform',
      name: BotPlatformToolsRoute.name,
    ),
  ],
)
class StudioRoute extends GoRouteData with $StudioRoute {
  const StudioRoute();
  static const name = 'studio';

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const StudioShell();
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();
  static const name = 'settings';

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        key: state.pageKey,
        restorationId: 'settings-page',
        child: const SettingsPage(),
      );

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) async {
    if (!await confirmLeaveModeEditor(context)) return false;
    return context.mounted && await confirmLeaveAccountsEditor(context);
  }
}

class ModeWorkspaceRoute extends GoRouteData with $ModeWorkspaceRoute {
  const ModeWorkspaceRoute({required this.modeId});
  static const name = 'mode-workspace';
  final String modeId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        key: state.pageKey,
        restorationId: 'mode-workspace-page',
        child: ModeWorkspacePage(modeId: modeId),
      );

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) async {
    final owner = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(anyworkClientProvider).modeEditor;
    if (owner.openedModeId != modeId) return true;
    return confirmLeaveModeEditor(context);
  }
}

class ModeDetailRoute extends GoRouteData with $ModeDetailRoute {
  const ModeDetailRoute({required this.modeId, this.stage, this.edge});
  static const name = 'mode-detail';
  final String modeId;
  final String? stage;
  final String? edge;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        key: state.pageKey,
        restorationId: 'mode-detail-page',
        child: ModeDetailPage(modeId: modeId, stage: stage, edge: edge),
      );
}

class BotDetailsRoute extends GoRouteData with $BotDetailsRoute {
  const BotDetailsRoute({required this.botId});
  static const name = 'bot-details';
  final String botId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      BotDetailsPage(key: ValueKey((botId, null)), botId: botId);
}

class BotConversationRoute extends GoRouteData with $BotConversationRoute {
  const BotConversationRoute({
    required this.botId,
    required this.chatId,
    required this.threadId,
  });
  static const name = 'bot-conversation';
  final String botId;
  final String chatId;
  final String threadId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      BotChatPage(botId: botId, chatId: chatId, threadId: threadId);
}

class BotPlatformToolsRoute extends GoRouteData with $BotPlatformToolsRoute {
  const BotPlatformToolsRoute({required this.botId, required this.chatId});
  static const name = 'bot-platform-tools';
  final String botId;
  final String chatId;

  @override
  Widget build(BuildContext context, GoRouterState state) => BotDetailsPage(
    key: ValueKey((botId, chatId)),
    botId: botId,
    chatId: chatId,
  );
}
