import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/statistics_repository.dart';
import '../domain/statistics_state.dart';
import '../domain/statistics_values.dart';
import 'account_read_fields.dart';
import 'statistics_frames.dart';
import 'statistics_port.dart';
import 'statistics_reader.dart';

typedef _CostsDemand = ({SessionCostsReadTarget? target, Object? opening});

/// A concrete root-scoped query borrow. Separate borrows have separate native
/// observations and close rights; every scope still charges the App's one
/// shared ResourceBudget. No observer can close another borrow's connection.
final class StatisticsCostsQuery implements SessionCostsQuery {
  StatisticsCostsQuery(
    this.port,
    ResourceBudget budget,
    this.rootThreadId,
    this.onClean,
  ) : lifetime = ResourceLifetime(budget),
      source = ResourceSource(
        SessionCostsState(
          projection: const ProductProjection(
            stamp: null,
            header: null,
            sync: ResourceSyncState(
              phase: ResourceSyncPhase.idle,
              error: null,
              retryExhausted: false,
            ),
          ),
          rootThreadId: rootThreadId,
          cost: null,
        ),
        budget,
        'statistics:costs:observer',
      ) {
    lifetime.onSeal(source.seal);
  }
  final StatisticsPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<SessionCostsState> source;
  final void Function(StatisticsCostsQuery) onClean;
  @override
  final String rootThreadId;
  @override
  ReadonlyLatestValue<SessionCostsState> get state => source.readonly;
  ProductFeedOwner<SessionCostsFrame>? _feed;
  ProductFeedOwner<SessionCostsFrame>? _retiring;
  ProductProjectionStamp? _feedStamp;
  Object? _opening;
  Future<void>? _restart;
  final Map<SessionCostsReadTarget, PinnedReadOwner<SessionCostsReadConnection>>
  _pins = {};
  final Map<_CostsDemand, Future<void>> _loads = {};
  bool _sourceClosed = false;

