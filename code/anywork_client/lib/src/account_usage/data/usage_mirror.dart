import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/usage_state.dart';
import '../domain/usage_values.dart';
import 'account_collection.dart';
import 'account_read_fields.dart';
import 'account_usage_port.dart';
import 'usage_frames.dart';
import 'usage_reader.dart';

typedef UsageDemand = ({
  ProductReadOrigin? origin,
  AccountUsageReadRef? reference,
  ProductCollectionRef? collection,
  Object? opening,
});
typedef UsageBinding = ({
  AccountUsageReadTarget target,
  ProductCollectionRef collection,
});

/// Canonical usage material only. It never substitutes record revision or a
/// configuration fingerprint for the account's true usage query identity.
final class UsageMirror {
  UsageMirror(this.port, this.lifetime)
    : source = ResourceSource(
        AccountUsageState(
          projection: const ProductProjection(
            stamp: null,
            header: null,
            sync: ResourceSyncState(
              phase: ResourceSyncPhase.idle,
              error: null,
              retryExhausted: false,
            ),
          ),
          sourceStatus: null,
          usages: const CollectionMirror.unavailable(lastKnown: null),
          configFingerprint: null,
        ),
        lifetime.budget,
        'account-usage:observer',
      ) {
    lifetime.onSeal(source.seal);
  }
  final AccountUsagePort port;
  final ResourceLifetime lifetime;
  final ResourceSource<AccountUsageState> source;
  ProductFeedOwner<AccountUsageFrame>? _feed;
  ProductFeedOwner<AccountUsageFrame>? _retiring;
  ProductProjectionStamp? _feedStamp;
  ProductCollectionRef? _collection;
  Object? _opening;
  Future<void>? _restart;
  final Map<AccountUsageReadTarget, PinnedReadOwner<AccountUsageReadConnection>>
  _pins = {};
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    PinnedReadOwner<ProductSourceStatusReadConnection>
  >
  _statusPins = {};
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    Future<void>
  >
  _statusLoads = {};
  final Map<({String id, UsageDemand demand}), Future<AccountUsageRecord>>
  _records = {};
  final Map<
    ({UsageDemand demand, CollectionContinuation? continuation, int limit}),
    Future<void>
  >
  _pages = {};
  int _pageGeneration = 0;

  UsageDemand capture() {
    lifetime.admit();
    if (_feed == null) {
      _start();
    } else if (_feed!.closing && _restart == null) {
      _backgroundResync(retry: true);
    }
    lifetime.admit();
    final projection = source.value.projection;
    if (projection.sync.phase == ResourceSyncPhase.ready &&
        projection.header?.reference != null)
      return (
        origin: projection.stamp!.origin,
        reference: projection.header!.reference,
        collection: _collection,
        opening: null,
      );
    return (origin: null, reference: null, collection: null, opening: _opening);
  }

