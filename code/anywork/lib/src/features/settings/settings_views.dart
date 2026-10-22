import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/lsp_store.dart';
import '../../presentation/providers/mcp_store.dart';
import '../../presentation/providers/model_performance_store.dart';
import '../../presentation/providers/provider_usage_store.dart';
import '../../presentation/providers/recovery_store.dart';
import '../../presentation/providers/selection_store.dart';
import '../../presentation/providers/settings_store.dart';
import '../../presentation/providers/skills_store.dart';
import '../../presentation/providers/bots_store.dart';
import '../../presentation/providers/project_store.dart';
import '../../presentation/providers/thread_session_store.dart';

import 'package:anywork_client/studio_client.dart';

import 'settings_account_usage_demand.dart';

/// 设置页是否已经有可渲染的配置 canonical。
///
/// 传输失败只在尚无 last-known 快照时占位；已有快照后由各 tab 自己的 topic 状态提示。
class SettingsPageReadiness {
  const SettingsPageReadiness({
    required this.ready,
    required this.error,
    required this.settingsRevision,
    required this.configSync,
  });

  final bool ready;
  final String? error;
  final int settingsRevision;
  final DomainSyncStatus configSync;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsPageReadiness &&
          ready == other.ready &&
          error == other.error &&
          settingsRevision == other.settingsRevision &&
          configSync == other.configSync;

  @override
  int get hashCode => Object.hash(ready, error, settingsRevision, configSync);
}

final settingsPageReadinessProvider =
    Provider.autoDispose<SettingsPageReadiness>((ref) {
      final selected = ref.watch(
        settingsStoreProvider.select(
          (state) => (
            ready: state.canonical != null,
            revision: state.settingsRevision,
            sync: state.configSync,
          ),
        ),
      );
      return SettingsPageReadiness(
        ready: selected.ready,
        error: selected.ready ? null : _syncError(selected.sync),
        settingsRevision: selected.revision,
        configSync: selected.sync,
      );
    }, name: 'settingsPageReadinessProvider');

class SettingsAccountsView {
  SettingsAccountsView({
    required this.canonical,
    required this.accountCatalog,
    required this.defaultAccountId,
    required this.settingsRevision,
    required this.modelCatalogRevision,
    required this.accountCatalogRevision,
  }) : accounts = List<AccountSettingsView>.unmodifiable(
         accountsWithCatalogMetadata(
           canonical?.accounts ?? const <AccountSettingsView>[],
           accountCatalog,
         ),
       );

  final SettingsStateSnapshot? canonical;
  final AccountCatalogView accountCatalog;
  final String? defaultAccountId;
  final int settingsRevision;
  final int modelCatalogRevision;
  final String accountCatalogRevision;
  final List<AccountSettingsView> accounts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsAccountsView &&
          defaultAccountId == other.defaultAccountId &&
          settingsRevision == other.settingsRevision &&
          modelCatalogRevision == other.modelCatalogRevision &&
          accountCatalogRevision == other.accountCatalogRevision &&
          identical(canonical, other.canonical) &&
          identical(accountCatalog, other.accountCatalog);

  @override
  int get hashCode => Object.hash(
    defaultAccountId,
    settingsRevision,
    modelCatalogRevision,
    accountCatalogRevision,
    identityHashCode(canonical),
    identityHashCode(accountCatalog),
  );
}

final settingsAccountsViewProvider = Provider.autoDispose<SettingsAccountsView>(
  (ref) {
    final store = ref.watch(settingsStoreProvider);
    return SettingsAccountsView(
      canonical: store.canonical,
      accountCatalog: store.accountCatalog,
      defaultAccountId: store.canonical?.defaultAccountId,
      settingsRevision: store.settingsRevision,
      modelCatalogRevision: store.modelCatalogRevision,
      accountCatalogRevision: store.accountCatalogRevision,
    );
  },
  name: 'settingsAccountsViewProvider',
);

/// 自动额度只消费 (id, usageQueryRevision)，不把 catalog/settings 全局水位当查询身份。
final settingsAccountUsageQueryIdentitiesProvider =
    Provider.autoDispose<AccountUsageQueryIdentitySnapshot>((ref) {
      return ref.watch(
        settingsAccountsViewProvider.select((view) {
          return AccountUsageQueryIdentitySnapshot([
            for (final account in view.accounts)
              AccountUsageQueryIdentity(
                id: account.id,
                usageQueryRevision: account.usageQueryRevision,
              ),
          ]);
        }),
      );
    }, name: 'settingsAccountUsageQueryIdentitiesProvider');

