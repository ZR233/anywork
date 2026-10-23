import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import '../domain/directory_values.dart';
import 'directory_collection.dart';
import 'directory_materialization.dart';
import 'directory_read_jobs.dart';
import 'directory_read_pins.dart';
import 'project_directory_mirror.dart';
import 'workspace_port.dart';

typedef _LookupKey = ({int generation, ProductReadOrigin? origin, ProjectDirectoryReadRef? reference, String id});
typedef _SourceKey = ({int generation, ProductReadOrigin? origin, ProductSourceStatusRef? reference});
typedef _PageKey = ({int generation, ProductReadOrigin? origin, ProjectDirectoryReadRef? reference,
  ProductCollectionRef? collection, CollectionContinuation? continuation, int limit});
typedef ProjectDirectoryRecord = ({ProjectDirectoryBinding binding, ProductEntityRef reference, ProjectRecord value});

final class ProjectDirectoryReads {
  ProjectDirectoryReads(this.mirror, this.pins, this.lifetime)
      : _lookups = DirectoryReadJobs(lifetime, 'project-directory-lookup'),
        _sources = DirectoryReadJobs(lifetime, 'project-directory-source'),
        _pages = DirectoryReadJobs(lifetime, 'project-directory-page');
  final ProjectDirectoryMirror mirror;
  final DirectoryReadPins pins;
  final ResourceLifetime lifetime;
  final DirectoryReadJobs<_LookupKey, ProjectDirectoryRecord> _lookups;
  final DirectoryReadJobs<_SourceKey, void> _sources;
  final DirectoryReadJobs<_PageKey, void> _pages;
  final Map<int, ProjectDirectoryBinding> _active = {};
  int _sequence = 0;

  bool _loading(ProjectDirectoryBinding binding, {int? except}) => _active.entries.any((entry) =>
    entry.key != except && entry.value.generation == binding.generation && entry.value.origin == binding.origin &&
    entry.value.header.reference == binding.header.reference && entry.value.collection == binding.collection);

  void _refreshLoading() {
    final binding = mirror.current;
    final visible = mirror.source.value.projects;
    if (lifetime.sealed || binding == null || visible is! CurrentCollectionMirror<ProjectRecord> ||
        visible.window.origin != binding.origin || visible.window.reference != binding.collection) return;
    final loading = _loading(binding);
    if (loading != visible.window.loading) mirror.source.publish(mirror.source.value.copyWith(
      projects: CollectionMirror.current(window: visible.window.copyWith(loading: loading))));
  }

  bool current(ProjectDirectoryBinding binding, {bool source = false}) {
    final now = mirror.current;
    return !lifetime.sealed && now != null && now.origin == binding.origin && now.generation == binding.generation &&
      (source ? now.header.source.status == binding.header.source.status :
        now.header.reference == binding.header.reference && now.collection == binding.collection);
  }

  Future<T> use<T>(ProjectDirectoryBinding binding, Future<T> Function(ProjectDirectoryReadConnection) action) {
    mirror.check(binding);
    return pins.project(binding.target, () => current(binding), action);
  }

  CollectionWindow<ProjectRecord> _window(ProjectDirectoryBinding binding) {
    final ref = binding.collection;
    if (ref == null) throw directoryUnavailable;
    final value = mirror.source.value.projects;
    if (value is CurrentCollectionMirror<ProjectRecord> && value.window.origin == binding.origin && value.window.reference == ref) {
      return value.window;
    }
    final old = directoryWindow(value);
    return directoryEmpty<ProjectRecord>(binding.origin, ref).copyWith(rows: old?.origin == binding.origin ? old!.rows : const {});
  }

  bool _ready(ReadValue<ProjectRecord, ProductEntityRef>? value, ProductReadOrigin origin, ProductEntityRef ref) =>
    value is ReadyReadValue<ProjectRecord, ProductEntityRef> && value.current.origin == origin && value.current.reference == ref;

