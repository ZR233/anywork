import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/src/conversation/data/conversation_content_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';

import '../support/chat_fixtures.dart' show workItem, chatMessage;
import '../support/mapped_conversation_feed.dart';

const _demand = ReadDemand(maxItems: 9, maxBytes: 256 * 1024);

ChatBatch _batch(ChatPlacement placement, {int sequence = 1, String? before}) =>
    ChatBatch(
      placement: placement,
      entries: [
        chatMessage('${placement.name}:$sequence', completionSeq: sequence),
      ],
      before: before,
      fromSeq: placement == ChatPlacement.append ? sequence - 1 : null,
      throughSeq: sequence,
    );
ActivitySnapshot _activity(int revision, {bool empty = false}) =>
    ActivitySnapshot(
      revision: revision,
      completedThrough: 1,
      executionPresent: true,
      entries: empty
          ? const []
          : [
              ActivityEntry(
                identity: const ModelPartActivityIdentity(atomId: 'part'),
                atom: ChatAtom(
                  id: 'part',
                  source: const ForegroundTurnChatSource(turnId: 'turn'),
                  sourceOrder: 1,
                  kind: ChatAtomKind.text,
                  delivery: ChatDeliveryKind.foreground,
                  lifecycle: const ActiveChatAtom(
                    started: null,
                    status: ChatActiveStatus.running,
                  ),
                  contents: const [],
                ),
              ),
            ],
    );

