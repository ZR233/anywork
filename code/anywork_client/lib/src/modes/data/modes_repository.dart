import 'dart:async';

import '../../../operations.dart';
import '../../../operations_ports.dart' show OperationRecorder, OperationWriter, RejectedCommandDispatchFailure, UnknownOutcomeCommandDispatchFailure, CommittedButUnobservedCommandDispatchFailure, ConfirmedWithoutUsableReceiptCommandDispatchFailure;
import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/mode_documents.dart';
import '../domain/mode_values.dart';
import '../domain/modes_repository.dart';
import '../domain/modes_state.dart';
import 'mode_intents.dart';
import 'mode_reader.dart';
import 'modes_frames.dart';
import 'modes_port.dart';

ModesRepository createModesRepository({required ModesPort port, required ResourceBudget budget, required OperationRecorder operations}) => _ModesRepository(port, budget, operations);

final class _ModesRepository implements ModesRepository {
  _ModesRepository(this.port, ResourceBudget budget, this.operations) : lifetime = ResourceLifetime(budget), source = ResourceSource(ModesState(projection: const ProductProjection(stamp: null, header: null, sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)), modes: const CollectionMirror.unavailable(lastKnown: null)), budget, 'modes:observer') {
    lifetime.onSeal(source.seal);
  }
  final ModesPort port;
  final OperationRecorder operations;
  final ResourceLifetime lifetime;
  final ResourceSource<ModesState> source;
  ProductFeedOwner<ModeCatalogFrame>? _feed;
  ProductProjectionStamp? _feedStamp;
  ProductCollectionRef? _collection;
  final Map<ModeCatalogReadTarget, PinnedReadOwner<ModeCatalogReadConnection>> _scopes = {};
  final Map<({ProductReadOrigin? origin, ModeCatalogReadRef? reference, ProductCollectionRef? collection, Object? opening, CollectionContinuation? continuation, int limit}), Future<void>> _pages = {};
  final Map<OperationId, _ModeJob> _jobs = {};
  Object? _opening;
  Future<void>? _restarting;
  ProductFeedOwner<ModeCatalogFrame>? _retiringFeed;
  final Map<ProductFeedOwner<ModeCatalogFrame>, Future<void>> _deferredRestarts = {};
  Future<void> _writes = Future.value();
  int _pageGeneration = 0;
  bool _sealed = false;
  bool _sourceClosed = false;

  @override
  ReadonlyLatestValue<ModesState> get state => source.readonly;
  void _admit() { if (_sealed) throw resourceCancelled; lifetime.admit(); }

  void _start({Object? opening}) {
    lifetime.admit();
    _feedStamp = null;
    late final ProductFeedOwner<ModeCatalogFrame> feed;
    feed = ProductFeedOwner(lifetime: lifetime, owner: 'modes:catalog-feed', open: port.openModeCatalog, sequence: (frame) => frame is ModeCatalogData ? frame.deliverySequence : null, apply: (frame) async {
      if (!identical(_feed, feed) || lifetime.sealed) return frame is ModeCatalogData ? frame.deliverySequence : null;
      switch (frame) {
        case ModeCatalogData(:final deliverySequence, :final event):
          switch (event) {
            case ModeCatalogBaselineEvent(:final identity, :final stamp, :final value):
              if (_feedStamp != null || identity.resource != ProductResource.modeCatalog || identity.ownerEpoch != stamp.ownerEpoch || identity.incarnation != stamp.incarnation) throw resourceProtocol('The Mode baseline has another source identity.');
              feed.bindIdentity(identity); _feedStamp = stamp;
              _adopt(stamp, value.header, value.collection, null, const [], const [], baseline: true);
            case ModeCatalogChangeEvent(:final stamp, :final baseRevision, :final value):
              if (_feedStamp == null || _feedStamp!.origin != stamp.origin || baseRevision != _feedStamp!.revision || stamp.revision <= baseRevision) throw resourceProtocol('The Mode projection has a revision gap.');
              _feedStamp = stamp;
              _adopt(stamp, value.header, value.collection, value.baseCollectionRevision, value.upserted, value.removedEntries, baseline: false);
          }
          return deliverySequence;
        case ModeCatalogResyncRequired(:final identity):
          _control(identity); _restart(feed);
        case ModeCatalogFeedFailure(:final identity, :final error):
          _control(identity); _failed(feed, error);
        case ModeCatalogClosed(:final identity, :final reason):
          _control(identity);
          if (reason == ProductFeedCloseReason.ownerReplaced) { _restart(feed); } else { _failed(feed, const StudioFailure(code: StudioFailureCode.unavailable, message: 'The Mode catalog feed closed.', retryable: true, correlationId: 'modes')); }
      }
      return null;
    }, failed: (error) => _failed(feed, error));
    _feed = feed; _opening = opening ?? feed;
    _sync(ResourceSyncPhase.connecting);
  }

  void _sync(ResourceSyncPhase phase, [StudioFailure? error]) => source.publish(source.value.copyWith(projection: source.value.projection.copyWith(sync: ResourceSyncState(phase: phase, error: error, retryExhausted: false))));
  void _control(ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.modeCatalog || _feedStamp != null && (identity.ownerEpoch != _feedStamp!.ownerEpoch || identity.incarnation != _feedStamp!.incarnation)) throw resourceProtocol('A Mode control frame belongs to another source.');
    _feed!.bindIdentity(identity);
  }
  void _failed(ProductFeedOwner<ModeCatalogFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _sync(ResourceSyncPhase.failed, error); feed.requestClose(); unawaited(feed.cleanup(retry: false));
  }
  Future<void> _restart(ProductFeedOwner<ModeCatalogFrame> feed, {bool retry = false, Object? opening}) {
    final deferred = _deferredRestarts[feed]; if (deferred != null) return deferred;
    final prior = _restarting;
    if (prior != null) {
      if (identical(_retiringFeed, feed)) return prior;
      final queued = Completer<void>(); final token = opening ?? queued.future;
      _deferredRestarts[feed] = queued.future; _opening = token; feed.requestClose();
      Future<void>.sync(() => lifetime.run('modes:deferred-resync', () async {
        await prior; _deferredRestarts.remove(feed);
        if (!lifetime.sealed && identical(_feed, feed)) await _restart(feed, retry: retry, opening: token);
      })).then((_) => queued.complete(), onError: (Object error, StackTrace stack) { _deferredRestarts.remove(feed); queued.completeError(resourceFailure(error), stack); });
      queued.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      return queued.future;
    }
    final done = Completer<void>(); final token = opening ?? done.future;
    _restarting = done.future; _retiringFeed = feed; _opening = token;
    _sync(ResourceSyncPhase.reconnecting); feed.requestClose();
    Future<void>.sync(() => lifetime.run('modes:resync', () async {
      await feed.cleanup(retry: retry);
      if (!lifetime.sealed && identical(_feed, feed)) {
        if (!feed.released) throw const StudioFailure(code: StudioFailureCode.busy, message: 'The original Mode feed has unresolved cleanup.', retryable: true, correlationId: 'modes');
        _start(opening: token);
      }
    })).then((_) { _restarting = null; _retiringFeed = null; done.complete(); }, onError: (Object error, StackTrace stack) {
      lifetime.lastCause = error; lifetime.lastStack = stack; _restarting = null; _retiringFeed = null;
      if (!lifetime.sealed) _sync(ResourceSyncPhase.failed, resourceFailure(error));
      done.completeError(resourceFailure(error), stack);
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return done.future;
  }

  void _adopt(ProductProjectionStamp stamp, ModeCatalogHeader header, ProductCollectionRef? collection, int? base, List<ProductEntityRef> upserted, List<int> removed, {required bool baseline}) {
    if (collection == null || collection.total < 0 || header.revision < 0 || stamp.revision < 0 || upserted.length + removed.length > 100) throw resourceProtocol('The canonical Mode catalog metadata is invalid.');
    final old = source.value;
    if (old.projection.stamp?.origin == stamp.origin && old.projection.stamp!.revision > stamp.revision) return;
    if (!baseline && (base != _collection?.revision || collection.entry != _collection?.entry)) throw resourceProtocol('The Mode collection has an identity or revision gap.');
    if (upserted.map((item) => item.entry).toSet().length != upserted.length || removed.toSet().length != removed.length || removed.any((entry) => upserted.any((item) => item.entry == entry))) throw resourceProtocol('A Mode delta has inconsistent membership.');
    final prior = switch (old.modes) { CurrentCollectionMirror<ThreadModeDescriptor>(:final window) => window, UnavailableCollectionMirror<ThreadModeDescriptor>(:final lastKnown) => lastKnown };
    CollectionMirror<ThreadModeDescriptor> mirror;
    if (collection.total == 0) {
      mirror = CollectionMirror.current(window: _empty(stamp.origin, collection));
    } else if (prior?.origin == stamp.origin && prior?.reference == collection) {
      mirror = CollectionMirror.current(window: prior!);
    } else if (!baseline && old.modes is CurrentCollectionMirror<ThreadModeDescriptor> && prior!.origin == stamp.origin) {
      final rows = Map<int, ReadValue<ThreadModeDescriptor, ProductEntityRef>>.of(prior.rows)..removeWhere((entry, _) => removed.contains(entry));
      for (final reference in upserted) {
        final previous = _previous(rows[reference.entry]);
        if (previous != null && previous.reference != reference) rows[reference.entry] = ReadValue.failed(origin: stamp.origin, reference: reference, error: _superseded, previous: previous);
      }
      mirror = CollectionMirror.current(window: prior.copyWith(reference: collection, entries: const [], rows: rows, continuation: const CollectionContinuation.unknown(), complete: false, error: null));
    } else {
      mirror = prior == null ? CollectionMirror.current(window: _empty(stamp.origin, collection)) : CollectionMirror.unavailable(lastKnown: prior);
    }
    _collection = collection;
    final target = ModeCatalogReadTarget(origin: stamp.origin, reference: header.reference);
    for (final entry in List.of(_scopes.entries)) { if (entry.key != target) { entry.value.retire(); _scopes.remove(entry.key); } }
    source.publish(ModesState(projection: ProductProjection(stamp: stamp, header: header, sync: const ResourceSyncState(phase: ResourceSyncPhase.ready, error: null, retryExhausted: false)), modes: mirror));
    operations.observe(ResourceStamp(resourceKey: 'thread-mode-catalog', ownerEpoch: stamp.ownerEpoch, revision: header.revision));
  }

  CollectionWindow<ThreadModeDescriptor> _empty(ProductReadOrigin origin, ProductCollectionRef collection) => CollectionWindow(origin: origin, reference: collection, entries: const [], rows: const {}, continuation: collection.total == 0 ? const CollectionContinuation.end() : const CollectionContinuation.unknown(), complete: collection.total == 0, loading: false, error: null);
  PinnedReadOwner<ModeCatalogReadConnection> _scope(ModeCatalogReadTarget target) {
    final prior = _scopes[target]; if (prior != null && prior.accepting) return prior;
    return _scopes[target] = PinnedReadOwner(lifetime: lifetime, owner: 'modes:catalog-read', open: () => port.openModeCatalogRead(target.reference, origin: target.origin), request: (scope) => scope.requestClose(), closeNative: (scope) => scope.close(), retryNative: (scope) => scope.retryClose());
  }
  void _ensureFeed() {
    if (_feed == null) { _start(); } else if (_feed!.closing && _restarting == null) { _restart(_feed!, retry: true); }
  }
  Future<({ModeCatalogReadTarget target, ProductCollectionRef collection})> _ready() async {
    lifetime.admit(); _ensureFeed();
    ({ModeCatalogReadTarget target, ProductCollectionRef collection})? binding;
    await source.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed) throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      binding = (target: ModeCatalogReadTarget(origin: value.projection.stamp!.origin, reference: value.projection.header!.reference), collection: _collection!);
      return true;
    });
    return binding!;
  }

  @override
  Future<void> loadModesPage({int limit = 32}) {
    _admit(); if (limit < 1 || limit > 100) throw const StudioFailure(code: StudioFailureCode.invalidArgument, message: 'A Mode page limit must be between 1 and 100.', retryable: false, correlationId: 'modes');
    _ensureFeed(); _admit();
    final projection = source.value.projection;
    final current = source.value.modes;
    if (projection.sync.phase == ResourceSyncPhase.ready && current is CurrentCollectionMirror<ThreadModeDescriptor> && current.window.complete && current.window.error == null) return Future.value();
    final available = projection.sync.phase == ResourceSyncPhase.ready;
    final key = (origin: available ? projection.stamp?.origin : null, reference: available ? projection.header?.reference : null, collection: available ? _collection : null, opening: available ? null : _opening, continuation: current is CurrentCollectionMirror<ThreadModeDescriptor> && available ? current.window.continuation : null, limit: limit);
    final pending = _pages[key]; if (pending != null) return pending;
    final done = Completer<void>(); _pages[key] = done.future; final generation = ++_pageGeneration;
    lifetime.run('modes:catalog-page', () async {
      final binding = await _ready();
      if (key.reference != null && (key.origin != binding.target.origin || key.reference != binding.target.reference || key.collection != binding.collection) || key.opening != null && !identical(key.opening, _opening)) throw _superseded;
      final prior = source.value.modes;
      final window = prior is CurrentCollectionMirror<ThreadModeDescriptor> && prior.window.origin == binding.target.origin && prior.window.reference == binding.collection ? prior.window : _empty(binding.target.origin, binding.collection);
      final offset = switch (window.continuation) { OffsetCollectionContinuation(:final value) => value, EndCollectionContinuation() => binding.collection.total, _ => 0 };
      if (prior is CurrentCollectionMirror<ThreadModeDescriptor>) source.publish(source.value.copyWith(modes: CollectionMirror.current(window: window.copyWith(loading: true, error: null))));
      try {
        await _scope(binding.target).use((scope) async {
          final page = await scope.entries(offset: offset, limit: limit);
          final end = offset + page.items.length;
          if (page.collection != binding.collection || page.offset != offset || page.items.length > limit || end < offset || end > binding.collection.total || page.items.isEmpty && end < binding.collection.total || page.nextOffset != (end == binding.collection.total ? null : end)) throw resourceProtocol('The Mode index page does not match its pinned collection.');
          final rows = Map<int, ReadValue<ThreadModeDescriptor, ProductEntityRef>>.of(window.rows);
          final seen = window.entries.take(offset).map((entry) => entry.entry).toSet();
          for (final reference in page.items) {
            if (!seen.add(reference.entry)) throw resourceProtocol('The Mode index repeated an entry.');
            final entity = await scope.entity(reference);
            if (entity.reference != reference) throw resourceProtocol('The Mode entity response has another reference.');
            final value = await readModeDescriptor(scope, entity.value);
            rows[reference.entry] = ReadValue.ready(current: Materialized(origin: binding.target.origin, reference: reference, value: value));
          }
          if (lifetime.sealed) throw resourceCancelled;
          if (generation != _pageGeneration || source.value.projection.stamp?.origin != binding.target.origin || _collection != binding.collection) throw _superseded;
          final prefix = window.entries.take(offset).toList(); if (prefix.length != offset) throw _superseded;
          source.publish(source.value.copyWith(modes: CollectionMirror.current(window: window.copyWith(entries: [...prefix, ...page.items], rows: rows, continuation: page.nextOffset == null ? const CollectionContinuation.end() : CollectionContinuation.offset(value: page.nextOffset!), complete: page.nextOffset == null && end == binding.collection.total, loading: false, error: null))));
        });
      } catch (error) {
        final latest = source.value.modes;
        if (!lifetime.sealed && generation == _pageGeneration && source.value.projection.stamp?.origin == binding.target.origin && latest is CurrentCollectionMirror<ThreadModeDescriptor>) source.publish(source.value.copyWith(modes: CollectionMirror.current(window: latest.window.copyWith(loading: false, error: resourceFailure(error)))));
        rethrow;
      }
    }).then((_) { _pages.remove(key); done.complete(); }, onError: (Object error, StackTrace stack) { _pages.remove(key); done.completeError(resourceFailure(error), stack); });
    return done.future;
  }

  @override
  Future<ModeDefinitionSnapshot> readDefinition(String modeId) {
    _admit(); final requested = modeId; ThreadModeId(requested);
    return _query('modes:definition', () async {
      final snapshot = await port.readDefinition(requested);
      if (snapshot.document.definition.id.id != requested) throw resourceProtocol('The Mode definition belongs to another requested ID.');
      return freezeModeDefinition(snapshot);
    });
  }
  @override
  Future<ModeValidationResult> validate(String rawJson) { _admit(); return _query('modes:validate', () async { final result = await port.validate(rawJson); return ModeValidationResult(document: result.document == null ? null : freezeModeDocument(result.document!), issues: List.unmodifiable(result.issues)); }); }
  @override
  Future<String> schema() { _admit(); return _query('modes:schema', port.schema); }
  @override
  Future<WorkflowPreviewSnapshot> preview(WorkflowPreviewRequest request) { _admit(); final frozen = freezeWorkflowPreview(request); return _query('modes:preview', () async => freezeWorkflowPreviewResult(await port.preview(frozen))); }

  Future<T> _query<T>(String owner, Future<T> Function() read) {
    _admit();
    final ResourcePermit permit;
    try { permit = lifetime.budget.acquire(ResourceKind.readModel, owner: owner); } on ResourceBudgetExceeded catch (error) { throw error.failure; }
    try { return lifetime.run(owner, () async { try { return await read(); } finally { permit.release(); } }); } catch (_) { permit.release(); rethrow; }
  }

  @override
  OperationTicket<ModeDefinitionResult> save(ModeDocument document, {required int expectedRevision}) {
    _admit(); final frozen = freezeModeDocument(document);
    return _command('modes:save:${frozen.definition.id.id}', expectedRevision, (id) => port.save(frozen, expectedRevision: expectedRevision, operationId: id));
  }
  @override
  OperationTicket<ModeDefinitionResult> delete(String modeId, {required int expectedRevision}) { _admit(); ThreadModeId(modeId); return _command('modes:delete:$modeId', expectedRevision, (id) => port.delete(modeId, expectedRevision: expectedRevision, operationId: id)); }
  @override
  OperationTicket<ModeDefinitionResult> reload({required int expectedRevision}) => _command('modes:reload', expectedRevision, (id) => port.reload(expectedRevision: expectedRevision, operationId: id));

  OperationTicket<ModeDefinitionResult> _command(String target, int expectedRevision, Future<ModeDefinitionCommandReply> Function(OperationId) send) {
    _admit(); if (expectedRevision < 0) throw const StudioFailure(code: StudioFailureCode.invalidArgument, message: 'A Mode revision cannot be negative.', retryable: false, correlationId: 'modes');
    final previous = _writes; final done = Completer<void>(); final ready = Completer<_ModeJob?>(); _writes = done.future;
    _ModeJob? admitted;
    void activate() {
      try {
        lifetime.run('modes:command', () async { await previous; final job = await ready.future; try { if (job != null) await _execute(job); } finally { done.complete(); } }).then<void>((_) {}, onError: (Object error, StackTrace stack) { lifetime.lastCause = error; lifetime.lastStack = stack; if (!done.isCompleted) done.complete(); });
      } catch (error, stack) {
        lifetime.lastCause = error; lifetime.lastStack = stack;
        final job = admitted;
        if (job != null && !job.dispatched) { job.writer.rejected(resourceFailure(error)); }
        else if (job != null) { job.writer.evidenceFailed(resourceFailure(error)); }
        if (!done.isCompleted) done.complete();
      }
    }
    OperationWriter<ModeDefinitionResult>? writer;
    try {
      writer = operations.begin<ModeDefinitionResult>(target: target);
      final job = _ModeJob(writer, AttemptId(lifetime.nextAttempt()), send);
      job.permit = lifetime.budget.acquire(ResourceKind.observer, owner: 'modes:operation:${writer.ticket.id.value}');
      _jobs[writer.ticket.id] = job;
      void observe(OperationState _) { if (job.proven) { _jobs.remove(job.writer.ticket.id); job.observation?.cancel(); job.permit?.release(); } }
      final watched = writer.ticket.state.watchLatest(observe); job.observation = watched.observation; observe(watched.value);
      admitted = job; ready.complete(job); activate(); return writer.ticket;
    } catch (error) {
      ready.complete(null);
      activate();
      final job = writer == null ? null : _jobs.remove(writer.ticket.id); job?.observation?.cancel(); job?.permit?.release(); writer?.rejected(resourceFailure(error));
      throw resourceFailure(error);
    }
  }

  Future<void> _execute(_ModeJob job) async {
    CommitReceipt? receipt;
    ModeDefinitionResult? value;
    try {
      if (_sealed || lifetime.sealed) { job.writer.rejected(resourceCancelled); return; }
      job.dispatched = true;
      final reply = await job.send(job.writer.ticket.id);
      if (reply.receipt.operationId != job.writer.ticket.id) throw ConfirmedWithoutUsableReceiptCommandDispatchFailure(failure: resourceProtocol('The Mode receipt belongs to another operation.'));
      receipt = reply.receipt;
      value = ModeDefinitionResult(catalog: reply.catalog, definition: reply.definition == null ? null : freezeModeDefinition(reply.definition!));
      await _synchronize(reply.catalog, receipt);
      job.writer.accepted(value, receipt);
      if (!job.writer.ticket.state.value.observed) job.writer.synchronizationFailed(resourceProtocol('The canonical Mode source clock did not cover its receipt.'), value: value, receipt: receipt);
    } catch (error, stack) {
      lifetime.lastCause = error; lifetime.lastStack = stack;
      final failure = switch (error) { RejectedCommandDispatchFailure(:final failure) || UnknownOutcomeCommandDispatchFailure(:final failure) || CommittedButUnobservedCommandDispatchFailure(:final failure) || ConfirmedWithoutUsableReceiptCommandDispatchFailure(:final failure) => failure, _ => resourceFailure(error) };
      if (receipt != null) { job.writer.synchronizationFailed(failure, value: value, receipt: receipt); }
      else if (error is RejectedCommandDispatchFailure || !job.dispatched) { job.writer.rejected(failure); }
      else if (error is CommittedButUnobservedCommandDispatchFailure && error.receipt.operationId == job.writer.ticket.id) { job.writer.synchronizationFailed(failure, receipt: error.receipt); }
      else if (error is ConfirmedWithoutUsableReceiptCommandDispatchFailure || error is CommittedButUnobservedCommandDispatchFailure) { job.writer.acknowledgedSynchronizationFailed(failure); }
      else { job.writer.unknownOutcome(failure); }
      if (job.permit?.isReleased == false) job.permit!.mark(ResourcePhase.unresolved);
    } finally {
      job.finished = true;
    }
  }

  Future<void> _synchronize(ModeCatalogReadTarget target, CommitReceipt receipt) async {
    final stamps = receipt.targets.whereType<ResourceStamp>().toList();
    if (stamps.length != 1 || receipt.targets.length != 1 || stamps.single.resourceKey != 'thread-mode-catalog' || stamps.single.ownerEpoch != target.origin.ownerEpoch) throw resourceProtocol('The Mode receipt has inconsistent source targets.');
    _ensureFeed();
    if (source.value.projection.sync.phase == ResourceSyncPhase.ready && source.value.projection.stamp?.origin != target.origin) {
      await _scope(target).use((scope) async { await scope.header(); });
      await _restart(_feed!, retry: true);
    }
    await source.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed) throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      if (value.projection.stamp?.origin != target.origin) throw _superseded;
      final reference = value.projection.header!.reference;
      return reference.entry == target.reference.entry && reference.revision >= target.reference.revision && value.projection.header!.revision >= stamps.single.revision;
    });
  }

  @override
  void seal() => _sealed = true;
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => _close(deadline, true);
  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    seal();
    if (deadline == null) { await _writes; } else {
      final expired = Completer<void>(); final remaining = deadline.difference(DateTime.now()); final timer = Timer(remaining.isNegative ? Duration.zero : remaining, expired.complete);
      try { await Future.any([_writes, expired.future]); } finally { timer.cancel(); }
    }
    final report = await lifetime.close(deadline: deadline, retry: retry);
    final unresolved = <UnresolvedResource>[...report.unresolved];
    for (final job in _jobs.values) {
      final state = job.writer.ticket.state.value;
      unresolved.add(UnresolvedResource(owner: 'modes:operation:${state.id.value}', attemptId: job.attempt, issues: [FeedCloseIssue(diagnostic: StudioShutdownIssue(stage: 'modes', code: state.failurePhase?.name ?? 'commandEvidencePending', message: 'The original Mode operation has unresolved outcome or receipt observation.', retryable: state.error?.retryable ?? false, correlationId: state.error?.correlationId ?? 'modes'), recovery: job.finished ? CleanupRecovery.terminal : CleanupRecovery.awaitCompletion)]));
    }
    if (unresolved.isEmpty && !_sourceClosed) { _sourceClosed = true; _sync(ResourceSyncPhase.closed); source.close(); }
    return CloseReport(unresolved: unresolved);
  }

  Materialized<T, R>? _previous<T, R>(ReadValue<T, R>? value) => switch (value) { ReadyReadValue<T, R>(:final current) => current, LoadingReadValue<T, R>(:final previous) || FailedReadValue<T, R>(:final previous) => previous, _ => null };
  static const _superseded = StudioFailure(code: StudioFailureCode.superseded, message: 'The requested Mode catalog version has advanced.', retryable: true, correlationId: 'modes');
}

final class _ModeJob {
  _ModeJob(this.writer, this.attempt, this.send);
  final OperationWriter<ModeDefinitionResult> writer;
  final AttemptId attempt;
  final Future<ModeDefinitionCommandReply> Function(OperationId) send;
  ResourcePermit? permit;
  Observation? observation;
  bool dispatched = false;
  bool finished = false;
  bool get proven { final state = writer.ticket.state.value; return state.failurePhase == OperationFailurePhase.rejected || state.receipt != null && state.observed || state.acknowledged && state.observed; }
}
