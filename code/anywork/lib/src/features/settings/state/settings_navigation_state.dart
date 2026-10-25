import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:anywork_client/resources.dart';

part 'settings_navigation_state.freezed.dart';

/// Presentation order also defines the established settings navigation indices.
enum SettingsTab {
  accounts,
  instructions,
  modes,
  skills,
  agents,
  mcp,
  lsp,
  ssh,
  statistics,
  security,
  general,
  bots,
}

@freezed
abstract class SettingsNavigationRequest with _$SettingsNavigationRequest {
  const factory SettingsNavigationRequest({
    required int generation,
    required SettingsTab from,
    required SettingsTab? destination,
  }) = _SettingsNavigationRequest;
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
