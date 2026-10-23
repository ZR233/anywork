import '../../../operations.dart';
import '../../../resources.dart';
import 'mode_documents.dart';
import 'modes_state.dart';

/// Canonical catalog and native authoring capabilities only. Graph/raw editing,
/// dirty state and the 64-entry undo history belong to the presentation VM.
abstract interface class ModesRepository {
  ReadonlyLatestValue<ModesState> get state;
  Future<void> loadModesPage({int limit = 32});
  Future<ModeDefinitionSnapshot> readDefinition(String modeId);
  Future<ModeValidationResult> validate(String rawJson);
  Future<String> schema();
  Future<WorkflowPreviewSnapshot> preview(WorkflowPreviewRequest request);
  OperationTicket<ModeDefinitionResult> save(ModeDocument document, {required int expectedRevision});
  OperationTicket<ModeDefinitionResult> delete(String modeId, {required int expectedRevision});
  OperationTicket<ModeDefinitionResult> reload({required int expectedRevision});
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
