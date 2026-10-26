import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import '../domain/directory_values.dart';
import 'directory_collection.dart';
import 'thread_directory_frames.dart';
import 'workspace_port.dart';

final class ThreadDirectoryBinding {
  const ThreadDirectoryBinding(
    this.origin,
    this.header,
    this.collection,
    this.generation,
  );
  final ProductReadOrigin origin;
  final ThreadDirectoryHeader header;
  final ProductCollectionRef? collection;
  final int generation;
  ThreadDirectoryReadTarget get target {
    final ref = header.reference;
    if (ref == null) throw directoryUnavailable;
    return ThreadDirectoryReadTarget(origin: origin, reference: ref);
  }
}

typedef ThreadDirectoryDemand = ({
  int generation,
  ThreadDirectoryBinding? binding,
});

final class ThreadDirectoryMirror {
  ThreadDirectoryMirror(this.port, this.lifetime, this.scope, this.operations)
    : source = ResourceSource(
        ThreadDirectoryState(
          projection: const ProductProjection(
            stamp: null,
            header: null,
            sync: ResourceSyncState(
              phase: ResourceSyncPhase.idle,
              error: null,
              retryExhausted: false,
            ),
          ),
          scope: scope,
          sourceStatus: null,
          threads: const CollectionMirror.unavailable(lastKnown: null),
        ),
        lifetime.budget,
        'thread-directory',
      ) {
    lifetime.onSeal(source.seal);
  }
  final WorkspacePort port;
  final ResourceLifetime lifetime;
  final ThreadDirectoryScope scope;
  final OperationRecorder operations;
  final ResourceSource<ThreadDirectoryState> source;
  void Function(ThreadDirectoryBinding)? adopted;
  void Function(ProductReadOrigin, List<int>)? removed;
  ProductFeedOwner<ThreadDirectoryFrame>? _feed;
  Future<ThreadDirectoryConnection>? _opening;
  ProductProjectionStamp? _stamp;
  ProductCollectionRef? _collection;
  Future<void>? _restarting;
  int generation = 0;

  ThreadDirectoryBinding? get current {
    final state = source.value.projection;
    return state.sync.phase == ResourceSyncPhase.ready &&
            state.stamp != null &&
            state.header != null
        ? ThreadDirectoryBinding(
            state.stamp!.origin,
            state.header!,
            _collection,
            generation,
          )
        : null;
  }

