import 'dart:async';

import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ClientScope root;
  late DriverDemoStudioTransport transport;

  setUp(() async {
    root = ClientScope(owner: 'demo-conversation-feed');
    transport = DriverDemoStudioTransport(
      contentScope: root.child('transport'),
    );
    await transport.readBootstrap();
    addTearDown(() async {
      final budget = ClientCloseBudget(const Duration(seconds: 5));
      await transport.cancelDartSubscriptions(budget: budget);
      final report = await root.close(budget: budget);
      expect(report.complete, isTrue);
    });
  });

  test(
    'initial events, older cursor and reset use the same Demo Feed',
    () async {
      final feed = await transport.openConversationFeed(
        'thread-main',
        initialLimit: 1,
      );
      final events = StreamIterator(feed.events);
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);
      final initial =
          (events.current as ConversationTimeline).patch as TimelineReset;
      expect(initial.items, hasLength(1));
      expect(initial.hasMoreOlder, isTrue);
      expect(await events.moveNext(), isTrue);
      expect(
        (events.current as ConversationLiveStatus).snapshot,
        feed.liveStatusSnapshot,
      );
      expect(await events.moveNext(), isTrue);
      expect(
        (events.current as ConversationSessionMeta).snapshot,
        feed.sessionMetaSnapshot,
      );
      expect(feed.sessionMetaSnapshot.threadId, 'thread-main');

      final older = await feed.loadOlder(
        cursor: initial.olderCursor!,
        limit: 2,
      ) as TimelinePrependOlder;
      expect(older.items, hasLength(2));
      expect(older.items.last.seq, lessThan(initial.items.first.seq));
      expect(older.olderCursor, isNot(initial.olderCursor));
      final reset = await feed.resetToLatest(limit: 1) as TimelineReset;
      expect(reset.items, initial.items);
      expect(reset.revision, greaterThan(initial.revision));
      expect(await events.moveNext(), isTrue);
      expect(events.current, ConversationTimeline(patch: reset));
      await feed.close();
    },
  );

  test(
    'an unlistened Feed joins and rejects reads while a peer stays usable',
    () async {
      final feed = await transport.openConversationFeed('thread-main');
      final peer = await transport.openConversationFeed('thread-main');
      feed.requestClose();
      await expectLater(feed.resetToLatest(), throwsA(isA<StudioFailure>()));
      await feed.close().timeout(const Duration(seconds: 1));
      final reset = await peer.resetToLatest(limit: 2) as TimelineReset;
      expect(reset.items, hasLength(2));
      expect(
        peer.sessionMetaSnapshot.ownerEpoch,
        feed.sessionMetaSnapshot.ownerEpoch,
      );
      await peer.close();
    },
  );
}
