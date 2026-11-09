import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 4096);
const _reference = DisplayBlockRef(databaseId: 'db', blockId: 'work');

DisplayBlockBody _body(String id) =>
    SingleDisplayBlock(atom: fixtureMember(id), completionId: id);
DisplayBlock _block(String id, int pos) =>
    DisplayBlock(id: id, historyPos: pos, body: _body(id));
LiveDisplayWindow _live(List<String> ids, {int pos = 0, int revision = 1}) =>
    LiveDisplayWindow(
      revision: revision,
      historyThrough: pos,
      executionPresent: true,
      blocks: [
        for (var i = 0; i < ids.length; i++)
          LiveDisplayBlock(
            id: ids[i],
            blockOrder: i + 1,
            body: _body(ids[i]),
            closing: true,
          ),
      ],
    );
TimelineBatch _set({
  List<String> live = const ['work', 'text'],
  int version = 1,
}) => TimelineBatch(
  presentationVersion: version,
  placement: ChatPlacement.set,
  blocks: [],
  throughPos: 0,
  live: _live(live),
);
TimelineBatch _append(String id, int pos, {LiveDisplayWindow? live}) =>
    TimelineBatch(
      presentationVersion: 1,
      placement: ChatPlacement.append,
      blocks: [_block(id, pos)],
      fromPos: pos - 1,
      throughPos: pos,
      live: live,
    );

