import 'dart:async';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_member_controller.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';
import '../support/mapped_conversation_feed.dart';
import '../support/recording_demo_transport.dart' show timelineReady;

// The real SDK and presentation owner admit batches into the real component.
// The transport supplies only explicit facts and I/O barriers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('current renderer borrows coexist, unregister independently and retire together', () async {
    final h = _Harness([chatMessage('main')]);
    await h.open();
    final lease = h.lease..bind();
    final work = _CurrentDisplay();
    final output = _CurrentDisplay();
    final unregisterWork = lease.registerCurrentDisplay(work);
    final unregisterOutput = lease.registerCurrentDisplay(output);
    expect(lease.isMounted, isTrue);
    expect(lease.currentDisplays, unorderedEquals([work, output]));
    unregisterOutput();
    expect(lease.currentDisplays, [work]);
    final unregisterOutputAgain = lease.registerCurrentDisplay(output);
    unregisterWork();
    expect(lease.currentDisplays, [output]);
    unregisterWork();
    expect(lease.currentDisplays, [output]);
    lease.registerCurrentDisplay(work);
    output.isCurrent = false;
    expect(lease.currentDisplays, [work]);
    output.isCurrent = true;
    expect(lease.currentDisplays, unorderedEquals([work, output]));
    expect(h.transport.opens, 1, reason: 'borrowing never opens a feed');
    final retiring = lease.retire();
    expect(lease.isRetired, isTrue);
    expect(lease.currentDisplays, isEmpty);
    lease.registerCurrentDisplay(_CurrentDisplay());
    expect(lease.currentDisplays, isEmpty);
    unregisterOutputAgain();
    expect(lease.currentDisplays, isEmpty);
    // Resource registration does not take over renderer teardown.
    expect(work.isCurrent, isTrue);
    expect(output.isCurrent, isTrue);
    await lease.unbind();
    await retiring;
  });

  test('Children close failure releases its display and other side without retiring Main', () async {
    final transport = _ScopedTransport();
    final client = AnyworkClient(transport: transport, clientId: 'scopes');
    final owner = TimelineSessionOwner(client: client)
      ..updateReadDemand(chatDemand);
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await transport.main.accepted(1);
    final mainLease = owner.lease('thread')!;
    final mainCurrent = mainLease.live.value;
    expect(mainCurrent, isNotNull);
    final children = await client.conversations.openRecords(
      threadId: 'thread',
      scope: const ChatScope.conversation(parentId: 'parent'),
      demand: chatDemand,
    );
    final controller = InMemoryChatController();
    final images = TimelineImageResources(threadId: 'thread');
    final adapter = TimelineMemberController(controller);
    final consumer = children.attachConsumer(adapter, demand: chatDemand);
    addTearDown(() async {
      transport.childReader.failClose = false;
      consumer.cancel();
      await children.close();
      expect((await client.conversations.retryCleanup()).complete, isTrue);
      adapter.dispose();
      images.release();
      controller.dispose();
      expect((await owner.close()).complete, isTrue);
      await client.close();
      expect((await client.retryCleanup()).complete, isTrue);
    });
    await children.ready;
    await transport.child.accepted(1);
    expect(controller.messages.single.id, 'child');
    expect(mainLease.live.value, same(mainCurrent));
    expect(children.activity.value, isNull);
    expect(
      transport.scopes.last,
      isA<ChatScope>().having((scope) => scope.parentId, 'parentId', 'parent'),
    );
    transport.childReader.failClose = true;
    consumer.cancel();
    final report = await children.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 30)),
    );
    expect(report.complete, isFalse);
    expect(
      transport.child.closed,
      isTrue,
      reason: 'feed cancellation still happens when read close fails',
    );
    expect(transport.child.closeCalls, greaterThanOrEqualTo(1));
    expect(transport.childReader.closeCalls, greaterThanOrEqualTo(1));
    expect(transport.main.closed, isFalse);
    expect(owner.lease('thread'), same(mainLease));
    transport.main.emitTimeline(
      _mainBatch([
        chatMessage('main-next', completionSeq: 2),
      ], placement: ChatPlacement.append),
    );
    await transport.main.accepted(2);
    expect(mainLease.controller.messages.map((message) => message.id), [
      'main',
      'main-next',
    ]);
    transport.childReader.failClose = false;
    expect((await client.conversations.retryCleanup()).complete, isTrue);
    expect(transport.childReader.closeCalls, greaterThanOrEqualTo(2));
  });

  test(
    'Set owns one controller collection and an opaque older boundary',
    () async {
      final h = _Harness([
        chatMessage('a', completionSeq: 10),
        chatMessage('b', completionSeq: 11),
      ], before: 'opaque:before');
      await h.open();
      final lease = h.lease;
      expect(lease.controller, isA<InMemoryChatController>());
      expect(lease.controller.messages.map((message) => message.id), [
        'a',
        'b',
      ]);
      expect(lease.controller.messages.first.createdAt, isNull);
      expect(lease.loadedCount, 2);
      expect(lease.olderCursor, 'opaque:before');
      expect(lease.hasOlder, isTrue);
      expect(h.transport.opens, 1);
    },
  );

  test('older read is admitted once before return and preserves existing Message identity', () async {
    final h = _Harness([
      chatMessage('c', completionSeq: 1000),
    ], before: 'opaque:before');
    await h.open();
    final lease = h.lease;
    final message = lease.controller.messages.single;
    final operations = <ChatOperation>[];
    final observed = lease.controller.operationsStream.listen(operations.add);
    addTearDown(observed.cancel);
    final loading = h.owner.loadOlder('thread', generation: lease.generation);
    await h.transport.reader.entered.future;
    h.transport.reader.reply.complete(
      _mainBatch([
        chatMessage('a', completionSeq: 10),
        chatMessage('b', completionSeq: 11),
      ], placement: ChatPlacement.prepend),
    );
    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(lease.controller.messages.map((message) => message.id), [
      'a',
      'b',
      'c',
    ]);
    expect(lease.controller.messages.last, same(message));
    expect(
      operations,
      hasLength(1),
      reason: 'loadOlder must not perform a second insert',
    );
    expect(lease.hasOlder, isFalse);
    expect(h.transport.reader.boundaries, ['opaque:before']);
    expect(h.transport.reader.demands, [chatDemand]);
    expect(
      h.transport.opens,
      1,
      reason: 'queries retain the original feed reader',
    );
  });

  test(
    'history mode accepts Append without replacing display or old messages',
    () async {
      final h = _Harness([chatMessage('a')], before: 'older');
      await h.open();
      final lease = h.lease;
      final first = lease.controller.messages.single;
      await h.owner.dispatch('thread', const TimelineEnterHistory());
      await h.append([chatMessage('b', completionSeq: 2)]);
      expect(h.lease, same(lease));
      expect(lease.controller.messages.first, same(first));
      expect(lease.loadedCount, 2);
      expect(
        lease.olderCursor,
        'older',
        reason: 'Append never advances before',
      );
      expect(h.owner.source.value?.hasNewOutput, isTrue);
      await h.owner.returnToLive('thread');
      expect(h.lease, same(lease));
      expect(h.owner.source.value?.hasNewOutput, isFalse);
      expect(h.transport.opens, 1);
    },
  );

  test(
    'mounted lease retains controller ownership until unbind and close retry',
    () async {
      final h = _Harness([chatMessage('a')]);
      h.owner.noteVisibleSelection('thread');
      await h.open();
      final lease = h.lease..bind();
      final controller = lease.controller;
      expect(h.owner.visibleLayoutSnapshot!.firstContentLayout, isNull);
      h.owner.recordContentLayout(lease, 'a', h.owner.monotonicMicros);
      final visible = h.owner.visibleLayoutSnapshot!;
      expect(visible.threadId, 'thread');
      expect(visible.selectionId, lease.selectionId);
      expect(visible.generation, lease.generation);
      expect(visible.firstContentLayout, same(lease.firstContentLayout));
      expect(visible.firstContentLayout, isNotNull);
      expect(h.owner.visibleLayoutSnapshot, visible);
      expect(h.transport.opens, 1);
      expect(h.transport.reader.boundaries, isEmpty);
      expect(h.transport.reader.demands, isEmpty);
      h.client.conversations.setVisibleThread(null);
      final closing = h.owner.close(deadline: DateTime.utc(2000));
      expect(h.owner.visibleLayoutSnapshot, isNull);
      expect(h.owner.close(), same(closing));
      expect((await closing).complete, isFalse);
      expect(lease.isRetired, isTrue);
      expect(lease.isReleased, isFalse);
      expect(lease.controller, same(controller));
      expect(h.owner.lease('thread'), isNull);
      h.owner.recordContentLayout(lease, 'a', h.owner.monotonicMicros);
      expect(h.owner.visibleLayoutSnapshot, isNull);
      expect(lease.firstContentLayout, same(visible.firstContentLayout));
      await lease.unbind();
      expect(lease.isReleased, isTrue);
      expect(lease.loadedCount, 0);
      expect(() => lease.controller, throwsStateError);
      expect((await h.owner.close()).complete, isTrue);
      expect(h.owner.visibleLayoutSnapshot, isNull);
    },
  );

  test('native GUI reader close failure stays with its original UI owner after display release', () async {
    final h = _Harness([
      chatMessage('c', completionSeq: 1000),
    ], before: 'older');
    await h.open();
    final lease = h.lease;
    final scope = lease.openDetailQueries()!;
    h.transport.reader.failClose = true;
    h.client.conversations.setVisibleThread(null);
    expect((await h.owner.close()).complete, isFalse);
    expect(scope.isActive, isFalse);
    expect(lease.isReleased, isTrue);
    final report = await h.client.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 30)),
    );
    expect(report.complete, isTrue);
    expect(h.transport.reader.closeCalls, greaterThanOrEqualTo(1));
    h.transport.reader.failClose = false;
    expect((await h.owner.close()).complete, isTrue);
    expect(h.transport.reader.closeCalls, greaterThanOrEqualTo(2));
  });

  test(
    'retirement fences new queries and joins an already accepted older read',
    () async {
      final h = _Harness([
        chatMessage('c', completionSeq: 1000),
      ], before: 'older');
      await h.open();
      final lease = h.lease;
      final loading = h.owner.loadOlder('thread', generation: lease.generation);
      await h.transport.reader.entered.future;
      h.client.conversations.setVisibleThread(null);
      expect(
        (await h.owner.close(deadline: DateTime.utc(2000))).complete,
        isFalse,
      );
      expect(lease.queries, isNull);
      expect(lease.openDetailQueries(), isNull);
      expect(lease.isReleased, isFalse);
      h.transport.reader.reply.complete(
        _mainBatch([chatMessage('late')], placement: ChatPlacement.prepend),
      );
      await loading;
      expect((await h.owner.close()).complete, isTrue);
      expect(lease.isReleased, isTrue);
      expect(h.transport.reader.boundaries, ['older']);
    },
  );

  test('new Set changes chat identity and releases borrowed image only after unbind', () async {
    final h = _Harness([chatMessage('image-atom')]);
    await h.open();
    final old = h.lease..bind();
    // A mounted attachment connector declares references on the lease; merely
    // loading a message no longer creates a second attachment/item mirror.
    old.imageResources.retainItem('image-atom', const [
      ThreadAttachmentView(
        id: 'image',
        modality: AttachmentModalityView.image,
        mediaType: 'image/png',
        byteSize: 8,
      ),
    ]);
    final resource = old.imageResources.borrow('image');
    final oldKey = old.chatKey;
    h.transport.initial = _mainBatch([chatMessage('reset')]);
    h.owner.refresh('thread');
    await timelineReady(h.owner, 'thread');
    await h.transport.feed.accepted(1);
    final next = h.lease;
    expect(next.chatKey, isNot(oldKey));
    expect(next.scrollController.keepScrollOffset, isFalse);
    expect(next.controller.messages.single.id, 'reset');
    expect(old.isRetired, isTrue);
    expect(old.isReleased, isFalse);
    expect(
      () => resource.retry(() async => throw StateError('must not read')),
      throwsStateError,
    );
    await old.unbind();
    expect(old.isReleased, isTrue);
    expect(h.transport.opens, 2);
  });

  test('Append preserves parsed card and body references without a second collection', () async {
    final h = _Harness([chatMessage('body', body: 'unchanged')]);
    await h.open();
    final original = h.lease.controller.messages.single;
    final card =
        original.metadata![chatItemPresentationKey] as ChatItemPresentation;
    final body = card.body('body');
    await h.append([chatMessage('next', completionSeq: 2)]);
    expect(h.lease.controller.messages.first, same(original));
    expect(
      h.lease.controller.messages.first.metadata![chatItemPresentationKey],
      same(card),
    );
    expect(card.body('body'), same(body));
    expect(card.inlineText('body'), 'unchanged');
  });
}

