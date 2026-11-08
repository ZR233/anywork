import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  test(
    'completion envelopes preserve producer order, payload and run position',
    () {
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
      expect(encoded['run'], {'startSeq': 7, 'ordinal': 1});
      expect(encoded['mainPresentation'], 'single');
      expect(encoded['atom'], chatAtomToJson(first.atom));
    },
  );

  test(
    'run reference binds the database and index version with value equality',
    () {
      const reference = CompletionRunRef(
        databaseId: 'db',
        indexVersion: 1,
        startSeq: 7,
      );
      expect(
        reference,
        const CompletionRunRef(databaseId: 'db', indexVersion: 1, startSeq: 7),
      );
      expect(
        reference,
        isNot(
          const CompletionRunRef(
            databaseId: 'other',
            indexVersion: 1,
            startSeq: 7,
          ),
        ),
      );
      expect(completionRunRefToJson(reference), {
        'databaseId': 'db',
        'indexVersion': 1,
        'startSeq': 7,
      });
    },
  );
}
