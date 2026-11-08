import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_member_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/completion_fixtures.dart';

void main() {
  late InMemoryChatController stock;
  late TimelineMemberController adapter;
  late List<ChatOperation> operations;
  late StreamSubscription<ChatOperation> observed;
  setUp(() {
    stock = InMemoryChatController();
    adapter = TimelineMemberController(stock);
    operations = [];
    observed = stock.operationsStream.listen(operations.add);
  });
  tearDown(() async {
    adapter.dispose();
    await observed.cancel();
    stock.dispose();
  });

  test('members use record IDs; prepend and append preserve existing message objects', () async {
    await adapter.applyBatch(
      completedBatch([
        completionEntry('middle', 2, presentation: MainPresentation.single),
      ], through: 2),
    );
    final message = stock.messages.single;
    await adapter.applyBatch(
      completedBatch(
        [completionEntry('older', 1, presentation: MainPresentation.single)],
        placement: ChatPlacement.prepend,
        through: 2,
      ),
    );
    await adapter.applyBatch(
      completedBatch(
        [completionEntry('newer', 3, presentation: MainPresentation.single)],
        placement: ChatPlacement.append,
        from: 2,
      ),
    );
    expect(stock.messages.map((value) => value.id), [
      'older',
      'middle',
      'newer',
    ]);
    expect(stock.messages[1], same(message));
    expect(
      chatItemPresentationOf(stock.messages.first)!.atom!.id,
      'atom:older',
    );
  });

  test(
    'completed members cannot be updated by replay or repeated within a page',
    () async {
      final entry = completionEntry('member', 1);
      await adapter.applyBatch(completedBatch([entry]));
      await expectLater(
        adapter.applyBatch(
          completedBatch([entry], placement: ChatPlacement.prepend, through: 1),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
      await expectLater(
        adapter.applyBatch(completedBatch([entry, entry])),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(stock.messages.single.id, 'member');
    },
  );

  test('an empty checked prefix produces no component operation and still permits the next Append', () async {
    await adapter.applyBatch(completedBatch([]));
    await Future<void>.delayed(Duration.zero);
    operations.clear();
    await adapter.applyBatch(
      completedBatch([], placement: ChatPlacement.append, from: 0, through: 5),
    );
    await Future<void>.delayed(Duration.zero);
    expect(operations, isEmpty);
    await adapter.applyBatch(
      completedBatch(
        [completionEntry('after-hidden', 6)],
        placement: ChatPlacement.append,
        from: 5,
      ),
    );
    expect(stock.messages.single.id, 'after-hidden');
  });

  test(
    'members accept Activity without history and stop after retirement',
    () async {
      await adapter.applyActivity(
        ActivitySnapshot(
          revision: 1,
          completedThrough: 0,
          executionPresent: true,
          entries: const [],
        ),
      );
      adapter.dispose();
      await expectLater(
        adapter.applyActivity(
          ActivitySnapshot(
            revision: 2,
            completedThrough: 0,
            executionPresent: false,
            entries: const [],
          ),
        ),
        throwsA(isA<StaleConversationScope>()),
      );
      await expectLater(
        adapter.applyBatch(completedBatch([])),
        throwsA(isA<StaleConversationScope>()),
      );
    },
  );
}
