import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/view_models/display_member_controller.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = DisplayBlockRef(databaseId: 'db', blockId: 'group');
const _demand = ReadDemand(maxItems: 1, maxBytes: 4096);

void main() {
  test('sealed head revokes mutable page immediately and waits for native sealed records', () async {
    final handle = _Handle();
    final controller = DisplayMemberController(
      reference: _ref,
      demand: _demand,
      open: (_, _, _) async => handle,
    );
    await handle.pulling.future;
    final page = DisplayMemberPage(
      block: _ref,
      revision: 1,
      sealed: false,
      entries: [
        DisplayMemberHead(
          memberKey: 'row',
          memberOrder: 1,
          record: DisplayRecord(
            contentSource: const CurrentAtom(),
            atom: ChatAtom(
              id: 'atom',
              source: const ForegroundTurnChatSource(turnId: 'turn'),
              sourceOrder: 1,
              kind: ChatAtomKind.reasoning,
              delivery: ChatDeliveryKind.foreground,
              lifecycle: const ActiveChatAtom(
                started: null,
                status: ChatActiveStatus.running,
              ),
              contents: const [],
            ),
          ),
        ),
      ],
    );
    handle.reply.complete(page);
    await Future<void>.delayed(Duration.zero);
    final old = controller.disclosure('row')..expanded = true;
    controller.requireSealed();
    expect(controller.page, same(page));
    expect(controller.awaitingSealed, isTrue);
    expect(old.retired, isTrue);
    expect(controller.disclosure('row').expanded, isTrue);
    handle.reply.complete(
      DisplayMemberPage(block: _ref, revision: 2, sealed: false, entries: []),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.page, same(page));
    final sealed = DisplayMemberPage(
      block: _ref,
      revision: 3,
      sealed: true,
      entries: [],
    );
    handle.reply.complete(sealed);
    await Future<void>.delayed(Duration.zero);
    expect(controller.page, same(sealed));
    expect(controller.awaitingSealed, isFalse);
    expect(controller.error, isNull);
    await controller.close();
    controller.dispose();
  });

  test('sealed current page stays readable after explicit EOF and releases its handle', () async {
    final handle = _Handle();
    final controller = DisplayMemberController(
      reference: _ref,
      demand: _demand,
      open: (reference, window, demand) async => handle,
    );
    await handle.pulling.future;
    final page = DisplayMemberPage(
      block: _ref,
      revision: 1,
      sealed: true,
      entries: [],
      before: 50,
    );
    final accepted = Completer<void>();
    controller.addListener(() {
      if (controller.page == page && !accepted.isCompleted) accepted.complete();
    });
    handle.reply.complete(page);
    await accepted.future;
    // The consumer requests exactly one next after accepting the real sealed page.
    await Future<void>.delayed(Duration.zero);
    handle.reply.complete(null);
    await handle.closed.future;
    expect(controller.page, same(page));
    expect(controller.error, isNull);
    expect(handle.calls, 2);
    await controller.close();
    controller.dispose();
  });

  test(
    'window switch closes original demand and rejects its late failure',
    () async {
      final windows = <DisplayMemberWindow>[];
      final handles = <_Handle>[];
      final controller = DisplayMemberController(
        reference: _ref,
        demand: _demand,
        open: (reference, window, demand) async {
          expect(reference, _ref);
          expect(demand.maxItems, 1);
          windows.add(window);
          final handle = _Handle();
          handles.add(handle);
          return handle;
        },
      );
      await Future<void>.delayed(Duration.zero);
      final old = handles.single;
      controller.select(const BeforeDisplayMembers(memberOrder: 50));
      expect(old.requested, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(windows, [
        isA<LatestDisplayMembers>(),
        isA<BeforeDisplayMembers>(),
      ]);
      final current = handles.last;
      final value = DisplayMemberPage(
        block: _ref,
        revision: 3,
        sealed: false,
        entries: [],
      );
      current.reply.complete(value);
      await Future<void>.delayed(Duration.zero);
      expect(controller.page, same(value));
      expect(controller.error, isNull);
      controller.retire();
      expect(current.requested, isTrue);
      await controller.close();
      controller.dispose();
    },
  );

  test('Latest to Before to Latest rejects the first Latest late failure with the same page generation', () async {
    final firstOpen = Completer<DisplayMembers>();
    final before = _Handle();
    final latest = _Handle();
    final windows = <DisplayMemberWindow>[];
    final controller = DisplayMemberController(
      reference: _ref,
      demand: _demand,
      open: (_, window, _) {
        windows.add(window);
        return switch (windows.length) {
          1 => firstOpen.future,
          2 => Future.value(before),
          _ => Future.value(latest),
        };
      },
    );
    await Future<void>.delayed(Duration.zero);
    controller.select(const BeforeDisplayMembers(memberOrder: 50));
    await before.pulling.future;
    controller.select(const LatestDisplayMembers());
    await latest.pulling.future;
    final page = DisplayMemberPage(
      block: _ref,
      revision: 7,
      sealed: false,
      entries: [],
    );
    latest.reply.complete(page);
    await Future<void>.delayed(Duration.zero);
    expect(windows, [
      isA<LatestDisplayMembers>(),
      isA<BeforeDisplayMembers>(),
      isA<LatestDisplayMembers>(),
    ]);
    expect(before.requested, isTrue);
    expect(controller.page, same(page));
    firstOpen.completeError(StateError('obsolete first Latest'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.page, same(page));
    expect(controller.error, isNull);
    expect(controller.loading, isFalse);
    await controller.close();
    controller.dispose();
  });

  test('retry retains cleanup failure until the same handle really closes, then accepts a clean page', () async {
    final failure = StateError('first close failed');
    final old = _Handle()..closeFailure = failure;
    final fresh = _Handle();
    var opens = 0;
    final controller = DisplayMemberController(
      reference: _ref,
      demand: _demand,
      open: (_, _, _) async => ++opens == 1 ? old : fresh,
    );
    await old.pulling.future;
    controller.select(const BeforeDisplayMembers(memberOrder: 50));
    await Future<void>.delayed(Duration.zero);
    expect(controller.cleanupError, same(failure));
    expect(opens, 1);
    old.closeFailure = null;
    old.closeGate = Completer<void>();
    final retry = controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(old.closeCalls, 2);
    expect(controller.error, same(failure));
    expect(
      opens,
      1,
      reason: 'A new page cannot bypass unfinished original cleanup',
    );
    old.closeGate!.complete();
    await retry;
    await fresh.pulling.future;
    final atom = ChatAtom(
      id: 'fresh-member',
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      sourceOrder: 1,
      kind: ChatAtomKind.reasoning,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const ActiveChatAtom(
        started: null,
        status: ChatActiveStatus.running,
      ),
      contents: const [],
    );
    final page = DisplayMemberPage(
      block: _ref,
      revision: 2,
      sealed: false,
      entries: [
        DisplayMemberHead(
          memberKey: 'fresh-key',
          memberOrder: 1,
          record: DisplayRecord(atom: atom, contentSource: const CurrentAtom()),
        ),
      ],
    );
    fresh.reply.complete(page);
    await Future<void>.delayed(Duration.zero);
    expect(old.closed.isCompleted, isTrue);
    expect(old.closeCalls, 2);
    expect(opens, 2);
    expect(controller.page, same(page));
    expect(controller.page!.entries.single.record.atom, same(atom));
    expect(controller.error, isNull);
    expect(controller.cleanupError, isNull);
    await controller.close();
    controller.dispose();
  });

  test('closing another handle cannot erase an unresolved original cleanup failure', () async {
    final lateOpen = Completer<DisplayMembers>();
    final failure = StateError('late original close failed');
    final original = _Handle()..closeFailure = failure;
    final current = _Handle()..closeGate = Completer<void>();
    final fresh = _Handle();
    var opens = 0;
    final controller = DisplayMemberController(
      reference: _ref,
      demand: _demand,
      open: (_, _, _) {
        opens++;
        return switch (opens) {
          1 => lateOpen.future,
          2 => Future.value(current),
          _ => Future.value(fresh),
        };
      },
    );
    await Future<void>.delayed(Duration.zero);
    controller.select(const BeforeDisplayMembers(memberOrder: 60));
    await current.pulling.future;
    lateOpen.complete(original);
    await Future<void>.delayed(Duration.zero);
    expect(controller.error, same(failure));
    controller.select(const BeforeDisplayMembers(memberOrder: 40));
    await Future<void>.delayed(Duration.zero);
    current.closeGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(current.closed.isCompleted, isTrue);
    expect(
      controller.cleanupError,
      same(failure),
      reason: 'The first handle still owns a failed close obligation',
    );
    expect(opens, 2);
    original.closeFailure = null;
    await controller.retry();
    await fresh.pulling.future;
    fresh.reply.complete(
      DisplayMemberPage(block: _ref, revision: 3, sealed: false, entries: []),
    );
    await Future<void>.delayed(Duration.zero);
    expect(original.closeCalls, 2);
    expect(controller.error, isNull);
    await controller.close();
    controller.dispose();
  });
}

class _Handle implements DisplayMembers {
  Completer<DisplayMemberPage?> reply = Completer();
  final pulling = Completer<void>();
  final closed = Completer<void>();
  bool requested = false;
  bool waiting = false;
  int calls = 0;
  int closeCalls = 0;
  Object? closeFailure;
  Completer<void>? closeGate;
  @override
  Future<DisplayMemberPage?> next() {
    calls++;
    waiting = true;
    if (!pulling.isCompleted) pulling.complete();
    final original = reply;
    return original.future
        .then((page) {
          if (identical(reply, original)) {
            reply = Completer<DisplayMemberPage?>();
          }
          return page;
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
    if (closeFailure case final failure?) throw failure;
    if (!closed.isCompleted) closed.complete();
  }
}
