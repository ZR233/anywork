import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../../view_models/read_values.dart';
import '../state/mode_editor_state.dart';
import '../state/mode_dialog_state.dart';
import 'mode_graph_edits.dart';

part 'mode_editor_view_model.g.dart';

@Riverpod(keepAlive: true)
class ModeEditorViewModel extends _$ModeEditorViewModel {
  late ModesRepository _repository;
  bool _alive = true;
  bool _jsonSession = false;
  int _session = 0;
  int _intent = 0;
  int _dialogGeneration = 0;
  int _lastWriteRevision = -1;
  ModeEditorRequest? _lastWriteKind;
  Observation? _operationWatch;

  int get lifetime => _session;

  @override
  Future<ModeEditorViewState> build() async {
    _alive = true;
    _repository = ref.watch(modesRepositoryProvider);
    // Deferred, coalesced publication for the build-time registration: a
    // catalog can publish while another provider is still building.
    ModesState? pendingCatalog;
    var catalogScheduled = false;
    void publishCatalog(ModesState catalog) {
      if (!_alive || state.asData == null) return;
      pendingCatalog = catalog;
      if (catalogScheduled) return;
      catalogScheduled = true;
      scheduleMicrotask(() {
        catalogScheduled = false;
        final next = pendingCatalog;
        pendingCatalog = null;
        if (!_alive || next == null) return;
        final current = state.asData?.value;
        if (current == null) return;
        state = AsyncData(
          current.copyWith(
            catalog: next,
            catalogRevision: next.projection.header?.revision,
          ),
        );
      });
    }

    final watch = _repository.state.watchLatest(publishCatalog);
    ref.onDispose(() {
      _alive = false;
      _session++;
      watch.observation.cancel();
      _operationWatch?.cancel();
      // Observing an editor never owns the native mutation or Mode catalog.
    });
    StudioFailure? readError;
    try {
      await _repository.loadModesPage();
    } on StudioFailure catch (error) {
      readError = error;
    }
    var catalog = _repository.state.value;
    ModeDefinitionSnapshot? initial;
    final origin = catalog.projection.stamp?.origin;
    if (catalog.modes case CurrentCollectionMirror<ThreadModeDescriptor>(
      :final window,
    )) {
      final reference = window.entries.firstOrNull;
      final first = reference == null
          ? null
          : switch (window.rows[reference.entry]) {
              ReadyReadValue<ThreadModeDescriptor, ProductEntityRef>(
                :final current,
              )
                  when current.reference == reference &&
                      current.origin == window.origin =>
                current.value,
              _ => null,
            };
      if (first != null && window.origin == origin) {
        try {
          initial = await _repository.readDefinition(first.id.id);
        } on StudioFailure catch (error) {
          readError ??= error;
        }
      }
    }
    catalog = _repository.state.value;
    if (origin != catalog.projection.stamp?.origin) initial = null;
    final document = initial?.document;
    final json = document == null ? '' : _json(document);
    return ModeEditorViewState(
      catalog: catalog,
      catalogRevision: catalog.projection.header?.revision,
      catalogReadError: readError,
      document: document,
      selectedModeId: document?.definition.id.id,
      jsonText: json,
      savedJson: json,
      savedDocument: document,
      savedRevision: initial?.revision,
      draftCatalogRevision: initial?.revision,
      draftOrigin: document == null ? null : origin,
      orderText: document?.definition.order.toString() ?? '',
      readOnly: initial?.readOnly ?? false,
    );
  }

  void setTab(ModeEditorTab tab) => _set(state.requireValue.copyWith(tab: tab));
  void setQuery(String query) =>
      _set(state.requireValue.copyWith(query: query));
  void select(ModeEditorSelection selection) {
    _jsonSession = false;
    _set(
      state.requireValue.copyWith(
        selection: selection,
        inspectorOpen: selection is NoModeSelection
            ? state.requireValue.inspectorOpen
            : true,
      ),
    );
  }

  void setInspectorOpen(bool open) =>
      _set(state.requireValue.copyWith(inspectorOpen: open));
  void setPreviewReason(String reason) =>
      _set(state.requireValue.copyWith(previewReason: reason));
  void clearNotice() => _set(state.requireValue.copyWith(notice: null));
  void copied() =>
      _set(state.requireValue.copyWith(notice: ModeEditorNotice.copied));

  bool duplicate(String suffix) {
    final current = state.requireValue;
    if (current.document == null || current.busy || current.dirty) return false;
    if (!catalogKnown) {
      _set(
        current.copyWith(error: settingsUnavailable('complete Mode catalog')),
      );
      return false;
    }
    final window =
        (current.catalog.modes as CurrentCollectionMirror<ThreadModeDescriptor>)
            .window;
    final ids = window.rows.values
        .map((row) => displayReadValue(row)!.id.id)
        .toSet();
    final base =
        'mode.custom-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    var id = base;
    var index = 1;
    while (ids.contains(id)) {
      id = '$base-${index++}';
    }
    create(
      current.document!.copyWith(
        definition: current.document!.definition.copyWith(
          id: ThreadModeId(id),
          displayName: '${current.document!.definition.displayName} $suffix',
        ),
      ),
    );
    _set(state.requireValue.copyWith(notice: ModeEditorNotice.duplicated));
    return true;
  }

