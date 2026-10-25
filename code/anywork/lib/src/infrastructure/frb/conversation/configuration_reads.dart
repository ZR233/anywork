import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/read/configuration.dart'
    as native;
import 'configuration_converters.dart';
import 'identity_converters.dart';
import 'thread_read_connection.dart';
import 'value_read_converters.dart';

final class FrbThreadConfigurationReadConnection
    extends FrbThreadTextReadConnection<native.BridgeThreadConfigurationRead>
    implements ThreadConfigurationReadConnection {
  FrbThreadConfigurationReadConnection({
    required String threadId,
    required ThreadConfigurationReadRef reference,
    required super.origin,
  }) : super(
         resource: 'thread-configuration-read',
         diagnosticPrefix: 'thread-configuration-read',
         diagnosticLabel: 'Thread Configuration read',
         facet: ThreadFacet.configuration,
         sourceRevision: reference.revision,
         open: () => native.openThreadConfigurationRead(
           threadId: threadId,
           reference: threadConfigurationRefToBridge(reference),
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
  Future<ThreadConfigurationReadHeader> header() => query(
    (handle, scope) async => configurationHeaderFromBridge(
      await handle.header(),
      expectedScope: scope,
    ),
  );

  @override
  Future<SkillNamePage> activeSkills({int offset = 0, int limit = 32}) =>
      pageQuery(offset, limit, (handle, scope, nativeOffset) async {
        final page = skillNamePageFromBridge(
          await handle.activeSkills(offset: nativeOffset, limit: limit),
          expectedScope: scope,
        );
        requireThreadReadPage(
          diagnosticPrefix: 'thread-configuration-read',
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
