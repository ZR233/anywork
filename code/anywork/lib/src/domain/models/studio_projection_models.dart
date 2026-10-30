import 'package:anywork_client/models.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'agent_workspace_view.dart';
import 'studio_state.dart';

part 'studio_projection_models.freezed.dart';

@freezed
abstract class ShellChromeView with _$ShellChromeView {
  const factory ShellChromeView({
    required List<StudioRecoveryIssue> applicationRecoveryIssues,
    required PersistenceStateSnapshot persistenceState,
  }) = _ShellChromeView;

  factory ShellChromeView.fromState(StudioState state) {
    return ShellChromeView(
      applicationRecoveryIssues: state.applicationRecoveryIssues,
      persistenceState: state.persistenceState,
    );
  }
}

@freezed
abstract class SidebarView with _$SidebarView {
  const SidebarView._();

  const factory SidebarView({
    required List<StudioProject> projects,
    required List<StudioThread> rootThreads,
    required String? selectedProjectId,
    required String? selectedRootThreadId,
    required bool isBusy,
    required Map<String, StudioRecoveryIssue> projectRecoveryIssues,
    required Map<String, StudioRecoveryIssue> threadRecoveryIssues,
    required Map<String, String> modeDisplayNames,
    @Default(false) bool directoryHasMore,
    @Default(false) bool directoryIsLoading,
  }) = _SidebarView;

  factory SidebarView.fromDirectories({
    required List<StudioProject> projects,
    required List<StudioThread> rootThreads,
    required String? selectedProjectId,
    required String? selectedRootThreadId,
    required bool isBusy,
    required List<StudioRecoveryIssue> recoveryIssues,
    required Map<String, String> modeDisplayNames,
    required bool directoryHasMore,
    required bool directoryIsLoading,
  }) {
    final projectRecoveryIssues = <String, StudioRecoveryIssue>{};
    for (final project in projects) {
      final issue = recoveryIssuesForTarget(
        recoveryIssues,
        workspaceId: project.id,
      ).firstOrNull;
      if (issue != null) projectRecoveryIssues[project.id] = issue;
    }
    final threadRecoveryIssues = <String, StudioRecoveryIssue>{};
    for (final thread in rootThreads) {
      final issue = recoveryIssuesForTarget(
        recoveryIssues,
        workspaceId: thread.workspaceId,
        threadId: thread.id,
      ).firstOrNull;
      if (issue != null) threadRecoveryIssues[thread.id] = issue;
    }
    return SidebarView(
      projects: projects,
      rootThreads: rootThreads,
      selectedProjectId: selectedProjectId,
      selectedRootThreadId: selectedRootThreadId,
      isBusy: isBusy,
      projectRecoveryIssues: projectRecoveryIssues,
      threadRecoveryIssues: threadRecoveryIssues,
      modeDisplayNames: modeDisplayNames,
      directoryHasMore: directoryHasMore,
      directoryIsLoading: directoryIsLoading,
    );
  }

  factory SidebarView.fromState(StudioState state) =>
      SidebarView.fromDirectories(
        projects: state.projects,
        rootThreads: state.rootThreads,
        selectedProjectId: state.selectedProjectId,
        selectedRootThreadId: state.selectedRootThread?.id,
        isBusy: state.isBusy,
        recoveryIssues: state.recoveryIssues,
        modeDisplayNames: {
          for (final mode in state.threadModeCatalog.modes)
            mode.id: mode.displayName,
        },
        directoryHasMore: state.threadDirectory.hasMore,
        directoryIsLoading: state.threadDirectory.isLoading,
      );
}

@freezed
abstract class HeaderView with _$HeaderView {
  const factory HeaderView({
    required StudioThread? selectedRootThread,
    required StudioProject? selectedProject,
    required String? selectedProjectId,
    required List<StudioThread> workspaceThreads,
    required List<StudioAgentView> agents,
    required String? selectedThreadId,
    required ThreadRuntimeView runtime,
    required SessionCostView? sessionCost,
    required List<PendingInteraction> pendingInteractions,
  }) = _HeaderView;

  factory HeaderView.fromState(StudioState state) {
    final root = state.selectedRootThread;
    final workspaceId = root?.workspaceId ?? state.selectedProjectId;
    StudioProject? selectedProject;
    for (final project in state.projects) {
      if (project.id == workspaceId) {
        selectedProject = project;
        break;
      }
    }
    return HeaderView(
      selectedRootThread: root,
      selectedProject: selectedProject,
      selectedProjectId: state.selectedProjectId,
      workspaceThreads: state.threadsForSelectedRoot,
      agents: state.selectedAgents,
      selectedThreadId: state.selectedThreadId,
      runtime: state.runtime,
      sessionCost: state.selectedSessionCost,
      pendingInteractions: state.pendingInteractions,
    );
  }
}

@freezed
abstract class StatusBarView with _$StatusBarView {
  const StatusBarView._();

  const factory StatusBarView({
    required StudioThread thread,
    required List<ModelSelectionAccount> accounts,
    required List<RoleSettingsView> roles,
    required bool isBusy,
    ThreadModelRouteView? modelRoute,
    WorkflowRunView? workflowRun,
    @Default(<String>[]) List<String> activeSkills,
    @Default(<String>[]) List<String> activeMcpServers,
    @Default(<String>[]) List<String> activeLspServers,
  }) = _StatusBarView;

  factory StatusBarView.fromWorkspace(AgentWorkspaceView workspace) {
    final runtime = workspace.runtime;
    return StatusBarView(
      thread: workspace.thread,
      accounts: workspace.accounts,
      roles: workspace.roles,
      isBusy: workspace.isBusy,
      modelRoute: runtime.modelRoute,
      workflowRun: runtime.workflow?.currentRun,
      activeSkills: runtime.activeSkills,
      activeMcpServers: runtime.activeMcpServers,
      activeLspServers: runtime.activeLspServers,
    );
  }
}
