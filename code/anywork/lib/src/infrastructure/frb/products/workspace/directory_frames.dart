import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/feed/agent_directory.dart'
    as agents;
import '../../../../rust/api/studio/products/feed/project_directory.dart'
    as projects;
import '../../../../rust/api/studio/products/feed/thread_directory.dart'
    as threads;
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../directory_headers.dart';
import '../identity_converters.dart';

ProjectDirectoryFrame projectDirectoryFrameFromBridge(
  projects.BridgeProjectDirectoryFrame value,
) => switch (value) {
  projects.BridgeProjectDirectoryFrame_Data(
    :final deliverySequence,
    :final event,
  ) =>
    ProjectDirectoryFrame.data(
      deliverySequence: exactU64(
        deliverySequence,
        'Project directory delivery',
      ),
      event: switch (event) {
        projects.BridgeProjectDirectoryEvent_Baseline(
          :final identity,
          :final stamp,
          :final value,
        ) =>
          ProjectDirectoryEvent.baseline(
            identity: productFeedIdentityFromBridge(identity),
            stamp: productStampFromBridge(stamp),
            value: ProjectDirectoryBaseline(
              header: projectHeaderFromBridge(value.header),
              collection: value.collection == null
                  ? null
                  : collectionRefFromBridge(value.collection!),
            ),
          ),
        projects.BridgeProjectDirectoryEvent_Change(
          :final stamp,
          :final baseRevision,
          :final value,
        ) =>
          ProjectDirectoryEvent.change(
            stamp: productStampFromBridge(stamp),
            baseRevision: exactU64(
              baseRevision,
              'Project projection base revision',
            ),
            value: ProjectDirectoryChange(
              header: projectHeaderFromBridge(value.header),
              baseCollectionRevision: nullableU64(
                value.baseCollectionRevision,
                'Project collection base revision',
              ),
              collection: value.collection == null
                  ? null
                  : collectionRefFromBridge(value.collection!),
              upserted: [
                for (final entry in value.upserted) entityRefFromBridge(entry),
              ],
              removedEntries: [
                for (final entry in value.removedEntries)
                  exactU64(entry, 'removed Project entry'),
              ],
            ),
          ),
      },
    ),
  projects.BridgeProjectDirectoryFrame_ResyncRequired(
    :final identity,
    :final reason,
  ) =>
    ProjectDirectoryFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  projects.BridgeProjectDirectoryFrame_Failure(:final identity, :final error) =>
    ProjectDirectoryFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  projects.BridgeProjectDirectoryFrame_Closed(:final identity, :final reason) =>
    ProjectDirectoryFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};

ThreadDirectoryFrame threadDirectoryFrameFromBridge(
  threads.BridgeThreadDirectoryFrame value,
) => switch (value) {
  threads.BridgeThreadDirectoryFrame_Data(
    :final deliverySequence,
    :final event,
  ) =>
    ThreadDirectoryFrame.data(
      deliverySequence: exactU64(deliverySequence, 'Thread directory delivery'),
      event: switch (event) {
        threads.BridgeThreadDirectoryEvent_Baseline(
          :final identity,
          :final stamp,
          :final value,
        ) =>
          ThreadDirectoryEvent.baseline(
            identity: productFeedIdentityFromBridge(identity),
            stamp: productStampFromBridge(stamp),
            value: ThreadDirectoryBaseline(
              header: threadDirectoryHeaderFromBridge(value.header),
              collection: value.collection == null
                  ? null
                  : collectionRefFromBridge(value.collection!),
            ),
          ),
        threads.BridgeThreadDirectoryEvent_Change(
          :final stamp,
          :final baseRevision,
          :final value,
        ) =>
          ThreadDirectoryEvent.change(
            stamp: productStampFromBridge(stamp),
            baseRevision: exactU64(
              baseRevision,
              'Thread projection base revision',
            ),
            value: ThreadDirectoryChange(
              header: threadDirectoryHeaderFromBridge(value.header),
              baseCollectionRevision: nullableU64(
                value.baseCollectionRevision,
                'Thread collection base revision',
              ),
              collection: value.collection == null
                  ? null
                  : collectionRefFromBridge(value.collection!),
              upserted: [
                for (final entry in value.upserted) entityRefFromBridge(entry),
              ],
              removedEntries: [
                for (final entry in value.removedEntries)
                  exactU64(entry, 'removed Thread entry'),
              ],
            ),
          ),
      },
    ),
  threads.BridgeThreadDirectoryFrame_ResyncRequired(
    :final identity,
    :final reason,
  ) =>
    ThreadDirectoryFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  threads.BridgeThreadDirectoryFrame_Failure(:final identity, :final error) =>
    ThreadDirectoryFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  threads.BridgeThreadDirectoryFrame_Closed(:final identity, :final reason) =>
    ThreadDirectoryFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};

AgentDirectoryFrame agentDirectoryFrameFromBridge(
  agents.BridgeAgentDirectoryFrame value,
) => switch (value) {
  agents.BridgeAgentDirectoryFrame_Data(
    :final deliverySequence,
    :final event,
  ) =>
    AgentDirectoryFrame.data(
      deliverySequence: exactU64(deliverySequence, 'Agent directory delivery'),
      event: switch (event) {
        agents.BridgeAgentDirectoryEvent_Baseline(
          :final identity,
          :final stamp,
          :final value,
        ) =>
          AgentDirectoryEvent.baseline(
            identity: productFeedIdentityFromBridge(identity),
            stamp: productStampFromBridge(stamp),
            value: AgentDirectoryBaseline(
              header: agentHeaderFromBridge(value.header),
              collection: value.collection == null
                  ? null
                  : collectionRefFromBridge(value.collection!),
            ),
          ),
        agents.BridgeAgentDirectoryEvent_Change(
          :final stamp,
          :final baseRevision,
          :final value,
        ) =>
          AgentDirectoryEvent.change(
            stamp: productStampFromBridge(stamp),
            baseRevision: exactU64(
              baseRevision,
              'Agent projection base revision',
            ),
            value: AgentDirectoryChange(
              header: agentHeaderFromBridge(value.header),
              baseCollectionRevision: nullableU64(
                value.baseCollectionRevision,
                'Agent collection base revision',
              ),
              collection: value.collection == null
                  ? null
                  : collectionRefFromBridge(value.collection!),
              upserted: [
                for (final entry in value.upserted) entityRefFromBridge(entry),
              ],
              removedEntries: [
                for (final entry in value.removedEntries)
                  exactU64(entry, 'removed Agent entry'),
              ],
            ),
          ),
      },
    ),
  agents.BridgeAgentDirectoryFrame_ResyncRequired(
    :final identity,
    :final reason,
  ) =>
    AgentDirectoryFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  agents.BridgeAgentDirectoryFrame_Failure(:final identity, :final error) =>
    AgentDirectoryFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  agents.BridgeAgentDirectoryFrame_Closed(:final identity, :final reason) =>
    AgentDirectoryFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
