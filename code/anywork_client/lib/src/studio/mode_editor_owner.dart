import 'dart:convert';

import '../../anywork_client.dart' show ReadModel, ResourceKind, ResourcePermit;
import '../../models.dart';
import 'anywork_client.dart';
import 'commands/command_lane.dart';

const Object _modeEditorUnset = Object();
const int _modeEditorHistoryLimit = 64;

/// One authored Mode tab. The owner survives widget disposal for the Client
/// lifetime; navigation must resolve [dirty] before calling [open] or [create].
final class ModeEditorState {
  const ModeEditorState({
    this.document,
    this.jsonText = '',
    this.dirty = false,
    this.readOnly = false,
    this.busy = false,
    this.error,
    this.issues = const [],
    this.preview,
    this.canUndo = false,
    this.canRedo = false,
  });

  final ModeDocument? document;
  final String jsonText;
  final bool dirty;
  final bool readOnly;
  final bool busy;
  final String? error;
  final List<ModeValidationIssue> issues;
  final WorkflowPreviewSnapshot? preview;
  final bool canUndo;
  final bool canRedo;

  ModeEditorState copyWith({
    Object? document = _modeEditorUnset,
    String? jsonText,
    bool? dirty,
    bool? readOnly,
    bool? busy,
    Object? error = _modeEditorUnset,
    List<ModeValidationIssue>? issues,
    Object? preview = _modeEditorUnset,
    bool? canUndo,
    bool? canRedo,
  }) => ModeEditorState(
    document: identical(document, _modeEditorUnset)
        ? this.document
        : document as ModeDocument?,
    jsonText: jsonText ?? this.jsonText,
    dirty: dirty ?? this.dirty,
    readOnly: readOnly ?? this.readOnly,
    busy: busy ?? this.busy,
    error: identical(error, _modeEditorUnset) ? this.error : error as String?,
    issues: issues ?? this.issues,
    preview: identical(preview, _modeEditorUnset)
        ? this.preview
        : preview as WorkflowPreviewSnapshot?,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
  );
}

final class _ModeEditorSnapshot {
  const _ModeEditorSnapshot({
    required this.document,
    required this.jsonText,
    required this.jsonApplied,
  });

  final ModeDocument document;
  final String jsonText;
  final bool jsonApplied;
}

/// Client-owned Mode authoring draft and typed command admission.
class ModeEditorOwner extends ReadModel<ModeEditorState> {
  ModeEditorOwner(this._client) : super(const ModeEditorState());

  final AnyworkClient _client;
  ResourcePermit? _permit;
  final CommandLane _lane = CommandLane();
  final List<_ModeEditorSnapshot> _undo = [];
  final List<_ModeEditorSnapshot> _redo = [];

  String? _modeId;
  int _revision = 0;
  ModeDocument? _savedDocument;
  String _savedJson = '';
  bool _jsonApplied = true;
  bool _jsonEditSession = false;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _closing;

  Future<void> close() {
    final existing = _closing;
    if (existing != null) return existing;
    _closed = true;
    _lane.seal();
    return _closing = () async {
      try {
        await _lane.join();
      } finally {
        _permit?.release();
        _permit = null;
        _undo.clear();
        _redo.clear();
        _savedDocument = null;
        _savedJson = '';
        source.close();
      }
    }();
  }

  Future<bool> open(String id) async {
    _ensureOpen();
    if (state.busy) return false;
    if (state.dirty) {
      _publish(
        error: 'Discard or save the current Mode draft before opening another',
      );
      return false;
    }
    final generation = ++_generation;
    _publish(busy: true, error: null, issues: const [], preview: null);
    try {
      final snapshot = await _lane.run(
        () => _client.transport.readThreadModeDefinition(id),
      );
      if (_closed || generation != _generation) return false;
      _adoptSnapshot(snapshot, resetHistory: true);
      return true;
    } catch (error) {
      if (!_closed && generation == _generation) {
        _publish(error: error.toString());
      }
      return false;
    } finally {
      if (!_closed && generation == _generation) _publish(busy: false);
    }
  }