class SettingsInstructionsView {
  const SettingsInstructionsView({
    required this.settings,
    required this.settingsRevision,
  });

  final InstructionsSettingsView settings;
  final int settingsRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsInstructionsView &&
          settingsRevision == other.settingsRevision &&
          identical(settings, other.settings);

  @override
  int get hashCode => Object.hash(settingsRevision, identityHashCode(settings));
}

final settingsInstructionsViewProvider =
    Provider.autoDispose<SettingsInstructionsView>((ref) {
      final selected = ref.watch(
        settingsStoreProvider.select(
          (state) => (
            settings: state.canonical?.instructions,
            revision: state.settingsRevision,
          ),
        ),
      );
      return SettingsInstructionsView(
        settings: selected.settings ?? const InstructionsSettingsView(),
        settingsRevision: selected.revision,
      );
    }, name: 'settingsInstructionsViewProvider');

class SettingsGeneralView {
  const SettingsGeneralView({
    required this.settings,
    required this.webSearch,
    required this.deepSeekWebSearch,
    required this.runtimeBusy,
    required this.settingsRevision,
    required this.threadRevision,
  });

  final GeneralSettingsView settings;
  final WebSearchSettingsView webSearch;
  final DeepSeekWebSearchSettingsView deepSeekWebSearch;
  final bool runtimeBusy;
  final int settingsRevision;
  final int threadRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsGeneralView &&
          runtimeBusy == other.runtimeBusy &&
          settingsRevision == other.settingsRevision &&
          threadRevision == other.threadRevision &&
          identical(settings, other.settings) &&
          identical(webSearch, other.webSearch) &&
          identical(deepSeekWebSearch, other.deepSeekWebSearch);

  @override
  int get hashCode => Object.hash(
    runtimeBusy,
    settingsRevision,
    threadRevision,
    identityHashCode(settings),
    identityHashCode(webSearch),
    identityHashCode(deepSeekWebSearch),
  );
}

final settingsGeneralViewProvider = Provider.autoDispose<SettingsGeneralView>((
  ref,
) {
  final canonical = ref.watch(
    settingsStoreProvider.select((state) => state.canonical),
  );
  final revision = ref.watch(
    settingsStoreProvider.select((state) => state.settingsRevision),
  );
  final session = _watchSelectedSession(ref);
  return SettingsGeneralView(
    settings: canonical?.general ?? const GeneralSettingsView(),
    webSearch: canonical?.webSearch ?? const WebSearchSettingsView(),
    deepSeekWebSearch:
        canonical?.deepSeekWebSearch ?? const DeepSeekWebSearchSettingsView(),
    runtimeBusy: session?.busy ?? false,
    settingsRevision: revision,
    threadRevision: session?.revision ?? 0,
  );
}, name: 'settingsGeneralViewProvider');

class SettingsAgentsView {
  const SettingsAgentsView({
    required this.profiles,
    required this.profilesLoaded,
    required this.profilesRevision,
    required this.profilesSync,
    required this.canonical,
    required this.accountCatalog,
    required this.recovery,
    required this.recoveryRevision,
    required this.settingsRevision,
    required this.accountCatalogRevision,
  });

  final AgentProfilesStateView? profiles;
  final bool profilesLoaded;
  final int profilesRevision;
  final DomainSyncStatus profilesSync;
  final SettingsStateSnapshot? canonical;
  final AccountCatalogView accountCatalog;
  final RecoveryStateSnapshot? recovery;
  final int recoveryRevision;
  final int settingsRevision;
  final String accountCatalogRevision;

  List<AccountSettingsView> get accounts => accountsWithCatalogMetadata(
    canonical?.accounts ?? const <AccountSettingsView>[],
    accountCatalog,
  );

  List<RoleSettingsView> get roles => canonical?.roles ?? const [];

  bool get profilesFailed => profilesSync.phase == DomainSyncPhase.failed;

  bool get profilesLoading => !profilesLoaded && !profilesFailed;

  String? get profilesErrorMessage =>
      profilesFailed ? profilesSync.errorMessage : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsAgentsView &&
          profilesLoaded == other.profilesLoaded &&
          profilesRevision == other.profilesRevision &&
          profilesSync == other.profilesSync &&
          recoveryRevision == other.recoveryRevision &&
          settingsRevision == other.settingsRevision &&
          accountCatalogRevision == other.accountCatalogRevision &&
          identical(profiles, other.profiles) &&
          identical(canonical, other.canonical) &&
          identical(accountCatalog, other.accountCatalog) &&
          identical(recovery, other.recovery);

