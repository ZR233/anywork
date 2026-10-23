import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/recovery_state.dart';
import 'recovery_frames.dart';
import 'recovery_index.dart';
import 'recovery_port.dart';

final class RecoveryBinding {
  const RecoveryBinding(this.origin, this.header, this.collection, this.generation);
  final ProductReadOrigin origin;
  final RecoveryHeader header;
  final ProductCollectionRef? collection;
  final int generation;
  RecoveryReadTarget get target {
    final ref = header.reference;
    if (ref == null) throw recoveryUnavailable;
    return RecoveryReadTarget(origin: origin, reference: ref);
  }
}

final class RecoveryDemand {
  const RecoveryDemand(this.generation, this.binding);
  final int generation;
  final RecoveryBinding? binding;
}

const recoveryUnavailable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The recovery source has no current business value.',
  retryable: true,
  correlationId: 'recovery',
);

/// Only this repository-owned mirror writes RecoveryState; replies merely lend
/// original read targets and never bypass this feed reducer.
final class RecoveryMirror {
  RecoveryMirror(this.port, this.lifetime) : source = ResourceSource(
    const RecoveryState(
      projection: ProductProjection(stamp: null, header: null,
        sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)),
      sourceStatus: null, issues: CollectionMirror.unavailable(lastKnown: null),
    ), lifetime.budget, 'recovery-state') {
    lifetime.onSeal(source.seal);
  }
  final RecoveryPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<RecoveryState> source;
  final Set<RecoveryIndexRead> reads = {};
  void Function(RecoveryBinding)? adopted;
  ProductFeedOwner<RecoveryFrame>? _feed;
  ProductProjectionStamp? _stamp;
  ProductCollectionRef? _collection;
  Future<void>? _restarting;
  int generation = 0;

  RecoveryBinding? get current {
    final value = source.value;
    if (value.projection.sync.phase != ResourceSyncPhase.ready ||
        value.projection.header == null || value.projection.stamp == null) return null;
    return RecoveryBinding(value.projection.stamp!.origin,
      value.projection.header!, _collection, generation);
  }

  RecoveryDemand capture() {
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
    return RecoveryDemand(generation, current);
  }

  Future<RecoveryBinding> ready(RecoveryDemand demand,
      {void Function(RecoveryBinding)? bind}) async {
    lifetime.admit();
    if (demand.generation != generation) throw recoverySuperseded;
    final frozen = demand.binding;
    if (frozen != null) {
      bind?.call(frozen);
      return frozen;
    }
    if (_restarting case final pending?) await pending;
    RecoveryBinding? result;
    await source.waitFor((value) {
      if (demand.generation != generation) throw recoverySuperseded;
      if (value.projection.sync.phase == ResourceSyncPhase.failed) {
        throw value.projection.sync.error!;
      }
      final binding = current;
      if (binding == null) return false;
      result = binding;
      bind?.call(binding);
      return true;
    });
    return result!;
  }

  void check(RecoveryBinding binding) {
    lifetime.admit();
    final latest = current;
    if (latest == null) throw source.value.projection.sync.error ?? recoverySuperseded;
    if (binding.generation != generation || latest.origin != binding.origin) {
      throw recoverySuperseded;
    }
  }

  ProductCollectionRef? get collection => _collection;

  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? _retireStatus(StudioFailure error) =>
      switch (source.value.sourceStatus) {
        LoadingReadValue<ProductSourceStatus, ProductSourceStatusRef>(
            :final origin, :final reference, :final previous) =>
          ReadValue.failed(origin: origin, reference: reference, error: error, previous: previous),
        final value => value,
      };

  void _sync(ResourceSyncPhase phase, [StudioFailure? error]) {
    source.publish(source.value.copyWith(
      issues: CollectionMirror.unavailable(
        lastKnown: recoveryWindow(source.value.issues)?.copyWith(loading: false)),
      sourceStatus: _retireStatus(error ?? recoverySuperseded),
      projection: source.value.projection.copyWith(
      sync: ResourceSyncState(phase: phase, error: error, retryExhausted: false))));
  }

  void _start(int attemptGeneration) {
    if (lifetime.sealed) return;
    _stamp = null;
    late final ProductFeedOwner<RecoveryFrame> feed;
    feed = ProductFeedOwner<RecoveryFrame>(
      lifetime: lifetime, owner: 'recovery-feed', open: port.openRecovery,
      sequence: (frame) => frame is RecoveryData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed || generation != attemptGeneration) {
          return frame is RecoveryData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case RecoveryData(:final deliverySequence, :final event):
            switch (event) {
              case RecoveryBaselineEvent(:final identity, :final stamp, :final value):
                if (_stamp != null || identity.resource != ProductResource.recovery ||
                    identity.ownerEpoch != stamp.ownerEpoch || identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol('Recovery baseline identity mismatch.');
                }
                feed.bindIdentity(identity);
                _adopt(stamp, value.header, value.collection, null, const [], const [], baseline: true);
                _stamp = stamp;
              case RecoveryChangeEvent(:final stamp, :final baseRevision, :final value):
                if (_stamp == null || stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision || stamp.revision <= baseRevision) {
                  throw resourceProtocol('Recovery projection revision gap.');
                }
                _adopt(stamp, value.header, value.collection, value.baseCollectionRevision,
                  value.upserted, value.removedEntries, baseline: false);
                _stamp = stamp;
            }
            return deliverySequence;
          case RecoveryResyncRequired(:final identity):
            _control(feed, identity);
            _restart(feed);
          case RecoveryFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case RecoveryClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _restart(feed);
            } else {
              _failed(feed, recoveryUnavailable);
            }
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _sync(ResourceSyncPhase.connecting);
  }

  void _control(ProductFeedOwner<RecoveryFrame> feed, ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.recovery ||
        (_stamp != null && (identity.ownerEpoch != _stamp!.ownerEpoch ||
            identity.incarnation != _stamp!.incarnation))) {
      throw resourceProtocol('Recovery control frame belongs to another origin.');
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<RecoveryFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    final previous = recoveryWindow(source.value.issues);
    source.publish(source.value.copyWith(
      issues: CollectionMirror.unavailable(lastKnown: previous?.copyWith(loading: false)),
      sourceStatus: _retireStatus(error),
      projection: source.value.projection.copyWith(sync: ResourceSyncState(
        phase: ResourceSyncPhase.failed, error: error, retryExhausted: false)),
    ));
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _restart(ProductFeedOwner<RecoveryFrame> feed, {bool retry = false}) {
    if (lifetime.sealed || _restarting != null) return;
    final done = Completer<void>();
    _restarting = done.future;
    final nextGeneration = ++generation;
    final retiringReads = List.of(reads);
    for (final read in retiringReads) { read.invalid = true; read.changes.clear(); }
    Future<void>.sync(() => lifetime.run('recovery-resync', () async {
    _sync(ResourceSyncPhase.reconnecting);
    for (final read in retiringReads) { read.cancel?.call(); }
    feed.requestClose();
      await feed.cleanup(retry: retry);
      if (lifetime.sealed) throw resourceCancelled;
      if (!feed.released) throw const StudioFailure(
        code: StudioFailureCode.busy,
        message: 'The previous recovery feed retains unresolved cleanup.',
        retryable: true, correlationId: 'recovery',
      );
      if (identical(_feed, feed)) _start(nextGeneration);
    })).then<void>((_) {
      _restarting = null;
      done.complete();
    }, onError: (Object error, StackTrace stack) {
      _restarting = null;
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
      if (!lifetime.sealed) _sync(ResourceSyncPhase.failed, resourceFailure(error));
      done.completeError(resourceFailure(error), stack);
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  void _adopt(ProductProjectionStamp stamp, RecoveryHeader header,
      ProductCollectionRef? collection, int? base,
      List<ProductEntityRef> upserted, List<int> removed, {required bool baseline}) {
    final hasValue = switch (header.source.brief) {
      ReadyObservedBrief() || RefreshingObservedBrief() || StaleObservedBrief() ||
      DegradedObservedBrief() => true,
      _ => false,
    };
    if (stamp.revision < 0 || (header.reference != null) != hasValue ||
        (collection != null) != hasValue ||
        (!baseline && base != _collection?.revision)) {
      throw resourceProtocol('Recovery header availability or collection clock mismatch.');
    }
    final old = source.value;
    final prior = old.projection.stamp;
    if (prior != null && prior.origin == stamp.origin && stamp.revision < prior.revision) {
      throw resourceProtocol('Recovery baseline moved the projection backwards.');
    }
    if (!baseline && (collection != _collection || upserted.isNotEmpty || removed.isNotEmpty)) {
      for (final read in reads) {
        read.changed(stamp.origin, base, collection, upserted, removed);
      }
    }
    final mirror = baseline ? recoveryBaseline(old.issues, stamp.origin, collection)
        : recoveryChange(old.issues, stamp.origin, base, collection, upserted, removed);
    _collection = collection;
    source.publish(old.copyWith(
      projection: ProductProjection(stamp: stamp, header: header,
        sync: const ResourceSyncState(phase: ResourceSyncPhase.ready, error: null, retryExhausted: false)),
      issues: mirror,
      sourceStatus: recoveryRebind(old.sourceStatus, stamp.origin, header.source.status),
    ));
    adopted?.call(RecoveryBinding(stamp.origin, header, collection, generation));
  }
}
