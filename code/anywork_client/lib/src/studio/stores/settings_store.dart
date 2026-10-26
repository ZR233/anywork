import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';

/// General settings and routes only. Account configuration, effective catalogs,
/// usage and ACP operation facts have independent domain owners.
class SettingsStore extends ReadModel<SettingsStoreState> {
  SettingsStore() : super(const SettingsStoreState());

  void resetForOwner() {
    state = const SettingsStoreState();
  }

  void merge(
    SettingsStateSnapshot incoming, {
    SettingsMergeScope scope = SettingsMergeScope.both,
  }) {
    if (scope == SettingsMergeScope.catalogOnly) return;
    state = mergeSettingsState(state, incoming, scope: scope);
  }

  void applyAgentProfiles(AgentProfilesStateView next) {
    if (state.agentProfilesLoaded &&
        next.revision <= state.agentProfilesRevision)
      return;
    state = state.copyWith(
      agentProfiles: next,
      agentProfilesLoaded: true,
      agentProfilesRevision: next.revision,
      agentProfilesSync: state.agentProfilesSync.connected(),
    );
  }

  void applyConfigTransport(DomainSyncStatus sync) {
    if (sync != state.configSync) state = state.copyWith(configSync: sync);
  }

  void applyAgentProfilesTransport(DomainSyncStatus sync) {
    if (sync != state.agentProfilesSync)
      state = state.copyWith(agentProfilesSync: sync);
  }

  void beginCommand(String key, CommandTarget target) => _putCommand(
    CommandStatus(key: key, phase: CommandPhase.pending, target: target),
  );
  void failCommand(String key, StudioFailure error, {CommandTarget? target}) =>
      _putCommand(
        CommandStatus(
          key: key,
          phase: CommandPhase.failed,
          target:
              target ?? state.commands[key]?.target ?? const CommandTarget(),
          error: error,
        ),
      );
  void clearCommand(String key) {
    if (state.commands.containsKey(key))
      state = state.copyWith(commands: {...state.commands}..remove(key));
  }

  void _putCommand(CommandStatus status) {
    final commands = {...state.commands, status.key: status};
    if (!commandMapsEqual(commands, state.commands))
      state = state.copyWith(commands: commands);
  }
}

class SettingsStoreState {
  const SettingsStoreState({
    this.canonical,
    this.configLoaded = false,
    this.settingsRevision = 0,
    this.configSync = const DomainSyncStatus(),
    this.agentProfiles,
    this.agentProfilesLoaded = false,
    this.agentProfilesRevision = 0,
    this.agentProfilesSync = const DomainSyncStatus(),
    this.commands = const {},
  });
  final SettingsStateSnapshot? canonical;
  final bool configLoaded;
  final int settingsRevision;
  final DomainSyncStatus configSync;
  final AgentProfilesStateView? agentProfiles;
  final bool agentProfilesLoaded;
  final int agentProfilesRevision;
  final DomainSyncStatus agentProfilesSync;
  final Map<String, CommandStatus> commands;
  bool get loaded => canonical != null;

  SettingsStoreState copyWith({
    SettingsStateSnapshot? canonical,
    bool? configLoaded,
    int? settingsRevision,
    DomainSyncStatus? configSync,
    AgentProfilesStateView? agentProfiles,
    bool? agentProfilesLoaded,
    int? agentProfilesRevision,
    DomainSyncStatus? agentProfilesSync,
    Map<String, CommandStatus>? commands,
  }) => SettingsStoreState(
    canonical: canonical ?? this.canonical,
    configLoaded: configLoaded ?? this.configLoaded,
    settingsRevision: settingsRevision ?? this.settingsRevision,
    configSync: configSync ?? this.configSync,
    agentProfiles: agentProfiles ?? this.agentProfiles,
    agentProfilesLoaded: agentProfilesLoaded ?? this.agentProfilesLoaded,
    agentProfilesRevision: agentProfilesRevision ?? this.agentProfilesRevision,
    agentProfilesSync: agentProfilesSync ?? this.agentProfilesSync,
    commands: commands ?? this.commands,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsStoreState &&
          configLoaded == other.configLoaded &&
          settingsRevision == other.settingsRevision &&
          configSync == other.configSync &&
          agentProfilesLoaded == other.agentProfilesLoaded &&
          agentProfilesRevision == other.agentProfilesRevision &&
          agentProfilesSync == other.agentProfilesSync &&
          identical(canonical, other.canonical) &&
          identical(agentProfiles, other.agentProfiles) &&
          commandMapsEqual(commands, other.commands);
  @override
  int get hashCode => Object.hash(
    configLoaded,
    settingsRevision,
    configSync,
    agentProfilesLoaded,
    agentProfilesRevision,
    agentProfilesSync,
    identityHashCode(canonical),
    identityHashCode(agentProfiles),
    commandMapHash(commands),
  );
}

SettingsStoreState mergeSettingsState(
  SettingsStoreState current,
  SettingsStateSnapshot incoming, {
  SettingsMergeScope scope = SettingsMergeScope.both,
}) {
  if (scope == SettingsMergeScope.catalogOnly ||
      incoming.state.value == null ||
      current.configLoaded && incoming.revision <= current.settingsRevision)
    return current;
  final data = incoming.state.value!;
  // The transport reply may legitimately contain several domains. Only this
  // slice is retained here; routing consumes account content independently.
  final canonical = SettingsStateSnapshot(
    revision: incoming.revision,
    modeModelRoutes: data.modeModelRoutes,
    roles: data.roles,
    mcpServers: data.mcpServers,
    instructions: data.instructions,
    skills: data.skills,
    general: data.general,
    delegation: data.delegation,
    webSearch: data.webSearch,
    deepSeekWebSearch: data.deepSeekWebSearch,
    permissionMode: data.permissionMode,
  );
  return current.copyWith(
    canonical: canonical,
    configLoaded: true,
    settingsRevision: incoming.revision,
    configSync: current.configSync.connected(),
  );
}