void main() {
  test('a sealed member page is followed by explicit EOF, never a repeated page', () async {
    final h = _Harness();
    addTearDown(h.close);
    final feed = await h.open();
    await feed.deliver(ConversationTimelineEvent(batch: _set()));
    final native = _Members();
    feed.members = native;
    final scope = h.content.openScope(generation: 1);
    final members = await scope.openDisplayMembers(
      reference: _reference, window: const LatestDisplayMembers(), demand: _demand,
    );
    final first = members.next();
    native.pending.complete(DisplayMemberPage(
      block: _reference, revision: 2, sealed: true, entries: [],
    ));
    expect((await first)!.sealed, isTrue);
    native.pending = Completer<DisplayMemberPage?>();
    final eof = members.next();
    native.pending.complete(null);
    expect(await eof, isNull);
    expect(await members.next(), isNull);
    await members.close();
  });

  test('max_items=1 retires only delivered IDs and publishes/ACKs after acceptance', () async {
    final h = _Harness();
    addTearDown(h.close);
    final feed = await h.open();
    await feed.deliver(ConversationTimelineEvent(batch: _set()));
    expect(
      h.transport.opens,
      isEmpty,
      reason: 'GUI does not consume the atomic feed',
    );
    expect(h.transport.demands.single.maxItems, 1);
    final observed = <List<String>>[];
    final observation = h.content.live.watch(
      (window) =>
          observed.add(window!.blocks.map((block) => block.id).toList()),
    );
    addTearDown(observation.cancel);
    final gate = Completer<void>();
    h.consumer.onApply = (_, _) => gate.future;
    feed.send(ConversationTimelineEvent(batch: _append('work', 1)));
    await h.consumer.called(2);
    expect(h.consumer.values.last.$2.blocks.map((block) => block.id), ['text']);
    expect(h.content.live.value!.blocks.map((block) => block.id), [
      'work',
      'text',
    ]);
    expect(observed, isEmpty);
    expect(feed.acknowledgements, [1]);
    gate.complete();
    await feed.acknowledged(2);
    expect(observed, [
      ['text'],
    ]);
    h.consumer.onApply = null;
    await feed.deliver(
      ConversationTimelineEvent(
        batch: _append('text', 2, live: _live([], pos: 2, revision: 2)),
      ),
    );
    expect(observed, <List<String>>[
      ['text'],
      [],
    ]);
    expect(h.content.live.value!.historyThrough, 2);
  });

  test('pure live Append keeps P and Prepend shares the serial gate but not credit', () async {
    final h = _Harness();
    addTearDown(h.close);
    final feed = await h.open();
    await feed.deliver(ConversationTimelineEvent(batch: _set()));
    final gate = Completer<void>();
    h.consumer.onApply = (_, _) => gate.future;
    final updated = _live(['work'], revision: 2);
    feed.send(
      ConversationTimelineEvent(
        batch: TimelineBatch(
          presentationVersion: 1,
          placement: ChatPlacement.append,
          blocks: [],
          fromPos: 0,
          throughPos: 0,
          live: updated,
        ),
      ),
    );
    await h.consumer.called(2);
    final io = Completer<void>();
    feed.onOlder = (_, _) async {
      io.complete();
      return TimelineBatch(
        presentationVersion: 1,
        placement: ChatPlacement.prepend,
        blocks: [],
        throughPos: 0,
      );
    };
    final scope = h.content.openScope(generation: 1);
    final page = scope.loadTimelineOlder(before: 'older', demand: _demand);
    await io.future;
    expect(
      h.consumer.values.length,
      2,
      reason: 'query IO is not blocked by apply/credit',
    );
    gate.complete();
    await page;
    await feed.acknowledged(2);
    expect(h.consumer.values.length, 3);
    expect(h.consumer.values.last.$2, same(updated));
    expect(feed.acknowledgements, [1, 2], reason: 'query Prepend does not ACK');
  });

  test(
    'wrong presentation version is rejected before delivery and ACK',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final feed = await h.open();
      feed.send(ConversationTimelineEvent(batch: _set(version: 2)));
      await feed.requestCloseStarted.future;
      expect(h.consumer.values, isEmpty);
      expect(feed.acknowledgements, isEmpty);
      expect(h.content.state.value, isA<ChatFailed<bool>>());
    },
  );

  test(
    'Timeline feed rejects atomic Chat and Activity rather than combining them',
    () async {
      for (final event in <ConversationEvent>[
        ConversationChatEvent(batch: chatSet()),
        ConversationActivityEvent(
          snapshot: ActivitySnapshot(
            revision: 1,
            completedThrough: 0,
            executionPresent: true,
            entries: [],
          ),
        ),
      ]) {
        final h = _Harness();
        final feed = await h.open();
        feed.send(event);
        await feed.requestCloseStarted.future;
        expect(feed.acknowledgements, isEmpty);
        expect(h.consumer.values, isEmpty);
        await h.close();
      }
    },
  );

  test('A-B-A old successful acceptance cannot publish or ACK into new qualification', () async {
    final h = _Harness();
    addTearDown(h.close);
    final old = await h.open();
    await old.deliver(ConversationTimelineEvent(batch: _set()));
    final gate = Completer<void>();
    h.consumer.onApply = (_, _) => gate.future;
    old.send(ConversationTimelineEvent(batch: _append('work', 1)));
    await h.consumer.called(2);
    h.fixture.repository.setVisibleThread(null);
    h.consumer.onApply = null;
    h.fixture.repository.setVisibleThread('thread');
    final current = await h.finishOpen(1);
    await current.deliver(
      ConversationTimelineEvent(batch: _set(live: ['new'])),
    );
    gate.complete();
    await old.closeCompleted.future;
    expect(h.content.live.value!.blocks.single.id, 'new');
    expect(old.acknowledgements, [1]);
    expect(current.acknowledgements, [1]);
  });

  test(
    'late query error after close is stale and does not change new admission',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final old = await h.open();
      await old.deliver(ConversationTimelineEvent(batch: _set()));
      final scope = h.content.openScope(generation: 1);
      final response = Completer<LiveDisplayWindow>();
      old.onLiveOlder = (_, _) => response.future;
      final pending = scope.loadLiveOlder(
        before: 'live-older',
        demand: _demand,
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<StaleConversationScope>()),
      );
      h.fixture.repository.setVisibleThread(null);
      h.fixture.repository.setVisibleThread('thread');
      final current = await h.finishOpen(1);
      await current.deliver(
        ConversationTimelineEvent(batch: _set(live: ['new'])),
      );
      response.completeError(StateError('old IO failed'));
      await assertion;
      expect(h.content.live.value!.blocks.single.id, 'new');
      expect(h.content.state.value, isA<ChatReady<bool>>());
    },
  );

  test('member window is bounded, single-flight, and close wakes and joins its exact handle', () async {
    final h = _Harness();
    addTearDown(h.close);
    final feed = await h.open();
    await feed.deliver(ConversationTimelineEvent(batch: _set()));
    final native = _Members();
    feed.members = native;
    final scope = h.content.openScope(generation: 1);
    final members = await scope.openDisplayMembers(
      reference: _reference,
      window: const LatestDisplayMembers(),
      demand: _demand,
    );
    final initial = members.next();
    native.pending.complete(
      DisplayMemberPage(
        block: _reference,
        revision: 1,
        sealed: false,
        entries: [
          DisplayMemberHead(
            memberKey: 'member',
            memberOrder: 10,
            atom: fixtureMember('member'),
          ),
        ],
        before: 10,
      ),
    );
    final page = await initial;
    expect(page!.entries.single.memberOrder, 10);
    native.pending = Completer<DisplayMemberPage?>();
    final next = members.next();
    final stale = expectLater(next, throwsA(isA<StaleConversationScope>()));
    await expectLater(members.next(), throwsStateError);
    native.closeFailure = StateError('join failed');
    scope.retire();
    expect(native.requested, isTrue);
    await stale;
    final report = await scope.close();
    expect(report.complete, isFalse);
    native.closeFailure = null;
    expect((await scope.close()).complete, isTrue);
    expect(native.closeCalls, 2);
  });

  test('late member open is closed under its original retired scope', () async {
    final h = _Harness();
    addTearDown(h.close);
    final feed = await h.open();
    await feed.deliver(ConversationTimelineEvent(batch: _set()));
    final response = Completer<DisplayMembers>();
    feed.membersOpening = response;
    final scope = h.content.openScope(generation: 1);
    final opening = scope.openDisplayMembers(
      reference: _reference,
      window: const LatestDisplayMembers(),
      demand: _demand,
    );
    final stale = expectLater(opening, throwsA(isA<StaleConversationScope>()));
    scope.retire();
    final native = _Members();
    response.complete(native);
    await stale;
    expect(native.requested, isTrue);
    expect(native.closeCalls, 1);
    expect((await scope.close()).complete, isTrue);
  });
}

