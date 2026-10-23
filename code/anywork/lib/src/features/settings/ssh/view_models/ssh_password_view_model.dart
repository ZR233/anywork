import 'package:anywork_client/remote.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../state/ssh_editor_state.dart';
import 'ssh_operation_watch.dart';

part 'ssh_password_view_model.g.dart';

@riverpod
class SshPasswordViewModel extends _$SshPasswordViewModel {
  late RemoteRepository _repository;
  final _operation = SshOperationWatch();
  bool _alive = true;
  bool _submitting = false;
  int _lifetime = 0;
  int _intent = 0;
  void Function()? _releaseRetention;
  @override
  Future<SshPasswordViewState> build(String alias, int scopeId, int promptId) async {
    _alive = true; _lifetime++;
    _repository = ref.watch(remoteRepositoryProvider);
    _releaseRetention = ref.keepAlive().close;
    ref.onDispose(() { _alive = false; _lifetime++; _operation.dispose(); });
    return SshPasswordViewState(alias: alias);
  }
  bool get _editable => _alive && !_submitting && state.asData != null && !(state.requireValue.action?.preventsResubmission ?? false);
  void endEditing() { _alive = false; _releaseRetention?.call(); _releaseRetention = null; }
  void setPassword(String value) {
    if (_editable) state = AsyncData(state.requireValue.copyWith(password: value, requiredError: false));
  }
  void setRemember(bool value) {
    if (_editable) state = AsyncData(state.requireValue.copyWith(rememberPassword: value));
  }
  void toggleVisibility() {
    if (_alive && state.asData != null) state = AsyncData(state.requireValue.copyWith(passwordVisible: !state.requireValue.passwordVisible));
  }
  Future<bool> submit() async {
    if (!_editable) return false;
    if (state.requireValue.password.trim().isEmpty) {
      state = AsyncData(state.requireValue.copyWith(requiredError: true)); return false;
    }
    _submitting = true;
    final frozen = state.requireValue;
    final lifetime = _lifetime;
    final repository = _repository;
    final intent = ++_intent;
    try {
      state = AsyncData(frozen.copyWith(action: SettingsAction(intent: intent, pending: true), connection: null));
      bool owns() => _alive && lifetime == _lifetime && state.asData?.value.action?.intent == intent;
      if (!owns()) return false;
      final result = await _operation.run(intent: intent,
        admit: () => repository.authenticate(frozen.alias, frozen.password, rememberPassword: frozen.rememberPassword),
        owns: owns, update: (action) => state = AsyncData(state.requireValue.copyWith(action: action)));
      if (!owns()) return false;
      final connection = repository.state.value.connections[frozen.alias];
      state = AsyncData(state.requireValue.copyWith(connection: connection));
      final ready = result.action.succeeded && connection?.state is ReadySshConnectionState;
      if (ready) state = AsyncData(state.requireValue.copyWith(password: ''));
      return ready;
    } finally { _submitting = false; }
  }
}