  void create({
    required String id,
    required String displayName,
    ModeDocument? template,
  }) {
    _ensureOpen();
    if (state.busy) return;
    if (state.dirty) {
      _publish(
        error: 'Discard or save the current Mode draft before creating another',
      );
      return;
    }
    if (_isBuiltinId(id)) {
      _publish(error: 'Built-in Mode IDs cannot be created or overwritten');
      return;
    }
    final templateDefinition = template?.definition;
    final document = ModeDocument(
      definition: ModeDefinition(
        id: id,
        displayName: displayName,
        description: templateDefinition?.description ?? '',
        order: templateDefinition?.order ?? 0,
        prompt: templateDefinition?.prompt ?? '',
        workflow: templateDefinition?.workflow,
      ),
      editor: template?.editor ?? const ModeEditorLayout(),
    );
    _modeId = id;
    _revision = _client.modeCatalog.state.revision;
    _savedDocument = null;
    _savedJson = '';
    _jsonApplied = true;
    _jsonEditSession = false;
    _undo.clear();
    _redo.clear();
    _publish(
      document: document,
      jsonText: _encode(document),
      dirty: true,
      readOnly: false,
      error: null,
      issues: const [],
      preview: null,
      canUndo: false,
      canRedo: false,
    );
  }

  void replace(ModeDocument doc) {
    _ensureOpen();
    if (_guardWritable()) return;
    if (state.busy || doc == state.document) return;
    if (_isBuiltinId(doc.definition.id)) {
      _publish(
        error: 'Built-in Mode IDs cannot be overwritten; use a custom ID',
      );
      return;
    }
    _recordUndo();
    _jsonEditSession = false;
    _jsonApplied = true;
    _modeId = doc.definition.id;
    final jsonText = _encode(doc);
    _publish(
      document: doc,
      jsonText: jsonText,
      dirty: _computeDirty(doc, jsonText),
      error: null,
      issues: const [],
      preview: null,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
  }

  void editJson(String raw) {
    _ensureOpen();
    if (_guardWritable()) return;
    if (state.busy || raw == state.jsonText) return;
    if (!_jsonEditSession) {
      _recordUndo();
      _jsonEditSession = true;
    }
    _jsonApplied = false;
    _publish(
      jsonText: raw,
      dirty: true,
      error: null,
      issues: const [],
      preview: null,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
  }

  Future<bool> applyJson() async {
    _ensureOpen();
    if (_guardWritable()) return false;
    if (state.busy) return false;
    final generation = ++_generation;
    final raw = state.jsonText;
    _publish(busy: true, error: null, issues: const []);
    try {
      final result = await _lane.run(
        () => _client.transport.validateThreadModeDefinition(raw),
      );
      if (_closed || generation != _generation) return false;
      final document = result.document;
      if (document == null || result.issues.isNotEmpty) {
        _publish(
          issues: result.issues,
          error: result.issues.isEmpty
              ? 'The Mode definition could not be decoded'
              : result.issues.first.message,
        );
        return false;
      }
      if (_isBuiltinId(document.definition.id)) {
        _publish(
          error: 'Built-in Mode IDs cannot be overwritten; use a custom ID',
        );
        return false;
      }
      _recordUndo();
      _jsonEditSession = false;
      _jsonApplied = true;
      _modeId = document.definition.id;
      _publish(
        document: document,
        dirty: _computeDirty(document, raw),
        error: null,
        issues: const [],
        preview: null,
        canUndo: _undo.isNotEmpty,
        canRedo: false,
      );
      return true;
    } catch (error) {
      if (!_closed && generation == _generation) {
        _publish(error: error.toString());
      }
      return false;
    } finally {
      if (!_closed && generation == _generation) _publish(busy: false);
    }
  }

  void undo() {
    _ensureOpen();
    if (state.busy || _undo.isEmpty) return;
    _redo.add(_currentSnapshot());
    _trimHistory(_redo);
    final previous = _undo.removeLast();
    _restore(previous);
  }

  void redo() {
    _ensureOpen();
    if (state.busy || _redo.isEmpty) return;
    _undo.add(_currentSnapshot());
    _trimHistory(_undo);
    final next = _redo.removeLast();
    _restore(next);
  }

  Future<bool> save() async {
    _ensureOpen();
    if (_guardWritable()) return false;
    if (state.busy) return false;
    final initial = state.document;
    if (initial == null) {
      _publish(error: 'There is no Mode definition to save');
      return false;
    }
    if (!state.dirty && _savedDocument != null) return true;
    if (!_jsonApplied) {
      if (!await applyJson()) return false;
      if (_guardWritable()) return false;
    }
    final document = state.document;
    if (document == null) return false;
    final generation = ++_generation;
    _publish(busy: true, error: null);
    try {
      final reply = await _execute(
        'save:${document.definition.id}',
        (operationId) => _client.transport.saveThreadModeDefinition(
          document,
          expectedRevision: _revision,
          operationId: operationId,
        ),
      );
      if (reply == null || _closed) return false;
      final snapshot = reply.definition;
      if (snapshot == null) {
        final jsonText = _encode(document);
        _savedDocument = document;
        _savedJson = jsonText;
        _revision = reply.catalog.revision;
        _publish(document: document, jsonText: jsonText, dirty: false);
      } else {
        _adoptSnapshot(snapshot, resetHistory: false);
      }
      return true;
    } finally {
      if (!_closed && generation == _generation) _publish(busy: false);
    }
  }

  Future<bool> delete() async {
    _ensureOpen();
    if (_guardWritable()) return false;
    if (state.busy) return false;
    final modeId = _modeId ?? state.document?.definition.id;
    if (modeId == null) {
      _publish(error: 'There is no Mode definition to delete');
      return false;
    }
    final generation = ++_generation;
    _publish(busy: true, error: null);
    try {
      final reply = await _execute(
        'delete:$modeId',
        (operationId) => _client.transport.deleteThreadModeDefinition(
          modeId,
          expectedRevision: _revision,
          operationId: operationId,
        ),
      );
      if (reply == null || _closed) return false;
      _modeId = null;
      _revision = 0;
      _savedDocument = null;
      _savedJson = '';
      _undo.clear();
      _redo.clear();
      _publish(
        document: null,
        jsonText: '',
        dirty: false,
        readOnly: false,
        error: null,
        issues: const [],
        preview: null,
        canUndo: false,
        canRedo: false,
      );
      return true;
    } finally {
      if (!_closed && generation == _generation) _publish(busy: false);
    }
  }

  Future<bool> reload() async {
    _ensureOpen();
    if (state.busy) return false;
    if (state.dirty) {
      _publish(
        error: 'Discard or save the current Mode draft before reloading',
      );
      return false;
    }
    final modeId = _modeId;
    final generation = ++_generation;
    _publish(busy: true, error: null);
    try {
      final reply = await _execute(
        'reload',
        (operationId) => _client.transport.reloadThreadModeDefinitions(
          expectedRevision: _client.modeCatalog.state.loaded
              ? _client.modeCatalog.state.revision
              : _revision,
          operationId: operationId,
        ),
      );
      if (reply == null || _closed) return false;
      if (modeId == null ||
          !reply.catalog.modes.any((mode) => mode.id == modeId)) {
        _modeId = null;
        _revision = reply.catalog.revision;
        _savedDocument = null;
        _savedJson = '';
        _jsonApplied = true;
        _jsonEditSession = false;
        _undo.clear();
        _redo.clear();
        _publish(
          document: null,
          jsonText: '',
          dirty: false,
          readOnly: false,
          error: null,
          issues: const [],
          preview: null,
          canUndo: false,
          canRedo: false,
        );
        return true;
      }
      final snapshot = await _lane.run(
        () => _client.transport.readThreadModeDefinition(modeId),
      );
      if (_closed || generation != _generation) return false;
      _adoptSnapshot(snapshot, resetHistory: true);
      return true;
    } catch (error) {
      if (!_closed && generation == _generation) {
        _publish(error: error.toString());
      }
      return false;
    } finally {
      if (!_closed && generation == _generation) _publish(busy: false);
    }
  }

  Future<void> validate() async {
    _ensureOpen();
    if (state.busy) return;
    final generation = ++_generation;
    _publish(busy: true, error: null);
    try {
      final result = await _lane.run(
        () => _client.transport.validateThreadModeDefinition(state.jsonText),
      );
      if (_closed || generation != _generation) return;
      _publish(
        issues: result.issues,
        error: result.issues.isEmpty ? null : result.issues.first.message,
      );
    } catch (error) {
      if (!_closed && generation == _generation) {
        _publish(error: error.toString());
      }
    } finally {
      if (!_closed && generation == _generation) _publish(busy: false);
    }
  }

  Future<void> preview({
    String? targetStateId,
    bool reset = false,
    String reason = '手动确认阶段完成和转换条件',
  }) async {
    _ensureOpen();
    if (state.busy) return;
    if (!_jsonApplied) {
      if (!await applyJson()) return;
      if (state.busy) return;
    }
    final document = state.document;
    if (document == null) {
      _publish(error: 'There is no Mode definition to preview');
      return;
    }
    final generation = ++_generation;
    final path = reset
        ? const <String>[]
        : state.preview?.path ?? const <String>[];
    _publish(busy: true, error: null);
    try {
      final result = await _lane.run(
        () => _client.transport.previewThreadModeWorkflow(
          WorkflowPreviewRequest(
            document: document,
            path: path,
            targetStateId: targetStateId,
            reason: reason,
          ),
        ),
      );
      if (_closed || generation != _generation) return;
      _publish(preview: result, error: result.accepted ? null : result.message);
    } catch (error) {
      if (!_closed && generation == _generation) {
        _publish(error: error.toString());
      }
    } finally {
      if (!_closed && generation == _generation) _publish(busy: false);
    }
  }

  Future<String> schema() async {
    _ensureOpen();
    try {
      return await _lane.run(_client.transport.threadModeDefinitionSchema);
    } catch (error) {
      if (!_closed) _publish(error: error.toString());
      rethrow;
    }
  }

  void discard() {
    _ensureOpen();
    if (state.busy) return;
    _undo.clear();
    _redo.clear();
    _jsonEditSession = false;
    if (_savedDocument == null) {
      _modeId = null;
      _revision = 0;
      _publish(
        document: null,
        jsonText: '',
        dirty: false,
        readOnly: false,
        error: null,
        issues: const [],
        preview: null,
        canUndo: false,
        canRedo: false,
      );
      return;
    }
    _jsonApplied = true;
    _modeId = _savedDocument!.definition.id;
    _publish(
      document: _savedDocument,
      jsonText: _savedJson,
      dirty: false,
      error: null,
      issues: const [],
      preview: null,
      canUndo: false,
      canRedo: false,
    );
  }

  Future<ModeDefinitionCommandReply?> _execute(
    String target,
    Future<ModeDefinitionCommandReply> Function(OperationId operationId)
    request,
  ) async {
    if (_closed) return null;
    final operation = _client.mutations.begin(target: 'mode-editor:$target');
    try {
      final reply = await _lane.enqueue(() => request(operation.id));
      if (!_closed) {
        _client.modeCatalog.apply(reply.catalog);
        for (final target in reply.receipt.targets) {
          if (target.revision == reply.catalog.revision) {
            _client.observeResource(target.resourceKey, target.revision);
          }
        }
      }
      operation.accept(reply.receipt.toCommitReceipt());
      return reply;
    } catch (error) {
      if (operation.state.value.receipt != null) {
        operation.syncFailed(error);
      } else if (_knownRejection(error)) {
        operation.reject(error);
      } else {
        operation.unknownOutcome(error);
      }
      if (!_closed) _publish(error: error.toString());
      return null;
    }
  }

  void _adoptSnapshot(
    ModeDefinitionSnapshot snapshot, {
    required bool resetHistory,
  }) {
    _modeId = snapshot.document.definition.id;
    _revision = snapshot.revision;
    _savedDocument = snapshot.document;
    _savedJson = _encode(snapshot.document);
    _jsonApplied = true;
    _jsonEditSession = false;
    if (resetHistory) {
      _undo.clear();
      _redo.clear();
    }
    _publish(
      document: snapshot.document,
      jsonText: _savedJson,
      dirty: false,
      readOnly: snapshot.readOnly,
      error: null,
      issues: const [],
      preview: null,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
  }

  void _restore(_ModeEditorSnapshot snapshot) {
    _jsonApplied = snapshot.jsonApplied;
    _jsonEditSession = false;
    _modeId = snapshot.document.definition.id;
    final jsonText = snapshot.jsonText;
    _publish(
      document: snapshot.document,
      jsonText: jsonText,
      dirty: _computeDirty(snapshot.document, jsonText),
      error: null,
      issues: const [],
      preview: null,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
  }

  _ModeEditorSnapshot _currentSnapshot() => _ModeEditorSnapshot(
    document: state.document!,
    jsonText: state.jsonText,
    jsonApplied: _jsonApplied,
  );

  void _recordUndo() {
    final document = state.document;
    if (document == null) return;
    _undo.add(
      _ModeEditorSnapshot(
        document: document,
        jsonText: state.jsonText,
        jsonApplied: _jsonApplied,
      ),
    );
    _trimHistory(_undo);
    _redo.clear();
  }

  void _trimHistory(List<_ModeEditorSnapshot> history) {
    while (history.length > _modeEditorHistoryLimit) {
      history.removeAt(0);
    }
  }

  bool _computeDirty(ModeDocument document, String jsonText) {
    final saved = _savedDocument;
    return saved == null || document != saved || jsonText != _savedJson;
  }

  bool _isBuiltinId(String id) =>
      id == ThreadModeId.simple.id ||
      id == ThreadModeId.task.id ||
      (_client.modeCatalog.state.value?.modes.any(
            (mode) => mode.id == id && mode.readOnly,
          ) ??
          false);

  bool _guardWritable() {
    if (!state.readOnly) return false;
    _publish(error: 'Built-in Mode definitions are read-only');
    return true;
  }

  void _publish({
    Object? document = _modeEditorUnset,
    String? jsonText,
    bool? dirty,
    bool? readOnly,
    bool? busy,
    Object? error = _modeEditorUnset,
    List<ModeValidationIssue>? issues,
    Object? preview = _modeEditorUnset,
    bool? canUndo,
    bool? canRedo,
  }) {
    if (_closed) return;
    state = state.copyWith(
      document: document,
      jsonText: jsonText,
      dirty: dirty,
      readOnly: readOnly,
      busy: busy,
      error: error,
      issues: issues,
      preview: preview,
      canUndo: canUndo,
      canRedo: canRedo,
    );
  }

  void _ensureOpen() {
    if (_closed || _client.isClosed) {
      throw StateError('The Mode editor is closed');
    }
    _permit ??= _client.budget.acquire(
      ResourceKind.draft,
      owner: 'mode-editor',
    );
  }
}

String _encode(ModeDocument document) =>
    const JsonEncoder.withIndent('  ').convert(document.toJson());

bool _knownRejection(Object error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.notFound ||
      StudioFailureCode.busy ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.overloaded ||
      StudioFailureCode.notInitialized => true,
      _ => false,
    };
