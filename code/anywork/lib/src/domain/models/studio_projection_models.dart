import 'package:anywork_client/models.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

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
    required List<String> projectIds,
    required String? standaloneProjectId,
    required String? selectedProjectId,
  }) = _SidebarView;

  factory SidebarView.fromProjects({
    required List<StudioProject> projects,
    required String? selectedProjectId,
  }) {
    return SidebarView(
      projectIds: [for (final project in projects) project.id],
      standaloneProjectId: projects
          .where((project) => project.isStandalone)
          .firstOrNull
          ?.id,
      selectedProjectId: selectedProjectId,
    );
  }
}

@freezed
abstract class HeaderView with _$HeaderView {
  const factory HeaderView({
    required SessionDirectoryRow? selectedRootRow,
    required StudioProject? selectedProject,
    required String? selectedProjectId,
    required List<SessionDirectoryRow> workspaceRows,
    required List<StudioAgentView> agents,
    required String? selectedThreadId,
    required ThreadRuntimeView runtime,
    required SessionCostView? sessionCost,
    required List<PendingInteraction> pendingInteractions,
  }) = _HeaderView;

  factory HeaderView.fromState(StudioState state) {
    final root = state.selectedRootRow;
    final workspaceId = root?.workspaceId ?? state.selectedProjectId;
    StudioProject? selectedProject;
    for (final project in state.projects) {
      if (project.id == workspaceId) {
        selectedProject = project;
        break;
      }
    }
    return HeaderView(
      selectedRootRow: root,
      selectedProject: selectedProject,
      selectedProjectId: state.selectedProjectId,
      workspaceRows: state.rowsForSelectedSession,
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
    required SessionDirectoryRow row,
    required List<ModelSelectionAccount> accounts,
    required List<RoleSettingsView> roles,
    required bool isBusy,
    ThreadModelRouteView? modelRoute,
    WorkflowRunView? workflowRun,
  }) = _StatusBarView;
}
