import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 20, maxBytes: 65536);

void main() {
  test('SDK delivers unknown, malformed and deferred payloads unchanged without business decoding', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final bytes = [255, 0, 128, 123];
    final unknown = fixtureAtom(
      id: 'unknown',
      payload: InlinePayload(
        bytes: utf8.encode('{"format":"future/9","x":42}'),
      ),
    );
    final malformed = fixtureAtom(
      id: 'malformed',
      payload: InlinePayload(bytes: bytes),
    );
    const reference = ContentRef(
      databaseId: 'database',
      target: ItemPayloadTarget(itemId: 'large'),
    );
    final deferred = fixtureAtom(
      id: 'large',
      payload: DeferredPayload(reference: reference, byteLength: 1000000),
    );
    final batch = ChatBatch(
      placement: ChatPlacement.append,
      entries: ([unknown, malformed, deferred]).map(ChatAtomEntry.new).toList(),
    );
    await feed.deliver(ConversationChatEvent(batch: batch));
    final accepted = fixture.consumers['thread']!.batches.last;
    final atoms = accepted.entries
        .whereType<ChatAtomEntry>()
        .map((entry) => entry.atom)
        .toList();
    expect(accepted, same(batch));
    expect(atoms, [unknown, malformed, deferred]);
    expect((atoms[1].payload as InlinePayload).bytes, bytes);
    expect((atoms[2].payload as DeferredPayload).reference, same(reference));
    expect(feed.acknowledgements, [1, 2]);
    expect((await fixture.close()).complete, isTrue);
  });

  for (final mismatch in ['thread', 'subscription', 'sequence', 'credit']) {
    test(
      '$mismatch envelope violation retires original feed without accepting wrong data',
      () async {
        final fixture = ConversationFixture();
        final feed = await fixture.open(demand: _demand);
        final count = fixture.consumers['thread']!.batches.length;
        if (mismatch == 'credit') {
          // ACK has started but is not yet settled. One additional frame may be
          // admitted behind it; a third ordinary frame cannot grow an async queue.
          // Hold component acceptance as well so this is a deterministic violation.
          feed.ackGate = Completer<void>();
        }
        final batch = ChatBatch(
          placement: ChatPlacement.append,
          entries: ([chatMessage(id: 'wrong')]).map(ChatAtomEntry.new).toList(),
        );
        if (mismatch == 'credit') {
          feed.send(ConversationChatEvent(batch: batch));
          await feed.ackStarted(2);
          feed.send(ConversationChatEvent(batch: batch));
          feed.send(ConversationChatEvent(batch: batch));
        } else {
          feed.send(
            ConversationChatEvent(batch: batch),
            frameThread: mismatch == 'thread' ? 'other-thread' : null,
            frameSubscription: mismatch == 'subscription'
                ? 'other-subscription'
                : null,
            sequence: mismatch == 'sequence' ? 99 : null,
          );
        }
        await feed.requestCloseStarted.future;
        expect(
          fixture.consumers['thread']!.batches,
          hasLength(mismatch == 'credit' ? count + 1 : count),
        );
        expect(feed.acknowledgements, [1]);
        feed.ackGate?.complete();
        expect((await fixture.close()).complete, isTrue);
      },
    );
  }

  test('Set and Append preserve producer order and opaque before without SDK history grouping', () async {
    final fixture = ConversationFixture();
    final initial = chatSet(
      messages: [chatMessage(id: 'newer')],
      before: 'opaque-not-a-sequence',
    );
    final feed = await fixture.open(initial: initial, demand: _demand);
    final append = ChatBatch(
      placement: ChatPlacement.append,
      entries: ([
        chatMessage(id: 'one'),
        chatMessage(id: 'two'),
      ]).map(ChatAtomEntry.new).toList(),
    );
    await feed.deliver(ConversationChatEvent(batch: append));
    final batches = fixture.consumers['thread']!.batches;
    expect(batches, [initial, append]);
    expect(batches.first.before, 'opaque-not-a-sequence');
    expect(
      batches.last.before,
      isNull,
      reason: 'Append carries no cursor replacement',
    );
    expect(
      batches.last.entries.whereType<ChatAtomEntry>().map(
        (entry) => entry.atom.id,
      ),
      ['one', 'two'],
    );
    expect(feed.acknowledgements, [1, 2]);
    expect((await fixture.close()).complete, isTrue);
  });
}
