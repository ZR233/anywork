import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';

import '../state/mode_editor_state.dart';
import '../workflow_layout.dart';

/// Private implementation of the single editor VM's typed graph intents.
/// This is not a parser/validator: only Rust may accept an authoring document.
ModeDocument applyModeGraphEdit(ModeDocument document, ModeEdit edit) {
  final definition = document.definition;
  final workflow = definition.workflow;
  final updated = switch (edit) {
    EditModeDisplayName(:final value) => definition.copyWith(displayName: value),
    EditModeDescription(:final value) => definition.copyWith(description: value),
    EditModePrompt(:final value) => definition.copyWith(prompt: value),
    EditModeOrder() => throw _invalid('Order text belongs to the editor VM'),
    EnableModeWorkflow(:final value) => definition.copyWith(workflow: value),
    RemoveModeWorkflow() => definition.copyWith(workflow: null),
    EditWorkflowTitle(:final value) => definition.copyWith(
      workflow: _requireWorkflow(workflow).copyWith(title: value),
    ),
    EditWorkflowGoal(:final value) => definition.copyWith(
      workflow: _requireWorkflow(workflow).copyWith(goal: value),
    ),
    EditInitialState(:final value) => definition.copyWith(
      workflow: _initial(_requireWorkflow(workflow), value),
    ),
    AddWorkflowState(:final value) => definition.copyWith(
      workflow: _addState(_requireWorkflow(workflow), value),
    ),
    RenameWorkflowState(:final oldId, :final newId) => definition.copyWith(
      workflow: _renameState(_requireWorkflow(workflow), oldId, newId),
    ),
    RemoveWorkflowState(:final id) => definition.copyWith(
      workflow: _removeState(_requireWorkflow(workflow), id),
    ),
    EditWorkflowStateTitle(:final id, :final value) => definition.copyWith(
      workflow: _replaceState(_requireWorkflow(workflow), id,
        (state) => state.copyWith(title: value)),
    ),
    EditWorkflowStateInstructions(:final id, :final value) => definition.copyWith(
      workflow: _replaceState(_requireWorkflow(workflow), id,
        (state) => state.copyWith(instructions: value)),
    ),
    EditWorkflowStateCriteria(:final id, :final values) => definition.copyWith(
      workflow: _replaceState(_requireWorkflow(workflow), id,
        (state) => state.copyWith(completionCriteria: List.of(values))),
    ),
    EditWorkflowStateKind(:final id, :final value) => definition.copyWith(
      workflow: _replaceState(_requireWorkflow(workflow), id,
        (state) => state.copyWith(kind: value)),
    ),
    AddWorkflowTransition(:final value) => definition.copyWith(
      workflow: _addTransition(_requireWorkflow(workflow), value),
    ),
    RemoveWorkflowTransition(:final sourceId, :final targetId) => definition.copyWith(
      workflow: _removeTransition(_requireWorkflow(workflow), sourceId, targetId),
    ),
    EditWorkflowTransitionGuard(:final sourceId, :final targetId, :final value) => definition.copyWith(
      workflow: _replaceGuard(_requireWorkflow(workflow), sourceId, targetId, value),
    ),
    EditWorkflowNodePositions() => definition,
  };
  var nodes = document.editor.nodes;
  switch (edit) {
    case AddWorkflowState(:final value):
      nodes = [...nodes, nextWorkflowPosition(document, value.id)];
    case RenameWorkflowState(:final oldId, :final newId):
      nodes = [for (final node in nodes)
        node.stateId == oldId ? node.copyWith(stateId: newId) : node];
    case RemoveWorkflowState(:final id):
      nodes = nodes.where((node) => node.stateId != id).toList();
    case RemoveModeWorkflow():
      nodes = [];
    case EditWorkflowNodePositions(:final values):
      final graph = _requireWorkflow(workflow);
      final seen = <String>{};
      for (final node in values) {
        _requireState(graph, node.stateId);
        if (!node.x.isFinite || !node.y.isFinite || !seen.add(node.stateId)) {
          throw _invalid('Invalid workflow node position');
        }
      }
      nodes = List.of(values);
    default:
      break;
  }
  return document.copyWith(
    definition: updated,
    editor: document.editor.copyWith(nodes: nodes),
  );
}

