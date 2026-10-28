import '../../models.dart';

/// Typed Mode authoring commands and read-only validation helpers.
///
/// The schema is the only string-based authoring surface; runtime snapshots,
/// documents and preview results stay typed.
abstract interface class ModeEditorTransport {
  Future<ModeDefinitionSnapshot> readThreadModeDefinition(String modeId);

  Future<ModeDefinitionCommandReply> saveThreadModeDefinition(
    ModeDocument document, {
    required int expectedRevision,
    required OperationId operationId,
  });

  Future<ModeDefinitionCommandReply> deleteThreadModeDefinition(
    String modeId, {
    required int expectedRevision,
    required OperationId operationId,
  });

  Future<ModeDefinitionCommandReply> reloadThreadModeDefinitions({
    required int expectedRevision,
    required OperationId operationId,
  });

  Future<ModeValidationResult> validateThreadModeDefinition(String json);

  Future<String> threadModeDefinitionSchema();

  Future<WorkflowPreviewSnapshot> previewThreadModeWorkflow(
    WorkflowPreviewRequest request,
  );
}
