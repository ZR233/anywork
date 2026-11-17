import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 4096);
const _reference = DisplayBlockRef(databaseId: 'db', blockId: 'work');

DisplayMemberHead _head(
  String key,
  int order, {
  int finishedAt = 20,
  String? completionId,
  ChatAtomLifecycle? lifecycle,
  ChatSourceState? sourceState,
  ContentRef? body,
  PayloadData? payload,
}) => DisplayMemberHead(
  memberKey: key,
  memberOrder: order,
  record: DisplayRecord(
    atom: ChatAtom(
      id: key,
      completionItemId: key,
      completionSeq: 7,
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      sourceState: sourceState,
      sourceOrder: 4,
      kind: ChatAtomKind.reasoning,
      delivery: ChatDeliveryKind.foreground,
      lifecycle:
          lifecycle ??
          const TerminalChatAtom(
            started: ChatFactPosition(effectSeq: 3, suborder: 1),
            ended: ChatFactPosition(effectSeq: 8, suborder: 2),
            outcome: ChatTerminalOutcome.completed,
          ),
      turnId: 'turn',
      attemptId: 'attempt',
      textChannel: ThreadTextChannel.finalAnswer,
      contentPresent: true,
      startedAt: 10,
      finishedAt: finishedAt,
      contents: [
        ChatAtomContent(
          role: ChatContentRole.reasoningSummary,
          reference:
              body ??
              ContentRef(
                databaseId: 'db',
                target: BodyContentTarget(
                  owner: ItemContentOwner(itemId: key),
                  key: 'summary',
                ),
              ),
        ),
      ],
      payload: payload ?? InlinePayload(bytes: [1, 2, 3]),
    ),
    contentSource: CompletedOriginal(completionId: completionId ?? key),
  ),
);

DisplayMemberBatch _batch(
  List<DisplayMemberHead> entries, {
  int revision = 11,
  int offset = 0,
  bool sealed = false,
  bool complete = true,
  DisplayBlockRef block = _reference,
}) => DisplayMemberBatch(
  block: block,
  revision: revision,
  offset: offset,
  sealed: sealed,
  complete: complete,
  entries: entries,
);

Future<(DisplayMembers, _Members)> _openMembers(_Harness h) async {
  final feed = await h.open();
  final native = _Members();
  feed.members = native;
  final members = await h
      .scope(generation: 1)
      .openDisplayMembers(
        reference: _reference,
        demand: const ReadDemand(maxItems: 12, maxBytes: 32768),
      );
  return (members, native);
}

Future<DisplayMemberBatch?> _deliver(
  DisplayMembers members,
  _Members native,
  DisplayMemberBatch? batch,
) {
  native.pending = Completer<DisplayMemberBatch?>();
  final result = members.next();
  native.pending.complete(batch);
  return result;
}

