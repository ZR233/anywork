import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../anywork_client/test/support/timeline_transport.dart';

const _closeIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'nativeJoin',
    code: 'joinUnconfirmed',
    message: 'The original native join is unresolved.',
    retryable: true,
    correlationId: 'original-native-join',
  ),
  recovery: CleanupRecovery.retryClose,
);
const _deliveryIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'deliveryJoin',
    code: 'deliveryUnconfirmed',
    message: 'The original delivery join is unresolved.',
    retryable: true,
    correlationId: 'original-delivery-join',
  ),
  recovery: CleanupRecovery.awaitCompletion,
);

void main() {
  test(
    'cleanup retry leaves a healthy active Session and its permits intact',
    () async {
      final fixture = ConversationFixture();
      addTearDown(() async {
        expect((await fixture.repository.close()).complete, isTrue);
        expect(fixture.budget.usage, isEmpty);
      });
      final ready = await _select(fixture, 'healthy');
      final attempt = ready.session.timeline.state.value.attemptId;
      final stamp = ready.session.timeline.state.value.lastStamp;
      final usage = fixture.budget.used(ResourceKind.readModel);

      expect((await fixture.repository.retryCleanup()).complete, isTrue);

      expect(fixture.repository.active.value, same(ready.session));
      expect(
        fixture.repository.existingSession('healthy'),
        same(ready.session),
      );
      expect(
        ready.session.timeline.state.value.phase,
        TimelineConnectionPhase.ready,
      );
      expect(ready.session.timeline.state.value.attemptId, attempt);
      expect(ready.session.timeline.state.value.lastStamp, stamp);
      expect(ready.connection.native.requestCloseCalls, 0);
      expect(ready.connection.native.closeCalls, 0);
      expect(ready.connection.native.retryCloseCalls, 0);
      expect(fixture.facets.execution.single.feed.requestCloseCalls, 0);
      expect(fixture.facets.metrics.single.feed.requestCloseCalls, 0);
      expect(fixture.facets.context.single.feed.requestCloseCalls, 0);
      expect(fixture.facets.configuration.single.feed.requestCloseCalls, 0);
      expect(fixture.facets.authoring.single.feed.requestCloseCalls, 0);
      expect(fixture.timeline.requests, hasLength(1));
      expect(fixture.budget.used(ResourceKind.chatHandle), 1);
      expect(fixture.budget.used(ResourceKind.readModel), usage);

      // A no-op cleanup must not seal new admission either.
      expect(fixture.repository.session('another'), isNotNull);
    },
  );

  test('cleanup retry advances only the unresolved retired Session beside a healthy one', () async {
    final fixture = ConversationFixture();
    final old = await _select(fixture, 'retired');
    addTearDown(() async {
      old.connection.native.closeReport = _clean('retired');
      await fixture.repository.close();
      expect((await fixture.repository.retryCleanup()).complete, isTrue);
      expect(fixture.budget.usage, isEmpty);
    });
    old.connection.native.closeReport = _unresolved('retired');
    final retiring = await fixture.demand.retire('retired');
    final original = retiring.unresolved.singleWhere(
      (entry) => entry.owner == 'timeline:retired',
    );
    expect(original.issues, containsAll([_closeIssue, _deliveryIssue]));
    final healthy = await _select(fixture, 'healthy');
    final attempt = healthy.session.timeline.state.value.attemptId;

    final failedRetry = await fixture.repository.retryCleanup();
    final retained = failedRetry.unresolved.singleWhere(
      (entry) => entry.owner == original.owner,
    );
    expect(retained.attemptId, original.attemptId);
    expect(retained.issues, containsAll([_closeIssue, _deliveryIssue]));
    expect(old.connection.native.retryCloseCalls, 1);
    expect(fixture.budget.used(ResourceKind.chatHandle), 2);

    old.connection.native.closeReport = _clean('retired');
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(
      old.connection.native.retryCloseCalls,
      2,
      reason: 'an Unresolved Future is not cached forever',
    );
    expect(old.connection.native.disposeCalls, 1);
    expect(fixture.repository.active.value, same(healthy.session));
    expect(healthy.session.timeline.state.value.attemptId, attempt);
    expect(healthy.connection.native.requestCloseCalls, 0);
    expect(healthy.connection.native.closeCalls, 0);
    expect(fixture.budget.used(ResourceKind.chatHandle), 1);
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(old.connection.native.retryCloseCalls, 2);
    expect(
      old.connection.native.disposeCalls,
      1,
      reason: 'successful cleanup releases only once',
    );
    expect(
      fixture.timeline.requests,
      hasLength(2),
      reason: 'cleanup never opens a connection',
    );
  });

  test('cleanup retry joins an old Timeline attempt without sealing its current Session', () async {
    final fixture = ConversationFixture();
    final ready = await _select(fixture, 'thread');
    addTearDown(() async {
      ready.connection.native.closeFailure = null;
      if (ready.connection.native.closeGate?.isCompleted == false) {
        ready.connection.native.closeGate!.complete();
      }
      await fixture.repository.close();
      expect((await fixture.repository.retryCleanup()).complete, isTrue);
      expect(fixture.budget.usage, isEmpty);
    });
    ready.connection.native.closeGate = Completer<void>();
    ready.connection.native.closeFailure = const StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'The original native close failed.',
      retryable: false,
      correlationId: 'retired-native-close',
    );
    ready.connection.native.emitClosed();
    await ready.connection.native.closeStarted.future;
    ready.session.timeline.refresh();
    final current = await _accept(fixture, ready.session, 'replacement');
    ready.connection.native.closeGate!.complete();
    await ready.connection.native.closeCompleted.future;
    // Native close completion is not the Dart owner's join. Observe the
    // already-registered retired join before explicitly retrying its failure.
    final original = await ready.session.timeline.lifecycle.observeRetired(
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(
      original.unresolved
          .expand((entry) => entry.issues)
          .any(
            (issue) =>
                issue.diagnostic.correlationId == 'retired-native-close' &&
                issue.recovery == CleanupRecovery.retryClose,
          ),
      isTrue,
    );
    final attempt = ready.session.timeline.state.value.attemptId;

    ready.connection.native.closeFailure = null;
    expect((await fixture.repository.retryCleanup()).complete, isTrue);

    expect(ready.connection.native.retryCloseCalls, 1);
    expect(ready.connection.native.disposeCalls, 1);
    expect(fixture.repository.active.value, same(ready.session));
    expect(ready.session.timeline.state.value.attemptId, attempt);
    expect(ready.session.timeline.state.value.lastStamp?.viewId, 'replacement');
    expect(current.native.requestCloseCalls, 0);
    expect(current.native.closeCalls, 0);
    expect(fixture.budget.used(ResourceKind.chatHandle), 1);
    expect(fixture.timeline.requests, hasLength(2));
  });

  test('application close still seals all Sessions and retries its original unresolved join', () async {
    final fixture = ConversationFixture();
    final ready = await _select(fixture, 'thread');
    addTearDown(() async {
      ready.connection.native.closeReport = _clean('thread');
      expect((await fixture.repository.retryCleanup()).complete, isTrue);
      expect(fixture.budget.usage, isEmpty);
    });
    ready.connection.native.closeReport = _unresolved('thread');

    final closing = await fixture.repository.close();

    expect(
      closing.unresolved.expand((entry) => entry.issues),
      containsAll([_closeIssue, _deliveryIssue]),
    );
    expect(fixture.repository.active.value, isNull);
    expect(
      () => fixture.repository.session('another'),
      throwsA(isA<StudioFailure>()),
    );
    expect(ready.connection.native.requestCloseCalls, greaterThan(0));
    expect(fixture.budget.used(ResourceKind.chatHandle), 1);
    ready.connection.native.closeReport = _clean('thread');
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(ready.connection.native.retryCloseCalls, 1);
    expect(ready.connection.native.disposeCalls, 1);
    expect(fixture.timeline.requests, hasLength(1));
    expect(fixture.budget.usage, isEmpty);
  });
}

Future<({ConversationSession session, TimelineConnectionProbe connection})>
_select(ConversationFixture fixture, String threadId) async {
  final session = fixture.select(threadId);
  session.timeline.attachConsumer((_) {});
  return (
    session: session,
    connection: await _accept(fixture, session, threadId),
  );
}

Future<TimelineConnectionProbe> _accept(
  ConversationFixture fixture,
  ConversationSession session,
  String subscriptionId,
) async {
  final index = fixture.timeline.requests
      .where((request) => request.result.isCompleted)
      .length;
  final connection = TimelineConnectionProbe(
    TestTimelineConnection(
      initial: baseline(1, subscriptionId: subscriptionId, items: const []),
    ),
  );
  (await fixture.timeline.opened(index)).result.complete(connection);
  await session.timeline.ready;
  await connection.acknowledged(1);
  return connection;
}

FeedCloseReport _unresolved(String subscriptionId) => FeedCloseReport(
  feedId: subscriptionId,
  outcome: FeedCloseOutcome.unresolved(issues: [_closeIssue, _deliveryIssue]),
);

FeedCloseReport _clean(String subscriptionId) => FeedCloseReport(
  feedId: subscriptionId,
  outcome: const FeedCloseOutcome.clean(),
);
