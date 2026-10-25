import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/modes.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../catalog_references.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import 'read_values.dart';

final class FrbModeCatalogReadConnection implements ModeCatalogReadConnection {
  FrbModeCatalogReadConnection(
    ModeCatalogReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeModeCatalogReadConnection>(
      resource: 'mode-catalog-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openModeCatalogRead(
        reference: modeCatalogReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgeModeCatalogReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<ModeCatalogReadHeader> header() => _owner.query((handle) async {
    final value = await handle.header();
    return ModeCatalogReadHeader(
      revision: exactU64(value.revision, 'Mode catalog business revision'),
      modes: typedListFromBridge(value.modes),
    );
  });

  @override
  Future<ModeCatalogEntryPage> entries({int offset = 0, int limit = 32}) =>
      _owner.query((handle) async {
        final request = modelPageArguments(offset, limit);
        final page = modeEntriesFromBridge(
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
  Future<ModeCatalogEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = await handle.entity(
          reference: modelEntityToBridge(reference),
        );
        final result = ModeCatalogEntityRead(
          reference: entityRefFromBridge(value.reference),
          value: modeDescriptorFromBridge(value.value),
        );
        if (result.reference != reference) {
          throw adapterProtocol('mode-catalog-entity-reference');
        }
        return result;
      });

  @override
  Future<ProductEntityRef?> lookupMode(ThreadModeId mode) =>
      _owner.query((handle) async {
        final result = await handle.lookupMode(mode: mode.id);
        return result == null ? null : entityRefFromBridge(result);
      });

  @override
  Future<ThreadModeDescriptorReadPage> modes(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = modeDescriptorsFromBridge(
      await handle.modes(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
      listId: page.listId,
      requestedListId: listId,
    );
    return page;
  });

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'Mode catalog text field'),
              offset: nativeU64(offset, 'Mode catalog UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });

  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
