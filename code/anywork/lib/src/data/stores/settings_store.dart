import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'domain_sync.dart';

part 'settings_store.g.dart';

/// 配置与模型目录进入同一条 merge path 的范围。
enum SettingsMergeScope { both, configOnly, catalogOnly }

/// 设置域：配置 revision 与模型目录 revision 独立比较。
///
/// 命令 in-flight 结果放在 [commands]，不写入 canonical 字段。
/// 未加载的时钟不会因为另一路快照夹带的水位而被标记为已消费。
@Riverpod(keepAlive: true)
class SettingsStore extends _$SettingsStore {
  @override
  SettingsStoreState build() => const SettingsStoreState();

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
  void applyProviderCatalog(ProviderCatalogView next) {
    if (state.providerCatalogLoaded &&
        next.revision == state.providerCatalogRevision) {
      return;
    }
    state = state.copyWith(
      providerCatalog: next,
      providerCatalogLoaded: true,
      providerCatalogRevision: next.revision,
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
    this.providerCatalog = const ProviderCatalogView.empty(),
    this.providerCatalogLoaded = false,
    this.providerCatalogRevision = '',
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
  final ProviderCatalogView providerCatalog;
  final bool providerCatalogLoaded;
  final String providerCatalogRevision;
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
    ProviderCatalogView? providerCatalog,
    bool? providerCatalogLoaded,
    String? providerCatalogRevision,
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
      providerCatalog: providerCatalog ?? this.providerCatalog,
      providerCatalogLoaded:
          providerCatalogLoaded ?? this.providerCatalogLoaded,
      providerCatalogRevision:
          providerCatalogRevision ?? this.providerCatalogRevision,
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
          providerCatalogLoaded == other.providerCatalogLoaded &&
          providerCatalogRevision == other.providerCatalogRevision &&
          identical(canonical, other.canonical) &&
          identical(agentProfiles, other.agentProfiles) &&
          identical(providerCatalog, other.providerCatalog) &&
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
    providerCatalogLoaded,
    providerCatalogRevision,
    identityHashCode(canonical),
    identityHashCode(agentProfiles),
    identityHashCode(providerCatalog),
    commandMapHash(commands),
  );
}

/// 配置水位前进只替换配置字段，目录水位前进只替换 provider 模型目录。
///
/// 配置水位与目录水位独立比较。未加载的一路不会被另一路快照夹带的水位标记为已消费。
SettingsStoreState mergeSettingsState(
  SettingsStoreState current,
  SettingsStateSnapshot incoming, {
  SettingsMergeScope scope = SettingsMergeScope.both,
}) {
  final incomingData = incoming.state.value;
  if (incomingData == null) return current;
  final takeConfig =
      scope != SettingsMergeScope.catalogOnly &&
      (!current.configLoaded || incoming.revision > current.settingsRevision);
  final takeCatalog =
      scope != SettingsMergeScope.configOnly &&
      (!current.catalogLoaded ||
          incoming.modelCatalogRevision > current.modelCatalogRevision);
  if (!takeConfig && !takeCatalog) return current;

  final previousData = current.canonical?.state.value ?? incomingData;
  final configData = takeConfig ? incomingData : previousData;
  final catalogData = takeCatalog ? incomingData : previousData;
  final settingsRevision = takeConfig
      ? incoming.revision
      : current.settingsRevision;
  final catalogRevision = takeCatalog
      ? incoming.modelCatalogRevision
      : current.modelCatalogRevision;
  return current.copyWith(
    canonical: projectSettingsSnapshot(
      configData: configData,
      catalogData: catalogData,
      settingsRevision: settingsRevision,
      modelCatalogRevision: catalogRevision,
    ),
    configLoaded: current.configLoaded || takeConfig,
    catalogLoaded: current.catalogLoaded || takeCatalog,
    settingsRevision: settingsRevision,
    modelCatalogRevision: catalogRevision,
    configSync: takeConfig
        ? current.configSync.connected()
        : current.configSync,
    catalogSync: takeCatalog
        ? current.catalogSync.connected()
        : current.catalogSync,
  );
}

SettingsStateSnapshot projectSettingsSnapshot({
  required SettingsStateData configData,
  required SettingsStateData catalogData,
  required int settingsRevision,
  required int modelCatalogRevision,
}) {
  final catalogByProvider = {
    for (final provider in catalogData.providers) provider.id: provider,
  };
  final providers = [
    for (final provider in configData.providers)
      if (catalogByProvider[provider.id] case final catalogProvider?)
        provider.copyWith(
          models: catalogProvider.models,
          modelCatalog: catalogProvider.modelCatalog,
        )
      else
        provider,
  ];
  return SettingsStateSnapshot(
    providers: providers,
    defaultProviderId: configData.defaultProviderId,
    modeModelRoutes: configData.modeModelRoutes,
    roles: configData.roles,
    mcpServers: configData.mcpServers,
    instructions: configData.instructions,
    skills: configData.skills,
    general: configData.general,
    webSearch: configData.webSearch,
    deepSeekWebSearch: configData.deepSeekWebSearch,
    permissionMode: configData.permissionMode,
    revision: settingsRevision,
    modelCatalogRevision: modelCatalogRevision,
  );
}
