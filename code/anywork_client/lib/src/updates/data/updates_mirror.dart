import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/update_values.dart';
import '../domain/updates_state.dart';
import 'updates_frames.dart';
import 'updates_materialization.dart';
import 'updates_port.dart';
import 'updates_state_helpers.dart';

final class UpdatesBinding {
  const UpdatesBinding(this.origin, this.header, this.generation);
  final ProductReadOrigin origin;
  final UpdatesHeader header;
  final int generation;
  UpdatesReadTarget get target => UpdatesReadTarget(origin: origin, reference: header.reference);
}
typedef UpdatesDemand = ({int generation, UpdatesBinding? binding});

/// The sole canonical writer. Three stable typed field cells avoid full reads
/// on each byte-progress frame; installer material is never cached here.
final class UpdatesMirror {
  UpdatesMirror(this.port, this.lifetime) : source = ResourceSource(
    const UpdatesState(projection: ProductProjection(stamp: null, header: null,
      sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)), value: null),
    lifetime.budget, 'updates-state') { lifetime.onSeal(source.seal); }
  final UpdatesPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<UpdatesState> source;
  void Function(UpdatesBinding)? adopted;
  ProductFeedOwner<UpdatesFrame>? _feed;
  ProductProjectionStamp? _stamp;
  Future<void>? _restarting;
  int generation = 0;
  Materialized<UpdateSummary, UpdateSummaryReadRef>? _summary;
  Materialized<String, UpdateOperationReadRef>? _operation;
  Materialized<SourceStateError, UpdateErrorReadRef>? _error;

  UpdatesBinding? get current {
    final value = source.value.projection;
    return value.sync.phase == ResourceSyncPhase.ready && value.stamp != null && value.header != null
        ? UpdatesBinding(value.stamp!.origin, value.header!, generation) : null;
  }

  UpdateSummary? summary(UpdatesBinding binding) => _summary?.origin == binding.origin &&
      _summary?.reference == binding.header.summary ? _summary!.value : null;

  UpdatesDemand capture() {
    lifetime.admit();
    try {
      if (_feed == null) { _start(++generation); }
      else if (_feed!.closing && _restarting == null) { _restart(_feed!, retry: true); }
    } on ResourceBudgetExceeded catch (error) { throw error.failure; }
    return (generation: generation, binding: current);
  }

  Future<UpdatesBinding> ready(UpdatesDemand demand, {void Function(UpdatesBinding)? bind}) async {
    lifetime.admit();
    if (demand.generation != generation) throw updatesSuperseded;
    if (demand.binding case final binding?) { bind?.call(binding); return binding; }
    if (_restarting case final pending?) await pending;
    UpdatesBinding? result;
    await source.waitFor((value) {
      if (demand.generation != generation) throw updatesSuperseded;
      if (value.projection.sync.phase == ResourceSyncPhase.failed) throw value.projection.sync.error!;
      final binding = current;
      if (binding == null) return false;
      result = binding; bind?.call(binding); return true;
    });
    return result!;
  }

  void check(UpdatesBinding binding) {
    lifetime.admit();
    final latest = current;
    if (latest == null || latest.origin != binding.origin || generation != binding.generation) {
      throw source.value.projection.sync.error ?? updatesSuperseded;
    }
  }

  void _unavailable(ResourceSyncPhase phase, StudioFailure? error) {
    final old = source.value;
    source.publish(old.copyWith(projection: old.projection.copyWith(sync: ResourceSyncState(
      phase: phase, error: error, retryExhausted: false)), value: updatesStale(old.value, error ?? updatesSuperseded)));
  }

  void _start(int attemptGeneration) {
    lifetime.admit(); _stamp = null;
    late final ProductFeedOwner<UpdatesFrame> feed;
    feed = ProductFeedOwner<UpdatesFrame>(lifetime: lifetime, owner: 'updates-feed', open: port.openUpdates,
      sequence: (frame) => frame is UpdatesData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed || generation != attemptGeneration) {
          return frame is UpdatesData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case UpdatesData(:final deliverySequence, :final event):
            switch (event) {
              case UpdatesBaselineEvent(:final identity, :final stamp, :final value):
                if (_stamp != null || identity.resource != ProductResource.updates ||
                    identity.ownerEpoch != stamp.ownerEpoch || identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol('Updates baseline identity mismatch.');
                }
                feed.bindIdentity(identity); _adopt(stamp, value); _stamp = stamp;
              case UpdatesReplaceEvent(:final stamp, :final baseRevision, :final value):
                if (_stamp == null || stamp.origin != _stamp!.origin ||
                    baseRevision != _stamp!.revision || stamp.revision <= baseRevision) {
                  throw resourceProtocol('Updates projection revision gap.');
                }
                _adopt(stamp, value); _stamp = stamp;
            }
            return deliverySequence;
          case UpdatesResyncRequired(:final identity): _control(feed, identity); _restart(feed);
          case UpdatesFeedFailure(:final identity, :final error): _control(feed, identity); _failed(feed, error);
          case UpdatesClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) { _restart(feed); }
            else { _failed(feed, updatesUnavailable); }
        }
        return null;
      }, failed: (error) => _failed(feed, error));
    _feed = feed; _unavailable(ResourceSyncPhase.connecting, null);
  }

  void _control(ProductFeedOwner<UpdatesFrame> feed, ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.updates || (_stamp != null &&
        (identity.ownerEpoch != _stamp!.ownerEpoch || identity.incarnation != _stamp!.incarnation))) {
      throw resourceProtocol('Updates control frame belongs to another source.');
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<UpdatesFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _unavailable(ResourceSyncPhase.failed, error); feed.requestClose(); unawaited(feed.cleanup(retry: false));
  }

  void _restart(ProductFeedOwner<UpdatesFrame> feed, {bool retry = false}) {
    if (lifetime.sealed || _restarting != null) return;
    final done = Completer<void>(); _restarting = done.future;
    final next = ++generation;
    Future<void>.sync(() => lifetime.run('updates-resync', () async {
      _unavailable(ResourceSyncPhase.reconnecting, null); feed.requestClose();
      await feed.cleanup(retry: retry); lifetime.admit();
      if (!feed.released) throw const StudioFailure(code: StudioFailureCode.busy,
        message: 'The previous Updates feed retains unresolved cleanup.', retryable: true, correlationId: 'updates');
      if (identical(_feed, feed)) _start(next);
    })).then<void>((_) { _restarting = null; done.complete(); }, onError: (Object error, StackTrace stack) {
      _restarting = null;
      if (!lifetime.sealed) _unavailable(ResourceSyncPhase.failed, resourceFailure(error));
      done.completeError(resourceFailure(error), stack);
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  void _adopt(ProductProjectionStamp stamp, UpdatesHeader header) {
    _validate(header);
    final old = source.value;
    final prior = old.projection.stamp;
    if (stamp.revision < 0 || prior?.origin == stamp.origin &&
        (stamp.revision < prior!.revision || header.brief.revision < old.projection.header!.brief.revision ||
         header.reference.entry == old.projection.header!.reference.entry &&
           header.reference.revision < old.projection.header!.reference.revision ||
         header.reference == old.projection.header!.reference && header != old.projection.header)) {
      throw resourceProtocol('Updates moved its original source or business ref backwards.');
    }
    final binding = UpdatesBinding(stamp.origin, header, generation);
    final value = _compose(binding);
    source.publish(old.copyWith(projection: ProductProjection(stamp: stamp, header: header,
      sync: const ResourceSyncState(phase: ResourceSyncPhase.ready, error: null, retryExhausted: false)),
      value: value == null ? updatesRebind(old.value, stamp.origin, header.reference)
          : ReadValue.ready(current: Materialized(origin: stamp.origin, reference: header.reference, value: value))));
    adopted?.call(binding);
  }

  void _validate(UpdatesHeader header) {
    validateUpdatesBrief(header.brief);
    final hasUpdate = switch (header.brief) {
      AvailableUpdatesBrief() || DownloadingUpdatesBrief() || VerifyingUpdatesBrief() ||
      ReadyUpdatesBrief() || InstallerLaunchedUpdatesBrief() || InstallFailedUpdatesBrief() => true,
      _ => false,
    };
    final hasError = header.brief is CheckFailedUpdatesBrief || header.brief is InstallFailedUpdatesBrief;
    if (header.reference.entry < 0 || header.reference.revision < 0 || header.brief.revision < 0 ||
        header.summary != null && (header.summary!.entry < 0 || header.summary!.revision < 0) ||
        header.details != null && (header.details!.entry < 0 || header.details!.revision < 0) ||
        header.operation != null && (header.operation!.entry < 0 || header.operation!.revision < 0) ||
        header.error != null && (header.error!.entry < 0 || header.error!.revision < 0) ||
        (header.summary != null) != hasUpdate || (header.details != null) != hasUpdate ||
        (header.operation != null) != (header.brief is CheckingUpdatesBrief) || (header.error != null) != hasError) {
      throw resourceProtocol('Updates typed field refs disagree with the canonical phase.');
    }
  }

  UpdatesValue? _compose(UpdatesBinding binding) => updatesFromBrief(binding.header.brief,
    summary: summary(binding), operationId: _operation?.origin == binding.origin &&
      _operation?.reference == binding.header.operation ? _operation!.value : null,
    error: _error?.origin == binding.origin && _error?.reference == binding.header.error ? _error!.value : null);

  bool _accept(UpdatesBinding binding) => !lifetime.sealed && current?.origin == binding.origin &&
      current?.generation == binding.generation;

  void offerSummary(UpdatesBinding binding, UpdateSummary value) {
    final ref = binding.header.summary;
    if (!_accept(binding) || ref == null || current!.header.summary != ref) return;
    final prior = summary(binding);
    if (prior != null && prior != value) throw resourceProtocol('An immutable update summary changed its value.');
    _summary = Materialized(origin: binding.origin, reference: ref, value: value); _refresh();
  }

  void offerValue(UpdatesBinding binding, UpdatesValue value) {
    final expected = updatesFromBrief(binding.header.brief, summary: updatesSummary(value),
      operationId: value is CheckingUpdatesValue ? value.operationId : null, error: updatesError(value));
    if (expected != value) throw resourceProtocol('Materialized Updates value disagrees with its original header.');
    if (!_accept(binding)) return;
    final latest = current!;
    final summary = updatesSummary(value);
    final error = updatesError(value);
    // Validate every original field before changing any cell.
    if (summary != null && binding.header.summary != null && latest.header.summary == binding.header.summary) {
      final prior = this.summary(binding);
      if (prior != null && prior != summary) throw resourceProtocol('An immutable update summary changed its value.');
    }
    if (value is CheckingUpdatesValue && binding.header.operation != null && latest.header.operation == binding.header.operation) {
      if (_operation?.origin == binding.origin && _operation?.reference == binding.header.operation &&
          _operation!.value != value.operationId) throw resourceProtocol('An immutable update operation changed its value.');
    }
    if (error != null && binding.header.error != null && latest.header.error == binding.header.error) {
      if (_error?.origin == binding.origin && _error?.reference == binding.header.error &&
          _error!.value != error) throw resourceProtocol('An immutable update error changed its value.');
    }
    if (summary != null && binding.header.summary != null && latest.header.summary == binding.header.summary) {
      _summary = Materialized(origin: binding.origin, reference: binding.header.summary!, value: summary);
    }
    if (value is CheckingUpdatesValue && binding.header.operation != null && latest.header.operation == binding.header.operation) {
      _operation = Materialized(origin: binding.origin, reference: binding.header.operation!, value: value.operationId);
    }
    if (error != null && binding.header.error != null && latest.header.error == binding.header.error) {
      _error = Materialized(origin: binding.origin, reference: binding.header.error!, value: error);
    }
    _refresh();
  }

  void offerTarget(UpdatesReadTarget target, UpdatesValue value) {
    final binding = current;
    if (binding != null && binding.target == target) offerValue(binding, value);
  }

  void _refresh() {
    final binding = current;
    if (lifetime.sealed || binding == null) return;
    final value = _compose(binding);
    if (value != null) source.publish(source.value.copyWith(value: ReadValue.ready(current:
      Materialized(origin: binding.origin, reference: binding.header.reference, value: value))));
  }

  Future<void> synchronize(UpdatesReadTarget target) async {
    await ready(capture());
    await source.waitFor((state) {
      lifetime.admit();
      final binding = current;
      if (binding == null) {
        if (state.projection.sync.phase == ResourceSyncPhase.failed) throw state.projection.sync.error!;
        return false;
      }
      if (binding.origin != target.origin || binding.header.reference.entry != target.reference.entry) throw updatesSuperseded;
      return binding.header.reference.revision >= target.reference.revision;
    });
  }
}