  List<ThreadModeDescriptor> get visibleModes {
    final current = state.requireValue;
    final mirror = current.catalog.modes;
    final window = switch (mirror) {
      CurrentCollectionMirror<ThreadModeDescriptor>(:final window) => window,
      UnavailableCollectionMirror<ThreadModeDescriptor>(:final lastKnown) =>
        lastKnown,
    };
    final query = current.query.trim().toLowerCase();
    return [
      if (window != null)
        for (final reference in window.entries)
          if (displayReadValue(window.rows[reference.entry]) case final value?)
            if (query.isEmpty ||
                '${value.id.id} ${value.displayName}'.toLowerCase().contains(
                  query,
                ))
              value,
    ];
  }

  bool get catalogKnown => switch (state.requireValue.catalog.modes) {
    CurrentCollectionMirror<ThreadModeDescriptor>(:final window) =>
      window.complete &&
          window.entries.every(
            (reference) =>
                window.rows[reference.entry]
                    is ReadyReadValue<ThreadModeDescriptor, ProductEntityRef>,
          ),
    _ => false,
  };
  bool get catalogPageLoading => switch (state.requireValue.catalog.modes) {
    CurrentCollectionMirror<ThreadModeDescriptor>(:final window) =>
      window.loading,
    UnavailableCollectionMirror<ThreadModeDescriptor>(:final lastKnown) =>
      lastKnown?.loading ?? false,
  };
  Future<void> loadModesPage() async {
    final repository = _repository;
    _set(state.requireValue.copyWith(catalogReadError: null));
    try {
      await repository.loadModesPage();
    } on StudioFailure catch (error) {
      if (_alive && identical(repository, _repository)) {
        _set(state.requireValue.copyWith(catalogReadError: error));
      }
    }
  }

  Future<bool> open(String modeId) async {
    final current = state.requireValue;
    if (!_alive) return false;
    if (current.dirty || current.busy) {
      _set(
        current.copyWith(
          error: _conflict(
            current.dirty
                ? 'Save or discard the current Mode draft before opening another definition'
                : 'Wait for the current Mode request before opening another definition',
          ),
        ),
      );
      return false;
    }
    final session = ++_session;
    final intent = _begin(ModeEditorRequest.open);
    try {
      final snapshot = await _repository.readDefinition(modeId);
      if (!_owns(session, intent)) return false;
      if (!_sameOrigin(current.catalog.projection.stamp?.origin)) {
        _fail(
          session,
          intent,
          _conflict('Mode source changed; reload the editor'),
        );
        return false;
      }
      _install(
        snapshot.document,
        readOnly: snapshot.readOnly,
        saved: snapshot.document,
        savedRevision: snapshot.revision,
      );
      return true;
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
      return false;
    } finally {
      _finish(session, intent);
    }
  }

  void create(ModeDocument initial) {
    final current = state.requireValue;
    if (!_alive || current.dirty || current.busy) return;
    if (_readOnly(initial.definition.id)) {
      _set(
        current.copyWith(
          error: _conflict(
            'Built-in Mode IDs cannot be overwritten; use a custom ID',
          ),
        ),
      );
      return;
    }
    _session++;
    _install(
      initial,
      readOnly: _readOnly(initial.definition.id),
      baseRevision: current.catalogRevision,
      notice: ModeEditorNotice.draftCreated,
    );
  }

  Future<bool> importJson(String raw) async {
    final current = state.requireValue;
    if (!_alive ||
        current.busy ||
        (current.dirty && current.dialog?.kind != ModeDialogKind.importJson)) {
      return false;
    }
    final session = ++_session;
    final intent = _begin(ModeEditorRequest.importJson);
    _set(
      state.requireValue.copyWith(
        jsonText: raw,
        jsonApplied: false,
        dirty: true,
      ),
    );
    try {
      final result = await _repository.validate(raw);
      if (!_owns(session, intent)) return false;
      if (result.document == null || result.issues.isNotEmpty) {
        _set(
          state.requireValue.copyWith(
            issues: result.issues,
            validationRequested: true,
          ),
        );
        return false;
      }
      if (_readOnly(result.document!.definition.id)) {
        _fail(
          session,
          intent,
          _conflict('Built-in Mode IDs cannot be overwritten; use a custom ID'),
        );
        return false;
      }
      ModeDefinitionSnapshot? existing;
      try {
        existing = await _repository.readDefinition(
          result.document!.definition.id.id,
        );
      } on StudioFailure catch (error) {
        if (error.code != StudioFailureCode.notFound) rethrow;
      }
      if (!_owns(session, intent)) return false;
      if (!_sameOrigin(current.catalog.projection.stamp?.origin)) {
        _fail(
          session,
          intent,
          _conflict('Mode source changed; reload the editor'),
        );
        return false;
      }
      if (existing?.readOnly ?? false) {
        _fail(
          session,
          intent,
          _conflict('Built-in Mode IDs cannot be overwritten; use a custom ID'),
        );
        return false;
      }
      _install(
        result.document!,
        readOnly: _readOnly(result.document!.definition.id),
        saved: existing?.document,
        savedRevision: existing?.revision,
        baseRevision: current.catalogRevision,
        notice: ModeEditorNotice.imported,
        raw: raw,
      );
      return true;
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
      return false;
    } finally {
      _finish(session, intent);
    }
  }

