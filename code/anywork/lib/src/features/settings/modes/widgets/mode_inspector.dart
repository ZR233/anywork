import 'package:anywork_client/modes.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_form_field.dart';
import '../state/mode_editor_state.dart';

class ModeInspector extends StatelessWidget {
  const ModeInspector({
    required this.state,
    required this.onEdit,
    required this.onRename,
    required this.onDeleteState,
    required this.onDeleteTransition,
    required this.onAddTransition,
    required this.onCriteria,
    required this.onClose,
    super.key,
  });
  final ModeEditorViewState state;
  final ValueChanged<ModeEdit> onEdit;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onDeleteState;
  final void Function(String source, String target) onDeleteTransition;
  final ValueChanged<String?> onAddTransition;
  final void Function(String id, String raw) onCriteria;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final workflow = state.document!.definition.workflow;
    final nodeId = switch (state.selection) {
      ModeNodeSelection(:final stateId) => stateId,
      _ => null,
    };
    final node = workflow?.states
        .where((node) => node.id == nodeId)
        .firstOrNull;
    final edge = switch (state.selection) {
      ModeEdgeSelection(:final sourceStateId, :final targetStateId) =>
        workflow?.transitions
            .where(
              (edge) =>
                  edge.sourceStateId == sourceStateId &&
                  edge.targetStateId == targetStateId,
            )
            .firstOrNull,
      _ => null,
    };
    final enabled = state.canEdit && state.jsonApplied;
    final l10n = context.l10n;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l10n.modeEditorFlowInspector),
                ),
              ),
              IconButton(
                key: const ValueKey('mode-editor-close-inspector'),
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('mode-editor-inspector-scroll'),
              padding: const EdgeInsets.all(16),
              children: [
                if (node != null) ...[
                  SelectableText(node.id),
                  TextButton(
                    key: const ValueKey('mode-editor-rename-state'),
                    onPressed: enabled ? () => onRename(node.id) : null,
                    child: Text(l10n.modeEditorRenameId),
                  ),
                  SettingsFormField(
                    key: const ValueKey('mode-editor-inspector-state-title'),
                    value: node.title,
                    label: l10n.modeEditorStageTitle,
                    enabled: enabled,
                    onChanged: (raw) =>
                        onEdit(ModeEdit.stateTitle(node.id, raw)),
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<WorkflowStateKind>(
                    key: ValueKey(
                      'mode-editor-inspector-kind-${node.id}-${node.kind == WorkflowStateKind.atomic ? 'atomic' : 'final'}',
                    ),
                    initialSelection: node.kind,
                    enabled: enabled,
                    label: Text(l10n.modeEditorStageKind),
                    dropdownMenuEntries: [
                      DropdownMenuEntry(
                        value: WorkflowStateKind.atomic,
                        label: l10n.modeEditorStageAction,
                      ),
                      DropdownMenuEntry(
                        value: WorkflowStateKind.finalState,
                        label: l10n.modeEditorFinalLabel,
                      ),
                    ],
                    onSelected: (kind) {
                      if (kind != null) {
                        onEdit(ModeEdit.stateKind(node.id, kind));
                      }
                    },
                  ),
                  SwitchListTile(
                    key: const ValueKey('mode-editor-initial-state'),
                    title: Text(l10n.modeEditorInitialStateLabel),
                    value: workflow!.initialStateId == node.id,
                    onChanged: !enabled || workflow.initialStateId == node.id
                        ? null
                        : (_) => onEdit(ModeEdit.initialState(node.id)),
                  ),
                  SettingsFormField(
                    key: const ValueKey(
                      'mode-editor-inspector-state-instructions',
                    ),
                    value: node.instructions,
                    label: l10n.modeEditorStageInstructions,
                    minLines: 5,
                    maxLines: 12,
                    enabled: enabled,
                    onChanged: (raw) =>
                        onEdit(ModeEdit.stateInstructions(node.id, raw)),
                  ),
                  const SizedBox(height: 12),
                  SettingsFormField(
                    key: const ValueKey('mode-editor-inspector-state-criteria'),
                    value:
                        state.criteriaRaw[node.id] ??
                        node.completionCriteria.join('\n'),
                    label: l10n.modeEditorCompletionCriteria,
                    minLines: 3,
                    maxLines: 8,
                    enabled: enabled,
                    onChanged: (raw) => onCriteria(node.id, raw),
                  ),
                  if (node.kind == WorkflowStateKind.atomic &&
                      node.completionCriteria.isEmpty)
                    Text(l10n.modeEditorAtomicCriteriaRequired),
                  for (final transition in workflow.transitions.where(
                    (edge) => edge.sourceStateId == node.id,
                  ))
                    ListTile(
                      title: Text(transition.targetStateId),
                      subtitle: Text(transition.guard),
                    ),
                  TextButton(
                    key: const ValueKey('mode-editor-inspector-add-transition'),
                    onPressed: enabled ? () => onAddTransition(node.id) : null,
                    child: Text(l10n.modeEditorAddTransition),
                  ),
                  TextButton(
                    key: const ValueKey('mode-editor-delete-state'),
                    onPressed: enabled ? () => onDeleteState(node.id) : null,
                    child: Text(l10n.modeEditorDeleteState),
                  ),
                ] else if (edge != null) ...[
                  SelectableText(
                    '${edge.sourceStateId} → ${edge.targetStateId}',
                  ),
                  SettingsFormField(
                    key: const ValueKey('mode-editor-inspector-edge-guard'),
                    value: edge.guard,
                    label: l10n.modeEditorTransitionGuard,
                    minLines: 4,
                    maxLines: 8,
                    enabled: enabled,
                    onChanged: (raw) => onEdit(
                      ModeEdit.transitionGuard(
                        edge.sourceStateId,
                        edge.targetStateId,
                        raw,
                      ),
                    ),
                  ),
                  Text(l10n.modeEditorTransitionRuleHint),
                  TextButton(
                    key: const ValueKey('mode-editor-delete-transition'),
                    onPressed: enabled
                        ? () => onDeleteTransition(
                            edge.sourceStateId,
                            edge.targetStateId,
                          )
                        : null,
                    child: Text(l10n.modeEditorDeleteTransition),
                  ),
                ] else if (workflow != null) ...[
                  Text(
                    l10n.modeEditorWorkflowSummary(
                      workflow.states.length,
                      workflow.transitions.length,
                    ),
                  ),
                  SettingsFormField(
                    value: workflow.title,
                    label: l10n.modeEditorWorkflowTitle,
                    enabled: enabled,
                    onChanged: (raw) => onEdit(ModeEdit.workflowTitle(raw)),
                  ),
                  const SizedBox(height: 12),
                  SettingsFormField(
                    value: workflow.goal,
                    label: l10n.modeEditorWorkflowGoal,
                    minLines: 4,
                    maxLines: 8,
                    enabled: enabled,
                    onChanged: (raw) => onEdit(ModeEdit.workflowGoal(raw)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
