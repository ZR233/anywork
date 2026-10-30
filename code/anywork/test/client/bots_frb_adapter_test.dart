import 'support/test_statistics_feed.dart';

import 'package:anywork/src/app/app_graph.dart';

import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/types/bots.dart' as frb_bots;
import 'package:anywork/src/rust/api/studio/types/event.dart' as frb_event;
import 'package:anywork/src/rust/api/studio/types/product_topic.dart'
    as frb_topic;
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

// These tests execute the production FRB envelope mapper with real generated
// DTOs, the Client canonical reducer and the Driver projection. The fake
// transport only supplies envelope ordering; no native library is loaded and
// no live Feishu platform is involved.

const _verificationUrl =
    'https://accounts.feishu.cn/device_code?user_code=FRB-SECRET-9f2';

frb_bots.BridgeBotSnapshot _frbBot() {
  return frb_bots.BridgeBotSnapshot(
    id: 'bot-frb-1',
    name: '中文机器人',
    workspaceId: 'project-a',
    appId: 'cli_frb_1',
    platform: frb_bots.BridgeBotPlatform.feishuChina,
    enabled: true,
    toolsEnabled: false,
    workspacePath: 'C:/Studio/v2/bots/bot-frb-1/workspace',
    modelRoute: const frb_bots.BridgeBotModelRoute(
      accountId: 'account-a',
      modelId: 'model-a',
      effort: 'high',
    ),
    lastActivityAt: 1718000040,
    configRevision: BigInt.from(3),
    trustedOpenIds: ['ou_trusted_1'],
    trustedChatIds: ['oc_trusted_1', 'oc_trusted_2'],
    connection: frb_bots.BridgeBotConnectionState.reconnecting(
      nextAttemptAt: 1718000060,
      attempt: 2,
    ),
    credential: frb_bots.BridgeBotCredentialAvailability.sessionOnly,
    credentialOperation: frb_bots.BridgeBotCredentialOperation.commitUncertain(
      operationId: 'op-cu-1',
    ),
    pairing: [
      frb_bots.BridgeBotPairingRequest(
        requestId: 'pair-1',
        botId: 'bot-frb-1',
        openId: 'ou_pairing_1',
        displayName: '配对用户',
        createdAt: 1718000030,
      ),
    ],
    canChangeProject: true,
    canChangeAppId: false,
    createdAt: 1718000000,
    updatedAt: 1718000050,
  );
}

frb_bots.BridgeBotsStateSnapshot _frbSnapshot({
  required BigInt revision,
  frb_bots.BridgeBotRegistrationStatus? registrationStatus,
  String? completedBotId,
}) {
  return frb_bots.BridgeBotsStateSnapshot(
    revision: revision,
    updatedAt: 1718000000,
    bots: [_frbBot()],
    registration: registrationStatus == null
        ? null
        : frb_bots.BridgeBotRegistrationAttempt(
            attemptId: 'attempt-9',
            name: '中文机器人',
            workspaceId: 'project-a',
            status: registrationStatus,
            completedBotId: completedBotId,
          ),
    pendingCredentialOperations: const [
      frb_bots.BridgeBotPendingCredentialOperation(
        botId: 'bot-frb-1',
        credentialOperation:
            frb_bots.BridgeBotCredentialOperation.commitUncertain(
              operationId: 'op-cu-1',
            ),
        diagnostic: frb_bots.BridgeBotDiagnostic(
          code: 'commit_uncertain',
          message: '保存结果未知，等待核实',
          retryable: true,
          platformCode: '23200',
        ),
      ),
    ],
  );
}

frb_topic.BridgeProductTopicStreamEnvelope _baselineEnvelope(
  frb_bots.BridgeBotsStateSnapshot snapshot,
) {
  return frb_topic.BridgeProductTopicStreamEnvelope.baseline(
    topic: const frb_topic.BridgeProductTopic.bots(),
    revision: snapshot.revision,
    state: frb_topic.BridgeProductBaseline.bots(snapshot),
  );
}

