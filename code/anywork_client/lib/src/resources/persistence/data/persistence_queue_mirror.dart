import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_state.dart';
import 'persistence_collection.dart';
import 'persistence_frames.dart';
import 'persistence_port.dart';

final class PersistenceQueueBinding {
  const PersistenceQueueBinding(
    this.origin,
    this.header,
    this.collection,
    this.generation,
  );
  final ProductReadOrigin origin;
  final PersistenceQueueHeader header;
  final ProductCollectionRef collection;
  final int generation;
}

typedef PersistenceQueueDemand = ({
  int generation,
  PersistenceQueueBinding? binding,
});

/// The published queue has its own clock; raw command replies never write here.
final class PersistenceQueueMirror {
  PersistenceQueueMirror(this.port, this.lifetime)
    : source = ResourceSource(
        const PersistenceQueueState(
          projection: ProductProjection(
            stamp: null,
            header: null,
            sync: ResourceSyncState(
              phase: ResourceSyncPhase.idle,
              error: null,
              retryExhausted: false,
            ),
          ),
          threads: CollectionMirror.unavailable(lastKnown: null),
          lastError: null,
        ),
        lifetime.budget,
        'persistence-queue-state',
      ) {
    lifetime.onSeal(source.seal);
  }
  final PersistencePort port;
  final ResourceLifetime lifetime;
  final ResourceSource<PersistenceQueueState> source;
  final Set<PersistenceIndexRead> reads = {};
  void Function(PersistenceQueueBinding)? adopted;
  ProductFeedOwner<PersistenceQueueFrame>? _feed;
  ProductProjectionStamp? _stamp;
  ProductCollectionRef? _collection;
  Future<void>? _restarting;
  int generation = 0;

  PersistenceQueueBinding? get current {
    final value = source.value.projection;
    return value.sync.phase == ResourceSyncPhase.ready &&
            value.stamp != null &&
            value.header != null &&
            _collection != null
        ? PersistenceQueueBinding(
            value.stamp!.origin,
            value.header!,
            _collection!,
            generation,
          )
        : null;
  }

