import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:anywork_client/models.dart' show ThreadStatusView;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

const source = ForegroundTurnChatSource(turnId: 'T');
ChatAtom part(
  String id,
  int? order, {
  ChatAtomKind kind = ChatAtomKind.reasoning,
  bool terminal = false,
  int? seq,
  ChatSourceId from = source,
  String? completionItemId,
  PayloadData? payload,
  ChatSourceState? sourceState,
  ChatDeliveryKind delivery = ChatDeliveryKind.foreground,
}) => ChatAtom(
  id: id,
  source: from,
  sourceOrder: order,
  kind: kind,
  delivery: delivery,
  sourceState: sourceState,
  completionItemId: terminal ? completionItemId ?? id : null,
  completionSeq: seq,
  lifecycle: terminal
      ? const TerminalChatAtom(
          started: null,
          ended: null,
          outcome: ChatTerminalOutcome.completed,
        )
      : const ActiveChatAtom(started: null, status: ChatActiveStatus.running),
  contents: const [],
  payload: payload,
);
ChatSourceState state({
  ChatSourceId from = source,
  bool ended = false,
  bool unknown = false,
}) => ChatSourceState(
  source: from,
  started: null,
  ended: null,
  lifecycle: unknown
      ? const UnknownChatSource()
      : ended
      ? const EndedChatSource(outcome: ChatTerminalOutcome.completed)
      : const ActiveChatSource(),
);
ChatBatch page(
  List<ChatAtom> atoms, {
  ChatPlacement placement = ChatPlacement.append,
  List<ChatSourceState> sources = const [],
  CurrentProjection? current,
  String? before,
}) => ChatBatch(
  placement: placement,
  entries: [
    ...sources.map(ChatSourceEntry.new),
    ...atoms.map(ChatAtomEntry.new),
  ],
  current: current,
  before: before,
);
void main() {
  late InMemoryChatController controller;
  late TimelineMessageController owner;
  TimelineDisplayUnit unit(Message message) =>
      message.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit;
  setUp(() {
    controller = InMemoryChatController();
    owner = TimelineMessageController(
      controller,
      generation: 1,
      imageResources: TimelineImageResources(threadId: 'thread'),
      displayDemand: const ReadDemand(maxItems: 2, maxBytes: 32768),
    );
  });
  tearDown(() {
    owner.dispose();
    controller.dispose();
  });

  for (final emptySeparator in [false, true]) {
    test(
      'R1 recovery EOF keeps a later-completed ${emptySeparator ? 'empty ' : ''}text separator',
      () async {
        ChatAtom recoveryAtom(int order, {int? seq, bool ended = false}) =>
            part(
              'a$order',
              order * 10,
              seq: seq,
              terminal: seq != null,
              completionItemId: 'original-payload-$order',
              sourceState: state(ended: ended),
              kind: order.isEven ? ChatAtomKind.text : ChatAtomKind.reasoning,
              payload: seq == null
                  ? null
                  : InlinePayload(
                      bytes: utf8.encode(
                        jsonEncode({
                          'contract': 'anywork.chat/1',
                          'type': order.isEven ? 'text' : 'thinking',
                          'data': {},
                          'bodies': [
                            {
                              'key': 'body',
                              'byteLength': emptySeparator && order == 4
                                  ? 0
                                  : 3,
                              'inline': emptySeparator && order == 4
                                  ? []
                                  : [97, 98, 99],
                            },
                          ],
                        }),
                      ),
                    ),
            );
        var maxWire = 0;
        Future<void> apply(
          List<ChatAtom> atoms, {
          ChatPlacement placement = ChatPlacement.append,
          String? before,
          Object? range,
        }) async {
          final batch = page(atoms, placement: placement, before: before);
          final bytes = utf8
              .encode(
                jsonEncode({
                  'placement': placement.name,
                  'entries': batch.entries.map(chatEntryToJson).toList(),
                  'before': before,
                  'current': null,
                }),
              )
              .length;
          maxWire = bytes > maxWire ? bytes : maxWire;
          expect(batch.entries.length, lessThanOrEqualTo(2));
          expect(bytes, lessThanOrEqualTo(32768));
          await owner.applyBatch(batch, windowRange: range);
          expect(owner.retainedCompletedBudget.$1, lessThanOrEqualTo(2));
          expect(owner.retainedCompletedBudget.$2, lessThanOrEqualTo(32768));
        }

        await apply([], placement: ChatPlacement.set, before: 'H0');
        for (var order = 1; order <= 6; order++) {
          await apply([recoveryAtom(order)]);
        }
        const completedOrders = [2, 3, 5, 4, 6, 1];
        for (var seq = 1; seq <= completedOrders.length; seq++) {
          await apply([
            recoveryAtom(completedOrders[seq - 1], seq: seq, ended: seq == 6),
          ]);
        }
        expect(controller.messages.map((m) => unit(m).members.single.id), [
          'a1',
          'a4',
          'a6',
        ]);
        final stable = {
          for (final message in controller.messages) message.id: message,
        };
        final range = owner.recoveryRange!;
        expect((range.$2, range.$3), (1, 3));
        await apply(
          [
            recoveryAtom(3, seq: 2, ended: true),
            recoveryAtom(5, seq: 3, ended: true),
          ],
          placement: ChatPlacement.prepend,
          before: 'continue-original-fixed-cut',
          range: range.$1,
        );
        expect(controller.messages.map((m) => unit(m).members.single.id), [
          'a1',
          'a3',
          'a4',
          'a5',
          'a6',
        ]);
        await apply(
          [recoveryAtom(2, seq: 1, ended: true)],
          placement: ChatPlacement.prepend,
          range: range.$1,
        );
        owner.finishRecovery(range.$1);
        expect(
          controller.messages
              .map((m) => unit(m).members.map((a) => a.id).join(','))
              .toList(),
          ['a1', 'a2', 'a3', 'a4', 'a5', 'a6'],
        );
        expect(owner.recoveryRange, isNull);
        for (final message in controller.messages) {
          final member = unit(message).members.single;
          expect(
            member.completionItemId,
            'original-payload-${member.id.substring(1)}',
          );
          if (stable.containsKey(message.id)) {
            expect(message, same(stable[message.id]));
          }
        }
        final separator = controller.messages.singleWhere((m) => m.id == 'a4');
        expect(
          ChatItemPresentation.decode(unit(separator).members.single)
              .isKnownEmptyText,
          emptySeparator,
        );
        debugPrint(
          'R1 empty=$emptySeparator maxWire=$maxWire; order=[a1,a2,a3,a4,a5,a6]; pages=2',
        );
      },
    );
  }

  test('one annotated atom is one entry; source Ended never fabricates member terminal', () async {
    expect(part('default', 0).sourceState, isNull);
    final first = page([
      part('R', 1, sourceState: state(ended: true)),
    ], placement: ChatPlacement.set);
    expect(first.entries, hasLength(1));
    await owner.applyBatch(first);
    final key = owner.live.value.single.id;
    expect(controller.messages, isEmpty);
    expect(owner.live.value.single.closedForAdmission, isTrue);
    expect(owner.live.value.single.activeCount, 1);
    expect(
      owner.live.value.single.members.single.lifecycle,
      isA<ActiveChatAtom>(),
    );
    await owner.applyBatch(
      page([part('R', 1, sourceState: state(unknown: true))]),
    );
    expect(owner.live.value.single.sourceLifecycle, isA<EndedChatSource>());
    await owner.applyBatch(page([part('R', 1, sourceState: state())]));
    expect(owner.live.value.single.sourceLifecycle, isA<EndedChatSource>());
    await owner.applyBatch(page([part('R', 1, terminal: true, seq: 1)]));
    expect(controller.messages.single.id, key);
    expect(owner.live.value, isEmpty);
  });

  test('annotations and reliable lifecycle entries share monotonic memory across old pages and windows', () async {
    await owner.applyBatch(
      page(
        [part('R2', 2, terminal: true, seq: 2)],
        placement: ChatPlacement.set,
        sources: [state(ended: true)],
      ),
    );
    final key = controller.messages.single.id;
    await owner.applyBatch(
      page([
        part('R1', 1, terminal: true, seq: 1, sourceState: state()),
      ], placement: ChatPlacement.prepend),
    );
    expect(
      unit(controller.messages.single).sourceLifecycle,
      isA<EndedChatSource>(),
    );
    final historical = unit(controller.messages.single);
    await owner.applyBatch(
      page([
        part(
          'R1',
          1,
          terminal: true,
          seq: 1,
          sourceState: state(unknown: true),
        ),
      ], placement: ChatPlacement.prepend),
      windowIntent: historical.expansion,
    );
    expect(controller.messages.single.id, key);
    expect(
      unit(controller.messages.single).sourceLifecycle,
      isA<EndedChatSource>(),
    );
    expect(unit(controller.messages.single).activeCount, 0);
  });

  test('mismatched source annotation rejects Set before replacing the actual collection', () async {
    await owner.applyBatch(
      page([
        part('R', 1, terminal: true, seq: 1, sourceState: state(ended: true)),
      ], placement: ChatPlacement.set),
    );
    final original = controller.messages.single;
    await expectLater(
      owner.applyBatch(
        page([
          part(
            'bad',
            2,
            sourceState: state(
              from: const ForegroundTurnChatSource(turnId: 'other'),
            ),
          ),
        ], placement: ChatPlacement.set),
      ),
      throwsStateError,
    );
    expect(controller.messages.single, same(original));
    expect(owner.live.value, isEmpty);
  });

  test(
    'member terminal alone stays live; text start does not end reasoning',
    () async {
      await owner.applyBatch(
        page([part('R', 1)], placement: ChatPlacement.set, sources: [state()]),
      );
      final key = owner.live.value.single.id;
      await owner.applyBatch(
        page([part('A', 2, kind: ChatAtomKind.text, terminal: true, seq: 1)]),
      );
      expect(controller.messages, isEmpty);
      expect(owner.live.value.map((unit) => unit.kind), [
        TimelineUnitKind.work,
        TimelineUnitKind.text,
      ]);
      expect(owner.live.value.first.activeCount, 1);
      await owner.applyBatch(page([part('R', 1, terminal: true, seq: 2)]));
      expect(controller.messages.map((message) => unit(message).id), [
        key,
        'A',
      ]);
      expect(owner.live.value, isEmpty);
    },
  );
  test('one Turn presents work A, text A, work B, text B as separate complete units', () async {
    await owner.applyBatch(
      page(
        [part('RA', 1, terminal: true, seq: 1)],
        placement: ChatPlacement.set,
        sources: [state()],
      ),
    );
    final aKey = owner.live.value.single.id;
    await owner.applyBatch(page([part('A', 2, kind: ChatAtomKind.text)]));
    expect(controller.messages.single.id, aKey);
    expect(owner.live.value.single.members.single.id, 'A');
    await owner.applyBatch(
      page([
        part('A', 2, kind: ChatAtomKind.text, terminal: true, seq: 2),
        part('RB', 3, terminal: true, seq: 3, kind: ChatAtomKind.toolCall),
      ]),
    );
    final bKey = owner.live.value.single.id;
    expect(controller.messages.map((message) => unit(message).kind), [
      TimelineUnitKind.work,
      TimelineUnitKind.text,
    ]);
    expect(owner.live.value.single.closedForAdmission, isFalse);
    await owner.applyBatch(
      page([part('B', 4, kind: ChatAtomKind.text, terminal: true, seq: 4)]),
    );
    expect(controller.messages.map((message) => message.id), [
      aKey,
      'A',
      bKey,
      'B',
    ]);
    expect(controller.messages.map((message) => unit(message).kind), [
      TimelineUnitKind.work,
      TimelineUnitKind.text,
      TimelineUnitKind.work,
      TimelineUnitKind.text,
    ]);
    expect(owner.live.value, isEmpty);
  });
  test('real empty text keeps the two work records separate without a rendered empty card', () async {
    final empty = part(
      'empty',
      2,
      kind: ChatAtomKind.text,
      terminal: true,
      seq: 2,
      payload: InlinePayload(
        bytes: utf8.encode(
          jsonEncode({
            'contract': 'anywork.chat/1',
            'type': 'text',
            'data': {'channel': 'final', 'attachments': []},
            'bodies': [],
          }),
        ),
      ),
    );
    await owner.applyBatch(
      page(
        [
          part('R1', 1, terminal: true, seq: 1),
          empty,
          part('R2', 3, terminal: true, seq: 3),
        ],
        placement: ChatPlacement.set,
        sources: [state(ended: true)],
      ),
    );
    expect(controller.messages.map((message) => unit(message).kind), [
      TimelineUnitKind.work,
      TimelineUnitKind.text,
      TimelineUnitKind.work,
    ]);
    expect(controller.messages.first.id, isNot(controller.messages.last.id));
    expect(
      chatItemPresentationOf(controller.messages[1])!.isKnownEmptyText,
      isTrue,
    );
  });
  test('temporarily complete long work converges to bounded props and scalar summary', () async {
    for (var order = 1; order <= 120; order++) {
      await owner.applyBatch(
        page(
          [part('R$order', order, terminal: true, seq: order)],
          placement: order == 1 ? ChatPlacement.set : ChatPlacement.append,
          sources: [state()],
        ),
      );
    }
    expect(controller.messages, isEmpty);
    expect(owner.live.value.single.memberCount, 120);
    expect(owner.live.value.single.members.length, lessThanOrEqualTo(2));
    expect(owner.hasUnmaterialized.value, isTrue);
    expect(
      owner.hasRecoveryDemand,
      isFalse,
      reason: 'An open real source is not an automatic background scan demand',
    );
    await owner.applyBatch(page([], sources: [state(ended: true)]));
    expect(controller.messages, hasLength(1));
    expect(unit(controller.messages.single).memberCount, 120);
  });
  test('a later unfinished part does not keep an earlier released interval blocked', () async {
    await owner.applyBatch(
      page(
        [part('late', 1)],
        placement: ChatPlacement.set,
        sources: [state()],
        before: 'H0',
      ),
    );
    await owner.applyBatch(
      page([
        part('text-2', 2, kind: ChatAtomKind.text, terminal: true, seq: 1),
        part('work-3', 3, terminal: true, seq: 2),
        part('text-4', 4, kind: ChatAtomKind.text, terminal: true, seq: 3),
        part('later-active', 5),
      ]),
    );
    expect(owner.hasRecoveryDemand, isFalse);
    await owner.applyBatch(page([part('late', 1, terminal: true, seq: 4)]));
    expect(owner.hasRecoveryDemand, isTrue);
    expect(
      owner.live.value
          .expand((unit) => unit.members)
          .where((atom) => atom.lifecycle is ActiveChatAtom)
          .map((atom) => atom.id),
      ['later-active'],
    );
  });
  test(
    'all genuine unfinished parts survive a smaller completed props budget',
    () async {
      await owner.applyBatch(
        page(
          [for (var i = 1; i <= 7; i++) part('active-$i', i * 10)],
          placement: ChatPlacement.set,
          sources: [state()],
          before: 'H0',
        ),
      );
      for (var i = 1; i <= 9; i++) {
        await owner.applyBatch(
          page([
            part(
              'complete-$i',
              100 + i * 10,
              kind: i.isEven ? ChatAtomKind.text : ChatAtomKind.reasoning,
              terminal: true,
              seq: i,
            ),
          ]),
        );
      }
      expect(
        owner.live.value
            .expand((unit) => unit.members)
            .where((atom) => atom.lifecycle is ActiveChatAtom),
        hasLength(7),
      );
      expect(owner.retainedCompletedBudget.$1, lessThanOrEqualTo(2));
      expect(owner.retainedCompletedBudget.$2, lessThanOrEqualTo(32768));
    },
  );
  test(
    'ordinary Prepend may insert after the existing row (R then T)',
    () async {
      await owner.applyBatch(
        page(
          [part('R', 1, terminal: true, seq: 2)],
          placement: ChatPlacement.set,
          sources: [state(ended: true)],
          before: 'opaque',
        ),
      );
      final key = unit(controller.messages.single).id;
      await owner.applyBatch(
        page(
          [part('A', 2, kind: ChatAtomKind.text, terminal: true, seq: 1)],
          placement: ChatPlacement.prepend,
          sources: [state(ended: true)],
        ),
      );
      expect(controller.messages.map((message) => message.id), [key, 'A']);
    },
  );
  test(
    'unknown source and empty previews never become an Ended fact',
    () async {
      await owner.applyBatch(
        page(
          [part('R', null, terminal: true, seq: 1)],
          placement: ChatPlacement.set,
          sources: [state(unknown: true)],
        ),
      );
      await owner.applyBatch(
        page(
          [],
          current: CurrentProjection(
            sourceEffectSeq: 2,
            logicalStatus: ThreadStatusView.idle,
            executionPresent: false,
            sources: [state(unknown: true)],
            atoms: const [],
            previews: const [],
            collections: const [],
          ),
        ),
      );
      expect(controller.messages, isEmpty);
      expect(owner.live.value.single.closedForAdmission, isFalse);
    },
  );
  test(
    'background B commits immediately and cold loaded order remains B then T',
    () async {
      const background = BackgroundResultChatSource(messageId: 'B');
      final b = part(
        'B',
        1,
        terminal: true,
        seq: 1,
        from: background,
        delivery: ChatDeliveryKind.independent,
        kind: ChatAtomKind.toolCall,
      );
      final t = part(
        'T',
        1,
        terminal: true,
        seq: 2,
        kind: ChatAtomKind.toolCall,
      );
      await owner.applyBatch(
        page(
          [part('T', 1, kind: ChatAtomKind.toolCall)],
          placement: ChatPlacement.set,
          sources: [state()],
        ),
      );
      await owner.applyBatch(page([b]));
      expect(controller.messages.single.id, 'B');
      expect(owner.live.value.single.activeCount, 1);
      await owner.applyBatch(page([t], sources: [state(ended: true)]));
      expect(controller.messages.map((message) => unit(message).source), [
        background,
        source,
      ]);
      await owner.applyBatch(
        page(
          [t, b],
          placement: ChatPlacement.set,
          sources: [state(ended: true)],
        ),
      );
      expect(controller.messages.map((message) => unit(message).source), [
        background,
        source,
      ]);
    },
  );
  test(
    'unknown gaps do not merge; older text affects its actual loaded position',
    () async {
      await owner.applyBatch(
        page(
          [
            part('R1', 1, terminal: true, seq: 4),
            part('R3', 3, terminal: true, seq: 3),
          ],
          placement: ChatPlacement.set,
          sources: [state(ended: true)],
          before: 'opaque',
        ),
      );
      final keys = controller.messages.map((message) => message.id).toList();
      expect(keys, hasLength(2));
      await owner.applyBatch(
        page(
          [part('A', 2, kind: ChatAtomKind.text, terminal: true, seq: 1)],
          placement: ChatPlacement.prepend,
          sources: [state(ended: true)],
        ),
      );
      expect(controller.messages.map((message) => message.id), [
        keys.first,
        'A',
        keys.last,
      ]);
    },
  );
  test(
    'parallel terminal order does not replace key or stable member order',
    () async {
      await owner.applyBatch(
        page(
          [part('R1', 1), part('R2', 2)],
          placement: ChatPlacement.set,
          sources: [state()],
        ),
      );
      final key = owner.live.value.single.id;
      final intent = owner.live.value.single.expansion;
      intent.setBodyVisible(Object(), true);
      final bodyGeneration = intent.bodyGeneration;
      await owner.applyBatch(
        page([
          part(
            'R2',
            2,
            terminal: true,
            seq: 1,
            completionItemId: 'background-start-receipt',
          ),
        ]),
      );
      expect(owner.live.value.single.id, key);
      expect(owner.live.value.single.members.map((atom) => atom.id), [
        'R1',
        'R2',
      ]);
      expect(
        owner.live.value.single.members.last.completionItemId,
        'background-start-receipt',
      );
      await owner.applyBatch(
        page(
          [part('R1', 1, terminal: true, seq: 2)],
          sources: [state(ended: true)],
        ),
      );
      expect(controller.messages.single.id, key);
      expect(unit(controller.messages.single).expansion, same(intent));
      expect(intent.isRetired, isFalse);
      expect(intent.bodyActive, isTrue);
      expect(intent.bodyGeneration, same(bodyGeneration));
    },
  );
}
