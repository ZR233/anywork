import 'dart:async';

import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/studio_typography.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../state/mode_editor_state.dart';
import '../state/mode_dialog_state.dart';
import '../view_models/mode_editor_view_model.dart';
import '../views/mode_dialog_view.dart';
import '../views/mode_editor_view.dart';

/// Also used by the Settings route/tab owner. No implicit discard from dispose.
Future<bool> confirmLeaveModeEditor(BuildContext context, WidgetRef ref, {bool Function()? isCurrent}) async {
  if (!context.mounted || isCurrent?.call() == false) return false;
  final vm = ref.read(modeEditorViewModelProvider.notifier);
  final snapshot = ref.read(modeEditorViewModelProvider);
  if (snapshot.isLoading || snapshot.hasError) return false;
  final current = snapshot.asData?.value;
  if (current == null || current.busy) return false;
  final lifetime = vm.lifetime;
  final selectedModeId = current.selectedModeId;
  final editRevision = current.editRevision;
  final latestIntent = current.latestIntent;
  bool owns() {
    if (!context.mounted || isCurrent?.call() == false ||
        !identical(ref.read(modeEditorViewModelProvider.notifier), vm) || vm.lifetime != lifetime) return false;
    final snapshot = ref.read(modeEditorViewModelProvider);
    final value = snapshot.asData?.value;
    return !snapshot.isLoading && !snapshot.hasError && value != null && !value.busy && value.selectedModeId == selectedModeId &&
      value.editRevision == editRevision && value.latestIntent == latestIntent;
  }
  if (!owns()) return false;
  if (!current.dirty) return true;
  final l10n = context.l10n;
  final choice = await showDialog<ModeLeaveChoice>(context: context, builder: (context) => AlertDialog(
    key: const ValueKey('mode-editor-unsaved-dialog'), title: Text(l10n.modeEditorUnsavedTitle), content: Text(l10n.modeEditorUnsavedBody),
    actions: [
      TextButton(key: const ValueKey('mode-editor-unsaved-cancel'), onPressed: () => Navigator.pop(context, ModeLeaveChoice.stay), child: Text(l10n.modeEditorCancel)),
      TextButton(key: const ValueKey('mode-editor-unsaved-discard'), onPressed: () => Navigator.pop(context, ModeLeaveChoice.discard), child: Text(l10n.modeEditorDiscard)),
      FilledButton(key: const ValueKey('mode-editor-unsaved-save'), onPressed: () => Navigator.pop(context, ModeLeaveChoice.save), child: Text(l10n.modeEditorSaveAndContinue)),
    ]));
  if (!owns()) return false;
  // No await between the final identity check and admission. An admitted save
  // remains the original operation even if a later navigation supersedes it.
  return vm.resolveLeave(choice ?? ModeLeaveChoice.stay);
}

class ModeEditorConnector extends ConsumerStatefulWidget {
  const ModeEditorConnector({super.key});
  @override
  ConsumerState<ModeEditorConnector> createState() => _ModeEditorConnectorState();
}

class _ModeEditorConnectorState extends ConsumerState<ModeEditorConnector> {
  bool _showingDialog = false; // Modal visibility only, never authoring data.
  bool _guarding = false;
  bool _confirming = false;
  ModeEditorViewModel get _vm => ref.read(modeEditorViewModelProvider.notifier);
  ModeEditorViewState get _current => ref.read(modeEditorViewModelProvider).requireValue;