  PersistenceQueueDemand capture() {
    lifetime.admit();
    try {
      if (_feed == null) {
        _start(++generation);
      } else if (_feed!.closing && _restarting == null) {
        _restart(_feed!, retry: true);
      }
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    return (generation: generation, binding: current);
  }

  Future<PersistenceQueueBinding> ready(
    PersistenceQueueDemand demand, {
    void Function(PersistenceQueueBinding)? bind,
  }) async {
    lifetime.admit();
    if (demand.generation != generation) throw persistenceSuperseded;
    if (demand.binding case final binding?) {
      bind?.call(binding);
      return binding;
    }
    if (_restarting case final pending?) await pending;
    PersistenceQueueBinding? result;
    await source.waitFor((value) {
      if (demand.generation != generation) throw persistenceSuperseded;
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

  void check(PersistenceQueueBinding binding) {
    lifetime.admit();
    final latest = current;
    if (latest == null ||
        latest.origin != binding.origin ||
        generation != binding.generation) {
      throw source.value.projection.sync.error ?? persistenceSuperseded;
    }
  }

  void _unavailable(ResourceSyncPhase phase, StudioFailure? error) {
    final old = source.value;
    source.publish(
      old.copyWith(
        projection: old.projection.copyWith(
          sync: ResourceSyncState(
            phase: phase,
            error: error,
            retryExhausted: false,
          ),
        ),
        threads: CollectionMirror.unavailable(
          lastKnown: persistenceWindow(old.threads)?.copyWith(loading: false),
        ),
        lastError: persistenceStale(
          old.lastError,
          error ?? persistenceSuperseded,
        ),
      ),
    );
  }

  void _start(int attemptGeneration) {
    lifetime.admit();
    _stamp = null;
    late final ProductFeedOwner<PersistenceQueueFrame> feed;
    feed = ProductFeedOwner<PersistenceQueueFrame>(
      lifetime: lifetime,
      owner: 'persistence-queue-feed',
      open: port.openPersistenceQueue,
      sequence: (frame) =>
          frame is PersistenceQueueData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) ||
            lifetime.sealed ||
            generation != attemptGeneration) {
          return frame is PersistenceQueueData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case PersistenceQueueData(:final deliverySequence, :final event):
            switch (event) {
              case PersistenceQueueBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_stamp != null ||
                    identity.resource != ProductResource.persistenceQueue ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol(
                    'Persistence queue baseline identity mismatch.',
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
              case PersistenceQueueChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_stamp == null ||
                    stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol(
                    'Persistence queue projection revision gap.',
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
          case PersistenceQueueResyncRequired(:final identity):
            _control(feed, identity);
            _restart(feed);
          case PersistenceQueueFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case PersistenceQueueClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _restart(feed);
            } else {
              _failed(feed, persistenceUnavailable);
            }
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _unavailable(ResourceSyncPhase.connecting, null);
  }

  void _control(
    ProductFeedOwner<PersistenceQueueFrame> feed,
    ProductFeedIdentity identity,
  ) {
    if (identity.resource != ProductResource.persistenceQueue ||
        (_stamp != null &&
            (identity.ownerEpoch != _stamp!.ownerEpoch ||
                identity.incarnation != _stamp!.incarnation))) {
      throw resourceProtocol(
        'Persistence queue control frame belongs to another source.',
      );
    }
    feed.bindIdentity(identity);
  }

  void _failed(
    ProductFeedOwner<PersistenceQueueFrame> feed,
    StudioFailure error,
  ) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _unavailable(ResourceSyncPhase.failed, error);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _restart(
    ProductFeedOwner<PersistenceQueueFrame> feed, {
    bool retry = false,
  }) {
    if (lifetime.sealed || _restarting != null) return;
    final done = Completer<void>();
    _restarting = done.future;
    final nextGeneration = ++generation;
    final retiring = List.of(reads);
    for (final read in retiring) {
      read.invalidate();
    }
    unawaited(
      Future<void>.sync(
        () => lifetime.run('persistence-queue-resync', () async {
          _unavailable(ResourceSyncPhase.reconnecting, null);
          for (final read in retiring) {
            read.cancel?.call();
          }
          feed.requestClose();
          await feed.cleanup(retry: retry);
          lifetime.admit();
          if (!feed.released)
            throw const StudioFailure(
              code: StudioFailureCode.busy,
              message: 'The previous persistence queue feed retains unresolved cleanup.',
              retryable: true,
              correlationId: 'persistence',
            );
          if (identical(_feed, feed)) _start(nextGeneration);
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
    PersistenceQueueHeader header,
    ProductCollectionRef? collection,
    int? base,
    List<ProductEntityRef> upserted,
    List<int> removed, {
    required bool baseline,
  }) {
    final old = source.value;
    final prior = old.projection.stamp;
    if (stamp.revision < 0 ||
        header.revision < 0 ||
        header.reference.entry < 0 ||
        header.reference.revision < 0 ||
        collection == null ||
        !baseline && base != _collection?.revision ||
        prior?.origin == stamp.origin &&
            (stamp.revision < prior!.revision ||
                header.revision < old.projection.header!.revision)) {
      throw resourceProtocol(
        'Persistence queue header or collection clock mismatch.',
      );
    }
    final threads = baseline
        ? persistenceBaseline(old.threads, stamp.origin, collection)
        : persistenceChange(
            old.threads,
            stamp.origin,
            base,
            collection,
            upserted,
            removed,
          );
    if (baseline ||
        collection != _collection ||
        upserted.isNotEmpty ||
        removed.isNotEmpty) {
      for (final read in reads) {
        read.invalidate();
      }
    }
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
        threads: threads,
        lastError: persistenceRebind(
          old.lastError,
          stamp.origin,
          header.reference,
        ),
      ),
    );
    adopted?.call(
      PersistenceQueueBinding(stamp.origin, header, collection, generation),
    );
  }
}