  void editJson(String raw) {
    final current = state.requireValue;
    if ((!current.canEdit &&
            current.dialog?.kind != ModeDialogKind.importJson) ||
        (current.busy && current.request != ModeEditorRequest.save) ||
        current.jsonText == raw) {
      return;
    }
    var next = current;
    if (!_jsonSession && current.document != null) {
      next = _push(next);
      _jsonSession = true;
    }
    _set(
      _dirty(
        next.copyWith(
          jsonText: raw,
          jsonApplied: false,
          editRevision: current.editRevision + 1,
          preview: null,
          notice: null,
          error: null,
        ),
      ),
    );
  }

  void edit(ModeEdit intent) {
    final current = state.requireValue;
    if (!current.canEdit) {
      _set(
        current.copyWith(
          error: StudioFailure(
            code: current.readOnly
                ? StudioFailureCode.permissionDenied
                : current.document == null
                ? StudioFailureCode.notFound
                : StudioFailureCode.busy,
            message: current.readOnly
                ? 'Built-in Mode definitions are read-only'
                : current.document == null
                ? 'Open a Mode definition before editing'
                : 'Wait for the current Mode request before editing',
            retryable: false,
            correlationId: 'mode-editor-edit',
          ),
        ),
      );
      return;
    }
    if (!current.jsonApplied) {
      _set(
        current.copyWith(
          error: _conflict(
            'Apply or discard the JSON edit before editing the graph',
          ),
        ),
      );
      return;
    }
    _jsonSession = false;
    try {
      if (intent case EditModeOrder(:final value)) {
        final order = int.tryParse(value.trim());
        final issue = order == null || order < 0 || order > 0xffffffff
            ? const ValidationIssue(
                code: 'invalid_order',
                path: 'order',
                message: 'Order must be a u32 integer',
              )
            : null;
        final document = issue == null
            ? current.document!.copyWith(
                definition: current.document!.definition.copyWith(
                  order: order!,
                ),
              )
            : current.document!;
        _set(
          _dirty(
            _push(current).copyWith(
              document: document,
              orderText: value,
              orderError: issue,
              jsonText: _json(document),
              editRevision: current.editRevision + 1,
              preview: null,
              error: null,
              notice: null,
            ),
          ),
        );
        return;
      }
      final document = applyModeGraphEdit(current.document!, intent);
      if (document == current.document) return;
      final selection = switch ((current.selection, intent)) {
        (_, AddWorkflowState(:final value)) => ModeEditorSelection.node(
          stateId: value.id,
        ),
        (
          ModeNodeSelection(stateId: final selected),
          RenameWorkflowState(:final oldId, :final newId),
        )
            when selected == oldId =>
          ModeEditorSelection.node(stateId: newId),
        (
          ModeEdgeSelection(
            sourceStateId: final source,
            targetStateId: final target,
          ),
          RenameWorkflowState(:final oldId, :final newId),
        ) =>
          ModeEditorSelection.edge(
            sourceStateId: source == oldId ? newId : source,
            targetStateId: target == oldId ? newId : target,
          ),
        (
          ModeNodeSelection(stateId: final selected),
          RemoveWorkflowState(:final id),
        )
            when selected == id =>
          const ModeEditorSelection.none(),
        (
          ModeEdgeSelection(
            sourceStateId: final source,
            targetStateId: final target,
          ),
          RemoveWorkflowState(:final id),
        )
            when source == id || target == id =>
          const ModeEditorSelection.none(),
        (
          ModeEdgeSelection(
            sourceStateId: final source,
            targetStateId: final target,
          ),
          RemoveWorkflowTransition(:final sourceId, :final targetId),
        )
            when source == sourceId && target == targetId =>
          const ModeEditorSelection.none(),
        _ => current.selection,
      };
      final criteriaRaw = {...current.criteriaRaw};
      switch (intent) {
        case RenameWorkflowState(:final oldId, :final newId):
          final raw = criteriaRaw.remove(oldId);
          if (raw != null) criteriaRaw[newId] = raw;
        case RemoveWorkflowState(:final id):
          criteriaRaw.remove(id);
        case RemoveModeWorkflow():
          criteriaRaw.clear();
        default:
          break;
      }
      _set(
        _dirty(
          _push(current).copyWith(
            document: document,
            jsonText: _json(document),
            editRevision: current.editRevision + 1,
            selection: selection,
            criteriaRaw: criteriaRaw,
            inspectorOpen: intent is AddWorkflowState
                ? true
                : current.inspectorOpen,
            preview: null,
            error: null,
            notice: null,
          ),
        ),
      );
    } on StudioFailure catch (error) {
      _set(current.copyWith(error: error));
    }
  }

  void undo() => _moveHistory(redo: false);
  void redo() => _moveHistory(redo: true);

  void _moveHistory({required bool redo}) {
    final current = state.requireValue;
    if (!current.canEdit) return;
    final source = redo ? current.redo : current.undo;
    if (source.isEmpty) return;
    _jsonSession = false;
    final snapshot = source.last;
    final destination = _bounded([
      ...(redo ? current.undo : current.redo),
      _snapshot(current),
    ]);
    _set(
      _dirty(
        current.copyWith(
          document: snapshot.document,
          jsonText: snapshot.jsonText,
          jsonApplied: snapshot.jsonApplied,
          selectedModeId: snapshot.document.definition.id.id,
          orderText: snapshot.orderText,
          orderError: snapshot.orderError,
          criteriaRaw: snapshot.criteriaRaw,
          undo: redo ? destination : source.sublist(0, source.length - 1),
          redo: redo ? source.sublist(0, source.length - 1) : destination,
          editRevision: current.editRevision + 1,
          preview: null,
          error: null,
          notice: null,
        ),
      ),
    );
  }

