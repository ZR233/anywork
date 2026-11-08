import 'dart:async';
import 'dart:collection';

import 'package:anywork/src/features/conversation/timeline/state/completion_run_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_member_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/completion_fixtures.dart';

void main() {
  late _CountingController stock;
  late TimelineMessageController adapter;
  late List<ChatOperation> operations;
  late StreamSubscription<ChatOperation> subscription;
  setUp(() {
    stock = _CountingController();
    adapter = TimelineMessageController(stock, generation: 1);
    operations = [];
    subscription = stock.operationsStream.listen(operations.add);
  });
  tearDown(() async {
    adapter.dispose();
    await subscription.cancel();
    stock.dispose();
  });
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  TimelineDisplayUnit unit(int index) =>
      stock.messages[index].metadata![timelineDisplayUnitKey]
          as TimelineDisplayUnit;

  test(
    'Set uses one operation and Prepend accepts complete representatives',
    () async {
      await adapter.applyBatch(
        completedBatch(
          [completionEntry('latest', 20, start: 10, ordinal: 9)],
          through: 25,
          before: 'older',
        ),
      );
      await flush();
      expect(operations.single.type, ChatOperationType.set);
      expect(operations.single.animated, isFalse);
      final latest = stock.messages.single;
      await adapter.applyBatch(
        completedBatch(
          [
            completionEntry('first', 5, start: 1, ordinal: 4),
            completionEntry('text', 8, presentation: MainPresentation.single),
          ],
          placement: ChatPlacement.prepend,
          through: 25,
        ),
      );
      expect(stock.messages, hasLength(3));
      expect(stock.messages.last, same(latest));
      expect(unit(0).entry.run!.ordinal, 4);
      expect(unit(2).entry.run!.ordinal, 9);
    },
  );

  test(
    'B → text → A preserves completion order without source reordering',
    () async {
      await adapter.applyBatch(completedBatch([]));
      await adapter.applyBatch(
        completedBatch(
          [
            completionEntry('B', 1),
            completionEntry('body', 2, presentation: MainPresentation.single),
            completionEntry('A', 3),
          ],
          placement: ChatPlacement.append,
          from: 0,
        ),
      );
      expect(
        [for (var i = 0; i < 3; i++) unit(i).entry.recordId],
        ['B', 'body', 'A'],
      );
      expect(stock.messages.map((message) => message.id).toSet(), hasLength(3));
    },
  );

  test('adjacent Append updates only the tail and preserves disclosure and member scope', () async {
    await adapter.applyBatch(
      completedBatch([
        for (var i = 1; i <= 1000; i++) completionEntry('row-$i', i),
      ]),
    );
    final before = stock.messages[998];
    final original = unit(999);
    original.expansion.expanded = true;
    original.expansion.setBodyVisible(Object(), true);
    final bodyGeneration = original.expansion.bodyGeneration;
    await flush();
    operations.clear();
    stock.resetCounts();
    await adapter.applyBatch(
      completedBatch(
        [completionEntry('grown', 1001, start: 1000, ordinal: 2)],
        placement: ChatPlacement.append,
        from: 1000,
      ),
    );
    await flush();
    expect(stock.iterations, 0);
    expect(operations.single.type, ChatOperationType.update);
    expect(stock.messages, hasLength(1000));
    expect(stock.messages[998], same(before));
    expect(unit(999).id, original.id);
    expect(unit(999).expansion, same(original.expansion));
    expect(unit(999).expansion.bodyGeneration, same(bodyGeneration));
    expect(unit(999).expansion.expanded, isTrue);
    final card =
        stock.messages.last.metadata![completionRunPresentationKey]
            as CompletionRunPresentation;
    expect(card.representative.run!.ordinal, 2);
  });

  test('empty Append and Activity perform zero historical enumeration or operations', () async {
    await adapter.applyBatch(completedBatch([completionEntry('first', 1)]));
    await flush();
    operations.clear();
    stock.resetCounts();
    await adapter.applyBatch(
      completedBatch([], placement: ChatPlacement.append, from: 1, through: 5),
    );
    await adapter.applyActivity(
      ActivitySnapshot(
        revision: 1,
        completedThrough: 5,
        executionPresent: true,
        entries: const [],
      ),
    );
    await flush();
    expect(stock.iterations, 0);
    expect(stock.reads, 0);
    expect(operations, isEmpty);
  });

  test(
    'return to a non-tail Run and decreasing ordinal fail without mutation',
    () async {
      await adapter.applyBatch(
        completedBatch([
          completionEntry('first', 1),
          completionEntry('second', 2),
        ]),
      );
      for (final entry in [
        completionEntry('old-run', 3, start: 1, ordinal: 2),
        completionEntry('backwards', 3, start: 2, ordinal: 1),
        completionEntry('missing-run-head', 4, start: 3, ordinal: 2),
      ]) {
        await expectLater(
          adapter.applyBatch(
            completedBatch([entry], placement: ChatPlacement.append, from: 2),
          ),
          throwsA(isA<ConversationContinuityError>()),
        );
      }
      expect(stock.messages, hasLength(2));
    },
  );

  test(
    'independent Run members cannot overwrite Main total and reject replay',
    () async {
      await adapter.applyBatch(
        completedBatch([completionEntry('head', 99, start: 1, ordinal: 80)]),
      );
      final members = InMemoryChatController();
      final reader = TimelineMemberController(members);
      await reader.applyBatch(
        completedBatch([
          completionEntry('member', 98, start: 1, ordinal: 79),
        ], through: 99),
      );
      expect(unit(0).entry.run!.ordinal, 80);
      await expectLater(
        reader.applyBatch(
          completedBatch(
            [completionEntry('member', 98)],
            placement: ChatPlacement.prepend,
            through: 99,
          ),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(members.messages.single.id, 'member');
      reader.dispose();
      members.dispose();
    },
  );
}

final class _CountingController extends InMemoryChatController {
  int iterations = 0;
  int reads = 0;
  void resetCounts() {
    iterations = 0;
    reads = 0;
  }

  @override
  List<Message> get messages => _CountingList(super.messages, this);
}

final class _CountingList extends ListBase<Message> {
  _CountingList(this.source, this.owner);
  final List<Message> source;
  final _CountingController owner;
  @override
  int get length => source.length;
  @override
  set length(int value) => source.length = value;
  @override
  Message operator [](int index) {
    owner.reads++;
    return source[index];
  }

  @override
  void operator []=(int index, Message value) => source[index] = value;
  @override
  Iterator<Message> get iterator {
    owner.iterations++;
    return super.iterator;
  }
}
