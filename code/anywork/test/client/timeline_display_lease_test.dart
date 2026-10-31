import 'dart:async';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/conversation_fixtures.dart';
import 'support/mapped_conversation_feed.dart';

// SDK owns feed/reader lifetimes; the owner commits completed atoms to the real
// Flyer controller. The transport below only supplies authoritative facts and
// explicit I/O barriers. Atomic grouping itself is covered by the controller tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'baseline owns one loaded collection and an independent completion cursor',
    () async {
      final h = _Harness([_text('a', 3), _text('b', 4)], hasOlder: true);
      await h.open();
      final lease = h.lease;
      expect(lease.items.map((item) => item.id), ['a', 'b']);
      expect(
        lease.controller.messages.map(
          (message) => timelineEntryOf(message)!.first.id,
        ),
        ['a', 'b'],
      );
      expect(lease.completedCursor?.timelineEpoch, 'epoch');
      expect(lease.completedCursor?.appendSeq, 4);
      expect(lease.olderCursor, 'before');
      expect(lease.hasOlder, isTrue);
      expect(lease.loadedCount, 2);
      expect(lease.controller, isA<InMemoryChatController>());
      expect(lease.controller.messages.first.createdAt, isNull);
      expect(h.transport.opens, 1);
    },
  );

  test(
    'overlapping older page preserves loaded identities and completion cursor',
    () async {
      final c = _text('c', 3);
      final h = _Harness([c], hasOlder: true);
      await h.open();
      final lease = h.lease;
      final message = lease.controller.messages.single;
      final cursor = lease.completedCursor;
      final loading = h.owner.loadOlder('thread', generation: lease.generation);
      final reader = await h.transport.readerOpened.future;
      await reader.entered.future;
      reader.reply.complete(_page([_text('a', 1), _text('b', 2), c]));
      await loading;
      expect(lease.items.map((item) => item.id), ['a', 'b', 'c']);
      expect(lease.controller.messages.last, same(message));
      expect(lease.completedCursor, same(cursor));
      expect(lease.hasOlder, isFalse);
      expect(reader.boundaries, [const ConversationQueryCursor('before')]);
      expect(
        h.transport.opens,
        1,
        reason: 'history reads never reopen the feed',
      );
    },
  );

  test('reading accepts completed batches without replacing the display or consumer', () async {
    final h = _Harness([_text('a', 1)]);
    await h.open();
    final lease = h.lease;
    final first = lease.controller.messages.single;
    await h.owner.dispatch('thread', const TimelineEnterHistory());
    await h.append([_text('b', 2)]);
    expect(h.lease, same(lease));
    expect(lease.controller.messages.first, same(first));
    expect(lease.loadedCount, 2);
    expect(lease.completedCursor?.appendSeq, 2);
    expect(h.owner.source.value?.hasNewOutput, isTrue);
    await h.owner.returnToLive('thread');
    expect(h.lease, same(lease));
    expect(h.owner.source.value?.hasNewOutput, isFalse);
    expect(h.transport.opens, 1);
  });

  test('mounted lease retains real controller ownership until unbind and close retry', () async {
    final h = _Harness([_text('a', 1)]);
    await h.open();
    final lease = h.lease;
    lease.bind();
    h.client.conversations.setVisibleThread(null);
    final closing = h.owner.close(deadline: DateTime.utc(2000));
    expect(h.owner.close(), same(closing));
    final report = await closing;
    expect(report.complete, isFalse);
    expect(lease.isRetired, isTrue);
    expect(lease.isReleased, isFalse);
    expect(h.owner.lease('thread'), isNull);
    await lease.unbind();
    expect(lease.isReleased, isTrue);
    expect((await h.owner.close()).complete, isTrue);
  });

  test('reader close failure retains query and lease responsibility for actual retry', () async {
    final h = _Harness([_text('c', 3)], hasOlder: true);
    await h.open();
    final lease = h.lease;
    final loading = h.owner.loadOlder('thread', generation: lease.generation);
    final reader = await h.transport.readerOpened.future;
    await reader.entered.future;
    reader.reply.complete(_page([_text('b', 2)]));
    await loading;
    final scope = lease.queries!;
    reader.failClose = true;
    h.client.conversations.setVisibleThread(null);
    final report = await h.owner.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse);
    expect(lease.isReleased, isFalse);
    await expectLater(lease.closeDetailQueries(scope), throwsStateError);
    expect(lease.queryCleanupError, isNotNull);
    expect(reader.closeCalls, greaterThanOrEqualTo(1));
    reader.failClose = false;
    expect((await h.owner.close()).complete, isTrue);
    expect(lease.isReleased, isTrue);
    expect(reader.closeCalls, greaterThanOrEqualTo(2));
    expect(h.transport.opens, 1);
  });

  test(
    'retirement fences new queries and waits for the accepted independent page',
    () async {
      final h = _Harness([_text('c', 3)], hasOlder: true);
      await h.open();
      final lease = h.lease;
      final loading = h.owner.loadOlder('thread', generation: lease.generation);
      final reader = await h.transport.readerOpened.future;
      await reader.entered.future;
      h.client.conversations.setVisibleThread(null);
      final report = await h.owner.close(deadline: DateTime.utc(2000));
      expect(report.complete, isFalse);
      expect(lease.queries, isNull);
      expect(lease.openDetailQueries(), isNull);
      expect(lease.isReleased, isFalse);
      reader.reply.complete(_page([_text('late', 1)]));
      await loading;
      expect(lease.itemOf('late'), isNull);
      expect((await h.owner.close()).complete, isTrue);
      expect(lease.isReleased, isTrue);
      expect(reader.boundaries, hasLength(1));
    },
  );

  test('epoch reset changes chat identity and releases a borrowed image only after unbind', () async {
    const image = ThreadAttachmentView(
      id: 'image',
      modality: AttachmentModalityView.image,
      mediaType: 'image/png',
      byteSize: 8,
    );
    final atom = conversationFixture(
      id: 'image-atom',
      threadId: 'thread',
      appendSeq: 1,
      descriptor: ConversationTextDescriptor(
        channel: ThreadTextChannel.user,
        attachments: const [image],
        outcome: _completed(),
      ),
    );
    final h = _Harness([atom]);
    await h.open();
    final old = h.lease;
    old.bind();
    final resource = old.imageResources.borrow('image');
    final oldKey = old.chatKey;
    h.transport.feed.emit(
      ConversationReset(_baseline([_text('reset', 7)], epoch: 'next')),
    );
    await h.transport.feed.accepted(2);
    final next = h.lease;
    expect(next.timelineEpoch, 'next');
    expect(next.chatKey, isNot(oldKey));
    expect(next.scrollController.keepScrollOffset, isFalse);
    expect(old.isRetired, isTrue);
    expect(old.isReleased, isFalse);
    expect(
      () => resource.retry(
        () async => throw StateError('must not read after retirement'),
      ),
      throwsStateError,
    );
    expect(next.completedCursor?.appendSeq, 7);
    expect(next.itemOf('image-atom'), isNull);
    await old.unbind();
    await old.released;
    expect(old.isReleased, isTrue);
    expect(h.transport.opens, 1);
  });

  test('completed activity append updates only its boundary and keeps expansion and body references', () async {
    final body = _text('body', 1);
    final thinking = conversationFixture(
      id: 'thinking',
      threadId: 'thread',
      appendSeq: 2,
      descriptor: ConversationThinkingDescriptor(outcome: _completed()),
    );
    final h = _Harness([body, thinking]);
    await h.open();
    final lease = h.lease;
    final untouched = lease.controller.messages.first;
    final group = lease.presentationFor('thinking')!;
    final member = lease.memberObservation('thinking');
    group.toggle();
    var memberChanges = 0;
    member!.addListener(() => memberChanges++);
    await h.append([
      conversationFixture(
        id: 'tool',
        threadId: 'thread',
        appendSeq: 3,
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'call',
            name: 'exec',
          ),
          state: ConversationToolSucceeded(
            completedAt: DateTime.utc(2026),
            output: ConversationToolOutputDescriptor(attachments: const []),
          ),
        ),
      ),
    ]);
    expect(lease.controller.messages, hasLength(2));
    expect(lease.controller.messages.first, same(untouched));
    expect(lease.presentationFor('tool'), same(group));
    expect(group.anchorItemId, 'thinking');
    expect(group.memberIds, ['thinking', 'tool']);
    expect(group.expanded, isTrue);
    expect(lease.memberObservation('thinking'), same(member));
    expect(memberChanges, 0);
    expect(lease.completedCursor?.appendSeq, 3);
  });

  test(
    'completed failures count while cancellation and interruption add no issue',
    () async {
      final stopped = conversationFixture(
        id: 'thinking',
        threadId: 'thread',
        appendSeq: 1,
        descriptor: ConversationThinkingDescriptor(
          outcome: ConversationContentCancelled(
            CancelledThreadContentView(DateTime.utc(2026), 'Interrupted'),
          ),
        ),
      );
      ConversationItem tool(String id, int seq, ConversationToolState state) =>
          conversationFixture(
            id: id,
            threadId: 'thread',
            appendSeq: seq,
            descriptor: ConversationToolDescriptor(
              invocation: ConversationToolInvocation(
                toolCallId: id,
                name: 'exec',
              ),
              state: state,
            ),
          );
      final h = _Harness([
        stopped,
        tool(
          'broken',
          2,
          ConversationToolFailed(
            failedAt: DateTime.utc(2026),
            failure: const ThreadToolFailureView(
              kind: ThreadToolFailureKindView.execution,
              message: 'exit code 1',
            ),
          ),
        ),
        tool(
          'interrupted',
          3,
          ConversationToolInterrupted(
            interruptedAt: DateTime.utc(2026),
            reason: 'Interrupted',
          ),
        ),
      ]);
      await h.open();
      final group = h.lease.presentationFor('thinking')!;
      expect(group.memberIds, ['thinking', 'broken', 'interrupted']);
      expect(group.issueCount, 1);
      await h.append([
        conversationFixture(
          id: 'turn-end',
          threadId: 'thread',
          appendSeq: 4,
          descriptor: const ConversationTurnDescriptor(
            outcome: ConversationTurnCancelled(
              CancelledStudioTurnState(
                startedAt: 1,
                requestedAt: 2,
                completedAt: 3,
                cause: InterruptedTurnCancellation(),
              ),
            ),
          ),
          fields: {},
        ),
      ]);
      final turn = h.lease.presentationFor('turn-end')!;
      expect(turn.kind, isNot(TimelineEntryKind.hidden));
      expect(turn.issueCount, 0);
      expect(turn.elapsedDuration, const Duration(seconds: 2));
      expect(h.lease.controller.messages, hasLength(2));
    },
  );

  test('activity without canonical start keeps unknown duration despite seal and sequence', () async {
    final h = _Harness([
      conversationFixture(
        id: 'thinking',
        threadId: 'thread',
        appendSeq: 30,
        sealedAt: 1767225600,
        descriptor: ConversationThinkingDescriptor(outcome: _completed()),
      ),
      conversationFixture(
        id: 'tool',
        threadId: 'thread',
        appendSeq: 31,
        sealedAt: 1767225608,
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'tool',
            name: 'stat_path',
          ),
          state: ConversationToolSucceeded(
            completedAt: DateTime.utc(2026, 1, 1, 0, 0, 8),
            output: ConversationToolOutputDescriptor(attachments: const []),
          ),
        ),
      ),
    ]);
    await h.open();
    final group = h.lease.presentationFor('thinking')!;
    expect(group.memberIds, ['thinking', 'tool']);
    expect(group.elapsedDuration, isNull);
  });
}

