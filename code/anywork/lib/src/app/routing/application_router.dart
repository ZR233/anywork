import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/settings.dart';
import '../../features/settings/settings_bots_chat_page.dart';
import '../../features/settings/settings_bots_tab.dart';
import '../../features/modes/modes.dart';
import '../../features/settings/accounts/connectors/account_navigation.dart';
import '../../features/shell/studio_shell.dart';

/// 应用唯一的声明式路由表。
///
/// 页面级导航只允许经由这里声明的路由（`context.pushNamed`/`context.pop`），
/// 不再使用绕过路由表的 `Navigator.push(MaterialPageRoute)`；页内 tab 与
/// master-detail 槽位切换不属于页面导航，保持原有实现。
GoRouter createApplicationRouter(WidgetRef ref) => GoRouter(
  restorationScopeId: 'anywork-router',
  routes: [
    GoRoute(
      path: '/',
      name: 'studio',
      builder: (context, state) => const StudioShell(),
      routes: [
        GoRoute(
          path: 'settings',
          name: 'settings',
          onExit: (context, state) async {
            if (!await confirmLeaveModeEditor(context, ref)) return false;
            return context.mounted &&
                await confirmLeaveAccountsEditor(context, ref);
          },
          pageBuilder: (context, state) => const MaterialPage<void>(
            restorationId: 'settings-page',
            child: SettingsPage(),
          ),
          routes: [
            GoRoute(
              path: 'modes/:modeId',
              name: 'mode-workspace',
              pageBuilder: (context, state) => MaterialPage<void>(
                restorationId: 'mode-workspace-page',
                child: ModeWorkspacePage(
                  modeId: state.pathParameters['modeId']!,
                ),
              ),
              routes: [
                GoRoute(
                  path: 'details',
                  name: 'mode-detail',
                  pageBuilder: (context, state) => MaterialPage<void>(
                    restorationId: 'mode-detail-page',
                    child: ModeDetailPage(
                      modeId: state.pathParameters['modeId']!,
                      stage: state.uri.queryParameters['stage'],
                      edge: state.uri.queryParameters['edge'],
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: 'bots/:botId',
              name: 'bot-details',
              pageBuilder: (context, state) => MaterialPage<void>(
                restorationId: 'bot-details-page',
                child: BotDetailsPage(
                  botId: state.pathParameters['botId']!,
                  chatId: state.uri.queryParameters['chatId'],
                ),
              ),
              routes: [
                GoRoute(
                  path: 'chat',
                  name: 'bot-chat',
                  pageBuilder: (context, state) => MaterialPage<void>(
                    restorationId: 'bot-chat-page',
                    child: BotChatPage(
                      botId: state.pathParameters['botId']!,
                      chatId: state.uri.queryParameters['chatId'] ?? '',
                      title: state.uri.queryParameters['title'],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
