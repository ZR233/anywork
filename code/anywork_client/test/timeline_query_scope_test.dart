import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/conversation_fixture.dart';
import 'support/timeline_transport.dart';

/// Public Repository/Session assembly: a scope captures one original attempt,
/// rejects late publication after retirement, and joins real query completion.
Future<
  ({
    ConversationFixture fixture,
    ConversationSession session,
    TimelineConnectionProbe connection,
    StudioTimelineQueryScope scope,
  })
>
_open() async {
  final fixture = ConversationFixture();
  final session = fixture.select('thread');
  session.timeline.attachConsumer((_) {});
  final connection = TimelineConnectionProbe(
    TestTimelineConnection(initial: baseline(3)),
  );
  (await fixture.timeline.opened(0)).result.complete(connection);
  await session.timeline.ready;
  await connection.acknowledged(1);
  final scope = session.timeline.openScope(generation: 1)!;
  return (
    fixture: fixture,
    session: session,
    connection: connection,
    scope: scope,
  );
}

final _cancelled = throwsA(
  isA<StudioFailure>().having(
    (failure) => failure.code,
    'code',
    StudioFailureCode.cancelled,
  ),
);

void main() {
  test('page carries the opaque cursor and explicit limit unchanged', () async {
    final ready = await _open();
    final future = ready.scope.page(before: 'tlp1.opaque', limit: 32);
    final request = await ready.connection.pageRequested(0);
    expect(request.before, 'tlp1.opaque');
    expect(request.limit, 32);
    ready.connection.native.pageResult!.complete(
      StudioTimelinePage(
        items: [timelineItem(2, id: 'older')],
        before: 'tlp1.next',
        hasOlder: true,
      ),
    );
    final page = await future;
    expect(page.items.single.id, 'older');
    expect(page.before, 'tlp1.next');
    expect(page.hasOlder, isTrue);
    expect((await ready.fixture.repository.close()).complete, isTrue);
  });

  test('invalid page limits are rejected rather than clamped', () async {
    final ready = await _open();
    for (final limit in [0, 101, -1]) {
      await expectLater(
        ready.scope.page(limit: limit),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.invalidArgument,
          ),
        ),
      );
    }
    expect(ready.connection.native.pageRequests, isEmpty);
    expect((await ready.fixture.repository.close()).complete, isTrue);
  });

  test('invalid detail sizes are rejected rather than clamped', () async {
    final ready = await _open();
    for (final maxBytes in [3, 262145, 0]) {
      await expectLater(
        ready.scope.readDetail(
          itemId: 'item',
          query: StudioTimelineDetailQuery(
            field: const ThreadTextFieldView(),
            revision: 2,
            maxBytes: maxBytes,
          ),
        ),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.invalidArgument,
          ),
        ),
      );
    }
    expect(ready.connection.native.detailRequests, isEmpty);
    expect((await ready.fixture.repository.close()).complete, isTrue);
  });

  test(
    'detail chunks preserve revision, field and opaque continuation',
    () async {
      final ready = await _open();
      final first = ready.scope.readDetail(
        itemId: 'item',
        query: const StudioTimelineDetailQuery(
          field: ThreadToolResultFieldView(),
          revision: 5,
          maxBytes: 8,
        ),
      );
      final request = await ready.connection.detailRequested(0);
      expect(request.itemId, 'item');
      expect(request.query.revision, 5);
      expect(request.query.field, const ThreadToolResultFieldView());
      expect(request.query.maxBytes, 8);
      ready.connection.native.detailResult!.complete(
        const StudioTimelineDetailChunk(
          itemId: 'item',
          field: ThreadToolResultFieldView(),
          revision: 5,
          text: 'ab',
          totalBytes: 6,
          continuation: 'tld1.next',
        ),
      );
      final chunk = await first;
      expect(chunk.text, 'ab');
      expect(chunk.isLast, isFalse);
      expect(chunk.totalBytes, 6);

      final next = ready.scope.readDetail(
        itemId: 'item',
        query: StudioTimelineDetailQuery(
          field: chunk.field,
          revision: chunk.revision,
          continuation: chunk.continuation,
          maxBytes: 8,
        ),
      );
      final continuation = await ready.connection.detailRequested(1);
      expect(continuation.query.continuation, 'tld1.next');
      expect(continuation.query.revision, 5);
      ready.connection.native.detailResult!.complete(
        const StudioTimelineDetailChunk(
          itemId: 'item',
          field: ThreadToolResultFieldView(),
          revision: 5,
          text: 'cdef',
          totalBytes: 6,
          continuation: null,
        ),
      );
      expect((await next).isLast, isTrue);
      expect((await ready.fixture.repository.close()).complete, isTrue);
    },
  );

  test(
    'retired scopes reject new work and never publish an admitted late page',
    () async {
      final ready = await _open();
      final pending = ready.scope.page();
      await ready.connection.pageRequested(0);
      ready.scope.retire();
      await expectLater(ready.scope.page(), _cancelled);
      final rejected = expectLater(pending, _cancelled);
      ready.connection.native.pageResult!.complete(
        StudioTimelinePage(items: [], before: null, hasOlder: false),
      );
      await rejected;
      expect(ready.connection.native.pageRequests, hasLength(1));
      expect((await ready.fixture.repository.close()).complete, isTrue);
    },
  );

  test('scope deadline retains the original query and its permits until settlement', () async {
    final ready = await _open();
    final pending = ready.scope.page();
    await ready.connection.pageRequested(0);
    expect(ready.fixture.budget.used(ResourceKind.pendingOperation), 1);
    expect(ready.scope.pendingQueries, 1);
    final report = await ready.scope.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse);
    expect(report.unresolved.single.attemptId, ready.scope.attemptId);
    expect(
      report.unresolved.single.issues.single.recovery,
      CleanupRecovery.awaitCompletion,
    );
    expect(ready.fixture.budget.used(ResourceKind.pendingOperation), 1);
    final rejected = expectLater(pending, _cancelled);
    ready.connection.native.pageResult!.complete(
      StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    await rejected;
    expect(ready.scope.pendingQueries, 0);
    expect(ready.fixture.budget.used(ResourceKind.pendingOperation), 0);
    expect((await ready.scope.close()).complete, isTrue);
    expect((await ready.fixture.repository.close()).complete, isTrue);
    expect(ready.fixture.budget.usage, isEmpty);
  });

  test(
    'refresh retires the old scope and keeps its admitted query supervised',
    () async {
      final ready = await _open();
      final pending = ready.scope.page();
      await ready.connection.pageRequested(0);
      ready.session.timeline.refresh();
      expect(ready.scope.isActive, isFalse);
      await expectLater(
        ready.scope.readDetail(
          itemId: 'item',
          query: const StudioTimelineDetailQuery(
            field: ThreadTextFieldView(),
            revision: 1,
          ),
        ),
        _cancelled,
      );
      expect(ready.connection.native.detailRequests, isEmpty);
      final rejected = expectLater(pending, _cancelled);
      ready.connection.native.pageResult!.complete(
        StudioTimelinePage(items: [], before: null, hasOlder: false),
      );
      await rejected;
      await ready.connection.native.closeCompleted.future;

      final replacement = TimelineConnectionProbe(
        TestTimelineConnection(initial: baseline(4, subscriptionId: 'sub2')),
      );
      (await ready.fixture.timeline.opened(1)).result.complete(replacement);
      expect(
        (await ready.session.timeline.ready).baseline.subscriptionId,
        'sub2',
      );
      await replacement.acknowledged(1);
      expect(
        ready.session.timeline.openScope(generation: 2)!.attemptId,
        isNot(ready.scope.attemptId),
      );
      expect((await ready.fixture.repository.close()).complete, isTrue);
      expect(ready.scope.isActive, isFalse);
      expect(ready.fixture.budget.usage, isEmpty);
    },
  );

  test('a sealed Session rejects opening another scope', () async {
    final ready = await _open();
    expect((await ready.fixture.repository.close()).complete, isTrue);
    expect(() => ready.session.timeline.openScope(generation: 3), _cancelled);
  });

  test('detail failures preserve the original typed error rather than an empty body', () async {
    final ready = await _open();
    final future = ready.scope.readDetail(
      itemId: 'item',
      query: const StudioTimelineDetailQuery(
        field: ThreadTextFieldView(),
        revision: 2,
      ),
    );
    await ready.connection.detailRequested(0);
    const error = StudioFailure(
      code: StudioFailureCode.staleRevision,
      message: 'stale',
      retryable: false,
      correlationId: 'detail-stale',
    );
    final failure = expectLater(future, throwsA(same(error)));
    ready.connection.native.detailResult!.completeError(error);
    await failure;
    expect((await ready.fixture.repository.close()).complete, isTrue);
  });

  test(
    'a cursor failure stays typed rather than becoming an empty page',
    () async {
      final ready = await _open();
      final future = ready.scope.page(before: 'tlp1.bad');
      await ready.connection.pageRequested(0);
      const error = StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'bad cursor',
        retryable: false,
        correlationId: 'cursor-invalid',
      );
      final failure = expectLater(future, throwsA(same(error)));
      ready.connection.native.pageResult!.completeError(error);
      await failure;
      expect((await ready.fixture.repository.close()).complete, isTrue);
    },
  );

  test('failed close retains the connection until explicit cleanup', () async {
    final ready = await _open();
    ready.connection.native.closeFailure = const StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'Native close failed',
      retryable: true,
      correlationId: 'scope-close-failed',
    );
    final report = await ready.fixture.repository.close();
    expect(report.complete, isFalse);
    expect(ready.fixture.budget.used(ResourceKind.chatHandle), 1);
    expect(
      report.unresolved
          .expand((owner) => owner.issues)
          .any(
            (issue) => issue.diagnostic.correlationId == 'scope-close-failed',
          ),
      isTrue,
    );
    ready.connection.native.closeFailure = null;
    expect((await ready.fixture.repository.retryCleanup()).complete, isTrue);
    expect(ready.connection.native.disposeCalls, 1);
    expect(ready.fixture.budget.usage, isEmpty);
  });

  test('native close and query completion must both settle before Repository Clean', () async {
    final ready = await _open();
    final pending = ready.scope.page();
    await ready.connection.pageRequested(0);
    expect(ready.fixture.budget.used(ResourceKind.pendingOperation), 1);
    final report = await ready.fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(report.complete, isFalse);
    expect(ready.fixture.budget.used(ResourceKind.pendingOperation), 1);
    expect(ready.fixture.budget.used(ResourceKind.chatHandle), 1);
    expect(
      ready.connection.native.disposeCalls,
      0,
      reason: 'The original connection also joins its admitted query',
    );
    final rejected = expectLater(pending, _cancelled);
    ready.connection.native.pageResult!.complete(
      StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    await rejected;
    expect((await ready.fixture.repository.retryCleanup()).complete, isTrue);
    expect(ready.connection.native.disposeCalls, 1);
    expect(ready.fixture.budget.usage, isEmpty);
  });

  test('clean scopes release their own read permits without closing the active connection', () async {
    final ready = await _open();
    final budget = ready.fixture.budget;
    final initialReadModels = budget.used(ResourceKind.readModel);
    expect((await ready.scope.close()).complete, isTrue);
    final withoutScope = budget.used(ResourceKind.readModel);
    expect(withoutScope, initialReadModels - 1);
    for (var round = 0; round < 3; round++) {
      final scope = ready.session.timeline.openScope(generation: round + 2)!;
      expect(budget.used(ResourceKind.readModel), withoutScope + 1);
      final page = scope.page();
      await ready.connection.pageRequested(round);
      ready.connection.native.pageResult!.complete(
        StudioTimelinePage(items: [], before: null, hasOlder: false),
      );
      await page;
      expect((await scope.close()).complete, isTrue);
      expect(budget.used(ResourceKind.pendingOperation), 0);
      expect(budget.used(ResourceKind.readModel), withoutScope);
      expect(ready.connection.native.disposeCalls, 0);
    }
    expect(
      ready.session.timeline.state.value.phase,
      TimelineConnectionPhase.ready,
    );
    expect((await ready.fixture.repository.close()).complete, isTrue);
    expect(budget.usage, isEmpty);
  });

  test(
    'retired attempts keep in-flight queries visible to Repository close',
    () async {
      final ready = await _open();
      final pending = ready.scope.page();
      await ready.connection.pageRequested(0);
      ready.session.timeline.refresh();
      final replacement = TimelineConnectionProbe(
        TestTimelineConnection(initial: baseline(4, subscriptionId: 'sub2')),
      );
      (await ready.fixture.timeline.opened(1)).result.complete(replacement);
      expect(
        (await ready.session.timeline.ready).baseline.subscriptionId,
        'sub2',
      );
      await replacement.acknowledged(1);
      expect(ready.scope.isActive, isFalse);
      expect(ready.fixture.budget.used(ResourceKind.chatHandle), 2);
      final report = await ready.fixture.repository.close(
        deadline: DateTime.utc(2000),
      );
      expect(report.complete, isFalse);
      expect(
        report.unresolved
            .expand((owner) => owner.issues)
            .any((issue) => issue.recovery == CleanupRecovery.awaitCompletion),
        isTrue,
      );
      expect(ready.fixture.budget.used(ResourceKind.pendingOperation), 1);
      final rejected = expectLater(pending, _cancelled);
      ready.connection.native.pageResult!.complete(
        StudioTimelinePage(items: [], before: null, hasOlder: false),
      );
      await rejected;
      expect((await ready.fixture.repository.retryCleanup()).complete, isTrue);
      expect(ready.fixture.budget.used(ResourceKind.pendingOperation), 0);
      expect(ready.fixture.budget.usage, isEmpty);
    },
  );

  test(
    'a detail response for another item, field or revision is never published',
    () async {
      final ready = await _open();
      for (final response in [
        const StudioTimelineDetailChunk(
          itemId: 'other',
          field: ThreadTextFieldView(),
          revision: 2,
          text: 'wrong item',
          totalBytes: 10,
        ),
        const StudioTimelineDetailChunk(
          itemId: 'item',
          field: ThreadToolResultFieldView(),
          revision: 2,
          text: 'wrong field',
          totalBytes: 11,
        ),
        const StudioTimelineDetailChunk(
          itemId: 'item',
          field: ThreadTextFieldView(),
          revision: 3,
          text: 'wrong revision',
          totalBytes: 14,
        ),
      ].indexed) {
        final request = ready.scope.readDetail(
          itemId: 'item',
          query: const StudioTimelineDetailQuery(
            field: ThreadTextFieldView(),
            revision: 2,
          ),
        );
        await ready.connection.detailRequested(response.$1);
        final rejected = expectLater(
          request,
          throwsA(
            isA<StudioFailure>().having(
              (failure) => failure.code,
              'code',
              StudioFailureCode.protocol,
            ),
          ),
        );
        ready.connection.native.detailResult!.complete(response.$2);
        await rejected;
      }
      expect((await ready.fixture.repository.close()).complete, isTrue);
    },
  );
}
