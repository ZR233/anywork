import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../../../models.dart' show BillingKind;
import '../../acp/domain/acp_values.dart';
import '../domain/configuration_values.dart';

part 'configuration_reads.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ConfigurationReadHeader with _$ConfigurationReadHeader {
  const factory ConfigurationReadHeader({
    required ReadText? defaultAccountId,
    required TypedListRef accounts,
    required TypedListRef acpAccounts,
    required TypedListRef modeModelRoutes,
    required TypedListRef roles,
    required ReadText permissionMode,
    required InstructionsSettingsRead instructions,
    required SkillsSettingsRead skills,
    required TypedListRef mcpServers,
    required GeneralSettingsRead general,
    required DelegationSettings delegation,
    required WebSearchConfigurationRead webSearch,
    required DeepSeekSearchConfigurationRead deepseekWebSearch,
  }) = _ConfigurationReadHeader;
}

/// 配置材料里的一行 ACP 接入。
///
/// 稳定 ID 与名称是可分块读取的文本，[provider] 是类型化供应商，
/// [connectionRevision] 是该设置版本捕获的 ACP 连接代次。SDK 不重新推导连接代次：
/// 它不是 Settings revision、不是列表位置，也不是认证观察的最新状态。
@Freezed(toStringOverride: false)
abstract class AcpAccountConfigurationRead with _$AcpAccountConfigurationRead {
  const factory AcpAccountConfigurationRead({
    required ReadText accountId,
    required ReadText name,
    required AcpProvider provider,
    required int connectionRevision,
  }) = _AcpAccountConfigurationRead;
}

@Freezed(toStringOverride: false)
abstract class AccountConfigurationRead with _$AccountConfigurationRead {
  const factory AccountConfigurationRead({
    required BillingKind billingKind,
    required BillingKind? billingKindOverride,
    required TypedListRef disabledModels,
    required ReadText accountId,
    required ReadText? templateId,
    required ReadText protocol,
    required ReadText name,
    required ReadText baseUrl,
    required bool hasBearerToken,
    required ReadText? bearerTokenEnv,
    required int usageQueryRevision,
    required TypedListRef customModels,
    required TypedListRef modelConnectionModes,
    required TypedListRef modelAutoCompactLimits,
    required ReadText? catalogId,
  }) = _AccountConfigurationRead;
}

@Freezed(toStringOverride: false)
abstract class CustomModelConfigurationRead
    with _$CustomModelConfigurationRead {
  const factory CustomModelConfigurationRead({
    required TypedListRef inputCapabilities,
    required int? contextWindow,
    required int? maxOutputTokens,
    required ReadText modelId,
    required ReadText displayName,
    required TypedListRef reasoningEfforts,
    required ReadText baseInstructions,
    required ReadText wireApi,
    required TypedListRef supportedConnectionModes,
    required ReadText defaultConnectionMode,
  }) = _CustomModelConfigurationRead;
}

@Freezed(toStringOverride: false)
abstract class ModelConnectionRead with _$ModelConnectionRead {
  const factory ModelConnectionRead({
    required ReadText modelId,
    required ReadText connectionMode,
  }) = _ModelConnectionRead;
}

@Freezed(toStringOverride: false)
abstract class ModelAutoCompactRead with _$ModelAutoCompactRead {
  const factory ModelAutoCompactRead({
    required ReadText modelId,
    required int? overrideLimit,
  }) = _ModelAutoCompactRead;
}

@Freezed(toStringOverride: false)
abstract class ModeModelRouteRead with _$ModeModelRouteRead {
  const factory ModeModelRouteRead({
    required ReadText modeId,
    required ReadText accountId,
    required ReadText modelId,
    required ReadText effort,
  }) = _ModeModelRouteRead;
}

@Freezed(toStringOverride: false)
abstract class RoleModelRouteRead with _$RoleModelRouteRead {
  const factory RoleModelRouteRead({
    required ReadText key,
    required ReadText accountId,
    required ReadText modelId,
    required ReadText effort,
  }) = _RoleModelRouteRead;
}

@Freezed(toStringOverride: false)
abstract class InstructionsSettingsRead with _$InstructionsSettingsRead {
  const factory InstructionsSettingsRead({
    required ReadText baseOverride,
    required ReadText developer,
    required ReadText user,
    required int projectDocMaxBytes,
    required TypedListRef projectDocFallbackFilenames,
  }) = _InstructionsSettingsRead;
}

@Freezed(toStringOverride: false)
abstract class SkillsSettingsRead with _$SkillsSettingsRead {
  const factory SkillsSettingsRead({
    required bool enabled,
    required bool autoLearn,
    required bool systemEnabled,
    required ReadText projectDir,
    required ReadText userDir,
    required TypedListRef externalDirs,
    required TypedListRef disabled,
    required int autoLearnMinToolCalls,
  }) = _SkillsSettingsRead;
}

@Freezed(toStringOverride: false)
abstract class McpConfigurationRead with _$McpConfigurationRead {
  const factory McpConfigurationRead({
    required ReadText id,
    required ReadText transport,
    required ReadText endpoint,
    required McpConfigurationState configuration,
    required ReadText sourceKind,
    required ReadText mutationPolicy,
  }) = _McpConfigurationRead;
}

@freezed
abstract class GeneralSettingsRead with _$GeneralSettingsRead {
  const factory GeneralSettingsRead({
    required bool followActiveTurn,
    required bool compactTimeline,
    required int? sidebarWidth,
    required TypedListRef pinnedThreadIds,
    required TypedListRef pinnedProjectIds,
  }) = _GeneralSettingsRead;
}

@Freezed(toStringOverride: false)
abstract class WebSearchConfigurationRead with _$WebSearchConfigurationRead {
  const factory WebSearchConfigurationRead({
    required ReadText configuredMode,
    required ReadText? contextSize,
    required TypedListRef allowedDomains,
    required ReadText? country,
    required ReadText? region,
    required ReadText? city,
    required ReadText? timezone,
  }) = _WebSearchConfigurationRead;
}

@freezed
abstract class DeepSeekSearchConfigurationRead
    with _$DeepSeekSearchConfigurationRead {
  const factory DeepSeekSearchConfigurationRead({
    required bool configuredEnabled,
    required bool configuredFetchEnabled,
  }) = _DeepSeekSearchConfigurationRead;
}