  void discard() {
    final current = state.requireValue;
    if (current.busy) return;
    _session++;
    _jsonSession = false;
    _set(
      current.copyWith(
        document: current.savedDocument,
        jsonText: current.savedJson,
        jsonApplied: true,
        dirty: false,
        orderError: null,
        criteriaRaw: {},
        orderText: current.savedDocument?.definition.order.toString() ?? '',
        selectedModeId: current.savedDocument?.definition.id.id,
        undo: [],
        redo: [],
        preview: null,
        issues: [],
        validationRequested: false,
        selection: const ModeEditorSelection.none(),
        error: null,
        notice: null,
        editRevision: current.editRevision + 1,
      ),
    );
  }

  Future<bool> applyJson() async {
    final frozen = state.requireValue;
    if (!frozen.canEdit || frozen.busy) return false;
    _jsonSession = false;
    final session = _session;
    final intent = _begin(ModeEditorRequest.apply);
    try {
      final result = await _repository.validate(frozen.jsonText);
      if (!_sameEdit(session, intent, frozen.editRevision)) return false;
      if (result.document == null || result.issues.isNotEmpty) {
        _set(
          state.requireValue.copyWith(
            issues: result.issues,
            validationRequested: true,
          ),
        );
        return false;
      }
      final document = result.document!;
      if (_readOnly(document.definition.id)) {
        _fail(
          session,
          intent,
          _conflict('Built-in Mode IDs cannot be overwritten; use a custom ID'),
        );
        return false;
      }
      _set(
        _dirty(
          _push(state.requireValue).copyWith(
            document: document,
            jsonApplied: true,
            selectedModeId: document.definition.id.id,
            criteriaRaw: {},
            orderText: document.definition.order.toString(),
            orderError: null,
            issues: result.issues,
            validationRequested: true,
            preview: null,
            editRevision: frozen.editRevision + 1,
          ),
        ),
      );
      return true;
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
      return false;
    } finally {
      _finish(session, intent);
    }
  }

  Future<void> validate() async {
    final frozen = state.requireValue;
    if (frozen.document == null || frozen.busy) return;
    final session = _session;
    final intent = _begin(ModeEditorRequest.validate);
    try {
      final result = await _repository.validate(frozen.jsonText);
      if (!_sameEdit(session, intent, frozen.editRevision)) return;
      _set(
        state.requireValue.copyWith(
          issues: result.issues,
          validationRequested: true,
        ),
      );
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
    } finally {
      _finish(session, intent);
    }
  }

  Future<void> preview({
    String? targetStateId,
    bool reset = false,
    String defaultReason = '手动确认阶段完成和转换条件',
  }) async {
    final initial = state.requireValue;
    if (initial.busy || initial.orderError != null) return;
    final originalSession = _session;
    final reason = initial.previewReason.trim().isEmpty
        ? defaultReason
        : initial.previewReason.trim();
    var frozen = initial;
    if (!initial.jsonApplied) {
      if (!await applyJson() ||
          !_alive ||
          _session != originalSession ||
          state.requireValue.editRevision != initial.editRevision + 1) {
        return;
      }
      frozen = state.requireValue;
    }
    if (frozen.document?.definition.workflow == null) return;
    final session = _session;
    final intent = _begin(ModeEditorRequest.preview);
    final request = WorkflowPreviewRequest(
      document: frozen.document!,
      path: reset ? [] : frozen.preview?.path ?? [],
      targetStateId: targetStateId,
      reason: reason,
    );
    try {
      final result = await _repository.preview(request);
      if (!_sameEdit(session, intent, frozen.editRevision)) return;
      _set(state.requireValue.copyWith(preview: result));
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
    } finally {
      _finish(session, intent);
    }
  }

  Future<String> readSchema() => _repository.schema();

  void setCriteriaRaw(String stateId, String raw) {
    final current = state.requireValue;
    final workflow = current.document?.definition.workflow;
    if (!current.canEdit ||
        !current.jsonApplied ||
        workflow == null ||
        !workflow.states.any((state) => state.id == stateId)) {
      return;
    }
    final parsed = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    edit(ModeEdit.stateCriteria(stateId, parsed));
    final afterEdit = state.requireValue;
    final next = afterEdit.editRevision == current.editRevision
        ? _push(afterEdit)
        : afterEdit;
    _set(
      next.copyWith(
        criteriaRaw: {...next.criteriaRaw, stateId: raw},
        editRevision: next.editRevision == current.editRevision
            ? next.editRevision + 1
            : next.editRevision,
        dirty: true,
        error: null,
        notice: null,
      ),
    );
  }

  void addDefaultState({
    required WorkflowStateKind kind,
    required String title,
    required String instructions,
    required List<String> criteria,
  }) {
    final workflow = state.requireValue.document?.definition.workflow;
    if (workflow == null) return;
    final prefix = kind == WorkflowStateKind.atomic ? 'stage' : 'final';
    var index = 1;
    while (workflow.states.any((state) => state.id == '$prefix$index')) {
      index++;
    }
    edit(
      ModeEdit.addState(
        WorkflowState(
          id: '$prefix$index',
          title: title,
          instructions: instructions,
          completionCriteria: criteria,
          kind: kind,
        ),
      ),
    );
  }