  Future<ProjectDirectoryRecord> lookup(String id) {
    final demand = mirror.capture();
    _LookupKey key(ProjectDirectoryBinding? value) => (generation: demand.generation,
      origin: value?.origin, reference: value?.header.reference, id: id);
    return _lookups.run(key(demand.binding), (bind) async {
      Future<ProjectDirectoryRecord>? joined;
      final binding = await mirror.ready(demand, bind: (value) { joined = bind(key(value)); });
      if (joined case final work?) return await work;
      mirror.check(binding, exact: true);
      return await use(binding, (scope) async {
        final header = await scope.header();
        if (header.projects.listId < 0 || header.projects.total != binding.collection?.total) {
          throw resourceProtocol('Project root read changed its frozen collection.');
        }
        final ref = await scope.lookupProject(id);
        if (ref == null) throw const StudioFailure(code: StudioFailureCode.notFound,
          message: 'The requested Project is absent from the original full directory scope.', retryable: false, correlationId: 'workspace');
        if (ref.entry < 0 || ref.revision < 0) throw resourceProtocol('Project lookup returned an invalid ref.');
        final entity = await scope.entity(ref);
        if (entity.reference != ref) throw resourceProtocol('Project entity has another ref.');
        final value = await readProjectRecord(entity.value, (field, offset) => scope.text(field, offset: offset, maxBytes: 65536));
        if (value.id != id) throw resourceProtocol('Project lookup returned another business identity.');
        mirror.check(binding, exact: true);
        if (current(binding)) {
          final window = _window(binding);
          final rows = Map<int, ReadValue<ProjectRecord, ProductEntityRef>>.of(window.rows);
          rows[ref.entry] = ReadValue.ready(current: Materialized(origin: binding.origin, reference: ref, value: value));
          mirror.source.publish(mirror.source.value.copyWith(projects: CollectionMirror.current(window: window.copyWith(rows: rows))));
        }
        mirror.check(binding, exact: true);
        return (binding: binding, reference: ref, value: value);
      });
    });
  }

