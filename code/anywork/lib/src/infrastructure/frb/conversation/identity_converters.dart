import 'package:anywork_client/configuration.dart' show ConfigProjectionStamp;
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/conversation/identity.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';

ThreadFacet threadFacetFromBridge(native.BridgeThreadFacet value) =>
    switch (value) {
      native.BridgeThreadFacet.execution => ThreadFacet.execution,
      native.BridgeThreadFacet.metrics => ThreadFacet.metrics,
      native.BridgeThreadFacet.context => ThreadFacet.context,
      native.BridgeThreadFacet.configuration => ThreadFacet.configuration,
      native.BridgeThreadFacet.authoring => ThreadFacet.authoring,
    };

native.BridgeThreadFacet threadFacetToBridge(ThreadFacet value) =>
    switch (value) {
      ThreadFacet.execution => native.BridgeThreadFacet.execution,
      ThreadFacet.metrics => native.BridgeThreadFacet.metrics,
      ThreadFacet.context => native.BridgeThreadFacet.context,
      ThreadFacet.configuration => native.BridgeThreadFacet.configuration,
      ThreadFacet.authoring => native.BridgeThreadFacet.authoring,
    };

ThreadObservationMode observationModeFromBridge(
  native.BridgeThreadObservationMode value,
) => switch (value) {
  native.BridgeThreadObservationMode.live => ThreadObservationMode.live,
  native.BridgeThreadObservationMode.cold => ThreadObservationMode.cold,
};

native.BridgeThreadObservationMode observationModeToBridge(
  ThreadObservationMode value,
) => switch (value) {
  ThreadObservationMode.live => native.BridgeThreadObservationMode.live,
  ThreadObservationMode.cold => native.BridgeThreadObservationMode.cold,
};

ThreadFeedIdentity feedIdentityFromBridge(
  native.BridgeThreadFeedIdentity value,
) {
  if (value.feedId.isEmpty || value.runtimeEpoch.isEmpty) {
    throw adapterProtocol('thread-feed-identity');
  }
  return ThreadFeedIdentity(
    feedId: value.feedId,
    runtimeEpoch: value.runtimeEpoch,
    incarnation: exactU64(value.incarnation, 'Thread incarnation'),
    facet: threadFacetFromBridge(value.facet),
    mode: observationModeFromBridge(value.mode),
  );
}

ThreadFacetStamp facetStampFromBridge(native.BridgeThreadFacetStamp value) =>
    ThreadFacetStamp(
      runtimeEpoch: value.runtimeEpoch,
      incarnation: exactU64(value.incarnation, 'Thread incarnation'),
      facet: threadFacetFromBridge(value.facet),
      revision: exactU64(value.revision, 'facet revision'),
    );

native.BridgeThreadFacetStamp facetStampToBridge(ThreadFacetStamp value) =>
    native.BridgeThreadFacetStamp(
      runtimeEpoch: value.runtimeEpoch,
      incarnation: nativeU64(value.incarnation, 'Thread incarnation'),
      facet: threadFacetToBridge(value.facet),
      revision: nativeU64(value.revision, 'facet revision'),
    );

ReadScopeIdentity readScopeFromBridge(native.BridgeReadScopeIdentity value) {
  if (value.scopeId.isEmpty || value.runtimeEpoch.isEmpty) {
    throw adapterProtocol('thread-read-scope');
  }
  return ReadScopeIdentity(
    scopeId: value.scopeId,
    runtimeEpoch: value.runtimeEpoch,
    incarnation: exactU64(value.incarnation, 'read incarnation'),
    sourceRevision: exactU64(value.sourceRevision, 'read source revision'),
  );
}

ReadScopeIdentity checkedReadScope(
  native.BridgeReadScopeIdentity value,
  ReadScopeIdentity expected,
) {
  final actual = readScopeFromBridge(value);
  requireReadScope(actual, expected);
  return actual;
}

ThreadResyncReason resyncReasonFromBridge(native.BridgeResyncReason value) =>
    switch (value) {
      native.BridgeResyncReason.sourceLagged => ThreadResyncReason.sourceLagged,
      native.BridgeResyncReason.reliableQueueFull =>
        ThreadResyncReason.reliableQueueFull,
      native.BridgeResyncReason.revisionGap => ThreadResyncReason.revisionGap,
    };

ThreadFeedClosedReason closedReasonFromBridge(
  native.BridgeFeedClosedReason value,
) => switch (value) {
  native.BridgeFeedClosedReason.requested => ThreadFeedClosedReason.requested,
  native.BridgeFeedClosedReason.ownerReplaced =>
    ThreadFeedClosedReason.ownerReplaced,
  native.BridgeFeedClosedReason.runtimeStopped =>
    ThreadFeedClosedReason.runtimeStopped,
};

