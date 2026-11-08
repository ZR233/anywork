import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/controlled_batch_consumer.dart';
import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 16384);

void main() {
  for (final run in [false, true]) {
    test(
      '${run ? 'Run' : 'Children'} has independent demand, cursor and ownership',
      () async {
        final fixture = ConversationFixture();
        final main = await fixture.open(
          demand: _demand,
          initial: chatSet(before: 'main-cursor'),
        );
        final activity = ActivitySnapshot(
          revision: 1,
          completedThrough: 1,
          executionPresent: true,
          entries: [],
        );
        await main.deliver(ConversationActivityEvent(snapshot: activity));
        const reference = CompletionRunRef(
          databaseId: 'db',
          indexVersion: 1,
          startSeq: 1,
        );
        final detail = run
            ? await fixture.repository.openRun(
                threadId: 'thread',
                reference: reference,
                demand: _demand,
              )
            : await fixture.repository.openChildren(
                threadId: 'thread',
                parentId: 'parent',
                demand: _demand,
              );
        final consumer = ControlledBatchConsumer();
        detail.attachConsumer(consumer, demand: _demand);
        await fixture.transport.opened(1);
        final opening = fixture.transport.opens[1];
        expect(opening.demand, same(_demand));
        if (run) {
          expect((opening.scope as RunChatScope).reference, same(reference));
        } else {
          expect((opening.scope as ChildrenChatScope).parentId, 'parent');
        }
        final feed = TestConversationFeed(subscriptionId: 'detail');
        opening.result.complete(feed);
        final entry = completedFixture('real-member');
        await feed.deliver(
          ConversationChatEvent(
            batch: ChatBatch(
              placement: ChatPlacement.set,
              entries: [entry],
              before: 'detail-cursor',
              throughSeq: 1,
            ),
          ),
        );
        expect(consumer.batches.single.entries.single, same(entry));
        expect(detail.activity.value, isNull);
        final acceptance = Completer<void>();
        final entered = Completer<void>();
        consumer.onActivity = (_) {
          entered.complete();
          return acceptance.future;
        };
        final local = ActivitySnapshot(
          revision: 1,
          completedThrough: 1,
          executionPresent: true,
          entries: [],
        );
        feed.send(ConversationActivityEvent(snapshot: local));
        await entered.future;
        expect(feed.acknowledgements, [1]);
        expect(detail.activity.value, isNull);
        expect(fixture.session().activity.value, same(activity));
        acceptance.complete();
        await feed.acknowledged(2);
        expect(detail.activity.value, same(local));
        await feed.deliver(
          ConversationChatEvent(
            batch: ChatBatch(
              placement: ChatPlacement.append,
              entries: [],
              fromSeq: 1,
              throughSeq: 4,
            ),
          ),
        );
        consumer.onActivity = null;
        final advanced = ActivitySnapshot(
          revision: 2,
          completedThrough: 4,
          executionPresent: false,
          entries: [],
        );
        await feed.deliver(ConversationActivityEvent(snapshot: advanced));
        expect(detail.activity.value, same(advanced));
        expect(consumer.batches, hasLength(1));
        expect(feed.acknowledgements, [1, 2, 3, 4]);
        expect(fixture.session().activity.value, same(activity));
        expect(
          fixture.consumers['thread']!.batches.single.before,
          'main-cursor',
        );
        expect((await detail.close()).complete, isTrue);
        expect(main.requestCloseCalls, 0);
        expect((await fixture.close()).complete, isTrue);
      },
    );
  }

  test(
    'activity observation reentry cannot ACK after detaching its lease',
    () async {
      final fixture = ConversationFixture();
      final consumer = ControlledBatchConsumer();
      final content = fixture.session().content;
      final lease = content.attachConsumer(consumer, demand: _demand);
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(0);
      final feed = TestConversationFeed();
      fixture.transport.opens.single.result.complete(feed);
      await feed.deliver(ConversationChatEvent(batch: chatSet()));
      final observation = content.activity.watch((snapshot) {
        if (snapshot != null) lease.cancel();
      });
      feed.send(
        ConversationActivityEvent(
          snapshot: ActivitySnapshot(
            revision: 1,
            completedThrough: 1,
            executionPresent: true,
            entries: [],
          ),
        ),
      );
      await feed.requestCloseStarted.future;
      expect(feed.acknowledgements, [1]);
      observation.cancel();
      expect((await fixture.close()).complete, isTrue);
    },
  );
}
