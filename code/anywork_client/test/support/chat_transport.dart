import 'dart:async';

import 'package:anywork_client/anywork_client.dart';

typedef TestSnapshot = ChatSnapshot<String>;
typedef TestFrame = ChatFrame<String>;

TestSnapshot snapshot(
  int version, {
  String viewId = 'view',
  String body = 'body',
}) => ChatSnapshot(
  stamp: ViewStamp(
    threadId: 'thread',
    viewId: viewId,
    viewEpoch: 'epoch',
    version: version,
  ),
  items: [
    ChatItem(
      id: 'item',
      revision: version,
      value: body,
      saved: false,
      terminal: false,
    ),
  ],
);

final class TestTransport
    implements ChatTransport<TestSnapshot, TestFrame, int> {
  final List<Completer<TestHandle>> opens = [];

  @override
  Future<TestHandle> open(String threadId) {
    final pending = Completer<TestHandle>();
    opens.add(pending);
    return pending.future;
  }
}

final class TestHandle implements ChatHandle<TestSnapshot, TestFrame, int> {
  TestHandle({TestSnapshot? initial}) {
    if (initial != null) initialResult.complete(initial);
  }

  final Completer<TestSnapshot> initialResult = Completer();
  final Completer<void> initialStarted = Completer();
  final Completer<void> nextStarted = Completer();
  final Completer<void> closeCompleted = Completer();
  final Completer<void> closeStarted = Completer();
  Completer<void>? closeGate;
  final Completer<void> controlStarted = Completer();
  final Completer<int> controlResult = Completer();
  Completer<TestFrame?>? _pending;
  bool _closed = false;
  int initialCalls = 0;
  int nextCalls = 0;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  Object? closeFailure;

  @override
  Future<TestSnapshot> initial() {
    initialCalls++;
    if (!initialStarted.isCompleted) initialStarted.complete();
    return initialResult.future;
  }

  @override
  Future<TestFrame?> next() {
    if (_closed) return Future.value(null);
    if (_pending != null) throw StateError('Two concurrent next calls');
    nextCalls++;
    final pending = Completer<TestFrame?>();
    _pending = pending;
    if (!nextStarted.isCompleted) nextStarted.complete();
    return pending.future;
  }

  void emit(TestFrame? frame) {
    final pending = _pending;
    if (pending == null) throw StateError('No pending content read');
    _pending = null;
    pending.complete(frame);
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    _closed = true;
    if (initialCalls > 0 && !initialResult.isCompleted) {
      initialResult.completeError(const StaleChatAttempt());
    }
    final pending = _pending;
    _pending = null;
    pending?.complete(null);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (!closeStarted.isCompleted) closeStarted.complete();
    await closeGate?.future;
    if (closeFailure case final error?) throw error;
    if (!closeCompleted.isCompleted) closeCompleted.complete();
  }

  Future<int> _control() {
    if (!controlStarted.isCompleted) controlStarted.complete();
    return controlResult.future;
  }

  @override
  Future<int> load(ChatDirection direction) => _control();
  @override
  Future<int> extendLatest() => _control();
  @override
  Future<int> focus(String? itemId) => _control();
  @override
  Future<int> expand(String itemId) => _control();
}

ChatChannel<TestSnapshot, TestFrame, int> channel(
  TestTransport transport, {
  ResourceBudget? budget,
}) => ChatChannel(
  threadId: 'thread',
  transport: transport,
  reducer: const ChatSnapshotReducer<String>(),
  retryPolicy: const RetryPolicy(delays: []),
  budget: budget,
);