void main() {
  test('manifest and body queries never ACK a frame or automatically admit history', () async {
    final h = _Harness()..attach();
    final feed = await h.opened();
    feed.sendScenario(
      1,
      ConversationChatEvent(batch: _batch(ChatPlacement.set, sequence: 1)),
    );
    await feed.ackScenario(1);
    final scope = h.owner.openScope(generation: 1);
    final listing = scope.listContents(
      itemId: 'original-payload',
      continuation: 'opaque-manifest',
      demand: _demand,
    );
    final manifest = ContentManifestPage(
      entries: const [],
      continuation: 'next-manifest',
    );
    feed.reader.manifest.complete(manifest);
    expect(await listing, same(manifest));
    expect(feed.reader.manifestRequests.single, (
      'original-payload',
      'opaque-manifest',
      _demand,
    ));
    const reference = ContentRef(
      databaseId: 'database',
      target: ItemPayloadTarget(itemId: 'original-payload'),
    );
    const range = ContentRange(offset: 7, maxBytes: 32);
    final reading = scope.readContent(reference: reference, range: range);
    final body = ContentWindow(
      bytes: const [0, 34, 255],
      offset: 7,
      generation: 'body-generation',
      availableThrough: 10,
      sealed: true,
    );
    feed.reader.body.complete(body);
    expect(await reading, same(body));
    expect(feed.reader.bodyRequests.single, (reference, range));
    expect(h.consumer.batches, hasLength(1));
    expect(feed.reader.loads, 0);
    expect(feed.acks, [
      1,
    ], reason: 'Queries do not own feed credit or history admission');
    expect((await h.owner.close()).complete, isTrue);
  });

  for (final lateFailure in [false, true]) {
    test(
      'body query retirement revokes synchronously and joins original late ${lateFailure ? 'failure' : 'success'}',
      () async {
        final h = _Harness()..attach();
        final feed = await h.opened();
        feed.sendScenario(
          1,
          ConversationChatEvent(batch: _batch(ChatPlacement.set, sequence: 1)),
        );
        await feed.ackScenario(1);
        final scope = h.owner.openScope(generation: 1);
        const reference = ContentRef(
          databaseId: 'database',
          target: ItemPayloadTarget(itemId: 'retired-body'),
        );
        final query = scope.readContent(
          reference: reference,
          range: const ContentRange(offset: 0, maxBytes: 16),
        );
        final rejected = expectLater(
          query,
          throwsA(isA<StaleConversationScope>()),
        );
        scope.retire();
        expect(scope.isActive, isFalse);
        var joined = false;
        final close = scope.close().then((report) {
          joined = true;
          return report;
        });
        await Future<void>.delayed(Duration.zero);
        expect(joined, isFalse);
        if (lateFailure) {
          feed.reader.body.completeError(StateError('original body failed'));
        } else {
          feed.reader.body.complete(
            ContentWindow(
              bytes: const [65],
              offset: 0,
              generation: 'retired-generation',
              availableThrough: 1,
              sealed: true,
            ),
          );
        }
        await rejected;
        expect((await close).complete, isTrue);
        expect(h.consumer.batches, hasLength(1));
        expect(feed.acks, [1]);
        expect((await h.owner.close()).complete, isTrue);
      },
    );
  }
  test('real serial ACK accepts an unfinished Run tail immediately without body reads or layout', () async {
    final h = _Harness();
    final controller = InMemoryChatController();
    final presentation = TimelineMessageController(controller, generation: 1);
    h.attach(presentation);
    final feed = await h.opened();
    feed.sendScenario(
      1,
      ConversationChatEvent(
        batch: ChatBatch(
          placement: ChatPlacement.set,
          entries: [workItem('first', count: 1)],
          throughSeq: 1,
        ),
      ),
    );
    await feed.ackScenario(1).timeout(const Duration(seconds: 2));
    final original = controller.messages.single;
    feed.sendScenario(
      2,
      ConversationChatEvent(
        batch: ChatBatch(
          placement: ChatPlacement.append,
          entries: [workItem('second', count: 2)],
          fromSeq: 1,
          throughSeq: 2,
        ),
      ),
    );
    await feed.ackScenario(2).timeout(const Duration(seconds: 2));
    expect(controller.messages.single.id, original.id);
    expect(feed.reader.loads, 0);
    expect((await h.owner.close()).complete, isTrue);
    presentation.dispose();
    controller.dispose();
  });
  test('scope retirement rejects a page already queued behind component acceptance', () async {
    final h = _Harness();
    final accepting = Completer<void>();
    h.consumer.block = accepting.future;
    h.attach();
    final feed = await h.opened();
    feed.sendScenario(
      1,
      ConversationChatEvent(batch: _batch(ChatPlacement.set)),
    );
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

  test(
    'query IO bypasses blocked flow; page Future joins original applyBatch',
    () async {
      final h = _Harness();
      final initialAccepted = Completer<void>();
      h.consumer.block = initialAccepted.future;
      h.attach();
      final feed = await h.opened();
      feed.sendScenario(
        1,
        ConversationChatEvent(batch: _batch(ChatPlacement.set, sequence: 1)),
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
      expect(h.owner.activity.value, isNull);
      expect(
        feed.acks,
        isEmpty,
        reason: 'Content credit waits for actual component acceptance',
      );
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
      expect(h.consumer.batches.first.throughSeq, 1);
      expect(feed.acks, [1]); // A query is not another transport delivery.
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test('Activity is published only after actual acceptance and a later empty snapshot clears it', () async {
    final h = _Harness()..attach();
    final feed = await h.opened();
    feed.sendScenario(
      1,
      ConversationChatEvent(batch: _batch(ChatPlacement.set)),
    );
    await feed.ackScenario(1);
    feed.sendScenario(2, ConversationActivityEvent(snapshot: _activity(1)));
    await feed.ackScenario(2);
    final gate = Completer<void>();
    h.consumer.block = gate.future;
    feed.sendScenario(3, ConversationActivityEvent(snapshot: _activity(2)));
    await Future<void>.delayed(Duration.zero);
    expect(h.owner.activity.value!.revision, 1);
    expect(feed.acks, [1, 2]);
    gate.complete();
    await feed.ackScenario(3);
    expect(h.owner.activity.value!.revision, 2);
    feed.sendScenario(
      4,
      ConversationActivityEvent(snapshot: _activity(3, empty: true)),
    );
    await feed.ackScenario(4);
    expect(h.owner.activity.value!.entries, isEmpty);
    expect(h.consumer.batches, hasLength(1));
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
        feed.sendScenario(
          1,
          ConversationChatEvent(batch: _batch(ChatPlacement.set, sequence: 1)),
        );
        await h.consumer.entered.future;
      }
      feed.sendScenario(sequence, const ConversationClosedEvent());
      // Terminal classification publishes the connection phase on its own
      // observation surface instead of a removed content callback.
      final terminal = await h.owner.state.waitFor(
        (state) => state is ChatReconnecting<bool> || state is ChatFailed<bool>,
      );
      // Even an accepted component operation cannot publish after this barrier.
      gate.complete();
      expect((await h.owner.close()).complete, isTrue);
      expect(
        feed.acks,
        isEmpty,
        reason: 'Terminal frames never return content credit',
      );
      expect(h.owner.activity.value, isNull);
      final error = switch (terminal) {
        ChatReconnecting<bool>(:final error) => error,
        ChatFailed<bool>(:final error) => error,
        _ => null,
      };
      expect(error, isA<ConversationStreamEnded>());
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
      first.sendScenario(
        1,
        ConversationChatEvent(batch: _batch(ChatPlacement.set, sequence: 1)),
      );
      await h.consumer.entered.future;
      lease.cancel();
      final next = _Consumer();
      h.owner.attachConsumer(next, demand: _demand);
      await Future<void>.delayed(Duration.zero);
      final second = h.transport.feeds.last;
      expect(identical(first, second), isFalse);
      second.sendScenario(
        1,
        ConversationChatEvent(batch: _batch(ChatPlacement.set, sequence: 2)),
      );
      await second.ackScenario(1);
      gate.complete();
      await h.owner.joinRetired();
      expect(next.batches.single.entries.single.completionSeq, 2);
      expect(
        first.acks,
        isEmpty,
        reason: 'A retired attempt never returns content credit',
      );
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
      feed.sendScenario(
        1,
        ConversationChatEvent(
          batch: ChatBatch(
            placement: ChatPlacement.set,
            entries: const [],
            throughSeq: 0,
          ),
        ),
      );
      await h.owner.ready;
      expect(h.owner.activity.value, isNull);
      expect(h.consumer.batches.single.entries, isEmpty);
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
      feed.closeFailure = null;
      expect((await h.owner.retryCleanup()).complete, isTrue);
      expect(h.transport.feeds, [feed]);
      expect(feed.closes, 2);
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
    native.failure = null;
    expect((await scope.close()).complete, isTrue);
    expect(
      native.closes,
      2,
      reason: 'Retry joins the same native handle, not the cached Dart cancellation',
    );
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
    expect((await h.owner.close()).complete, isFalse);
  });
}

final class _Harness {
  _Harness({ChatScope scope = const MainChatScope()}) {
    owner = ConversationContentImpl(
      threadId: 'thread',
      transport: transport,
      scope: scope,
    );
  }
  final transport = _Transport();
  final consumer = _Consumer();
  Future<_Feed> opened() async {
    final feed = await transport.opened.future;
    await feed.listening.future;
    return feed;
  }

  late final ConversationContentImpl owner;
  Observation attach([ConversationBatchConsumer? target]) {
    final lease = owner.attachConsumer(target ?? consumer, demand: _demand);
    owner.setDemand(true);
    return lease;
  }
}

final class _Consumer implements ConversationBatchConsumer {
  @override
  Future<void> applyActivity(ActivitySnapshot snapshot) async {
    await block;
  }

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

  /// The state channel has its own subscription and is never observed here, so
  /// this content fixture exposes a real scripted state feed instead of
  /// borrowing content delivery.
  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async => ScriptedConversationStateFeed(threadId: threadId);

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

  void sendScenario(int sequence, ConversationEvent event) => controller.add(
    ConversationFrame(
      threadId: threadId,
      subscriptionId: subscriptionId,
      deliverySequence: sequence,
      event: event,
    ),
  );
  Future<void> ackScenario(int sequence) => _wireAck(sequence);
  Future<void> _wireAck(int sequence) => acks.contains(sequence)
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
  Future<ThreadBusinessRefs> readBusinessRefs() async =>
      const ThreadBusinessRefs(plan: null, interactions: null);
  @override
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  }) => throw UnimplementedError('Not part of this read fixture');
  @override
  String get threadId => 'thread';
  final page = Completer<ChatBatch>();
  final manifest = Completer<ContentManifestPage>();
  final body = Completer<ContentWindow>();
  final manifestRequests = <(String, String?, ReadDemand)>[];
  final bodyRequests = <(ContentRef, ContentRange)>[];
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
  }) {
    manifestRequests.add((itemId, continuation, demand));
    return manifest.future;
  }

  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    bodyRequests.add((reference, range));
    return body.future;
  }

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