final class _CurrentDisplay implements TimelineCurrentDisplay {
  @override
  bool isCurrent = true;
  @override
  String? get turnId => 'turn';
  @override
  String? get activityId => 'activity';
  @override
  bool get expanded => false;
  @override
  Iterable<TimelineCurrentCollectionDisplay> get collections => const [];
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows => const [];
}

final class _Harness {
  _Harness(List<CompletedEntry> messages, {String? before})
    : transport = _LeaseTransport(_mainBatch(messages, before: before)) {
    client = AnyworkClient(transport: transport, clientId: 'lease');
    owner = TimelineSessionOwner(client: client)..updateReadDemand(chatDemand);
    addTearDown(() async {
      transport.reader.failClose = false;
      if (!transport.reader.reply.isCompleted) {
        transport.reader.reply.complete(
          _mainBatch([], placement: ChatPlacement.prepend),
        );
      }
      client.conversations.setVisibleThread(null);
      final current = owner.lease('thread');
      if (current?.isMounted ?? false) unawaited(current!.unbind());
      expect((await owner.close()).complete, isTrue);
      final report = await client.close();
      if (!report.complete) {
        expect((await client.retryCleanup()).complete, isTrue);
      }
    });
  }
  final _LeaseTransport transport;
  late final AnyworkClient client;
  late final TimelineSessionOwner owner;
  TimelineDisplayLease get lease => owner.lease('thread')!;
  Future<void> open() async {
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await transport.feed.accepted(1);
  }

