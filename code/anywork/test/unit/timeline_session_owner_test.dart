import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

// These tests exercise the presentation owner with the real Flyer controller.
// SDK transport/ACK and native-reader lifecycles have their own integration tests;
// the doubles here only expose explicit completion and page handoff barriers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final lateError in [false, true]) {
    test(
      'merged recovery revokes its old cut; retry and selection reject late ${lateError ? 'failure' : 'success'}',
      () async {
        final h = _Harness();
        h.owner.updateReadDemand(
          const ReadDemand(maxItems: 1, maxBytes: 32768),
        );
        ChatAtom part(String turn, int order, int? seq, {bool ended = false}) {
          final source = ForegroundTurnChatSource(turnId: turn);
          return ChatAtom(
            id: '$turn-$order',
            completionItemId: seq == null ? null : 'payload-$turn-$order',
            completionSeq: seq,
            source: source,
            sourceOrder: order * 10,
            sourceState: ChatSourceState(
              source: source,
              lifecycle: ended
                  ? const EndedChatSource(
                      outcome: ChatTerminalOutcome.completed,
                    )
                  : const ActiveChatSource(),
              started: null,
              ended: null,
            ),
            kind: order.isEven ? ChatAtomKind.text : ChatAtomKind.reasoning,
            delivery: ChatDeliveryKind.foreground,
            contents: const [],
            lifecycle: seq == null
                ? const ActiveChatAtom(
                    started: null,
                    status: ChatActiveStatus.running,
                  )
                : const TerminalChatAtom(
                    started: null,
                    ended: null,
                    outcome: ChatTerminalOutcome.completed,
                  ),
          );
        }

        h.owner.select('a');
        await h.a.deliver(
          ChatBatch(
            placement: ChatPlacement.set,
            before: 'H0',
            entries: [ChatAtomEntry(part('T', 1, null))],
          ),
        );
        final display = h.owner.lease('a')!;
        for (final atom in [
          part('T', 2, 1),
          part('T', 3, 2),
          part('T', 1, 3, ended: true),
        ]) {
          await h.a.deliver(
            ChatBatch(
              placement: ChatPlacement.append,
              entries: [ChatAtomEntry(atom)],
            ),
          );
        }
        final first = h.owner.loadActivity('a', generation: display.generation);
        final firstRejected = expectLater(
          first,
          throwsA(isA<StaleConversationScope>()),
        );
        final old = h.a.scopes.last;
        expect(old.windowAnchor, 1);
        for (final atom in [
          part('U', 1, null),
          part('U', 2, 4),
          part('U', 3, 5),
          part('U', 1, 6, ended: true),
        ]) {
          await h.a.deliver(
            ChatBatch(
              placement: ChatPlacement.append,
              entries: [ChatAtomEntry(atom)],
            ),
          );
        }
        expect(old.isActive, isFalse);
        expect(old.closeCalls, 1);
        expect(old.closed, isFalse, reason: 'Retirement is not native join');
        old.window.complete(
          ChatBatch(
            placement: ChatPlacement.prepend,
            entries: [ChatAtomEntry(part('T', 2, 1, ended: true))],
          ),
        );
        await firstRejected;
        expect(
          display.controller.messages.any((message) => message.id == 'T-2'),
          isFalse,
        );
        final failure = h.owner.loadOlder('a', generation: display.generation);
        final fresh = h.a.scopes.last;
        expect(fresh, isNot(same(old)));
        expect(fresh.windowAnchor, 4);
        expect(fresh.windowBefore, isNull);
        fresh.window.completeError(StateError('recovery transport error'));
        await failure;
        expect(h.owner.source.value!.olderError, isA<StateError>());
        expect(display.olderCursor, 'H0');
        fresh.window = Completer<ChatBatch>();
        final retry = h.owner.retryOlder('a', generation: display.generation);
        expect(fresh.windowAnchor, 4);
        expect(fresh.windowBefore, isNull);
        fresh.window.complete(
          ChatBatch(
            placement: ChatPlacement.prepend,
            before: 'fixed-cut-before',
            entries: [ChatAtomEntry(part('U', 2, 4, ended: true))],
          ),
        );
        await retry;
        expect(h.owner.source.value!.olderError, isNull);
        fresh.window = Completer<ChatBatch>();
        final late = h.owner.loadActivity('a', generation: display.generation);
        final rejected = expectLater(
          late,
          throwsA(
            lateError ? isA<StateError>() : isA<StaleConversationScope>(),
          ),
        );
        // A distinct intent queues behind the same physical read slot. It must
        // revalidate selection before publishing any loading state.
        final queued = h.owner.loadOlder('a', generation: display.generation);
        expect(fresh.windowBefore, 'fixed-cut-before');
        h.owner.select('b');
        await h.b.deliver(chatBatch([_text('b', 1)]));
        final replacement = h.owner.lease('b')!;
        expect(fresh.isActive, isFalse);
        if (lateError) {
          fresh.window.completeError(StateError('late retired failure'));
        } else {
          fresh.window.complete(
            ChatBatch(
              placement: ChatPlacement.prepend,
              entries: [ChatAtomEntry(part('T', 2, 1, ended: true))],
            ),
          );
        }
        await rejected;
        await queued;
        expect(h.owner.lease('b'), same(replacement));
        expect(replacement.controller.messages.single.id, 'b-1');
        expect(h.owner.source.value!.olderError, isNull);
        expect(h.owner.source.value!.isLoadingOlder, isFalse);
        expect((await h.owner.close()).complete, isTrue);
      },
    );
  }

  for (final outcome in [
    ChatTerminalOutcome.completed,
    ChatTerminalOutcome.failed,
    ChatTerminalOutcome.cancelled,
  ]) {
    test(
      'global completed props stay bounded and all 81 segments recover after $outcome',
      () async {
        final h = _Harness();
        h.owner.updateReadDemand(
          const ReadDemand(maxItems: 2, maxBytes: 32768),
        );
        const source = ForegroundTurnChatSource(turnId: 'blocked');
        List<int> payloadBytes(int order) => utf8.encode(
          jsonEncode({
            'contract': 'anywork.chat/1',
            'type': order.isEven ? 'text' : 'thinking',
            'data': {},
            'bodies': [
              {
                'key': 'body',
                'byteLength': order == 4 ? 0 : 1024,
                'inline': order == 4 ? [] : List.filled(1024, 65),
              },
            ],
          }),
        );
        h.a.payloads.addAll({
          for (var order = 1; order <= 81; order++)
            'payload-$order': payloadBytes(order),
        });
        ChatAtom member(int order, {int? seq, bool deferred = false}) =>
            ChatAtom(
              id: 'member-$order',
              completionItemId: seq == null ? null : 'payload-$order',
              completionSeq: seq,
              source: source,
              sourceOrder: order * 10,
              kind: order.isEven ? ChatAtomKind.text : ChatAtomKind.reasoning,
              delivery: ChatDeliveryKind.foreground,
              sourceState: ChatSourceState(
                source: source,
                lifecycle: seq == 82 || deferred
                    ? EndedChatSource(outcome: outcome)
                    : const ActiveChatSource(),
                started: null,
                ended: null,
              ),
              lifecycle: seq == null
                  ? const ActiveChatAtom(
                      started: null,
                      status: ChatActiveStatus.running,
                    )
                  : TerminalChatAtom(
                      started: null,
                      ended: null,
                      outcome: order == 1
                          ? outcome
                          : ChatTerminalOutcome.completed,
                    ),
              contents: const [],
              payload: seq == null
                  ? null
                  : deferred
                  ? DeferredPayload(
                      reference: ContentRef(
                        databaseId: 'db',
                        target: ItemPayloadTarget(itemId: 'payload-$order'),
                      ),
                      byteLength: payloadBytes(order).length,
                    )
                  : InlinePayload(bytes: payloadBytes(order)),
            );
        h.owner.select('a');
        await h.a.deliver(
          ChatBatch(
            placement: ChatPlacement.set,
            before: 'main-H0',
            entries: [ChatAtomEntry(member(1))],
          ),
        );
        final lease = h.owner.lease('a')!;
        final key = lease.liveUnits.value.single.id;
        var maximumItems = 0, maximumBytes = 0;
        var maximumPageBytes = 0;
        void checkPage(ChatBatch batch) {
          final bytes = utf8
              .encode(
                jsonEncode({
                  'placement': batch.placement.name,
                  'entries': batch.entries.map(chatEntryToJson).toList(),
                  'before': batch.before,
                  'current': null,
                }),
              )
              .length;
          maximumPageBytes = bytes > maximumPageBytes
              ? bytes
              : maximumPageBytes;
          expect(batch.entries.length, lessThanOrEqualTo(2));
          expect(bytes, lessThanOrEqualTo(32768));
        }

        for (var order = 2; order <= 81; order++) {
          final completion = ChatBatch(
            placement: ChatPlacement.append,
            entries: [ChatAtomEntry(member(order, seq: order - 1))],
          );
          checkPage(completion);
          await h.a.deliver(completion);
          final (items, bytes) = lease.retainedCompletedBudget;
          maximumItems = items > maximumItems ? items : maximumItems;
          maximumBytes = bytes > maximumBytes ? bytes : maximumBytes;
          expect(items, lessThanOrEqualTo(2));
          expect(bytes, lessThanOrEqualTo(32768));
          final holders = <ChatAtom>{
            for (final unit in lease.liveUnits.value) ...[
              ...unit.members.where(
                (atom) => atom.lifecycle is TerminalChatAtom,
              ),
              if (unit.lastCompletion != null) unit.lastCompletion!,
              ...unit.expansion.current!.members.where(
                (atom) => atom.lifecycle is TerminalChatAtom,
              ),
            ],
          };
          for (final unit in lease.liveUnits.value) {
            expect(unit.expansion.current, same(unit));
            expect(unit.expansion.committedMessage, isNull);
            expect(
              unit.expansion.completionAnchor,
              isNull,
              reason: 'No hidden expansion or anchor object for evicted props',
            );
          }
          expect(holders.length, items);
          final canonicalBytes = holders.fold<int>(
            0,
            (n, atom) => n + chatAtomEntryEncodedLength(atom),
          );
          expect(canonicalBytes, lessThanOrEqualTo(32768));
          expect(
            canonicalBytes,
            lessThanOrEqualTo(bytes),
            reason: 'Decoded UI values are additional to the full canonical entries',
          );
          expect(
            holders
                .where((atom) => atom.payload is InlinePayload)
                .fold<int>(
                  0,
                  (n, atom) => n + (atom.payload as InlinePayload).bytes.length,
                ),
            lessThanOrEqualTo(bytes),
          );
          expect(
            lease.liveUnits.value
                .expand((unit) => unit.members)
                .where((atom) => atom.lifecycle is ActiveChatAtom)
                .map((atom) => atom.id),
            ['member-1'],
          );
        }
        expect(lease.activity.value.hasMore, isTrue);
        expect(lease.liveUnits.value.length, lessThanOrEqualTo(3));
        expect(lease.controller.messages, isEmpty);
        final background = ChatAtom(
          id: 'B',
          completionItemId: 'payload-B',
          completionSeq: 81,
          source: const BackgroundResultChatSource(messageId: 'B'),
          sourceOrder: 1,
          kind: ChatAtomKind.toolCall,
          delivery: ChatDeliveryKind.independent,
          lifecycle: const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          ),
          contents: const [],
        );
        await h.a.deliver(
          ChatBatch(
            placement: ChatPlacement.append,
            entries: [ChatAtomEntry(background)],
          ),
        );
        expect(lease.controller.messages.single.id, 'B');
        await h.a.deliver(
          ChatBatch(
            placement: ChatPlacement.append,
            entries: [ChatAtomEntry(member(1, seq: 82))],
          ),
        );
        expect(
          lease.controller.messages.any((message) => message.id == key),
          isTrue,
        );
        final canonical = [
          for (var order = 2; order <= 81; order++)
            member(order, seq: order - 1, deferred: true),
        ];
        var pages = 0, repeats = 0;
        final readPositions = <int>{};
        while (lease.activity.value.hasMore) {
          if (h.a.scopes.isNotEmpty) {
            h.a.scopes.last.window = Completer<ChatBatch>();
          }
          final reading = h.owner.loadOlder('a', generation: lease.generation);
          final scope = h.a.scopes.last;
          final anchor = scope.windowAnchor!;
          final end = scope.windowBefore == null
              ? anchor
              : int.parse(scope.windowBefore!.split(':').last);
          final selected = canonical
              .where((atom) => atom.completionSeq! <= end)
              .toList();
          final atoms = selected
              .skip(selected.length > 2 ? selected.length - 2 : 0)
              .toList();
          for (final atom in atoms) {
            if (!readPositions.add(atom.completionSeq!)) repeats++;
          }
          final ordinaryPage = ChatBatch(
            placement: ChatPlacement.prepend,
            entries: atoms.map(ChatAtomEntry.new).toList(),
            before: selected.length <= 2
                ? null
                : 'ordinary:${atoms.first.completionSeq! - 1}',
          );
          checkPage(ordinaryPage);
          scope.window.complete(ordinaryPage);
          await reading;
          expect(h.owner.source.value!.olderError, isNull);
          expect(lease.olderCursor, 'main-H0');
          expect(lease.retainedCompletedBudget.$1, lessThanOrEqualTo(2));
          expect(lease.retainedCompletedBudget.$2, lessThanOrEqualTo(32768));
          pages++;
        }
        final restored = [
          for (final message in lease.controller.messages)
            ...(message.metadata![timelineDisplayUnitKey]
                    as TimelineDisplayUnit)
                .members,
        ];
        expect(restored.map((atom) => atom.id).toSet(), {
          for (var order = 1; order <= 81; order++) 'member-$order',
          'B',
        });
        expect(
          restored
              .where((atom) => atom.source == source)
              .map((atom) => atom.sourceOrder),
          [for (var order = 1; order <= 81; order++) order * 10],
        );
        final bodies = lease.queries!;
        for (final atom in restored.where((atom) => atom.id != 'B')) {
          final PayloadData materialized;
          if (atom.payload case DeferredPayload(
            :final reference,
            :final byteLength,
          )) {
            expect(
              (reference.target as ItemPayloadTarget).itemId,
              atom.completionItemId,
            );
            final window = await bodies.readContent(
              reference: reference,
              range: const ContentRange(offset: 0, maxBytes: 32768),
            );
            expect(window.bytes.length, byteLength);
            materialized = InlinePayload(bytes: window.bytes);
          } else {
            materialized = atom.payload!;
          }
          final presentation = ChatItemPresentation.decodePayload(
            atom.id,
            materialized,
          );
          expect(
            presentation.inlineText('body'),
            atom.id == 'member-4' ? '' : 'A' * 1024,
          );
          if (atom.id == 'member-4') {
            expect(presentation.isKnownEmptyText, isTrue);
          }
        }
        expect(lease.liveUnits.value, isEmpty);
        expect(pages, 40);
        expect(repeats, 0);
        debugPrint(
          'F3 $outcome: retained=$maximumItems/$maximumBytes; maxPageBytes=$maximumPageBytes; recoveryPages=$pages; repeatedAtoms=$repeats',
        );
        expect((await h.owner.close()).complete, isTrue);
      },
    );
  }

  for (final failClose in [false, true]) {
    test(
      'R2 permanent merge joins only its body scope and preserves ${failClose ? 'close failure' : 'Main'}',
      () async {
        final h = _Harness();
        h.owner.updateReadDemand(
          const ReadDemand(maxItems: 2, maxBytes: 32768),
        );
        const source = ForegroundTurnChatSource(turnId: 'T');
        ContentRef body(int order) => ContentRef(
          databaseId: 'db',
          target: BodyContentTarget(
            owner: ItemContentOwner(itemId: 'original-$order'),
            key: 'body',
          ),
        );
        ChatAtom member(int order, int seq) => ChatAtom(
          id: 'member-$order',
          completionItemId: 'original-$order',
          completionSeq: seq,
          source: source,
          sourceOrder: order,
          kind: ChatAtomKind.reasoning,
          delivery: ChatDeliveryKind.foreground,
          sourceState: const ChatSourceState(
            source: source,
            lifecycle: EndedChatSource(outcome: ChatTerminalOutcome.completed),
            started: null,
            ended: null,
          ),
          lifecycle: const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          ),
          contents: [
            ChatAtomContent(role: ChatContentRole.body, reference: body(order)),
          ],
          payload: InlinePayload(
            bytes: utf8.encode(
              jsonEncode({
                'contract': 'anywork.chat/1',
                'type': 'thinking',
                'data': {},
                'bodies': [
                  {
                    'key': 'body',
                    'byteLength': 4,
                    'reference': contentRefToJson(body(order)),
                  },
                ],
              }),
            ),
          ),
        );
        h.owner.select('a');
        final atoms = [member(10, 1), member(30, 2)];
        expect(
          atoms.fold<int>(0, (n, atom) => n + chatAtomEntryEncodedLength(atom)),
          lessThan(32768),
        );
        await h.a.deliver(
          ChatBatch(
            placement: ChatPlacement.set,
            before: 'unknown',
            entries: atoms.map(ChatAtomEntry.new).toList(),
          ),
        );
        final lease = h.owner.lease('a')!;
        final main = lease.queries!;
        final removed =
            lease.controller.messages.last.metadata![timelineDisplayUnitKey]
                as TimelineDisplayUnit;
        final intent = removed.expansion;
        final token = Object();
        intent.setBodyVisible(token, true);
        final pending = intent.readBody!(
          intent.bodyGeneration,
          body(30),
          const ContentRange(offset: 0, maxBytes: 32768),
        );
        final rejected = expectLater(
          pending,
          throwsA(isA<StaleConversationScope>()),
        );
        final original = h.a.scopes.last..failClose = failClose;
        await h.a.deliver(
          ChatBatch(placement: ChatPlacement.prepend, entries: const []),
        );
        expect(intent.isRetired, isTrue);
        expect(original.isActive, isFalse);
        expect(original.closeCalls, 1);
        expect(original.closed, isFalse, reason: 'Retirement is not IO join');
        expect(main.isActive, isTrue);
        expect(lease.isRetired, isFalse);
        original.bodyRequests.single.complete(
          ContentWindow(
            offset: 0,
            bytes: utf8.encode('late'),
            generation: 'g',
            availableThrough: 4,
            sealed: true,
          ),
        );
        await rejected;
        Object? originalCleanupError;
        if (failClose) {
          await expectLater(
            lease.closeDetailQueries(original),
            throwsStateError,
          );
          expect(lease.queryCleanupError, isA<StateError>());
          expect(
            lease.queryCleanupError.toString(),
            contains('native close failed'),
          );
          originalCleanupError = lease.queryCleanupError;
          original.failClose = false;
        }
        await lease.closeDetailQueries(original);
        expect(original.closed, isTrue);
        expect(
          lease.queryCleanupError,
          failClose ? same(originalCleanupError) : isNull,
          reason: 'The existing owner retains cleanup diagnostics until all its scopes settle',
        );
        expect(main.isActive, isTrue);
        expect(lease.isRetired, isFalse);
        final retained =
            lease.controller.messages.single.metadata![timelineDisplayUnitKey]
                as TimelineDisplayUnit;
        expect(retained.expansion.isRetired, isFalse);
        expect((await h.owner.close()).complete, isTrue);
        expect(lease.queryCleanupError, isNull);
      },
    );
  }
  test('history body fold revokes only its local scope, joins IO, and reopens a new generation', () async {
    final h = _Harness();
    h.owner.select('a');
    const source = ForegroundTurnChatSource(turnId: 'T');
    await h.a.deliver(
      ChatBatch(
        placement: ChatPlacement.set,
        entries: [
          const ChatSourceEntry(
            ChatSourceState(
              source: source,
              lifecycle: EndedChatSource(
                outcome: ChatTerminalOutcome.completed,
              ),
              started: null,
              ended: null,
            ),
          ),
          ChatAtomEntry(
            ChatAtom(
              id: 'R',
              completionItemId: 'R',
              completionSeq: 1,
              source: source,
              sourceOrder: 10,
              kind: ChatAtomKind.reasoning,
              delivery: ChatDeliveryKind.foreground,
              lifecycle: const TerminalChatAtom(
                started: null,
                ended: null,
                outcome: ChatTerminalOutcome.completed,
              ),
              contents: const [],
            ),
          ),
        ],
      ),
    );
    final lease = h.owner.lease('a')!;
    final main = lease.queries!;
    final unit =
        lease.controller.messages.single.metadata![timelineDisplayUnitKey]
            as TimelineDisplayUnit;
    final intent = unit.expansion;
    final token = Object();
    const reference = ContentRef(
      databaseId: 'db',
      target: BodyContentTarget(
        owner: ItemContentOwner(itemId: 'R'),
        key: 'body',
      ),
    );
    intent.setBodyVisible(token, true);
    final generation = intent.bodyGeneration;
    final pending = intent.readBody!(
      generation,
      reference,
      const ContentRange(offset: 0, maxBytes: 32768),
    );
    final stale = expectLater(pending, throwsA(isA<StaleConversationScope>()));
    final original = h.a.scopes.last;
    intent.setBodyVisible(token, false);
    expect(original.isActive, isFalse);
    expect(original.closeCalls, 1);
    expect(main.isActive, isTrue);
    expect(lease.isRetired, isFalse);
    intent.setBodyVisible(token, true);
    expect(intent.bodyGeneration, isNot(same(generation)));
    final fresh = intent.readBody!(
      intent.bodyGeneration,
      reference,
      const ContentRange(offset: 0, maxBytes: 32768),
    );
    final replacement = h.a.scopes.last;
    expect(replacement, isNot(same(original)));
    original.bodyRequests.single.complete(
      ContentWindow(
        offset: 0,
        bytes: [1],
        generation: 'old',
        availableThrough: 1,
        sealed: true,
      ),
    );
    await stale;
    await Future<void>.delayed(Duration.zero);
    expect(original.closed, isTrue);
    expect(replacement.isActive, isTrue);
    final admitted = ContentWindow(
      offset: 0,
      bytes: [2],
      generation: 'new',
      availableThrough: 1,
      sealed: true,
    );
    replacement.bodyRequests.single.complete(admitted);
    expect(await fresh, same(admitted));
    intent.setBodyVisible(token, false);
    await Future<void>.delayed(Duration.zero);
    expect(replacement.closed, isTrue);
    expect(main.isActive, isTrue);
    await h.owner.close();
  });

  test('expanded ordinary window uses the same reducer without moving Main cursor; retry preserves window cursor', () async {
    final h = _Harness();
    h.owner.updateReadDemand(const ReadDemand(maxItems: 1, maxBytes: 32768));
    const source = ForegroundTurnChatSource(turnId: 'T');
    ChatAtom member(int order) => ChatAtom(
      id: 'R$order',
      completionItemId: 'R$order',
      completionSeq: order,
      source: source,
      sourceOrder: order,
      kind: ChatAtomKind.reasoning,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const TerminalChatAtom(
        started: null,
        ended: null,
        outcome: ChatTerminalOutcome.completed,
      ),
      contents: const [],
    );
    h.owner.select('a');
    await h.a.deliver(
      ChatBatch(
        placement: ChatPlacement.set,
        before: 'main-before',
        entries: const [],
      ),
    );
    // These members were reliably admitted after the opening cut, rather than
    // inferring a complete source range from consecutive numeric fixture IDs.
    await h.a.deliver(
      ChatBatch(
        placement: ChatPlacement.append,
        entries: [
          const ChatSourceEntry(
            ChatSourceState(
              source: source,
              lifecycle: EndedChatSource(
                outcome: ChatTerminalOutcome.completed,
              ),
              started: null,
              ended: null,
            ),
          ),
          for (var i = 1; i <= 3; i++) ChatAtomEntry(member(i)),
        ],
      ),
    );
    final lease = h.owner.lease('a')!;
    final unit =
        lease.controller.messages.single.metadata![timelineDisplayUnitKey]
            as TimelineDisplayUnit;
    expect(unit.members.map((atom) => atom.id), ['R3']);
    final visibility = Object();
    unit.expansion.onVisibilityChanged!(visibility, true);
    final reading = unit.expansion.readEarlier!();
    final scope = h.a.scopes.single;
    expect(scope.windowAnchor, 3);
    expect(scope.windowBefore, isNull);
    scope.window.complete(
      ChatBatch(
        placement: ChatPlacement.prepend,
        before: 'window-before',
        entries: [ChatAtomEntry(member(1))],
      ),
    );
    await reading;
    expect(lease.olderCursor, 'main-before');
    final updated =
        lease.controller.messages.single.metadata![timelineDisplayUnitKey]
            as TimelineDisplayUnit;
    expect(updated.id, unit.id);
    expect(updated.members.map((atom) => atom.id), ['R1', 'R3']);
    expect(updated.memberCount, 3);
    expect(unit.expansion.before, 'window-before');
    expect(lease.liveUnits.value, isEmpty);

    scope.window = Completer<ChatBatch>();
    final failing = unit.expansion.readEarlier!();
    final rejected = expectLater(failing, throwsStateError);
    scope.window.completeError(StateError('window failed'));
    await rejected;
    expect(unit.expansion.before, 'window-before');
    expect(lease.olderCursor, 'main-before');
    expect(unit.expansion.error, isA<StateError>());

    scope.window = Completer<ChatBatch>();
    final retry = unit.expansion.readEarlier!();
    expect(scope.windowBefore, 'window-before');
    scope.window.complete(
      ChatBatch(
        placement: ChatPlacement.prepend,
        entries: [ChatAtomEntry(member(2))],
      ),
    );
    await retry;
    expect(unit.expansion.before, isNull);
    expect(unit.expansion.error, isNull);
    unit.expansion.onVisibilityChanged!(visibility, false);
    expect(scope.isActive, isFalse);
    expect(lease.olderCursor, 'main-before');
    expect((await h.owner.close()).complete, isTrue);
  });

  test('selection alone does not attach; first viewport demand attaches only the latest selection', () async {
    final h = _Harness(viewport: false);
    h.owner.select('a');
    h.owner.select('b');
    expect(h.a.consumer, isNull);
    expect(h.b.consumer, isNull);
    expect(h.a.attaches + h.b.attaches, 0);
    h.owner.updateReadDemand(chatDemand);
    expect(h.a.consumer, isNull);
    expect(h.b.consumer, isNotNull);
    await h.b.deliver(chatBatch([_text('b', 1)]));
    expect(h.owner.lease('b')!.controller.messages.single.id, 'b-1');
    await h.owner.close();
  });

  for (final phase in [
    TimelineConnectionPhase.idle,
    TimelineConnectionPhase.ready,
  ]) {
    test(
      'reentrant $phase selection retains only the final consumer',
      () async {
        final h = _Harness();
        var switched = false;
        final observation = h.owner.source.watch((state) {
          if (!switched &&
              state?.threadId == 'a' &&
              state?.connection == phase) {
            switched = true;
            h.owner.select('b');
          }
        });
        addTearDown(observation.cancel);
        h.owner.select('a');
        expect(switched, isTrue);
        expect(h.owner.source.value?.threadId, 'b');
        expect(h.a.consumer, isNull);
        expect(h.b.consumer, isNotNull);
        expect(h.a.state.observerCount, 0);
        expect(h.b.state.observerCount, 1);
        h.owner.select(null);
        expect(h.b.consumer, isNull);
        h.owner.select('b');
        await h.b.deliver(chatBatch([_text('b', 1)]));
        expect(h.owner.lease('b')!.controller.messages.single.id, 'b-1');
        expect((await h.owner.close()).complete, isTrue);
        expect(h.a.consumer, isNull);
        expect(h.b.consumer, isNull);
        expect(h.a.state.observerCount + h.b.state.observerCount, 0);
      },
    );
  }

  test(
    'reentrant binding A to B to A releases the provisional consumer',
    () async {
      final h = _Harness();
      h.a.onAttach = () {
        h.a.onAttach = null;
        h.owner.select('b');
        h.owner.select('a');
      };
      h.owner.select('a');
      expect(h.owner.source.value?.threadId, 'a');
      expect(h.owner.source.value?.connectionError, isNull);
      expect(h.a.consumer, isNotNull);
      expect(h.b.consumer, isNull);
      await h.a.deliver(chatBatch([_text('a', 1)]));
      expect(h.owner.lease('a')!.controller.messages.single.id, 'a-1');
      expect((await h.owner.close()).complete, isTrue);
      expect(h.a.consumer, isNull);
      expect(h.b.consumer, isNull);
      expect(h.a.state.observerCount + h.b.state.observerCount, 0);
    },
  );

  test('reentrant detach cannot retire the newly selected display', () async {
    final h = _Harness();
    await h.openA([_text('a', 1)]);
    final previous = h.owner.lease('a')!;
    h.a.onDetach = () {
      h.a.onDetach = null;
      h.owner.select('b');
    };
    h.owner.select(null);
    expect(h.owner.source.value?.threadId, 'b');
    expect(h.a.consumer, isNull);
    expect(h.b.consumer, isNotNull);
    await h.b.deliver(chatBatch([_text('b', 1)]));
    expect(h.owner.lease('b')!.controller.messages.single.id, 'b-1');
    await previous.released;
    expect((await h.owner.close()).complete, isTrue);
    expect(h.a.consumer, isNull);
    expect(h.b.consumer, isNull);
  });

  test(
    'reentrant close during binding joins the provisional consumer',
    () async {
      final h = _Harness();
      late Future<CloseReport> closing;
      h.a.onAttach = () {
        closing = h.owner.close();
        h.owner.select('b');
      };
      h.owner.select('a');
      expect((await closing).complete, isTrue);
      expect(h.owner.source.value, isNull);
      expect(h.a.consumer, isNull);
      expect(h.b.consumer, isNull);
      expect(h.a.state.observerCount + h.b.state.observerCount, 0);
    },
  );

  test(
    'reentrant close publication shares the mounted display obligation',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!..bind();
      late Future<CloseReport> nested;
      final observation = h.owner.source.watch((state) {
        if (state == null) nested = h.owner.close(deadline: DateTime.utc(2000));
      });
      addTearDown(observation.cancel);
      final closing = h.owner.close(deadline: DateTime.utc(2000));
      expect(nested, same(closing));
      final report = await nested;
      expect(report.complete, isFalse);
      expect(report.unresolved.single.owner, 'timeline-display:a');
      expect(lease.isReleased, isFalse);
      await lease.unbind();
      expect((await h.owner.close()).complete, isTrue);
    },
  );

  test('reentrant close from detach retains the old mounted display', () async {
    final h = _Harness();
    await h.openA([_text('a', 1)]);
    final lease = h.owner.lease('a')!..bind();
    late Future<CloseReport> closing;
    h.a.onDetach = () {
      h.a.onDetach = null;
      closing = h.owner.close(deadline: DateTime.utc(2000));
    };
    h.owner.select('b');
    final report = await closing;
    expect(report.complete, isFalse);
    expect(report.unresolved.single.owner, 'timeline-display:a');
    expect(h.owner.source.value, isNull);
    expect(h.b.consumer, isNull);
    expect(lease.isReleased, isFalse);
    await lease.unbind();
    expect((await h.owner.close()).complete, isTrue);
  });

  test('Set admits a message without synthesizing timestamps or a completion cursor', () async {
    final h = _Harness();
    h.owner.select('a');
    final atom = _text('a', 1);
    await h.a.deliver(chatBatch([atom]));
    final lease = h.owner.lease('a')!;
    expect(lease.controller.messages.single.id, atom.id);
    expect(lease.controller.messages, hasLength(1));
    expect(h.a.attaches, 1);
    expect(h.a.refreshes, 0);
    expect((await h.owner.close()).complete, isTrue);
  });

  test(
    'reading and return-to-latest preserve the consumer and loaded window',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!;
      await h.owner.dispatch('a', const TimelineEnterHistory());
      await h.a.deliver(
        chatBatch([_text('a', 2)], placement: ChatPlacement.append),
      );
      expect(h.owner.lease('a'), same(lease));
      expect(lease.loadedCount, 2);
      expect(h.owner.source.value?.hasNewOutput, isTrue);
      await h.owner.returnToLive('a');
      expect(h.owner.lease('a'), same(lease));
      expect(lease.loadedCount, 2);
      expect(h.owner.source.value?.mode, TimelineDisplayMode.live);
      expect(h.owner.source.value?.hasNewOutput, isFalse);
      expect(h.a.attaches, 1);
      expect(h.a.refreshes, 0);
      await h.owner.close();
    },
  );

  test(
    'connection/save notifications perform no historical controller operation',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!;
      final operations = <ChatOperation>[];
      final observed = lease.controller.operationsStream.listen(operations.add);
      h.a.state.publish(const ChatReconnecting('a', error: 'offline'));
      h.a.state.publish(const ChatReady('a', true));
      await Future<void>.delayed(Duration.zero);
      expect(operations, isEmpty);
      expect(lease.loadedCount, 1);
      await observed.cancel();
      await h.owner.close();
    },
  );

  test('pending older read does not hold completion acceptance or require a ready feed', () async {
    final h = _Harness();
    await h.openA([_text('a', 3)], hasOlder: true);
    final lease = h.owner.lease('a')!;
    h.a.state.publish(const ChatFailed('a', error: 'offline'));
    final loading = h.owner.loadOlder('a', generation: lease.generation);
    final scope = h.a.scopes.single;
    await scope.requested.future;
    await h.a.deliver(
      chatBatch([_text('a', 4)], placement: ChatPlacement.append),
    );
    expect(lease.loadedCount, 2);
    scope.reply.complete(
      ChatBatch(
        placement: ChatPlacement.prepend,
        entries: ([
          _text('a', 1),
          _text('a', 2),
        ]).map(ChatAtomEntry.new).toList(),
        before: 'before-1',
      ),
    );
    await loading;
    expect(lease.loadedCount, 4);
    expect(lease.controller.messages.map((message) => message.id), [
      'a-1',
      'a-2',
      'a-3',
      'a-4',
    ]);
    expect(lease.olderCursor, 'before-1');
    expect(h.owner.source.value?.isLoadingOlder, isFalse);
    expect(h.a.attaches, 1);
    await h.owner.close();
  });

  test('A to B to A rejects a page from the first A generation', () async {
    final h = _Harness();
    await h.openA([_text('a', 3)], hasOlder: true);
    final first = h.owner.lease('a')!;
    final oldPage = h.owner.loadOlder('a', generation: first.generation);
    final scope = h.a.scopes.single;
    await scope.requested.future;
    h.owner.select('b');
    await h.b.deliver(chatBatch([_text('b', 1)]));
    h.owner.select('a');
    await h.a.deliver(chatBatch([_text('a', 10)]));
    final latest = h.owner.lease('a')!;
    expect(latest, isNot(same(first)));
    scope.reply.complete(
      ChatBatch(
        placement: ChatPlacement.prepend,
        entries: ([_text('a', 1)]).map(ChatAtomEntry.new).toList(),
        before: null,
      ),
    );
    await oldPage;
    expect(h.owner.lease('a'), same(latest));
    expect(latest.controller.messages.single.id, 'a-10');
    await first.released;
    await h.owner.close();
  });

  test('new Set retires the old display and its query scopes', () async {
    final h = _Harness();
    await h.openA([_text('a', 1)]);
    final first = h.owner.lease('a')!;
    final scope = first.openDetailQueries()!;
    await h.a.deliver(chatBatch([_text('a', 7)]));
    expect(scope.isActive, isFalse);
    final next = h.owner.lease('a')!;
    expect(next.generation, greaterThan(first.generation));
    expect(next.controller.messages.single.id, 'a-7');
    expect(h.a.attaches, 1);
    expect(h.a.refreshes, 0);
    await first.released;
    await h.owner.close();
  });

  for (final returnToA in [false, true]) {
    test(
      'component await selection ${returnToA ? 'A-B-A' : 'A-B'} never publishes old Append state',
      () async {
        final h = _Harness();
        await h.openA([_text('a', 1)]);
        await h.owner.dispatch('a', const TimelineEnterHistory());
        final old = h.owner.lease('a')!..bind();
        var switched = false;
        final operations = old.controller.operationsStream.listen((_) {
          if (switched) return;
          switched = true;
          h.owner.select('b');
          if (returnToA) h.owner.select('a');
        });
        addTearDown(operations.cancel);
        await h.a.deliver(
          chatBatch([_text('a', 2)], placement: ChatPlacement.append),
        );
        expect(
          switched,
          isTrue,
          reason:
              'selection must run from the real controller operation stream',
        );
        expect(old.isRetired, isTrue);
        expect(
          old.isReleased,
          isFalse,
          reason: 'mounted subtree still owns the old controller',
        );
        expect(h.owner.source.value?.threadId, returnToA ? 'a' : 'b');
        expect(h.owner.source.value?.hasNewOutput, isFalse);
        final target = returnToA ? h.a : h.b;
        await target.deliver(chatBatch([_text(returnToA ? 'a' : 'b', 10)]));
        final next = h.owner.lease(returnToA ? 'a' : 'b')!;
        expect(next, isNot(same(old)));
        expect(next.controller.messages.single.id, returnToA ? 'a-10' : 'b-10');
        await old.unbind();
        expect(old.isReleased, isTrue);
        await h.owner.close();
      },
    );
  }

  for (final failOld in [false, true]) {
    test(
      'late old ${failOld ? 'error' : 'success'} and finally preserve new A loading state',
      () async {
        final h = _Harness();
        await h.openA([_text('a', 3)], hasOlder: true);
        final old = h.owner.lease('a')!;
        final oldLoad = h.owner.loadOlder('a', generation: old.generation);
        final oldScope = h.a.scopes.single;
        await oldScope.requested.future;
        h.owner.select('b');
        h.owner.select('a');
        await h.a.deliver(chatBatch([_text('a', 10)], before: 'new-before'));
        final next = h.owner.lease('a')!;
        final newLoad = h.owner.loadOlder('a', generation: next.generation);
        final newScope = h.a.scopes.last;
        await newScope.requested.future;
        if (failOld) {
          oldScope.reply.completeError(StateError('old failure'));
        } else {
          oldScope.reply.complete(
            chatBatch([_text('a', 1)], placement: ChatPlacement.prepend),
          );
        }
        await oldLoad;
        expect(h.owner.lease('a'), same(next));
        expect(next.controller.messages.single.id, 'a-10');
        expect(next.olderCursor, 'new-before');
        expect(h.owner.source.value?.olderError, isNull);
        expect(
          h.owner.source.value?.isLoadingOlder,
          isTrue,
          reason: 'old finally cannot clear the new request',
        );
        newScope.reply.complete(
          chatBatch([_text('a', 9)], placement: ChatPlacement.prepend),
        );
        await newLoad;
        expect(next.controller.messages.map((message) => message.id), [
          'a-9',
          'a-10',
        ]);
        expect(h.owner.source.value?.isLoadingOlder, isFalse);
        await old.released;
        await h.owner.close();
      },
    );
  }

  test('Append without an active Set is rejected', () async {
    final h = _Harness();
    h.owner.select('a');
    await expectLater(
      h.a.deliver(chatBatch([_text('a', 3)], placement: ChatPlacement.append)),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect(h.owner.lease('a'), isNull);
    await h.owner.close();
  });

  test(
    'page failures preserve the display and retry the same atomic boundary',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 3)], hasOlder: true);
      final lease = h.owner.lease('a')!;
      final loading = h.owner.loadOlder('a', generation: lease.generation);
      final scope = h.a.scopes.single;
      scope.reply.completeError(StateError('read failed'));
      await loading;
      expect(h.owner.source.value?.olderError, isA<StateError>());
      expect(lease.olderCursor, 'before-3');
      expect(lease.loadedCount, 1);
      scope.reply = Completer<ChatBatch>();
      final retry = h.owner.retryOlder('a', generation: lease.generation);
      scope.reply.complete(
        ChatBatch(
          placement: ChatPlacement.prepend,
          entries: ([_text('a', 2)]).map(ChatAtomEntry.new).toList(),
          before: null,
        ),
      );
      await retry;
      expect(lease.loadedCount, 2);
      expect(h.owner.source.value?.olderError, isNull);
      expect(scope.boundaries, ['before-3', 'before-3']);
      await h.owner.close();
    },
  );

  test('close waits for accepted reads and real subtree unbind, retaining retry responsibility', () async {
    final h = _Harness();
    await h.openA([_text('a', 3)], hasOlder: true);
    final lease = h.owner.lease('a')!;
    lease.bind();
    final loading = h.owner.loadOlder('a', generation: lease.generation);
    final scope = h.a.scopes.single;
    await scope.requested.future;
    final closing = h.owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 15)),
    );
    expect(h.owner.source.value, isNull);
    expect(h.owner.close(), same(closing));
    final report = await closing;
    expect(report.complete, isFalse);
    expect(lease.isReleased, isFalse);
    expect(scope.isActive, isFalse);
    scope.reply.complete(
      ChatBatch(
        placement: ChatPlacement.prepend,
        entries: const [],
        before: null,
      ),
    );
    await loading;
    await lease.unbind();
    expect(lease.isReleased, isTrue);
    expect((await h.owner.close()).complete, isTrue);
  });

  test(
    'failed native reader close keeps the lease until a successful retry',
    () async {
      final h = _Harness();
      await h.openA([_text('a', 1)]);
      final lease = h.owner.lease('a')!;
      final scope = lease.openDetailQueries()! as _Scope;
      scope.failClose = true;
      final report = await h.owner.close(
        deadline: DateTime.now().add(const Duration(milliseconds: 15)),
      );
      expect(report.complete, isFalse);
      expect(lease.queryCleanupError, isNotNull);
      expect(lease.isReleased, isFalse);
      scope.failClose = false;
      expect((await h.owner.close()).complete, isTrue);
      expect(lease.isReleased, isTrue);
    },
  );
}

