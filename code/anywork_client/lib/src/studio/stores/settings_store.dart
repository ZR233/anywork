import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';

class SettingsStore extends ReadModel<SettingsStoreState> {
  SettingsStore() : super(const SettingsStoreState());

  /// topic 帧、baseline 与命令响应的唯一入口。
  void merge(
    SettingsStateSnapshot incoming, {
    SettingsMergeScope scope = SettingsMergeScope.both,
  }) {
    state = mergeSettingsState(state, incoming, scope: scope);
  }

  void applyAgentProfiles(AgentProfilesStateView next) {
    if (state.agentProfilesLoaded &&
        next.revision <= state.agentProfilesRevision) {
      return;
    }
    state = state.copyWith(
      agentProfiles: next,
      agentProfilesLoaded: true,
      agentProfilesRevision: next.revision,
      agentProfilesSync: state.agentProfilesSync.connected(),
    );
  }

  /// 静态供应商目录的字符串 revision 不是配置/目录 int 时钟。
  /// 只用于幂等丢弃同一次目录加载，不参与双时钟比较。
  void applyAccountCatalog(AccountCatalogView next) {
    if (!next.isUsable) return;
    if (state.accountCatalogLoaded &&
        next.revision == state.accountCatalogRevision) {
      return;
    }
    state = state.copyWith(
      accountCatalog: next,
      accountCatalogLoaded: true,
      accountCatalogRevision: next.revision,
    );
  }

  void applyConfigTransport(DomainSyncStatus sync) {
    if (sync == state.configSync) return;
    state = state.copyWith(configSync: sync);
  }

  void applyCatalogTransport(DomainSyncStatus sync) {
    if (sync == state.catalogSync) return;
    state = state.copyWith(catalogSync: sync);
  }

  void applyAgentProfilesTransport(DomainSyncStatus sync) {
    if (sync == state.agentProfilesSync) return;
    state = state.copyWith(agentProfilesSync: sync);
  }

  void beginCommand(String key, CommandTarget target) {
    _putCommand(
      CommandStatus(key: key, phase: CommandPhase.pending, target: target),
    );
  }

  void failCommand(String key, StudioFailure error, {CommandTarget? target}) {
    final existing = state.commands[key];
    _putCommand(
      CommandStatus(
        key: key,
        phase: CommandPhase.failed,
        target: target ?? existing?.target ?? const CommandTarget(),
        error: error,
      ),
    );
  }

  /// 成功后 canonical 已由响应写入；清掉 in-flight，显示回到 canonical。
  void clearCommand(String key) {
    if (!state.commands.containsKey(key)) return;
    state = state.copyWith(commands: {...state.commands}..remove(key));
  }

  void _putCommand(CommandStatus status) {
    final commands = {...state.commands, status.key: status};
    if (commandMapsEqual(commands, state.commands)) return;
    state = state.copyWith(commands: commands);
  }
}

class SettingsStoreState {
  const SettingsStoreState({
    this.canonical,
    this.configLoaded = false,
    this.catalogLoaded = false,
    this.settingsRevision = 0,
    this.modelCatalogRevision = 0,
    this.configSync = const DomainSyncStatus(),
    this.catalogSync = const DomainSyncStatus(),
    this.agentProfiles,
    this.agentProfilesLoaded = false,
    this.agentProfilesRevision = 0,
    this.agentProfilesSync = const DomainSyncStatus(),
    this.accountCatalog = const AccountCatalogView.empty(),
    this.accountCatalogLoaded = false,
    this.accountCatalogRevision = '',
    this.commands = const {},
  });

  final SettingsStateSnapshot? canonical;
  final bool configLoaded;
  final bool catalogLoaded;
  final int settingsRevision;
  final int modelCatalogRevision;
  final DomainSyncStatus configSync;
  final DomainSyncStatus catalogSync;
  final AgentProfilesStateView? agentProfiles;
  final bool agentProfilesLoaded;
  final int agentProfilesRevision;
  final DomainSyncStatus agentProfilesSync;
  final AccountCatalogView accountCatalog;
  final bool accountCatalogLoaded;
  final String accountCatalogRevision;
  final Map<String, CommandStatus> commands;

  bool get loaded => canonical != null;