  void _start({Object? opening}) {
    lifetime.admit();
    _feedStamp = null;
    late final ProductFeedOwner<SessionCostsFrame> feed;
    feed = ProductFeedOwner(
      lifetime: lifetime,
      owner: 'statistics:costs-feed',
      open: () => port.openSessionCosts(rootThreadId),
      sequence: (frame) =>
          frame is SessionCostsData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed)
          return frame is SessionCostsData ? frame.deliverySequence : null;
        switch (frame) {
          case SessionCostsData(:final deliverySequence, :final event):
            switch (event) {
              case SessionCostsBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.sessionCosts ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation)
                  throw accountDataProtocol(
                    'The SessionCosts baseline has another source identity.',
                  );
                feed.bindIdentity(identity);
                _feedStamp = stamp;
                _adopt(stamp, value);
              case SessionCostsReplaceEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_feedStamp == null ||
                    stamp.origin != _feedStamp!.origin ||
                    baseRevision != _feedStamp!.revision ||
                    stamp.revision <= baseRevision)
                  throw accountDataProtocol(
                    'The SessionCosts projection has a revision gap.',
                  );
                _feedStamp = stamp;
                _adopt(stamp, value);
            }
            return deliverySequence;
          case SessionCostsResyncRequired(:final identity):
            _control(identity);
            _backgroundResync();
          case SessionCostsFeedFailure(:final identity, :final error):
            _control(identity);
            _failed(feed, error);
          case SessionCostsClosed(:final identity, :final reason):
            _control(identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _backgroundResync();
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.unavailable,
                  message: 'The SessionCosts feed closed.',
                  retryable: true,
                  correlationId: 'statistics',
                ),
              );
            }
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _opening = opening ?? feed;
    _sync(ResourceSyncPhase.connecting);
  }

  void _control(ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.sessionCosts ||
        _feedStamp != null &&
            (identity.ownerEpoch != _feedStamp!.ownerEpoch ||
                identity.incarnation != _feedStamp!.incarnation))
      throw accountDataProtocol(
        'A SessionCosts control frame belongs to another source.',
      );
    _feed!.bindIdentity(identity);
  }

  void _sync(ResourceSyncPhase phase, [StudioFailure? error]) => source.publish(
    source.value.copyWith(
      projection: source.value.projection.copyWith(
        sync: ResourceSyncState(
          phase: phase,
          error: error,
          retryExhausted: false,
        ),
      ),
    ),
  );
  void _failed(ProductFeedOwner<SessionCostsFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _sync(ResourceSyncPhase.failed, error);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _backgroundResync({bool retry = false}) => unawaited(
    _resync(retry: retry)
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}),
  );
  Future<void> _resync({bool retry = false}) {
    lifetime.admit();
    if (_feed == null) {
      _start();
      return Future.value();
    }
    final feed = _feed!;
    final prior = _restart;
    if (prior != null) {
      if (identical(_retiring, feed)) return prior;
      feed.requestClose();
      return Future<void>.sync(
        () => lifetime.run('statistics:costs-deferred-resync', () async {
          await prior;
          if (!lifetime.sealed && identical(_feed, feed))
            await _resync(retry: retry);
        }),
      );
    }
    final done = Completer<void>();
    _restart = done.future;
    _retiring = feed;
    _opening = done.future;
    _sync(ResourceSyncPhase.reconnecting);
    feed.requestClose();
    unawaited(
      Future<void>.sync(
        () => lifetime.run('statistics:costs-resync', () async {
          await feed.cleanup(retry: retry);
          if (!lifetime.sealed && identical(_feed, feed)) {
            if (!feed.released)
              throw const StudioFailure(
                code: StudioFailureCode.busy,
                message: 'The SessionCosts feed has unresolved cleanup.',
                retryable: true,
                correlationId: 'statistics',
              );
            _start(opening: done.future);
          }
        }),
      ).then(
        (_) {
          _restart = null;
          _retiring = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          _restart = null;
          _retiring = null;
          if (!lifetime.sealed)
            _sync(ResourceSyncPhase.failed, accountDataFailure(error));
          done.completeError(accountDataFailure(error), stack);
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }

  void _adopt(ProductProjectionStamp stamp, SessionCostsHeader header) {
    if (stamp.revision < 0 || stamp.incarnation < 0 || header.revision < 0)
      throw accountDataProtocol(
        'The SessionCosts header has invalid revision metadata.',
      );
    final target = SessionCostsReadTarget(
      origin: stamp.origin,
      reference: header.reference,
    );
    for (final entry in List.of(_pins.entries)) {
      if (entry.key != target) {
        entry.value.retire();
        _pins.remove(entry.key);
      }
    }
    final previous = source.value.cost;
    final known = accountPrevious(previous);
    final oldTarget = switch (previous) {
      ReadyReadValue<SessionCost?, SessionCostsReadRef>(:final current) =>
        SessionCostsReadTarget(
          origin: current.origin,
          reference: current.reference,
        ),
      UnloadedReadValue<SessionCost?, SessionCostsReadRef>(
        :final origin,
        :final reference,
      ) ||
      LoadingReadValue<SessionCost?, SessionCostsReadRef>(
        :final origin,
        :final reference,
      ) ||
      FailedReadValue<SessionCost?, SessionCostsReadRef>(
        :final origin,
        :final reference,
      ) => SessionCostsReadTarget(origin: origin, reference: reference),
      null => null,
    };
    final value = oldTarget == target
        ? previous
        : known == null
        ? ReadValue<SessionCost?, SessionCostsReadRef>.unloaded(
            origin: target.origin,
            reference: target.reference,
          )
        : ReadValue<SessionCost?, SessionCostsReadRef>.failed(
            origin: target.origin,
            reference: target.reference,
            error: accountDataSuperseded,
            previous: known,
          );
    source.publish(
      source.value.copyWith(
        projection: ProductProjection(
          stamp: stamp,
          header: header,
          sync: const ResourceSyncState(
            phase: ResourceSyncPhase.ready,
            error: null,
            retryExhausted: false,
          ),
        ),
        cost: value,
      ),
    );
  }

  _CostsDemand _capture() {
    lifetime.admit();
    if (_feed == null) {
      _start();
    } else if (_feed!.closing && _restart == null) {
      _backgroundResync(retry: true);
    }
    lifetime.admit();
    final projection = source.value.projection;
    return projection.sync.phase == ResourceSyncPhase.ready
        ? (
            target: SessionCostsReadTarget(
              origin: projection.stamp!.origin,
              reference: projection.header!.reference,
            ),
            opening: null,
          )
        : (target: null, opening: _opening);
  }

  Future<({SessionCostsReadTarget target, SessionCostsHeader header})> _bind(
    _CostsDemand demand,
  ) async {
    lifetime.admit();
    ({SessionCostsReadTarget target, SessionCostsHeader header})? binding;
    await source.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed)
        throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      binding = (
        target: SessionCostsReadTarget(
          origin: value.projection.stamp!.origin,
          reference: value.projection.header!.reference,
        ),
        header: value.projection.header!,
      );
      return true;
    });
    if (demand.opening != null && !identical(demand.opening, _opening) ||
        demand.target != null && demand.target != binding!.target)
      throw accountDataSuperseded;
    return binding!;
  }

  bool _current(SessionCostsReadTarget target) =>
      source.value.projection.stamp?.origin == target.origin &&
      source.value.projection.header?.reference == target.reference;
  PinnedReadOwner<SessionCostsReadConnection> _pin(
    SessionCostsReadTarget target,
  ) {
    final previous = _pins[target];
    if (previous != null && previous.accepting) return previous;
    return _pins[target] = PinnedReadOwner(
      lifetime: lifetime,
      owner: 'statistics:costs-read',
      open: () =>
          port.openSessionCostsRead(target.reference, origin: target.origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
  }

  @override
  Future<void> load() {
    final demand = _capture();
    final known = source.value.cost;
    if (demand.target != null &&
        known is ReadyReadValue<SessionCost?, SessionCostsReadRef> &&
        known.current.origin == demand.target!.origin &&
        known.current.reference == demand.target!.reference)
      return Future.value();
    final pending = _loads[demand];
    if (pending != null) return pending;
    final done = Completer<void>();
    _loads[demand] = done.future;
    unawaited(
      lifetime
          .run('statistics:costs-load', () async {
            final binding = await _bind(demand);
            final target = binding.target;
            source.publish(
              source.value.copyWith(
                cost: ReadValue.loading(
                  origin: target.origin,
                  reference: target.reference,
                  previous: accountPrevious(source.value.cost),
                ),
              ),
            );
            try {
              final value = await _pin(target)
                  .use((scope) => readSessionCost(scope, rootThreadId));
              if (binding.header.hasCost != (value != null) ||
                  value != null &&
                      binding.header.hasUnpricedUsage != value.hasUnpricedUsage)
                throw accountDataProtocol(
                  'The SessionCosts body disagrees with its original header.',
                );
              if (lifetime.sealed) throw resourceCancelled;
              if (!_current(target)) throw accountDataSuperseded;
              source.publish(
                source.value.copyWith(
                  cost: ReadValue.ready(
                    current: Materialized(
                      origin: target.origin,
                      reference: target.reference,
                      value: value,
                    ),
                  ),
                ),
              );
            } catch (error) {
              if (!lifetime.sealed && _current(target))
                source.publish(
                  source.value.copyWith(
                    cost: ReadValue.failed(
                      origin: target.origin,
                      reference: target.reference,
                      error: accountDataFailure(error),
                      previous: accountPrevious(source.value.cost),
                    ),
                  ),
                );
              rethrow;
            }
          })
          .then(
            (_) {
              unawaited(_loads.remove(demand));
              done.complete();
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_loads.remove(demand));
              done.completeError(accountDataFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  @override
  void requestClose() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);
  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final report = await lifetime.close(deadline: deadline, retry: retry);
    if (report.complete && !_sourceClosed) {
      _sourceClosed = true;
      _sync(ResourceSyncPhase.closed);
      source.close();
      onClean(this);
    }
    return report;
  }
}
