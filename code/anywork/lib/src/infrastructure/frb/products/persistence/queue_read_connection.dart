import 'package:anywork_client/persistence_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/persistence_queue.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import '../resource_references.dart';
import 'read_values.dart';

final class FrbPersistenceQueueReadConnection
    implements PersistenceQueueReadConnection {
  FrbPersistenceQueueReadConnection(
    PersistenceQueueReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgePersistenceQueueReadConnection>(
      resource: 'persistence-queue-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openPersistenceQueueRead(
        reference: persistenceQueueReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgePersistenceQueueReadConnection>
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<PersistenceQueueReadHeader> header() => _owner.query(
    (handle) async =>
        persistenceQueueReadHeaderFromBridge(await handle.header()),
  );
  @override
  Future<PersistenceQueueEntryPage> entries({int offset = 0, int limit = 32}) =>
      _owner.query((handle) async {
        final request = modelPageArguments(offset, limit);
        final page = persistenceQueueEntriesFromBridge(
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
  Future<PersistenceQueueEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = persistenceQueueEntityFromBridge(
          await handle.entity(reference: modelEntityToBridge(reference)),
        );
        if (value.reference != reference) {
          throw adapterProtocol('persistence-queue-entity-reference');
        }
        return value;
      });
  @override
  Future<ProductEntityRef?> lookupThread(String threadId) =>
      _owner.query((handle) async {
        final value = await handle.lookupThread(id: threadId);
        return value == null ? null : entityRefFromBridge(value);
      });
  @override
  Future<ThreadPersistenceReadPage> threads(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = persistenceThreadsFromBridge(
      await handle.threads(listId: id, offset: start, limit: count),
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
              fieldId: nativeU64(fieldId, 'persistence queue text field'),
              offset: nativeU64(offset, 'persistence queue UTF-8 offset'),
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
