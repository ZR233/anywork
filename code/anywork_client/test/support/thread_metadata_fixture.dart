import 'dart:async';

import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart';

const metadataOrigin = ProductReadOrigin(ownerEpoch: 'metadata-native', incarnation: 1);

/// Explicit native directory material. No Session, capture, membership policy
/// or UI demand is implemented by this environment.
ThreadMetadataState metadataState({WorkspaceThreadRecord? record, ProductReadOrigin origin = metadataOrigin,
  ResourceSyncPhase phase = ResourceSyncPhase.ready, StudioFailure? sourceError, StudioFailure? readError}) =>
  ThreadMetadataState(projection: ProductProjection(
    stamp: ProductProjectionStamp(ownerEpoch: origin.ownerEpoch, incarnation: origin.incarnation, revision: 1),
    header: const ThreadDirectoryHeader(source: ObservedHeader(
      brief: ObservedBrief.ready(revision: 1, updatedAt: 1, lastCheckedAt: null),
      status: ProductSourceStatusRef(entry: 9, revision: 1)),
      reference: ThreadDirectoryReadRef(entry: 1, revision: 1), directoryRevision: 1,
      searchProjectRevision: null, hasMore: false, nextCursor: null),
    sync: ResourceSyncState(phase: phase, error: sourceError, retryExhausted: false)),
    sourceStatus: null, readError: readError,
    value: record == null ? null : ReadValue.ready(current: Materialized(origin: origin,
      reference: const ProductEntityRef(entry: 2, revision: 1), value: record)));

/// The allowed external ThreadMetadata boundary. D0 owns readonly observation;
/// tests supply independent original query and native cleanup receipts.
final class ScriptedThreadMetadata implements ThreadMetadata {
  ScriptedThreadMetadata(this.threadId, {required ThreadMetadataState initial}) : source = LatestValue(initial);
  @override
  final String threadId;
  final LatestValue<ThreadMetadataState> source;
  late final ReadonlyLatestValue<ThreadMetadataState> _view = _MetadataStateView(this);
  @override
  ReadonlyLatestValue<ThreadMetadataState> get state => _view;
  final retryCalled = Completer<void>();
  final queryReply = Completer<void>();
  final closeCalled = Completer<void>();
  final retryCloseCalled = Completer<void>();
  final closed = Completer<void>();
  final _queries = <Future<void>>[];
  Completer<CloseReport>? closeReply;
  Completer<CloseReport>? retryCloseReply;
  void Function()? afterWatch;
  int retryCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  int requestCloseCalls = 0;
  bool _closing = false;
  @override
  Future<void> retry() {
    if (_closing) throw const StudioFailure(code: StudioFailureCode.cancelled,
      message: 'The original metadata owner is closing.', retryable: false, correlationId: 'metadata-script-close');
    retryCalls++;
    if (!retryCalled.isCompleted) retryCalled.complete();
    _queries.add(queryReply.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    return queryReply.future;
  }
  @override
  void requestClose() { requestCloseCalls++; _closing = true; }
  @override
  Future<CloseReport> close({DateTime? deadline}) {
    closeCalls++;
    if (!closeCalled.isCompleted) closeCalled.complete();
    return _close(closeReply);
  }
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    retryCloseCalls++;
    if (!retryCloseCalled.isCompleted) retryCloseCalled.complete();
    return _close(retryCloseReply);
  }
  Future<CloseReport> _close(Completer<CloseReport>? receipt) async {
    requestClose();
    final report = await (receipt?.future ?? Future.value(CloseReport(unresolved: [])));
    if (report.complete) {
      await Future.wait(_queries);
      source.close();
      if (!closed.isCompleted) closed.complete();
    }
    return report;
  }
  void releasePending() {
    if (retryCalled.isCompleted && !queryReply.isCompleted) queryReply.complete();
    for (final receipt in [closeReply, retryCloseReply]) {
      if (receipt != null && !receipt.isCompleted) receipt.complete(CloseReport(unresolved: []));
    }
  }
}

/// Thin native observation seam: a scripted synchronous publication after
/// registration can make watchLatest's returned snapshot older than value.
/// All observer state/notification/cancellation remains in D0 LatestValue.
final class _MetadataStateView implements ReadonlyLatestValue<ThreadMetadataState> {
  _MetadataStateView(this.owner);
  final ScriptedThreadMetadata owner;
  ReadonlyLatestValue<ThreadMetadataState> get delegate => owner.source.readonly;
  @override
  ThreadMetadataState get value => delegate.value;
  @override
  int get observerCount => delegate.observerCount;
  @override
  Observation watch(void Function(ThreadMetadataState) listener, {bool fireImmediately = false}) =>
    delegate.watch(listener, fireImmediately: fireImmediately);
  @override
  LatestWatch<ThreadMetadataState> watchLatest(void Function(ThreadMetadataState) listener) {
    final watched = delegate.watchLatest(listener);
    final action = owner.afterWatch;
    owner.afterWatch = null;
    action?.call();
    return watched;
  }
  @override
  Future<ThreadMetadataState> waitFor(bool Function(ThreadMetadataState) predicate) => delegate.waitFor(predicate);
}