ConversationContentCompleted _completed() => ConversationContentCompleted(
  CompletedThreadContentView(DateTime.utc(2026)),
);
ConversationItem _text(String id, int seq) => conversationFixture(
  id: id,
  threadId: 'thread',
  appendSeq: seq,
  fields: {const ThreadTextFieldView(): 'body-$id'},
);
ConversationPage _page(List<ConversationItem> items) => ConversationPage(
  threadId: 'thread',
  timelineEpoch: 'epoch',
  items: items,
  before: null,
  hasOlder: false,
);
ConversationBaseline _baseline(
  List<ConversationItem> items, {
  String epoch = 'epoch',
  bool hasOlder = false,
}) => ConversationBaseline(
  subscriptionId: 'lease',
  timelineEpoch: epoch,
  items: items,
  before: hasOlder ? const ConversationQueryCursor('before') : null,
  hasOlder: hasOlder,
  completedCursor: ConversationCompletionCursor(
    timelineEpoch: epoch,
    appendSeq: items.last.header.appendSeq,
  ),
);

final class _Harness {
  _Harness(List<ConversationItem> items, {bool hasOlder = false})
    : transport = _LeaseTransport(_baseline(items, hasOlder: hasOlder)) {
    client = AnyworkClient(transport: transport, clientId: 'lease');
    owner = TimelineSessionOwner(client: client);
    addTearDown(() async {
      final reader = transport.reader;
      if (reader != null) {
        reader.failClose = false;
        if (!reader.reply.isCompleted) reader.reply.complete(_page([]));
      }
      client.conversations.setVisibleThread(null);
      final current = owner.lease('thread');
      if (current?.isMounted ?? false) unawaited(current!.unbind());
      expect((await owner.close()).complete, isTrue);
      expect((await client.close()).complete, isTrue);
    });
  }
  final _LeaseTransport transport;
  late final AnyworkClient client;
  late final TimelineSessionOwner owner;
  TimelineDisplayLease get lease => owner.lease('thread')!;
  Future<void> open() async {
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await client.conversations.session('thread').content.ready;
  }

