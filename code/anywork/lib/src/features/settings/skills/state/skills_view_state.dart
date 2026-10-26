import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/skills.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'skills_view_state.freezed.dart';

enum SkillsReadField { catalog, warnings, sourceStatus, activeNames }

enum SkillsPreferencesReadField { configuration, sourceStatus }

@Freezed(toStringOverride: false)
abstract class SkillsPreferencesState with _$SkillsPreferencesState {
  const factory SkillsPreferencesState({
    required ConfigurationState source,
    @Default('') String queryRaw,
    @Default({}) Map<SkillsPreferencesReadField, StudioFailure> readIssues,
    @Default({}) Set<SkillsPreferencesReadField> reading,
    SettingsAction? disabledAction,
  }) = _SkillsPreferencesState;
}

@Freezed(toStringOverride: false)
abstract class ActiveSkillNames with _$ActiveSkillNames {
  const factory ActiveSkillNames({
    required String threadId,
    required ThreadFacetStamp origin,
    required ThreadConfigurationReadRef reference,
    required List<String> names,
  }) = _ActiveSkillNames;
}

@Freezed(toStringOverride: false)
abstract class SkillsViewState with _$SkillsViewState {
  const factory SkillsViewState({
    required String projectId,
    required SkillsState source,
    @Default('') String searchQuery,
    @Default(0) int searchGeneration,
    SkillSearchResult? search,
    @Default(false) bool searching,
    StudioFailure? searchError,
    ActiveSkillNames? activeNames,
    @Default({}) Map<SkillsReadField, StudioFailure> readIssues,
    @Default({}) Set<SkillsReadField> reading,
    @Default([]) List<CloseReport> cleanupReports,
    @Default([]) List<StudioFailure> cleanupErrors,
    SettingsAction? discoverAction,
  }) = _SkillsViewState;
}

/// A name from configuration/active metadata is not a fabricated catalog entry.
@Freezed(toStringOverride: false)
sealed class SettingsSkillRow with _$SettingsSkillRow {
  const SettingsSkillRow._();
  const factory SettingsSkillRow.catalog({required SkillSummary summary}) =
      CatalogSettingsSkillRow;
  const factory SettingsSkillRow.nameOnly({required String value}) =
      NameOnlySettingsSkillRow;
  String get name => switch (this) {
    CatalogSettingsSkillRow(:final summary) => summary.name,
    NameOnlySettingsSkillRow(:final value) => value,
  };
}
