import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        ModeEditorLayout,
        ModeEditorState,
        ThreadModeDescriptorView,
        WorkflowState,
        WorkflowStateKind,
        WorkflowTransition;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../presentation/providers/client_provider.dart';
import '../../../presentation/providers/mode_catalog_store.dart';
import '../../../presentation/providers/mode_editor_store.dart';
import '../settings_scope.dart';
import 'mode_editor_dialogs.dart';
import 'mode_editor_inspector.dart';
import 'mode_editor_panels.dart';
import 'mode_editor_support.dart';
import 'mode_workflow_canvas.dart';

/// Settings page for catalog CRUD and workflow authoring.
class ModeEditorTab extends ConsumerStatefulWidget {
  const ModeEditorTab({super.key, required this.tabIndex});

  /// This page's index in the settings shell. Display observation is gated on
  /// visibility, while the Client keeps the draft across tab changes.
  final int tabIndex;

  @override
  ConsumerState<ModeEditorTab> createState() => _ModeEditorTabState();
}

class _ModeEditorTabState extends ConsumerState<ModeEditorTab> {
  int _tab = 0;
  String? _selectedNodeId;
  String? _selectedConnectionId;
  bool _inspectorOpen = false;
  bool _validationRequested = false;
  bool _autoOpenScheduled = false;
  String? _lastDocumentId;
  String _previewReason = '';
  String _query = '';
  String? _notice;
  Timer? _noticeTimer;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  void _showError(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
  }

  void _selectNode(String? id) {
    if (id == null) {
      if (_selectedNodeId == null && _selectedConnectionId == null) return;
      setState(() {
        _selectedNodeId = null;
        _selectedConnectionId = null;
      });
      return;
    }
    if (_selectedNodeId == id && _selectedConnectionId == null) return;
    setState(() {
      _selectedNodeId = id;
      _selectedConnectionId = null;
    });
  }

  void _selectEdge(String? id) {
    if (id == null) {
      if (_selectedNodeId == null && _selectedConnectionId == null) return;
      setState(() {
        _selectedNodeId = null;
        _selectedConnectionId = null;
      });
      return;
    }
    if (_selectedConnectionId == id && _selectedNodeId == null) return;
    setState(() {
      _selectedConnectionId = id;
      _selectedNodeId = null;
    });
  }

  void _setTab(int tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  Future<bool> _guard() => confirmLeaveModeEditor(context, ref);

  Future<void> _openMode(String id) async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    if (owner.state.document?.definition.id == id) return;
    if (!await _guard() || !mounted) return;
    final opened = await owner.open(id);
    if (!mounted) return;
    if (opened) {
      _showNotice(context.l10n.modeEditorOpenNotice(id));
    } else if (owner.state.error != null) {
      _showError(owner.state.error!);
    }
  }

