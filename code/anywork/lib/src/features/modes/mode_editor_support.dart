import 'package:anywork_client/studio_client.dart'
    show
        ModeDefinition,
        WorkflowDefinition,
        WorkflowState,
        WorkflowStateKind,
        WorkflowTransition;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Mode 编辑器与工作区的 Driver/测试身份 key。
abstract final class ModeEditorKeys {
  static const page = ValueKey<String>('mode-editor-page');
  static const workspacePage = ValueKey<String>('mode-workspace-page');
  static const backButton = ValueKey<String>('mode-workspace-back');
  static const detailBack = ValueKey<String>('mode-detail-back');
  static const tabFlow = ValueKey<String>('mode-editor-tab-flow');
  static const tabJson = ValueKey<String>('mode-editor-tab-json');
  static const tabSettings = ValueKey<String>('mode-editor-tab-settings');
  static const tabPreview = ValueKey<String>('mode-editor-tab-preview');
  static const focusAll = ValueKey<String>('mode-workspace-focus-all');
  static const focusSelected = ValueKey<String>(
    'mode-workspace-focus-selected',
  );
  static const search = ValueKey<String>('mode-editor-search');
  static const create = ValueKey<String>('mode-editor-create');
  static const importJson = ValueKey<String>('mode-editor-import');
  static const save = ValueKey<String>('mode-editor-save');
  static const copy = ValueKey<String>('mode-editor-copy');
  static const deleteMode = ValueKey<String>('mode-editor-delete');
  static const reload = ValueKey<String>('mode-editor-reload');
  static const undo = ValueKey<String>('mode-editor-undo');
  static const redo = ValueKey<String>('mode-editor-redo');
  static const addState = ValueKey<String>('mode-editor-add-state');
  static const addFinalState = ValueKey<String>('mode-editor-add-final');
  static const addTransition = ValueKey<String>('mode-editor-add-transition');
  static const inspectorAddTransition = ValueKey<String>(
    'mode-editor-inspector-add-transition',
  );
  static const validate = ValueKey<String>('mode-editor-validate');
  static const autoLayout = ValueKey<String>('mode-editor-auto-layout');
  static const fitView = ValueKey<String>('mode-editor-fit-view');
  static const zoomIn = ValueKey<String>('mode-editor-zoom-in');
  static const zoomOut = ValueKey<String>('mode-editor-zoom-out');
  static const closeDetail = ValueKey<String>('mode-editor-close-detail');
  static const enableWorkflow = ValueKey<String>('mode-editor-enable-workflow');
  static const removeWorkflow = ValueKey<String>('mode-editor-remove-workflow');
  static const jsonEditor = ValueKey<String>('mode-editor-json-editor');
  static const applyJson = ValueKey<String>('mode-editor-apply-json');
  static const copyJson = ValueKey<String>('mode-editor-copy-json');
  static const schema = ValueKey<String>('mode-editor-schema');
  static const previewStart = ValueKey<String>('mode-editor-preview-start');
  static const previewReset = ValueKey<String>('mode-editor-preview-reset');
  static const previewReason = ValueKey<String>('mode-editor-preview-reason');
  static const deleteState = ValueKey<String>('mode-editor-delete-state');
  static const deleteTransition = ValueKey<String>(
    'mode-editor-delete-transition',
  );
  static const renameState = ValueKey<String>('mode-editor-rename-state');
  static const initialSwitch = ValueKey<String>('mode-editor-initial-state');
  static const notice = ValueKey<String>('mode-editor-notice');

  static ValueKey<String> catalogItem(String id) =>
      ValueKey<String>('mode-editor-catalog-$id');

  static ValueKey<String> node(String id) =>
      ValueKey<String>('mode-editor-node-$id');

  static ValueKey<String> edge(String id) =>
      ValueKey<String>('mode-editor-edge-$id');

  static ValueKey<String> previewTarget(String id) =>
      ValueKey<String>('mode-editor-preview-target-$id');

  static ValueKey<String> settingsField(String field) =>
      ValueKey<String>('mode-editor-settings-$field');

  static ValueKey<String> detailField(String field) =>
      ValueKey<String>('mode-editor-detail-$field');
}

/// 新建模式对话框的模板选择。
enum ModeTemplateKind { minimal, none }

WorkflowDefinition minimalWorkflow(AppLocalizations l10n) => WorkflowDefinition(
  title: l10n.modeEditorWorkflow,
  goal: l10n.modeEditorWorkflowGoalText,
  initialStateId: 'start',
  states: [
    WorkflowState(
      id: 'start',
      title: l10n.modeEditorStart,
      instructions: l10n.modeEditorStageInstructionsPlaceholder,
      completionCriteria: [l10n.modeEditorStageCriterionPlaceholder],
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowState(
      id: 'done',
      title: l10n.modeEditorDone,
      instructions: '',
      completionCriteria: const [],
      kind: WorkflowStateKind.finalState,
    ),
  ],
  transitions: [
    WorkflowTransition(
      sourceStateId: 'start',
      targetStateId: 'done',
      guard: l10n.modeEditorTransitionGuardPlaceholder,
    ),
  ],
);

ModeDefinition newModeDefinition({
  required String id,
  required String displayName,
  required int order,
  required ModeTemplateKind template,
  required AppLocalizations l10n,
}) {
  final templateWorkflow = switch (template) {
    ModeTemplateKind.minimal => minimalWorkflow(l10n),
    ModeTemplateKind.none => null,
  };
  return ModeDefinition(
    id: id,
    displayName: displayName,
    description: '',
    order: order,
    prompt: '# $displayName\n\n${l10n.modeEditorPromptDescription}\n',
    workflow: templateWorkflow,
  );
}
