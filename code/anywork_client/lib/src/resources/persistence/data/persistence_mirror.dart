import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_state.dart';
import 'persistence_collection.dart';
import 'persistence_frames.dart';
import 'persistence_port.dart';

final class PersistenceBinding {
  const PersistenceBinding(this.origin, this.header, this.generation);
  final ProductReadOrigin origin;
  final PersistenceHeader header;
  final int generation;
  PersistenceReadTarget get target =>
      PersistenceReadTarget(origin: origin, reference: header.reference);
}

typedef PersistenceDemand = ({int generation, PersistenceBinding? binding});

/// Scalar persistence is not an ObservedResource and has no sourceStatus feed.
final class PersistenceMirror {
  PersistenceMirror(this.port, this.lifetime)
    : source = ResourceSource(
        const PersistenceState(
          projection: ProductProjection(
            stamp: null,
            header: null,
            sync: ResourceSyncState(
              phase: ResourceSyncPhase.idle,
              error: null,
              retryExhausted: false,
            ),
          ),
          value: null,
        ),
        lifetime.budget,
        'persistence-state',
      ) {
    lifetime.onSeal(source.seal);
  }
  final PersistencePort port;
  final ResourceLifetime lifetime;
  final ResourceSource<PersistenceState> source;
  void Function(PersistenceBinding)? adopted;
  ProductFeedOwner<PersistenceFrame>? _feed;
  ProductProjectionStamp? _stamp;
  Future<void>? _restarting;
  int generation = 0;

  PersistenceBinding? get current {
    final value = source.value.projection;
    return value.sync.phase == ResourceSyncPhase.ready &&
            value.stamp != null &&
            value.header != null
        ? PersistenceBinding(value.stamp!.origin, value.header!, generation)
        : null;
  }

  PersistenceDemand capture() {
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

  Future<PersistenceBinding> ready(
    PersistenceDemand demand, {
    void Function(PersistenceBinding)? bind,
  }) async {
    lifetime.admit();
    if (demand.generation != generation) throw persistenceSuperseded;
    if (demand.binding case final binding?) {
      bind?.call(binding);
      return binding;
    }
    if (_restarting case final pending?) await pending;
    PersistenceBinding? result;
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

  void check(PersistenceBinding binding) {
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
        value: persistenceStale(old.value, error ?? persistenceSuperseded),
      ),
    );
  }

  void _start(int attemptGeneration) {
    lifetime.admit();
    _stamp = null;
    late final ProductFeedOwner<PersistenceFrame> feed;
    feed = ProductFeedOwner<PersistenceFrame>(
      lifetime: lifetime,
      owner: 'persistence-feed',
      open: port.openPersistence,
      sequence: (frame) =>
          frame is PersistenceData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) ||
            lifetime.sealed ||
            generation != attemptGeneration) {
          return frame is PersistenceData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case PersistenceData(:final deliverySequence, :final event):
            switch (event) {
              case PersistenceBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_stamp != null ||
                    identity.resource != ProductResource.persistence ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol(
                    'Persistence baseline identity mismatch.',
                  );
                }
                feed.bindIdentity(identity);
                _adopt(stamp, value);
                _stamp = stamp;
              case PersistenceReplaceEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_stamp == null ||
                    stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol(
                    'Persistence projection revision gap.',
                  );
                }
                _adopt(stamp, value);
                _stamp = stamp;
            }
            return deliverySequence;
          case PersistenceResyncRequired(:final identity):
            _control(feed, identity);
            _restart(feed);
          case PersistenceFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case PersistenceClosed(:final identity, :final reason):
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
    ProductFeedOwner<PersistenceFrame> feed,
    ProductFeedIdentity identity,
  ) {
    if (identity.resource != ProductResource.persistence ||
        (_stamp != null &&
            (identity.ownerEpoch != _stamp!.ownerEpoch ||
                identity.incarnation != _stamp!.incarnation))) {
      throw resourceProtocol(
        'Persistence control frame belongs to another source.',
      );
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<PersistenceFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _unavailable(ResourceSyncPhase.failed, error);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _restart(ProductFeedOwner<PersistenceFrame> feed, {bool retry = false}) {
    if (lifetime.sealed || _restarting != null) return;
    final done = Completer<void>();
    _restarting = done.future;
    final nextGeneration = ++generation;
    unawaited(
      Future<void>.sync(
        () => lifetime.run('persistence-resync', () async {
          _unavailable(ResourceSyncPhase.reconnecting, null);
          feed.requestClose();
          await feed.cleanup(retry: retry);
          lifetime.admit();
          if (!feed.released)
            throw const StudioFailure(
              code: StudioFailureCode.busy,
              message:
                  'The previous persistence feed retains unresolved cleanup.',
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

  void _adopt(ProductProjectionStamp stamp, PersistenceHeader header) {
    final old = source.value;
    final prior = old.projection.stamp;
    if (stamp.revision < 0 ||
        header.revision < 0 ||
        header.reference.entry < 0 ||
        header.reference.revision < 0 ||
        prior?.origin == stamp.origin &&
            (stamp.revision < prior!.revision ||
                header.revision < old.projection.header!.revision)) {
      throw resourceProtocol(
        'Persistence header moved its original source backwards.',
      );
    }
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
        value: persistenceRebind(old.value, stamp.origin, header.reference),
      ),
    );
    adopted?.call(PersistenceBinding(stamp.origin, header, generation));
  }

  Future<void> synchronize(PersistenceReadTarget target) async {
    await ready(capture());
    await source.waitFor((value) {
      lifetime.admit();
      final latest = current;
      if (latest == null) {
        if (value.projection.sync.phase == ResourceSyncPhase.failed)
          throw value.projection.sync.error!;
        return false;
      }
      if (latest.origin != target.origin ||
          latest.header.reference.entry != target.reference.entry) {
        throw persistenceSuperseded;
      }
      return latest.header.reference.revision >= target.reference.revision;
    });
  }
}
