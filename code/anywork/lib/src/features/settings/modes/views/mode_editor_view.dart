import 'dart:async';

import 'package:anywork_client/modes.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_pane.dart';
import '../state/mode_editor_state.dart';
import '../widgets/mode_document_panels.dart';
import '../widgets/mode_inspector.dart';
import '../widgets/workflow_canvas.dart';

class ModeEditorView extends StatelessWidget {
  const ModeEditorView({required this.state, required this.modes, required this.catalogKnown,
    required this.catalogPageLoading, required this.onMoreModes,
    required this.errors, required this.notice, required this.onOpen, required this.onEdit,
    required this.onQuery, required this.onTab, required this.onSelection, required this.onInspector,
    required this.onUndo, required this.onRedo, required this.onCreate, required this.onImport,
    required this.onDuplicate, required this.onDelete, required this.onSave, required this.onReload,
    required this.onJson, required this.onApply, required this.onCopyJson, required this.onValidate,
    required this.onSchema, required this.onReason, required this.onPreview,
    required this.onAddState, required this.onAddFinal, required this.onAddTransition,
    required this.onRename, required this.onConfirmRemoveState, required this.onRemoveState,
    required this.onRemoveTransition, required this.onCreateTransition, required this.onRemoveWorkflow,
    required this.onEnableWorkflow, required this.onCriteria, super.key});
  final ModeEditorViewState state;
  final List<ThreadModeDescriptor> modes;
  final bool catalogKnown;
  final bool catalogPageLoading;
  final VoidCallback onMoreModes;
  final List<String> errors;
  final String? notice;
  final Future<bool> Function(String id) onOpen;
  final ValueChanged<ModeEdit> onEdit;
  final ValueChanged<String> onQuery;
  final ValueChanged<ModeEditorTab> onTab;
  final ValueChanged<ModeEditorSelection> onSelection;
  final ValueChanged<bool> onInspector;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onCreate;
  final VoidCallback onImport;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onSave;
  final VoidCallback onReload;
  final ValueChanged<String> onJson;
  final VoidCallback onApply;
  final VoidCallback onCopyJson;
  final VoidCallback onValidate;
  final VoidCallback onSchema;
  final ValueChanged<String> onReason;
  final void Function(String? target, bool reset) onPreview;
  final VoidCallback onAddState;
  final VoidCallback onAddFinal;
  final ValueChanged<String?> onAddTransition;
  final ValueChanged<String> onRename;
  final Future<bool> Function(String id) onConfirmRemoveState;
  final ValueChanged<String> onRemoveState;
  final void Function(String source, String target) onRemoveTransition;
  final void Function(String source, String target) onCreateTransition;
  final VoidCallback onRemoveWorkflow;
  final VoidCallback onEnableWorkflow;
  final void Function(String id, String raw) onCriteria;

