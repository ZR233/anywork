import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_fixtures.dart';

// Placement/order are producer facts. The adapter must not recreate the deleted
// atom/seq/group ledger, deduplicate, or merge adjacent same-turn activities.
void main() {
  late InMemoryChatController stock;
  late TimelineMessageController adapter;
  late TimelineImageResources images;
  late List<ChatOperation> operations;
  late StreamSubscription<ChatOperation> observed;
  setUp(() {
    stock = InMemoryChatController();
    images = TimelineImageResources(threadId: 'thread');
    adapter = TimelineMessageController(
      stock,
      generation: 7,
      imageResources: images,
    );
    operations = [];
    observed = stock.operationsStream.listen(operations.add);
  });
  tearDown(() async {
    adapter.dispose();
    images.release();
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

  test('Append inserts the whole batch once and preserves loaded Message/card/body references', () async {
    await adapter.applyBatch(chatBatch([chatMessage('old')]));
    final message = stock.messages.single;
    final presentation = card(0);
    final body = presentation.body('body');
    await flush();
    operations.clear();
    await adapter.applyBatch(
      chatBatch([
        chatEnvelope('thinking', type: 'thinking', data: const {}),
        chatEnvelope(
          'tool',
          type: 'tool',
          data: const {
            'invocation': {'name': 'exec', 'presentationContract': 'generic@1'},
          },
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
            chatEnvelope(
              'assistant-looking-id',
              type: 'text',
              data: {'channel': channel},
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
        ChatMessage(
          id: 'unknown',
          payload: InlinePayload(bytes: utf8.encode(raw)),
        ),
        ChatMessage(
          id: 'bad',
          payload: InlinePayload(bytes: utf8.encode('{broken')),
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
        ChatMessage(
          id: 'large',
          payload: DeferredPayload(reference: reference, byteLength: 123456),
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
