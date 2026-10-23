import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import '../domain/directory_values.dart';
import '../domain/workspace_repository.dart';
import 'directory_collection.dart';
import 'directory_read_pins.dart';
import 'thread_directory_mirror.dart';
import 'thread_directory_pages.dart';
import 'thread_directory_reads.dart';
import 'workspace_port.dart';

/// A concrete readonly scope, not an execution Session or a second directory.
final class WorkspaceThreadDirectory {
  WorkspaceThreadDirectory({required WorkspacePort port, required ResourceBudget budget,
      required OperationRecorder operations, required ThreadDirectoryScope scope}) : lifetime = ResourceLifetime(budget) {
    mirror = ThreadDirectoryMirror(port, lifetime, scope, operations);
    final pins = DirectoryReadPins(port, lifetime);
    reads = ThreadDirectoryReads(mirror, pins, lifetime);
    pages = ThreadDirectoryPages(mirror, reads, lifetime);
    mirror.adopted = (binding) {
      pins.threadAdopted(binding);
      if (lifetime.sealed) return;
      // A visible query has no separate source-status read method. Metadata is
      // an explicit single-record demand, never an eager directory scan.
      final status = (origin: binding.origin, reference: binding.header.source.status);
      if (_sourceTarget != status) {
        _sourceTarget = status; _observe(reads.sourceStatus);
      }
      final target = (generation: binding.generation, origin: binding.origin, reference: binding.header.reference);
      if (scope is SingleThreadDirectoryScope && _metadataTarget != target) {
        _metadataTarget = target;
        _observe(() => reads.lookup(scope.threadId).then<void>((_) {}));
      }
    };
    mirror.capture();
  }
  final ResourceLifetime lifetime;
  late final ThreadDirectoryMirror mirror;
  late final ThreadDirectoryReads reads;
  late final ThreadDirectoryPages pages;
  Future<void>? _loading;
  ({ProductReadOrigin origin, ProductSourceStatusRef reference})? _sourceTarget;
  ({int generation, ProductReadOrigin origin, ThreadDirectoryReadRef? reference})? _metadataTarget;
  bool _publisherClosed = false;
  void Function()? released;

  void _observe(Future<void> Function() action) {
    Future<void>.sync(action).then<void>((_) {}, onError: (Object error, StackTrace stack) {
      lifetime.lastCause = error; lifetime.lastStack = stack;
    });
  }

  ThreadDirectoryQuery asQuery(DirectoryQuery query) {
    final scope = mirror.scope;
    if (scope is! QueryThreadDirectoryScope || scope.query != query) throw resourceProtocol('Another query cannot borrow this directory.');
    return _Query(this, query);
  }
  ThreadMetadata asMetadata(String threadId) {
    final scope = mirror.scope;
    if (scope is! SingleThreadDirectoryScope || scope.threadId != threadId) throw resourceProtocol('Another Thread cannot borrow this metadata.');
    return _Metadata(this, threadId);
  }

  Future<void> loadMore() {
    lifetime.admit();
    if (_loading case final work?) return work;
    final done = Completer<void>(); _loading = done.future;
    lifetime.run('thread-directory-load-more', () async {
      final binding = await mirror.ready(mirror.capture());
      mirror.check(binding, exact: true);
      final visible = mirror.source.value.threads;
      if (visible is CurrentCollectionMirror<WorkspaceThreadRecord> && visible.window.origin == binding.origin &&
          visible.window.reference == binding.collection && visible.window.complete) {
        if (binding.header.hasMore != true) return;
        final target = await mirror.extend(binding);
        mirror.check(binding);
        if (mirror.current?.target != target) throw directorySuperseded;
      }
      // One demand reads at most one page of this immutable window. The native
      // connection, never a Dart cursor/offset reconstruction, owns extension.
      await pages.load();
    }).then<void>((_) {
      _loading = null; done.complete();
    }, onError: (Object error, StackTrace stack) {
      _loading = null; done.completeError(resourceFailure(error), stack);
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return done.future;
  }

  void requestClose() => lifetime.seal();
  Future<void> retry() {
    lifetime.admit();
    return Future.wait([pages.load(), reads.sourceStatus()]).then<void>((_) {});
  }
  Future<void> retryMetadata(String id) {
    lifetime.admit();
    return Future.wait([reads.lookup(id).then<void>((_) {}), reads.sourceStatus()]).then<void>((_) {});
  }
  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    final report = await lifetime.close(deadline: deadline, retry: retry);
    if (report.complete && !_publisherClosed) {
      mirror.source.close(); _publisherClosed = true; released?.call();
    }
    return report;
  }
}

final class _Query implements ThreadDirectoryQuery {
  _Query(this.owner, this.query);
  final WorkspaceThreadDirectory owner;
  @override
  final DirectoryQuery query;
  @override
  ReadonlyLatestValue<ThreadDirectoryState> get state => owner.mirror.source.readonly;
  @override
  Future<void> loadMore() => owner.loadMore();
  @override
  Future<void> retry() => owner.retry();
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<CloseReport> close({DateTime? deadline}) => owner.close(deadline: deadline);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => owner.close(deadline: deadline, retry: true);
}

final class _Metadata implements ThreadMetadata {
  _Metadata(this.owner, this.threadId);
  final WorkspaceThreadDirectory owner;
  @override
  final String threadId;
  @override
  late final ReadonlyLatestValue<ThreadMetadataState> state = _MetadataView(owner, threadId);
  @override
  Future<void> retry() => owner.retryMetadata(threadId);
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<CloseReport> close({DateTime? deadline}) => owner.close(deadline: deadline);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => owner.close(deadline: deadline, retry: true);
}

/// Pure view of this single-entity mirror; no publisher, overlay or extra cache.
final class _MetadataView implements ReadonlyLatestValue<ThreadMetadataState> {
  _MetadataView(this.owner, this.id);
  final WorkspaceThreadDirectory owner;
  final String id;
  ThreadMetadataState _view(ThreadDirectoryState state) {
    ReadValue<WorkspaceThreadRecord, ProductEntityRef>? value;
    final collection = state.threads;
    final window = directoryWindow(collection);
    if (window != null) {
      for (final row in window.rows.values) {
        final previous = directoryPrevious(row);
        if (previous != null && previous.value.id != id) continue;
        value = collection is CurrentCollectionMirror<WorkspaceThreadRecord> &&
            state.projection.sync.phase == ResourceSyncPhase.ready ? row :
          directoryStale(row, state.projection.sync.error ?? directoryUnavailable);
        break;
      }
    }
    return ThreadMetadataState(projection: state.projection, sourceStatus: state.sourceStatus,
      value: value, readError: owner.reads.metadataError(state));
  }
  @override
  ThreadMetadataState get value => _view(owner.mirror.source.value);
  @override
  int get observerCount => owner.mirror.source.observerCount;
  @override
  Observation watch(void Function(ThreadMetadataState) listener, {bool fireImmediately = false}) =>
    owner.mirror.source.watch((value) => listener(_view(value)), fireImmediately: fireImmediately);
  @override
  LatestWatch<ThreadMetadataState> watchLatest(void Function(ThreadMetadataState) listener) {
    final result = owner.mirror.source.watchLatest((value) => listener(_view(value)));
    return LatestWatch(value: _view(result.value), observation: result.observation);
  }
  @override
  Future<ThreadMetadataState> waitFor(bool Function(ThreadMetadataState) predicate) async =>
    _view(await owner.mirror.source.waitFor((value) => predicate(_view(value))));
}
