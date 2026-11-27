mod acp;
mod catalog;
mod mcp;
mod mode_definitions;
mod profiles;
pub(crate) use mode_definitions::ModeDefinitionCommandOutcome;

use std::sync::{Arc, Mutex, RwLock};

use crate::studio::unix_seconds;
use crate::{PureError, Result};

use super::agent_profile::{NativeProfileCheck, validate_native_profile_declaration};
use super::model_catalog::{self, Observation};
use super::store::CredentialPolicy;
use super::{AgentProfilesResource, ConfigStore, McpCatalogResource, StudioConfig};
use crate::StudioModelCatalogStatus;
use crate::mode::ThreadModeDocument;
use crate::mode::ThreadModeId;
use crate::mode::ThreadModeManager;
use pl_model::config::AccountId;
use std::collections::BTreeMap;

/// Settings desired state 的唯一进程内 owner。
///
/// 查询只克隆内存 snapshot；磁盘读写只发生在构造、显式 reload 或 CAS update command。
#[derive(Clone)]
pub struct ConfigRuntime {
    store: ConfigStore,
    command_lock: Arc<Mutex<()>>,
    state: Arc<RwLock<RuntimeState>>,
    catalog_updates: tokio::sync::broadcast::Sender<()>,
    /// canonical Settings 提交的同步观察者（ACP 身份与账号用量 owner）。
    ///
    /// 配置 owner 强持有该观察者，观察者自身只以 `Weak` 引用运行时 owner，因此不会形成
    /// ConfigRuntime ↔ 运行时 owner 的 `Arc` 环。
    settings_observer: Arc<Mutex<Vec<Arc<dyn SettingsCommitObserver>>>>,
    /// 配置 owner 持有的 canonical Agent Profiles 资源；命令路径扫描，查询只读缓存。
    profiles: AgentProfilesResource,
    acp: super::AcpDefinitionsResource,
    /// 配置 owner 持有的按环境作用域组织的单文件 MCP 配置目录资源。
    mcp_catalog: McpCatalogResource,
    /// 配置 owner 独占的 Mode 注册表；StudioRuntime 只持有同一 manager 的克隆。
    modes: ThreadModeManager,
    /// 文件定义的完整编辑文档；查询只读该缓存，不扫描目录。
    mode_documents: Arc<RwLock<BTreeMap<ThreadModeId, ThreadModeDocument>>>,
}

struct RuntimeState {
    native_revision: u64,
    desired: StudioConfig,
    snapshot: ConfigRuntimeSnapshot,
    catalog: ModelCatalogRuntimeSnapshot,
    observations: BTreeMap<AccountId, Observation>,
    closing: bool,
    /// Target delivery metadata from the original settings/catalog clocks; no business mirror.
    account_projection_revisions: BTreeMap<crate::AccountIdentity, (u64, u64)>,
}

impl RuntimeState {
    fn observe_native_config(&mut self, next: &StudioConfig) {
        let current = &self.snapshot.config;
        // These are the settings read when building a live provider and its tool registrations.
        if current.models != next.models
            || current.runtime != next.runtime
            || current.skills != next.skills
            || current.web_search != next.web_search
            || current.deepseek_web_search != next.deepseek_web_search
        {
            self.native_revision = self.native_revision.saturating_add(1);
        }
    }
}

/// canonical Settings 提交的同步观察者。
///
/// 在 Settings command 锁内、状态发布之后被调用：实现必须是同步、非阻塞的，不得等待 IO、
/// 用户输入或进程退出，也不得重入配置 owner。它把"已提交的 canonical revision"交给需要与该
/// revision 严格对齐的 owner（例如 ACP 接入身份），因此同一 revision 的读取与准入不会与提交
/// 交错。
pub(crate) trait SettingsCommitObserver: Send + Sync {
    /// 已提交的 canonical 设置 revision 与其内容。
    fn settings_committed(&self, snapshot: &ConfigRuntimeSnapshot);
}

/// 已校验 Studio 配置及其单调 revision。
///
/// `config` 是带当前目录 overlay 的运行时解析配置，供模型路由和执行路径使用。
/// `canonical_config` 是持久化的配置事实源，目录刷新不会修改它，也不会提升这个
/// snapshot 的 revision。
#[derive(Debug, Clone, PartialEq)]
pub struct ConfigRuntimeSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub config: StudioConfig,
    /// Read-only ACP resource snapshot from the same command publication boundary.
    pub acp: super::AcpDefinitionsSnapshot,
    canonical_config: StudioConfig,
    usage_query_revisions: BTreeMap<AccountId, u64>,
}

impl ConfigRuntimeSnapshot {
    pub(crate) fn canonical_config(&self) -> &StudioConfig {
        &self.canonical_config
    }

    pub(crate) fn usage_query_revision(&self, account: &AccountId) -> Option<u64> {
        self.usage_query_revisions.get(account).copied()
    }
}

/// 独立的模型目录 canonical snapshot。
///
/// 目录刷新只推进这个 revision；配置写入可以同时更新目录内容，但不会把两个时钟
/// 合并到同一个快照中。
#[derive(Debug, Clone, PartialEq)]
pub struct ModelCatalogRuntimeSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub catalogs: BTreeMap<AccountId, StudioModelCatalogStatus>,
}

/// Parameters resolved from one configuration revision for a newly created product Agent.
#[derive(Clone)]
pub struct ResolvedAgentProfile {
    /// The same snapshot used for Profile and route resolution, for coherent resource assembly.
    pub config: StudioConfig,
    pub revision: u64,
    pub profile: crate::AgentProfileSnapshot,
    pub definition: crate::AgentDefinitionSnapshot,
    pub binding: crate::AgentBinding,
    pub route: pl_model::config::ResolvedModelRoute,
}

impl std::fmt::Debug for ResolvedAgentProfile {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ResolvedAgentProfile")
            .field("revision", &self.revision)
            .field("profile_id", &self.profile.profile_id)
            .finish_non_exhaustive()
    }
}

