import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

final class _OpenThreads {
  _OpenThreads(this.query, this.window, this.resourceId);
  final DirectoryQuery query;
  final DirectoryWindow window;
  final ClientResourceId resourceId;
  final result = Completer<_Handle>();
}

final class _Feed implements DirectoryFeedPort {
  final lifecycleScope = ClientScope(owner: 'directory-observation-test');
  final List<_OpenThreads> threads = [];
  final Map<int, Completer<_OpenThreads>> _opened = {};
  void Function(_OpenThreads)? onOpen;

  Future<_OpenThreads> opened(int index) => index < threads.length
      ? Future.value(threads[index])
      : (_opened[index] ??= Completer<_OpenThreads>()).future;

  @override
  Future<ThreadsObservationHandle> openThreadsObservation(
    DirectoryQuery query,
    DirectoryWindow window, {
    required ClientResourceId resourceId,
  }) async {
    final acquisition = lifecycleScope.open<_Handle>('test-directory-owner', (
      operation,
    ) async {
      final open = _OpenThreads(query, window, operation.resourceId);
      threads.add(open);
      _opened.remove(threads.length - 1)?.complete(open);
      final callback = onOpen;
      onOpen = null;
      callback?.call(open);
      final handle = await open.result.future;
      handle.resourceId = operation.resourceId;
      return handle;
    }, identity: resourceId);
    await acquisition.ready;
    return _HandleProxy(acquisition);
  }

  @override
  Future<ThreadObservationHandle> openThreadObservation(
    String threadId, {
    required ClientResourceId resourceId,
  }) => throw UnsupportedError('metadata is not used by this fixture');
}

final class _Handle implements ThreadsObservationHandle {
  @override
  late final ClientResourceId resourceId;
  final List<ThreadDirectoryFrame> _queued = [];
  Completer<ThreadDirectoryFrame?>? _waiting;
  final closeEntered = Completer<void>();
  final allowClose = Completer<void>();
  final reading = Completer<void>();
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
    if (!reading.isCompleted) reading.complete();
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

  @override
  Future<void> retryClose() => close();
}

final class _HandleProxy implements ThreadsObservationHandle {
  _HandleProxy(this.acquisition);
  final ClientAcquisition<_Handle> acquisition;

  @override
  ClientResourceId get resourceId => acquisition.resourceId;
  @override
  Future<ThreadDirectoryFrame?> next() async =>
      (await acquisition.ready).next();
  @override
  void requestClose() => acquisition.requestClose();
  @override
  Future<void> close() => acquisition.close();
  @override
  Future<void> retryClose() => acquisition.retryClose();
}

SessionDirectoryRow _thread(String id, {String title = 'Thread'}) =>
    SessionDirectoryRow(
      backend: NativeAgentBackendView(
        config: const NativeAgentConfigView(),
        status: ThreadStatusView.idle,
      ),
      sessionId: 'session-$id',
      agentId: 'agent-$id',
      threadId: id,
      workspaceId: 'workspace',
      title: title,
      mode: ThreadModeId.auto,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      updatedAt: DateTime.utc(2026),
      workspacePath: '/workspace',
    );

