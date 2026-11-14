import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  test('completion envelopes preserve producer order, payload and completion position', () {
    final first = chatMessage(id: 'z-first', seq: 7);
    final second = chatMessage(id: 'a-second', seq: 9);
    final entries = [first, second];
    final batch = ChatBatch(
      placement: ChatPlacement.append,
      entries: entries,
      fromSeq: 6,
      throughSeq: 11,
    );
    entries.clear();
    expect(batch.entries, orderedEquals([same(first), same(second)]));
    expect(() => batch.entries.clear(), throwsUnsupportedError);
    final encoded = completedEntryToJson(first);
    expect(encoded['recordId'], 'z-first');
    expect(encoded['completionSeq'], 7);
    expect(encoded.containsKey('run'), isFalse);
    expect(encoded.containsKey('mainPresentation'), isFalse);
    expect(encoded['atom'], chatAtomToJson(first.atom));
  });

  test('record filters encode explicit class or all and the real parent', () {
    expect(chatScopeToJson(const ChatScope.conversation(parentId: 'parent')), {
      'queryClass': {'kind': 'class', 'value': 'conversation'},
      'parentId': 'parent',
    });
    expect(chatScopeToJson(const ChatScope(queryClass: AllChatClasses())), {
      'queryClass': {'kind': 'all'},
      'parentId': null,
    });
  });
}
