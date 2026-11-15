import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/completion_fixtures.dart';
import '../support/display_fixtures.dart';

// Placement, Run composition and work counters are covered by
// completion_run_controller_test. These assertions preserve the original
// single-record rendering and compatibility behavior across the protocol cut.
void main() {
  test(
    'Single retains its completion identity and original renderer payload',
    () async {
      final stock = InMemoryChatController();
      final adapter = TimelineMessageController(stock, generation: 7);
      await adapter.applyFixtureUpdate(
        displayBatch([
          displaySingle(
            completionEntry('completion', 1, isText: true, text: '中文 🐱'),
          ),
        ]),
      );
      final card = chatItemPresentationOf(stock.messages.single)!;
      expect(stock.messages.single.id, 'completion');
      expect(card.id, 'completion');
      expect(card.atom!.id, 'atom:completion');
      expect(card.inlineText('body'), '中文 🐱');
      expect(card.authorId, 'assistant');
      adapter.dispose();
      stock.dispose();
    },
  );

  test(
    'unknown and malformed envelopes preserve their own diagnostic body',
    () {
      const raw = '{"contract":"future.chat/2","type":"future","data":{}}';
      final unknown = ChatItemPresentation.decodePayload(
        'unknown',
        InlinePayload(bytes: utf8.encode(raw)),
      );
      final malformed = ChatItemPresentation.decodePayload(
        'bad',
        InlinePayload(bytes: utf8.encode('{broken')),
      );
      expect(unknown.compatibility, ChatItemCompatibility.unknown);
      expect(unknown.raw, raw);
      expect(malformed.compatibility, ChatItemCompatibility.malformed);
      expect(malformed.raw, '{broken');
    },
  );

  test(
    'Deferred holds only its original content capability and byte length',
    () {
      const reference = ContentRef(
        databaseId: 'database',
        target: ItemPayloadTarget(itemId: 'large'),
      );
      final card = ChatItemPresentation.decodePayload(
        'large',
        const DeferredPayload(reference: reference, byteLength: 123456),
      );
      expect(card.compatibility, ChatItemCompatibility.deferred);
      expect(card.reference, same(reference));
      expect(card.byteLength, 123456);
      expect(card.bodies, isEmpty);
      expect(card.raw, isNull);
    },
  );

  test('retirement rejects admission and leaves the component lifetime with its owner', () async {
    final stock = InMemoryChatController();
    final adapter = TimelineMessageController(stock, generation: 7);
    await adapter.applyFixtureUpdate(
      displayBatch([displaySingle(completionEntry('loaded', 1))]),
    );
    adapter.retireDisplays();
    await expectLater(
      () => adapter.applyFixtureUpdate(displayBatch([])),
      throwsA(isA<StaleConversationScope>()),
    );
    adapter.dispose();
    await stock.insertMessage(
      const Message.custom(id: 'owner', authorId: 'unknown'),
    );
    expect(stock.messages.last.id, 'owner');
    stock.dispose();
  });
}
