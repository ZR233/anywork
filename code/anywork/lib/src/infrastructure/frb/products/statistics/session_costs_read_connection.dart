import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/statistics.dart' as native;
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import '../statistics_references.dart';
import 'read_pages.dart';
import 'read_values.dart';

final class FrbSessionCostsReadConnection
    implements SessionCostsReadConnection {
  FrbSessionCostsReadConnection(
    SessionCostsReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeSessionCostsReadConnection>(
      resource: 'session-costs-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openSessionCostsRead(
        reference: costsReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgeSessionCostsReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<SessionCostsReadHeader> header() => _owner.query(
    (handle) async => costsReadHeaderFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'session costs text field'),
              offset: nativeU64(offset, 'session costs UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });
  @override
  Future<PurposeCostReadPage> purposes(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = purposesPageFromBridge(
      await handle.purposes(listId: id, offset: start, limit: count),
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
  Future<RuntimeCostReadPage> amounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = amountsPageFromBridge(
      await handle.amounts(listId: id, offset: start, limit: count),
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
