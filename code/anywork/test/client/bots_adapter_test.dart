import 'support/test_statistics_feed.dart';

import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/platform/feishu_app_links.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registration handoff preserves the ticket and rejects other origins', () {
    const verification =
        'https://accounts.feishu.cn/oauth/authorize?code=a%2Bb%26c&redirect=%2Fconfirm&name=Bot test';
    final link = Uri.parse(feishuRegistrationAppLink(verification)!);
    expect(link.scheme, 'feishu');
    expect(link.host, 'applink');
    expect(link.path, '/client/web_url/open');
    expect(link.queryParameters, {'mode': 'window', 'url': verification});
    expect(link.query, isNot(contains('+')));
    for (final rejected in [
      'http://127.0.0.1:8192/fixture?code=local',
      'https://accounts.feishu.cn.example.com/authorize',
      'https://user@accounts.feishu.cn/authorize',
      'https://accounts.feishu.cn:8443/authorize',
      'https://accounts.feishu.cn/authorize#ticket',
      'https://accounts.feishu.cn/authorize\n',
    ]) {
      expect(feishuRegistrationAppLink(rejected), isNull);
    }
  });

  test('bot chat handoff keeps the selected app as a single encoded value', () {
    const appId = 'cli_example test&url=https://unrelated.example';
    for (final browser in [false, true]) {
      final link = Uri.parse(feishuBotAppLink(appId, browser: browser));
      expect(link.scheme, browser ? 'https' : 'feishu');
      expect(link.host, browser ? 'applink.feishu.cn' : 'applink');
      expect(link.path, '/client/bot/open');
      expect(link.queryParameters, {'appId': appId});
      expect(link.query, contains('cli_example%20test%26url%3D'));
    }
  });

  test(
    'conversation handoff opens its chat rather than the bot default DM',
    () {
      const chatId = 'oc_selected&openId=unrelated';
      for (final browser in [false, true]) {
        final link = Uri.parse(feishuChatAppLink(chatId, browser: browser));
        expect(link.scheme, browser ? 'https' : 'feishu');
        expect(link.path, '/client/chat/open');
        expect(link.queryParameters, {'openChatId': chatId});
      }
    },
  );

  test(
    'demo adapter maps bot save, registration start and cancel states',
    () async {
      final transport = RecordingDemoTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'bots-adapter',
      );
      addTearDown(client.close);
      await client.bootstrap();
      final saved = await client.botsCommands.saveBot(
        expectedConfigRevision: 0,
        name: 'Feishu China',
        workspaceId: 'project-local',
        appId: 'cli_demo',
        secret: BotSecretReplace('memory-only'),
      );
      expect(saved.bots, isNotEmpty);
      expect(saved.bots.single.credential, BotCredentialAvailability.stored);
      expect(jsonEncode(saved.toString()), isNot(contains('memory-only')));
      final started = await client.botsCommands.startRegistration(
        name: 'Feishu China',
        workspaceId: 'project-local',
      );
      expect(started.registration?.status, isA<BotRegistrationWaiting>());
      expect(
        started.registration.toString(),
        isNot(contains('https://accounts.feishu.cn')),
      );
      await client.botsCommands.cancelRegistration(
        attemptId: started.registration!.attemptId,
      );
      expect(
        client.bots.state.value?.registration?.status,
        isA<BotRegistrationCancelled>(),
      );
    },
  );

  test(
    'Driver bots projection excludes secrets and verification URLs',
    () async {
      final transport = RecordingDemoTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'bots-driver',
      );
      final client = graph.client;
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      await client.bootstrap();
      await client.botsCommands.startRegistration(
        name: 'Scan bot',
        workspaceId: 'project-local',
      );
      final timeline = graph.timeline;
      bindStudioDriver(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
        timeline: timeline,
      );
      final facts = queryStudioDriverFacts(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
        timeline: timeline,
      );
      final json = jsonDecode(
        StudioDriverState.snapshotJson(observed: facts),
      ) as Map<String, dynamic>;
      final encoded = jsonEncode(json);
      expect(encoded, isNot(contains('accounts.feishu.cn')));
      expect(encoded, isNot(contains('verificationUrl')));
      expect(encoded, isNot(contains('secret')));
      expect(json['bots'], isA<Map>());
      expect((json['bots'] as Map)['registrationKind'], 'waiting');
      expect((json['bots'] as Map).containsKey('verificationUrl'), isFalse);
    },
  );

  test(
    'settings navigation to bots does not close the active session',
    () async {
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: RecordingDemoTransport(),
        clientId: 'bots-session',
      );
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      await graph.client.bootstrap();
      await (graph..setConversationPageVisible(true)).client.directoryCommands
          .selectThread('thread-main');
      final session = graph.client.conversations.existingSession('thread-main');
      expect(session, isNotNull);
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      addTearDown(container.dispose);
      graph.client.channels.acquireSettingsScope(
        BridgeSettingsScopeKind.bots,
        null,
      );
      expect(
        graph.client.conversations.existingSession('thread-main'),
        same(session),
      );
      expect(graph.client.conversations.sessionState('thread-main'), isNotNull);
    },
  );
}
