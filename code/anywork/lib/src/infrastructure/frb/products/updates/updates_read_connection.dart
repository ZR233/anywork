import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';

import '../../../../rust/api/studio/products/read/updates.dart' as native;
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import '../update_references.dart';
import 'read_values.dart';

final class FrbUpdatesReadConnection implements UpdatesReadConnection {
  FrbUpdatesReadConnection(UpdatesReadRef reference, ProductReadOrigin origin) {
    _owner = ProductReadOwner<native.BridgeUpdatesReadConnection>(
      resource: 'updates-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openUpdatesRead(
        reference: updatesReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgeUpdatesReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<UpdatesReadHeader> header() => _owner.query(
    (handle) async => updatesReadHeaderFromBridge(await handle.header()),
  );

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'updates text field'),
              offset: nativeU64(offset, 'updates UTF-8 offset'),
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