ThreadCapabilitySupport capabilityFromBridge(
  native.BridgeThreadCapabilitySupport value,
) => switch (value) {
  native.BridgeThreadCapabilitySupport.unsupported =>
    ThreadCapabilitySupport.unsupported,
};

ConfigProjectionStamp configSourcesFromBridge(
  native.BridgeConfigProjectionStamp value,
) => ConfigProjectionStamp(
  settingsRevision: exactU64(
    value.settingsRevision,
    'settings source revision',
  ),
  modelCatalogRevision: exactU64(
    value.modelCatalogRevision,
    'catalog source revision',
  ),
  closing: value.closing,
);

TurnReadRef turnRefFromBridge(native.BridgeTurnReadRef value) => TurnReadRef(
  entry: exactU64(value.entry, 'Turn read entry'),
  revision: exactU64(value.revision, 'Turn read revision'),
);
InteractionReadRef interactionRefFromBridge(
  native.BridgeInteractionReadRef value,
) => InteractionReadRef(
  entry: exactU64(value.entry, 'interaction read entry'),
  revision: exactU64(value.revision, 'interaction read revision'),
);
InteractionIndexRef interactionIndexRefFromBridge(
  native.BridgeInteractionIndexRef value,
) => InteractionIndexRef(
  entry: exactU64(value.entry, 'interaction index entry'),
  revision: exactU64(value.revision, 'interaction index revision'),
);
ActivityReadRef activityRefFromBridge(native.BridgeActivityReadRef value) =>
    ActivityReadRef(
      entry: exactU64(value.entry, 'activity read entry'),
      revision: exactU64(value.revision, 'activity read revision'),
    );
StorageReadRef storageRefFromBridge(native.BridgeStorageReadRef value) =>
    StorageReadRef(
      entry: exactU64(value.entry, 'storage read entry'),
      revision: exactU64(value.revision, 'storage read revision'),
    );

native.BridgeTurnReadRef turnRefToBridge(TurnReadRef value) =>
    native.BridgeTurnReadRef(
      entry: nativeU64(value.entry, 'Turn read entry'),
      revision: nativeU64(value.revision, 'Turn read revision'),
    );
native.BridgeInteractionReadRef interactionRefToBridge(
  InteractionReadRef value,
) => native.BridgeInteractionReadRef(
  entry: nativeU64(value.entry, 'interaction read entry'),
  revision: nativeU64(value.revision, 'interaction read revision'),
);
native.BridgeInteractionIndexRef interactionIndexRefToBridge(
  InteractionIndexRef value,
) => native.BridgeInteractionIndexRef(
  entry: nativeU64(value.entry, 'interaction index entry'),
  revision: nativeU64(value.revision, 'interaction index revision'),
);
native.BridgeActivityReadRef activityRefToBridge(ActivityReadRef value) =>
    native.BridgeActivityReadRef(
      entry: nativeU64(value.entry, 'activity read entry'),
      revision: nativeU64(value.revision, 'activity read revision'),
    );
native.BridgeStorageReadRef storageRefToBridge(StorageReadRef value) =>
    native.BridgeStorageReadRef(
      entry: nativeU64(value.entry, 'storage read entry'),
      revision: nativeU64(value.revision, 'storage read revision'),
    );

ContextReadRef contextRefFromBridge(native.BridgeContextReadRef value) =>
    ContextReadRef(
      entry: exactU64(value.entry, 'context read entry'),
      revision: exactU64(value.revision, 'context read revision'),
    );
ThreadConfigurationReadRef configurationRefFromBridge(
  native.BridgeThreadConfigurationReadRef value,
) => ThreadConfigurationReadRef(
  entry: exactU64(value.entry, 'Thread configuration read entry'),
  revision: exactU64(value.revision, 'Thread configuration read revision'),
);
TodoReadRef todoRefFromBridge(native.BridgeTodoReadRef value) => TodoReadRef(
  entry: exactU64(value.entry, 'Todo read entry'),
  revision: exactU64(value.revision, 'Todo read revision'),
);
WorkflowReadRef workflowRefFromBridge(native.BridgeWorkflowReadRef value) =>
    WorkflowReadRef(
      entry: exactU64(value.entry, 'workflow read entry'),
      revision: exactU64(value.revision, 'workflow read revision'),
    );
MetricsIdentityRef metricsIdentityRefFromBridge(
  native.BridgeMetricsIdentityRef value,
) => MetricsIdentityRef(entry: exactU64(value.entry, 'metrics identity entry'));