WorkflowDefinition _requireWorkflow(WorkflowDefinition? workflow) =>
    workflow ?? (throw _invalid('No workflow is being edited'));

WorkflowState _requireState(WorkflowDefinition workflow, String id) =>
    workflow.states.where((state) => state.id == id).firstOrNull ??
    (throw _invalid('Workflow state does not exist'));

WorkflowDefinition _initial(WorkflowDefinition workflow, String id) {
  _requireState(workflow, id);
  return workflow.copyWith(initialStateId: id);
}

WorkflowDefinition _addState(WorkflowDefinition workflow, WorkflowState state) {
  if (workflow.states.any((existing) => existing.id == state.id)) {
    throw _invalid('Workflow state already exists');
  }
  if (workflow.states.length >= 32) throw _invalid('A workflow may contain at most 32 states');
  return workflow.copyWith(states: [...workflow.states, state],
    initialStateId: !workflow.states.any((value) => value.id == workflow.initialStateId) &&
        state.kind == WorkflowStateKind.atomic ? state.id : workflow.initialStateId);
}

WorkflowDefinition _renameState(WorkflowDefinition workflow, String oldId, String newId) {
  _requireState(workflow, oldId);
  if (oldId != newId && workflow.states.any((state) => state.id == newId)) {
    throw _invalid('Workflow state already exists');
  }
  return workflow.copyWith(
    initialStateId: workflow.initialStateId == oldId ? newId : workflow.initialStateId,
    states: [for (final state in workflow.states)
      state.id == oldId ? state.copyWith(id: newId) : state],
    transitions: [for (final edge in workflow.transitions) edge.copyWith(
      sourceStateId: edge.sourceStateId == oldId ? newId : edge.sourceStateId,
      targetStateId: edge.targetStateId == oldId ? newId : edge.targetStateId,
    )],
  );
}

WorkflowDefinition _removeState(WorkflowDefinition workflow, String id) {
  _requireState(workflow, id);
  final remaining = workflow.states.where((state) => state.id != id).toList();
  return workflow.copyWith(
    states: remaining,
    initialStateId: workflow.initialStateId == id
        ? remaining.where((state) => state.kind == WorkflowStateKind.atomic).firstOrNull?.id ??
          remaining.firstOrNull?.id ?? '' : workflow.initialStateId,
    transitions: workflow.transitions.where((edge) =>
      edge.sourceStateId != id && edge.targetStateId != id).toList(),
  );
}

WorkflowDefinition _replaceState(
  WorkflowDefinition workflow,
  String id,
  WorkflowState Function(WorkflowState) replace,
) {
  final updated = replace(_requireState(workflow, id));
  return workflow.copyWith(states: [for (final state in workflow.states)
    state.id == id ? updated : state]);
}

WorkflowDefinition _addTransition(WorkflowDefinition workflow, WorkflowTransition edge) {
  _requireState(workflow, edge.sourceStateId);
  _requireState(workflow, edge.targetStateId);
  if (workflow.transitions.any((existing) =>
      existing.sourceStateId == edge.sourceStateId && existing.targetStateId == edge.targetStateId)) {
    throw _invalid('Workflow transition already exists');
  }
  return workflow.copyWith(transitions: [...workflow.transitions, edge]);
}

void _requireTransition(WorkflowDefinition workflow, String source, String target) {
  if (!workflow.transitions.any((edge) => edge.sourceStateId == source && edge.targetStateId == target)) {
    throw _invalid('Workflow transition does not exist');
  }
}

WorkflowDefinition _removeTransition(WorkflowDefinition workflow, String source, String target) {
  _requireTransition(workflow, source, target);
  return workflow.copyWith(transitions: workflow.transitions.where((edge) =>
    edge.sourceStateId != source || edge.targetStateId != target).toList());
}

WorkflowDefinition _replaceGuard(WorkflowDefinition workflow, String source, String target, String guard) {
  _requireTransition(workflow, source, target);
  return workflow.copyWith(transitions: [for (final edge in workflow.transitions)
    if (edge.sourceStateId == source && edge.targetStateId == target)
      edge.copyWith(guard: guard) else edge]);
}

StudioFailure _invalid(String message) => StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: message,
  retryable: false,
  correlationId: 'mode-editor-intent',
);
