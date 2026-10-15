import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';

class ProjectStore extends ReadModel<ProjectStoreState> {
  ProjectStore() : super(const ProjectStoreState());

  bool applyProjectDirectory(ProjectDirectoryState next) {
    if (state.projectsLoaded && next.revision <= state.projectRevision) {
      return false;
    }
    state = state.copyWith(
      projects: next,
      projectSync: state.projectSync.connected(),
    );
    return true;
  }

  bool applyAgentDirectory(AgentDirectoryState next) {
    if (state.agentsLoaded && next.revision <= state.agentRevision) {
      return false;
    }
    state = state.copyWith(
      agents: next,
      agentSync: state.agentSync.connected(),
    );
    return true;
  }

  void applyProjectTransport(DomainSyncStatus sync) {
    if (sync == state.projectSync) return;
    state = state.copyWith(projectSync: sync);
  }

  void applyAgentTransport(DomainSyncStatus sync) {
    if (sync == state.agentSync) return;
    state = state.copyWith(agentSync: sync);
  }
}

class ProjectStoreState {
  const ProjectStoreState({
    this.projects,
    this.agents,
    this.projectSync = const DomainSyncStatus(),
    this.agentSync = const DomainSyncStatus(),
  });

  final ProjectDirectoryState? projects;
  final AgentDirectoryState? agents;
  final DomainSyncStatus projectSync;
  final DomainSyncStatus agentSync;

  bool get projectsLoaded => projects != null;
  bool get agentsLoaded => agents != null;
  int get projectRevision => projects?.revision ?? 0;
  int get agentRevision => agents?.revision ?? 0;

  ProjectStoreState copyWith({
    ProjectDirectoryState? projects,
    AgentDirectoryState? agents,
    DomainSyncStatus? projectSync,
    DomainSyncStatus? agentSync,
  }) {
    return ProjectStoreState(
      projects: projects ?? this.projects,
      agents: agents ?? this.agents,
      projectSync: projectSync ?? this.projectSync,
      agentSync: agentSync ?? this.agentSync,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectStoreState &&
          projectRevision == other.projectRevision &&
          agentRevision == other.agentRevision &&
          projectsLoaded == other.projectsLoaded &&
          agentsLoaded == other.agentsLoaded &&
          projectSync == other.projectSync &&
          agentSync == other.agentSync &&
          identical(projects, other.projects) &&
          identical(agents, other.agents);

  @override
  int get hashCode => Object.hash(
    projectRevision,
    agentRevision,
    projectsLoaded,
    agentsLoaded,
    projectSync,
    agentSync,
    identityHashCode(projects),
    identityHashCode(agents),
  );
}
