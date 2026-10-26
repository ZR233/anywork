import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/models_state.dart';
import '../domain/template_values.dart';
import 'model_reader.dart';
import 'models_collection.dart';
import 'models_frames.dart';
import 'models_port.dart';
import 'template_reader.dart';
import 'template_reads.dart';

typedef _TemplatesDemand = ({
  ProductReadOrigin? origin,
  AccountTemplatesReadRef? reference,
  ProductCollectionRef? collection,
  Object? opening,
});

final class ModelsTemplates {
  ModelsTemplates(this.port, this.lifetime)
    : state = ResourceSource(
        TemplatesState(
          projection: const ProductProjection(
            stamp: null,
            header: null,
            sync: ResourceSyncState(
              phase: ResourceSyncPhase.idle,
              error: null,
              retryExhausted: false,
            ),
          ),
          templates: const CollectionMirror.unavailable(lastKnown: null),
          catalogs: null,
          catalogRevision: null,
        ),
        lifetime.budget,
        'models:templates-observer',
      ) {
    lifetime.onSeal(state.seal);
  }

  final ModelsPort port;
  final ResourceLifetime lifetime;
  final ResourceSource<TemplatesState> state;
  ProductFeedOwner<AccountTemplatesFrame>? _feed;
  ProductProjectionStamp? _feedStamp;
  ProductCollectionRef? _collection;
  final Map<
    AccountTemplatesReadTarget,
    PinnedReadOwner<AccountTemplatesReadConnection>
  >
  _scopes = {};
  Future<void>? _restart;
  Object? _opening;
  ProductFeedOwner<AccountTemplatesFrame>? _retiringFeed;
  final Map<ProductFeedOwner<AccountTemplatesFrame>, Future<void>>
  _deferredRestarts = {};
  final Map<_TemplatesDemand, Future<AccountTemplatesValue>> _loading = {};

