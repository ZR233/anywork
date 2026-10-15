import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late A1 retirement cannot erase A2 unresolved close ownership', () async {
    final transport = RecordingDemoTransport();
    final releaseFirst = Completer<void>();
    final firstCreated = Completer<RecordingChatWindow>();
    final secondCreated = Completer<_FailingCloseWindow>();
    var mainOpens = 0;
    transport.chatWindowFactory = (threadId, inner) async {
      if (threadId != 'thread-main') return inner;
      mainOpens++;
      if (mainOpens == 1) {
        final first = RecordingChatWindow(threadId: threadId, inner: inner);
        firstCreated.complete(first);
        await releaseFirst.future;
        return first;
      }
      final second = _FailingCloseWindow(threadId: threadId, inner: inner)
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
    final first = await firstCreated.future;
    final owner = client.existingSession('thread-main')!;
    final firstAttempt = owner.chat.currentAttemptId!;
    await client.directoryCommands.selectThread('thread-alt');
    await client
        .existingSession('thread-alt')!
        .source
        .waitFor((s) => s.hasChatWindow);
    await client.directoryCommands.selectThread('thread-main');
    final second = await secondCreated.future;
    await second.nextEntered.future;
    final secondAttempt = owner.chat.currentAttemptId!;
    expect(secondAttempt, isNot(firstAttempt));

    // An expired deadline reports both the blocked A1 open and A2's real close
    // failure without waiting on wall-clock delays or abandoning either permit.
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
    // This public join shares the retired pump tasks with the earlier A1
    // retirement. Its completion is a lifecycle barrier, not a timer flush.
    await owner.retire();
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
    expect(mainOpens, 2, reason: 'cleanup never reopens a ChatView');
    // These are Client ownership contracts over Demo, not native FRB evidence.
  });

  test(
    'cleanup retry leaves a healthy active ChatView out of unresolved',
    () async {
      final transport = RecordingDemoTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'healthy-cleanup',
      );
      addTearDown(() => client.close(deadline: _deadline()));
      await client.bootstrap();
      await client.directoryCommands.selectThread('thread-main');
      final owner = client.existingSession('thread-main')!;
      await owner.source.waitFor((s) => s.hasChatWindow);
      final window = transport.windows.single;
      await window.nextEntered.future;
      final attempt = owner.chat.currentAttemptId;
      final viewId = owner.state.chatViewId;

      final report = await client.retryCleanup(deadline: _deadline());

      expect(report.complete, isTrue);
      expect(client.unresolvedResources, isEmpty);
      expect(owner.chat.currentAttemptId, attempt);
      expect(owner.state.chatViewId, viewId);
      expect(owner.state.hasChatWindow, isTrue);
      expect(window.requestCloseCalls, 0);
      expect(window.closeCalls, 0);
      expect(transport.windows, hasLength(1));
      expect(
        client.budget.used(ResourceKind.chatHandle),
        1,
        reason: 'a healthy active view keeps its real owner permit',
      );
    },
  );
}

final class _FailingCloseWindow extends RecordingChatWindow {
  _FailingCloseWindow({required super.threadId, required super.inner});

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

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
