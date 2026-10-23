import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import '../domain/directory_values.dart';
import 'directory_collection.dart';
import 'directory_materialization.dart';
import 'directory_read_jobs.dart';
import 'thread_directory_mirror.dart';
import 'thread_directory_reads.dart';

typedef _PageKey = ({int generation, ProductReadOrigin? origin, ThreadDirectoryReadRef? reference,
  ProductCollectionRef? collection, CollectionContinuation? continuation, int limit});

final class ThreadDirectoryPages {
  ThreadDirectoryPages(this.mirror, this.reads, this.lifetime)
      : _jobs = DirectoryReadJobs(lifetime, 'thread-directory-page');
  final ThreadDirectoryMirror mirror;
  final ThreadDirectoryReads reads;
  final ResourceLifetime lifetime;
  final DirectoryReadJobs<_PageKey, void> _jobs;
  final Map<int, ThreadDirectoryBinding> _active = {};
  int _sequence = 0;

  bool _loading(ThreadDirectoryBinding binding, {int? except}) => _active.entries.any((entry) =>
    entry.key != except && entry.value.generation == binding.generation && entry.value.origin == binding.origin &&
    entry.value.header.reference == binding.header.reference && entry.value.collection == binding.collection);

  void _refreshLoading() {
    final binding = mirror.current;
    final visible = mirror.source.value.threads;
    if (lifetime.sealed || binding == null || visible is! CurrentCollectionMirror<WorkspaceThreadRecord> ||
        visible.window.origin != binding.origin || visible.window.reference != binding.collection) return;
    final loading = _loading(binding);
    if (loading != visible.window.loading) mirror.source.publish(mirror.source.value.copyWith(
      threads: CollectionMirror.current(window: visible.window.copyWith(loading: loading))));
  }

  CollectionWindow<WorkspaceThreadRecord> _window(ThreadDirectoryBinding binding) {
    final ref = binding.collection;
    if (ref == null) throw directoryUnavailable;
    final visible = mirror.source.value.threads;
    if (visible is CurrentCollectionMirror<WorkspaceThreadRecord> && visible.window.origin == binding.origin &&
        visible.window.reference == ref) return visible.window;
    final old = directoryWindow(visible);
    return directoryEmpty<WorkspaceThreadRecord>(binding.origin, ref).copyWith(
      rows: old?.origin == binding.origin ? old!.rows : const {});
  }

  bool _ready(ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value, ProductReadOrigin origin, ProductEntityRef ref) =>
    value is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> && value.current.origin == origin && value.current.reference == ref;

