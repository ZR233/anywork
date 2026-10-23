import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import '../domain/directory_values.dart';
import 'directory_collection.dart';
import 'directory_materialization.dart';
import 'directory_read_jobs.dart';
import 'directory_read_pins.dart';
import 'thread_directory_mirror.dart';
import 'workspace_port.dart';

typedef _LookupKey = ({int generation, ProductReadOrigin? origin, ThreadDirectoryReadRef? reference, String id});
typedef _SourceKey = ({int generation, ProductReadOrigin? origin, ProductSourceStatusRef? reference});
typedef ThreadDirectoryRecord = ({ThreadDirectoryBinding binding, ProductEntityRef reference, WorkspaceThreadRecord value});

final class ThreadDirectoryReads {
  ThreadDirectoryReads(this.mirror, this.pins, this.lifetime)
      : _lookups = DirectoryReadJobs(lifetime, 'thread-directory-lookup'),
        _sources = DirectoryReadJobs(lifetime, 'thread-directory-source');
  final ThreadDirectoryMirror mirror;
  final DirectoryReadPins pins;
  final ResourceLifetime lifetime;
  final DirectoryReadJobs<_LookupKey, ThreadDirectoryRecord> _lookups;
  final DirectoryReadJobs<_SourceKey, void> _sources;
  int _lookupAttempt = 0;
  ({int attempt, ThreadDirectoryBinding binding, StudioFailure? error})? _metadataRead;

  StudioFailure? metadataError(ThreadDirectoryState state) {
    if (state.projection.sync.phase == ResourceSyncPhase.failed) return state.projection.sync.error;
    final read = _metadataRead;
    if (read == null || read.attempt != _lookupAttempt || !current(read.binding) ||
        state.projection.stamp?.origin != read.binding.origin ||
        state.projection.header?.reference != read.binding.header.reference) return null;
    return read.error;
  }

  void _metadataResult(int attempt, ThreadDirectoryBinding? binding, StudioFailure? error) {
    if (mirror.scope is! SingleThreadDirectoryScope || lifetime.sealed || attempt != _lookupAttempt ||
        binding != null && !current(binding)) return;
    _metadataRead = binding == null ? null : (attempt: attempt, binding: binding, error: error);
    // Notify the existing mirror's observers without changing canonical source
    // state or inventing an entity ref for a lookup that failed before one.
    mirror.source.publish(mirror.source.value);
  }

  bool current(ThreadDirectoryBinding binding, {bool source = false}) {
    final now = mirror.current;
    return !lifetime.sealed && now != null && now.origin == binding.origin && now.generation == binding.generation &&
      (source ? now.header.source.status == binding.header.source.status :
        now.header.reference == binding.header.reference && now.collection == binding.collection);
  }

  Future<T> use<T>(ThreadDirectoryBinding binding, Future<T> Function(ThreadDirectoryReadConnection) action) {
    mirror.check(binding);
    return pins.thread(binding.target, () => current(binding), action);
  }

  Future<ThreadDirectoryRecord> lookup(String id) {
    final demand = mirror.capture();
    final attempt = ++_lookupAttempt;
    ThreadDirectoryBinding? original = demand.binding;
    _LookupKey key(ThreadDirectoryBinding? value) => (generation: demand.generation,
      origin: value?.origin, reference: value?.header.reference, id: id);
    final work = _lookups.run(key(demand.binding), (bind) async {
      Future<ThreadDirectoryRecord>? joined;
      final binding = await mirror.ready(demand, bind: (value) { joined = bind(key(value)); });
      original = binding;
      if (joined case final work?) return await work;
      mirror.check(binding, exact: true);
      return await use(binding, (scope) async {
        final header = await scope.header();
        if (header.threads.total != binding.collection?.total || header.threads.listId < 0 ||
            header.hasMore != binding.header.hasMore) throw resourceProtocol('Thread root read changed its frozen window.');
        final ref = await scope.lookupThread(id);
        if (ref == null) throw const StudioFailure(code: StudioFailureCode.notFound,
          message: 'The requested Thread is absent from its original metadata scope.', retryable: false, correlationId: 'workspace');
        if (ref.entry < 0 || ref.revision < 0) throw resourceProtocol('Thread lookup returned an invalid ref.');
        _offer(binding, ref, (old) => ReadValue.loading(origin: binding.origin, reference: ref,
          previous: directoryPrevious(old)), attempt: attempt);
        try {
        final entity = await scope.entity(ref);
          if (entity.reference != ref) throw resourceProtocol('Thread entity has another ref.');
        final value = await readWorkspaceThreadRecord(entity.value,
          (field, offset) => scope.text(field, offset: offset, maxBytes: 65536));
        if (value.id != id) throw resourceProtocol('Thread lookup returned another business identity.');
          mirror.check(binding, exact: true);
          _offer(binding, ref, (_) => ReadValue.ready(current: Materialized(origin: binding.origin, reference: ref, value: value)),
            attempt: attempt);
          mirror.check(binding, exact: true);
        return (binding: binding, reference: ref, value: value);
        } catch (error, stack) {
          _offer(binding, ref, (old) {
            if (old is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> && old.current.reference == ref) return old;
            return ReadValue.failed(origin: binding.origin, reference: ref,
              error: resourceFailure(error), previous: directoryPrevious(old));
          }, attempt: attempt);
          Error.throwWithStackTrace(error, stack);
  }
      });
    });
    final result = work.then<ThreadDirectoryRecord>((record) {
      mirror.check(record.binding, exact: true);
      _offer(record.binding, record.reference, (_) => ReadValue.ready(current: Materialized(
        origin: record.binding.origin, reference: record.reference, value: record.value)), attempt: attempt);
      mirror.check(record.binding, exact: true);
      _metadataResult(attempt, record.binding, null);
      return record;
    }).then<ThreadDirectoryRecord>((record) => record, onError: (Object error, StackTrace stack) {
      _metadataResult(attempt, original, resourceFailure(error));
      Error.throwWithStackTrace(resourceFailure(error), stack);
    });
    // Complete work and handlers precede publication; reentrant retry can only
    // clear/settle its own newer attempt, even when it joins the same read job.
    _metadataResult(attempt, demand.binding, null);
    return result;
  }

