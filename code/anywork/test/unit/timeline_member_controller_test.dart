import 'dart:collection';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_member_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

void main() {
  test('large member page indexes loaded IDs once and updates repeated activity in place', () async {
    final controller = _CountingController();
    final adapter = TimelineMemberController(controller);
    await adapter.applyBatch(
      ChatBatch(
        placement: ChatPlacement.set,
        entries: [
          for (var i = 0; i < 2000; i++)
            ChatAtomEntry(chatAtomMessage('member-$i')),
        ],
      ),
    );
    final originalNeighbor = controller.messages[1998];
    controller.resetAccessCounts();
    final firstUpdate = chatAtomMessage('member-1999', body: 'running');
    final secondUpdate = chatAtomMessage('member-1999', body: 'complete');
    await adapter.applyBatch(
      ChatBatch(
        placement: ChatPlacement.append,
        entries: [
          ChatAtomEntry(firstUpdate),
          ChatAtomEntry(secondUpdate),
          ChatAtomEntry(chatAtomMessage('page-next')),
        ],
      ),
    );
    expect(controller.iterations, 1);
    expect(controller.elementReads, 2000);
    expect(controller.messages, hasLength(2001));
    expect(controller.messages[1998], same(originalNeighbor));
    expect(controller.messages.map((message) => message.id).last, 'page-next');
    expect(
      chatItemPresentationOf(controller.messages[1999])!.atom,
      same(secondUpdate),
    );
    adapter.dispose();
    controller.dispose();
  });

  for (final placement in [ChatPlacement.append, ChatPlacement.prepend]) {
    test(
      '$placement keeps first insertion position and latest same-batch value',
      () async {
        final controller = InMemoryChatController();
        final adapter = TimelineMemberController(controller);
        await adapter.applyBatch(
          ChatBatch(
            placement: ChatPlacement.set,
            entries: [ChatAtomEntry(chatAtomMessage('base'))],
          ),
        );
        final running = chatAtomMessage('new', body: 'running');
        final neighbor = chatAtomMessage('neighbor');
        final complete = chatAtomMessage('new', body: 'complete');
        await adapter.applyBatch(
          ChatBatch(
            placement: placement,
            entries: [
              ChatAtomEntry(running),
              ChatAtomEntry(neighbor),
              ChatAtomEntry(complete),
            ],
          ),
        );
        expect(
          controller.messages.map((message) => message.id),
          placement == ChatPlacement.append
              ? ['base', 'new', 'neighbor']
              : ['new', 'neighbor', 'base'],
        );
        final updated = placement == ChatPlacement.append
            ? controller.messages[1]
            : controller.messages[0];
        expect(chatItemPresentationOf(updated)!.atom, same(complete));
        adapter.dispose();
        controller.dispose();
      },
    );
  }
  test('a real terminal updates the same member only, without duplicating identity or moving its neighbours', () async {
    final controller = InMemoryChatController();
    final adapter = TimelineMemberController(controller);
    final running = ChatAtom(
      id: 'tool',
      source: const ForegroundTurnChatSource(turnId: 'T'),
      sourceOrder: 2,
      kind: ChatAtomKind.toolCall,
      delivery: ChatDeliveryKind.foreground,
      tool: const ChatToolIdentity(callId: 'call', name: 'read_image'),
      lifecycle: const ActiveChatAtom(
        started: null,
        status: ChatActiveStatus.running,
      ),
      contents: const [],
    );
    await adapter.applyBatch(
      ChatBatch(
        placement: ChatPlacement.set,
        entries: [
          ChatAtomEntry(chatAtomMessage('before')),
          ChatAtomEntry(running),
          ChatAtomEntry(chatAtomMessage('after')),
        ],
      ),
    );
    final before = controller.messages.first;
    final after = controller.messages.last;
    final terminal = ChatAtom(
      id: 'tool',
      source: running.source,
      sourceOrder: 2,
      kind: ChatAtomKind.toolCall,
      delivery: ChatDeliveryKind.foreground,
      tool: running.tool,
      lifecycle: const TerminalChatAtom(
        started: null,
        ended: null,
        outcome: ChatTerminalOutcome.failed,
      ),
      contents: const [],
    );
    await adapter.applyBatch(
      ChatBatch(
        placement: ChatPlacement.append,
        entries: [ChatAtomEntry(terminal)],
      ),
    );
    expect(controller.messages.map((message) => message.id), [
      'before',
      'tool',
      'after',
    ]);
    expect(controller.messages.first, same(before));
    expect(controller.messages.last, same(after));
    final atom = chatItemPresentationOf(controller.messages[1])!.atom!;
    expect(atom, same(terminal));
    expect(
      (atom.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.failed,
    );
    adapter.dispose();
    controller.dispose();
  });

  test(
    'Main item cannot enter an independently scoped member controller',
    () async {
      final controller = InMemoryChatController();
      final adapter = TimelineMemberController(controller);
      await expectLater(
        adapter.applyBatch(chatBatch([workItem('main')])),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(controller.messages, isEmpty);
      adapter.dispose();
      controller.dispose();
    },
  );

  test('even an empty current snapshot is rejected before replacing accepted members', () async {
    final controller = InMemoryChatController();
    final adapter = TimelineMemberController(controller);
    await adapter.applyBatch(
      ChatBatch(
        placement: ChatPlacement.set,
        entries: [ChatAtomEntry(chatAtomMessage('accepted'))],
      ),
    );
    final accepted = controller.messages.single;
    await expectLater(
      adapter.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          entries: [ChatAtomEntry(chatAtomMessage('rejected'))],
          current: chatCurrent(),
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(controller.messages.single, same(accepted));
    adapter.dispose();
    controller.dispose();
  });
}

final class _CountingController extends InMemoryChatController {
  int iterations = 0;
  int elementReads = 0;

  void resetAccessCounts() {
    iterations = 0;
    elementReads = 0;
  }

  @override
  List<Message> get messages => _CountingList(super.messages, this);
}

final class _CountingList extends ListBase<Message> {
  _CountingList(this._messages, this.owner);
  final List<Message> _messages;
  final _CountingController owner;

  @override
  int get length => _messages.length;

  @override
  Message operator [](int index) {
    owner.elementReads++;
    return _messages[index];
  }

  @override
  void operator []=(int index, Message value) => _messages[index] = value;

  @override
  set length(int value) => _messages.length = value;

  @override
  Iterator<Message> get iterator {
    owner.iterations++;
    return super.iterator;
  }
}
