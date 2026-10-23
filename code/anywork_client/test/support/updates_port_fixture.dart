import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';

import 'scripted_feed.dart';

const updatesTestOrigin = ProductReadOrigin(ownerEpoch: 'updates-native', incarnation: 1);
const updatesTestCancelled = StudioFailure(code: StudioFailureCode.cancelled,
  message: 'The scripted Updates environment is closing.', retryable: false, correlationId: 'updates-test-close');

UpdatesHeader availableUpdateHeader(int revision) => UpdatesHeader(
  reference: UpdatesReadRef(entry: 1, revision: revision),
  brief: UpdatesBrief.available(revision: revision, checkedAt: revision),
  summary: UpdateSummaryReadRef(entry: 2, revision: revision), operation: null, error: null,
  details: UpdateDetailsReadRef(entry: 3, revision: revision));

UpdatesHeader idleUpdateHeader(int revision) => UpdatesHeader(
  reference: UpdatesReadRef(entry: 1, revision: revision),
  brief: UpdatesBrief.idle(revision: revision, updatedAt: revision),
  summary: null, operation: null, error: null, details: null);

UpdatesReadHeader availableUpdateRead(int revision) => UpdatesReadHeader.available(
  revision: revision, checkedAt: revision, update: UpdateDetailsRead(
    summary: UpdateSummaryRead(version: ReadText.inline(text: '2.0.$revision'), publishedAt: revision,
      notesUrl: ReadText.inline(text: 'https://updates.invalid/$revision')),
    installer: const UpdateAssetRead(url: ReadText.inline(text: 'https://updates.invalid/installer'), size: 7,
      sha256: ReadText.inline(text: 'unused-by-value-read'), signature: ReadText.inline(text: 'unused-by-value-read'))));

/// Native frames only. Tests choose every header/origin; there is no mirror,
/// automatic-start policy, value gate or business retry in this environment.
final class UpdatesNativeFeed {
  UpdatesNativeFeed(this.origin, int index)
    : feed = ScriptedFeed<UpdatesFrame>(feedId: 'updates-native-$index',
        sequenceOf: (frame) => frame is UpdatesData ? frame.deliverySequence : null,
        isTerminal: (frame) => frame is! UpdatesData);
  final ProductReadOrigin origin;
  final ScriptedFeed<UpdatesFrame> feed;
  int _sequence = 0;
  int _revision = 0;
  ProductFeedIdentity get identity => ProductFeedIdentity(feedId: feed.feedId,
    ownerEpoch: origin.ownerEpoch, incarnation: origin.incarnation, resource: ProductResource.updates);

  Future<void> publish(UpdatesHeader header, {required int projectionRevision}) async {
    await feed.listened.future;
    final stamp = ProductProjectionStamp(ownerEpoch: origin.ownerEpoch,
      incarnation: origin.incarnation, revision: projectionRevision);
    final event = _sequence == 0
      ? UpdatesEvent.baseline(identity: identity, stamp: stamp, value: header)
      : UpdatesEvent.replace(stamp: stamp, baseRevision: _revision, value: header);
    _revision = projectionRevision;
    feed.emit(UpdatesFrame.data(deliverySequence: ++_sequence, event: event));
    await feed.acknowledged(_sequence);
  }

  void fail(StudioFailure failure) => feed.emit(UpdatesFrame.failure(identity: identity, error: failure));
  void replaceOwner() => feed.emit(UpdatesFrame.closed(identity: identity, reason: ProductFeedCloseReason.ownerReplaced));
}

final class UpdatesFeedOpen {
  UpdatesFeedOpen(this.index);
  final int index;
  final reply = Completer<FeedConnection<UpdatesFrame>>();
  UpdatesNativeFeed? native;
  UpdatesNativeFeed accept({ProductReadOrigin origin = updatesTestOrigin}) {
    final value = UpdatesNativeFeed(origin, index);
    native = value;
    reply.complete(value.feed);
    return value;
  }
}

final class UpdatesValueOpen {
  UpdatesValueOpen(this.target, this.index);
  final UpdatesReadTarget target;
  final int index;
  final reply = Completer<UpdatesReadConnection>();
  UpdatesValuePin? native;
  UpdatesValuePin accept() {
    final value = UpdatesValuePin('updates-value-$index');
    native = value;
    reply.complete(value);
    return value;
  }
}

