import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';

part 'agent_profiles_state.freezed.dart';

enum AgentProfilesReadField { profiles, configuration, models, recovery,
  profilesSource, configurationSource, modelSource, recoverySource }
enum AgentProfileAction { enabled, model, effort }

@Freezed(toStringOverride: false)
abstract class SettingsRoleRead with _$SettingsRoleRead {
  const factory SettingsRoleRead({required String roleId, required ConfigurationRoleReadTarget? target,
    required int intent, @Default(false) bool pending, RoleRouteRead? value, StudioFailure? error}) = _SettingsRoleRead;
}

@freezed
abstract class SettingsRoleRoute with _$SettingsRoleRoute {
  const factory SettingsRoleRoute({required ConfigurationRoleReadTarget target, required String accountId, required String modelId,
    required String? effort, required ModelDescriptor? descriptor, required bool configured}) = _SettingsRoleRoute;
}

@freezed
abstract class AgentProfilesViewState with _$AgentProfilesViewState {
  const factory AgentProfilesViewState({
    required ProfilesState source,
    required ConfigurationState configurationSource,
    required ModelsState modelSource,
    required RecoveryState recoverySource,
    @Default('') String query,
    @Default({}) Map<String, String> systemSearchLabels,
    @Default([]) List<String> matchingProfileIds,
    @Default({}) Map<String, SettingsRoleRead> roleReads,
    @Default({}) Map<String, SettingsRoleRoute> routes,
    @Default({}) Map<(String, AgentProfileAction), SettingsAction> actions,
    @Default({}) Map<(WorktreeOwner, String, int), SettingsAction> cleanupActions,
    SettingsAction? retryRecoveryAction,
    ProfileEditorKey? editor,
    @Default(0) int latestIntent,
    @Default({}) Map<AgentProfilesReadField, StudioFailure> readIssues,
    @Default({}) Set<AgentProfilesReadField> reading,
  }) = _AgentProfilesViewState;
}