  @override
  int get hashCode => Object.hash(
    profilesLoaded,
    profilesRevision,
    profilesSync,
    recoveryRevision,
    settingsRevision,
    accountCatalogRevision,
    identityHashCode(profiles),
    identityHashCode(canonical),
    identityHashCode(accountCatalog),
    identityHashCode(recovery),
  );
}

final settingsAgentsViewProvider = Provider.autoDispose<SettingsAgentsView>((
  ref,
) {
  final settings = ref.watch(settingsStoreProvider);
  final recovery = ref.watch(recoveryStoreProvider);
  return SettingsAgentsView(
    profiles: settings.agentProfiles,
    profilesLoaded: settings.agentProfilesLoaded,
    profilesRevision: settings.agentProfilesRevision,
    profilesSync: settings.agentProfilesSync,
    canonical: settings.canonical,
    accountCatalog: settings.accountCatalog,
    recovery: recovery.value,
    recoveryRevision: recovery.revision,
    settingsRevision: settings.settingsRevision,
    accountCatalogRevision: settings.accountCatalogRevision,
  );
}, name: 'settingsAgentsViewProvider');

class SettingsMcpView {
  const SettingsMcpView({
    required this.configServers,
    required this.runtime,
    required this.settingsRevision,
    required this.runtimeRevision,
    required this.sync,
  });

  final List<McpServerSettingsView> configServers;
  final McpStateSnapshot? runtime;
  final int settingsRevision;
  final int runtimeRevision;
  final DomainSyncStatus sync;

  List<McpServerSettingsView> get runtimeServers =>
      runtime?.servers ?? const <McpServerSettingsView>[];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsMcpView &&
          settingsRevision == other.settingsRevision &&
          runtimeRevision == other.runtimeRevision &&
          sync == other.sync &&
          identical(configServers, other.configServers) &&
          identical(runtime, other.runtime);

  @override
  int get hashCode => Object.hash(
    settingsRevision,
    runtimeRevision,
    sync,
    identityHashCode(configServers),
    identityHashCode(runtime),
  );
}

final settingsMcpViewProvider = Provider.autoDispose<SettingsMcpView>((ref) {
  final config = ref.watch(
    settingsStoreProvider.select(
      (state) => (
        servers: state.canonical?.mcpServers ?? const <McpServerSettingsView>[],
        revision: state.settingsRevision,
      ),
    ),
  );
  final runtime = ref.watch(mcpStoreProvider);
  return SettingsMcpView(
    configServers: config.servers,
    runtime: runtime.value,
    settingsRevision: config.revision,
    runtimeRevision: runtime.revision,
    sync: runtime.sync,
  );
}, name: 'settingsMcpViewProvider');

class SettingsLspView {
  const SettingsLspView({
    required this.projectId,
    required this.runtime,
    required this.runtimeRevision,
    required this.sync,
  });

  final String? projectId;
  final LspStateSnapshot? runtime;
  final int runtimeRevision;
  final DomainSyncStatus sync;

  List<LspServerStateView> get servers =>
      runtime?.servers ?? const <LspServerStateView>[];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsLspView &&
          projectId == other.projectId &&
          runtimeRevision == other.runtimeRevision &&
          sync == other.sync &&
          identical(runtime, other.runtime);

  @override
  int get hashCode =>
      Object.hash(projectId, runtimeRevision, sync, identityHashCode(runtime));
}

final settingsLspViewProvider = Provider.autoDispose<SettingsLspView>((ref) {
  final projectId = ref.watch(
    selectionStoreProvider.select(
      (state) => _nonBlank(state.selectedProjectId),
    ),
  );
  final runtime = ref.watch(lspStoreProvider);
  return SettingsLspView(
    projectId: projectId,
    runtime: runtime.value,
    runtimeRevision: runtime.revision,
    sync: runtime.sync,
  );
}, name: 'settingsLspViewProvider');

class SettingsSkillsView {
  const SettingsSkillsView({
    required this.projectId,
    required this.settings,
    required this.catalog,
    required this.activeSkills,
    required this.settingsRevision,
    required this.catalogRevision,
    required this.catalogStoreRevision,
    required this.threadRevision,
    required this.sync,
  });