/// Stable Settings owner failures used by transport adapters.
#[derive(Debug, thiserror::Error)]
pub enum ConfigRuntimeError {
    #[error("required config.toml could not be read")]
    RequiredConfiguration {
        #[source]
        source: std::io::Error,
    },
    #[error(transparent)]
    AcpDefinition(#[from] super::AcpDefinitionError),
    #[error("model discovery is unsupported for this account")]
    ModelDiscoveryUnsupported,
    #[error(
        "bundled Agent product resources are invalid; startup must stop without data recovery: {0:#}"
    )]
    BundledAgentCatalog(#[source] anyhow::Error),
    #[error("configuration migration failed: {0}")]
    Migration(#[source] anyhow::Error),
    #[error("work mode configuration requires repair; original files preserved: {0:#}")]
    ModeDefinitions(#[source] anyhow::Error),
    #[error("Agent Profile {0} changed since it was opened")]
    ProfileConflict(String),
    #[error("settings revision conflict: expected {expected}, actual {actual}")]
    StaleRevision { expected: u64, actual: u64 },
    #[error(transparent)]
    Core(#[from] PureError),
}

type ConfigRuntimeResult<T> = std::result::Result<T, ConfigRuntimeError>;

impl From<ConfigRuntimeError> for PureError {
    fn from(error: ConfigRuntimeError) -> Self {
        match error {
            ConfigRuntimeError::RequiredConfiguration { source } => PureError::Io(source),
            ConfigRuntimeError::AcpDefinition(error) => PureError::ConfigError(error.to_string()),
            ConfigRuntimeError::ModelDiscoveryUnsupported => {
                PureError::ConfigError("model discovery is unsupported".into())
            }
            ConfigRuntimeError::ProfileConflict(_) => PureError::ConfigError(error.to_string()),
            ConfigRuntimeError::Core(error) => error,
            ConfigRuntimeError::Migration(error) => match error.downcast::<PureError>() {
                Ok(error) => error,
                Err(error) => PureError::ConfigError(error.to_string()),
            },
            ConfigRuntimeError::BundledAgentCatalog(error) => {
                PureError::ConfigError(format!("bundled Agent resources are invalid: {error:#}"))
            }
            ConfigRuntimeError::ModeDefinitions(error) => PureError::ConfigError(format!(
                "work mode configuration requires repair: {error:#}"
            )),
            ConfigRuntimeError::StaleRevision { expected, actual } => PureError::ConfigError(
                format!("settings revision conflict: expected {expected}, actual {actual}"),
            ),
        }
    }
}

impl ConfigRuntime {
    /// 从磁盘加载并校验初始 desired config。
    pub fn initialize(store: ConfigStore) -> ConfigRuntimeResult<Self> {
        crate::agent::catalog::validate_startup_entries()
            .map_err(|error| ConfigRuntimeError::BundledAgentCatalog(anyhow::Error::new(error)))?;
        let desired = store.load_for_startup()?;
        let observations = model_catalog::reconcile(store.paths(), &desired, &BTreeMap::new(), 1)?;
        let config = effective_runtime_config(&desired, &observations)?;
        config.validate_declarations()?;
        super::AgentProfileCatalog::validate_for_startup(store.paths())?;
        // canonical Agent Profiles 资源：启动装载一次扫描，之后查询/订阅只读缓存。
        let acp = super::AcpDefinitionsResource::new(store.paths());
        let acp_snapshot = acp.read();
        let native_check = match store.credential_policy {
            CredentialPolicy::Stored | CredentialPolicy::NativeEnvironment => {
                NativeProfileCheck::OnScan
            }
            CredentialPolicy::AcpEnvironment => NativeProfileCheck::OnDispatch,
        };
        let profiles = AgentProfilesResource::with_native_check(
            store.paths(),
            &config,
            &acp_snapshot,
            native_check,
        );
        if store.credential_policy == CredentialPolicy::NativeEnvironment {
            for (role, selector) in &config.models.routes {
                crate::studio::delegation::validate_credential(
                    &config.models.resolve_route(role.clone(), selector)?,
                )?;
            }
            for selector in config.mode_model_routes.values() {
                crate::studio::delegation::validate_credential(
                    &config
                        .models
                        .resolve_route(super::root_agent_route_id(), selector)?,
                )?;
            }
        }
        if store.credential_policy != CredentialPolicy::Stored {
            for profile in profiles
                .read()
                .catalog
                .profiles
                .iter()
                .filter(|profile| profile.enabled)
            {
                if matches!(profile.binding, crate::AgentBinding::Native(_)) {
                    match native_check {
                        NativeProfileCheck::OnScan => {
                            crate::studio::delegation::validate_credential(
                                &super::resolve_profile_route(&config, profile)?,
                            )?
                        }
                        NativeProfileCheck::OnDispatch => {
                            validate_native_profile_declaration(&config, profile)?;
                        }
                    }
                }
            }
        }
        let mcp_catalog = McpCatalogResource::new(store.paths(), &config.models);
        let (modes, mode_documents) = mode_definitions::initialize(store.paths())
            .map_err(ConfigRuntimeError::ModeDefinitions)?;
        let (catalog_updates, _) = tokio::sync::broadcast::channel(64);
        Ok(Self {
            store,
            command_lock: Arc::new(Mutex::new(())),
            catalog_updates,
            settings_observer: Arc::new(Mutex::new(Vec::new())),
            state: Arc::new(RwLock::new(RuntimeState {
                native_revision: 1,
                account_projection_revisions: initial_account_projection_revisions(
                    &desired,
                    &acp_snapshot,
                ),
                desired: desired.clone(),
                closing: false,
                snapshot: ConfigRuntimeSnapshot {
                    revision: 1,
                    updated_at: unix_seconds(),
                    config: config.clone(),
                    acp: acp_snapshot,
                    usage_query_revisions: config
                        .models
                        .accounts
                        .keys()
                        .cloned()
                        .map(|id| (id, 1))
                        .collect(),
                    canonical_config: desired,
                },
                catalog: ModelCatalogRuntimeSnapshot {
                    revision: 1,
                    updated_at: unix_seconds(),
                    catalogs: statuses(&observations),
                },
                observations,
            })),
            profiles,
            acp,
            mcp_catalog,
            modes,
            mode_documents: Arc::new(RwLock::new(mode_documents)),
        })
    }

    /// 返回内存 canonical snapshot，不访问磁盘。
    pub fn read(&self) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        self.state
            .read()
            .map(|state| state.snapshot.clone())
            .map_err(|_| config_runtime_poisoned())
    }

    /// Borrowed, bounded account projections. The closure must not do IO or reenter this owner.
    /// Lock order is ConfigRuntime command/state before the ACP/usage projection owners.
    pub(crate) fn with_account_projection<T>(
        &self,
        read: impl FnOnce(&ConfigRuntimeSnapshot, &ModelCatalogRuntimeSnapshot) -> T,
    ) -> ConfigRuntimeResult<T> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        Ok(read(&state.snapshot, &state.catalog))
    }

    pub(crate) fn account_configuration_revision(
        &self,
        identity: &crate::AccountIdentity,
    ) -> ConfigRuntimeResult<Option<u64>> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        Ok(state
            .account_projection_revisions
            .get(identity)
            .map(|revisions| revisions.0))
    }

    pub(crate) fn account_catalog_revision(
        &self,
        account: &str,
    ) -> ConfigRuntimeResult<Option<u64>> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        Ok(state
            .account_projection_revisions
            .get(&crate::AccountIdentity::Native {
                account_id: account.to_owned(),
            })
            .map(|revisions| revisions.1))
    }

    /// Coherent configuration and directory watermarks from one owner read lock.
    pub fn read_with_catalog(
        &self,
    ) -> ConfigRuntimeResult<(ConfigRuntimeSnapshot, ModelCatalogRuntimeSnapshot)> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        Ok((state.snapshot.clone(), state.catalog.clone()))
    }

    pub(crate) fn native_configuration(&self) -> ConfigRuntimeResult<(StudioConfig, u64)> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        Ok((state.snapshot.config.clone(), state.native_revision))
    }

    pub(crate) fn native_runtime_revision(&self) -> ConfigRuntimeResult<u64> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        Ok(state.native_revision)
    }

    /// 安装 Settings 提交观察者，并在同一 command 边界内立即观察当前 canonical 快照。
    ///
    /// 安装与首次观察都在 command 锁内完成，因此不会出现"提交已发生但观察者还没装上"的缺口。
    pub(crate) fn install_settings_observer(
        &self,
        observer: Arc<dyn SettingsCommitObserver>,
    ) -> ConfigRuntimeResult<()> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let snapshot = {
            let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
            state.snapshot.clone()
        };
        self.settings_observer
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(Arc::clone(&observer));
        observer.settings_committed(&snapshot);
        Ok(())
    }

    /// 同一 command 边界内取得一致的 Settings 与目录快照；供只读投影使用。
    pub(crate) fn with_consistent_snapshot<T>(
        &self,
        run: impl FnOnce(&ConfigRuntimeSnapshot, &ModelCatalogRuntimeSnapshot) -> T,
    ) -> ConfigRuntimeResult<T> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let (snapshot, catalog) = self.read_with_catalog()?;
        Ok(run(&snapshot, &catalog))
    }

    /// 在 command 锁内同步通知已提交的 canonical revision。
    fn notify_settings_committed(&self, snapshot: &ConfigRuntimeSnapshot) {
        let observers = self
            .settings_observer
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        for observer in observers {
            observer.settings_committed(snapshot);
        }
    }

    /// Commits an in-memory observation at the same boundary as input invalidation.
    /// The callback must not await, perform IO, or re-enter this config owner.
    pub(crate) fn if_usage_query_current(
        &self,
        account: &AccountId,
        revision: u64,
        commit: impl FnOnce(),
    ) -> ConfigRuntimeResult<bool> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        if state.closing || state.snapshot.usage_query_revision(account) != Some(revision) {
            return Ok(false);
        }
        commit();
        Ok(true)
    }

    /// 返回独立的模型目录 snapshot，不访问磁盘。
    pub fn read_catalog(&self) -> ConfigRuntimeResult<ModelCatalogRuntimeSnapshot> {
        self.state
            .read()
            .map(|state| state.catalog.clone())
            .map_err(|_| config_runtime_poisoned())
    }

    /// Scalar qualification waterline for hot projections; never clones catalog/config payloads.
    pub(crate) fn model_catalog_revision(&self) -> ConfigRuntimeResult<u64> {
        self.state
            .read()
            .map(|state| state.catalog.revision)
            .map_err(|_| config_runtime_poisoned())
    }

    /// 读取系统凭据库或当前进程租约中的 SSH 主机密码。
    pub fn load_ssh_password(&self, alias: &str) -> Result<Option<String>> {
        self.store.load_ssh_password(alias)
    }

    /// 将 SSH 主机密码保存到系统凭据库。
    pub fn save_ssh_password(&self, alias: &str, secret: &str) -> Result<()> {
        self.store.save_ssh_password(alias, secret)
    }

    /// 从系统凭据库删除指定 SSH 主机密码。
    pub fn delete_ssh_password(&self, alias: &str) -> Result<()> {
        self.store.delete_ssh_password(alias)
    }

    pub(crate) fn bot_credentials(&self) -> crate::config::BotCredentialCapability {
        self.store.bot_credentials()
    }

    pub(crate) fn chatgpt_host_id(&self) -> Result<String> {
        self.store.chatgpt_host_id()
    }

    pub(crate) fn chatgpt_session(
        &self,
        id: &str,
        record: &pl_model_auth::chatgpt::ChatGptCredentialRecord,
    ) -> Result<pl_model_auth::chatgpt::ChatGptSession> {
        self.store.chatgpt_session(id, record)
    }

    /// 使用 expected revision 原子保存完整 desired config。
    pub fn replace(
        &self,
        expected_revision: u64,
        config: StudioConfig,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        self.update(expected_revision, |_| Ok(config))
    }

    /// 在串行 command 边界内变换、校验、持久化并发布配置。
    pub fn update(
        &self,
        expected_revision: u64,
        edit: impl FnOnce(&StudioConfig) -> Result<StudioConfig>,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        self.update_with_effective(expected_revision, |desired, _effective| edit(desired))
    }

    /// 在编辑 canonical desired config 时同时暴露当前 effective runtime
    /// config。模型目录观察是独立资源，路由选择必须能校验刚发现的模型，
    /// 但提交到磁盘的配置仍只能来自 desired，不能把目录 overlay 写回配置。
    pub fn update_with_effective(
        &self,
        expected_revision: impl Into<Option<u64>>,
        edit: impl FnOnce(&StudioConfig, &StudioConfig) -> Result<StudioConfig>,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        self.update_with_credential_intents(
            expected_revision,
            super::credential_commit::CredentialIntents::default(),
            edit,
        )
    }

    pub(crate) fn update_with_credential_intents(
        &self,
        expected_revision: impl Into<Option<u64>>,
        intents: super::credential_commit::CredentialIntents,
        edit: impl FnOnce(&StudioConfig, &StudioConfig) -> Result<StudioConfig>,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let before = self.snapshot_for_commit()?;
        if let Some(expected) = expected_revision.into() {
            ensure_revision(expected, before.snapshot.revision)?;
        }
        let mut next_config = edit(&before.desired, &before.snapshot.config)?;
        for account in next_config.models.accounts.values_mut() {
            account.clear_model_catalog_overlay();
        }
        let next_observations = model_catalog::reconcile(
            self.store.paths(),
            &next_config,
            &before.observations,
            before.snapshot.revision.saturating_add(1),
        )?;
        let effective = effective_runtime_config(&next_config, &next_observations)?;
        effective.validate_declarations()?;
        validate_changed_selections(&before.desired, &effective)?;

        self.commit_and_publish_snapshot(
            before,
            PreparedConfig {
                desired: next_config,
                effective,
                observations: next_observations,
            },
            ConfigCommit::Update(intents),
        )
    }

    /// 显式从磁盘重新加载配置；普通 read 永不调用此方法。
    pub fn reload_from_disk(
        &self,
        expected_revision: u64,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let before = self.snapshot_for_commit()?;
        ensure_revision(expected_revision, before.snapshot.revision)?;
        let desired = self.store.load_or_default()?;
        let next_observations = model_catalog::reconcile(
            self.store.paths(),
            &desired,
            &before.observations,
            before.snapshot.revision.saturating_add(1),
        )?;
        let config = effective_runtime_config(&desired, &next_observations)?;
        config.validate_declarations()?;
        super::AgentProfileCatalog::validate_for_startup(self.store.paths())?;
        self.commit_and_publish_snapshot(
            before,
            PreparedConfig {
                desired,
                effective: config,
                observations: next_observations,
            },
            ConfigCommit::Reload,
        )
    }

    fn snapshot_for_commit(&self) -> ConfigRuntimeResult<ConfigBeforeCommit> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        if state.closing {
            return Err(PureError::ConfigError("settings owner is closing".into()).into());
        }
        Ok(ConfigBeforeCommit {
            snapshot: state.snapshot.clone(),
            catalog: state.catalog.clone(),
            desired: state.desired.clone(),
            observations: state.observations.clone(),
        })
    }

    /// Caller holds the command lock until derived resources and synchronous observers settle.
    fn commit_and_publish_snapshot(
        &self,
        before: ConfigBeforeCommit,
        prepared: PreparedConfig,
        commit: ConfigCommit,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        let ConfigBeforeCommit {
            snapshot: current,
            catalog: current_catalog,
            desired: previous,
            observations,
        } = before;
        let PreparedConfig {
            desired,
            effective: config,
            observations: next_observations,
        } = prepared;
        let catalogs = statuses(&next_observations);
        let catalog_changed = matches!(&commit, ConfigCommit::Reload)
            || catalogs != current_catalog.catalogs
            || config.models.accounts != current.config.models.accounts;
        // File and credential work completes before runtime state, leases or observers change.
        let acp = match commit {
            ConfigCommit::Update(intents) => {
                self.store.commit_config(&previous, &desired, &intents)?;
                current.acp.clone()
            }
            ConfigCommit::Reload => self.acp.reload(self.store.paths()),
        };
        let now = unix_seconds();
        let next = ConfigRuntimeSnapshot {
            revision: current.revision.saturating_add(1),
            updated_at: now,
            usage_query_revisions: next_usage_query_revisions(&current, &config),
            config,
            acp,
            canonical_config: desired.clone(),
        };
        let catalog = ModelCatalogRuntimeSnapshot {
            revision: current_catalog
                .revision
                .saturating_add(u64::from(catalog_changed)),
            updated_at: if catalog_changed {
                now
            } else {
                current_catalog.updated_at
            },
            catalogs,
        };
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        revoke_replaced_chatgpt_sessions(&previous, &desired);
        invalidate_observations(&observations, &next_observations);
        update_account_projection_revisions(&mut state, &next, &catalog);
        state.observe_native_config(&next.config);
        state.desired = desired;
        state.observations = next_observations;
        state.snapshot = next.clone();
        state.catalog = catalog;
        drop(state);

        self.profiles
            .adopt_scan(self.store.paths(), &next.config, &next.acp);
        self.mcp_catalog
            .refresh_all_scopes(self.store.paths(), &next.config.models, &[]);
        self.notify_settings_committed(&next);
        Ok(next)
    }
}

