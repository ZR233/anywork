import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/read/thread_directory.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../directory_references.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import 'directory_pages.dart';
import 'directory_values.dart';

final class FrbThreadDirectoryReadConnection
    implements ThreadDirectoryReadConnection {
  FrbThreadDirectoryReadConnection(
    ThreadDirectoryReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeThreadDirectoryReadConnection>(
      resource: 'thread-directory-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openThreadDirectoryRead(
        reference: threadDirectoryReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgeThreadDirectoryReadConnection>
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<ThreadDirectoryReadHeader> header() => _owner.query((handle) async {
    final value = await handle.header();
    return ThreadDirectoryReadHeader(
      threads: typedListFromBridge(value.threads),
      nextCursor: nullableReadText(value.nextCursor),
      hasMore: value.hasMore,
    );
  });

  @override
  Future<ThreadDirectoryEntryPage> entries({String? cursor, int limit = 32}) =>
      _owner.query((handle) async {
        modelPageArguments(0, limit);
        final page = threadEntriesFromBridge(
          await handle.entries(cursor: cursor, limit: limit),
        );
        if (page.items.length > limit) {
          throw adapterProtocol('thread-directory-page-limit');
        }
        return page;
      });

  @override
  Future<ThreadDirectoryEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = await handle.entity(
          reference: modelEntityToBridge(reference),
        );
        final result = ThreadDirectoryEntityRead(
          reference: entityRefFromBridge(value.reference),
          value: workspaceThreadReadFromBridge(value.value),
        );
        if (result.reference != reference) {
          throw adapterProtocol('thread-directory-entity-reference');
        }
        return result;
      });

  @override
  Future<ProductEntityRef?> lookupThread(String threadId) =>
      _owner.query((handle) async {
        final result = await handle.lookupThread(threadId: threadId);
        return result == null ? null : entityRefFromBridge(result);
      });

  @override
  Future<WorkspaceThreadRecordReadPage> threads(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = threadRecordsFromBridge(
      await handle.threads(listId: id, offset: start, limit: count),
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
              fieldId: nativeU64(fieldId, 'Thread directory text field'),
              offset: nativeU64(offset, 'Thread directory UTF-8 offset'),
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