  final String? projectId;
  final SkillsSettingsView? settings;
  final SkillsStateSnapshot? catalog;
  final List<String> activeSkills;
  final int settingsRevision;
  final int catalogRevision;
  final int catalogStoreRevision;
  final int threadRevision;
  final DomainSyncStatus sync;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsSkillsView &&
          projectId == other.projectId &&
          settingsRevision == other.settingsRevision &&
          catalogRevision == other.catalogRevision &&
          catalogStoreRevision == other.catalogStoreRevision &&
          threadRevision == other.threadRevision &&
          sync == other.sync &&
          identical(settings, other.settings) &&
          identical(catalog, other.catalog) &&
          listEquals(activeSkills, other.activeSkills);

  @override
  int get hashCode => Object.hash(
    projectId,
    settingsRevision,
    catalogRevision,
    catalogStoreRevision,
    threadRevision,
    sync,
    identityHashCode(settings),
    identityHashCode(catalog),
    Object.hashAll(activeSkills),
  );
}

final settingsSkillsViewProvider = Provider.autoDispose<SettingsSkillsView>((
  ref,
) {
  final projectId = ref.watch(
    selectionStoreProvider.select(
      (state) => _nonBlank(state.selectedProjectId),
    ),
  );
  final settings = ref.watch(
    settingsStoreProvider.select(
      (state) =>
          (skills: state.canonical?.skills, revision: state.settingsRevision),
    ),
  );
  final catalog = projectId == null
      ? null
      : ref.watch(skillsStoreProvider(projectId));
  final session = _watchSelectedSession(ref);
  return SettingsSkillsView(
    projectId: projectId,
    settings: settings.skills,
    catalog: catalog?.value,
    activeSkills: session?.activeSkills ?? const <String>[],
    settingsRevision: settings.revision,
    catalogRevision: catalog?.value?.catalogRevision ?? 0,
    catalogStoreRevision: catalog?.revision ?? 0,
    threadRevision: session?.revision ?? 0,
    sync: catalog?.sync ?? const DomainSyncStatus(),
  );
}, name: 'settingsSkillsViewProvider');

class SettingsUsageView {
  const SettingsUsageView({
    required this.snapshot,
    required this.revision,
    required this.loaded,
    required this.sync,
  });

  final AccountUsageStateSnapshot? snapshot;
  final int revision;
  final bool loaded;
  final DomainSyncStatus sync;

  List<AccountUsageView> get usages =>
      snapshot?.usages ?? const <AccountUsageView>[];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsUsageView &&
          revision == other.revision &&
          loaded == other.loaded &&
          sync == other.sync &&
          identical(snapshot, other.snapshot);

  @override
  int get hashCode =>
      Object.hash(revision, loaded, sync, identityHashCode(snapshot));
}

final settingsUsageViewProvider = Provider.autoDispose<SettingsUsageView>((
  ref,
) {
  final store = ref.watch(accountUsageStoreProvider);
  return SettingsUsageView(
    snapshot: store.value,
    revision: store.revision,
    loaded: store.loaded,
    sync: store.sync,
  );
}, name: 'settingsUsageViewProvider');

class SettingsStatisticsView {
  const SettingsStatisticsView({
    required this.snapshot,
    required this.revision,
    required this.loaded,
    required this.sync,
  });

  final ModelPerformanceSnapshotView? snapshot;
  final int revision;
  final bool loaded;
  final DomainSyncStatus sync;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsStatisticsView &&
          revision == other.revision &&
          loaded == other.loaded &&
          sync == other.sync &&
          identical(snapshot, other.snapshot);

  @override
  int get hashCode =>
      Object.hash(revision, loaded, sync, identityHashCode(snapshot));
}

final settingsStatisticsViewProvider =
    Provider.autoDispose<SettingsStatisticsView>((ref) {
      final store = ref.watch(modelPerformanceStoreProvider);
      return SettingsStatisticsView(
        snapshot: store.value,
        revision: store.revision,
        loaded: store.loaded,
        sync: store.sync,
      );
    }, name: 'settingsStatisticsViewProvider');

class SettingsBotsView {
  const SettingsBotsView({
    required this.snapshot,
    required this.revision,
    required this.loaded,
    required this.sync,
    required this.queries,
    required this.sends,
    required this.projects,
    required this.modelConfigured,
  });

