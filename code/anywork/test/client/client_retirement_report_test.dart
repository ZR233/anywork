import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late A1 retirement cannot erase A2 unresolved close ownership', () async {
    final transport = RecordingDemoTransport();
    final releaseFirst = Completer<void>();
    final firstCreated = Completer<RecordingConversationFeed>();
    final secondCreated = Completer<_FailingCloseConnection>();
    var mainOpens = 0;
    transport.conversationFeedFactory = (threadId, inner) async {
      if (threadId != 'thread-main') return inner;
      mainOpens++;
      if (mainOpens == 1) {
        final first = RecordingConversationFeed(inner: inner);
        firstCreated.complete(first);
        await releaseFirst.future;
        return first;
      }
      final second = _FailingCloseConnection(inner: inner)
        ..failure = StateError('A2 close acknowledgement failed');
      secondCreated.complete(second);
      return second;
    };
    // A1 opening, B retiring and A2 opening are independent live resources.
    final client = AnyworkClient(
      transport: transport,
      clientId: 'retirement-report',
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
    addTearDown(() async {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      if (secondCreated.isCompleted) {
        (await secondCreated.future).failure = null;
      }
      await client.close(deadline: _deadline());
      await client.retryCleanup(deadline: _deadline());
    });
    await client.bootstrap();
    await client.directoryCommands.selectThread('thread-main');
    client.conversations.setVisibleThread('thread-main');
    final first = await firstCreated.future;
    final owner = client.conversations.existingSession('thread-main')!;
    final firstAttempt = owner.content.currentAttemptId!;
    await client.directoryCommands.selectThread('thread-alt');
    client.conversations.setVisibleThread('thread-alt');
    await client.conversations
        .existingSession('thread-alt')!
        .content
        .state
        .waitFor((state) => state.snapshot is ConversationBaselineFrame);
    await client.directoryCommands.selectThread('thread-main');
    client.conversations.setVisibleThread('thread-main');
    final second = await secondCreated.future;
    await second.nextEntered.future;
    final secondAttempt = owner.content.currentAttemptId!;
    expect(secondAttempt, isNot(firstAttempt));

    // An expired deadline reports both the blocked A1 open and A2's real close
    // failure without waiting on wall-clock delays or abandoning either permit.
    client.conversations.setVisibleThread(null);
    final closing = client.close(deadline: DateTime.utc(2000));
    await second.closeFailed.future;
    final report = await closing;
    expect(
      report.unresolved.any(
        (entry) =>
            entry.owner == 'thread-main' && entry.attemptId == secondAttempt,
      ),
      isTrue,
    );
    expect(first.closeCalls, 0);

    releaseFirst.complete();
    await first.joined.future;
    // 撤销公开需求并汇合已退役的 A1；A2 的失败仍必须保留为未解决责任。
    final retired = await client.retryCleanup(deadline: _deadline());
    expect(retired.complete, isFalse);
    expect(first.initialCalls, 0);
    expect(client.budget.used(ResourceKind.chatHandle), 1);
    expect(
      client.unresolvedResources.any(
        (entry) =>
            entry.owner == 'thread-main' && entry.attemptId == secondAttempt,
      ),
      isTrue,
      reason:
          'the old successful retirement must not replace A2 close evidence',
    );

    second.failure = null;
    expect((await client.retryCleanup(deadline: _deadline())).complete, isTrue);
    expect(client.budget.used(ResourceKind.chatHandle), 0);
    expect(mainOpens, 2, reason: 'cleanup never reopens a timeline connection');
    // These are Client ownership contracts over Demo, not native FRB evidence.
  });

  test(
    'cleanup retry leaves a healthy active timeline out of unresolved',
    () async {
      final transport = RecordingDemoTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'healthy-cleanup',
      );
      addTearDown(() => client.close(deadline: _deadline()));
      await client.bootstrap();
      await client.directoryCommands.selectThread('thread-main');
      client.conversations.setVisibleThread('thread-main');
      final owner = client.conversations.existingSession('thread-main')!;
      await owner.content.state.waitFor(
        (state) => state.snapshot is ConversationBaselineFrame,
      );
      final connection = transport.feeds.single;
      await connection.nextEntered.future;
      final attempt = owner.content.currentAttemptId;
      final delivered = owner.content.lastDeliveredFrame;

      final report = await client.retryCleanup(deadline: _deadline());

      expect(report.complete, isTrue);
      expect(client.unresolvedResources, isEmpty);
      expect(owner.content.currentAttemptId, attempt);
      // demo 在会话打开后仍会推进真实内容：cleanup 重试不得替换连接，
      // 因此比较订阅身份而不是某一帧对象。
      expect(
        _subscriptionOf(owner.content.lastDeliveredFrame!),
        _subscriptionOf(delivered!),
      );
      expect(connection.requestCloseCalls, 0);
      expect(connection.closeCalls, 0);
      expect(transport.feeds, hasLength(1));
      expect(
        client.budget.used(ResourceKind.chatHandle),
        1,
        reason: 'a healthy active view keeps its real owner permit',
      );
    },
  );
}

final class _FailingCloseConnection extends RecordingConversationFeed {
  _FailingCloseConnection({required super.inner});

  Object? failure;
  final closeFailed = Completer<void>();

  @override
  Future<void> close() async {
    final error = failure;
    if (error == null) return super.close();
    closeCalls++;
    await inner.close();
    if (!closeFailed.isCompleted) closeFailed.complete();
    throw error;
  }
}

String _subscriptionOf(ConversationContentFrame frame) => switch (frame) {
  ConversationBaselineFrame(:final baseline) => baseline.subscriptionId,
  ConversationPatchFrame(:final patch) => patch.subscriptionId,
};

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
