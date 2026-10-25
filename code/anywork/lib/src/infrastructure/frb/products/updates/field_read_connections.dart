import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';

import '../../../../rust/api/studio/products/read/updates.dart' as native;
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import '../source_converters.dart';
import '../update_references.dart';
import 'read_values.dart';

final class FrbUpdateSummaryReadConnection
    implements UpdateSummaryReadConnection {
  FrbUpdateSummaryReadConnection(
    UpdateSummaryReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeUpdateSummaryReadConnection>(
      resource: 'update-summary-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openSummary(
        reference: updateSummaryRefToBridge(reference),
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
  late final ProductReadOwner<native.BridgeUpdateSummaryReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<UpdateSummaryRead> header() => _owner.query(
    (handle) async => updateSummaryReadFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'update summary text field'),
              offset: nativeU64(offset, 'update summary UTF-8 offset'),
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

final class FrbUpdateOperationReadConnection
    implements UpdateOperationReadConnection {
  FrbUpdateOperationReadConnection(
    UpdateOperationReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeUpdateOperationReadConnection>(
      resource: 'update-operation-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openOperation(
        reference: updateOperationRefToBridge(reference),
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
  late final ProductReadOwner<native.BridgeUpdateOperationReadConnection>
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<UpdateOperationReadHeader> header() => _owner.query(
    (handle) async => UpdateOperationReadHeader(
      operationId: readTextFromBridge((await handle.header()).operationId),
    ),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'update operation text field'),
              offset: nativeU64(offset, 'update operation UTF-8 offset'),
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

final class FrbUpdateErrorReadConnection implements UpdateErrorReadConnection {
  FrbUpdateErrorReadConnection(
    UpdateErrorReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeUpdateErrorReadConnection>(
      resource: 'update-error-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openError(
        reference: updateErrorRefToBridge(reference),
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
  late final ProductReadOwner<native.BridgeUpdateErrorReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<SourceStateErrorRead> header() => _owner.query(
    (handle) async => sourceErrorReadFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'update error text field'),
              offset: nativeU64(offset, 'update error UTF-8 offset'),
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

final class FrbUpdateDetailsReadConnection
    implements UpdateDetailsReadConnection {
  FrbUpdateDetailsReadConnection(
    UpdateDetailsReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeUpdateDetailsReadConnection>(
      resource: 'update-details-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openDetails(
        reference: updateDetailsRefToBridge(reference),
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
  late final ProductReadOwner<native.BridgeUpdateDetailsReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<UpdateDetailsRead> header() => _owner.query(
    (handle) async => updateDetailsReadFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'update details text field'),
              offset: nativeU64(offset, 'update details UTF-8 offset'),
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
