import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/conversation/configuration.dart' as native;
import '../../../rust/api/studio/conversation/identity.dart' as identity;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';

ThreadConfigurationFrame configurationFrameFromBridge(
  native.BridgeThreadConfigurationFrame value,
) => switch (value) {
  native.BridgeThreadConfigurationFrame_Data(
    :final deliverySequence,
    :final event,
  ) =>
    ThreadConfigurationFrame.data(
      deliverySequence: exactU64(
        deliverySequence,
        'configuration delivery sequence',
      ),
      event: switch (event) {
        native.BridgeThreadConfigurationEvent_Baseline(
          :final identity,
          :final stamp,
          :final value,
        ) =>
          ThreadConfigurationEvent.baseline(
            identity: feedIdentityFromBridge(identity),
            stamp: facetStampFromBridge(stamp),
            value: configurationValueFromBridge(value),
          ),
        native.BridgeThreadConfigurationEvent_Replace(
          :final stamp,
          :final value,
        ) =>
          ThreadConfigurationEvent.replace(
            stamp: facetStampFromBridge(stamp),
            value: configurationValueFromBridge(value),
          ),
      },
    ),
  native.BridgeThreadConfigurationFrame_ResyncRequired(
    :final identity,
    :final reason,
  ) =>
    ThreadConfigurationFrame.resyncRequired(
      identity: feedIdentityFromBridge(identity),
      reason: resyncReasonFromBridge(reason),
    ),
  native.BridgeThreadConfigurationFrame_Failure(
    :final identity,
    :final error,
  ) =>
    ThreadConfigurationFrame.failure(
      identity: feedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeThreadConfigurationFrame_Closed(
    :final identity,
    :final reason,
  ) =>
    ThreadConfigurationFrame.closed(
      identity: feedIdentityFromBridge(identity),
      reason: closedReasonFromBridge(reason),
    ),
};

ThreadConfigurationValue configurationValueFromBridge(
  native.BridgeConfigurationValue value,
) => ThreadConfigurationValue(
  details: threadConfigurationRefFromBridge(value.details),
  sources: configSourcesFromBridge(value.sources),
  modeRevision: exactU64(value.modeRevision, 'Mode catalog revision'),
  modeBindingRevision: nullableU64(
    value.modeBindingRevision,
    'Mode extension binding revision',
  ),
  modelRoute: value.modelRoute == null
      ? null
      : ModelRouteBrief(
          revision: exactU64(
            value.modelRoute!.revision,
            'model route revision',
          ),
          available: value.modelRoute!.available,
          hasUnavailableReason: value.modelRoute!.hasUnavailableReason,
        ),
  activeSkillCount: exactU64(value.activeSkillCount, 'active skill count'),
  activeMcp: capabilityFromBridge(value.activeMcp),
  activeLsp: capabilityFromBridge(value.activeLsp),
  mcpHealth: capabilityFromBridge(value.mcpHealth),
);

ThreadConfigurationReadRef threadConfigurationRefFromBridge(
  identity.BridgeThreadConfigurationReadRef value,
) => ThreadConfigurationReadRef(
  entry: exactU64(value.entry, 'Thread configuration read entry'),
  revision: exactU64(value.revision, 'Thread configuration read revision'),
);

identity.BridgeThreadConfigurationReadRef threadConfigurationRefToBridge(
  ThreadConfigurationReadRef value,
) => identity.BridgeThreadConfigurationReadRef(
  entry: nativeU64(value.entry, 'Thread configuration read entry'),
  revision: nativeU64(value.revision, 'Thread configuration read revision'),
);