ChatAtom _text(String thread, int seq) =>
    chatMessage('$thread-$seq', body: 'body-$seq', completionSeq: seq);

final class _Harness {
  _Harness({bool viewport = true}) {
    repository.sessions['a'] = _Session('a', a);
    repository.sessions['b'] = _Session('b', b);
    owner = TimelineSessionOwner(client: _Client(repository));
    if (viewport) owner.updateReadDemand(chatDemand);
  }
  final a = _Content('a');
  final b = _Content('b');
  final repository = _Repository();
  late final TimelineSessionOwner owner;
  Future<void> openA(List<ChatAtom> items, {bool hasOlder = false}) async {
    owner.select('a');
    await a.deliver(chatBatch(items, before: hasOlder ? 'before-3' : null));
  }
}

final class _Client extends Fake implements AnyworkClient {
  _Client(this.conversations);
  @override
  final ConversationRepository conversations;
}

final class _Repository extends Fake implements ConversationRepository {
  final sessions = <String, ConversationSession>{};
  @override
  ConversationSession? existingSession(String threadId) => sessions[threadId];
}

final class _Session extends Fake implements ConversationSession {
  _Session(this.threadId, this.content);
  @override
  final String threadId;
  @override
  final ConversationContent content;
}

final class _Content extends Fake implements ConversationContent {
  _Content(this.threadId) : state = LatestValue(ChatReady(threadId, true));
  @override
  final String threadId;
  @override
  final LatestValue<ChatUiState<bool>> state;
  ConversationBatchConsumer? consumer;
  void Function()? onAttach;
  void Function()? onDetach;
  int attaches = 0;
  int refreshes = 0;
  final scopes = <_Scope>[];
  final payloads = <String, List<int>>{};
  @override
  Observation attachConsumer(
    ConversationBatchConsumer value, {
    required ReadDemand demand,
  }) {
    if (consumer != null) throw StateError('duplicate consumer');
    attaches++;
    consumer = value;
    onAttach?.call();
    return _Observation(() {
      if (identical(consumer, value)) consumer = null;
      onDetach?.call();
    });
  }

