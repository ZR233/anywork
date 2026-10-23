import 'package:anywork_client/account_usage.dart' as usage;
import 'package:anywork_client/configuration.dart' as config;
import 'package:anywork_client/models.dart' as models;
import 'package:anywork_client/modes.dart' as modes;

import '../../../rust/api/studio/products/references.dart' as native;
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';

config.ConfigurationReadRef configurationReadRefFromBridge(native.BridgeConfigurationReadRef value) => config.ConfigurationReadRef(
  entry: exactU64(value.entry, 'configuration read entry'), revision: exactU64(value.revision, 'configuration read revision'),
);
config.AgentProfilesReadRef profilesReadRefFromBridge(native.BridgeAgentProfilesReadRef value) => config.AgentProfilesReadRef(
  entry: exactU64(value.entry, 'profiles read entry'), revision: exactU64(value.revision, 'profiles read revision'),
);
models.ModelCatalogReadRef modelCatalogReadRefFromBridge(native.BridgeModelCatalogReadRef value) => models.ModelCatalogReadRef(
  entry: exactU64(value.entry, 'model catalog read entry'), revision: exactU64(value.revision, 'model catalog read revision'),
);
models.AccountTemplatesReadRef templatesReadRefFromBridge(native.BridgeAccountTemplatesReadRef value) => models.AccountTemplatesReadRef(
  entry: exactU64(value.entry, 'templates read entry'), revision: exactU64(value.revision, 'templates read revision'),
);
modes.ModeCatalogReadRef modeCatalogReadRefFromBridge(native.BridgeModeCatalogReadRef value) => modes.ModeCatalogReadRef(
  entry: exactU64(value.entry, 'Mode catalog read entry'), revision: exactU64(value.revision, 'Mode catalog read revision'),
);
usage.AccountUsageReadRef accountUsageReadRefFromBridge(native.BridgeAccountUsageReadRef value) => usage.AccountUsageReadRef(
  entry: exactU64(value.entry, 'account usage read entry'), revision: exactU64(value.revision, 'account usage read revision'),
);

native.BridgeConfigurationReadRef configurationReadRefToBridge(config.ConfigurationReadRef value) => native.BridgeConfigurationReadRef(
  entry: nativeU64(value.entry, 'configuration read entry'), revision: nativeU64(value.revision, 'configuration read revision'),
);
native.BridgeAgentProfilesReadRef profilesReadRefToBridge(config.AgentProfilesReadRef value) => native.BridgeAgentProfilesReadRef(
  entry: nativeU64(value.entry, 'profiles read entry'), revision: nativeU64(value.revision, 'profiles read revision'),
);
native.BridgeModelCatalogReadRef modelCatalogReadRefToBridge(models.ModelCatalogReadRef value) => native.BridgeModelCatalogReadRef(
  entry: nativeU64(value.entry, 'model catalog read entry'), revision: nativeU64(value.revision, 'model catalog read revision'),
);
native.BridgeAccountTemplatesReadRef templatesReadRefToBridge(models.AccountTemplatesReadRef value) => native.BridgeAccountTemplatesReadRef(
  entry: nativeU64(value.entry, 'templates read entry'), revision: nativeU64(value.revision, 'templates read revision'),
);
native.BridgeModeCatalogReadRef modeCatalogReadRefToBridge(modes.ModeCatalogReadRef value) => native.BridgeModeCatalogReadRef(
  entry: nativeU64(value.entry, 'Mode catalog read entry'), revision: nativeU64(value.revision, 'Mode catalog read revision'),
);
native.BridgeAccountUsageReadRef accountUsageReadRefToBridge(usage.AccountUsageReadRef value) => native.BridgeAccountUsageReadRef(
  entry: nativeU64(value.entry, 'account usage read entry'), revision: nativeU64(value.revision, 'account usage read revision'),
);

// Every target takes its own original native origin, never a latest feed stamp.
config.ConfigurationReadTarget configurationTargetFromBridge(native.BridgeConfigurationReadTarget value) => config.ConfigurationReadTarget(
  origin: productOriginFromBridge(value.origin), reference: configurationReadRefFromBridge(value.reference),
);
config.AgentProfilesReadTarget profilesTargetFromBridge(native.BridgeAgentProfilesReadTarget value) => config.AgentProfilesReadTarget(
  origin: productOriginFromBridge(value.origin), reference: profilesReadRefFromBridge(value.reference),
);
models.ModelCatalogReadTarget modelCatalogTargetFromBridge(native.BridgeModelCatalogReadTarget value) => models.ModelCatalogReadTarget(
  origin: productOriginFromBridge(value.origin), reference: modelCatalogReadRefFromBridge(value.reference),
);
models.AccountTemplatesReadTarget templatesTargetFromBridge(native.BridgeAccountTemplatesReadTarget value) => models.AccountTemplatesReadTarget(
  origin: productOriginFromBridge(value.origin), reference: templatesReadRefFromBridge(value.reference),
);
modes.ModeCatalogReadTarget modeCatalogTargetFromBridge(native.BridgeModeCatalogReadTarget value) => modes.ModeCatalogReadTarget(
  origin: productOriginFromBridge(value.origin), reference: modeCatalogReadRefFromBridge(value.reference),
);
usage.AccountUsageReadTarget accountUsageTargetFromBridge(native.BridgeAccountUsageReadTarget value) => usage.AccountUsageReadTarget(
  origin: productOriginFromBridge(value.origin), reference: accountUsageReadRefFromBridge(value.reference),
);
