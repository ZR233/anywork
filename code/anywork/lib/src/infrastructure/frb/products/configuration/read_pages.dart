import 'package:anywork_client/configuration_ports.dart';

import '../../../../rust/api/studio/products/read/configuration_pages.dart'
    as native;
import '../../../../rust/api/studio/products/read/profile_values.dart'
    as profile;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import 'profile_values.dart';
import 'read_values.dart';

ConfigurationEntryPage configurationEntriesFromBridge(
  native.BridgeConfigurationEntryPage value,
) => ConfigurationEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'configuration entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false),
  nextOffset: nullableU64(
    value.nextOffset,
    'configuration entries next offset',
  ),
);
ConfigurationEntityRead configurationEntityFromBridge(
  native.BridgeConfigurationEntityRead value,
) => ConfigurationEntityRead(
  reference: entityRefFromBridge(value.reference),
  value: accountConfigurationFromBridge(value.value),
);
AccountConfigurationReadPage configurationAccountsPageFromBridge(
  native.BridgeAccountConfigurationReadPage value,
) => AccountConfigurationReadPage(
  listId: exactU64(value.listId, 'configuration accounts list'),
  offset: exactU64(value.offset, 'configuration accounts offset'),
  total: exactU64(value.total, 'configuration accounts total'),
  items: value.items
      .map(accountConfigurationFromBridge)
      .toList(growable: false),
  nextOffset: nullableU64(
    value.nextOffset,
    'configuration accounts next offset',
  ),
);
CustomModelConfigurationReadPage configurationCustomModelsPageFromBridge(
  native.BridgeCustomModelConfigurationReadPage value,
) => CustomModelConfigurationReadPage(
  listId: exactU64(value.listId, 'custom models list'),
  offset: exactU64(value.offset, 'custom models offset'),
  total: exactU64(value.total, 'custom models total'),
  items: value.items
      .map(customModelConfigurationFromBridge)
      .toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'custom models next offset'),
);
ModelConnectionReadPage configurationConnectionsPageFromBridge(
  native.BridgeModelConnectionReadPage value,
) => ModelConnectionReadPage(
  listId: exactU64(value.listId, 'model connections list'),
  offset: exactU64(value.offset, 'model connections offset'),
  total: exactU64(value.total, 'model connections total'),
  items: value.items
      .map(configurationConnectionFromBridge)
      .toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'model connections next offset'),
);
ModelAutoCompactReadPage configurationAutoCompactPageFromBridge(
  native.BridgeModelAutoCompactReadPage value,
) => ModelAutoCompactReadPage(
  listId: exactU64(value.listId, 'model compaction list'),
  offset: exactU64(value.offset, 'model compaction offset'),
  total: exactU64(value.total, 'model compaction total'),
  items: value.items
      .map(configurationAutoCompactFromBridge)
      .toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'model compaction next offset'),
);
ModeModelRouteReadPage configurationModesPageFromBridge(
  native.BridgeModeModelRouteReadPage value,
) => ModeModelRouteReadPage(
  listId: exactU64(value.listId, 'mode routes list'),
  offset: exactU64(value.offset, 'mode routes offset'),
  total: exactU64(value.total, 'mode routes total'),
  items: value.items
      .map(configurationModeRouteFromBridge)
      .toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'mode routes next offset'),
);
RoleModelRouteReadPage configurationRolesPageFromBridge(
  native.BridgeRoleModelRouteReadPage value,
) => RoleModelRouteReadPage(
  listId: exactU64(value.listId, 'role routes list'),
  offset: exactU64(value.offset, 'role routes offset'),
  total: exactU64(value.total, 'role routes total'),
  items: value.items
      .map(configurationRoleReadFromBridge)
      .toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'role routes next offset'),
);
McpConfigurationReadPage configurationMcpPageFromBridge(
  native.BridgeMcpConfigurationReadPage value,
) => McpConfigurationReadPage(
  listId: exactU64(value.listId, 'MCP configs list'),
  offset: exactU64(value.offset, 'MCP configs offset'),
  total: exactU64(value.total, 'MCP configs total'),
  items: value.items.map(configurationMcpFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'MCP configs next offset'),
);

AgentProfilesEntryPage profilesEntriesFromBridge(
  profile.BridgeAgentProfilesEntryPage value,
) => AgentProfilesEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'profiles entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'profiles entries next offset'),
);
AgentProfilesEntityRead profilesEntityFromBridge(
  profile.BridgeAgentProfilesEntityRead value,
) => AgentProfilesEntityRead(
  reference: entityRefFromBridge(value.reference),
  value: profileReadFromBridge(value.value),
);
AgentProfileReadPage profilesPageFromBridge(
  profile.BridgeAgentProfileReadPage value,
) => AgentProfileReadPage(
  listId: exactU64(value.listId, 'profiles list'),
  offset: exactU64(value.offset, 'profiles offset'),
  total: exactU64(value.total, 'profiles total'),
  items: value.items.map(profileReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'profiles next offset'),
);
ProfileDiagnosticReadPage profilesDiagnosticsPageFromBridge(
  profile.BridgeProfileDiagnosticReadPage value,
) => ProfileDiagnosticReadPage(
  listId: exactU64(value.listId, 'profile diagnostics list'),
  offset: exactU64(value.offset, 'profile diagnostics offset'),
  total: exactU64(value.total, 'profile diagnostics total'),
  items: value.items.map(profileDiagnosticFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'profile diagnostics next offset'),
);