struct ConfigBeforeCommit {
    snapshot: ConfigRuntimeSnapshot,
    catalog: ModelCatalogRuntimeSnapshot,
    desired: StudioConfig,
    observations: BTreeMap<AccountId, Observation>,
}

struct PreparedConfig {
    desired: StudioConfig,
    effective: StudioConfig,
    observations: BTreeMap<AccountId, Observation>,
}

enum ConfigCommit {
    Update(super::credential_commit::CredentialIntents),
    Reload,
}

fn revoke_replaced_chatgpt_sessions(previous: &StudioConfig, next: &StudioConfig) {
    for (id, account) in &previous.models.accounts {
        if let Some(session) = &account.chatgpt_session {
            let retained = next
                .models
                .accounts
                .get(id)
                .and_then(|account| account.chatgpt_session.as_ref());
            if retained != Some(session) {
                session.revoke();
            }
        }
    }
}

fn initial_account_projection_revisions(
    config: &StudioConfig,
    acp: &super::AcpDefinitionsSnapshot,
) -> BTreeMap<crate::AccountIdentity, (u64, u64)> {
    use crate::AccountIdentity;
    config
        .models
        .accounts
        .keys()
        .map(|id| AccountIdentity::Native {
            account_id: id.to_string(),
        })
        .chain(acp.definitions.keys().map(|id| AccountIdentity::Acp {
            account_id: id.clone(),
        }))
        .map(|identity| (identity, (1, 1)))
        .collect()
}

