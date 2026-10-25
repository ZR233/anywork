import 'dart:async';

import 'package:anywork_client/modes.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/mode_editor_state.dart';
import '../widgets/mode_document_panels.dart';
import '../widgets/mode_inspector.dart';
import '../widgets/workflow_canvas.dart';

/// Mode catalog + workflow authoring surface.
///
/// Restores the pre-refactor two-pane page: no settings page header, a 236 px
/// catalog rail (220 px strip above 780 px), the catalog owns create/import and
/// the search field, every document action lives in the document header, tabs
/// are underline `_TabButton`s, and the notice bar sits under the content.
class ModeEditorView extends StatelessWidget {
  const ModeEditorView({
    required this.state,
    required this.modes,
    required this.catalogKnown,
    required this.catalogPageLoading,
    required this.onMoreModes,
    required this.errors,
    required this.notice,
    required this.onOpen,
    required this.onEdit,
    required this.onQuery,
    required this.onTab,
    required this.onSelection,
    required this.onInspector,
    required this.onUndo,
    required this.onRedo,
    required this.onCreate,
    required this.onImport,
    required this.onDuplicate,
    required this.onDelete,
    required this.onSave,
    required this.onReload,
    required this.onJson,
    required this.onApply,
    required this.onCopyJson,
    required this.onValidate,
    required this.onSchema,
    required this.onReason,
    required this.onPreview,
    required this.onAddState,
    required this.onAddFinal,
    required this.onAddTransition,
    required this.onRename,
    required this.onConfirmRemoveState,
    required this.onRemoveState,
    required this.onRemoveTransition,
    required this.onCreateTransition,
    required this.onRemoveWorkflow,
    required this.onEnableWorkflow,
    required this.onCriteria,
    super.key,
  });
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
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey('mode-editor-page'),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 780;
        final catalog = _catalogPane(context, compact);
        final content = _content(context);
        if (compact) {
          return Column(
            children: [
              SizedBox(height: 220, child: catalog),
              Divider(height: 1, color: context.colors.outlineVariant),
              Expanded(child: content),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 236, child: catalog),
            VerticalDivider(width: 1, color: context.colors.outlineVariant),
            Expanded(child: content),
          ],
        );
      },
    ),
  );

  Widget _content(BuildContext context) {
    final document = state.document;
    if (document == null) {
      return Center(
        child: state.busy
            ? const CircularProgressIndicator()
            : Text(
                context.l10n.modeEditorSelectOrCreate,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
      );
    }
    final message = notice ?? (errors.isNotEmpty ? errors.first : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _documentHeader(context, document),
        _tabs(context),
        Expanded(
          child: switch (state.tab) {
            ModeEditorTab.json => ModeJsonPanel(
              state: state,
              onJson: onJson,
              onApply: onApply,
              onCopy: onCopyJson,
              onValidate: onValidate,
              onSchema: onSchema,
            ),
            ModeEditorTab.settings => ModeSettingsPanel(
              state: state,
              onEdit: onEdit,
              onRemoveWorkflow: onRemoveWorkflow,
              onEnableWorkflow: onEnableWorkflow,
            ),
            ModeEditorTab.preview => ModePreviewPanel(
              state: state,
              onReason: onReason,
              onPreview: onPreview,
            ),
            ModeEditorTab.graph => _graphPanel(context),
          },
        ),
        if (message != null)
          _noticeBar(context, message, isError: notice == null),
      ],
    );
  }

  Widget _documentHeader(BuildContext context, ModeDocument document) {
    final l10n = context.l10n;
    final definition = document.definition;
    final readOnly = state.readOnly;
    final dirty = state.dirty;
    final busy = state.busy;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                definition.displayName.isEmpty
                    ? definition.id.id
                    : definition.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.headlineSmall?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (readOnly) _Chip(label: l10n.modeEditorReadOnly),
            if (dirty) ...[
              const SizedBox(width: 6),
              _Chip(
                label: l10n.modeEditorUnsaved,
                color: context.colors.tertiaryContainer,
                foreground: context.colors.onTertiaryContainer,
              ),
            ],
            if (busy) ...[
              const SizedBox(width: 10),
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          definition.description.isEmpty
              ? definition.id.id
              : '${definition.id.id} · ${definition.description}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('mode-editor-undo'),
          tooltip: l10n.modeEditorUndo,
          onPressed: state.canEdit && state.undo.isNotEmpty ? onUndo : null,
          icon: const Icon(Icons.undo, size: 18),
        ),
        IconButton(
          key: const ValueKey('mode-editor-redo'),
          tooltip: l10n.modeEditorRedo,
          onPressed: state.canEdit && state.redo.isNotEmpty ? onRedo : null,
          icon: const Icon(Icons.redo, size: 18),
        ),
        IconButton(
          key: const ValueKey('mode-editor-reload'),
          tooltip: l10n.modeEditorReload,
          onPressed: busy ? null : onReload,
          icon: const Icon(Icons.refresh, size: 18),
        ),
        OutlinedButton.icon(
          key: const ValueKey('mode-editor-copy'),
          onPressed: busy ? null : onDuplicate,
          icon: const Icon(Icons.copy_all_outlined, size: 17),
          label: Text(l10n.modeEditorDuplicate),
        ),
        if (!readOnly)
          IconButton(
            key: const ValueKey('mode-editor-delete'),
            tooltip: l10n.modeEditorDeleteMode,
            onPressed: busy ? null : onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: context.colors.error,
            ),
          ),
        if (!readOnly)
          FilledButton.icon(
            key: const ValueKey('mode-editor-save'),
            onPressed: state.canEdit && !busy ? onSave : null,
            icon: const Icon(Icons.save_outlined, size: 17),
            label: Text(l10n.modeEditorSave),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 8), actions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

  /// Underline tab strip with the trailing unsaved-draft hint.
  Widget _tabs(BuildContext context) {
    final l10n = context.l10n;
    final tabs = [
      (
        ModeEditorTab.graph,
        l10n.modeEditorTabFlow,
        Icons.account_tree_outlined,
      ),
      (ModeEditorTab.json, l10n.modeEditorTabJson, Icons.data_object),
      (ModeEditorTab.settings, l10n.modeEditorTabSettings, Icons.tune),
      (
        ModeEditorTab.preview,
        l10n.modeEditorTabPreview,
        Icons.play_circle_outline,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final tab in tabs)
                    _TabButton(
                      key: ValueKey('mode-editor-tab-${tab.$1.name}'),
                      icon: tab.$3,
                      label: tab.$2,
                      selected: state.tab == tab.$1,
                      onTap: () => onTab(tab.$1),
                    ),
                ],
              ),
            ),
          ),
          if (state.dirty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(
                l10n.modeEditorDraftUnsaved,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.tertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _graphPanel(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = WorkflowCanvas(
          document: state.document!,
          readOnly: !state.canEdit || !state.jsonApplied,
          l10n: l10n,
          selection: state.selection,
          inspectorOpen: state.inspectorOpen,
          onEdit: onEdit,
          onSelection: onSelection,
          onAddState: onAddState,
          onAddFinal: onAddFinal,
          onAddTransition: () => onAddTransition(null),
          onConfirmRemoveState: onConfirmRemoveState,
          onCreateTransition: onCreateTransition,
          onValidate: onValidate,
          onEnable: onEnableWorkflow,
          onInspector: () => onInspector(!state.inspectorOpen),
        );
        final inspector = ModeInspector(
          state: state,
          onEdit: onEdit,
          onRename: onRename,
          onDeleteState: onRemoveState,
          onDeleteTransition: onRemoveTransition,
          onAddTransition: onAddTransition,
          onCriteria: onCriteria,
          onClose: () => onInspector(false),
        );
        final Widget pane;
        if (!state.inspectorOpen) {
          pane = canvas;
        } else if (constraints.maxWidth >= 980) {
          // Pre-refactor inspector geometry: 300 px side column with a hairline.
          pane = Row(
            children: [
              Expanded(child: canvas),
              VerticalDivider(width: 1, color: context.colors.outlineVariant),
              SizedBox(width: 300, child: inspector),
            ],
          );
        } else if (constraints.maxHeight < 540) {
          pane = SingleChildScrollView(
            key: const ValueKey('mode-editor-narrow-scroll'),
            child: Column(
              children: [
                SizedBox(height: 280, child: canvas),
                SizedBox(height: 300, child: inspector),
              ],
            ),
          );
        } else {
          pane = Column(
            children: [
              Expanded(child: canvas),
              SizedBox(height: 300, child: inspector),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: pane),
            if (state.validationRequested && state.issues.isNotEmpty)
              _issuesBar(context),
          ],
        );
      },
    );
  }

  /// Validation results strip: a bounded error surface under the canvas.
  Widget _issuesBar(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 132),
      child: Container(
        color: context.colors.errorContainer,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          children: [
            for (final issue in state.issues)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${issue.code} · ${issue.path} · ${issue.message}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onErrorContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _noticeBar(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    return Container(
      key: const ValueKey('mode-editor-notice'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: isError
          ? context.colors.errorContainer
          : context.colors.surfaceContainerHigh,
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall?.copyWith(
          color: isError
              ? context.colors.onErrorContainer
              : context.colors.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Catalog rail: title + create/import, search field, grouped list, and the
  /// import/read-only footer on the wide layout.
  Widget _catalogPane(BuildContext context, bool compact) {
    final l10n = context.l10n;
    final builtIn = modes.where((mode) => mode.readOnly).toList();
    final custom = modes.where((mode) => !mode.readOnly).toList();
    final list = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            notification.dragDetails != null &&
            notification.metrics.extentAfter < 160 &&
            !catalogKnown &&
            !catalogPageLoading) {
          onMoreModes();
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        scrollDirection: compact ? Axis.horizontal : Axis.vertical,
        children: [
          if (!compact) ...[
            _groupLabel(context, l10n.modeEditorBuiltInGroup),
            for (final mode in builtIn)
              _modeTile(context, mode, compact: false),
            _groupLabel(context, l10n.modeEditorMyModesGroup),
            for (final mode in custom) _modeTile(context, mode, compact: false),
          ] else ...[
            for (final mode in modes)
              SizedBox(
                width: 176,
                child: _modeTile(context, mode, compact: true),
              ),
          ],
          if (modes.isEmpty && catalogKnown)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                l10n.modeEditorNoMatches,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          if (catalogPageLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(),
              ),
            ),
          if (!catalogKnown)
            Center(
              child: IconButton(
                key: const ValueKey('mode-editor-more-modes'),
                onPressed: catalogPageLoading ? null : onMoreModes,
                tooltip: l10n.settingsSshNextPage,
                icon: const Icon(Icons.expand_more),
              ),
            ),
        ],
      ),
    );
    return Material(
      color: context.colors.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.modeEditorTitle,
                    style: context.text.titleSmall?.copyWith(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('mode-editor-create'),
                  tooltip: l10n.modeEditorNewMode,
                  onPressed: state.busy ? null : onCreate,
                  icon: const Icon(Icons.add, size: 19),
                ),
                if (compact)
                  IconButton(
                    key: const ValueKey('mode-editor-import'),
                    tooltip: l10n.modeEditorImportJson,
                    onPressed: state.busy ? null : onImport,
                    icon: const Icon(Icons.data_object, size: 18),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              key: const ValueKey('mode-editor-search'),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.modeEditorSearchHint,
                prefixIcon: const Icon(Icons.search, size: 17),
              ),
              onChanged: onQuery,
            ),
          ),
          if (compact)
            SizedBox(height: 88, child: list)
          else
            Expanded(child: list),
          if (!compact) ...[
            Divider(height: 1, color: context.colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: TextButton.icon(
                key: const ValueKey('mode-editor-import'),
                onPressed: state.busy ? null : onImport,
                icon: const Icon(Icons.data_object, size: 17),
                label: Text(l10n.modeEditorImportJson),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                l10n.modeEditorCatalogReadOnlyHint,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeTile(
    BuildContext context,
    ThreadModeDescriptor mode, {
    required bool compact,
  }) {
    return _modeEntry(context, mode);
  }

  Widget _groupLabel(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
    child: Text(
      label,
      style: context.text.labelSmall?.copyWith(
        color: context.colors.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _modeEntry(BuildContext context, ThreadModeDescriptor mode) {
    final selected = mode.id.id == state.selectedModeId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? context.colors.surfaceContainerHigh
            : Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        child: InkWell(
          key: ValueKey('mode-editor-catalog-${mode.id.id}'),
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          onTap: () => unawaited(onOpen(mode.id.id)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? context.colors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              borderRadius: BorderRadius.circular(StudioRadii.sm),
            ),
            child: Row(
              children: [
                Icon(
                  mode.readOnly
                      ? Icons.lock_outline
                      : mode.hasWorkflow
                      ? Icons.account_tree_outlined
                      : Icons.notes_outlined,
                  size: 16,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.displayName.isEmpty
                            ? mode.id.id
                            : mode.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurface,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      Text(
                        mode.id.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? context.colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? context.colors.onSurface
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.text.labelMedium?.copyWith(
                  color: selected
                      ? context.colors.onSurface
                      : context.colors.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.color, this.foreground});

  final String label;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(StudioRadii.pill),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: foreground ?? context.colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
