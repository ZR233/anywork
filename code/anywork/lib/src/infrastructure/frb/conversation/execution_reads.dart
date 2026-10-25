import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/read/connections.dart' as native;
import '../shared/adapter_failure.dart';
import 'identity_converters.dart';
import 'thread_read_connection.dart';
import 'turn_read_converters.dart';

final class FrbTurnReadConnection
    extends FrbThreadTextReadConnection<native.BridgeTurnRead>
    implements TurnReadConnection {
  FrbTurnReadConnection({
    required String threadId,
    required TurnReadRef reference,
    required super.origin,
  }) : super(
         resource: 'turn-read',
         diagnosticPrefix: 'execution-read',
         diagnosticLabel: 'Execution read',
         facet: ThreadFacet.execution,
         sourceRevision: reference.revision,
         open: () => native.openTurnRead(
           threadId: threadId,
           reference: turnRefToBridge(reference),
           origin: facetStampToBridge(origin),
         ),
         identityOf: (handle) => handle.identity(),
         requestNativeClose: (handle) => handle.requestClose(),
         closeNative: (handle) => handle.close(),
         retryNativeClose: (handle) => handle.retryClose(),
         disposeNative: (handle) => handle.dispose(),
         readText: (handle, field, offset, bytes) =>
             handle.text(fieldId: field, offset: offset, maxBytes: bytes),
       );

  @override
  Future<TurnReadHeader> header() => query((handle, scope) async {
    final header = turnHeaderFromBridge(
      await handle.header(),
      expectedScope: scope,
    );
    if (header.revision != scope.sourceRevision) {
      throw adapterProtocol('turn-read-header-revision');
    }
    return header;
  });
}

final class FrbInteractionIndexReadConnection
    extends FrbThreadTextReadConnection<native.BridgeInteractionIndexRead>
    implements InteractionIndexReadConnection {
  FrbInteractionIndexReadConnection({
    required String threadId,
    required InteractionIndexRef reference,
    required super.origin,
  }) : super(
         resource: 'interaction-index-read',
         diagnosticPrefix: 'execution-read',
         diagnosticLabel: 'Execution read',
         facet: ThreadFacet.execution,
         sourceRevision: reference.revision,
         open: () => native.openInteractionIndexRead(
           threadId: threadId,
           reference: interactionIndexRefToBridge(reference),
           origin: facetStampToBridge(origin),
         ),
         identityOf: (handle) => handle.identity(),
         requestNativeClose: (handle) => handle.requestClose(),
         closeNative: (handle) => handle.close(),
         retryNativeClose: (handle) => handle.retryClose(),
         disposeNative: (handle) => handle.dispose(),
         readText: (handle, field, offset, bytes) =>
             handle.text(fieldId: field, offset: offset, maxBytes: bytes),
       );

  @override
  Future<InteractionIndexReadHeader> header() => query(
    (handle, scope) async => interactionIndexHeaderFromBridge(
      await handle.header(),
      expectedScope: scope,
    ),
  );

  @override
  Future<InteractionBriefPage> entries({int offset = 0, int limit = 32}) =>
      pageQuery(offset, limit, (handle, scope, nativeOffset) async {
        final page = interactionBriefPageFromBridge(
          await handle.entries(offset: nativeOffset, limit: limit),
          expectedScope: scope,
        );
        requireThreadReadPage(
          diagnosticPrefix: 'execution-read',
          requestedOffset: offset,
          limit: limit,
          offset: page.offset,
          total: page.total,
          count: page.items.length,
          nextOffset: page.nextOffset,
        );
        return page;
      });
}

final class FrbStorageReadConnection
    extends FrbThreadTextReadConnection<native.BridgeStorageRead>
    implements StorageReadConnection {
  FrbStorageReadConnection({
    required String threadId,
    required StorageReadRef reference,
    required super.origin,
  }) : super(
         resource: 'storage-read',
         diagnosticPrefix: 'execution-read',
         diagnosticLabel: 'Execution read',
         facet: ThreadFacet.execution,
         sourceRevision: reference.revision,
         open: () => native.openStorageRead(
           threadId: threadId,
           reference: storageRefToBridge(reference),
           origin: facetStampToBridge(origin),
         ),
         identityOf: (handle) => handle.identity(),
         requestNativeClose: (handle) => handle.requestClose(),
         closeNative: (handle) => handle.close(),
         retryNativeClose: (handle) => handle.retryClose(),
         disposeNative: (handle) => handle.dispose(),
         readText: (handle, field, offset, bytes) =>
             handle.text(fieldId: field, offset: offset, maxBytes: bytes),
       );

  @override
  Future<StorageReadHeader> header() => query(
    (handle, scope) async =>
        storageHeaderFromBridge(await handle.header(), expectedScope: scope),
  );
}
