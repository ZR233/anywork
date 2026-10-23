import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/conversation/configuration.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';

ThreadConfigurationFrame configurationFrameFromBridge(native.BridgeConfigurationFrame value) => switch (value) {
  native.BridgeConfigurationFrame_Data(:final deliverySequence, :final event) =>
    ThreadConfigurationFrame.data(deliverySequence: exactU64(deliverySequence, 'configuration delivery sequence'), event: switch (event) {
      native.BridgeConfigurationEvent_Baseline(:final identity, :final stamp, :final value) =>
        ThreadConfigurationEvent.baseline(identity: feedIdentityFromBridge(identity), stamp: facetStampFromBridge(stamp), value: configurationValueFromBridge(value)),
      native.BridgeConfigurationEvent_Replace(:final stamp, :final value) =>
        ThreadConfigurationEvent.replace(stamp: facetStampFromBridge(stamp), value: configurationValueFromBridge(value)),
    }),
  native.BridgeConfigurationFrame_ResyncRequired(:final identity, :final reason) =>
    ThreadConfigurationFrame.resyncRequired(identity: feedIdentityFromBridge(identity), reason: resyncReasonFromBridge(reason)),
  native.BridgeConfigurationFrame_Failure(:final identity, :final error) =>
    ThreadConfigurationFrame.failure(identity: feedIdentityFromBridge(identity), error: bridgeFailure(error)),
  native.BridgeConfigurationFrame_Closed(:final identity, :final reason) =>
    ThreadConfigurationFrame.closed(identity: feedIdentityFromBridge(identity), reason: closedReasonFromBridge(reason)),
};

ThreadConfigurationValue configurationValueFromBridge(native.BridgeConfigurationValue value) => ThreadConfigurationValue(
  details: configurationRefFromBridge(value.details),
  sources: configSourcesFromBridge(value.sources),
  modeRevision: exactU64(value.modeRevision, 'Mode catalog revision'),
  modeBindingRevision: nullableU64(value.modeBindingRevision, 'Mode extension binding revision'),
  modelRoute: value.modelRoute == null ? null : ModelRouteBrief(
    revision: exactU64(value.modelRoute!.revision, 'model route revision'),
    available: value.modelRoute!.available,
    hasUnavailableReason: value.modelRoute!.hasUnavailableReason,
  ),
  activeSkillCount: exactU64(value.activeSkillCount, 'active skill count'),
  activeMcp: capabilityFromBridge(value.activeMcp),
  activeLsp: capabilityFromBridge(value.activeLsp),
  mcpHealth: capabilityFromBridge(value.mcpHealth),
);
