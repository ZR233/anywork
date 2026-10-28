import 'dart:async';

import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        ModeEditorState,
        ModeValidationIssue,
        ThreadModeDescriptorView,
        WorkflowDefinition,
        WorkflowState,
        WorkflowTransition,
        applyAutoLayout,
        autoLayoutOffsets,
        documentWithWorkflow,
        duplicateDefinition,
        prettyDocumentJson,
        suggestedModeId;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../presentation/providers/client_provider.dart';
import '../../../presentation/providers/mode_catalog_store.dart';
import '../../../presentation/providers/mode_editor_store.dart';
import '../mode_editor_dialogs.dart';
import '../mode_editor_support.dart';
import '../connectors/mode_editor_actions.dart';
import '../state/mode_workspace_view_state.dart';
import '../view_models/mode_workspace_controller.dart';
import '../widgets/mode_editor_panes.dart';
import '../widgets/mode_stage_detail_panel.dart';
import '../widgets/mode_transition_detail_panel.dart';
import '../widgets/mode_workflow_canvas.dart';

/// 宽屏（画布与右侧详情并排）与窄屏（详情作为子路由页面）的断点。
const double modeWorkspaceWideBreakpoint = 960;

/// 任务模式全屏工作区（`mode-workspace` 路由）。
///
/// 顶部返回与身份信息、紧凑 TabBar（流程 | 预演 | JSON | 设置）；
/// 流程分区中点击阶段卡片或连线即展开详情：宽屏右侧面板，窄屏进入
/// `mode-detail` 子路由页。文档草稿归 Client owner 所有，本页只装配
/// 视图状态与动作。
class ModeWorkspacePage extends ConsumerStatefulWidget {
  const ModeWorkspacePage({super.key, required this.modeId});

  final String modeId;

  @override
  ConsumerState<ModeWorkspacePage> createState() => _ModeWorkspacePageState();
}

