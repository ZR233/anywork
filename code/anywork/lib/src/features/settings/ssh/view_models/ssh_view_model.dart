import 'package:anywork_client/remote.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';
import '../state/ssh_view_state.dart';
import 'ssh_operation_watch.dart';

part 'ssh_view_model.g.dart';

@Riverpod(keepAlive: true)
class SshViewModel extends _$SshViewModel {
  late RemoteRepository _repository;
  final _reloadWatch = SshOperationWatch();
  final _rowWatches = <String, SshOperationWatch>{};
  bool _alive = true;
  int _lifetime = 0;
  int _editor = 0;
  int _dialog = 0;

  @override
  Future<SshViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(remoteRepositoryProvider);
    final watch = _repository.state.watchLatest((source) {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(source: source));
    });
    ref.onDispose(() {
      _alive = false; _lifetime++;
      watch.observation.cancel(); _reloadWatch.dispose();
      for (final observer in _rowWatches.values) { observer.dispose(); }
      _rowWatches.clear();
    });
    // reloadServers is an explicit action; build merely observes known results.
    return SshViewState(source: watch.value);
  }
  bool _owns(int lifetime) => _alive && lifetime == _lifetime && state.asData != null;
  int get lifetime => _lifetime;
  bool ownsLifetime(int lifetime) => _owns(lifetime);
  SshServerRuntimeEntry? server(String alias) => state.asData?.value.source.servers
    ?.where((entry) => entry.profile.alias == alias).firstOrNull;
  Future<void> enter() async {
    if (state.asData?.value.source.servers == null && state.asData?.value.reloadAction == null) await reload();
  }
  Future<void> reload() async {
    if (!_alive || state.asData == null || (state.requireValue.reloadAction?.preventsResubmission ?? false)) return;
    final lifetime = _lifetime;
    final repository = _repository;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(state.requireValue.copyWith(latestIntent: intent, reloadAction: SettingsAction(intent: intent, pending: true)));
    bool owns() => _owns(lifetime) && state.requireValue.reloadAction?.intent == intent;
    if (!owns()) return;
    await _reloadWatch.run(intent: intent, admit: repository.reloadServers, owns: owns,
      update: (action) => state = AsyncData(state.requireValue.copyWith(reloadAction: action)));
  }
  bool busy(String alias) => (state.asData?.value.actions[alias]?.action.preventsResubmission ?? false) ||
    state.asData?.value.editor?.alias == alias || state.asData?.value.directoryAlias == alias ||
    state.asData?.value.passwordAlias == alias || state.asData?.value.deleteConfirmationAlias == alias;
  bool get _hasModal => state.requireValue.editor != null || state.requireValue.directoryAlias != null ||
    state.requireValue.passwordAlias != null || state.requireValue.deleteConfirmationAlias != null;

  SshEditorKey? beginEditor([String? alias]) {
    if (!_alive || state.asData == null || _hasModal) return null;
    if (alias != null && (busy(alias) || server(alias)?.managed != true)) return null;
    final key = SshEditorKey(editorId: ++_editor, alias: alias);
    state = AsyncData(state.requireValue.copyWith(editor: key));
    return key;
  }
  void finishEditor(SshEditorKey key) {
    if (_alive && state.asData?.value.editor == key) state = AsyncData(state.requireValue.copyWith(editor: null));
  }
  int? beginDirectory(String alias) {
    if (!_alive || state.asData == null || _hasModal || busy(alias) || server(alias) == null) return null;
    final id = ++_dialog;
    state = AsyncData(state.requireValue.copyWith(directoryAlias: alias, directoryDialogId: id));
    return id;
  }
  void finishDirectory(String alias, int id) {
    if (_alive && state.asData?.value.directoryAlias == alias && state.asData?.value.directoryDialogId == id)
      state = AsyncData(state.requireValue.copyWith(directoryAlias: null, directoryDialogId: null));
  }
  ({int scopeId, int promptId})? beginPassword(String alias) {
    if (!_alive || state.asData == null || server(alias) == null) return null;
    final current = state.requireValue;
    if (current.editor != null || current.deleteConfirmationAlias != null || current.passwordAlias != null ||
        current.directoryAlias != null && current.directoryAlias != alias ||
        (current.actions[alias]?.action.preventsResubmission ?? false)) return null;
    final id = ++_dialog;
    final scope = current.directoryDialogId ?? 0;
    state = AsyncData(current.copyWith(passwordAlias: alias, passwordDialogId: id, passwordScopeId: scope));
    return (scopeId: scope, promptId: id);
  }
  void finishPassword(String alias, int id) {
    if (_alive && state.asData?.value.passwordAlias == alias && state.asData?.value.passwordDialogId == id)
      state = AsyncData(state.requireValue.copyWith(passwordAlias: null, passwordDialogId: null, passwordScopeId: null));
  }
  Future<SshPasswordChallenge?> test(String alias) => _connect(alias, SshRowOperation.test);
  bool ownsChallenge(SshPasswordChallenge challenge) => _alive &&
    state.asData?.value.actions[challenge.alias]?.action.intent == challenge.intent &&
    state.asData?.value.actions[challenge.alias]?.action.error == challenge.error;
  Future<SshPasswordChallenge?> reconnect(String alias) => _connect(alias, SshRowOperation.reconnect);
  Future<SshPasswordChallenge?> _connect(String alias, SshRowOperation kind) async {
    final repository = _repository;
    final result = await _run<SshConnectionSnapshot>(alias, kind,
      () => kind == SshRowOperation.test ? repository.test(alias) : repository.reconnect(alias));
    if (result == null || result.action.outcome != SettingsActionOutcome.rejected) return null;
    final error = result.action.error;
    if (error?.details case SshAuthenticationFailureDetails(passwordOffered: true)) {
      return SshPasswordChallenge(alias: alias, intent: result.action.intent, error: error!);
    }
    return null;
  }
  Future<void> delete(String alias) async {
    if (server(alias)?.managed != true || state.asData?.value.deleteConfirmationAlias != alias) return;
    final repository = _repository;
    final result = await _run<Unit>(alias, SshRowOperation.delete, () => repository.delete(alias), confirmedDelete: true);
    if (_alive && state.asData != null && result?.action.succeeded == true && server(alias) == null) {
      _rowWatches.remove(alias)?.dispose();
      state = AsyncData(state.requireValue.copyWith(actions: {...state.requireValue.actions}..remove(alias)));
  }
  }
  bool beginDeleteConfirmation(String alias) {
    if (!_alive || state.asData == null || _hasModal || busy(alias) || server(alias)?.managed != true) return false;
    state = AsyncData(state.requireValue.copyWith(deleteConfirmationAlias: alias));
    return true;
  }
  void cancelDeleteConfirmation(String alias) {
    if (_alive && state.asData?.value.deleteConfirmationAlias == alias)
      state = AsyncData(state.requireValue.copyWith(deleteConfirmationAlias: null));
  }
  Future<({SettingsAction action, T? value})?> _run<T>(String alias, SshRowOperation kind,
      OperationTicket<T> Function() admit, {bool confirmedDelete = false}) async {
    if (!_alive || state.asData == null || server(alias) == null) return null;
    if (confirmedDelete) {
      if (state.requireValue.deleteConfirmationAlias != alias ||
          (state.requireValue.actions[alias]?.action.preventsResubmission ?? false)) return null;
    } else if (busy(alias)) { return null; }
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    final observer = _rowWatches.putIfAbsent(alias, SshOperationWatch.new);
    state = AsyncData(state.requireValue.copyWith(latestIntent: intent,
      deleteConfirmationAlias: confirmedDelete ? null : state.requireValue.deleteConfirmationAlias,
      actions: {...state.requireValue.actions,
      alias: SshRowAction(kind: kind, action: SettingsAction(intent: intent, pending: true))}));
    bool owns() => _owns(lifetime) && state.requireValue.actions[alias]?.action.intent == intent;
    if (!owns()) return null;
    final result = await observer.run<T>(intent: intent, admit: admit, owns: owns,
      update: (action) => state = AsyncData(state.requireValue.copyWith(actions: {...state.requireValue.actions,
        alias: SshRowAction(kind: kind, action: action)})));
    return owns() ? result : null;
  }
}
