import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';

part 'profile_editor_state.freezed.dart';

enum ProfileField {
  id,
  displayName,
  description,
  whenToUse,
  instructions,
  route,
}

enum ProfileValidation { required, invalidId }

enum ProfileRouteSuggestionKind { newProfile, selectedModel }

@Freezed(toStringOverride: false)
abstract class ProfileRouteSuggestion with _$ProfileRouteSuggestion {
  const factory ProfileRouteSuggestion({
    required ProfileEditorKey editor,
    required int intent,
    required ProfileRouteSuggestionKind kind,
    required ModelCatalogReadTarget? catalog,
    required AccountModelKey? model,
    @Default(false) bool pending,
    StudioFailure? error,
  }) = _ProfileRouteSuggestion;
}

/// A targeted Repository read for a selection outside the loaded account page.
/// Its original catalog remains attached; this is not another catalog mirror.
@Freezed(toStringOverride: false)
abstract class ProfileRouteModel with _$ProfileRouteModel {
  const factory ProfileRouteModel({
    required AccountModelKey model,
    required ModelCatalogReadTarget catalog,
    required ModelDescriptor descriptor,
  }) = _ProfileRouteModel;
}

@Freezed(toStringOverride: false)
abstract class ProfileEditorViewState with _$ProfileEditorViewState {
  const factory ProfileEditorViewState({
    required ProfileEditorKey key,
    required ProfilesState source,
    required ModelsState modelSource,
    required ConfigurationState configurationSource,
    AgentProfileSnapshot? canonical,
    required String profileId,
    required String displayName,
    required String description,
    required String whenToUse,
    required String instructions,
    required String accountId,
    required String modelId,
    String? effort,
    required bool enabled,
    required AgentWorkspaceMode workspaceMode,
    @Default([]) List<AccountCatalogEntry> models,
    @Default(0) int revision,
    @Default(false) bool dirty,
    @Default(false) bool loadingModels,
    ProfileRouteSuggestion? routeSuggestion,
    ProfileRouteModel? routeModel,
    StudioFailure? routeModelError,
    @Default({}) Map<ProfileField, ProfileValidation> validation,
    SettingsAction? saveAction,
    StudioFailure? sourceError,
  }) = _ProfileEditorViewState;
}
