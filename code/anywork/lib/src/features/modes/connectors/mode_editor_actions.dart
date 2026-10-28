import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        WorkflowState,
        WorkflowStateKind,
        WorkflowTransition,
        addState,
        addTransition,
        documentWithWorkflow,
        maxModeWorkflowStates,
        nextStateId,
        nextFreePosition,
        removeState,
        removeTransition,
        replaceState,
        stateWith,
        workflowWith;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../presentation/providers/client_provider.dart';
import '../mode_editor_dialogs.dart';
import '../state/mode_workspace_view_state.dart';
import '../view_models/mode_workspace_controller.dart';
import '../widgets/mode_stage_detail_panel.dart' show WorkflowTransitionRef;

ModeDocument? _documentOf(WidgetRef ref) =>
    ref.read(anyworkClientProvider).modeEditor.state.document;

void _replaceDocument(WidgetRef ref, ModeDocument document) =>
    ref.read(anyworkClientProvider).modeEditor.replace(document);

/// 添加一个阶段并选中它；返回 notice 文案，上限时返回上限提示。
String? addWorkflowStage(
  WidgetRef ref,
  AppLocalizations l10n, {
  required bool finalStage,
}) {
  final document = _documentOf(ref);
  final workflow = document?.definition.workflow;
  if (document == null || workflow == null) return null;
  if (workflow.states.length >= maxModeWorkflowStates) {
    return l10n.modeEditorMaxStates(maxModeWorkflowStates);
  }
  final id = nextStateId(workflow, finalState: finalStage);
  final state = WorkflowState(
    id: id,
    title: finalStage ? l10n.modeEditorNewFinalState : l10n.modeEditorNewStage,
    instructions: finalStage ? '' : l10n.modeEditorStageInstructionsPlaceholder,
    completionCriteria: finalStage
        ? const []
        : [l10n.modeEditorStageCriterionPlaceholder],
    kind: finalStage ? WorkflowStateKind.finalState : WorkflowStateKind.atomic,
  );
  var next = addState(document, state, nextFreePosition(document));
  final nextWorkflow = next.definition.workflow;
  final hasInitial =
      nextWorkflow != null &&
      nextWorkflow.states.any(
        (candidate) => candidate.id == nextWorkflow.initialStateId,
      );
  if (!hasInitial &&
      state.kind == WorkflowStateKind.atomic &&
      nextWorkflow != null) {
    next = documentWithWorkflow(
      next,
      workflowWith(nextWorkflow, initialStateId: state.id),
    );
  }
  _replaceDocument(ref, next);
  ref.read(modeWorkspaceControllerProvider.notifier).selectStage(id);
  return finalStage
      ? l10n.modeEditorFinalStateAdded
      : l10n.modeEditorStageAdded;
}

/// 删除阶段并清掉指向它的选中状态。
void removeWorkflowStage(WidgetRef ref, String stateId) {
  final document = _documentOf(ref);
  if (document == null) return;
  final workflow = document.definition.workflow;
  if (workflow == null ||
      !workflow.states.any((state) => state.id == stateId)) {
    return;
  }
  _replaceDocument(ref, removeState(document, stateId));
  final selection = ref.read(modeWorkspaceControllerProvider).selection;
  if (selection is ModeStageSelection && selection.stateId == stateId) {
    ref.read(modeWorkspaceControllerProvider.notifier).closeDetail();
  }
}

Future<bool> confirmRemoveWorkflowStage(
  BuildContext context,
  WidgetRef ref,
  String stateId,
) async {
  final workflow = _documentOf(ref)?.definition.workflow;
  if (workflow == null) return false;
  WorkflowState? state;
  for (final candidate in workflow.states) {
    if (candidate.id == stateId) state = candidate;
  }
  if (state == null) return false;
  final count = workflow.transitions
      .where(
        (transition) =>
            transition.sourceStateId == stateId ||
            transition.targetStateId == stateId,
      )
      .length;
  return confirmRemoveState(
    context,
    title: state.title.isEmpty ? state.id : state.title,
    transitionCount: count,
  );
}

void removeWorkflowTransition(WidgetRef ref, WorkflowTransitionRef target) {
  final document = _documentOf(ref);
  final workflow = document?.definition.workflow;
  if (document == null || workflow == null) return;
  WorkflowTransition? removed;
  for (final transition in workflow.transitions) {
    if (transition.sourceStateId == target.sourceStateId &&
        transition.targetStateId == target.targetStateId) {
      removed = transition;
      break;
    }
  }
  if (removed == null) return;
  _replaceDocument(ref, removeTransition(document, removed));
  final selection = ref.read(modeWorkspaceControllerProvider).selection;
  if (selection is ModeTransitionSelection &&
      selection.sourceStateId == removed.sourceStateId &&
      selection.targetStateId == removed.targetStateId) {
    ref.read(modeWorkspaceControllerProvider.notifier).closeDetail();
  }
}

/// 画布拖拽建连后创建转换并选中；返回 notice 文案。
String? createWorkflowTransition(
  WidgetRef ref,
  AppLocalizations l10n,
  String source,
  String target,
) {
  final document = _documentOf(ref);
  final workflow = document?.definition.workflow;
  if (document == null || workflow == null) return null;
  final sourceKnown = workflow.states.any((state) => state.id == source);
  final targetKnown = workflow.states.any((state) => state.id == target);
  if (!sourceKnown || !targetKnown) return null;
  final transition = WorkflowTransition(
    sourceStateId: source,
    targetStateId: target,
    guard: l10n.modeEditorContinueGuardPlaceholder,
  );
  _replaceDocument(ref, addTransition(document, transition));
  ref
      .read(modeWorkspaceControllerProvider.notifier)
      .selectTransition('edge:$source->$target');
  return l10n.modeEditorTransitionAdded;
}

Future<void> addWorkflowTransitionDialog(
  BuildContext context,
  WidgetRef ref, {
  String? sourceStateId,
}) async {
  final workflow = _documentOf(ref)?.definition.workflow;
  if (workflow == null) return;
  if (workflow.states.length < 2) {
    _snack(context, context.l10n.modeEditorNeedTwoStates);
    return;
  }
  final transition = await showTransitionDialog(
    context,
    workflow: workflow,
    initialSourceId: sourceStateId,
  );
  if (transition == null) return;
  final document = _documentOf(ref);
  if (document == null) return;
  _replaceDocument(ref, addTransition(document, transition));
  ref
      .read(modeWorkspaceControllerProvider.notifier)
      .selectTransition(
        'edge:${transition.sourceStateId}->${transition.targetStateId}',
      );
}

Future<void> renameWorkflowStageDialog(
  BuildContext context,
  WidgetRef ref,
  WorkflowState state,
) async {
  final document = _documentOf(ref);
  final workflow = document?.definition.workflow;
  if (document == null || workflow == null) return;
  final id = await showRenameStateDialog(
    context,
    state: state,
    workflow: workflow,
  );
  if (id == null || id == state.id) return;
  _replaceDocument(
    ref,
    replaceState(document, state.id, stateWith(state, id: id)),
  );
  ref.read(modeWorkspaceControllerProvider.notifier).selectStage(id);
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
