import 'package:anywork_client/configuration_ports.dart';

import '../../../rust/api/studio/products/feed/agent_profiles.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'catalog_references.dart';
import 'identity_converters.dart';
import 'source_converters.dart';

AgentProfilesHeader profilesHeaderFromBridge(
  native.BridgeAgentProfilesHeader value,
) => AgentProfilesHeader(
  source: observedHeaderFromBridge(value.source),
  profilesRevision: nullableU64(value.profilesRevision, 'profiles revision'),
  reference: value.reference == null
      ? null
      : profilesReadRefFromBridge(value.reference!),
);

AgentProfilesBaseline profilesBaselineFromBridge(
  native.BridgeAgentProfilesBaseline value,
) => AgentProfilesBaseline(
  header: profilesHeaderFromBridge(value.header),
  collection: value.collection == null
      ? null
      : collectionRefFromBridge(value.collection!),
);

AgentProfilesChange profilesChangeFromBridge(
  native.BridgeAgentProfilesChange value,
) => AgentProfilesChange(
  header: profilesHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(
    value.baseCollectionRevision,
    'profiles base collection revision',
  ),
  collection: value.collection == null
      ? null
      : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries
      .map((entry) => exactU64(entry, 'profiles removed entry'))
      .toList(growable: false),
);

AgentProfilesEvent profilesEventFromBridge(
  native.BridgeAgentProfilesEvent value,
) => switch (value) {
  native.BridgeAgentProfilesEvent_Baseline(
    :final identity,
    :final stamp,
    :final value,
  ) =>
    AgentProfilesEvent.baseline(
      identity: productFeedIdentityFromBridge(identity),
      stamp: productStampFromBridge(stamp),
      value: profilesBaselineFromBridge(value),
    ),
  native.BridgeAgentProfilesEvent_Change(
    :final stamp,
    :final baseRevision,
    :final value,
  ) =>
    AgentProfilesEvent.change(
      stamp: productStampFromBridge(stamp),
      baseRevision: exactU64(baseRevision, 'profiles base revision'),
      value: profilesChangeFromBridge(value),
    ),
};

AgentProfilesFrame profilesFrameFromBridge(
  native.BridgeAgentProfilesFrame value,
) => switch (value) {
  native.BridgeAgentProfilesFrame_Data(:final deliverySequence, :final event) =>
    AgentProfilesFrame.data(
      deliverySequence: exactU64(
        deliverySequence,
        'profiles delivery sequence',
      ),
      event: profilesEventFromBridge(event),
    ),
  native.BridgeAgentProfilesFrame_ResyncRequired(
    :final identity,
    :final reason,
  ) =>
    AgentProfilesFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  native.BridgeAgentProfilesFrame_Failure(:final identity, :final error) =>
    AgentProfilesFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeAgentProfilesFrame_Closed(:final identity, :final reason) =>
    AgentProfilesFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
