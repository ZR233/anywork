import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import 'agent_directory_frames.dart';
import 'directory_collection.dart';
import 'workspace_port.dart';

final class AgentDirectoryBinding {
  const AgentDirectoryBinding(
    this.origin,
    this.header,
    this.collection,
    this.generation,
  );
  final ProductReadOrigin origin;
  final AgentDirectoryHeader header;
  final ProductCollectionRef? collection;
  final int generation;
  AgentDirectoryReadTarget get target {
    final ref = header.reference;
    if (ref == null) throw directoryUnavailable;
    return AgentDirectoryReadTarget(origin: origin, reference: ref);
  }
}

typedef AgentDirectoryDemand = ({
  int generation,
  AgentDirectoryBinding? binding,
});

final class AgentDirectoryMirror {
  AgentDirectoryMirror(this.port, this.lifetime)
    : source = ResourceSource(
        const AgentDirectoryState(
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
          agents: CollectionMirror.unavailable(lastKnown: null),
        ),
        lifetime.budget,
        'agent-directory',
      ) {
    lifetime.onSeal(source.seal);
  }
  final WorkspacePort port;
  final ResourceLifetime lifetime;
  final ResourceSource<AgentDirectoryState> source;
  void Function(AgentDirectoryBinding)? adopted;
  ProductFeedOwner<AgentDirectoryFrame>? _feed;
  ProductProjectionStamp? _stamp;
  ProductCollectionRef? _collection;
  Future<void>? _restarting;
  int generation = 0;

  void start() {
    if (lifetime.sealed) return;
    try {
      capture();
    } catch (error, stack) {
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
      if (!lifetime.sealed)
        _unavailable(ResourceSyncPhase.failed, resourceFailure(error));
    }
  }

  AgentDirectoryBinding? get current {
    final state = source.value.projection;
    return state.sync.phase == ResourceSyncPhase.ready &&
            state.stamp != null &&
            state.header != null
        ? AgentDirectoryBinding(
            state.stamp!.origin,
            state.header!,
            _collection,
            generation,
          )
        : null;
  }

  AgentDirectoryDemand capture() {
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

  Future<AgentDirectoryBinding> ready(
    AgentDirectoryDemand demand, {
    void Function(AgentDirectoryBinding)? bind,
  }) async {
    lifetime.admit();
    if (demand.generation != generation) throw directorySuperseded;
    if (demand.binding case final binding?) {
      bind?.call(binding);
      return binding;
    }
    if (_restarting case final work?) await work;
    AgentDirectoryBinding? result;
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

  void check(AgentDirectoryBinding binding, {bool exact = false}) {
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
        agents: CollectionMirror.unavailable(
          lastKnown: directoryWindow(old.agents)?.copyWith(loading: false),
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
    late final ProductFeedOwner<AgentDirectoryFrame> feed;
    feed = ProductFeedOwner(
      lifetime: lifetime,
      owner: 'agent-directory-feed',
      open: port.openAgentDirectory,
      sequence: (frame) =>
          frame is AgentDirectoryData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (lifetime.sealed ||
            !identical(_feed, feed) ||
            generation != expected) {
          return frame is AgentDirectoryData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case AgentDirectoryData(:final deliverySequence, :final event):
            switch (event) {
              case AgentDirectoryBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_stamp != null ||
                    identity.resource != ProductResource.agentDirectory ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol(
                    'Agent directory baseline identity mismatch.',
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
              case AgentDirectoryChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_stamp == null ||
                    stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol(
                    'Agent directory projection revision gap.',
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
          case AgentDirectoryResyncRequired(:final identity):
            _control(feed, identity);
            _restart(feed);
          case AgentDirectoryFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case AgentDirectoryClosed(:final identity, :final reason):
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
    ProductFeedOwner<AgentDirectoryFrame> feed,
    ProductFeedIdentity identity,
  ) {
    if (identity.resource != ProductResource.agentDirectory ||
        _stamp != null && identity.ownerEpoch != _stamp!.ownerEpoch ||
        _stamp != null && identity.incarnation != _stamp!.incarnation)
      throw resourceProtocol('Agent directory control identity mismatch.');
    feed.bindIdentity(identity);
  }

  void _failed(
    ProductFeedOwner<AgentDirectoryFrame> feed,
    StudioFailure failure,
  ) {
    if (lifetime.sealed || !identical(_feed, feed)) return;
    _unavailable(ResourceSyncPhase.failed, failure);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _restart(
    ProductFeedOwner<AgentDirectoryFrame> feed, {
    bool retry = false,
  }) {
    if (lifetime.sealed || _restarting != null) return;
    final done = Completer<void>();
    _restarting = done.future;
    final next = ++generation;
    unawaited(
      Future<void>.sync(
        () => lifetime.run('agent-directory-resync', () async {
          _unavailable(ResourceSyncPhase.reconnecting, null);
          feed.requestClose();
          await feed.cleanup(retry: retry);
          lifetime.admit();
          if (!feed.released)
            throw const StudioFailure(
              code: StudioFailureCode.busy,
              message: 'The previous agent directory feed retains unresolved cleanup.',
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
    AgentDirectoryHeader header,
    ProductCollectionRef? collection,
    int? base,
    List<ProductEntityRef> upserted,
    List<int> removed, {
    required bool baseline,
  }) {
    validateDirectoryHeader(
      header.source,
      collection,
      entry: header.reference?.entry,
      revision: header.reference?.revision,
    );
    final old = source.value;
    final prior = old.projection.stamp;
    final previous = old.projection.header?.reference;
    if (stamp.revision < 0 ||
        !baseline && base != _collection?.revision ||
        prior?.origin == stamp.origin &&
            (stamp.revision < prior!.revision ||
                previous?.entry == header.reference?.entry &&
                    previous != null &&
                    header.reference != null &&
                    previous.revision > header.reference!.revision)) {
      throw resourceProtocol('Agent directory source moved backwards.');
    }
    final agents = baseline
        ? directoryBaseline(old.agents, stamp.origin, collection)
        : directoryChanged(
            old.agents,
            stamp.origin,
            base,
            collection,
            upserted,
            removed,
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
        agents: agents,
      ),
    );
    adopted?.call(
      AgentDirectoryBinding(stamp.origin, header, collection, generation),
    );
  }
}