  Future<void> deliver(ChatBatch batch) => consumer!.applyBatch(batch);
  @override
  void refresh() => refreshes++;
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = _Scope(threadId, generation, consumer!)..payloads = payloads;
    scopes.add(scope);
    return scope;
  }
}

final class _Observation implements Observation {
  _Observation(this.onCancel);
  final void Function() onCancel;
  @override
  bool isCancelled = false;
  @override
  bool isPaused = false;
  @override
  void pause() => isPaused = true;
  @override
  void resume() => isPaused = false;
  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    onCancel();
  }
}

final class _Scope extends Fake implements ConversationQueryScope {
  _Scope(this.threadId, this.generation, this.consumer);
  final ConversationBatchConsumer consumer;
  @override
  final String threadId;
  @override
  final int generation;
  @override
  bool isActive = true;
  bool failClose = false;
  bool closed = false;
  int closeCalls = 0;
  final bodyRequests = <Completer<ContentWindow>>[];
  Map<String, List<int>> payloads = const {};
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    if (reference.target case ItemPayloadTarget(:final itemId)
        when payloads.containsKey(itemId)) {
      final bytes = payloads[itemId]!;
      return Future.value(
        ContentWindow(
          offset: range.offset,
          bytes: bytes.skip(range.offset).take(range.maxBytes).toList(),
          generation: 'frozen',
          availableThrough: bytes.length,
          sealed: true,
        ),
      );
    }
    final request = Completer<ContentWindow>();
    bodyRequests.add(request);
    _reading = request.future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return request.future;
  }

  final requested = Completer<void>();
  Completer<ChatBatch> reply = Completer<ChatBatch>();
  Future<void>? _reading;
  final boundaries = <String?>[];
  Completer<ChatBatch> window = Completer<ChatBatch>();
  int? windowAnchor;
  String? windowBefore;
  @override
  Future<ChatBatch> readAt({
    required int completionSeq,
    String? before,
    required ReadDemand demand,
  }) {
    windowAnchor = completionSeq;
    windowBefore = before;
    final result = window.future;
    _reading = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<ChatBatch> readBefore({
    required int completionSeq,
    String? before,
    required ReadDemand demand,
  }) {
    windowAnchor = completionSeq;
    windowBefore = before;
    final result = window.future;
    _reading = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) {
    boundaries.add(before);
    if (!requested.isCompleted) requested.complete();
    // Match the SDK boundary: resolve only after the captured consumer admits
    // the batch. Retired scopes never redirect a page into a later consumer.
    final result = reply.future.then((batch) async {
      if (isActive) await consumer.applyBatch(batch);
      return batch;
    });
    _reading = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  void retire() => isActive = false;
  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    closeCalls++;
    retire();
    await _reading;
    if (failClose) throw StateError('native close failed');
    closed = true;
    return CloseReport();
  }
}
