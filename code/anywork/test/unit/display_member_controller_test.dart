import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/view_models/display_member_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = DisplayBlockRef(databaseId: 'db', blockId: 'group');
const _demand = ReadDemand(maxItems: 12, maxBytes: 32768);

DisplayMemberHead _head(int order, {bool frozen = false, String? text}) =>
    DisplayMemberHead(
      memberKey: 'row-$order',
      memberOrder: order * 7,
      record: DisplayRecord(
        contentSource: frozen
            ? const FrozenObservation(capturedAt: 100, available: true)
            : const CurrentAtom(),
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
  int revision = 1,
  int offset = 0,
  bool complete = true,
  bool sealed = false,
}) => DisplayMemberBatch(
  block: _ref,
  revision: revision,
  offset: offset,
  complete: complete,
  sealed: sealed,
  entries: entries,
);
Future<void> _drain() => Future<void>.delayed(Duration.zero);
DisplayMemberController _controller(_Handle handle) => DisplayMemberController(
  reference: _ref,
  demand: _demand,
  open: (_, _) async => handle,
);

Future<
  ({
    DisplayMemberController controller,
    _Handle fresh,
    List<DisplayMemberHead> retained,
  })
>
_retryAfterSnapshot({
  required bool sealed,
  List<DisplayMemberHead>? entries,
}) async {
  final old = _Handle();
  final fresh = _Handle();
  var opens = 0;
  final controller = DisplayMemberController(
    reference: _ref,
    demand: _demand,
    open: (_, _) async => ++opens == 1 ? old : fresh,
  );
  addTearDown(() async {
    await controller.close();
    controller.dispose();
  });
  await old.pulling.future;
  old.reply.complete(
    _batch(entries ?? [_head(1, frozen: sealed)], revision: 7, sealed: sealed),
  );
  await _drain();
  final retained = controller.entries;
  expect(controller.revision, 7);
  old.reply.completeError(StateError('transient member transport failure'));
  await _drain();
  expect(controller.error, isA<StateError>());
  expect(controller.entries, same(retained));
  await controller.retry();
  await fresh.pulling.future;
  expect(old.closed.isCompleted, isTrue);
  expect(controller.entries, same(retained));
  expect(controller.loading, isTrue);
  return (controller: controller, fresh: fresh, retained: retained);
}

