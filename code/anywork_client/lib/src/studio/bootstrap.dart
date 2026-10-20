import '../../models.dart';

enum StudioBootstrapPhase { idle, loading, ready, failed }

/// Application-owned startup status, including failures before any domain has
/// received a baseline. It does not stand in for those domains' revisions.
final class StudioBootstrapState {
  const StudioBootstrapState({
    this.phase = StudioBootstrapPhase.idle,
    this.failure,
  });

  final StudioBootstrapPhase phase;
  final StudioFailure? failure;
}

/// One-time startup facts; never used as mutation-success compensation.
class StudioBootstrap {
  const StudioBootstrap({
    required this.ownerEpoch,
    required this.projectDirectory,
    required this.threadDirectory,
    required this.agentDirectory,
    required this.settingsState,
    required this.recoveryState,
    required this.mcpState,
    required this.lspState,
    required this.skillsByProject,
    required this.threadModeCatalog,
    required this.accountUsageState,
    required this.modelPerformance,
    required this.updaterState,
    required this.persistenceState,
    this.persistenceQueueState,
    this.agentProfilesState,
    this.sessionCostsByRoot = const {},
    this.selectedProjectId,
    this.selectedThreadId,
  });
  final String ownerEpoch;
  final ProjectDirectoryState projectDirectory;
  final ThreadDirectoryWindow threadDirectory;
  final AgentDirectoryState agentDirectory;
  final SettingsStateSnapshot settingsState;
  final RecoveryStateSnapshot recoveryState;
  final McpStateSnapshot mcpState;
  final LspStateSnapshot lspState;
  final Map<String, SkillsStateSnapshot> skillsByProject;
  final ThreadModeCatalogView threadModeCatalog;
  final AccountUsageStateSnapshot accountUsageState;
  final ModelPerformanceSnapshotView modelPerformance;
  final UpdaterStateSnapshot updaterState;
  final PersistenceStateSnapshot persistenceState;
  final PersistenceQueueStateView? persistenceQueueState;
  final AgentProfilesStateView? agentProfilesState;
  final Map<String, SessionCostsStateView> sessionCostsByRoot;
  final String? selectedProjectId;
  final String? selectedThreadId;
}
