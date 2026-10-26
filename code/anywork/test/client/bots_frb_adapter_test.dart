import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/infrastructure/frb/products/bots/state_values.dart';
import 'package:anywork/src/rust/api/studio/products/identity.dart'
    as frb_identity;
import 'package:anywork/src/rust/api/studio/products/read/bots.dart'
    as frb_feed;
import 'package:anywork/src/rust/api/studio/products/source.dart' as frb_source;
import 'package:anywork/src/rust/api/studio/types/bots.dart' as frb_bots;
import 'package:anywork/src/shared/driver_bots_projection.dart';
import 'package:anywork/src/shared/driver_snapshot_json.dart';
import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/scripted_feed.dart';

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
    projectId: 'project-a',
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
            projectId: 'project-a',
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

frb_identity.BridgeProductProjectionStamp _stamp(BigInt revision) =>
    frb_identity.BridgeProductProjectionStamp(
      ownerEpoch: 'bots-native',
      incarnation: BigInt.one,
      revision: revision,
    );

frb_feed.BridgeBotsHeader _header(frb_bots.BridgeBotsStateSnapshot snapshot) =>
    frb_feed.BridgeBotsHeader(
      source: frb_source.BridgeObservedHeader(
        brief: frb_source.BridgeObservedBrief.ready(
          revision: snapshot.revision,
          updatedAt: snapshot.updatedAt,
        ),
        status: frb_identity.BridgeProductSourceStatusRef(
          entry: BigInt.one,
          revision: snapshot.revision,
        ),
      ),
      botsRevision: snapshot.revision,
      updatedAt: snapshot.updatedAt,
    );

frb_feed.BridgeBotsFrame _baselineEnvelope(
  frb_bots.BridgeBotsStateSnapshot snapshot,
) {
  return frb_feed.BridgeBotsFrame.data(
    deliverySequence: BigInt.one,
    event: frb_feed.BridgeBotsEvent.baseline(
      identity: frb_identity.BridgeProductFeedIdentity(
        feedId: 'bots-frb-feed',
        ownerEpoch: 'bots-native',
        incarnation: BigInt.one,
        resource: frb_identity.BridgeProductResource.bots,
      ),
      stamp: _stamp(snapshot.revision),
      header: _header(snapshot),
      state: snapshot,
    ),
  );
}

frb_feed.BridgeBotsFrame _dataEnvelope(
  BigInt sequence,
  frb_bots.BridgeBotsStateSnapshot snapshot,
) {
  return frb_feed.BridgeBotsFrame.data(
    deliverySequence: sequence,
    event: frb_feed.BridgeBotsEvent.stateChanged(
      stamp: _stamp(snapshot.revision),
      baseRevision: snapshot.revision - BigInt.one,
      header: _header(snapshot),
      state: snapshot,
    ),
  );
}

/// Maps real FRB envelopes for the bots topic through the production public
/// mapper. Other topics keep the demo behavior; the bots stream stays open
/// because only the registry owns cancellation.
final class _FrbEnvelopeBotsTransport implements BotsPort {
  _FrbEnvelopeBotsTransport(this.baseline);

  final frb_feed.BridgeBotsFrame baseline;
  final feed = ScriptedFeed<BotsFrame>(
    feedId: 'bots-frb-feed',
    sequenceOf: (frame) => frame is BotsData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! BotsData,
  );

  @override
  Future<FeedConnection<BotsFrame>> openBots() async {
    unawaited(
      feed.listened.future.then(
        (_) => feed.emit(botsFrameFromBridge(baseline)),
      ),
    );
    return feed;
  }

  void emitBots(frb_feed.BridgeBotsFrame envelope) =>
      feed.emit(botsFrameFromBridge(envelope));

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Bots capability: ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'FRB baseline envelope maps bot config, connection, credential and pending',
    () {
      final frame = botsFrameFromBridge(
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

      expect(frame, isA<BotsData>());
      final data = frame as BotsData;
      expect(data.deliverySequence, 1);
      final state = data.event;
      expect(state, isA<BotsBaseline>());
      final baseline = state as BotsBaseline;
      expect(baseline.identity.resource, ProductResource.bots);
      expect(baseline.identity.ownerEpoch, 'bots-native');
      expect(baseline.identity.incarnation, 1);
      expect(
        baseline.stamp,
        const ProductProjectionStamp(
          ownerEpoch: 'bots-native',
          incarnation: 1,
          revision: 7,
        ),
      );
      final snapshot = baseline.state!;
      expect(snapshot.revision, 7);
      expect(snapshot.updatedAt, 1718000000);

      final bot = snapshot.bots.single;
      expect(bot.id, 'bot-frb-1');
      expect(bot.name, '中文机器人');
      expect(bot.projectId, 'project-a');
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
      expect(_verificationOf(committing), isNull);
    },
  );

