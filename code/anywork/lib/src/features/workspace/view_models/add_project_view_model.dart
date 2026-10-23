import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/add_project_state.dart';
import '../state/workspace_view_state.dart';

part 'add_project_view_model.g.dart';

/// Dialog editing/workflow only. Remote and Workspace remain the canonical
/// owners of commands and batches, including results after this VM is disposed.
@riverpod
class AddProjectViewModel extends _$AddProjectViewModel {
  final List<Observation> _observations = [];
  Observation? _operation;
  bool _alive = true;
  bool _initializing = false;
  int _intent = 0;
  int _binding = 0;

  @override
  FutureOr<AddProjectState> build(AddProjectDialogKey target) {
    _alive = true;
    _initializing = true;
    ref.onDispose(_dispose);
    try {
      final remote = ref.watch(remoteRepositoryProvider);
      final workspace = ref.watch(workspaceRepositoryProvider);
      final connections = remote.state.watchLatest((value) {
        if (!_alive || _initializing) return;
        final previous = state.requireValue;
        state = AsyncData(previous.copyWith(connections: value,
          selectedServer: value.servers == null ? previous.selectedServer
              : value.servers!.where((server) => server.profile.alias == previous.selectedAlias).firstOrNull));
      });
      _observations.add(connections.observation);
      final selection = workspace.state.watchLatest((value) {
        if (_alive && !_initializing) state = AsyncData(state.requireValue.copyWith(sealed: value.sealed));
      });
      _observations.add(selection.observation);
      _initializing = false;
      return AddProjectState(step: AddProjectStep.location, remote: null,
        rawSearch: '', localPathRaw: '', connections: remote.state.value, selectedServer: null,
        picking: false, pending: false, sealed: workspace.state.value.sealed,
        action: null, failure: null, authenticationFailure: null,
        passwordUnavailable: false, connection: null, opened: null);
    } catch (error, stack) {
      _dispose();
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _dispose() {
    _alive = false;
    ++_intent;
    ++_binding;
    _operation?.cancel();
    _operation = null;
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
  }

  bool get _editable => _alive && !state.requireValue.pending && !state.requireValue.sealed;

  void chooseLocation(bool remote) {
    if (!_editable) return;
    ++_intent;
    state = AsyncData(state.requireValue.copyWith(remote: remote, failure: null));
  }

  void changeSearch(String raw) {
    if (!_editable) return;
    ++_intent;
    state = AsyncData(state.requireValue.copyWith(rawSearch: raw));
  }

  void chooseServer(SshServerRuntimeEntry server) {
    if (!_editable) return;
    ++_intent;
    state = AsyncData(state.requireValue.copyWith(selectedServer: server,
      failure: null, authenticationFailure: null, passwordUnavailable: false, connection: null));
  }

  void back() {
    if (!_editable) return;
    ++_intent;
    state = AsyncData(state.requireValue.copyWith(step: switch (state.requireValue.step) {
      AddProjectStep.directory => AddProjectStep.connections,
      _ => AddProjectStep.location,
    }, failure: null, authenticationFailure: null, passwordUnavailable: false));
  }

  void dismissOpenResult() {
    state = AsyncData(state.requireValue.copyWith(opened: null));
  }

  Future<void> showConnections() async {
    if (!_editable) return;
    state = AsyncData(state.requireValue.copyWith(step: AddProjectStep.connections));
    await reloadServers();
  }

  Future<void> reloadServers() async {
    if (!_editable) return;
    final remote = ref.read(remoteRepositoryProvider);
    await _command(remote.reloadServers);
  }

  AddProjectEditorIntent? beginEditorIntent() => _editable
      ? AddProjectEditorIntent._(this, _binding, ++_intent) : null;

  void editorSaved(SshServerRuntimeEntry saved, AddProjectEditorIntent original) {
    if (!_editable || !identical(original._owner, this) ||
        original._binding != _binding || original._intent != _intent) return;
    // The helper returns this exact save result, including a new alias. Keep
    // it as the UI selection target even if a full list is not materialized;
    // never merge it into RemoteState or infer it from a reload/diff/editor.
    // chooseServer consumes the intent before its state publication can reenter.
    chooseServer(saved);
  }

  void reportPlatformFailure(StudioFailure failure) {
    if (_alive) state = AsyncData(state.requireValue.copyWith(failure: failure));
  }

  void changeLocalPath(String raw) {
    if (_alive && state.requireValue.picking && !state.requireValue.sealed) {
      state = AsyncData(state.requireValue.copyWith(localPathRaw: raw));
    }
  }

  String? submitLocalPath() {
    if (!_alive || state.requireValue.sealed || !state.requireValue.picking) return null;
    final path = state.requireValue.localPathRaw.trim();
    return path.isEmpty ? null : path;
  }

  Future<void> deleteServer(SshServerRuntimeEntry frozen) async {
    if (!_editable || !frozen.managed) return;
    final remote = ref.read(remoteRepositoryProvider);
    final binding = _binding;
    final intent = _intent + 1;
    final result = await _command(() => remote.delete(frozen.profile.alias));
    if (!_alive || binding != _binding || intent != _intent || result == null) return;
    if (_successful(result)) await reloadServers();
  }

  Future<void> connect(SshServerRuntimeEntry frozen) async {
    if (!_editable) return;
    final remote = ref.read(remoteRepositoryProvider);
    final binding = _binding;
    final intent = _intent + 1;
    final result = await _command(() => remote.test(frozen.profile.alias));
    if (!_alive || binding != _binding || intent != _intent || result == null ||
        state.requireValue.selectedAlias != frozen.profile.alias) return;
    final connection = switch (result) {
      CommittedCommandResult<SshConnectionSnapshot>(:final value) ||
      AcknowledgedCommandResult<SshConnectionSnapshot>(:final value) => value,
      _ => null,
    };
    if (connection != null) {
      authenticated(frozen, connection);
      return;
    }
    final failure = state.requireValue.failure;
    if (failure?.details case SshAuthenticationFailureDetails(:final passwordOffered)) {
      state = AsyncData(state.requireValue.copyWith(
        authenticationFailure: passwordOffered == true ? failure : null,
        passwordUnavailable: passwordOffered != true));
    }
  }

  /// U1's public password prompt performs authentication and owns secret input.
  /// Its result can advance only the original frozen server, never a new alias.
  void authenticated(SshServerRuntimeEntry frozen, SshConnectionSnapshot connection) {
    if (!_editable || state.requireValue.selectedAlias != frozen.profile.alias ||
        connection.alias != frozen.profile.alias) return;
    state = AsyncData(state.requireValue.copyWith(connection: connection,
      authenticationFailure: null, passwordUnavailable: false,
      step: connection.state is ReadySshConnectionState ? AddProjectStep.directory : AddProjectStep.connections));
  }

  /// Called only after U1's public password helper returns true for the frozen
  /// original server. That helper owns the command/result; do not test or
  /// authenticate a second time, or invent a new canonical connection value.
  void passwordAuthenticated(SshServerRuntimeEntry frozen) {
    if (!_editable || state.requireValue.selectedAlias != frozen.profile.alias) return;
    state = AsyncData(state.requireValue.copyWith(step: AddProjectStep.directory,
      connection: null, failure: null, authenticationFailure: null, passwordUnavailable: false));
  }

  Future<bool> openLocal(Future<String?> Function() pickDirectory) async {
    if (!_editable) return false;
    final binding = _binding;
    final intent = ++_intent;
    final workspace = ref.read(workspaceRepositoryProvider);
    var successful = false;
    state = AsyncData(state.requireValue.copyWith(pending: true, picking: true,
      localPathRaw: '', failure: null, opened: null, action: null));
    bool current() => _alive && binding == _binding && intent == _intent;
    try {
      final path = await pickDirectory();
      if (!current() || state.requireValue.sealed) return false;
      state = AsyncData(state.requireValue.copyWith(picking: false));
      // Keep the native picker's original value; only its existing null/empty
      // cancellation semantics apply. Driver raw path trimming is separate.
      if (path == null || path.isEmpty) return false;
      final batch = workspace.openProject(path);
      final result = await batch.result;
      if (current()) state = AsyncData(state.requireValue.copyWith(opened: result));
      successful = _openedSuccessfully(result);
    } on StudioFailure catch (error) {
      if (current()) state = AsyncData(state.requireValue.copyWith(failure: error));
    } finally {
      if (current()) state = AsyncData(state.requireValue.copyWith(pending: false, picking: false));
    }
    return current() && successful;
  }

  Future<CommandResult<T>?> _command<T>(OperationTicket<T> Function() create) async {
    if (!_editable) return null;
    final intent = ++_intent;
    final binding = _binding;
    bool current() => _alive && binding == _binding && intent == _intent;
    CommandResult<T>? settled;
    _operation?.cancel();
    _operation = null;
    state = AsyncData(state.requireValue.copyWith(pending: true, failure: null,
      authenticationFailure: null, passwordUnavailable: false,
      action: WorkspaceActionPresentation(intent: intent, waiting: true,
        operation: null, admissionError: null)));
    try {
      final ticket = create();
      try {
        final watched = ticket.state.watchLatest((value) {
          if (current()) state = AsyncData(state.requireValue.copyWith(
            action: state.requireValue.action!.copyWith(operation: value)));
        });
        if (current()) {
          _operation = watched.observation;
          state = AsyncData(state.requireValue.copyWith(
            action: state.requireValue.action!.copyWith(operation: watched.value)));
        } else {
          watched.observation.cancel();
        }
      } on StudioFailure catch (error) {
        if (current()) state = AsyncData(state.requireValue.copyWith(
          action: state.requireValue.action!.copyWith(observationError: error)));
      }
      final result = await ticket.result;
      if (current()) state = AsyncData(state.requireValue.copyWith(
        action: state.requireValue.action!.copyWith(waiting: false, operation: ticket.state.value),
        failure: switch (result) {
          RejectedCommandResult(:final error) || UnknownOutcomeCommandResult(:final error) ||
          SyncFailedCommandResult(:final error) || AcknowledgedSyncFailedCommandResult(:final error) => error,
          _ => null,
        }));
      settled = result;
    } on StudioFailure catch (error) {
      if (current()) state = AsyncData(state.requireValue.copyWith(failure: error,
        action: state.requireValue.action!.copyWith(waiting: false, admissionError: error)));
    } finally {
      if (current()) state = AsyncData(state.requireValue.copyWith(pending: false));
    }
    // pending=false can synchronously admit a newer UI intent. Do not return
    // an old result to its caller until that re-entrant publication has ended.
    return current() ? settled : null;
  }

  bool _successful<T>(CommandResult<T> result) =>
      result is CommittedCommandResult<T> || result is AcknowledgedCommandResult<T>;

  bool _openedSuccessfully(WorkspaceOpenResult result) =>
      result.selection is AppliedWorkspaceOpenSelection && result.steps.every((step) => switch (step) {
        OpenedWorkspaceOpenStep(:final result) => _successful(result),
        RenamedWorkspaceOpenStep(:final result) => _successful(result),
        ActivatedWorkspaceOpenStep(:final result) => _successful(result),
        NotStartedWorkspaceOpenStep() => false,
      });
}

/// Runtime admission of one U3 editor invocation, not a value/SSH family ID or
/// another registry. It can settle only its original live VM/binding/intent.
final class AddProjectEditorIntent {
  AddProjectEditorIntent._(this._owner, this._binding, this._intent);
  final AddProjectViewModel _owner;
  final int _binding;
  final int _intent;
}
