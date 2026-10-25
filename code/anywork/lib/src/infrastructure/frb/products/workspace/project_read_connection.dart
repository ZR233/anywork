import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/read/project_directory.dart'
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

final class FrbProjectDirectoryReadConnection
    implements ProjectDirectoryReadConnection {
  FrbProjectDirectoryReadConnection(
    ProjectDirectoryReadRef reference,
    ProductReadOrigin origin,
  ) {
    _owner = ProductReadOwner<native.BridgeProjectDirectoryReadConnection>(
      resource: 'project-directory-read',
      origin: origin,
      version: ProductReadVersion.value(
        entry: reference.entry,
        revision: reference.revision,
      ),
      open: () => native.openProjectDirectoryRead(
        reference: projectReadRefToBridge(reference),
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

  late final ProductReadOwner<native.BridgeProjectDirectoryReadConnection>
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});

  @override
  Future<ProjectDirectoryReadHeader> header() => _owner.query(
    (handle) async => ProjectDirectoryReadHeader(
      projects: typedListFromBridge((await handle.header()).projects),
    ),
  );

  @override
  Future<ProjectDirectoryEntryPage> entries({int offset = 0, int limit = 32}) =>
      _owner.query((handle) async {
        final request = modelPageArguments(offset, limit);
        final page = projectEntriesFromBridge(
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
  Future<ProjectDirectoryEntityRead> entity(ProductEntityRef reference) =>
      _owner.query((handle) async {
        final value = await handle.entity(
          reference: modelEntityToBridge(reference),
        );
        final result = ProjectDirectoryEntityRead(
          reference: entityRefFromBridge(value.reference),
          value: projectRecordReadFromBridge(value.value),
        );
        if (result.reference != reference) {
          throw adapterProtocol('project-directory-entity-reference');
        }
        return result;
      });

  @override
  Future<ProductEntityRef?> lookupProject(String projectId) =>
      _owner.query((handle) async {
        final result = await handle.lookupProject(projectId: projectId);
        return result == null ? null : entityRefFromBridge(result);
      });

  @override
  Future<ProjectRecordReadPage> projects(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) => _owner.list(listId, offset, limit, (handle, id, start, count) async {
    final page = projectRecordsFromBridge(
      await handle.projects(listId: id, offset: start, limit: count),
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
              fieldId: nativeU64(fieldId, 'Project text field'),
              offset: nativeU64(offset, 'Project UTF-8 offset'),
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
