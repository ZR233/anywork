import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import '../domain/directory_values.dart';
import '../domain/selection.dart';
import '../domain/workspace_repository.dart';
import 'workspace_access.dart';
import 'workspace_archive_capture_port.dart';
import 'workspace_archive_work.dart';
import 'workspace_commands.dart';
import 'workspace_directories.dart';
import 'workspace_mutations.dart';
import 'workspace_port.dart';
import 'workspace_selection_owner.dart';
import 'workspace_selection_port.dart';

/// Pure Dart construction only. Native sources open on explicit domain demand
/// after the application's RuntimeReady boundary, never while wiring the graph.
({
  WorkspaceRepository repository,
  WorkspaceSubmissionSelection submissionSelection,
})
createWorkspaceRepository({
  required WorkspacePort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
  required ReadonlyLatestValue<RecoveryState> recovery,
  required WorkspaceArchiveCapturePort archiveCapture,
}) {
  final owner = _WorkspaceRepository(
    port,
    budget,
    operations,
    recovery,
    archiveCapture,
  );
  return (repository: owner, submissionSelection: owner);
}

final class _WorkspaceRepository
    implements WorkspaceRepository, WorkspaceSubmissionSelection {
  _WorkspaceRepository(
    WorkspacePort port,
    ResourceBudget budget,
    OperationRecorder operations,
    ReadonlyLatestValue<RecoveryState> recovery,
    WorkspaceArchiveCapturePort capture,
  ) {
    directories = WorkspaceDirectories(port, budget, operations);
    final commands = WorkspaceCommands(directories.lifetime, operations);
    final access = WorkspaceAccess(recovery);
    selection = WorkspaceSelectionOwner(directories, commands, access);
    mutations = WorkspaceMutations(directories, commands, access);
    archives = WorkspaceArchives(
      directories,
      commands,
      selection,
      access,
      capture,
    );
    // No feed capture/start, library initialization or external archive callback.
  }
  late final WorkspaceDirectories directories;
  late final WorkspaceSelectionOwner selection;
  late final WorkspaceMutations mutations;
  late final WorkspaceArchives archives;

  @override
  ReadonlyLatestValue<WorkspaceState> get state => selection.source.readonly;
  @override
  ReadonlyLatestValue<ProjectDirectoryState> get projects =>
      directories.projects.source.readonly;
  @override
  ReadonlyLatestValue<AgentDirectoryState> get agents =>
      directories.agents.source.readonly;
  @override
  Future<void> loadProjectsPage({int limit = 32}) =>
      directories.projectReads.page(limit: limit);
  @override
  Future<void> loadAgentsPage({int limit = 32}) =>
      directories.agentReads.page(limit: limit);
  @override
  Future<void> loadAgents() => directories.agentReads.complete();
  @override
  Future<void> loadProjectSourceStatus() =>
      directories.projectReads.sourceStatus();
  @override
  Future<void> loadAgentSourceStatus() => directories.agentReads.sourceStatus();
  @override
  ThreadDirectoryQuery queryThreads(DirectoryQuery query) =>
      directories.query(query);
  @override
  ThreadMetadata thread(String threadId) => directories.metadata(threadId);
  @override
  Future<ProjectRecord> readProject(String projectId) =>
      directories.readProject(projectId);
  @override
  Future<WorkspaceThreadRecord> readThread(String threadId) =>
      directories.readThread(threadId);
  @override
  WorkspaceOpenBatch openProject(String path) => selection.opening.local(path);
  @override
  WorkspaceOpenBatch openRemoteProject(
    String alias,
    String path, {
    String? name,
  }) => selection.opening.remote(alias, path, name: name);
  @override
  OperationTicket<WorkspaceSelectionResult> selectProject(String projectId) =>
      selection.selectProject(projectId);
  @override
  OperationTicket<WorkspaceSelectionResult> selectThread(String threadId) =>
      selection.selectThread(threadId);
  @override
  OperationTicket<WorkspaceSelectionResult> selectAgentThread(
    String threadId,
  ) => selection.selectAgentThread(threadId);
  @override
  WorkspaceSelectionResult restoreSelection(WorkspaceSelection value) =>
      selection.restoreSelection(value);
  @override
  OperationTicket<WorkspaceSelectionResult> openSelectedThread(
    String threadId,
  ) => selection.openSelectedThread(threadId);
  @override
  OperationTicket<WorkspaceSelectionResult> beginNewThread(String projectId) =>
      selection.beginNewThread(projectId);
  @override
  OperationTicket<WorkspaceSelectionResult> restoreThread(String threadId) =>
      selection.restoreThread(threadId);
  @override
  OperationTicket<ProjectRecord> renameProject(String projectId, String name) =>
      mutations.renameProject(projectId, name);
  @override
  OperationTicket<Unit> archiveProject(String projectId) =>
      archives.project(projectId);
  @override
  OperationTicket<WorkspaceThreadRecord> renameThread(
    String threadId,
    String title,
  ) => mutations.renameThread(threadId, title);
  @override
  OperationTicket<ArchiveThreadResult> archiveThread(String threadId) =>
      archives.thread(threadId);
  @override
  WorkspaceIntentStamp capture(String projectId) =>
      selection.capture(projectId);
  @override
  bool adoptCreatedThread(
    WorkspaceThreadRecord thread,
    WorkspaceIntentStamp expected,
  ) => selection.adoptCreatedThread(thread, expected);
  @override
  void seal() => directories.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) =>
      selection.close(deadline: deadline);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      selection.close(deadline: deadline, retry: true);
}
