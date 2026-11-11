import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display_fixtures.dart';

void main() {
  late InMemoryChatController stock;
  late TimelineMessageController adapter;
  late StreamSubscription<ChatOperation> subscription;
  late List<ChatOperation> operations;
  final intents = <String, TimelineExpansionIntent>{};
  setUp(() {
    intents.clear();
    stock = InMemoryChatController();
    operations = [];
    subscription = stock.operationsStream.listen(operations.add);
    adapter = TimelineMessageController(
      stock,
      generation: 1,
      expansionForBlock: (id) =>
          intents.putIfAbsent(id, TimelineExpansionIntent.new),
    );
  });
  tearDown(() async {
    adapter.dispose();
    await subscription.cancel();
    stock.dispose();
  });
  TimelineDisplayUnit unit(int index) =>
      stock.messages[index].metadata![timelineDisplayUnitKey]
          as TimelineDisplayUnit;

  test('a frozen 100000-member block is one synchronous Main operation without members', () async {
    final accepted = adapter.applyTimeline(
      displayBatch([displayWork('large', 3, total: 100000)]),
    );
    expect(
      stock.messages.single.id,
      'large',
      reason: 'mutation precedes Future/paint',
    );
    expect(unit(0).summary!.total, 100000);
    expect(unit(0).expansion.members, isNull);
    await accepted;
    await Future<void>.delayed(Duration.zero);
    expect(operations.single.type, ChatOperationType.set);
    expect(operations.single.animated, isFalse);
  });

  test(
    'Set/Prepend/Append each batch once and never update an old tail block',
    () async {
      await adapter.applyTimeline(displayBatch([displayWork('middle', 3)]));
      await adapter.applyTimeline(
        displayBatch(
          [displayWork('old-a', 1), displayWork('old-b', 2)],
          placement: ChatPlacement.prepend,
          through: 3,
        ),
      );
      final oldTail = stock.messages.last;
      await adapter.applyTimeline(
        displayBatch(
          [displayWork('next-a', 4), displayWork('next-b', 5)],
          placement: ChatPlacement.append,
          from: 3,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(stock.messages.map((message) => message.id), [
        'old-a',
        'old-b',
        'middle',
        'next-a',
        'next-b',
      ]);
      expect(stock.messages[2], same(oldTail));
      expect(operations.map((operation) => operation.type), [
        ChatOperationType.set,
        ChatOperationType.insertAll,
        ChatOperationType.insertAll,
      ]);
    },
  );

  test(
    'pure live changes perform no history enumeration or component operation',
    () async {
      final reads = _ReadCounter();
      final controller = TimelineMessageController(reads, generation: 1);
      await controller.applyTimeline(displayBatch([displayWork('first', 1)]));
      reads.reads = 0;
      await controller.applyTimeline(
        displayBatch(
          [],
          placement: ChatPlacement.append,
          from: 1,
          through: 1,
          live: LiveDisplayWindow(
            revision: 2,
            historyThrough: 1,
            executionPresent: true,
            blocks: [],
          ),
        ),
      );
      expect(reads.reads, 0);
      controller.dispose();
      reads.dispose();
    },
  );

  test('handoff borrows the exact live disclosure identity and keeps expansion intent', () async {
    final intent = intents.putIfAbsent('work', TimelineExpansionIntent.new);
    intent.expanded = true;
    await adapter.applyTimeline(displayBatch([displayWork('work', 1)]));
    expect(unit(0).expansion, same(intent));
    expect(unit(0).expansion.expanded, isTrue);
    expect(
      unit(0).memberReference,
      const DisplayBlockRef(databaseId: 'db', blockId: 'work'),
    );
  });

  test('invalid cuts reject synchronously before touching Main', () async {
    await adapter.applyTimeline(displayBatch([displayWork('work', 1)]));
    final original = stock.messages.single;
    expect(
      () => adapter.applyTimeline(
        displayBatch(
          [displayWork('invalid', 2)],
          placement: ChatPlacement.append,
          from: 0,
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(stock.messages.single, same(original));
    expect(
      () => adapter.applyTimeline(
        displayBatch(
          [displayWork('overlap', 1)],
          placement: ChatPlacement.prepend,
          through: 1,
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
  });

  test(
    'cross-batch duplicate IDs reject synchronously for Append and Prepend',
    () async {
      await adapter.applyTimeline(displayBatch([displayWork('existing', 3)]));
      final original = stock.messages.single;
      final current = intents['existing']!.current;
      for (final batch in [
        displayBatch(
          [displayWork('existing', 4)],
          placement: ChatPlacement.append,
          from: 3,
        ),
        displayBatch(
          [displayWork('existing', 2)],
          placement: ChatPlacement.prepend,
          through: 3,
        ),
      ]) {
        expect(
          () => adapter.applyTimeline(batch),
          throwsA(isA<ConversationContinuityError>()),
        );
        expect(stock.messages.single, same(original));
        expect(intents['existing']!.current, same(current));
        expect(intents['existing']!.isRetired, isFalse);
      }
      await adapter.applyTimeline(
        displayBatch(
          [displayWork('valid', 4)],
          placement: ChatPlacement.append,
          from: 3,
        ),
      );
      expect(stock.messages.map((message) => message.id), [
        'existing',
        'valid',
      ]);
    },
  );

  for (final placement in ChatPlacement.values) {
    test(
      'failed component Future for ${placement.name} preserves position, Main and shared intent until a correct retry',
      () async {
        final component = _FailingComponent();
        final created = <String>[];
        final retired = <String>[];
        final localIntents = <String, TimelineExpansionIntent>{};
        final projection = TimelineMessageController(
          component,
          generation: 2,
          expansionForBlock: (id) =>
              localIntents.putIfAbsent(id, TimelineExpansionIntent.new),
          onUnitCreated: (unit) => created.add(unit.id),
          onUnitRetired: (unit) => retired.add(unit.id),
        );
        await projection.applyTimeline(displayBatch([displayWork('old', 3)]));
        final old = component.messages.single;
        final oldUnit = localIntents['old']!.current!;
        final pendingIntent = localIntents.putIfAbsent(
          'next',
          TimelineExpansionIntent.new,
        )..expanded = true;
        final liveUnit = TimelineDisplayUnit(
          block: displayWork('next', 1),
          expansion: pendingIntent,
        );
        pendingIntent.current = liveUnit;
        final gate = Completer<void>();
        component.failure = gate.future;
        final batch = switch (placement) {
          ChatPlacement.set => displayBatch([displayWork('next', 5)]),
          ChatPlacement.prepend => displayBatch(
            [displayWork('next', 2)],
            placement: placement,
            through: 3,
          ),
          ChatPlacement.append => displayBatch(
            [displayWork('next', 4)],
            placement: placement,
            from: 3,
          ),
        };
        final applying = projection.applyTimeline(batch);
        final failure = StateError('component failed asynchronously');
        final rejected = expectLater(applying, throwsA(same(failure)));
        expect(pendingIntent.current, same(liveUnit));
        expect(created, ['old']);
        expect(retired, isEmpty);
        gate.completeError(failure);
        await rejected;
        expect(component.messages.single, same(old));
        expect(localIntents['old']!.current, same(oldUnit));
        expect(oldUnit.expansion.isRetired, isFalse);
        expect(pendingIntent.current, same(liveUnit));
        expect(pendingIntent.expanded, isTrue);
        expect(created, ['old']);
        expect(retired, isEmpty);
        component.failure = null;
        await projection.applyTimeline(
          displayBatch(
            [displayWork('next', 4)],
            placement: ChatPlacement.append,
            from: 3,
          ),
        );
        expect(component.messages.map((message) => message.id), [
          'old',
          'next',
        ]);
        expect(pendingIntent.current!.historyPos, 4);
        expect(pendingIntent.expanded, isTrue);
        expect(created, ['old', 'next']);
        expect(retired, isEmpty);
        projection.dispose();
        component.dispose();
      },
    );
  }
}

class _FailingComponent extends InMemoryChatController {
  Future<void>? failure;
  @override
  Future<void> setMessages(List<Message> messages, {bool animated = true}) =>
      failure ?? super.setMessages(messages, animated: animated);
  @override
  Future<void> insertAllMessages(
    List<Message> messages, {
    int? index,
    bool animated = true,
  }) =>
      failure ??
      super.insertAllMessages(messages, index: index, animated: animated);
}

class _ReadCounter extends InMemoryChatController {
  int reads = 0;
  @override
  List<Message> get messages {
    reads++;
    return super.messages;
  }
}