  Future<void> append(List<CompletedEntry> messages) async {
    final response = transport.feed.deliveredFrames + 1;
    transport.feed.emitTimeline(
      _mainBatch(messages, placement: ChatPlacement.append),
    );
    await transport.feed.accepted(response);
  }
}

final class _LeaseTransport extends Fake
    implements StudioTransport, TimelineTransport {
  _LeaseTransport(this.initial) {
    _createFeed();
  }
  ViewUpdate initial;
  void _createFeed() {
    feed = ScriptedTimelineReader(
      queries: _TimelineQueries(reader, 'lease'),
      initial: () => initial,
    );
  }

  late ScriptedTimelineReader feed;
  _Reader reader = _Reader();
  int opens = 0;

  /// The independent state subscription carries only state facts; each attempt
  /// owns its own single-consumer feed.
  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async => ScriptedConversationStateFeed(
    threadId: 'thread',
    subscriptionId: 'lease-state',
    initialState: () => ThreadSnapshotFrame(
      workspace: chatWorkspace('thread'),
      completedHistoryVersion: completedHistoryVersion,
      schemaVersion: threadSchemaVersion,
    ),
  );

  @override
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required int presentationVersion,
    required int readerProtocolVersion,
    required ReadDemand demand,
  }) async {
    if (opens > 0) {
      reader = _Reader();
      _createFeed();
    }
    opens++;
    return feed;
  }
}

