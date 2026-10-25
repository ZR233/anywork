import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/modes.dart' as native;
import '../../../../rust/api/studio/types/mode_editor.dart' as documents;
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import 'command_results.dart';
import 'document_values.dart';
import 'mode_catalog_connection.dart';
import 'mode_catalog_read_connection.dart';

ModesPort createModesPort() => const FrbModesPort();

/// Pure boundary assembly: construction neither loads Rust nor opens a feed.
final class FrbModesPort implements ModesPort {
  const FrbModesPort();

  @override
  Future<FeedConnection<ModeCatalogFrame>> openModeCatalog() async {
    final connection = FrbModeCatalogConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<ModeCatalogReadConnection> openModeCatalogRead(
    ModeCatalogReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbModeCatalogReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ModeDefinitionSnapshot> readDefinition(String modeId) => bridgeQuery(
    () async => modeDefinitionSnapshotFromBridge(
      await native.readModeDefinition(modeId: modeId),
    ),
  );

  @override
  Future<ModeValidationResult> validate(String rawJson) => bridgeQuery(
    () async => modeValidationFromBridge(
      await native.validateModeDefinition(rawJson: rawJson),
    ),
  );

  @override
  Future<String> schema() => bridgeQuery(native.modeDefinitionSchema);

  @override
  Future<WorkflowPreviewSnapshot> preview(WorkflowPreviewRequest request) =>
      bridgeQuery(
        () async => workflowPreviewFromBridge(
          await native.previewModeWorkflow(
            request: workflowPreviewToBridge(request),
          ),
        ),
      );

  @override
  Future<ModeDefinitionCommandReply> save(
    ModeDocument document, {
    required int expectedRevision,
    required OperationId operationId,
  }) {
    final documents.BridgeThreadModeDocument frozen;
    final BigInt revision;
    try {
      frozen = modeDocumentToBridge(document);
      revision = nativeU64(expectedRevision, 'expected Mode revision');
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(failure: modeCommandFailure(error)),
        stack,
      );
    }
    return invokeModeCommand(
      operationId,
      () => native.saveModeDefinition(
        document: frozen,
        expectedRevision: revision,
        operationId: operationId.value,
      ),
      savedModeId: document.definition.id.id,
    );
  }

  @override
  Future<ModeDefinitionCommandReply> delete(
    String modeId, {
    required int expectedRevision,
    required OperationId operationId,
  }) {
    final BigInt revision;
    try {
      ThreadModeId(modeId);
      revision = nativeU64(expectedRevision, 'expected Mode revision');
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(failure: modeCommandFailure(error)),
        stack,
      );
    }
    return invokeModeCommand(
      operationId,
      () => native.deleteModeDefinition(
        modeId: modeId,
        expectedRevision: revision,
        operationId: operationId.value,
      ),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> reload({
    required int expectedRevision,
    required OperationId operationId,
  }) {
    final BigInt revision;
    try {
      revision = nativeU64(expectedRevision, 'expected Mode revision');
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(failure: modeCommandFailure(error)),
        stack,
      );
    }
    return invokeModeCommand(
      operationId,
      () => native.reloadModeDefinitions(
        expectedRevision: revision,
        operationId: operationId.value,
      ),
    );
  }
}
