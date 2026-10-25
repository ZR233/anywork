import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/modes.dart'
    show DelegationMode, DelegationPreference;
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/configuration_commands.dart'
    as command;
import '../../../../rust/api/studio/products/read/profile_commands.dart'
    as profile;
import '../../../../rust/api/studio/types/delegation.dart' as delegation;
import '../../../../rust/api/studio/types/settings.dart' as native;
import '../../shared/exact_numbers.dart';
import 'scalar_values.dart';

String configurationOperationToBridge(OperationId value) {
  if (value.value.trim().isEmpty) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'Configuration operationId must not be blank',
      retryable: false,
      correlationId: 'adapter-configuration-operation-id',
    );
  }
  return value.value;
}

command.BridgeConfigurationCommandRequest configurationRequestToBridge(
  OperationId operation,
  int revision,
  command.BridgeConfigurationMutation mutation,
) => command.BridgeConfigurationCommandRequest(
  operationId: configurationOperationToBridge(operation),
  expectedRevision: nativeU64(revision, 'expected settings revision'),
  command: mutation,
);

native.AccountSettingsInput configurationAccountToBridge(
  AccountSettingsUpdate value,
) => native.AccountSettingsInput(
  account: native.AccountInput(
    accountId: value.accountId,
    templateId: value.templateId,
    protocol: value.protocol,
    name: value.name,
    baseUrl: value.baseUrl,
    secret: switch (value.secret) {
      PreserveAccountSecret() => const native.AccountSecretInput.preserve(),
      ReplaceAccountSecret(:final value) => native.AccountSecretInput.replace(
        value: value,
      ),
      ClearAccountSecret() => const native.AccountSecretInput.clear(),
    },
    pricingEnabled: value.pricingEnabled,
    customModels: value.customModels
        .map(
          (model) => native.AccountModelInput(
            modelId: model.modelId,
            displayName: model.displayName,
            wireApi: model.wireApi,
            contextWindow: model.contextWindow == null
                ? null
                : nativeU64(
                    model.contextWindow!,
                    'custom model context window',
                  ),
            maxOutputTokens: model.maxOutputTokens == null
                ? null
                : nativeU64(
                    model.maxOutputTokens!,
                    'custom model max output tokens',
                  ),
          ),
        )
        .toList(growable: false),
    modelConnectionModes: value.modelConnectionModes
        .map(
          (mode) => native.AccountModelConnectionInput(
            modelId: mode.modelId,
            connectionMode: mode.connectionMode,
          ),
        )
        .toList(growable: false),
    modelAutoCompactLimits: value.modelAutoCompactLimits
        .map(
          (limit) => native.AccountModelAutoCompactInput(
            modelId: limit.modelId,
            limit: nativeU64(limit.limit, 'model auto compact limit'),
          ),
        )
        .toList(growable: false),
  ),
);

// Check only the actual wire integer widths, not additional business limits.
int _unsigned(int value, int maximum, String field) {
  if (value < 0 || value > maximum) {
    throw StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'The $field integer cannot be represented exactly',
      retryable: false,
      correlationId: 'adapter-integer-range',
    );
  }
  return value;
}

