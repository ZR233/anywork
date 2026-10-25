import 'dart:async';

import '../../../operations.dart' show CommitReceipt;
import '../../../operations_ports.dart' show OperationRecorder;
import '../../../resources_ports.dart';
import '../domain/configuration_state.dart';
import '../domain/profile_values.dart';
import 'configuration_frames.dart';
import 'configuration_port.dart';
import 'configuration_read_chain.dart';
import 'configuration_read_fields.dart';
import 'configuration_reducer.dart';
import 'configuration_status_reader.dart';
import 'profiles_reader.dart';

typedef _ProfilesDemand = ({
  ProductReadOrigin? origin,
  AgentProfilesReadRef? reference,
  ProductCollectionRef? collection,
  Object? opening,
});
typedef _ProfilesBinding = ({
  AgentProfilesReadTarget target,
  ProductCollectionRef collection,
});

/// Profiles has its own source clock, pins and details. A Settings publication
/// never stands in for observing this source or resolving profile instructions.
final class ProfilesMirror {
  ProfilesMirror(this.port, this.lifetime, this.operations)
    : source = ResourceSource(
        ProfilesState(
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
          profiles: const CollectionMirror.unavailable(lastKnown: null),
          details: const {},
          diagnostics: null,
        ),
        lifetime.budget,
        'profiles:observer',
      ) {
    status = ConfigurationStatusReads(
      lifetime: lifetime,
      owner: 'profiles:source-status',
      open: port.openSourceStatus,
      current: () => (
        origin: source.value.projection.stamp?.origin,
        source: source.value.projection.header?.source,
        value: source.value.sourceStatus,
      ),
      publish: (value) =>
          source.publish(source.value.copyWith(sourceStatus: value)),
    );
    lifetime.onSeal(source.seal);
  }

  final ConfigurationPort port;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final ResourceSource<ProfilesState> source;
  late final ConfigurationStatusReads status;
  ProductFeedOwner<AgentProfilesFrame>? _feed;
  ProductFeedOwner<AgentProfilesFrame>? _retiring;
  ProductProjectionStamp? _feedStamp;
  ProductCollectionRef? _collection;
  Object? _opening;
  Future<void>? _restart;
  final Map<
    AgentProfilesReadTarget,
    PinnedReadOwner<AgentProfilesReadConnection>
  >
  _pins = {};
  final Set<ConfigurationReadChain> _reads = {};
  final Map<({String id, _ProfilesDemand demand}), Future<AgentProfileSnapshot>>
  _details = {};
  final Map<_ProfilesDemand, Future<List<ProfileDiagnostic>>> _diagnostics = {};
  final Map<
    ({_ProfilesDemand demand, CollectionContinuation? continuation, int limit}),
    Future<void>
  >
  _pages = {};
  int _pageGeneration = 0;