fn update_account_projection_revisions(
    state: &mut RuntimeState,
    next: &ConfigRuntimeSnapshot,
    catalog: &ModelCatalogRuntimeSnapshot,
) {
    use crate::AccountIdentity;
    let mut revisions = BTreeMap::new();
    for (id, account) in &next.canonical_config.models.accounts {
        let identity = AccountIdentity::Native {
            account_id: id.to_string(),
        };
        let old = state.account_projection_revisions.get(&identity).copied();
        let same_config = state.desired.models.accounts.get(id) == Some(account)
            && default_account_model(&state.desired, id)
                == default_account_model(&next.canonical_config, id)
            && state.snapshot.usage_query_revision(id) == next.usage_query_revision(id);
        let same_catalog = state.snapshot.config.models.accounts.get(id)
            == next.config.models.accounts.get(id)
            && state.catalog.catalogs.get(id) == catalog.catalogs.get(id);
        revisions.insert(
            identity,
            (
                old.filter(|_| same_config)
                    .map_or(next.revision, |value| value.0),
                old.filter(|_| same_catalog)
                    .map_or(catalog.revision, |value| value.1),
            ),
        );
    }
    for (id, account) in &next.acp.definitions {
        let identity = AccountIdentity::Acp {
            account_id: id.clone(),
        };
        let revision = state
            .account_projection_revisions
            .get(&identity)
            .filter(|_| state.snapshot.acp.definitions.get(id) == Some(account))
            .map_or(next.revision, |value| value.0);
        revisions.insert(identity, (revision, 0));
    }
    state.account_projection_revisions = revisions;
}

