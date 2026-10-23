import 'dart:async';

import '../../../resources.dart';
import '../../../resources_ports.dart';
import 'account_collection.dart';
import 'account_read_fields.dart';
import 'statistics_pages.dart';

/// Shared statistics collection invariants, not a generic product port. The
/// concrete subclasses switch their own sealed frames and publish their own
/// complete State. ResourceLifetime/ProductFeedOwner own all actual resources.
abstract class StatisticsCollectionMirror<T, H, R, C, F, I> implements StatisticsPageHost<T, R, C> {
  StatisticsCollectionMirror(this.lifetime, this.resource, this.owner);
  @override
  final ResourceLifetime lifetime;
  final ProductResource resource;
  final String owner;
  ProductProjection<H> get projection;
  R reference(H header);
  void validateHeader(H header);
  void replace(ProductProjection<H> projection, CollectionMirror<T> mirror);
  Future<FeedConnection<F>> openFeed();
  int? sequence(F frame);
  Future<int?> apply(F frame, ProductFeedOwner<F> feed);
  Future<C> openRead(R reference, ProductReadOrigin origin);
  void requestReadClose(C scope);
  Future<FeedCloseReport> closeRead(C scope, bool retry);
  Future<void> waitFor(bool Function(ProductProjection<H>) predicate);
  StatisticsPages<T, R, C, I> get pages;

  ProductFeedOwner<F>? _feed;
  ProductFeedOwner<F>? _retiring;
  ProductProjectionStamp? _feedStamp;
  ProductCollectionRef? _collection;
  final Map<({ProductReadOrigin origin, R reference}), PinnedReadOwner<C>> _pins = {};
  Object? _opening;
  Future<void>? _restart;

  void _start({Object? opening}) {
    lifetime.admit(); _feedStamp = null;
    late final ProductFeedOwner<F> feed;
    feed = ProductFeedOwner(lifetime: lifetime, owner: '$owner:feed', open: openFeed, sequence: sequence, apply: (frame) async {
      if (!identical(_feed, feed) || lifetime.sealed) return sequence(frame);
      return apply(frame, feed);
    }, failed: (error) => _failed(feed, error));
    _feed = feed; _opening = opening ?? feed; _sync(ResourceSyncPhase.connecting);
  }

