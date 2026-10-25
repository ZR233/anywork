import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'directory_state.dart';
import 'directory_values.dart';
import 'selection.dart';

abstract interface class WorkspaceRepository {
  ReadonlyLatestValue<WorkspaceState> get state;
  ReadonlyLatestValue<ProjectDirectoryState> get projects;
  ReadonlyLatestValue<AgentDirectoryState> get agents;
  Future<void> loadProjectsPage({int limit = 32});
  Future<void> loadAgentsPage({int limit = 32});

  /// Reads metadata in bounded pages, never activates cold member Sessions.
  Future<void> loadAgents();
  Future<void> loadProjectSourceStatus();
  Future<void> loadAgentSourceStatus();
  ThreadDirectoryQuery queryThreads(DirectoryQuery query);
  ThreadMetadata thread(String threadId);
  Future<ProjectRecord> readProject(String projectId);
  Future<WorkspaceThreadRecord> readThread(String threadId);
  WorkspaceOpenBatch openProject(String path);
  WorkspaceOpenBatch openRemoteProject(
    String alias,
    String path, {
    String? name,
  });
  OperationTicket<WorkspaceSelectionResult> selectProject(String projectId);
  OperationTicket<WorkspaceSelectionResult> selectThread(String threadId);
  OperationTicket<WorkspaceSelectionResult> selectAgentThread(String threadId);

  /// Restores only selection, synchronously and without an operation/receipt.
  /// A Thread becomes pending-open regardless of the input's [WorkspaceSelection.needsOpen].
  /// Project-only/empty selections remain without a pending Thread. Invalid
  /// combinations and sealed owners throw the usual typed [StudioFailure].
  WorkspaceSelectionResult restoreSelection(WorkspaceSelection selection);
  OperationTicket<WorkspaceSelectionResult> openSelectedThread(String threadId);
  OperationTicket<WorkspaceSelectionResult> beginNewThread(String projectId);
  OperationTicket<WorkspaceSelectionResult> restoreThread(String threadId);
  OperationTicket<ProjectRecord> renameProject(String projectId, String name);
  OperationTicket<Unit> archiveProject(String projectId);
  OperationTicket<WorkspaceThreadRecord> renameThread(
    String threadId,
    String title,
  );
  OperationTicket<ArchiveThreadResult> archiveThread(String threadId);
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

/// A read-only directory demand. It neither activates nor owns a Thread Session.
abstract interface class ThreadDirectoryQuery {
  DirectoryQuery get query;
  ReadonlyLatestValue<ThreadDirectoryState> get state;
  Future<void> loadMore();
  Future<void> retry();
  void requestClose();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

abstract interface class ThreadMetadata {
  String get threadId;
  ReadonlyLatestValue<ThreadMetadataState> get state;
  Future<void> retry();
  void requestClose();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
