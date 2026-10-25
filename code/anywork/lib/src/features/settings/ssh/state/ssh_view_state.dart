import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';

part 'ssh_view_state.freezed.dart';

enum SshRowOperation { test, reconnect, delete }

@Freezed(toStringOverride: false)
abstract class SshRowAction with _$SshRowAction {
  const factory SshRowAction({
    required SshRowOperation kind,
    required SettingsAction action,
  }) = _SshRowAction;
}

@Freezed(toStringOverride: false)
abstract class SshPasswordChallenge with _$SshPasswordChallenge {
  const factory SshPasswordChallenge({
    required String alias,
    required int intent,
    required StudioFailure error,
  }) = _SshPasswordChallenge;
}

@Freezed(toStringOverride: false)
abstract class SshViewState with _$SshViewState {
  const factory SshViewState({
    required RemoteState source,
    @Default({}) Map<String, SshRowAction> actions,
    @Default(0) int latestIntent,
    SettingsAction? reloadAction,
    SshEditorKey? editor,
    String? directoryAlias,
    int? directoryDialogId,
    String? passwordAlias,
    int? passwordDialogId,
    int? passwordScopeId,
    String? deleteConfirmationAlias,
  }) = _SshViewState;
}