  void control(ProductFeedIdentity identity, ProductFeedOwner<F> feed) {
    if (identity.resource != resource || _feedStamp != null && (identity.ownerEpoch != _feedStamp!.ownerEpoch || identity.incarnation != _feedStamp!.incarnation)) throw accountDataProtocol('A statistics control frame belongs to another source.');
    feed.bindIdentity(identity);
  }
  void baseline(ProductFeedIdentity identity, ProductProjectionStamp stamp, H header, ProductCollectionRef? collection, ProductFeedOwner<F> feed) {
    if (_feedStamp != null || identity.resource != resource || identity.ownerEpoch != stamp.ownerEpoch || identity.incarnation != stamp.incarnation) throw accountDataProtocol('A statistics baseline has another source identity.');
    feed.bindIdentity(identity); _feedStamp = stamp;
    _adopt(stamp, header, collection, null, const [], const [], baseline: true);
  }
  void change(ProductProjectionStamp stamp, int baseRevision, H header, int? baseCollection, ProductCollectionRef? collection, List<ProductEntityRef> updates, List<int> removed) {
    if (_feedStamp == null || stamp.origin != _feedStamp!.origin || baseRevision != _feedStamp!.revision || stamp.revision <= baseRevision) throw accountDataProtocol('A statistics projection has a revision gap.');
    _feedStamp = stamp;
    _adopt(stamp, header, collection, baseCollection, updates, removed, baseline: false);
  }
  void failed(ProductFeedOwner<F> feed, StudioFailure failure) => _failed(feed, failure);
  void closed(ProductFeedOwner<F> feed, ProductFeedCloseReason reason) {
    if (reason == ProductFeedCloseReason.ownerReplaced) { resyncInBackground(); } else { _failed(feed, const StudioFailure(code: StudioFailureCode.unavailable, message: 'The statistics feed closed.', retryable: true, correlationId: 'statistics')); }
  }
  void _sync(ResourceSyncPhase phase, [StudioFailure? error]) => replace(projection.copyWith(sync: ResourceSyncState(phase: phase, error: error, retryExhausted: false)), mirror);
  void _failed(ProductFeedOwner<F> feed, StudioFailure failure) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _sync(ResourceSyncPhase.failed, failure); feed.requestClose(); unawaited(feed.cleanup(retry: false));
  }

  void resyncInBackground({bool retry = false}) => unawaited(_resync(retry: retry).then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  Future<void> _resync({bool retry = false}) {
    lifetime.admit();
    if (_feed == null) { _start(); return Future.value(); }
    final feed = _feed!; final prior = _restart;
    if (prior != null) {
      if (identical(_retiring, feed)) return prior;
      feed.requestClose();
      return Future<void>.sync(() => lifetime.run('$owner:deferred-resync', () async { await prior; if (!lifetime.sealed && identical(_feed, feed)) await _resync(retry: retry); }));
    }
    final done = Completer<void>(); _restart = done.future; _retiring = feed; _opening = done.future;
    _sync(ResourceSyncPhase.reconnecting); feed.requestClose();
    Future<void>.sync(() => lifetime.run('$owner:resync', () async {
      await feed.cleanup(retry: retry);
      if (!lifetime.sealed && identical(_feed, feed)) {
        if (!feed.released) throw const StudioFailure(code: StudioFailureCode.busy, message: 'The original statistics feed has unresolved cleanup.', retryable: true, correlationId: 'statistics');
        _start(opening: done.future);
      }
    })).then((_) { _restart = null; _retiring = null; done.complete(); }, onError: (Object error, StackTrace stack) {
      lifetime.lastCause = error; lifetime.lastStack = stack; _restart = null; _retiring = null;
      if (!lifetime.sealed) _sync(ResourceSyncPhase.failed, accountDataFailure(error));
      done.completeError(accountDataFailure(error), stack);
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return done.future;
  }

  void _adopt(ProductProjectionStamp stamp, H header, ProductCollectionRef? collection, int? baseCollection, List<ProductEntityRef> updates, List<int> removed, {required bool baseline}) {
    if (collection == null || collection.total < 0 || stamp.revision < 0 || stamp.incarnation < 0) throw accountDataProtocol('The statistics collection has invalid metadata.');
    validateHeader(header);
    if (!baseline && baseCollection != _collection?.revision) throw accountDataProtocol('A statistics collection has a revision gap.');
    final next = baseline ? accountCollectionBaseline(mirror, stamp.origin, collection) : accountCollectionChange(mirror, stamp.origin, collection, updates, removed);
    _collection = collection;
    final target = (origin: stamp.origin, reference: reference(header));
    for (final entry in List.of(_pins.entries)) { if (entry.key != target) { entry.value.retire(); _pins.remove(entry.key); } }
    pages.retain(stamp.origin, next);
    replace(ProductProjection(stamp: stamp, header: header, sync: const ResourceSyncState(phase: ResourceSyncPhase.ready, error: null, retryExhausted: false)), next);
  }

  @override
  StatisticsDemand<R> capture() {
    lifetime.admit();
    if (_feed == null) { _start(); } else if (_feed!.closing && _restart == null) { resyncInBackground(retry: true); }
    lifetime.admit(); final current = projection;
    if (current.sync.phase == ResourceSyncPhase.ready) return (origin: current.stamp!.origin, reference: reference(current.header as H), collection: _collection, opening: null);
    return (origin: null, reference: null, collection: null, opening: _opening);
  }
  @override
  Future<StatisticsBinding<R>> bind(StatisticsDemand<R> demand) async {
    lifetime.admit(); StatisticsBinding<R>? binding;
    await waitFor((projection) {
      if (projection.sync.phase == ResourceSyncPhase.failed) throw projection.sync.error!;
      if (projection.sync.phase != ResourceSyncPhase.ready) return false;
      binding = (origin: projection.stamp!.origin, reference: reference(projection.header as H), collection: _collection!); return true;
    });
    final original = binding!;
    if (demand.opening != null && !identical(demand.opening, _opening) || demand.reference != null && (demand.origin != original.origin || demand.reference != original.reference || demand.collection != original.collection)) throw accountDataSuperseded;
    return original;
  }
  @override
  bool current(StatisticsBinding<R> binding) => projection.sync.phase == ResourceSyncPhase.ready && projection.stamp?.origin == binding.origin && reference(projection.header as H) == binding.reference && _collection == binding.collection;
  @override
  PinnedReadOwner<C> pin(StatisticsBinding<R> binding) {
    final key = (origin: binding.origin, reference: binding.reference); final existing = _pins[key]; if (existing != null && existing.accepting) return existing;
    return _pins[key] = PinnedReadOwner(lifetime: lifetime, owner: '$owner:read', open: () => openRead(binding.reference, binding.origin), request: requestReadClose, closeNative: (scope) => closeRead(scope, false), retryNative: (scope) => closeRead(scope, true));
  }
  void markClosed() => _sync(ResourceSyncPhase.closed);
}
