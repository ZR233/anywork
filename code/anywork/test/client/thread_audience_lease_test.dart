import 'package:anywork/src/domain/models/audience_delivery_presentation.dart';
import 'package:anywork/src/domain/models/timeline_presentation.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/providers/thread_audience_provider.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Shared scripted environment only; both suites exercise the public Client.
import '../../../anywork_client/test/support/audience_fixture.dart';

ReadThreadAudienceItemsReply _receiptReply(
  AudienceReadCall call, {
  required int summaryVersion,
  required int deliveryVersion,
  required BotPlatformResult platform,
  required bool accepted,
  int controlRevision = 1,
}) => ReadThreadAudienceItemsReply(
  threadId: call.request.threadId,
  authorization: call.request.authorization,
  result: BotAudienceItemsReadItems(
    authorization: BotAuthorizationRef(
      id: call.request.authorization,
      revision: controlRevision,
    ),
    phase: BotAuthorizationPhase.active,
    summaryVersion: summaryVersion,
    deliveryVersion: deliveryVersion,
    items: [
      for (final id in call.request.itemIds)
        BotAudienceItemStatus(
          itemId: id,
          canonical: const BotAudienceCanonicalItemPresent(
            revision: 1,
            saved: true,
            eligibility: BotItemEligibilityText(
              channel: BotPublicTextChannel.finalAnswer,
            ),
          ),
          delivery: BotItemDeliveryKnown(
            ledger: BotItemLedgerSummary(
              observedRevision: 1,
              projected: const BotItemPresentationText(
                revision: 1,
                integrity: BotTextIntegrity.full,
                saved: true,
              ),
              accepted: accepted
                  ? const BotItemPresentationText(
                      revision: 1,
                      integrity: BotTextIntegrity.full,
                      saved: true,
                    )
                  : const BotItemPresentationNone(),
              platform: BotItemPlatformCard(
                latestOperation: BotCardOperationSummary(
                  operationId: 'card-operation-$deliveryVersion',
                  contentRevision: 1,
                  action: BotCardOperationKind.content,
                  result: platform,
                ),
              ),
            ),
          ),
        ),
    ],
  ),
);