  @override
  Widget build(BuildContext context) => SettingsPane(
    key: const ValueKey('mode-editor-page'), title: context.l10n.modeEditorTitle,
    subtitle: context.l10n.modeEditorCatalogReadOnlyHint,
    toolbar: Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton(key: const ValueKey('mode-editor-create'), onPressed: state.busy ? null : onCreate, child: Text(context.l10n.modeEditorNewMode)),
      OutlinedButton(key: const ValueKey('mode-editor-import'), onPressed: state.busy ? null : onImport, child: Text(context.l10n.modeEditorImportJson)),
      OutlinedButton(key: const ValueKey('mode-editor-reload'), onPressed: state.busy ? null : onReload, child: Text(context.l10n.modeEditorReload)),
      IconButton(key: const ValueKey('mode-editor-undo'), onPressed: state.canEdit && state.undo.isNotEmpty ? onUndo : null,
        tooltip: context.l10n.modeEditorUndo, icon: const Icon(Icons.undo)),
      IconButton(key: const ValueKey('mode-editor-redo'), onPressed: state.canEdit && state.redo.isNotEmpty ? onRedo : null,
        tooltip: context.l10n.modeEditorRedo, icon: const Icon(Icons.redo)),
      OutlinedButton(key: const ValueKey('mode-editor-copy'), onPressed: state.document == null || state.busy ? null : onDuplicate,
        child: Text(context.l10n.modeEditorDuplicate)),
      OutlinedButton(key: const ValueKey('mode-editor-delete'), onPressed: state.document == null || state.readOnly || state.busy ? null : onDelete,
        child: Text(context.l10n.modeEditorDeleteMode)),
      FilledButton(key: const ValueKey('mode-editor-save'), onPressed: state.canEdit && !state.busy ? onSave : null,
        child: Text(context.l10n.modeEditorSave)),
      if (state.dirty) Text(context.l10n.modeEditorUnsaved),
      if (state.readOnly) Text(context.l10n.modeEditorReadOnly),
    ]),
    child: Column(children: [
      if (state.busy) const LinearProgressIndicator(),
      for (final error in errors) StudioInlineMessage(icon: Icons.error_outline, message: error, color: Theme.of(context).colorScheme.error),
      if (notice != null) Text(notice!, key: const ValueKey('mode-editor-notice')),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final catalog = _catalog(context);
        final editor = _editor(context);
        return constraints.maxWidth >= 1000
          ? Row(children: [SizedBox(width: 240, child: catalog), const VerticalDivider(), Expanded(child: editor)])
          : Column(children: [SizedBox(height: constraints.maxHeight < 450 ? 120 : 170, child: catalog), const Divider(), Expanded(child: editor)]);
      })),
    ]),
  );

  Widget _catalog(BuildContext context) => Column(children: [
    SettingsFormField(key: const ValueKey('mode-editor-search'), value: state.query,
      label: context.l10n.modeEditorSearchHint, onChanged: onQuery),
    Expanded(child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification && notification.dragDetails != null &&
            notification.metrics.extentAfter < 160 && !catalogKnown && !catalogPageLoading) onMoreModes();
        return false;
      }, child: ListView(children: [
      for (final readOnly in [true, false]) ...[
        Text(readOnly ? context.l10n.modeEditorBuiltInGroup : context.l10n.modeEditorMyModesGroup),
        for (final mode in modes.where((mode) => mode.readOnly == readOnly)) ListTile(
          key: ValueKey('mode-editor-catalog-${mode.id.id}'), title: Text(mode.displayName), subtitle: Text(mode.id.id),
          selected: mode.id.id == state.selectedModeId, enabled: !state.busy,
          onTap: () => unawaited(onOpen(mode.id.id))),
      ],
      if (modes.isEmpty && catalogKnown) Text(context.l10n.modeEditorNoMatches),
      if (catalogPageLoading) const Center(child: CircularProgressIndicator()),
      if (!catalogKnown) IconButton(onPressed: catalogPageLoading ? null : onMoreModes,
        tooltip: context.l10n.settingsSshNextPage, icon: const Icon(Icons.expand_more)),
    ]))),
  ]);

  Widget _editor(BuildContext context) {
    if (state.document == null) return Center(child: Text(context.l10n.modeEditorSelectOrCreate));
    final l10n = context.l10n;
    return Column(children: [
      Wrap(spacing: 8, children: [
        for (final tab in ModeEditorTab.values) TextButton(
          key: ValueKey('mode-editor-tab-${tab.name}'), onPressed: () => onTab(tab),
          child: Text([l10n.modeEditorTabFlow, l10n.modeEditorTabJson, l10n.modeEditorTabSettings, l10n.modeEditorTabPreview][tab.index])),
      ]),
      Expanded(child: switch (state.tab) {
        ModeEditorTab.graph => LayoutBuilder(builder: (context, constraints) {
          final canvas = WorkflowCanvas(document: state.document!, readOnly: !state.canEdit || !state.jsonApplied,
            l10n: l10n, selection: state.selection, inspectorOpen: state.inspectorOpen,
            onEdit: onEdit, onSelection: onSelection, onAddState: onAddState,
            onAddFinal: onAddFinal, onAddTransition: () => onAddTransition(null),
            onConfirmRemoveState: onConfirmRemoveState, onCreateTransition: onCreateTransition,
            onValidate: onValidate, onEnable: onEnableWorkflow, onInspector: () => onInspector(!state.inspectorOpen));
          if (!state.inspectorOpen) return canvas;
          final inspector = ModeInspector(state: state, onEdit: onEdit, onRename: onRename,
            onDeleteState: onRemoveState, onDeleteTransition: onRemoveTransition,
            onAddTransition: onAddTransition, onCriteria: onCriteria, onClose: () => onInspector(false));
          return constraints.maxWidth >= 780
            ? Row(children: [Expanded(child: canvas), SizedBox(width: 320, child: inspector)])
            : Column(children: [Expanded(child: canvas), SizedBox(height: constraints.maxHeight * 0.5, child: inspector)]);
        }),
        ModeEditorTab.json => ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, children: [
            FilledButton(key: const ValueKey('mode-editor-apply-json'), onPressed: state.canEdit && !state.busy ? onApply : null, child: Text(l10n.modeEditorApplyJson)),
            OutlinedButton(key: const ValueKey('mode-editor-copy-json'), onPressed: onCopyJson, child: Text(l10n.modeEditorCopyJson)),
            OutlinedButton(onPressed: state.busy ? null : onValidate, child: Text(l10n.modeEditorValidate)),
            TextButton(key: const ValueKey('mode-editor-schema'), onPressed: onSchema, child: Text(l10n.modeEditorSchemaLabel)),
          ]),
          SettingsFormField(key: const ValueKey('mode-editor-json-editor'), value: state.jsonText,
            label: l10n.modeEditorJsonHint, enabled: state.canEdit, minLines: 20, maxLines: null, code: true, onChanged: onJson),
          if (state.validationRequested && state.issues.isEmpty) Text(l10n.modeEditorValidationPassed),
          for (final issue in state.issues) SelectableText('${issue.path}: ${issue.message} [${issue.code}]'),
        ]),
        ModeEditorTab.settings => ModeSettingsPanel(state: state, onEdit: onEdit, onRemoveWorkflow: onRemoveWorkflow),
        ModeEditorTab.preview => ModePreviewPanel(state: state, onReason: onReason, onPreview: onPreview),
      }),
    ]);
  }
}