  void _offer(ThreadDirectoryBinding binding, ProductEntityRef ref,
      ReadValue<WorkspaceThreadRecord, ProductEntityRef> Function(ReadValue<WorkspaceThreadRecord, ProductEntityRef>?) change,
      {required int attempt}) {
    if (!current(binding) || mirror.scope is SingleThreadDirectoryScope && attempt != _lookupAttempt) return;
    final visible = mirror.source.value.threads;
    final collection = binding.collection;
    if (collection != null) {
      final window = visible is CurrentCollectionMirror<WorkspaceThreadRecord> && visible.window.origin == binding.origin &&
          visible.window.reference == collection ? visible.window : directoryEmpty<WorkspaceThreadRecord>(binding.origin, collection);
      final old = window.rows[ref.entry];
      final next = change(old);
      if (next == old) return;
      final rows = Map<int, ReadValue<WorkspaceThreadRecord, ProductEntityRef>>.of(window.rows);
      rows[ref.entry] = next;
      mirror.source.publish(mirror.source.value.copyWith(threads: CollectionMirror.current(window: window.copyWith(rows: rows))));
    }
  }

  Future<void> sourceStatus() {
    final demand = mirror.capture();
    _SourceKey key(ThreadDirectoryBinding? value) => (generation: demand.generation,
      origin: value?.origin, reference: value?.header.source.status);
    ThreadDirectoryBinding? original;
    return _sources.run(key(demand.binding), (bind) async {
      Future<void>? joined;
      final binding = await mirror.ready(demand, bind: (value) { joined = bind(key(value)); });
      if (joined case final work?) { await work; return; }
      original = binding; mirror.check(binding);
      if (!current(binding, source: true)) throw directorySuperseded;
      final ref = binding.header.source.status;
      final old = mirror.source.value.sourceStatus;
      if (old is ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef> &&
          old.current.origin == binding.origin && old.current.reference == ref) return;
      mirror.source.publish(mirror.source.value.copyWith(sourceStatus: ReadValue.loading(origin: binding.origin,
        reference: ref, previous: directoryPrevious(old))));
      final value = await pins.source((resource: ProductResource.threadDirectory, origin: binding.origin, reference: ref),
        binding.header.source.brief, () => current(binding, source: true));
      if (!current(binding, source: true)) throw directorySuperseded;
      mirror.source.publish(mirror.source.value.copyWith(sourceStatus: ReadValue.ready(
        current: Materialized(origin: binding.origin, reference: ref, value: value))));
    }).then<void>((_) {}, onError: (Object error, StackTrace stack) {
      final binding = original;
      if (binding != null && current(binding, source: true)) {
        final old = mirror.source.value.sourceStatus;
        if (old is! ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef>) {
          mirror.source.publish(mirror.source.value.copyWith(sourceStatus: ReadValue.failed(origin: binding.origin,
            reference: binding.header.source.status, error: resourceFailure(error), previous: directoryPrevious(old))));
        }
      }
      Error.throwWithStackTrace(resourceFailure(error), stack);
    });
  }
}
