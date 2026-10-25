import 'package:anywork_client/configuration_ports.dart';

import '../../../rust/api/studio/products/feed/configuration.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'catalog_references.dart';
import 'configuration/route_values.dart';
import 'identity_converters.dart';
import 'source_converters.dart';

ConfigurationHeader productConfigurationHeaderFromBridge(
  native.BridgeConfigurationHeader value,
) => ConfigurationHeader(
  source: observedHeaderFromBridge(value.source),
  configurationRevision: nullableU64(
    value.configurationRevision,
    'configuration revision',
  ),
  updatedAt: nullableI64(
    value.updatedAt == null ? null : BigInt.from(value.updatedAt!),
    'configuration updated Unix seconds',
  ),
  reference: value.reference == null
      ? null
      : configurationReadRefFromBridge(value.reference!),
  roleRead: value.roleRead == null
      ? null
      : configurationRoleTargetFromBridge(value.roleRead!),
);

ConfigurationBaseline productConfigurationBaselineFromBridge(
  native.BridgeConfigurationBaseline value,
) => ConfigurationBaseline(
  header: productConfigurationHeaderFromBridge(value.header),
  collection: value.collection == null
      ? null
      : collectionRefFromBridge(value.collection!),
);

ConfigurationChange productConfigurationChangeFromBridge(
  native.BridgeConfigurationChange value,
) => ConfigurationChange(
  header: productConfigurationHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(
    value.baseCollectionRevision,
    'configuration base collection revision',
  ),
  collection: value.collection == null
      ? null
      : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries
      .map((entry) => exactU64(entry, 'configuration removed entry'))
      .toList(growable: false),
);

ConfigurationEvent productConfigurationEventFromBridge(
  native.BridgeConfigurationEvent value,
) => switch (value) {
  native.BridgeConfigurationEvent_Baseline(
    :final identity,
    :final stamp,
    :final value,
  ) =>
    ConfigurationEvent.baseline(
      identity: productFeedIdentityFromBridge(identity),
      stamp: productStampFromBridge(stamp),
      value: productConfigurationBaselineFromBridge(value),
    ),
  native.BridgeConfigurationEvent_Change(
    :final stamp,
    :final baseRevision,
    :final value,
  ) =>
    ConfigurationEvent.change(
      stamp: productStampFromBridge(stamp),
      baseRevision: exactU64(baseRevision, 'configuration base revision'),
      value: productConfigurationChangeFromBridge(value),
    ),
};

ConfigurationFrame productConfigurationFrameFromBridge(
  native.BridgeConfigurationFrame value,
) => switch (value) {
  native.BridgeConfigurationFrame_Data(:final deliverySequence, :final event) =>
    ConfigurationFrame.data(
      deliverySequence: exactU64(
        deliverySequence,
        'configuration delivery sequence',
      ),
      event: productConfigurationEventFromBridge(event),
    ),
  native.BridgeConfigurationFrame_ResyncRequired(
    :final identity,
    :final reason,
  ) =>
    ConfigurationFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  native.BridgeConfigurationFrame_Failure(:final identity, :final error) =>
    ConfigurationFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeConfigurationFrame_Closed(:final identity, :final reason) =>
    ConfigurationFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
