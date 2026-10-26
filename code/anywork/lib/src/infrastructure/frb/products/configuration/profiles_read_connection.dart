import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/agent_profiles.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../catalog_references.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import 'profile_values.dart';
import 'read_pages.dart';

final class FrbAgentProfilesReadConnection
    implements AgentProfilesReadConnection {
  FrbAgentProfilesReadConnection(
    AgentProfilesReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeAgentProfilesReadConnection>(
      resource: 'agent-profiles-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openAgentProfilesRead(
        reference: profilesReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgeAgentProfilesReadConnection> _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<AgentProfilesReadHeader> header() => _owner.query(
    (handle) async => profilesReadHeaderFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'profiles text field'),
              offset: nativeU64(offset, 'profiles UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });
  @override
  Future<AgentProfilesEntryPage> entries({int offset = 0, int limit = 32}) =>
      _owner.query((handle) async {
        final request = modelPageArguments(offset, limit);
        final page = profilesEntriesFromBridge(
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
  Future<AgentProfilesEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = profilesEntityFromBridge(
          await handle.entity(reference: modelEntityToBridge(reference)),
        );
        if (value.reference != reference) {
          throw adapterProtocol('profiles-entity-reference');
        }
        return value;
      });
  @override
  Future<ProductEntityRef?> lookupProfile(String profileId) =>
      _owner.query((handle) async {
        final value = await handle.lookupProfile(profileId: profileId);
        return value == null ? null : entityRefFromBridge(value);
      });
  @override
  Future<AgentProfileReadPage> profiles(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = profilesPageFromBridge(
      await handle.profiles(listId: id, offset: start, limit: count),
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
  Future<ProfileDiagnosticReadPage> diagnostics(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = profilesDiagnosticsPageFromBridge(
      await handle.diagnostics(listId: id, offset: start, limit: count),
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
