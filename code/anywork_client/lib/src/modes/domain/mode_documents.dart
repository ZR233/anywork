import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'mode_values.dart';

part 'mode_documents.freezed.dart';

/// Authoring values intentionally have no tolerant fromJson. Raw input is
/// validated by the production Rust validator, including unknown fields.
@Freezed(toStringOverride: false)
abstract class ModeDefinition with _$ModeDefinition {
  const factory ModeDefinition({
    required ThreadModeId id,
    required String displayName,
    required String description,
    required int order,
    required String prompt,
    required WorkflowDefinition? workflow,
  }) = _ModeDefinition;
}

@Freezed(toStringOverride: false)
abstract class ModeDocument with _$ModeDocument {
  const ModeDocument._();
  const factory ModeDocument({
    required ModeDefinition definition,
    required ModeEditorLayout editor,
  }) = _ModeDocument;

  /// The established file format is flat, not {definition: ...}.
  Map<String, Object?> toJson() => {
    'id': definition.id.id,
    'displayName': definition.displayName,
    'description': definition.description,
    'order': definition.order,
    'prompt': definition.prompt,
    'workflow': definition.workflow?.toJson(),
    'editor': {
      'nodes': [
        for (final node in editor.nodes)
          {'stateId': node.stateId, 'x': node.x, 'y': node.y},
      ],
    },
  };
}

@freezed
abstract class ModeEditorLayout with _$ModeEditorLayout {
  const factory ModeEditorLayout({required List<WorkflowNodePosition> nodes}) =
      _ModeEditorLayout;
}

@freezed
abstract class WorkflowNodePosition with _$WorkflowNodePosition {
  const factory WorkflowNodePosition({
    required String stateId,
    required double x,
    required double y,
  }) = _WorkflowNodePosition;
}

@Freezed(toStringOverride: false)
abstract class WorkflowDefinition with _$WorkflowDefinition {
  const WorkflowDefinition._();
  const factory WorkflowDefinition({
    required String title,
    required String goal,
    required String initialStateId,
    required List<WorkflowState> states,
    required List<WorkflowTransition> transitions,
  }) = _WorkflowDefinition;

  Map<String, Object?> toJson() => {
    'title': title,
    'goal': goal,
    'initialStateId': initialStateId,
    'states': [for (final state in states) state.toJson()],
    'transitions': [for (final transition in transitions) transition.toJson()],
  };
}

enum WorkflowStateKind { atomic, finalState }

@Freezed(toStringOverride: false)
abstract class WorkflowState with _$WorkflowState {
  const WorkflowState._();
  const factory WorkflowState({
    required String id,
    required String title,
    required String instructions,
    required List<String> completionCriteria,
    required WorkflowStateKind kind,
  }) = _WorkflowState;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'instructions': instructions,
    'completionCriteria': completionCriteria,
    'kind': kind == WorkflowStateKind.finalState ? 'final' : 'atomic',
  };
}

@Freezed(toStringOverride: false)
abstract class WorkflowTransition with _$WorkflowTransition {
  const WorkflowTransition._();
  const factory WorkflowTransition({
    required String sourceStateId,
    required String targetStateId,
    required String guard,
  }) = _WorkflowTransition;

  Map<String, Object?> toJson() => {
    'sourceStateId': sourceStateId,
    'targetStateId': targetStateId,
    'guard': guard,
  };
}

@Freezed(toStringOverride: false)
abstract class ModeDefinitionSnapshot with _$ModeDefinitionSnapshot {
  const factory ModeDefinitionSnapshot({
    required int revision,
    required ModeDocument document,
    required bool readOnly,
  }) = _ModeDefinitionSnapshot;
}

@Freezed(toStringOverride: false)
abstract class ModeValidationResult with _$ModeValidationResult {
  const factory ModeValidationResult({
    required ModeDocument? document,
    required List<ValidationIssue> issues,
  }) = _ModeValidationResult;
}

@Freezed(toStringOverride: false)
abstract class WorkflowPreviewRequest with _$WorkflowPreviewRequest {
  const factory WorkflowPreviewRequest({
    required ModeDocument document,
    required List<String> path,
    required String? targetStateId,
    required String reason,
  }) = _WorkflowPreviewRequest;
}

@Freezed(toStringOverride: false)
abstract class WorkflowPreviewSnapshot with _$WorkflowPreviewSnapshot {
  const factory WorkflowPreviewSnapshot({
    required bool accepted,
    required String message,
    required WorkflowState? currentState,
    required List<WorkflowTransition> transitions,
    required List<String> path,
    required bool terminal,
  }) = _WorkflowPreviewSnapshot;
}