  void beginCreateDialog() {
    final current = state.requireValue;
    if (current.dirty || current.busy) return;
    _set(
      current.copyWith(
        dialog: ModeDialogDraft(
          generation: ++_dialogGeneration,
          kind: ModeDialogKind.create,
          id: 'mode.custom-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
        ),
      ),
    );
  }

  void beginImportDialog() {
    final current = state.requireValue;
    if (current.dirty || current.busy) return;
    _set(
      current.copyWith(
        dialog: ModeDialogDraft(
          generation: ++_dialogGeneration,
          kind: ModeDialogKind.importJson,
        ),
        jsonText: '',
        jsonApplied: false,
        dirty: true,
      ),
    );
  }

  void beginRenameDialog(String id) {
    if (!state.requireValue.canEdit) return;
    _set(
      state.requireValue.copyWith(
        dialog: ModeDialogDraft(
          generation: ++_dialogGeneration,
          kind: ModeDialogKind.renameState,
          originalStateId: id,
          id: id,
        ),
      ),
    );
  }

  void beginTransitionDialog({String? sourceId}) {
    final current = state.requireValue;
    final workflow = current.document?.definition.workflow;
    if (!current.canEdit || workflow == null) return;
    _set(
      current.copyWith(
        dialog: ModeDialogDraft(
          generation: ++_dialogGeneration,
          kind: ModeDialogKind.transition,
          sourceId:
              sourceId ??
              workflow.states
                  .where((state) => state.kind == WorkflowStateKind.atomic)
                  .firstOrNull
                  ?.id,
          targetId: workflow.states.firstOrNull?.id,
        ),
      ),
    );
  }

  void setDialogId(String raw) =>
      _dialog(state.requireValue.dialog?.copyWith(id: raw, validation: null));
  void setDialogName(String raw) =>
      _dialog(state.requireValue.dialog?.copyWith(name: raw, validation: null));
  void setDialogGuard(String raw) => _dialog(
    state.requireValue.dialog?.copyWith(guard: raw, validation: null),
  );
  void setDialogSource(String? id) => _dialog(
    state.requireValue.dialog?.copyWith(sourceId: id, validation: null),
  );
  void setDialogTarget(String? id) => _dialog(
    state.requireValue.dialog?.copyWith(targetId: id, validation: null),
  );
  void setDialogTemplate(ModeTemplateKind template) =>
      _dialog(state.requireValue.dialog?.copyWith(template: template));
  void _dialog(ModeDialogDraft? dialog) {
    if (!state.requireValue.busy) {
      _set(state.requireValue.copyWith(dialog: dialog));
    }
  }

  void cancelDialog() {
    if (state.requireValue.busy) return;
    if (state.requireValue.dialog?.kind == ModeDialogKind.importJson) discard();
    _dialog(null);
  }

  Future<bool> submitCreateDialog(ModeDocument template) async {
    final frozen = state.requireValue;
    final dialog = frozen.dialog;
    if (dialog?.kind != ModeDialogKind.create || frozen.busy) return false;
    if (!catalogKnown) {
      _set(
        frozen.copyWith(
          error: settingsUnavailable('complete Mode catalog for draft order'),
        ),
      );
      return false;
    }
    final id = dialog!.id.trim();
    if (!RegExp(r'^mode\.[a-z0-9_-]+$').hasMatch(id) || id.length > 64) {
      _dialog(dialog.copyWith(validation: ModeDialogValidation.invalidModeId));
      return false;
    }
    if (dialog.name.trim().isEmpty) {
      _dialog(dialog.copyWith(validation: ModeDialogValidation.nameRequired));
      return false;
    }
    final session = _session;
    final intent = _begin(ModeEditorRequest.create);
    try {
      try {
        await _repository.readDefinition(id);
        if (_owns(session, intent)) {
          _set(
            state.requireValue.copyWith(
              dialog: dialog.copyWith(
                validation: ModeDialogValidation.modeExists,
              ),
            ),
          );
        }
        return false;
      } on StudioFailure catch (error) {
        if (error.code != StudioFailureCode.notFound) rethrow;
      }
      if (!_owns(session, intent) ||
          state.requireValue.dialog?.generation != dialog.generation) {
        return false;
      }
      if (!_sameOrigin(frozen.catalog.projection.stamp?.origin)) {
        _fail(
          session,
          intent,
          _conflict('Mode source changed; reload the editor'),
        );
        return false;
      }
      final window =
          (frozen.catalog.modes
                  as CurrentCollectionMirror<ThreadModeDescriptor>)
              .window;
      var order = 10;
      for (final row in window.rows.values) {
        final value = displayReadValue(row)!;
        if (value.order >= order) order = value.order + 10;
      }
      _install(
        template.copyWith(
          definition: template.definition.copyWith(
            id: ThreadModeId(id),
            displayName: dialog.name.trim(),
            order: order,
          ),
        ),
        readOnly: false,
        baseRevision: frozen.catalogRevision,
        notice: ModeEditorNotice.draftCreated,
      );
      return true;
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
      return false;
    } finally {
      _finish(session, intent);
    }
  }

