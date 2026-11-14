import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/controlled_timeline_transport.dart';
import '../support/display_fixtures.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

const _demand = ReadDemand(maxItems: 20, maxBytes: 65536);
TailSnapshot _tail(
  int frontier, {
  int revision = 1,
  List<LiveDisplayBlock> blocks = const [],
  String? work,
}) => TailSnapshot(
  revision: revision,
  layoutRevision: revision,
  readyFrontier: frontier,
  executionPresent: false,
  currentWorkId: work,
  blocks: blocks,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'selection opens no reader until an actual viewport declares its demand',
    () async {
      final h = _Harness(viewport: false);
      await h.open();
      expect(h.transport.readers, isEmpty);
      h.owner.updateReadDemand(_demand);
      await timelineReady(h.owner, 'thread-main');
      expect(h.transport.readers, hasLength(1));
      expect(h.lease.controller.messages, isNotEmpty);
    },
  );

  test('only the component owns history; empty and status responses perform zero component operations', () async {
    final h = _Harness();
    await h.open();
    final lease = h.lease;
    final before = lease.olderCursor;
    final messages = [...lease.controller.messages];
    final operations = <ChatOperation>[];
    final subscription = lease.controller.operationsStream.listen(
      operations.add,
    );
    addTearDown(subscription.cancel);
    final frontier = h.readerThrough;
    final live = _tail(
      frontier,
      revision: 100,
      blocks: [
        LiveDisplayBlock(
          id: 'work',
          blockOrder: frontier + 1,
          state: DisplayBlockState.open,
          body: displayWork('work', frontier + 1).body,
        ),
      ],
      work: 'work',
    );
    await h.reader.send(
      displayBatch(
        [],
        placement: ChatPlacement.append,
        from: frontier,
        through: frontier,
        live: live,
      ),
    );
    for (var i = 101; i < 121; i++) {
      await h.reader.send(
        ViewUpdate(
          presentationVersion: 6,
          readerProtocolVersion: 1,
          after: const ViewCursor('declared'),
          next: const ViewCursor('peer'),
          history: HistoryDelta(
            placement: HistoryPlacement.append,
            fromOrder: frontier,
            throughOrder: frontier,
            blocks: [],
          ),
          tail: TailStatus(
            baseLayoutRevision: 100,
            revision: i,
            currentWorkId: 'work',
            thinkingSummary: '摘要 $i',
          ),
        ),
      );
    }
    expect(operations, isEmpty);
    expect(h.lease, same(lease));
    expect(lease.controller.messages, orderedEquals(messages));
    expect(lease.olderCursor, before);
    expect(lease.live.value!.layoutRevision, 100);
    expect(lease.live.value!.revision, 120);
    expect(lease.live.value!.blocks.single.thinkingSummary, '摘要 120');
    expect(h.reader.olderRequests, isEmpty);
    final order = frontier + 1;
    await h.reader.send(
      displayBatch(
        [displayWork('work', order)],
        placement: ChatPlacement.append,
        from: frontier,
        through: order,
        live: _tail(order, revision: 121),
      ),
    );
    expect(
      operations,
      hasLength(1),
      reason: 'a real history insertion is the positive control',
    );
    expect(lease.controller.messages.last.id, 'work');
    expect(lease.live.value!.blocks, isEmpty);
  });

  test(
    'Keep retires only actually received identities across a sparse frontier',
    () async {
      final h = _Harness();
      h.transport.initial = displayBatch(
        [],
        through: 0,
        live: _tail(
          0,
          blocks: [
            LiveDisplayBlock(
              id: 'first',
              blockOrder: 2,
              state: DisplayBlockState.sealed,
              body: displayWork('first', 2).body,
            ),
            LiveDisplayBlock(
              id: 'tail',
              blockOrder: 8,
              state: DisplayBlockState.open,
              body: displayWork('tail', 8).body,
            ),
          ],
          work: 'tail',
        ),
      );
      await h.open();
      await h.reader.send(
        displayBatch(
          [displayWork('first', 2)],
          placement: ChatPlacement.append,
          from: 0,
          through: 7,
        ),
      );
      expect(h.lease.live.value!.blocks.map((b) => b.id), ['tail']);
      expect(h.lease.live.value!.readyFrontier, 0);
      expect(h.lease.live.value!.layoutRevision, 1);
      expect(h.lease.live.value!.currentWorkId, 'tail');
      await h.reader.send(
        displayBatch(
          [],
          placement: ChatPlacement.append,
          from: 7,
          through: 7,
          live: _tail(
            7,
            revision: 2,
            blocks: [
              LiveDisplayBlock(
                id: 'tail',
                blockOrder: 8,
                state: DisplayBlockState.open,
                body: displayWork('tail', 8).body,
              ),
            ],
            work: 'tail',
          ),
        ),
      );
      expect(h.lease.controller.messages.map((m) => m.id), ['first']);
      expect(h.lease.live.value!.readyFrontier, 7);
    },
  );

  test(
    'older results are pure queries and apply once through the GUI queue',
    () async {
      final h = _Harness();
      h.transport.controlOlder = true;
      h.transport.initial = displayBatch(
        [displayWork('current', 10)],
        through: 10,
        before: 'older-10',
        live: _tail(10),
      );
      await h.open();
      final original = h.lease.controller.messages.single;
      final cursor = h.reader.cursors.last;
      final load = h.owner.loadOlder(
        'thread-main',
        generation: h.lease.generation,
      );
      final secondLoad = h.owner.loadOlder(
        'thread-main',
        generation: h.lease.generation,
      );
      final request = h.reader.olderRequests.single;
      expect(h.lease.controller.messages.single, same(original));
      request.reply.complete(
        TimelinePage(
          presentationVersion: 6,
          databaseId: 'db',
          ceiling: 10,
          blocks: [displayWork('older', 3)],
        ),
      );
      await Future.wait([load, secondLoad]);
      expect(h.lease.controller.messages.map((m) => m.id), [
        'older',
        'current',
      ]);
      expect(h.lease.controller.messages.last, same(original));
      expect(
        h.reader.cursors.last,
        cursor,
        reason: 'older pages never advance the main cursor',
      );
      expect(h.reader.olderRequests, hasLength(1));
    },
  );

  for (final lateFailure in [false, true]) {
    test(
      'old page ${lateFailure ? 'failure' : 'success'} cannot touch a replacement selection',
      () async {
        final h = _Harness();
        h.transport.controlOlder = true;
        h.transport.initial = displayBatch(
          [displayWork('current', 10)],
          through: 10,
          before: 'older-10',
          live: _tail(10),
        );
        await h.open();
        final old = h.lease;
        final load = h.owner.loadOlder(
          'thread-main',
          generation: old.generation,
        );
        final request = h.reader.olderRequests.single;
        await h.select('thread-alt');
        await h.select('thread-main');
        final replacement = h.lease;
        final state = h.owner.source.value;
        if (lateFailure) {
          request.reply.completeError(StateError('late old page'));
        } else {
          request.reply.complete(
            TimelinePage(
              presentationVersion: 6,
              databaseId: 'db',
              ceiling: 10,
              blocks: [displayWork('late', 2)],
            ),
          );
        }
        await load;
        expect(h.lease, same(replacement));
        expect(h.owner.source.value, same(state));
        expect(h.lease.controller.messages.any((m) => m.id == 'late'), isFalse);
        expect(old.isRetired, isTrue);
      },
    );
  }

  test(
    'refresh retains the accepted surface until a new Set applies',
    () async {
      final h = _Harness();
      await h.open();
      final old = h.lease;
      final gate = Completer<void>();
      h.transport.nextOpenGate = gate.future;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final opened = h.transport.opened.stream.first;
      h.owner.refresh('thread-main');
      await opened;
      expect(h.lease, same(old));
      expect(old.isRetired, isFalse);
      gate.complete();
      await timelineReady(h.owner, 'thread-main');
      expect(h.lease, isNot(same(old)));
      expect(old.isRetired, isTrue);
      expect(h.transport.readers.first.closed, isTrue);
    },
  );

  test(
    'a real component failure discards the reader and rebuilds from Set',
    () async {
      final h = _Harness();
      await h.open();
      final old = h.lease;
      final failing = h.reader;
      final duplicateId = old.controller.messages.first.id;
      final gate = Completer<void>();
      h.transport.nextOpenGate = gate.future;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final opened = h.transport.opened.stream.first;
      failing.emitTimeline(
        displayBatch(
          [displayWork(duplicateId, h.readerThrough + 1)],
          placement: ChatPlacement.append,
          from: h.readerThrough,
        ),
      );
      await opened;
      expect(
        failing.acceptedCursors,
        hasLength(1),
        reason: 'the failed Append cursor was never accepted',
      );
      expect(h.lease, same(old));
      gate.complete();
      await timelineReady(h.owner, 'thread-main');
      expect(h.lease, isNot(same(old)));
      expect(
        h.lease.controller.messages.map((m) => m.id).toSet().length,
        h.lease.loadedCount,
      );
      expect(failing.closed, isTrue);
    },
  );

  test('invalid protocol continuity fails visibly without reopening or touching accepted history', () async {
    final h = _Harness();
    await h.open();
    final old = h.lease;
    final messages = [...old.controller.messages];
    h.reader.emitTimeline(
      displayBatch(
        [displayWork('bad', h.readerThrough + 1)],
        placement: ChatPlacement.append,
        from: 0,
      ),
    );
    await h.owner.source.waitFor(
      (value) => value?.connection == TimelineConnectionPhase.failed,
    );
    expect(h.transport.readers, hasLength(1));
    expect(h.lease, same(old));
    expect(old.controller.messages, orderedEquals(messages));
    expect(h.reader.acceptedCursors, hasLength(1));
  });

  test('mounted generations keep resources until unbind and close reports the actual outstanding owner', () async {
    final h = _Harness();
    await h.open();
    final lease = h.lease..bind();
    final report = await h.owner.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse);
    expect(lease.isReleased, isFalse);
    expect(lease.isRetired, isTrue);
    await lease.unbind();
    expect(
      (await h.owner.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
    expect(lease.isReleased, isTrue);
  });
}

final class _Harness {
  _Harness({this.viewport = true}) {
    graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'cursor-owner-test',
    );
    addTearDown(() async {
      await transport.settleFixtures();
      final report = await graph.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(report.complete, isTrue, reason: '${report.unresolved}');
    });
  }
  final bool viewport;
  final transport = ControlledTimelineTransport();
  late final AppGraph graph;
  TimelineSessionOwner get owner => graph.timeline;
  TimelineDisplayLease get lease => owner.lease('thread-main')!;
  ControlledTimelineReader get reader => transport.readers.last;
  int get readerThrough => lease.live.value!.readyFrontier;
  Future<void> open() async {
    await graph.client.bootstrap();
    if (viewport) owner.updateReadDemand(_demand);
    graph.setConversationPageVisible(true);
    await graph.client.directoryCommands.selectThread('thread-main');
    if (viewport) {
      await timelineReady(owner, 'thread-main');
      await reader.accepted(1);
    }
  }

  Future<void> select(String thread) async {
    await graph.client.directoryCommands.selectThread(thread);
    await timelineReady(owner, thread);
    await reader.accepted(1);
  }
}