void main() {
  test(
    'complete sealed batches preserve sparse order and deliver all members',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final (members, native) = await _openMembers(h);
      final heads = [for (var i = 0; i < 15; i++) _head('m$i', i * 3 + 2)];
      final delivered = <DisplayMemberHead>[];
      for (var offset = 0; offset < heads.length; offset += 4) {
        final end = (offset + 4).clamp(0, heads.length);
        final batch = _batch(
          heads.sublist(offset, end),
          offset: offset,
          sealed: true,
          complete: end == heads.length,
        );
        expect(await _deliver(members, native, batch), same(batch));
        delivered.addAll(batch.entries);
      }
      expect(delivered, orderedEquals(heads));
      expect(delivered.map((head) => head.memberKey).toSet(), hasLength(15));
      expect(
        delivered.map((head) => head.memberOrder),
        orderedEquals([for (var i = 0; i < 15; i++) i * 3 + 2]),
      );
      expect(await _deliver(members, native, null), isNull);
      expect(await members.next(), isNull);
      await members.close();
      expect(native.closeCalls, 1);
    },
  );

  test('sealed incomplete batch continues; a later complete batch closes the group', () async {
    final h = _Harness();
    addTearDown(h.close);
    final (members, native) = await _openMembers(h);
    final first = _batch([_head('first', 5)], sealed: true, complete: false);
    expect(await _deliver(members, native, first), same(first));
    final second = _batch(
      [_head('second', 20)],
      offset: 1,
      sealed: true,
      complete: true,
    );
    expect(await _deliver(members, native, second), same(second));
    expect(await _deliver(members, native, null), isNull);
    await members.close();
  });

  test(
    'new revision may replace an earlier row before final sealing',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final (members, native) = await _openMembers(h);
      final original = _batch([
        _head('same', 8, finishedAt: 20),
      ], complete: true);
      expect(await _deliver(members, native, original), same(original));
      final replacement = _batch(
        [_head('same', 8, finishedAt: 21)],
        revision: 12,
        sealed: true,
        complete: true,
      );
      expect(await _deliver(members, native, replacement), same(replacement));
      expect(await _deliver(members, native, null), isNull);
      await members.close();
    },
  );

  test('same revision may be re-delivered sealed only with identical full contents', () async {
    final h = _Harness();
    addTearDown(h.close);
    final (members, native) = await _openMembers(h);
    final rows = [_head('a', 2), _head('b', 9)];
    final open = _batch(rows, complete: true);
    expect(await _deliver(members, native, open), same(open));
    final sealedFirst = _batch([rows.first], sealed: true, complete: false);
    expect(await _deliver(members, native, sealedFirst), same(sealedFirst));
    final sealedLast = _batch(
      [rows.last],
      offset: 1,
      sealed: true,
      complete: true,
    );
    expect(await _deliver(members, native, sealedLast), same(sealedLast));
    expect(await _deliver(members, native, null), isNull);
    await members.close();
  });

  final invalidStreams = <String, List<DisplayMemberBatch?>>{
    'initial EOF': [null],
    'initial offset is nonzero': [
      _batch([_head('a', 1)], offset: 1),
    ],
    'EOF in a partial result': [
      _batch([_head('a', 1)], complete: false),
      null,
    ],
    'EOF after an open complete result': [
      _batch([_head('a', 1)], complete: true),
      null,
    ],
    'empty incomplete batch': [_batch([], complete: false)],
    'batch exceeds demand maxItems': [
      _batch([for (var i = 0; i < 13; i++) _head('m$i', i + 1)]),
    ],
    'offset gap': [
      _batch([_head('a', 1)], complete: false),
      _batch([_head('b', 2)], offset: 2),
    ],
    'offset overlap': [
      _batch([_head('a', 1)], complete: false),
      _batch([_head('b', 2)], offset: 0),
    ],
    'mixed revision': [
      _batch([_head('a', 1)], complete: false),
      _batch([_head('b', 2)], revision: 12, offset: 1),
    ],
    'mixed block': [
      _batch([_head('a', 1)], complete: false),
      _batch(
        [_head('b', 2)],
        offset: 1,
        block: const DisplayBlockRef(databaseId: 'db', blockId: 'elsewhere'),
      ),
    ],
    'mixed sealed state': [
      _batch([_head('a', 1)], sealed: true, complete: false),
      _batch([_head('b', 2)], offset: 1, sealed: false),
    ],
    'empty key': [
      _batch([_head('', 1)]),
    ],
    'duplicate key across batches': [
      _batch([_head('a', 1)], complete: false),
      _batch([_head('a', 2)], offset: 1),
    ],
    'zero member order': [
      _batch([_head('a', 0)]),
    ],
    'non-increasing order across batches': [
      _batch([_head('a', 9)], complete: false),
      _batch([_head('b', 8)], offset: 1),
    ],
    'non-increasing order within batch': [
      _batch([_head('a', 3), _head('b', 3)]),
    ],
    'same revision after completed result': [
      _batch([_head('a', 1)], complete: true),
      _batch([_head('b', 2)], complete: true),
    ],
    'revision regresses after completed result': [
      _batch([_head('a', 1)], revision: 12, complete: true),
      _batch([_head('b', 2)], revision: 11, complete: true),
    ],
    'sealed result followed by more data': [
      _batch([_head('a', 1)], sealed: true),
      _batch([_head('b', 2)], revision: 12, sealed: true),
    ],
  };
  for (final testCase in invalidStreams.entries) {
    test('rejects ${testCase.key} as continuity error', () async {
      final h = _Harness();
      addTearDown(h.close);
      final (members, native) = await _openMembers(h);
      final stream = testCase.value;
      for (var i = 0; i < stream.length - 1; i++) {
        final validPrefixBatch = stream[i];
        expect(
          await _deliver(members, native, validPrefixBatch),
          same(validPrefixBatch),
          reason: '${testCase.key}: valid prefix batch $i must be accepted',
        );
      }
      await expectLater(
        _deliver(members, native, stream.last),
        throwsA(isA<ConversationContinuityError>()),
        reason: '${testCase.key}: only the final invalid input must fail',
      );
      await members.close();
    });
  }

  test('same-revision multi-batch sealing rejects a changed row', () async {
    final h = _Harness();
    addTearDown(h.close);
    final (members, native) = await _openMembers(h);
    final first = _head('a', 2);
    final second = _head('b', 8);
    final openFirst = _batch([first], complete: false);
    expect(await _deliver(members, native, openFirst), same(openFirst));
    final openLast = _batch([second], offset: 1, complete: true);
    expect(await _deliver(members, native, openLast), same(openLast));
    final changedFirst = _batch(
      [_head('a', 2, finishedAt: 21)],
      sealed: true,
      complete: false,
    );
    await expectLater(
      _deliver(members, native, changedFirst),
      throwsA(isA<ConversationContinuityError>()),
    );
    final sealedFirst = _batch([first], sealed: true, complete: false);
    expect(await _deliver(members, native, sealedFirst), same(sealedFirst));
    final sealedLast = _batch([second], offset: 1, sealed: true);
    expect(await _deliver(members, native, sealedLast), same(sealedLast));
    expect(await _deliver(members, native, null), isNull);
    await members.close();
  });

  test('same-revision seal verifies every display field', () async {
    final h = _Harness();
    addTearDown(h.close);
    final (members, native) = await _openMembers(h);
    final original = _head('member', 2);
    final deferred = _head(
      'other',
      9,
      payload: const DeferredPayload(
        reference: ContentRef(
          databaseId: 'db',
          target: ItemPayloadTarget(itemId: 'other'),
        ),
        byteLength: 37,
      ),
    );
    final open = _batch([original, deferred], complete: true);
    expect(await _deliver(members, native, open), same(open));
    final changedFact = DisplayMemberHead(
      memberKey: original.memberKey,
      memberOrder: original.memberOrder,
      record: DisplayRecord(
        atom: original.record.atom,
        startFact: const ChatFactPosition(effectSeq: 99, suborder: 0),
        endFact: original.record.endFact,
        contentSource: original.record.contentSource,
      ),
    );
    final changedSource = DisplayMemberHead(
      memberKey: original.memberKey,
      memberOrder: original.memberOrder,
      record: DisplayRecord(
        atom: original.record.atom,
        startFact: original.record.startFact,
        endFact: original.record.endFact,
        contentSource: const FrozenObservation(capturedAt: 50, available: true),
      ),
    );
    final changes = <String, List<DisplayMemberHead>>{
      'member key': [_head('rewritten', 2), deferred],
      'member order': [_head('member', 3), deferred],
      'completion identity': [
        _head('member', 2, completionId: 'rewritten'),
        deferred,
      ],
      'fact cut': [changedFact, deferred],
      'content source': [changedSource, deferred],
      'atom metadata': [_head('member', 2, finishedAt: 21), deferred],
      'lifecycle evidence': [
        _head(
          'member',
          2,
          lifecycle: const TerminalChatAtom(
            started: ChatFactPosition(effectSeq: 3, suborder: 1),
            ended: ChatFactPosition(effectSeq: 9, suborder: 2),
            outcome: ChatTerminalOutcome.completed,
          ),
        ),
        deferred,
      ],
      'source evidence': [
        _head(
          'member',
          2,
          sourceState: const ChatSourceState(
            source: ForegroundTurnChatSource(turnId: 'turn'),
            lifecycle: ActiveChatSource(),
            started: null,
            ended: null,
          ),
        ),
        deferred,
      ],
      'body capability': [
        _head(
          'member',
          2,
          body: const ContentRef(
            databaseId: 'db',
            target: ItemPayloadTarget(itemId: 'rewritten'),
          ),
        ),
        deferred,
      ],
      'inline payload': [
        _head('member', 2, payload: InlinePayload(bytes: [1, 2, 4])),
        deferred,
      ],
      'deferred payload': [
        original,
        _head(
          'other',
          9,
          payload: const DeferredPayload(
            reference: ContentRef(
              databaseId: 'db',
              target: ItemPayloadTarget(itemId: 'other'),
            ),
            byteLength: 38,
          ),
        ),
      ],
    };
    for (final change in changes.entries) {
      await expectLater(
        _deliver(members, native, _batch(change.value, sealed: true)),
        throwsA(isA<ConversationContinuityError>()),
        reason: 'Changed ${change.key} must invalidate same-revision sealing',
      );
    }
    final sealed = _batch([original, deferred], sealed: true);
    expect(await _deliver(members, native, sealed), same(sealed));
    expect(await _deliver(members, native, null), isNull);
    await members.close();
  });

  test('sealed empty complete result permits EOF', () async {
    final h = _Harness();
    addTearDown(h.close);
    final (members, native) = await _openMembers(h);
    final empty = _batch([], sealed: true);
    expect(await _deliver(members, native, empty), same(empty));
    expect(await _deliver(members, native, null), isNull);
    await members.close();
  });

  test(
    'single-flight and close wake/join preserve native error behavior',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final feed = await h.open();
      final native = _Members();
      feed.members = native;
      final scope = h.scope(generation: 1);
      final members = await scope.openDisplayMembers(
        reference: _reference,
        demand: _demand,
      );
      final first = members.next();
      native.pending.complete(_batch([_head('a', 10)], complete: true));
      expect((await first)!.entries.single.memberKey, 'a');
      native.pending = Completer<DisplayMemberBatch?>();
      final next = members.next();
      final stale = expectLater(next, throwsA(isA<StaleConversationScope>()));
      await expectLater(members.next(), throwsStateError);
      native.closeFailure = StateError('join failed');
      scope.retire();
      expect(native.requested, isTrue);
      await stale;
      final report = await scope.close();
      expect(report.complete, isFalse);
      native.closeFailure = null;
      expect((await scope.close()).complete, isTrue);
      expect(native.closeCalls, 2);
    },
  );

  test('late member open is closed under its original retired scope', () async {
    final h = _Harness();
    addTearDown(h.close);
    final feed = await h.open();
    final response = Completer<DisplayMembers>();
    feed.membersOpening = response;
    final scope = h.scope(generation: 1);
    final opening = scope.openDisplayMembers(
      reference: _reference,
      demand: _demand,
    );
    final stale = expectLater(opening, throwsA(isA<StaleConversationScope>()));
    scope.retire();
    final native = _Members();
    response.complete(native);
    await stale;
    expect(native.requested, isTrue);
    expect(native.closeCalls, 1);
    expect((await scope.close()).complete, isTrue);
  });
}

