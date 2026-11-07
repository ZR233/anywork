import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

TimelineItem _resultGroup({
  int count = 1,
  int position = 0,
  String id = 'results',
}) {
  final fixture = workItem(id, count: count);
  return TimelineItem(
    id: id,
    kind: TimelineItemKind.workGroup,
    source: const BackgroundResultChatSource(messageId: 'first-result'),
    delivery: ChatDeliveryKind.independent,
    position: position,
    admissionClosed: true,
    contents: const [],
    summary: fixture.summary,
    members: fixture.members,
  );
}

// Placement/order are producer facts. The adapter must not recreate the deleted
// atom/seq/group ledger, deduplicate, or merge adjacent same-turn activities.
void main() {
  test('only explicit contentPresent false proves emptiness; legacy unknown and whitespace are preserved', () {
    final legacy = ChatItemPresentation.decode(
      chatAtomMessage('legacy', body: ''),
    );
    final empty = ChatItemPresentation.decode(
      chatAtomMessage('empty', body: '', contentPresent: false),
    );
    final whitespace = ChatItemPresentation.decode(
      chatAtomMessage('space', body: '  \n', contentPresent: true),
    );
    expect(legacy.isKnownEmptyText, isFalse);
    expect(empty.isKnownEmptyText, isTrue);
    expect(whitespace.isKnownEmptyText, isFalse);
    expect(whitespace.inlineText('body'), '  \n');
  });
  late InMemoryChatController stock;
  late TimelineMessageController adapter;
  late List<ChatOperation> operations;
  late StreamSubscription<ChatOperation> observed;
  setUp(() {
    stock = InMemoryChatController();
    adapter = TimelineMessageController(stock, generation: 7);
    operations = [];
    observed = stock.operationsStream.listen(operations.add);
  });
  tearDown(() async {
    adapter.dispose();
    await observed.cancel();
    stock.dispose();
  });
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  ChatItemPresentation card(int index) =>
      stock.messages[index].metadata![chatItemPresentationKey]
          as ChatItemPresentation;

  test(
    'Set uses a nonanimated operation and one custom Message per producer item',
    () async {
      await adapter.applyBatch(chatBatch([chatMessage('first')]));
      await flush();
      expect(operations.single.type, ChatOperationType.set);
      expect(operations.single.animated, isFalse);
      expect(stock.messages.single, isA<CustomMessage>());
      expect(stock.messages.single.id, 'first');
      expect(stock.messages.single.createdAt, isNull);
      expect(card(0).inlineText('body'), '中文 🐱');
    },
  );

  test(
    'large Main page builds one temporary ID index and still rejects repeats',
    () async {
      final counted = _CountingController();
      final countedAdapter = TimelineMessageController(counted, generation: 8);
      await countedAdapter.applyBatch(
        chatBatch([for (var i = 0; i < 2000; i++) chatMessage('item-$i')]),
      );
      counted.resetAccessCounts();
      await expectLater(
        countedAdapter.applyBatch(
          chatBatch([
            chatMessage('item-1999'),
          ], placement: ChatPlacement.append),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(counted.iterations, 1);
      expect(counted.elementReads, 2000);
      expect(counted.messages, hasLength(2000));
      countedAdapter.dispose();
      counted.dispose();
    },
  );

  test('Append inserts the whole batch once and preserves loaded Message/card/body references', () async {
    await adapter.applyBatch(chatBatch([chatMessage('old')]));
    final message = stock.messages.single;
    final presentation = card(0);
    final body = presentation.body('body');
    await flush();
    operations.clear();
    await adapter.applyBatch(
      chatBatch([
        statusItem(chatEnvelope('thinking', type: 'thinking', data: const {})),
        statusItem(
          chatEnvelope(
            'tool',
            type: 'tool',
            data: const {
              'invocation': {
                'name': 'exec',
                'presentationContract': 'generic@1',
              },
            },
          ),
        ),
        chatMessage('separator'),
      ], placement: ChatPlacement.append),
    );
    await flush();
    expect(operations.single.type, ChatOperationType.insertAll);
    expect(operations.single.messages, hasLength(3));
    expect(stock.messages.map((message) => message.id), [
      'old',
      'thinking',
      'tool',
      'separator',
    ]);
    expect(stock.messages.first, same(message));
    expect(card(0), same(presentation));
    expect(card(0).body('body'), same(body));
  });

  test('Update replaces a result-group header in place and preserves its open member scope', () async {
    await adapter.applyBatch(
      chatBatch([chatMessage('before'), _resultGroup()]),
    );
    final before = stock.messages.first;
    final original =
        stock.messages.last.metadata![timelineDisplayUnitKey]
            as TimelineDisplayUnit;
    original.expansion.expanded = true;
    original.expansion.setBodyVisible(Object(), true);
    final bodyGeneration = original.expansion.bodyGeneration;
    await flush();
    operations.clear();
    await adapter.applyBatch(
      chatBatch([_resultGroup(count: 3)], placement: ChatPlacement.update),
    );
    await flush();
    final updated =
        stock.messages.last.metadata![timelineDisplayUnitKey]
            as TimelineDisplayUnit;
    expect(stock.messages, hasLength(2));
    expect(stock.messages.first, same(before));
    expect(updated.item.position, 0);
    expect(updated.item.summary!.memberCount, 3);
    expect(updated.expansion, same(original.expansion));
    expect(updated.expansion.expanded, isTrue);
    expect(updated.expansion.bodyActive, isTrue);
    expect(updated.expansion.bodyGeneration, same(bodyGeneration));
    expect(updated.expansion.current, same(updated));
    expect(operations, hasLength(1));
    expect(operations.single.type, ChatOperationType.update);
  });

  test('Update rejects unknown groups, changed positions and ordinary items before mutating', () async {
    await adapter.applyBatch(chatBatch([_resultGroup(), chatMessage('text')]));
    final original = List<Message>.of(stock.messages);
    await flush();
    operations.clear();
    for (final replacement in [
      _resultGroup(id: 'unknown'),
      _resultGroup(position: 9),
      workItem('results'),
      chatMessage('text'),
    ]) {
      await expectLater(
        adapter.applyBatch(
          chatBatch([replacement], placement: ChatPlacement.update),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
    }
    await expectLater(
      adapter.applyBatch(
        chatBatch([
          _resultGroup(count: 3),
          _resultGroup(id: 'missing'),
        ], placement: ChatPlacement.update),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
    await flush();
    expect(stock.messages, orderedEquals(original));
    expect(operations, isEmpty);
  });

  test('Prepend preserves producer order and old identities without grouping or a second insert', () async {
    await adapter.applyBatch(chatBatch([chatMessage('latest')]));
    final latest = stock.messages.single;
    await flush();
    operations.clear();
    await adapter.applyBatch(
      chatBatch([
        chatMessage('older-2'),
        chatMessage('older-1'),
      ], placement: ChatPlacement.prepend),
    );
    await flush();
    expect(stock.messages.map((message) => message.id), [
      'older-2',
      'older-1',
      'latest',
    ]);
    expect(stock.messages.last, same(latest));
    expect(operations.single.type, ChatOperationType.insertAll);
    expect(operations.single.index, 0);
    expect(operations.single.animated, isFalse);
  });

  test('empty Append/Prepend do not mutate messages while empty Set explicitly clears', () async {
    await adapter.applyBatch(chatBatch([chatMessage('old')]));
    await flush();
    operations.clear();
    await adapter.applyBatch(
      chatBatch([], placement: ChatPlacement.append, current: chatCurrent()),
    );
    await adapter.applyBatch(chatBatch([], placement: ChatPlacement.prepend));
    await flush();
    expect(operations, isEmpty);
    expect(stock.messages.single.id, 'old');
    await adapter.applyBatch(chatBatch([]));
    await flush();
    expect(stock.messages, isEmpty);
    expect(operations.single.type, ChatOperationType.set);
  });

  test('attachments do not manufacture extra messages and only real sealedAt creates a date', () async {
    await adapter.applyBatch(
      chatBatch([
        statusItem(
          chatEnvelope(
            'media',
            type: 'text',
            sealedAt: 123,
            data: const {
              'channel': 'user',
              'attachments': [
                {
                  'id': 'image',
                  'modality': 'image',
                  'mediaType': 'image/png',
                  'byteSize': 10,
                },
                {
                  'id': 'file',
                  'modality': 'file',
                  'mediaType': 'text/plain',
                  'byteSize': 20,
                },
              ],
            },
            bodies: [inlineBody('body', 'caption')],
          ),
        ),
      ]),
    );
    expect(stock.messages, hasLength(1));
    expect(
      stock.messages.single.createdAt,
      DateTime.fromMillisecondsSinceEpoch(123000, isUtc: true),
    );
    expect(card(0).attachments.map((attachment) => attachment.id), [
      'image',
      'file',
    ]);
    expect(card(0).inlineText('body'), 'caption');
  });

  for (final (channel, author) in [
    ('user', 'user'),
    ('parentAgent', 'parentAgent'),
    ('final', 'assistant'),
    ('commentary', 'assistant'),
    ('future-channel', 'unknown'),
  ]) {
    test(
      'author uses explicit $channel rather than guessing from identity',
      () async {
        await adapter.applyBatch(
          chatBatch([
            statusItem(
              chatEnvelope(
                'assistant-looking-id',
                type: 'text',
                data: {'channel': channel},
              ),
            ),
          ]),
        );
        expect(stock.messages.single.authorId, author);
      },
    );
  }

  test('unknown and malformed payload remain visible records rather than throwing or disappearing', () async {
    final raw = '{"contract":"future/2","type":"thinking","data":{}}';
    await adapter.applyBatch(
      chatBatch([
        statusItem(
          fixtureAtom(
            id: 'unknown',
            payload: InlinePayload(bytes: utf8.encode(raw)),
          ),
        ),
        statusItem(
          fixtureAtom(
            id: 'bad',
            payload: InlinePayload(bytes: utf8.encode('{broken')),
          ),
        ),
      ]),
    );
    expect(stock.messages.map((message) => message.id), ['unknown', 'bad']);
    expect(card(0).compatibility, ChatItemCompatibility.unknown);
    expect(card(0).raw, raw);
    expect(card(1).compatibility, ChatItemCompatibility.malformed);
    expect(card(1).raw, '{broken');
  });

  test('Deferred retains only original reference and byte length, never a fabricated preview', () async {
    const reference = ContentRef(
      databaseId: 'database',
      target: ItemPayloadTarget(itemId: 'large'),
    );
    await adapter.applyBatch(
      chatBatch([
        statusItem(
          fixtureAtom(
            id: 'large',
            payload: DeferredPayload(reference: reference, byteLength: 123456),
          ),
        ),
      ]),
    );
    expect(stock.messages, hasLength(1));
    expect(card(0).compatibility, ChatItemCompatibility.deferred);
    expect(card(0).reference, same(reference));
    expect(card(0).byteLength, 123456);
    expect(card(0).bodies, isEmpty);
  });

  test('dispose rejects future admission but leaves controller lifetime to its owner', () async {
    await adapter.applyBatch(chatBatch([chatMessage('loaded')]));
    adapter.dispose();
    await expectLater(adapter.applyBatch(chatBatch([])), throwsStateError);
    await stock.insertAllMessages([
      const Message.custom(id: 'owner', authorId: 'unknown'),
    ]);
    expect(stock.messages.map((message) => message.id), ['loaded', 'owner']);
  });
}

final class _CountingController extends InMemoryChatController {
  int iterations = 0;
  int elementReads = 0;

  void resetAccessCounts() {
    iterations = 0;
    elementReads = 0;
  }

  @override
  List<Message> get messages => _CountingList(super.messages, this);
}

final class _CountingList extends ListBase<Message> {
  _CountingList(this._messages, this.owner);
  final List<Message> _messages;
  final _CountingController owner;

  @override
  int get length => _messages.length;

  @override
  Message operator [](int index) {
    owner.elementReads++;
    return _messages[index];
  }

  @override
  void operator []=(int index, Message value) => _messages[index] = value;

  @override
  set length(int value) => _messages.length = value;

  @override
  Iterator<Message> get iterator {
    owner.iterations++;
    return super.iterator;
  }
}
