import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';

import 'scripted_feed.dart';

const updatesTestOrigin = ProductReadOrigin(
  ownerEpoch: 'updates-native',
  incarnation: 1,
);
const updatesTestCancelled = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The scripted Updates environment is closing.',
  retryable: false,
  correlationId: 'updates-test-close',
);

/// One business update has one immutable version text; only progress and
/// business revisions advance, so a preparation's captured version still
/// matches the value its native finish target returns.
const updatesTestVersion = '2.0.0';

UpdatesHeader availableUpdateHeader(int revision) => UpdatesHeader(
  reference: UpdatesReadRef(entry: 1, revision: revision),
  brief: UpdatesBrief.available(revision: revision, checkedAt: revision),
  summary: UpdateSummaryReadRef(entry: 2, revision: revision),
  operation: null,
  error: null,
  details: UpdateDetailsReadRef(entry: 3, revision: revision),
);

UpdatesHeader downloadingUpdateHeader(int revision) => UpdatesHeader(
  reference: UpdatesReadRef(entry: 1, revision: revision),
  brief: UpdatesBrief.downloading(
    revision: revision,
    updatedAt: revision,
    downloaded: 1,
    total: 100,
  ),
  summary: UpdateSummaryReadRef(entry: 2, revision: revision),
  operation: null,
  error: null,
  details: UpdateDetailsReadRef(entry: 3, revision: revision),
);

UpdatesHeader readyUpdateHeader(int revision) => UpdatesHeader(
  reference: UpdatesReadRef(entry: 1, revision: revision),
  brief: UpdatesBrief.ready(revision: revision, readyAt: revision),
  summary: UpdateSummaryReadRef(entry: 2, revision: revision),
  operation: null,
  error: null,
  details: UpdateDetailsReadRef(entry: 3, revision: revision),
);

UpdatesHeader installFailedUpdateHeader(int revision) => UpdatesHeader(
  reference: UpdatesReadRef(entry: 1, revision: revision),
  brief: UpdatesBrief.installFailed(
    revision: revision,
    failedAt: revision,
    retryable: true,
  ),
  summary: UpdateSummaryReadRef(entry: 2, revision: revision),
  operation: null,
  error: UpdateErrorReadRef(entry: 4, revision: revision),
  details: UpdateDetailsReadRef(entry: 3, revision: revision),
);

UpdatesHeader idleUpdateHeader(int revision) => UpdatesHeader(
  reference: UpdatesReadRef(entry: 1, revision: revision),
  brief: UpdatesBrief.idle(revision: revision, updatedAt: revision),
  summary: null,
  operation: null,
  error: null,
  details: null,
);

SourceStateErrorRead installErrorRead() => const SourceStateErrorRead(
  code: ReadText.inline(text: 'network'),
  message: ReadText.inline(text: 'offline'),
  retryable: true,
);

UpdateDetailsRead updateDetailsRead(int revision) => UpdateDetailsRead(
  summary: UpdateSummaryRead(
    version: const ReadText.inline(text: updatesTestVersion),
    publishedAt: revision,
    notesUrl: ReadText.inline(text: 'https://updates.invalid/$revision'),
  ),
  installer: const UpdateAssetRead(
    url: ReadText.inline(text: 'https://updates.invalid/installer'),
    size: 7,
    sha256: ReadText.inline(text: 'unused-by-value-read'),
    signature: ReadText.inline(text: 'unused-by-value-read'),
  ),
);

UpdatesReadHeader availableUpdateRead(int revision) =>
    UpdatesReadHeader.available(
      revision: revision,
      checkedAt: revision,
      update: updateDetailsRead(revision),
    );

UpdatesReadHeader downloadingUpdateRead(int revision) =>
    UpdatesReadHeader.downloading(
      revision: revision,
      updatedAt: revision,
      update: updateDetailsRead(revision),
      downloaded: 1,
      total: 100,
    );

UpdatesReadHeader readyUpdateRead(int revision) => UpdatesReadHeader.ready(
  revision: revision,
  readyAt: revision,
  update: updateDetailsRead(revision),
);

UpdatesReadHeader installFailedUpdateRead(int revision) =>
    UpdatesReadHeader.installFailed(
      revision: revision,
      failedAt: revision,
      update: updateDetailsRead(revision),
      error: installErrorRead(),
    );

/// Native frames only. Tests choose every header/origin; there is no mirror,
/// automatic-start policy, value gate or business retry in this environment.
final class UpdatesNativeFeed {
  UpdatesNativeFeed(this.origin, int index)
    : feed = ScriptedFeed<UpdatesFrame>(
        feedId: 'updates-native-$index',
        sequenceOf: (frame) =>
            frame is UpdatesData ? frame.deliverySequence : null,
        isTerminal: (frame) => frame is! UpdatesData,
      );
  final ProductReadOrigin origin;
  final ScriptedFeed<UpdatesFrame> feed;
  int _sequence = 0;
  int _revision = 0;
  ProductFeedIdentity get identity => ProductFeedIdentity(
    feedId: feed.feedId,
    ownerEpoch: origin.ownerEpoch,
    incarnation: origin.incarnation,
    resource: ProductResource.updates,
  );

