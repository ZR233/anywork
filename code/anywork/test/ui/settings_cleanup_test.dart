import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/settings_bots_tab.dart'
    show BotDetailsPage;
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../support/pump_client_future.dart';
import '../support/test_app_lifecycle.dart'
    show ClientCloseBudget, TestDemoStudioTransport, testAppGraph;
import '../support/test_statistics_feed.dart';

final class _BotMenuTransport extends TestDemoStudioTransport {
  _BotMenuTransport();

  final conversations = const <BotConversation>[
    BotConversation(
      chatId: 'chat-group-target',
      kind: BotConversationKind.group,
      source: BotConversationSource.remoteGroup,
      name: 'Target group',
    ),
    BotConversation(
      chatId: 'chat-direct-target',
      kind: BotConversationKind.direct,
      source: BotConversationSource.observedDirect,
      name: 'Target direct chat',
    ),
  ];
  final trustedChatRequests = <SetBotTrustedChatRequest>[];
  int trustedChatRequestsCompleted = 0;
  final messageChatIds = <String>[];
  int messageRequestsCompleted = 0;
  final threadRequests = <CreateBotConversationThreadRequest>[];
  int threadRequestsCompleted = 0;
  final enabledStarted = Completer<void>();
  final releaseEnabled = Completer<void>();
  final enabledFinished = Completer<void>();

  @override
  Future<BotConversationPage> listBotConversations(
    ListBotConversationsRequest request,
  ) async =>
      BotConversationPage(botId: request.botId, conversations: conversations);

  @override
  Future<BotMessagePage> readBotMessages(ReadBotMessagesRequest request) async {
    messageChatIds.add(request.chatId);
    try {
      return await super.readBotMessages(request);
    } finally {
      messageRequestsCompleted++;
    }
  }

  @override
  Future<BotsCommandReply> setBotTrustedChat(
    SetBotTrustedChatRequest request,
  ) async {
    trustedChatRequests.add(request);
    try {
      return await super.setBotTrustedChat(request);
    } finally {
      trustedChatRequestsCompleted++;
    }
  }

  @override
  Future<BotConversationThreadReply> createBotConversationThread(
    CreateBotConversationThreadRequest request,
  ) async {
    threadRequests.add(request);
    try {
      return await super.createBotConversationThread(request);
    } finally {
      threadRequestsCompleted++;
    }
  }

  @override
  Future<BotsCommandReply> setBotEnabled(SetBotEnabledRequest request) async {
    if (!enabledStarted.isCompleted) enabledStarted.complete();
    await releaseEnabled.future;
    try {
      return await super.setBotEnabled(request);
    } finally {
      if (!enabledFinished.isCompleted) enabledFinished.complete();
    }
  }
}

