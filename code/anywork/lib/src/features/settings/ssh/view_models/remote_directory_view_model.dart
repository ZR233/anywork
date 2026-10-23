import 'dart:async';

import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../state/remote_directory_view_state.dart';

part 'remote_directory_view_model.g.dart';

@riverpod
class RemoteDirectoryViewModel extends _$RemoteDirectoryViewModel {
  late RemoteRepository _remote;
  late WorkspaceRepository _workspace;
  late String _alias;
  RemoteDirectoryQuery? _query;
  Observation? _observation;
  final _retired = <RemoteDirectoryQuery, CloseReport?>{};
  final _closingQueries = <RemoteDirectoryQuery, Future<CloseReport>>{};
  Completer<void>? _browseSettled;
  Future<bool>? _closeTask;
  bool _alive = true;
  bool _browsing = false;
  bool _openingProject = false;
  bool _closing = false;
  bool _started = false;
  int _generation = 0;
  int _lifetime = 0;
  void Function()? _releaseRetention;

  @override
  Future<RemoteDirectoryViewState> build(String alias, int pickerId, bool showProjectNameField) async {
    _alive = true; _lifetime++; _alias = alias;
    _remote = ref.watch(remoteRepositoryProvider);
    _workspace = ref.watch(workspaceRepositoryProvider);
    _releaseRetention = ref.keepAlive().close;
    ref.onDispose(() {
      _alive = false; _lifetime++; _generation++;
      _observation?.cancel(); _observation = null;
      // Query and all accepted work remain supervised by RemoteRepository.
      // Explicit leave closes the borrow; disposal must not pretend to join it.
    });
    return RemoteDirectoryViewState(alias: alias, showProjectNameField: showProjectNameField);
  }
  String? get openedPath => _alive ? state.asData?.value.completedPath : null;
  bool _owns(int lifetime, int generation) => _alive && lifetime == _lifetime &&
    generation == _generation && state.asData != null && !_closing;
  void setPath(String raw) {
    if (!_alive || _browsing || _openingProject || _closing || state.asData == null) return;
    state = AsyncData(state.requireValue.copyWith(pathRaw: raw, pathIssue: null, error: null));
  }
  void setName(String raw) {
    if (!_alive || state.asData == null || !state.requireValue.showProjectNameField || _browsing || _openingProject || _closing) return;
    state = AsyncData(state.requireValue.copyWith(nameRaw: raw, nameEdited: true, nameRequired: false));
  }
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await browse(null);
  }
  Future<void> go() async {
    if (!_alive || state.asData == null || _browsing || _openingProject || _closing) return;
    final raw = state.requireValue.pathRaw.trim();
    if (raw.isEmpty || !raw.startsWith('/')) {
      state = AsyncData(state.requireValue.copyWith(pathIssue: raw.isEmpty ? RemotePathIssue.required : RemotePathIssue.absolute));
      return;
    }
    await browse(raw);
  }
  Future<void> browse(String? path) async {
    if (!_alive || state.asData == null || _browsing || _openingProject || _closing) return;
    if (path != null && !path.startsWith('/')) {
      state = AsyncData(state.requireValue.copyWith(pathIssue: RemotePathIssue.absolute)); return;
    }
    _browsing = true;
    final settled = Completer<void>();
    _browseSettled = settled;
    final lifetime = _lifetime;
    final generation = ++_generation;
    final alias = _alias;
    final remote = _remote;
    final previous = _query;
    _query = null;
    _observation?.cancel(); _observation = null;
    state = AsyncData(state.requireValue.copyWith(generation: generation, browsing: true,
      pathRaw: path ?? state.requireValue.pathRaw, directory: null, verified: false,
      pathIssue: null, error: null, observationError: null));
    try {
      if (previous != null) await _retire(previous);
      if (!_owns(lifetime, generation)) return;
      final query = await remote.openDirectory(alias, path: path);
      if (!_owns(lifetime, generation)) { await _retire(query); return; }
      _query = query;
      LatestWatch<RemoteDirectoryState> watch;
      try {
        watch = query.state.watchLatest((directory) {
        if (_owns(lifetime, generation) && identical(_query, query)) _publishDirectory(directory);
      });
      } on StudioFailure catch (error) {
        if (_owns(lifetime, generation)) {
          _publishDirectory(query.state.value, observed: false);
          if (_owns(lifetime, generation)) state = AsyncData(state.requireValue.copyWith(observationError: error, verified: false));
        }
        return;
      }
      if (!_owns(lifetime, generation) || !identical(_query, query)) {
        watch.observation.cancel(); await _retire(query); return;
      }
      _observation = watch.observation;
      _publishDirectory(watch.value);
    } on StudioFailure catch (error) {
      if (_owns(lifetime, generation)) state = AsyncData(state.requireValue.copyWith(error: error, verified: false));
    } finally {
      _browsing = false;
      if (_alive && lifetime == _lifetime && state.asData != null) {
        state = AsyncData(state.requireValue.copyWith(browsing: false));
      }
      settled.complete();
      if (identical(_browseSettled, settled)) _browseSettled = null;
    }
  }
  void _publishDirectory(RemoteDirectoryState directory, {bool observed = true}) {
    final absolute = directory.path.startsWith('/');
    final current = state.requireValue;
    final suggestedName = directory.path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? 'remote-workspace';
    final useSuggested = current.showProjectNameField && !current.nameEdited && absolute && !directory.loading && directory.error == null;
    state = AsyncData(state.requireValue.copyWith(directory: directory,
      pathRaw: directory.path, verified: observed && absolute && !directory.loading && directory.error == null,
      nameRaw: useSuggested ? suggestedName : current.nameRaw,
      pathIssue: absolute ? null : RemotePathIssue.absolute, error: directory.error));
  }
  Future<void> nextPage() async {
    final query = _query;
    if (!_alive || state.asData == null || query == null || _browsing || _openingProject || _closing ||
        state.requireValue.directory?.nextCursor == null) return;
    final lifetime = _lifetime;
    final generation = _generation;
    _browsing = true;
    final settled = Completer<void>(); _browseSettled = settled;
    state = AsyncData(state.requireValue.copyWith(browsing: true, verified: false, error: null));
    try {
      if (!_owns(lifetime, generation) || !identical(query, _query)) return;
      // Native nextCursor remains inside this exact query. The returned page
      // replaces its old page; the VM never synthesizes a cursor or appends.
      await query.loadMore();
      if (_owns(lifetime, generation) && identical(query, _query)) _publishDirectory(query.state.value);
    } on StudioFailure catch (error) {
      if (_owns(lifetime, generation)) state = AsyncData(state.requireValue.copyWith(error: error, verified: false));
    } finally {
      _browsing = false;
      if (_alive && lifetime == _lifetime && state.asData != null) state = AsyncData(state.requireValue.copyWith(browsing: false));
      settled.complete(); if (identical(_browseSettled, settled)) _browseSettled = null;
    }
  }
  Future<void> _retire(RemoteDirectoryQuery query, {bool retry = false}) async {
    query.requestClose();
    _retired.putIfAbsent(query, () => null);
    final existing = _closingQueries[query];
    final task = existing ?? (retry ? query.retryCleanup() : query.close());
    _closingQueries[query] = task;
    try {
      final report = await task;
      if (report.complete) { _retired.remove(query); } else { _retired[query] = report; }
      if (_alive && state.asData != null) state = AsyncData(state.requireValue.copyWith(
        cleanupReports: [for (final value in _retired.values) if (value != null) value]));
    } finally {
      if (identical(_closingQueries[query], task)) _closingQueries.remove(query);
    }
  }
  Future<bool> close({bool retry = false}) {
    if (_openingProject) return Future.value(false);
    if (_closeTask case final task?) return task;
    final settled = Completer<bool>();
    final task = settled.future;
    _closeTask = task;
    _closing = true; _generation++;
    final query = _query; _query = null;
    query?.requestClose();
    _observation?.cancel(); _observation = null;
    if (_alive && state.asData != null) state = AsyncData(state.requireValue.copyWith(closing: true, verified: false));
    unawaited(_close(query, retry).then<void>(settled.complete,
      onError: (Object error, StackTrace stack) => settled.completeError(error, stack)));
    unawaited(task.then<void>((_) { if (identical(_closeTask, task)) _closeTask = null; },
      onError: (Object error, StackTrace stack) { if (identical(_closeTask, task)) _closeTask = null; }));
    return task;
  }
  Future<bool> _close(RemoteDirectoryQuery? query, bool retry) async {
    try {
      if (query != null) await _retire(query);
      // A late open is handed back to its original alias owner by browse().
      await _browseSettled?.future;
      for (final owner in List<RemoteDirectoryQuery>.of(_retired.keys)) await _retire(owner, retry: retry);
      return _retired.isEmpty;
    } on StudioFailure catch (error) {
      if (_alive && state.asData != null) state = AsyncData(state.requireValue.copyWith(error: error));
      return false;
    }
  }
  void endBrowsing() {
    _alive = false;
    _releaseRetention?.call(); _releaseRetention = null;
  }
  Future<bool> openProject() async {
    if (!_alive || state.asData == null || _openingProject || _browsing || _closing) return false;
    if (state.requireValue.showProjectNameField && state.requireValue.nameRaw.trim().isEmpty) {
      state = AsyncData(state.requireValue.copyWith(nameRequired: true)); return false;
    }
    if (!state.requireValue.canOpen) return false;
    final alias = _alias;
    final path = state.requireValue.directory!.path;
    final name = state.requireValue.showProjectNameField ? state.requireValue.nameRaw.trim() : null;
    final workspace = _workspace;
    final generation = _generation;
    final lifetime = _lifetime;
    _openingProject = true;
    state = AsyncData(state.requireValue.copyWith(opening: true, error: null, openResult: null));
    try {
      if (!_owns(lifetime, generation)) return false;
      final batch = workspace.openRemoteProject(alias, path, name: name);
      final result = await batch.result;
      if (!_owns(lifetime, generation)) return false;
      final actions = [for (final step in result.steps) switch (step) {
        OpenedWorkspaceOpenStep(:final result) => settledSettingsAction(0, result),
        RenamedWorkspaceOpenStep(:final result) => settledSettingsAction(0, result),
        ActivatedWorkspaceOpenStep(:final result) => settledSettingsAction(0, result),
        NotStartedWorkspaceOpenStep(:final error) => SettingsAction(intent: 0, outcome: SettingsActionOutcome.rejected, error: error),
      }];
      final applied = result.selection;
      final succeeded = actions.isNotEmpty && actions.every((action) => action.succeeded) &&
        applied is AppliedWorkspaceOpenSelection && applied.value.disposition != SelectionDisposition.superseded;
      state = AsyncData(state.requireValue.copyWith(openResult: result,
        openUncertain: actions.any((action) => action.preventsResubmission), completedPath: succeeded ? path : null));
      return succeeded;
    } on StudioFailure catch (error) {
      if (_owns(lifetime, generation)) state = AsyncData(state.requireValue.copyWith(error: error));
      return false;
    } finally {
      _openingProject = false;
      if (_alive && lifetime == _lifetime && state.asData != null) state = AsyncData(state.requireValue.copyWith(opening: false));
    }
  }
}
