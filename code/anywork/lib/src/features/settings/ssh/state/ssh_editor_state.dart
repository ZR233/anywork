import 'package:anywork_client/remote.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';

part 'ssh_editor_state.freezed.dart';

enum SshEditorField { alias, host, port, username, identityFile }

enum SshValidation { required, aliasInvalid, portInvalid }

enum SshSecretIntent { preserve, replace, clear }

/// No JSON or generated toString for any state that can contain a password.
@Freezed(toStringOverride: false)
abstract class SshEditorViewState with _$SshEditorViewState {
  const SshEditorViewState._();
  const factory SshEditorViewState({
    required SshEditorKey target,
    SshServerRuntimeEntry? canonical,
    @Default('') String alias,
    @Default('') String host,
    @Default('22') String port,
    @Default('') String username,
    @Default('') String identityFile,
    @Default('') String password,
    @Default(SshSecretIntent.preserve) SshSecretIntent passwordIntent,
    @Default(false) bool passwordVisible,
    @Default(false) bool dirty,
    @Default(0) int draftRevision,
    @Default({}) Map<SshEditorField, SshValidation> validation,
    SettingsAction? saveAction,
  }) = _SshEditorViewState;
  bool get editing => target.alias != null;
  bool get hasPassword => canonical?.hasPassword ?? false;
  bool get readOnly => canonical?.managed == false;
  bool get saving => saveAction?.pending ?? false;
}

@Freezed(toStringOverride: false)
abstract class SshPasswordViewState with _$SshPasswordViewState {
  const factory SshPasswordViewState({
    required String alias,
    @Default('') String password,
    @Default(true) bool rememberPassword,
    @Default(false) bool passwordVisible,
    @Default(false) bool requiredError,
    SshConnectionSnapshot? connection,
    SettingsAction? action,
  }) = _SshPasswordViewState;
}
