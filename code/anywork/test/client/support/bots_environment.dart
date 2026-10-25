import 'dart:async';

import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../anywork_client/test/support/profile_native_pin.dart';
import '../../../../anywork_client/test/support/scripted_feed.dart';

/// Native material and dispatch barriers only. Tests supply each authoritative
/// value explicitly; the real Repository owns reduction and operation evidence.
final class BotsTestPort implements BotsPort {
  final feed = ScriptedFeed<BotsFrame>(
    feedId: 'bots-adapter',
    sequenceOf: (frame) => frame is BotsData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! BotsData,
  );
  final saved = Completer<SaveBotRequest>();
  final saveReply = Completer<BotsCommandReply>();
  final started = Completer<StartBotRegistrationRequest>();
  final startReply = Completer<BotsCommandReply>();
  final cancelled = Completer<CancelBotRegistrationRequest>();
  final cancelReply = Completer<BotsCommandReply>();
  static const origin = ProductReadOrigin(
    ownerEpoch: 'bots-native',
    incarnation: 1,
  );

  @override
  Future<FeedConnection<BotsFrame>> openBots() async => feed;

  Future<void> publish(BotsStateSnapshot snapshot) async {
    await feed.listened.future;
    final revision = snapshot.revision;
    final header = BotsHeader(
      source: profileSource(revision),
      botsRevision: revision,
      updatedAt: snapshot.updatedAt,
    );
    feed.emit(
      BotsFrame.data(
        deliverySequence: revision,
        event: revision == 1
            ? BotsEvent.baseline(
                identity: profileIdentity(
                  feed.feedId,
                  origin,
                  ProductResource.bots,
                ),
                stamp: profileStamp(origin, revision),
                header: header,
                state: snapshot,
              )
            : BotsEvent.stateChanged(
                stamp: profileStamp(origin, revision),
                baseRevision: revision - 1,
                header: header,
                state: snapshot,
              ),
      ),
    );
    await feed.acknowledged(revision);
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async => ProfileSourcePin(reference.revision);

  @override
  Future<BotsCommandReply> saveBot(SaveBotRequest request) {
    saved.complete(request);
    return saveReply.future;
  }

  @override
  Future<BotsCommandReply> startBotRegistration(
    StartBotRegistrationRequest request,
  ) {
    started.complete(request);
    return startReply.future;
  }

  @override
  Future<BotsCommandReply> cancelBotRegistration(
    CancelBotRegistrationRequest request,
  ) {
    cancelled.complete(request);
    return cancelReply.future;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Bots native capability: ${invocation.memberName}',
  );
}

BotsCommandReply botsReply(
  OperationId operationId,
  int revision, {
  BotSnapshot? bot,
  BotRegistrationAttempt? registration,
}) {
  final stamp = ResourceStamp(
    resourceKey: 'bots',
    ownerEpoch: 'bots-native',
    revision: revision,
  );
  return BotsCommandReply(
    bot: bot,
    registration: registration,
    stamp: stamp,
    receipt: CommitReceipt(
      operationId: operationId,
      disposition: CommitDisposition.applied,
      targets: [stamp],
      effect: EffectPoint.immediate,
    ),
  );
}

final savedBot = BotSnapshot(
  id: 'bot-1',
  name: 'Feishu China',
  projectId: 'project-local',
  appId: 'cli_demo',
  platform: BotPlatform.feishuChina,
  enabled: true,
  toolsEnabled: true,
  modelRoute: null,
  workspacePath: '/bots/bot-1',
  lastActivityAt: null,
  configRevision: 1,
  trustedOpenIds: [],
  trustedChatIds: [],
  connection: const BotConnectionDisabled(),
  credential: BotCredentialAvailability.stored,
  credentialOperation: const BotCredentialOperationIdle(),
  pairing: [],
  diagnostic: null,
  canChangeProject: true,
  canChangeAppId: true,
  createdAt: 1,
  updatedAt: 1,
);

BotRegistrationAttempt waitingRegistration(String name) =>
    BotRegistrationAttempt(
      attemptId: 'attempt-1',
      name: name,
      projectId: 'project-local',
      completedBotId: null,
      status: const BotRegistrationWaiting(
        attemptId: 'attempt-1',
        verificationUrl: 'https://accounts.feishu.cn/wait',
        expiresAt: 9,
        intervalSeconds: 5,
      ),
    );

BotsStateSnapshot botsSnapshot(
  int revision, {
  List<BotSnapshot> bots = const [],
  BotRegistrationAttempt? registration,
}) => BotsStateSnapshot(
  revision: revision,
  updatedAt: revision,
  bots: bots,
  registration: registration,
  pendingCredentialOperations: const [],
);
