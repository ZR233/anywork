import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/products/read/catalog.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/close_converters.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'catalog_references.dart';
import 'identity_converters.dart';
import 'model_read_pages.dart';
import 'model_read_values.dart';
import 'models_read_owner.dart';

/// The entire SDK Catalog connection, pinned to its original native origin/ref.
final class FrbModelCatalogReadConnection implements ModelCatalogReadConnection {
  FrbModelCatalogReadConnection(ModelCatalogReadRef reference, ProductReadOrigin origin) {
    _owner = ModelsReadOwner<native.BridgeModelCatalogReadConnection>(
      resource: 'model-catalog-read', origin: origin, entry: reference.entry, revision: reference.revision,
      open: () => native.openModelCatalogRead(reference: modelCatalogReadRefToBridge(reference), origin: productOriginToBridge(origin)),
      identity: (handle) => handle.identity(), requestClose: (handle) => handle.requestClose(),
      close: (handle) async => feedCloseReportFromBridge(await handle.close()),
      retryClose: (handle) async => feedCloseReportFromBridge(await handle.retryClose()), dispose: (handle) => handle.dispose(),
    );
  }

  late final ModelsReadOwner<native.BridgeModelCatalogReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<ModelCatalogReadHeader> header() => _owner.query((handle) async => modelCatalogReadHeaderFromBridge(await handle.header()));
  @override
  Future<String?> effortAfterModelSelection(String accountId, String modelId, {required String? candidate}) =>
      _owner.query((handle) => handle.effortAfterModelSelection(accountId: accountId, modelId: modelId, candidate: candidate));
  @override
  Future<ModelSelection?> firstTextModel() => _owner.query((handle) async {
    final result = await handle.firstTextModel();
    return result == null ? null : modelSelectionFromBridge(result);
  });
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) => _owner.query((handle) async {
    modelTextArguments(maxBytes);
    return requireModelText(textChunkFromBridge(await handle.text(
      fieldId: nativeU64(fieldId, 'model catalog text field'), offset: nativeU64(offset, 'model catalog UTF-8 offset'), maxBytes: maxBytes,
    )), fieldId, offset, maxBytes);
  });
  @override
  Future<ModelCatalogEntryPage> entries({int offset = 0, int limit = 32}) => _owner.query((handle) async {
    final request = modelPageArguments(offset, limit);
    final page = modelCatalogEntriesFromBridge(await handle.entries(offset: request.offset, limit: request.limit));
    requireModelPage(requestedOffset: offset, limit: limit, offset: page.offset,
      total: page.collection.total, count: page.items.length, nextOffset: page.nextOffset);
    return page;
  });
  @override
  Future<ModelCatalogEntityRead> entity(ProductEntityRef reference) => _owner.query((handle) async {
    final result = modelCatalogEntityFromBridge(await handle.entity(reference: modelEntityToBridge(reference)));
    if (result.reference != reference) throw adapterProtocol('model-catalog-entity-reference');
    return result;
  });
  @override
  Future<ProductEntityRef?> lookupAccount(String accountId) => _owner.query((handle) async {
    final result = await handle.lookupAccount(accountId: accountId);
    return result == null ? null : entityRefFromBridge(result);
  });
  @override
  Future<AccountCatalogEntryReadPage> accounts(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => accountCatalogPageFromBridge(await handle.accounts(listId: id, offset: start, limit: count)));
  @override
  Future<ModelDescriptorReadPage> models(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => modelDescriptorPageFromBridge(await handle.models(listId: id, offset: start, limit: count)));
  @override
  Future<ModelTypeSupportReadPage> typeSupport(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => modelTypeSupportPageFromBridge(await handle.typeSupport(listId: id, offset: start, limit: count)));
  @override
  Future<ModelTypeExclusionReadPage> typeExclusions(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => modelExclusionPageFromBridge(await handle.typeExclusions(listId: id, offset: start, limit: count)));
  @override
  Future<ConnectionModeReadPage> connectionModes(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => connectionModePageFromBridge(await handle.connectionModes(listId: id, offset: start, limit: count)));
  @override
  Future<ModelInputCapabilityReadPage> inputCapabilities(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => modelInputCapabilityPageFromBridge(await handle.inputCapabilities(listId: id, offset: start, limit: count)));
  @override
  Future<ModelInputSourceReadPage> inputSources(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => modelInputSourcePageFromBridge(await handle.inputSources(listId: id, offset: start, limit: count)));
  @override
  Future<ModelModalityReadPage> modalities(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => modelModalityPageFromBridge(await handle.modalities(listId: id, offset: start, limit: count)));
  @override
  Future<ModelPriceTierReadPage> priceTiers(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => modelPriceTierPageFromBridge(await handle.priceTiers(listId: id, offset: start, limit: count)));
  @override
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => modelStringsPageFromBridge(await handle.strings(listId: id, offset: start, limit: count)));
  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
