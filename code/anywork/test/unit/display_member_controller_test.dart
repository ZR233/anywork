import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/display_member_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = DisplayBlockRef(
  blockId: 'group',
  cut: HistoryCut('H1'),
  anchorSeq: 1,
  headSeq: 2,
);
const _nextRef = DisplayBlockRef(
  blockId: 'group',
  cut: HistoryCut('H2'),
  anchorSeq: 1,
  headSeq: 3,
);
const _demand = ReadDemand(maxItems: 12, maxBytes: 32768);

DisplayMemberHead _head(
  int order, {
  String? text,
  bool frozen = false,
  String? key,
}) => DisplayMemberHead(
  memberKey: key ?? 'row-$order',
  memberOrder: order * 7,
  record: DisplayRecord(
    contentSource: frozen
        ? const FrozenObservation(capturedAt: 100, available: true)
        : const CurrentAtomSource(),
    atom: ChatAtom(
      id: 'atom-$order',
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      sourceOrder: order,
      kind: ChatAtomKind.reasoning,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const ActiveChatAtom(
        started: null,
        status: ChatActiveStatus.running,
      ),
      contents: const [],
      payload: InlinePayload(bytes: (text ?? 'row-$order').codeUnits),
    ),
  ),
);
DisplayMemberBatch _batch(
  List<DisplayMemberHead> entries, {
  DisplayBlockRef reference = _ref,
  int offset = 0,
  bool complete = true,
}) => DisplayMemberBatch(
  block: reference,
  offset: offset,
  complete: complete,
  entries: entries,
);
Future<void> _drain() => Future<void>.delayed(Duration.zero);
DisplayMemberController _controller(_Handle handle) => DisplayMemberController(
  reference: _ref,
  groupClosed: false,
  demand: _demand,
  open: (_, _, _) async => handle,
);

