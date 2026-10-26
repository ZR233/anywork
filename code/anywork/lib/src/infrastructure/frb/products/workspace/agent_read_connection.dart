import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/read/agent_directory.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../directory_references.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import 'directory_pages.dart';
import 'directory_values.dart';

final class FrbAgentDirectoryReadConnection
    implements AgentDirectoryReadConnection {
  FrbAgentDirectoryReadConnection(
    AgentDirectoryReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeAgentDirectoryReadConnection>(
      resource: 'agent-directory-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openAgentDirectoryRead(
        reference: agentReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgeAgentDirectoryReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<AgentDirectoryReadHeader> header() => _owner.query(
    (handle) async => AgentDirectoryReadHeader(
      agents: typedListFromBridge((await handle.header()).agents),
    ),
  );

  @override
  Future<AgentDirectoryEntryPage> entries({int offset = 0, int limit = 32}) =>
      _owner.query((handle) async {
        final request = modelPageArguments(offset, limit);
        final page = agentEntriesFromBridge(
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
  Future<AgentDirectoryEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = await handle.entity(
          reference: modelEntityToBridge(reference),
        );
        final result = AgentDirectoryEntityRead(
          reference: entityRefFromBridge(value.reference),
          value: agentDirectoryReadFromBridge(value.value),
        );
        if (result.reference != reference) {
          throw adapterProtocol('agent-directory-entity-reference');
        }
        return result;
      });

  @override
  Future<ProductEntityRef?> lookupAgent(String agentId) =>
      _owner.query((handle) async {
        final result = await handle.lookupAgent(agentId: agentId);
        return result == null ? null : entityRefFromBridge(result);
      });

  @override
  Future<AgentDirectoryEntryReadPage> agents(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = agentRecordsFromBridge(
      await handle.agents(listId: id, offset: start, limit: count),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
      listId: page.listId,
      requestedListId: listId,
    );
    return page;
  });

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'Agent directory text field'),
              offset: nativeU64(offset, 'Agent directory UTF-8 offset'),
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
