import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        projectId: 'project-local',
        appId: 'cli_demo',
        secret: BotSecretReplace('memory-only'),
      );
      expect(saved.bots, isNotEmpty);
      expect(saved.bots.single.credential, BotCredentialAvailability.stored);
      expect(jsonEncode(saved.toString()), isNot(contains('memory-only')));
      final started = await client.botsCommands.startRegistration(
        name: 'Feishu China',
        projectId: 'project-local',
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
      final client = AnyworkClient(
        transport: transport,
        clientId: 'bots-driver',
      );
      addTearDown(client.close);
      await client.bootstrap();
      await client.botsCommands.startRegistration(
        name: 'Scan bot',
        projectId: 'project-local',
      );
      final timeline = TimelineSessionOwner(client: client);
      addTearDown(timeline.close);
      bindStudioDriver(client, timeline: timeline);
      final facts = queryStudioDriverFacts(client, timeline: timeline);
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
        transport: RecordingDemoTransport(),
        clientId: 'bots-session',
      );
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      await graph.client.bootstrap();
      await graph.client.directoryCommands.selectThread('thread-main');
      expect(graph.client.activeSession, isNotNull);
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      addTearDown(container.dispose);
      graph.client.channels.acquireSettingsScope(
        BridgeSettingsScopeKind.bots,
        null,
      );
      expect(graph.client.activeSession, isNotNull);
      expect(graph.client.sessionState('thread-main'), isNotNull);
    },
  );
}
