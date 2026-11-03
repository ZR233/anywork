import 'dart:async';

import 'package:anywork/src/features/shell/sidebar/sidebar_directory_owner.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_models.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Production SidebarDirectoryOwner + production ThreadDirectoryStore. The fake
// below controls only native open/next/close timing; it owns no row projection,
// query membership, ordering, or merge behavior.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('query A-B-A isolates stale next, open error, and close finally', (
    tester,
  ) async {
    final feed = _DirectoryFeed();
    final budget = ResourceBudget();
    final store = ThreadDirectoryStore(feed: feed, budget: budget);
    var changes = 0;
    final owner = SidebarDirectoryOwner(
      observeThreads: store.observeThreads,
      onChanged: () => changes++,
    );
    addTearDown(() async {
      owner.dispose();
      await store.close();
    });

    void configure(String search) {
      owner.configure(
        const [_project],
        SidebarQuerySelection(
          search: search,
          expandedProjectIds: const {_projectId},
        ),
      );
    }

    configure('A');
    await _pumpUntil(tester, () => feed.requests.length == 1, 'query A open');
    final firstARequest = feed.requests[0];
    final firstA = firstARequest.complete(completeNextOnClose: false);
    await _pumpUntil(tester, () => firstA.nextCalls == 1, 'query A next');

    configure('B');
    await _pumpUntil(
      tester,
      () => feed.requests.length == 2 && firstA.closeRequested,
      'query B replaces A while A next is in flight',
    );
    final requestB = feed.requests[1];

    configure('A');
    await _pumpUntil(
      tester,
      () => feed.requests.length == 3,
      'second query A replaces B while B open is in flight',
    );
    final secondARequest = feed.requests[2];
    final secondA = secondARequest.complete();
    await _pumpUntil(
      tester,
      () => secondA.nextCalls == 1,
      'second query A next',
    );
    secondA.emit(
      _frame(secondARequest, [
        _thread('current-a', 'Current A', 2026),
      ], revision: 3),
    );
    await _pumpUntil(
      tester,
      () => owner.windows[_projectId]?.rows.singleOrNull?.title == 'Current A',
      'second query A frame reaches production owner',
    );

    // The retired first A completes next, and the retired B fails open. Neither
    // completion may publish into the current A entry or its finally path.
    firstA.emit(
      _frame(firstARequest, [_thread('stale-a', 'Stale A', 2024)], revision: 1),
    );
    requestB.fail(StateError('retired B open failed'));
    await _pumpUntil(
      tester,
      () => firstA.closeCalled,
      'retired A close converges after its in-flight next',
    );
    expect(owner.windows[_projectId]!.rows.single.title, 'Current A');
    expect(owner.windows[_projectId]!.error, isNull);
    expect(changes, greaterThan(0));

    owner.dispose();
    final report = await store.close();
    expect(report.complete, isTrue);
    expect(firstA.closeCalled, isTrue);
    expect(secondA.closeCalled, isTrue);
    expect(budget.usage, isEmpty);
  });

  testWidgets('refresh preserves an expanded window beyond the first page', (
    tester,
  ) async {
    final feed = _DirectoryFeed();
    final budget = ResourceBudget();
    final store = ThreadDirectoryStore(feed: feed, budget: budget);
    final owner = SidebarDirectoryOwner(
      observeThreads: store.observeThreads,
      onChanged: () {},
    );
    addTearDown(() async {
      owner.dispose();
      await store.close();
    });

    owner.configure(const [
      _project,
    ], SidebarQuerySelection(expandedProjectIds: const {_projectId}));
    await _pumpUntil(
      tester,
      () => feed.requests.length == 1,
      'initial directory open',
    );
    final initialRequest = feed.requests[0];
    expect(initialRequest.window, DirectoryWindow());
    final initial = initialRequest.complete();
    await _pumpUntil(tester, () => initial.nextCalls == 1, 'initial next');
    initial.emit(
      _frame(
        initialRequest,
        _threads(20, prefix: 'initial'),
        revision: 1,
        nextCursor: 'cursor-20',
      ),
    );
    await _pumpUntil(
      tester,
      () => owner.windows[_projectId]?.rows.length == 20,
      'initial 20-row frame',
    );

    owner.more(_projectId);
    await _pumpUntil(
      tester,
      () => feed.requests.length == 2,
      'expanded directory open',
    );
    final expandedRequest = feed.requests[1];
    expect(expandedRequest.window.limit, 40);
    expect(expandedRequest.window.before, isNull);
    final expanded = expandedRequest.complete();
    await _pumpUntil(tester, () => expanded.nextCalls == 1, 'expanded next');
    expanded.emit(
      _frame(
        expandedRequest,
        _threads(40, prefix: 'expanded'),
        revision: 2,
        nextCursor: 'cursor-40',
      ),
    );
    await _pumpUntil(
      tester,
      () => owner.windows[_projectId]?.rows.length == 40,
      'expanded 40-row frame',
    );

    final refreshing = owner.refresh(_projectId);
    await refreshing;
    await _pumpUntil(
      tester,
      () => feed.requests.length == 3,
      'refresh reopens the expanded demand',
    );
    final refreshRequest = feed.requests[2];
    expect(refreshRequest.query, expandedRequest.query);
    expect(refreshRequest.window, expandedRequest.window);
    final refreshed = refreshRequest.complete();
    await _pumpUntil(tester, () => refreshed.nextCalls == 1, 'refresh next');
    refreshed.emit(
      _frame(
        refreshRequest,
        _threads(40, prefix: 'refreshed'),
        revision: 3,
        nextCursor: 'cursor-40',
      ),
    );
    await _pumpUntil(
      tester,
      () => owner.windows[_projectId]?.rows.firstOrNull?.title == 'refreshed-0',
      'refreshed expanded frame',
    );
    expect(owner.windows[_projectId]!.rows, hasLength(40));

    owner.dispose();
    final report = await store.close();
    expect(report.complete, isTrue);
    expect(initial.closeCalled, isTrue);
    expect(expanded.closeCalled, isTrue);
    expect(refreshed.closeCalled, isTrue);
    expect(budget.usage, isEmpty);
  });

  testWidgets('pinned and ordinary demands stay complete and independent', (
    tester,
  ) async {
    final feed = _DirectoryFeed();
    final budget = ResourceBudget();
    final store = ThreadDirectoryStore(feed: feed, budget: budget);
    final owner = SidebarDirectoryOwner(
      observeThreads: store.observeThreads,
      onChanged: () {},
    );
    addTearDown(() async {
      owner.dispose();
      await store.close();
    });

    owner.configure(
      const [_project],
      SidebarQuerySelection(expandedProjectIds: const {_projectId}),
      pinnedThreadIds: const ['pin-b', 'pin-a'],
    );
    await _pumpUntil(
      tester,
      () => feed.requests.length == 2,
      'ordinary and pinned opens',
    );
    final ordinaryRequest = feed.requests.singleWhere(
      (request) => request.query.threadIds == null,
    );
    final pinnedRequest = feed.requests.singleWhere(
      (request) => request.query.threadIds != null,
    );
    expect(ordinaryRequest.query.excludedThreadIds, ['pin-a', 'pin-b']);
    expect(pinnedRequest.query.threadIds, ['pin-a', 'pin-b']);
    expect(pinnedRequest.window.limit, DirectoryQuery.maxIdFilterItems);

    final ordinary = ordinaryRequest.complete();
    final pinned = pinnedRequest.complete();
    await _pumpUntil(
      tester,
      () => ordinary.nextCalls == 1 && pinned.nextCalls == 1,
      'ordinary and pinned next calls',
    );
    ordinary.emit(
      _frame(
        ordinaryRequest,
        [
          _thread('ordinary-b', 'Ordinary B', 2024),
          _thread('ordinary-a', 'Ordinary A', 2026),
        ],
        revision: 1,
        nextCursor: 'ordinary-more',
      ),
    );
    pinned.emit(
      _frame(pinnedRequest, [
        _thread('pin-b', 'Pinned B', 2024),
        _thread('pin-a', 'Pinned A', 2026),
      ], revision: 1),
    );
    await _pumpUntil(
      tester,
      () =>
          owner.windows[_projectId]?.loaded == true &&
          owner.pinnedWindows[_projectId]?.loaded == true,
      'complete ordinary and pinned frames',
    );
    expect(owner.windows[_projectId]!.rows.map((row) => row.threadId), [
      'ordinary-b',
      'ordinary-a',
    ]);
    expect(owner.pinnedWindows[_projectId]!.rows.map((row) => row.threadId), [
      'pin-b',
      'pin-a',
    ]);

    owner.more(_projectId);
    await _pumpUntil(
      tester,
      () => feed.requests.length == 3,
      'ordinary more open',
    );
    final expandedRequest = feed.requests.last;
    expect(expandedRequest.query.threadIds, isNull);
    expect(expandedRequest.query.excludedThreadIds, ['pin-a', 'pin-b']);
    expect(expandedRequest.window.limit, 40);
    expect(pinned.closeRequested, isFalse);
    final expanded = expandedRequest.complete();
    await _pumpUntil(
      tester,
      () => expanded.nextCalls == 1,
      'ordinary more next',
    );
    expanded.emit(
      _frame(expandedRequest, [
        _thread('ordinary-c', 'Ordinary C', 2025),
        _thread('ordinary-a', 'Ordinary A', 2026),
      ], revision: 2),
    );
    await _pumpUntil(
      tester,
      () =>
          owner.windows[_projectId]?.rows.firstOrNull?.threadId == 'ordinary-c',
      'expanded ordinary frame',
    );
    expect(owner.pinnedWindows[_projectId]!.rows.map((row) => row.threadId), [
      'pin-b',
      'pin-a',
    ]);
    expect(pinned.closeRequested, isFalse);

    owner.configure(
      const [_project],
      SidebarQuerySelection(expandedProjectIds: const {_projectId}),
      pinnedThreadIds: const ['pin-c'],
    );
    await _pumpUntil(
      tester,
      () => feed.requests.length == 5 && pinned.closeRequested,
      'changed pins replace both demand groups',
    );
    final replacements = feed.requests.skip(3).toList(growable: false);
    final replacementOrdinary = replacements.singleWhere(
      (request) => request.query.threadIds == null,
    );
    final replacementPinned = replacements.singleWhere(
      (request) => request.query.threadIds != null,
    );
    expect(replacementOrdinary.query.excludedThreadIds, ['pin-c']);
    expect(replacementPinned.query.threadIds, ['pin-c']);
    final nextOrdinary = replacementOrdinary.complete();
    final nextPinned = replacementPinned.complete();
    await _pumpUntil(
      tester,
      () => nextOrdinary.nextCalls == 1 && nextPinned.nextCalls == 1,
      'replacement ordinary and pinned next calls',
    );
    nextOrdinary.emit(
      _frame(replacementOrdinary, [
        _thread('ordinary-d', 'Ordinary D', 2023),
      ], revision: 3),
    );
    nextPinned.emit(
      _frame(replacementPinned, [
        _thread('pin-c', 'Pinned C', 2023),
      ], revision: 3),
    );
    await _pumpUntil(
      tester,
      () =>
          owner.windows[_projectId]?.rows.singleOrNull?.threadId ==
              'ordinary-d' &&
          owner.pinnedWindows[_projectId]?.rows.singleOrNull?.threadId ==
              'pin-c',
      'replacement frames',
    );

    owner.dispose();
    final report = await store.close();
    expect(report.complete, isTrue);
    for (final handle in [
      ordinary,
      pinned,
      expanded,
      nextOrdinary,
      nextPinned,
    ]) {
      expect(handle.closeCalled, isTrue);
    }
    expect(budget.usage, isEmpty);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate,
  String description,
) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (predicate()) return;
    await tester.pump();
  }
  fail('Timed out waiting for $description');
}