final class _Harness {
  _Harness() {
    fixture = ConversationFixture(transport: transport);
    content = fixture.session().content as TimelineContent;
    content.attachTimelineConsumer(consumer, demand: _demand);
  }
  final _Transport transport = _Transport();
  final _Consumer consumer = _Consumer();
  late final ConversationFixture fixture;
  late final TimelineContent content;
  Future<_Feed> open() async {
    fixture.repository.setVisibleThread('thread');
    return finishOpen(0);
  }

  Future<_Feed> finishOpen(int index) async {
    await transport.openedTimeline(index);
    final feed = _Feed(subscriptionId: 'timeline-$index');
    transport.timelineOpens[index].complete(feed);
    return feed;
  }

  Future<void> close() async =>
      expect((await fixture.close()).complete, isTrue);
}

final class _Transport extends TestConversationTransport
    implements TimelineTransport {
  final List<Completer<TimelineFeed>> timelineOpens = [];
  final List<ReadDemand> demands = [];
  final Map<int, Completer<void>> _opening = {};
  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) {
    demands.add(demand);
    final result = Completer<TimelineFeed>();
    timelineOpens.add(result);
    _opening.remove(timelineOpens.length - 1)?.complete();
    return result.future;
  }

  Future<void> openedTimeline(int index) => timelineOpens.length > index
      ? Future.value()
      : (_opening[index] ??= Completer<void>()).future;
}

final class _Feed extends TestConversationFeed implements TimelineFeed {
  _Feed({required super.subscriptionId});
  Future<TimelineBatch> Function(String, ReadDemand)? onOlder;
  Future<LiveDisplayWindow> Function(String, ReadDemand)? onLiveOlder;
  DisplayMembers? members;
  Completer<DisplayMembers>? membersOpening;
  @override
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => onOlder!(before, demand);
  @override
  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) => onLiveOlder!(before, demand);
  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) async => membersOpening == null ? members! : await membersOpening!.future;
}

final class _Consumer implements TimelineBatchConsumer {
  final List<(TimelineBatch, LiveDisplayWindow)> values = [];
  final Map<int, Completer<void>> _called = {};
  Future<void> Function(TimelineBatch, LiveDisplayWindow)? onApply;
  @override
  Future<void> applyTimeline(
    TimelineBatch batch,
    LiveDisplayWindow live,
  ) async {
    values.add((batch, live));
    _called.remove(values.length)?.complete();
    await onApply?.call(batch, live);
  }

  Future<void> called(int count) => values.length >= count
      ? Future.value()
      : (_called[count] ??= Completer<void>()).future;
}

final class _Members implements DisplayMembers {
  Completer<DisplayMemberPage?> pending = Completer();
  bool listening = false;
  bool requested = false;
  int closeCalls = 0;
  Object? closeFailure;
  @override
  Future<DisplayMemberPage?> next() {
    listening = true;
    return pending.future;
  }

  @override
  void requestClose() {
    requested = true;
    if (listening && !pending.isCompleted)
      pending.completeError(const StaleConversationScope());
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (closeFailure case final failure?) throw failure;
  }
}
