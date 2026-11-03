import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/controlled_batch_consumer.dart';
import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 10, maxBytes: 16384);

CurrentProjection _active(int source) => CurrentProjection(
  sourceEffectSeq: source,
  logicalStatus: ThreadStatusView.running,
  executionPresent: true,
  sources: const [],
  items: [
    TimelineItem(
      id: 'active-work',
      kind: TimelineItemKind.workGroup,
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      delivery: ChatDeliveryKind.foreground,
      summary: TimelineGroupSummary(
        memberCount: 1,
        activeCount: 1,
        failedCount: 0,
        cancelledCount: 0,
        categories: const [
          TimelineCategoryCount(category: TimelineCategory.thinking, count: 1),
        ],
      ),
      members: const TimelineMembersRef(
        databaseId: 'database', projectionVersion: 1, itemId: 'active-work',
      ),
      contents: const [],
      admissionClosed: false,
    ),
  ],
  atoms: const [],
  active: const CurrentActivityHead(
    id: 'activity',
    kind: ThreadActivityKind.thinking,
    summary: 'working',
    toolCount: 1,
    backgroundToolCount: 0,
  ),
  previews: [],
  collections: [],
);

void main() {
  test(
    'Main current commits only after the same batch has been applied',
    () async {
      final fixture = ConversationFixture();
      final content = fixture.session().content;
      final consumer = ControlledBatchConsumer();
      content.attachConsumer(consumer, demand: _demand);
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(0);
      final feed = TestConversationFeed();
      fixture.transport.opens[0].result.complete(feed);
      final active = _active(1);
      await feed.deliver(
        ConversationChatEvent(batch: chatSet(current: active)),
      );
      final gate = Completer<void>();
      consumer.onApply = (_) => gate.future;
      final retired = emptyCurrent();
      final completion = ChatBatch(
        placement: ChatPlacement.append,
        entries: [ItemChatEntry(chatMessage(id: 'completed-member'))],
        current: retired,
      );
      feed.send(ConversationChatEvent(batch: completion));
      await consumer.waitForCount(2);
      expect(content.current.value, same(active));
      expect(fixture.session().current.value, same(active));
      expect(feed.acknowledgements, [1]);
      gate.complete();
      await feed.acknowledged(2);
      expect(consumer.batches.last, same(completion));
      expect(content.current.value, same(retired));
      expect(fixture.session().current.value, same(retired));
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('absent current preserves committed value, concrete empty current clears it', () async {
    final fixture = ConversationFixture();
    final active = _active(1);
    final feed = await fixture.open(
      initial: chatSet(current: active, before: 'opaque-before'),
      demand: _demand,
    );
    await feed.deliver(
      ConversationChatEvent(
        batch: ChatBatch(
          placement: ChatPlacement.append,
          entries: [ItemChatEntry(chatMessage(id: 'completed'))],
        ),
      ),
    );
    expect(fixture.session().current.value, same(active));
    final empty = emptyCurrent();
    await feed.deliver(
      ConversationChatEvent(
        batch: ChatBatch(
          placement: ChatPlacement.append,
          entries: [],
          current: empty,
        ),
      ),
    );
    expect(fixture.session().current.value, same(empty));
    final batches = fixture.consumers['thread']!.batches;
    expect(batches.map((batch) => batch.before), ['opaque-before', null, null]);
    expect(batches.last.entries, isEmpty);
    expect((await fixture.close()).complete, isTrue);
  });

  test(
    'current reentry detaching consumer cannot ACK into the replaced lease',
    () async {
      final fixture = ConversationFixture();
      final content = fixture.session().content;
      final consumer = ControlledBatchConsumer();
      final lease = content.attachConsumer(consumer, demand: _demand);
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(0);
      final feed = TestConversationFeed();
      fixture.transport.opens[0].result.complete(feed);
      final observation = content.current.watch((current) {
        if (current != null) lease.cancel();
      });
      feed.send(ConversationChatEvent(batch: chatSet(current: _active(1))));
      await feed.requestCloseStarted.future;
      expect(feed.acknowledgements, isEmpty);
      expect(content.state.value, isNot(isA<ChatReady<bool>>()));
      observation.cancel();
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test(
    'Children has independent scope/demand and never overwrites Main current',
    () async {
      final fixture = ConversationFixture();
      final mainCurrent = _active(1);
      final main = await fixture.open(
        initial: chatSet(current: mainCurrent),
        demand: _demand,
      );
      final children = await fixture.repository.openChildren(
        threadId: 'thread',
        parentId: 'real-turn-parent',
        demand: _demand,
      );
      expect(
        fixture.transport.opens,
        hasLength(1),
        reason: 'No component has attached yet',
      );
      final consumer = ControlledBatchConsumer();
      children.attachConsumer(consumer, demand: _demand);
      await fixture.transport.opened(1);
      final open = fixture.transport.opens[1];
      expect(open.threadId, 'thread');
      expect(
        open.scope,
        isA<ChildrenChatScope>().having(
          (scope) => scope.parentId,
          'parentId',
          'real-turn-parent',
        ),
      );
      expect(open.demand, same(_demand));
      final child = TestConversationFeed(subscriptionId: 'children');
      open.result.complete(child);
      final set = ChatBatch(
        placement: ChatPlacement.set,
        entries: [ChatAtomEntry(fixtureMember('tool'))],
      );
      await child.deliver(ConversationChatEvent(batch: set));
      await children.ready;
      expect(consumer.batches, [set]);
      expect(children.current.value, isNull);
      expect(fixture.session().current.value, same(mainCurrent));
      expect((await children.close()).complete, isTrue);
      expect(main.requestCloseCalls, 0);
      expect(fixture.session().current.value, same(mainCurrent));
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test(
    'GroupMembers forwards typed identity and owns a separate consumer and cursor',
    () async {
      final fixture = ConversationFixture();
      final mainCurrent = _active(1);
      final main = await fixture.open(
        initial: chatSet(current: mainCurrent, before: 'main-cursor'),
        demand: _demand,
      );
      const reference = TimelineMembersRef(
        databaseId: 'database',
        projectionVersion: 7,
        itemId: 'stable-group',
      );
      final members = await fixture.repository.openGroupMembers(
        threadId: 'thread',
        reference: reference,
        demand: _demand,
      );
      expect(fixture.transport.opens, hasLength(1));
      final consumer = ControlledBatchConsumer();
      members.attachConsumer(consumer, demand: _demand);
      await fixture.transport.opened(1);
      final open = fixture.transport.opens[1];
      expect((open.scope as GroupMembersChatScope).reference, same(reference));
      final feed = TestConversationFeed(subscriptionId: 'members');
      open.result.complete(feed);
      final set = ChatBatch(
        placement: ChatPlacement.set,
        entries: [ChatAtomEntry(fixtureMember('real-member'))],
        before: 'member-cursor',
      );
      final gate = Completer<void>();
      consumer.onApply = (_) => gate.future;
      feed.send(ConversationChatEvent(batch: set));
      await consumer.waitForCount(1);
      expect(feed.acknowledgements, isEmpty);
      gate.complete();
      await feed.acknowledged(1);
      expect(consumer.batches.single.atoms.single.id, 'real-member');
      expect(consumer.batches.single.items, isEmpty);
      expect(fixture.session().current.value, same(mainCurrent));
      expect(fixture.consumers['thread']!.batches.single.before, 'main-cursor');
      expect((await members.close()).complete, isTrue);
      expect(main.requestCloseCalls, 0);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test(
    'refresh retains committed current until replacement Set is accepted',
    () async {
      final fixture = ConversationFixture();
      final content = fixture.session().content;
      final consumer = ControlledBatchConsumer();
      content.attachConsumer(consumer, demand: _demand);
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(0);
      final first = TestConversationFeed();
      fixture.transport.opens[0].result.complete(first);
      final active = _active(10);
      await first.deliver(
        ConversationChatEvent(batch: chatSet(current: active)),
      );
      content.refresh();
      await fixture.transport.opened(1);
      final replacement = TestConversationFeed(subscriptionId: 'new');
      fixture.transport.opens[1].result.complete(replacement);
      final gate = Completer<void>();
      consumer.onApply = (_) => gate.future;
      final empty = emptyCurrent();
      replacement.send(
        ConversationChatEvent(
          batch: chatSet(messages: [], current: empty),
        ),
      );
      await consumer.waitForCount(2);
      expect(content.current.value, same(active));
      expect(replacement.acknowledgements, isEmpty);
      gate.complete();
      await replacement.acknowledged(1);
      expect(content.current.value, same(empty));
      expect((await fixture.close()).complete, isTrue);
    },
  );
}
