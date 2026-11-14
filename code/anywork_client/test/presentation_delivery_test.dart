import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 4096);
const _reference = DisplayBlockRef(databaseId: 'db', blockId: 'work');

DisplayMemberHead _sealHead({
  String memberKey = 'member',
  int order = 1,
  String completionId = 'member',
  int finishedAt = 20,
  ChatAtomLifecycle? lifecycle,
  ChatSourceState? sourceState,
  ContentRef? body,
  PayloadData? payload,
}) => DisplayMemberHead(
  memberKey: memberKey,
  memberOrder: order,
  record: DisplayRecord(
    atom: ChatAtom(
      id: 'member',
      completionItemId: 'member',
      completionSeq: 7,
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      sourceState: sourceState,
      sourceOrder: 4,
      kind: ChatAtomKind.reasoning,
      delivery: ChatDeliveryKind.foreground,
      lifecycle:
          lifecycle ??
          TerminalChatAtom(
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
              const ContentRef(
                databaseId: 'db',
                target: BodyContentTarget(
                  owner: ItemContentOwner(itemId: 'member'),
                  key: 'summary',
                ),
              ),
        ),
      ],
      payload: payload ?? InlinePayload(bytes: [1, 2, 3]),
    ),
    contentSource: CompletedOriginal(completionId: completionId),
  ),
);

DisplayMemberPage _sealPage({
  int revision = 11,
  bool sealed = false,
  DisplayBlockRef block = _reference,
  List<DisplayMemberHead>? entries,
  int lastOrder = 2,
  int? before,
}) => DisplayMemberPage(
  block: block,
  revision: revision,
  sealed: sealed,
  entries:
      entries ??
      [
        _sealHead(),
        _sealHead(
          memberKey: 'other',
          order: lastOrder,
          completionId: 'other',
          payload: const DeferredPayload(
            reference: ContentRef(
              databaseId: 'db',
              target: ItemPayloadTarget(itemId: 'other'),
            ),
            byteLength: 37,
          ),
        ),
      ],
  before: before,
);

Future<(DisplayMembers, _Members)> _openSealMembers(_Harness h) async {
  final feed = await h.open();
  final native = _Members();
  feed.members = native;
  final members = await h
      .scope(generation: 1)
      .openDisplayMembers(
        reference: _reference,
        window: const LatestDisplayMembers(),
        demand: const ReadDemand(maxItems: 12, maxBytes: 32768),
      );
  return (members, native);
}

Future<DisplayMemberPage?> _deliverMemberPage(
  DisplayMembers members,
  _Members native,
  DisplayMemberPage? page,
) {
  native.pending = Completer<DisplayMemberPage?>();
  final result = members.next();
  native.pending.complete(page);
  return result;
}

