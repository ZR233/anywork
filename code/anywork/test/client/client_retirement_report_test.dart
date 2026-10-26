import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/timeline_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late A1 retirement cannot erase A2 unresolved close ownership', () async {
    final transport = _RetirementTransport();
    final environment = TimelineTestEnvironment(
      timeline: transport,
      budget: ResourceBudget(
        capacities: {
          ResourceKind.chatHandle: 3,
          ResourceKind.pendingOperation: 64,
          ResourceKind.draft: 64,
          ResourceKind.attachment: 256,
          ResourceKind.observer: 1024,
          ResourceKind.readModel: 256,
        },
      ),
    );
    final repository = environment.conversations;
    final first = TestTimelineConnection(
      initial: baseline(
        1,
        subscriptionId: 'a1',
        items: [timelineItem(1, threadId: 'thread-main')],
      ),
    );
    final second =
        TestTimelineConnection(
            initial: baseline(
              1,
              subscriptionId: 'a2',
              items: [timelineItem(1, threadId: 'thread-main')],
            ),
          )
          ..closeFailure = const StudioFailure(
            code: StudioFailureCode.unavailable,
            message: 'A2 close acknowledgement failed',
            retryable: true,
            correlationId: 'a2-close',
          );
    addTearDown(() async {
      for (final opening in transport.opens) {
        if (!opening.reply.isCompleted) opening.reply.complete(first);
      }
      second.closeFailure = null;
      await repository.close(deadline: _deadline());
      await repository.retryCleanup(deadline: _deadline());
      environment.operations.seal();
    });

    environment.select('thread-main');
    final a1 = await transport.opened(0);
    final firstOwner = repository.existingSession('thread-main')!;
    final firstAttempt = firstOwner.timeline.state.value.attemptId!;
    environment.select('thread-alt');
    final b = await transport.opened(1);
    b.reply.complete(
      TestTimelineConnection(
        initial: baseline(
          1,
          subscriptionId: 'b',
          items: [timelineItem(1, threadId: 'thread-alt')],
        ),
      ),
    );
    await repository.active.value!.timeline.ready;
    environment.select('thread-main');
    final a2 = await transport.opened(2);
    a2.reply.complete(second);
    final owner = repository.existingSession('thread-main')!;
    await owner.timeline.ready;
    await second.subscribed.future;
    final secondAttempt = owner.timeline.state.value.attemptId!;
    expect(secondAttempt, isNot(firstAttempt));

    // An expired deadline reports the blocked A1 open and A2's close ownership.
    // No timer or dropped Future is used as evidence that A1 has joined.
    final closing = repository.close(deadline: DateTime.utc(2000));
    await second.closeCompleted.future;
    final report = await closing;
    expect(
      report.unresolved.any(
        (entry) =>
            entry.owner == 'timeline:thread-main' &&
            entry.attemptId == secondAttempt,
      ),
      isTrue,
    );
    expect(first.closeCalls, 0);

    a1.reply.complete(first);
    await first.closeCompleted.future;
    // Observe the original A1 retirement only, without re-closing A2 by ID.
    expect(
      (await firstOwner.timeline.lifecycle.observeRetired(
        deadline: _deadline(),
      )).complete,
      isTrue,
    );
    expect(first.wasSubscribed, isFalse);
    expect(environment.budget.used(ResourceKind.chatHandle), 1);
    final retriesBeforeObservation = second.retryCloseCalls;
    final retained = await owner.timeline.lifecycle.observeRetired(
      deadline: _deadline(),
    );
    expect(
      retained.unresolved.any(
        (entry) =>
            entry.owner == 'timeline:thread-main' &&
            entry.attemptId == secondAttempt,
      ),
      isTrue,
      reason:
          'the old successful retirement must not replace A2 close evidence',
    );
    expect(
      second.retryCloseCalls,
      retriesBeforeObservation,
      reason: 'the evidence read cannot repair or recreate A2 close ownership',
    );

    second.closeFailure = null;
    expect(
      (await repository.retryCleanup(deadline: _deadline())).complete,
      isTrue,
    );
    expect(environment.budget.used(ResourceKind.chatHandle), 0);
    expect(
      transport.opens.where((open) => open.threadId == 'thread-main'),
      hasLength(2),
      reason: 'cleanup never reopens a timeline connection',
    );
    expect(environment.budget.usage, isEmpty);
    // These are public Conversation ownership contracts, not native FRB evidence.
  });

  test(
    'cleanup retry leaves a healthy active timeline out of unresolved',
    () async {
      final transport = _RetirementTransport();
      final environment = TimelineTestEnvironment(timeline: transport);
      addTearDown(environment.close);
      environment.select('thread-main');
      final opening = await transport.opened(0);
      final connection = TestTimelineConnection(
        initial: baseline(1, items: [timelineItem(1, threadId: 'thread-main')]),
      );
      opening.reply.complete(connection);
      final owner = environment.conversations.existingSession('thread-main')!;
      final delivered = await owner.timeline.ready;
      await connection.subscribed.future;
      final attempt = owner.timeline.state.value.attemptId;

      final report = await environment.conversations.retryCleanup(
        deadline: _deadline(),
      );

      expect(report.complete, isTrue);
      expect(report.unresolved, isEmpty);
      expect(owner.timeline.state.value.attemptId, attempt);
      expect(
        (await owner.timeline.ready).baseline.subscriptionId,
        delivered.baseline.subscriptionId,
      );
      expect(connection.requestCloseCalls, 0);
      expect(connection.closeCalls, 0);
      expect(transport.opens, hasLength(1));
      expect(
        environment.budget.used(ResourceKind.chatHandle),
        1,
        reason: 'a healthy active view keeps its real owner permit',
      );
    },
  );
}

final class _TimelineOpening {
  _TimelineOpening(this.threadId);
  final String threadId;
  final reply = Completer<StudioTimelineConnection>();
}

/// Native opening gates only. Attempt identity, retirement and reporting are
/// all owned by the actual Conversation Repository and Timeline owner.
final class _RetirementTransport implements TimelineTransport {
  final opens = <_TimelineOpening>[];
  final _waiters = <int, Completer<_TimelineOpening>>{};
  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) {
    final opening = _TimelineOpening(threadId);
    opens.add(opening);
    _waiters.remove(opens.length - 1)?.complete(opening);
    return opening.reply.future;
  }

  Future<_TimelineOpening> opened(int index) => index < opens.length
      ? Future.value(opens[index])
      : _waiters.putIfAbsent(index, Completer<_TimelineOpening>.new).future;
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
