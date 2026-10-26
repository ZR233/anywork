import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';

import '../../../rust/api/studio/types/response.dart' as response;
import '../../../rust/api/studio/types/settings.dart' as native;
import '../products/configuration/scalar_values.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'command_model_converters.dart';

ThreadSettingsSnapshot commandSettingsFromBridge(
  response.BridgeSettingsStateResponse value,
) => ThreadSettingsSnapshot(
  config: ThreadSettingsConfigSnapshot(
    revision: exactU64(value.config.revision, 'command settings revision'),
    updatedAt: exactI64(
      BigInt.from(value.config.updatedAt),
      'command settings updated Unix seconds',
    ),
    settings: commandSettingsValueFromBridge(value.config.settings),
  ),
  catalog: ThreadSettingsCatalogSnapshot(
    revision: exactU64(value.catalog.revision, 'command catalog revision'),
    updatedAt: exactI64(
      BigInt.from(value.catalog.updatedAt),
      'command catalog updated Unix seconds',
    ),
    accounts: [
      for (final account in value.catalog.accounts)
        ThreadSettingsCatalogAccount(
          accountId: account.accountId,
          effectiveModels: account.effectiveModels
              .map(commandModelFromBridge)
              .toList(growable: false),
          modelCatalog: commandCatalogStatusFromBridge(account.modelCatalog),
        ),
    ],
  ),
);

ThreadSettingsValue commandSettingsValueFromBridge(
  native.BridgeStudioSettingsDto value,
) => ThreadSettingsValue(
  defaultAccountId: value.defaultAccountId,
  accounts: value.accounts
      .map(commandSettingsAccountFromBridge)
      .toList(growable: false),
  modeModelRoutes: [
    for (final route in value.modeModelRoutes)
      ModeModelRoute(
        modeId: route.modeId,
        accountId: route.accountId,
        modelId: route.modelId,
        effort: route.effort,
      ),
  ],
  roles: [
    for (final role in value.roles)
      RoleModelRoute(
        key: role.key,
        accountId: role.accountId,
        modelId: role.modelId,
        effort: role.effort,
      ),
  ],
  permissionMode: value.permissionMode,
  instructions: InstructionsSettings(
    baseOverride: value.instructions.baseOverride,
    developer: value.instructions.developer,
    user: value.instructions.user,
    projectDocMaxBytes: exactU64(
      value.instructions.projectDocMaxBytes,
      'command project documentation bytes',
    ),
    projectDocFallbackFilenames: value.instructions.projectDocFallbackFilenames,
  ),
  skills: SkillsSettings(
    enabled: value.skills.enabled,
    autoLearn: value.skills.autoLearn,
    systemEnabled: value.skills.systemEnabled,
    projectDir: value.skills.projectDir,
    userDir: value.skills.userDir,
    externalDirs: value.skills.externalDirs,
    disabled: value.skills.disabled,
    autoLearnMinToolCalls: value.skills.autoLearnMinToolCalls,
  ),
  mcpServers: [
    for (final server in value.mcpServers)
      McpConfiguration(
        id: server.id,
        transport: server.transport,
        endpoint: server.endpoint,
        configuration: configurationMcpStateFromBridge(server.configuration),
        sourceKind: server.sourceKind,
        mutationPolicy: server.mutationPolicy,
      ),
  ],
  general: GeneralSettings(
    followActiveTurn: value.general.followActiveTurn,
    compactTimeline: value.general.compactTimeline,
    sidebarWidth: value.general.sidebarWidth,
    pinnedThreadIds: value.general.pinnedThreadIds,
    pinnedProjectIds: value.general.pinnedProjectIds,
  ),
  delegation: configurationDelegationFromBridge(value.delegation),
  webSearch: ThreadWebSearchSettings(
    configuration: WebSearchConfiguration(
      configuredMode: value.webSearch.configuredMode,
      contextSize: value.webSearch.contextSize,
      allowedDomains: value.webSearch.allowedDomains,
      country: value.webSearch.country,
      region: value.webSearch.region,
      city: value.webSearch.city,
      timezone: value.webSearch.timezone,
    ),
    effective: EffectiveWebSearch(
      effectiveMode: value.webSearch.effectiveMode,
      availability: value.webSearch.availability,
      accountId: value.webSearch.accountId,
      modelId: value.webSearch.modelId,
    ),
  ),
  deepseekWebSearch: ThreadDeepSeekSearchSettings(
    configuration: DeepSeekSearchConfiguration(
      configuredEnabled: value.deepseekWebSearch.configuredEnabled,
      configuredFetchEnabled: value.deepseekWebSearch.configuredFetchEnabled,
    ),
    effective: EffectiveDeepSeekSearch(
      effectiveEnabled: value.deepseekWebSearch.effectiveEnabled,
      effectiveFetchEnabled: value.deepseekWebSearch.effectiveFetchEnabled,
      availability: value.deepseekWebSearch.availability,
      accountId: value.deepseekWebSearch.accountId,
    ),
  ),
);

ThreadSettingsAccount commandSettingsAccountFromBridge(
  native.BridgeAccountSettingsDto value,
) => ThreadSettingsAccount(
  configuration: AccountConfiguration(
    billingKind: configurationBillingFromBridge(value.billingKind),
    billingKindOverride: value.billingKindOverride == null
        ? null
        : configurationBillingFromBridge(value.billingKindOverride!),
    disabledModels: value.disabledModels,
    accountId: value.accountId,
    templateId: value.templateId,
    protocol: value.protocol,
    name: value.name,
    baseUrl: value.baseUrl,
    hasBearerToken: value.hasBearerToken,
    bearerTokenEnv: value.bearerTokenEnv,
    usageQueryRevision: exactU64(
      value.usageQueryRevision,
      'command account usage revision',
    ),
    customModels: [
      for (final model in value.customModels)
        CustomModelConfiguration(
          inputCapabilities: model.inputCapabilities
              .map(commandModelInputFromBridge)
              .toList(growable: false),
          contextWindow: nullableU64(
            model.contextWindow,
            'command custom model context window',
          ),
          maxOutputTokens: nullableU64(
            model.maxOutputTokens,
            'command custom model maximum output tokens',
          ),
          modelId: model.modelId,
          displayName: model.displayName,
          reasoningEfforts: model.reasoningEfforts,
          baseInstructions: model.baseInstructions,
          wireApi: model.wireApi,
          supportedConnectionModes: model.supportedConnectionModes,
          defaultConnectionMode: model.defaultConnectionMode,
        ),
    ],
    modelConnectionModes: [
      for (final mode in value.modelConnectionModes)
        ModelConnection(
          modelId: mode.modelId,
          connectionMode: mode.connectionMode,
        ),
    ],
    modelAutoCompactLimits: [
      for (final limit in value.modelAutoCompactLimits)
        ModelAutoCompact(
          modelId: limit.modelId,
          overrideLimit: nullableU64(
            limit.overrideLimit,
            'command model compact override',
          ),
        ),
    ],
    catalogId: value.catalogId,
  ),
  credentialRequired: value.credentialRequired,
  capabilitySource: value.capabilitySource,
  hostedWebSearch: value.hostedWebSearch,
  hostedWebSearchDialect: value.hostedWebSearchDialect,
  standaloneWebSearch: value.standaloneWebSearch,
  promptCacheDialect: value.promptCacheDialect,
  responsesProgrammaticToolCalling: value.responsesProgrammaticToolCalling,
  defaultModelId: value.defaultModelId,
);