  void _start({Object? opening}) {
    lifetime.admit();
    _feedStamp = null;
    late final ProductFeedOwner<AccountUsageFrame> feed;
    feed = ProductFeedOwner(
      lifetime: lifetime,
      owner: 'account-usage:feed',
      open: port.openAccountUsage,
      sequence: (frame) =>
          frame is AccountUsageDataFrame ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed)
          return frame is AccountUsageDataFrame ? frame.deliverySequence : null;
        switch (frame) {
          case AccountUsageDataFrame(:final deliverySequence, :final event):
            switch (event) {
              case AccountUsageBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.accountUsage ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation)
                  throw accountDataProtocol(
                    'The usage baseline has another source identity.',
                  );
                feed.bindIdentity(identity);
                _feedStamp = stamp;
                _adopt(
                  stamp,
                  value.header,
                  value.collection,
                  null,
                  const [],
                  const [],
                  baseline: true,
                );
              case AccountUsageChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_feedStamp == null ||
                    stamp.origin != _feedStamp!.origin ||
                    baseRevision != _feedStamp!.revision ||
                    stamp.revision <= baseRevision)
                  throw accountDataProtocol(
                    'The usage projection has a revision gap.',
                  );
                _feedStamp = stamp;
                _adopt(
                  stamp,
                  value.header,
                  value.collection,
                  value.baseCollectionRevision,
                  value.upserted,
                  value.removedEntries,
                  baseline: false,
                );
            }
            return deliverySequence;
          case AccountUsageResyncRequired(:final identity):
            _control(identity);
            _backgroundResync();
          case AccountUsageFeedFailure(:final identity, :final error):
            _control(identity);
            _failed(feed, error);
          case AccountUsageClosed(:final identity, :final reason):
            _control(identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _backgroundResync();
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.unavailable,
                  message: 'The account usage feed closed.',
                  retryable: true,
                  correlationId: 'account-usage',
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
    if (identity.resource != ProductResource.accountUsage ||
        _feedStamp != null &&
            (identity.ownerEpoch != _feedStamp!.ownerEpoch ||
                identity.incarnation != _feedStamp!.incarnation))
      throw accountDataProtocol(
        'A usage control frame belongs to another source.',
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
  void _failed(ProductFeedOwner<AccountUsageFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _sync(ResourceSyncPhase.failed, error);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _backgroundResync({bool retry = false}) => unawaited(
    resync(retry: retry)
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}),
  );
  Future<void> resync({bool retry = false}) {
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
        () => lifetime.run('account-usage:deferred-resync', () async {
          await prior;
          if (!lifetime.sealed && identical(_feed, feed))
            await resync(retry: retry);
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
        () => lifetime.run('account-usage:resync', () async {
          await feed.cleanup(retry: retry);
          if (!lifetime.sealed && identical(_feed, feed)) {
            if (!feed.released)
              throw const StudioFailure(
                code: StudioFailureCode.busy,
                message: 'The original usage feed has unresolved cleanup.',
                retryable: true,
                correlationId: 'account-usage',
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

  void _adopt(
    ProductProjectionStamp stamp,
    AccountUsageHeader header,
    ProductCollectionRef? collection,
    int? base,
    List<ProductEntityRef> updates,
    List<int> removed, {
    required bool baseline,
  }) {
    final available =
        header.source.brief is ReadyObservedBrief ||
        header.source.brief is RefreshingObservedBrief ||
        header.source.brief is StaleObservedBrief ||
        header.source.brief is DegradedObservedBrief;
    if (stamp.revision < 0 ||
        stamp.incarnation < 0 ||
        available != (header.reference != null) ||
        available != (collection != null))
      throw accountDataProtocol(
        'The usage header has inconsistent value availability.',
      );
    if (!baseline && base != _collection?.revision)
      throw accountDataProtocol('The usage collection has a revision gap.');
    final mirror = baseline
        ? accountCollectionBaseline(
            source.value.usages,
            stamp.origin,
            collection,
          )
        : accountCollectionChange(
            source.value.usages,
            stamp.origin,
            collection,
            updates,
            removed,
          );
    _collection = collection;
    final target = header.reference == null
        ? null
        : AccountUsageReadTarget(
            origin: stamp.origin,
            reference: header.reference!,
          );
    for (final entry in List.of(_pins.entries)) {
      if (entry.key != target) {
        entry.value.retire();
        _pins.remove(entry.key);
      }
    }
    for (final entry in List.of(_statusPins.entries)) {
      if (entry.key.origin != stamp.origin ||
          entry.key.reference != header.source.status) {
        entry.value.retire();
        _statusPins.remove(entry.key);
      }
    }
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
        usages: mirror,
        configFingerprint: _field(
          source.value.configFingerprint,
          stamp.origin,
          header.reference,
        ),
        sourceStatus: _field(
          source.value.sourceStatus,
          stamp.origin,
          header.source.status,
        ),
      ),
    );
  }

  ReadValue<T, R>? _field<T, R>(
    ReadValue<T, R>? previous,
    ProductReadOrigin origin,
    R? reference,
  ) {
    final known = accountPrevious(previous);
    if (reference == null)
      return known == null
          ? null
          : ReadValue.failed(
              origin: known.origin,
              reference: known.reference,
              error: const StudioFailure(
                code: StudioFailureCode.unavailable,
                message: 'The usage source has no current value.',
                retryable: true,
                correlationId: 'account-usage',
              ),
              previous: known,
            );
    final old = switch (previous) {
      ReadyReadValue<T, R>(:final current) => (
        origin: current.origin,
        reference: current.reference,
      ),
      UnloadedReadValue<T, R>(:final origin, :final reference) ||
      LoadingReadValue<T, R>(:final origin, :final reference) ||
      FailedReadValue<T, R>(
        :final origin,
        :final reference,
      ) => (origin: origin, reference: reference),
      null => null,
    };
    if (old?.origin == origin && old?.reference == reference) return previous;
    return known == null
        ? ReadValue.unloaded(origin: origin, reference: reference)
        : ReadValue.failed(
            origin: origin,
            reference: reference,
            error: accountDataSuperseded,
            previous: known,
          );
  }

  Future<UsageBinding> bind(UsageDemand demand) async {
    lifetime.admit();
    UsageBinding? binding;
    await source.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed)
        throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      final reference = value.projection.header!.reference;
      final collection = _collection;
      if (reference == null || collection == null)
        throw const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Account usage has no current business value.',
          retryable: true,
          correlationId: 'account-usage',
        );
      binding = (
        target: AccountUsageReadTarget(
          origin: value.projection.stamp!.origin,
          reference: reference,
        ),
        collection: collection,
      );
      return true;
    });
    if (demand.opening != null && !identical(demand.opening, _opening) ||
        demand.reference != null &&
            (demand.origin != binding!.target.origin ||
                demand.reference != binding!.target.reference ||
                demand.collection != binding!.collection))
      throw accountDataSuperseded;
    return binding!;
  }

  bool current(AccountUsageReadTarget target) =>
      source.value.projection.stamp?.origin == target.origin &&
      source.value.projection.header?.reference == target.reference;
  PinnedReadOwner<AccountUsageReadConnection> pin(
    AccountUsageReadTarget target,
  ) {
    final previous = _pins[target];
    if (previous != null && previous.accepting) return previous;
    return _pins[target] = PinnedReadOwner(
      lifetime: lifetime,
      owner: 'account-usage:read',
      open: () =>
          port.openAccountUsageRead(target.reference, origin: target.origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
  }

  CollectionWindow<AccountUsageRecord> _window(
    ProductReadOrigin origin,
    ProductCollectionRef collection,
  ) {
    if (source.value.projection.stamp?.origin != origin ||
        _collection != collection)
      throw accountDataSuperseded;
    final mirror = source.value.usages;
    return mirror is CurrentCollectionMirror<AccountUsageRecord> &&
            mirror.window.origin == origin &&
            mirror.window.reference == collection
        ? mirror.window
        : emptyAccountWindow(origin, collection);
  }

  Future<void> loadStatus() {
    final demand = capture();
    final snapshot = source.value;
    if (snapshot.projection.sync.phase == ResourceSyncPhase.ready)
      return _status(
        snapshot.projection.stamp!.origin,
        snapshot.projection.header!.source,
      );
    return lifetime.run('account-usage:load-source-status', () async {
      AccountUsageState? snapshot;
      await source.waitFor((value) {
        if (value.projection.sync.phase == ResourceSyncPhase.failed)
          throw value.projection.sync.error!;
        if (value.projection.sync.phase != ResourceSyncPhase.ready)
          return false;
        snapshot = value;
        return true;
      });
      if (demand.opening != null && !identical(demand.opening, _opening))
        throw accountDataSuperseded;
      await _status(
        snapshot!.projection.stamp!.origin,
        snapshot!.projection.header!.source,
      );
    });
  }

  Future<void> _status(ProductReadOrigin origin, ObservedHeader header) {
    lifetime.admit();
    final target = (origin: origin, reference: header.status);
    final known = source.value.sourceStatus;
    if (known is ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef> &&
        known.current.origin == origin &&
        known.current.reference == header.status) {
      if (accountStatusBrief(known.current.value) != header.brief)
        throw accountDataProtocol(
          'The usage source brief changed without a new status reference.',
        );
      return Future.value();
    }
    final pending = _statusLoads[target];
    if (pending != null) return pending;
    final done = Completer<void>();
    _statusLoads[target] = done.future;
    bool current() =>
        source.value.projection.stamp?.origin == origin &&
        source.value.projection.header?.source.status == header.status;
    unawaited(
      lifetime
          .run('account-usage:source-status', () async {
            if (!current()) throw accountDataSuperseded;
            source.publish(
              source.value.copyWith(
                sourceStatus: ReadValue.loading(
                  origin: origin,
                  reference: header.status,
                  previous: accountPrevious(source.value.sourceStatus),
                ),
              ),
            );
            try {
              final pin = _statusPins.putIfAbsent(
                target,
                () => PinnedReadOwner(
                  lifetime: lifetime,
                  owner: 'account-usage:source-status-read',
                  open: () =>
                      port.openSourceStatus(header.status, origin: origin),
                  request: (scope) => scope.requestClose(),
                  closeNative: (scope) => scope.close(),
                  retryNative: (scope) => scope.retryClose(),
                ),
              );
              final value = await pin.use(readAccountSourceStatus);
              if (accountStatusBrief(value) != header.brief)
                throw accountDataProtocol(
                  'The usage source metadata disagrees with its original brief.',
                );
              if (lifetime.sealed) throw resourceCancelled;
              if (!current()) throw accountDataSuperseded;
              source.publish(
                source.value.copyWith(
                  sourceStatus: ReadValue.ready(
                    current: Materialized(
                      origin: origin,
                      reference: header.status,
                      value: value,
                    ),
                  ),
                ),
              );
            } catch (error) {
              if (!lifetime.sealed && current())
                source.publish(
                  source.value.copyWith(
                    sourceStatus: ReadValue.failed(
                      origin: origin,
                      reference: header.status,
                      error: accountDataFailure(error),
                      previous: accountPrevious(source.value.sourceStatus),
                    ),
                  ),
                );
              rethrow;
            }
          })
          .then(
            (_) {
              unawaited(_statusLoads.remove(target));
              done.complete();
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_statusLoads.remove(target));
              done.completeError(accountDataFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  Future<AccountUsageRecord> record(String id) {
    final demand = capture();
    final key = (id: id, demand: demand);
    final mirror = source.value.usages;
    if (demand.origin != null &&
        mirror is CurrentCollectionMirror<AccountUsageRecord> &&
        mirror.window.origin == demand.origin &&
        mirror.window.reference == demand.collection) {
      for (final row in mirror.window.rows.values) {
        if (row is ReadyReadValue<AccountUsageRecord, ProductEntityRef> &&
            row.current.value.accountId == id)
          return Future.value(row.current.value);
      }
    }
    final pending = _records[key];
    if (pending != null) return pending;
    final done = Completer<AccountUsageRecord>();
    _records[key] = done.future;
    unawaited(
      lifetime
          .run('account-usage:record', () async {
            final binding = await bind(demand);
            return readTarget(
              binding.target,
              id,
              collection: binding.collection,
            );
          })
          .then(
            (value) {
              unawaited(_records.remove(key));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_records.remove(key));
              done.completeError(accountDataFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  Future<AccountUsageRecord> readTarget(
    AccountUsageReadTarget target,
    String id, {
    ProductCollectionRef? collection,
    bool Function()? validate,
  }) => pin(target).use((scope) async {
    final reference = await scope.lookupAccount(id);
    if (reference == null)
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The requested usage record does not exist in this source.',
        retryable: false,
        correlationId: 'account-usage',
      );
    final entity = await scope.entity(reference);
    if (entity.reference != reference)
      throw accountDataProtocol('A usage lookup returned another reference.');
    final value = await UsageReader(scope).record(entity.value);
    if (value.accountId != id)
      throw accountDataProtocol('A usage lookup returned another account.');
    if (lifetime.sealed) throw resourceCancelled;
    if (!current(target) ||
        collection != null && collection != _collection ||
        validate != null && !validate())
      throw accountDataSuperseded;
    final window = _window(target.origin, _collection!);
    source.publish(
      source.value.copyWith(
        usages: CollectionMirror.current(
          window: window.copyWith(
            rows: {
              ...window.rows,
              reference.entry: ReadValue.ready(
                current: Materialized(
                  origin: target.origin,
                  reference: reference,
                  value: value,
                ),
              ),
            },
          ),
        ),
      ),
    );
    return value;
  });

  Future<AccountUsageRecord> synchronize(
    AccountUsageReadTarget target,
    String id, {
    required bool Function() validate,
  }) {
    lifetime.admit();
    capture();
    return lifetime.run('account-usage:check-target', () async {
      // Validate the returned native version itself before waiting for a feed
      // watermark; a foreign/invalid target must fail, not wait indefinitely.
      await pin(target).use((scope) async {
        await scope.header();
      });
      if (source.value.projection.sync.phase == ResourceSyncPhase.ready &&
          source.value.projection.stamp?.origin != target.origin) {
        await resync(retry: true);
      }
      await source.waitFor((value) {
        if (value.projection.sync.phase == ResourceSyncPhase.failed)
          throw value.projection.sync.error!;
        if (value.projection.sync.phase != ResourceSyncPhase.ready)
          return false;
        if (value.projection.stamp?.origin != target.origin)
          throw accountDataSuperseded;
        final reference = value.projection.header?.reference;
        return reference != null &&
            reference.entry == target.reference.entry &&
            reference.revision >= target.reference.revision;
      });
      if (!validate()) throw accountDataSuperseded;
      return readTarget(target, id, validate: validate);
    });
  }

  Future<void> page({int limit = 32}) {
    lifetime.admit();
    if (limit < 1 || limit > 100)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A usage page limit must be between 1 and 100.',
        retryable: false,
        correlationId: 'account-usage',
      );
    final demand = capture();
    final mirror = source.value.usages;
    if (demand.origin != null &&
        mirror is CurrentCollectionMirror<AccountUsageRecord> &&
        mirror.window.origin == demand.origin &&
        mirror.window.reference == demand.collection &&
        mirror.window.complete &&
        mirror.window.error == null)
      return Future.value();
    final continuation =
        mirror is CurrentCollectionMirror<AccountUsageRecord> &&
            mirror.window.origin == demand.origin &&
            mirror.window.reference == demand.collection
        ? mirror.window.continuation
        : null;
    final key = (demand: demand, continuation: continuation, limit: limit);
    final pending = _pages[key];
    if (pending != null) return pending;
    final done = Completer<void>();
    _pages[key] = done.future;
    final generation = ++_pageGeneration;
    unawaited(
      lifetime
          .run('account-usage:page', () async {
            final binding = await bind(demand);
            final window = _window(binding.target.origin, binding.collection);
            final offset = switch (window.continuation) {
              OffsetCollectionContinuation(:final value) => value,
              EndCollectionContinuation() => binding.collection.total,
              _ => 0,
            };
            source.publish(
              source.value.copyWith(
                usages: CollectionMirror.current(
                  window: window.copyWith(loading: true, error: null),
                ),
              ),
            );
            try {
              await pin(binding.target).use((scope) async {
                final page = await scope.entries(offset: offset, limit: limit);
                final end = offset + page.items.length;
                if (page.collection != binding.collection ||
                    page.offset != offset ||
                    page.items.length > limit ||
                    end < offset ||
                    end > binding.collection.total ||
                    page.items.isEmpty && end < binding.collection.total ||
                    page.nextOffset !=
                        (end == binding.collection.total ? null : end))
                  throw accountDataProtocol(
                    'A usage page does not match its original collection.',
                  );
                final prefix = window.entries.take(offset).toList();
                if (prefix.length != offset) throw accountDataSuperseded;
                final seen = prefix.map((item) => item.entry).toSet();
                final rows =
                    Map<
                      int,
                      ReadValue<AccountUsageRecord, ProductEntityRef>
                    >.of(window.rows);
                StudioFailure? failure;
                for (final reference in page.items) {
                  if (!seen.add(reference.entry))
                    throw accountDataProtocol(
                      'A usage index page repeated an entry.',
                    );
                  final old = rows[reference.entry];
                  if (old
                          is ReadyReadValue<
                            AccountUsageRecord,
                            ProductEntityRef
                          > &&
                      old.current.reference == reference)
                    continue;
                  try {
                    final entity = await scope.entity(reference);
                    if (entity.reference != reference)
                      throw accountDataProtocol(
                        'A usage entity returned another reference.',
                      );
                    final value = await UsageReader(scope).record(entity.value);
                    rows[reference.entry] = ReadValue.ready(
                      current: Materialized(
                        origin: binding.target.origin,
                        reference: reference,
                        value: value,
                      ),
                    );
                  } catch (error) {
                    failure ??= accountDataFailure(error);
                    rows[reference.entry] = ReadValue.failed(
                      origin: binding.target.origin,
                      reference: reference,
                      error: accountDataFailure(error),
                      previous: accountPrevious(old),
                    );
                  }
                }
                if (lifetime.sealed) throw resourceCancelled;
                if (generation != _pageGeneration ||
                    !current(binding.target) ||
                    _collection != binding.collection)
                  throw accountDataSuperseded;
                source.publish(
                  source.value.copyWith(
                    usages: CollectionMirror.current(
                      window: window.copyWith(
                        entries: [...prefix, ...page.items],
                        rows: rows,
                        continuation: failure != null
                            ? CollectionContinuation.offset(value: offset)
                            : page.nextOffset == null
                            ? const CollectionContinuation.end()
                            : CollectionContinuation.offset(
                                value: page.nextOffset!,
                              ),
                        complete:
                            failure == null &&
                            page.nextOffset == null &&
                            end == binding.collection.total,
                        loading: false,
                        error: failure,
                      ),
                    ),
                  ),
                );
                if (failure != null) throw failure;
              });
            } catch (error) {
              final latest = source.value.usages;
              if (!lifetime.sealed &&
                  generation == _pageGeneration &&
                  current(binding.target) &&
                  latest is CurrentCollectionMirror<AccountUsageRecord>)
                source.publish(
                  source.value.copyWith(
                    usages: CollectionMirror.current(
                      window: latest.window.copyWith(
                        loading: false,
                        error: accountDataFailure(error),
                      ),
                    ),
                  ),
                );
              rethrow;
            }
          })
          .then(
            (_) {
              unawaited(_pages.remove(key));
              done.complete();
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_pages.remove(key));
              done.completeError(accountDataFailure(error), stack);
            },
          ),
    );
    return done.future;
  }
}
