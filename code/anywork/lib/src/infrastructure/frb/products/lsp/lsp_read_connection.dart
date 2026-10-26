import 'package:anywork_client/lsp_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/lsp.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../model_read_pages.dart';
import '../product_read_owner.dart';
import '../resource_references.dart';
import 'read_values.dart';

final class FrbLspReadConnection implements LspReadConnection {
  FrbLspReadConnection(LspReadRef reference, ProductReadOrigin origin) {
    _owner = ProductReadOwner<native.BridgeLspReadConnection>(
      resource: 'lsp-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openLspRead(
        reference: lspReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgeLspReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<LspReadHeader> header() => _owner.query(
    (handle) async => lspReadHeaderFromBridge(await handle.header()),
  );
  @override
  Future<LspEntryPage> entries({int offset = 0, int limit = 32}) =>
      _owner.query((handle) async {
        final request = modelPageArguments(offset, limit);
        final page = lspEntriesFromBridge(
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
  Future<LspEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = lspEntityFromBridge(
          await handle.entity(reference: modelEntityToBridge(reference)),
        );
        if (value.reference != reference) {
          throw adapterProtocol('lsp-entity-reference');
        }
        return value;
      });
  @override
  Future<ProductEntityRef?> lookupServer(String serverId) =>
      _owner.query((handle) async {
        final value = await handle.lookupServer(key: serverId);
        return value == null ? null : entityRefFromBridge(value);
      });
  @override
  Future<LspServerReadPage> servers(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = lspServersFromBridge(
      await handle.servers(listId: id, offset: start, limit: count),
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
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'LSP text field'),
              offset: nativeU64(offset, 'LSP UTF-8 offset'),
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