final class _Harness {
  _Harness() {
    fixture = ConversationFixture(transport: transport);
  }
  final _Transport transport = _Transport();
  late final ConversationFixture fixture;
  final Set<ConversationReadScope> scopes = {};
  _Reader? reader;
  Future<_Reader> open() async {
    final opening = fixture.repository.openTimelineReader(
      'thread',
      demand: _demand,
    );
    await transport.openedTimeline(0);
    final result = _Reader();
    reader = result;
    transport.timelineOpens[0].complete(result);
    expect(await opening, same(result));
    return result;
  }

  ConversationReadScope scope({required int generation}) {
    final owner = reader!;
    final result = ConversationReadScope(
      threadId: 'thread',
      generation: generation,
      reader: owner.reader,
      timeline: owner,
      isEligible: () => !owner.closed,
    );
    scopes.add(result);
    return result;
  }

  Future<void> close() async {
    for (final scope in scopes) {
      scope.retire();
      expect((await scope.close()).complete, isTrue);
    }
    await reader?.close();
    expect((await fixture.close()).complete, isTrue);
  }
}

final class _Transport extends TestConversationTransport
    implements TimelineTransport {
  final List<Completer<TimelineReader>> timelineOpens = [];
  final Map<int, Completer<void>> _opening = {};
  @override
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required int presentationVersion,
    required int readerProtocolVersion,
    required ReadDemand demand,
  }) {
    expect(threadId, 'thread');
    expect(presentationVersion, 6);
    expect(readerProtocolVersion, 1);
    expect(demand, same(_demand));
    final result = Completer<TimelineReader>();
    timelineOpens.add(result);
    _opening.remove(timelineOpens.length - 1)?.complete();
    return result.future;
  }

  Future<void> openedTimeline(int index) => timelineOpens.length > index
      ? Future.value()
      : (_opening[index] ??= Completer<void>()).future;
}

