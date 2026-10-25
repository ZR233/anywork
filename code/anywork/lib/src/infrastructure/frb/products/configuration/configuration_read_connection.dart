import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart'
    show ModelInputCapabilityReadPage, ModelInputSourceReadPage;
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/configuration.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../catalog_references.dart';
import '../identity_converters.dart';
import '../model_read_pages.dart';
import '../product_read_owner.dart';
import 'read_pages.dart';
import 'read_values.dart';

/// Queries only the original immutable configuration value, never latest state.
final class FrbConfigurationReadConnection
    implements ConfigurationReadConnection {
  FrbConfigurationReadConnection(
    ConfigurationReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeConfigurationReadConnection>(
      resource: 'configuration-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openConfigurationRead(
        reference: configurationReadRefToBridge(reference),
        origin: productOriginToBridge(origin),
      ),
      identity: (handle) => handle.identity(),
      requestClose: (handle) => handle.requestClose(),
      close: (handle) async => feedCloseReportFromBridge(await handle.close()),
      retryClose: (handle) async =>
          feedCloseReportFromBridge(await handle.retryClose()),
      dispose: (handle) => handle.dispose(),
    );
  }

  late final ProductReadOwner<native.BridgeConfigurationReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<ConfigurationReadHeader> header() => _owner.query(
    (handle) async => configurationReadHeaderFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'configuration text field'),
              offset: nativeU64(offset, 'configuration UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });
  @override
  Future<ConfigurationEntryPage> entries({int offset = 0, int limit = 32}) =>
      _owner.query((handle) async {
        final request = modelPageArguments(offset, limit);
        final page = configurationEntriesFromBridge(
          await handle.entries(offset: request.offset, limit: request.limit),
        );
        requireModelPage(
          requestedOffset: offset,
          limit: limit,
          offset: page.offset,
          total: page.collection.total,
          count: page.items.length,
          nextOffset: page.nextOffset,
        );
        return page;
      });
  @override
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = configurationEntityFromBridge(
          await handle.entity(reference: modelEntityToBridge(reference)),
        );
        if (value.reference != reference) {
          throw adapterProtocol('configuration-entity-reference');
        }
        return value;
      });
  @override
  Future<ProductEntityRef?> lookupAccount(String accountId) =>
      _owner.query((handle) async {
        final value = await handle.lookupAccount(accountId: accountId);
        return value == null ? null : entityRefFromBridge(value);
      });
  @override
  Future<AccountConfigurationReadPage> accounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = configurationAccountsPageFromBridge(
      await handle.accounts(listId: id, offset: start, limit: count),
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
  Future<CustomModelConfigurationReadPage> customModels(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = configurationCustomModelsPageFromBridge(
      await handle.customModels(listId: id, offset: start, limit: count),
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
  Future<ModelConnectionReadPage> modelConnections(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = configurationConnectionsPageFromBridge(
      await handle.modelConnections(listId: id, offset: start, limit: count),
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
  Future<ModelAutoCompactReadPage> autoCompactOverrides(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = configurationAutoCompactPageFromBridge(
      await handle.autoCompactOverrides(
        listId: id,
        offset: start,
        limit: count,
      ),
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
  Future<ModeModelRouteReadPage> modeRoutes(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = configurationModesPageFromBridge(
      await handle.modeRoutes(listId: id, offset: start, limit: count),
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
  Future<RoleModelRouteReadPage> roleRoutes(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = configurationRolesPageFromBridge(
      await handle.roleRoutes(listId: id, offset: start, limit: count),
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
  Future<McpConfigurationReadPage> mcpConfigs(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = configurationMcpPageFromBridge(
      await handle.mcpConfigs(listId: id, offset: start, limit: count),
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
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32}) =>
      _owner.list(listId, offset, limit, (handle, id, start, count) async {
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
  Future<ModelInputCapabilityReadPage> inputCapabilities(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
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
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
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
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