fn default_account_model<'a>(
    config: &'a StudioConfig,
    id: &AccountId,
) -> (Option<&'a str>, Option<&'a str>) {
    let auto = config
        .mode_model_routes
        .get(&ThreadModeId::auto())
        .filter(|route| &route.account_id == id)
        .map(|route| route.model_id.as_str());
    let role = config
        .models
        .routes
        .values()
        .find(|route| &route.account_id == id)
        .map(|route| route.model_id.as_str());
    (auto, role)
}

fn next_usage_query_revisions(
    previous: &ConfigRuntimeSnapshot,
    config: &StudioConfig,
) -> BTreeMap<AccountId, u64> {
    config
        .models
        .accounts
        .iter()
        .map(|(id, account)| {
            let unchanged = previous.config.models.accounts.get(id).is_some_and(|old| {
                old.protocol == account.protocol
                    && old.authentication == account.authentication
                    && old.chatgpt_session == account.chatgpt_session
                    && old.template_id() == account.template_id()
                    && old.base_url == account.base_url
                    && old.http_headers == account.http_headers
                    && old.resolved_bearer_token() == account.resolved_bearer_token()
            });
            let revision = if unchanged {
                previous
                    .usage_query_revision(id)
                    .unwrap_or(previous.revision)
            } else {
                // Use a fresh owner-local waterline also after delete/recreate,
                // so an old request cannot match a new instance with the same id.
                previous.revision.saturating_add(1)
            };
            (id.clone(), revision)
        })
        .collect()
}

fn statuses(
    observations: &BTreeMap<AccountId, Observation>,
) -> BTreeMap<AccountId, StudioModelCatalogStatus> {
    observations
        .iter()
        .map(|(id, observation)| (id.clone(), observation.status.clone()))
        .collect()
}

/// 构造执行路径与 settings 视图使用的 effective 配置。
///
/// 只应用目录 overlay 与产品固定策略；`canonical_config`/desired 仍是持久化事实源。
fn effective_runtime_config(
    desired: &StudioConfig,
    observations: &BTreeMap<AccountId, Observation>,
) -> Result<StudioConfig> {
    let mut config = model_catalog::effective(desired, observations)?;
    config.runtime.enforce_fixed_permission_mode();
    Ok(config)
}

fn invalidate_observations(
    old: &BTreeMap<AccountId, Observation>,
    next: &BTreeMap<AccountId, Observation>,
) {
    for (id, observation) in old {
        if next
            .get(id)
            .is_none_or(|next| next.generation != observation.generation)
        {
            observation.cancellation.cancel();
        }
    }
}

fn validate_changed_selections(old: &StudioConfig, next: &StudioConfig) -> Result<()> {
    for (role, route) in &next.models.routes {
        if old.models.routes.get(role) != Some(route) {
            next.models.resolve_route(role.clone(), route)?;
        }
    }
    for (mode, route) in &next.mode_model_routes {
        if old.mode_model_routes.get(mode) != Some(route) {
            next.models
                .resolve_route(super::root_agent_route_id(), route)?;
        }
    }
    for (id, account) in &next.models.accounts {
        let models = account.effective_models(None)?;
        for (model_id, mode) in account.connection_overrides() {
            if old
                .models
                .accounts
                .get(id)
                .and_then(|old| old.connection_overrides().get(model_id))
                == Some(mode)
            {
                continue;
            }
            let model = models
                .iter()
                .find(|model| model.base.slug == *model_id)
                .ok_or_else(|| {
                    PureError::ConfigError(
                        "new connection override references unavailable model".into(),
                    )
                })?;
            if !model
                .extra
                .binding
                .transport
                .supported_connection_modes
                .contains(mode)
            {
                return Err(PureError::ConfigError(
                    "new connection override is unsupported".into(),
                ));
            }
        }
    }
    Ok(())
}

fn ensure_revision(expected: u64, actual: u64) -> ConfigRuntimeResult<()> {
    if expected != actual {
        return Err(ConfigRuntimeError::StaleRevision { expected, actual });
    }
    Ok(())
}

