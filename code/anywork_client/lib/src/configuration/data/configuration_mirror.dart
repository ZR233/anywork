import 'dart:async';

import '../../../operations.dart' show CommitReceipt;
import '../../../operations_ports.dart' show OperationRecorder;
import '../../../resources_ports.dart';
import '../domain/configuration_state.dart';
import '../domain/configuration_values.dart';
import 'configuration_access.dart';
import 'configuration_fields.dart';
import 'configuration_frames.dart';
import 'configuration_port.dart';
import 'configuration_read_chain.dart';
import 'configuration_read_fields.dart';
import 'configuration_reader.dart';
import 'configuration_reducer.dart';
import 'configuration_status_reader.dart';
import 'configuration_start_reads.dart';

final class ConfigurationMirror implements ConfigurationReadAccess {
  ConfigurationMirror(this.port, this.lifetime, this.operations)
    : source = ResourceSource(
        ConfigurationState(
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
          accounts: const CollectionMirror.unavailable(lastKnown: null),
          defaultAccountId: null,
          modeRoutes: null,
          roles: null,
          permissionMode: null,
          instructions: null,
          skillsSettings: null,
          mcpConfigurations: null,
          general: null,
          delegation: null,
          webSearch: null,
          deepSeekSearch: null,
        ),
        lifetime.budget,
        'configuration:observer',
      ) {
    fields = ConfigurationFields(this);
    startRoutes = ConfigurationStartReads(port, lifetime);
    status = ConfigurationStatusReads(
      lifetime: lifetime,
      owner: 'configuration:source-status',
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
  @override
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  @override
  final ResourceSource<ConfigurationState> source;
  late final ConfigurationFields fields;
  late final ConfigurationStartReads startRoutes;
  late final ConfigurationStatusReads status;
  ProductFeedOwner<ConfigurationFrame>? _feed;
  ProductFeedOwner<ConfigurationFrame>? _retiring;
  ProductProjectionStamp? _feedStamp;
  ProductCollectionRef? _collection;
  Object? _opening;
  Future<void>? _restart;
  final Map<
    ConfigurationReadTarget,
    PinnedReadOwner<ConfigurationReadConnection>
  >
  _pins = {};
  final Map<
    ConfigurationRoleReadTarget,
    PinnedReadOwner<ConfigurationRoleReadConnection>
  >
  _rolePins = {};
  final Map<
    ({ConfigurationRoleReadTarget target, String roleId}),
    Future<RoleRouteRead>
  >
  _roleQueries = {};
  final Set<ConfigurationReadChain> _reads = {};
  final Map<
    ({String id, ConfigurationDemand demand}),
    Future<AccountConfiguration?>
  >
  _accounts = {};
  final Map<
    ({
      ConfigurationDemand demand,
      CollectionContinuation? continuation,
      int limit,
    }),
    Future<void>
  >
  _pages = {};
  int _pageGeneration = 0;

  @override
  ConfigurationDemand capture() {
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
    late final ProductFeedOwner<ConfigurationFrame> feed;
    feed = ProductFeedOwner(
      lifetime: lifetime,
      owner: 'configuration:feed',
      open: port.openConfiguration,
      sequence: (frame) =>
          frame is ConfigurationData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed)
          return frame is ConfigurationData ? frame.deliverySequence : null;
        switch (frame) {
          case ConfigurationData(:final deliverySequence, :final event):
            switch (event) {
              case ConfigurationBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.configuration ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation)
                  throw configurationProtocol(
                    'The Configuration baseline has another identity.',
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
              case ConfigurationChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_feedStamp == null ||
                    stamp.origin != _feedStamp!.origin ||
                    baseRevision != _feedStamp!.revision ||
                    stamp.revision <= baseRevision)
                  throw configurationProtocol(
                    'The Configuration projection has a revision gap.',
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
          case ConfigurationResyncRequired(:final identity):
            _control(identity);
            _backgroundResync();
          case ConfigurationFeedFailure(:final identity, :final error):
            _control(identity);
            _failed(feed, error);
          case ConfigurationClosed(:final identity, :final reason):
            _control(identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _backgroundResync();
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.unavailable,
                  message: 'The Configuration feed closed.',
                  retryable: true,
                  correlationId: 'configuration',
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
    if (identity.resource != ProductResource.configuration ||
        _feedStamp != null &&
            (identity.ownerEpoch != _feedStamp!.ownerEpoch ||
                identity.incarnation != _feedStamp!.incarnation))
      throw configurationProtocol(
        'A Configuration control frame belongs to another source.',
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
  void _failed(ProductFeedOwner<ConfigurationFrame> feed, StudioFailure error) {
    // PROBE
    print('[F] failed ${error.code} ${error.message}');
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
        () => lifetime.run('configuration:deferred-resync', () async {
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
        () => lifetime.run('configuration:resync', () async {
          await feed.cleanup(retry: retry);
          if (!lifetime.sealed && identical(_feed, feed)) {
            if (!feed.released)
              throw const StudioFailure(
                code: StudioFailureCode.busy,
                message: 'The Configuration feed has unresolved cleanup.',
                retryable: true,
                correlationId: 'configuration',
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
    ConfigurationHeader header,
    ProductCollectionRef? collection,
    int? base,
    List<ProductEntityRef> updates,
    List<int> removed, {
    ConfigurationBaseline? baseline,
    ConfigurationChange? change,
  }) {
    // PROBE
    print('[F] adopt rev=${stamp.revision} baseline=${baseline != null}');
    final valueAvailable =
        header.source.brief is ReadyObservedBrief ||
        header.source.brief is RefreshingObservedBrief ||
        header.source.brief is StaleObservedBrief ||
        header.source.brief is DegradedObservedBrief;
    if (stamp.revision < 0 ||
        stamp.incarnation < 0 ||
        valueAvailable != (header.reference != null) ||
        valueAvailable != (collection != null) ||
        valueAvailable != (header.configurationRevision != null) ||
        valueAvailable != (header.updatedAt != null))
      throw configurationProtocol(
        'The Configuration header has inconsistent value availability.',
      );
    final previous = source.value;
    if (previous.projection.stamp?.origin == stamp.origin &&
        previous.projection.stamp!.revision > stamp.revision)
      return;
    if (change != null && base != _collection?.revision)
      throw configurationProtocol(
        'The Configuration collection clock has a gap.',
      );
    final target = header.reference == null
        ? null
        : ConfigurationReadTarget(
            origin: stamp.origin,
            reference: header.reference!,
          );
    final roleTarget = header.roleRead;
    final previousRoleTarget = previous.projection.header?.roleRead;
    // A pair is a native credential pinned at its own issue snapshot: the
    // header's value reference may advance while the retained pair keeps
    // describing the material it was issued for. Only a newly issued pair must
    // describe the header it arrived with, and it must belong to this source.
    // Consumers that need the pin to mirror the current canonical value compare
    // it with the header themselves before opening a read.
    if (roleTarget != null &&
        roleTarget != previousRoleTarget &&
        (roleTarget.configuration != target ||
            roleTarget.stamp.settingsRevision != header.configurationRevision))
      throw configurationProtocol(
        'The role read pair does not match its Configuration header.',
      );
    if (roleTarget != null &&
        previousRoleTarget != null &&
        roleTarget.configuration.origin ==
            previousRoleTarget.configuration.origin &&
        roleTarget.reference == previousRoleTarget.reference &&
        roleTarget != previousRoleTarget)
      throw configurationProtocol(
        'A role read reference changed its immutable pair.',
      );
    // Pair-only metadata must not consume ordinary account read-chain history.
    if (previous.projection.stamp?.origin != stamp.origin ||
        collection != _collection ||
        updates.isNotEmpty ||
        removed.isNotEmpty) {
      for (final read in _reads) {
        read.change(stamp.origin, base, collection, updates, removed);
      }
    }
    _collection = collection;
    for (final entry in List.of(_pins.entries)) {
      if (entry.key != target) {
        entry.value.retire();
        _pins.remove(entry.key);
      }
    }
    for (final entry in List.of(_rolePins.entries)) {
      if (entry.key != roleTarget) {
        entry.value.retire();
        _rolePins.remove(entry.key);
      }
    }
    startRoutes.retainOnly(roleTarget);
    status.retireExcept(stamp.origin, header.source.status);
    source.publish(
      baseline != null
          ? reduceConfigurationBaseline(previous, stamp, baseline)
          : reduceConfigurationChange(previous, stamp, change!),
    );
    if (header.configurationRevision case final revision?)
      operations.observe(
        ResourceStamp(
          resourceKey: 'settings',
          ownerEpoch: stamp.ownerEpoch,
          revision: revision,
        ),
      );
  }

  Future<ConfigurationState> _projection(ConfigurationDemand demand) async {
    lifetime.admit();
    ConfigurationState? snapshot;
    await source.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed)
        throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      snapshot = value;
      return true;
    });
    if (demand.opening != null && !identical(demand.opening, _opening))
      throw configurationSuperseded;
    return snapshot!;
  }

  @override
  Future<ConfigurationBinding> bind(ConfigurationDemand demand) async {
    lifetime.admit();
    ConfigurationBinding? binding;
    await source.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed)
        throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      final header = value.projection.header!;
      final collection = _collection;
      if (header.reference == null ||
          header.configurationRevision == null ||
          collection == null)
        throw const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Configuration has no current business value.',
          retryable: true,
          correlationId: 'configuration',
        );
      binding = (
        target: ConfigurationReadTarget(
          origin: value.projection.stamp!.origin,
          reference: header.reference!,
        ),
        collection: collection,
        revision: header.configurationRevision!,
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

  @override
  PinnedReadOwner<ConfigurationReadConnection> pin(
    ConfigurationReadTarget target,
  ) {
    final previous = _pins[target];
    if (previous != null && previous.accepting) return previous;
    return _pins[target] = PinnedReadOwner(
      lifetime: lifetime,
      owner: 'configuration:read',
      open: () =>
          port.openConfigurationRead(target.reference, origin: target.origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
  }

  @override
  bool current(ConfigurationReadTarget target) =>
      source.value.projection.stamp?.origin == target.origin &&
      source.value.projection.header?.reference == target.reference;

  PinnedReadOwner<ConfigurationRoleReadConnection> _rolePin(
    ConfigurationRoleReadTarget target,
  ) {
    final previous = _rolePins[target];
    if (previous != null && previous.accepting) return previous;
    return _rolePins[target] = PinnedReadOwner(
      lifetime: lifetime,
      owner: 'configuration:role-read',
      open: () => port.openRoleRead(target),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
  }

  /// Native resolves presence and missing-role policy over this original pair.
  /// Replies are borrowed query results, never another canonical projection.
  Future<RoleRouteRead> roleRoute({
    required ConfigurationRoleReadTarget target,
    required String roleId,
  }) {
    lifetime.admit();
    final key = (target: target, roleId: roleId);
    final pending = _roleQueries[key];
    if (pending != null) return pending;
    final done = Completer<RoleRouteRead>();
    _roleQueries[key] = done.future;
    unawaited(
      Future<RoleRouteRead>.sync(
        () => lifetime.run('configuration:role-route', () async {
          final pin = _rolePin(key.target);
          try {
            final value = await pin.use((scope) async {
              final header = await scope.header();
              if (header != key.target)
                throw configurationProtocol(
                  'The role scope returned another immutable pair.',
                );
              if (lifetime.sealed) throw resourceCancelled;
              final value = await scope.roleRoute(key.roleId);
              if (value case ConfiguredRoleRouteRead(:final route)) {
                if (route.key != key.roleId)
                  throw configurationProtocol(
                    'The role query returned another configured key.',
                  );
              }
              return value;
            });
            if (lifetime.sealed) throw resourceCancelled;
            return value;
          } catch (_) {
            pin.retire();
            if (identical(_rolePins[key.target], pin))
              _rolePins.remove(key.target);
            rethrow;
          }
        }),
      ).then(
        (value) {
          unawaited(_roleQueries.remove(key));
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          unawaited(_roleQueries.remove(key));
          done.completeError(configurationFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  Future<void> loadStatus() {
    final demand = capture();
    final snapshot = source.value;
    if (snapshot.projection.sync.phase == ResourceSyncPhase.ready)
      return status.load(
        snapshot.projection.stamp!.origin,
        snapshot.projection.header!.source,
      );
    return lifetime.run('configuration:load-source-status', () async {
      final snapshot = await _projection(demand);
      await status.load(
        snapshot.projection.stamp!.origin,
        snapshot.projection.header!.source,
      );
    });
  }

  Future<({ProductReadOrigin origin, int revision})> writeBase() async {
    final binding = await bind(capture());
    return (origin: binding.target.origin, revision: binding.revision);
  }

  Future<AccountConfiguration?> account(String id) {
    final demand = capture();
    final key = (id: id, demand: demand);
    final known = cachedAccount(id);
    if (known != null && demand.origin != null) return Future.value(known);
    final pending = _accounts[key];
    if (pending != null) return pending;
    final done = Completer<AccountConfiguration?>();
    _accounts[key] = done.future;
    unawaited(
      lifetime
          .run('configuration:account', () async {
            final binding = await bind(demand);
            final chain = ConfigurationReadChain(
              binding.target.origin,
              binding.collection,
              orderStableForValueChanges: true,
            );
            _reads.add(chain);
            try {
              return await pin(binding.target).use((scope) async {
                final reference = await scope.lookupAccount(id);
                if (reference == null) {
                  if (_collection != binding.collection ||
                      source.value.projection.stamp?.origin !=
                          binding.target.origin)
                    throw configurationSuperseded;
                  return null;
                }
                final entity = await scope.entity(reference);
                if (entity.reference != reference)
                  throw configurationProtocol(
                    'An account lookup returned another reference.',
                  );
                final value = await ConfigurationReader(scope)
                    .account(entity.value);
                if (value.accountId != id)
                  throw configurationProtocol(
                    'An account lookup returned another identity.',
                  );
                if (lifetime.sealed) throw resourceCancelled;
                if (chain.entity(
                      reference,
                      source.value.projection.stamp!.origin,
                      _collection,
                    ) !=
                    reference)
                  throw configurationSuperseded;
                final window = _window(binding.target.origin, _collection!);
                source.publish(
                  source.value.copyWith(
                    accounts: CollectionMirror.current(
                      window: window.copyWith(
                        rows: {
                          ...window.rows,
                          reference.entry: ReadValue.ready(
                            current: Materialized(
                              origin: binding.target.origin,
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
            } finally {
              _reads.remove(chain);
            }
          })
          .then(
            (value) {
              unawaited(_accounts.remove(key));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_accounts.remove(key));
              done.completeError(configurationFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  AccountConfiguration? cachedAccount(String id) {
    final state = source.value;
    if (state.projection.sync.phase != ResourceSyncPhase.ready ||
        state.projection.header?.reference == null ||
        state.accounts is! CurrentCollectionMirror<AccountConfiguration>)
      return null;
    final window =
        (state.accounts as CurrentCollectionMirror<AccountConfiguration>)
            .window;
    if (window.origin != state.projection.stamp?.origin) return null;
    for (final row in window.rows.values) {
      if (row is ReadyReadValue<AccountConfiguration, ProductEntityRef> &&
          row.current.value.accountId == id)
        return row.current.value;
    }
    return null;
  }

  Future<
    ({ProductReadOrigin origin, int revision, AccountConfiguration? account})
  >
  accountBase(String id) async {
    final binding = await bind(capture());
    final value = await account(id);
    if (!current(binding.target) ||
        source.value.projection.sync.phase != ResourceSyncPhase.ready ||
        _collection != binding.collection)
      throw configurationSuperseded;
    return (
      origin: binding.target.origin,
      revision: binding.revision,
      account: value,
    );
  }

  CollectionWindow<AccountConfiguration> _window(
    ProductReadOrigin origin,
    ProductCollectionRef collection,
  ) {
    if (source.value.projection.stamp?.origin != origin ||
        _collection != collection)
      throw configurationSuperseded;
    final mirror = source.value.accounts;
    if (mirror is CurrentCollectionMirror<AccountConfiguration> &&
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

  Future<void> page({int limit = 32}) {
    lifetime.admit();
    if (limit < 1 || limit > 100)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'An account page limit must be between 1 and 100.',
        retryable: false,
        correlationId: 'configuration',
      );
    final demand = capture();
    final mirror = source.value.accounts;
    if (source.value.projection.sync.phase == ResourceSyncPhase.ready &&
        mirror is CurrentCollectionMirror<AccountConfiguration> &&
        mirror.window.complete &&
        mirror.window.error == null)
      return Future.value();
    final continuation =
        mirror is CurrentCollectionMirror<AccountConfiguration> &&
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
          .run('configuration:accounts-page', () async {
            final binding = await bind(demand);
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
              orderStableForValueChanges: true,
            );
            _reads.add(chain);
            source.publish(
              source.value.copyWith(
                accounts: CollectionMirror.current(
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
                  throw configurationProtocol(
                    'An account index page does not match its frozen collection.',
                  );
                final loaded =
                    <int, ReadValue<AccountConfiguration, ProductEntityRef>>{};
                StudioFailure? failure;
                for (final reference in page.items) {
                  if (loaded.containsKey(reference.entry))
                    throw configurationProtocol(
                      'An account index page repeated an entry.',
                    );
                  final old = window.rows[reference.entry];
                  if (old
                          is ReadyReadValue<
                            AccountConfiguration,
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
                        'An account entity returned another reference.',
                      );
                    final value = await ConfigurationReader(scope)
                        .account(entity.value);
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
                final current = source.value.accounts;
                if (generation != _pageGeneration ||
                    !identical(_pages[key], done.future) ||
                    source.value.projection.stamp?.origin !=
                        binding.target.origin ||
                    _collection != binding.collection ||
                    current is! CurrentCollectionMirror<AccountConfiguration> ||
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
                final rows =
                    Map<
                      int,
                      ReadValue<AccountConfiguration, ProductEntityRef>
                    >.of(latest.rows);
                for (var index = 0; index < entries.length; index++) {
                  final reference = entries[index];
                  final value = loaded[reference.entry]!;
                  if (reference != page.items[index]) {
                    failure ??= configurationSuperseded;
                    rows[reference.entry] = ReadValue.failed(
                      origin: binding.target.origin,
                      reference: reference,
                      error: configurationSuperseded,
                      previous: configurationPrevious(value),
                    );
                  } else {
                    rows[reference.entry] = value;
                  }
                }
                final prefix = latest.entries.take(offset).toList();
                if (prefix.length != offset ||
                    prefix.any(
                      (item) =>
                          entries.any((other) => other.entry == item.entry),
                    ))
                  throw configurationSuperseded;
                source.publish(
                  source.value.copyWith(
                    accounts: CollectionMirror.current(
                      window: latest.copyWith(
                        entries: [...prefix, ...entries],
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
              final latest = source.value.accounts;
              if (!lifetime.sealed &&
                  generation == _pageGeneration &&
                  identical(_pages[key], done.future) &&
                  source.value.projection.stamp?.origin ==
                      binding.target.origin &&
                  _collection == binding.collection &&
                  latest is CurrentCollectionMirror<AccountConfiguration> &&
                  latest.window.origin == binding.target.origin &&
                  latest.window.reference == binding.collection)
                source.publish(
                  source.value.copyWith(
                    accounts: CollectionMirror.current(
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
    ConfigurationReadTarget target, {
    CommitReceipt? receipt,
  }) {
    lifetime.admit();
    capture();
    return lifetime.run('configuration:command-target', () async {
      if (source.value.projection.sync.phase == ResourceSyncPhase.ready &&
          source.value.projection.stamp?.origin != target.origin) {
        await pin(target).use((scope) async {
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
            .where((stamp) => stamp.resourceKey == 'settings')
            .toList();
        if (targets.length != 1 ||
            targets.single.ownerEpoch != target.origin.ownerEpoch)
          throw configurationProtocol(
            'The Settings receipt has inconsistent source targets.',
          );
        final revision = value.projection.header?.configurationRevision;
        return revision != null && revision >= targets.single.revision;
      });
    });
  }
}