Widget _host(AppGraph graph, GoRouter router) => ProviderScope(
  overrides: [appGraphProvider.overrideWithValue(graph)],
  child: MaterialApp.router(
    routerConfig: router,
    theme: pureStudioTheme(),
    locale: const Locale('en'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
  ),
);

Future<AppGraph> _bootstrap(
  WidgetTester tester,
  _BotMenuTransport transport,
  GoRouter router,
) async {
  final graph = testAppGraph(
    statisticsFeed: const TestStatisticsFeedPort(),
    transport: transport,
    clientId: 'settings-bot-menu',
  );
  addTearDown(() async {
    if (transport.enabledStarted.isCompleted &&
        !transport.enabledFinished.isCompleted) {
      if (!transport.releaseEnabled.isCompleted) {
        transport.releaseEnabled.complete();
      }
      await pumpClientUntil(
        tester,
        () => transport.enabledFinished.isCompleted,
        'finish pending bot enable command',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(budget: ClientCloseBudget(const Duration(seconds: 5))),
      'settings bot menu teardown',
    );
    router.dispose();
  });
  await pumpClientFuture(
    tester,
    graph.client.bootstrap(),
    'bot menu bootstrap',
  );
  return graph;
}

void main() {
  testWidgets(
    'Bot conversation menu sends each action to its conversation and disables while busy',
    (tester) async {
      final transport = _BotMenuTransport();
      final router = createApplicationRouter();
      final graph = await _bootstrap(tester, transport, router);
      final bots = await pumpClientFuture(
        tester,
        graph.client.botsCommands.saveBot(
          expectedConfigRevision: 0,
          name: 'Menu bot',
          workspaceId: 'project-local',
          appId: 'menu-app',
          secret: const BotSecretPreserve(),
        ),
        'create menu test bot',
      );
      final botId = bots.bots.single.id;
      router.go(BotDetailsRoute(botId: botId).location);
      await tester.pumpWidget(_host(graph, router));
      await tester.pumpAndSettle();

      final groupActions = find.byKey(
        StudioDriverKeys.botsConversationActions('chat-group-target'),
      );
      final directActions = find.byKey(
        StudioDriverKeys.botsConversationActions('chat-direct-target'),
      );
      final l10n = AppLocalizations.of(tester.element(groupActions));
      Future<void> openMenu(Finder actions) async {
        await tester.ensureVisible(actions);
        await tester.pumpAndSettle();
        await tester.tap(actions);
        await tester.pumpAndSettle();
      }

      await openMenu(groupActions);
      await tester.tap(find.text(l10n.settingsBotsApproveGroup));
      await tester.pumpAndSettle();
      await pumpClientUntil(
        tester,
        () => transport.trustedChatRequestsCompleted == 1,
        'approve target group',
      );
      await tester.pumpAndSettle();
      expect(transport.trustedChatRequests, hasLength(1));
      expect(transport.trustedChatRequests.single.chatId, 'chat-group-target');
      expect(transport.trustedChatRequests.single.trusted, isTrue);

      await openMenu(groupActions);
      expect(find.text(l10n.settingsBotsRevoke), findsOneWidget);
      await tester.tap(find.text(l10n.settingsBotsRevoke));
      await tester.pumpAndSettle();
      await pumpClientUntil(
        tester,
        () => transport.trustedChatRequestsCompleted == 2,
        'revoke target group',
      );
      await tester.pumpAndSettle();
      expect(transport.trustedChatRequests, hasLength(2));
      expect(transport.trustedChatRequests.last.chatId, 'chat-group-target');
      expect(transport.trustedChatRequests.last.trusted, isFalse);

      await openMenu(directActions);
      expect(find.text(l10n.settingsBotsApproveGroup), findsNothing);
      expect(find.text(l10n.settingsBotsRevoke), findsNothing);
      await tester.tap(find.text(l10n.botsPlatformTools));
      await tester.pumpAndSettle();
      final platformDestination = find.byKey(
        ValueKey((botId, 'chat-direct-target')),
      );
      expect(platformDestination, findsOneWidget);
      expect(
        tester.widget<BotDetailsPage>(platformDestination).chatId,
        'chat-direct-target',
      );
      await pumpClientUntil(
        tester,
        () => transport.messageChatIds.contains('chat-direct-target'),
        'load routed direct chat',
      );
      router.pop();
      await tester.pumpAndSettle();

      await openMenu(groupActions);
      await tester.tap(find.text(l10n.settingsBotsNewThread));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StudioDriverKeys.botsConfirmNewThread));
      await tester.pumpAndSettle();
      await pumpClientUntil(
        tester,
        () => transport.threadRequestsCompleted == 1,
        'create target group thread',
      );
      await tester.pumpAndSettle();
      expect(transport.threadRequests, hasLength(1));
      expect(transport.threadRequests.single.botId, botId);
      expect(transport.threadRequests.single.chatId, 'chat-group-target');

      final enableSwitch = find.byKey(StudioDriverKeys.botsEnabled);
      await tester.ensureVisible(enableSwitch);
      await tester.pumpAndSettle();
      await tester.tap(enableSwitch);
      await tester.pump();
      await transport.enabledStarted.future;
      await tester.pump();
      expect(tester.widget<IconButton>(groupActions).onPressed, isNull);
      await tester.ensureVisible(groupActions);
      await tester.pump();
      await tester.tap(groupActions);
      await tester.pump();
      expect(find.text(l10n.botsPlatformTools), findsNothing);

      transport.releaseEnabled.complete();
      await pumpClientUntil(
        tester,
        () => transport.enabledFinished.isCompleted,
        'finish bot enable command',
      );
      await tester.pump();
      expect(tester.widget<IconButton>(groupActions).onPressed, isNotNull);
    },
  );
}
