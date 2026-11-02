import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/conversation/data/conversation_content_impl.dart';
import 'package:anywork_client/src/lifecycle/resource_budget.dart';
import 'package:flutter_test/flutter_test.dart';

const _demand = ReadDemand(maxItems: 9, maxBytes: 256 * 1024);

CurrentProjection _current(int source) => CurrentProjection(
  sourceEffectSeq: source,
  logicalStatus: ThreadStatusView.idle,
  executionPresent: false,
  previews: const [],
  collections: const [],
);

ChatBatch _batch(ChatPlacement placement, {int? current, String? before}) =>
    ChatBatch(
      placement: placement,
      messages: [
        ChatMessage(
          id: '${placement.name}:${current ?? before}',
          payload: InlinePayload(bytes: const [123, 125]),
        ),
      ],
      current: current == null ? null : _current(current),
      before: before,
    );

void main() {
  test('scope retirement rejects a page already queued behind component acceptance', () async {
    final h = _Harness();
    final accepting = Completer<void>();
    h.consumer.block = accepting.future;
    h.attach();
    final feed = await h.opened();
    feed.send(1, ConversationChatEvent(batch: _batch(ChatPlacement.set)));
    await h.consumer.entered.future;
    final scope = h.owner.openScope(generation: 1);
    final page = scope.loadOlder(before: 'before', demand: _demand);
    final rejected = expectLater(page, throwsA(isA<StaleConversationScope>()));
    feed.reader.page.complete(_batch(ChatPlacement.prepend, before: 'older'));
    await Future<void>.delayed(
      Duration.zero,
    ); // IO has entered the serial queue.
    scope.retire();
    accepting.complete();
    await rejected;
    expect(
      h.consumer.batches.map((batch) => batch.placement),
      [ChatPlacement.set],
      reason: 'Reporting stale after consumer.applyBatch cannot undo admission',
    );
    expect((await h.owner.close()).complete, isTrue);
  });

  test('watch budget rejection reaches the original stream and completes without a handle', () async {
    final h = _Harness()..attach();
    final feed = await h.opened();
    final permits = [
      for (
        var i = 0;
        i < h.budget.capacities[ResourceKind.pendingOperation]!;
        i++
      )
        h.budget.acquire(ResourceKind.pendingOperation, owner: 'saturated:$i'),
    ];
    var opened = false;
    feed.reader.watchFactory = () {
      opened = true;
      return _Watch(const Stream.empty());
    };
    final scope = h.owner.openScope(generation: 1);
    final errors = <Object>[];
    final zoneErrors = <Object>[];
    final done = Completer<void>();
    late StreamSubscription<ContentWindow> subscription;
    await runZonedGuarded(() async {
      subscription = scope
          .watchContent(
            reference: const ContentRef(
              databaseId: 'db',
              target: ItemPayloadTarget(itemId: 'item'),
            ),
            range: const ContentRange(offset: 0, maxBytes: 32),
          )
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => zoneErrors.add(error));
    expect(zoneErrors, isEmpty);
    expect(errors.single, isA<ResourceBudgetExceeded>());
    expect(done.isCompleted, isTrue);
    expect(opened, isFalse);
    expect(h.budget.used(ResourceKind.pendingOperation), permits.length);
    await subscription.cancel();
    expect((await scope.close()).complete, isTrue);
    for (final permit in permits) {
      permit.release();
    }
    expect((await h.owner.close()).complete, isTrue);
  });

  test(
    'query IO bypasses blocked flow; page Future joins original applyBatch',
    () async {
      final h = _Harness();
      final initialAccepted = Completer<void>();
      h.consumer.block = initialAccepted.future;
      h.attach();
      final feed = await h.opened();
      feed.send(
        1,
        ConversationChatEvent(batch: _batch(ChatPlacement.set, current: 1)),
      );
      await h.consumer.entered.future;
      final query = h.owner.openScope(generation: 1);
      final older = query.loadOlder(before: 'cursor', demand: _demand);
      expect(feed.reader.loads, 1);
      expect(
        identical(older, query.loadOlder(before: 'cursor', demand: _demand)),
        isTrue,
      );
      feed.reader.page.complete(_batch(ChatPlacement.prepend, before: 'older'));
      await Future<void>.delayed(Duration.zero);
      expect(h.consumer.batches.length, 1);
      expect(h.owner.current.value, isNull);
      expect(feed.acks, isEmpty);
      final pageAccepted = Completer<void>();
      h.consumer.block = pageAccepted.future;
      initialAccepted.complete();
      await h.owner.ready;
      await Future<void>.delayed(Duration.zero);
      var returned = false;
      unawaited(older.then((_) => returned = true));
      expect(h.consumer.batches.map((b) => b.placement), [
        ChatPlacement.set,
        ChatPlacement.prepend,
      ]);
      expect(returned, isFalse);
      pageAccepted.complete();
      expect((await older).before, 'older');
      expect(h.owner.current.value!.sourceEffectSeq, 1);
      expect(feed.acks, [1]); // A query is not another transport delivery.
      expect((await h.owner.close()).complete, isTrue);
      expect(h.budget.used(ResourceKind.pendingOperation), 0);
    },
  );

  test('current is published after acceptance; null retains, empty snapshot clears', () async {
    final h = _Harness()..attach();
    final feed = await h.opened();
    feed.send(
      1,
      ConversationChatEvent(batch: _batch(ChatPlacement.set, current: 1)),
    );
    await h.owner.ready;
    await feed.ack(1);
    final gate = Completer<void>();
    h.consumer.block = gate.future;
    feed.send(
      2,
      ConversationChatEvent(batch: _batch(ChatPlacement.append, current: 2)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(h.owner.current.value!.sourceEffectSeq, 1);
    expect(feed.acks, [1]);
    gate.complete();
    await feed.ack(2);
    expect(h.owner.current.value!.sourceEffectSeq, 2);
    feed.send(3, ConversationChatEvent(batch: _batch(ChatPlacement.append)));
    await feed.ack(3);
    expect(h.owner.current.value!.sourceEffectSeq, 2);
    expect((await h.owner.close()).complete, isTrue);
  });

  for (final sequence in [0, 1]) {
    test('terminal sequence $sequence is classified without credit or ACK', () async {
      final h = _Harness();
      final gate = Completer<void>();
      h.consumer.block = gate.future;
      h.attach();
      final feed = await h.opened();
      if (sequence == 1) {
        feed.send(
          1,
          ConversationChatEvent(batch: _batch(ChatPlacement.set, current: 1)),
        );
        await h.consumer.entered.future;
      }
      feed.send(sequence, const ConversationClosedEvent());
      await h.failed.future;
      // Even an accepted component operation cannot publish after this barrier.
      gate.complete();
      expect((await h.owner.close()).complete, isTrue);
      expect(feed.acks, isEmpty);
      expect(h.owner.current.value, isNull);
      expect(h.failures.single, isA<ConversationStreamEnded>());
    });
  }

  test(
    'detached consumer cannot publish to a same-thread replacement',
    () async {
      final h = _Harness();
      final gate = Completer<void>();
      h.consumer.block = gate.future;
      final lease = h.attach();
      final first = await h.opened();
      first.send(
        1,
        ConversationChatEvent(batch: _batch(ChatPlacement.set, current: 1)),
      );
      await h.consumer.entered.future;
      lease.cancel();
      final next = _Consumer();
      h.owner.attachConsumer(next, demand: _demand);
      await Future<void>.delayed(Duration.zero);
      final second = h.transport.feeds.last;
      expect(identical(first, second), isFalse);
      second.send(
        1,
        ConversationChatEvent(batch: _batch(ChatPlacement.set, current: 2)),
      );
      await second.ack(1);
      gate.complete();
      await h.owner.joinRetired();
      expect(h.owner.current.value!.sourceEffectSeq, 2);
      expect(first.acks, isEmpty);
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test(
    'Children has independent consumer, scope and current ownership',
    () async {
      final h = _Harness(
        scope: const ChildrenChatScope(parentId: 'turn:opaque'),
      )..attach();
      final feed = await h.opened();
      expect(
        (h.transport.scopes.single as ChildrenChatScope).parentId,
        'turn:opaque',
      );
      feed.send(
        1,
        ConversationChatEvent(
          batch: ChatBatch(placement: ChatPlacement.set, messages: const []),
        ),
      );
      await h.owner.ready;
      expect(h.owner.current.value, isNull);
      expect(h.consumer.batches.single.messages, isEmpty);
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test(
    'close failure keeps unresolved owner and retry joins the original facade',
    () async {
      final h = _Harness()..attach();
      final feed = await h.opened();
      feed.closeFailure = StateError('read lease close failed');
      final report = await h.owner.close();
      expect(report.complete, isFalse);
      expect(h.owner.ownedAttemptCount, 1);
      expect(h.budget.used(ResourceKind.chatHandle), 1);
      feed.closeFailure = null;
      expect((await h.owner.retryCleanup()).complete, isTrue);
      expect(h.transport.feeds, [feed]);
      expect(feed.closes, 2);
      expect(h.budget.used(ResourceKind.chatHandle), 0);
    },
  );

  test(
    'retiring query rejects late error and releases permit only on settlement',
    () async {
      final h = _Harness()..attach();
      final feed = await h.opened();
      final scope = h.owner.openScope(generation: 1);
      final older = scope.loadOlder(before: 'cursor', demand: _demand);
      final assertion = expectLater(
        older,
        throwsA(isA<StaleConversationScope>()),
      );
      scope.retire();
      expect((await scope.close(deadline: DateTime.now())).complete, isFalse);
      expect(h.budget.used(ResourceKind.pendingOperation), 1);
      feed.reader.page.completeError(StateError('old database failed'));
      await assertion;
      expect((await scope.close()).complete, isTrue);
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test(
    'watch pause propagates and retirement retains cancellation join',
    () async {
      final h = _Harness()..attach();
      final feed = await h.opened();
      final cancelled = Completer<void>();
      var pauses = 0;
      var resumes = 0;
      var closes = 0;
      final windows = StreamController<ContentWindow>(
        onPause: () => pauses++,
        onResume: () => resumes++,
        onCancel: () {
          closes++;
          return cancelled.future;
        },
      );
      final nativeWatch = _Watch(windows.stream);
      feed.reader.watchFactory = () => nativeWatch;
      final scope = h.owner.openScope(generation: 1);
      final subscription = scope
          .watchContent(
            reference: const ContentRef(
              databaseId: 'database',
              target: ItemPayloadTarget(itemId: 'item'),
            ),
            range: const ContentRange(offset: 0, maxBytes: 4096),
          )
          .listen((_) {});
      subscription.pause();
      expect(pauses, 1);
      subscription.resume();
      expect(resumes, 1);
      scope.retire();
      expect(nativeWatch.requests, greaterThan(0)); // Synchronous native wake.
      expect((await scope.close(deadline: DateTime.now())).complete, isFalse);
      expect(h.budget.used(ResourceKind.pendingOperation), 1);
      cancelled.complete();
      expect((await scope.close()).complete, isTrue);
      expect(closes, 1);
      await subscription.cancel();
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test('failed original watch join is retried after subscription cancel has settled', () async {
    final h = _Harness()..attach();
    final feed = await h.opened();
    final windows = StreamController<ContentWindow>();
    final native = _Watch(windows.stream)
      ..failure = StateError('native join failed');
    feed.reader.watchFactory = () => native;
    final scope = h.owner.openScope(generation: 1);
    final subscription = scope
        .watchContent(
          reference: const ContentRef(
            databaseId: 'db',
            target: ItemPayloadTarget(itemId: 'item'),
          ),
          range: const ContentRange(offset: 0, maxBytes: 32),
        )
        .listen((_) {});
    await expectLater(subscription.cancel(), throwsStateError);
    expect(native.closes, 1);
    expect(h.budget.used(ResourceKind.pendingOperation), 1);
    native.failure = null;
    expect((await scope.close()).complete, isTrue);
    expect(
      native.closes,
      2,
      reason: 'Retry joins the same native handle, not the cached Dart cancellation',
    );
    expect(h.budget.used(ResourceKind.pendingOperation), 0);
    expect((await h.owner.close()).complete, isTrue);
  });

  test(
    'EOF cannot release original watch ownership when native join fails',
    () async {
      final h = _Harness()..attach();
      final feed = await h.opened();
      final windows = StreamController<ContentWindow>();
      final native = _Watch(windows.stream)
        ..failure = StateError('EOF join failed');
      feed.reader.watchFactory = () => native;
      final scope = h.owner.openScope(generation: 1);
      final subscription = scope
          .watchContent(
            reference: const ContentRef(
              databaseId: 'db',
              target: ItemPayloadTarget(itemId: 'item'),
            ),
            range: const ContentRange(offset: 0, maxBytes: 32),
          )
          .listen((_) {}, onError: (Object _) {});
      await windows.close();
      await Future<void>.delayed(Duration.zero);
      expect((await scope.close()).complete, isFalse);
      expect(h.budget.used(ResourceKind.pendingOperation), 1);
      native.failure = null;
      expect((await scope.close()).complete, isTrue);
      await subscription.cancel();
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test('successful native close cannot erase a failed local subscription cancellation', () async {
    final h = _Harness()..attach();
    final feed = await h.opened();
    final cancellationFailure = StateError(
      'local subscription cancellation failed',
    );
    final windows = StreamController<ContentWindow>(
      onCancel: () => Future<void>.error(cancellationFailure),
    );
    final native = _Watch(windows.stream);
    feed.reader.watchFactory = () => native;
    final scope = h.owner.openScope(generation: 1);
    final subscription = scope
        .watchContent(
          reference: const ContentRef(
            databaseId: 'db',
            target: ItemPayloadTarget(itemId: 'item'),
          ),
          range: const ContentRange(offset: 0, maxBytes: 32),
        )
        .listen((_) {});
    await expectLater(
      subscription.cancel(),
      throwsA(same(cancellationFailure)),
    );
    expect(
      native.closes,
      1,
      reason:
          'The native side is still processed after local cancellation fails',
    );
    final report = await scope.close();
    expect(report.complete, isFalse);
    expect(
      report.unresolved.map((resource) => resource.reason),
      contains(same(cancellationFailure)),
    );
    expect(h.budget.used(ResourceKind.pendingOperation), 1);
    expect((await h.owner.close()).complete, isFalse);
  });
}

final class _Harness {
  _Harness({ChatScope scope = const MainChatScope()}) {
    owner = ConversationContentImpl(
      threadId: 'thread',
      transport: transport,
      budget: budget,
      scope: scope,
      onState: (_, _) {},
      onAttempt: (_) {},
      onFailure: (_, error, _) {
        failures.add(error);
        if (!failed.isCompleted) failed.complete();
      },
    );
  }
  final budget = ResourceBudget();
  final transport = _Transport();
  final consumer = _Consumer();
  final failures = <Object>[];
  final failed = Completer<void>();
  Future<_Feed> opened() async {
    final feed = await transport.opened.future;
    await feed.listening.future;
    return feed;
  }

  late final ConversationContentImpl owner;
  Observation attach() {
    final lease = owner.attachConsumer(consumer, demand: _demand);
    owner.setDemand(true);
    return lease;
  }
}

final class _Consumer implements ConversationBatchConsumer {
  final batches = <ChatBatch>[];
  final entered = Completer<void>();
  Future<void>? block;
  @override
  Future<void> applyBatch(ChatBatch batch) async {
    batches.add(batch);
    if (!entered.isCompleted) entered.complete();
    await block;
  }
}

final class _Transport implements ConversationTransport {
  final opened = Completer<_Feed>();
  final feeds = <_Feed>[];
  final scopes = <ChatScope>[];
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    expect(demand.maxItems, _demand.maxItems);
    scopes.add(scope);
    final feed = _Feed('subscription:${feeds.length}');
    feeds.add(feed);
    if (!opened.isCompleted) opened.complete(feed);
    return feed;
  }
}

final class _Feed implements ConversationFeed {
  _Feed(this.subscriptionId);
  @override
  String get threadId => 'thread';
  @override
  final String subscriptionId;
  @override
  final _Reader reader = _Reader();
  final controller = StreamController<ConversationFrame>();
  final listening = Completer<void>();
  final acks = <int>[];
  final waiting = <int, Completer<void>>{};
  Object? closeFailure;
  int closes = 0;
  @override
  Stream<ConversationFrame> get events {
    if (!listening.isCompleted) listening.complete();
    return controller.stream;
  }

  void send(int sequence, ConversationEvent event) => controller.add(
    ConversationFrame(
      threadId: threadId,
      subscriptionId: subscriptionId,
      deliverySequence: sequence,
      event: event,
    ),
  );
  Future<void> ack(int sequence) => acks.contains(sequence)
      ? Future.value()
      : (waiting[sequence] ??= Completer<void>()).future;
  @override
  Future<void> acknowledge(int deliverySequence) async {
    acks.add(deliverySequence);
    waiting.remove(deliverySequence)?.complete();
  }

  @override
  void requestClose() {}
  @override
  Future<void> close() async {
    closes++;
    if (closeFailure case final failure?) throw failure;
    // Closing native ownership must also work before events has a listener.
    unawaited(controller.close());
  }
}

final class _Reader implements ConversationReader {
  @override
  String get threadId => 'thread';
  final page = Completer<ChatBatch>();
  int loads = 0;
  ConversationContentWatch Function()? watchFactory;
  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) {
    loads++;
    return page.future;
  }

  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) async => ContentManifestPage(entries: const []);
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) => throw UnimplementedError();
  @override
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) => watchFactory?.call() ?? _Watch(const Stream.empty());
  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) async =>
      CurrentCollectionPage(revision: reference.revision, entries: const []);
  @override
  void requestClose() {}
  @override
  Future<void> close() async {}
}

final class _Watch implements ConversationContentWatch {
  _Watch(this.windows);
  @override
  final Stream<ContentWindow> windows;
  int requests = 0;
  int closes = 0;
  Object? failure;
  @override
  void requestClose() {
    requests++;
  }

  @override
  Future<void> close() async {
    closes++;
    if (failure case final error?) throw error;
  }
}
