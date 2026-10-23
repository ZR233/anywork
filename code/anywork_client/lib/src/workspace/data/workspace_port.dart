import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import '../domain/directory_values.dart';
import 'agent_directory_frames.dart';
import 'directory_reads.dart';
import 'project_directory_frames.dart';
import 'thread_directory_frames.dart';
import 'workspace_command_replies.dart';

abstract interface class WorkspacePort {
  Future<FeedConnection<ProjectDirectoryFrame>> openProjectDirectory();
  Future<FeedConnection<AgentDirectoryFrame>> openAgentDirectory();
  Future<ThreadDirectoryConnection> openThreadDirectory(ThreadDirectoryScope scope);
  Future<ProjectDirectoryReadConnection> openProjectDirectoryRead(ProjectDirectoryReadRef reference,
    {required ProductReadOrigin origin});
  Future<ThreadDirectoryReadConnection> openThreadDirectoryRead(ThreadDirectoryReadRef reference,
    {required ProductReadOrigin origin});
  Future<AgentDirectoryReadConnection> openAgentDirectoryRead(AgentDirectoryReadRef reference,
    {required ProductReadOrigin origin});
  Future<ProductSourceStatusReadConnection> openSourceStatus(ProductSourceStatusRef reference,
    {required ProductReadOrigin origin});
  Future<ProjectRecord> openProject(String path);
  Future<ProjectRecord> openRemoteProject(String alias, String path);
  Future<void> activateProject(String projectId);
  Future<ProjectRecord> renameProject(String projectId, String name);
  Future<ProjectRecord> archiveProject(String projectId);
  Future<WorkspaceThreadRecord> restoreThread(String threadId);
  Future<RenameThreadCommandReply> renameThread(String threadId, String title,
    {required OperationId operationId});
  Future<ArchiveThreadCommandReply> archiveThread(String threadId, {required OperationId operationId});
}

/// Owns the original backend frontier. Immutable read scopes cannot extend it.
abstract interface class ThreadDirectoryConnection implements FeedConnection<ThreadDirectoryFrame> {
  Future<ThreadDirectoryReadTarget> extendWindow(ProductCollectionRef expectedCollection, {int limit = 32});
}

abstract interface class ProjectDirectoryReadConnection {
  Future<ProjectDirectoryReadHeader> header();
  Future<ProjectDirectoryEntryPage> entries({int offset = 0, int limit = 32});
  Future<ProjectDirectoryEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupProject(String projectId);
  Future<ProjectRecordReadPage> projects(int listId, {int offset = 0, int limit = 32});
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class ThreadDirectoryReadConnection {
  Future<ThreadDirectoryReadHeader> header();
  Future<ThreadDirectoryEntryPage> entries({String? cursor, int limit = 32});
  Future<ThreadDirectoryEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupThread(String threadId);
  Future<WorkspaceThreadRecordReadPage> threads(int listId, {int offset = 0, int limit = 32});
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class AgentDirectoryReadConnection {
  Future<AgentDirectoryReadHeader> header();
  Future<AgentDirectoryEntryPage> entries({int offset = 0, int limit = 32});
  Future<AgentDirectoryEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupAgent(String agentId);
  Future<AgentDirectoryEntryReadPage> agents(int listId, {int offset = 0, int limit = 32});
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
