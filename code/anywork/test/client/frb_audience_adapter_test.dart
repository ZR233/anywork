import 'dart:async';

import 'package:anywork/src/domain/models/audience_delivery_presentation.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/frb_generated.dart';
import 'package:anywork/src/rust/api/studio/subscription.dart' as sub;
import 'package:anywork/src/rust/api/studio/types/bot_audience.dart'
    as delivery;
import 'package:anywork/src/rust/api/studio/types/thread_audience.dart'
    as audience;
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart' as thread;
import 'package:anywork/src/rust/api/studio/types/delegation.dart'
    as delegation;
import 'package:anywork/src/rust/api/studio/types/bots.dart' as bots;
import 'package:anywork/src/rust/api/studio/types/command.dart' as command;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Subscription implements sub.BridgeEventSubscription {
  _Subscription(this.updates);
  final List<thread.BridgeThreadSubscriptionUpdate> updates;
  int cancelled = 0;
  int disposed = 0;
  @override
  Stream<sub.BridgeThreadStreamEnvelope> threadStream() => Stream.fromIterable([
    for (final update in updates)
      sub.BridgeThreadStreamEnvelope.data(update: update),
  ]);
  @override
  Future<void> cancel() async {
    cancelled++;
  }

  @override
  void dispose() {
    disposed++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused opaque capability');
}

final class _Wire implements RustLibApi {
  _Subscription? subscription;
  delivery.BridgeReadThreadAudienceItemsReply? readReply;
  delivery.BridgeChangeBotThreadSyncRequest? syncRequest;
  delivery.BridgeReadThreadAudienceItemsRequest? itemRequest;
  delivery.BridgeReadThreadClosedAuthorizationsRequest? historyRequest;
  @override
  Future<sub.BridgeEventSubscription>
  crateApiStudioSubscriptionThreadSubscribeThread({
    required String threadId,
  }) async => subscription!;
  @override
  Future<delivery.BridgeReadThreadAudienceItemsReply>
  crateApiStudioHandlersBotsReadThreadAudienceItems({
    required delivery.BridgeReadThreadAudienceItemsRequest request,
  }) async {
    itemRequest = request;
    return readReply!;
  }

  @override
  Future<delivery.BridgeReadThreadClosedAuthorizationsReply>
  crateApiStudioHandlersBotsReadThreadClosedAuthorizations({
    required delivery.BridgeReadThreadClosedAuthorizationsRequest request,
  }) async {
    historyRequest = request;
    return delivery.BridgeReadThreadClosedAuthorizationsReply(
      threadId: request.threadId,
      result: delivery.BridgeThreadClosedAuthorizationsRead.page(
        page: delivery.BridgeThreadClosedAuthorizationPage(
          target: _known().target,
          authorizations: [_known().latestClosed!],
          nextCursor: 'opaque-page',
        ),
      ),
    );
  }

  @override
  Future<delivery.BridgeChangeBotThreadSyncReply>
  crateApiStudioHandlersBotsChangeBotThreadSync({
    required delivery.BridgeChangeBotThreadSyncRequest request,
  }) async {
    syncRequest = request;
    return delivery.BridgeChangeBotThreadSyncReply(
      threadId: request.threadId,
      audience: audience.BridgeThreadAudience.known(audience: _known()),
      state: delivery.BridgeBotThreadSyncCommandState.pendingStart(
        authorization: _ref().id,
      ),
      receipt: command.BridgeStudioCommandReceipt(
        operationId: request.operationId,
        disposition: command.BridgeCommandDisposition.applied,
        targets: [
          command.BridgeResourceStamp(
            resourceKey: 'bot-audience:thread:7',
            ownerEpoch: 'host-epoch',
            revision: BigInt.from(3),
          ),
        ],
        effect: command.BridgeCommandEffectPoint.nextTurn,
        effective: false,
        durable: true,
        requiresIdentityObservation: false,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused generated API ${invocation.memberName}');
}

audience.BridgeBotAuthorizationRef _ref() => audience.BridgeBotAuthorizationRef(
  id: audience.BridgeBotAuthorizationId(
    botId: 'bot',
    chatId: 'chat',
    generation: BigInt.from(7),
  ),
  revision: BigInt.from(3),
);
audience.BridgeBotThreadAudience _known() => audience.BridgeBotThreadAudience(
  target: const audience.BridgeBotAudienceTarget(
    botId: 'bot',
    botName: '机器人',
    chatId: 'chat',
    chatName: '讨论 群',
    kind: bots.BridgeBotConversationKind.group,
  ),
  binding: audience.BridgeBotThreadBindingPosition.current(
    cas: audience.BridgeBotSyncCas(
      bindingRevision: BigInt.from(11),
      authorizationHead: audience.BridgeBotAuthorizationHead.present(
        authorization: _ref(),
      ),
    ),
    sync_: audience.BridgeBotCurrentSync.paused(
      authorization: audience.BridgeBotStartedAuthorization(
        authorization: _ref(),
        bindingRevision: BigInt.from(9),
        start: audience.BridgeBotAudienceStart(
          commitSequence: BigInt.from(13),
          excludedTurnId: 'excluded',
        ),
      ),
    ),
  ),
  latestClosed: audience.BridgeBotClosedAuthorization(
    authorization: audience.BridgeBotAuthorizationRef(
      id: audience.BridgeBotAuthorizationId(
        botId: 'bot',
        chatId: 'chat',
        generation: BigInt.from(6),
      ),
      revision: BigInt.from(99),
    ),
    bindingRevision: BigInt.from(8),
    start: const audience.BridgeBotClosedStart.neverActivated(),
    reason: audience.BridgeBotAudienceCloseReason.startCancelled,
    closedAt: 123,
  ),
  hasOlderClosed: true,
  delivery: audience.BridgeBotDeliverySummary(
    version: BigInt.from(20),
    pendingItems: 16384,
    unknownOperations: 2,
    incompleteItems: 3,
    countsCapped: true,
  ),
  legacyFinal: const audience.BridgeBotLegacyFinalSummary(
    unfinishedChains: 2,
    unknownOperations: 1,
    needsAttention: true,
    countsCapped: false,
  ),
);
thread.BridgeThreadSnapshot _snapshot(audience.BridgeThreadAudience value) =>
    thread.BridgeThreadSnapshot(
      schemaVersion: 17,
      revision: BigInt.from(4),
      audience: value,
      thread: const thread.BridgeThread(
        id: 'thread',
        projectId: 'project',
        title: 'Thread',
        mode: 'mode.simple',
        delegationMode: delegation.BridgeDelegationMode.profile,
        delegationPreference: delegation.BridgeDelegationPreference.balanced,
        workspaceMode: 'local',
        workspacePath: '/workspace',
        rootThreadId: 'thread',
        role: 'planner',
        agentPath: 'root',
        status: thread.BridgeThreadStatus.idle,
        createdAt: 123,
        updatedAt: 124,
        archived: false,
      ),
      interactions: const [],
      runtimeAvailability: thread.BridgeThreadRuntimeAvailability.inactive,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Wire wire;
  setUp(() {
    wire = _Wire();
    RustLib.initMock(api: wire);
    FrbStudioTransport.debugOverrideInitialization(() async {});
  });
  tearDown(() {
    FrbStudioTransport.debugOverrideInitialization(null);
    RustLib.dispose();
  });

  test('snapshot and AudienceChanged preserve typed audience and original continuity envelope', () async {
    wire.subscription = _Subscription([
      thread.BridgeThreadSubscriptionUpdate.snapshot(
        snapshot: _snapshot(const audience.BridgeThreadAudience.unbound()),
      ),
      thread.BridgeThreadSubscriptionUpdate.snapshot(
        snapshot: _snapshot(
          const audience.BridgeThreadAudience.unavailable(
            reason: audience
                .BridgeThreadAudienceUnavailableReason
                .bindingUnavailable,
          ),
        ),
      ),
      thread.BridgeThreadSubscriptionUpdate.snapshot(
        snapshot: _snapshot(
          audience.BridgeThreadAudience.known(audience: _known()),
        ),
      ),
      thread.BridgeThreadSubscriptionUpdate.notification(
        notification: thread.BridgeThreadNotificationEnvelope(
          threadId: 'thread',
          epoch: BigInt.from(8),
          baseRevision: BigInt.from(4),
          revision: BigInt.from(5),
          emittedAt: 125,
          notification: thread.BridgeThreadNotification.audienceChanged(
            audience: audience.BridgeThreadAudience.known(audience: _known()),
          ),
        ),
      ),
    ]);
    final frames = await FrbStudioTransport()
        .subscribeThread('thread')
        .take(4)
        .toList();
    expect(
      (frames[0] as ThreadSnapshotFrame).workspace.audience,
      isA<ThreadAudienceUnbound>(),
    );
    expect(
      (frames[1] as ThreadSnapshotFrame).workspace.audience,
      const ThreadAudienceUnavailable(
        reason: ThreadAudienceUnavailableReason.bindingUnavailable,
      ),
    );
    final known = (frames[2] as ThreadSnapshotFrame).workspace.audience.known!;
    expect(known.target.kind, BotConversationKind.group);
    expect(known.target.chatName, '讨论 群');
    expect(known.delivery.pendingItems, 16384);
    expect(known.delivery.countsCapped, isTrue);
    expect(known.latestClosed!.authorization.id.generation, 6);
    expect(known.latestClosed!.start, isA<BotClosedStartNeverActivated>());
    final started =
        ((known.binding as BotThreadBindingPositionCurrent).sync
                as BotCurrentSyncPaused)
            .authorization;
    expect(started.authorization.id.generation, 7);
    expect(started.bindingRevision, 9);
    expect(started.start.commitSequence, 13);
    expect(started.start.excludedTurnId, 'excluded');
    final change = frames.last as ThreadNotificationFrame;
    expect((change.epoch, change.baseRevision, change.revision), (8, 4, 5));
    expect((change.update as ThreadAudienceUpdate).audience.known, known);
    expect(wire.subscription!.cancelled, 1);
    expect(wire.subscription!.disposed, 1);
  });

  test('queries preserve Missing/Removed, text integrity and independent file upload/message outcomes', () async {
    const rejected = bots.BridgeBotDiagnostic(
      code: 'platform-rejected',
      message: 'rejected',
      retryable: false,
    );
    wire.readReply = delivery.BridgeReadThreadAudienceItemsReply(
      threadId: 'thread',
      authorization: _ref().id,
      result: delivery.BridgeBotAudienceItemsRead.items(
        authorization: _ref(),
        phase: delivery.BridgeBotAuthorizationPhase.paused,
        summaryVersion: BigInt.from(20),
        deliveryVersion: BigInt.from(27),
        items: [
          delivery.BridgeBotAudienceItemStatus(
            itemId: 'text',
            canonical: delivery.BridgeBotAudienceCanonicalItem.present(
              revision: BigInt.from(5),
              saved: false,
              eligibility: const delivery.BridgeBotItemEligibility.text(
                channel: delivery.BridgeBotPublicTextChannel.final_,
              ),
            ),
            delivery: delivery.BridgeBotItemDelivery.known(
              ledger: delivery.BridgeBotItemLedgerSummary(
                observedRevision: BigInt.from(5),
                projected: delivery.BridgeBotItemPresentation.text(
                  revision: BigInt.from(5),
                  integrity: delivery.BridgeBotTextIntegrity.truncated,
                  saved: false,
                ),
                accepted: delivery.BridgeBotItemPresentation.text(
                  revision: BigInt.from(4),
                  integrity: delivery.BridgeBotTextIntegrity.full,
                  saved: true,
                ),
                platform: delivery.BridgeBotItemPlatform.card(
                  latestOperation: delivery.BridgeBotCardOperationSummary(
                    operationId: 'settings-op',
                    contentRevision: BigInt.from(5),
                    action: delivery.BridgeBotCardOperationKind.settings,
                    result: const delivery.BridgeBotPlatformResult.inFlight(),
                  ),
                ),
              ),
            ),
          ),
          delivery.BridgeBotAudienceItemStatus(
            itemId: 'file',
            canonical: delivery.BridgeBotAudienceCanonicalItem.present(
              revision: BigInt.from(3),
              saved: true,
              eligibility:
                  const delivery.BridgeBotItemEligibility.publicArtifact(),
            ),
            delivery: delivery.BridgeBotItemDelivery.known(
              ledger: delivery.BridgeBotItemLedgerSummary(
                observedRevision: BigInt.from(3),
                projected: delivery.BridgeBotItemPresentation.file(
                  revision: BigInt.from(3),
                ),
                accepted: const delivery.BridgeBotItemPresentation.none(),
                platform: delivery.BridgeBotItemPlatform.file(
                  operationId: 'file-op',
                  contentRevision: BigInt.from(3),
                  upload: const delivery.BridgeBotPlatformResult.accepted(),
                  message: const delivery.BridgeBotPlatformResult.rejected(
                    diagnostic: rejected,
                  ),
                  outcome: delivery.BridgeBotFileOutcome.partial,
                ),
              ),
            ),
          ),
          const delivery.BridgeBotAudienceItemStatus(
            itemId: 'missing',
            canonical: delivery.BridgeBotAudienceCanonicalItem.unavailable(
              reason: delivery.BridgeBotCanonicalUnavailableReason.missing,
            ),
            delivery: delivery.BridgeBotItemDelivery.notProjected(),
          ),
          const delivery.BridgeBotAudienceItemStatus(
            itemId: 'removed',
            canonical: delivery.BridgeBotAudienceCanonicalItem.removed(),
            delivery: delivery.BridgeBotItemDelivery.notProjected(),
          ),
        ],
      ),
    );
    final result =
        (await FrbStudioTransport().readThreadAudienceItems(
              ReadThreadAudienceItemsRequest(
                threadId: 'thread',
                authorization: const BotAuthorizationId(
                  botId: 'bot',
                  chatId: 'chat',
                  generation: 7,
                ),
                itemIds: ['text', 'file', 'missing', 'removed'],
              ),
            )).result
            as BotAudienceItemsReadItems;
    expect(wire.itemRequest!.itemIds, ['text', 'file', 'missing', 'removed']);
    expect(
      (
        result.summaryVersion,
        result.deliveryVersion,
        result.authorization.revision,
      ),
      (20, 27, 3),
    );
    final text = AudienceItemDeliveryProjection.fromStatus(
      result.items.first,
      displayRevision: 5,
    );
    expect(text.currentRevisionAccepted, isFalse);
    expect(text.historicalRevisionAccepted, isTrue);
    expect(
      (text.ledger!.projected as BotItemPresentationText).integrity,
      BotTextIntegrity.truncated,
    );
    expect(
      (text.ledger!.platform as BotItemPlatformCard).latestOperation.result,
      isA<BotPlatformResultInFlight>(),
    );
    final file = (result.items[1].delivery as BotItemDeliveryKnown).ledger;
    expect((file.projected as BotItemPresentationFile).revision, 3);
    final platform = file.platform as BotItemPlatformFile;
    expect(platform.upload, isA<BotPlatformResultAccepted>());
    expect(platform.message, isA<BotPlatformResultRejected>());
    expect(platform.outcome, BotFileOutcome.partial);
    expect(
      (result.items[2].canonical as BotAudienceCanonicalItemUnavailable).reason,
      BotCanonicalUnavailableReason.missing,
    );
    expect(result.items[3].canonical, isA<BotAudienceCanonicalItemRemoved>());
  });

  test('control and history map full CAS, stable operation, durable versus effective, and opaque cursor', () async {
    final api = FrbStudioTransport();
    final reply = await api.changeBotThreadSync(
      ChangeBotThreadSyncRequest(
        operationId: 'stable-op',
        threadId: 'thread',
        expected: BotSyncCas(
          bindingRevision: 11,
          authorizationHead: BotAuthorizationHeadPresent(
            authorization: BotAuthorizationRef(
              id: const BotAuthorizationId(
                botId: 'bot',
                chatId: 'chat',
                generation: 7,
              ),
              revision: 3,
            ),
          ),
        ),
        action: BotThreadSyncAction.close,
      ),
    );
    expect(wire.syncRequest!.operationId, 'stable-op');
    expect(wire.syncRequest!.expected.bindingRevision, BigInt.from(11));
    expect(
      wire.syncRequest!.expected.authorizationHead,
      audience.BridgeBotAuthorizationHead.present(authorization: _ref()),
    );
    expect(wire.syncRequest!.action, delivery.BridgeBotThreadSyncAction.close);
    expect(reply.state, isA<BotThreadSyncCommandStatePendingStart>());
    expect(reply.receipt.durable, isTrue);
    expect(reply.receipt.effective, isFalse);
    expect(reply.receipt.targets.single.resourceKey, 'bot-audience:thread:7');
    final history = await api.readThreadClosedAuthorizations(
      const ReadThreadClosedAuthorizationsRequest(
        threadId: 'thread',
        cursor: 'opaque-in',
        limit: 32,
      ),
    );
    expect(wire.historyRequest!.cursor, 'opaque-in');
    expect(wire.historyRequest!.limit, 32);
    expect(
      (history.result as ThreadClosedAuthorizationsReadPage).page.nextCursor,
      'opaque-page',
    );
  });
}
