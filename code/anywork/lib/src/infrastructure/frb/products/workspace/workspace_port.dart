import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/handlers/lifecycle.dart' as projects;
import '../../../../rust/api/studio/handlers/ssh.dart' as remote;
import '../../../../rust/api/studio/handlers/thread.dart' as threads;
import '../../drafts/draft_command_values.dart' show createdThreadFromBridge;
import '../../shared/adapter_failure.dart';
import 'agent_read_connection.dart';
import 'command_results.dart';
import 'directory_feeds.dart';
import 'directory_values.dart';
import 'project_read_connection.dart';
import 'source_status_connection.dart';
import 'thread_read_connection.dart';

WorkspacePort createWorkspacePort() => const FrbWorkspacePort();

/// A pure transport leaf. Construction does not load the library, open feeds,
/// activate a Project or restore a Thread; Repository owners decide demand.
final class FrbWorkspacePort implements WorkspacePort {
  const FrbWorkspacePort();

  @override
  Future<FeedConnection<ProjectDirectoryFrame>> openProjectDirectory() async {
    final connection = FrbProjectDirectoryConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<FeedConnection<AgentDirectoryFrame>> openAgentDirectory() async {
    final connection = FrbAgentDirectoryConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<ThreadDirectoryConnection> openThreadDirectory(
    ThreadDirectoryScope scope,
  ) async {
    final connection = FrbThreadDirectoryConnection(scope);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProjectDirectoryReadConnection> openProjectDirectoryRead(
    ProjectDirectoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbProjectDirectoryReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ThreadDirectoryReadConnection> openThreadDirectoryRead(
    ThreadDirectoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbThreadDirectoryReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<AgentDirectoryReadConnection> openAgentDirectoryRead(
    AgentDirectoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbAgentDirectoryReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbWorkspaceSourceStatusConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProjectRecord> openProject(String path) => invokeWorkspaceCommand(
    () => projects.openProject(path: path),
    projectRecordFromBridge,
  );

  @override
  Future<ProjectRecord> openRemoteProject(String alias, String path) =>
      invokeWorkspaceCommand(
        () => remote.openRemoteProject(alias: alias, path: path),
        projectRecordFromBridge,
      );

  @override
  Future<void> activateProject(String projectId) => invokeWorkspaceCommand(
    () => projects.activateProject(projectId: projectId),
    (_) {},
  );

  @override
  Future<ProjectRecord> renameProject(String projectId, String name) =>
      invokeWorkspaceCommand(
        () => projects.renameProject(projectId: projectId, name: name),
        (value) {
          final result = projectRecordFromBridge(value);
          if (result.id != projectId) {
            throw adapterProtocol('workspace-rename-project-target');
          }
          return result;
        },
      );

  @override
  Future<ProjectRecord> archiveProject(String projectId) =>
      invokeWorkspaceCommand(
        () => projects.archiveProject(projectId: projectId),
        (value) {
          // Native success returns Some(original). None is not a successor or a
          // no-op success and must not be filled from current directory state.
          if (value == null) {
            throw adapterProtocol('workspace-archive-project-result');
          }
          final result = projectRecordFromBridge(value);
          if (result.id != projectId) {
            throw adapterProtocol('workspace-archive-project-target');
          }
          return result;
        },
      );

  @override
  Future<WorkspaceThreadRecord> restoreThread(String threadId) =>
      invokeWorkspaceCommand(() => threads.restoreThread(threadId: threadId), (
        value,
      ) {
        final result = createdThreadFromBridge(value);
        if (result.id != threadId) {
          throw adapterProtocol('workspace-restore-thread-target');
        }
        return result;
      });

  @override
  Future<RenameThreadCommandReply> renameThread(
    String threadId,
    String title, {
    required OperationId operationId,
  }) => invokeWorkspaceCommand(
    () => threads.renameThread(
      operationId: operationId.value,
      threadId: threadId,
      title: title,
    ),
    (value) => renameThreadReplyFromBridge(value, threadId, operationId),
  );

  @override
  Future<ArchiveThreadCommandReply> archiveThread(
    String threadId, {
    required OperationId operationId,
  }) => invokeWorkspaceCommand(
    () => threads.archiveThread(
      operationId: operationId.value,
      threadId: threadId,
    ),
    (value) => archiveThreadReplyFromBridge(value, threadId, operationId),
  );
}
