import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import 'directory_collection.dart';
import 'project_directory_frames.dart';
import 'workspace_port.dart';

final class ProjectDirectoryBinding {
  const ProjectDirectoryBinding(this.origin, this.header, this.collection, this.generation);
  final ProductReadOrigin origin;
  final ProjectDirectoryHeader header;
  final ProductCollectionRef? collection;
  final int generation;
  ProjectDirectoryReadTarget get target {
    final ref = header.reference;
    if (ref == null) throw directoryUnavailable;
    return ProjectDirectoryReadTarget(origin: origin, reference: ref);
  }
}
typedef ProjectDirectoryDemand = ({int generation, ProjectDirectoryBinding? binding});

final class ProjectDirectoryMirror {
  ProjectDirectoryMirror(this.port, this.lifetime) : source = ResourceSource(
    const ProjectDirectoryState(projection: ProductProjection(stamp: null, header: null,
      sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)),
      sourceStatus: null, projects: CollectionMirror.unavailable(lastKnown: null)), lifetime.budget, 'project-directory') {
    lifetime.onSeal(source.seal);
  }
  final WorkspacePort port;
  final ResourceLifetime lifetime;
  final ResourceSource<ProjectDirectoryState> source;
  void Function(ProjectDirectoryBinding)? adopted;
  void Function(ProductReadOrigin, List<String>)? removed;
  ProductFeedOwner<ProjectDirectoryFrame>? _feed;
  ProductProjectionStamp? _stamp;
  ProductCollectionRef? _collection;
  Future<void>? _restarting;
  int generation = 0;

  void start() {
    if (lifetime.sealed) return;
    try { capture(); } catch (error, stack) {
      lifetime.lastCause = error; lifetime.lastStack = stack;
      if (!lifetime.sealed) _unavailable(ResourceSyncPhase.failed, resourceFailure(error));
    }
  }

  ProjectDirectoryBinding? get current {
    final state = source.value.projection;
    return state.sync.phase == ResourceSyncPhase.ready && state.stamp != null && state.header != null ?
      ProjectDirectoryBinding(state.stamp!.origin, state.header!, _collection, generation) : null;
  }

  ProjectDirectoryDemand capture() {
    lifetime.admit();
    try {
      if (_feed == null) _start(++generation);
      else if (_feed!.closing && _restarting == null) _restart(_feed!, retry: true);
    } on ResourceBudgetExceeded catch (error) { throw error.failure; }
    return (generation: generation, binding: current);
  }

  Future<ProjectDirectoryBinding> ready(ProjectDirectoryDemand demand,
      {void Function(ProjectDirectoryBinding)? bind}) async {
    lifetime.admit();
    if (demand.generation != generation) throw directorySuperseded;
    if (demand.binding case final binding?) { bind?.call(binding); return binding; }
    if (_restarting case final work?) await work;
    ProjectDirectoryBinding? result;
    await source.waitFor((value) {
      if (demand.generation != generation) throw directorySuperseded;
      if (value.projection.sync.phase == ResourceSyncPhase.failed) throw value.projection.sync.error!;
      final binding = current;
      if (binding == null) return false;
      result = binding; bind?.call(binding); return true;
    });
    return result!;
  }

  void check(ProjectDirectoryBinding binding, {bool exact = false}) {
    lifetime.admit();
    final now = current;
    if (now == null || now.origin != binding.origin || now.generation != binding.generation ||
        exact && (now.header.reference != binding.header.reference || now.collection != binding.collection)) {
      throw directorySuperseded;
    }
  }

  void _unavailable(ResourceSyncPhase phase, StudioFailure? failure) {
    final old = source.value;
    source.publish(old.copyWith(projection: old.projection.copyWith(sync: ResourceSyncState(
      phase: phase, error: failure, retryExhausted: false)),
      projects: CollectionMirror.unavailable(lastKnown: directoryWindow(old.projects)?.copyWith(loading: false)),
      sourceStatus: directoryStale(old.sourceStatus, failure ?? directorySuperseded)));
  }

  void _start(int expected) {
    lifetime.admit(); _stamp = null;
    late final ProductFeedOwner<ProjectDirectoryFrame> feed;
    feed = ProductFeedOwner(lifetime: lifetime, owner: 'project-directory-feed', open: port.openProjectDirectory,
      sequence: (frame) => frame is ProjectDirectoryData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (lifetime.sealed || !identical(_feed, feed) || generation != expected) {
          return frame is ProjectDirectoryData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case ProjectDirectoryData(:final deliverySequence, :final event):
            switch (event) {
              case ProjectDirectoryBaselineEvent(:final identity, :final stamp, :final value):
                if (_stamp != null || identity.resource != ProductResource.projectDirectory ||
                    identity.ownerEpoch != stamp.ownerEpoch || identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol('Project directory baseline identity mismatch.');
                }
                feed.bindIdentity(identity); _adopt(stamp, value.header, value.collection, null, const [], const [], baseline: true);
                _stamp = stamp;
              case ProjectDirectoryChangeEvent(:final stamp, :final baseRevision, :final value):
                if (_stamp == null || stamp.origin != _stamp!.origin || baseRevision != _stamp!.revision || stamp.revision <= baseRevision) {
                  throw resourceProtocol('Project directory projection revision gap.');
                }
                _adopt(stamp, value.header, value.collection, value.baseCollectionRevision,
                  value.upserted, value.removedEntries, baseline: false); _stamp = stamp;
            }
            return deliverySequence;
          case ProjectDirectoryResyncRequired(:final identity): _control(feed, identity); _restart(feed);
          case ProjectDirectoryFeedFailure(:final identity, :final error): _control(feed, identity); _failed(feed, error);
          case ProjectDirectoryClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) _restart(feed); else _failed(feed, directoryUnavailable);
        }
        return null;
      }, failed: (error) => _failed(feed, error));
    _feed = feed; _unavailable(ResourceSyncPhase.connecting, null);
  }

  void _control(ProductFeedOwner<ProjectDirectoryFrame> feed, ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.projectDirectory || _stamp != null && identity.ownerEpoch != _stamp!.ownerEpoch ||
        _stamp != null && identity.incarnation != _stamp!.incarnation) throw resourceProtocol('Project directory control identity mismatch.');
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<ProjectDirectoryFrame> feed, StudioFailure failure) {
    if (lifetime.sealed || !identical(_feed, feed)) return;
    _unavailable(ResourceSyncPhase.failed, failure); feed.requestClose(); unawaited(feed.cleanup(retry: false));
  }

  void _restart(ProductFeedOwner<ProjectDirectoryFrame> feed, {bool retry = false}) {
    if (lifetime.sealed || _restarting != null) return;
    final done = Completer<void>(); _restarting = done.future;
    final next = ++generation;
    Future<void>.sync(() => lifetime.run('project-directory-resync', () async {
      _unavailable(ResourceSyncPhase.reconnecting, null); feed.requestClose(); await feed.cleanup(retry: retry);
      lifetime.admit();
      if (!feed.released) throw const StudioFailure(code: StudioFailureCode.busy,
        message: 'The previous project directory feed retains unresolved cleanup.', retryable: true, correlationId: 'workspace');
      if (identical(_feed, feed)) _start(next);
    })).then<void>((_) { _restarting = null; done.complete(); }, onError: (Object error, StackTrace stack) {
      _restarting = null;
      if (!lifetime.sealed) _unavailable(ResourceSyncPhase.failed, resourceFailure(error));
      done.completeError(resourceFailure(error), stack);
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  void _adopt(ProductProjectionStamp stamp, ProjectDirectoryHeader header, ProductCollectionRef? collection,
      int? base, List<ProductEntityRef> upserted, List<int> removedEntries, {required bool baseline}) {
    validateDirectoryHeader(header.source, collection, entry: header.reference?.entry, revision: header.reference?.revision);
    final old = source.value;
    final prior = old.projection.stamp;
    final previous = old.projection.header?.reference;
    if (stamp.revision < 0 || !baseline && base != _collection?.revision || prior?.origin == stamp.origin &&
        (stamp.revision < prior!.revision || previous?.entry == header.reference?.entry && previous != null &&
          header.reference != null && previous.revision > header.reference!.revision)) {
      throw resourceProtocol('Project directory source moved backwards.');
    }
    final removedIds = <String>[];
    for (final entry in removedEntries) {
      final known = directoryPrevious(directoryWindow(old.projects)?.rows[entry]);
      if (known?.origin == stamp.origin && known?.reference.entry == entry) removedIds.add(known!.value.id);
    }
    final projects = baseline ? directoryBaseline(old.projects, stamp.origin, collection) :
      directoryChanged(old.projects, stamp.origin, base, collection, upserted, removedEntries);
    _collection = collection;
    source.publish(old.copyWith(projection: ProductProjection(stamp: stamp, header: header,
      sync: const ResourceSyncState(phase: ResourceSyncPhase.ready, error: null, retryExhausted: false)),
      sourceStatus: directoryRebind(old.sourceStatus, stamp.origin, header.source.status), projects: projects));
    adopted?.call(ProjectDirectoryBinding(stamp.origin, header, collection, generation));
    if (!baseline && removedIds.isNotEmpty) removed?.call(stamp.origin, List.unmodifiable(removedIds));
  }
}
