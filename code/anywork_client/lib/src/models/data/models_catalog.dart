import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/model_values.dart';
import '../domain/models_state.dart';
import 'model_reader.dart';
import 'models_collection.dart';
import 'models_frames.dart';
import 'models_port.dart';
import 'models_status_reader.dart';

final class ModelsCatalog {
  ModelsCatalog(this.port, this.lifetime)
    : state = ResourceSource(
        ModelsState(
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
          webSearch: null,
          deepSeekSearch: null,
        ),
        lifetime.budget,
        'models:catalog-observer',
      ) {
    lifetime.onSeal(state.seal);
  }

  final ModelsPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<ModelsState> state;
  ProductFeedOwner<ModelCatalogFrame>? _feed;
  ProductProjectionStamp? _feedStamp;
  ProductCollectionRef? _collection;
  final Map<ModelCatalogReadTarget, PinnedReadOwner<ModelCatalogReadConnection>>
  _scopes = {};
  final Set<ModelCollectionRead> _reads = {};
  final Map<
    ({String accountId, _CatalogDemand demand}),
    Future<AccountCatalogEntry>
  >
  _accounts = {};
  final Map<
    ({AccountModelKey model, _CatalogDemand demand}),
    Future<ModelDescriptor>
  >
  _models = {};
  final Map<ModelCatalogReadTarget, Future<void>> _targets = {};
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    PinnedReadOwner<ProductSourceStatusReadConnection>
  >
  _statusScopes = {};
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    Future<void>
  >
  _statusTasks = {};
  ({ProductReadOrigin origin, ProductSourceStatusRef reference})?
  _statusAttempted;
  final Map<
    ({_CatalogDemand demand, CollectionContinuation? continuation, int limit}),
    Future<void>
  >
  _pages = {};
  int _pageGeneration = 0;
  Future<void>? _restart;
  ProductFeedOwner<ModelCatalogFrame>? _retiringFeed;
  Object? _opening;
  final Map<ProductFeedOwner<ModelCatalogFrame>, Future<void>>
  _deferredRestarts = {};
  final Map<_CatalogDemand, Future<EffectiveWebSearch>> _webReads = {};
  final Map<_CatalogDemand, Future<EffectiveDeepSeekSearch>> _deepReads = {};
  final Map<
    ({
      ModelCatalogReadTarget catalog,
      AccountModelKey model,
      String? candidate,
    }),
    Future<String?>
  >
  _effortSelections = {};
  final Map<ModelCatalogReadTarget, Future<ModelSelection?>>
  _firstTextSelections = {};

