import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

final class _OpenThreads {
  _OpenThreads(this.query, this.window);
  final DirectoryQuery query;
  final DirectoryWindow window;
  final result = Completer<ThreadsObservationHandle>();
}

final class _Feed implements DirectoryFeedPort {
  final List<_OpenThreads> threads = [];

  @override
  Future<ThreadsObservationHandle> openThreadsObservation(
    DirectoryQuery query,
    DirectoryWindow window,
  ) {
    final open = _OpenThreads(query, window);
    threads.add(open);
    return open.result.future;
  }

  @override
  Future<ThreadObservationHandle> openThreadObservation(String threadId) =>
      throw UnsupportedError('metadata is not used by this fixture');
}

final class _Handle implements ThreadsObservationHandle {
  final List<ThreadDirectoryFrame> _queued = [];
  Completer<ThreadDirectoryFrame?>? _waiting;
  final closeEntered = Completer<void>();
  final allowClose = Completer<void>();
  bool closeRequested = false;
  Object? closeFailure;
  int closeCalls = 0;
  final Map<int, Completer<void>> _closeCallWaiters = {};

  Future<void> closeCalled(int count) => closeCalls >= count
      ? Future.value()
      : (_closeCallWaiters[count] ??= Completer<void>()).future;

  void add(ThreadDirectoryFrame frame) {
    final waiting = _waiting;
    if (waiting == null) {
      _queued.add(frame);
    } else {
      _waiting = null;
      waiting.complete(frame);
    }
  }

  @override
  Future<ThreadDirectoryFrame?> next() {
    if (_queued.isNotEmpty) return Future.value(_queued.removeAt(0));
    if (closeRequested) return Future.value();
    return (_waiting = Completer<ThreadDirectoryFrame?>()).future;
  }

  @override
  void requestClose() {
    if (closeRequested) return;
    closeRequested = true;
    _waiting?.complete();
    _waiting = null;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    _closeCallWaiters.remove(closeCalls)?.complete();
    if (!closeEntered.isCompleted) closeEntered.complete();
    final failure = closeFailure;
    closeFailure = null;
    if (failure != null) throw failure;
    await allowClose.future;
  }
}

StudioThread _thread(String id, {String title = 'Thread'}) => StudioThread(
  id: id,
  workspaceId: 'workspace',
  title: title,
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/workspace',
);

ThreadDirectoryFrame _frame(
  DirectoryQuery query,
  DirectoryWindow window,
  List<StudioThread> threads, {
  int revision = 1,
  String? nextCursor,
}) => ThreadDirectoryFrame(
  query: query,
  window: window,
  stamp: ResourceStamp(
    resourceKey: 'thread-directory',
    ownerEpoch: 'runtime',
    revision: revision,
  ),
  threads: threads,
  nextCursor: nextCursor,
);