native.SettingsFieldInput configurationFieldToBridge(
  SettingsFieldUpdate update,
) => switch (update) {
  DelegationModeUpdate(:final value) =>
    native.SettingsFieldInput.delegationMode(
      value: switch (value) {
        DelegationMode.profile => delegation.BridgeDelegationMode.profile,
        DelegationMode.automatic => delegation.BridgeDelegationMode.automatic,
      },
    ),
  DelegationPreferenceUpdate(:final value) =>
    native.SettingsFieldInput.delegationPreference(
      value: switch (value) {
        DelegationPreference.economy =>
          delegation.BridgeDelegationPreference.economy,
        DelegationPreference.balanced =>
          delegation.BridgeDelegationPreference.balanced,
        DelegationPreference.fast => delegation.BridgeDelegationPreference.fast,
      },
    ),
  InstructionBaseOverride(:final value) =>
    native.SettingsFieldInput.instructionBaseOverride(value: value),
  InstructionDeveloper(:final value) =>
    native.SettingsFieldInput.instructionDeveloper(value: value),
  InstructionUser(:final value) => native.SettingsFieldInput.instructionUser(
    value: value,
  ),
  ProjectDocMaxBytes(:final value) =>
    native.SettingsFieldInput.projectDocMaxBytes(
      value: nativeU64(value, 'project document max bytes'),
    ),
  ProjectDocFallbackFilenames(:final value) =>
    native.SettingsFieldInput.projectDocFallbackFilenames(value: value),
  SkillsEnabled(:final value) => native.SettingsFieldInput.skillsEnabled(
    value: value,
  ),
  SkillsAutoLearn(:final value) => native.SettingsFieldInput.skillsAutoLearn(
    value: value,
  ),
  SkillsSystemEnabled(:final value) =>
    native.SettingsFieldInput.skillsSystemEnabled(value: value),
  SkillsProjectDir(:final value) => native.SettingsFieldInput.skillsProjectDir(
    value: value,
  ),
  SkillsUserDir(:final value) => native.SettingsFieldInput.skillsUserDir(
    value: value,
  ),
  SkillsExternalDirs(:final value) =>
    native.SettingsFieldInput.skillsExternalDirs(value: value),
  SkillsDisabled(:final value) => native.SettingsFieldInput.skillsDisabled(
    value: value,
  ),
  SkillsAutoLearnMinToolCalls(:final value) =>
    native.SettingsFieldInput.skillsAutoLearnMinToolCalls(
      value: _unsigned(value, 0xffffffff, 'skills minimum tool calls'),
    ),
  McpServerEnabled(:final id, :final value) =>
    native.SettingsFieldInput.mcpServerEnabled(id: id, value: value),
  McpServerTransport(:final id, :final transport) =>
    native.SettingsFieldInput.mcpServerTransport(id: id, transport: transport),
  McpServerEndpoint(:final id, :final endpoint) =>
    native.SettingsFieldInput.mcpServerEndpoint(id: id, endpoint: endpoint),
  GeneralFollowActiveTurn(:final value) =>
    native.SettingsFieldInput.generalFollowActiveTurn(value: value),
  GeneralCompactTimeline(:final value) =>
    native.SettingsFieldInput.generalCompactTimeline(value: value),
  GeneralSidebarWidth(:final value) =>
    native.SettingsFieldInput.generalSidebarWidth(
      value: value == null
          ? null
          : _unsigned(value, 0xffff, 'general sidebar width'),
    ),
  GeneralPinnedThreadIds(:final value) =>
    native.SettingsFieldInput.generalPinnedThreadIds(value: value),
  GeneralPinnedProjectIds(:final value) =>
    native.SettingsFieldInput.generalPinnedProjectIds(value: value),
  WebSearchMode(:final value) => native.SettingsFieldInput.webSearchMode(
    value: value,
  ),
  WebSearchContextSize(:final value) =>
    native.SettingsFieldInput.webSearchContextSize(value: value),
  WebSearchAllowedDomains(:final value) =>
    native.SettingsFieldInput.webSearchAllowedDomains(value: value),
  WebSearchCountry(:final value) => native.SettingsFieldInput.webSearchCountry(
    value: value,
  ),
  WebSearchRegion(:final value) => native.SettingsFieldInput.webSearchRegion(
    value: value,
  ),
  WebSearchCity(:final value) => native.SettingsFieldInput.webSearchCity(
    value: value,
  ),
  WebSearchTimezone(:final value) =>
    native.SettingsFieldInput.webSearchTimezone(value: value),
  DeepSeekWebSearchEnabled(:final value) =>
    native.SettingsFieldInput.deepSeekWebSearchEnabled(value: value),
  DeepSeekWebFetchEnabled(:final value) =>
    native.SettingsFieldInput.deepSeekWebFetchEnabled(value: value),
  ModeModel(:final modeId, :final accountId, :final modelId) =>
    native.SettingsFieldInput.modeModel(
      modeId: modeId,
      accountId: accountId,
      modelId: modelId,
    ),
  ModeReasoningEffort(:final modeId, :final effort) =>
    native.SettingsFieldInput.modeReasoningEffort(
      modeId: modeId,
      effort: effort,
    ),
  RoleModel(:final role, :final accountId, :final modelId) =>
    native.SettingsFieldInput.roleModel(
      role: role,
      accountId: accountId,
      modelId: modelId,
    ),
  RoleReasoningEffort(:final role, :final effort) =>
    native.SettingsFieldInput.roleReasoningEffort(role: role, effort: effort),
};

profile.BridgeProfileCommandRequest saveProfileToBridge(
  SaveProfileRequest value,
) => profile.BridgeProfileCommandRequest.saveProfile(
  request: profile.BridgeSaveProfileRequest(
    operationId: configurationOperationToBridge(value.operationId),
    expectedSettingsRevision: nativeU64(
      value.expectedSettingsRevision,
      'expected settings revision',
    ),
    profile: profile.BridgeAgentProfileEdit(
      profileId: value.profile.profileId,
      displayName: value.profile.displayName,
      description: value.profile.description,
      whenToUse: value.profile.whenToUse,
      systemInstructions: value.profile.systemInstructions,
      accountId: value.profile.accountId,
      modelId: value.profile.modelId,
      effort: value.profile.effort,
      enabled: value.profile.enabled,
      workspaceMode: profileWorkspaceToBridge(value.profile.workspaceMode),
    ),
  ),
);

profile.BridgeProfileCommandRequest systemProfileEnabledToBridge(
  SetSystemProfileEnabledRequest value,
) => profile.BridgeProfileCommandRequest.setSystemProfileEnabled(
  request: profile.BridgeSetSystemProfileEnabledRequest(
    operationId: configurationOperationToBridge(value.operationId),
    expectedSettingsRevision: nativeU64(
      value.expectedSettingsRevision,
      'expected settings revision',
    ),
    profileId: value.profileId,
    enabled: value.enabled,
  ),
);

profile.BridgeConfigurationReloadRequest configurationReloadToBridge(
  ConfigurationReloadRequest value,
) => profile.BridgeConfigurationReloadRequest(
  operationId: configurationOperationToBridge(value.operationId),
  expectedRevision: nativeU64(
    value.expectedRevision,
    'expected settings revision',
  ),
);
