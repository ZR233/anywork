import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../models.dart' show ModelInputCapability;

part 'configuration_values.freezed.dart';

enum PermissionMode { requestApproval, autoReview, fullAccess }
enum McpConfigurationState { enabled, disabled, missingCredential }

@freezed
final class ConfigurationValue with _$ConfigurationValue {
  ConfigurationValue({
    required this.defaultAccountId,
    required List<AccountConfiguration> accounts,
    required List<ModeModelRoute> modeModelRoutes,
    required List<RoleModelRoute> roles,
    required this.permissionMode,
    required this.instructions,
    required this.skills,
    required List<McpConfiguration> mcpServers,
    required this.general,
    required this.webSearch,
    required this.deepseekWebSearch,
  }) : accounts = List.unmodifiable(accounts), modeModelRoutes = List.unmodifiable(modeModelRoutes), roles = List.unmodifiable(roles), mcpServers = List.unmodifiable(mcpServers);

  final String? defaultAccountId;
  final List<AccountConfiguration> accounts;
  final List<ModeModelRoute> modeModelRoutes;
  final List<RoleModelRoute> roles;
  final String permissionMode;
  final InstructionsSettings instructions;
  final SkillsSettings skills;
  final List<McpConfiguration> mcpServers;
  final GeneralSettings general;
  final WebSearchConfiguration webSearch;
  final DeepSeekSearchConfiguration deepseekWebSearch;
}

/// Credential existence is observable; the credential itself is never readable.
@freezed
final class AccountConfiguration with _$AccountConfiguration {
  AccountConfiguration({
    required this.pricingEnabled,
    required this.accountId,
    required this.templateId,
    required this.protocol,
    required this.name,
    required this.baseUrl,
    required this.hasBearerToken,
    required this.usageQueryRevision,
    required List<CustomModelConfiguration> customModels,
    required List<ModelConnection> modelConnectionModes,
    required List<ModelAutoCompact> modelAutoCompactLimits,
    required this.catalogId,
  }) : customModels = List.unmodifiable(customModels), modelConnectionModes = List.unmodifiable(modelConnectionModes), modelAutoCompactLimits = List.unmodifiable(modelAutoCompactLimits);

  final bool pricingEnabled;
  final String accountId;
  final String? templateId;
  final String protocol;
  final String name;
  final String baseUrl;
  final bool hasBearerToken;
  final int usageQueryRevision;
  final List<CustomModelConfiguration> customModels;
  final List<ModelConnection> modelConnectionModes;
  final List<ModelAutoCompact> modelAutoCompactLimits;
  final String? catalogId;
}

@freezed
final class CustomModelConfiguration with _$CustomModelConfiguration {
  CustomModelConfiguration({
    required List<ModelInputCapability> inputCapabilities,
    required this.contextWindow,
    required this.maxOutputTokens,
    required this.modelId,
    required this.displayName,
    required List<String> reasoningEfforts,
    required this.baseInstructions,
    required this.wireApi,
    required List<String> supportedConnectionModes,
    required this.defaultConnectionMode,
  }) : inputCapabilities = List.unmodifiable(inputCapabilities), reasoningEfforts = List.unmodifiable(reasoningEfforts), supportedConnectionModes = List.unmodifiable(supportedConnectionModes);

  final List<ModelInputCapability> inputCapabilities;
  final int? contextWindow;
  final int? maxOutputTokens;
  final String modelId;
  final String displayName;
  final List<String> reasoningEfforts;
  final String baseInstructions;
  final String wireApi;
  final List<String> supportedConnectionModes;
  final String defaultConnectionMode;
}

@freezed
abstract class ModelConnection with _$ModelConnection {
  const factory ModelConnection({required String modelId, required String connectionMode}) = _ModelConnection;
}

@freezed
abstract class ModelAutoCompact with _$ModelAutoCompact {
  const factory ModelAutoCompact({required String modelId, required int? overrideLimit}) = _ModelAutoCompact;
}

@freezed
abstract class ModeModelRoute with _$ModeModelRoute {
  const factory ModeModelRoute({required String modeId, required String accountId, required String modelId, required String effort}) = _ModeModelRoute;
}

@freezed
abstract class RoleModelRoute with _$RoleModelRoute {
  const factory RoleModelRoute({required String key, required String accountId, required String modelId, required String effort}) = _RoleModelRoute;
}

@freezed
final class InstructionsSettings with _$InstructionsSettings {
  InstructionsSettings({required this.baseOverride, required this.developer, required this.user, required this.projectDocMaxBytes, required List<String> projectDocFallbackFilenames}) : projectDocFallbackFilenames = List.unmodifiable(projectDocFallbackFilenames);
  final String baseOverride;
  final String developer;
  final String user;
  final int projectDocMaxBytes;
  final List<String> projectDocFallbackFilenames;
}

@freezed
final class SkillsSettings with _$SkillsSettings {
  SkillsSettings({required this.enabled, required this.autoLearn, required this.systemEnabled, required this.projectDir, required this.userDir, required List<String> externalDirs, required List<String> disabled, required this.autoLearnMinToolCalls}) : externalDirs = List.unmodifiable(externalDirs), disabled = List.unmodifiable(disabled);
  final bool enabled;
  final bool autoLearn;
  final bool systemEnabled;
  final String projectDir;
  final String userDir;
  final List<String> externalDirs;
  final List<String> disabled;
  final int autoLearnMinToolCalls;
}

@freezed
abstract class McpConfiguration with _$McpConfiguration {
  const factory McpConfiguration({required String id, required String transport, required String endpoint, required McpConfigurationState configuration, required String sourceKind, required String mutationPolicy}) = _McpConfiguration;
}

@freezed
final class GeneralSettings with _$GeneralSettings {
  GeneralSettings({required this.followActiveTurn, required this.compactTimeline, required this.sidebarWidth, required List<String> pinnedThreadIds, required List<String> pinnedProjectIds}) : pinnedThreadIds = List.unmodifiable(pinnedThreadIds), pinnedProjectIds = List.unmodifiable(pinnedProjectIds);
  final bool followActiveTurn;
  final bool compactTimeline;
  final int? sidebarWidth;
  final List<String> pinnedThreadIds;
  final List<String> pinnedProjectIds;
}

@freezed
final class WebSearchConfiguration with _$WebSearchConfiguration {
  WebSearchConfiguration({required this.configuredMode, required this.contextSize, required List<String> allowedDomains, required this.country, required this.region, required this.city, required this.timezone}) : allowedDomains = List.unmodifiable(allowedDomains);
  final String configuredMode;
  final String? contextSize;
  final List<String> allowedDomains;
  final String? country;
  final String? region;
  final String? city;
  final String? timezone;
}

@freezed
abstract class DeepSeekSearchConfiguration with _$DeepSeekSearchConfiguration {
  const factory DeepSeekSearchConfiguration({required bool configuredEnabled, required bool configuredFetchEnabled}) = _DeepSeekSearchConfiguration;
}