  _ProfilesDemand _capture() {
    lifetime.admit();
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
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
    late final ProductFeedOwner<AgentProfilesFrame> feed;
    feed = ProductFeedOwner(
      lifetime: lifetime,
      owner: 'profiles:feed',
      open: port.openAgentProfiles,
      sequence: (frame) =>
          frame is AgentProfilesData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed)
          return frame is AgentProfilesData ? frame.deliverySequence : null;
        switch (frame) {
          case AgentProfilesData(:final deliverySequence, :final event):
            switch (event) {
              case AgentProfilesBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.agentProfiles ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation)
                  throw configurationProtocol(
                    'The Profiles baseline has another source identity.',
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
                  baseline: value,
                );
              case AgentProfilesChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_feedStamp == null ||
                    stamp.origin != _feedStamp!.origin ||
                    baseRevision != _feedStamp!.revision ||
                    stamp.revision <= baseRevision)
                  throw configurationProtocol(
                    'The Profiles projection has a revision gap.',
                  );
                _feedStamp = stamp;
                _adopt(
                  stamp,
                  value.header,
                  value.collection,
                  value.baseCollectionRevision,
                  value.upserted,
                  value.removedEntries,
                  change: value,
                );
            }
            return deliverySequence;
          case AgentProfilesResyncRequired(:final identity):
            _control(identity);
            _backgroundResync();
          case AgentProfilesFeedFailure(:final identity, :final error):
            _control(identity);
            _failed(feed, error);
          case AgentProfilesClosed(:final identity, :final reason):
            _control(identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _backgroundResync();
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.unavailable,
                  message: 'The Profiles feed closed.',
                  retryable: true,
                  correlationId: 'profiles',
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
    if (identity.resource != ProductResource.agentProfiles ||
        _feedStamp != null &&
            (identity.ownerEpoch != _feedStamp!.ownerEpoch ||
                identity.incarnation != _feedStamp!.incarnation))
      throw configurationProtocol(
        'A Profiles control frame belongs to another source.',
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
  void _failed(ProductFeedOwner<AgentProfilesFrame> feed, StudioFailure error) {
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
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
      return Future.value();
    }
    final feed = _feed!;
    final prior = _restart;
    if (prior != null) {
      if (identical(_retiring, feed)) return prior;
      feed.requestClose();
      return Future<void>.sync(
        () => lifetime.run('profiles:deferred-resync', () async {
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
        () => lifetime.run('profiles:resync', () async {
          await feed.cleanup(retry: retry);
          if (!lifetime.sealed && identical(_feed, feed)) {
            if (!feed.released)
              throw const StudioFailure(
                code: StudioFailureCode.busy,
                message: 'The Profiles feed has unresolved cleanup.',
                retryable: true,
                correlationId: 'profiles',
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
            _sync(ResourceSyncPhase.failed, configurationFailure(error));
          done.completeError(configurationFailure(error), stack);
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
    AgentProfilesHeader header,
    ProductCollectionRef? collection,
    int? base,
    List<ProductEntityRef> updates,
    List<int> removed, {
    AgentProfilesBaseline? baseline,
    AgentProfilesChange? change,
  }) {
    final available =
        header.source.brief is ReadyObservedBrief ||
        header.source.brief is RefreshingObservedBrief ||
        header.source.brief is StaleObservedBrief ||
        header.source.brief is DegradedObservedBrief;
    if (stamp.revision < 0 ||
        stamp.incarnation < 0 ||
        available != (header.reference != null) ||
        available != (collection != null) ||
        available != (header.profilesRevision != null))
      throw configurationProtocol(
        'The Profiles header has inconsistent value availability.',
      );
    final previous = source.value;
    if (previous.projection.stamp?.origin == stamp.origin &&
        previous.projection.stamp!.revision > stamp.revision)
      return;
    if (change != null && base != _collection?.revision)
      throw configurationProtocol('The Profiles collection clock has a gap.');
    for (final read in _reads) {
      read.change(stamp.origin, base, collection, updates, removed);
    }
    _collection = collection;
    final target = header.reference == null
        ? null
        : AgentProfilesReadTarget(
            origin: stamp.origin,
            reference: header.reference!,
          );
    for (final entry in List.of(_pins.entries)) {
      if (entry.key != target) {
        entry.value.retire();
        _pins.remove(entry.key);
      }
    }
    status.retireExcept(stamp.origin, header.source.status);
    source.publish(
      baseline != null
          ? reduceProfilesBaseline(previous, stamp, baseline)
          : reduceProfilesChange(previous, stamp, change!),
    );
    if (header.profilesRevision case final revision?)
      operations.observe(
        ResourceStamp(
          resourceKey: 'agent-profiles',
          ownerEpoch: stamp.ownerEpoch,
          revision: revision,
        ),
      );
  }

  Future<_ProfilesBinding> _bind(_ProfilesDemand demand) async {
    lifetime.admit();
    _ProfilesBinding? binding;
    await source.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed)
        throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      final reference = value.projection.header!.reference;
      final collection = _collection;
      if (reference == null || collection == null)
        throw const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Profiles has no current business value.',
          retryable: true,
          correlationId: 'profiles',
        );
      binding = (
        target: AgentProfilesReadTarget(
          origin: value.projection.stamp!.origin,
          reference: reference,
        ),
        collection: collection,
      );
      return true;
    });
    final original = binding!;
    if (demand.opening != null && !identical(demand.opening, _opening) ||
        demand.reference != null &&
            (demand.origin != original.target.origin ||
                demand.reference != original.target.reference ||
                demand.collection != original.collection))
      throw configurationSuperseded;
    return original;
  }

  bool _current(AgentProfilesReadTarget target) =>
      source.value.projection.stamp?.origin == target.origin &&
      source.value.projection.header?.reference == target.reference;
  PinnedReadOwner<AgentProfilesReadConnection> _pin(
    AgentProfilesReadTarget target,
  ) {
    final previous = _pins[target];
    if (previous != null && previous.accepting) return previous;
    return _pins[target] = PinnedReadOwner(
      lifetime: lifetime,
      owner: 'profiles:read',
      open: () =>
          port.openAgentProfilesRead(target.reference, origin: target.origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
  }

  CollectionWindow<AgentProfileSummary> _window(
    ProductReadOrigin origin,
    ProductCollectionRef collection,
  ) {
    if (source.value.projection.stamp?.origin != origin ||
        _collection != collection)
      throw configurationSuperseded;
    final mirror = source.value.profiles;
    if (mirror is CurrentCollectionMirror<AgentProfileSummary> &&
        mirror.window.origin == origin &&
        mirror.window.reference == collection)
      return mirror.window;
    return CollectionWindow(
      origin: origin,
      reference: collection,
      entries: const [],
      rows: const {},
      continuation: collection.total == 0
          ? const CollectionContinuation.end()
          : const CollectionContinuation.unknown(),
      complete: collection.total == 0,
      loading: false,
      error: null,
    );
  }

  Future<void> loadStatus() {
    final demand = _capture();
    final snapshot = source.value;
    if (snapshot.projection.sync.phase == ResourceSyncPhase.ready)
      return status.load(
        snapshot.projection.stamp!.origin,
        snapshot.projection.header!.source,
      );
    return lifetime.run('profiles:load-source-status', () async {
      ProfilesState? snapshot;
      await source.waitFor((value) {
        if (value.projection.sync.phase == ResourceSyncPhase.failed)
          throw value.projection.sync.error!;
        if (value.projection.sync.phase != ResourceSyncPhase.ready)
          return false;
        snapshot = value;
        return true;
      });
      if (demand.opening != null && !identical(demand.opening, _opening))
        throw configurationSuperseded;
      await status.load(
        snapshot!.projection.stamp!.origin,
        snapshot!.projection.header!.source,
      );
    });
  }

  Future<AgentProfileSnapshot> detail(String id) {
    final demand = _capture();
    final key = (id: id, demand: demand);
    if (demand.origin != null) {
      for (final row in source.value.details.values) {
        if (row is ReadyReadValue<AgentProfileSnapshot, ProductEntityRef> &&
            row.current.origin == demand.origin &&
            row.current.value.profileId == id)
          return Future.value(row.current.value);
      }
    }
    final pending = _details[key];
    if (pending != null) return pending;
    final done = Completer<AgentProfileSnapshot>();
    _details[key] = done.future;
    unawaited(
      lifetime
          .run('profiles:detail', () async {
            final binding = await _bind(demand);
            final chain = ConfigurationReadChain(
              binding.target.origin,
              binding.collection,
              orderStableForValueChanges: false,
            );
            _reads.add(chain);
            try {
              return await _pin(binding.target).use((scope) async {
                final reference = await scope.lookupProfile(id);
                if (reference == null) {
                  if (!_current(binding.target)) throw configurationSuperseded;
                  throw const StudioFailure(
                    code: StudioFailureCode.notFound,
                    message:
                        'The requested Profile does not exist in this source.',
                    retryable: false,
                    correlationId: 'profiles',
                  );
                }
                if (_current(binding.target))
                  source.publish(
                    source.value.copyWith(
                      details: {
                        ...source.value.details,
                        reference.entry: ReadValue.loading(
                          origin: binding.target.origin,
                          reference: reference,
                          previous: configurationPrevious(
                            source.value.details[reference.entry],
                          ),
                        ),
                      },
                    ),
                  );
                try {
                  final entity = await scope.entity(reference);
                  if (entity.reference != reference)
                    throw configurationProtocol(
                      'A Profile lookup returned another reference.',
                    );
                  final value = await ProfilesReader(scope)
                      .detail(entity.value);
                  if (value.profileId != id)
                    throw configurationProtocol(
                      'A Profile lookup returned another identity.',
                    );
                  if (lifetime.sealed) throw resourceCancelled;
                  if (chain.entity(
                        reference,
                        source.value.projection.stamp!.origin,
                        _collection,
                      ) !=
                      reference)
                    throw configurationSuperseded;
                  source.publish(
                    source.value.copyWith(
                      details: {
                        ...source.value.details,
                        reference.entry: ReadValue.ready(
                          current: Materialized(
                            origin: binding.target.origin,
                            reference: reference,
                            value: value,
                          ),
                        ),
                      },
                    ),
                  );
                  return value;
                } catch (error) {
                  if (!lifetime.sealed && _current(binding.target))
                    source.publish(
                      source.value.copyWith(
                        details: {
                          ...source.value.details,
                          reference.entry: ReadValue.failed(
                            origin: binding.target.origin,
                            reference: reference,
                            error: configurationFailure(error),
                            previous: configurationPrevious(
                              source.value.details[reference.entry],
                            ),
                          ),
                        },
                      ),
                    );
                  rethrow;
                }
              });
            } finally {
              _reads.remove(chain);
            }
          })
          .then(
            (value) {
              unawaited(_details.remove(key));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_details.remove(key));
              done.completeError(configurationFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  Future<List<ProfileDiagnostic>> diagnostics() {
    final demand = _capture();
    final known = source.value.diagnostics;
    if (known
            is ReadyReadValue<List<ProfileDiagnostic>, AgentProfilesReadRef> &&
        known.current.origin == demand.origin &&
        known.current.reference == demand.reference)
      return Future.value(known.current.value);
    final pending = _diagnostics[demand];
    if (pending != null) return pending;
    final done = Completer<List<ProfileDiagnostic>>();
    _diagnostics[demand] = done.future;
    unawaited(
      lifetime
          .run('profiles:diagnostics', () async {
            final binding = await _bind(demand);
            final target = binding.target;
            source.publish(
              source.value.copyWith(
                diagnostics: ReadValue.loading(
                  origin: target.origin,
                  reference: target.reference,
                  previous: configurationPrevious(source.value.diagnostics),
                ),
              ),
            );
            try {
              final value = await _pin(target).use(
                (scope) async =>
                    ProfilesReader(scope)
                        .diagnostics((await scope.header()).diagnostics),
              );
              if (lifetime.sealed) throw resourceCancelled;
              if (!_current(target)) throw configurationSuperseded;
              source.publish(
                source.value.copyWith(
                  diagnostics: ReadValue.ready(
                    current: Materialized(
                      origin: target.origin,
                      reference: target.reference,
                      value: value,
                    ),
                  ),
                ),
              );
              return value;
            } catch (error) {
              if (!lifetime.sealed && _current(target))
                source.publish(
                  source.value.copyWith(
                    diagnostics: ReadValue.failed(
                      origin: target.origin,
                      reference: target.reference,
                      error: configurationFailure(error),
                      previous: configurationPrevious(source.value.diagnostics),
                    ),
                  ),
                );
              rethrow;
            }
          })
          .then(
            (value) {
              unawaited(_diagnostics.remove(demand));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_diagnostics.remove(demand));
              done.completeError(configurationFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  Future<void> page({int limit = 32}) {
    lifetime.admit();
    if (limit < 1 || limit > 100)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A Profile page limit must be between 1 and 100.',
        retryable: false,
        correlationId: 'profiles',
      );
    final demand = _capture();
    final mirror = source.value.profiles;
    if (source.value.projection.sync.phase == ResourceSyncPhase.ready &&
        mirror is CurrentCollectionMirror<AgentProfileSummary> &&
        mirror.window.complete &&
        mirror.window.error == null)
      return Future.value();
    final continuation =
        mirror is CurrentCollectionMirror<AgentProfileSummary> &&
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
          .run('profiles:page', () async {
            final binding = await _bind(demand);
            if (generation != _pageGeneration ||
                !identical(_pages[key], done.future) ||
                source.value.projection.stamp?.origin !=
                    binding.target.origin ||
                _collection != binding.collection)
              throw configurationSuperseded;
            final window = _window(binding.target.origin, binding.collection);
            final offset = switch (window.continuation) {
              OffsetCollectionContinuation(:final value) => value,
              EndCollectionContinuation() => binding.collection.total,
              _ => 0,
            };
            final chain = ConfigurationReadChain(
              binding.target.origin,
              binding.collection,
              orderStableForValueChanges: false,
            );
            _reads.add(chain);
            source.publish(
              source.value.copyWith(
                profiles: CollectionMirror.current(
                  window: window.copyWith(loading: true, error: null),
                ),
              ),
            );
            try {
              await _pin(binding.target).use((scope) async {
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
                  throw configurationProtocol(
                    'A Profile index page does not match its frozen collection.',
                  );
                final loaded =
                    <int, ReadValue<AgentProfileSummary, ProductEntityRef>>{};
                StudioFailure? failure;
                for (final reference in page.items) {
                  if (loaded.containsKey(reference.entry))
                    throw configurationProtocol(
                      'A Profile index page repeated an entry.',
                    );
                  final old = window.rows[reference.entry];
                  if (old
                          is ReadyReadValue<
                            AgentProfileSummary,
                            ProductEntityRef
                          > &&
                      old.current.origin == binding.target.origin &&
                      old.current.reference == reference) {
                    loaded[reference.entry] = old;
                    continue;
                  }
                  try {
                    final entity = await scope.entity(reference);
                    if (entity.reference != reference)
                      throw configurationProtocol(
                        'A Profile entity returned another reference.',
                      );
                    final value = await ProfilesReader(scope)
                        .summary(entity.value);
                    loaded[reference.entry] = ReadValue.ready(
                      current: Materialized(
                        origin: binding.target.origin,
                        reference: reference,
                        value: value,
                      ),
                    );
                  } catch (error) {
                    failure ??= configurationFailure(error);
                    loaded[reference.entry] = ReadValue.failed(
                      origin: binding.target.origin,
                      reference: reference,
                      error: configurationFailure(error),
                      previous: configurationPrevious(old),
                    );
                  }
                }
                if (lifetime.sealed) throw resourceCancelled;
                final current = source.value.profiles;
                if (generation != _pageGeneration ||
                    !identical(_pages[key], done.future) ||
                    source.value.projection.stamp?.origin !=
                        binding.target.origin ||
                    _collection != binding.collection ||
                    current is! CurrentCollectionMirror<AgentProfileSummary> ||
                    current.window.origin != binding.target.origin ||
                    current.window.reference != binding.collection)
                  throw configurationSuperseded;
                final entries = chain.page(
                  page.items,
                  binding.target.origin,
                  binding.collection,
                );
                final latest = _window(
                  binding.target.origin,
                  binding.collection,
                );
                final prefix = latest.entries.take(offset).toList();
                if (prefix.length != offset ||
                    prefix.any(
                      (item) =>
                          entries.any((other) => other.entry == item.entry),
                    ))
                  throw configurationSuperseded;
                source.publish(
                  source.value.copyWith(
                    profiles: CollectionMirror.current(
                      window: latest.copyWith(
                        entries: [...prefix, ...entries],
                        rows: {...latest.rows, ...loaded},
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
                            end == latest.reference.total,
                        loading: false,
                        error: failure,
                      ),
                    ),
                  ),
                );
                if (failure != null) throw failure;
              });
            } catch (error) {
              final latest = source.value.profiles;
              if (!lifetime.sealed &&
                  generation == _pageGeneration &&
                  identical(_pages[key], done.future) &&
                  source.value.projection.stamp?.origin ==
                      binding.target.origin &&
                  _collection == binding.collection &&
                  latest is CurrentCollectionMirror<AgentProfileSummary> &&
                  latest.window.origin == binding.target.origin &&
                  latest.window.reference == binding.collection)
                source.publish(
                  source.value.copyWith(
                    profiles: CollectionMirror.current(
                      window: latest.window.copyWith(
                        loading: false,
                        error: configurationFailure(error),
                      ),
                    ),
                  ),
                );
              rethrow;
            } finally {
              _reads.remove(chain);
            }
          })
          .then(
            (_) {
              unawaited(_pages.remove(key));
              done.complete();
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_pages.remove(key));
              done.completeError(configurationFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  Future<void> synchronize(
    AgentProfilesReadTarget target, {
    CommitReceipt? receipt,
  }) {
    lifetime.admit();
    _capture();
    return lifetime.run('profiles:command-target', () async {
      if (source.value.projection.sync.phase == ResourceSyncPhase.ready &&
          source.value.projection.stamp?.origin != target.origin) {
        await _pin(target).use((scope) async {
          await scope.header();
        });
        await resync(retry: true);
      }
      await source.waitFor((value) {
        if (value.projection.sync.phase == ResourceSyncPhase.failed)
          throw value.projection.sync.error!;
        if (value.projection.sync.phase != ResourceSyncPhase.ready)
          return false;
        if (value.projection.stamp?.origin != target.origin)
          throw configurationSuperseded;
        final reference = value.projection.header?.reference;
        if (reference == null ||
            reference.entry != target.reference.entry ||
            reference.revision < target.reference.revision)
          return false;
        if (receipt == null) return true;
        final targets = receipt.targets
            .whereType<ResourceStamp>()
            .where((stamp) => stamp.resourceKey == 'agent-profiles')
            .toList();
        if (targets.length != 1 ||
            targets.single.ownerEpoch != target.origin.ownerEpoch)
          throw configurationProtocol(
            'The Profile receipt has inconsistent source targets.',
          );
        final revision = value.projection.header?.profilesRevision;
        return revision != null && revision >= targets.single.revision;
      });
    });
  }
}
