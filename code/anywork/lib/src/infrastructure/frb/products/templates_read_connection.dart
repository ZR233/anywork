import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/products/read/templates.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/close_converters.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'catalog_references.dart';
import 'identity_converters.dart';
import 'model_read_pages.dart';
import 'models_read_owner.dart';
import 'template_read_values.dart';

/// Complete Templates reads. No synthetic sourceStatus or revision hashing.
final class FrbAccountTemplatesReadConnection implements AccountTemplatesReadConnection {
  FrbAccountTemplatesReadConnection(AccountTemplatesReadRef reference, ProductReadOrigin origin) {
    _owner = ModelsReadOwner<native.BridgeAccountTemplatesReadConnection>(
      resource: 'account-templates-read', origin: origin, entry: reference.entry, revision: reference.revision,
      open: () => native.openAccountTemplatesRead(reference: templatesReadRefToBridge(reference), origin: productOriginToBridge(origin)),
      identity: (handle) => handle.identity(), requestClose: (handle) => handle.requestClose(),
      close: (handle) async => feedCloseReportFromBridge(await handle.close()),
      retryClose: (handle) async => feedCloseReportFromBridge(await handle.retryClose()), dispose: (handle) => handle.dispose(),
    );
  }

  late final ModelsReadOwner<native.BridgeAccountTemplatesReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<AccountTemplatesReadHeader> header() => _owner.query((handle) async => templatesReadHeaderFromBridge(await handle.header()));
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) => _owner.query((handle) async {
    modelTextArguments(maxBytes);
    return requireModelText(textChunkFromBridge(await handle.text(
      fieldId: nativeU64(fieldId, 'templates text field'), offset: nativeU64(offset, 'templates UTF-8 offset'), maxBytes: maxBytes,
    )), fieldId, offset, maxBytes);
  });
  @override
  Future<AccountTemplatesEntryPage> entries({int offset = 0, int limit = 32}) => _owner.query((handle) async {
    final request = modelPageArguments(offset, limit);
    final page = templatesEntriesFromBridge(await handle.entries(offset: request.offset, limit: request.limit));
    requireModelPage(requestedOffset: offset, limit: limit, offset: page.offset,
      total: page.collection.total, count: page.items.length, nextOffset: page.nextOffset);
    return page;
  });
  @override
  Future<AccountTemplatesEntityRead> entity(ProductEntityRef reference) => _owner.query((handle) async {
    final result = templatesEntityFromBridge(await handle.entity(reference: modelEntityToBridge(reference)));
    if (result.reference != reference) throw adapterProtocol('account-templates-entity-reference');
    return result;
  });
  @override
  Future<ProductEntityRef?> lookupTemplate(String templateId) => _owner.query((handle) async {
    final result = await handle.lookupTemplate(templateId: templateId);
    return result == null ? null : entityRefFromBridge(result);
  });
  @override
  Future<AccountTemplateReadPage> templates(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => accountTemplatePageFromBridge(await handle.templates(listId: id, offset: start, limit: count)));
  @override
  Future<NamedModelCatalogReadPage> catalogs(int listId, {int offset = 0, int limit = 32}) => _owner.list(listId, offset, limit,
    (handle, id, start, count) async => namedCatalogPageFromBridge(await handle.catalogs(listId: id, offset: start, limit: count)));
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
