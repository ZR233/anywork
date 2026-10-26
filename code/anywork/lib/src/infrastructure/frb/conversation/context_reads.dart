import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/read/context.dart' as native;
import 'context_converters.dart';
import 'identity_converters.dart';
import 'thread_read_connection.dart';
import 'value_read_converters.dart';

final class FrbThreadContextReadConnection
    extends FrbThreadTextReadConnection<native.BridgeThreadContextRead>
    implements ContextReadConnection {
  FrbThreadContextReadConnection({
    required String threadId,
    required ContextReadRef reference,
    required super.origin,
  }) : super(
         resource: 'thread-context-read',
         diagnosticPrefix: 'thread-context-read',
         diagnosticLabel: 'Thread Context read',
         facet: ThreadFacet.context,
         sourceRevision: reference.revision,
         open: () => native.openThreadContextRead(
           threadId: threadId,
           reference: contextRefToBridge(reference),
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
  Future<ContextReadHeader> header() => query(
    (handle, scope) async =>
        contextHeaderFromBridge(await handle.header(), expectedScope: scope),
  );

  @override
  Future<CostPage> costs({int offset = 0, int limit = 32}) =>
      _costPage(offset, limit, savings: false);

  @override
  Future<CostPage> cacheSavings({int offset = 0, int limit = 32}) =>
      _costPage(offset, limit, savings: true);

  Future<CostPage> _costPage(int offset, int limit, {required bool savings}) =>
      pageQuery(offset, limit, (handle, scope, nativeOffset) async {
        final raw = savings
            ? await handle.cacheSavings(offset: nativeOffset, limit: limit)
            : await handle.costs(offset: nativeOffset, limit: limit);
        final page = costPageFromBridge(raw, expectedScope: scope);
        requireThreadReadPage(
          diagnosticPrefix: 'thread-context-read',
          requestedOffset: offset,
          limit: limit,
          offset: page.offset,
          total: page.total,
          count: page.items.length,
          nextOffset: page.nextOffset,
          indices: page.items.map((item) => item.index),
        );
        return page;
      });
}
