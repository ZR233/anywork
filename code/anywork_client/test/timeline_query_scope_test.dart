import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 3, maxBytes: 4096);
const _reference = ContentRef(
  databaseId: 'original-database',
  target: ItemPayloadTarget(itemId: 'item'),
);
const _range = ContentRange(offset: 13, maxBytes: 37);
const _collection = CurrentCollectionRef(
  databaseId: 'original-database',
  collection: 'tools',
  revision: 42,
);

ContentWindow _window() => ContentWindow(
  offset: 13,
  bytes: [0, 255, 128],
  generation: 'generation-original',
  availableThrough: 91,
  sealed: true,
);

void main() {
  test('all queries use the original feed reader and preserve opaque arguments/results', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final scope = fixture.session().content.openScope(generation: 9);
    expect(scope.generation, 9);
    expect(scope.threadId, 'thread');
    final manifest = ContentManifestPage(
      entries: [],
      continuation: 'manifest-next',
    );
    final window = _window();
    final collection = CurrentCollectionPage(
      revision: 42,
      entries: [],
      continuation: 'current-next',
    );
    final calls = <String>[];
    feed.reader.onManifest = (item, continuation, demand) async {
      expect(item, 'item');
      expect(continuation, 'manifest-before');
      expect(demand, same(_demand));
      calls.add('manifest');
      return manifest;
    };
    feed.reader.onContent = (reference, range) async {
      expect(reference, same(_reference));
      expect(range, same(_range));
      calls.add('content');
      return window;
    };
    feed.reader.onCurrent = (reference, continuation, demand) async {
      expect(reference, same(_collection));
      expect(continuation, 'current-before');
      expect(demand, same(_demand));
      calls.add('current');
      return collection;
    };
    expect(
      await scope.listContents(
        itemId: 'item',
        continuation: 'manifest-before',
        demand: _demand,
      ),
      same(manifest),
    );
    expect(
      await scope.readContent(reference: _reference, range: _range),
      same(window),
    );
    expect(
      await scope.pageCurrent(
        reference: _collection,
        continuation: 'current-before',
        demand: _demand,
      ),
      same(collection),
    );
    expect(calls, ['manifest', 'content', 'current']);
    expect(feed.acknowledgements, [1]);
    expect(fixture.transport.opens, hasLength(1));
    expect((await scope.close()).complete, isTrue);
    expect(
      feed.requestCloseCalls,
      0,
      reason: 'Display scope only borrows the read lease',
    );
    expect((await fixture.close()).complete, isTrue);
  });

  test('older calls singleflight through IO and acceptance, then admit the next request', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final scope = fixture.session().content.openScope(generation: 1);
    final reply = Completer<ChatBatch>();
    var calls = 0;
    feed.reader.onOlder = (before, demand) {
      calls++;
      expect(before, 'opaque');
      expect(demand, same(_demand));
      return reply.future;
    };
    final first = scope.loadOlder(before: 'opaque', demand: _demand);
    final second = scope.loadOlder(before: 'opaque', demand: _demand);
    expect(second, same(first));
    expect(calls, 1);
    expect(scope.pendingQueries, 1);
    final page = ChatBatch(
      placement: ChatPlacement.prepend,
      entries: [],
      before: 'next',
    );
    reply.complete(page);
    expect(await first, same(page));
    expect(fixture.consumers['thread']!.batches.last, same(page));
    final next = await scope.loadOlder(before: 'opaque', demand: _demand);
    expect(next, same(page));
    expect(calls, 2);
    expect((await fixture.close()).complete, isTrue);
  });

  test('singleflight error propagates unchanged and a subsequent older request can retry', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final scope = fixture.session().content.openScope(generation: 1);
    final failure = StateError('original database error');
    feed.reader.onOlder = (_, __) => Future.error(failure);
    await expectLater(
      scope.loadOlder(before: 'before', demand: _demand),
      throwsA(same(failure)),
    );
    final page = ChatBatch(placement: ChatPlacement.prepend, entries: []);
    feed.reader.onOlder = (_, __) async => page;
    expect(
      await scope.loadOlder(before: 'before', demand: _demand),
      same(page),
    );
    expect(fixture.consumers['thread']!.batches, hasLength(2));
    expect((await fixture.close()).complete, isTrue);
  });

  test(
    'retirement rejects new queries without reaching the borrowed reader',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open(demand: _demand);
      final scope = fixture.session().content.openScope(generation: 1);
      scope.retire();
      await expectLater(
        scope.loadOlder(before: 'before', demand: _demand),
        throwsA(isA<StaleConversationScope>()),
      );
      await expectLater(
        scope.listContents(itemId: 'item', demand: _demand),
        throwsA(isA<StaleConversationScope>()),
      );
      await expectLater(
        scope.readContent(reference: _reference, range: _range),
        throwsA(isA<StaleConversationScope>()),
      );
      await expectLater(
        scope.pageCurrent(reference: _collection, demand: _demand),
        throwsA(isA<StaleConversationScope>()),
      );
      await expectLater(
        scope.watchContent(reference: _reference, range: _range),
        emitsError(isA<StaleConversationScope>()),
      );
      expect(fixture.client.budget.used(ResourceKind.pendingOperation), 0);
      expect(feed.requestCloseCalls, 0);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  for (final fail in [false, true]) {
    test(
      'late ${fail ? 'error' : 'result'} is stale after A-B-A and cannot apply to new A',
      () async {
        final fixture = ConversationFixture();
        final first = await fixture.open(threadId: 'A', demand: _demand);
        final content = fixture.session('A').content;
        final old = content.openScope(generation: 1);
        final reply = Completer<ChatBatch>();
        first.reader.onOlder = (_, __) => reply.future;
        final reading = expectLater(
          old.loadOlder(before: 'old-A-before', demand: _demand),
          throwsA(isA<StaleConversationScope>()),
        );
        fixture.repository.setVisibleThread('B');
        fixture.repository.setVisibleThread('A');
        await fixture.transport.opened(1);
        final second = TestConversationFeed(
          threadId: 'A',
          subscriptionId: 'new-A',
        );
        fixture.transport.opens[1].result.complete(second);
        final replacement = chatSet(messages: [chatMessage(id: 'new-A')]);
        await second.deliver(ConversationChatEvent(batch: replacement));
        final current = content.openScope(generation: 3);
        expect(old.isActive, isFalse);
        expect(current.isActive, isTrue);
        expect(old.pendingQueries, 1);
        if (fail) {
          reply.completeError(StateError('late old error'));
        } else {
          reply.complete(
            ChatBatch(
              placement: ChatPlacement.prepend,
              entries: [ItemChatEntry(chatMessage(id: 'stale'))],
            ),
          );
        }
        await reading;
        expect(fixture.consumers['A']!.batches, hasLength(2));
        expect(fixture.consumers['A']!.batches.last, same(replacement));
        expect(current.isActive, isTrue);
        expect(second.requestCloseCalls, 0);
        expect((await fixture.close()).complete, isTrue);
      },
    );
  }

  test('scope close timeout retains pending operation and does not close a sibling lease', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final content = fixture.session().content;
    final first = content.openScope(generation: 1);
    final sibling = content.openScope(generation: 2);
    final reply = Completer<ContentWindow>();
    feed.reader.onContent = (_, __) => reply.future;
    final reading = expectLater(
      first.readContent(reference: _reference, range: _range),
      throwsA(isA<StaleConversationScope>()),
    );
    final timed = await first.close(deadline: DateTime.now());
    expect(timed.complete, isFalse);
    expect(first.pendingQueries, 1);
    expect(fixture.client.budget.used(ResourceKind.pendingOperation), 1);
    expect(sibling.isActive, isTrue);
    expect(feed.requestCloseCalls, 0);
    reply.complete(_window());
    await reading;
    expect((await first.close()).complete, isTrue);
    expect(sibling.isActive, isTrue);
    expect(fixture.client.budget.used(ResourceKind.pendingOperation), 0);
    expect((await fixture.close()).complete, isTrue);
  });

  test('query budget rejects new IO and releases only on original Future settlement', () async {
    final budget = ResourceBudget(
      capacities: {
        ...ResourceBudget().capacities,
        ResourceKind.pendingOperation: 1,
      },
    );
    final fixture = ConversationFixture(budget: budget);
    final feed = await fixture.open(demand: _demand);
    final scope = fixture.session().content.openScope(generation: 1);
    final reply = Completer<ContentWindow>();
    feed.reader.onContent = (_, __) => reply.future;
    final reading = scope.readContent(reference: _reference, range: _range);
    expect(
      () => scope.listContents(itemId: 'item', demand: _demand),
      throwsA(isA<ResourceBudgetExceeded>()),
    );
    expect(budget.used(ResourceKind.pendingOperation), 1);
    reply.complete(_window());
    await reading;
    expect((await scope.close()).complete, isTrue);
    expect(budget.used(ResourceKind.pendingOperation), 0);
    expect((await fixture.close()).complete, isTrue);
  });

  test('watch budget exhaustion is a stream error and done without Zone escape or leaked admission', () async {
    final budget = ResourceBudget(
      capacities: {
        ...ResourceBudget().capacities,
        ResourceKind.pendingOperation: 1,
      },
    );
    final fixture = ConversationFixture(budget: budget);
    addTearDown(fixture.close);
    final feed = await fixture.open(demand: _demand);
    final scope = fixture.session().content.openScope(generation: 1);
    final reply = Completer<ContentWindow>();
    final window = _window();
    feed.reader.onContent = (_, __) => reply.future;
    final reading = scope.readContent(reference: _reference, range: _range);
    addTearDown(() async {
      if (!reply.isCompleted) reply.complete(window);
      await reading;
    });
    expect(budget.used(ResourceKind.pendingOperation), 1);
    final admitted = budget.usage
        .map((entry) => (entry.kind, entry.owner, entry.phase))
        .toList();
    var watchOpens = 0;
    feed.reader.onWatchHandle = (_, __) {
      watchOpens++;
      throw StateError('Exhausted budget must reject before opening a watch');
    };
    final values = <ContentWindow>[];
    final streamErrors = <Object>[];
    final zoneErrors = <Object>[];
    final terminal = Completer<void>();
    var done = false;
    StreamSubscription<ContentWindow>? subscription;
    runZonedGuarded(
      () {
        subscription = scope
            .watchContent(reference: _reference, range: _range)
            .listen(
              values.add,
              onError: (Object error) => streamErrors.add(error),
              onDone: () {
                done = true;
                if (!terminal.isCompleted) terminal.complete();
              },
            );
      },
      (Object error, StackTrace stack) {
        zoneErrors.add(error);
        // Wake the test on the broken onListen path too, rather than turning a
        // lost Stream error into a timeout or treating an empty Stream as pass.
        if (!terminal.isCompleted) terminal.complete();
      },
    );
    addTearDown(() async {
      await subscription?.cancel();
    });
    await terminal.future;
    expect(zoneErrors, isEmpty);
    expect(streamErrors, hasLength(1));
    expect(
      streamErrors.single,
      isA<ResourceBudgetExceeded>()
          .having((error) => error.kind, 'kind', ResourceKind.pendingOperation)
          .having((error) => error.capacity, 'capacity', 1),
    );
    expect(done, isTrue);
    expect(values, isEmpty);
    expect(watchOpens, 0);
    expect(scope.pendingQueries, 1);
    expect(
      budget.usage.map((entry) => (entry.kind, entry.owner, entry.phase)),
      admitted,
      reason: 'Only the original admitted read may retain a permit',
    );
    expect(feed.reader.closeCalls, 0);
    expect(feed.requestCloseCalls, 0);
    reply.complete(window);
    expect(await reading, same(window));
    expect((await scope.close()).complete, isTrue);
    expect(budget.used(ResourceKind.pendingOperation), 0);
    expect((await fixture.close()).complete, isTrue);
    expect(budget.usage, isEmpty);
  });

  test(
    'manifest, range and current errors retain original backend failure',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open(demand: _demand);
      final scope = fixture.session().content.openScope(generation: 1);
      final failure = StateError('stale revision in native reader');
      feed.reader.onManifest = (_, __, ___) => Future.error(failure);
      feed.reader.onContent = (_, __) => Future.error(failure);
      feed.reader.onCurrent = (_, __, ___) => Future.error(failure);
      await expectLater(
        scope.listContents(itemId: 'item', demand: _demand),
        throwsA(same(failure)),
      );
      await expectLater(
        scope.readContent(reference: _reference, range: _range),
        throwsA(same(failure)),
      );
      await expectLater(
        scope.pageCurrent(reference: _collection, demand: _demand),
        throwsA(same(failure)),
      );
      expect(feed.acknowledgements, [1]);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('watch uses original reference/range, propagates pause and joins cancellation', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final feed = await fixture.open(demand: _demand);
    final scope = fixture.session().content.openScope(generation: 1);
    final paused = Completer<void>();
    final resumed = Completer<void>();
    final handle =
        _ControlledContentWatch(
            onPause: () => paused.complete(),
            onResume: () => resumed.complete(),
          )
          ..cancelGate = Completer<void>()
          ..joinGate = Completer<void>();
    addTearDown(handle.dispose);
    feed.reader.onWatchHandle = (reference, range) {
      expect(reference, same(_reference));
      expect(range, same(_range));
      return handle;
    };
    final values = <ContentWindow>[];
    final arrived = Completer<void>();
    final subscription = scope
        .watchContent(reference: _reference, range: _range)
        .listen((value) {
          values.add(value);
          arrived.complete();
        });
    final window = _window();
    handle.add(window);
    await arrived.future;
    expect(values, [window]);
    subscription.pause();
    await paused.future;
    subscription.resume();
    await resumed.future;
    final cancelling = subscription.cancel();
    await handle.cancelStarted.future;
    await handle.joinStarted.future;
    expect(handle.calls.first, 'requestClose');
    expect(handle.waitingWoken.isCompleted, isTrue);
    expect(fixture.client.budget.used(ResourceKind.pendingOperation), 1);
    expect((await scope.close(deadline: DateTime.now())).complete, isFalse);
    handle.cancelGate!.complete();
    await handle.cancelFinished.future;
    expect(
      fixture.client.budget.used(ResourceKind.pendingOperation),
      1,
      reason: 'Local cancellation does not join the original watch',
    );
    handle.joinGate!.complete();
    await cancelling;
    expect((await scope.close()).complete, isTrue);
    expect(handle.cancelCalls, 1);
    expect(handle.joinCalls, 1);
    expect(handle.windowsReads, 1);
    expect(feed.requestCloseCalls, 0);
    expect(feed.reader.closeCalls, 0);
    expect(fixture.client.budget.used(ResourceKind.pendingOperation), 0);
    expect((await fixture.close()).complete, isTrue);
  });

  group('content watch ownership', () {
    test('retire wakes original handle and joins both sides before releasing permit', () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final feed = await fixture.open(demand: _demand);
      final scope = fixture.session().content.openScope(generation: 1);
      final handle = _ControlledContentWatch()
        ..cancelGate = Completer<void>()
        ..joinGate = Completer<void>();
      addTearDown(handle.dispose);
      feed.reader.onWatchHandle = (_, __) => handle;
      final subscription = scope
          .watchContent(reference: _reference, range: _range)
          .listen((_) {});
      await handle.listening.future;

      scope.retire();
      expect(scope.isActive, isFalse);
      expect(handle.waitingWoken.isCompleted, isTrue);
      await handle.cancelStarted.future;
      await handle.joinStarted.future;
      expect(handle.calls.first, 'requestClose');
      final timed = await scope.close(deadline: DateTime.now());
      expect(timed.complete, isFalse);
      handle.joinGate!.complete();
      await handle.firstJoinFinished.future;
      expect(
        fixture.client.budget.used(ResourceKind.pendingOperation),
        1,
        reason:
            'Native join does not erase the still-pending local cancellation',
      );
      handle.cancelGate!.complete();
      expect((await scope.close()).complete, isTrue);
      expect(handle.cancelCalls, 1);
      expect(handle.joinCalls, 1);
      expect(feed.requestCloseCalls, 0);
      expect(feed.reader.closeCalls, 0);
      await subscription.cancel();
      expect(fixture.client.budget.used(ResourceKind.pendingOperation), 0);
      expect((await fixture.close()).complete, isTrue);
    });

    for (final retryWithClient in [false, true]) {
      test(
        'failed original join retries same handle via ${retryWithClient ? 'retryCleanup' : 'scope.close'}',
        () async {
          final fixture = ConversationFixture();
          addTearDown(fixture.close);
          final feed = await fixture.open(demand: _demand);
          final scope = fixture.session().content.openScope(generation: 1);
          final failure = StateError('original watch join failed');
          final handle = _ControlledContentWatch()..joinFailure = failure;
          addTearDown(handle.dispose);
          var opens = 0;
          feed.reader.onWatchHandle = (reference, range) {
            expect(reference, same(_reference));
            expect(range, same(_range));
            opens++;
            return handle;
          };
          final subscription = scope
              .watchContent(reference: _reference, range: _range)
              .listen((_) {});
          await handle.listening.future;

          final failed = await scope.close();
          expect(failed.complete, isFalse);
          expect(
            failed.unresolved.map((entry) => entry.reason),
            contains(same(failure)),
          );
          expect(handle.joinCalls, 1);
          expect(handle.cancelCalls, 1);
          expect(fixture.client.budget.used(ResourceKind.pendingOperation), 1);
          expect(
            fixture.client.budget.usage
                .where((entry) => entry.owner.startsWith('chat-watch:'))
                .map((entry) => entry.phase),
            [ResourcePhase.unresolved],
          );

          handle.joinFailure = null;
          final retried = retryWithClient
              ? await fixture.client.retryCleanup()
              : await scope.close();
          expect(retried.complete, isTrue);
          expect(handle.joinCalls, 2);
          expect(
            handle.cancelCalls,
            1,
            reason: 'Dart cancel is not the retryable join',
          );
          expect(handle.windowsReads, 1);
          expect(opens, 1);
          expect(fixture.transport.opens, hasLength(1));
          expect(feed.reader.closeCalls, 0);
          expect(feed.requestCloseCalls, 0);
          expect(fixture.client.budget.used(ResourceKind.pendingOperation), 0);
          await subscription.cancel();
          expect((await fixture.close()).complete, isTrue);
        },
      );
    }

    for (final failWindows in [false, true]) {
      test(
        '${failWindows ? 'windows error without EOF' : 'windows EOF'} retains original join failure',
        () async {
          final fixture = ConversationFixture();
          addTearDown(fixture.close);
          final feed = await fixture.open(demand: _demand);
          final scope = fixture.session().content.openScope(generation: 1);
          final joinFailure = StateError('native watch still owned');
          final windowsFailure = StateError('window read failed');
          final handle = _ControlledContentWatch()
            ..joinGate = Completer<void>()
            ..joinFailure = joinFailure;
          addTearDown(handle.dispose);
          var opens = 0;
          feed.reader.onWatchHandle = (_, __) {
            opens++;
            return handle;
          };
          final receivedError = Completer<Object>();
          final subscription = scope
              .watchContent(reference: _reference, range: _range)
              .listen(
                (_) {},
                onError: (Object error) {
                  if (!receivedError.isCompleted) receivedError.complete(error);
                },
              );
          await handle.listening.future;

          if (failWindows) {
            // Deliberately leave windows open: an error must not need a later EOF
            // or page cancellation to start retiring its original native handle.
            handle.addError(windowsFailure);
            expect(await receivedError.future, same(windowsFailure));
            expect(handle.waitingWoken.isCompleted, isTrue);
          } else {
            await handle.finish();
          }
          await handle.joinStarted.future;
          expect(fixture.client.budget.used(ResourceKind.pendingOperation), 1);
          expect(
            (await scope.close(deadline: DateTime.now())).complete,
            isFalse,
          );
          handle.joinGate!.complete();
          final failed = await scope.close();
          expect(failed.complete, isFalse);
          expect(
            failed.unresolved.map((entry) => entry.reason),
            contains(same(joinFailure)),
          );
          expect(fixture.client.budget.used(ResourceKind.pendingOperation), 1);
          handle.joinFailure = null;
          expect((await scope.close()).complete, isTrue);
          expect(handle.windowsReads, 1);
          expect(opens, 1);
          expect(feed.reader.closeCalls, 0);
          expect(feed.requestCloseCalls, 0);
          expect(fixture.client.budget.used(ResourceKind.pendingOperation), 0);
          await subscription.cancel();
          expect((await fixture.close()).complete, isTrue);
        },
      );
    }

    test('local cancellation failure remains unresolved despite successful native join', () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final feed = await fixture.open(demand: _demand);
      final scope = fixture.session().content.openScope(generation: 1);
      final failure = StateError('independent Dart watch cancel failed');
      final handle = _ControlledContentWatch()..cancelFailure = failure;
      addTearDown(handle.dispose);
      var opens = 0;
      feed.reader.onWatchHandle = (_, __) {
        opens++;
        return handle;
      };
      final subscription = scope
          .watchContent(reference: _reference, range: _range)
          .listen((_) {});
      await handle.listening.future;

      final failed = await scope.close();
      expect(failed.complete, isFalse);
      expect(handle.successfulJoins, 1);
      expect(handle.cancelCalls, 1);
      expect(
        failed.unresolved.map((entry) => entry.reason),
        contains(same(failure)),
      );
      expect(fixture.client.budget.used(ResourceKind.pendingOperation), 1);
      final retried = await fixture.client.retryCleanup();
      expect(retried.complete, isFalse);
      expect(
        retried.unresolved.map((entry) => entry.reason),
        contains(same(failure)),
      );
      expect(
        handle.cancelCalls,
        1,
        reason: 'Keep the failed original cancellation Future',
      );
      expect(handle.windowsReads, 1);
      expect(opens, 1);
      expect(feed.reader.closeCalls, 0);
      expect(fixture.client.budget.used(ResourceKind.pendingOperation), 1);
      await expectLater(subscription.cancel(), throwsA(same(failure)));
      expect((await fixture.close()).complete, isFalse);
    });
  });
}