void main() {
  for (final sealed in [false, true]) {
    test('unchanged same revision snapshot resumes after retry sealed=$sealed', () async {
      final retry = await _retryAfterSnapshot(
        sealed: sealed,
        entries: [
          _head(1, frozen: sealed),
          _head(2, frozen: sealed),
        ],
      );
      final controller = retry.controller;
      final row = controller.member('row-1');
      var rowChanges = 0;
      row.addListener(() => rowChanges++);
      final disclosure = controller.disclosure('row-1')..expanded = true;
      retry.fresh.reply.complete(
        _batch(
          [_head(1, frozen: sealed)],
          revision: 7,
          sealed: sealed,
          complete: false,
        ),
      );
      await _drain();
      expect(controller.entries, same(retry.retained));
      expect(controller.loading, isTrue);
      retry.fresh.reply.complete(
        _batch(
          [_head(2, frozen: sealed)],
          revision: 7,
          sealed: sealed,
          offset: 1,
        ),
      );
      await _drain();
      expect(
        controller.error,
        isNull,
        reason: 'A new qualified observation may start at the unchanged current revision',
      );
      expect(controller.loading, isFalse);
      expect(controller.revision, 7);
      expect(controller.sealed, sealed);
      expect(controller.entries.map((e) => e.memberKey), ['row-1', 'row-2']);
      expect(controller.member('row-1'), same(row));
      expect(rowChanges, 0);
      expect(controller.disclosure('row-1'), same(disclosure));
      expect(disclosure.expanded, isTrue);
      expect(
        retry.fresh.requested,
        isFalse,
        reason:
            'Recovery must not swallow the error and close the new observation',
      );
      if (sealed) {
        retry.fresh.reply.complete(null);
        await retry.fresh.closed.future;
        expect(controller.error, isNull);
      } else {
        retry.fresh.reply.complete(
          _batch([_head(1, text: 'later update'), _head(2)], revision: 8),
        );
        await _drain();
        expect(controller.error, isNull);
        expect(controller.revision, 8);
        expect(rowChanges, 1);
      }
    });
  }

  for (final scenario in [
    (
      label: 'revision rollback',
      wasSealed: false,
      nextSealed: false,
      revision: 6,
      changed: false,
    ),
    (
      label: 'open content changed',
      wasSealed: false,
      nextSealed: false,
      revision: 7,
      changed: true,
    ),
    (
      label: 'sealed content changed',
      wasSealed: true,
      nextSealed: true,
      revision: 7,
      changed: true,
    ),
    (
      label: 'content changed while sealing',
      wasSealed: false,
      nextSealed: true,
      revision: 7,
      changed: true,
    ),
    (
      label: 'same revision unsealed',
      wasSealed: true,
      nextSealed: false,
      revision: 7,
      changed: false,
    ),
    (
      label: 'higher revision unsealed',
      wasSealed: true,
      nextSealed: false,
      revision: 8,
      changed: false,
    ),
  ]) {
    test(
      'retry rejects ${scenario.label} without replacing retained snapshot',
      () async {
        final retry = await _retryAfterSnapshot(sealed: scenario.wasSealed);
        retry.fresh.reply.complete(
          _batch(
            [
              _head(
                1,
                frozen: scenario.wasSealed,
                text: scenario.changed ? 'changed' : null,
              ),
            ],
            revision: scenario.revision,
            sealed: scenario.nextSealed,
          ),
        );
        await _drain();
        expect(retry.controller.error, isA<ConversationContinuityError>());
        expect(retry.controller.entries, same(retry.retained));
        expect(retry.controller.revision, 7);
        expect(retry.controller.sealed, scenario.wasSealed);
        expect(retry.fresh.requested, isTrue);
      },
    );
  }

  for (final reopened in [false, true]) {
    test(
      'same observation rejects ordinary duplicate after ${reopened ? 'retry' : 'initial open'}',
      () async {
        late DisplayMemberController controller;
        late _Handle handle;
        if (reopened) {
          final retry = await _retryAfterSnapshot(sealed: false);
          controller = retry.controller;
          handle = retry.fresh;
        } else {
          handle = _Handle();
          controller = _controller(handle);
          addTearDown(controller.close);
          await handle.pulling.future;
        }
        handle.reply.complete(_batch([_head(1)], revision: 7));
        await _drain();
        expect(controller.error, isNull);
        final retained = controller.entries;
        handle.reply.complete(_batch([_head(1)], revision: 7));
        await _drain();
        expect(controller.error, isA<ConversationContinuityError>());
        expect(controller.entries, same(retained));
        expect(handle.requested, isTrue);
      },
    );
  }

  test('one observation allows unchanged same revision qualification sealing then EOF', () async {
    final handle = _Handle();
    final controller = _controller(handle);
    addTearDown(controller.close);
    await handle.pulling.future;
    handle.reply.complete(_batch([_head(1)], revision: 7));
    await _drain();
    handle.reply.complete(_batch([_head(1)], revision: 7, sealed: true));
    await _drain();
    expect(controller.error, isNull);
    expect(controller.sealed, isTrue);
    handle.reply.complete(null);
    await handle.closed.future;
    expect(controller.error, isNull);
  });

  for (final sealed in [false, true]) {
    test(
      'one observation rejects data after complete sealed result nextSealed=$sealed',
      () async {
        final handle = _Handle();
        final controller = _controller(handle);
        addTearDown(controller.close);
        await handle.pulling.future;
        handle.reply.complete(
          _batch([_head(1, frozen: true)], revision: 7, sealed: true),
        );
        await _drain();
        final retained = controller.entries;
        handle.reply.complete(
          _batch([_head(1, frozen: true)], revision: 8, sealed: sealed),
        );
        await _drain();
        expect(controller.error, isA<ConversationContinuityError>());
        expect(controller.entries, same(retained));
        expect(controller.revision, 7);
        expect(controller.sealed, isTrue);
      },
    );
  }

  test('unpublished live result still advances the observation continuity baseline', () async {
    final handle = _Handle();
    final controller = _controller(handle);
    addTearDown(controller.close);
    await handle.pulling.future;
    handle.reply.complete(_batch([_head(1)], revision: 1));
    await _drain();
    final retained = controller.entries;
    controller.requireSealed();
    handle.reply.complete(_batch([_head(1)], revision: 3));
    await _drain();
    expect(controller.entries, same(retained));
    handle.reply.complete(
      _batch([_head(1, frozen: true)], revision: 2, sealed: true),
    );
    await _drain();
    expect(controller.error, isA<ConversationContinuityError>());
    expect(controller.entries, same(retained));
    expect(controller.revision, 1);
  });

  test('more than 12 members publish only at complete; early-row changes notify just that row', () async {
    final handle = _Handle();
    final controller = _controller(handle);
    addTearDown(controller.close);
    await handle.pulling.future;
    var structure = 0, first = 0, last = 0;
    controller.addListener(() => structure++);
    handle.reply.complete(
      _batch([for (var i = 1; i <= 12; i++) _head(i)], complete: false),
    );
    await _drain();
    expect(controller.entries, isEmpty);
    expect(controller.hasSnapshot, isFalse);
    expect(structure, 0);
    handle.reply.complete(
      _batch(
        [for (var i = 13; i <= 24; i++) _head(i)],
        offset: 12,
        complete: false,
      ),
    );
    await _drain();
    expect(controller.entries, isEmpty);
    handle.reply.complete(_batch([_head(25)], offset: 24));
    await _drain();
    expect(controller.entries.map((e) => e.memberKey), [
      for (var i = 1; i <= 25; i++) 'row-$i',
    ]);
    expect(() => controller.entries.clear(), throwsUnsupportedError);
    expect(structure, 1);
    controller.member('row-1').addListener(() => first++);
    controller.member('row-25').addListener(() => last++);
    final intent = controller.disclosure('row-25')..expanded = true;
    handle.reply.complete(
      _batch(
        [
          for (var i = 1; i <= 12; i++)
            _head(i, text: i == 1 ? 'changed' : null),
        ],
        revision: 2,
        complete: false,
      ),
    );
    await _drain();
    expect((first, last, structure), (0, 0, 1));
    handle.reply.complete(
      _batch(
        [for (var i = 13; i <= 24; i++) _head(i)],
        revision: 2,
        offset: 12,
        complete: false,
      ),
    );
    await _drain();
    expect((first, last, structure), (0, 0, 1));
    handle.reply.complete(_batch([_head(25)], revision: 2, offset: 24));
    await _drain();
    expect((first, last, structure), (1, 0, 1));
    expect(controller.disclosure('row-25'), same(intent));
    expect(intent.expanded, isTrue);
  });

  for (final eof in [false, true]) {
    test(
      'pending ${eof ? 'EOF' : 'failure'} retains the previous complete result and reports error',
      () async {
        final handle = _Handle();
        final controller = _controller(handle);
        addTearDown(controller.close);
        await handle.pulling.future;
        handle.reply.complete(_batch([_head(1)]));
        await _drain();
        final previous = controller.entries;
        handle.reply.complete(
          _batch([_head(2)], revision: 2, complete: false, sealed: true),
        );
        await _drain();
        expect(controller.entries, same(previous));
        if (eof) {
          handle.reply.complete(null);
        } else {
          handle.reply.completeError(StateError('pending failed'));
        }
        await _drain();
        expect(controller.entries, same(previous));
        expect(controller.revision, 1);
        expect(
          controller.error,
          eof ? isA<ConversationContinuityError>() : isA<StateError>(),
        );
        expect(controller.loading, isFalse);
        expect(handle.requested, isTrue);
      },
    );
  }

  test('sealed header revokes mutable disclosure synchronously before complete sealed result', () async {
    final handle = _Handle();
    final controller = _controller(handle);
    addTearDown(controller.close);
    await handle.pulling.future;
    handle.reply.complete(_batch([_head(1), _head(2)]));
    await _drain();
    final old = controller.disclosure('row-1')..expanded = true;
    controller.requireSealed();
    expect(old.retired, isTrue);
    expect(controller.disclosure('row-1').expanded, isTrue);
    expect(controller.awaitingSealed, isTrue);
    handle.reply.complete(
      _batch(
        [_head(1, frozen: true)],
        revision: 2,
        sealed: true,
        complete: false,
      ),
    );
    await _drain();
    expect(controller.revision, 1);
    expect(controller.awaitingSealed, isTrue);
    handle.reply.complete(
      _batch([_head(2, frozen: true)], revision: 2, sealed: true, offset: 1),
    );
    await _drain();
    expect(controller.revision, 2);
    expect(controller.awaitingSealed, isFalse);
    handle.reply.complete(null);
    await handle.closed.future;
    expect(controller.error, isNull);
    expect(controller.entries, hasLength(2));
  });

  test(
    'sealed members arriving before header stay readable through explicit EOF',
    () async {
      final handle = _Handle();
      final controller = _controller(handle);
      addTearDown(controller.close);
      await handle.pulling.future;
      handle.reply.complete(_batch([_head(1, frozen: true)], sealed: true));
      await _drain();
      final intent = controller.disclosure('row-1')..expanded = true;
      controller.requireSealed();
      expect(controller.disclosure('row-1'), same(intent));
      expect(intent.retired, isFalse);
      handle.reply.complete(null);
      await handle.closed.future;
      expect(controller.hasSnapshot, isTrue);
      expect(controller.error, isNull);
      expect(handle.calls, 2);
    },
  );

  test('retiring a pending open joins and closes its late success without publishing', () async {
    final opened = Completer<DisplayMembers>();
    final handle = _Handle();
    final controller = DisplayMemberController(
      reference: _ref,
      demand: _demand,
      open: (_, _) => opened.future,
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
        demand: _demand,
        open: (_, _) => ++opens == 1 ? opened.future : Future.value(fresh),
      );
      addTearDown(controller.close);
      await _drain();
      await controller.retry();
      await fresh.pulling.future;
      fresh.reply.complete(_batch([_head(1)], revision: 7));
      await _drain();
      opened.completeError(StateError('obsolete'));
      await _drain();
      expect(controller.revision, 7);
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
        demand: _demand,
        open: (_, _) async => ++opens == 1 ? old : fresh,
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
      fresh.reply.complete(_batch([_head(1)], revision: 2));
      await _drain();
      expect(controller.cleanupError, isNull);
      expect(controller.revision, 2);
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
        demand: _demand,
        open: (_, _) => switch (++opens) {
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