/// One native read and its real completion/close receipts. Close cannot turn
/// an entered header Future into a joined read before that reply settles.
final class UpdatesValuePin implements UpdatesReadConnection {
  UpdatesValuePin(this.id);
  final String id;
  final headerCalled = Completer<void>();
  final headerReply = Completer<UpdatesReadHeader>();
  final _headerReads = <Future<void>>[];
  final closeCalled = Completer<void>();
  Completer<FeedCloseReport>? closeReceipt;
  bool sealed = false;
  bool closed = false;
  int headerCalls = 0;
  @override
  Future<UpdatesReadHeader> header() {
    if (sealed) throw updatesTestCancelled;
    headerCalls++;
    if (!headerCalled.isCompleted) headerCalled.complete();
    // The same immutable native scope may be queried again by a task finish.
    // Every call still joins its original scripted material, never latest.
    _headerReads.add(headerReply.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    return headerReply.future;
  }
  @override
  void requestClose() => sealed = true;
  @override
  Future<FeedCloseReport> close() async {
    requestClose();
    if (!closeCalled.isCompleted) closeCalled.complete();
    await Future.wait(_headerReads);
    final report = await (closeReceipt?.future ?? Future.value(
      FeedCloseReport(feedId: id, outcome: const FeedCloseOutcome.clean())));
    closed = report.outcome is CleanFeedCloseOutcome;
    return report;
  }
  @override
  Future<FeedCloseReport> retryClose() => close();
  @override
  Never noSuchMethod(Invocation invocation) =>
    throw UnsupportedError('Unscripted Updates value capability: ${invocation.memberName}');
}

final class AutomaticUpdateOpen {
  AutomaticUpdateOpen(this.operationId, this.index);
  final OperationId operationId;
  final int index;
  final reply = Completer<UpdateTaskConnection>();
  ScriptedUpdateTask? native;
  ScriptedUpdateTask accept() {
    final value = ScriptedUpdateTask(UpdateTaskIdentity(runtimeEpoch: 'updates-runtime',
      taskId: 'automatic-$index', operationId: operationId));
    native = value;
    reply.complete(value);
    return value;
  }
}

/// Native task boundary only: identity, distinct finish/start/cancel calls and
/// actual RPC/native join. Outcomes are supplied by each test, not inferred.
final class ScriptedUpdateTask implements UpdateTaskConnection {
  ScriptedUpdateTask(this.identity);
  @override
  final UpdateTaskIdentity identity;
  final calls = <String>[];
  final startCalled = Completer<void>();
  final startReply = Completer<void>();
  final finishCalled = Completer<void>();
  final finishReply = Completer<UpdatesReadTarget>();
  final cancelCalled = Completer<void>();
  final closeCalled = Completer<void>();
  final retryCalled = Completer<void>();
  Completer<UpdateTaskCloseReport>? closeReceipt;
  Completer<UpdateTaskCloseReport>? retryReceipt;
  bool closed = false;
  @override
  Future<void> start() {
    calls.add('start'); startCalled.complete();
    return startReply.future;
  }
  @override
  Future<UpdatesReadTarget> finish() {
    calls.add('finish'); finishCalled.complete();
    return finishReply.future;
  }
  @override
  void requestCancel() {
    calls.add('cancel');
    if (!cancelCalled.isCompleted) cancelCalled.complete();
  }
  @override
  Future<UpdateTaskCloseReport> close() => _close(retry: false);
  @override
  Future<UpdateTaskCloseReport> retryClose() => _close(retry: true);
  Future<UpdateTaskCloseReport> _close({required bool retry}) async {
    calls.add(retry ? 'retryClose' : 'close');
    final entered = retry ? retryCalled : closeCalled;
    if (!entered.isCompleted) entered.complete();
    final report = await ((retry ? retryReceipt : closeReceipt)?.future ?? Future.value(
      UpdateTaskCloseReport(identity: identity, outcome: const FeedCloseOutcome.clean())));
    await Future.wait<void>([
      if (startCalled.isCompleted) startReply.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      if (finishCalled.isCompleted) finishReply.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    ]);
    closed = report.outcome is CleanFeedCloseOutcome;
    return report;
  }
}

final class ScriptedUpdatesPort implements UpdatesPort {
  final feeds = <UpdatesFeedOpen>[];
  final values = <UpdatesValueOpen>[];
  final automatic = <AutomaticUpdateOpen>[];
  final _feedWaiters = <int, Completer<UpdatesFeedOpen>>{};
  final _valueWaiters = <int, Completer<UpdatesValueOpen>>{};
  final _automaticWaiters = <int, Completer<AutomaticUpdateOpen>>{};
  void Function()? openingFeed;
  void Function()? openingAutomatic;