/// A scripted transport resource, not a watch reducer. The two joins have
/// independent gates/errors, and native close cannot finish without a wake.
final class _ControlledContentWatch implements ConversationContentWatch {
  _ControlledContentWatch({
    void Function()? onPause,
    void Function()? onResume,
  }) {
    _windows = StreamController<ContentWindow>(
      sync: true,
      onListen: () => listening.complete(),
      onPause: onPause,
      onResume: onResume,
      onCancel: () async {
        calls.add('cancel');
        cancelCalls++;
        if (!cancelStarted.isCompleted) cancelStarted.complete();
        try {
          await cancelGate?.future;
          if (cancelFailure case final failure?) throw failure;
        } finally {
          if (!cancelFinished.isCompleted) cancelFinished.complete();
        }
      },
    );
  }

  late final StreamController<ContentWindow> _windows;
  final listening = Completer<void>();
  final waitingWoken = Completer<void>();
  final cancelStarted = Completer<void>();
  final cancelFinished = Completer<void>();
  final joinStarted = Completer<void>();
  final firstJoinFinished = Completer<void>();
  final List<String> calls = [];
  Completer<void>? cancelGate;
  Completer<void>? joinGate;
  Object? cancelFailure;
  Object? joinFailure;
  int windowsReads = 0;
  int cancelCalls = 0;
  int joinCalls = 0;
  int successfulJoins = 0;

  @override
  Stream<ContentWindow> get windows {
    windowsReads++;
    return _windows.stream;
  }

  void add(ContentWindow window) => _windows.add(window);
  void addError(Object error) => _windows.addError(error);
  Future<void> finish() => _windows.close();

  @override
  void requestClose() {
    calls.add('requestClose');
    if (!waitingWoken.isCompleted) waitingWoken.complete();
  }

  @override
  Future<void> close() async {
    calls.add('join');
    joinCalls++;
    if (!joinStarted.isCompleted) joinStarted.complete();
    try {
      await waitingWoken.future;
      await joinGate?.future;
      if (joinFailure case final failure?) throw failure;
      successfulJoins++;
    } finally {
      if (!firstJoinFinished.isCompleted) firstJoinFinished.complete();
    }
  }

  Future<void> dispose() async {
    requestClose();
    if (cancelGate case final gate? when !gate.isCompleted) gate.complete();
    if (joinGate case final gate? when !gate.isCompleted) gate.complete();
    await _windows.close();
  }
}
