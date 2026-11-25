import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/completion_fixtures.dart';
import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';

FixtureCompletion _mutableTextEntry(
  String id,
  int seq,
  String text, {
  required bool active,
}) {
  final base = completionEntry(id, seq, isText: true, text: text).atom;
  return FixtureCompletion(
    recordId: id,
    completionSeq: seq,
    atom: ChatAtom(
      id: base.id,
      source: base.source,
      sourceOrder: base.sourceOrder,
      kind: base.kind,
      delivery: base.delivery,
      lifecycle: active
          ? const ActiveChatAtom(
              started: ChatFactPosition(effectSeq: 1, suborder: 0),
              status: ChatActiveStatus.running,
            )
          : base.lifecycle,
      textChannel: base.textChannel,
      contentPresent: base.contentPresent,
      contents: base.contents,
      payload: base.payload,
    ),
  );
}

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

  test(
    'real Flyer serializes apply and row-key reconcile in call order',
    () async {
      final stock = InMemoryChatController();
      final adapter = TimelineMessageController(stock, generation: 11);
      final first = displaySingle(
        _mutableTextEntry('row', 1, 'first', active: true),
      );
      final terminal = displaySingle(
        _mutableTextEntry('row', 1, 'terminal', active: false),
      );

      final set = adapter.applyBlocks([first], TimelineApplyPlacement.set);
      final reconcile = adapter.reconcileBlocks([terminal]);
      await Future.wait([set, reconcile]);

      final card = chatItemPresentationOf(stock.messages.single)!;
      expect(stock.messages.single.id, 'row');
      expect(card.inlineText('body'), 'terminal');
      adapter.dispose();
      stock.dispose();
    },
  );

  test(
    'uncertain Flyer mutation is replaced by a fresh generation Set',
    () async {
      final stock = _CommitThenFailController();
      final oldGeneration = TimelineMessageController(stock, generation: 12);
      final active = displaySingle(
        _mutableTextEntry('row', 1, 'active', active: true),
      );
      final terminal = displaySingle(
        _mutableTextEntry('row', 1, 'terminal', active: false),
      );
      await oldGeneration.applyBlocks([active], TimelineApplyPlacement.set);
      stock.failAfterUpdate = true;
      await expectLater(
        oldGeneration.reconcileBlocks([terminal]),
        throwsStateError,
      );

      oldGeneration.retireDisplays();
      final nextGeneration = TimelineMessageController(stock, generation: 13);
      await nextGeneration.applyBlocks([terminal], TimelineApplyPlacement.set);
      final card = chatItemPresentationOf(stock.messages.single)!;
      expect(card.inlineText('body'), 'terminal');

      nextGeneration.dispose();
      stock.dispose();
    },
  );

  test(
    'older prepend and accepted-window reconcile stay in serial Flyer order',
    () async {
      final stock = InMemoryChatController();
      final adapter = TimelineMessageController(stock, generation: 14);
      await adapter.applyBlocks([
        displaySingle(completionEntry('a', 2, isText: true, text: 'a')),
        displaySingle(_mutableTextEntry('c', 3, 'active c', active: true)),
      ], TimelineApplyPlacement.set);

      final older = adapter.applyBlocks([
        displaySingle(completionEntry('b', 1, isText: true, text: 'older b')),
      ], TimelineApplyPlacement.prepend);
      final terminal = adapter.reconcileBlocks([
        displaySingle(completionEntry('b', 1, isText: true, text: 'older b')),
        displaySingle(completionEntry('a', 2, isText: true, text: 'a')),
        displaySingle(_mutableTextEntry('c', 3, 'terminal c', active: false)),
      ]);
      await Future.wait([older, terminal]);

      expect(stock.messages.map((message) => message.id), ['b', 'a', 'c']);
      final c = chatItemPresentationOf(stock.messages.last)!;
      expect(c.inlineText('body'), 'terminal c');
      adapter.dispose();
      stock.dispose();
    },
  );

  test(
    'a frozen historical boundary cannot be replaced by a later original',
    () async {
      final stock = InMemoryChatController();
      final adapter = TimelineMessageController(stock, generation: 15);
      final atom = completionEntry(
        'row',
        1,
        isText: true,
        text: 'boundary',
      ).atom;
      final boundary = DisplayBlock(
        id: 'row',
        blockOrder: 1,
        body: SingleDisplayBlock(
          record: DisplayRecord(
            atom: atom,
            contentSource: const FrozenObservation(
              capturedAt: 10,
              available: true,
            ),
          ),
          visibility: HistorySingleVisibility.content,
        ),
      );
      final later = displaySingle(
        completionEntry('row', 1, isText: true, text: 'later original'),
      );

      await adapter.applyBlocks([boundary], TimelineApplyPlacement.set);
      await adapter.reconcileBlocks([later]);

      final card = chatItemPresentationOf(stock.messages.single)!;
      expect(card.displayRecord?.contentSource, isA<FrozenObservation>());
      adapter.dispose();
      stock.dispose();
    },
  );

  test('sealed WorkDisplayBlock stays immutable when HistoryCut or tail beforeSeq advances', () async {
    final stock = InMemoryChatController();
    var updates = 0;
    final sub = stock.operationsStream.listen((op) {
      if (op.type == ChatOperationType.update) updates++;
    });
    addTearDown(sub.cancel);

    final expansion = TimelineExpansionIntent()..expanded = true;
    final adapter = TimelineMessageController(
      stock,
      generation: 16,
      expansionForBlock: (_) => expansion,
    );

    DisplayBlock workBlock({
      required HistoryCut cut,
      required int? beforeSeq,
    }) => DisplayBlock(
      id: 'work:2',
      blockOrder: 2,
      body: WorkDisplayBlock(
        timing: const WorkTiming(startedAtMillis: 1000, finishedAtMillis: 2500),
        members: DisplayBlockRef(
          blockId: 'work:2',
          cut: cut,
          anchorSeq: 2,
          headSeq: 4,
          afterSeq: 1,
          beforeSeq: beforeSeq,
          runId: 'run-1',
        ),
        executionPresent: false,
        memberCount: 3,
        unfinishedCount: 0,
        groupClosed: true,
      ),
    );

    await adapter.applyBlocks([
      workBlock(cut: const HistoryCut('cut-1'), beforeSeq: null),
    ], TimelineApplyPlacement.set);
    final initialMessage = stock.messages.single;
    final initialUnit =
        initialMessage.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit;

    await adapter.reconcileBlocks([
      workBlock(cut: const HistoryCut('cut-2'), beforeSeq: 5),
    ]);

    expect(updates, 0);
    expect(identical(stock.messages.single, initialMessage), isTrue);
    expect(
      identical(
        stock.messages.single.metadata![timelineDisplayUnitKey],
        initialUnit,
      ),
      isTrue,
    );
    expect(expansion.expanded, isTrue);

    adapter.dispose();
    stock.dispose();
  });
}

final class _CommitThenFailController extends InMemoryChatController {
  bool failAfterUpdate = false;

  @override
  Future<void> updateMessage(Message oldMessage, Message newMessage) async {
    await super.updateMessage(oldMessage, newMessage);
    if (failAfterUpdate) {
      failAfterUpdate = false;
      throw StateError('mutation outcome unknown');
    }
  }
}