  /// Pure original-version queries. Native owns both effort policy and the
  /// complete catalog's ordering/eligibility; no latest feed is substituted.
  Future<String?> effortAfterModelSelection({
    required ModelCatalogReadTarget catalog,
    required AccountModelKey model,
    required String? candidate,
  }) {
    lifetime.admit();
    final key = (catalog: catalog, model: model, candidate: candidate);
    final pending = _effortSelections[key];
    if (pending != null) return pending;
    final done = Completer<String?>();
    _effortSelections[key] = done.future;
    unawaited(
      Future<String?>.sync(
        () => lifetime.run('models:effort-selection', () async {
          final value = await _scope(key.catalog).use(
            (scope) => scope.effortAfterModelSelection(
              key.model.accountId,
              key.model.modelId,
              candidate: key.candidate,
            ),
          );
          if (lifetime.sealed) throw resourceCancelled;
          return value;
        }),
      ).then(
        (value) {
          unawaited(_effortSelections.remove(key));
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          unawaited(_effortSelections.remove(key));
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  Future<ModelSelection?> firstTextModel({
    required ModelCatalogReadTarget catalog,
  }) {
    lifetime.admit();
    final target = catalog;
    final pending = _firstTextSelections[target];
    if (pending != null) return pending;
    final done = Completer<ModelSelection?>();
    _firstTextSelections[target] = done.future;
    unawaited(
      Future<ModelSelection?>.sync(
        () => lifetime.run('models:first-text-model', () async {
          final value = await _scope(target)
              .use((scope) => scope.firstTextModel());
          if (lifetime.sealed) throw resourceCancelled;
          return value;
        }),
      ).then(
        (value) {
          unawaited(_firstTextSelections.remove(target));
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          unawaited(_firstTextSelections.remove(target));
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  _CatalogDemand _demand() {
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
    } else if (_feed!.closing && _restart == null) {
      unawaited(_resync(_feed!, retryCleanup: true));
    }
    lifetime.admit();
    final projection = state.value.projection;
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

  void _checkDemand(
    _CatalogDemand demand,
    ModelCatalogReadTarget target,
    ProductCollectionRef collection,
  ) {
    if (demand.reference != null &&
            (demand.origin != target.origin ||
                demand.reference != target.reference ||
                demand.collection != collection) ||
        demand.opening != null && !identical(demand.opening, _opening))
      throw modelsSuperseded;
  }

  PinnedReadOwner<ModelCatalogReadConnection> _scope(
    ModelCatalogReadTarget target,
  ) {
    final prior = _scopes[target];
    if (prior != null && prior.accepting) return prior;
    final scope = PinnedReadOwner<ModelCatalogReadConnection>(
      lifetime: lifetime,
      owner: 'models:catalog-read',
      open: () =>
          port.openModelCatalogRead(target.reference, origin: target.origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
    _scopes[target] = scope;
    return scope;
  }

  void _start({Object? opening}) {
    if (lifetime.sealed) return;
    _feedStamp = null;
    late final ProductFeedOwner<ModelCatalogFrame> feed;
    feed = ProductFeedOwner<ModelCatalogFrame>(
      lifetime: lifetime,
      owner: 'models:catalog-feed',
      open: port.openModelCatalog,
      sequence: (frame) =>
          frame is ModelCatalogData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed)
          return frame is ModelCatalogData ? frame.deliverySequence : null;
        switch (frame) {
          case ModelCatalogData(:final deliverySequence, :final event):
            switch (event) {
              case ModelCatalogBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.modelCatalog ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation)
                  throw resourceProtocol(
                    'The catalog baseline identity is inconsistent.',
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
              case ModelCatalogChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_feedStamp == null ||
                    _feedStamp!.origin != stamp.origin ||
                    baseRevision != _feedStamp!.revision ||
                    stamp.revision <= baseRevision)
                  throw resourceProtocol(
                    'The catalog projection has a revision gap.',
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
          case ModelCatalogResyncRequired(:final identity):
            _checkControl(identity);
            unawaited(_resync(feed));
          case ModelCatalogFeedFailure(:final identity, :final error):
            _checkControl(identity);
            _failed(feed, error);
          case ModelCatalogClosed(:final identity, :final reason):
            _checkControl(identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              unawaited(_resync(feed));
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.unavailable,
                  message: 'The catalog feed closed.',
                  retryable: true,
                  correlationId: 'models-catalog',
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

  void _checkControl(ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.modelCatalog ||
        _feedStamp != null && identity.ownerEpoch != _feedStamp!.ownerEpoch ||
        _feedStamp != null && identity.incarnation != _feedStamp!.incarnation)
      throw resourceProtocol(
        'A catalog control frame belongs to another source.',
      );
    _feed!.bindIdentity(identity);
  }

  void _sync(ResourceSyncPhase phase, [StudioFailure? error]) => state.publish(
    state.value.copyWith(
      projection: state.value.projection.copyWith(
        sync: ResourceSyncState(
          phase: phase,
          error: error,
          retryExhausted: false,
        ),
      ),
    ),
  );

  void _failed(ProductFeedOwner<ModelCatalogFrame> feed, StudioFailure error) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _sync(ResourceSyncPhase.failed, error);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  Future<void> _resync(
    ProductFeedOwner<ModelCatalogFrame> feed, {
    bool retryCleanup = false,
    Object? opening,
  }) {
    final deferred = _deferredRestarts[feed];
    if (deferred != null) return deferred;
    final prior = _restart;
    if (prior != null) {
      if (identical(_retiringFeed, feed)) return prior;
      final queued = Completer<void>();
      _deferredRestarts[feed] = queued.future;
      final token = opening ?? queued.future;
      _opening = token;
      feed.requestClose();
      unawaited(
        Future<void>.sync(
          () => lifetime.run('models:deferred-catalog-resync', () async {
            await prior;
            unawaited(_deferredRestarts.remove(feed));
            if (!lifetime.sealed && identical(_feed, feed))
              await _resync(feed, retryCleanup: retryCleanup, opening: token);
          }),
        ).then(
          (_) => queued.complete(),
          onError: (Object error, StackTrace stack) {
            unawaited(_deferredRestarts.remove(feed));
            queued.completeError(error, stack);
          },
        ),
      );
      unawaited(
        queued.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      );
      return queued.future;
    }
    final done = Completer<void>();
    _restart = done.future;
    _retiringFeed = feed;
    final token = opening ?? done.future;
    _opening = token;
    _sync(ResourceSyncPhase.reconnecting);
    feed.requestClose();
    unawaited(
      Future<void>.sync(
        () => lifetime.run('models:catalog-resync', () async {
          await feed.cleanup(retry: retryCleanup);
          if (!lifetime.sealed && identical(_feed, feed)) {
            if (!feed.released)
              throw const StudioFailure(
                code: StudioFailureCode.busy,
                message: 'The prior catalog feed has unresolved cleanup.',
                retryable: true,
                correlationId: 'models-catalog',
              );
            _start(opening: token);
          }
        }),
      ).then(
        (_) {
          _restart = null;
          _retiringFeed = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          _restart = null;
          _retiringFeed = null;
          if (!lifetime.sealed)
            _sync(ResourceSyncPhase.failed, resourceFailure(error));
          done.completeError(error, stack);
        },
      ),
    );
    // Resync may be driven by a control frame without an awaiting UI caller.
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }

  void _adopt(
    ProductProjectionStamp stamp,
    ModelCatalogHeader header,
    ProductCollectionRef? collection,
    int? baseCollection,
    List<ProductEntityRef> upserted,
    List<int> removed, {
    required bool baseline,
  }) {
    final old = state.value;
    if (stamp.revision < 0 ||
        stamp.incarnation < 0 ||
        (header.reference == null) != (collection == null) ||
        (header.catalogRevision == null) != (collection == null) ||
        (header.updatedAt == null) != (collection == null))
      throw resourceProtocol(
        'The catalog header has inconsistent value availability.',
      );
    final source = header.source.brief;
    final hasValue =
        source is ReadyObservedBrief ||
        source is RefreshingObservedBrief ||
        source is StaleObservedBrief ||
        source is DegradedObservedBrief;
    if (hasValue != (collection != null))
      throw resourceProtocol(
        'The catalog source status does not match value availability.',
      );
    final current = old.projection.stamp;
    if (current != null &&
        current.origin == stamp.origin &&
        current.revision > stamp.revision)
      return;
    if (!baseline && baseCollection != _collection?.revision)
      throw resourceProtocol(
        'The catalog collection source clock has a revision gap.',
      );
    for (final read in _reads) {
      read.changed(stamp.origin, baseCollection, collection, upserted, removed);
    }
    final mirror = baseline
        ? modelCollectionBaseline(old.accounts, stamp.origin, collection)
        : modelCollectionChange(
            old.accounts,
            stamp.origin,
            baseCollection,
            collection,
            upserted,
            removed,
          );
    _collection = collection;
    final target = header.reference == null
        ? null
        : ModelCatalogReadTarget(
            origin: stamp.origin,
            reference: header.reference!,
          );
    for (final entry in List.of(_scopes.entries)) {
      if (entry.key != target) {
        entry.value.retire();
        _scopes.remove(entry.key);
      }
    }
    for (final entry in List.of(_statusScopes.entries)) {
      if (entry.key.origin != stamp.origin ||
          entry.key.reference != header.source.status) {
        entry.value.retire();
        _statusScopes.remove(entry.key);
      }
    }
    state.publish(
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
        accounts: mirror,
        sourceStatus: _readValue(
          old.sourceStatus,
          stamp.origin,
          header.source.status,
        ),
        webSearch: target == null
            ? _unavailable(old.webSearch)
            : _readValue(old.webSearch, target.origin, target.reference),
        deepSeekSearch: target == null
            ? _unavailable(old.deepSeekSearch)
            : _readValue(old.deepSeekSearch, target.origin, target.reference),
      ),
    );
    if (state.observerCount != 0 && header.source.brief is! ReadyObservedBrief)
      _demandStatus();
  }

  void _demandStatus({bool retry = false}) {
    if (lifetime.sealed) return;
    final snapshot = state.value;
    final origin = snapshot.projection.stamp?.origin;
    final source = snapshot.projection.header?.source;
    if (origin == null || source == null) return;
    unawaited(
      _readStatus(
        origin,
        source,
        retry: retry,
      ).then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  Future<void> _readStatus(
    ProductReadOrigin origin,
    ObservedHeader source, {
    bool retry = false,
  }) {
    lifetime.admit();
    final snapshot = state.value;
    final target = (origin: origin, reference: source.status);
    final pending = _statusTasks[target];
    if (pending != null) return pending;
    if (_statusAttempted == target &&
        !(retry &&
            snapshot.sourceStatus
                is FailedReadValue<
                  ProductSourceStatus,
                  ProductSourceStatusRef
                >))
      return Future.value();
    _statusAttempted = target;
    final done = Completer<void>();
    _statusTasks[target] = done.future;
    unawaited(
      lifetime
          .run('models:source-status', () async {
            state.publish(
              state.value.copyWith(
                sourceStatus: ReadValue.loading(
                  origin: origin,
                  reference: source.status,
                  previous: modelPrevious(state.value.sourceStatus),
                ),
              ),
            );
            final scope = _statusScopes.putIfAbsent(
              target,
              () => PinnedReadOwner<ProductSourceStatusReadConnection>(
                lifetime: lifetime,
                owner: 'models:source-status-read',
                open: () => port.openSourceStatus(
                  target.reference,
                  origin: target.origin,
                ),
                request: (scope) => scope.requestClose(),
                closeNative: (scope) => scope.close(),
                retryNative: (scope) => scope.retryClose(),
              ),
            );
            final value = await scope.use(readModelsSourceStatus);
            if (modelsStatusBrief(value) != source.brief)
              throw resourceProtocol(
                'The source metadata disagrees with the published catalog brief.',
              );
            if (lifetime.sealed) throw resourceCancelled;
            if (state.value.projection.stamp?.origin != origin ||
                state.value.projection.header?.source.status != source.status)
              throw modelsSuperseded;
            state.publish(
              state.value.copyWith(
                sourceStatus: ReadValue.ready(
                  current: Materialized(
                    origin: origin,
                    reference: source.status,
                    value: value,
                  ),
                ),
              ),
            );
          })
          .then(
            (_) {
              unawaited(_statusTasks.remove(target));
              done.complete();
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_statusTasks.remove(target));
              if (!lifetime.sealed &&
                  state.value.projection.stamp?.origin == origin &&
                  state.value.projection.header?.source.status == source.status)
                state.publish(
                  state.value.copyWith(
                    sourceStatus: ReadValue.failed(
                      origin: origin,
                      reference: source.status,
                      error: resourceFailure(error),
                      previous: modelPrevious(state.value.sourceStatus),
                    ),
                  ),
                );
              done.completeError(resourceFailure(error), stack);
            },
          ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }

  Future<void> loadSourceStatus() {
    lifetime.admit();
    final demand = _demand();
    final current = state.value;
    if (current.projection.sync.phase == ResourceSyncPhase.ready &&
        current.projection.header != null)
      return _readStatus(
        current.projection.stamp!.origin,
        current.projection.header!.source,
        retry: true,
      );
    return lifetime.run('models:explicit-source-status', () async {
      ModelsState? original;
      await state.waitFor((value) {
        if (value.projection.sync.phase == ResourceSyncPhase.failed)
          throw value.projection.sync.error!;
        if (value.projection.sync.phase != ResourceSyncPhase.ready)
          return false;
        original = value;
        return true;
      });
      if (demand.opening != null && !identical(demand.opening, _opening))
        throw modelsSuperseded;
      await _readStatus(
        original!.projection.stamp!.origin,
        original!.projection.header!.source,
        retry: true,
      );
    });
  }

  Future<EffectiveWebSearch> loadWebSearch() => _policy(
    _webReads,
    (value) => value.webSearch,
    (value, read) => value.copyWith(webSearch: read),
    (scope) async {
      final header = await scope.header();
      final value = header.webSearch;
      final access = ModelReadAccess.catalog(scope);
      return EffectiveWebSearch(
        effectiveMode: await access.string(value.effectiveMode),
        availability: await access.string(value.availability),
        accountId: await access.optional(value.accountId),
        modelId: await access.optional(value.modelId),
      );
    },
  );

  Future<EffectiveDeepSeekSearch> loadDeepSeekSearch() => _policy(
    _deepReads,
    (value) => value.deepSeekSearch,
    (value, read) => value.copyWith(deepSeekSearch: read),
    (scope) async {
      final header = await scope.header();
      final value = header.deepseekWebSearch;
      final access = ModelReadAccess.catalog(scope);
      return EffectiveDeepSeekSearch(
        effectiveEnabled: value.effectiveEnabled,
        effectiveFetchEnabled: value.effectiveFetchEnabled,
        availability: await access.string(value.availability),
        accountId: await access.optional(value.accountId),
      );
    },
  );

  Future<T> _policy<T>(
    Map<_CatalogDemand, Future<T>> pending,
    ReadValue<T, ModelCatalogReadRef>? Function(ModelsState) current,
    ModelsState Function(ModelsState, ReadValue<T, ModelCatalogReadRef>) update,
    Future<T> Function(ModelCatalogReadConnection) read,
  ) {
    lifetime.admit();
    final demand = _demand();
    final known = current(state.value);
    if (known is ReadyReadValue<T, ModelCatalogReadRef> &&
        known.current.origin == demand.origin &&
        known.current.reference == demand.reference)
      return Future.value(known.current.value);
    final inFlight = pending[demand];
    if (inFlight != null) return inFlight;
    final done = Completer<T>();
    pending[demand] = done.future;
    unawaited(
      lifetime
          .run('models:effective-policy', () async {
            final binding = await _ready();
            _checkDemand(demand, binding.target, binding.collection);
            final target = binding.target;
            state.publish(
              update(
                state.value,
                ReadValue.loading(
                  origin: target.origin,
                  reference: target.reference,
                  previous: modelPrevious(current(state.value)),
                ),
              ),
            );
            try {
              final value = await _scope(target).use(read);
              if (lifetime.sealed) throw resourceCancelled;
              if (state.value.projection.stamp?.origin != target.origin ||
                  state.value.projection.header?.reference != target.reference)
                throw modelsSuperseded;
              state.publish(
                update(
                  state.value,
                  ReadValue.ready(
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
              if (!lifetime.sealed &&
                  state.value.projection.stamp?.origin == target.origin &&
                  state.value.projection.header?.reference == target.reference)
                state.publish(
                  update(
                    state.value,
                    ReadValue.failed(
                      origin: target.origin,
                      reference: target.reference,
                      error: resourceFailure(error),
                      previous: modelPrevious(current(state.value)),
                    ),
                  ),
                );
              rethrow;
            }
          })
          .then(
            (value) {
              unawaited(pending.remove(demand));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(pending.remove(demand));
              done.completeError(resourceFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  Future<({ModelCatalogReadTarget target, ProductCollectionRef collection})>
  _ready() async {
    lifetime.admit();
    final pendingRestart = _restart;
    if (pendingRestart != null) await pendingRestart;
    if (_feed == null) {
      _start();
    } else if (_feed!.closing) {
      await _resync(_feed!, retryCleanup: true);
    }
    ({ModelCatalogReadTarget target, ProductCollectionRef collection})? binding;
    await state.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed)
        throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      final reference = value.projection.header?.reference;
      final collection = _collection;
      if (reference == null || collection == null)
        throw const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'The catalog source has no current business value.',
          retryable: true,
          correlationId: 'models-catalog',
        );
      binding = (
        target: ModelCatalogReadTarget(
          origin: value.projection.stamp!.origin,
          reference: reference,
        ),
        collection: collection,
      );
      return true;
    });
    return binding!;
  }

  Future<void> loadAccountsPage({int limit = 32}) {
    lifetime.admit();
    if (limit < 1 || limit > 100)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A model page limit must be between 1 and 100.',
        retryable: false,
        correlationId: 'models-page',
      );
    _demandStatus(retry: true);
    final demand = _demand();
    final current = state.value.accounts;
    if (state.value.projection.sync.phase == ResourceSyncPhase.ready &&
        current is CurrentCollectionMirror<AccountCatalogEntry> &&
        current.window.origin == demand.origin &&
        current.window.reference == demand.collection &&
        _accountPageOffset(current.window) == null)
      return Future.value();
    final continuation =
        current is CurrentCollectionMirror<AccountCatalogEntry> &&
            current.window.origin == demand.origin &&
            current.window.reference == demand.collection
        ? current.window.continuation
        : null;
    final key = (demand: demand, continuation: continuation, limit: limit);
    final pending = _pages[key];
    if (pending != null) return pending;
    final done = Completer<void>();
    _pages[key] = done.future;
    final generation = ++_pageGeneration;
    unawaited(
      lifetime
          .run('models:accounts-page', () async {
            final binding = await _ready();
            _checkDemand(demand, binding.target, binding.collection);
            if (_pageGeneration != generation ||
                !identical(_pages[key], done.future))
              throw modelsSuperseded;
            if (_collection != binding.collection ||
                state.value.projection.stamp?.origin != binding.target.origin)
              throw modelsSuperseded;
            final window = _currentWindow(
              binding.target.origin,
              binding.collection,
            );
            final offset = _accountPageOffset(window);
            if (offset == null) return;
            final read = ModelCollectionRead(
              binding.target.origin,
              binding.collection,
            );
            _reads.add(read);
            state.publish(
              state.value.copyWith(
                accounts: CollectionMirror.current(
                  window: window.copyWith(loading: true, error: null),
                ),
              ),
            );
            try {
              await _scope(binding.target).use((scope) async {
                final page = await scope.entries(offset: offset, limit: limit);
                final end = offset + page.items.length;
                if (page.collection != binding.collection ||
                    page.offset != offset ||
                    page.items.length > limit ||
                    end < offset ||
                    end > binding.collection.total ||
                    page.items.map((item) => item.entry).toSet().length !=
                        page.items.length ||
                    page.nextOffset !=
                        (end == binding.collection.total ? null : end) ||
                    end < binding.collection.total && page.items.isEmpty)
                  throw resourceProtocol(
                    'The catalog index page does not match its frozen collection.',
                  );
                final rows =
                    <int, ReadValue<AccountCatalogEntry, ProductEntityRef>>{};
                StudioFailure? failure;
                for (final reference in page.items) {
                  final prior = window.rows[reference.entry];
                  if (prior
                          is ReadyReadValue<
                            AccountCatalogEntry,
                            ProductEntityRef
                          > &&
                      prior.current.origin == binding.target.origin &&
                      prior.current.reference == reference) {
                    rows[reference.entry] = prior;
                    continue;
                  }
                  try {
                    final entity = await scope.entity(reference);
                    if (entity.reference != reference)
                      throw resourceProtocol(
                        'A catalog entity returned another reference.',
                      );
                    final value = await ModelReadAccess.catalog(scope)
                        .account(entity.value);
                    rows[reference.entry] = ReadValue.ready(
                      current: Materialized(
                        origin: binding.target.origin,
                        reference: reference,
                        value: value,
                      ),
                    );
                  } catch (error) {
                    failure ??= resourceFailure(error);
                    rows[reference.entry] = ReadValue.failed(
                      origin: binding.target.origin,
                      reference: reference,
                      error: resourceFailure(error),
                      previous: modelPrevious(prior),
                    );
                  }
                }
                if (lifetime.sealed) throw resourceCancelled;
                final current = state.value.accounts;
                if (_pageGeneration != generation ||
                    !identical(_pages[key], done.future) ||
                    state.value.projection.stamp?.origin !=
                        binding.target.origin ||
                    _collection != binding.collection ||
                    current is! CurrentCollectionMirror<AccountCatalogEntry> ||
                    current.window.origin != binding.target.origin ||
                    current.window.reference != binding.collection)
                  throw modelsSuperseded;
                final refs = read.page(
                  page.items,
                  binding.target.origin,
                  binding.collection,
                );
                final latest = _currentWindow(
                  binding.target.origin,
                  binding.collection,
                );
                final nextRows =
                    Map<
                      int,
                      ReadValue<AccountCatalogEntry, ProductEntityRef>
                    >.of(latest.rows);
                for (var index = 0; index < refs.length; index++) {
                  final reference = refs[index];
                  final loaded = rows[reference.entry]!;
                  if (reference != page.items[index]) {
                    failure ??= modelsSuperseded;
                    nextRows[reference.entry] = ReadValue.failed(
                      origin: binding.target.origin,
                      reference: reference,
                      error: modelsSuperseded,
                      previous: modelPrevious(loaded),
                    );
                  } else {
                    nextRows[reference.entry] = loaded;
                  }
                }
                final prefix = latest.entries.take(offset).toList();
                if (prefix.length != offset ||
                    prefix.any(
                      (item) => refs.any((other) => item.entry == other.entry),
                    ))
                  throw modelsSuperseded;
                state.publish(
                  state.value.copyWith(
                    accounts: CollectionMirror.current(
                      window: latest.copyWith(
                        entries: [...prefix, ...refs],
                        rows: nextRows,
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
              if (!lifetime.sealed &&
                  _pageGeneration == generation &&
                  identical(_pages[key], done.future) &&
                  state.value.projection.stamp?.origin ==
                      binding.target.origin &&
                  _collection == binding.collection) {
                final latest = state.value.accounts;
                if (latest is CurrentCollectionMirror<AccountCatalogEntry> &&
                    latest.window.origin == binding.target.origin &&
                    latest.window.reference == binding.collection)
                  state.publish(
                    state.value.copyWith(
                      accounts: CollectionMirror.current(
                        window: latest.window.copyWith(
                          loading: false,
                          error: resourceFailure(error),
                        ),
                      ),
                    ),
                  );
              }
              rethrow;
            } finally {
              _reads.remove(read);
            }
          })
          .then(
            (_) {
              unawaited(_pages.remove(key));
              done.complete();
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_pages.remove(key));
              done.completeError(resourceFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  int? _accountPageOffset(CollectionWindow<AccountCatalogEntry> window) {
    // A complete index can still contain superseded/failed entity material.
    // Retry from its first non-current row instead of treating End as ready.
    for (var index = 0; index < window.entries.length; index++) {
      final reference = window.entries[index];
      final row = window.rows[reference.entry];
      if (row is! ReadyReadValue<AccountCatalogEntry, ProductEntityRef> ||
          row.current.origin != window.origin ||
          row.current.reference != reference)
        return index;
    }
    if (window.complete && window.error == null) return null;
    return switch (window.continuation) {
      OffsetCollectionContinuation(:final value) => value,
      EndCollectionContinuation() => window.reference.total,
      _ => 0,
    };
  }

  Future<void> synchronize(ModelCatalogReadTarget target) {
    lifetime.admit();
    final current = state.value.projection;
    final reference = current.header?.reference;
    if (current.sync.phase == ResourceSyncPhase.ready &&
        current.stamp?.origin == target.origin &&
        reference != null) {
      if (reference.entry == target.reference.entry &&
          reference.revision >= target.reference.revision)
        return Future.value();
    }
    final pending = _targets[target];
    if (pending != null) return pending;
    final done = Completer<void>();
    _targets[target] = done.future;
    unawaited(
      lifetime
          .run('models:command-target', () async {
            // Opening this exact native target confirms its source without loading any
            // account/model body or borrowing an origin from the latest feed.
            await _scope(target).use((scope) async {
              await scope.header();
            });
            if (_feed == null) {
              _start();
            } else if (_feed!.closing ||
                state.value.projection.stamp?.origin != target.origin) {
              await _resync(_feed!);
            }
            await state.waitFor((value) {
              if (value.projection.sync.phase == ResourceSyncPhase.failed)
                throw value.projection.sync.error!;
              if (value.projection.sync.phase != ResourceSyncPhase.ready)
                return false;
              if (value.projection.stamp?.origin != target.origin)
                throw modelsSuperseded;
              final reference = value.projection.header?.reference;
              return reference != null &&
                  reference.entry == target.reference.entry &&
                  reference.revision >= target.reference.revision;
            });
          })
          .then(
            (_) {
              unawaited(_targets.remove(target));
              done.complete();
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_targets.remove(target));
              done.completeError(resourceFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  Future<AccountCatalogEntry> loadAccount(String accountId) {
    lifetime.admit();
    _demandStatus(retry: true);
    final key = (accountId: accountId, demand: _demand());
    final existing = _accounts[key];
    if (existing != null) return existing;
    final ready = state.value.accounts;
    if (state.value.projection.sync.phase == ResourceSyncPhase.ready &&
        state.value.projection.header?.reference != null &&
        ready is CurrentCollectionMirror<AccountCatalogEntry> &&
        ready.window.origin == state.value.projection.stamp?.origin) {
      for (final row in ready.window.rows.values) {
        if (row is ReadyReadValue<AccountCatalogEntry, ProductEntityRef> &&
            row.current.value.accountId == accountId)
          return Future.value(row.current.value);
      }
    }
    final done = Completer<AccountCatalogEntry>();
    _accounts[key] = done.future;
    unawaited(
      lifetime
          .run('models:account', () async {
            final binding = await _ready();
            _checkDemand(key.demand, binding.target, binding.collection);
            final read = ModelCollectionRead(
              binding.target.origin,
              binding.collection,
            );
            _reads.add(read);
            try {
              return await _scope(binding.target).use((scope) async {
                final reference = await scope.lookupAccount(accountId);
                if (reference == null) {
                  if (_collection != binding.collection ||
                      state.value.projection.stamp?.origin !=
                          binding.target.origin)
                    throw modelsSuperseded;
                  throw _notFound;
                }
                final entity = await scope.entity(reference);
                if (entity.reference != reference)
                  throw resourceProtocol(
                    'The account entity response has a different reference.',
                  );
                final value = await ModelReadAccess.catalog(scope)
                    .account(entity.value);
                if (value.accountId != accountId)
                  throw resourceProtocol(
                    'The account lookup returned a different identity.',
                  );
                final current = read.currentEntity(
                  reference,
                  state.value.projection.stamp!.origin,
                  _collection,
                );
                if (current != reference) throw modelsSuperseded;
                _row(binding.target.origin, reference, value);
                return value;
              });
            } finally {
              _reads.remove(read);
            }
          })
          .then(
            (value) {
              unawaited(_accounts.remove(key));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_accounts.remove(key));
              done.completeError(resourceFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  Future<ModelDescriptor> loadModel(String accountId, String modelId) {
    lifetime.admit();
    _demandStatus(retry: true);
    final key = (
      model: AccountModelKey(accountId: accountId, modelId: modelId),
      demand: _demand(),
    );
    final existing = _models[key];
    if (existing != null) return existing;
    final done = Completer<ModelDescriptor>();
    _models[key] = done.future;
    unawaited(
      lifetime
          .run('models:model', () async {
            final binding = await _ready();
            _checkDemand(key.demand, binding.target, binding.collection);
            final read = ModelCollectionRead(
              binding.target.origin,
              binding.collection,
            );
            _reads.add(read);
            try {
              return await _scope(binding.target).use((scope) async {
                final reference = await scope.lookupAccount(accountId);
                if (reference == null) {
                  if (_collection != binding.collection ||
                      state.value.projection.stamp?.origin !=
                          binding.target.origin)
                    throw modelsSuperseded;
                  throw _notFound;
                }
                final entity = await scope.entity(reference);
                if (entity.reference != reference)
                  throw resourceProtocol(
                    'The model account reference changed in a pinned scope.',
                  );
                final access = ModelReadAccess.catalog(scope);
                if (await access.string(entity.value.accountId) != accountId)
                  throw resourceProtocol(
                    'The model account lookup returned a different identity.',
                  );
                var offset = 0;
                final list = entity.value.effectiveModels;
                while (offset < list.total) {
                  final page = await scope.models(
                    list.listId,
                    offset: offset,
                    limit: 32,
                  );
                  final end = offset + page.items.length;
                  if (page.listId != list.listId ||
                      page.offset != offset ||
                      page.total != list.total ||
                      page.items.isEmpty ||
                      page.items.length > 32 ||
                      end < offset ||
                      end > list.total ||
                      page.nextOffset != (end == list.total ? null : end))
                    throw resourceProtocol('The model page is not continuous.');
                  for (final item in page.items) {
                    if (await access.string(item.modelId) == modelId) {
                      final value = await access.model(item);
                      if (read.currentEntity(
                            reference,
                            state.value.projection.stamp!.origin,
                            _collection,
                          ) !=
                          reference)
                        throw modelsSuperseded;
                      return value;
                    }
                  }
                  offset = end;
                }
                if (read.currentEntity(
                      reference,
                      state.value.projection.stamp!.origin,
                      _collection,
                    ) !=
                    reference)
                  throw modelsSuperseded;
                throw _notFound;
              });
            } finally {
              _reads.remove(read);
            }
          })
          .then(
            (value) {
              unawaited(_models.remove(key));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_models.remove(key));
              done.completeError(resourceFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  void _row(
    ProductReadOrigin origin,
    ProductEntityRef reference,
    AccountCatalogEntry value,
  ) {
    if (state.value.projection.stamp?.origin != origin || _collection == null)
      throw modelsSuperseded;
    final window = _currentWindow(origin, _collection!);
    state.publish(
      state.value.copyWith(
        accounts: CollectionMirror.current(
          window: window.copyWith(
            rows: {
              ...window.rows,
              reference.entry: ReadValue.ready(
                current: Materialized(
                  origin: origin,
                  reference: reference,
                  value: value,
                ),
              ),
            },
          ),
        ),
      ),
    );
  }

  CollectionWindow<AccountCatalogEntry> _currentWindow(
    ProductReadOrigin origin,
    ProductCollectionRef collection,
  ) {
    if (state.value.projection.stamp?.origin != origin ||
        _collection != collection)
      throw modelsSuperseded;
    final mirror = state.value.accounts;
    if (mirror is CurrentCollectionMirror<AccountCatalogEntry> &&
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

  static const _notFound = StudioFailure(
    code: StudioFailureCode.notFound,
    message: 'The requested account model is unavailable; its identity was not replaced.',
    retryable: false,
    correlationId: 'models',
  );
}

typedef _CatalogDemand = ({
  ProductReadOrigin? origin,
  ModelCatalogReadRef? reference,
  ProductCollectionRef? collection,
  Object? opening,
});

ReadValue<T, R> _readValue<T, R>(
  ReadValue<T, R>? previous,
  ProductReadOrigin origin,
  R reference,
) {
  final known = modelPrevious(previous);
  if (known?.origin == origin &&
      known?.reference == reference &&
      previous != null)
    return previous;
  return known == null
      ? ReadValue.unloaded(origin: origin, reference: reference)
      : ReadValue.failed(
          origin: origin,
          reference: reference,
          error: modelsSuperseded,
          previous: known,
        );
}

ReadValue<T, R>? _unavailable<T, R>(ReadValue<T, R>? previous) {
  final known = modelPrevious(previous);
  if (known == null) return previous;
  return ReadValue.failed(
    origin: known.origin,
    reference: known.reference,
    error: const StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'The catalog source has no current value; the previous material is last-known only.',
      retryable: true,
      correlationId: 'models-catalog',
    ),
    previous: known,
  );
}
