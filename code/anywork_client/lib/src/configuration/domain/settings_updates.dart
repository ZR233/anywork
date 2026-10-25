import 'package:freezed_annotation/freezed_annotation.dart';

import '../../modes/domain/delegation_values.dart';

part 'settings_updates.freezed.dart';

/// Each variant changes exactly one native field. Sibling fields never come
/// from a UI snapshot. Raw authoring strings are not diagnostic payloads.
@Freezed(toStringOverride: false)
sealed class SettingsFieldUpdate with _$SettingsFieldUpdate {
  const SettingsFieldUpdate._();

  const factory SettingsFieldUpdate.delegationMode({
    required DelegationMode value,
  }) = DelegationModeUpdate;
  const factory SettingsFieldUpdate.delegationPreference({
    required DelegationPreference value,
  }) = DelegationPreferenceUpdate;
  const factory SettingsFieldUpdate.instructionBaseOverride({
    required String value,
  }) = InstructionBaseOverride;
  const factory SettingsFieldUpdate.instructionDeveloper({
    required String value,
  }) = InstructionDeveloper;
  const factory SettingsFieldUpdate.instructionUser({required String value}) =
      InstructionUser;
  const factory SettingsFieldUpdate.projectDocMaxBytes({required int value}) =
      ProjectDocMaxBytes;
  factory SettingsFieldUpdate.projectDocFallbackFilenames({
    required List<String> value,
  }) = ProjectDocFallbackFilenames;
  const factory SettingsFieldUpdate.skillsEnabled({required bool value}) =
      SkillsEnabled;
  const factory SettingsFieldUpdate.skillsAutoLearn({required bool value}) =
      SkillsAutoLearn;
  const factory SettingsFieldUpdate.skillsSystemEnabled({required bool value}) =
      SkillsSystemEnabled;
  const factory SettingsFieldUpdate.skillsProjectDir({required String value}) =
      SkillsProjectDir;
  const factory SettingsFieldUpdate.skillsUserDir({required String value}) =
      SkillsUserDir;
  factory SettingsFieldUpdate.skillsExternalDirs({
    required List<String> value,
  }) = SkillsExternalDirs;
  factory SettingsFieldUpdate.skillsDisabled({required List<String> value}) =
      SkillsDisabled;
  const factory SettingsFieldUpdate.skillsAutoLearnMinToolCalls({
    required int value,
  }) = SkillsAutoLearnMinToolCalls;
  const factory SettingsFieldUpdate.mcpServerEnabled({
    required String id,
    required bool value,
  }) = McpServerEnabled;
  const factory SettingsFieldUpdate.mcpServerTransport({
    required String id,
    required String transport,
  }) = McpServerTransport;
  const factory SettingsFieldUpdate.mcpServerEndpoint({
    required String id,
    required String endpoint,
  }) = McpServerEndpoint;
  const factory SettingsFieldUpdate.generalFollowActiveTurn({
    required bool value,
  }) = GeneralFollowActiveTurn;
  const factory SettingsFieldUpdate.generalCompactTimeline({
    required bool value,
  }) = GeneralCompactTimeline;
  const factory SettingsFieldUpdate.generalSidebarWidth({required int? value}) =
      GeneralSidebarWidth;
  factory SettingsFieldUpdate.generalPinnedThreadIds({
    required List<String> value,
  }) = GeneralPinnedThreadIds;
  factory SettingsFieldUpdate.generalPinnedProjectIds({
    required List<String> value,
  }) = GeneralPinnedProjectIds;
  const factory SettingsFieldUpdate.webSearchMode({required String value}) =
      WebSearchMode;
  const factory SettingsFieldUpdate.webSearchContextSize({
    required String? value,
  }) = WebSearchContextSize;
  factory SettingsFieldUpdate.webSearchAllowedDomains({
    required List<String> value,
  }) = WebSearchAllowedDomains;
  const factory SettingsFieldUpdate.webSearchCountry({required String? value}) =
      WebSearchCountry;
  const factory SettingsFieldUpdate.webSearchRegion({required String? value}) =
      WebSearchRegion;
  const factory SettingsFieldUpdate.webSearchCity({required String? value}) =
      WebSearchCity;
  const factory SettingsFieldUpdate.webSearchTimezone({
    required String? value,
  }) = WebSearchTimezone;
  const factory SettingsFieldUpdate.deepSeekWebSearchEnabled({
    required bool value,
  }) = DeepSeekWebSearchEnabled;
  const factory SettingsFieldUpdate.deepSeekWebFetchEnabled({
    required bool value,
  }) = DeepSeekWebFetchEnabled;
  const factory SettingsFieldUpdate.modeModel({
    required String modeId,
    required String accountId,
    required String modelId,
  }) = ModeModel;
  const factory SettingsFieldUpdate.modeReasoningEffort({
    required String modeId,
    required String? effort,
  }) = ModeReasoningEffort;
  const factory SettingsFieldUpdate.roleModel({
    required String role,
    required String accountId,
    required String modelId,
  }) = RoleModel;
  const factory SettingsFieldUpdate.roleReasoningEffort({
    required String role,
    required String? effort,
  }) = RoleReasoningEffort;
}

@Freezed(toStringOverride: false)
final class ProjectDocFallbackFilenames extends SettingsFieldUpdate
    with _$ProjectDocFallbackFilenames {
  ProjectDocFallbackFilenames({required List<String> value})
    : value = List.unmodifiable(value),
      super._();
  final List<String> value;
}

@Freezed(toStringOverride: false)
final class SkillsExternalDirs extends SettingsFieldUpdate
    with _$SkillsExternalDirs {
  SkillsExternalDirs({required List<String> value})
    : value = List.unmodifiable(value),
      super._();
  final List<String> value;
}

@Freezed(toStringOverride: false)
final class SkillsDisabled extends SettingsFieldUpdate with _$SkillsDisabled {
  SkillsDisabled({required List<String> value})
    : value = List.unmodifiable(value),
      super._();
  final List<String> value;
}

@Freezed(toStringOverride: false)
final class GeneralPinnedThreadIds extends SettingsFieldUpdate
    with _$GeneralPinnedThreadIds {
  GeneralPinnedThreadIds({required List<String> value})
    : value = List.unmodifiable(value),
      super._();
  final List<String> value;
}

@Freezed(toStringOverride: false)
final class GeneralPinnedProjectIds extends SettingsFieldUpdate
    with _$GeneralPinnedProjectIds {
  GeneralPinnedProjectIds({required List<String> value})
    : value = List.unmodifiable(value),
      super._();
  final List<String> value;
}

@Freezed(toStringOverride: false)
final class WebSearchAllowedDomains extends SettingsFieldUpdate
    with _$WebSearchAllowedDomains {
  WebSearchAllowedDomains({required List<String> value})
    : value = List.unmodifiable(value),
      super._();
  final List<String> value;
}
