import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/mcp_state.dart';
import 'mcp_collection.dart';
import 'mcp_frames.dart';
import 'mcp_port.dart';

final class McpBinding {
  const McpBinding(this.origin, this.header, this.collection, this.generation);
  final ProductReadOrigin origin;
  final McpHeader header;
  final ProductCollectionRef? collection;
  final int generation;
  McpReadTarget get target {
    final reference = header.reference;
    if (reference == null) throw mcpUnavailable;
    return McpReadTarget(origin: origin, reference: reference);
  }
}

typedef McpDemand = ({int generation, McpBinding? binding});

/// Domain reducer only. Shared owners retain native handles, permits and joins.
final class McpMirror {
  McpMirror(this.port, this.lifetime)
    : source = ResourceSource(
        const McpState(
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
          desiredConfigFingerprint: null,
          appliedConfigFingerprint: null,
        ),
        lifetime.budget,
        'mcp-state',
      ) {
    lifetime.onSeal(source.seal);
  }
  final McpPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<McpState> source;
  final Set<McpIndexRead> reads = {};
  void Function(McpBinding)? adopted;
  ProductFeedOwner<McpFrame>? _feed;
  ProductProjectionStamp? _stamp;
  ProductCollectionRef? _collection;
  Future<void>? _restarting;
  int generation = 0;

  McpBinding? get current {
    final projection = source.value.projection;
    if (projection.sync.phase != ResourceSyncPhase.ready ||
        projection.stamp == null ||
        projection.header == null)
      return null;
    return McpBinding(
      projection.stamp!.origin,
      projection.header!,
      _collection,
      generation,
    );
  }

  McpDemand capture() {
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

  Future<McpBinding> ready(
    McpDemand demand, {
    void Function(McpBinding)? bind,
  }) async {
    lifetime.admit();
    if (demand.generation != generation) throw mcpSuperseded;
    if (demand.binding case final binding?) {
      bind?.call(binding);
      return binding;
    }
    if (_restarting case final pending?) await pending;
    McpBinding? result;
    await source.waitFor((value) {
      if (demand.generation != generation) throw mcpSuperseded;
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

  void check(McpBinding binding) {
    lifetime.admit();
    final latest = current;
    if (latest == null)
      throw source.value.projection.sync.error ?? mcpSuperseded;
    if (binding.origin != latest.origin || binding.generation != generation)
      throw mcpSuperseded;
  }

  void _unavailable(ResourceSyncPhase phase, StudioFailure? error) {
    final old = source.value;
    final failure = error ?? mcpSuperseded;
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
          lastKnown: mcpWindow(old.servers)?.copyWith(loading: false),
        ),
        sourceStatus: mcpRetire(old.sourceStatus, failure),
        activeServerIds: mcpStale(old.activeServerIds, failure),
        desiredConfigFingerprint: mcpStale(
          old.desiredConfigFingerprint,
          failure,
        ),
        appliedConfigFingerprint: mcpStale(
          old.appliedConfigFingerprint,
          failure,
        ),
      ),
    );
  }

  void _start(int attemptGeneration) {
    lifetime.admit();
    _stamp = null;
    late final ProductFeedOwner<McpFrame> feed;
    feed = ProductFeedOwner<McpFrame>(
      lifetime: lifetime,
      owner: 'mcp-feed',
      open: port.openMcp,
      sequence: (frame) => frame is McpData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) ||
            lifetime.sealed ||
            generation != attemptGeneration) {
          return frame is McpData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case McpData(:final deliverySequence, :final event):
            switch (event) {
              case McpBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_stamp != null ||
                    identity.resource != ProductResource.mcp ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol('MCP baseline identity mismatch.');
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
              case McpChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_stamp == null ||
                    stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol('MCP projection revision gap.');
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
          case McpResyncRequired(:final identity):
            _control(feed, identity);
            _restart(feed);
          case McpFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case McpClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _restart(feed);
            } else {
              _failed(feed, mcpUnavailable);
            }
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _unavailable(ResourceSyncPhase.connecting, null);
  }

  void _control(ProductFeedOwner<McpFrame> feed, ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.mcp ||
        (_stamp != null &&
            (identity.ownerEpoch != _stamp!.ownerEpoch ||
                identity.incarnation != _stamp!.incarnation))) {
      throw resourceProtocol('MCP control frame belongs to another source.');
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<McpFrame> feed, StudioFailure failure) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _unavailable(ResourceSyncPhase.failed, failure);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _restart(ProductFeedOwner<McpFrame> feed, {bool retry = false}) {
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
        () => lifetime.run('mcp-resync', () async {
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
              message: 'The previous MCP feed retains unresolved cleanup.',
              retryable: true,
              correlationId: 'mcp',
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
    McpHeader header,
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
      throw resourceProtocol('MCP availability or collection clock mismatch.');
    }
    final old = source.value;
    final prior = old.projection.stamp;
    if (prior?.origin == stamp.origin && stamp.revision < prior!.revision) {
      throw resourceProtocol('MCP baseline moved the same source backwards.');
    }
    final servers = baseline
        ? mcpServersBaseline(old.servers, stamp.origin, collection)
        : mcpServersChange(
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
        sourceStatus: mcpRebind(
          old.sourceStatus,
          stamp.origin,
          header.source.status,
        ),
        activeServerIds: mcpRebind(
          old.activeServerIds,
          stamp.origin,
          header.reference,
        ),
        desiredConfigFingerprint: mcpRebind(
          old.desiredConfigFingerprint,
          stamp.origin,
          header.reference,
        ),
        appliedConfigFingerprint: mcpRebind(
          old.appliedConfigFingerprint,
          stamp.origin,
          header.reference,
        ),
      ),
    );
    adopted?.call(McpBinding(stamp.origin, header, collection, generation));
  }

  /// Called inside the already registered reset work; never dispatches a command.
  Future<void> synchronize(McpReadTarget target) async {
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
      if (latest.origin != target.origin) throw mcpSuperseded;
      final reference = latest.header.reference;
      if (reference == null) throw mcpUnavailable;
      if (reference.entry != target.reference.entry) throw mcpSuperseded;
      return reference.revision >= target.reference.revision;
    });
  }
}
