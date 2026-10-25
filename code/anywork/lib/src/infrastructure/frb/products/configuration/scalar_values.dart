import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart' show BillingKind;
import 'package:anywork_client/modes.dart'
    show DelegationMode, DelegationPreference;

import '../../../../rust/api/studio/types/agent_profile.dart' as profile;
import '../../../../rust/api/studio/types/delegation.dart' as native;
import '../../../../rust/api/studio/types/settings.dart' as settings;

BillingKind configurationBillingFromBridge(native.BridgeBillingKind value) =>
    switch (value) {
      native.BridgeBillingKind.metered => BillingKind.metered,
      native.BridgeBillingKind.subscription => BillingKind.subscription,
      native.BridgeBillingKind.unknown => BillingKind.unknown,
    };

native.BridgeBillingKind configurationBillingToBridge(BillingKind value) =>
    switch (value) {
      BillingKind.metered => native.BridgeBillingKind.metered,
      BillingKind.subscription => native.BridgeBillingKind.subscription,
      BillingKind.unknown => native.BridgeBillingKind.unknown,
    };

AgentWorkspaceMode profileWorkspaceFromBridge(
  profile.BridgeAgentWorkspaceMode value,
) => switch (value) {
  profile.BridgeAgentWorkspaceMode.unrestricted =>
    AgentWorkspaceMode.unrestricted,
  profile.BridgeAgentWorkspaceMode.directory => AgentWorkspaceMode.directory,
  profile.BridgeAgentWorkspaceMode.worktree => AgentWorkspaceMode.worktree,
  profile.BridgeAgentWorkspaceMode.review => AgentWorkspaceMode.review,
};

profile.BridgeAgentWorkspaceMode profileWorkspaceToBridge(
  AgentWorkspaceMode value,
) => switch (value) {
  AgentWorkspaceMode.unrestricted =>
    profile.BridgeAgentWorkspaceMode.unrestricted,
  AgentWorkspaceMode.directory => profile.BridgeAgentWorkspaceMode.directory,
  AgentWorkspaceMode.worktree => profile.BridgeAgentWorkspaceMode.worktree,
  AgentWorkspaceMode.review => profile.BridgeAgentWorkspaceMode.review,
};

DelegationSettings configurationDelegationFromBridge(
  native.BridgeDelegationSettings value,
) => DelegationSettings(
  mode: switch (value.mode) {
    native.BridgeDelegationMode.profile => DelegationMode.profile,
    native.BridgeDelegationMode.automatic => DelegationMode.automatic,
  },
  preference: switch (value.preference) {
    native.BridgeDelegationPreference.economy => DelegationPreference.economy,
    native.BridgeDelegationPreference.balanced => DelegationPreference.balanced,
    native.BridgeDelegationPreference.fast => DelegationPreference.fast,
  },
);

McpConfigurationState configurationMcpStateFromBridge(
  settings.BridgeMcpServerConfiguration value,
) => switch (value) {
  settings.BridgeMcpServerConfiguration.enabled =>
    McpConfigurationState.enabled,
  settings.BridgeMcpServerConfiguration.disabled =>
    McpConfigurationState.disabled,
  settings.BridgeMcpServerConfiguration.missingCredential =>
    McpConfigurationState.missingCredential,
};
