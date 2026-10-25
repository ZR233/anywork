import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/identity.dart' as identity;
import '../../../../rust/api/studio/products/read/account_usage.dart' as native;
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import '../source_converters.dart';

final class FrbAccountUsageSourceStatusConnection
    implements ProductSourceStatusReadConnection {
  FrbAccountUsageSourceStatusConnection(
    ProductSourceStatusRef reference,
    ProductReadOrigin origin,
  ) {
    _owner =
        ProductReadOwner<native.BridgeAccountUsageSourceStatusReadConnection>(
          resource: 'account-usage-source-status-read',
          origin: origin,
          version: ProductReadVersion.sourceStatus(
            entry: reference.entry,
            revision: reference.revision,
          ),
          open: () => native.openAccountUsageSourceStatusRead(
            reference: identity.BridgeProductSourceStatusRef(
              entry: nativeU64(reference.entry, 'source status entry'),
              revision: nativeU64(reference.revision, 'source status revision'),
            ),
            origin: productOriginToBridge(origin),
          ),
          identity: (handle) => handle.identity(),
          requestClose: (handle) => handle.requestClose(),
          close: (handle) async =>
              feedCloseReportFromBridge(await handle.close()),
          retryClose: (handle) async =>
              feedCloseReportFromBridge(await handle.retryClose()),
          dispose: (handle) => handle.dispose(),
        );
  }

  late final ProductReadOwner<
    native.BridgeAccountUsageSourceStatusReadConnection
  >
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<ProductSourceStatusReadHeader> header() => _owner.query(
    (handle) async => sourceStatusHeaderFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'account usage source text field'),
              offset: nativeU64(offset, 'account usage source UTF-8 offset'),
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
