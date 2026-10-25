import 'dart:convert';

import 'package:anywork/src/features/settings/bots/view_models/bots_settings_view_model.dart';
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/features/settings/view_models/settings_navigation_view_model.dart';
import 'package:anywork/src/platform/feishu_app_links.dart';
import 'package:anywork/src/shared/driver_bots_projection.dart';
import 'package:anywork/src/shared/driver_projection.dart';
import 'package:anywork/src/shared/driver_snapshot_json.dart';
import 'package:anywork_client/bots.dart';
import 'package:anywork_client/operations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/application_environment.dart';
import 'support/bots_environment.dart';

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
    'repository maps bot save, registration start and cancel states',
    () async {
      final port = BotsTestPort();
      final env = ApplicationTestEnvironment(botsPort: port)..installHost();
      addTearDown(env.close);
      final repository = env.graph.bots;
      final sync = repository.synchronize();
      await port.publish(botsSnapshot(1));
      await sync;
      final saving = repository.saveBot(
        const BotEdit(
          botId: null,
          expectedConfigRevision: 0,
          name: 'Feishu China',
          projectId: 'project-local',
          appId: 'cli_demo',
          secret: BotSecretReplace(value: 'memory-only'),
          enabled: true,
          toolsEnabled: true,
          modelRoute: null,
        ),
      );
      final save = await port.saved.future;
      expect(save.secret, const BotSecretReplace(value: 'memory-only'));
      port.saveReply.complete(botsReply(save.operationId, 2, bot: savedBot));
      await port.publish(botsSnapshot(2, bots: [savedBot]));
      expect(await saving.result, isA<CommittedCommandResult<BotSnapshot>>());
      final saved = repository.state.value.snapshot!.value;
      expect(saved.bots, isNotEmpty);
      expect(saved.bots.single.credential, BotCredentialAvailability.stored);
      expect(jsonEncode(saved.toString()), isNot(contains('memory-only')));
      final starting = repository.startRegistration(
        name: 'Feishu China',
        projectId: 'project-local',
      );
      final start = await port.started.future;
      final registration = waitingRegistration('Feishu China');
      port.startReply.complete(
        botsReply(start.operationId, 3, registration: registration),
      );
      await port.publish(
        botsSnapshot(3, bots: [savedBot], registration: registration),
      );
      expect(
        await starting.result,
        isA<CommittedCommandResult<BotRegistrationAttempt>>(),
      );
      final started = repository.state.value.snapshot!.value;
      expect(started.registration?.status, isA<BotRegistrationWaiting>());
      expect(
        started.registration.toString(),
        isNot(contains('https://accounts.feishu.cn')),
      );
      final cancelling = repository.cancelRegistration(
        attemptId: started.registration!.attemptId,
      );
      final cancel = await port.cancelled.future;
      expect(cancel.attemptId, registration.attemptId);
      final cancelled = registration.copyWith(
        status: BotRegistrationCancelled(attemptId: registration.attemptId),
      );
      port.cancelReply.complete(
        botsReply(cancel.operationId, 4, registration: cancelled),
      );
      await port.publish(
        botsSnapshot(4, bots: [savedBot], registration: cancelled),
      );
      expect(
        await cancelling.result,
        isA<CommittedCommandResult<BotRegistrationAttempt>>(),
      );
      expect(
        repository.state.value.snapshot!.value.registration?.status,
        isA<BotRegistrationCancelled>(),
      );
    },
  );

  test(
    'Driver bots projection excludes secrets and verification URLs',
    () async {
      final port = BotsTestPort();
      final env = ApplicationTestEnvironment(botsPort: port)..installHost();
      addTearDown(env.close);
      final repository = env.graph.bots;
      final sync = repository.synchronize();
      await port.publish(botsSnapshot(1));
      await sync;
      final starting = repository.startRegistration(
        name: 'Scan bot',
        projectId: 'project-local',
      );
      final start = await port.started.future;
      final registration = waitingRegistration('Scan bot');
      port.startReply.complete(
        botsReply(start.operationId, 2, registration: registration),
      );
      await port.publish(botsSnapshot(2, registration: registration));
      expect(
        await starting.result,
        isA<CommittedCommandResult<BotRegistrationAttempt>>(),
      );
      final facts = captureDriverSnapshot(
        env.graph,
        visible: const DriverViewFacts(),
        bots: projectBotsState(repository.state.value),
      );
      final json =
          jsonDecode(jsonEncode(facts.toJson())) as Map<String, dynamic>;
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
      final port = BotsTestPort();
      final env = ApplicationTestEnvironment(botsPort: port)..installHost();
      addTearDown(env.close);
      await env.domains.establish();
      await env.domains.selectThread('thread-main');
      final session = env.graph.conversation.active.value;
      expect(session, isNotNull);
      final container = env.container;
      await container.read(settingsNavigationViewModelProvider.future);
      container
          .read(settingsNavigationViewModelProvider.notifier)
          .enter(SettingsTab.bots);
      final visible = container.listen(
        botsSettingsViewModelProvider,
        (_, _) {},
      );
      addTearDown(visible.close);
      final sync = env.graph.bots.synchronize();
      await port.publish(botsSnapshot(1));
      await sync;
      await container.read(botsSettingsViewModelProvider.future);
      expect(env.graph.conversation.active.value, same(session));
      expect(
        env.graph.conversation.existingSession('thread-main'),
        same(session),
      );
    },
  );
}