final class _Reader extends Fake implements ConversationReader {
  @override
  String get threadId => 'thread';
  final reply = Completer<ViewUpdate>();
  final entered = Completer<void>();
  final boundaries = <String>[];
  final demands = <ReadDemand>[];
  bool failClose = false;
  int closeCalls = 0;
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    boundaries.add(before);
    demands.add(demand);
    if (!entered.isCompleted) entered.complete();
    return reply.future.then(historyFixturePage);
  }

  @override
  void requestClose() {}
  @override
  Future<void> close() async {
    closeCalls++;
    if (failClose) throw StateError('reader close failed');
  }
}

final class _ScopedTransport extends Fake
    implements StudioTransport, TimelineTransport {
  final mainReader = _Reader();
  final childReader = _Reader();
  late final main = ScriptedTimelineReader(
    queries: _TimelineQueries(mainReader, 'main'),
    initial: () => _mainBatch([chatMessage('main')]),
  );
  late final child = ScriptedConversationFeed(
    threadId: 'thread',
    subscriptionId: 'child',
    reader: childReader,
    initial: () => ChatBatch(
      placement: ChatPlacement.set,
      entries: [chatMessage('child')],
      throughSeq: 1,
    ),
  );
  final scopes = <ChatScope>[];

  /// Main owns the independent state subscription; Children stay content-only.
  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async => ScriptedConversationStateFeed(
    threadId: 'thread',
    subscriptionId: 'main-state',
    initialState: () => ThreadSnapshotFrame(
      workspace: chatWorkspace('thread'),
      completedHistoryVersion: completedHistoryVersion,
      schemaVersion: threadSchemaVersion,
    ),
  );

  @override
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required int presentationVersion,
    required int readerProtocolVersion,
    required ReadDemand demand,
  }) async => main;
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    scopes.add(scope);
    expect(scope, isA<ChatScope>());
    return child;
  }
}

ViewUpdate _mainBatch(
  List<CompletedEntry> entries, {
  ChatPlacement placement = ChatPlacement.set,
  String? before,
}) {
  final through = entries.lastOrNull?.completionSeq ?? 0;
  return displayBatch(
    [for (final entry in entries) displaySingle(entry)],
    placement: placement,
    before: before,
    from: placement == ChatPlacement.append
        ? entries.first.completionSeq - 1
        : null,
    through: through,
    live: placement == ChatPlacement.set
        ? TailSnapshot(
            currentWorkId: null,
            revision: 1,
            layoutRevision: 1,
            readyFrontier: through,
            executionPresent: false,
            blocks: const [],
          )
        : null,
  );
}

final class _TimelineQueries extends Fake implements TimelineReader {
  _TimelineQueries(this.reader, this.subscriptionId);
  @override
  OpenTimeline get metadata => OpenTimeline(
    readerId: subscriptionId,
    presentationVersion: 6,
    readerProtocolVersion: 1,
    initialCursor: ViewCursor('$subscriptionId-C0'),
  );
  @override
  final _Reader reader;
  String get threadId => 'thread';
  final String subscriptionId;
  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => reader.loadTimelineOlder(before: before, demand: demand);
  @override
  void requestClose() => reader.requestClose();
  @override
  Future<void> close() => reader.close();
}
