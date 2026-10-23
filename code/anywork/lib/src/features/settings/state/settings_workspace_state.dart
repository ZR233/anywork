import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_workspace_state.freezed.dart';

/// Read-only application context. WorkspaceRepository remains the sole
/// selection writer; the local issue describes only this UI observation.
@Freezed(toStringOverride: false)
abstract class SettingsWorkspaceState with _$SettingsWorkspaceState {
  const SettingsWorkspaceState._();
  const factory SettingsWorkspaceState({required WorkspaceState source,
    required bool observing, StudioFailure? observationError}) = _SettingsWorkspaceState;
  String? get projectId => source.selection.projectId;
}
