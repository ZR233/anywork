import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_member_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

void main() {
  test('a real terminal updates the same member only, without duplicating identity or moving its neighbours', () async {
    final controller = InMemoryChatController();
    final adapter = TimelineMemberController(controller);
    final running = ChatAtom(
      id: 'tool', source: const ForegroundTurnChatSource(turnId: 'T'), sourceOrder: 2,
      kind: ChatAtomKind.toolCall, delivery: ChatDeliveryKind.foreground,
      tool: const ChatToolIdentity(callId: 'call', name: 'read_image'),
      lifecycle: const ActiveChatAtom(started: null, status: ChatActiveStatus.running),
      contents: const [],
    );
    await adapter.applyBatch(ChatBatch(placement: ChatPlacement.set,
      entries: [ChatAtomEntry(chatAtomMessage('before')), ChatAtomEntry(running), ChatAtomEntry(chatAtomMessage('after'))],
    ));
    final before = controller.messages.first;
    final after = controller.messages.last;
    final terminal = ChatAtom(
      id: 'tool', source: running.source, sourceOrder: 2,
      kind: ChatAtomKind.toolCall, delivery: ChatDeliveryKind.foreground,
      tool: running.tool,
      lifecycle: const TerminalChatAtom(started: null, ended: null, outcome: ChatTerminalOutcome.failed),
      contents: const [],
    );
    await adapter.applyBatch(ChatBatch(placement: ChatPlacement.append, entries: [ChatAtomEntry(terminal)]));
    expect(controller.messages.map((message) => message.id), ['before', 'tool', 'after']);
    expect(controller.messages.first, same(before)); expect(controller.messages.last, same(after));
    final atom = chatItemPresentationOf(controller.messages[1])!.atom!;
    expect(atom, same(terminal));
    expect((atom.lifecycle as TerminalChatAtom).outcome, ChatTerminalOutcome.failed);
    adapter.dispose(); controller.dispose();
  });

  test('Main item cannot enter an independently scoped member controller', () async {
    final controller = InMemoryChatController(); final adapter = TimelineMemberController(controller);
    await expectLater(adapter.applyBatch(chatBatch([workItem('main')])), throwsA(isA<ConversationContinuityError>()));
    expect(controller.messages, isEmpty);
    adapter.dispose(); controller.dispose();
  });
}
