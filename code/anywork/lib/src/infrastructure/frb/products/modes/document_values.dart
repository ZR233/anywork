import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/types/mode_editor.dart' as native;
import '../../shared/exact_numbers.dart';

ModeDocument modeDocumentFromBridge(native.BridgeThreadModeDocument value) =>
    ModeDocument(
      definition: ModeDefinition(
        id: ThreadModeId(value.definition.id),
        displayName: value.definition.displayName,
        description: value.definition.description,
        order: value.definition.order,
        prompt: value.definition.prompt,
        workflow: switch (value.definition.workflow) {
          final workflow? => WorkflowDefinition(
            title: workflow.title,
            goal: workflow.goal,
            initialStateId: workflow.initialStateId,
            states: List.unmodifiable(workflow.states.map(_stateFromBridge)),
            transitions: List.unmodifiable(
              workflow.transitions.map(_transitionFromBridge),
            ),
          ),
          null => null,
        },
      ),
      editor: ModeEditorLayout(
        nodes: List.unmodifiable([
          for (final node in value.editor.nodes)
            WorkflowNodePosition(stateId: node.stateId, x: node.x, y: node.y),
        ]),
      ),
    );

native.BridgeThreadModeDocument modeDocumentToBridge(ModeDocument value) =>
    native.BridgeThreadModeDocument(
      definition: native.BridgeThreadModeDefinition(
        id: value.definition.id.id,
        displayName: value.definition.displayName,
        description: value.definition.description,
        order: _nativeOrder(value.definition.order),
        prompt: value.definition.prompt,
        workflow: switch (value.definition.workflow) {
          final workflow? => native.BridgeWorkflowDefinition(
            title: workflow.title,
            goal: workflow.goal,
            initialStateId: workflow.initialStateId,
            states: List.unmodifiable(workflow.states.map(_stateToBridge)),
            transitions: List.unmodifiable(
              workflow.transitions.map(_transitionToBridge),
            ),
          ),
          null => null,
        },
      ),
      editor: native.BridgeThreadModeEditorLayout(
        nodes: List.unmodifiable([
          for (final node in value.editor.nodes)
            native.BridgeWorkflowNodePosition(
              stateId: node.stateId,
              x: node.x,
              y: node.y,
            ),
        ]),
      ),
    );

ModeDefinitionSnapshot modeDefinitionSnapshotFromBridge(
  native.BridgeThreadModeDefinitionSnapshot value,
) => ModeDefinitionSnapshot(
  revision: exactU64(value.revision, 'Mode definition revision'),
  document: modeDocumentFromBridge(value.document),
  readOnly: value.readOnly,
);

ModeValidationResult modeValidationFromBridge(
  native.BridgeThreadModeValidationResult value,
) => ModeValidationResult(
  document: value.document == null
      ? null
      : modeDocumentFromBridge(value.document!),
  issues: List.unmodifiable([
    for (final issue in value.issues)
      ValidationIssue(
        code: issue.code,
        path: issue.path,
        message: issue.message,
      ),
  ]),
);

native.BridgeWorkflowPreviewRequest workflowPreviewToBridge(
  WorkflowPreviewRequest value,
) => native.BridgeWorkflowPreviewRequest(
  document: modeDocumentToBridge(value.document),
  path: List.unmodifiable(value.path),
  targetStateId: value.targetStateId,
  reason: value.reason,
);

WorkflowPreviewSnapshot workflowPreviewFromBridge(
  native.BridgeWorkflowPreviewSnapshot value,
) => WorkflowPreviewSnapshot(
  accepted: value.accepted,
  message: value.message,
  currentState: value.currentState == null
      ? null
      : _stateFromBridge(value.currentState!),
  transitions: List.unmodifiable(value.transitions.map(_transitionFromBridge)),
  path: List.unmodifiable(value.path),
  terminal: value.terminal,
);

WorkflowState _stateFromBridge(native.BridgeWorkflowState value) =>
    WorkflowState(
      id: value.id,
      title: value.title,
      instructions: value.instructions,
      completionCriteria: List.unmodifiable(value.completionCriteria),
      kind: switch (value.kind) {
        native.BridgeWorkflowStateKind.atomic => WorkflowStateKind.atomic,
        native.BridgeWorkflowStateKind.finalState =>
          WorkflowStateKind.finalState,
      },
    );

native.BridgeWorkflowState _stateToBridge(WorkflowState value) =>
    native.BridgeWorkflowState(
      id: value.id,
      title: value.title,
      instructions: value.instructions,
      completionCriteria: List.unmodifiable(value.completionCriteria),
      kind: switch (value.kind) {
        WorkflowStateKind.atomic => native.BridgeWorkflowStateKind.atomic,
        WorkflowStateKind.finalState =>
          native.BridgeWorkflowStateKind.finalState,
      },
    );

WorkflowTransition _transitionFromBridge(
  native.BridgeWorkflowTransition value,
) => WorkflowTransition(
  sourceStateId: value.sourceStateId,
  targetStateId: value.targetStateId,
  guard: value.guard,
);

native.BridgeWorkflowTransition _transitionToBridge(WorkflowTransition value) =>
    native.BridgeWorkflowTransition(
      sourceStateId: value.sourceStateId,
      targetStateId: value.targetStateId,
      guard: value.guard,
    );

int _nativeOrder(int value) {
  // This generated field is u32 (int), not u64 (BigInt). Do not let the FRB
  // codec truncate an out-of-range authoring value before Rust validates it.
  if (value < 0 || value > 0xffffffff) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'The Mode order integer cannot be represented exactly',
      retryable: false,
      correlationId: 'adapter-mode-order-range',
    );
  }
  return value;
}
