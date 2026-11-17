import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_member_controller.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/display_member_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/completion_fixtures.dart';

const _block = DisplayBlockRef(databaseId: 'db', blockId: 'work');
DisplayMemberHead _head(int order, {String? text}) => DisplayMemberHead(
  memberKey: 'row-$order',
  memberOrder: order,
  record: DisplayRecord(
    contentSource: const CurrentAtom(),
    atom: ChatAtom(
      id: 'atom-$order',
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      sourceOrder: order,
      kind: ChatAtomKind.raw,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const ActiveChatAtom(
        started: null,
        status: ChatActiveStatus.running,
      ),
      contents: const [],
      payload: InlinePayload(bytes: (text ?? 'row-$order').codeUnits),
    ),
  ),
);

DisplayMemberBatch _page(List<DisplayMemberHead> rows, {int revision = 1}) =>
    DisplayMemberBatch(
      offset: 0,
      complete: true,
      block: _block,
      revision: revision,
      sealed: false,
      entries: rows,
    );

class _Members implements DisplayMembers {
  final _queue = <DisplayMemberBatch>[];
  Completer<DisplayMemberBatch?>? pending;
  bool closed = false;
  void send(DisplayMemberBatch page) {
    final next = pending;
    pending = null;
    if (next == null) {
      _queue.add(page);
    } else {
      next.complete(page);
    }
  }

  @override
  Future<DisplayMemberBatch?> next() => closed
      ? Future.value()
      : _queue.isNotEmpty
      ? Future.value(_queue.removeAt(0))
      : (pending = Completer<DisplayMemberBatch?>()).future;
  @override
  void requestClose() {
    closed = true;
    pending?.complete(null);
    pending = null;
  }

  @override
  Future<void> close() async {
    requestClose();
  }
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  test('display rows notify only changed observable values, not the list structure', () async {
    final handle = _Members();
    final controller = DisplayMemberController(
      reference: _block,
      demand: const ReadDemand(maxItems: 3, maxBytes: 8192),
      open: (_, _) async => handle,
    );
    addTearDown(controller.close);
    handle.send(_page([_head(1), _head(2)]));
    await _drain();
    var structure = 0;
    var first = 0;
    var second = 0;
    controller.addListener(() => structure++);
    controller.member('row-1').addListener(() => first++);
    controller.member('row-2').addListener(() => second++);
    final disclosure = controller.disclosure('row-2')..expanded = true;
    handle.send(_page([_head(1, text: 'changed'), _head(2)], revision: 2));
    await _drain();
    expect((structure, first, second), (0, 1, 0));
    expect(controller.disclosure('row-2'), same(disclosure));
    expect(disclosure.expanded, isTrue);
    handle.send(_page([_head(1, text: 'changed'), _head(2)], revision: 3));
    await _drain();
    expect((structure, first, second), (0, 1, 0));
  });

  test('complete updates retain early rows and disclosure when later members arrive', () async {
    final handle = _Members();
    var opens = 0;
    final controller = DisplayMemberController(
      reference: _block,
      demand: const ReadDemand(maxItems: 32, maxBytes: 8192),
      open: (_, _) async {
        opens++;
        return handle;
      },
    );
    addTearDown(controller.close);
    handle.send(_page([for (var i = 1; i <= 15; i++) _head(i)]));
    await _drain();
    final intent = controller.disclosure('row-5')..expanded = true;
    handle.send(_page([for (var i = 1; i <= 19; i++) _head(i)], revision: 2));
    await _drain();
    expect(controller.entries.map((e) => e.memberOrder), [
      for (var i = 1; i <= 19; i++) i,
    ]);
    expect(controller.disclosure('row-5'), same(intent));
    expect(intent.expanded, isTrue);
    expect(opens, 1);
    expect(handle.closed, isFalse);
  });

  test('a late opened display reader is closed after retirement and never publishes', () async {
    final opened = Completer<DisplayMembers>();
    final controller = DisplayMemberController(
      reference: _block,
      demand: const ReadDemand(maxItems: 3, maxBytes: 8192),
      open: (_, _) => opened.future,
    );
    await _drain();
    controller.retire();
    var joined = false;
    final closing = controller.close().then((_) => joined = true);
    await _drain();
    expect(
      joined,
      isFalse,
      reason: 'Close joins an in-flight reader acquisition',
    );
    final handle = _Members()..send(_page([_head(1)]));
    opened.complete(handle);
    await closing;
    expect(joined, isTrue);
    expect(controller.hasSnapshot, isFalse);
    expect(handle.closed, isTrue);
  });

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
      completedBatch([completionEntry('middle', 2, isText: true)], through: 2),
    );
    final message = stock.messages.single;
    await adapter.applyBatch(
      completedBatch(
        [completionEntry('older', 1, isText: true)],
        placement: ChatPlacement.prepend,
        through: 2,
      ),
    );
    await adapter.applyBatch(
      completedBatch(
        [completionEntry('newer', 3, isText: true)],
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
