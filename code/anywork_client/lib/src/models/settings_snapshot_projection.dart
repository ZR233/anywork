import 'account_models.dart';
import 'studio_state_snapshots.dart';

/// 配置与模型目录进入同一条 merge path 的范围。
enum SettingsMergeScope { both, configOnly, catalogOnly }

/// 设置快照的纯投影状态。
///
/// 该类型只保存配置与模型目录的 canonical 值和各自水位，不携带数据源、
/// 同步传输或命令状态，因此 FRB 转换器和 SettingsStore 可以共享同一套
/// 双时钟合并语义。
class SettingsProjectionState {
  const SettingsProjectionState({
    this.canonical,
    this.configLoaded = false,
    this.catalogLoaded = false,
    this.settingsRevision = 0,
    this.modelCatalogRevision = 0,
  });

  final SettingsStateSnapshot? canonical;
  final bool configLoaded;
  final bool catalogLoaded;
  final int settingsRevision;
  final int modelCatalogRevision;
}

/// 按独立 revision 合并配置与模型目录。
///
/// 未加载的一路不会因为另一路快照夹带的水位而被标记为已消费；旧快照和
/// 幂等快照都会原样返回当前投影。
SettingsProjectionState mergeSettingsProjection(
  SettingsProjectionState current,
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
  return SettingsProjectionState(
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
  );
}

Map<String, AccountModelAutoCompactView> _projectAutoCompactLimits(
  AccountSettingsView configProvider,
  AccountSettingsView catalogProvider,
) {
  final projected = <String, AccountModelAutoCompactView>{
    for (final model in catalogProvider.models)
      model.modelId: AccountModelAutoCompactView.forModel(model)
          .withStoredOverride(
            configProvider.autoCompactLimits[model.modelId]?.overrideLimit,
          ),
  };
  for (final entry in configProvider.autoCompactLimits.entries) {
    if (projected.containsKey(entry.key)) continue;
    projected[entry.key] = AccountModelAutoCompactView(
      modelId: entry.key,
      defaultLimit: null,
      overrideLimit: entry.value.overrideLimit,
    );
  }
  return projected;
}

/// 把配置字段与模型目录字段合成为一个领域快照。
SettingsStateSnapshot projectSettingsSnapshot({
  required SettingsStateData configData,
  required SettingsStateData catalogData,
  required int settingsRevision,
  required int modelCatalogRevision,
}) {
  final catalogByProvider = {
    for (final account in catalogData.accounts) account.id: account,
  };
  final accounts = [
    for (final account in configData.accounts)
      if (catalogByProvider[account.id] case final catalogProvider?)
        account.copyWith(
          models: catalogProvider.models,
          modelCatalog: catalogProvider.modelCatalog,
          autoCompactLimits: _projectAutoCompactLimits(
            account,
            catalogProvider,
          ),
        )
      else
        account,
  ];
  return SettingsStateSnapshot(
    accounts: accounts,
    defaultAccountId: configData.defaultAccountId,
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
