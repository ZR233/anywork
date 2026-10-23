import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'general_settings_state.freezed.dart';

enum GeneralSettingAction { followActiveTurn, compactTimeline, deepSeekSearch, deepSeekFetch }

enum WebSearchField { mode, contextSize, domains, country, region, city, timezone }
enum GeneralReadField { general, webSearch, deepSeek, configurationSource, webPolicy, deepSeekPolicy, modelSource }

@Freezed(toStringOverride: false)
abstract class WebSearchDraft with _$WebSearchDraft {
  const factory WebSearchDraft({
    required String mode,
    required String? contextSize,
    required String domains,
    required String country,
    required String region,
    required String city,
    required String timezone,
    @Default({}) Set<WebSearchField> dirtyFields,
    @Default({}) Map<WebSearchField, int> fieldRevisions,
    @Default(0) int revision,
  }) = _WebSearchDraft;
}

@Freezed(toStringOverride: false)
abstract class GeneralSettingsViewState with _$GeneralSettingsViewState {
  const factory GeneralSettingsViewState({
    required ConfigurationState source,
    required ModelsState modelSource,
    required GeneralSettings? canonical,
    required WebSearchConfiguration? configuredWebSearch,
    required DeepSeekSearchConfiguration? configuredDeepSeek,
    required WebSearchDraft? webSearch,
    EffectiveWebSearch? effectiveWebSearch,
    EffectiveDeepSeekSearch? effectiveDeepSeek,
    @Default({}) Map<GeneralSettingAction, SettingsAction> actions,
    @Default([]) List<SettingsAction> webSaveActions,
    @Default({}) Map<WebSearchField, SettingsAction> webFieldActions,
    SettingsBatchResult? webSaveResult,
    @Default(false) bool webSaving,
    @Default(0) int webSaveIntent,
    @Default(0) int latestIntent,
    @Default([]) List<StudioFailure> readErrors,
    @Default({}) Map<GeneralReadField, StudioFailure> readIssues,
    @Default(false) bool readPending,
  }) = _GeneralSettingsViewState;
}