  @override
  Widget build(BuildContext context) => ref.watch(modeEditorViewModelProvider).when(
    data: (state) => ModeEditorView(state: state, modes: _vm.visibleModes, catalogKnown: _vm.catalogKnown,
      catalogPageLoading: _vm.catalogPageLoading, onMoreModes: () => unawaited(_vm.loadModesPage()),
      errors: _errors(state), notice: _notice(state.notice),
      onOpen: (id) async => await _guard() && mounted ? _vm.open(id) : false,
      onEdit: _vm.edit, onQuery: _vm.setQuery, onTab: _vm.setTab, onSelection: _vm.select,
      onInspector: _vm.setInspectorOpen, onUndo: _vm.undo, onRedo: _vm.redo,
      onCreate: () => unawaited(_create()), onImport: () => unawaited(_import()),
      onDuplicate: () => unawaited(_duplicate()), onDelete: () => unawaited(_delete()),
      onSave: () => unawaited(_vm.save()), onReload: () => unawaited(_reload()),
      onJson: _vm.editJson, onApply: () => unawaited(_vm.applyJson()),
      onCopyJson: () => unawaited(_copyJson()), onValidate: () => unawaited(_vm.validate()),
      onSchema: () => unawaited(_schema()), onReason: _vm.setPreviewReason,
      onPreview: (target, reset) => unawaited(_vm.preview(targetStateId: target, reset: reset,
        defaultReason: context.l10n.modeEditorPreviewReasonDefault)),
      onAddState: () => _addState(false), onAddFinal: () => _addState(true),
      onAddTransition: _transitionDialog,
      onRename: _renameDialog,
      onConfirmRemoveState: _confirmRemoveState,
      onRemoveState: (id) => unawaited(_removeState(id)),
      onRemoveTransition: (source, target) => _vm.edit(ModeEdit.removeTransition(source, target)),
      onCreateTransition: (source, target) => _vm.edit(ModeEdit.addTransition(WorkflowTransition(
        sourceStateId: source, targetStateId: target, guard: context.l10n.modeEditorContinueGuardPlaceholder))),
      onRemoveWorkflow: () => unawaited(_removeWorkflow()),
      onEnableWorkflow: () => _vm.edit(ModeEdit.enableWorkflow(_minimalWorkflow(context))),
      onCriteria: _vm.setCriteriaRaw,
    ),
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, stack) {
      if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
      return Center(child: SelectableText(settingsFailureText(error)));
    },
  );

  List<String> _errors(ModeEditorViewState state) => [
    if (state.error case final error?) settingsFailureText(error),
    if (state.operation?.observationError case final error?) settingsFailureText(error),
    if (state.catalog.projection.sync.error case final error?) settingsFailureText(error),
    if (state.catalogReadError case final error?) settingsFailureText(error),
  ];

  String? _notice(ModeEditorNotice? notice) => switch (notice) {
    ModeEditorNotice.draftCreated => context.l10n.modeEditorDraftCreated,
    ModeEditorNotice.imported => context.l10n.modeEditorImportedDraft,
    ModeEditorNotice.saved => context.l10n.modeEditorSaved,
    ModeEditorNotice.deleted => context.l10n.modeEditorDeleted,
    ModeEditorNotice.copied => context.l10n.modeEditorJsonCopied,
    ModeEditorNotice.duplicated => context.l10n.modeEditorCopyCreated,
    null => null,
  };

  Future<bool> _guard() async {
    if (_showingDialog || _guarding || _confirming) return false;
    _guarding = true;
    try { return await confirmLeaveModeEditor(context, ref); }
    finally { _guarding = false; }
  }
  void _transitionDialog(String? source) {
    if (_showingDialog || _guarding || _confirming) return;
    _vm.beginTransitionDialog(sourceId: source);
    unawaited(_dialog());
  }
  void _renameDialog(String id) {
    if (_showingDialog || _guarding || _confirming) return;
    _vm.beginRenameDialog(id);
    unawaited(_dialog());
  }
  Future<void> _create() async { if (!await _guard() || !mounted) return; _vm.beginCreateDialog(); await _dialog(); }
  Future<void> _import() async { if (!await _guard() || !mounted) return; _vm.beginImportDialog(); await _dialog(); }
  Future<void> _duplicate() async {
    if (await _guard() && mounted) _vm.duplicate(context.l10n.modeEditorCopySuffix);
  }
  Future<void> _reload() async { if (await _guard() && mounted) await _vm.reload(); }

  Future<void> _dialog() async {
    if (_showingDialog || _current.dialog == null) return;
    _showingDialog = true;
    final generation = _current.dialog!.generation;
    try {
      await showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) => Consumer(
        builder: (context, ref, child) {
          final state = ref.watch(modeEditorViewModelProvider).requireValue;
          if (state.dialog == null || state.dialog!.generation != generation) return const SizedBox.shrink();
          return ModeDialogView(state: state, errors: _errors(state),
            onId: _vm.setDialogId, onName: _vm.setDialogName, onTemplate: _vm.setDialogTemplate,
            onGuard: _vm.setDialogGuard, onSource: _vm.setDialogSource, onTarget: _vm.setDialogTarget,
            onJson: _vm.editJson,
            onCancel: () { _vm.cancelDialog(); Navigator.pop(dialogContext); },
            onSubmit: () => unawaited(_submitDialog(dialogContext, state)),
          );
        },
      ));
    } finally {
      _showingDialog = false;
      if (mounted && _current.dialog?.generation == generation && !_current.busy) _vm.cancelDialog();
    }
  }

  Future<void> _submitDialog(BuildContext dialogContext, ModeEditorViewState frozen) async {
    final draft = frozen.dialog!;
    final succeeded = switch (draft.kind) {
      ModeDialogKind.create => await _vm.submitCreateDialog(ModeDocument(
        definition: ModeDefinition(id: ThreadModeId('mode.custom'), displayName: '', description: '', order: 10,
          prompt: '# ${draft.name.trim()}\n\n${context.l10n.modeEditorPromptDescription}\n',
          workflow: draft.template == ModeTemplateKind.minimal ? _minimalWorkflow(context) : null),
        editor: const ModeEditorLayout(nodes: []))),
      ModeDialogKind.importJson => await _vm.importJson(frozen.jsonText),
      ModeDialogKind.renameState || ModeDialogKind.transition => _vm.submitGraphDialog(),
    };
    if (succeeded && dialogContext.mounted) Navigator.pop(dialogContext);
  }

  Future<void> _copyJson() async {
    final frozen = _current.jsonText;
    await Clipboard.setData(ClipboardData(text: frozen));
    if (mounted && _current.jsonText == frozen) _vm.copied();
  }
  Future<void> _schema() async {
    try {
      final schema = await _vm.readSchema();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        key: const ValueKey('mode-editor-schema-dialog'), title: Text(context.l10n.modeEditorSchemaDialogTitle),
        content: SizedBox(width: 720, height: 480, child: SingleChildScrollView(child: SelectableText(schema,
          style: const TextStyle(fontFamily: studioCodeFontFamily)))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.modeEditorClose))],
      ));
    } on StudioFailure catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(settingsFailureText(error))));
    }
  }
  Future<bool> _confirm(String title, String body, String action, {String? key}) async {
    if (_showingDialog || _guarding || _confirming) return false;
    _confirming = true;
    try {
      return await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(body),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.modeEditorCancel)),
        FilledButton(key: key == null ? null : ValueKey(key), onPressed: () => Navigator.pop(context, true), child: Text(action))])) == true;
    } finally { _confirming = false; }
  }
  Future<bool> _confirmRemoveState(String id) async {
    final frozen = _current;
    final workflow = frozen.document?.definition.workflow;
    final node = workflow?.states.where((node) => node.id == id).firstOrNull;
    if (node == null) return false;
    final count = workflow!.transitions.where((edge) => edge.sourceStateId == id || edge.targetStateId == id).length;
    return await _confirm(context.l10n.modeEditorRemoveStateTitle,
      context.l10n.modeEditorRemoveStateBody(node.title, count), context.l10n.modeEditorDeleteState,
      key: 'mode-editor-remove-state-confirm') && mounted && _current.editRevision == frozen.editRevision &&
      _current.document?.definition.id == frozen.document?.definition.id;
  }
  Future<void> _removeState(String id) async { if (await _confirmRemoveState(id)) _vm.edit(ModeEdit.removeState(id)); }
  Future<void> _removeWorkflow() async {
    final frozen = _current;
    if (await _confirm(context.l10n.modeEditorRemoveWorkflowTitle, context.l10n.modeEditorRemoveWorkflowBody,
        context.l10n.modeEditorRemoveWorkflow, key: 'mode-editor-remove-workflow-confirm') && mounted &&
        _current.editRevision == frozen.editRevision) _vm.edit(const ModeEdit.removeWorkflow());
  }
  Future<void> _delete() async {
    if (!await _guard() || !mounted) return;
    final frozen = _current;
    if (await _confirm(context.l10n.modeEditorDeleteDialogTitle,
        context.l10n.modeEditorDeleteDialogBody(frozen.document!.definition.displayName),
        context.l10n.modeEditorConfirmDelete, key: 'mode-editor-delete-confirm') && mounted &&
        _current.editRevision == frozen.editRevision) await _vm.delete();
  }
  void _addState(bool finalState) {
    final l10n = context.l10n;
    _vm.addDefaultState(kind: finalState ? WorkflowStateKind.finalState : WorkflowStateKind.atomic,
      title: finalState ? l10n.modeEditorNewFinalState : l10n.modeEditorNewStage,
      instructions: finalState ? '' : l10n.modeEditorStageInstructionsPlaceholder,
      criteria: finalState ? [] : [l10n.modeEditorStageCriterionPlaceholder]);
  }
}

WorkflowDefinition _minimalWorkflow(BuildContext context) => WorkflowDefinition(
  title: context.l10n.modeEditorWorkflow, goal: context.l10n.modeEditorWorkflowGoalText, initialStateId: 'start',
  states: [WorkflowState(id: 'start', title: context.l10n.modeEditorStart,
    instructions: context.l10n.modeEditorStageInstructionsPlaceholder,
    completionCriteria: [context.l10n.modeEditorStageCriterionPlaceholder], kind: WorkflowStateKind.atomic),
    WorkflowState(id: 'done', title: context.l10n.modeEditorDone, instructions: '', completionCriteria: [], kind: WorkflowStateKind.finalState)],
  transitions: [WorkflowTransition(sourceStateId: 'start', targetStateId: 'done', guard: context.l10n.modeEditorTransitionGuardPlaceholder)],
);