  SettingsStoreState copyWith({
    SettingsStateSnapshot? canonical,
    bool? configLoaded,
    bool? catalogLoaded,
    int? settingsRevision,
    int? modelCatalogRevision,
    DomainSyncStatus? configSync,
    DomainSyncStatus? catalogSync,
    AgentProfilesStateView? agentProfiles,
    bool? agentProfilesLoaded,
    int? agentProfilesRevision,
    DomainSyncStatus? agentProfilesSync,
    AccountCatalogView? accountCatalog,
    bool? accountCatalogLoaded,
    String? accountCatalogRevision,
    Map<String, CommandStatus>? commands,
  }) {
    return SettingsStoreState(
      canonical: canonical ?? this.canonical,
      configLoaded: configLoaded ?? this.configLoaded,
      catalogLoaded: catalogLoaded ?? this.catalogLoaded,
      settingsRevision: settingsRevision ?? this.settingsRevision,
      modelCatalogRevision: modelCatalogRevision ?? this.modelCatalogRevision,
      configSync: configSync ?? this.configSync,
      catalogSync: catalogSync ?? this.catalogSync,
      agentProfiles: agentProfiles ?? this.agentProfiles,
      agentProfilesLoaded: agentProfilesLoaded ?? this.agentProfilesLoaded,
      agentProfilesRevision:
          agentProfilesRevision ?? this.agentProfilesRevision,
      agentProfilesSync: agentProfilesSync ?? this.agentProfilesSync,
      accountCatalog: accountCatalog ?? this.accountCatalog,
      accountCatalogLoaded: accountCatalogLoaded ?? this.accountCatalogLoaded,
      accountCatalogRevision:
          accountCatalogRevision ?? this.accountCatalogRevision,
      commands: commands ?? this.commands,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsStoreState &&
          configLoaded == other.configLoaded &&
          catalogLoaded == other.catalogLoaded &&
          settingsRevision == other.settingsRevision &&
          modelCatalogRevision == other.modelCatalogRevision &&
          configSync == other.configSync &&
          catalogSync == other.catalogSync &&
          agentProfilesLoaded == other.agentProfilesLoaded &&
          agentProfilesRevision == other.agentProfilesRevision &&
          agentProfilesSync == other.agentProfilesSync &&
          accountCatalogLoaded == other.accountCatalogLoaded &&
          accountCatalogRevision == other.accountCatalogRevision &&
          identical(canonical, other.canonical) &&
          identical(agentProfiles, other.agentProfiles) &&
          identical(accountCatalog, other.accountCatalog) &&
          commandMapsEqual(commands, other.commands);

  @override
  int get hashCode => Object.hash(
    configLoaded,
    catalogLoaded,
    settingsRevision,
    modelCatalogRevision,
    configSync,
    catalogSync,
    agentProfilesLoaded,
    agentProfilesRevision,
    agentProfilesSync,
    accountCatalogLoaded,
    accountCatalogRevision,
    identityHashCode(canonical),
    identityHashCode(agentProfiles),
    identityHashCode(accountCatalog),
    commandMapHash(commands),
  );
}

/// 配置水位前进只替换配置字段，目录水位前进只替换 account 模型目录。
///
/// 配置水位与目录水位独立比较。未加载的一路不会被另一路快照夹带的水位标记为已消费。
SettingsStoreState mergeSettingsState(
  SettingsStoreState current,
  SettingsStateSnapshot incoming, {
  SettingsMergeScope scope = SettingsMergeScope.both,
}) {
  final projection = mergeSettingsProjection(
    SettingsProjectionState(
      canonical: current.canonical,
      configLoaded: current.configLoaded,
      catalogLoaded: current.catalogLoaded,
      settingsRevision: current.settingsRevision,
      modelCatalogRevision: current.modelCatalogRevision,
    ),
    incoming,
    scope: scope,
  );
  if (identical(projection.canonical, current.canonical) &&
      projection.configLoaded == current.configLoaded &&
      projection.catalogLoaded == current.catalogLoaded &&
      projection.settingsRevision == current.settingsRevision &&
      projection.modelCatalogRevision == current.modelCatalogRevision) {
    return current;
  }
  final takeConfig =
      projection.configLoaded != current.configLoaded ||
      projection.settingsRevision != current.settingsRevision;
  final takeCatalog =
      projection.catalogLoaded != current.catalogLoaded ||
      projection.modelCatalogRevision != current.modelCatalogRevision;
  return current.copyWith(
    canonical: projection.canonical,
    configLoaded: projection.configLoaded,
    catalogLoaded: projection.catalogLoaded,
    settingsRevision: projection.settingsRevision,
    modelCatalogRevision: projection.modelCatalogRevision,
    configSync: takeConfig
        ? current.configSync.connected()
        : current.configSync,
    catalogSync: takeCatalog
        ? current.catalogSync.connected()
        : current.catalogSync,
  );
}
