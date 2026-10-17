import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as dto;
import 'package:anywork/src/rust/api/studio/types/thread_stream/item.dart'
    as item_dto;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // These tests execute the production FRB adapter with generated DTOs and a
  // controlled opaque interface. No native library or Rust sink is loaded.
  test(
    'initial and Patch preserve identity, field revisions and save facts',
    () async {
      final bridge = _GeneratedChatView(_snapshot());
      final window = FrbChatWindow(bridge);
      addTearDown(window.close);

      final initial = await window.initial();
      expect(initial.version, 41);
      expect(initial.focusedItemId, 'item-text');
      expect(initial.hasOlder, isTrue);
      expect(initial.hasNewer, isFalse);
      final first = initial.items.single;
      expect(first.item.id, 'item-text');
      expect(first.item.threadId, 'thread-A');
      expect(first.item.turnId, 'turn-7');
      expect(first.item.ordinal, 1000000007);
      expect(first.item.revision, 8);
      expect(first.saved, isFalse);
      expect(
        first.terminal,
        isTrue,
        reason: 'execution terminal does not imply durable',
      );
      expect(first.item.saved, isFalse);
      expect(first.item.executionTerminal, isTrue);
      expect(first.item.bodyOmittedUnits, 13);
      expect(first.item.createdAt.millisecondsSinceEpoch, 1700000000000);
      final text = first.item.state as ThreadTextItemStateView;
      expect(text.channel, ThreadTextChannel.finalAnswer);
      expect(text.text, '中文 🐱\nfirst');

      final pending = window.next();
      expect(bridge.nextCalls, 1);
      bridge.deliver(
        dto.BridgeChatUpdate.patch(
          from: BigInt.from(41),
          to: BigInt.from(45),
          focus: const dto.BridgeChatFocus.around(itemId: 'item-text'),
          changes: [
            dto.BridgeViewChange.updateItem(
              itemId: 'item-text',
              expectedRevision: BigInt.from(8),
              revision: BigInt.from(9),
              omittedBytes: BigInt.zero,
              saved: true,
              lifecycle: dto.BridgeChatLifecycle.terminal,
              itemShell: null,
              fields: const [
                dto.BridgeFieldUpdate(
                  field: dto.BridgeContentField.text(),
                  change: dto.BridgeFieldChange.append(text: '\nsecond'),
                ),
              ],
            ),
            dto.BridgeViewChange.splice(
              index: BigInt.one,
              remove: BigInt.zero,
              items: [_wireItem(id: 'item-next', terminal: false, saved: true)],
            ),
          ],
          hasOlder: false,
          hasNewer: true,
          priority: dto.BridgeUpdatePriority.immediate,
        ),
      );
      final patch = (await pending) as StudioChatPatch;
      expect(patch.from, 41);
      expect(patch.to, 45, reason: 'consolidated patches may skip versions');
      expect(patch.focusedItemId, 'item-text');
      expect(patch.hasOlder, isFalse);
      expect(patch.hasNewer, isTrue);
      expect(patch.changes, hasLength(2));
      final update = patch.changes.first as StudioViewItemUpdate;
      expect(update.itemId, 'item-text');
      expect(update.expectedRevision, 8);
      expect(update.revision, 9);
      expect(update.omittedUnits, 0);
      expect(update.saved, isTrue);
      expect(update.lifecycle, StudioChatLifecycle.terminal);
      expect(update.fields.single.field, isA<ThreadTextFieldView>());
      expect(
        (update.fields.single.change as AppendThreadFieldChangeView).text,
        '\nsecond',
      );
      final splice = patch.changes.last as StudioViewSplice;
      expect(splice.index, 1);
      expect(splice.remove, 0);
      expect(splice.items.single.item.id, 'item-next');
      expect(splice.items.single.saved, isTrue);
      expect(
        splice.items.single.terminal,
        isFalse,
        reason: 'saved and execution terminal remain independent',
      );
      expect(
        bridge.initialCalls,
        1,
        reason: 'adapter maps frames without reading a second baseline',
      );
    },
  );

  test(
    'control receipts preserve explicit Applied and NoChange at equal version',
    () async {
      final bridge = _GeneratedChatView(_snapshot());
      final window = FrbChatWindow(bridge);
      addTearDown(window.close);
      await window.initial();

      bridge.receipt = _receipt(
        id: 101,
        disposition: dto.BridgeChatDisposition.applied,
        version: 41,
      );
      final applied = await window.load(TimelineDirection.older);
      expect(applied.operationId, 101);
      expect(applied.version, 41);
      expect(
        applied.disposition,
        StudioChatDisposition.applied,
        reason: 'equal delivered version is not evidence of NoChange',
      );
      expect(bridge.loadDirections, [dto.BridgeChatDirection.older]);

      bridge.receipt = _receipt(
        id: 102,
        disposition: dto.BridgeChatDisposition.noChange,
        version: 41,
      );
      final noChange = await window.load(TimelineDirection.newer);
      expect(noChange.operationId, 102);
      expect(noChange.version, 41);
      expect(noChange.disposition, StudioChatDisposition.noChange);
      await window.focus('item-text');
      await window.focus(null);
      expect(bridge.focuses, const [
        dto.BridgeChatFocus.around(itemId: 'item-text'),
        dto.BridgeChatFocus.latest(),
      ]);
      bridge.receipt = _receipt(
        id: 103,
        disposition: dto.BridgeChatDisposition.noChange,
        version: 41,
        retained: false,
      );
      final notRetained = await window.expandItem('item-text');
      expect(notRetained.retained, isFalse);
      expect(bridge.expandedIds, ['item-text']);
      expect(bridge.initialCalls, 1);
      expect(
        bridge.nextCalls,
        0,
        reason: 'control receipt never delivers or refreshes content',
      );

      final next = window.next();
      bridge.deliver(
        dto.BridgeChatUpdate.reset(snapshot: _snapshot(version: 46)),
      );
      expect(((await next) as StudioChatReset).snapshot.version, 46);
    },
  );

  test(
    'requestClose rejects new calls and close joins before disposing opaque',
    () async {
      final bridge = _GeneratedChatView(_snapshot())
        ..closeBarrier = Completer<void>();
      final window = FrbChatWindow(bridge);
      final inFlight = window.next();

      window.requestClose();
      window.requestClose();
      expect(bridge.requestCloseCalls, 1);
      expect(await window.next(), isNull);
      expect(bridge.nextCalls, 1);
      await expectLater(window.initial(), throwsStateError);
      await expectLater(window.focus(null), throwsStateError);
      bridge.deliver(
        dto.BridgeChatUpdate.reset(snapshot: _snapshot(version: 99)),
      );
      expect(
        await inFlight,
        isNull,
        reason: 'a late native reply cannot be delivered after cancellation',
      );

      final closing = window.close();
      expect(window.close(), same(closing));
      expect(bridge.closeCalls, 1);
      expect(
        bridge.disposeCalls,
        0,
        reason: 'requestClose is not a completed native join',
      );
      bridge.closeBarrier!.complete();
      await closing;
      expect(bridge.disposeCalls, 1);
      await window.close();
      expect(bridge.closeCalls, 1);
      expect(bridge.calls, ['next', 'requestClose', 'close', 'dispose']);
    },
  );

  test(
    'failed native join retains opaque and permits supervisor close retry',
    () async {
      final failure = StateError('native view join failed');
      final bridge = _GeneratedChatView(_snapshot())..closeFailure = failure;
      final window = FrbChatWindow(bridge);

      await expectLater(window.close(), throwsA(same(failure)));
      expect(
        bridge.disposeCalls,
        0,
        reason: 'an unresolved owner must retain the opaque handle',
      );
      expect(bridge.requestCloseCalls, 1);
      expect(bridge.closeCalls, 1);

      bridge.closeFailure = null;
      await window.close();
      expect(bridge.closeCalls, 2);
      expect(bridge.requestCloseCalls, 1);
      expect(bridge.disposeCalls, 1);
    },
  );
}

