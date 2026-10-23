import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/skills_state.dart';
import 'skills_collection.dart';
import 'skills_frames.dart';
import 'skills_port.dart';

final class SkillsBinding {
  const SkillsBinding(this.origin, this.header, this.collection, this.generation);
  final ProductReadOrigin origin;
  final SkillsHeader header;
  final ProductCollectionRef? collection;
  final int generation;
  SkillsReadTarget get target {
    final reference = header.reference;
    if (reference == null) throw skillsUnavailable;
    return SkillsReadTarget(origin: origin, reference: reference);
  }
}

typedef SkillsDemand = ({int generation, SkillsBinding? binding});

/// One Repo-owned canonical mirror per exact project ID, not per UI query.
final class SkillsMirror {
  SkillsMirror(this.projectId, this.port, this.lifetime) : source = ResourceSource(
    SkillsState(projectId: projectId,
      projection: const ProductProjection(stamp: null, header: null,
        sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)),
      sourceStatus: null, skills: const CollectionMirror.unavailable(lastKnown: null),
      warnings: null, projectDirectory: null, configFingerprint: null),
    lifetime.budget, 'skills-state:$projectId') {
    lifetime.onSeal(source.seal);
  }
  final String projectId;
  final SkillsPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<SkillsState> source;
  final Set<SkillsIndexRead> reads = {};
  void Function(SkillsBinding)? adopted;
  ProductFeedOwner<SkillsFrame>? _feed;
  ProductProjectionStamp? _stamp;
  ProductCollectionRef? _collection;
  Future<void>? _restarting;
  int generation = 0;

  SkillsBinding? get current {
    final projection = source.value.projection;
    if (projection.sync.phase != ResourceSyncPhase.ready ||
        projection.stamp == null || projection.header == null) return null;
    return SkillsBinding(projection.stamp!.origin, projection.header!, _collection, generation);
  }

  SkillsDemand capture() {
    lifetime.admit();
    try {
      if (_feed == null) { _start(++generation); }
      else if (_feed!.closing && _restarting == null) { _restart(_feed!, retry: true); }
    } on ResourceBudgetExceeded catch (error) { throw error.failure; }
    return (generation: generation, binding: current);
  }

  Future<SkillsBinding> ready(SkillsDemand demand, {void Function(SkillsBinding)? bind}) async {
    lifetime.admit();
    if (demand.generation != generation) throw skillsSuperseded;
    if (demand.binding case final binding?) { bind?.call(binding); return binding; }
    if (_restarting case final pending?) await pending;
    SkillsBinding? result;
    await source.waitFor((value) {
      if (demand.generation != generation) throw skillsSuperseded;
      if (value.projection.sync.phase == ResourceSyncPhase.failed) throw value.projection.sync.error!;
      final binding = current;
      if (binding == null) return false;
      result = binding;
      bind?.call(binding);
      return true;
    });
    return result!;
  }

  void check(SkillsBinding binding) {
    lifetime.admit();
    final latest = current;
    if (latest == null) throw source.value.projection.sync.error ?? skillsSuperseded;
    if (binding.origin != latest.origin || binding.generation != generation) throw skillsSuperseded;
  }

  void _unavailable(ResourceSyncPhase phase, StudioFailure? error) {
    final old = source.value;
    final failure = error ?? skillsSuperseded;
    final status = old.sourceStatus;
    source.publish(old.copyWith(projection: old.projection.copyWith(sync: ResourceSyncState(
      phase: phase, error: error, retryExhausted: false)),
      skills: CollectionMirror.unavailable(lastKnown: skillsWindow(old.skills)?.copyWith(loading: false)),
      warnings: skillsStale(old.warnings, failure),
      projectDirectory: skillsStale(old.projectDirectory, failure),
      configFingerprint: skillsStale(old.configFingerprint, failure),
      sourceStatus: status is LoadingReadValue<ProductSourceStatus, ProductSourceStatusRef>
          ? ReadValue.failed(origin: status.origin, reference: status.reference,
              error: failure, previous: status.previous) : status));
  }

  void _start(int attemptGeneration) {
    lifetime.admit();
    _stamp = null;
    late final ProductFeedOwner<SkillsFrame> feed;
    feed = ProductFeedOwner<SkillsFrame>(lifetime: lifetime, owner: 'skills-feed:$projectId',
      open: () => port.openSkills(projectId),
      sequence: (frame) => frame is SkillsData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed || generation != attemptGeneration) {
          return frame is SkillsData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case SkillsData(:final deliverySequence, :final event):
            switch (event) {
              case SkillsBaselineEvent(:final identity, :final stamp, :final value):
                if (_stamp != null || identity.resource != ProductResource.skills ||
                    identity.ownerEpoch != stamp.ownerEpoch || identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol('Skills baseline identity mismatch.');
                }
                feed.bindIdentity(identity);
                _adopt(stamp, value.header, value.collection, null, const [], const [], baseline: true);
                _stamp = stamp;
              case SkillsChangeEvent(:final stamp, :final baseRevision, :final value):
                if (_stamp == null || stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision || stamp.revision <= baseRevision) {
                  throw resourceProtocol('Skills projection revision gap.');
                }
                _adopt(stamp, value.header, value.collection, value.baseCollectionRevision,
                  value.upserted, value.removedEntries, baseline: false);
                _stamp = stamp;
            }
            return deliverySequence;
          case SkillsResyncRequired(:final identity):
            _control(feed, identity);
            _restart(feed);
          case SkillsFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case SkillsClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) { _restart(feed); }
            else { _failed(feed, skillsUnavailable); }
        }
        return null;
      }, failed: (error) => _failed(feed, error));
    _feed = feed;
    _unavailable(ResourceSyncPhase.connecting, null);
  }

  void _control(ProductFeedOwner<SkillsFrame> feed, ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.skills || (_stamp != null &&
        (identity.ownerEpoch != _stamp!.ownerEpoch || identity.incarnation != _stamp!.incarnation))) {
      throw resourceProtocol('Skills control frame belongs to another source.');
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<SkillsFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _unavailable(ResourceSyncPhase.failed, error);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _restart(ProductFeedOwner<SkillsFrame> feed, {bool retry = false}) {
    if (lifetime.sealed || _restarting != null) return;
    final done = Completer<void>();
    _restarting = done.future;
    final nextGeneration = ++generation;
    final retiring = List.of(reads);
    for (final read in retiring) { read.invalidate(); }
    Future<void>.sync(() => lifetime.run('skills-resync:$projectId', () async {
      _unavailable(ResourceSyncPhase.reconnecting, null);
      for (final read in retiring) { read.cancel?.call(); }
      feed.requestClose();
      await feed.cleanup(retry: retry);
      lifetime.admit();
      if (!feed.released) throw const StudioFailure(code: StudioFailureCode.busy,
        message: 'The previous Skills feed retains unresolved cleanup.', retryable: true, correlationId: 'skills');
      if (identical(_feed, feed)) _start(nextGeneration);
    })).then<void>((_) { _restarting = null; done.complete(); }, onError: (Object error, StackTrace stack) {
      _restarting = null;
      if (!lifetime.sealed) _unavailable(ResourceSyncPhase.failed, resourceFailure(error));
      done.completeError(resourceFailure(error), stack);
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  void _adopt(ProductProjectionStamp stamp, SkillsHeader header, ProductCollectionRef? collection,
      int? base, List<ProductEntityRef> upserted, List<int> removed, {required bool baseline}) {
    final hasValue = switch (header.source.brief) {
      ReadyObservedBrief() || RefreshingObservedBrief() || StaleObservedBrief() || DegradedObservedBrief() => true,
      _ => false,
    };
    if (stamp.revision < 0 || (header.reference != null) != hasValue ||
        (collection != null) != hasValue || (header.catalogRevision != null) != hasValue ||
        (header.complete != null) != hasValue || header.catalogRevision != null && header.catalogRevision! < 0 ||
        header.reference != null && (header.reference!.entry < 0 || header.reference!.revision < 0) ||
        !baseline && base != _collection?.revision) {
      throw resourceProtocol('Skills availability or collection clock mismatch.');
    }
    final old = source.value;
    final prior = old.projection.stamp;
    if (prior?.origin == stamp.origin && stamp.revision < prior!.revision) {
      throw resourceProtocol('Skills baseline moved the same source backwards.');
    }
    final skills = baseline ? skillsBaseline(old.skills, stamp.origin, collection)
        : skillsChange(old.skills, stamp.origin, base, collection, upserted, removed);
    if (baseline || collection != _collection || upserted.isNotEmpty || removed.isNotEmpty) {
      for (final read in reads) { read.invalidate(); }
    }
    _collection = collection;
    source.publish(old.copyWith(projection: ProductProjection(stamp: stamp, header: header,
      sync: const ResourceSyncState(phase: ResourceSyncPhase.ready, error: null, retryExhausted: false)),
      skills: skills, sourceStatus: skillsRebind(old.sourceStatus, stamp.origin, header.source.status),
      warnings: skillsRebind(old.warnings, stamp.origin, header.reference),
      projectDirectory: skillsRebind(old.projectDirectory, stamp.origin, header.reference),
      configFingerprint: skillsRebind(old.configFingerprint, stamp.origin, header.reference)));
    adopted?.call(SkillsBinding(stamp.origin, header, collection, generation));
  }

  /// Called only within the original registered discovery, never by replay.
  Future<void> synchronize(SkillsReadTarget target) async {
    await ready(capture());
    await source.waitFor((value) {
      lifetime.admit();
      final latest = current;
      if (latest == null) {
        if (value.projection.sync.phase == ResourceSyncPhase.failed) throw value.projection.sync.error!;
        return false;
      }
      if (latest.origin != target.origin) throw skillsSuperseded;
      final ref = latest.header.reference;
      if (ref == null) throw skillsUnavailable;
      if (ref.entry != target.reference.entry) throw skillsSuperseded;
      return ref.revision >= target.reference.revision;
    });
  }
}