ThreadDirectoryFrame _frame(
  DirectoryQuery query,
  DirectoryWindow window,
  List<String> threadIds, {
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
  threadIds: threadIds,
  nextCursor: nextCursor,
);

void main() {
  test('directory identities and metadata retain ACP references and nullable mode without Native status', () async {
    final transport = TestConversationTransport();
    final store = ThreadDirectoryStore(
      feed: transport,
      scope: transport.lifecycleScope.child('directory-store'),
    );
    addTearDown(
      () => store.close(budget: ClientCloseBudget(const Duration(seconds: 1))),
    );
    const query = DirectoryQuery(archived: true);
    final window = DirectoryWindow();
    final native = _thread('native')
        .copyWith(mode: const ThreadModeId('mode.custom'), archived: true);
    const reference = AcpSessionReferenceView(
      accountId: 'definition',
      acpSessionId: 'remote-session',
      cwd: '/synthetic/work',
    );
    final acp = _thread('external').copyWith(
      mode: null,
      backend: const AcpAgentBackendView(reference: reference),
      archived: true,
    );
    final child = native.copyWith(
      threadId: 'child',
      agentId: 'child-agent',
      parentAgentId: native.agentId,
      mode: null,
    );
    for (final row in [native, acp, child]) {
      transport.seedThread(row);
    }
    final lease = store.observeThreads(query, window);
    await lease.state.waitFor((state) => state.frame != null);
    final structure = lease.state.value.frame!;
    expect(structure.threadIds, [native.threadId, acp.threadId]);
    expect(transport.openedMetadataThreadIds, isEmpty);

    final nativeMetadata = store.observeThread(native.threadId);
    final acpMetadata = store.observeThread(acp.threadId);
    final childMetadata = store.observeThread(child.threadId);
    for (final observation in [nativeMetadata, acpMetadata, childMetadata]) {
      await observation.state.waitFor((state) => state.frame != null);
    }
    final observedNative = nativeMetadata.state.value.frame!.row!;
    final observedAcp = acpMetadata.state.value.frame!.row!;
    final observedChild = childMetadata.state.value.frame!.row!;
    expect(observedNative.mode, const ThreadModeId('mode.custom'));
    expect(observedAcp.mode, isNull);
    expect(
      observedAcp.backend,
      const AcpAgentBackendView(reference: reference),
    );
    expect(observedAcp.sessionId, acp.sessionId);
    expect(observedAcp.agentId, acp.agentId);
    expect(observedAcp.threadId, acp.threadId);
    expect(observedAcp.frozenModel, isNull);
    expect(observedAcp.isRootRow, isTrue);
    expect(observedAcp.archived, isTrue);
    expect(observedChild.mode, isNull);
    expect(observedChild.isChildRow, isTrue);
    expect(observedChild.sessionId, native.sessionId);

    transport.emitThread(
      acp.copyWith(title: 'Updated external session'),
      acp.threadId,
      revision: transport.directoryRevision + 1,
    );
    await acpMetadata.state.waitFor(
      (state) => state.frame?.row?.title == 'Updated external session',
    );
    expect(acpMetadata.state.value.frame!.row!.mode, isNull);
    expect(acpMetadata.state.value.frame!.row!.backend, observedAcp.backend);
    expect(lease.state.value.frame, same(structure));
    expect(nativeMetadata.state.value.frame!.row, same(observedNative));
    await Future.wait([
      nativeMetadata.release(),
      acpMetadata.release(),
      childMetadata.release(),
      lease.release(),
    ]);
  });

  test('directory frames freeze and validate ordered thread identities', () {
    final ids = ['first', 'second'];
    final frame = _frame(
      const DirectoryQuery(),
      DirectoryWindow(limit: 2),
      ids,
    );
    ids.add('later');
    expect(frame.threadIds, ['first', 'second']);
    expect(() => frame.threadIds.add('later'), throwsUnsupportedError);
    expect(
      () => _frame(const DirectoryQuery(), DirectoryWindow(), ['same', 'same']),
      throwsArgumentError,
    );
    expect(
      () => _frame(const DirectoryQuery(), DirectoryWindow(), ['']),
      throwsArgumentError,
    );
    expect(
      () => _frame(const DirectoryQuery(), DirectoryWindow(limit: 1), [
        'one',
        'two',
      ]),
      throwsArgumentError,
    );
  });

  test(
    'same demand shares one owner and A to B to A retires exact slots',
    () async {
      final feed = _Feed();
      final store = ThreadDirectoryStore(
        feed: feed,
        scope: feed.lifecycleScope.child('directory-store'),
      );
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
      aHandle.add(_frame(a, window, ['a']));
      bHandle.add(_frame(b, window, ['b']));
      await a1.state.waitFor((state) => state.frame != null);
      await b1.state.waitFor((state) => state.frame != null);
      expect(store.observedWindows.map((frame) => frame.query), {a, b});

      final releasingA1 = a1.release();
      expect(a1.retirementResourceIds, isEmpty);
      expect(a1.release(), same(releasingA1));
      expect(aHandle.closeRequested, isFalse);
      await releasingA1;
      await expectLater(a1.refresh(), throwsStateError);
      expect(aHandle.closeRequested, isFalse);
      final closingA = a2.release();
      expect(a2.retirementResourceIds, [feed.threads[0].resourceId]);
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
      nextAHandle.add(_frame(a, window, ['a2'], revision: 2));
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
      final store = ThreadDirectoryStore(
        feed: feed,
        scope: feed.lifecycleScope.child('directory-store'),
      );
      const query = DirectoryQuery(workspaceId: 'workspace');
      final window = DirectoryWindow(before: 'cursor-20', limit: 20);
      final observation = store.observeThreads(query, window);
      final first = _Handle();
      feed.threads.single.result.complete(first);
      first.add(_frame(query, window, ['older'], nextCursor: 'cursor-40'));
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
      second.add(_frame(query, window, ['older'], revision: 2));
      final refreshed = await observation.state.waitFor(
        (state) => state.frame?.stamp.revision == 2,
      );
      expect(refreshed.frame!.threadIds, ['older']);

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
      final store = ThreadDirectoryStore(
        feed: feed,
        scope: feed.lifecycleScope.child('directory-store'),
        onCleanupFailure: failures.add,
      );
      final window = DirectoryWindow();
      final firstBorrow = store.observeThreads(query, window);
      final secondBorrow = store.observeThreads(equivalent, window);
      expect(feed.threads, hasLength(1));
      final firstHandle = _Handle();
      feed.threads.single.result.complete(firstHandle);
      firstHandle.add(_frame(query, window, ['pin-a']));
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
      expect(failures.single.resourceId, firstHandle.resourceId);

      const replacementQuery = DirectoryQuery(search: 'replacement');
      final replacement = store.observeThreads(replacementQuery, window);
      expect(
        feed.threads,
        hasLength(2),
        reason: 'retry does not seal admission',
      );
      final replacementHandle = _Handle();
      feed.threads.last.result.complete(replacementHandle);
      replacementHandle.add(_frame(replacementQuery, window, ['replacement']));
      await replacement.state.waitFor((state) => state.frame != null);

      final retrying = store.retryCleanup(
        budget: ClientCloseBudget(const Duration(seconds: 1)),
      );
      await firstHandle.closeCalled(2);
      expect(firstHandle.closeCalls, 2);
      firstHandle.allowClose.complete();
      expect((await retrying).complete, isTrue);

      final closingReplacement = replacement.release();
      await replacementHandle.closeEntered.future;
      replacementHandle.allowClose.complete();
      await closingReplacement;
    },
  );

  test('client retryCleanup settles the failed directory owner', () async {
    final transport = TestConversationTransport();
    final client = AnyworkClient(
      transport: transport,
      scope: transport.lifecycleScope.child('client'),
      clientId: 'directory-cleanup',
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

    final retried = await client.retryCleanup(
      budget: ClientCloseBudget(const Duration(seconds: 1)),
    );
    expect(retried.complete, isTrue);
    expect(transport.directoryCloseCalls, 2);
    expect(
      (await client.close(
        budget: ClientCloseBudget(const Duration(seconds: 1)),
      )).complete,
      isTrue,
    );
  });

  test(
    'same-query reacquire waits for old ACK and old lease keeps its identity',
    () async {
      final feed = _Feed();
      final store = ThreadDirectoryStore(
        feed: feed,
        scope: feed.lifecycleScope.child('directory-store'),
      );
      const query = DirectoryQuery(search: 'same');
      final window = DirectoryWindow();
      final oldLease = store.observeThreads(query, window);
      final old = _Handle();
      feed.threads.single.result.complete(old);
      old.add(_frame(query, window, ['old']));
      await oldLease.state.waitFor((state) => state.frame != null);

      final failure = StateError('old cleanup failed');
      old.closeFailure = failure;
      await expectLater(oldLease.release(), throwsA(same(failure)));
      final oldIds = oldLease.retirementResourceIds;
      expect(oldIds, [old.resourceId]);
      final currentLease = store.observeThreads(query, window);
      await currentLease.state.waitFor((state) => state.error != null);
      await expectLater(currentLease.refresh(), throwsA(same(failure)));
      expect(feed.threads, hasLength(1));
      expect(old.closeCalls, 1, reason: 'refresh does not retry native close');

      final retrying = store.retryCleanup(
        budget: ClientCloseBudget(const Duration(seconds: 1)),
      );
      await old.closeCalled(2);
      expect(
        feed.threads,
        hasLength(1),
        reason: 'retry must receive actual ACK',
      );
      old.allowClose.complete();
      expect((await retrying).complete, isTrue);
      final next = await feed.opened(1);
      expect(next.resourceId, isNot(old.resourceId));
      final current = _Handle();
      next.result.complete(current);
      current.add(_frame(query, window, ['new'], revision: 2));
      await currentLease.state.waitFor(
        (state) => state.frame?.stamp.revision == 2,
      );

      await oldLease.release();
      expect(oldLease.retirementResourceIds, same(oldIds));
      expect(old.closeCalls, 2);
      expect(current.closeRequested, isFalse);
      expect(store.observedWindows.single.threadIds, ['new']);
      final closing = currentLease.release();
      expect(currentLease.retirementResourceIds, [next.resourceId]);
      await current.closeEntered.future;
      current.allowClose.complete();
      await closing;
    },
  );

  test(
    'refresh accepts a completed next while waiting for old close ACK',
    () async {
      final feed = _Feed();
      final store = ThreadDirectoryStore(
        feed: feed,
        scope: feed.lifecycleScope.child('directory-store'),
      );
      const query = DirectoryQuery();
      final window = DirectoryWindow();
      final observation = store.observeThreads(query, window);
      final old = _Handle();
      feed.threads.single.result.complete(old);
      old.add(_frame(query, window, ['first']));
      await observation.state.waitFor((state) => state.frame != null);
      await old.reading.future;
      final acceptedNext = observation.state.waitFor(
        (state) => state.frame?.stamp.revision == 2,
      );
      old.add(_frame(query, window, ['completed-next'], revision: 2));
      final refreshing = observation.refresh();
      await acceptedNext;
      await old.closeEntered.future;
      expect(observation.state.value.frame!.threadIds, ['completed-next']);
      expect(feed.threads, hasLength(1));
      old.allowClose.complete();
      await refreshing;
      final current = _Handle();
      feed.threads.last.result.complete(current);
      current.add(_frame(query, window, ['current'], revision: 3));
      await observation.state.waitFor(
        (state) => state.frame?.stamp.revision == 3,
      );
      final closing = observation.release();
      await current.closeEntered.future;
      current.allowClose.complete();
      await closing;
    },
  );

  test(
    'refresh can release synchronously while its new acquisition registers',
    () async {
      final feed = _Feed();
      final store = ThreadDirectoryStore(
        feed: feed,
        scope: feed.lifecycleScope.child('directory-store'),
      );
      const query = DirectoryQuery();
      final window = DirectoryWindow();
      final observation = store.observeThreads(query, window);
      final old = _Handle();
      feed.threads.single.result.complete(old);
      old.add(_frame(query, window, ['old']));
      await observation.state.waitFor((state) => state.frame != null);
      late Future<void> releasing;
      feed.onOpen = (open) {
        releasing = observation.release();
        expect(observation.retirementResourceIds, [open.resourceId]);
      };
      final refreshing = observation.refresh();
      await old.closeEntered.future;
      old.allowClose.complete();
      await refreshing;
      final late = _Handle();
      feed.threads.last.result.complete(late);
      await late.closeEntered.future;
      late.allowClose.complete();
      await releasing;
      expect(observation.retirementResourceIds, [late.resourceId]);
      expect(late.resourceId, isNot(old.resourceId));
      expect((old.closeCalls, late.closeCalls), (1, 1));
      expect(
        late.reading.isCompleted,
        isFalse,
        reason: 'late source is not consumed',
      );
    },
  );

  test('reentrant scoped release reports the assigned source and preserves its close error', () async {
    final feed = _Feed();
    final consumerScope = feed.lifecycleScope.child('directory-consumer');
    final failures = <UnresolvedResource>[];
    final diagnosticFailure = StateError('diagnostic callback failed');
    final store = ThreadDirectoryStore(
      feed: feed,
      scope: feed.lifecycleScope.child('directory-store'),
      onCleanupFailure: (failure) {
        failures.add(failure);
        throw diagnosticFailure;
      },
    );
    const query = DirectoryQuery();
    final window = DirectoryWindow();
    final observation = consumerScope.acquireLease(
      'directory-lease',
      () => store.observeThreads(query, window),
    );
    final old = _Handle();
    feed.threads.single.result.complete(old);
    old.add(_frame(query, window, ['old']));
    await observation.state.waitFor((state) => state.frame != null);

    late Future<CloseReport> closing;
    late Future<void> releasing;
    feed.onOpen = (open) {
      closing = consumerScope.close(
        budget: ClientCloseBudget(const Duration(seconds: 1)),
      );
      releasing = observation.release();
      expect(observation.retirementResourceIds, [open.resourceId]);
    };
    final refreshing = observation.refresh();
    await old.closeEntered.future;
    old.allowClose.complete();
    await refreshing;
    final failure = StateError('late source close failed');
    final late = _Handle()..closeFailure = failure;
    final releaseFailed = expectLater(releasing, throwsA(same(failure)));
    feed.threads.last.result.complete(late);
    await releaseFailed;
    final report = await closing;
    expect(failures.single.resourceId, late.resourceId);
    expect(failures.single.reason, same(failure));
    expect(report.complete, isFalse);
    expect(report.unresolved.single.resourceId, late.resourceId);
    expect(report.unresolved.single.reason, same(failure));
    expect(late.reading.isCompleted, isFalse);
    expect(late.closeCalls, 1);

    late.allowClose.complete();
    final retried = await consumerScope.retryCleanup(
      budget: ClientCloseBudget(const Duration(seconds: 1)),
    );
    expect(retried.complete, isTrue);
    expect(late.closeCalls, 2);
    expect(failures, hasLength(1));
  });

  test(
    'release after a failed open has closed omits its retired identity',
    () async {
      final feed = _Feed();
      final sourceScope = feed.lifecycleScope.child('directory-store');
      final consumerScope = feed.lifecycleScope.child('directory-consumer');
      final store = ThreadDirectoryStore(feed: feed, scope: sourceScope);
      final observation = consumerScope.acquireLease(
        'directory-lease',
        () => store.observeThreads(const DirectoryQuery(), DirectoryWindow()),
      );

      feed.threads.single.result.completeError(StateError('open failed'));
      await observation.state.waitFor((state) => state.error != null);
      final sourceReport = await sourceScope.retryCleanup(
        budget: ClientCloseBudget(const Duration(seconds: 1)),
      );
      expect(sourceReport.complete, isTrue);

      final report = await consumerScope.close(
        budget: ClientCloseBudget(const Duration(seconds: 1)),
      );
      expect(observation.retirementResourceIds, isEmpty);
      expect(report.complete, isTrue);
      expect(
        (await feed.lifecycleScope.close(
          budget: ClientCloseBudget(const Duration(seconds: 1)),
        )).complete,
        isTrue,
      );
    },
  );

  test('scope rejection before source identity allocation creates no cleanup report', () async {
    final feed = _Feed();
    final sourceScope = feed.lifecycleScope.child('directory-store');
    final consumerScope = feed.lifecycleScope.child('directory-consumer');
    final failures = <UnresolvedResource>[];
    final store = ThreadDirectoryStore(
      feed: feed,
      scope: sourceScope,
      onCleanupFailure: failures.add,
    );
    const query = DirectoryQuery();
    final window = DirectoryWindow();
    final observation = consumerScope.acquireLease(
      'directory-lease',
      () => store.observeThreads(query, window),
    );
    final old = _Handle();
    feed.threads.single.result.complete(old);
    old.add(_frame(query, window, ['old']));
    await observation.state.waitFor((state) => state.frame != null);

    final refreshing = observation.refresh();
    final rejected = expectLater(
      refreshing,
      throwsA(isA<ClientResourceClosed>()),
    );
    await old.closeEntered.future;
    sourceScope.requestClose();
    old.allowClose.complete();
    await rejected;
    expect(feed.threads, hasLength(1));
    final report = await consumerScope.close(
      budget: ClientCloseBudget(const Duration(seconds: 1)),
    );
    await observation.release();
    expect(observation.retirementResourceIds, isEmpty);
    expect(report.complete, isTrue);
    expect(failures, isEmpty);
    expect(old.closeCalls, 1);
  });

  test('last release joins an in-flight open and the native close', () async {
    final feed = _Feed();
    final store = ThreadDirectoryStore(
      feed: feed,
      scope: feed.lifecycleScope.child('directory-store'),
    );
    final observation = store.observeThreads(
      const DirectoryQuery(),
      DirectoryWindow(),
    );

    final closing = observation.release();
    expect(observation.retirementResourceIds, [feed.threads.single.resourceId]);
    expect(observation.release(), same(closing));
    await expectLater(observation.refresh(), throwsStateError);
    var completed = false;
    unawaited(closing.then((_) => completed = true));
    expect(completed, isFalse);

    final handle = _Handle();
    feed.threads.single.result.complete(handle);
    await handle.closeEntered.future;
    expect(handle.closeRequested, isTrue);
    expect(completed, isFalse);
    handle.allowClose.complete();
    await closing;
  });
}
