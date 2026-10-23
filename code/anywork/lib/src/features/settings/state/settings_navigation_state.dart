import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:anywork_client/resources.dart';

part 'settings_navigation_state.freezed.dart';

enum SettingsTab {
  accounts,
  agents,
  modes,
  instructions,
  skills,
  mcp,
  lsp,
  ssh,
  statistics,
  security,
  general,
}

@freezed
abstract class SettingsNavigationRequest with _$SettingsNavigationRequest {
  const factory SettingsNavigationRequest({required int generation, required SettingsTab from,
    required SettingsTab? destination}) = _SettingsNavigationRequest;
}

@freezed
abstract class SettingsNavigationState with _$SettingsNavigationState {
  const factory SettingsNavigationState({
    @Default(SettingsTab.accounts) SettingsTab tab,
    @Default(false) bool visible,
    @Default({}) Set<SettingsTab> visited,
    @Default(0) int generation,
    @Default(false) bool leaving,
    SettingsNavigationRequest? request,
    StudioFailure? error,
  }) = _SettingsNavigationState;
}
