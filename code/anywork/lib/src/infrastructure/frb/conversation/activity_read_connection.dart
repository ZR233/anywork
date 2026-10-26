import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/read/connections.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';
import 'activity_read_converters.dart';
import 'identity_converters.dart';
import 'thread_read_connection.dart';

final class FrbActivityReadConnection
    extends FrbThreadTextReadConnection<native.BridgeActivityRead>
    implements ActivityReadConnection {
  FrbActivityReadConnection({
    required String threadId,
    required ActivityReadRef reference,
    required super.origin,
  }) : super(
         resource: 'activity-read',
         diagnosticPrefix: 'execution-read',
         diagnosticLabel: 'Execution read',
         facet: ThreadFacet.execution,
         sourceRevision: reference.revision,
         open: () => native.openActivityRead(
           threadId: threadId,
           reference: activityRefToBridge(reference),
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
  Future<ActivityReadHeader> header() => query((handle, scope) async {
    final header = activityHeaderFromBridge(
      await handle.header(),
      expectedScope: scope,
    );
    if (header.revision != scope.sourceRevision) {
      throw adapterProtocol('activity-read-header-revision');
    }
    return header;
  });

  @override
  Future<ActivityToolPage> tools({int offset = 0, int limit = 32}) =>
      pageQuery(offset, limit, (handle, scope, nativeOffset) async {
        final page = activityToolPageFromBridge(
          await handle.tools(offset: nativeOffset, limit: limit),
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
          indices: page.items.map((item) => item.index),
        );
        return page;
      });

  @override
  Future<WaitTargetPage> waitTargets(
    int toolIndex, {
    int offset = 0,
    int limit = 32,
  }) => pageQuery(offset, limit, (handle, scope, nativeOffset) async {
    final page = waitTargetPageFromBridge(
      await handle.waitTargets(
        toolIndex: nativeU64(toolIndex, 'activity tool index'),
        offset: nativeOffset,
        limit: limit,
      ),
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
      indices: page.items.map((item) => item.index),
    );
    return page;
  });

  @override
  Future<WaitTargetPage> latestWaitTargets({int offset = 0, int limit = 32}) =>
      pageQuery(offset, limit, (handle, scope, nativeOffset) async {
        final page = waitTargetPageFromBridge(
          await handle.latestWaitTargets(offset: nativeOffset, limit: limit),
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
          indices: page.items.map((item) => item.index),
        );
        return page;
      });
}