  Future<void> load({int limit = 32}) {
    lifetime.admit(); directoryPageLimit(limit);
    final demand = mirror.capture();
    final originalWindow = demand.binding?.collection == null ? null : _window(demand.binding!);
    _PageKey key(ThreadDirectoryBinding? value, CollectionWindow<WorkspaceThreadRecord>? window) => (
      generation: demand.generation, origin: value?.origin, reference: value?.header.reference,
      collection: value?.collection, continuation: window?.continuation, limit: limit);
    ThreadDirectoryBinding? original;
    int? attempt;
    return _jobs.run(key(demand.binding, originalWindow), (bind) async {
      Future<void>? joined;
      CollectionWindow<WorkspaceThreadRecord>? snapshot;
      final binding = await mirror.ready(demand, bind: (value) {
        if (value.collection == null) throw directoryUnavailable;
        snapshot = originalWindow ?? _window(value);
        joined = bind(key(value, snapshot));
      });
      if (joined case final work?) { await work; return; }
      original = binding; mirror.check(binding, exact: true);
      final frozen = snapshot!;
      final dirty = frozen.entries.where((ref) => !_ready(frozen.rows[ref.entry], binding.origin, ref)).take(limit).toList();
      if (frozen.complete && dirty.isEmpty) return;
      attempt = ++_sequence;
      _active[attempt!] = binding;
      mirror.source.publish(mirror.source.value.copyWith(threads: CollectionMirror.current(
        window: frozen.copyWith(loading: true, error: null))));
      await reads.use(binding, (scope) async {
        final header = await scope.header();
        if (header.threads.listId < 0 || header.threads.total != frozen.reference.total ||
            header.hasMore != binding.header.hasMore) throw resourceProtocol('Thread root read changed its original fixed window.');
        final refs = <ProductEntityRef>[];
        var continuation = frozen.continuation;
        var indexComplete = continuation is EndCollectionContinuation;
        if (dirty.isNotEmpty) { refs.addAll(dirty); }
        else if (!indexComplete) {
          final cursor = switch (continuation) { CursorCollectionContinuation(:final value) => value, _ => null };
          final page = await scope.entries(cursor: cursor, limit: limit);
          if (page.collection != frozen.reference || page.items.length > limit ||
              page.items.any((ref) => ref.entry < 0 || ref.revision < 0) ||
              page.items.map((ref) => ref.entry).toSet().length != page.items.length ||
              page.items.any((ref) => frozen.entries.any((old) => old.entry == ref.entry)) ||
              frozen.entries.length + page.items.length > frozen.reference.total ||
              page.hasMore != (frozen.entries.length + page.items.length < frozen.reference.total) ||
              (page.nextCursor != null) != page.hasMore || page.hasMore && page.items.isEmpty) {
            throw resourceProtocol('A keyset page changed its original collection or ordered prefix.');
          }
          refs.addAll(page.items);
          if (page.hasMore) {
            final next = await materializeReadText(page.nextCursor!,
              read: (field, offset) => scope.text(field, offset: offset, maxBytes: 65536));
            if (next == cursor) throw resourceProtocol('The directory keyset cursor did not advance.');
            continuation = CollectionContinuation.cursor(value: next);
          } else { continuation = const CollectionContinuation.end(); }
          indexComplete = !page.hasMore;
        }
        final rows = Map<int, ReadValue<WorkspaceThreadRecord, ProductEntityRef>>.of(frozen.rows);
        StudioFailure? failure;
        StackTrace? failureStack;
        for (final ref in refs) {
          if (_ready(rows[ref.entry], binding.origin, ref)) continue;
          try {
            final entity = await scope.entity(ref);
            if (entity.reference != ref) throw resourceProtocol('A directory entity changed its original ref.');
            final value = await readWorkspaceThreadRecord(entity.value,
              (field, offset) => scope.text(field, offset: offset, maxBytes: 65536));
            final prior = directoryPrevious(rows[ref.entry]);
            if (prior?.origin == binding.origin && prior?.reference.entry == ref.entry && prior!.value.id != value.id) {
              throw resourceProtocol('A directory entry was reused for another Thread.');
            }
            final input = mirror.scope;
            if (input is QueryThreadDirectoryScope && (!value.isRoot || value.archived != input.query.archived ||
                input.query.projectId != null && value.projectId != input.query.projectId) ||
                input is SingleThreadDirectoryScope && value.id != input.threadId) {
              throw resourceProtocol('A directory entity does not belong to its original scope.');
            }
            rows[ref.entry] = ReadValue.ready(current: Materialized(origin: binding.origin, reference: ref, value: value));
          } catch (error, stack) {
            lifetime.lastCause = error; lifetime.lastStack = stack;
            failure ??= resourceFailure(error); failureStack ??= stack;
            rows[ref.entry] = ReadValue.failed(origin: binding.origin, reference: ref,
              error: resourceFailure(error), previous: directoryPrevious(rows[ref.entry]));
          }
        }
        mirror.check(binding, exact: true);
        final candidate = dirty.isNotEmpty ? frozen.entries : [...frozen.entries, ...refs];
        final latest = _window(binding);
        final overlap = candidate.length < latest.entries.length ? candidate.length : latest.entries.length;
        for (var index = 0; index < overlap; index++) { if (candidate[index] != latest.entries[index]) throw directorySuperseded; }
        final expands = candidate.length >= latest.entries.length;
        final entries = expands ? candidate : latest.entries;
        final merged = Map<int, ReadValue<WorkspaceThreadRecord, ProductEntityRef>>.of(latest.rows);
        for (final ref in refs) { if (!_ready(merged[ref.entry], binding.origin, ref)) merged[ref.entry] = rows[ref.entry]!; }
        // Concurrent lookup is allowed to fill the same immutable field first.
        final next = expands ? continuation : latest.continuation;
        final complete = (expands ? indexComplete : next is EndCollectionContinuation) && entries.length == frozen.reference.total &&
          entries.every((ref) => _ready(merged[ref.entry], binding.origin, ref));
        StudioFailure? visibleError;
        for (final ref in entries) { if (merged[ref.entry] case FailedReadValue<WorkspaceThreadRecord, ProductEntityRef>(:final error)) visibleError ??= error; }
        mirror.source.publish(mirror.source.value.copyWith(threads: CollectionMirror.current(window: CollectionWindow(
          origin: binding.origin, reference: frozen.reference, entries: entries, rows: merged,
          continuation: next, complete: complete, loading: _loading(binding, except: attempt), error: visibleError))));
        if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
      });
    }).then<void>((_) { if (attempt != null) _active.remove(attempt); _refreshLoading(); }, onError: (Object error, StackTrace stack) {
      if (attempt != null) _active.remove(attempt);
      final binding = original;
      if (binding != null && reads.current(binding) && attempt == _sequence) {
        final window = _window(binding);
        if (!window.complete) mirror.source.publish(mirror.source.value.copyWith(threads: CollectionMirror.current(
          window: window.copyWith(loading: _loading(binding), error: resourceFailure(error)))));
      }
      _refreshLoading();
      Error.throwWithStackTrace(resourceFailure(error), stack);
    });
  }
}
