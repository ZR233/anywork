import 'package:anywork_client/configuration_ports.dart';

import '../../../../rust/api/studio/products/read/configuration_values.dart'
    as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import 'scalar_values.dart';

ConfigurationReadHeader configurationReadHeaderFromBridge(
  native.BridgeConfigurationReadHeader value,
) => ConfigurationReadHeader(
  defaultAccountId: nullableReadText(value.defaultAccountId),
  accounts: typedListFromBridge(value.accounts),
  modeModelRoutes: typedListFromBridge(value.modeModelRoutes),
  roles: typedListFromBridge(value.roles),
  permissionMode: readTextFromBridge(value.permissionMode),
  instructions: configurationInstructionsFromBridge(value.instructions),
  skills: configurationSkillsFromBridge(value.skills),
  mcpServers: typedListFromBridge(value.mcpServers),
  general: configurationGeneralFromBridge(value.general),
  delegation: configurationDelegationFromBridge(value.delegation),
  webSearch: configurationWebSearchFromBridge(value.webSearch),
  deepseekWebSearch: DeepSeekSearchConfigurationRead(
    configuredEnabled: value.deepseekWebSearch.configuredEnabled,
    configuredFetchEnabled: value.deepseekWebSearch.configuredFetchEnabled,
  ),
);

AccountConfigurationRead accountConfigurationFromBridge(
  native.BridgeAccountConfigurationRead value,
) => AccountConfigurationRead(
  pricingEnabled: value.pricingEnabled,
  billingKind: configurationBillingFromBridge(value.billingKind),
  billingKindOverride: value.billingKindOverride == null
      ? null
      : configurationBillingFromBridge(value.billingKindOverride!),
  disabledModels: typedListFromBridge(value.disabledModels),
  accountId: readTextFromBridge(value.accountId),
  templateId: nullableReadText(value.templateId),
  protocol: readTextFromBridge(value.protocol),
  name: readTextFromBridge(value.name),
  baseUrl: readTextFromBridge(value.baseUrl),
  hasBearerToken: value.hasBearerToken,
  bearerTokenEnv: nullableReadText(value.bearerTokenEnv),
  usageQueryRevision: exactU64(
    value.usageQueryRevision,
    'account usage query revision',
  ),
  customModels: typedListFromBridge(value.customModels),
  modelConnectionModes: typedListFromBridge(value.modelConnectionModes),
  modelAutoCompactLimits: typedListFromBridge(value.modelAutoCompactLimits),
  catalogId: nullableReadText(value.catalogId),
);

CustomModelConfigurationRead customModelConfigurationFromBridge(
  native.BridgeCustomModelConfigurationRead value,
) => CustomModelConfigurationRead(
  inputCapabilities: typedListFromBridge(value.inputCapabilities),
  contextWindow: nullableU64(
    value.contextWindow,
    'custom model context window',
  ),
  maxOutputTokens: nullableU64(
    value.maxOutputTokens,
    'custom model max output tokens',
  ),
  modelId: readTextFromBridge(value.modelId),
  displayName: readTextFromBridge(value.displayName),
  reasoningEfforts: typedListFromBridge(value.reasoningEfforts),
  baseInstructions: readTextFromBridge(value.baseInstructions),
  wireApi: readTextFromBridge(value.wireApi),
  supportedConnectionModes: typedListFromBridge(value.supportedConnectionModes),
  defaultConnectionMode: readTextFromBridge(value.defaultConnectionMode),
);

ModelConnectionRead configurationConnectionFromBridge(
  native.BridgeModelConnectionRead value,
) => ModelConnectionRead(
  modelId: readTextFromBridge(value.modelId),
  connectionMode: readTextFromBridge(value.connectionMode),
);
ModelAutoCompactRead configurationAutoCompactFromBridge(
  native.BridgeModelAutoCompactRead value,
) => ModelAutoCompactRead(
  modelId: readTextFromBridge(value.modelId),
  overrideLimit: nullableU64(
    value.overrideLimit,
    'model auto compact override',
  ),
);
ModeModelRouteRead configurationModeRouteFromBridge(
  native.BridgeModeModelRouteRead value,
) => ModeModelRouteRead(
  modeId: readTextFromBridge(value.modeId),
  accountId: readTextFromBridge(value.accountId),
  modelId: readTextFromBridge(value.modelId),
  effort: readTextFromBridge(value.effort),
);
RoleModelRouteRead configurationRoleReadFromBridge(
  native.BridgeRoleModelRouteRead value,
) => RoleModelRouteRead(
  key: readTextFromBridge(value.key),
  accountId: readTextFromBridge(value.accountId),
  modelId: readTextFromBridge(value.modelId),
  effort: readTextFromBridge(value.effort),
);
InstructionsSettingsRead configurationInstructionsFromBridge(
  native.BridgeInstructionsSettingsRead value,
) => InstructionsSettingsRead(
  baseOverride: readTextFromBridge(value.baseOverride),
  developer: readTextFromBridge(value.developer),
  user: readTextFromBridge(value.user),
  projectDocMaxBytes: exactU64(
    value.projectDocMaxBytes,
    'project document max bytes',
  ),
  projectDocFallbackFilenames: typedListFromBridge(
    value.projectDocFallbackFilenames,
  ),
);
SkillsSettingsRead configurationSkillsFromBridge(
  native.BridgeSkillsSettingsRead value,
) => SkillsSettingsRead(
  enabled: value.enabled,
  autoLearn: value.autoLearn,
  systemEnabled: value.systemEnabled,
  projectDir: readTextFromBridge(value.projectDir),
  userDir: readTextFromBridge(value.userDir),
  externalDirs: typedListFromBridge(value.externalDirs),
  disabled: typedListFromBridge(value.disabled),
  autoLearnMinToolCalls: value.autoLearnMinToolCalls,
);
McpConfigurationRead configurationMcpFromBridge(
  native.BridgeMcpConfigurationRead value,
) => McpConfigurationRead(
  id: readTextFromBridge(value.id),
  transport: readTextFromBridge(value.transport),
  endpoint: readTextFromBridge(value.endpoint),
  configuration: configurationMcpStateFromBridge(value.configuration),
  sourceKind: readTextFromBridge(value.sourceKind),
  mutationPolicy: readTextFromBridge(value.mutationPolicy),
);
GeneralSettingsRead configurationGeneralFromBridge(
  native.BridgeGeneralSettingsRead value,
) => GeneralSettingsRead(
  followActiveTurn: value.followActiveTurn,
  compactTimeline: value.compactTimeline,
  sidebarWidth: value.sidebarWidth,
  pinnedThreadIds: typedListFromBridge(value.pinnedThreadIds),
  pinnedProjectIds: typedListFromBridge(value.pinnedProjectIds),
);
WebSearchConfigurationRead configurationWebSearchFromBridge(
  native.BridgeWebSearchConfigurationRead value,
) => WebSearchConfigurationRead(
  configuredMode: readTextFromBridge(value.configuredMode),
  contextSize: nullableReadText(value.contextSize),
  allowedDomains: typedListFromBridge(value.allowedDomains),
  country: nullableReadText(value.country),
  region: nullableReadText(value.region),
  city: nullableReadText(value.city),
  timezone: nullableReadText(value.timezone),
);