void main() {
  test(
    '120 members across bounded History pages publish together in owner order',
    () async {
      final handle = _Handle();
      final controller = _controller(handle);
      addTearDown(controller.close);
      await handle.pulling.future;
      for (var offset = 0; offset < 120; offset += 12) {
        handle.reply.complete(
          _batch(
            [
              for (var index = 0; index < 12; index++)
                _head(120 - offset - index),
            ],
            offset: offset,
            complete: offset == 108,
          ),
        );
        await _drain();
        if (offset != 108) {
          expect(controller.entries, isEmpty);
          expect(controller.hasSnapshot, isFalse);
        }
      }
      expect(controller.entries.map((e) => e.memberKey), [
        for (var i = 1; i <= 120; i++) 'row-$i',
      ]);
      expect(controller.hasSnapshot, isTrue);
      expect(controller.error, isNull);
      expect(handle.closed.isCompleted, isTrue);
    },
  );

  for (final eof in [false, true]) {
    test(
      'incomplete new cut retains the previous result on ${eof ? 'EOF' : 'failure'}',
      () async {
        final old = _Handle();
        final next = _Handle();
        var opens = 0;
        final controller = DisplayMemberController(
          reference: _ref,
          groupClosed: false,
          demand: _demand,
          open: (_, _, _) async => ++opens == 1 ? old : next,
        );
        addTearDown(controller.close);
        await old.pulling.future;
        old.reply.complete(_batch([_head(1)]));
        await _drain();
        final previous = controller.entries;
        final disclosure = controller.disclosure('row-1')..expanded = true;
        controller.rebase(_nextRef, groupClosed: true);
        expect(disclosure.retired, isTrue);
        expect(controller.disclosure('row-1').expanded, isTrue);
        await next.pulling.future;
        next.reply.complete(
          _batch(
            [_head(2, frozen: true)],
            reference: _nextRef,
            complete: false,
          ),
        );
        await _drain();
        expect(controller.entries, same(previous));
        expect(controller.hasSnapshot, isFalse);
        if (eof) {
          next.reply.complete(null);
        } else {
          next.reply.completeError(StateError('controlled read failure'));
        }
        await _drain();
        expect(controller.entries, same(previous));
        expect(
          controller.error,
          eof ? isA<ConversationContinuityError>() : isA<StateError>(),
        );
        expect(controller.awaitingSealed, isTrue);
      },
    );
  }

  test(
    'new complete cut preserves expansion and notifies only the changed row',
    () async {
      final old = _Handle();
      final next = _Handle();
      var opens = 0;
      final controller = DisplayMemberController(
        reference: _ref,
        groupClosed: false,
        demand: _demand,
        open: (_, _, _) async => ++opens == 1 ? old : next,
      );
      addTearDown(controller.close);
      await old.pulling.future;
      old.reply.complete(_batch([_head(1), _head(2)]));
      await _drain();
      var first = 0, last = 0;
      var listUpdates = 0;
      controller.addListener(() => listUpdates++);
      controller.member('row-1').addListener(() => first++);
      controller.member('row-2').addListener(() => last++);
      final disclosure = controller.disclosure('row-1')..expanded = true;
      controller.rebase(_nextRef, groupClosed: false);
      await next.pulling.future;
      next.reply.complete(
        _batch([_head(1, text: 'new body'), _head(2)], reference: _nextRef),
      );
      await _drain();
      expect((first, last), (1, 0));
      expect(listUpdates, 0);
      expect(controller.disclosure('row-1'), same(disclosure));
      expect(controller.error, isNull);
    },
  );

  test('Current updates one open member without rereading History', () async {
    final handle = _Handle();
    var reads = 0;
    final controller = DisplayMemberController(
      reference: _ref,
      groupClosed: false,
      demand: _demand,
      open: (_, _, _) async {
        reads++;
        return handle;
      },
    );
    addTearDown(controller.close);
    await handle.pulling.future;
    handle.reply.complete(_batch([_head(1)]));
    await handle.closed.future;

    CurrentAtom tool(String generation) => CurrentAtom(
      id: 'atom-tool',
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      sourceOrder: 10,
      kind: ChatAtomKind.toolCall,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const ActiveChatAtom(
        started: null,
        status: ChatActiveStatus.running,
      ),
      tool: const ChatToolIdentity(callId: 'c1', name: 'read_file'),
      contents: [
        CurrentAtomContent(
          role: ChatContentRole.toolOutput,
          reference: CurrentContentRef(
            ownerId: 'run',
            domain: 'tool',
            entityId: 'atom-tool',
            contentKey: 'tool.result',
            generation: generation,
          ),
        ),
      ],
    );
    void publish(int revision, List<CurrentAtom> atoms) =>
        controller.updateLive(
          atoms: atoms,
          current: CurrentAtomSnapshot(
            revision: revision,
            ownerId: 'run',
            currentAtoms: atoms,
          ),
        );

    final historyRow = controller.member('row-1');
    final acceptedHistory = historyRow.value;
    final liveRow = controller.member('call:c1');
    var listUpdates = 0, liveUpdates = 0, historyUpdates = 0;
    controller.addListener(() => listUpdates++);
    liveRow.addListener(() => liveUpdates++);
    historyRow.addListener(() => historyUpdates++);
    publish(1, [tool('1')]);
    final disclosure = controller.disclosure('call:c1')..expanded = true;
    expect(controller.entries.map((entry) => entry.memberKey), [
      'row-1',
      'call:c1',
    ]);

    publish(2, [tool('2')]);
    publish(3, [tool('2')]);
    expect(reads, 1);
    expect((listUpdates, liveUpdates, historyUpdates), (1, 2, 0));
    expect(historyRow.value, same(acceptedHistory));
    expect(
      liveRow.value!.record.currentContents.single.reference.generation,
      '2',
    );
    expect(controller.disclosure('call:c1'), same(disclosure));

    publish(4, []);
    expect(controller.entries.single.memberKey, 'row-1');
    expect(liveRow.value, isNull);
    expect(listUpdates, 2);
    expect(disclosure.retired, isTrue);
  });

  for (final fault in ['cut', 'offset', 'key', 'order', 'empty']) {
    test(
      'invalid History member $fault never publishes a complete group',
      () async {
        final handle = _Handle();
        final controller = _controller(handle);
        addTearDown(controller.close);
        await handle.pulling.future;
        handle.reply.complete(switch (fault) {
          'cut' => _batch([_head(1)], reference: _nextRef),
          'offset' => _batch([_head(1)], offset: 1),
          'key' => _batch([_head(1), _head(2, key: 'row-1')]),
          'order' => _batch([_head(1), _head(1, key: 'other')]),
          _ => _batch([], complete: false),
        });
        await _drain();
        expect(controller.error, isA<ConversationContinuityError>());
        expect(controller.hasSnapshot, isFalse);
        expect(controller.entries, isEmpty);
      },
    );
  }

  test('retiring a pending open joins and closes its late success without publishing', () async {
    final opened = Completer<DisplayMembers>();
    final handle = _Handle();
    final controller = DisplayMemberController(
      reference: _ref,
      groupClosed: false,
      demand: _demand,
      open: (_, _, _) => opened.future,
    );
    await _drain();
    controller.retire();
    var joined = false;
    final closing = controller.close().then((_) => joined = true);
    await _drain();
    expect(joined, isFalse);
    opened.complete(handle);
    await closing;
    expect(handle.requested, isTrue);
    expect(handle.closed.isCompleted, isTrue);
    expect(controller.hasSnapshot, isFalse);
    expect(controller.error, isNull);
  });

  test(
    'retry drops pending cut and ignores obsolete acquisition failure',
    () async {
      final opened = Completer<DisplayMembers>();
      final fresh = _Handle();
      var opens = 0;
      final controller = DisplayMemberController(
        reference: _ref,
        groupClosed: false,
        demand: _demand,
        open: (_, _, _) => ++opens == 1 ? opened.future : Future.value(fresh),
      );
      addTearDown(controller.close);
      await _drain();
      await controller.retry();
      await fresh.pulling.future;
      fresh.reply.complete(_batch([_head(1)]));
      await _drain();
      opened.completeError(StateError('obsolete'));
      await _drain();
      expect(controller.hasSnapshot, isTrue);
      expect(controller.error, isNull);
    },
  );

  test(
    'retry keeps failed original close obligation until that same handle joins',
    () async {
      final failure = StateError('close failed');
      final old = _Handle()..closeFailure = failure;
      final fresh = _Handle();
      var opens = 0;
      final controller = DisplayMemberController(
        reference: _ref,
        groupClosed: false,
        demand: _demand,
        open: (_, _, _) async => ++opens == 1 ? old : fresh,
      );
      await old.pulling.future;
      old.reply.completeError(StateError('read failed'));
      await _drain();
      expect(controller.cleanupError, same(failure));
      old.closeFailure = null;
      old.closeGate = Completer<void>();
      final retry = controller.retry();
      await _drain();
      expect(old.closeCalls, 2);
      expect(opens, 1);
      expect(controller.error, same(failure));
      old.closeGate!.complete();
      await retry;
      await fresh.pulling.future;
      fresh.reply.complete(_batch([_head(1)]));
      await _drain();
      expect(controller.cleanupError, isNull);
      expect(controller.hasSnapshot, isTrue);
      await controller.close();
    },
  );

  test(
    'closing a different late handle cannot erase an unresolved cleanup error',
    () async {
      final late = Completer<DisplayMembers>();
      final failure = StateError('late original close failed');
      final original = _Handle()..closeFailure = failure;
      final current = _Handle()..closeGate = Completer<void>();
      final fresh = _Handle();
      var opens = 0;
      final controller = DisplayMemberController(
        reference: _ref,
        groupClosed: false,
        demand: _demand,
        open: (_, _, _) => switch (++opens) {
          1 => late.future,
          2 => Future.value(current),
          _ => Future.value(fresh),
        },
      );
      await _drain();
      await controller.retry();
      await current.pulling.future;
      late.complete(original);
      await _drain();
      expect(controller.cleanupError, same(failure));
      final restarting = controller.retry();
      await _drain();
      current.closeGate!.complete();
      await restarting;
      await _drain();
      expect(controller.cleanupError, same(failure));
      expect(opens, 2);
      original.closeFailure = null;
      await controller.retry();
      await fresh.pulling.future;
      expect(original.closeCalls, greaterThanOrEqualTo(2));
      fresh.reply.complete(_batch([]));
      await _drain();
      expect(controller.error, isNull);
      await controller.close();
    },
  );
}

class _Handle implements DisplayMembers {
  Completer<DisplayMemberBatch?> reply = Completer();
  final pulling = Completer<void>();
  final closed = Completer<void>();
  bool requested = false, waiting = false;
  int calls = 0, closeCalls = 0;
  Object? closeFailure;
  Completer<void>? closeGate;
  @override
  Future<DisplayMemberBatch?> next() {
    calls++;
    waiting = true;
    if (!pulling.isCompleted) {
      pulling.complete();
    }
    final original = reply;
    return original.future
        .then((batch) {
          if (identical(reply, original)) {
            reply = Completer<DisplayMemberBatch?>();
          }
          return batch;
        })
        .whenComplete(() => waiting = false);
  }

  @override
  void requestClose() {
    requested = true;
    if (waiting && !reply.isCompleted) {
      reply.completeError(const StaleConversationScope());
    }
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await closeGate?.future;
    if (closeFailure case final failure?) {
      throw failure;
    }
    if (!closed.isCompleted) {
      closed.complete();
    }
  }
}