  _TemplatesDemand _demand() {
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
        projection.header != null)
      return (
        origin: projection.stamp!.origin,
        reference: projection.header!.reference,
        collection: _collection,
        opening: null,
      );
    return (origin: null, reference: null, collection: null, opening: _opening);
  }

  PinnedReadOwner<AccountTemplatesReadConnection> _scope(
    AccountTemplatesReadTarget target,
  ) {
    final old = _scopes[target];
    if (old != null && old.accepting) return old;
    final result = PinnedReadOwner<AccountTemplatesReadConnection>(
      lifetime: lifetime,
      owner: 'models:templates-read',
      open: () => port.openAccountTemplatesRead(
        target.reference,
        origin: target.origin,
      ),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
    _scopes[target] = result;
    return result;
  }

  void _start({Object? opening}) {
    if (lifetime.sealed) return;
    _feedStamp = null;
    late final ProductFeedOwner<AccountTemplatesFrame> feed;
    feed = ProductFeedOwner<AccountTemplatesFrame>(
      lifetime: lifetime,
      owner: 'models:templates-feed',
      open: port.openAccountTemplates,
      sequence: (frame) =>
          frame is AccountTemplatesData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (!identical(_feed, feed) || lifetime.sealed)
          return frame is AccountTemplatesData ? frame.deliverySequence : null;
        switch (frame) {
          case AccountTemplatesData(:final deliverySequence, :final event):
            switch (event) {
              case AccountTemplatesBaselineEvent(
                :final identity,
                :final stamp,
                :final value,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.accountTemplates ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation)
                  throw resourceProtocol(
                    'The templates baseline identity is inconsistent.',
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
              case AccountTemplatesChangeEvent(
                :final stamp,
                :final baseRevision,
                :final value,
              ):
                if (_feedStamp == null ||
                    _feedStamp!.origin != stamp.origin ||
                    baseRevision != _feedStamp!.revision ||
                    stamp.revision <= baseRevision)
                  throw resourceProtocol(
                    'The templates projection has a revision gap.',
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
          case AccountTemplatesResyncRequired(:final identity):
            _control(identity);
            unawaited(_resync(feed));
          case AccountTemplatesFeedFailure(:final identity, :final error):
            _control(identity);
            _failed(feed, error);
          case AccountTemplatesClosed(:final identity, :final reason):
            _control(identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              unawaited(_resync(feed));
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.unavailable,
                  message: 'The templates feed closed.',
                  retryable: true,
                  correlationId: 'models-templates',
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
    if (identity.resource != ProductResource.accountTemplates ||
        _feedStamp != null && identity.ownerEpoch != _feedStamp!.ownerEpoch ||
        _feedStamp != null && identity.incarnation != _feedStamp!.incarnation)
      throw resourceProtocol(
        'A templates control frame belongs to another source.',
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

  void _failed(
    ProductFeedOwner<AccountTemplatesFrame> feed,
    StudioFailure error,
  ) {
    if (!identical(_feed, feed) || lifetime.sealed) return;
    _sync(ResourceSyncPhase.failed, error);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  Future<void> _resync(
    ProductFeedOwner<AccountTemplatesFrame> feed, {
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
          () => lifetime.run('models:deferred-templates-resync', () async {
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
        () => lifetime.run('models:templates-resync', () async {
          await feed.cleanup(retry: retryCleanup);
          if (!lifetime.sealed && identical(_feed, feed)) {
            if (!feed.released)
              throw const StudioFailure(
                code: StudioFailureCode.busy,
                message: 'The templates feed has unresolved cleanup.',
                retryable: true,
                correlationId: 'models-templates',
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
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }

  void _adopt(
    ProductProjectionStamp stamp,
    AccountTemplatesHeader header,
    ProductCollectionRef? collection,
    int? base,
    List<ProductEntityRef> upserted,
    List<int> removed, {
    required bool baseline,
  }) {
    if (collection == null ||
        stamp.revision < 0 ||
        stamp.incarnation < 0 ||
        header.schemaVersion < 0)
      throw resourceProtocol('The canonical templates collection is missing.');
    final old = state.value;
    if (old.projection.stamp?.origin == stamp.origin &&
        old.projection.stamp!.revision > stamp.revision)
      return;
    if (!baseline && base != _collection?.revision)
      throw resourceProtocol(
        'The templates collection source clock has a revision gap.',
      );
    final target = AccountTemplatesReadTarget(
      origin: stamp.origin,
      reference: header.reference,
    );
    _collection = collection;
    for (final item in List.of(_scopes.entries)) {
      if (item.key != target) {
        item.value.retire();
        _scopes.remove(item.key);
      }
    }
    var templates = baseline
        ? modelCollectionBaseline(old.templates, stamp.origin, collection)
        : modelCollectionChange(
            old.templates,
            stamp.origin,
            base,
            collection,
            upserted,
            removed,
          );
    if ((old.projection.stamp?.origin != target.origin ||
            old.projection.header?.reference != target.reference) &&
        templates is CurrentCollectionMirror<AccountTemplate>) {
      templates = CollectionMirror.current(
        window: templates.window.copyWith(loading: false),
      );
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
        templates: templates,
        catalogs: _next(old.catalogs, target),
        catalogRevision: _next(old.catalogRevision, target),
      ),
    );
  }

  ReadValue<T, AccountTemplatesReadRef> _next<T>(
    ReadValue<T, AccountTemplatesReadRef>? previous,
    AccountTemplatesReadTarget target,
  ) {
    final known = modelPrevious(previous);
    if (known?.origin == target.origin &&
        known?.reference == target.reference &&
        previous != null)
      return previous;
    return known == null
        ? ReadValue.unloaded(origin: target.origin, reference: target.reference)
        : ReadValue.failed(
            origin: target.origin,
            reference: target.reference,
            error: modelsSuperseded,
            previous: known,
          );
  }

  Future<
    ({
      AccountTemplatesReadTarget target,
      ProductCollectionRef collection,
      int schemaVersion,
    })
  >
  _ready() async {
    lifetime.admit();
    if (_restart case final restart?) await restart;
    if (_feed == null) {
      _start();
    } else if (_feed!.closing) {
      await _resync(_feed!, retryCleanup: true);
    }
    ({
      AccountTemplatesReadTarget target,
      ProductCollectionRef collection,
      int schemaVersion,
    })?
    binding;
    await state.waitFor((value) {
      if (value.projection.sync.phase == ResourceSyncPhase.failed)
        throw value.projection.sync.error!;
      if (value.projection.sync.phase != ResourceSyncPhase.ready) return false;
      final header = value.projection.header!;
      binding = (
        target: AccountTemplatesReadTarget(
          origin: value.projection.stamp!.origin,
          reference: header.reference,
        ),
        collection: _collection!,
        schemaVersion: header.schemaVersion,
      );
      return true;
    });
    return binding!;
  }

  Future<AccountTemplatesValue> load() {
    lifetime.admit();
    final demand = _demand();
    final pending = _loading[demand];
    if (pending != null) return pending;
    final cached = _cached();
    if (cached != null) return Future.value(cached);
    final done = Completer<AccountTemplatesValue>();
    _loading[demand] = done.future;
    unawaited(
      lifetime
          .run('models:templates', () async {
            final binding = await _ready();
            if (demand.reference != null &&
                    (demand.origin != binding.target.origin ||
                        demand.reference != binding.target.reference ||
                        demand.collection != binding.collection) ||
                demand.opening != null && !identical(demand.opening, _opening))
              throw modelsSuperseded;
            if (!_current(binding.target) ||
                _collection != binding.collection ||
                !identical(_loading[demand], done.future))
              throw modelsSuperseded;
            final old = state.value.templates;
            final window =
                old is CurrentCollectionMirror<AccountTemplate> &&
                    old.window.origin == binding.target.origin &&
                    old.window.reference == binding.collection
                ? old.window
                : CollectionWindow<AccountTemplate>(
                    origin: binding.target.origin,
                    reference: binding.collection,
                    entries: const [],
                    rows: const {},
                    continuation: binding.collection.total == 0
                        ? const CollectionContinuation.end()
                        : const CollectionContinuation.unknown(),
                    complete: binding.collection.total == 0,
                    loading: false,
                    error: null,
                  );
            state.publish(
              state.value.copyWith(
                templates: CollectionMirror.current(
                  window: window.copyWith(loading: true, error: null),
                ),
              ),
            );
            try {
              return await _scope(binding.target).use((scope) async {
                final header = await scope.header();
                if (header.schemaVersion != binding.schemaVersion ||
                    header.templates.total != binding.collection.total)
                  throw resourceProtocol(
                    'The templates header does not match its frozen collection.',
                  );
                final access = ModelReadAccess.templates(scope);
                final templates = <AccountTemplate>[];
                final entries = <ProductEntityRef>[];
                final rows =
                    <int, ReadValue<AccountTemplate, ProductEntityRef>>{};
                var offset = 0;
                while (offset < binding.collection.total) {
                  final page = await scope.entries(offset: offset, limit: 32);
                  final end = offset + page.items.length;
                  if (page.collection != binding.collection ||
                      page.offset != offset ||
                      page.items.isEmpty ||
                      page.items.length > 32 ||
                      end < offset ||
                      end > binding.collection.total ||
                      page.nextOffset !=
                          (end == binding.collection.total ? null : end))
                    throw resourceProtocol(
                      'The templates index page is not continuous.',
                    );
                  for (final reference in page.items) {
                    if (rows.containsKey(reference.entry))
                      throw resourceProtocol(
                        'The templates collection repeated an entry.',
                      );
                    final entity = await scope.entity(reference);
                    if (entity.reference != reference)
                      throw resourceProtocol(
                        'A template entity returned another reference.',
                      );
                    final value = await readAccountTemplate(
                      entity.value,
                      access,
                    );
                    entries.add(reference);
                    templates.add(value);
                    rows[reference.entry] = ReadValue.ready(
                      current: Materialized(
                        origin: binding.target.origin,
                        reference: reference,
                        value: value,
                      ),
                    );
                  }
                  offset = end;
                }
                final catalogReads =
                    await readModelList<NamedModelCatalogReadItem>(
                      header.modelCatalogs,
                      (offset) async {
                        final page = await scope.catalogs(
                          header.modelCatalogs.listId,
                          offset: offset,
                          limit: 32,
                        );
                        return (
                          listId: page.listId,
                          offset: page.offset,
                          total: page.total,
                          items: page.items,
                          nextOffset: page.nextOffset,
                        );
                      },
                    );
                final catalogs = <String, NamedModelCatalog>{};
                for (final item in catalogReads) {
                  final key = await access.string(item.key);
                  if (catalogs.containsKey(key))
                    throw resourceProtocol(
                      'The templates catalog repeated a canonical map key.',
                    );
                  catalogs[key] = NamedModelCatalog(
                    id: await access.string(item.value.id),
                    models: await access.modelList(item.value.models),
                  );
                }
                final revision = await access.string(header.revision);
                if (lifetime.sealed) throw resourceCancelled;
                final current = state.value.templates;
                if (!_current(binding.target) ||
                    _collection != binding.collection ||
                    !identical(_loading[demand], done.future) ||
                    current is! CurrentCollectionMirror<AccountTemplate> ||
                    current.window.origin != binding.target.origin ||
                    current.window.reference != binding.collection)
                  throw modelsSuperseded;
                final value = AccountTemplatesValue(
                  schemaVersion: header.schemaVersion,
                  revision: revision,
                  templates: List.unmodifiable(templates),
                  modelCatalogs: Map.unmodifiable(catalogs),
                );
                state.publish(
                  state.value.copyWith(
                    templates: CollectionMirror.current(
                      window: CollectionWindow(
                        origin: binding.target.origin,
                        reference: binding.collection,
                        entries: List.unmodifiable(entries),
                        rows: Map.unmodifiable(rows),
                        continuation: const CollectionContinuation.end(),
                        complete: true,
                        loading: false,
                        error: null,
                      ),
                    ),
                    catalogs: ReadValue.ready(
                      current: Materialized(
                        origin: binding.target.origin,
                        reference: binding.target.reference,
                        value: value.modelCatalogs,
                      ),
                    ),
                    catalogRevision: ReadValue.ready(
                      current: Materialized(
                        origin: binding.target.origin,
                        reference: binding.target.reference,
                        value: revision,
                      ),
                    ),
                  ),
                );
                return value;
              });
            } catch (error) {
              if (!lifetime.sealed &&
                  _current(binding.target) &&
                  _collection == binding.collection &&
                  identical(_loading[demand], done.future)) {
                final latest = state.value.templates;
                if (latest is CurrentCollectionMirror<AccountTemplate> &&
                    latest.window.origin == binding.target.origin &&
                    latest.window.reference == binding.collection)
                  state.publish(
                    state.value.copyWith(
                      templates: CollectionMirror.current(
                        window: latest.window.copyWith(
                          loading: false,
                          error: resourceFailure(error),
                        ),
                      ),
                    ),
                  );
              }
              rethrow;
            }
          })
          .then(
            (value) {
              unawaited(_loading.remove(demand));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(_loading.remove(demand));
              done.completeError(resourceFailure(error), stack);
            },
          ),
    );
    return done.future;
  }

  bool _current(AccountTemplatesReadTarget target) =>
      state.value.projection.stamp?.origin == target.origin &&
      state.value.projection.header?.reference == target.reference;

  AccountTemplatesValue? _cached() {
    final snapshot = state.value;
    final mirror = snapshot.templates;
    final catalogs = snapshot.catalogs;
    final revision = snapshot.catalogRevision;
    final header = snapshot.projection.header;
    final origin = snapshot.projection.stamp?.origin;
    if (snapshot.projection.sync.phase != ResourceSyncPhase.ready ||
        header == null ||
        mirror is! CurrentCollectionMirror<AccountTemplate> ||
        !mirror.window.complete ||
        mirror.window.error != null ||
        catalogs
            is! ReadyReadValue<
              Map<String, NamedModelCatalog>,
              AccountTemplatesReadRef
            > ||
        revision is! ReadyReadValue<String, AccountTemplatesReadRef> ||
        catalogs.current.origin != origin ||
        revision.current.origin != origin ||
        catalogs.current.reference != header.reference ||
        revision.current.reference != header.reference ||
        mirror.window.origin != origin ||
        mirror.window.entries.length != mirror.window.reference.total)
      return null;
    final templates = <AccountTemplate>[];
    for (final reference in mirror.window.entries) {
      final row = mirror.window.rows[reference.entry];
      if (row is! ReadyReadValue<AccountTemplate, ProductEntityRef> ||
          row.current.origin != origin ||
          row.current.reference != reference)
        return null;
      templates.add(row.current.value);
    }
    return AccountTemplatesValue(
      schemaVersion: header.schemaVersion,
      revision: revision.current.value,
      templates: List.unmodifiable(templates),
      modelCatalogs: catalogs.current.value,
    );
  }
}