ThreadDirectoryFrame _frame(
  _ThreadsOpen request,
  List<SessionDirectoryRow> rows, {
  required int revision,
  String? nextCursor,
}) => ThreadDirectoryFrame(
  query: request.query,
  window: request.window,
  stamp: ResourceStamp(
    resourceKey: 'thread-directory',
    ownerEpoch: 'sidebar-owner-test',
    revision: revision,
  ),
  rows: rows,
  nextCursor: nextCursor,
);

List<SessionDirectoryRow> _threads(int count, {required String prefix}) => [
  for (var index = 0; index < count; index++)
    _thread('$prefix-$index', '$prefix-$index', 2026),
];

const _projectId = 'query-ordering-project';
const _project = StudioProject(
  id: _projectId,
  name: 'Query ordering',
  path: '/synthetic/query-ordering',
);

SessionDirectoryRow _thread(String id, String title, int year) =>
    SessionDirectoryRow(
      sessionId: id,
      agentId: id,
      threadId: id,
      workspaceId: _projectId,
      title: title,
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      updatedAt: DateTime.utc(year),
      status: ThreadStatusView.idle,
      workspaceMode: ThreadWorkspaceMode.local,
      workspacePath: _project.path,
    );

final class _DirectoryFeed implements DirectoryFeedPort {
  final List<_ThreadsOpen> requests = [];

