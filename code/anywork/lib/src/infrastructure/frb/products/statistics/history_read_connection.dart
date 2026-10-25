import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/statistics.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import '../statistics_references.dart';
import 'read_pages.dart';
import 'read_values.dart';

final class FrbPerformanceHistoryReadConnection
    implements PerformanceHistoryReadConnection {
  FrbPerformanceHistoryReadConnection(
    PerformanceHistoryReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgePerformanceHistoryReadConnection>(
      resource: 'performance-history-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openPerformanceHistoryRead(
        reference: historyReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgePerformanceHistoryReadConnection>
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<PerformanceHistoryReadHeader> header() => _owner.query(
    (handle) async => historyReadHeaderFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'performance history text field'),
              offset: nativeU64(offset, 'performance history UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });
  @override
  Future<PerformanceHistoryEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) => _owner.query((handle) async {
    final request = modelPageArguments(offset, limit);
    final page = historyEntriesFromBridge(
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
  Future<PerformanceHistoryEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = historyEntityFromBridge(
          await handle.entity(reference: modelEntityToBridge(reference)),
        );
        if (value.reference != reference) {
          throw adapterProtocol('performance-history-entity-reference');
        }
        return value;
      });
  @override
  Future<PerformanceSampleReadPage> samples(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = samplesPageFromBridge(
      await handle.samples(listId: id, offset: start, limit: count),
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