fn config_runtime_poisoned() -> ConfigRuntimeError {
    PureError::ConfigError("ConfigRuntime state lock is poisoned".to_string()).into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::mcp_resource::scan_scope_catalog;
    use crate::config::{ConfigPaths, ConfigStore};
    use crate::{
        CreateMcpDocumentRequest, DeleteMcpDocumentRequest, McpScope, UpdateMcpDocumentRequest,
    };

    #[test]
    fn background_mcp_scan_cannot_regrant_deleted_or_disabled_configuration() {
        use std::sync::{atomic, mpsc};
        use std::time::Duration;

        for disable in [false, true] {
            let (directory, mut runtime) = runtime();
            let raw = "schema_version = 1\nid = \"guarded\"\nkind = \"server\"\ntransport = \"streamableHttp\"\nurl = \"https://guarded.example/mcp\"\n";
            let (receipt, _) = runtime
                .create_mcp_document(&CreateMcpDocumentRequest {
                    scope: McpScope::Host,
                    id: "guarded".into(),
                    raw_toml: raw.into(),
                })
                .unwrap();
            let document = receipt.document.unwrap();
            let content = runtime.read_mcp_document(&document).unwrap();
            let original = runtime
                .mcp_catalog
                .configuration_authorization(&McpScope::Host)
                .unwrap()
                .0;
            let (prepared, observed) = mpsc::channel();
            let (release, proceed) = mpsc::channel();
            let proceed = std::sync::Mutex::new(proceed);
            let first = atomic::AtomicBool::new(true);
            runtime.mcp_catalog =
                runtime
                    .mcp_catalog
                    .with_scanner(Arc::new(move |paths, models, scope| {
                        let scan = scan_scope_catalog(paths, models, scope)?;
                        if matches!(scope, McpScope::Host)
                            && std::thread::current().name() == Some("mcp-model-scan")
                            && first.swap(false, atomic::Ordering::AcqRel)
                        {
                            prepared.send(()).unwrap();
                            proceed
                                .lock()
                                .unwrap()
                                .recv_timeout(Duration::from_secs(10))
                                .unwrap();
                        }
                        Ok(scan)
                    }));
            let background_runtime = runtime.clone();
            let background = std::thread::Builder::new()
                .name("mcp-model-scan".into())
                .spawn(move || background_runtime.refresh_mcp_catalogs_for_models())
                .unwrap();
            let prepared = observed.recv_timeout(Duration::from_secs(10));
            // The scan has captured old enabled data, but must still own the canonical
            // command boundary. A deletion cannot commit then be overwritten by this scan.
            let boundary_held = runtime.command_lock.try_lock().is_err();
            let mutation_runtime = runtime.clone();
            let mutation = std::thread::spawn(move || {
                if disable {
                    mutation_runtime
                        .update_mcp_document(&UpdateMcpDocumentRequest {
                            document,
                            expected_revision: content.revision,
                            raw_toml: format!("{raw}enabled = false\n"),
                        })
                        .map(|_| ())
                } else {
                    mutation_runtime
                        .delete_mcp_document(&DeleteMcpDocumentRequest {
                            document,
                            expected_revision: content.revision,
                        })
                        .map(|_| ())
                }
            });
            // Always release and join before assertions, including a missing hook or a
            // broken boundary, so a failing regression does not strand either worker.
            let _ = release.send(());
            let background = background.join();
            let mutation = mutation.join();
            prepared.unwrap();
            background.unwrap().unwrap();
            mutation.unwrap().unwrap();
            assert!(
                boundary_held,
                "background scan escaped the MCP command boundary"
            );
            assert!(!original.is_active());
            let current = runtime
                .resolve_thread_mcp_snapshot(
                    &McpScope::Host,
                    directory.path(),
                    directory.path(),
                    None,
                )
                .unwrap();
            assert!(current.authorization.is_active());
            assert!(!current.servers.contains_key("guarded"));
            if disable {
                let catalog = runtime.mcp_catalog_snapshot(&McpScope::Host).unwrap();
                assert!(catalog.entries.iter().any(|entry| {
                    entry.id == "guarded"
                        && entry.config_status == crate::McpConfigStatusKind::Disabled
                }));
            } else {
                let catalog = runtime.mcp_catalog_snapshot(&McpScope::Host).unwrap();
                assert!(!catalog.entries.iter().any(|entry| entry.id == "guarded"));
            }
        }
    }

    #[test]
    fn cold_mcp_scope_entrypoints_hold_the_configuration_boundary() {
        use std::sync::mpsc;
        use std::time::Duration;

        for entrypoint in 0..4 {
            let (directory, mut runtime) = runtime();
            let (receipt, _) = runtime
                .create_mcp_document(&CreateMcpDocumentRequest {
                    scope: McpScope::Host,
                    id: "cold-shared".into(),
                    raw_toml: "schema_version = 1\nid = \"cold-shared\"\nkind = \"server\"\ntransport = \"streamableHttp\"\nurl = \"https://cold.example/mcp\"\n".into(),
                })
                .unwrap();
            let document = receipt.document.unwrap();
            let content = runtime.read_mcp_document(&document).unwrap();
            let scope = McpScope::Ssh {
                ssh_alias: format!("cold-{entrypoint}"),
            };
            assert!(
                runtime
                    .mcp_catalog
                    .configuration_authorization(&scope)
                    .is_none()
            );
            let (reached, observed) = mpsc::channel();
            let (release, proceed) = mpsc::channel();
            let proceed = std::sync::Mutex::new(proceed);
            let selected = scope.clone();
            runtime.mcp_catalog =
                runtime
                    .mcp_catalog
                    .with_scanner(Arc::new(move |paths, models, scope| {
                        if scope == &selected
                            && std::thread::current().name() == Some("mcp-cold-read")
                        {
                            // The caller has the models snapshot and is about to read a cold scope.
                            reached.send(()).unwrap();
                            proceed
                                .lock()
                                .unwrap()
                                .recv_timeout(Duration::from_secs(10))
                                .unwrap();
                        }
                        scan_scope_catalog(paths, models, scope)
                    }));
            let reader_runtime = runtime.clone();
            let reader_scope = scope.clone();
            let root = directory.path().to_path_buf();
            let reader = std::thread::Builder::new()
                .name("mcp-cold-read".into())
                .spawn(move || match entrypoint {
                    0 => reader_runtime
                        .mcp_catalog_snapshot(&reader_scope)
                        .map(|_| ()),
                    1 => reader_runtime
                        .subscribe_mcp_catalog(&reader_scope)
                        .map(|_| ()),
                    2 => reader_runtime
                        .effective_mcp_servers_for_scope(&reader_scope)
                        .map(|_| ()),
                    _ => reader_runtime
                        .resolve_thread_mcp_configs(&reader_scope, &root, &root, None)
                        .map(|_| ()),
                })
                .unwrap();
            let reached = observed.recv_timeout(Duration::from_secs(10));
            let boundary_held = runtime.command_lock.try_lock().is_err();
            let mutation_runtime = runtime.clone();
            let mutation = std::thread::spawn(move || {
                mutation_runtime.delete_mcp_document(&DeleteMcpDocumentRequest {
                    document,
                    expected_revision: content.revision,
                })
            });
            let _ = release.send(());
            let reader = reader.join();
            let mutation = mutation.join();
            reached.unwrap();
            reader.unwrap().unwrap();
            mutation.unwrap().unwrap();
            assert!(
                boundary_held,
                "cold MCP entrypoint {entrypoint} escaped configuration ordering"
            );
            let current = runtime
                .resolve_thread_mcp_snapshot(&scope, directory.path(), directory.path(), None)
                .unwrap();
            assert!(current.authorization.is_active());
            assert!(!current.servers.contains_key("cold-shared"));
        }
    }

    fn runtime() -> (tempfile::TempDir, ConfigRuntime) {
        let directory = tempfile::tempdir().expect("isolated config directory");
        let store = ConfigStore::new(ConfigPaths::from_config_dir(directory.path()));
        let runtime = ConfigRuntime::initialize(store).expect("default config initializes");
        (directory, runtime)
    }

    #[test]
    fn acp_cli_defers_native_profile_qualification_across_reload() -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let paths = ConfigPaths::from_config_dir(directory.path());
        let mut config = StudioConfig::default_config()?;
        let selector = config.mode_model_route(&ThreadModeId::auto())?.clone();
        config
            .models
            .accounts
            .get_mut(&selector.account_id)
            .expect("default account")
            .bearer_token_env = None;
        ConfigStore::new(paths.clone()).save(&config)?;
        let profile = crate::config::UserAgentProfile {
            enabled: true,
            display_name: "Native child".into(),
            description: "Native Profile qualification".into(),
            when_to_use: "A selected Native task".into(),
            binding: crate::AgentBinding::Native(crate::NativeAgentConfig {
                route: Some(crate::NewThreadModelRoute {
                    account_id: selector.account_id.to_string(),
                    model_id: selector.model_id,
                    effort: selector.effort.map(|effort| effort.as_str().to_owned()),
                }),
                system_instructions: Some("Complete the assigned task.".into()),
            }),
            workspace_mode: crate::AgentWorkspaceMode::Directory,
        };
        let save = |id| {
            crate::config::save_user_agent_profile(
                &paths,
                id,
                &profile,
                &config,
                &Default::default(),
            )
        };
        let has_diagnostic = |snapshot: &crate::config::AgentProfilesSnapshot, id: &str| {
            snapshot.catalog.diagnostics.iter().any(|diagnostic| {
                diagnostic.path.ends_with(format!("{id}.toml"))
                    && diagnostic
                        .message
                        .contains("model account credential is unavailable")
            })
        };
        save("native-configured")?;
        let desktop = ConfigRuntime::initialize(ConfigStore::new(paths.clone()))?;
        assert!(has_diagnostic(
            &desktop.agent_profiles_snapshot()?,
            "native-configured"
        ));

        let acp = ConfigRuntime::initialize(ConfigStore::for_acp_cli(directory.path()))?;
        let startup = acp.agent_profiles_snapshot()?;
        assert!(!has_diagnostic(&startup, "native-configured"));
        save("native-reloaded")?;
        acp.reload_from_disk(acp.read()?.revision)?;
        let after = acp.agent_profiles_snapshot()?;
        assert!(after.revision > startup.revision);

        let visible = acp.agent_profiles()?;
        for id in ["native-configured", "native-reloaded"] {
            assert!(!has_diagnostic(&after, id));
            assert!(
                visible
                    .profiles
                    .iter()
                    .any(|entry| entry.definition.definition_id == id)
            );
            let Err(error) =
                acp.resolve_delegated_profile(id, crate::DelegationMode::Profile, None)
            else {
                anyhow::bail!("dispatch accepted Native Profile `{id}` without a credential");
            };
            assert!(
                error
                    .to_string()
                    .contains("model account credential is unavailable"),
                "{error}"
            );
        }
        Ok(())
    }

    #[test]
    fn credential_conflict_and_bad_reload_preserve_published_configuration() -> anyhow::Result<()> {
        #[derive(Default)]
        struct CommittedRevisions(Mutex<Vec<u64>>);
        impl SettingsCommitObserver for CommittedRevisions {
            fn settings_committed(&self, snapshot: &ConfigRuntimeSnapshot) {
                self.0.lock().unwrap().push(snapshot.revision);
            }
        }

        let (_directory, runtime) = runtime();
        let before = runtime.read_with_catalog()?;
        let path = runtime.store.paths().config_file();
        runtime.store.save(before.0.canonical_config())?;
        let canonical_bytes = std::fs::read(path)?;
        let revision = before.0.revision;
        let native_revision = runtime.native_runtime_revision()?;
        let observer = Arc::new(CommittedRevisions::default());
        runtime.install_settings_observer(observer.clone())?;
        let profiles = runtime.agent_profiles_snapshot()?;

        let account_id = before.0.config.models.accounts.keys().next().unwrap();
        runtime
            .store
            .credentials
            .save(account_id.as_str(), "external-fixture-key")?;
        let error = runtime
            .update_with_credential_intents(
                revision,
                super::super::credential_commit::CredentialIntents::for_account(
                    account_id.as_str(),
                    &crate::AccountAuthenticationIntent::ApiKey,
                ),
                |desired, _| {
                    let mut candidate = desired.clone();
                    candidate
                        .models
                        .accounts
                        .get_mut(account_id)
                        .unwrap()
                        .bearer_token = Some("candidate-fixture-key".into());
                    candidate.skills.enabled = !candidate.skills.enabled;
                    Ok(candidate)
                },
            )
            .unwrap_err();
        assert!(
            error.to_string().contains("credential binding changed"),
            "{error}"
        );
        assert_eq!(std::fs::read(path)?, canonical_bytes);
        assert_eq!(runtime.read_with_catalog()?, before);

        let broken = b"schema_version = [invalid";
        std::fs::write(path, broken)?;
        runtime.reload_from_disk(revision).unwrap_err();
        assert_eq!(std::fs::read(path)?, broken);
        assert_eq!(runtime.read_with_catalog()?, before);
        assert_eq!(runtime.native_runtime_revision()?, native_revision);
        assert_eq!(
            runtime.agent_profiles_snapshot()?.revision,
            profiles.revision
        );
        assert_eq!(*observer.0.lock().unwrap(), [revision]);

        std::fs::write(path, canonical_bytes)?;
        let reloaded = runtime.reload_from_disk(revision)?;
        assert_eq!(reloaded.revision, revision + 1);
        assert_eq!(
            reloaded.config.models.accounts[account_id]
                .bearer_token
                .as_deref(),
            Some("external-fixture-key")
        );
        assert_eq!(*observer.0.lock().unwrap(), [revision, revision + 1]);
        Ok(())
    }

    #[test]
    fn reload_is_rejected_after_configuration_owner_closes() -> anyhow::Result<()> {
        let (_directory, runtime) = runtime();
        let before = runtime.read()?;
        runtime.close_model_catalogs()?;
        assert!(runtime.reload_from_disk(before.revision).is_err());
        assert_eq!(runtime.read()?.revision, before.revision);
        Ok(())
    }

    #[test]
    fn mode_document_edits_are_independent_and_external_changes_survive_stale_writes()
    -> anyhow::Result<()> {
        use crate::mode::ThreadModeId;
        let (_dir, runtime) = runtime();
        let mut first = runtime
            .read_thread_mode_definition(&ThreadModeId::auto())?
            .document;
        first.id = ThreadModeId::new("mode.first")?;
        let mut second = first.clone();
        second.id = ThreadModeId::new("mode.second")?;
        let opened = runtime
            .save_thread_mode_definition(0, first.clone())?
            .definition
            .unwrap()
            .revision;
        runtime.save_thread_mode_definition(0, second)?;
        first.prompt.push_str(" edited");
        let saved = runtime
            .save_thread_mode_definition(opened, first.clone())?
            .definition
            .unwrap()
            .revision;
        assert!(
            runtime
                .save_thread_mode_definition(0, first.clone())
                .is_err()
        );
        let path = runtime.store.paths().modes_dir().join("mode.first.json");
        first.prompt.push_str(" externally");
        let external = serde_json::to_vec_pretty(&first)?;
        std::fs::write(&path, &external)?;
        assert!(
            runtime
                .delete_thread_mode_definition(saved, &first.id)
                .is_err()
        );
        assert!(runtime.save_thread_mode_definition(saved, first).is_err());
        assert_eq!(std::fs::read(path)?, external);
        Ok(())
    }

    #[test]
    fn scalar_config_mutation_does_not_advance_catalog_clock() {
        let (_directory, runtime) = runtime();
        let before = runtime.read().expect("read config");
        let catalog_before = runtime.read_catalog().expect("read catalog");
        let native = runtime.native_runtime_revision().unwrap();
        let next = runtime
            .update(before.revision, |config| {
                let mut next = config.clone();
                next.instructions.user = "independent config field".to_string();
                Ok(next)
            })
            .expect("update one field");

        assert_eq!(runtime.native_runtime_revision().unwrap(), native);
        assert_eq!(next.revision, before.revision + 1);
        assert_eq!(
            runtime
                .read()
                .expect("read updated config")
                .config
                .instructions
                .user,
            "independent config field"
        );
        assert_eq!(
            runtime
                .read_catalog()
                .expect("read catalog after config")
                .revision,
            catalog_before.revision,
            "a scalar settings write must not be published as a catalog refresh",
        );
    }

    #[test]
    fn stale_config_revision_is_rejected_before_editing_canonical_state() {
        let (_directory, runtime) = runtime();
        let before = runtime.read().expect("read config");
        let _next = runtime
            .update(before.revision, |config| {
                let mut next = config.clone();
                next.instructions.user = "first".to_string();
                Ok(next)
            })
            .expect("first update");

        let error = runtime
            .update(before.revision, |config| {
                let mut next = config.clone();
                next.instructions.user = "stale must not win".to_string();
                Ok(next)
            })
            .expect_err("old CAS revision must fail");
        assert!(matches!(error, ConfigRuntimeError::StaleRevision { .. }));
        assert_eq!(
            runtime
                .read()
                .expect("read canonical config")
                .config
                .instructions
                .user,
            "first",
        );
    }

    #[test]
    fn acp_profile_dispatch_checks_definitions_in_both_modes_without_native_routes() {
        let (_directory, runtime) = runtime();
        runtime
            .save_acp_definition(
                &crate::config::AcpServiceDefinition::template(
                    "acp-fixture".into(),
                    "ACP fixture".into(),
                    crate::config::AcpProvider::Antigravity,
                ),
                None,
            )
            .expect("configure ACP definition");
        let profile = super::super::UserAgentProfile {
            enabled: true,
            display_name: "ACP child".into(),
            description: "ACP configuration boundary".into(),
            when_to_use: "ACP dispatch fixture".into(),
            binding: crate::AgentBinding::Acp(crate::AcpAgentConfig {
                account_id: "acp-fixture".into(),
            }),
            workspace_mode: crate::AgentWorkspaceMode::Directory,
        };
        runtime
            .save_user_agent_profile(None, "acp-child", &profile)
            .expect("ACP Profile is a valid current configuration");
        let opened = runtime
            .agent_profiles_snapshot()
            .unwrap()
            .catalog
            .profiles
            .into_iter()
            .find(|item| item.definition.definition_id == "acp-child")
            .unwrap()
            .definition
            .revision;
        runtime
            .save_user_agent_profile(None, "another-child", &profile)
            .unwrap();
        let mut edited = profile.clone();
        edited.description.push_str(" updated");
        runtime
            .save_user_agent_profile(Some(&opened), "acp-child", &edited)
            .unwrap();
        assert!(matches!(
            runtime.save_user_agent_profile(Some(&opened), "acp-child", &profile),
            Err(ConfigRuntimeError::ProfileConflict(_))
        ));
        let path = runtime.store.paths().agents_dir().join("acp-child.toml");
        assert!(
            std::fs::read_to_string(path)
                .unwrap()
                .contains(&edited.description)
        );

        let catalog = runtime
            .agent_profiles_snapshot()
            .expect("current profiles")
            .catalog;
        assert!(
            catalog
                .profiles
                .iter()
                .any(|profile| profile.definition.definition_id == "acp-child")
        );
        for mode in [
            crate::DelegationMode::Profile,
            crate::DelegationMode::Automatic,
        ] {
            assert!(
                catalog
                    .executable(mode)
                    .expect("dispatch view")
                    .profiles
                    .iter()
                    .any(|profile| profile.definition.definition_id == "acp-child")
            );
        }

        let error = runtime
            .resolve_agent_profile("acp-child")
            .expect_err("Native resolver must not fabricate an ACP model route");
        assert!(
            error
                .to_string()
                .contains("ACP Profile requires ACP business preparation")
        );
        let (_, definition) = runtime
            .resolve_acp_child_profile("acp-child")
            .expect("ACP admission");
        let entry = runtime.read_acp_definitions().definitions["acp-fixture"].clone();
        let mut disabled = definition;
        disabled.enabled = false;
        runtime
            .save_acp_definition(&disabled, Some(entry.document_revision))
            .expect("disable definition");
        for mode in [
            crate::DelegationMode::Profile,
            crate::DelegationMode::Automatic,
        ] {
            assert!(
                runtime
                    .agent_profiles_snapshot()
                    .unwrap()
                    .catalog
                    .executable(mode)
                    .unwrap()
                    .profiles
                    .iter()
                    .all(|profile| profile.definition.definition_id != "acp-child")
            );
        }
        assert!(runtime.resolve_acp_child_profile("acp-child").is_err());
    }
}