  @override
  Future<ThreadsObservationHandle> openThreadsObservation(
    DirectoryQuery query,
    DirectoryWindow window,
  ) {
    final request = _ThreadsOpen(query, window);
    requests.add(request);
    return request.open.future;
  }

  @override
  Future<ThreadObservationHandle> openThreadObservation(String threadId) =>
      Future.error(
        StateError('No selected-thread observation expected for $threadId'),
      );
}

final class _ThreadsOpen {
  _ThreadsOpen(this.query, this.window);

  final DirectoryQuery query;
  final DirectoryWindow window;
  final Completer<ThreadsObservationHandle> open = Completer();

  _ThreadsHandle complete({bool completeNextOnClose = true}) {
    final handle = _ThreadsHandle(completeNextOnClose: completeNextOnClose);
    open.complete(handle);
    return handle;
  }

  void fail(Object error) => open.completeError(error);
}

final class _ThreadsHandle implements ThreadsObservationHandle {
  _ThreadsHandle({required this.completeNextOnClose});

  final bool completeNextOnClose;
  Completer<ThreadDirectoryFrame?>? _pending;
  int nextCalls = 0;
  bool closeRequested = false;
  bool closeCalled = false;

  @override
  Future<ThreadDirectoryFrame?> next() {
    nextCalls++;
    final pending = Completer<ThreadDirectoryFrame?>();
    _pending = pending;
    if (closeRequested && completeNextOnClose) pending.complete(null);
    return pending.future;
  }

  void emit(ThreadDirectoryFrame frame) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      throw StateError('No directory next is awaiting a frame');
    }
    pending.complete(frame);
  }

  @override
  void requestClose() {
    closeRequested = true;
    final pending = _pending;
    if (completeNextOnClose && pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  @override
  Future<void> close() async {
    closeCalled = true;
    requestClose();
    final pending = _pending;
    if (pending != null && !pending.isCompleted) await pending.future;
  }
}
