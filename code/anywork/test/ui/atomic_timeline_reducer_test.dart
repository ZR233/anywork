import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

CurrentProjection _current(List<TimelineItem> items) => CurrentProjection(
  sourceEffectSeq: 1, logicalStatus: ThreadStatusView.running,
  executionPresent: true, sources: const [], atoms: const [], items: items,
  previews: const [], collections: const [],
);

void main() {
  late InMemoryChatController controller;
  late TimelineMessageController owner;
  setUp(() {
    controller = InMemoryChatController();
    owner = TimelineMessageController(controller, generation: 1);
  });
  tearDown(() { owner.dispose(); controller.dispose(); });

  test('producer work A / response A / work B / response B are four stable Main messages', () async {
    final a = workItem('work-A');
    final textA = chatMessage('response-A');
    final b = workItem('work-B');
    final textB = chatMessage('response-B');
    await owner.applyBatch(chatBatch([a, textA, b, textB]));
    expect(controller.messages.map((message) => message.id), ['work-A', 'response-A', 'work-B', 'response-B']);
    expect((controller.messages.first.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit).item, same(a));
  });

  test('active group never hides a later current response or fabricates a terminal', () async {
    final group = workItem('R', closed: true, active: 1);
    final response = chatMessage('A');
    await owner.applyBatch(chatBatch([], current: _current([group, response])));
    expect(controller.messages, isEmpty);
    expect(owner.live.value.map((unit) => unit.id), ['R', 'A']);
    expect(owner.live.value.first.item.summary!.activeCount, 1);
    expect(owner.live.value.first.item, same(group));
  });

  test('live to history borrows only same item intent; unrelated current item remains readable', () async {
    await owner.applyBatch(chatBatch([], current: _current([workItem('group', closed: false, active: 1), chatMessage('later')])));
    final intent = owner.live.value.first.expansion..expanded = true;
    await owner.applyBatch(chatBatch([workItem('group')], placement: ChatPlacement.append, current: _current([chatMessage('later')])));
    final history = controller.messages.single.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit;
    expect(history.expansion, same(intent));
    expect(history.expansion.expanded, isTrue);
    expect(history.expansion.isRetired, isFalse);
    expect(owner.live.value.single.id, 'later');
  });

  test('ordinary Prepend does not join adjacent groups even with same source and missing member pages', () async {
    await owner.applyBatch(chatBatch([workItem('newer')], before: 'next'));
    final newer = controller.messages.single;
    await owner.applyBatch(chatBatch([workItem('older')], placement: ChatPlacement.prepend));
    expect(controller.messages.map((message) => message.id), ['older', 'newer']);
    expect(controller.messages.last, same(newer));
    expect(owner.live.value, isEmpty);
  });

  test('Main rejects raw atoms before Set can replace accepted history', () async {
    await owner.applyBatch(chatBatch([chatMessage('accepted')]));
    final accepted = controller.messages.single;
    await expectLater(owner.applyBatch(ChatBatch(placement: ChatPlacement.set,
      entries: [ChatAtomEntry(chatAtomMessage('raw'))],
    )), throwsA(isA<ConversationContinuityError>()));
    expect(controller.messages.single, same(accepted));
  });

  test('current-only publication does not mutate loaded history or infer closing from atom/source facts', () async {
    await owner.applyBatch(chatBatch([chatMessage('loaded')]));
    final loaded = controller.messages.single;
    await owner.applyBatch(chatBatch([], placement: ChatPlacement.append, current: _current([workItem('still-open', closed: false)])));
    expect(controller.messages.single, same(loaded));
    expect(owner.live.value.single.item.admissionClosed, isFalse);
    final retired = owner.live.value.single.expansion;
    await owner.applyBatch(chatBatch([], placement: ChatPlacement.append, current: _current([])));
    expect(retired.isRetired, isTrue);
  });
}
