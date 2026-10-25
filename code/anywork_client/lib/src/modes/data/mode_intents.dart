import '../domain/mode_documents.dart';

/// Snapshot all caller-owned graph collections before admission/dispatch. No
/// parsing, normalization or validation policy is duplicated from Rust.
ModeDocument freezeModeDocument(ModeDocument value) {
  final workflow = value.definition.workflow;
  return value.copyWith(
    definition: value.definition.copyWith(
      workflow: workflow == null
          ? null
          : workflow.copyWith(
              states: List.unmodifiable([
                for (final state in workflow.states)
                  state.copyWith(
                    completionCriteria: List.unmodifiable(
                      state.completionCriteria,
                    ),
                  ),
              ]),
              transitions: List.unmodifiable(workflow.transitions),
            ),
    ),
    editor: value.editor.copyWith(nodes: List.unmodifiable(value.editor.nodes)),
  );
}

ModeDefinitionSnapshot freezeModeDefinition(ModeDefinitionSnapshot value) =>
    value.copyWith(document: freezeModeDocument(value.document));

WorkflowPreviewRequest freezeWorkflowPreview(WorkflowPreviewRequest value) =>
    value.copyWith(
      document: freezeModeDocument(value.document),
      path: List.unmodifiable(value.path),
    );

WorkflowPreviewSnapshot freezeWorkflowPreviewResult(
  WorkflowPreviewSnapshot value,
) => value.copyWith(
  currentState: value.currentState?.copyWith(
    completionCriteria: List.unmodifiable(
      value.currentState!.completionCriteria,
    ),
  ),
  transitions: List.unmodifiable(value.transitions),
  path: List.unmodifiable(value.path),
);