void main() {
  for (final cold in [false, true]) {
    test(
      'member seal ${cold ? 'cold first page' : 'same revision handoff'} preserves values and reaches EOF',
      () async {
        final h = _Harness();
        addTearDown(h.close);
        final (members, native) = await _openSealMembers(h);
        if (!cold) {
          final live = _sealPage();
          expect(await _deliverMemberPage(members, native, live), same(live));
        }
        // Fresh allocations model the FRB/SQLite page, not reused Dart objects.
        final sealed = _sealPage(sealed: true);
        expect(await _deliverMemberPage(members, native, sealed), same(sealed));
        expect(await _deliverMemberPage(members, native, null), isNull);
        expect(await members.next(), isNull);
        expect(h.transport.timelineOpens, hasLength(1));
        await members.close();
        expect(native.closeCalls, 1);
      },
    );
  }

  test(
    'member seal newer revision may update members before sealing',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final (members, native) = await _openSealMembers(h);
      await _deliverMemberPage(members, native, _sealPage());
      final updated = _sealPage(
        revision: 12,
        entries: [_sealHead(finishedAt: 21)],
      );
      expect(await _deliverMemberPage(members, native, updated), same(updated));
      final sealed = _sealPage(
        revision: 12,
        sealed: true,
        entries: [_sealHead(finishedAt: 21)],
      );
      expect(await _deliverMemberPage(members, native, sealed), same(sealed));
      expect(await _deliverMemberPage(members, native, null), isNull);
      await members.close();
    },
  );

  final invalidSeals = <String, DisplayMemberPage Function()>{
    for (final changeSource in [false, true])
      'changed display ${changeSource ? "content source" : "fact cut"}': () {
        final page = _sealPage(sealed: true);
        return DisplayMemberPage(
          block: page.block,
          revision: page.revision,
          sealed: true,
          before: page.before,
          entries: [
            for (final head in page.entries)
              DisplayMemberHead(
                memberKey: head.memberKey,
                memberOrder: head.memberOrder,
                record: DisplayRecord(
                  atom: head.record.atom,
                  startFact: changeSource
                      ? head.record.startFact
                      : const ChatFactPosition(effectSeq: 99, suborder: 0),
                  endFact: head.record.endFact,
                  contentSource: changeSource
                      ? const FrozenObservation(capturedAt: 50, available: true)
                      : head.record.contentSource,
                ),
              ),
          ],
        );
      },
    'ordinary duplicate': () => _sealPage(),
    'revision regression': () => _sealPage(revision: 10, sealed: true),
    'different database': () => _sealPage(
      sealed: true,
      block: const DisplayBlockRef(databaseId: 'other-db', blockId: 'work'),
    ),
    'different block': () => _sealPage(
      sealed: true,
      block: const DisplayBlockRef(databaseId: 'db', blockId: 'other'),
    ),
    'changed continuation': () => _sealPage(sealed: true, before: 1),
    'missing member': () => _sealPage(sealed: true, entries: [_sealHead()]),
    'changed member identity': () => _sealPage(
      sealed: true,
      entries: [
        _sealHead(memberKey: 'rewritten'),
        _sealPage().entries.last,
      ],
    ),
    'changed member order': () => _sealPage(sealed: true, lastOrder: 3),
    'changed completion': () => _sealPage(
      sealed: true,
      entries: [
        _sealHead(completionId: 'rewritten'),
        _sealPage().entries.last,
      ],
    ),
    'changed metadata': () => _sealPage(
      sealed: true,
      entries: [_sealHead(finishedAt: 21), _sealPage().entries.last],
    ),
    'changed lifecycle evidence': () => _sealPage(
      sealed: true,
      entries: [
        _sealHead(
          lifecycle: const TerminalChatAtom(
            started: ChatFactPosition(effectSeq: 3, suborder: 1),
            ended: ChatFactPosition(effectSeq: 9, suborder: 2),
            outcome: ChatTerminalOutcome.completed,
          ),
        ),
        _sealPage().entries.last,
      ],
    ),
    'changed source evidence': () => _sealPage(
      sealed: true,
      entries: [
        _sealHead(
          sourceState: const ChatSourceState(
            source: ForegroundTurnChatSource(turnId: 'turn'),
            lifecycle: ActiveChatSource(),
            started: null,
            ended: null,
          ),
        ),
        _sealPage().entries.last,
      ],
    ),
    'changed body capability': () => _sealPage(
      sealed: true,
      entries: [
        _sealHead(
          body: const ContentRef(
            databaseId: 'db',
            target: ItemPayloadTarget(itemId: 'rewritten'),
          ),
        ),
        _sealPage().entries.last,
      ],
    ),
    'changed inline payload': () => _sealPage(
      sealed: true,
      entries: [
        _sealHead(payload: InlinePayload(bytes: [1, 2, 4])),
        _sealPage().entries.last,
      ],
    ),
    'changed deferred payload': () => _sealPage(
      sealed: true,
      entries: [
        _sealHead(),
        _sealHead(
          memberKey: 'other',
          order: 2,
          completionId: 'other',
          payload: const DeferredPayload(
            reference: ContentRef(
              databaseId: 'db',
              target: ItemPayloadTarget(itemId: 'other'),
            ),
            byteLength: 38,
          ),
        ),
      ],
    ),
  };
  for (final invalid in invalidSeals.entries) {
    test('member seal rejects ${invalid.key}', () async {
      final h = _Harness();
      addTearDown(h.close);
      final (members, native) = await _openSealMembers(h);
      await _deliverMemberPage(members, native, _sealPage());
      await expectLater(
        _deliverMemberPage(members, native, invalid.value()),
        throwsA(isA<ConversationContinuityError>()),
      );
      final sealed = _sealPage(sealed: true);
      expect(
        await _deliverMemberPage(members, native, sealed),
        same(sealed),
        reason: 'A rejected page must not advance revision or sealing',
      );
      expect(await _deliverMemberPage(members, native, null), isNull);
      await members.close();
    });
  }

  test(
    'member seal rejects any page after sealing, even a newer revision',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final (members, native) = await _openSealMembers(h);
      await _deliverMemberPage(members, native, _sealPage(sealed: true));
      await expectLater(
        _deliverMemberPage(
          members,
          native,
          _sealPage(revision: 12, sealed: true),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(await _deliverMemberPage(members, native, null), isNull);
      await members.close();
    },
  );

  test(
    'a sealed member page is followed by explicit EOF, never a repeated page',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final feed = await h.open();
      final native = _Members();
      feed.members = native;
      final scope = h.scope(generation: 1);
      final members = await scope.openDisplayMembers(
        reference: _reference,
        window: const LatestDisplayMembers(),
        demand: _demand,
      );
      final first = members.next();
      native.pending.complete(
        DisplayMemberPage(
          block: _reference,
          revision: 2,
          sealed: true,
          entries: [],
        ),
      );
      expect((await first)!.sealed, isTrue);
      native.pending = Completer<DisplayMemberPage?>();
      final eof = members.next();
      native.pending.complete(null);
      expect(await eof, isNull);
      expect(await members.next(), isNull);
      await members.close();
    },
  );

  test('member window is bounded, single-flight, and close wakes and joins its exact handle', () async {
    final h = _Harness();
    addTearDown(h.close);
    final feed = await h.open();
    final native = _Members();
    feed.members = native;
    final scope = h.scope(generation: 1);
    final members = await scope.openDisplayMembers(
      reference: _reference,
      window: const LatestDisplayMembers(),
      demand: _demand,
    );
    final initial = members.next();
    native.pending.complete(
      DisplayMemberPage(
        block: _reference,
        revision: 1,
        sealed: false,
        entries: [
          DisplayMemberHead(
            memberKey: 'member',
            memberOrder: 10,
            record: DisplayRecord(
              atom: fixtureMember('member'),
              contentSource: const CurrentAtom(),
            ),
          ),
        ],
        before: 10,
      ),
    );
    final page = await initial;
    expect(page!.entries.single.memberOrder, 10);
    native.pending = Completer<DisplayMemberPage?>();
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
  });

  test('late member open is closed under its original retired scope', () async {
    final h = _Harness();
    addTearDown(h.close);
    final feed = await h.open();
    final response = Completer<DisplayMembers>();
    feed.membersOpening = response;
    final scope = h.scope(generation: 1);
    final opening = scope.openDisplayMembers(
      reference: _reference,
      window: const LatestDisplayMembers(),
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
  Future<TimelinePage> Function(String, ReadDemand)? onOlder;
  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => onOlder!(before, demand);
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
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) async => membersOpening == null ? members! : await membersOpening!.future;
  @override
  void requestClose() {
    closed = true;
  }

  @override
  Future<void> close() async {
    requestClose();
  }
}

final class _Members implements DisplayMembers {
  Completer<DisplayMemberPage?> pending = Completer();
  bool listening = false;
  bool requested = false;
  int closeCalls = 0;
  Object? closeFailure;
  @override
  Future<DisplayMemberPage?> next() {
    listening = true;
    return pending.future;
  }

  @override
  void requestClose() {
    requested = true;
    if (listening && !pending.isCompleted)
      pending.completeError(const StaleConversationScope());
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (closeFailure case final failure?) throw failure;
  }
}