StudioTimelineItem _thinking(String id, int ordinal) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    state: ThreadThinkingItemStateView(
      summary: const ['bounded preview'],
      content: const [],
      lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
    ),
  ),
  saved: true,
  lifecycle: StudioTimelineLifecycle.terminal,
  omittedBytes: 0,
  details: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('summary invalidation hides cached receipts while an older read is still pending', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    final scope = client.audienceQueries.openScope('thread', 1);
    addTearDown(() async {
      // Drain accepted test transport work even if a freshness assertion fails.
      scope.retire();
      for (final call in transport.reads) {
        if (!call.result.isCompleted) {
          call.result.complete(
            ReadThreadAudienceItemsReply(
              threadId: call.request.threadId,
              authorization: call.request.authorization,
              result: const BotAudienceItemsReadUnavailable(
                reason: BotAudienceItemsUnavailableReason.scopeChanged,
              ),
            ),
          );
        }
      }
      await scope.close();
      await client.close();
    });
    final session = client.session('thread');
    session.applySnapshot(audienceWorkspace(knownAudience()));
    scope.setVisible({'canonical-A': 1});
    final first = await transport.nextRead();
    first.result.complete(
      _receiptReply(
        first,
        summaryVersion: 1,
        deliveryVersion: 10,
        platform: const BotPlatformResultAccepted(),
        accepted: true,
      ),
    );
    await scope.source.waitFor((value) => value.deliveryVersion == 10);
    expect(
      (scope.state.items['canonical-A']!.delivery as BotItemDeliveryKnown)
          .ledger
          .accepted,
      isA<BotItemPresentationText>(),
    );
    scope.retry();
    final blocked = await transport.nextRead();
    session.applyNotification(
      ThreadNotificationFrame(
        threadId: 'thread',
        revision: 2,
        epoch: 1,
        baseRevision: 1,
        update: ThreadAudienceUpdate(knownAudience(summaryVersion: 2)),
      ),
    );
    // Same auth/control reference and same canonical item revision do not prove
    // the old ledger is fresh after its summary invalidates it.
    expect(scope.state.authorization, authorization(1, 1));
    expect(
      scope.state.items,
      isEmpty,
      reason: 'old Accepted must not be exposed as current while waiting for an old read',
    );
    expect(scope.state.loading, isTrue);
    expect(scope.state.summaryVersion, isNull);
    expect(
      transport.reads,
      hasLength(2),
      reason: 'do not run another chain behind the blocked read',
    );
    blocked.result.complete(
      _receiptReply(
        blocked,
        summaryVersion: 1,
        deliveryVersion: 10,
        platform: const BotPlatformResultAccepted(),
        accepted: true,
      ),
    );
    final latest = await transport.nextRead();
    expect(
      scope.state.items,
      isEmpty,
      reason: 'the stale completion cannot republish its old receipt',
    );
    expect(scope.state.loading, isTrue);
    latest.result.complete(
      _receiptReply(
        latest,
        summaryVersion: 2,
        deliveryVersion: 11,
        platform: const BotPlatformResultUnknown(
          diagnostic: BotDiagnostic(
            code: 'unknown',
            message: 'unconfirmed',
            retryable: false,
          ),
        ),
        accepted: false,
      ),
    );
    await scope.source.waitFor((value) => value.deliveryVersion == 11);
    expect(scope.state.summaryVersion, 2);
    final ledger =
        (scope.state.items['canonical-A']!.delivery as BotItemDeliveryKnown)
            .ledger;
    expect(ledger.accepted, isA<BotItemPresentationNone>());
    expect(
      (ledger.platform as BotItemPlatformCard).latestOperation.result,
      isA<BotPlatformResultUnknown>(),
    );
  });

  test('display demand uses canonical group members, shares observers and only releases its own resources', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    client.session('thread').applySnapshot(audienceWorkspace(knownAudience()));
    client.composer('thread').updateDraft('keep input and ownership');
    final lease = TimelineDisplayLease(
      threadId: 'thread',
      generation: 1,
      openQueries: (_) => null,
      openAudience: () => client.audienceQueries.openScope('thread', 1),
    );
    lease.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'sub',
        version: 1,
        before: null,
        items: [_thinking('canonical-A', 1), _thinking('canonical-B', 2)],
        hasOlder: false,
      ),
    );
    final group = timelinePresentationOf(lease.controller.messages.single)!;
    expect(group.visibleMemberIds, ['canonical-A', 'canonical-B']);
    final scope = lease.audience!;
    final firstRow = Object(), repeatedRow = Object();
    lease.setAudienceDemand(firstRow, group.visibleMemberIds);
    lease.setAudienceDemand(repeatedRow, group.visibleMemberIds);
    final request = await transport.nextRead();
    expect(request.request.itemIds, ['canonical-A', 'canonical-B']);
    expect(request.request.itemIds, isNot(contains(group.id)));
    request.complete();
    await scope.source.waitFor((value) => value.items.length == 2);
    final container = ProviderContainer(
      overrides: [anyworkClientProvider.overrideWithValue(client)],
    );
    final before = client.budget.used(ResourceKind.observer);
    final first = container.listen(
      threadAudienceItemsProvider(scope),
      (_, _) {},
    );
    final second = container.listen(
      threadAudienceItemsProvider(scope),
      (_, _) {},
    );
    expect(
      client.budget.used(ResourceKind.observer),
      before + 1,
      reason: 'the provider shares one budgeted observation',
    );
    first.close();
    second.close();
    await container.pump();
    container.dispose();
    expect(client.budget.used(ResourceKind.observer), before);
    expect(scope.isActive, isTrue);
    expect(transport.reads.length, 1);
    expect(client.composer('thread').state.draft, 'keep input and ownership');
    lease.removeAudienceDemand(firstRow);
    lease.removeAudienceDemand(repeatedRow);
    await Future<void>.value();
    await lease.retire();
    expect(lease.isReleased, isTrue);
    expect(transport.reads.length, 1);
    expect(client.composer('thread').state.draft, 'keep input and ownership');
  });

  test('retiring a display joins the actual audience read; its late result cannot publish into a fresh lease', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    client.session('thread').applySnapshot(audienceWorkspace(knownAudience()));
    TimelineDisplayLease display(int generation) {
      final lease = TimelineDisplayLease(
        threadId: 'thread',
        generation: generation,
        openQueries: (_) => null,
        openAudience: () =>
            client.audienceQueries.openScope('thread', generation),
      );
      lease.adoptBaseline(
        StudioTimelineBaseline(
          subscriptionId: 'sub-$generation',
          version: 1,
          before: null,
          items: [_thinking('canonical-A', 1)],
          hasOlder: false,
        ),
      );
      return lease;
    }

    final old = display(1);
    final oldScope = old.audience!;
    final container = ProviderContainer(
      overrides: [anyworkClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final observation = container.listen(
      threadAudienceItemsProvider(oldScope),
      (_, _) {},
    );
    old.setAudienceDemand(Object(), ['canonical-A']);
    final first = await transport.nextRead();
    var released = false;
    final retiring = old.retire().then((_) => released = true);
    final fresh = display(2);
    final freshScope = fresh.audience!;
    fresh.setAudienceDemand(Object(), ['canonical-A']);
    final latest = await transport.nextRead();
    latest.complete(deliveryVersion: 2);
    await freshScope.source.waitFor((value) => value.deliveryVersion == 2);
    expect(released, isFalse);
    first.complete(deliveryVersion: 1);
    await retiring;
    await container.pump();
    container.invalidate(threadAudienceItemsProvider(oldScope));
    expect(
      container.read(threadAudienceItemsProvider(oldScope)).items,
      isEmpty,
    );
    observation.close();
    expect(oldScope.state.items, isEmpty);
    expect(freshScope.state.deliveryVersion, 2);
    expect(freshScope.state.items.keys, ['canonical-A']);
    await fresh.retire();
    await client.close();
    // These same-source projections may also rebuild with a closed AppGraph.
    // They borrow final values without admitting a fresh Session observation.
    container.read(threadAudienceProvider('thread'));
    container.read(threadSyncProgressProvider('thread'));
    expect(client.budget.used(ResourceKind.observer), 0);
  });

  test('a control revision change on the same generation stops current Accepted receipts', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    final scope = client.audienceQueries.openScope('thread', 1);
    addTearDown(() async {
      scope.retire();
      for (final call in transport.reads) {
        if (!call.result.isCompleted) {
          call.result.complete(
            ReadThreadAudienceItemsReply(
              threadId: call.request.threadId,
              authorization: call.request.authorization,
              result: const BotAudienceItemsReadUnavailable(
                reason: BotAudienceItemsUnavailableReason.scopeChanged,
              ),
            ),
          );
        }
      }
      await scope.close();
      await client.close();
    });
    final session = client.session('thread');
    session.applySnapshot(audienceWorkspace(knownAudience()));
    scope.setVisible({'canonical-A': 1});
    final first = await transport.nextRead();
    first.result.complete(
      _receiptReply(
        first,
        summaryVersion: 1,
        deliveryVersion: 10,
        platform: const BotPlatformResultAccepted(),
        accepted: true,
      ),
    );
    await scope.source.waitFor((value) => value.deliveryVersion == 10);
    expect(
      AudienceItemDeliveryProjection.fromStatus(
        scope.state.items['canonical-A']!,
        displayRevision: 1,
      ).currentRevisionAccepted,
      isTrue,
    );
    // Pause advances only the authorization control revision. The canonical
    // item revision and the delivery watermark stay identical, so only the
    // control version can prove the cached receipt is stale.
    session.applyNotification(
      ThreadNotificationFrame(
        threadId: 'thread',
        revision: 2,
        epoch: 1,
        baseRevision: 1,
        update: ThreadAudienceUpdate(
          knownAudience(controlRevision: 2, phase: 'paused'),
        ),
      ),
    );
    expect(scope.state.authorization, authorization(1, 2));
    expect(scope.state.items, isEmpty);
    expect(scope.state.loading, isTrue);
    expect(scope.state.deliveryVersion, isNull);
    final stale = await transport.nextRead();
    expect(stale.request.authorization.generation, 1);
    // A reply that still reports the superseded control revision cannot
    // restore the old Accepted presentation.
    stale.result.complete(
      _receiptReply(
        stale,
        summaryVersion: 1,
        deliveryVersion: 10,
        platform: const BotPlatformResultAccepted(),
        accepted: true,
        controlRevision: 1,
      ),
    );
    await scope.source.waitFor((value) => value.error != null);
    expect(
      scope.state.error,
      isA<StudioFailure>(),
      reason: 'a superseded control revision is not a fresh receipt',
    );
    expect(scope.state.items, isEmpty);
    expect(scope.state.deliveryVersion, isNull);
    // Recovery is an explicit bounded read, never a background poll.
    scope.retry();
    final retried = await transport.nextRead();
    retried.result.complete(
      _receiptReply(
        retried,
        summaryVersion: 1,
        deliveryVersion: 11,
        platform: const BotPlatformResultAccepted(),
        accepted: true,
        controlRevision: 2,
      ),
    );
    await scope.source.waitFor((value) => value.deliveryVersion == 11);
    expect(scope.state.authorization, authorization(1, 2));
    final projection = AudienceItemDeliveryProjection.fromStatus(
      scope.state.items['canonical-A']!,
      displayRevision: 1,
    );
    expect(projection.currentRevisionAccepted, isTrue);
    expect(
      (projection.ledger!.platform as BotItemPlatformCard)
          .latestOperation
          .result,
      isA<BotPlatformResultAccepted>(),
    );
  });

  test('a historical selection survives replaced bindings but not loss of its target proof', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    final scope = client.audienceQueries.openScope('thread', 1);
    addTearDown(() async {
      scope.retire();
      for (final call in transport.reads) {
        if (!call.result.isCompleted) {
          call.result.complete(
            ReadThreadAudienceItemsReply(
              threadId: call.request.threadId,
              authorization: call.request.authorization,
              result: const BotAudienceItemsReadUnavailable(
                reason: BotAudienceItemsUnavailableReason.scopeChanged,
              ),
            ),
          );
        }
      }
      await scope.close();
      await client.close();
    });
    final session = client.session('thread');
    session.applySnapshot(
      audienceWorkspace(knownAudience(phase: 'closed', controlRevision: 4)),
    );
    final selected = BotAuthorizationRef(
      id: authorization(1, 4).id,
      revision: 4,
    );
    scope.selectAuthorization(selected);
    scope.setVisible({'canonical-A': 1});
    final historical = await transport.nextRead();
    expect(historical.request.authorization, selected.id);
    historical.complete(controlRevision: 4);
    await scope.source.waitFor((value) => value.items.isNotEmpty);
    expect(scope.isHistoricalSelection, isTrue);
    // The same bot/chat is still proven after this Thread's binding is
    // replaced, so its own closed authorization remains explainable.
    session.applySnapshot(audienceWorkspace(replacedAudience(), revision: 2));
    expect(scope.state.items, isEmpty);
    expect(scope.isHistoricalSelection, isTrue);
    final retained = await transport.nextRead();
    retained.complete(controlRevision: 4);
    await scope.source.waitFor((value) => value.items.isNotEmpty);
    // Ownership can no longer be proven: an old authorization's receipts are
    // no longer a displayable current context and must not be re-queried.
    session.applySnapshot(
      audienceWorkspace(
        const ThreadAudienceUnavailable(
          reason: ThreadAudienceUnavailableReason.stateUnreadable,
        ),
        revision: 3,
      ),
    );
    expect(scope.isHistoricalSelection, isFalse);
    expect(scope.state.authorization, isNull);
    expect(scope.state.items, isEmpty);
    expect(scope.state.loading, isFalse);
    expect(
      transport.reads,
      hasLength(2),
      reason: 'an unprovable scope stops reading instead of re-querying',
    );
  });

  test('a historical selection never survives a different known bot or chat identity', () async {
    // A known binding may be replaced by another bot or by another chat of the
    // same bot. Both identity components must invalidate a closed
    // authorization that this Thread can no longer attribute.
    for (final variant in const [
      (name: 'other bot', botId: 'other-bot', chatId: 'chat'),
      (name: 'other chat', botId: 'bot', chatId: 'other-chat'),
    ]) {
      final transport = AudienceTransport();
      final client = audienceClient(transport);
      final scope = client.audienceQueries.openScope('thread', 1);
      addTearDown(() async {
        scope.retire();
        for (final call in transport.reads) {
          if (!call.result.isCompleted) {
            call.result.complete(
              ReadThreadAudienceItemsReply(
                threadId: call.request.threadId,
                authorization: call.request.authorization,
                result: const BotAudienceItemsReadUnavailable(
                  reason: BotAudienceItemsUnavailableReason.scopeChanged,
                ),
              ),
            );
          }
        }
        await scope.close();
        await client.close();
      });
      final session = client.session('thread');
      session.applySnapshot(
        audienceWorkspace(knownAudience(phase: 'closed', controlRevision: 4)),
      );
      final selected = BotAuthorizationRef(
        id: authorization(1, 4).id,
        revision: 4,
      );
      scope.selectAuthorization(selected);
      scope.setVisible({'canonical-A': 1});
      final historical = await transport.nextRead();
      expect(
        historical.request.authorization,
        selected.id,
        reason: '${variant.name}: the explicit history read uses its scope',
      );
      historical.result.complete(
        _receiptReply(
          historical,
          summaryVersion: 1,
          deliveryVersion: 1,
          platform: const BotPlatformResultAccepted(),
          accepted: true,
          controlRevision: 4,
        ),
      );
      await scope.source.waitFor((value) => value.items.isNotEmpty);
      expect(scope.isHistoricalSelection, isTrue);

      final other = knownAudience(botId: variant.botId, chatId: variant.chatId);
      session.applySnapshot(audienceWorkspace(other, revision: 2));
      final current = other.queryAuthorization!;
      expect(
        current.id,
        isNot(selected.id),
        reason: '${variant.name}: a different target is a different scope',
      );
      expect(
        scope.isHistoricalSelection,
        isFalse,
        reason:
            '${variant.name}: the old closed authorization is no longer '
            'attributable to this Thread',
      );
      expect(
        scope.state.items,
        isEmpty,
        reason: '${variant.name}: old receipts stop being current at once',
      );
      expect(
        scope.state.authorization,
        current,
        reason:
            '${variant.name}: display follows the new current authorization',
      );
      expect(
        () => scope.selectAuthorization(selected),
        throwsArgumentError,
        reason: '${variant.name}: a foreign authorization cannot be selected',
      );
      // Following the new legitimate current authorization stays allowed;
      // only the old one may never be read again.
      final fresh = await transport.nextRead();
      expect(fresh.request.authorization, current.id);
      expect(
        transport.reads.where(
          (call) => call.request.authorization == selected.id,
        ),
        hasLength(1),
        reason: '${variant.name}: the old authorization is never re-read',
      );
      fresh.result.complete(
        _receiptReply(
          fresh,
          summaryVersion: 1,
          deliveryVersion: 1,
          platform: const BotPlatformResultAccepted(),
          accepted: true,
        ),
      );
      await scope.source.waitFor((value) => value.items.isNotEmpty);
      expect(scope.state.authorization, current);
      expect(scope.state.items.keys, ['canonical-A']);
    }
  });
}
