import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _reference = CurrentContentRef(
  ownerId: 'owner',
  domain: 'state:runtime',
  entityId: 'state',
  contentKey: 'activeSkills',
  generation: '2',
);

void main() {
  test(
    'CurrentStateField reads exact JSON with bounded windows and no cache',
    () async {
      final bytes = utf8.encode(jsonEncode(['dart', 'rust']));
      final reader = TestCurrentReader();
      final ranges = <ContentRange>[];
      reader.onReadBody = (reference, range) async {
        expect(reference, _reference);
        ranges.add(range);
        final end = range.offset + range.maxBytes > bytes.length
            ? bytes.length
            : range.offset + range.maxBytes;
        return ContentWindow(
          offset: range.offset,
          bytes: bytes.sublist(range.offset, end),
          generation: reference.generation,
          availableThrough: bytes.length,
          sealed: true,
        );
      };
      final scope = CurrentReadScope(
        threadId: 'thread',
        generation: 1,
        reader: reader,
        isEligible: () => !reader.requested,
      );
      final field = BodyCurrentStateField(
        field: 'activeSkills',
        reference: _reference,
        byteLength: bytes.length,
      );

      expect(await scope.readStateField(field), ['dart', 'rust']);
      expect(ranges.single.offset, 0);
      expect(ranges.single.maxBytes, bytes.length);
      expect((await scope.close()).complete, isTrue);
    },
  );

  test('retiring scope rejects a late State field window', () async {
    final reply = Completer<ContentWindow>();
    final reader = TestCurrentReader()..onReadBody = (_, _) => reply.future;
    final scope = CurrentReadScope(
      threadId: 'thread',
      generation: 1,
      reader: reader,
      isEligible: () => !reader.requested,
    );
    final reading = scope.readStateField(
      const BodyCurrentStateField(
        field: 'progress',
        reference: CurrentContentRef(
          ownerId: 'owner',
          domain: 'state:runtime',
          entityId: 'state',
          contentKey: 'progress',
          generation: '1',
        ),
        byteLength: 2,
      ),
    );
    final rejected = expectLater(
      reading,
      throwsA(isA<StaleConversationScope>()),
    );
    scope.retire();
    reply.complete(
      ContentWindow(
        offset: 0,
        bytes: const [123, 125],
        generation: '1',
        availableThrough: 2,
        sealed: true,
      ),
    );
    await rejected;
    expect((await scope.close()).complete, isTrue);
  });

  test('large State fields use contiguous 64 KiB Current windows', () async {
    final value = {'progress': 'x' * (70 * 1024)};
    final bytes = utf8.encode(jsonEncode(value));
    final reader = TestCurrentReader();
    final ranges = <ContentRange>[];
    reader.onReadBody = (reference, range) async {
      expect(reference, _reference);
      ranges.add(range);
      final end = range.offset + range.maxBytes;
      return ContentWindow(
        offset: range.offset,
        bytes: bytes.sublist(range.offset, end),
        generation: reference.generation,
        availableThrough: bytes.length,
        sealed: end == bytes.length,
      );
    };
    final scope = CurrentReadScope(
      threadId: 'thread',
      generation: 1,
      reader: reader,
      isEligible: () => !reader.requested,
    );
    final field = BodyCurrentStateField(
      field: 'progress',
      reference: _reference,
      byteLength: bytes.length,
    );

    expect(await scope.readStateField(field), value);
    expect(ranges.map((range) => range.offset), [0, 64 * 1024]);
    expect(ranges.map((range) => range.maxBytes), [
      64 * 1024,
      bytes.length - 64 * 1024,
    ]);
    expect((await scope.close()).complete, isTrue);
  });

  test(
    'State collection heads page through Current and retain full count',
    () async {
      const collection = CurrentCollectionRef(
        ownerId: 'owner',
        collection: 'state:runtime:activeSkills',
        revision: 7,
      );
      const field = CollectionCurrentStateField(
        field: 'activeSkills',
        reference: collection,
        count: 301,
      );
      final reader = TestCurrentReader();
      final pages = <(CurrentCollectionRef, String?, ReadDemand)>[];
      reader.onPage = (reference, continuation, demand) async {
        pages.add((reference, continuation, demand));
        return CurrentCollectionPage(
          revision: reference.revision,
          entries: const [],
          continuation: continuation == null ? 'next-page' : null,
        );
      };
      final scope = CurrentReadScope(
        threadId: 'thread',
        generation: 1,
        reader: reader,
        isEligible: () => !reader.requested,
      );

      final first = await scope.pageStateCollection(
        field,
        demand: const ReadDemand(maxItems: 7, maxBytes: 4096),
      );
      expect(first.continuation, 'next-page');
      expect(field.count, 301);
      expect(pages.single.$1, collection);
      expect(pages.single.$2, isNull);
      expect((await scope.close()).complete, isTrue);
    },
  );

  test('CurrentStateField JSON keeps body and collection disjoint', () {
    final body = CurrentStateField.fromJson({
      'kind': 'body',
      'field': 'progress',
      'reference': {
        'ownerId': 'owner',
        'domain': 'state:runtime',
        'entityId': 'state',
        'contentKey': 'progress',
        'generation': '2',
      },
      'byteLength': 17,
    });
    final collection = CurrentStateField.fromJson({
      'kind': 'collection',
      'field': 'activeSkills',
      'reference': {
        'ownerId': 'owner',
        'collection': 'state:runtime:activeSkills',
        'revision': 7,
      },
      'count': 301,
    });
    expect(body, isA<BodyCurrentStateField>());
    expect(collection, isA<CollectionCurrentStateField>());
  });
}