  final BotsStateSnapshot? snapshot;
  final int revision;
  final bool loaded;
  final DomainSyncStatus sync;
  final BotsQueryState queries;
  final BotsSendState sends;
  final List<StudioProject> projects;
  final bool modelConfigured;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsBotsView &&
          revision == other.revision &&
          loaded == other.loaded &&
          sync == other.sync &&
          queries == other.queries &&
          sends == other.sends &&
          modelConfigured == other.modelConfigured &&
          identical(snapshot, other.snapshot) &&
          identical(projects, other.projects);

  @override
  int get hashCode => Object.hash(
    revision,
    loaded,
    sync,
    queries,
    sends,
    modelConfigured,
    identityHashCode(snapshot),
    identityHashCode(projects),
  );
}

final settingsBotsViewProvider = Provider.autoDispose<SettingsBotsView>((ref) {
  final store = ref.watch(botsStoreProvider);
  final queries = ref.watch(botsQueryStoreProvider);
  final sends = ref.watch(botsSendStoreProvider);
  final settings = ref.watch(
    settingsStoreProvider.select((state) => state.canonical),
  );
  final route = ModelRouteQueries.modeRoute(
    settings?.modeModelRoutes ?? const [],
    ThreadModeId.simple,
  );
  final account = settings?.accounts
      .where((account) => account.id == route?.accountId)
      .firstOrNull;
  final model = route == null
      ? null
      : ModelRouteQueries.model(
          settings?.accounts ?? const [],
          route.accountId,
          route.modelId,
        );
  final projects = ref.watch(
    projectStoreProvider.select(
      (state) =>
          state.projects?.values.toList(growable: false) ??
          const <StudioProject>[],
    ),
  );
  return SettingsBotsView(
    snapshot: store.value,
    revision: store.revision,
    loaded: store.loaded,
    sync: store.sync,
    queries: queries,
    sends: sends,
    projects: projects,
    modelConfigured:
        model != null &&
        account != null &&
        (!account.credentialRequired || account.hasBearerToken),
  );
}, name: 'settingsBotsViewProvider');

/// 单个设置命令的 in-flight 标志。UI 只显示 pending，不改用目标值。
class SettingsCommandPendingView {
  const SettingsCommandPendingView({
    required this.pending,
    required this.settingsRevision,
  });

  final bool pending;
  final int settingsRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsCommandPendingView &&
          pending == other.pending &&
          settingsRevision == other.settingsRevision;

  @override
  int get hashCode => Object.hash(pending, settingsRevision);
}

final settingsCommandPendingProvider = Provider.autoDispose
    .family<SettingsCommandPendingView, String>((ref, key) {
      final selected = ref.watch(
        settingsStoreProvider.select(
          (state) => (
            pending: state.commands[key]?.isPending ?? false,
            revision: state.settingsRevision,
          ),
        ),
      );
      return SettingsCommandPendingView(
        pending: selected.pending,
        settingsRevision: selected.revision,
      );
    }, name: 'settingsCommandPendingProvider');

final settingsRoleCommandPendingProvider = Provider.autoDispose
    .family<SettingsCommandPendingView, String>((ref, role) {
      final selected = ref.watch(
        settingsStoreProvider.select(
          (state) => (
            pending:
                state.commands['agent-role:modelId:$role']?.isPending == true ||
                state.commands['agent-role:effort:$role']?.isPending == true,
            revision: state.settingsRevision,
          ),
        ),
      );
      return SettingsCommandPendingView(
        pending: selected.pending,
        settingsRevision: selected.revision,
      );
    }, name: 'settingsRoleCommandPendingProvider');

class _SelectedSessionFacts {
  const _SelectedSessionFacts({
    required this.busy,
    required this.revision,
    required this.activeSkills,
  });

  final bool busy;
  final int revision;
  final List<String> activeSkills;
}

_SelectedSessionFacts? _watchSelectedSession(Ref ref) {
  final threadId = ref.watch(
    selectionStoreProvider.select((state) => _nonBlank(state.selectedThreadId)),
  );
  if (threadId == null) return null;
  final session = ref.watch(threadSessionStoreProvider(threadId));
  return _SelectedSessionFacts(
    busy:
        (session.activeTurn?.state.isBusy ?? false) ||
        (session.runtime?.hasActiveWorkflow ?? false),
    revision: session.revision,
    activeSkills: session.runtime?.activeSkills ?? const <String>[],
  );
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String? _syncError(DomainSyncStatus sync) {
  if (sync.phase != DomainSyncPhase.failed) return null;
  final message = sync.errorMessage?.trim();
  if (message == null || message.isEmpty) return 'settings unavailable';
  return message;
}
