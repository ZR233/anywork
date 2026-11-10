import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/realtime_background_observation.dart';
import '../support/display_fixtures.dart';

TimelineDisplayUnit _single({
  String blockId = 'background-block',
  String turnId = 'turn',
  String callId = 'call',
  ChatSourceId source = const BackgroundResultChatSource(messageId: 'message'),
  ChatDeliveryKind delivery = ChatDeliveryKind.independent,
  ChatTerminalOutcome outcome = ChatTerminalOutcome.completed,
  String atomCompletionId = 'completion',
  int? completionSeq = 7,
}) => TimelineDisplayUnit(
  block: DisplayBlock(
    id: blockId,
    historyPos: 2,
    body: SingleDisplayBlock(
      record: DisplayRecord(
        atom: ChatAtom(
          id: 'background-message-atom',
          completionItemId: atomCompletionId,
          completionSeq: completionSeq,
          source: source,
          sourceOrder: 1,
          kind: ChatAtomKind.toolCall,
          delivery: delivery,
          lifecycle: TerminalChatAtom(
            started: null,
            ended: null,
            outcome: outcome,
          ),
          turnId: turnId,
          tool: ChatToolIdentity(callId: callId, name: 'exec'),
          contents: const [],
          payload: const DeferredPayload(
            reference: ContentRef(
              databaseId: 'db',
              target: ItemPayloadTarget(itemId: 'completion'),
            ),
            byteLength: 1024,
          ),
        ),
        contentSource: CompletedOriginal(completionId: 'completion'),
      ),
    ),
  ),
);

TimelineDisplayUnit? _select(Iterable<TimelineDisplayUnit> main) =>
    realtimeBackgroundSingle(main, turnId: 'turn', callId: 'call');

void main() {
  testWidgets(
    'loaded Main Single is missed by Work-only but precisely selected',
    (tester) async {
      final controller = InMemoryChatController();
      final adapter = TimelineMessageController(controller, generation: 1);
      addTearDown(() {
        adapter.dispose();
        controller.dispose();
      });
      final single = _single();
      await adapter.applyTimeline(
        displayBatch([
          displayWork('unrelated-work', 1),
          DisplayBlock(id: single.id, historyPos: 2, body: single.body),
        ]),
      );
      final main = controller.messages
          .map(
            (message) =>
                message.metadata![timelineDisplayUnitKey]
                    as TimelineDisplayUnit,
          )
          .toList();
      final oldCandidates = main.where((unit) => unit.body is WorkDisplayBlock);
      expect(oldCandidates.any((unit) => unit.id == single.id), isFalse);
      final selected = _select(main)!;
      expect(selected, same(main.last));
      expect(selected.atom!.id, 'background-message-atom');
      expect(selected.id, isNot(selected.atom!.id));
      expect(selected.memberReference, isNull);
      expect(selected.atom!.completionItemId, 'completion');
      expect(selected.atom!.completionSeq, 7);
      expect(
        ChatItemPresentation.forUnit(selected).compatibility,
        ChatItemCompatibility.deferred,
      );
      expect(main.first.summary!.total, 3);
      expect(controller.messages, hasLength(2));
    },
  );

  test('unrelated turn, call and foreground source are not accepted', () {
    expect(
      _select([
        _single(turnId: 'other-turn'),
        _single(callId: 'other-call'),
        _single(source: const ForegroundTurnChatSource(turnId: 'turn')),
      ]),
      isNull,
    );
  });

  final invalid = <String, TimelineDisplayUnit>{
    'empty background message identity': _single(
      source: const BackgroundResultChatSource(messageId: ''),
    ),
    'foreground delivery': _single(delivery: ChatDeliveryKind.foreground),
    'failed instead of completed terminal': _single(
      outcome: ChatTerminalOutcome.failed,
    ),
    'different completion identity': _single(
      atomCompletionId: 'other-completion',
    ),
    'missing completion sequence': _single(completionSeq: null),
  };
  for (final entry in invalid.entries) {
    test('matching Single rejects ${entry.key}', () {
      expect(() => _select([entry.value]), throwsA(isA<TestFailure>()));
    });
  }

  test(
    'duplicate exact background Singles fail rather than choosing first',
    () {
      expect(
        () => _select([_single(), _single(blockId: 'duplicate-block')]),
        throwsA(isA<TestFailure>()),
      );
    },
  );
}
