import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart' show AccountModelKey;
import 'package:anywork_client/modes.dart' show ThreadModeId;

import '../../../../rust/api/studio/conversation/identity.dart' as clock;
import '../../../../rust/api/studio/products/read/configuration_values.dart'
    as native;
import '../../../../rust/api/studio/products/read/primitives.dart' as primitive;
import '../../../../rust/api/studio/products/references.dart' as reference;
import '../../conversation/identity_converters.dart'
    show configSourcesFromBridge;
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import '../catalog_references.dart';
import '../identity_converters.dart';
import '../model_read_values.dart' show modelSelectionFromBridge;
import 'scalar_values.dart';

ConfigurationRoleReadTarget configurationRoleTargetFromBridge(
  native.BridgeConfigurationRoleReadTarget value,
) => ConfigurationRoleReadTarget(
  reference: ConfigurationRoleReadRef(
    entry: exactU64(value.reference.entry, 'configuration pair entry'),
    revision: exactU64(value.reference.revision, 'configuration pair revision'),
  ),
  configuration: configurationTargetFromBridge(value.configuration),
  catalog: modelCatalogTargetFromBridge(value.catalog),
  stamp: configSourcesFromBridge(value.stamp),
);

native.BridgeConfigurationRoleReadTarget configurationRoleTargetToBridge(
  ConfigurationRoleReadTarget value,
) => native.BridgeConfigurationRoleReadTarget(
  reference: native.BridgeConfigurationRoleReadRef(
    entry: nativeU64(value.reference.entry, 'configuration pair entry'),
    revision: nativeU64(
      value.reference.revision,
      'configuration pair revision',
    ),
  ),
  configuration: reference.BridgeConfigurationReadTarget(
    origin: productOriginToBridge(value.configuration.origin),
    reference: configurationReadRefToBridge(value.configuration.reference),
  ),
  catalog: reference.BridgeModelCatalogReadTarget(
    origin: productOriginToBridge(value.catalog.origin),
    reference: modelCatalogReadRefToBridge(value.catalog.reference),
  ),
  stamp: clock.BridgeConfigProjectionStamp(
    settingsRevision: nativeU64(
      value.stamp.settingsRevision,
      'settings source revision',
    ),
    modelCatalogRevision: nativeU64(
      value.stamp.modelCatalogRevision,
      'catalog source revision',
    ),
    closing: value.stamp.closing,
  ),
);

RoleRouteRead configurationRoleRouteFromBridge(
  native.BridgeRoleRouteRead value,
) => switch (value) {
  native.BridgeRoleRouteRead_Configured(:final route) =>
    RoleRouteRead.configured(
      route: RoleModelRoute(
        key: route.key,
        accountId: route.accountId,
        modelId: route.modelId,
        effort: route.effort,
      ),
    ),
  native.BridgeRoleRouteRead_Missing(:final suggestion) =>
    RoleRouteRead.missing(
      suggestion: suggestion == null
          ? null
          : modelSelectionFromBridge(suggestion),
    ),
};

primitive.BridgeAccountModelKey startModelToBridge(AccountModelKey value) =>
    primitive.BridgeAccountModelKey(
      accountId: value.accountId,
      modelId: value.modelId,
    );

native.BridgeStartRouteIntent startIntentToBridge(StartRouteIntent value) =>
    native.BridgeStartRouteIntent(
      mode: value.mode.id,
      model: value.model == null ? null : startModelToBridge(value.model!),
      effort: value.effort,
    );

StartRouteIntent startIntentFromBridge(native.BridgeStartRouteIntent value) =>
    StartRouteIntent(
      mode: ThreadModeId(value.mode),
      model: value.model == null
          ? null
          : AccountModelKey(
              accountId: value.model!.accountId,
              modelId: value.model!.modelId,
            ),
      effort: value.effort,
    );

native.BridgeStartRouteQuery startQueryToBridge(StartRouteQuery value) =>
    switch (value) {
      ResolveStartRouteQuery(:final intent) =>
        native.BridgeStartRouteQuery.resolve(
          intent: startIntentToBridge(intent),
        ),
      SelectModelStartRouteQuery(:final intent, :final selected) =>
        native.BridgeStartRouteQuery.selectModel(
          intent: startIntentToBridge(intent),
          selected: startModelToBridge(selected),
        ),
    };

StartRouteQuery startQueryFromBridge(native.BridgeStartRouteQuery value) =>
    switch (value) {
      native.BridgeStartRouteQuery_Resolve(:final intent) =>
        StartRouteQuery.resolve(intent: startIntentFromBridge(intent)),
      native.BridgeStartRouteQuery_SelectModel(
        :final intent,
        :final selected,
      ) =>
        StartRouteQuery.selectModel(
          intent: startIntentFromBridge(intent),
          selected: AccountModelKey(
            accountId: selected.accountId,
            modelId: selected.modelId,
          ),
        ),
    };

StartRouteRead startReadFromBridge(native.BridgeStartRouteRead value) =>
    switch (value) {
      native.BridgeStartRouteRead_Ready(
        :final sources,
        :final query,
        :final intent,
        :final route,
        :final defaults,
      ) =>
        StartRouteRead.ready(
          sources: configurationRoleTargetFromBridge(sources),
          query: startQueryFromBridge(query),
          intent: startIntentFromBridge(intent),
          route: modelSelectionFromBridge(route),
          defaults: configurationDelegationFromBridge(defaults),
        ),
      native.BridgeStartRouteRead_Unavailable(
        :final sources,
        :final query,
        :final intent,
        :final desired,
        :final defaults,
        :final error,
      ) =>
        StartRouteRead.unavailable(
          sources: configurationRoleTargetFromBridge(sources),
          query: startQueryFromBridge(query),
          intent: startIntentFromBridge(intent),
          desired: desired == null ? null : modelSelectionFromBridge(desired),
          defaults: configurationDelegationFromBridge(defaults),
          error: bridgeFailure(error),
        ),
    };