  Future<void> publish(
    UpdatesHeader header, {
    required int projectionRevision,
  }) async {
    await feed.listened.future;
    final stamp = ProductProjectionStamp(
      ownerEpoch: origin.ownerEpoch,
      incarnation: origin.incarnation,
      revision: projectionRevision,
    );
    final event = _sequence == 0
        ? UpdatesEvent.baseline(identity: identity, stamp: stamp, value: header)
        : UpdatesEvent.replace(
            stamp: stamp,
            baseRevision: _revision,
            value: header,
          );
    _revision = projectionRevision;
    feed.emit(UpdatesFrame.data(deliverySequence: ++_sequence, event: event));
    await feed.acknowledged(_sequence);
  }

  void fail(StudioFailure failure) =>
      feed.emit(UpdatesFrame.failure(identity: identity, error: failure));
  void replaceOwner() => feed.emit(
    UpdatesFrame.closed(
      identity: identity,
      reason: ProductFeedCloseReason.ownerReplaced,
    ),
  );
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
    _headerReads.add(
      headerReply.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      ),
    );
    return headerReply.future;
  }

  @override
  void requestClose() => sealed = true;
  @override
  Future<FeedCloseReport> close() async {
    requestClose();
    if (!closeCalled.isCompleted) closeCalled.complete();
    await Future.wait(_headerReads);
    final report =
        await (closeReceipt?.future ??
            Future.value(
              FeedCloseReport(
                feedId: id,
                outcome: const FeedCloseOutcome.clean(),
              ),
            ));
    closed = report.outcome is CleanFeedCloseOutcome;
    return report;
  }

  @override
  Future<FeedCloseReport> retryClose() => close();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Updates value capability: ${invocation.memberName}',
  );
}

/// One scripted native task scope. Every manual/automatic/preparation open is
/// the same native shape; tests only choose which capability they exercise and
/// what the original preparation target carried.
final class UpdateTaskOpen {
  UpdateTaskOpen(
    this.kind,
    this.operationId,
    this.index, {
    this.expectedRevision,
    this.version,
  });
  final String kind;
  final OperationId operationId;
  final int index;
  final int? expectedRevision;
  final String? version;
  final reply = Completer<UpdateTaskConnection>();
  ScriptedUpdateTask? native;
  ScriptedUpdateTask accept() {
    final value = ScriptedUpdateTask(
      UpdateTaskIdentity(
        runtimeEpoch: 'updates-runtime',
        taskId: '$kind-$index',
        operationId: operationId,
      ),
    );
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
    calls.add('start');
    startCalled.complete();
    return startReply.future;
  }

  @override
  Future<UpdatesReadTarget> finish() {
    calls.add('finish');
    finishCalled.complete();
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
    final report =
        await ((retry ? retryReceipt : closeReceipt)?.future ??
            Future.value(
              UpdateTaskCloseReport(
                identity: identity,
                outcome: const FeedCloseOutcome.clean(),
              ),
            ));
    await Future.wait<void>([
      if (startCalled.isCompleted)
        startReply.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        ),
      if (finishCalled.isCompleted)
        finishReply.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        ),
    ]);
    closed = report.outcome is CleanFeedCloseOutcome;
    return report;
  }
}

final class ScriptedUpdatesPort implements UpdatesPort {
  final feeds = <UpdatesFeedOpen>[];
  final values = <UpdatesValueOpen>[];
  final checks = <UpdateTaskOpen>[];
  final preparations = <UpdateTaskOpen>[];
  final automatic = <UpdateTaskOpen>[];
  final _feedWaiters = <int, Completer<UpdatesFeedOpen>>{};
  final _valueWaiters = <int, Completer<UpdatesValueOpen>>{};
  final _checkWaiters = <int, Completer<UpdateTaskOpen>>{};
  final _preparationWaiters = <int, Completer<UpdateTaskOpen>>{};
  final _automaticWaiters = <int, Completer<UpdateTaskOpen>>{};
  void Function()? openingFeed;
  void Function()? openingCheck;
  void Function()? openingPreparation;
  void Function()? openingAutomatic;

  Future<UpdatesFeedOpen> feedOpened(int index) => index < feeds.length
      ? Future.value(feeds[index])
      : _feedWaiters.putIfAbsent(index, Completer<UpdatesFeedOpen>.new).future;
  Future<UpdatesValueOpen> valueOpened(int index) => index < values.length
      ? Future.value(values[index])
      : _valueWaiters
            .putIfAbsent(index, Completer<UpdatesValueOpen>.new)
            .future;
  Future<UpdateTaskOpen> checkOpened(int index) => index < checks.length
      ? Future.value(checks[index])
      : _checkWaiters.putIfAbsent(index, Completer<UpdateTaskOpen>.new).future;
  Future<UpdateTaskOpen> preparationOpened(int index) =>
      index < preparations.length
      ? Future.value(preparations[index])
      : _preparationWaiters
            .putIfAbsent(index, Completer<UpdateTaskOpen>.new)
            .future;
  Future<UpdateTaskOpen> automaticOpened(int index) => index < automatic.length
      ? Future.value(automatic[index])
      : _automaticWaiters
            .putIfAbsent(index, Completer<UpdateTaskOpen>.new)
            .future;