final class _Reader implements TimelineReader {
  @override
  final TestConversationReader reader = TestConversationReader();
  @override
  final OpenTimeline metadata = const OpenTimeline(
    readerId: 'reader',
    presentationVersion: 6,
    readerProtocolVersion: 1,
    initialCursor: ViewCursor('opaque'),
  );
  DisplayMembers? members;
  Completer<DisplayMembers>? membersOpening;
  bool closed = false;
  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => throw UnimplementedError();
  @override
  Future<TailSnapshot> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) => throw UnimplementedError();
  @override
  Future<ViewUpdate> next({required ViewCursor after}) =>
      throw UnimplementedError();
  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required ReadDemand demand,
  }) async => membersOpening == null ? members! : await membersOpening!.future;
  @override
  void requestClose() {
    closed = true;
  }

  @override
  Future<void> close() async => requestClose();
}

final class _Members implements DisplayMembers {
  Completer<DisplayMemberBatch?> pending = Completer();
  bool listening = false;
  bool requested = false;
  int closeCalls = 0;
  Object? closeFailure;
  @override
  Future<DisplayMemberBatch?> next() {
    listening = true;
    return pending.future;
  }

  @override
  void requestClose() {
    requested = true;
    if (listening && !pending.isCompleted) {
      pending.completeError(const StaleConversationScope());
    }
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (closeFailure case final failure?) throw failure;
  }
}