  Future<void> append(List<ConversationItem> items) async {
    transport.feed.emit(
      ConversationBatch(
        subscriptionId: 'lease',
        timelineEpoch: 'epoch',
        fromSeq: lease.completedCursor!.appendSeq,
        throughSeq: items.last.header.appendSeq,
        items: items,
      ),
    );
    await transport.feed.accepted(transport.feed.deliveredFrames);
  }
}

final class _Feed extends ScriptedConversationFeed {
  _Feed(ConversationBaseline value)
    : super(threadId: 'thread', subscriptionId: 'lease', baseline: () => value);
  final _acks = <int, Completer<void>>{};
  Future<void> accepted(int sequence) {
    if (acknowledgements.contains(sequence)) return Future.value();
    return (_acks[sequence] ??= Completer<void>()).future;
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    await super.acknowledge(deliverySequence);
    _acks.remove(deliverySequence)?.complete();
  }
}

final class _LeaseTransport extends Fake implements StudioTransport {
  _LeaseTransport(ConversationBaseline baseline) : feed = _Feed(baseline);
  final _Feed feed;
  int opens = 0;
  _Reader? reader;
  final readerOpened = Completer<_Reader>();
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  }) async {
    opens++;
    return feed;
  }

  @override
  Future<ConversationHistoryReader> openHistoryReader(String threadId) async {
    final value = _Reader();
    reader = value;
    readerOpened.complete(value);
    return value;
  }
}

final class _Reader extends Fake implements ConversationHistoryReader {
  @override
  String get threadId => 'thread';
  @override
  String get timelineEpoch => 'epoch';
  final reply = Completer<ConversationPage>();
  final entered = Completer<void>();
  final boundaries = <ConversationQueryCursor?>[];
  bool failClose = false;
  int closeCalls = 0;
  @override
  Future<ConversationPage> page({ConversationQueryCursor? before, int? limit}) {
    boundaries.add(before);
    if (!entered.isCompleted) entered.complete();
    return reply.future;
  }

  @override
  void requestClose() {}
  @override
  Future<void> close() async {
    closeCalls++;
    if (failClose) throw StateError('reader close failed');
  }
}