  Future<void> page({int limit = 32}) {
    lifetime.admit(); directoryPageLimit(limit);
    final demand = mirror.capture();
    final prior = demand.binding?.collection == null ? null : _window(demand.binding!);
    _PageKey key(ProjectDirectoryBinding? binding, CollectionWindow<ProjectRecord>? window) => (
      generation: demand.generation, origin: binding?.origin, reference: binding?.header.reference,
      collection: binding?.collection, continuation: window?.continuation, limit: limit);
    ProjectDirectoryBinding? original;
    int? attempt;
    return _pages.run(key(demand.binding, prior), (bind) async {
      Future<void>? joined;
      CollectionWindow<ProjectRecord>? snapshot;
      final binding = await mirror.ready(demand, bind: (value) {
        snapshot = prior ?? _window(value); joined = bind(key(value, snapshot));
      });
      if (joined case final work?) { await work; return; }
      original = binding; mirror.check(binding, exact: true);
      final frozen = snapshot!;
      final dirty = frozen.entries.where((ref) => !_ready(frozen.rows[ref.entry], binding.origin, ref)).take(limit).toList();
      if (frozen.complete && dirty.isEmpty) return;
      attempt = ++_sequence;
      _active[attempt!] = binding;
      mirror.source.publish(mirror.source.value.copyWith(projects: CollectionMirror.current(window: frozen.copyWith(loading: true, error: null))));
      await use(binding, (scope) async {
        final header = await scope.header();
        if (header.projects.listId < 0 || header.projects.total != frozen.reference.total) throw resourceProtocol('Project read root changed collection.');
        final refs = <ProductEntityRef>[];
        var continuation = frozen.continuation;
        var indexComplete = continuation is EndCollectionContinuation;
        if (dirty.isNotEmpty) { refs.addAll(dirty); }
        else if (!indexComplete) {
          final offset = continuation is OffsetCollectionContinuation ? continuation.value : 0;
          final page = await scope.entries(offset: offset, limit: limit);
          final end = offset + page.items.length;
          if (page.collection != frozen.reference || page.offset != offset || page.items.length > limit ||
              page.items.any((ref) => ref.entry < 0 || ref.revision < 0) ||
              page.items.map((ref) => ref.entry).toSet().length != page.items.length ||
              page.items.any((ref) => frozen.entries.any((old) => old.entry == ref.entry)) ||
              offset != frozen.entries.length || end > frozen.reference.total ||
              page.nextOffset != (end == frozen.reference.total ? null : end) || end < frozen.reference.total && page.items.isEmpty) {
            throw resourceProtocol('A Project page changed its original ordered prefix.');
          }
          refs.addAll(page.items);
          continuation = page.nextOffset == null ? const CollectionContinuation.end() : CollectionContinuation.offset(value: page.nextOffset!);
          indexComplete = page.nextOffset == null;
        }
        final rows = Map<int, ReadValue<ProjectRecord, ProductEntityRef>>.of(frozen.rows);
        StudioFailure? failure;
        StackTrace? failureStack;
        for (final ref in refs) {
          if (_ready(rows[ref.entry], binding.origin, ref)) continue;
          try {
            final entity = await scope.entity(ref);
            if (entity.reference != ref) throw resourceProtocol('Project entity changed its original ref.');
            final value = await readProjectRecord(entity.value, (field, offset) => scope.text(field, offset: offset, maxBytes: 65536));
            final old = directoryPrevious(rows[ref.entry]);
            if (old?.origin == binding.origin && old?.reference.entry == ref.entry && old!.value.id != value.id) {
              throw resourceProtocol('An entry was reused for another Project.');
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
        final merged = Map<int, ReadValue<ProjectRecord, ProductEntityRef>>.of(latest.rows);
        for (final ref in refs) { if (!_ready(merged[ref.entry], binding.origin, ref)) merged[ref.entry] = rows[ref.entry]!; }
        final next = expands ? continuation : latest.continuation;
        StudioFailure? visibleError;
        for (final ref in entries) { if (merged[ref.entry] case FailedReadValue<ProjectRecord, ProductEntityRef>(:final error)) visibleError ??= error; }
        mirror.source.publish(mirror.source.value.copyWith(projects: CollectionMirror.current(window: CollectionWindow(
          origin: binding.origin, reference: frozen.reference, entries: entries, rows: merged, continuation: next,
          complete: (expands ? indexComplete : next is EndCollectionContinuation) && entries.length == frozen.reference.total &&
            entries.every((ref) => _ready(merged[ref.entry], binding.origin, ref)),
          loading: _loading(binding, except: attempt), error: visibleError))));
        if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
      });
    }).then<void>((_) { if (attempt != null) _active.remove(attempt); _refreshLoading(); }, onError: (Object error, StackTrace stack) {
      if (attempt != null) _active.remove(attempt);
      final binding = original;
      if (binding != null && current(binding) && attempt == _sequence) {
        final window = _window(binding);
        if (!window.complete) mirror.source.publish(mirror.source.value.copyWith(projects: CollectionMirror.current(
          window: window.copyWith(loading: _loading(binding), error: resourceFailure(error)))));
      }
      _refreshLoading();
      Error.throwWithStackTrace(resourceFailure(error), stack);
    });
  }

  Future<void> sourceStatus() {
    final demand = mirror.capture();
    _SourceKey key(ProjectDirectoryBinding? value) => (generation: demand.generation,
      origin: value?.origin, reference: value?.header.source.status);
    ProjectDirectoryBinding? original;
    return _sources.run(key(demand.binding), (bind) async {
      Future<void>? joined;
      final binding = await mirror.ready(demand, bind: (value) { joined = bind(key(value)); });
      if (joined case final work?) { await work; return; }
      original = binding; mirror.check(binding);
      if (!current(binding, source: true)) throw directorySuperseded;
      final ref = binding.header.source.status;
      final old = mirror.source.value.sourceStatus;
      if (old is ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef> && old.current.origin == binding.origin && old.current.reference == ref) return;
      mirror.source.publish(mirror.source.value.copyWith(sourceStatus: ReadValue.loading(origin: binding.origin,
        reference: ref, previous: directoryPrevious(old))));
      final value = await pins.source((resource: ProductResource.projectDirectory, origin: binding.origin, reference: ref),
        binding.header.source.brief, () => current(binding, source: true));
      if (!current(binding, source: true)) throw directorySuperseded;
      mirror.source.publish(mirror.source.value.copyWith(sourceStatus: ReadValue.ready(
        current: Materialized(origin: binding.origin, reference: ref, value: value))));
    }).then<void>((_) {}, onError: (Object error, StackTrace stack) {
      final binding = original;
      if (binding != null && current(binding, source: true)) {
        final old = mirror.source.value.sourceStatus;
        if (old is! ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef>) mirror.source.publish(mirror.source.value.copyWith(
          sourceStatus: ReadValue.failed(origin: binding.origin, reference: binding.header.source.status,
            error: resourceFailure(error), previous: directoryPrevious(old))));
      }
      Error.throwWithStackTrace(resourceFailure(error), stack);
    });
  }
}