  test(
    'FRB data envelopes keep the waiting URL typed and terminal identity',
    () {
      final waitingFrame = botsFrameFromBridge(
        _dataEnvelope(
          BigInt.two,
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

      expect(waitingFrame, isA<BotsData>());
      final waitingData = waitingFrame as BotsData;
      // Typed domain frames replace generic topic/event metadata. Baseline also
      // consumes one delivery; projection identity and ordering remain exact.
      expect(waitingData.deliverySequence, 2);
      final waitingPayload = waitingData.event;
      expect(waitingPayload, isA<BotsStateChangedPayload>());
      final change = waitingPayload as BotsStateChangedPayload;
      expect(
        change.stamp,
        const ProductProjectionStamp(
          ownerEpoch: 'bots-native',
          incarnation: 1,
          revision: 8,
        ),
      );
      expect(change.baseRevision, 7);
      expect(change.header.botsRevision, 8);
      final waitingState = change.state!;
      expect(waitingState.revision, 8);
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

      final terminalFrame = botsFrameFromBridge(
        _dataEnvelope(
          BigInt.from(3),
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
      final terminalPayload =
          (terminalFrame as BotsData).event as BotsStateChangedPayload;
      expect(terminalFrame.deliverySequence, 3);
      expect(
        terminalPayload.stamp,
        const ProductProjectionStamp(
          ownerEpoch: 'bots-native',
          incarnation: 1,
          revision: 9,
        ),
      );
      expect(terminalPayload.baseRevision, 8);
      expect(terminalPayload.state!.revision, 9);
      final terminal = terminalPayload.state!.registration!;
      expect(terminal.status, isA<BotRegistrationCompleted>());
      // Terminal states clear the URL but keep the safe completed identity.
      expect(_verificationOf(terminal.status), isNull);
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
      final budget = ResourceBudget();
      final operations = OperationRegistry(
        clientId: 'bots-frb-driver',
        budget: budget,
      );
      final bots = createBotsRepository(
        port: transport,
        budget: budget,
        operations: operations,
      );
      addTearDown(() async {
        expect((await bots.close()).complete, isTrue);
        operations.seal();
        expect(budget.usage, isEmpty);
      });
      await bots.synchronize();
      await transport.feed.acknowledged(1);
      expect(bots.state.value.projection.stamp!.revision, 7);
      expect(transport.feed.acknowledgements, [1]);

      Map<String, dynamic> driverJson() => jsonDecode(
        jsonEncode({
          'bots': botsDiagnostic(projectBotsState(bots.state.value)),
        }),
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
          BigInt.two,
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
      await transport.feed.acknowledged(2);
      expect(bots.state.value.projection.stamp!.revision, 8);
      expect(transport.feed.acknowledgements, [1, 2]);
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
          bots.state.value.snapshot!.value.registration!.status
              as BotRegistrationWaiting;
      expect(waitingStatus.verificationUrl, _verificationUrl);

      transport.emitBots(
        _dataEnvelope(
          BigInt.from(3),
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
      await transport.feed.acknowledged(3);
      expect(bots.state.value.projection.stamp!.revision, 9);
      expect(transport.feed.acknowledgements, [1, 2, 3]);
      final completedBots = driverJson()['bots'] as Map<String, dynamic>;
      expect(completedBots['registrationKind'], 'completed');
      expect(completedBots['completedBotId'], 'bot-frb-1');
      // Terminal states drop the URL material from typed state as well.
      expect(
        _verificationOf(bots.state.value.snapshot!.value.registration!.status),
        isNull,
      );
    },
  );
}

// Authorization material exists only on these two typed variants. In
// particular Committing and every terminal variant cannot retain a URL field.
String? _verificationOf(BotRegistrationStatus value) => switch (value) {
  BotRegistrationWaiting(:final verificationUrl) ||
  BotRegistrationSlowDown(:final verificationUrl) => verificationUrl,
  _ => null,
};