dto.BridgeChatSnapshot _snapshot({int version = 41}) => dto.BridgeChatSnapshot(
  focus: const dto.BridgeChatFocus.around(itemId: 'item-text'),
  version: BigInt.from(version),
  items: [_wireItem()],
  hasOlder: true,
  hasNewer: false,
);

dto.BridgeChatItem _wireItem({
  String id = 'item-text',
  bool terminal = true,
  bool saved = false,
}) => dto.BridgeChatItem(
  item: item_dto.BridgeThreadItem(
    id: id,
    threadId: 'thread-A',
    turnId: 'turn-7',
    ordinal: BigInt.from(1000000007),
    revision: BigInt.from(8),
    createdAt: 1700000000,
    updatedAt: 1700000001,
    state: item_dto.BridgeThreadItemState.text(
      channel: item_dto.BridgeThreadTextChannel.final_,
      text: '中文 🐱\nfirst',
      attachments: const [],
      lifecycle: terminal
          ? const item_dto.BridgeThreadContentLifecycle.completed(
              completedAt: 1700000001,
            )
          : const item_dto.BridgeThreadContentLifecycle.streaming(),
    ),
  ),
  saved: saved,
  lifecycle: terminal
      ? dto.BridgeChatLifecycle.terminal
      : dto.BridgeChatLifecycle.streaming,
  omittedBytes: BigInt.from(13),
);