class _ModeWorkspacePageState extends ConsumerState<ModeWorkspacePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: 0,
  );
  String? _lastDocumentId;
  String? _notice;
  Timer? _noticeTimer;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    final section = ref.read(modeWorkspaceControllerProvider).section;
    _tabs.index = section.index;
    _tabs.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIfNeeded());
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    final section = ModeWorkspaceSection.values[_tabs.index];
    ref.read(modeWorkspaceControllerProvider.notifier).setSection(section);
  }

  Future<void> _openIfNeeded() async {
    if (!mounted || _opening) return;
    final owner = ref.read(anyworkClientProvider).modeEditor;
    if (owner.state.document?.definition.id == widget.modeId) return;
    _opening = true;
    try {
      final opened = await owner.open(widget.modeId);
      if (!mounted) return;
      if (!opened && owner.state.error != null) {
        _showError(owner.state.error!);
      }
    } finally {
      _opening = false;
    }
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

  // ---------------------------------------------------------------------------
  // 命令动作（全部直接转发 Client owner）
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final l10n = context.l10n;
    try {
      await owner.validate();
      if (!mounted) return;
      if (owner.state.issues.isNotEmpty) {
        ref.read(modeWorkspaceControllerProvider.notifier)
          ..requestValidation()
          ..setSection(ModeWorkspaceSection.flow);
        _tabs.index = ModeWorkspaceSection.flow.index;
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
      ref
          .read(modeWorkspaceControllerProvider.notifier)
          .clearValidationRequest();
      _showNotice(l10n.modeEditorSaved);
      return;
    }
    _showError(owner.state.error ?? l10n.modeEditorSaveFailed);
  }

  Future<void> _reload() async {
    if (!await confirmLeaveModeEditor(context, ref) || !mounted) return;
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final l10n = context.l10n;
    final reloaded = await owner.reload();
    if (!mounted) return;
    if (reloaded) {
      ref
          .read(modeWorkspaceControllerProvider.notifier)
          .clearValidationRequest();
      _showNotice(l10n.modeEditorReloaded);
      return;
    }
    _showError(owner.state.error ?? l10n.modeEditorReloadFailed);
  }

  Future<void> _deleteMode() async {
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
    final deleted = await owner.delete();
    if (!mounted) return;
    if (!deleted) {
      _showError(owner.state.error ?? l10n.modeEditorDeleteFailed);
      return;
    }
    _showNotice(l10n.modeEditorDeleted);
    if (context.canPop()) context.pop();
  }

  Future<void> _duplicateMode() async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    if (owner.state.document == null) return;
    if (!await confirmLeaveModeEditor(context, ref) || !mounted) return;
    final document = owner.state.document;
    if (document == null) return;
    final l10n = context.l10n;
    final catalog =
        ref.read(modeCatalogStoreProvider).value?.modes ??
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
    if (!mounted) return;
    _showNotice(l10n.modeEditorCopyCreated);
    context.pushReplacementNamed(
      'mode-workspace',
      pathParameters: {'modeId': id},
    );
  }

  Future<void> _copyJson() async {
    final document = ref.read(anyworkClientProvider).modeEditor.state.document;
    if (document == null) return;
    await Clipboard.setData(ClipboardData(text: prettyDocumentJson(document)));
    if (!mounted) return;
    _showNotice(context.l10n.modeEditorJsonCopied);
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
      ref.read(modeWorkspaceControllerProvider.notifier).requestValidation();
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
    ref.read(modeWorkspaceControllerProvider.notifier).clearValidationRequest();
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
      ref.read(modeWorkspaceControllerProvider.notifier).requestValidation();
      _showError(owner.state.error ?? l10n.modeEditorJsonApplyFix);
      return;
    }
    await _validate();
  }

  Future<void> _preview({String? targetStateId, bool reset = false}) async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final l10n = context.l10n;
    final reason = ref
        .read(modeWorkspaceControllerProvider)
        .previewReason
        .trim();
    try {
      await owner.preview(
        targetStateId: targetStateId,
        reset: reset,
        reason: reason.isEmpty ? l10n.modeEditorPreviewReasonDefault : reason,
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

  // ---------------------------------------------------------------------------
  // 工作流编辑动作
  // ---------------------------------------------------------------------------

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
    ref.read(modeWorkspaceControllerProvider.notifier).closeDetail();
  }

  // ---------------------------------------------------------------------------
  // 布局
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(modeEditorStateProvider);
    final viewState = ref.watch(modeWorkspaceControllerProvider);
    final document = editor.document;
    final documentId = document?.definition.id;

    // 文档切换后重置与旧文档绑定的呈现状态（选中、校验请求、聚焦）。
    if (documentId != _lastDocumentId) {
      _lastDocumentId = documentId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(modeWorkspaceControllerProvider.notifier).resetForDocument();
        }
      });
    }
    return KeyedSubtree(
      key: ModeEditorKeys.workspacePage,
      child: Scaffold(
        appBar: _appBar(context, editor: editor, document: document),
        body: document == null
            ? Center(
                child: editor.busy
                    ? const CircularProgressIndicator()
                    : Text(
                        context.l10n.modeEditorSelectOrCreate,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: switch (viewState.section) {
                      ModeWorkspaceSection.json => ModeJsonPanel(
                        text: editor.jsonText,
                        issues: editor.issues,
                        error: editor.error,
                        readOnly: editor.readOnly,
                        busy: editor.busy,
                        validated: viewState.validationRequested,
                        l10n: context.l10n,
                        onChanged: ref
                            .read(anyworkClientProvider)
                            .modeEditor
                            .editJson,
                        onApply: _applyJson,
                        onCopy: _copyJson,
                        onValidate: _validateJson,
                        onSchema: _showSchema,
                      ),
                      ModeWorkspaceSection.settings => ModeSettingsPanel(
                        document: document,
                        readOnly: editor.readOnly || editor.busy,
                        l10n: context.l10n,
                        onDocumentChanged: _replace,
                        onEnableWorkflow: _enableWorkflow,
                        onRemoveWorkflow: _removeWorkflow,
                      ),
                      ModeWorkspaceSection.preview => ModePreviewPanel(
                        document: document,
                        preview: editor.preview,
                        reason: viewState.previewReason,
                        busy: editor.busy,
                        l10n: context.l10n,
                        onReasonChanged: (value) => ref
                            .read(modeWorkspaceControllerProvider.notifier)
                            .setPreviewReason(value),
                        onStart: () => _preview(reset: true),
                        onReset: () => _preview(reset: true),
                        onAdvance: (target) => _preview(targetStateId: target),
                      ),
                      ModeWorkspaceSection.flow => _flowSection(
                        context,
                        editor: editor,
                        document: document,
                        viewState: viewState,
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
              ),
      ),
    );
  }

  PreferredSizeWidget _appBar(
    BuildContext context, {
    required ModeEditorState editor,
    required ModeDocument? document,
  }) {
    final l10n = context.l10n;
    final readOnly = editor.readOnly;
    final busy = editor.busy;
    final dirty = editor.dirty;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final title = document?.definition.displayName.isEmpty ?? true
        ? document?.definition.id ?? ''
        : document!.definition.displayName;
    return AppBar(
      toolbarHeight: 64,
      leading: BackButton(
        key: ModeEditorKeys.backButton,
        onPressed: () async {
          if (!await confirmLeaveModeEditor(context, ref)) return;
          if (!mounted) return;
          if (this.context.canPop()) this.context.pop();
        },
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium?.copyWith(
                color: context.colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (readOnly)
            _AppBarChip(
              label: l10n.modeEditorReadOnly,
              icon: Icons.lock_outline,
            ),
          if (dirty) ...[
            const SizedBox(width: 6),
            _AppBarChip(
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
      actions: [
        if (!readOnly && !compact)
          IconButton(
            key: ModeEditorKeys.undo,
            tooltip: l10n.modeEditorUndo,
            onPressed: editor.canUndo
                ? ref.read(anyworkClientProvider).modeEditor.undo
                : null,
            icon: const Icon(Icons.undo, size: 18),
          ),
        if (!readOnly && !compact)
          IconButton(
            key: ModeEditorKeys.redo,
            tooltip: l10n.modeEditorRedo,
            onPressed: editor.canRedo
                ? ref.read(anyworkClientProvider).modeEditor.redo
                : null,
            icon: const Icon(Icons.redo, size: 18),
          ),
        if (compact)
          IconButton(
            key: ModeEditorKeys.copy,
            tooltip: l10n.modeEditorDuplicate,
            onPressed: busy ? null : _duplicateMode,
            icon: const Icon(Icons.copy_all_outlined, size: 18),
          )
        else
          OutlinedButton.icon(
            key: ModeEditorKeys.copy,
            onPressed: busy ? null : _duplicateMode,
            icon: const Icon(Icons.copy_all_outlined, size: 17),
            label: Text(l10n.modeEditorDuplicate),
          ),
        if (readOnly)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: FilledButton.icon(
              onPressed: () {
                _tabs.index = ModeWorkspaceSection.preview.index;
                ref
                    .read(modeWorkspaceControllerProvider.notifier)
                    .setSection(ModeWorkspaceSection.preview);
              },
              icon: const Icon(Icons.play_arrow_outlined, size: 18),
              label: Text(l10n.modeEditorTabPreview),
            ),
          ),
        if (!readOnly)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: ModeEditorKeys.save,
              onPressed: busy ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 17),
              label: Text(l10n.modeEditorSave),
            ),
          ),
        MenuAnchor(
          menuChildren: [
            if (!readOnly && compact) ...[
              MenuItemButton(
                key: ModeEditorKeys.undo,
                onPressed: editor.canUndo
                    ? ref.read(anyworkClientProvider).modeEditor.undo
                    : null,
                leadingIcon: const Icon(Icons.undo, size: 18),
                child: Text(l10n.modeEditorUndo),
              ),
              MenuItemButton(
                key: ModeEditorKeys.redo,
                onPressed: editor.canRedo
                    ? ref.read(anyworkClientProvider).modeEditor.redo
                    : null,
                leadingIcon: const Icon(Icons.redo, size: 18),
                child: Text(l10n.modeEditorRedo),
              ),
            ],
            MenuItemButton(
              key: ModeEditorKeys.reload,
              onPressed: busy ? null : _reload,
              leadingIcon: const Icon(Icons.refresh, size: 18),
              child: Text(l10n.modeEditorReload),
            ),
            if (!readOnly)
              MenuItemButton(
                key: ModeEditorKeys.deleteMode,
                onPressed: busy ? null : _deleteMode,
                leadingIcon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: context.colors.error,
                ),
                child: Text(l10n.modeEditorDeleteMode),
              ),
          ],
          builder: (context, controller, child) => IconButton(
            key: ModeEditorKeys.more,
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.more_horiz),
          ),
        ),
        const SizedBox(width: 12),
      ],
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        labelPadding: const EdgeInsets.symmetric(horizontal: 20),
        tabs: [
          Tab(
            key: ModeEditorKeys.tabFlow,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_tree_outlined, size: 16),
                const SizedBox(width: 8),
                Text(l10n.modeEditorTabFlow),
              ],
            ),
          ),
          Tab(
            key: ModeEditorKeys.tabPreview,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_outline, size: 16),
                const SizedBox(width: 8),
                Text(l10n.modeEditorTabPreview),
              ],
            ),
          ),
          Tab(
            key: ModeEditorKeys.tabJson,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.data_object, size: 16),
                const SizedBox(width: 8),
                Text(l10n.modeEditorTabJson),
              ],
            ),
          ),
          Tab(
            key: ModeEditorKeys.tabSettings,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune, size: 16),
                const SizedBox(width: 8),
                Text(l10n.modeEditorTabSettings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flowSection(
    BuildContext context, {
    required ModeEditorState editor,
    required ModeDocument document,
    required ModeWorkspaceViewState viewState,
  }) {
    final workflow = document.definition.workflow;
    final selection = viewState.selection;
    final dimmed = _dimmedStateIds(workflow, selection, viewState.focus);
    final dimmedCount = workflow == null
        ? 0
        : workflow.transitions
              .where(
                (transition) =>
                    dimmed.contains(transition.sourceStateId) ||
                    dimmed.contains(transition.targetStateId),
              )
              .length;
    final canvas = ModeWorkflowCanvas(
      document: document,
      readOnly: editor.readOnly || editor.busy,
      l10n: context.l10n,
      dimmedStateIds: dimmed,
      onDocumentChanged: _replace,
      onSelectStage: (id) =>
          ref.read(modeWorkspaceControllerProvider.notifier).selectStage(id),
      onSelectTransition: (id) => ref
          .read(modeWorkspaceControllerProvider.notifier)
          .selectTransition(id),
      onAddStage: () {
        final notice = addWorkflowStage(ref, context.l10n, finalStage: false);
        if (notice != null) _showNotice(notice);
      },
      onAddFinalStage: () {
        final notice = addWorkflowStage(ref, context.l10n, finalStage: true);
        if (notice != null) _showNotice(notice);
      },
      onAddTransition: () => addWorkflowTransitionDialog(context, ref),
      onConfirmRemoveStage: (stateId) =>
          confirmRemoveWorkflowStage(context, ref, stateId),
      onRemoveStage: (stateId) => removeWorkflowStage(ref, stateId),
      onRemoveTransition: (source, target) => removeWorkflowTransition(ref, (
        sourceStateId: source,
        targetStateId: target,
      )),
      onCreateTransition: (source, target) {
        final notice = createWorkflowTransition(
          ref,
          context.l10n,
          source,
          target,
        );
        if (notice != null) _showNotice(notice);
      },
      onAutoLayout: _autoLayout,
      onEnableWorkflow: _enableWorkflow,
      selectedStateId: switch (selection) {
        ModeStageSelection(:final stateId) => stateId,
        _ => null,
      },
      selectedEdgeId: switch (selection) {
        ModeTransitionSelection(:final sourceStateId, :final targetStateId) =>
          'edge:$sourceStateId->$targetStateId',
        _ => null,
      },
    );
    final detail = _detailPanel(
      context,
      editor: editor,
      document: document,
      selection: selection,
    );
    // Keep the canvas in the same element slot when details open or close;
    // its controller owns the viewport across the constraint change.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= modeWorkspaceWideBreakpoint;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _focusBar(
                    context,
                    viewState: viewState,
                    dimmedCount: dimmedCount,
                    title: workflow?.title,
                    summary: workflow == null
                        ? null
                        : context.l10n.modeEditorWorkflowSummary(
                            workflow.states.length,
                            workflow.transitions.length,
                          ),
                  ),
                  Expanded(child: canvas),
                  if (viewState.validationRequested && editor.issues.isNotEmpty)
                    _issuePanel(context, editor.issues),
                ],
              ),
            ),
            if (wide && detail != null)
              SizedBox(
                width: (constraints.maxWidth * 0.28).clamp(360, 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerLow,
                    border: Border(
                      left: BorderSide(color: context.colors.outlineVariant),
                    ),
                  ),
                  child: Material(
                    color: context.colors.surfaceContainerLow,
                    child: detail,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Set<String> _dimmedStateIds(
    WorkflowDefinition? workflow,
    ModeDetailSelection? selection,
    ModeWorkflowFocus focus,
  ) {
    if (focus != ModeWorkflowFocus.focused || workflow == null) {
      return const {};
    }
    if (selection == null) return const {};
    final states = workflow.states;
    final transitions = workflow.transitions;
    final related = <String>{};
    switch (selection) {
      case ModeStageSelection(:final stateId):
        related.add(stateId);
        for (final transition in transitions) {
          if (transition.sourceStateId == stateId) {
            related.add(transition.targetStateId);
          }
          if (transition.targetStateId == stateId) {
            related.add(transition.sourceStateId);
          }
        }
      case ModeTransitionSelection(:final sourceStateId, :final targetStateId):
        related
          ..add(sourceStateId)
          ..add(targetStateId);
    }
    return states
        .map((state) => state.id)
        .where((id) => !related.contains(id))
        .toSet();
  }

  Widget _focusBar(
    BuildContext context, {
    required ModeWorkspaceViewState viewState,
    required int dimmedCount,
    String? title,
    String? summary,
  }) {
    final l10n = context.l10n;
    return Container(
      color: context.colors.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Wrap(
        spacing: 20,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          if (summary != null)
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (title != null && title.isNotEmpty)
                  Text(
                    title,
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  summary,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<ModeWorkflowFocus>(
                key: viewState.focus == ModeWorkflowFocus.focused
                    ? ModeEditorKeys.focusSelected
                    : ModeEditorKeys.focusAll,
                segments: [
                  ButtonSegment(
                    value: ModeWorkflowFocus.focused,
                    label: Text(l10n.modeEditorFocusSelected),
                  ),
                  ButtonSegment(
                    value: ModeWorkflowFocus.all,
                    label: Text(l10n.modeEditorFocusAll),
                  ),
                ],
                selected: {viewState.focus},
                onSelectionChanged: (values) => ref
                    .read(modeWorkspaceControllerProvider.notifier)
                    .setFocus(values.first),
                showSelectedIcon: false,
              ),
              OutlinedButton.icon(
                key: ModeEditorKeys.validate,
                onPressed: _validate,
                icon: const Icon(Icons.fact_check_outlined, size: 16),
                label: Text(l10n.modeEditorValidate),
              ),
            ],
          ),
          if (viewState.focus == ModeWorkflowFocus.focused && dimmedCount > 0)
            Text(
              l10n.modeEditorDimmedEdges(dimmedCount),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget? _detailPanel(
    BuildContext context, {
    required ModeEditorState editor,
    required ModeDocument document,
    required ModeDetailSelection? selection,
  }) {
    final workflow = document.definition.workflow;
    if (workflow == null || selection == null) return null;
    final readOnly = editor.readOnly || editor.busy;
    void onSelectStage(String id) =>
        ref.read(modeWorkspaceControllerProvider.notifier).selectStage(id);
    void onSelectTransition(String id) =>
        ref.read(modeWorkspaceControllerProvider.notifier).selectTransition(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selection is ModeStageSelection
                      ? context.l10n.modeEditorDetailStage
                      : context.l10n.modeEditorDetailTransition,
                  style: context.text.titleSmall?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: ModeEditorKeys.closeDetail,
                tooltip: context.l10n.modeEditorCollapse,
                onPressed: () => ref
                    .read(modeWorkspaceControllerProvider.notifier)
                    .closeDetail(),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (selection) {
            ModeStageSelection(:final stateId) => () {
              WorkflowState? state;
              for (final candidate in workflow.states) {
                if (candidate.id == stateId) state = candidate;
              }
              if (state == null) {
                return _detailPlaceholder(context);
              }
              return ModeStageDetailPanel(
                document: document,
                workflow: workflow,
                state: state,
                readOnly: readOnly,
                l10n: context.l10n,
                onDocumentChanged: _replace,
                onSelectTransition: onSelectTransition,
                onRenameState: (state) =>
                    renameWorkflowStageDialog(context, ref, state),
                onDeleteState: (state) async {
                  if (await confirmRemoveWorkflowStage(
                    context,
                    ref,
                    state.id,
                  )) {
                    removeWorkflowStage(ref, state.id);
                  }
                },
                onDeleteTransition: (target) =>
                    removeWorkflowTransition(ref, target),
                onAddTransitionFrom: (source) => addWorkflowTransitionDialog(
                  context,
                  ref,
                  sourceStateId: source,
                ),
              );
            }(),
            ModeTransitionSelection(
              :final sourceStateId,
              :final targetStateId,
            ) =>
              () {
                WorkflowTransition? transition;
                for (final candidate in workflow.transitions) {
                  if (candidate.sourceStateId == sourceStateId &&
                      candidate.targetStateId == targetStateId) {
                    transition = candidate;
                  }
                }
                if (transition == null) {
                  return _detailPlaceholder(context);
                }
                return ModeTransitionDetailPanel(
                  document: document,
                  workflow: workflow,
                  transition: transition,
                  readOnly: readOnly,
                  l10n: context.l10n,
                  onDocumentChanged: _replace,
                  onSelectStage: onSelectStage,
                  onSelectTransition: onSelectTransition,
                  onDeleteTransition: (target) =>
                      removeWorkflowTransition(ref, target),
                );
              }(),
          },
        ),
      ],
    );
  }

  Widget _detailPlaceholder(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        context.l10n.modeEditorInspectorSelectHint,
        textAlign: TextAlign.center,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ),
  );

  Widget _issuePanel(BuildContext context, List<ModeValidationIssue> issues) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 132),
      child: Container(
        color: context.colors.errorContainer,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

class _AppBarChip extends StatelessWidget {
  const _AppBarChip({
    required this.label,
    this.color,
    this.foreground,
    this.icon,
  });

  final String label;
  final Color? color;
  final Color? foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(StudioRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: foreground ?? context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: foreground ?? context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
