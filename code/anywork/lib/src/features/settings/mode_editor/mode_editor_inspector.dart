import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        WorkflowDefinition,
        WorkflowState,
        WorkflowStateKind,
        WorkflowTransition;
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'mode_editor_fields.dart';
import 'mode_editor_support.dart';

/// Property editor for the selected workflow node or transition.
class ModeEditorInspector extends StatelessWidget {
  const ModeEditorInspector({
    super.key,
    required this.document,
    required this.readOnly,
    required this.l10n,
    required this.onDocumentChanged,
    required this.onSelectNode,
    required this.onSelectEdge,
    required this.onRenameState,
    required this.onDeleteState,
    required this.onDeleteTransition,
    required this.onAddTransitionFrom,
    required this.onClose,
    this.selectedNodeId,
    this.selectedConnectionId,
  });

  final ModeDocument document;
  final bool readOnly;
  final AppLocalizations l10n;
  final ValueChanged<ModeDocument> onDocumentChanged;
  final ValueChanged<String?> onSelectNode;
  final ValueChanged<String?> onSelectEdge;
  final ValueChanged<WorkflowState> onRenameState;
  final ValueChanged<WorkflowState> onDeleteState;
  final ValueChanged<WorkflowTransition> onDeleteTransition;
  final ValueChanged<String> onAddTransitionFrom;
  final VoidCallback onClose;
  final String? selectedNodeId;
  final String? selectedConnectionId;

  WorkflowDefinition? get _workflow => document.definition.workflow;

  WorkflowState? _selectedState(WorkflowDefinition workflow) {
    final id = selectedNodeId;
    if (id == null) return null;
    for (final state in workflow.states) {
      if (state.id == id) return state;
    }
    return null;
  }

