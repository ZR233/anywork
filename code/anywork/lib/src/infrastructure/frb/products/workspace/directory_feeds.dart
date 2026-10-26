import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/feed/agent_directory.dart'
    as agents;
import '../../../../rust/api/studio/products/feed/agent_directory_transport.dart'
    as agent_native;
import '../../../../rust/api/studio/products/feed/project_directory.dart'
    as projects;
import '../../../../rust/api/studio/products/feed/project_directory_transport.dart'
    as project_native;
import '../../../../rust/api/studio/products/feed/thread_directory.dart'
    as threads;
import '../../../../rust/api/studio/products/feed/thread_directory_transport.dart'
    as thread_native;
import '../../../../rust/api/studio/products/identity.dart' as native_identity;
import '../../shared/adapter_failure.dart';
import '../../shared/exact_numbers.dart';
import '../directory_references.dart';
import '../product_read_owner.dart' show modelPageArguments;
import 'directory_feed_connection.dart';
import 'directory_frames.dart';
import 'directory_values.dart';

final class FrbProjectDirectoryConnection
    extends
        FrbDirectoryFeedConnection<
          project_native.BridgeProjectDirectoryFeed,
          projects.BridgeProjectDirectoryFrame,
          ProjectDirectoryFrame
        > {
  FrbProjectDirectoryConnection()
    : super(
        ProductResource.projectDirectory,
        resource: 'project-directory',
        open: project_native.openProjectDirectory,
        identity: (handle) => handle.identity(),
        stream: (handle) => handle.stream(),
        ack: (handle, sequence) =>
            handle.ackThrough(deliverySequence: sequence),
        requestClose: (handle) => handle.requestClose(),
        close: (handle) => handle.close(),
        retryClose: (handle) => handle.retryClose(),
        dispose: (handle) => handle.dispose(),
        convert: projectDirectoryFrameFromBridge,
        isTerminal: (frame) => frame is! ProjectDirectoryData,
        failureFrame: (identity, error) =>
            ProjectDirectoryFrame.failure(identity: identity, error: error),
        frameIdentity: (frame) => switch (frame) {
          ProjectDirectoryData(
            event: ProjectDirectoryBaselineEvent(:final identity),
          ) =>
            identity,
          ProjectDirectoryResyncRequired(:final identity) => identity,
          ProjectDirectoryFeedFailure(:final identity) => identity,
          ProjectDirectoryClosed(:final identity) => identity,
          ProjectDirectoryData(event: ProjectDirectoryChangeEvent()) => null,
        },
        frameStamp: (frame) => switch (frame) {
          ProjectDirectoryData(
            event: ProjectDirectoryBaselineEvent(:final stamp),
          ) =>
            stamp,
          ProjectDirectoryData(
            event: ProjectDirectoryChangeEvent(:final stamp),
          ) =>
            stamp,
          _ => null,
        },
      );
}

final class FrbAgentDirectoryConnection
    extends
        FrbDirectoryFeedConnection<
          agent_native.BridgeAgentDirectoryFeed,
          agents.BridgeAgentDirectoryFrame,
          AgentDirectoryFrame
        > {
  FrbAgentDirectoryConnection()
    : super(
        ProductResource.agentDirectory,
        resource: 'agent-directory',
        open: agent_native.openAgentDirectory,
        identity: (handle) => handle.identity(),
        stream: (handle) => handle.stream(),
        ack: (handle, sequence) =>
            handle.ackThrough(deliverySequence: sequence),
        requestClose: (handle) => handle.requestClose(),
        close: (handle) => handle.close(),
        retryClose: (handle) => handle.retryClose(),
        dispose: (handle) => handle.dispose(),
        convert: agentDirectoryFrameFromBridge,
        isTerminal: (frame) => frame is! AgentDirectoryData,
        failureFrame: (identity, error) =>
            AgentDirectoryFrame.failure(identity: identity, error: error),
        frameIdentity: (frame) => switch (frame) {
          AgentDirectoryData(
            event: AgentDirectoryBaselineEvent(:final identity),
          ) =>
            identity,
          AgentDirectoryResyncRequired(:final identity) => identity,
          AgentDirectoryFeedFailure(:final identity) => identity,
          AgentDirectoryClosed(:final identity) => identity,
          AgentDirectoryData(event: AgentDirectoryChangeEvent()) => null,
        },
        frameStamp: (frame) => switch (frame) {
          AgentDirectoryData(
            event: AgentDirectoryBaselineEvent(:final stamp),
          ) =>
            stamp,
          AgentDirectoryData(event: AgentDirectoryChangeEvent(:final stamp)) =>
            stamp,
          _ => null,
        },
      );
}

final class FrbThreadDirectoryConnection
    extends
        FrbDirectoryFeedConnection<
          thread_native.BridgeThreadDirectoryFeed,
          threads.BridgeThreadDirectoryFrame,
          ThreadDirectoryFrame
        >
    implements ThreadDirectoryConnection {
  FrbThreadDirectoryConnection(ThreadDirectoryScope scope)
    : super(
        ProductResource.threadDirectory,
        resource: 'thread-directory',
        open: () => thread_native.openThreadDirectory(
          scope: threadDirectoryScopeToBridge(scope),
        ),
        identity: (handle) => handle.identity(),
        stream: (handle) => handle.stream(),
        ack: (handle, sequence) =>
            handle.ackThrough(deliverySequence: sequence),
        requestClose: (handle) => handle.requestClose(),
        close: (handle) => handle.close(),
        retryClose: (handle) => handle.retryClose(),
        dispose: (handle) => handle.dispose(),
        convert: threadDirectoryFrameFromBridge,
        isTerminal: (frame) => frame is! ThreadDirectoryData,
        failureFrame: (identity, error) =>
            ThreadDirectoryFrame.failure(identity: identity, error: error),
        frameIdentity: (frame) => switch (frame) {
          ThreadDirectoryData(
            event: ThreadDirectoryBaselineEvent(:final identity),
          ) =>
            identity,
          ThreadDirectoryResyncRequired(:final identity) => identity,
          ThreadDirectoryFeedFailure(:final identity) => identity,
          ThreadDirectoryClosed(:final identity) => identity,
          ThreadDirectoryData(event: ThreadDirectoryChangeEvent()) => null,
        },
        frameStamp: (frame) => switch (frame) {
          ThreadDirectoryData(
            event: ThreadDirectoryBaselineEvent(:final stamp),
          ) =>
            stamp,
          ThreadDirectoryData(
            event: ThreadDirectoryChangeEvent(:final stamp),
          ) =>
            stamp,
          _ => null,
        },
      );

  @override
  Future<ThreadDirectoryReadTarget> extendWindow(
    ProductCollectionRef expectedCollection, {
    int limit = 32,
  }) => nativeQuery((handle) async {
    final request = modelPageArguments(0, limit);
    final target = threadDirectoryTargetFromBridge(
      await handle.extendWindow(
        expectedCollection: native_identity.BridgeProductCollectionRef(
          entry: nativeU64(expectedCollection.entry, 'Thread collection entry'),
          revision: nativeU64(
            expectedCollection.revision,
            'Thread collection revision',
          ),
          total: nativeU64(expectedCollection.total, 'Thread collection total'),
        ),
        limit: request.limit,
      ),
    );
    if (target.origin != originalOrigin) {
      throw adapterProtocol('thread-directory-extend-origin');
    }
    return target;
  });
}