dto.BridgeChatReceipt _receipt({
  required int id,
  required dto.BridgeChatDisposition disposition,
  required int version,
  bool retained = true,
}) => dto.BridgeChatReceipt(
  operationId: BigInt.from(id),
  disposition: disposition,
  version: BigInt.from(version),
  retained: retained,
);

class _GeneratedChatView implements wire.BridgeChatView {
  _GeneratedChatView(this.baseline);

  final dto.BridgeChatSnapshot baseline;
  final calls = <String>[];
  final pendingFrames = <Completer<dto.BridgeChatUpdate?>>[];
  final loadDirections = <dto.BridgeChatDirection>[];
  final focuses = <dto.BridgeChatFocus>[];
  final expandedIds = <String>[];
  var receipt = _receipt(
    id: 1,
    disposition: dto.BridgeChatDisposition.noChange,
    version: 41,
  );
  Completer<void>? closeBarrier;
  Object? closeFailure;
  int initialCalls = 0;
  int nextCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<dto.BridgeChatSnapshot> initial() async {
    initialCalls++;
    calls.add('initial');
    return baseline;
  }

  @override
  Future<dto.BridgeChatUpdate?> next() {
    nextCalls++;
    calls.add('next');
    final pending = Completer<dto.BridgeChatUpdate?>();
    pendingFrames.add(pending);
    return pending.future;
  }

  void deliver(dto.BridgeChatUpdate? frame) {
    pendingFrames.removeAt(0).complete(frame);
  }

  @override
  Future<dto.BridgeChatReceipt> load({
    required dto.BridgeChatDirection direction,
  }) async {
    loadDirections.add(direction);
    return receipt;
  }

  @override
  Future<dto.BridgeChatReceipt> focus({
    required dto.BridgeChatFocus focus,
  }) async {
    focuses.add(focus);
    return receipt;
  }

  @override
  Future<dto.BridgeChatReceipt> expand({required String itemId}) async {
    expandedIds.add(itemId);
    return receipt;
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    calls.add('requestClose');
  }

  @override
  Future<void> close() {
    closeCalls++;
    calls.add('close');
    final failure = closeFailure;
    if (failure != null) return Future.error(failure);
    return closeBarrier?.future ?? Future.value();
  }

  @override
  void dispose() {
    disposeCalls++;
    calls.add('dispose');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