frb_topic.BridgeProductTopicStreamEnvelope _dataEnvelope(
  String eventId,
  BigInt sequence,
  frb_bots.BridgeBotsStateSnapshot snapshot,
) {
  return frb_topic.BridgeProductTopicStreamEnvelope.data(
    event: frb_event.BridgeProductEventEnvelope(
      eventId: eventId,
      sequence: sequence,
      createdAt: 1718000100,
      payload: frb_event.BridgeProductEventPayload.botsStateChanged(snapshot),
    ),
  );
}

/// Maps real FRB envelopes for the bots topic through the production public
/// mapper. Other topics keep the demo behavior; the bots stream stays open
/// because only the registry owns cancellation.
final class _FrbEnvelopeBotsTransport extends RecordingDemoTransport {
  _FrbEnvelopeBotsTransport(this.baseline);

  final frb_topic.BridgeProductTopicStreamEnvelope baseline;
  StreamController<ProductTopicFrame>? _bots;

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    if (topic == const BotsTopic()) {
      late final StreamController<ProductTopicFrame> controller;
      controller = StreamController<ProductTopicFrame>(
        onListen: () {
          controller.add(productTopicFrameFromEnvelope(topic, baseline)!);
        },
      );
      _bots = controller;
      return controller.stream;
    }
    return super.subscribeProductTopic(topic);
  }

  void emitBots(frb_topic.BridgeProductTopicStreamEnvelope envelope) {
    final frame = productTopicFrameFromEnvelope(const BotsTopic(), envelope);
    if (frame != null) {
      _bots?.add(frame);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'FRB baseline envelope maps bot config, connection, credential and pending',
    () {
      final frame = productTopicFrameFromEnvelope(
        const BotsTopic(),
        _baselineEnvelope(
          _frbSnapshot(
            revision: BigInt.from(7),
            registrationStatus:
                const frb_bots.BridgeBotRegistrationStatus.committing(
                  attemptId: 'attempt-9',
                  botId: 'bot-frb-1',
                ),
          ),
        ),
      )!;

      expect(frame, isA<ProductTopicBaselineFrame>());
      final baseline = frame as ProductTopicBaselineFrame;
      expect(baseline.topic, const BotsTopic());
      expect(baseline.revision, 7);
      final state = baseline.state;
      expect(state, isA<BotsBaseline>());
      final snapshot = (state as BotsBaseline).state;
      expect(snapshot.revision, 7);
      expect(snapshot.updatedAt, 1718000000);

      final bot = snapshot.bots.single;
      expect(bot.id, 'bot-frb-1');
      expect(bot.name, '中文机器人');
      expect(bot.workspaceId, 'project-a');
      expect(bot.appId, 'cli_frb_1');
      expect(bot.platform, BotPlatform.feishuChina);
      expect(bot.enabled, isTrue);
      expect(bot.toolsEnabled, isFalse);
      expect(bot.workspacePath, 'C:/Studio/v2/bots/bot-frb-1/workspace');
      expect(bot.lastActivityAt, 1718000040);
      expect(
        bot.modelRoute,
        const BotModelRoute(
          accountId: 'account-a',
          modelId: 'model-a',
          effort: 'high',
        ),
      );
      expect(bot.configRevision, 3);
      expect(bot.trustedOpenIds, ['ou_trusted_1']);
      expect(bot.trustedChatIds, ['oc_trusted_1', 'oc_trusted_2']);
      expect(
        bot.connection,
        const BotConnectionReconnecting(nextAttemptAt: 1718000060, attempt: 2),
      );
      expect(bot.credential, BotCredentialAvailability.sessionOnly);
      expect(
        bot.credentialOperation,
        const BotCredentialOperationCommitUncertain(operationId: 'op-cu-1'),
      );
      expect(bot.pairing.single.requestId, 'pair-1');
      expect(bot.pairing.single.displayName, '配对用户');
      expect(bot.canChangeProject, isTrue);
      expect(bot.canChangeAppId, isFalse);
      expect(bot.createdAt, 1718000000);
      expect(bot.updatedAt, 1718000050);

      final pending = snapshot.pendingCredentialOperations.single;
      expect(pending.botId, 'bot-frb-1');
      expect(
        pending.credentialOperation,
        const BotCredentialOperationCommitUncertain(operationId: 'op-cu-1'),
      );
      expect(pending.diagnostic?.platformCode, '23200');
      expect(pending.diagnostic?.retryable, isTrue);

      final registration = snapshot.registration!;
      expect(registration.attemptId, 'attempt-9');
      final committing = registration.status;
      expect(committing, isA<BotRegistrationCommitting>());
      expect((committing as BotRegistrationCommitting).botId, 'bot-frb-1');
      // Committing carries no URL material; the safe bot id must survive.
      expect(committing.verificationUrl, isNull);
    },
  );

  test(
    'FRB data envelopes keep the waiting URL typed and terminal identity',
    () {
      final waitingFrame = productTopicFrameFromEnvelope(
        const BotsTopic(),
        _dataEnvelope(
          'evt-wait',
          BigInt.one,
          _frbSnapshot(
            revision: BigInt.from(8),
            registrationStatus:
                const frb_bots.BridgeBotRegistrationStatus.waiting(
                  attemptId: 'attempt-9',
                  verificationUrl: _verificationUrl,
                  expiresAt: 1718000400,
                  intervalSeconds: 5,
                ),
          ),
        ),
      )!;

      expect(waitingFrame, isA<ProductTopicDataFrame>());
      final waitingData = waitingFrame as ProductTopicDataFrame;
      // The topic is derived from the typed payload, not from a string label.
      expect(waitingData.topic, const BotsTopic());
      expect(waitingData.event.eventId, 'evt-wait');
      expect(waitingData.event.sequence, BigInt.one);
      expect(
        waitingData.event.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1718000100 * 1000),
      );
      final waitingPayload = waitingData.event.payload;
      expect(waitingPayload, isA<BotsStateChangedPayload>());
      final waitingState = (waitingPayload as BotsStateChangedPayload).state;
      final waiting = waitingState.registration!.status;
      expect(waiting, isA<BotRegistrationWaiting>());
      // The URL stays available as typed in-memory data for the QR surface.
      expect(
        (waiting as BotRegistrationWaiting).verificationUrl,
        _verificationUrl,
      );
      expect(waiting.expiresAt, 1718000400);
      expect(waiting.intervalSeconds, 5);
      // Printed representations never carry the raw material.
      expect(waiting.toString(), contains('<redacted>'));
      expect(waiting.toString(), isNot(contains('accounts.feishu.cn')));
      expect(
        waitingState.registration.toString(),
        isNot(contains('FRB-SECRET-9f2')),
      );

      final terminalFrame = productTopicFrameFromEnvelope(
        const BotsTopic(),
        _dataEnvelope(
          'evt-done',
          BigInt.two,
          _frbSnapshot(
            revision: BigInt.from(9),
            registrationStatus:
                const frb_bots.BridgeBotRegistrationStatus.completed(
                  attemptId: 'attempt-9',
                ),
            completedBotId: 'bot-frb-1',
          ),
        ),
      )!;
      final terminalPayload =
          (terminalFrame as ProductTopicDataFrame).event.payload
              as BotsStateChangedPayload;
      final terminal = terminalPayload.state.registration!;
      expect(terminal.status, isA<BotRegistrationCompleted>());
      // Terminal states clear the URL but keep the safe completed identity.
      expect(terminal.status.verificationUrl, isNull);
      expect(terminal.completedBotId, 'bot-frb-1');
    },
  );

  test(
    'Driver bots facts follow FRB-mapped frames without leaking URL material',
    () async {
      final transport = _FrbEnvelopeBotsTransport(
        _baselineEnvelope(
          _frbSnapshot(
            revision: BigInt.from(7),
            registrationStatus:
                const frb_bots.BridgeBotRegistrationStatus.committing(
                  attemptId: 'attempt-9',
                  botId: 'bot-frb-1',
                ),
          ),
        ),
      );
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'bots-frb-driver',
      );
      final client = graph.client;
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      await client.bootstrap();
      final scope = client.channels.acquireSettingsScope(
        BridgeSettingsScopeKind.bots,
        null,
      );
      addTearDown(scope.release);
      await client.bots.source.waitFor(
        (clock) => clock.loaded && clock.revision == 7,
      );

      final timeline = graph.timeline;

      Map<String, dynamic> driverJson() => jsonDecode(
        StudioDriverState.snapshotJson(
          observed: queryStudioDriverFacts(
            client,
            accountsRepository: graph.accounts,
            modelsRepository: graph.models,
            usageRepository: graph.accountUsage,
            acpService: graph.acp,
            timeline: timeline,
          ),
        ),
      ) as Map<String, dynamic>;

      final committingJson = driverJson();
      final committingBots = committingJson['bots'] as Map<String, dynamic>;
      expect(committingBots['registrationKind'], 'committing');
      // No URL exists yet in Committing; the safe pending bot id must survive.
      expect(committingBots['registrationBotId'], 'bot-frb-1');
      final committingBot =
          (committingBots['bots'] as List).single as Map<String, dynamic>;
      expect(committingBot['id'], 'bot-frb-1');
      expect(committingBot['connectionKind'], 'reconnecting');
      expect(committingBot['credential'], 'sessionOnly');
      expect(committingBot['pendingKind'], 'commitUncertain');
      expect(committingBot['trustedUserCount'], 1);
      expect(committingBot['trustedGroupCount'], 2);
      expect(committingBot['pairingCount'], 1);
      expect(committingBot['canChangeProject'], isTrue);
      expect(committingBot['canChangeAppId'], isFalse);
      final committingPending =
          (committingBots['pending'] as List).single as Map<String, dynamic>;
      expect(committingPending['botId'], 'bot-frb-1');
      expect(committingPending['kind'], 'commitUncertain');
      final committingEncoded = jsonEncode(committingJson);
      expect(committingEncoded, isNot(contains('verificationUrl')));
      expect(committingEncoded, isNot(contains('secret')));

      transport.emitBots(
        _dataEnvelope(
          'evt-wait',
          BigInt.one,
          _frbSnapshot(
            revision: BigInt.from(8),
            registrationStatus:
                const frb_bots.BridgeBotRegistrationStatus.waiting(
                  attemptId: 'attempt-9',
                  verificationUrl: _verificationUrl,
                  expiresAt: 1718000400,
                  intervalSeconds: 5,
                ),
          ),
        ),
      );
      await client.bots.source.waitFor((clock) => clock.revision == 8);
      final waitingJson = driverJson();
      final waitingBots = waitingJson['bots'] as Map<String, dynamic>;
      expect(waitingBots['registrationKind'], 'waiting');
      expect(waitingBots['registrationBotId'], isNull);
      final waitingEncoded = jsonEncode(waitingJson);
      expect(waitingEncoded, isNot(contains('accounts.feishu.cn')));
      expect(waitingEncoded, isNot(contains('FRB-SECRET-9f2')));
      expect(waitingEncoded, isNot(contains('verificationUrl')));
      // Typed memory still holds the URL for the local QR surface only.
      final waitingStatus =
          client.bots.state.value!.registration!.status
              as BotRegistrationWaiting;
      expect(waitingStatus.verificationUrl, _verificationUrl);

      transport.emitBots(
        _dataEnvelope(
          'evt-done',
          BigInt.two,
          _frbSnapshot(
            revision: BigInt.from(9),
            registrationStatus:
                const frb_bots.BridgeBotRegistrationStatus.completed(
                  attemptId: 'attempt-9',
                ),
            completedBotId: 'bot-frb-1',
          ),
        ),
      );
      await client.bots.source.waitFor((clock) => clock.revision == 9);
      final completedBots = driverJson()['bots'] as Map<String, dynamic>;
      expect(completedBots['registrationKind'], 'completed');
      expect(completedBots['completedBotId'], 'bot-frb-1');
      // Terminal states drop the URL material from typed state as well.
      expect(
        client.bots.state.value!.registration!.status.verificationUrl,
        isNull,
      );
    },
  );
}