  @override
  Future<FeedConnection<UpdatesFrame>> openUpdates() {
    final call = UpdatesFeedOpen(feeds.length);
    feeds.add(call);
    _feedWaiters.remove(call.index)?.complete(call);
    openingFeed?.call();
    return call.reply.future;
  }

  @override
  Future<UpdatesReadConnection> openUpdatesRead(
    UpdatesReadRef reference, {
    required ProductReadOrigin origin,
  }) {
    final call = UpdatesValueOpen(
      UpdatesReadTarget(origin: origin, reference: reference),
      values.length,
    );
    values.add(call);
    _valueWaiters.remove(call.index)?.complete(call);
    return call.reply.future;
  }

  @override
  Future<UpdateTaskConnection> openUpdateCheck(OperationId operationId) {
    final call = UpdateTaskOpen('check', operationId, checks.length);
    checks.add(call);
    _checkWaiters.remove(call.index)?.complete(call);
    openingCheck?.call();
    return call.reply.future;
  }

  @override
  Future<UpdateTaskConnection> openUpdatePreparation(
    OperationId operationId, {
    required int expectedRevision,
    required String version,
  }) {
    final call = UpdateTaskOpen(
      'preparation',
      operationId,
      preparations.length,
      expectedRevision: expectedRevision,
      version: version,
    );
    preparations.add(call);
    _preparationWaiters.remove(call.index)?.complete(call);
    openingPreparation?.call();
    return call.reply.future;
  }

  @override
  Future<UpdateTaskConnection> openAutomaticUpdate(OperationId operationId) {
    final call = UpdateTaskOpen('automatic', operationId, automatic.length);
    automatic.add(call);
    _automaticWaiters.remove(call.index)?.complete(call);
    openingAutomatic?.call();
    return call.reply.future;
  }

  /// After the real owners seal, release only this test's pending native
  /// barriers so their original cleanup can join, including a late open.
  void releasePending() {
    for (final call in feeds) {
      final native =
          call.native ?? (!call.reply.isCompleted ? call.accept() : null);
      native?.feed.requestClose();
      final receipt = native?.feed.closeReceipt;
      if (receipt != null && !receipt.isCompleted)
        receipt.complete(
          FeedCloseReport(
            feedId: native!.feed.feedId,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
    }
    for (final call in values) {
      final pin =
          call.native ?? (!call.reply.isCompleted ? call.accept() : null);
      if (pin == null) continue;
      if (pin.headerCalled.isCompleted && !pin.headerReply.isCompleted)
        pin.headerReply.completeError(updatesTestCancelled);
      final receipt = pin.closeReceipt;
      if (receipt != null && !receipt.isCompleted)
        receipt.complete(
          FeedCloseReport(
            feedId: pin.id,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
    }
    for (final call in [...checks, ...preparations, ...automatic]) {
      if (!call.reply.isCompleted)
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: updatesTestCancelled),
        );
      final task = call.native;
      if (task == null) continue;
      if (!task.startReply.isCompleted) task.startReply.complete();
      if (task.finishCalled.isCompleted && !task.finishReply.isCompleted)
        task.finishReply.completeError(
          const CommandDispatchFailure.rejected(failure: updatesTestCancelled),
        );
      for (final receipt in [task.closeReceipt, task.retryReceipt]) {
        if (receipt != null && !receipt.isCompleted)
          receipt.complete(
            UpdateTaskCloseReport(
              identity: task.identity,
              outcome: const FeedCloseOutcome.clean(),
            ),
          );
      }
    }
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Updates native capability: ${invocation.memberName}',
  );
}

/// The factory and operation registry are production implementations. Only the
/// native port is scripted; no test implements UpdatesRepository/Lifecycle.
final class UpdatesPortFixture {
  UpdatesPortFixture({ResourceBudget? resourceBudget, bool enabled = true})
    : budget = resourceBudget ?? ResourceBudget() {
    operations = OperationRegistry(clientId: 'updates-test', budget: budget);
    final assembly = createUpdatesRepository(
      port: port,
      budget: budget,
      operations: operations,
      controls: UpdateControls(enabled: enabled),
    );
    repository = assembly.repository;
    lifecycle = assembly.lifecycle;
  }
  final ResourceBudget budget;
  final port = ScriptedUpdatesPort();
  late final OperationRegistry operations;
  late final UpdatesRepository repository;
  late final UpdatesLifecycle lifecycle;
  Future<CloseReport> close() {
    repository.seal();
    port.releasePending();
    return repository.close();
  }
}
