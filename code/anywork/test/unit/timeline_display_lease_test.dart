import 'dart:async';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_member_controller.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/mapped_conversation_feed.dart';

// The real SDK and presentation owner admit batches into the real component.
// The transport supplies only explicit facts and I/O barriers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Children close failure releases its display and other side without retiring Main', () async {
    final transport = _ScopedTransport();
    final client = AnyworkClient(transport: transport, clientId: 'scopes');
    final owner = TimelineSessionOwner(client: client)
      ..updateReadDemand(chatDemand);
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    final session = client.conversations.session('thread');
    await session.content.ready;
    await transport.main.accepted(1);
    final mainLease = owner.lease('thread')!;
    final mainCurrent = session.current.value;
    final children = await client.conversations.openChildren(
      threadId: 'thread',
      parentId: 'parent',
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
    expect(session.current.value, same(mainCurrent));
    expect(children.current.value, isNull);
    expect(
      transport.scopes.last,
      isA<ChildrenChatScope>().having(
        (scope) => scope.parentId,
        'parentId',
        'parent',
      ),
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
    transport.main.emit(
      chatBatch([chatMessage('main-next')], placement: ChatPlacement.append),
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
        chatMessage('a'),
        chatMessage('b'),
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
    final h = _Harness([chatMessage('c')], before: 'opaque:before');
    await h.open();
    final lease = h.lease;
    final message = lease.controller.messages.single;
    final operations = <ChatOperation>[];
    final observed = lease.controller.operationsStream.listen(operations.add);
    addTearDown(observed.cancel);
    final loading = h.owner.loadOlder('thread', generation: lease.generation);
    await h.transport.reader.entered.future;
    h.transport.reader.reply.complete(
      chatBatch([
        chatMessage('a'),
        chatMessage('b'),
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
      await h.append([chatMessage('b')]);
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

  test('native reader close failure belongs to SDK and remains retryable after UI release', () async {
    final h = _Harness([chatMessage('c')], before: 'older');
    await h.open();
    final lease = h.lease;
    final scope = lease.openDetailQueries()!;
    h.transport.reader.failClose = true;
    h.client.conversations.setVisibleThread(null);
    expect((await h.owner.close()).complete, isTrue);
    expect(scope.isActive, isFalse);
    expect(lease.isReleased, isTrue);
    final report = await h.client.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 30)),
    );
    expect(report.complete, isFalse);
    expect(h.transport.reader.closeCalls, greaterThanOrEqualTo(1));
    h.transport.reader.failClose = false;
    expect((await h.client.retryCleanup()).complete, isTrue);
    expect(h.transport.reader.closeCalls, greaterThanOrEqualTo(2));
  });

  test(
    'retirement fences new queries and joins an already accepted older read',
    () async {
      final h = _Harness([chatMessage('c')], before: 'older');
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
        chatBatch([chatMessage('late')], placement: ChatPlacement.prepend),
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
    h.transport.feed.emit(chatBatch([chatMessage('reset')]));
    await h.transport.feed.accepted(2);
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
    expect(h.transport.opens, 1);
  });

  test('Append preserves parsed card and body references without a second collection', () async {
    final h = _Harness([chatMessage('body', body: 'unchanged')]);
    await h.open();
    final original = h.lease.controller.messages.single;
    final card =
        original.metadata![chatItemPresentationKey] as ChatItemPresentation;
    final body = card.body('body');
    await h.append([chatMessage('next')]);
    expect(h.lease.controller.messages.first, same(original));
    expect(
      h.lease.controller.messages.first.metadata![chatItemPresentationKey],
      same(card),
    );
    expect(card.body('body'), same(body));
    expect(card.inlineText('body'), 'unchanged');
  });
}

final class _Harness {
  _Harness(List<TimelineItem> messages, {String? before})
    : transport = _LeaseTransport(
        chatBatch(messages, before: before, current: chatCurrent()),
      ) {
    client = AnyworkClient(transport: transport, clientId: 'lease');
    owner = TimelineSessionOwner(client: client)..updateReadDemand(chatDemand);
    addTearDown(() async {
      transport.reader.failClose = false;
      if (!transport.reader.reply.isCompleted) {
        transport.reader.reply.complete(
          chatBatch([], placement: ChatPlacement.prepend),
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
    await client.conversations.session('thread').content.ready;
    await transport.feed.accepted(1);
  }

  Future<void> append(List<TimelineItem> messages) async {
    transport.feed.emit(chatBatch(messages, placement: ChatPlacement.append));
    await transport.feed.accepted(transport.feed.deliveredFrames);
  }
}

final class _LeaseTransport extends Fake implements StudioTransport {
  _LeaseTransport(ChatBatch initial) {
    feed = ScriptedConversationFeed(
      threadId: 'thread',
      subscriptionId: 'lease',
      initial: () => initial,
      reader: reader,
    );
  }
  late final ScriptedConversationFeed feed;
  final reader = _Reader();
  int opens = 0;
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    opens++;
    return feed;
  }
}

final class _Reader extends Fake implements ConversationReader {
  @override
  String get threadId => 'thread';
  final reply = Completer<ChatBatch>();
  final entered = Completer<void>();
  final boundaries = <String>[];
  final demands = <ReadDemand>[];
  bool failClose = false;
  int closeCalls = 0;
  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) {
    boundaries.add(before);
    demands.add(demand);
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

final class _ScopedTransport extends Fake implements StudioTransport {
  final mainReader = _Reader();
  final childReader = _Reader();
  late final main = ScriptedConversationFeed(
    threadId: 'thread',
    subscriptionId: 'main',
    reader: mainReader,
    initial: () =>
        chatBatch([chatMessage('main')], current: chatCurrent(sequence: 1)),
  );
  late final child = ScriptedConversationFeed(
    threadId: 'thread',
    subscriptionId: 'child',
    reader: childReader,
    initial: () => ChatBatch(
      placement: ChatPlacement.set,
      entries: [ChatAtomEntry(chatAtomMessage('child'))],
    ),
  );
  final scopes = <ChatScope>[];
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    scopes.add(scope);
    return scope is MainChatScope ? main : child;
  }
}
