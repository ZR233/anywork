import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/lsp_state.dart';
import 'lsp_collection.dart';
import 'lsp_frames.dart';
import 'lsp_port.dart';

final class LspBinding {
  const LspBinding(this.origin, this.header, this.collection, this.generation);
  final ProductReadOrigin origin;
  final LspHeader header;
  final ProductCollectionRef? collection;
  final int generation;
  LspReadTarget get target {
    final reference = header.reference;
    if (reference == null) throw lspUnavailable;
    return LspReadTarget(origin: origin, reference: reference);
  }
}

typedef LspDemand = ({int generation, LspBinding? binding});

/// The global LSP canonical reducer; all native resources belong to D0 owners.
final class LspMirror {
  LspMirror(this.port, this.lifetime)
    : source = ResourceSource(
        const LspState(
          projection: ProductProjection(
            stamp: null,
            header: null,
            sync: ResourceSyncState(
              phase: ResourceSyncPhase.idle,
              error: null,
              retryExhausted: false,
            ),
          ),
          sourceStatus: null,
          servers: CollectionMirror.unavailable(lastKnown: null),
          activeServerIds: null,
        ),
        lifetime.budget,
        'lsp-state',
      ) {
    lifetime.onSeal(source.seal);
  }
  final LspPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<LspState> source;
  final Set<LspIndexRead> reads = {};
  void Function(LspBinding)? adopted;
  ProductFeedOwner<LspFrame>? _feed;
  ProductProjectionStamp? _stamp;
  ProductCollectionRef? _collection;
  Future<void>? _restarting;
  int generation = 0;

  LspBinding? get current {
    final projection = source.value.projection;
    if (projection.sync.phase != ResourceSyncPhase.ready ||
        projection.stamp == null ||
        projection.header == null)
      return null;
    return LspBinding(
      projection.stamp!.origin,
      projection.header!,
      _collection,
      generation,
    );
  }

  LspDemand capture() {
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

  Future<LspBinding> ready(
    LspDemand demand, {
    void Function(LspBinding)? bind,
  }) async {
    lifetime.admit();
    if (demand.generation != generation) throw lspSuperseded;
    if (demand.binding case final binding?) {
      bind?.call(binding);
      return binding;
    }
    if (_restarting case final pending?) await pending;
    LspBinding? result;
    await source.waitFor((value) {
      if (demand.generation != generation) throw lspSuperseded;
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

  void check(LspBinding binding) {
    lifetime.admit();
    final latest = current;
    if (latest == null)
      throw source.value.projection.sync.error ?? lspSuperseded;
    if (binding.origin != latest.origin || binding.generation != generation)
      throw lspSuperseded;
  }

  void _unavailable(ResourceSyncPhase phase, StudioFailure? error) {
    final old = source.value;
    final failure = error ?? lspSuperseded;
    final status = old.sourceStatus;
    source.publish(
      old.copyWith(
        projection: old.projection.copyWith(
          sync: ResourceSyncState(
            phase: phase,
            error: error,
            retryExhausted: false,
          ),
        ),
        servers: CollectionMirror.unavailable(
          lastKnown: lspWindow(old.servers)?.copyWith(loading: false),
        ),
        activeServerIds: lspStale(old.activeServerIds, failure),
        sourceStatus:
            status
                is LoadingReadValue<ProductSourceStatus, ProductSourceStatusRef>
            ? ReadValue.failed(
                origin: status.origin,
                reference: status.reference,
                error: failure,
                previous: status.previous,
              )
            : status,
      ),
    );
  }

  void _start(int attemptGeneration) {
    lifetime.admit();
    _stamp = null;
    late final ProductFeedOwner<LspFrame> feed;
    feed = ProductFeedOwner<LspFrame>(
      lifetime: lifetime,
      owner: 'lsp-feed',
      open: port.openLsp,
      sequence: (frame) => frame is LspData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) ||
            lifetime.sealed ||
            generation != attemptGeneration) {
          return frame is LspData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case LspData(:final deliverySequence, :final event):
            switch (event) {
              case LspBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_stamp != null ||
                    identity.resource != ProductResource.lsp ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol('LSP baseline identity mismatch.');
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
              case LspChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_stamp == null ||
                    stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol('LSP projection revision gap.');
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
          case LspResyncRequired(:final identity):
            _control(feed, identity);
            _restart(feed);
          case LspFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case LspClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _restart(feed);
            } else {
              _failed(feed, lspUnavailable);
            }
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _unavailable(ResourceSyncPhase.connecting, null);
  }

  void _control(ProductFeedOwner<LspFrame> feed, ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.lsp ||
        (_stamp != null &&
            (identity.ownerEpoch != _stamp!.ownerEpoch ||
                identity.incarnation != _stamp!.incarnation))) {
      throw resourceProtocol('LSP control frame belongs to another source.');
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<LspFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _unavailable(ResourceSyncPhase.failed, error);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _restart(ProductFeedOwner<LspFrame> feed, {bool retry = false}) {
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
        () => lifetime.run('lsp-resync', () async {
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
              message: 'The previous LSP feed retains unresolved cleanup.',
              retryable: true,
              correlationId: 'lsp',
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
    LspHeader header,
    ProductCollectionRef? collection,
    int? base,
    List<ProductEntityRef> upserted,
    List<int> removed, {
    required bool baseline,
  }) {
    final hasValue = switch (header.source.brief) {
      ReadyObservedBrief() ||
      RefreshingObservedBrief() ||
      StaleObservedBrief() ||
      DegradedObservedBrief() => true,
      _ => false,
    };
    if (stamp.revision < 0 ||
        (header.reference != null) != hasValue ||
        (collection != null) != hasValue ||
        !baseline && base != _collection?.revision) {
      throw resourceProtocol('LSP availability or collection clock mismatch.');
    }
    final old = source.value;
    final prior = old.projection.stamp;
    if (prior?.origin == stamp.origin && stamp.revision < prior!.revision) {
      throw resourceProtocol('LSP baseline moved the same source backwards.');
    }
    final servers = baseline
        ? lspBaseline(old.servers, stamp.origin, collection)
        : lspChange(
            old.servers,
            stamp.origin,
            base,
            collection,
            upserted,
            removed,
          );
    if (!baseline &&
        (collection != _collection ||
            upserted.isNotEmpty ||
            removed.isNotEmpty)) {
      for (final read in reads) {
        read.changed(stamp.origin, base, collection, upserted, removed);
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
        servers: servers,
        sourceStatus: lspRebind(
          old.sourceStatus,
          stamp.origin,
          header.source.status,
        ),
        activeServerIds: lspRebind(
          old.activeServerIds,
          stamp.origin,
          header.reference,
        ),
      ),
    );
    adopted?.call(LspBinding(stamp.origin, header, collection, generation));
  }

  /// Executes inside the registered original action, never replaying a command.
  Future<void> synchronize(LspReadTarget target) async {
    final binding = await ready(capture());
    check(binding);
    await source.waitFor((value) {
      lifetime.admit();
      final latest = current;
      if (latest == null) {
        if (value.projection.sync.phase == ResourceSyncPhase.failed)
          throw value.projection.sync.error!;
        return false;
      }
      if (latest.origin != target.origin) throw lspSuperseded;
      final ref = latest.header.reference;
      if (ref == null) throw lspUnavailable;
      if (ref.entry != target.reference.entry) throw lspSuperseded;
      return ref.revision >= target.reference.revision;
    });
  }
}
