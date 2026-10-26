import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/identity.dart' as identity;
import '../../../../rust/api/studio/products/read/project_directory.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import '../source_converters.dart';

/// The reference and original origin identify the correct Workspace source;
/// this connection neither needs nor consults a currently active directory feed.
final class FrbWorkspaceSourceStatusConnection
    implements ProductSourceStatusReadConnection {
  FrbWorkspaceSourceStatusConnection(
    this._reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeWorkspaceSourceStatusReadConnection>(
      resource: 'workspace-source-status-read',
      origin: origin,
      version: ProductReadVersion.sourceStatus(
        entry: _reference.entry,
        revision: _reference.revision,
      ),
      open: () => native.openWorkspaceSourceStatusRead(
        reference: identity.BridgeProductSourceStatusRef(
          entry: nativeU64(_reference.entry, 'Workspace source entry'),
          revision: nativeU64(_reference.revision, 'Workspace source revision'),
        ),
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

  final ProductSourceStatusRef _reference;
  late final ProductReadOwner<native.BridgeWorkspaceSourceStatusReadConnection>
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<ProductSourceStatusReadHeader> header() =>
      _owner.query((handle) async {
        final value = sourceStatusHeaderFromBridge(await handle.header());
        if (value.revision != _reference.revision) {
          throw adapterProtocol('workspace-source-status-revision');
        }
        return value;
      });

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'Workspace source text field'),
              offset: nativeU64(offset, 'Workspace source UTF-8 offset'),
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