  ThreadDirectoryDemand capture() {
    lifetime.admit();
    try {
      if (_feed == null)
        _start(++generation);
      else if (_feed!.closing && _restarting == null)
        _restart(_feed!, retry: true);
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    return (generation: generation, binding: current);
  }

  Future<ThreadDirectoryBinding> ready(
    ThreadDirectoryDemand demand, {
    void Function(ThreadDirectoryBinding)? bind,
  }) async {
    lifetime.admit();
    if (demand.generation != generation) throw directorySuperseded;
    if (demand.binding case final binding?) {
      bind?.call(binding);
      return binding;
    }
    if (_restarting case final work?) await work;
    ThreadDirectoryBinding? result;
    await source.waitFor((value) {
      if (demand.generation != generation) throw directorySuperseded;
      if (value.projection.sync.phase == ResourceSyncPhase.failed)
        throw value.projection.sync.error!;
      final binding = current;
      if (binding == null) return false;
      result = binding;
      bind?.call(binding);
      return true;
    });
    return result!;
  }

  void check(ThreadDirectoryBinding binding, {bool exact = false}) {
    lifetime.admit();
    final now = current;
    if (now == null ||
        now.origin != binding.origin ||
        now.generation != binding.generation ||
        exact &&
            (now.header.reference != binding.header.reference ||
                now.collection != binding.collection))
      throw directorySuperseded;
  }

  void _unavailable(ResourceSyncPhase phase, StudioFailure? failure) {
    final old = source.value;
    source.publish(
      old.copyWith(
        projection: old.projection.copyWith(
          sync: ResourceSyncState(
            phase: phase,
            error: failure,
            retryExhausted: false,
          ),
        ),
        threads: CollectionMirror.unavailable(
          lastKnown: directoryWindow(old.threads)?.copyWith(loading: false),
        ),
        sourceStatus: directoryStale(
          old.sourceStatus,
          failure ?? directorySuperseded,
        ),
      ),
    );
  }

  void _start(int expected) {
    lifetime.admit();
    _stamp = null;
    final opening = Completer<ThreadDirectoryConnection>();
    _opening = opening.future;
    unawaited(
      opening.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    late final ProductFeedOwner<ThreadDirectoryFrame> feed;
    feed = ProductFeedOwner(
      lifetime: lifetime,
      owner: 'thread-directory-feed',
      open: () async {
        try {
          final connection = await port.openThreadDirectory(scope);
          opening.complete(connection);
          return connection;
        } catch (error, stack) {
          opening.completeError(error, stack);
          rethrow;
        }
      },
      sequence: (frame) =>
          frame is ThreadDirectoryData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (lifetime.sealed ||
            !identical(_feed, feed) ||
            generation != expected) {
          return frame is ThreadDirectoryData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case ThreadDirectoryData(:final deliverySequence, :final event):
            switch (event) {
              case ThreadDirectoryBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_stamp != null ||
                    identity.resource != ProductResource.threadDirectory ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol(
                    'Thread directory baseline identity mismatch.',
                  );
                }
                feed.bindIdentity(identity);
                _adopt(
                  stamp,
                  value.header,
                  value.collection,
                  null,
                  const [],
                  const [],
                  baseline: true,
                );
                _stamp = stamp;
              case ThreadDirectoryChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_stamp == null ||
                    stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol(
                    'Thread directory projection revision gap.',
                  );
                }
                _adopt(
                  stamp,
                  value.header,
                  value.collection,
                  value.baseCollectionRevision,
                  value.upserted,
                  value.removedEntries,
                  baseline: false,
                );
                _stamp = stamp;
            }
            return deliverySequence;
          case ThreadDirectoryResyncRequired(:final identity):
            _control(feed, identity);
            _restart(feed);
          case ThreadDirectoryFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case ThreadDirectoryClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced)
              _restart(feed);
            else
              _failed(feed, directoryUnavailable);
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _unavailable(ResourceSyncPhase.connecting, null);
  }

  void _control(
    ProductFeedOwner<ThreadDirectoryFrame> feed,
    ProductFeedIdentity identity,
  ) {
    if (identity.resource != ProductResource.threadDirectory ||
        _stamp != null && identity.ownerEpoch != _stamp!.ownerEpoch ||
        _stamp != null && identity.incarnation != _stamp!.incarnation)
      throw resourceProtocol('Thread directory control identity mismatch.');
    feed.bindIdentity(identity);
  }

  void _failed(
    ProductFeedOwner<ThreadDirectoryFrame> feed,
    StudioFailure failure,
  ) {
    if (lifetime.sealed || !identical(_feed, feed)) return;
    _unavailable(ResourceSyncPhase.failed, failure);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _restart(
    ProductFeedOwner<ThreadDirectoryFrame> feed, {
    bool retry = false,
  }) {
    if (lifetime.sealed || _restarting != null) return;
    final done = Completer<void>();
    _restarting = done.future;
    final next = ++generation;
    unawaited(
      Future<void>.sync(
        () => lifetime.run('thread-directory-resync', () async {
          _unavailable(ResourceSyncPhase.reconnecting, null);
          feed.requestClose();
          await feed.cleanup(retry: retry);
          lifetime.admit();
          if (!feed.released)
            throw const StudioFailure(
              code: StudioFailureCode.busy,
              message: 'The previous thread directory feed retains unresolved cleanup.',
              retryable: true,
              correlationId: 'workspace',
            );
          if (identical(_feed, feed)) _start(next);
        }),
      ).then<void>(
        (_) {
          _restarting = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _restarting = null;
          if (!lifetime.sealed)
            _unavailable(ResourceSyncPhase.failed, resourceFailure(error));
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  void _adopt(
    ProductProjectionStamp stamp,
    ThreadDirectoryHeader header,
    ProductCollectionRef? collection,
    int? base,
    List<ProductEntityRef> upserted,
    List<int> removedEntries, {
    required bool baseline,
  }) {
    validateDirectoryHeader(
      header.source,
      collection,
      entry: header.reference?.entry,
      revision: header.reference?.revision,
    );
    final hasValue = collection != null;
    if ((header.directoryRevision != null) != hasValue ||
        (header.hasMore != null) != hasValue ||
        header.directoryRevision != null && header.directoryRevision! < 0 ||
        header.searchProjectRevision != null &&
            header.searchProjectRevision! < 0 ||
        !hasValue &&
            (header.searchProjectRevision != null ||
                header.nextCursor != null) ||
        scope is SingleThreadDirectoryScope &&
            (header.searchProjectRevision != null ||
                header.hasMore == true ||
                header.nextCursor != null ||
                collection != null &&
                    (collection.total > 1 ||
                        baseline && collection.total != 1))) {
      throw resourceProtocol(
        'Thread directory source/window metadata is invalid.',
      );
    }
    final old = source.value;
    final prior = old.projection.stamp;
    final previous = old.projection.header;
    if (stamp.revision < 0 ||
        !baseline && base != _collection?.revision ||
        prior?.origin == stamp.origin &&
            (stamp.revision < prior!.revision ||
                previous?.reference?.entry == header.reference?.entry &&
                    previous?.reference != null &&
                    header.reference != null &&
                    previous!.reference!.revision >
                        header.reference!.revision ||
                previous?.directoryRevision != null &&
                    header.directoryRevision != null &&
                    previous!.directoryRevision! > header.directoryRevision! ||
                previous?.searchProjectRevision != null &&
                    header.searchProjectRevision != null &&
                    previous!.searchProjectRevision! >
                        header.searchProjectRevision!))
      throw resourceProtocol('Thread directory source moved backwards.');
    final threads = baseline
        ? directoryBaseline(old.threads, stamp.origin, collection)
        : directoryChanged(
            old.threads,
            stamp.origin,
            base,
            collection,
            upserted,
            removedEntries,
          );
    _collection = collection;
    source.publish(
      old.copyWith(
        projection: ProductProjection(
          stamp: stamp,
          header: header,
          sync: const ResourceSyncState(
            phase: ResourceSyncPhase.ready,
            error: null,
            retryExhausted: false,
          ),
        ),
        sourceStatus: directoryRebind(
          old.sourceStatus,
          stamp.origin,
          header.source.status,
        ),
        threads: threads,
      ),
    );
    if (header.directoryRevision case final revision?) {
      operations.observe(
        ResourceStamp(
          resourceKey: 'thread-directory',
          ownerEpoch: stamp.ownerEpoch,
          revision: revision,
        ),
      );
    }
    adopted?.call(
      ThreadDirectoryBinding(stamp.origin, header, collection, generation),
    );
    if (!baseline && removedEntries.isNotEmpty)
      removed?.call(stamp.origin, removedEntries);
  }

  Future<ThreadDirectoryReadTarget> extend(
    ThreadDirectoryBinding binding, {
    int limit = 32,
  }) {
    lifetime.admit();
    directoryPageLimit(limit);
    check(binding, exact: true);
    if (scope is! QueryThreadDirectoryScope)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Single-thread metadata cannot extend its window.',
        retryable: false,
        correlationId: 'workspace',
      );
    final collection = binding.collection;
    if (collection == null) throw directoryUnavailable;
    final originalOpening = _opening!;
    return lifetime.run('thread-directory-extend', () async {
      final connection = await originalOpening;
      check(binding, exact: true);
      final target = await connection.extendWindow(collection, limit: limit);
      if (target.origin != binding.origin ||
          target.reference.entry != binding.target.reference.entry ||
          target.reference.revision < binding.target.reference.revision)
        throw resourceProtocol('Extension returned another original query.');
      await source.waitFor((state) {
        check(binding);
        final current = this.current!;
        if (current.header.reference?.entry != target.reference.entry)
          throw directorySuperseded;
        return current.header.reference!.revision >= target.reference.revision;
      });
      return target;
    });
  }
}