  Future<UpdatesFeedOpen> feedOpened(int index) => index < feeds.length ? Future.value(feeds[index])
    : _feedWaiters.putIfAbsent(index, Completer<UpdatesFeedOpen>.new).future;
  Future<UpdatesValueOpen> valueOpened(int index) => index < values.length ? Future.value(values[index])
    : _valueWaiters.putIfAbsent(index, Completer<UpdatesValueOpen>.new).future;
  Future<AutomaticUpdateOpen> automaticOpened(int index) => index < automatic.length ? Future.value(automatic[index])
    : _automaticWaiters.putIfAbsent(index, Completer<AutomaticUpdateOpen>.new).future;

  @override
  Future<FeedConnection<UpdatesFrame>> openUpdates() {
    final call = UpdatesFeedOpen(feeds.length);
    feeds.add(call); _feedWaiters.remove(call.index)?.complete(call);
    openingFeed?.call();
    return call.reply.future;
  }
  @override
  Future<UpdatesReadConnection> openUpdatesRead(UpdatesReadRef reference, {required ProductReadOrigin origin}) {
    final call = UpdatesValueOpen(UpdatesReadTarget(origin: origin, reference: reference), values.length);
    values.add(call); _valueWaiters.remove(call.index)?.complete(call);
    return call.reply.future;
  }
  @override
  Future<UpdateTaskConnection> openAutomaticUpdate(OperationId operationId) {
    final call = AutomaticUpdateOpen(operationId, automatic.length);
    automatic.add(call); _automaticWaiters.remove(call.index)?.complete(call);
    openingAutomatic?.call();
    return call.reply.future;
  }

  /// After the real owners seal, release only this test's pending native
  /// barriers so their original cleanup can join, including a late open.
  void releasePending() {
    for (final call in feeds) {
      final native = call.native ?? (!call.reply.isCompleted ? call.accept() : null);
      native?.feed.requestClose();
      final receipt = native?.feed.closeReceipt;
      if (receipt != null && !receipt.isCompleted) receipt.complete(
        FeedCloseReport(feedId: native!.feed.feedId, outcome: const FeedCloseOutcome.clean()));
    }
    for (final call in values) {
      final pin = call.native ?? (!call.reply.isCompleted ? call.accept() : null);
      if (pin == null) continue;
      if (pin.headerCalled.isCompleted && !pin.headerReply.isCompleted) pin.headerReply.completeError(updatesTestCancelled);
      final receipt = pin.closeReceipt;
      if (receipt != null && !receipt.isCompleted) receipt.complete(
        FeedCloseReport(feedId: pin.id, outcome: const FeedCloseOutcome.clean()));
    }
    for (final call in automatic) {
      if (!call.reply.isCompleted) call.reply.completeError(
        const CommandDispatchFailure.rejected(failure: updatesTestCancelled));
      final task = call.native;
      if (task == null) continue;
      if (!task.startReply.isCompleted) task.startReply.complete();
      if (task.finishCalled.isCompleted && !task.finishReply.isCompleted) task.finishReply.completeError(
        const CommandDispatchFailure.rejected(failure: updatesTestCancelled));
      for (final receipt in [task.closeReceipt, task.retryReceipt]) {
        if (receipt != null && !receipt.isCompleted) receipt.complete(
          UpdateTaskCloseReport(identity: task.identity, outcome: const FeedCloseOutcome.clean()));
      }
    }
  }
  @override
  Never noSuchMethod(Invocation invocation) =>
    throw UnsupportedError('Unscripted Updates native capability: ${invocation.memberName}');
}

/// The factory and operation registry are production implementations. Only the
/// native port is scripted; no test implements UpdatesRepository/Lifecycle.
final class UpdatesPortFixture {
  UpdatesPortFixture({ResourceBudget? resourceBudget, bool enabled = true})
    : budget = resourceBudget ?? ResourceBudget() {
    operations = OperationRegistry(clientId: 'updates-test', budget: budget);
    final assembly = createUpdatesRepository(port: port, budget: budget,
      operations: operations, controls: UpdateControls(enabled: enabled));
    repository = assembly.repository; lifecycle = assembly.lifecycle;
  }
  final ResourceBudget budget;
  final port = ScriptedUpdatesPort();
  late final OperationRegistry operations;
  late final UpdatesRepository repository;
  late final UpdatesLifecycle lifecycle;
  Future<CloseReport> close() {
    repository.seal(); port.releasePending();
    return repository.close();
  }
}
