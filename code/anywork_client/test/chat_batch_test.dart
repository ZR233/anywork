import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  final first = chatMessage(id: 'z-first');
  final second = chatMessage(id: 'a-second');
  final atom = fixtureMember('real-member');
  const state = ChatSourceState(
    source: ForegroundTurnChatSource(turnId: 'turn'),
    lifecycle: ActiveChatSource(),
    started: null,
    ended: null,
  );
  final atomEntry = ChatAtomEntry(atom);
  const sourceEntry = ChatSourceEntry(state);

  test(
    'item access retains empty batches and exact producer order and objects',
    () {
      expect(
        ChatBatch(placement: ChatPlacement.set, entries: []).items,
        isEmpty,
      );
      final batch = ChatBatch(
        placement: ChatPlacement.prepend,
        entries: [ItemChatEntry(first), ItemChatEntry(second)],
      );
      expect(batch.items, orderedEquals([same(first), same(second)]));
    },
  );

  for (final placement in ChatPlacement.values) {
    test(
      'item access rejects every non-Item variant before yielding a partial $placement batch',
      () {
        for (final entries in <List<ChatEntry>>[
          [atomEntry],
          [sourceEntry],
          [ItemChatEntry(first), atomEntry],
          [sourceEntry, ItemChatEntry(second)],
          [ItemChatEntry(first), sourceEntry, ItemChatEntry(second)],
        ]) {
          final batch = ChatBatch(placement: placement, entries: entries);
          expect(() => batch.items, throwsStateError);
        }
      },
    );
  }

  test(
    'member/Children Atom and Source batches remain legal and fully observable',
    () {
      final batch = ChatBatch(
        placement: ChatPlacement.append,
        entries: [sourceEntry, atomEntry],
      );
      expect(
        batch.entries,
        orderedEquals([same(sourceEntry), same(atomEntry)]),
      );
      expect(batch.atoms.single, same(atom));
      expect(() => batch.items, throwsStateError);
    },
  );
}