  Future<void> _save() async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final l10n = context.l10n;
    try {
      await owner.validate();
      if (!mounted) return;
      if (owner.state.issues.isNotEmpty) {
        setState(() {
          _validationRequested = true;
          _tab = 0;
        });
        _showError(
          l10n.modeEditorSaveValidationIssues(owner.state.issues.length),
        );
        return;
      }
    } catch (error) {
      if (!mounted) return;
      _showError(l10n.modeEditorPreSaveValidationFailed('$error'));
      return;
    }
    final saved = await owner.save();
    if (!mounted) return;
    if (saved) {
      _validationRequested = false;
      _showNotice(l10n.modeEditorSaved);
      return;
    }
    _showError(owner.state.error ?? l10n.modeEditorSaveFailed);
  }

  Future<void> _reload() async {
    if (!await _guard() || !mounted) return;
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final l10n = context.l10n;
    final reloaded = await owner.reload();
    if (!mounted) return;
    if (reloaded) {
      _validationRequested = false;
      _showNotice(l10n.modeEditorReloaded);
      return;
    }
    _showError(owner.state.error ?? l10n.modeEditorReloadFailed);
  }

  Future<void> _deleteMode(List<ThreadModeDescriptorView> catalog) async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final document = owner.state.document;
    final l10n = context.l10n;
    if (document == null || owner.state.readOnly) return;
    if (!await confirmDeleteMode(
      context,
      displayName: document.definition.displayName,
    )) {
      return;
    }
    if (!mounted) return;
    final deletedId = document.definition.id;
    final deleted = await owner.delete();
    if (!mounted) return;
    if (!deleted) {
      _showError(owner.state.error ?? l10n.modeEditorDeleteFailed);
      return;
    }
    _showNotice(l10n.modeEditorDeleted);
    final remaining = catalog
        .where((mode) => mode.id != deletedId)
        .toList(growable: false);
    if (remaining.isNotEmpty) {
      await owner.open(_preferredMode(remaining).id);
    }
  }

  Future<void> _duplicateMode() async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    if (owner.state.document == null) return;
    if (!await _guard() || !mounted) return;
    final document = owner.state.document;
    if (document == null) return;
    final l10n = context.l10n;
    final catalog =
        ref.read(anyworkClientProvider).modeCatalog.state.value?.modes ??
        const <ThreadModeDescriptorView>[];
    final id = suggestedModeId(catalog.map((mode) => mode.id));
    final definition = duplicateDefinition(
      document.definition,
      id: id,
      displayName:
          '${document.definition.displayName} ${l10n.modeEditorCopySuffix}',
    );
    owner.create(
      id: id,
      displayName: definition.displayName,
      template: ModeDocument(definition: definition, editor: document.editor),
    );
    _showNotice(l10n.modeEditorCopyCreated);
  }

  Future<void> _createMode(List<ThreadModeDescriptorView> catalog) async {
    final result = await showCreateModeDialog(
      context,
      existingIds: catalog.map((mode) => mode.id).toSet(),
    );
    if (result == null || !mounted) return;
    if (!await _guard() || !mounted) return;
    final l10n = context.l10n;
    final owner = ref.read(anyworkClientProvider).modeEditor;
    var order = 10;
    for (final mode in catalog) {
      if (mode.order >= order) order = mode.order + 10;
    }
    final definition = newModeDefinition(
      id: result.id,
      displayName: result.displayName,
      order: order,
      template: result.template,
      l10n: l10n,
    );
    owner.create(
      id: result.id,
      displayName: result.displayName,
      template: ModeDocument(
        definition: definition,
        editor: ModeEditorLayout(nodes: const []),
      ),
    );
    _showNotice(l10n.modeEditorDraftCreated);
  }

  Future<void> _importMode(List<ThreadModeDescriptorView> catalog) async {
    final raw = await showImportModeDialog(context);
    if (raw == null || !mounted) return;
    final l10n = context.l10n;
    ModeDocument document;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _showError(l10n.modeEditorImportObjectRequired);
        return;
      }
      document = ModeDocument.fromJson(decoded);
    } catch (error) {
      _showError(l10n.modeEditorImportReadFailed('$error'));
      return;
    }
    final id = document.definition.id;
    if (!isValidModeId(id)) {
      _showError(l10n.modeEditorInvalidModeId);
      return;
    }
    ThreadModeDescriptorView? existing;
    for (final mode in catalog) {
      if (mode.id == id) {
        existing = mode;
        break;
      }
    }
    if (existing?.readOnly ?? false) {
      _showError(l10n.modeEditorBuiltInCannotOverwrite);
      return;
    }
    if (!await _guard() || !mounted) return;
    final owner = ref.read(anyworkClientProvider).modeEditor;
    if (existing == null) {
      owner.create(
        id: id,
        displayName: document.definition.displayName,
        template: document,
      );
    } else {
      if (!await owner.open(id)) return;
    }
    // Preserve the authored source for Rust validation; parsing a display draft must not drop fields.
    owner.editJson(raw);
    await owner.applyJson();
    if (!mounted) return;
    setState(() => _tab = 1);
    _showNotice(l10n.modeEditorImportedDraft);
  }

  Future<void> _copyJson() async {
    final document = ref.read(anyworkClientProvider).modeEditor.state.document;
    if (document == null) return;
    final l10n = context.l10n;
    await Clipboard.setData(ClipboardData(text: prettyDocumentJson(document)));
    if (!mounted) return;
    _showNotice(l10n.modeEditorJsonCopied);
  }

  Future<void> _showSchema() async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    try {
      final schema = await owner.schema();
      if (!mounted) return;
      await showSchemaDialog(context, schema);
    } catch (error) {
      if (!mounted) return;
      _showError(context.l10n.modeEditorSchemaReadFailed('$error'));
    }
  }

  Future<void> _validate() async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    try {
      await owner.validate();
      if (!mounted) return;
      setState(() => _validationRequested = true);
      final issues = owner.state.issues;
      _showNotice(
        issues.isEmpty
            ? context.l10n.modeEditorValidationPassed
            : context.l10n.modeEditorIssuesFound(issues.length),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(context.l10n.modeEditorValidationFailed('$error'));
    }
  }

  Future<void> _applyJson() async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final l10n = context.l10n;
    final applied = await owner.applyJson();
    if (!mounted) return;
    _validationRequested = false;
    if (applied) {
      _showNotice(l10n.modeEditorJsonApplied);
    } else {
      _showError(owner.state.error ?? l10n.modeEditorJsonApplyFailed);
    }
  }

  Future<void> _validateJson() async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final l10n = context.l10n;
    final applied = await owner.applyJson();
    if (!mounted) return;
    if (!applied) {
      setState(() => _validationRequested = true);
      _showError(owner.state.error ?? l10n.modeEditorJsonApplyFix);
      return;
    }
    await _validate();
  }

  Future<void> _preview({String? targetStateId, bool reset = false}) async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final l10n = context.l10n;
    final reason = _previewReason.trim().isEmpty
        ? l10n.modeEditorPreviewReasonDefault
        : _previewReason.trim();
    try {
      await owner.preview(
        targetStateId: targetStateId,
        reset: reset,
        reason: reason,
      );
      if (!mounted) return;
      final preview = owner.state.preview;
      if (preview != null && !preview.accepted) {
        _showNotice(preview.message);
      }
    } catch (error) {
      if (!mounted) return;
      _showError(l10n.modeEditorPreviewFailed('$error'));
    }
  }

  void _replace(ModeDocument document) {
    ref.read(anyworkClientProvider).modeEditor.replace(document);
  }

  ModeDocument? get _document =>
      ref.read(anyworkClientProvider).modeEditor.state.document;

  void _addState({required bool finalState}) {
    final document = _document;
    final workflow = document?.definition.workflow;
    if (document == null || workflow == null) return;
    final l10n = context.l10n;
    if (workflow.states.length >= maxModeWorkflowStates) {
      _showNotice(l10n.modeEditorMaxStates(maxModeWorkflowStates));
      return;
    }
    final id = nextStateId(workflow, finalState: finalState);
    final state = WorkflowState(
      id: id,
      title: finalState
          ? l10n.modeEditorNewFinalState
          : l10n.modeEditorNewStage,
      instructions: finalState
          ? ''
          : l10n.modeEditorStageInstructionsPlaceholder,
      completionCriteria: finalState
          ? const []
          : [l10n.modeEditorStageCriterionPlaceholder],
      kind: finalState
          ? WorkflowStateKind.finalState
          : WorkflowStateKind.atomic,
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
    _replace(next);
    setState(() {
      _selectedNodeId = id;
      _selectedConnectionId = null;
      _inspectorOpen = true;
    });
    _showNotice(
      finalState ? l10n.modeEditorFinalStateAdded : l10n.modeEditorStageAdded,
    );
  }

  void _removeStateById(String stateId) {
    final document = _document;
    if (document == null) return;
    final workflow = document.definition.workflow;
    if (workflow == null ||
        !workflow.states.any((state) => state.id == stateId)) {
      return;
    }
    _replace(removeState(document, stateId));
    if (_selectedNodeId == stateId) {
      setState(() {
        _selectedNodeId = null;
        _selectedConnectionId = null;
      });
    }
  }

  Future<bool> _confirmRemoveState(String stateId) async {
    final document = _document;
    final workflow = document?.definition.workflow;
    if (document == null || workflow == null) return false;
    WorkflowState? state;
    for (final candidate in workflow.states) {
      if (candidate.id == stateId) {
        state = candidate;
        break;
      }
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

  Future<void> _deleteStateFromInspector(WorkflowState state) async {
    if (await _confirmRemoveState(state.id)) {
      _removeStateById(state.id);
    }
  }

  void _removeTransition(String sourceStateId, String targetStateId) {
    final document = _document;
    final workflow = document?.definition.workflow;
    if (document == null || workflow == null) return;
    WorkflowTransition? removed;
    for (final transition in workflow.transitions) {
      if (transition.sourceStateId == sourceStateId &&
          transition.targetStateId == targetStateId) {
        removed = transition;
        break;
      }
    }
    if (removed == null) return;
    _replace(removeTransition(document, removed));
    if (_selectedConnectionId == connectionId(removed)) {
      setState(() => _selectedConnectionId = null);
    }
  }

  void _removeTransitionFromInspector(WorkflowTransition transition) {
    _removeTransition(transition.sourceStateId, transition.targetStateId);
  }

  void _createTransitionFromCanvas(String source, String target) {
    final document = _document;
    final workflow = document?.definition.workflow;
    if (document == null || workflow == null) return;
    final sourceKnown = workflow.states.any((state) => state.id == source);
    final targetKnown = workflow.states.any((state) => state.id == target);
    if (!sourceKnown || !targetKnown) return;
    final l10n = context.l10n;
    final transition = WorkflowTransition(
      sourceStateId: source,
      targetStateId: target,
      guard: l10n.modeEditorContinueGuardPlaceholder,
    );
    _replace(addTransition(document, transition));
    setState(() {
      _selectedConnectionId = connectionId(transition);
      _selectedNodeId = null;
      _inspectorOpen = true;
    });
    _showNotice(l10n.modeEditorTransitionAdded);
  }

  Future<void> _addTransition({String? sourceStateId}) async {
    final document = _document;
    final workflow = document?.definition.workflow;
    if (document == null || workflow == null) return;
    if (workflow.states.length < 2) {
      _showNotice(context.l10n.modeEditorNeedTwoStates);
      return;
    }
    final transition = await showTransitionDialog(
      context,
      workflow: workflow,
      initialSourceId: sourceStateId,
    );
    if (transition == null || !mounted) return;
    _replace(addTransition(document, transition));
    setState(() {
      _selectedConnectionId = connectionId(transition);
      _selectedNodeId = null;
      _inspectorOpen = true;
    });
  }

  Future<void> _renameState(WorkflowState state) async {
    final document = _document;
    final workflow = document?.definition.workflow;
    if (document == null || workflow == null) return;
    final id = await showRenameStateDialog(
      context,
      state: state,
      workflow: workflow,
    );
    if (id == null || !mounted || id == state.id) return;
    final next = stateWith(state, id: id);
    _replace(replaceState(document, state.id, next));
    setState(() => _selectedNodeId = id);
  }

  void _autoLayout() {
    final document = _document;
    final workflow = document?.definition.workflow;
    if (document == null || workflow == null) return;
    _replace(applyAutoLayout(document, autoLayoutOffsets(workflow)));
    _showNotice(context.l10n.modeEditorLayoutReset);
  }

  void _enableWorkflow() {
    final document = _document;
    if (document == null || document.definition.workflow != null) return;
    final l10n = context.l10n;
    _replace(documentWithWorkflow(document, minimalWorkflow(l10n)));
    _showNotice(l10n.modeEditorWorkflowEnabled);
  }

  Future<void> _removeWorkflow() async {
    final document = _document;
    if (document == null || document.definition.workflow == null) return;
    if (!await confirmRemoveWorkflow(context) || !mounted) return;
    _replace(documentWithWorkflow(document, null));
    setState(() {
      _selectedNodeId = null;
      _selectedConnectionId = null;
      _inspectorOpen = false;
    });
  }

  ThreadModeDescriptorView _preferredMode(
    List<ThreadModeDescriptorView> catalog,
  ) {
    final sorted = [...catalog]..sort((a, b) => a.order.compareTo(b.order));
    for (final mode in sorted) {
      if (mode.id == 'mode.task') return mode;
    }
    return sorted.first;
  }

  List<ThreadModeDescriptorView> _filteredCatalog(
    List<ThreadModeDescriptorView> catalog,
  ) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return catalog;
    return catalog
        .where(
          (mode) =>
              mode.displayName.toLowerCase().contains(query) ||
              mode.id.toLowerCase().contains(query) ||
              mode.description.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(settingsVisibleTabProvider) == widget.tabIndex;
    final client = ref.watch(anyworkClientProvider);
    final editor = visible
        ? ref.watch(modeEditorStateProvider)
        : client.modeEditor.state;
    final catalogState = visible
        ? ref.watch(modeCatalogStoreProvider)
        : client.modeCatalog.state;
    final catalog =
        catalogState.value?.modes ?? const <ThreadModeDescriptorView>[];
    final l10n = context.l10n;
    final document = editor.document;
    final documentId = document?.definition.id;

    if (documentId != _lastDocumentId) {
      _lastDocumentId = documentId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedNodeId = null;
          _selectedConnectionId = null;
          _validationRequested = false;
        });
      });
    }
    if (!_autoOpenScheduled &&
        visible &&
        document == null &&
        !editor.busy &&
        catalog.isNotEmpty) {
      _autoOpenScheduled = true;
      final preferred = _preferredMode(catalog);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMode(preferred.id);
      });
    }

    return KeyedSubtree(
      key: ModeEditorKeys.page,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;
          final catalogPane = _ModeCatalog(
            catalog: _filteredCatalog(catalog),
            selectedId: documentId,
            compact: compact,
            l10n: l10n,
            onQueryChanged: (value) => setState(() => _query = value),
            onOpen: _openMode,
            onCreate: () => _createMode(catalog),
            onImport: () => _importMode(catalog),
          );
          final content = _buildContent(
            context,
            l10n: l10n,
            editor: editor,
            document: document,
            catalog: catalog,
          );
          if (compact) {
            return Column(
              children: [
                SizedBox(height: 220, child: catalogPane),
                Divider(height: 1, color: context.colors.outlineVariant),
                Expanded(child: content),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 236, child: catalogPane),
              VerticalDivider(width: 1, color: context.colors.outlineVariant),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required AppLocalizations l10n,
    required ModeEditorState editor,
    required ModeDocument? document,
    required List<ThreadModeDescriptorView> catalog,
  }) {
    if (document == null) {
      return Center(
        child: editor.busy
            ? const CircularProgressIndicator()
            : Text(
                l10n.modeEditorSelectOrCreate,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          l10n: l10n,
          editor: editor,
          document: document,
          catalog: catalog,
        ),
        _tabs(context, l10n: l10n, editor: editor),
        Expanded(
          child: switch (_tab) {
            1 => ModeJsonPanel(
              text: editor.jsonText,
              issues: editor.issues,
              error: editor.error,
              readOnly: editor.readOnly,
              busy: editor.busy,
              validated: _validationRequested,
              l10n: l10n,
              onChanged: ref.read(anyworkClientProvider).modeEditor.editJson,
              onApply: _applyJson,
              onCopy: _copyJson,
              onValidate: _validateJson,
              onSchema: _showSchema,
            ),
            2 => ModeSettingsPanel(
              document: document,
              readOnly: editor.readOnly || editor.busy,
              l10n: l10n,
              onDocumentChanged: _replace,
              onEnableWorkflow: _enableWorkflow,
              onRemoveWorkflow: _removeWorkflow,
            ),
            3 => ModePreviewPanel(
              document: document,
              preview: editor.preview,
              reason: _previewReason,
              busy: editor.busy,
              l10n: l10n,
              onReasonChanged: (value) =>
                  setState(() => _previewReason = value),
              onStart: () => _preview(reset: true),
              onReset: () => _preview(reset: true),
              onAdvance: (target) => _preview(targetStateId: target),
            ),
            _ => _graphPanel(
              context,
              l10n: l10n,
              editor: editor,
              document: document,
            ),
          },
        ),
        if (_notice != null || editor.error != null)
          _noticeBar(
            context,
            message: _notice ?? editor.error!,
            isError: _notice == null,
          ),
      ],
    );
  }

  Widget _header(
    BuildContext context, {
    required AppLocalizations l10n,
    required ModeEditorState editor,
    required ModeDocument document,
    required List<ThreadModeDescriptorView> catalog,
  }) {
    final definition = document.definition;
    final readOnly = editor.readOnly;
    final busy = editor.busy;
    final dirty = editor.dirty;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                definition.displayName.isEmpty
                    ? definition.id
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
              ? definition.id
              : '${definition.id} · ${definition.description}',
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
          key: ModeEditorKeys.undo,
          tooltip: l10n.modeEditorUndo,
          onPressed: editor.canUndo
              ? ref.read(anyworkClientProvider).modeEditor.undo
              : null,
          icon: const Icon(Icons.undo, size: 18),
        ),
        IconButton(
          key: ModeEditorKeys.redo,
          tooltip: l10n.modeEditorRedo,
          onPressed: editor.canRedo
              ? ref.read(anyworkClientProvider).modeEditor.redo
              : null,
          icon: const Icon(Icons.redo, size: 18),
        ),
        IconButton(
          key: ModeEditorKeys.reload,
          tooltip: l10n.modeEditorReload,
          onPressed: busy ? null : _reload,
          icon: const Icon(Icons.refresh, size: 18),
        ),
        OutlinedButton.icon(
          key: ModeEditorKeys.copy,
          onPressed: busy ? null : _duplicateMode,
          icon: const Icon(Icons.copy_all_outlined, size: 17),
          label: Text(l10n.modeEditorDuplicate),
        ),
        if (!readOnly)
          IconButton(
            key: ModeEditorKeys.deleteMode,
            tooltip: l10n.modeEditorDeleteMode,
            onPressed: busy ? null : () => _deleteMode(catalog),
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: context.colors.error,
            ),
          ),
        if (!readOnly)
          FilledButton.icon(
            key: ModeEditorKeys.save,
            onPressed: busy ? null : _save,
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

  Widget _tabs(
    BuildContext context, {
    required AppLocalizations l10n,
    required ModeEditorState editor,
  }) {
    final tabs = [
      (
        ModeEditorKeys.tabGraph,
        l10n.modeEditorTabFlow,
        Icons.account_tree_outlined,
      ),
      (ModeEditorKeys.tabJson, l10n.modeEditorTabJson, Icons.data_object),
      (ModeEditorKeys.tabSettings, l10n.modeEditorTabSettings, Icons.tune),
      (
        ModeEditorKeys.tabPreview,
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
                  for (var index = 0; index < tabs.length; index++)
                    _TabButton(
                      key: tabs[index].$1,
                      icon: tabs[index].$3,
                      label: tabs[index].$2,
                      selected: _tab == index,
                      onTap: () => _setTab(index),
                    ),
                ],
              ),
            ),
          ),
          if (editor.dirty)
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

  Widget _graphPanel(
    BuildContext context, {
    required AppLocalizations l10n,
    required ModeEditorState editor,
    required ModeDocument document,
  }) {
    final canvas = ModeWorkflowCanvas(
      document: document,
      readOnly: editor.readOnly || editor.busy,
      l10n: l10n,
      onDocumentChanged: _replace,
      onSelectNode: _selectNode,
      onSelectEdge: _selectEdge,
      onAddState: () => _addState(finalState: false),
      onAddFinalState: () => _addState(finalState: true),
      onAddTransition: () => _addTransition(),
      onConfirmRemoveState: _confirmRemoveState,
      onRemoveState: _removeStateById,
      onRemoveTransition: _removeTransition,
      onCreateTransition: _createTransitionFromCanvas,
      onAutoLayout: _autoLayout,
      onValidate: _validate,
      onEnableWorkflow: _enableWorkflow,
      inspectorOpen: _inspectorOpen,
      onToggleInspector: () => setState(() => _inspectorOpen = !_inspectorOpen),
      selectedNodeId: _selectedNodeId,
      selectedConnectionId: _selectedConnectionId,
    );
    final inspector = ModeEditorInspector(
      document: document,
      readOnly: editor.readOnly || editor.busy,
      l10n: l10n,
      onDocumentChanged: _replace,
      onSelectNode: _selectNode,
      onSelectEdge: _selectEdge,
      onRenameState: _renameState,
      onDeleteState: _deleteStateFromInspector,
      onDeleteTransition: _removeTransitionFromInspector,
      onAddTransitionFrom: (source) => _addTransition(sourceStateId: source),
      onClose: () => setState(() => _inspectorOpen = false),
      selectedNodeId: _selectedNodeId,
      selectedConnectionId: _selectedConnectionId,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth >= 980;
        final issues = editor.issues;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: side
                  ? Row(
                      children: [
                        Expanded(child: canvas),
                        if (_inspectorOpen) ...[
                          VerticalDivider(
                            width: 1,
                            color: context.colors.outlineVariant,
                          ),
                          SizedBox(width: 300, child: inspector),
                        ],
                      ],
                    )
                  : _inspectorOpen && constraints.maxHeight < 540
                  ? SingleChildScrollView(
                      key: const ValueKey('mode-editor-narrow-scroll'),
                      child: Column(
                        children: [
                          SizedBox(height: 280, child: canvas),
                          SizedBox(height: 300, child: inspector),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(child: canvas),
                        if (_inspectorOpen)
                          SizedBox(height: 300, child: inspector),
                      ],
                    ),
            ),
            if (_validationRequested && issues.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 132),
                child: Container(
                  color: context.colors.errorContainer,
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    children: [
                      for (final issue in issues)
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
              ),
          ],
        );
      },
    );
  }

  Widget _noticeBar(
    BuildContext context, {
    required String message,
    required bool isError,
  }) {
    return Container(
      key: ModeEditorKeys.notice,
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
}

class _ModeCatalog extends StatelessWidget {
  const _ModeCatalog({
    required this.catalog,
    required this.selectedId,
    required this.compact,
    required this.l10n,
    required this.onQueryChanged,
    required this.onOpen,
    required this.onCreate,
    required this.onImport,
  });

  final List<ThreadModeDescriptorView> catalog;
  final String? selectedId;
  final bool compact;
  final AppLocalizations l10n;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final builtIn = catalog.where((mode) => mode.readOnly).toList();
    final custom = catalog.where((mode) => !mode.readOnly).toList();
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      scrollDirection: compact ? Axis.horizontal : Axis.vertical,
      children: [
        if (!compact) ...[
          _groupLabel(context, l10n.modeEditorBuiltInGroup),
          for (final mode in builtIn) _modeTile(context, mode),
          _groupLabel(context, l10n.modeEditorMyModesGroup),
          for (final mode in custom) _modeTile(context, mode),
          if (catalog.isEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                l10n.modeEditorNoMatches,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ] else ...[
          for (final mode in catalog)
            SizedBox(width: 176, child: _modeTile(context, mode)),
          if (catalog.isEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                l10n.modeEditorNoMatches,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
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
                  key: ModeEditorKeys.create,
                  tooltip: l10n.modeEditorNewMode,
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 19),
                ),
                if (compact)
                  IconButton(
                    key: ModeEditorKeys.importJson,
                    tooltip: l10n.modeEditorImportJson,
                    onPressed: onImport,
                    icon: const Icon(Icons.data_object, size: 18),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              key: ModeEditorKeys.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.modeEditorSearchHint,
                prefixIcon: const Icon(Icons.search, size: 17),
              ),
              onChanged: onQueryChanged,
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
                key: ModeEditorKeys.importJson,
                onPressed: onImport,
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

  Widget _modeTile(BuildContext context, ThreadModeDescriptorView mode) {
    final selected = mode.id == selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? context.colors.surfaceContainerHigh
            : Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        child: InkWell(
          key: ModeEditorKeys.catalogItem(mode.id),
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          onTap: () => onOpen(mode.id),
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
                        mode.displayName.isEmpty ? mode.id : mode.displayName,
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
                        mode.id,
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