void main() {
  test(
    'same demand shares one owner and A to B to A retires exact slots',
    () async {
      final feed = _Feed();
      final store = ThreadDirectoryStore(feed: feed, budget: ResourceBudget());
      const a = DirectoryQuery(search: 'a');
      const b = DirectoryQuery(search: 'b');
      final window = DirectoryWindow();

      final a1 = store.observeThreads(a, window);
      final a2 = store.observeThreads(a, window);
      final b1 = store.observeThreads(b, window);
      expect(feed.threads, hasLength(2));

      final aHandle = _Handle();
      final bHandle = _Handle();
      feed.threads[0].result.complete(aHandle);
      feed.threads[1].result.complete(bHandle);
      aHandle.add(_frame(a, window, [_thread('a')]));
      bHandle.add(_frame(b, window, [_thread('b')]));
      await a1.state.waitFor((state) => state.frame != null);
      await b1.state.waitFor((state) => state.frame != null);
      expect(store.observedWindows.map((frame) => frame.query), {a, b});

      final releasingA1 = a1.release();
      expect(a1.release(), same(releasingA1));
      expect(aHandle.closeRequested, isFalse);
      await releasingA1;
      await expectLater(a1.refresh(), throwsStateError);
      expect(aHandle.closeRequested, isFalse);
      final closingA = a2.release();
      expect(a2.release(), same(closingA));
      expect(aHandle.closeRequested, isTrue);
      expect(store.observedWindows.map((frame) => frame.query), {b});
      var aRetired = false;
      unawaited(closingA.then((_) => aRetired = true));
      await aHandle.closeEntered.future;
      expect(aRetired, isFalse);
      aHandle.allowClose.complete();
      await closingA;
      expect(a2.state.value.closed, isTrue);
      expect(a2.state.value.frame, isNull);

      final a3 = store.observeThreads(a, window);
      expect(feed.threads, hasLength(3), reason: 'retired A is never revived');
      final nextAHandle = _Handle();
      feed.threads[2].result.complete(nextAHandle);
      nextAHandle.add(_frame(a, window, [_thread('a2')], revision: 2));
      await a3.state.waitFor((state) => state.frame?.stamp.revision == 2);

      final closingB = b1.release();
      await bHandle.closeEntered.future;
      bHandle.allowClose.complete();
      await closingB;
      final closingA3 = a3.release();
      await nextAHandle.closeEntered.future;
      nextAHandle.allowClose.complete();
      await closingA3;
      expect(store.observedWindows, isEmpty);
    },
  );

  test(
    'refresh reopens the exact non-first window after old close joins',
    () async {
      final feed = _Feed();
      final store = ThreadDirectoryStore(feed: feed, budget: ResourceBudget());
      const query = DirectoryQuery(workspaceId: 'workspace');
      final window = DirectoryWindow(before: 'cursor-20', limit: 20);
      final observation = store.observeThreads(query, window);
      final first = _Handle();
      feed.threads.single.result.complete(first);
      first.add(
        _frame(query, window, [_thread('older')], nextCursor: 'cursor-40'),
      );
      await observation.state.waitFor((state) => state.frame != null);

      final refreshing = observation.refresh();
      await first.closeEntered.future;
      expect(feed.threads, hasLength(1));
      first.allowClose.complete();
      await refreshing;
      expect(feed.threads, hasLength(2));
      expect(feed.threads.last.window, window);
      final second = _Handle();
      feed.threads.last.result.complete(second);
      second.add(
        _frame(query, window, [
          _thread('older', title: 'changed'),
        ], revision: 2),
      );
      final refreshed = await observation.state.waitFor(
        (state) => state.frame?.stamp.revision == 2,
      );
      expect(refreshed.frame!.threads.single.title, 'changed');

      final closing = observation.release();
      await second.closeEntered.future;
      second.allowClose.complete();
      await closing;
    },
  );

  test(
    'normalized ID demand shares and failed close retries without sealing',
    () async {
      final included = ['pin-b', 'pin-a', 'pin-b'];
      final excluded = ['other-b', 'other-a', 'other-b'];
      final query = DirectoryQuery.withThreadIds(
        workspaceId: 'workspace',
        threadIds: included,
        excludedThreadIds: excluded,
      );
      included
        ..clear()
        ..add('changed');
      excluded.clear();
      expect(query.threadIds, ['pin-a', 'pin-b']);
      expect(query.excludedThreadIds, ['other-a', 'other-b']);
      expect(() => query.threadIds!.add('later'), throwsUnsupportedError);

      final equivalent = DirectoryQuery.withThreadIds(
        workspaceId: 'workspace',
        threadIds: const ['pin-b', 'pin-a'],
        excludedThreadIds: const ['other-b', 'other-a'],
      );
      expect(equivalent, query);
      expect(equivalent.hashCode, query.hashCode);
      expect(
        DirectoryQuery.withThreadIds(threadIds: const []),
        isNot(DirectoryQuery.withThreadIds()),
      );
      expect(
        () => DirectoryQuery.withThreadIds(
          threadIds: List.generate(65, (index) => '$index'),
        ),
        throwsArgumentError,
      );
      expect(
        () => DirectoryQuery.withThreadIds(
          excludedThreadIds: const ['valid', ' '],
        ),
        throwsArgumentError,
      );

      final failures = <UnresolvedResource>[];
      final feed = _Feed();
      final budget = ResourceBudget();
      final store = ThreadDirectoryStore(
        feed: feed,
        budget: budget,
        onCleanupFailure: failures.add,
      );
      final window = DirectoryWindow();
      final firstBorrow = store.observeThreads(query, window);
      final secondBorrow = store.observeThreads(equivalent, window);
      expect(feed.threads, hasLength(1));
      final firstHandle = _Handle();
      feed.threads.single.result.complete(firstHandle);
      firstHandle.add(_frame(query, window, [_thread('pin-a')]));
      await firstBorrow.state.waitFor((state) => state.frame != null);

      await firstBorrow.release();
      final closeFailure = StateError('first close failed');
      firstHandle.closeFailure = closeFailure;
      final releasing = secondBorrow.release();
      expect(secondBorrow.release(), same(releasing));
      await expectLater(releasing, throwsA(same(closeFailure)));
      await expectLater(secondBorrow.refresh(), throwsStateError);
      expect(firstHandle.closeCalls, 1);
      expect(failures.single.reason, same(closeFailure));
      expect(budget.usage, hasLength(2));

      const replacementQuery = DirectoryQuery(search: 'replacement');
      final replacement = store.observeThreads(replacementQuery, window);
      expect(
        feed.threads,
        hasLength(2),
        reason: 'retry does not seal admission',
      );
      final replacementHandle = _Handle();
      feed.threads.last.result.complete(replacementHandle);
      replacementHandle.add(
        _frame(replacementQuery, window, [_thread('replacement')]),
      );
      await replacement.state.waitFor((state) => state.frame != null);

      final retrying = store.retryCleanup();
      await firstHandle.closeCalled(2);
      expect(firstHandle.closeCalls, 2);
      firstHandle.allowClose.complete();
      expect((await retrying).complete, isTrue);
      expect(budget.usage, hasLength(2), reason: 'replacement remains owned');

      final closingReplacement = replacement.release();
      await replacementHandle.closeEntered.future;
      replacementHandle.allowClose.complete();
      await closingReplacement;
      expect(budget.usage, isEmpty);
    },
  );

  test('client retryCleanup settles the failed directory owner', () async {
    final transport = TestConversationTransport();
    final budget = ResourceBudget();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'directory-cleanup',
      budget: budget,
    );
    final observation = client.threadDirectory.observeThreads(
      const DirectoryQuery(search: 'client'),
      DirectoryWindow(),
    );
    await observation.state.waitFor((state) => state.frame != null);

    final closeFailure = StateError('directory native close failed');
    transport.directoryCloseFailure = closeFailure;
    await expectLater(observation.release(), throwsA(same(closeFailure)));
    expect(client.resourceFailure.value?.reason, same(closeFailure));
    expect(transport.directoryCloseCalls, 1);
    expect(budget.usage, isNotEmpty);

    final retried = await client.retryCleanup();
    expect(retried.complete, isTrue);
    expect(transport.directoryCloseCalls, 2);
    expect(budget.usage, isEmpty);
    expect((await client.close()).complete, isTrue);
  });

  test('last release joins an in-flight open and the native close', () async {
    final feed = _Feed();
    final budget = ResourceBudget();
    final store = ThreadDirectoryStore(feed: feed, budget: budget);
    final observation = store.observeThreads(
      const DirectoryQuery(),
      DirectoryWindow(),
    );

    final closing = observation.release();
    expect(observation.release(), same(closing));
    await expectLater(observation.refresh(), throwsStateError);
    var completed = false;
    unawaited(closing.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    final handle = _Handle();
    feed.threads.single.result.complete(handle);
    await handle.closeEntered.future;
    expect(handle.closeRequested, isTrue);
    expect(completed, isFalse);
    handle.allowClose.complete();
    await closing;
    expect(budget.usage, isEmpty);
  });
}
