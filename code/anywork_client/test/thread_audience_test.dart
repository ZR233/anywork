import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/audience_fixture.dart';

void main() {
  test('delivery versions cannot regress and budget pressure is explicit without hidden polling', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    client.session('thread').applySnapshot(audienceWorkspace(knownAudience()));
    final scope = client.audienceQueries.openScope('thread', 1);
    scope.setVisible({'item': 1});
    (await transport.nextRead()).complete(deliveryVersion: 10);
    await scope.source.waitFor((value) => value.deliveryVersion == 10);
    scope.retry();
    (await transport.nextRead()).complete(deliveryVersion: 9);
    await scope.source.waitFor((value) => value.error != null);
    expect(scope.state.error, isA<StudioFailure>());
    expect(scope.state.items, isEmpty);
    scope.retry();
    (await transport.nextRead()).complete(deliveryVersion: 11);
    await scope.source.waitFor((value) => value.deliveryVersion == 11);
    await scope.close();
    final blockedTransport = AudienceTransport();
    final budget = ResourceBudget(
      capacities: {
        for (final kind in ResourceKind.values)
          kind: kind == ResourceKind.pendingOperation ? 0 : 32,
      },
    );
    final blocked = audienceClient(blockedTransport, budget: budget);
    addTearDown(blocked.close);
    blocked.session('thread').applySnapshot(audienceWorkspace(knownAudience()));
    final unavailable = blocked.audienceQueries.openScope('thread', 1);
    unavailable.setVisible({'item': 1});
    await unavailable.source.waitFor((value) => value.error != null);
    expect(unavailable.state.error, isA<ResourceBudgetExceeded>());
    expect(blockedTransport.reads, isEmpty);
    await unavailable.close();
    expect(budget.used(ResourceKind.observer), 0);
  });

  test('audience follows the existing snapshot and epoch/gap gate; unavailable is not unbound', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    final session = client.session('thread');
    expect(session.state.audience, isA<ThreadAudienceUnavailable>());
    session.applySnapshot(audienceWorkspace(const ThreadAudienceUnbound()));
    expect(session.state.audience, isA<ThreadAudienceUnbound>());
    session.applyNotification(
      ThreadNotificationFrame(
        threadId: 'thread',
        revision: 2,
        epoch: 4,
        baseRevision: 1,
        update: ThreadAudienceUpdate(knownAudience()),
      ),
    );
    expect(session.state.audience.known?.target, audienceTarget);
    final retained = session.state.audience;
    session.applyNotification(
      ThreadNotificationFrame(
        threadId: 'thread',
        revision: 3,
        epoch: 3,
        baseRevision: 2,
        update: ThreadAudienceUpdate(knownAudience(generation: 2)),
      ),
    );
    expect(
      session.state.audience,
      retained,
      reason: 'old owner epoch cannot change audience',
    );
    session.applyNotification(
      ThreadNotificationFrame(
        threadId: 'thread',
        revision: 4,
        epoch: 4,
        baseRevision: 3,
        update: ThreadAudienceUpdate(knownAudience(generation: 2)),
      ),
    );
    expect(
      session.state.audience,
      retained,
      reason: 'a gap cannot bypass resync',
    );
    session.applySnapshot(
      audienceWorkspace(
        const ThreadAudienceUnavailable(
          reason: ThreadAudienceUnavailableReason.bindingUnavailable,
        ),
        revision: 4,
      ),
    );
    expect(
      session.state.audience,
      const ThreadAudienceUnavailable(
        reason: ThreadAudienceUnavailableReason.bindingUnavailable,
      ),
    );
  });

  test('visible demand batches unique canonical IDs at 100, shares requests, and joins retirement', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    client.session('thread').applySnapshot(audienceWorkspace(knownAudience()));
    final scope = client.audienceQueries.openScope('thread', 7);
    final visible = {for (var i = 0; i < 101; i++) 'canonical-$i': 1};
    final next = transport.nextRead();
    scope.setVisible(visible);
    scope.setVisible(Map.of(visible));
    final first = await next;
    expect(first.request.itemIds, visible.keys.take(100).toList());
    expect(first.request.authorization, authorization(1, 1).id);
    first.complete();
    final second = await transport.nextRead();
    expect(second.request.itemIds, ['canonical-100']);
    second.complete();
    final ready = await scope.source.waitFor(
      (value) => value.items.length == 101,
    );
    expect(ready.deliveryVersion, 1);
    expect(transport.reads.length, 2);
    final nextRead = transport.nextRead();
    scope.setVisible({'canonical-0': 2});
    final inFlight = await nextRead;
    var closed = false;
    final closing = scope.close().then((_) => closed = true);
    await Future<void>.value();
    expect(
      closed,
      isFalse,
      reason: 'retirement must join actual transport work',
    );
    expect(() => scope.setVisible({'late': 1}), throwsStateError);
    inFlight.complete(revision: 2);
    await closing;
    expect(
      scope.state.items,
      isEmpty,
      reason: 'a retired reply cannot publish',
    );
    expect(client.session('thread').state.audience, isA<ThreadAudienceKnown>());
  });

  test('late authorization or canonical-revision response cannot overwrite current display', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    final session = client.session('thread');
    session.applySnapshot(audienceWorkspace(knownAudience()));
    client.composer('thread').updateDraft('keep this draft');
    final old = client.audienceQueries.openScope('thread', 1);
    old.setVisible({'public-item': 1});
    final first = await transport.nextRead();
    old.setVisible({'public-item': 2});
    session.applySnapshot(
      audienceWorkspace(
        knownAudience(generation: 2, summaryVersion: 2),
        revision: 2,
      ),
    );
    first.complete();
    final latest = await transport.nextRead();
    expect(latest.request.authorization.generation, 2);
    expect(old.state.items, isEmpty);
    latest.complete(revision: 2, summaryVersion: 2);
    await old.source.waitFor((value) => value.items['public-item'] != null);
    expect(old.state.authorization?.id.generation, 2);
    expect(
      (old.state.items['public-item']!.canonical
              as BotAudienceCanonicalItemPresent)
          .revision,
      2,
    );
    await old.close();
    expect(client.composer('thread').state.draft, 'keep this draft');
    final fresh = client.audienceQueries.openScope('thread', 2);
    fresh.setVisible({'public-item': 3});
    final mismatch = await transport.nextRead();
    mismatch.complete(revision: 2, summaryVersion: 2);
    await fresh.source.waitFor((value) => value.unavailable != null);
    expect(fresh.state.items, isEmpty);
    expect(
      fresh.state.unavailable,
      BotAudienceItemsUnavailableReason.canonicalReadInvalidated,
    );
    await fresh.close();
  });

  test('gen1 high watermark never confirms gen2; pending durable is not effective and Close bypasses Enable', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    final session = client.session('thread');
    session.applySnapshot(
      audienceWorkspace(
        knownAudience(generation: 1, controlRevision: 99, phase: 'closed'),
      ),
    );
    client.observeResource('bot-audience:thread:1', 999);
    final enable = client.botThreadSync.change(
      'thread',
      BotThreadSyncAction.enable,
    );
    final enableCall = await transport.nextControl();
    final prepared = knownAudience(generation: 2, phase: 'pending');
    enableCall.complete(prepared, pending: true, effective: false);
    await enable;
    final pending = client.botThreadSync.forThread('thread')!;
    expect(pending.operation.state.value.durable, isTrue);
    expect(pending.operation.state.value.effective, isFalse);
    expect(
      pending.operation.state.value.observed,
      isFalse,
      reason: 'gen1 revision 999 cannot cover gen2 revision 1',
    );
    session.applySnapshot(audienceWorkspace(prepared, revision: 2));
    final close = client.botThreadSync.change(
      'thread',
      BotThreadSyncAction.close,
    );
    final closeCall = await transport.nextControl();
    expect(
      closeCall.request.expected.authorizationHead,
      BotAuthorizationHeadPresent(authorization: authorization(2, 1)),
    );
    final closed = knownAudience(
      generation: 2,
      controlRevision: 2,
      phase: 'closed',
    );
    session.applySnapshot(audienceWorkspace(closed, revision: 3));
    closeCall.complete(closed);
    await close;
    final result = client.botThreadSync.forThread('thread')!;
    expect(result.request.action, BotThreadSyncAction.close);
    expect(result.operation.state.value.observed, isTrue);
    expect(result.operation.state.value.effective, isTrue);
    await expectLater(
      client.botThreadSync.change('thread', BotThreadSyncAction.resume),
      throwsA(isA<StudioFailure>()),
    );
    expect(transport.controls.length, 2);
  });

  test('late Enable reply does not replace successor Close; unknown reconciliation keeps operation and CAS', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    final session = client.session('thread');
    session.applySnapshot(audienceWorkspace(knownAudience(phase: 'closed')));
    final enable = client.botThreadSync.change(
      'thread',
      BotThreadSyncAction.enable,
    );
    final first = await transport.nextControl();
    final prepared = knownAudience(generation: 2, phase: 'pending');
    session.applySnapshot(audienceWorkspace(prepared, revision: 2));
    final close = client.botThreadSync.change(
      'thread',
      BotThreadSyncAction.close,
    );
    final second = await transport.nextControl();
    final rejected = expectLater(close, throwsA(isA<StudioFailure>()));
    second.result.completeError(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'ambiguous transport result',
        retryable: true,
        correlationId: 'test',
      ),
    );
    await rejected;
    expect(client.botThreadSync.forThread('thread')!.unknown, isTrue);
    first.complete(prepared, pending: true, effective: false);
    await enable;
    expect(
      client.botThreadSync.forThread('thread')!.request.operationId,
      second.request.operationId,
    );
    await expectLater(
      client.botThreadSync.change('thread', BotThreadSyncAction.close),
      throwsA(isA<StudioFailure>()),
    );
    final reconcile = client.botThreadSync.reconcile('thread');
    final repeated = await transport.nextControl();
    expect(repeated.request, second.request);
    final closed = knownAudience(
      generation: 2,
      controlRevision: 2,
      phase: 'closed',
    );
    session.applySnapshot(audienceWorkspace(closed, revision: 3));
    repeated.complete(closed);
    await reconcile;
    expect(
      client.botThreadSync.forThread('thread')!.operation.state.value.observed,
      isTrue,
    );
  });

  test(
    'authorization history is explicit, bounded, opaque and target scoped',
    () async {
      final transport = AudienceTransport();
      final client = audienceClient(transport);
      addTearDown(client.close);
      client
          .session('thread')
          .applySnapshot(audienceWorkspace(knownAudience()));
      expect(transport.history, isEmpty);
      final history = client.audienceQueries.openHistory('thread');
      await expectLater(history.next(limit: 33), throwsArgumentError);
      await history.next();
      await history.next(limit: 32);
      expect(transport.history.map((r) => r.limit), [16, 32]);
      expect(transport.history.last.cursor, 'opaque:not/a/timeline/cursor');
      history.retire();
      await expectLater(history.next(), throwsStateError);
      expect(transport.history.length, 2);
    },
  );

  test('verified target without an authorization head enables on the empty-head CAS and keeps its receipt owned until the boundary', () async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(client.close);
    final session = client.session('thread');
    final observers = client.budget.used(ResourceKind.observer);
    session.applySnapshot(
      audienceWorkspace(knownAudience(phase: 'closed', neverAuthorized: true)),
    );
    final audience = session.state.audience;
    // A verified current target with no authorization head has nothing to
    // query: no generation exists and no historical close may be invented.
    expect(
      (audience.known!.binding as BotThreadBindingPositionCurrent)
          .cas
          .authorizationHead,
      const BotAuthorizationHeadNone(),
    );
    expect(audience.known!.latestClosed, isNull);
    expect(audience.queryAuthorization, isNull);
    final enable = client.botThreadSync.change(
      'thread',
      BotThreadSyncAction.enable,
    );
    final first = await transport.nextControl();
    expect(
      first.request.expected,
      const BotSyncCas(
        bindingRevision: 3,
        authorizationHead: BotAuthorizationHeadNone(),
      ),
    );
    expect(first.request.threadId, 'thread');
    expect(first.request.action, BotThreadSyncAction.enable);
    final prepared = knownAudience(generation: 1, phase: 'pending');
    first.complete(prepared, pending: true, effective: false);
    final reply = await enable;
    expect(reply.state, isA<BotThreadSyncCommandStatePendingStart>());
    expect(
      (reply.state as BotThreadSyncCommandStatePendingStart).authorization,
      authorization(1, 1).id,
      reason: 'the first authorization of this target is generation 1',
    );
    final progress = client.botThreadSync.forThread('thread')!;
    expect(
      progress.operation.id.value,
      first.request.operationId,
      reason: 'the stable request identity owns the receipt',
    );
    expect(reply.receipt.targets.single.resourceKey, 'bot-audience:thread:1');
    expect(progress.operation.state.value.durable, isTrue);
    expect(progress.operation.state.value.effective, isFalse);
    expect(
      progress.operation.state.value.observed,
      isFalse,
      reason: 'a durable prepare is not yet visible in the audience',
    );
    session.applySnapshot(audienceWorkspace(prepared, revision: 2));
    expect(
      progress.operation.state.value.observed,
      isTrue,
      reason: 'the new generation now confirms this exact receipt',
    );
    expect(
      progress.operation.state.value.effective,
      isFalse,
      reason: 'PendingStart is not an effective boundary',
    );
    // The successor Close is admitted on the new head and is not queued
    // behind the pending Enable taking effect.
    final close = client.botThreadSync.change(
      'thread',
      BotThreadSyncAction.close,
    );
    final second = await transport.nextControl();
    expect(
      second.request.expected,
      BotSyncCas(
        bindingRevision: 3,
        authorizationHead: BotAuthorizationHeadPresent(
          authorization: authorization(1, 1),
        ),
      ),
    );
    final closed = knownAudience(
      generation: 1,
      controlRevision: 2,
      phase: 'closed',
    );
    session.applySnapshot(audienceWorkspace(closed, revision: 3));
    second.complete(closed);
    await close;
    final settled = client.botThreadSync.forThread('thread')!;
    expect(settled.request.operationId, second.request.operationId);
    expect(settled.operation.state.value.observed, isTrue);
    expect(settled.operation.state.value.effective, isTrue);
    expect(settled.superseded, isFalse);
    expect(transport.controls, hasLength(2));
    expect(
      client.budget.used(ResourceKind.observer),
      observers,
      reason: 'settled controls release their own observation permits',
    );
    session.applySnapshot(audienceWorkspace(knownAudience(), revision: 4));
  });

  test(
    'the control matrix admits no unproven or backward transition',
    () async {
      final transport = AudienceTransport();
      final client = audienceClient(transport);
      addTearDown(client.close);
      final session = client.session('thread');
      Future<void> rejected(
        BotThreadSyncAction action,
        StudioFailureCode code,
      ) async {
        await expectLater(
          client.botThreadSync.change('thread', action),
          throwsA(
            isA<StudioFailure>().having((error) => error.code, 'code', code),
          ),
        );
      }

      // PendingStart owns its start intent: Enable may not supersede it, while
      // Close remains the admissible successor.
      session.applySnapshot(audienceWorkspace(knownAudience(phase: 'pending')));
      await rejected(
        BotThreadSyncAction.enable,
        StudioFailureCode.invalidArgument,
      );
      await rejected(
        BotThreadSyncAction.pause,
        StudioFailureCode.invalidArgument,
      );
      await rejected(
        BotThreadSyncAction.resume,
        StudioFailureCode.invalidArgument,
      );
      session.applySnapshot(audienceWorkspace(replacedAudience(), revision: 2));
      for (final action in BotThreadSyncAction.values) {
        await rejected(action, StudioFailureCode.permissionDenied);
      }
      session.applySnapshot(
        audienceWorkspace(const ThreadAudienceUnbound(), revision: 3),
      );
      for (final action in BotThreadSyncAction.values) {
        await rejected(action, StudioFailureCode.permissionDenied);
      }
      session.applySnapshot(
        audienceWorkspace(
          const ThreadAudienceUnavailable(
            reason: ThreadAudienceUnavailableReason.ownershipUnproven,
          ),
          revision: 4,
        ),
      );
      for (final action in BotThreadSyncAction.values) {
        await rejected(action, StudioFailureCode.permissionDenied);
      }
      expect(
        transport.controls,
        isEmpty,
        reason: 'a rejected intent must never reach the host control endpoint',
      );
      expect(client.botThreadSync.forThread('thread'), isNull);
    },
  );
}