  bool submitGraphDialog() {
    final current = state.requireValue;
    final draft = current.dialog;
    final workflow = current.document?.definition.workflow;
    if (draft == null || workflow == null || !current.canEdit) return false;
    ModeDialogValidation? issue;
    ModeEdit? change;
    if (draft.kind == ModeDialogKind.renameState) {
      final id = draft.id.trim();
      if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(id) || id.length > 64) {
        issue = ModeDialogValidation.invalidStateId;
      } else if (id != draft.originalStateId &&
          workflow.states.any((state) => state.id == id)) {
        issue = ModeDialogValidation.stateExists;
      } else if (draft.originalStateId != null) {
        change = ModeEdit.renameState(draft.originalStateId!, id);
      }
    } else if (draft.kind == ModeDialogKind.transition) {
      if (!workflow.states.any(
        (state) =>
            state.id == draft.sourceId &&
            state.kind == WorkflowStateKind.atomic,
      )) {
        issue = ModeDialogValidation.sourceRequired;
      } else if (!workflow.states.any((state) => state.id == draft.targetId)) {
        issue = ModeDialogValidation.targetRequired;
      } else if (draft.guard.trim().isEmpty) {
        issue = ModeDialogValidation.guardRequired;
      } else if (workflow.transitions.any(
        (edge) =>
            edge.sourceStateId == draft.sourceId &&
            edge.targetStateId == draft.targetId,
      )) {
        issue = ModeDialogValidation.duplicateTransition;
      } else {
        change = ModeEdit.addTransition(
          WorkflowTransition(
            sourceStateId: draft.sourceId!,
            targetStateId: draft.targetId!,
            guard: draft.guard.trim(),
          ),
        );
      }
    }
    if (issue != null) {
      _dialog(draft.copyWith(validation: issue));
      return false;
    }
    if (change == null) return false;
    edit(change);
    if (state.requireValue.error != null) return false;
    _dialog(null);
    return true;
  }

  Future<bool> save() async {
    final frozen = state.requireValue;
    if (!frozen.canEdit || frozen.busy || frozen.orderError != null) {
      return false;
    }
    if (frozen.draftOrigin == null || !_sameOrigin(frozen.draftOrigin)) {
      _set(
        frozen.copyWith(
          error: _conflict('Mode source changed; reload the editor'),
        ),
      );
      return false;
    }
    if (!frozen.dirty && frozen.savedDocument != null) return true;
    if (_lastWriteRevision == frozen.editRevision &&
        (frozen.operation?.preventsResubmission ?? false)) {
      return false;
    }
    final revision = frozen.draftCatalogRevision;
    if (revision == null) {
      _set(
        frozen.copyWith(error: settingsUnavailable('Mode catalog revision')),
      );
      return false;
    }
    final session = _session;
    _jsonSession = false;
    final intent = _begin(ModeEditorRequest.save);
    try {
      final validation = await _repository.validate(frozen.jsonText);
      if (!_sameEdit(session, intent, frozen.editRevision)) return false;
      if (validation.document == null || validation.issues.isNotEmpty) {
        _set(
          state.requireValue.copyWith(
            issues: validation.issues,
            validationRequested: true,
          ),
        );
        return false;
      }
      final payload = validation.document!;
      if (!_sameOrigin(frozen.draftOrigin)) {
        _fail(
          session,
          intent,
          _conflict('Mode source changed; reload the editor'),
        );
        return false;
      }
      if (_readOnly(payload.definition.id)) {
        _fail(
          session,
          intent,
          _conflict('Built-in Mode IDs cannot be overwritten; use a custom ID'),
        );
        return false;
      }
      _lastWriteRevision = frozen.editRevision;
      final ticket = _repository.save(payload, expectedRevision: revision);
      final observed = await _observeCommand(ticket, session, intent);
      if (!_owns(session, intent)) return false;
      if (!observed.action.succeeded) return false;
      if (!_sameOrigin(frozen.draftOrigin)) {
        _fail(
          session,
          intent,
          _conflict('Mode source changed; reload the editor'),
        );
        return false;
      }
      final current = state.requireValue;
      // This is an editor baseline for the exact accepted payload, not a write
      // into the Repository catalog. Native definition remains legitimately optional.
      final result = observed.value;
      final saved = result?.definition?.document ?? payload;
      final sameEdit = current.editRevision == frozen.editRevision;
      _set(
        _dirty(
          current.copyWith(
            savedDocument: saved,
            savedJson: _json(saved),
            savedRevision: result?.definition?.revision,
            draftCatalogRevision:
                result?.definition?.revision ??
                _receiptRevision(observed.action),
            document: sameEdit ? saved : current.document,
            selectedModeId: sameEdit
                ? saved.definition.id.id
                : current.selectedModeId,
            jsonText: sameEdit ? _json(saved) : current.jsonText,
            jsonApplied: sameEdit ? true : current.jsonApplied,
            orderText: sameEdit
                ? saved.definition.order.toString()
                : current.orderText,
            criteriaRaw: sameEdit ? {} : current.criteriaRaw,
            notice: ModeEditorNotice.saved,
          ),
        ),
      );
      return true;
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
      return false;
    } finally {
      _finish(session, intent);
    }
  }

  Future<bool> delete() async {
    final frozen = state.requireValue;
    if (!_alive ||
        frozen.readOnly ||
        frozen.busy ||
        frozen.dirty ||
        frozen.selectedModeId == null) {
      return false;
    }
    if (frozen.draftOrigin == null || !_sameOrigin(frozen.draftOrigin)) {
      _set(
        frozen.copyWith(
          error: _conflict('Mode source changed; reload the editor'),
        ),
      );
      return false;
    }
    final revision = frozen.draftCatalogRevision;
    if (revision == null) {
      _set(
        frozen.copyWith(error: settingsUnavailable('Mode catalog revision')),
      );
      return false;
    }
    if (_lastWriteRevision == frozen.editRevision &&
        (frozen.operation?.preventsResubmission ?? false)) {
      return false;
    }
    final session = _session;
    final intent = _begin(ModeEditorRequest.delete);
    _lastWriteRevision = frozen.editRevision;
    try {
      final observed = await _observeCommand(
        _repository.delete(frozen.selectedModeId!, expectedRevision: revision),
        session,
        intent,
      );
      if (!_owns(session, intent) || !observed.action.succeeded) return false;
      if (!_sameOrigin(frozen.draftOrigin)) {
        _fail(
          session,
          intent,
          _conflict('Mode source changed; reload the editor'),
        );
        return false;
      }
      _set(
        state.requireValue.copyWith(
          document: null,
          selectedModeId: null,
          savedDocument: null,
          jsonText: '',
          savedJson: '',
          savedRevision: null,
          orderText: '',
          undo: [],
          redo: [],
          preview: null,
          issues: [],
          notice: ModeEditorNotice.deleted,
        ),
      );
      return true;
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
      return false;
    } finally {
      _finish(session, intent);
    }
  }

  Future<bool> reload() async {
    final frozen = state.requireValue;
    if (!_alive || frozen.busy || frozen.dirty) return false;
    if (_lastWriteKind == ModeEditorRequest.reload &&
        (frozen.operation?.preventsResubmission ?? false)) {
      return false;
    }
    final revision = frozen.catalogRevision;
    if (revision == null) {
      _set(
        frozen.copyWith(error: settingsUnavailable('Mode catalog revision')),
      );
      return false;
    }
    final session = _session;
    final intent = _begin(ModeEditorRequest.reload);
    try {
      final observed = await _observeCommand(
        _repository.reload(expectedRevision: revision),
        session,
        intent,
      );
      if (!_owns(session, intent) || !observed.action.succeeded) return false;
      final origin = observed.value?.catalog.origin;
      if (origin == null || !_sameOrigin(origin)) {
        _fail(
          session,
          intent,
          _conflict('Mode source changed; reload the editor'),
        );
        return false;
      }
      if (frozen.selectedModeId case final modeId?) {
        ModeDefinitionSnapshot snapshot;
        try {
          snapshot = await _repository.readDefinition(modeId);
        } on StudioFailure catch (error) {
          if (error.code != StudioFailureCode.notFound) rethrow;
          if (!_owns(session, intent)) return false;
          if (!_sameOrigin(origin)) {
            _fail(
              session,
              intent,
              _conflict('Mode source changed; reload the editor'),
            );
            return false;
          }
          // Only this explicit read's NotFound proves removal. A missing row in
          // a bounded catalog page is not deletion evidence.
          _jsonSession = false;
          _set(
            state.requireValue.copyWith(
              document: null,
              savedDocument: null,
              selectedModeId: null,
              jsonText: '',
              savedJson: '',
              jsonApplied: true,
              savedRevision: null,
              draftCatalogRevision: state.requireValue.catalogRevision,
              draftOrigin: origin,
              orderText: '',
              orderError: null,
              criteriaRaw: {},
              dirty: false,
              readOnly: false,
              undo: [],
              redo: [],
              selection: const ModeEditorSelection.none(),
              inspectorOpen: false,
              preview: null,
              issues: [],
              validationRequested: false,
              error: null,
              notice: null,
              dialog: null,
              editRevision: state.requireValue.editRevision + 1,
            ),
          );
          return true;
        }
        if (!_owns(session, intent) || !_sameOrigin(origin)) return false;
        _install(
          snapshot.document,
          readOnly: snapshot.readOnly,
          saved: snapshot.document,
          savedRevision: snapshot.revision,
        );
      }
      return true;
    } on StudioFailure catch (error) {
      _fail(session, intent, error);
      return false;
    } finally {
      _finish(session, intent);
    }
  }

  Future<bool> resolveLeave(ModeLeaveChoice choice) async {
    if (!state.requireValue.dirty) return !state.requireValue.busy;
    return switch (choice) {
      ModeLeaveChoice.stay => false,
      ModeLeaveChoice.discard => _discardForLeave(),
      ModeLeaveChoice.save => await save() && !state.requireValue.dirty,
    };
  }

  bool _discardForLeave() {
    if (state.requireValue.busy) return false;
    discard();
    return true;
  }

  Future<({SettingsAction action, ModeDefinitionResult? value})>
  _observeCommand(
    OperationTicket<ModeDefinitionResult> ticket,
    int session,
    int intent,
  ) async {
    _lastWriteKind = state.requireValue.request;
    _operationWatch?.cancel();
    StudioFailure? observationError;
    try {
      final watch = ticket.state.watchLatest((operation) {
        if (!_owns(session, intent)) return;
        _set(
          state.requireValue.copyWith(
            operation: state.requireValue.operation?.copyWith(
              operation: operation,
            ),
          ),
        );
      });
      _operationWatch = watch.observation;
    } on StudioFailure catch (error) {
      observationError = error;
    }
    _set(
      state.requireValue.copyWith(
        operation: SettingsAction(
          intent: intent,
          pending: true,
          operation: ticket.state.value,
          observationError: observationError,
        ),
      ),
    );
    final result = await ticket.result;
    final action = settledSettingsAction(
      intent,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: observationError);
    if (_owns(session, intent)) {
      _set(state.requireValue.copyWith(operation: action, error: action.error));
    }
    return (action: action, value: _commandValue(result));
  }

  int _begin(ModeEditorRequest request) {
    final intent = ++_intent;
    _set(
      state.requireValue.copyWith(
        busy: true,
        request: request,
        latestIntent: intent,
        error: null,
        notice: null,
      ),
    );
    return intent;
  }

  bool _owns(int session, int intent) =>
      _alive &&
      _session == session &&
      state.asData?.value.latestIntent == intent;
  bool _sameOrigin(ProductReadOrigin? origin) =>
      state.requireValue.catalog.projection.stamp?.origin == origin;
  bool _sameEdit(int session, int intent, int revision) =>
      _owns(session, intent) && state.requireValue.editRevision == revision;
  void _finish(int session, int intent) {
    if (_owns(session, intent)) {
      _set(state.requireValue.copyWith(busy: false, request: null));
    }
  }

  void _fail(int session, int intent, StudioFailure error) {
    if (_owns(session, intent)) _set(state.requireValue.copyWith(error: error));
  }

  void _set(ModeEditorViewState value) {
    if (_alive) state = AsyncData(value);
  }

  static String _json(ModeDocument document) =>
      const JsonEncoder.withIndent('  ').convert(document.toJson());
  static List<ModeEditorSnapshot> _bounded(List<ModeEditorSnapshot> values) =>
      values.length <= 64 ? values : values.sublist(values.length - 64);
  static ModeEditorSnapshot _snapshot(ModeEditorViewState value) =>
      ModeEditorSnapshot(
        document: value.document!,
        jsonText: value.jsonText,
        jsonApplied: value.jsonApplied,
        orderText: value.orderText,
        orderError: value.orderError,
        criteriaRaw: value.criteriaRaw,
      );
  static ModeEditorViewState _push(ModeEditorViewState value) => value.copyWith(
    undo: _bounded([...value.undo, _snapshot(value)]),
    redo: [],
  );
  static ModeEditorViewState _dirty(ModeEditorViewState value) =>
      value.copyWith(
        dirty:
            value.document != value.savedDocument ||
            value.jsonText != value.savedJson ||
            value.orderText !=
                (value.savedDocument?.definition.order.toString() ?? '') ||
            !value.jsonApplied ||
            value.orderError != null ||
            value.criteriaRaw.isNotEmpty,
      );

  void _install(
    ModeDocument document, {
    required bool readOnly,
    ModeDocument? saved,
    int? savedRevision,
    int? baseRevision,
    ModeEditorNotice? notice,
    String? raw,
  }) {
    _jsonSession = false;
    _operationWatch?.cancel();
    _operationWatch = null;
    final current = state.requireValue;
    _set(
      _dirty(
        current.copyWith(
          document: document,
          selectedModeId: document.definition.id.id,
          jsonText: raw ?? _json(document),
          jsonApplied: true,
          savedDocument: saved,
          savedJson: saved == null ? '' : _json(saved),
          savedRevision: savedRevision,
          draftCatalogRevision: savedRevision ?? baseRevision,
          draftOrigin: current.catalog.projection.stamp?.origin,
          dirty: saved == null,
          readOnly: readOnly,
          orderText: document.definition.order.toString(),
          orderError: null,
          criteriaRaw: {},
          undo: [],
          redo: [],
          preview: null,
          issues: [],
          validationRequested: false,
          selection: const ModeEditorSelection.none(),
          error: null,
          notice: notice,
          dialog: null,
          operation: null,
          editRevision: current.editRevision + 1,
        ),
      ),
    );
  }

  bool _readOnly(ThreadModeId id) {
    final mirror = state.requireValue.catalog.modes;
    if (mirror case CurrentCollectionMirror<ThreadModeDescriptor>(
      :final window,
    )) {
      for (final row in window.rows.values) {
        final value = displayReadValue(row);
        if (value?.id == id) return value!.readOnly;
      }
    }
    return id == ThreadModeId.simple || id == ThreadModeId.task;
  }

  static ModeDefinitionResult? _commandValue(
    CommandResult<ModeDefinitionResult> result,
  ) => switch (result) {
    CommittedCommandResult<ModeDefinitionResult>(:final value) => value,
    AcknowledgedCommandResult<ModeDefinitionResult>(:final value) => value,
    SyncFailedCommandResult<ModeDefinitionResult>(:final value) => value,
    AcknowledgedSyncFailedCommandResult<ModeDefinitionResult>(:final value) =>
      value,
    _ => null,
  };
  static int? _receiptRevision(SettingsAction action) => action
      .operation
      ?.receipt
      ?.targets
      .whereType<ResourceStamp>()
      .where((target) => target.resourceKey == 'thread-mode-catalog')
      .firstOrNull
      ?.revision;
  static StudioFailure _conflict(String message) => StudioFailure(
    code: StudioFailureCode.conflict,
    message: message,
    retryable: false,
    correlationId: 'mode-editor-conflict',
  );
}