  WorkflowTransition? _selectedTransition(WorkflowDefinition workflow) {
    final id = selectedConnectionId;
    if (id == null) return null;
    for (final transition in workflow.transitions) {
      if (connectionId(transition) == id) return transition;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final workflow = _workflow;
    final state = workflow == null ? null : _selectedState(workflow);
    final transition = workflow == null ? null : _selectedTransition(workflow);
    return Material(
      color: context.colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.modeEditorFlowInspector,
                    style: context.text.titleSmall?.copyWith(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: ModeEditorKeys.closeInspector,
                  tooltip: l10n.modeEditorCollapse,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.outlineVariant),
          Expanded(
            child: workflow == null
                ? _empty(context, l10n.modeEditorNoWorkflowPeriod)
                : state != null
                ? _StateInspector(
                    document: document,
                    workflow: workflow,
                    state: state,
                    readOnly: readOnly,
                    l10n: l10n,
                    onDocumentChanged: onDocumentChanged,
                    onSelectEdge: onSelectEdge,
                    onRenameState: onRenameState,
                    onDeleteState: onDeleteState,
                    onDeleteTransition: onDeleteTransition,
                    onAddTransitionFrom: onAddTransitionFrom,
                  )
                : transition != null
                ? _TransitionInspector(
                    document: document,
                    workflow: workflow,
                    transition: transition,
                    readOnly: readOnly,
                    l10n: l10n,
                    onDocumentChanged: onDocumentChanged,
                    onSelectNode: onSelectNode,
                    onSelectEdge: onSelectEdge,
                    onDeleteTransition: onDeleteTransition,
                  )
                : _empty(context, l10n.modeEditorInspectorSelectHint),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _StateInspector extends StatelessWidget {
  const _StateInspector({
    required this.document,
    required this.workflow,
    required this.state,
    required this.readOnly,
    required this.l10n,
    required this.onDocumentChanged,
    required this.onSelectEdge,
    required this.onRenameState,
    required this.onDeleteState,
    required this.onDeleteTransition,
    required this.onAddTransitionFrom,
  });

  final ModeDocument document;
  final WorkflowDefinition workflow;
  final WorkflowState state;
  final bool readOnly;
  final AppLocalizations l10n;
  final ValueChanged<ModeDocument> onDocumentChanged;
  final ValueChanged<String?> onSelectEdge;
  final ValueChanged<WorkflowState> onRenameState;
  final ValueChanged<WorkflowState> onDeleteState;
  final ValueChanged<WorkflowTransition> onDeleteTransition;
  final ValueChanged<String> onAddTransitionFrom;

  void _update(WorkflowState next) {
    onDocumentChanged(replaceState(document, state.id, next));
  }

  @override
  Widget build(BuildContext context) {
    final initial = workflow.initialStateId == state.id;
    final outgoing = workflow.transitions
        .where((transition) => transition.sourceStateId == state.id)
        .toList(growable: false);
    return ListView(
      key: const ValueKey('mode-editor-inspector-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                state.title.isEmpty ? state.id : state.title,
                style: context.text.titleMedium?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (initial)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer,
                  borderRadius: BorderRadius.circular(StudioRadii.pill),
                ),
                child: Text(
                  l10n.modeEditorInitialBadge,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                state.id,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            if (!readOnly)
              IconButton(
                key: ModeEditorKeys.renameState,
                tooltip: l10n.modeEditorRenameId,
                onPressed: () => onRenameState(state),
                icon: const Icon(Icons.link, size: 17),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ModeEditorTextField(
          key: ModeEditorKeys.inspectorField('state-title'),
          label: l10n.modeEditorStageTitle,
          value: state.title,
          enabled: !readOnly,
          onChanged: (value) => _update(stateWith(state, title: value)),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(
            'mode-editor-inspector-kind-${state.id}-${stateKindWire(state.kind)}',
          ),
          initialValue: stateKindWire(state.kind),
          decoration: InputDecoration(labelText: l10n.modeEditorStageKind),
          items: [
            DropdownMenuItem(
              value: 'atomic',
              child: Text(l10n.modeEditorAtomicStage),
            ),
            DropdownMenuItem(
              value: 'final',
              child: Text(l10n.modeEditorFinalState),
            ),
          ],
          onChanged: readOnly
              ? null
              : (value) {
                  if (value == null) return;
                  _update(stateWith(state, kind: wireStateKind(value)));
                },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: ModeEditorKeys.initialSwitch,
          contentPadding: EdgeInsets.zero,
          value: initial,
          onChanged: readOnly || initial
              ? null
              : (value) {
                  if (!value) return;
                  onDocumentChanged(
                    documentWithWorkflow(
                      document,
                      workflowWith(workflow, initialStateId: state.id),
                    ),
                  );
                },
          title: Text(l10n.modeEditorInitialStateSwitch),
          subtitle: Text(
            initial
                ? l10n.modeEditorInitialStateLockedHint
                : l10n.modeEditorInitialStateHint,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ModeEditorTextField(
          key: ModeEditorKeys.inspectorField('state-instructions'),
          label: l10n.modeEditorStageInstructions,
          value: state.instructions,
          enabled: !readOnly,
          minLines: 4,
          maxLines: 8,
          onChanged: (value) => _update(stateWith(state, instructions: value)),
        ),
        const SizedBox(height: 12),
        ModeEditorTextField(
          key: ModeEditorKeys.inspectorField('state-criteria'),
          label: l10n.modeEditorCompletionCriteria,
          value: completionCriteriaText(state),
          enabled: !readOnly,
          minLines: 3,
          maxLines: 8,
          onChanged: (value) => _update(
            stateWith(
              state,
              completionCriteria: parseCompletionCriteria(value),
            ),
          ),
        ),
        if (state.kind == WorkflowStateKind.atomic &&
            state.completionCriteria.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.modeEditorAtomicCriteriaRequired,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.modeEditorOutgoingTransitions,
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!readOnly)
              TextButton.icon(
                key: ModeEditorKeys.inspectorAddTransition,
                onPressed: () => onAddTransitionFrom(state.id),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.modeEditorAdd),
              ),
          ],
        ),
        if (outgoing.isEmpty)
          Text(
            l10n.modeEditorNoOutgoing,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        for (final transition in outgoing)
          ListTile(
            key: ModeEditorKeys.edge(connectionId(transition)),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.arrow_forward, size: 16),
            title: Text(stateTitle(workflow, transition.targetStateId)),
            subtitle: Text(
              transition.guard.isEmpty
                  ? l10n.modeEditorGuardRequiredShort
                  : transition.guard,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelectEdge(connectionId(transition)),
            trailing: readOnly
                ? null
                : IconButton(
                    tooltip: l10n.modeEditorDeleteTransition,
                    onPressed: () => onDeleteTransition(transition),
                    icon: const Icon(Icons.close, size: 16),
                  ),
          ),
        const SizedBox(height: 12),
        if (!readOnly)
          OutlinedButton.icon(
            key: ModeEditorKeys.deleteState,
            onPressed: () => onDeleteState(state),
            icon: const Icon(Icons.delete_outline, size: 17),
            label: Text(l10n.modeEditorDeleteState),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.error,
            ),
          ),
      ],
    );
  }
}

class _TransitionInspector extends StatelessWidget {
  const _TransitionInspector({
    required this.document,
    required this.workflow,
    required this.transition,
    required this.readOnly,
    required this.l10n,
    required this.onDocumentChanged,
    required this.onSelectNode,
    required this.onSelectEdge,
    required this.onDeleteTransition,
  });

  final ModeDocument document;
  final WorkflowDefinition workflow;
  final WorkflowTransition transition;
  final bool readOnly;
  final AppLocalizations l10n;
  final ValueChanged<ModeDocument> onDocumentChanged;
  final ValueChanged<String?> onSelectNode;
  final ValueChanged<String?> onSelectEdge;
  final ValueChanged<WorkflowTransition> onDeleteTransition;

  void _updateEndpoints(
    BuildContext context, {
    String? source,
    String? target,
  }) {
    final nextSource = source ?? transition.sourceStateId;
    final nextTarget = target ?? transition.targetStateId;
    final duplicate = workflow.transitions.any(
      (existing) =>
          !identical(existing, transition) &&
          existing.sourceStateId == nextSource &&
          existing.targetStateId == nextTarget,
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.modeEditorDuplicateTransition)),
      );
      return;
    }
    final next = transitionWith(
      transition,
      sourceStateId: nextSource,
      targetStateId: nextTarget,
    );
    onDocumentChanged(replaceTransition(document, transition, next));
    onSelectEdge(connectionId(next));
  }

  @override
  Widget build(BuildContext context) {
    final atomic = workflow.states
        .where((state) => state.kind == WorkflowStateKind.atomic)
        .toList(growable: false);
    return ListView(
      key: const ValueKey('mode-editor-inspector-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Text(
          l10n.modeEditorStateTransition,
          style: context.text.titleMedium?.copyWith(
            color: context.colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${stateTitle(workflow, transition.sourceStateId)} → '
          '${stateTitle(workflow, transition.targetStateId)}',
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(
            'mode-editor-inspector-edge-source-'
            '${transition.sourceStateId}-${transition.targetStateId}',
          ),
          initialValue:
              atomic.any((state) => state.id == transition.sourceStateId)
              ? transition.sourceStateId
              : null,
          decoration: InputDecoration(labelText: l10n.modeEditorSourceState),
          items: [
            for (final state in atomic)
              DropdownMenuItem(value: state.id, child: Text(state.title)),
          ],
          onChanged: readOnly
              ? null
              : (value) {
                  if (value == null) return;
                  onSelectNode(null);
                  _updateEndpoints(context, source: value);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(
            'mode-editor-inspector-edge-target-'
            '${transition.sourceStateId}-${transition.targetStateId}',
          ),
          initialValue:
              workflow.states.any(
                (state) => state.id == transition.targetStateId,
              )
              ? transition.targetStateId
              : null,
          decoration: InputDecoration(labelText: l10n.modeEditorTargetState),
          items: [
            for (final state in workflow.states)
              DropdownMenuItem(value: state.id, child: Text(state.title)),
          ],
          onChanged: readOnly
              ? null
              : (value) {
                  if (value == null) return;
                  onSelectNode(null);
                  _updateEndpoints(context, target: value);
                },
        ),
        const SizedBox(height: 12),
        ModeEditorTextField(
          key: ModeEditorKeys.inspectorField('edge-guard'),
          label: l10n.modeEditorTransitionGuard,
          value: transition.guard,
          enabled: !readOnly,
          minLines: 3,
          maxLines: 8,
          onChanged: (value) {
            final next = transitionWith(transition, guard: value);
            onDocumentChanged(replaceTransition(document, transition, next));
          },
        ),
        const SizedBox(height: 8),
        Text(
          l10n.modeEditorTransitionRuleHint,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (!readOnly)
          OutlinedButton.icon(
            key: ModeEditorKeys.deleteTransition,
            onPressed: () => onDeleteTransition(transition),
            icon: const Icon(Icons.delete_outline, size: 17),
            label: Text(l10n.modeEditorDeleteTransition),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.error,
            ),
          ),
      ],
    );
  }
}
