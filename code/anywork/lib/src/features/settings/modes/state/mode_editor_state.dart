import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';
import 'mode_dialog_state.dart';

part 'mode_editor_state.freezed.dart';

enum ModeEditorTab { graph, json, settings, preview }
enum ModeEditorNotice { draftCreated, imported, saved, deleted, copied, duplicated }
enum ModeLeaveChoice { save, discard, stay }
enum ModeEditorRequest { open, create, importJson, apply, validate, preview, save, delete, reload }

@freezed
sealed class ModeEditorSelection with _$ModeEditorSelection {
  const factory ModeEditorSelection.none() = NoModeSelection;
  const factory ModeEditorSelection.node({required String stateId}) = ModeNodeSelection;
  const factory ModeEditorSelection.edge({required String sourceStateId, required String targetStateId}) = ModeEdgeSelection;
}

@Freezed(toStringOverride: false)
abstract class ModeEditorSnapshot with _$ModeEditorSnapshot {
  const factory ModeEditorSnapshot({
    required ModeDocument document,
    required String jsonText,
    required bool jsonApplied,
    required String orderText,
    ValidationIssue? orderError,
    @Default({}) Map<String, String> criteriaRaw,
  }) = _ModeEditorSnapshot;
}

@Freezed(toStringOverride: false)
abstract class ModeEditorViewState with _$ModeEditorViewState {
  const ModeEditorViewState._();

  const factory ModeEditorViewState({
    required ModesState catalog,
    String? selectedModeId,
    int? catalogRevision,
    int? draftCatalogRevision,
    ProductReadOrigin? draftOrigin,
    ModeDocument? document,
    @Default('') String jsonText,
    @Default(true) bool jsonApplied,
    @Default('') String orderText,
    ValidationIssue? orderError,
    @Default({}) Map<String, String> criteriaRaw,
    ModeDocument? savedDocument,
    @Default('') String savedJson,
    int? savedRevision,
    @Default(false) bool dirty,
    @Default(false) bool readOnly,
    @Default(false) bool busy,
    ModeEditorRequest? request,
    @Default([]) List<ModeEditorSnapshot> undo,
    @Default([]) List<ModeEditorSnapshot> redo,
    @Default(ModeEditorTab.graph) ModeEditorTab tab,
    @Default(ModeEditorSelection.none()) ModeEditorSelection selection,
    @Default(false) bool inspectorOpen,
    @Default('') String query,
    @Default(false) bool validationRequested,
    @Default([]) List<ValidationIssue> issues,
    WorkflowPreviewSnapshot? preview,
    @Default('') String previewReason,
    @Default(0) int latestIntent,
    @Default(0) int editRevision,
    SettingsAction? operation,
    StudioFailure? error,
    StudioFailure? catalogReadError,
    ModeEditorNotice? notice,
    ModeDialogDraft? dialog,
  }) = _ModeEditorViewState;

  bool get canEdit => document != null && !readOnly &&
      (!busy || request == ModeEditorRequest.save);
}

@Freezed(toStringOverride: false)
sealed class ModeEdit with _$ModeEdit {
  const factory ModeEdit.displayName(String value) = EditModeDisplayName;
  const factory ModeEdit.description(String value) = EditModeDescription;
  const factory ModeEdit.orderRaw(String value) = EditModeOrder;
  const factory ModeEdit.prompt(String value) = EditModePrompt;
  const factory ModeEdit.workflowTitle(String value) = EditWorkflowTitle;
  const factory ModeEdit.workflowGoal(String value) = EditWorkflowGoal;
  const factory ModeEdit.initialState(String value) = EditInitialState;
  const factory ModeEdit.addState(WorkflowState value) = AddWorkflowState;
  const factory ModeEdit.renameState(String oldId, String newId) = RenameWorkflowState;
  const factory ModeEdit.removeState(String id) = RemoveWorkflowState;
  const factory ModeEdit.stateTitle(String id, String value) = EditWorkflowStateTitle;
  const factory ModeEdit.stateInstructions(String id, String value) = EditWorkflowStateInstructions;
  const factory ModeEdit.stateCriteria(String id, List<String> values) = EditWorkflowStateCriteria;
  const factory ModeEdit.stateKind(String id, WorkflowStateKind value) = EditWorkflowStateKind;
  const factory ModeEdit.addTransition(WorkflowTransition value) = AddWorkflowTransition;
  const factory ModeEdit.removeTransition(String sourceId, String targetId) = RemoveWorkflowTransition;
  const factory ModeEdit.transitionGuard(String sourceId, String targetId, String value) = EditWorkflowTransitionGuard;
  const factory ModeEdit.nodePositions(List<WorkflowNodePosition> values) = EditWorkflowNodePositions;
  const factory ModeEdit.enableWorkflow(WorkflowDefinition value) = EnableModeWorkflow;
  const factory ModeEdit.removeWorkflow() = RemoveModeWorkflow;
}
