import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/src/conversation/data/conversation_content_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';

import '../support/chat_fixtures.dart' show chatMessage;
import '../support/display_fixtures.dart';
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
  test('real serial ACK accepts live Work immediately and freezes only at the boundary without member/body reads or layout', () async {
    final h = _Harness();
    final controller = InMemoryChatController();
    final presentation = TimelineMessageController(controller, generation: 1);
    h.owner.attachTimelineConsumer(
      _TimelineConsumer(presentation),
      demand: _demand,
    );
    h.owner.setDemand(true);
    final feed = await h.opened();
    expect(
      h.transport.scopes,
      isEmpty,
      reason: 'The GUI consumer opens Timeline, never the atomic Chat feed',
    );
    const reference = DisplayBlockRef(databaseId: 'db', blockId: 'work');
    WorkDisplayBlock body(int total, int terminal) => WorkDisplayBlock(
      summary: displaySummary(
        total,
        terminal: terminal,
        running: total - terminal,
      ),
      members: reference,
    );
    LiveDisplayWindow live(int revision, int total, int terminal) =>
        LiveDisplayWindow(
          revision: revision,
          historyThrough: 0,
          executionPresent: true,
          blocks: [
            LiveDisplayBlock(
              id: reference.blockId,
              blockOrder: 1,
              closing: false,
              body: body(total, terminal),
            ),
          ],
        );
    final initial = live(1, 1, 0);
    feed.sendScenario(
      1,
      ConversationTimelineEvent(
        batch: displayBatch([], through: 0, live: initial),
      ),
    );
    await feed.ackScenario(1).timeout(const Duration(seconds: 2));
    expect(controller.messages, isEmpty);
    expect(h.owner.live.value, same(initial));
    for (final (sequence, terminal) in [(2, 1), (3, 2)]) {
      final current = live(sequence, 2, terminal);
      feed.sendScenario(
        sequence,
        ConversationTimelineEvent(
          batch: displayBatch(
            [],
            placement: ChatPlacement.append,
            from: 0,
            live: current,
          ),
        ),
      );
      await feed.ackScenario(sequence).timeout(const Duration(seconds: 2));
      expect(h.owner.live.value, same(current));
      expect(
        (current.blocks.single.body as WorkDisplayBlock).members,
        reference,
      );
      expect(
        controller.messages,
        isEmpty,
        reason:
            'Even all terminal members do not freeze a Work without a boundary',
      );
    }
    final frozen = DisplayBlock(
      id: reference.blockId,
      historyPos: 1,
      body: body(2, 2),
    );
    feed.sendScenario(
      4,
      ConversationTimelineEvent(
        batch: displayBatch(
          [frozen],
          placement: ChatPlacement.append,
          from: 0,
          live: LiveDisplayWindow(
            revision: 4,
            historyThrough: 1,
            executionPresent: false,
            blocks: const [],
          ),
        ),
      ),
    );
    await feed.ackScenario(4).timeout(const Duration(seconds: 2));
    expect(controller.messages.single.id, reference.blockId);
    expect(h.owner.live.value!.blocks, isEmpty);
    expect(feed.acks, [1, 2, 3, 4]);
    expect(feed.timelineQueries, 0);
    expect(feed.memberOpens, 0);
    expect(feed.reader.loads, 0);
    expect(feed.reader.manifestRequests, isEmpty);
    expect(feed.reader.bodyRequests, isEmpty);
    expect(h.failures, isEmpty);
    expect((await h.owner.close()).complete, isTrue);
    presentation.dispose();
    controller.dispose();
  });
  test('component failed Future preserves accepted live, Main and ACK through real serial admission', () async {
    final h = _Harness();
    final component = _FailingAppendComponent();
    final intents = <String, TimelineExpansionIntent>{};
    final projection = TimelineMessageController(
      component,
      generation: 1,
      expansionForBlock: (id) =>
          intents.putIfAbsent(id, TimelineExpansionIntent.new),
    );
    h.owner.attachTimelineConsumer(
      _TimelineConsumer(projection),
      demand: _demand,
    );
    h.owner.setDemand(true);
    final feed = await h.opened();
    final work = LiveDisplayBlock(
      id: 'work',
      blockOrder: 1,
      closing: true,
      body: WorkDisplayBlock(
        summary: displaySummary(2, terminal: 1, running: 1),
        members: const DisplayBlockRef(databaseId: 'db', blockId: 'work'),
      ),
    );
    final live = LiveDisplayWindow(
      revision: 1,
      historyThrough: 1,
      executionPresent: true,
      blocks: [work],
    );
    final intent = intents.putIfAbsent('work', TimelineExpansionIntent.new)
      ..expanded = true;
    final originalUnit = TimelineDisplayUnit.live(
      block: work,
      executionPresent: true,
      expansion: intent,
    );
    intent.current = originalUnit;
    feed.sendScenario(
      1,
      ConversationTimelineEvent(
        batch: displayBatch([displayWork('old', 1)], live: live),
      ),
    );
    await feed.ackScenario(1);
    final original = component.messages.single;
    var notifications = 0;
    final observation = h.owner.live.watch((_) => notifications++);
    final gate = Completer<void>();
    component.failure = gate.future;
    feed.sendScenario(
      2,
      ConversationTimelineEvent(
        batch: displayBatch(
          [displayWork('work', 2, total: 2)],
          placement: ChatPlacement.append,
          from: 1,
          live: LiveDisplayWindow(
            revision: 2,
            historyThrough: 2,
            executionPresent: false,
            blocks: const [],
          ),
        ),
      ),
    );
    await component.entered.future;
    expect(h.owner.live.value, same(live));
    expect(intent.current, same(originalUnit));
    expect(h.failures, isEmpty);
    expect(h.failed.isCompleted, isFalse);
    expect(feed.acks, [1]);
    final failure = StateError('actual component Future failed');
    gate.completeError(failure);
    await h.failed.future;
    h.owner.setDemand(false);
    expect(h.failures.single, same(failure));
    expect(component.messages.single, same(original));
    expect(h.owner.live.value, same(live));
    expect(notifications, 0);
    expect(intent.current, same(originalUnit));
    expect(intent.expanded, isTrue);
    expect(feed.acks, [
      1,
    ], reason: 'The failed handoff never returns its credit');
    component.failure = null;
    await projection.applyTimeline(
      displayBatch(
        [displayWork('work', 2)],
        placement: ChatPlacement.append,
        from: 1,
      ),
    );
    expect(component.messages.map((message) => message.id), ['old', 'work']);
    observation.cancel();
    expect((await h.owner.close()).complete, isTrue);
    projection.dispose();
    component.dispose();
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
    final failureObservation = owner.state.watch((state) {
      final Object error;
      if (state is ChatReconnecting<bool>) {
        error = state.error;
      } else if (state is ChatFailed<bool>) {
        error = state.error;
      } else {
        return;
      }
      failures.add(error);
      if (!failed.isCompleted) failed.complete();
    });
    addTearDown(failureObservation.cancel);
  }
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

final class _FailingAppendComponent extends InMemoryChatController {
  Future<void>? failure;
  final entered = Completer<void>();
  @override
  Future<void> insertAllMessages(
    List<Message> messages, {
    int? index,
    bool animated = true,
  }) {
    if (failure case final pending?) {
      if (!entered.isCompleted) entered.complete();
      return pending;
    }
    return super.insertAllMessages(messages, index: index, animated: animated);
  }
}

final class _TimelineConsumer implements TimelineBatchConsumer {
  _TimelineConsumer(this.presentation);
  final TimelineMessageController presentation;
  @override
  Future<void> applyTimeline(
    TimelineBatch batch,
    LiveDisplayWindow acceptedLive,
  ) => presentation.applyTimeline(batch);
}

final class _Transport implements ConversationTransport, TimelineTransport {
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
  }) {
    scopes.add(scope);
    return _open(demand);
  }

  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) => _open(demand);

  Future<_Feed> _open(ReadDemand demand) async {
    expect(demand.maxItems, _demand.maxItems);
    final feed = _Feed('subscription:${feeds.length}');
    feeds.add(feed);
    if (!opened.isCompleted) opened.complete(feed);
    return feed;
  }
}

final class _Feed implements TimelineFeed {
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
  int timelineQueries = 0;
  int memberOpens = 0;
  @override
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    timelineQueries++;
    throw StateError('Unexpected Timeline page query');
  }

  @override
  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) {
    timelineQueries++;
    throw StateError('Unexpected live page query');
  }

  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) {
    memberOpens++;
    throw StateError('Unexpected member query');
  }

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
