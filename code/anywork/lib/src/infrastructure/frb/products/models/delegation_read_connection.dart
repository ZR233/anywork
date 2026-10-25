import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/identity.dart' as wire;
import '../../../../rust/api/studio/products/read/delegation_models.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../model_read_pages.dart';
import '../product_read_owner.dart';
import 'delegation_values.dart';

/// One exact native pair/account/model pin. Target/scope metadata are checked
/// independently of the original owner's raw close identity, never a latest feed.
final class FrbDelegationModelReadConnection
    implements DelegationModelReadConnection {
  FrbDelegationModelReadConnection(this._requested) {
    final catalog = _requested.sources.catalog;
    _owner = ProductReadOwner<native.BridgeDelegationModelReadConnection>(
      resource: 'delegation-model-read',
      origin: catalog.origin,
      version: ProductReadVersion.value(
        entry: catalog.reference.entry,
        revision: catalog.reference.revision,
      ),
      open: () => native.openDelegationModelRead(
        target: delegationTargetToBridge(_requested),
      ),
      identity: _nativeIdentity,
      requestClose: (handle) => handle.requestClose(),
      close: (handle) async => feedCloseReportFromBridge(await handle.close()),
      retryClose: (handle) async =>
          feedCloseReportFromBridge(await handle.retryClose()),
      dispose: (handle) => handle.dispose(),
    );
  }

  final DelegationModelReadTarget _requested;
  late final ProductReadOwner<native.BridgeDelegationModelReadConnection>
  _owner;
  native.BridgeDelegationModelReadConnection? _handle;
  String? _scopeId;
  ProductReadScopeIdentity? _identity;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  wire.BridgeProductReadScopeIdentity _nativeIdentity(
    native.BridgeDelegationModelReadConnection handle,
  ) {
    // The shared owner's attachment hook saves raw scopeId before converting
    // metadata. A bad descriptor never prevents closing this same opaque.
    _handle ??= handle;
    final raw = handle.identity();
    if (_scopeId == null && raw.scopeId.isNotEmpty) _scopeId = raw.scopeId;
    return raw;
  }

  @override
  String get scopeId {
    final original = _scopeId;
    // This saved native value remains available after Clean/dispose, without
    // reopening a query or converting the possibly unusable descriptor.
    if (original != null) return original;
    try {
      final handle = _handle;
      if (handle == null) {
        throw adapterProtocol('delegation-model-scope-unavailable');
      }
      _nativeIdentity(handle);
      final recovered = _scopeId;
      if (recovered == null) {
        throw adapterProtocol('delegation-model-scope-unavailable');
      }
      return recovered;
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        _owner.owner.failure(error, stack, source: 'scope-identity'),
        stack,
      );
    }
  }

  ProductReadScopeIdentity _scope(
    native.BridgeDelegationModelReadConnection handle,
  ) {
    final actual = productScopeFromBridge(_nativeIdentity(handle));
    final catalog = _requested.sources.catalog;
    if (actual.scopeId.isEmpty ||
        actual.scopeId != _scopeId ||
        actual.ownerEpoch.isEmpty ||
        actual.incarnation < 1 ||
        actual.ownerEpoch != catalog.origin.ownerEpoch ||
        actual.incarnation != catalog.origin.incarnation ||
        actual.version !=
            ProductReadVersion.value(
              entry: catalog.reference.entry,
              revision: catalog.reference.revision,
            )) {
      throw adapterProtocol('delegation-model-origin');
    }
    if (_identity case final expected?) {
      requireProductReadScope(actual, expected);
    }
    return _identity ??= actual;
  }

  DelegationModelReadTarget _target(
    native.BridgeDelegationModelReadConnection handle,
  ) {
    final actual = delegationTargetFromBridge(handle.target());
    if (actual != _requested) throw adapterProtocol('delegation-model-target');
    return actual;
  }

  @override
  ProductReadScopeIdentity get identity {
    _owner.owner.ensureOpen();
    try {
      final handle = _handle;
      if (handle == null) throw adapterProtocol('delegation-model-not-opened');
      _target(handle);
      return _scope(handle);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        _owner.owner.failure(error, stack, source: 'descriptor'),
        stack,
      );
    }
  }

  @override
  DelegationModelReadTarget get target {
    _owner.owner.ensureOpen();
    try {
      final handle = _handle;
      if (handle == null) throw adapterProtocol('delegation-model-not-opened');
      _scope(handle);
      return _target(handle);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        _owner.owner.failure(error, stack, source: 'descriptor'),
        stack,
      );
    }
  }

  void _checkMaterial(native.BridgeDelegationModelReadConnection handle) {
    _scope(handle);
    _target(handle);
  }

  Future<T> _query<T>(
    Future<T> Function(native.BridgeDelegationModelReadConnection) action,
  ) => _owner.query((handle) async {
    _checkMaterial(handle);
    final value = await action(handle);
    _checkMaterial(handle);
    return value;
  });

  Future<T> _list<T>(
    int listId,
    int offset,
    int limit,
    Future<T> Function(
      native.BridgeDelegationModelReadConnection,
      BigInt,
      BigInt,
      int,
    )
    read,
  ) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    _checkMaterial(handle);
    final value = await read(handle, id, start, count);
    _checkMaterial(handle);
    return value;
  });

  @override
  Future<DelegationModelReadHeader> header() => _query((handle) async {
    final value = delegationHeaderFromBridge(await handle.header());
    requireProductReadScope(value.scope, _scope(handle));
    if (value.target != _requested) {
      throw adapterProtocol('delegation-model-header-target');
    }
    return value;
  });
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'delegation model text field'),
              offset: nativeU64(offset, 'delegation model UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });
  @override
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32}) =>
      _list(listId, offset, limit, (handle, id, start, count) async {
        final page = modelStringsPageFromBridge(
          await handle.strings(listId: id, offset: start, limit: count),
        );
        requireModelPage(
          requestedOffset: offset,
          limit: limit,
          listId: page.listId,
          requestedListId: listId,
          offset: page.offset,
          total: page.total,
          count: page.items.length,
          nextOffset: page.nextOffset,
        );
        return page;
      });
  @override
  Future<ModelTypeSupportReadPage> typeSupport(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = modelTypeSupportPageFromBridge(
      await handle.typeSupport(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  Future<ModelTypeExclusionReadPage> typeExclusions(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = modelExclusionPageFromBridge(
      await handle.typeExclusions(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  Future<ConnectionModeReadPage> connectionModes(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = connectionModePageFromBridge(
      await handle.connectionModes(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  Future<ModelInputCapabilityReadPage> inputCapabilities(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = modelInputCapabilityPageFromBridge(
      await handle.inputCapabilities(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  Future<ModelInputSourceReadPage> inputSources(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = modelInputSourcePageFromBridge(
      await handle.inputSources(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  Future<ModelModalityReadPage> modalities(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = modelModalityPageFromBridge(
      await handle.modalities(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  Future<ModelPriceTierReadPage> priceTiers(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = modelPriceTierPageFromBridge(
      await handle.priceTiers(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  Future<ModelSelectionSourceReadPage> selectionSources(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = modelSelectionSourcesPageFromBridge(
      await handle.selectionSources(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  Future<AgentEvaluationReadPage> evaluations(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _list(listId, offset, limit, (handle, id, start, count) async {
    final page = modelEvaluationsPageFromBridge(
      await handle.evaluations(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      listId: page.listId,
      requestedListId: listId,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });
  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
