mod catalog;
mod configuration_projection;
mod mode_definitions;
mod model_projection;
mod profile_commands;
pub(crate) use configuration_projection::{
    ConfigurationCaptureFailure, ConfigurationMaterial, ConfigurationPair, ConfigurationSnapshot,
    ConfigurationSource, ConfigurationStatusMaterial,
};
pub(crate) use mode_definitions::ModeDefinitionCommandOutcome;
pub(crate) use model_projection::{
    ModelCaptureFailure, ModelCatalogMaterial, ModelCatalogSource, ModelSourceStatusFailure,
    ModelSourceStatusMaterial, ModelsSnapshot,
};
pub(crate) use profile_commands::ProfileMutationFailure;

use std::sync::{Arc, Mutex, RwLock};

use crate::studio::unix_seconds;
use crate::{PureError, Result};

use super::model_catalog::{self, Observation};
use super::{AgentProfilesEvidence, AgentProfilesPublication, ProfilesSource};
use super::{AgentProfilesResource, AgentProfilesSnapshot, ConfigStore, StudioConfig};
use crate::mode::ThreadModeManager;
use pl_model::config::AccountId;
use pl_protocol::ThreadModeDocument;
use pl_protocol::{ThreadModeId, studio::StudioModelCatalogStatus};
use std::collections::BTreeMap;

/// Settings desired state 的唯一进程内 owner。
///
/// 查询只克隆内存 snapshot；磁盘读写只发生在构造、显式 reload 或 CAS update command。
#[derive(Clone)]
pub struct ConfigRuntime {
    store: ConfigStore,
    command_lock: Arc<Mutex<()>>,
    state: Arc<RwLock<RuntimeState>>,
    catalog_updates: tokio::sync::broadcast::Sender<CatalogChange>,
    projection_updates: tokio::sync::watch::Sender<pl_protocol::studio::ConfigProjectionStamp>,
    /// canonical Settings 提交的同步观察者（当前由 ACP 身份 owner 使用）。
    ///
    /// 配置 owner 强持有该观察者，观察者自身只以 `Weak` 引用运行时 owner，因此不会形成
    /// ConfigRuntime ↔ 运行时 owner 的 `Arc` 环。
    settings_observer: Arc<Mutex<Option<Arc<dyn SettingsCommitObserver>>>>,
    /// 配置 owner 持有的 canonical Agent Profiles 资源；命令路径扫描，查询只读缓存。
    profiles: AgentProfilesResource,
    /// 配置 owner 独占的 Mode 注册表；StudioRuntime 只持有同一 manager 的克隆。
    modes: ThreadModeManager,
    /// 文件定义的完整编辑文档；查询只读该缓存，不扫描目录。
    mode_documents: Arc<RwLock<BTreeMap<ThreadModeId, ThreadModeDocument>>>,
}

struct RuntimeState {
    desired: StudioConfig,
    snapshot: ConfigRuntimeSnapshot,
    catalog: ModelCatalogRuntimeSnapshot,
    models_status: model_projection::ModelSourceMetadata,
    observations: BTreeMap<AccountId, Observation>,
    models_sources: BTreeMap<String, std::sync::Weak<ModelCatalogSource>>,
    configuration_sources: BTreeMap<String, std::sync::Weak<ConfigurationSource>>,
    configuration_status: configuration_projection::ConfigurationMetadata,
    /// 与 `snapshot.revision` 严格相符的 ACP 目录捕获值。
    ///
    /// 只保存 Settings 提交观察边界取得的不可变值；配置所有者不管理认证任务，也不分配连接代次。
    acp_directory: Option<AcpDirectoryCapture>,
    closing: bool,
}

/// 一次 Settings 提交观察捕获的 ACP 目录事实。
///
/// 失败保留类型化诊断：来源未就绪或投影与设置版本不符都显式可见，绝不用空列表或零连接代次补齐。
#[derive(Clone)]
struct AcpDirectoryCapture {
    settings_revision: u64,
    accounts: std::result::Result<
        Arc<[pl_protocol::studio::AcpAccountSettings]>,
        Arc<pl_protocol::studio::StudioError>,
    >,
}

/// 一次 Settings 提交观察返回的不可变 ACP 目录投影。
pub(crate) struct SettingsCommitProjection {
    pub(crate) settings_revision: u64,
    pub(crate) accounts: Arc<[pl_protocol::studio::AcpAccountSettings]>,
}

/// canonical Settings 提交的同步观察者。
///
/// 在 Settings command 锁内、配置材料捕获之前被调用：实现必须是同步、非阻塞的，不得等待 IO、
/// 用户输入或进程退出，也不得重入配置 owner。它把"已提交的 canonical revision"交给需要与该
/// revision 严格对齐的 owner（例如 ACP 接入身份），并回传同一 revision 的不可变目录投影，
/// 因此同一 revision 的身份同步、目录捕获与配置材料发布不会与提交交错。
pub(crate) trait SettingsCommitObserver: Send + Sync {
    /// 已提交的 canonical 设置 revision 与其内容；返回同一 revision 的不可变 ACP 目录投影。
    ///
    /// 在配置材料捕获**之前**调用：实现同步 ACP 身份并返回该 revision 的目录，调用方随后才在
    /// 原状态发布边界采用配置材料，因此不存在"已发布配置 + 旧目录"的窗口。实现不得 I/O、
    /// await 或重入配置 owner，也不得在持有配置状态锁时被调用。
    fn settings_committed(
        &self,
        revision: u64,
        config: &StudioConfig,
    ) -> std::result::Result<SettingsCommitProjection, pl_protocol::studio::StudioError>;
}

#[derive(Clone)]
pub(crate) struct CatalogChange {
    pub affected: Vec<AccountId>,
}

/// Only notification responsibility escapes the canonical guard, never mutable source inputs.
struct ProjectionPublication {
    stamp: pl_protocol::studio::ConfigProjectionStamp,
    models: Vec<Arc<ModelCatalogSource>>,
    configuration: Vec<Arc<ConfigurationSource>>,
    configuration_captures: BTreeMap<
        String,
        std::result::Result<Arc<ConfigurationSnapshot>, pl_protocol::studio::StudioError>,
    >,
    catalog: ModelCatalogRuntimeSnapshot,
    catalog_change: Option<CatalogChange>,
    profiles: Option<AgentProfilesPublication>,
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

/// Registration and its compatible baseline are taken under the same canonical state guard.
pub(crate) struct ConfigProjectionObservation {
    pub current: (ConfigRuntimeSnapshot, ModelCatalogRuntimeSnapshot),
    pub stamp: pl_protocol::studio::ConfigProjectionStamp,
    pub updates: tokio::sync::watch::Receiver<pl_protocol::studio::ConfigProjectionStamp>,
}

/// Captured before releasing the original command/adopt-scan boundary.
pub struct ConfigProfileCommandResult {
    pub configuration: ConfigRuntimeSnapshot,
    pub catalog: ModelCatalogRuntimeSnapshot,
    pub profiles: AgentProfilesSnapshot,
    pub changed: bool,
    pub(crate) _evidence: ConfigMutationEvidence,
}

pub struct ConfigReloadResult {
    pub configuration: ConfigRuntimeSnapshot,
    pub catalog: ModelCatalogRuntimeSnapshot,
    pub profiles: AgentProfilesSnapshot,
    pub(crate) evidence: ConfigMutationEvidence,
}

/// Exact command publication, captured before releasing the original commit guard. Capturing
/// can fail after a successful durable save; that failure never changes the commit into rejection.
pub(crate) struct ConfigMutationEvidence {
    pub(crate) configuration: ConfigRuntimeSnapshot,
    pub(crate) catalog: ModelCatalogRuntimeSnapshot,
    pub(crate) captures: BTreeMap<
        String,
        std::result::Result<Arc<ConfigurationSnapshot>, pl_protocol::studio::StudioError>,
    >,
    pub(crate) profiles: AgentProfilesEvidence,
}

/// Private save-stage evidence: Profile calls can distinguish a confirmed save lacking a usable
/// receipt. The original eight command outcomes conservatively keep their existing Unknown
/// classification for both durable-error cases; legacy callers receive the original error.
#[derive(Debug, thiserror::Error)]
pub(crate) enum ConfigMutationFailure {
    #[error("Configuration command was rejected before commit")]
    Preflight(#[source] ConfigRuntimeError),
    #[error("Configuration command durable outcome is unknown")]
    Commit(#[source] ConfigRuntimeError),
    #[error("Configuration save succeeded but no usable state receipt was captured")]
    Confirmed(#[source] ConfigRuntimeError),
}

impl From<ConfigMutationFailure> for ConfigRuntimeError {
    fn from(failure: ConfigMutationFailure) -> Self {
        match failure {
            ConfigMutationFailure::Preflight(error)
            | ConfigMutationFailure::Commit(error)
            | ConfigMutationFailure::Confirmed(error) => error,
        }
    }
}

/// Parameters resolved from one configuration revision for a newly created product Agent.
#[derive(Clone)]
pub struct ResolvedAgentProfile {
    /// The same snapshot used for Profile and route resolution, for coherent resource assembly.
    pub config: StudioConfig,
    pub revision: u64,
    pub profile: pl_protocol::AgentProfileSnapshot,
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
    #[error(
        "bundled Agent product resources are invalid; startup must stop without data recovery: {0:#}"
    )]
    BundledAgentCatalog(#[source] anyhow::Error),
    #[error("configuration migration failed; original file preserved: {0}")]
    Migration(#[source] PureError),
    #[error("work mode configuration requires repair; original files preserved: {0:#}")]
    ModeDefinitions(#[source] anyhow::Error),
    #[error("settings revision conflict: expected {expected}, actual {actual}")]
    StaleRevision { expected: u64, actual: u64 },
    #[error(transparent)]
    Core(#[from] PureError),
}

type ConfigRuntimeResult<T> = std::result::Result<T, ConfigRuntimeError>;

impl From<ConfigRuntimeError> for PureError {
    fn from(error: ConfigRuntimeError) -> Self {
        match error {
            ConfigRuntimeError::Core(error) | ConfigRuntimeError::Migration(error) => error,
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
    /// Builder-only registration using a separately issued Profiles incarnation.
    pub(crate) fn attach_profiles_source(
        &self,
        origin: pl_protocol::products::identity::ProductReadOrigin,
    ) -> anyhow::Result<Arc<ProfilesSource>> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        if state.closing {
            return Err(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Cancelled,
                "Configuration owner is closing",
                false,
            )
            .into());
        }
        if state
            .configuration_sources
            .values()
            .filter_map(std::sync::Weak::upgrade)
            .any(|source| source.origin() == &origin)
            || state
                .models_sources
                .values()
                .filter_map(std::sync::Weak::upgrade)
                .any(|source| source.origin() == &origin)
        {
            return Err(pl_protocol::studio::StudioError::invalid_argument(
                "Profiles requires its own native-issued incarnation",
            )
            .into());
        }
        Ok(self.profiles.attach_source(origin)?)
    }

    /// 从磁盘加载并校验初始 desired config。
    pub fn initialize(store: ConfigStore) -> ConfigRuntimeResult<Self> {
        crate::agent::catalog::validate_startup_entries()
            .map_err(|error| ConfigRuntimeError::BundledAgentCatalog(anyhow::Error::new(error)))?;
        let desired = store.load_for_startup()?;
        let observations = model_catalog::reconcile(store.paths(), &desired, &BTreeMap::new())?;
        let config = effective_runtime_config(&desired, &observations)?;
        config.validate_declarations()?;
        super::AgentProfileCatalog::validate_for_startup(store.paths())?;
        // canonical Agent Profiles 资源：启动卸载一次扫描，之后查询/订阅只读缓存。
        let profiles = AgentProfilesResource::new(store.paths(), &config);
        let (modes, mode_documents) = mode_definitions::initialize(store.paths())
            .map_err(ConfigRuntimeError::ModeDefinitions)?;
        let initialized_at = unix_seconds();
        let (catalog_updates, _) = tokio::sync::broadcast::channel(64);
        let (projection_updates, _) =
            tokio::sync::watch::channel(pl_protocol::studio::ConfigProjectionStamp {
                settings_revision: 1,
                model_catalog_revision: 1,
                closing: false,
            });
        Ok(Self {
            store,
            command_lock: Arc::new(Mutex::new(())),
            catalog_updates,
            projection_updates,
            settings_observer: Arc::new(Mutex::new(None)),
            state: Arc::new(RwLock::new(RuntimeState {
                desired: desired.clone(),
                closing: false,
                snapshot: ConfigRuntimeSnapshot {
                    revision: 1,
                    updated_at: initialized_at,
                    config: config.clone(),
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
                    updated_at: initialized_at,
                    catalogs: statuses(&observations),
                },
                // Successful validated initialization is the sole initial Ready publication.
                // This counter is not borrowed from either business snapshot's waterline.
                models_status: Ok(Arc::new(pl_protocol::ObservedResource::ready(
                    1,
                    initialized_at,
                    (),
                ))),
                observations,
                models_sources: BTreeMap::new(),
                configuration_sources: BTreeMap::new(),
                configuration_status: Ok(Arc::new(pl_protocol::ObservedResource::ready(
                    1,
                    initialized_at,
                    (),
                ))),
                // 尚无 Settings 提交观察者；首次安装观察者后才取得同版本的 ACP 目录捕获值。
                acp_directory: None,
            })),
            profiles,
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

    /// Coherent configuration and directory watermarks from one owner read lock.
    pub fn read_with_catalog(
        &self,
    ) -> ConfigRuntimeResult<(ConfigRuntimeSnapshot, ModelCatalogRuntimeSnapshot)> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        Ok((state.snapshot.clone(), state.catalog.clone()))
    }

    pub(crate) fn observe_projection_sources(
        &self,
    ) -> ConfigRuntimeResult<ConfigProjectionObservation> {
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        Ok(ConfigProjectionObservation {
            current: (state.snapshot.clone(), state.catalog.clone()),
            stamp: projection_stamp(&state),
            updates: self.projection_updates.subscribe(),
        })
    }

    fn publish_projection_locked(&self, state: &mut RuntimeState) -> ProjectionPublication {
        let models = self.publish_models_locked(state);
        let configuration = self.publish_configuration_locked(state);
        let configuration_captures = configuration
            .iter()
            .map(|source| (source.origin().owner_epoch.clone(), source.current()))
            .collect();
        ProjectionPublication {
            models,
            configuration,
            configuration_captures,
            catalog: state.catalog.clone(),
            stamp: projection_stamp(state),
            catalog_change: None,
            profiles: None,
        }
    }

    /// Wakers may re-enter this owner; call only after releasing state and command guards.
    fn notify_projection(&self, publication: ProjectionPublication) {
        self.projection_updates.send_if_modified(|published| {
            let next = &publication.stamp;
            // Another command can publish and notify after our locks are released. A delayed
            // notification must not roll the retained compatible stamp back to an older pair.
            if published.settings_revision > next.settings_revision
                || published.model_catalog_revision > next.model_catalog_revision
                || (published.closing && !next.closing)
                || *published == *next
            {
                return false;
            }
            *published = *next;
            true
        });
        for source in publication.models {
            source.notify();
        }
        for source in publication.configuration {
            source.notify();
        }
        if let Some(profiles) = publication.profiles {
            profiles.notify();
        }
        if let Some(change) = publication.catalog_change {
            let _ = self.catalog_updates.send(change);
        }
    }

    /// 安装 Settings 提交观察者，并在同一 command 边界内立即观察当前 canonical 快照。
    ///
    /// 安装与首次观察都在 command 锁内完成，因此不会出现"提交已发生但观察者还没装上"的缺口。
    /// 观察同时返回当前 revision 的 ACP 目录捕获值，供随后建立的配置材料直接使用。
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
        *self
            .settings_observer
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(Arc::clone(&observer));
        // 观察者可能同步回调其它 owner；此处不持有配置状态锁。
        let capture = self.observe_settings_commit(&snapshot);
        self.state
            .write()
            .map_err(|_| config_runtime_poisoned())?
            .acp_directory = Some(capture);
        Ok(())
    }

    /// 在当前 command 边界内取得与 `snapshot.revision` 严格相符的 ACP 目录捕获值。
    ///
    /// 调用方必须持有 command 锁且不持有配置状态锁。只有观察者在同一 revision 成功返回捕获时
    /// 才形成目录事实（其中可以就是空列表）；观察者未安装或返回错误都保留显式诊断，绝不以
    /// canonical 的空集合伪装已确认空目录。
    fn observe_settings_commit(&self, snapshot: &ConfigRuntimeSnapshot) -> AcpDirectoryCapture {
        let observer = self
            .settings_observer
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .cloned();
        let accounts = match observer {
            Some(observer) => {
                match observer.settings_committed(snapshot.revision, snapshot.canonical_config()) {
                    Ok(projection) if projection.settings_revision == snapshot.revision => {
                        Ok(projection.accounts)
                    }
                    Ok(_) => Err(Arc::new(pl_protocol::studio::StudioError::new(
                        pl_protocol::studio::StudioErrorCode::Protocol,
                        "ACP directory projection does not match the committed Settings revision",
                        false,
                    ))),
                    Err(error) => Err(Arc::new(error)),
                }
            }
            // 未安装观察者即来源未就绪：保留显式错误，绝不把"没有观察者"当成已确认空目录。
            None => Err(Arc::new(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Unavailable,
                "ACP directory projection is not prepared: the settings commit observer is not installed",
                true,
            ))),
        };
        AcpDirectoryCapture {
            settings_revision: snapshot.revision,
            accounts,
        }
    }

    /// 在 Settings command 串行边界内取得 canonical 快照并执行同步 closure。
    ///
    /// closure 内可以安全地把该 revision 与其它 owner 的准入/身份绑定：其间没有其它配置提交能
    /// 插入。closure 不得 await、做 IO，也不得再次进入本配置 owner。
    pub(crate) fn with_canonical_snapshot<T>(
        &self,
        run: impl FnOnce(u64, &StudioConfig) -> T,
    ) -> ConfigRuntimeResult<T> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let (revision, desired) = {
            let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
            (state.snapshot.revision, state.desired.clone())
        };
        Ok(run(revision, &desired))
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

    #[allow(dead_code)]
    // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    /// Scalar qualification waterline for hot projections; never clones catalog/config payloads.
    pub(crate) fn model_catalog_revision(&self) -> ConfigRuntimeResult<u64> {
        self.state
            .read()
            .map(|state| state.catalog.revision)
            .map_err(|_| config_runtime_poisoned())
    }

    /// 从已发布缓存取得启用 Profile 的执行视图；不扫描文件。
    pub fn agent_profiles(&self) -> ConfigRuntimeResult<super::AgentProfileCatalog> {
        Ok(self
            .profiles
            .read()
            .catalog
            .executable(pl_protocol::DelegationMode::Profile)?)
    }

    /// 读取已发布的 Agent Profiles 资源快照（完整配置与诊断）；纯缓存读取。
    pub fn agent_profiles_snapshot(&self) -> ConfigRuntimeResult<AgentProfilesSnapshot> {
        Ok(self.profiles.read())
    }

    /// 订阅 Agent Profiles 资源变更唤醒；值为最新 revision。
    pub fn subscribe_agent_profiles(&self) -> tokio::sync::watch::Receiver<u64> {
        self.profiles.subscribe()
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

    /// Resolves an enabled Profile and its model from the same snapshot; reads the published cache.
    ///
    /// # Errors
    /// Returns unknown/disabled Profile, configuration or account route errors.
    pub fn resolve_agent_profile(
        &self,
        profile_id: &str,
    ) -> ConfigRuntimeResult<ResolvedAgentProfile> {
        self.resolve_delegated_profile(profile_id, pl_protocol::DelegationMode::Profile, None)
    }

    /// Resolves role and model together, before allocating workspaces or provider resources.
    pub fn resolve_delegated_profile(
        &self,
        profile_id: &str,
        mode: pl_protocol::DelegationMode,
        selection: Option<pl_protocol::studio::NewThreadModelRoute>,
    ) -> ConfigRuntimeResult<ResolvedAgentProfile> {
        // Configuration commands also adopt the Profile cache before releasing this lock.
        // This pure resolution cannot combine a new config with the previous role catalog.
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        if profile_id == super::ROOT_AGENT_ROUTE_KEY {
            return Err(PureError::ConfigError(
                "planner is reserved for the main agent; this child role is retired and cannot resume".into(),
            ).into());
        }
        // Root Agent definitions are product built-in roles, not dispatchable child Profiles.
        if crate::agent::definition::is_root_definition_id(profile_id) {
            return Err(PureError::ConfigError(format!(
                "root Agent definition `{profile_id}` cannot be dispatched as a child agent"
            ))
            .into());
        }
        let snapshot = self.read()?;
        // Resolve the actual frozen/selected route below rather than replacing its diagnostic
        // with a generic "missing Profile" from the model-visible availability filter.
        let catalog = self.profiles.read().catalog.enabled_for_dispatch()?;
        let mut profile = catalog
            .profiles
            .into_iter()
            .find(|profile| profile.profile_id == profile_id && profile.enabled)
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "Agent Profile is missing or disabled: {profile_id}"
                ))
            })?;
        match (mode, selection) {
            (pl_protocol::DelegationMode::Profile, None) => {}
            (pl_protocol::DelegationMode::Profile, Some(_)) => {
                return Err(PureError::ConfigError(
                    "fixed Profile delegation forbids modelSelection".into(),
                )
                .into());
            }
            (pl_protocol::DelegationMode::Automatic, None) => {
                return Err(PureError::ConfigError(
                    "automatic delegation requires modelSelection".into(),
                )
                .into());
            }
            (pl_protocol::DelegationMode::Automatic, Some(selection)) => {
                profile.account_id = selection.account_id;
                profile.model_id = selection.model_id;
                profile.effort = selection.effort;
                let mut identity = profile.clone();
                identity.content_hash.clear();
                profile.content_hash = crate::canonical_content_hash(
                    &serde_json::to_vec(&identity).map_err(PureError::from)?,
                );
            }
        }
        let route = crate::studio::delegation::resolve_child_route(&snapshot.config, &profile)?;
        Ok(ResolvedAgentProfile {
            config: snapshot.config,
            revision: snapshot.revision,
            profile,
            route,
        })
    }

    /// 原子创建或替换一个用户 Agent Profile 文件。
    pub fn save_user_agent_profile(
        &self,
        expected_revision: u64,
        profile_id: &str,
        profile: &super::UserAgentProfile,
    ) -> ConfigRuntimeResult<ConfigProfileCommandResult> {
        self.save_user_agent_profile_phased(expected_revision, profile_id, profile)
            .map_err(ConfigRuntimeError::from)
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
        expected_revision: u64,
        edit: impl FnOnce(&StudioConfig, &StudioConfig) -> Result<StudioConfig>,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        let command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let (snapshot, publication, _) =
            self.update_with_effective_locked(expected_revision, edit)?;
        drop(command);
        self.notify_projection(publication);
        Ok(snapshot)
    }

    pub(crate) fn update_evidence(
        &self,
        expected_revision: u64,
        edit: impl FnOnce(&StudioConfig) -> Result<StudioConfig>,
    ) -> anyhow::Result<ConfigMutationEvidence> {
        self.update_with_effective_evidence(expected_revision, |desired, _| edit(desired))
    }

    pub(crate) fn replace_evidence(
        &self,
        expected_revision: u64,
        config: StudioConfig,
    ) -> anyhow::Result<ConfigMutationEvidence> {
        self.update_evidence(expected_revision, |_| Ok(config))
    }

    pub(crate) fn update_with_effective_evidence(
        &self,
        expected_revision: u64,
        edit: impl FnOnce(&StudioConfig, &StudioConfig) -> Result<StudioConfig>,
    ) -> anyhow::Result<ConfigMutationEvidence> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| ConfigMutationFailure::Preflight(config_runtime_poisoned()))?;
        let (snapshot, publication, profiles) =
            self.update_with_effective_locked(expected_revision, edit)?;
        let evidence = ConfigMutationEvidence {
            configuration: snapshot,
            catalog: publication.catalog.clone(),
            captures: publication.configuration_captures.clone(),
            profiles,
        };
        drop(_command);
        self.notify_projection(publication);
        Ok(evidence)
    }

    fn update_with_effective_locked(
        &self,
        expected_revision: u64,
        edit: impl FnOnce(&StudioConfig, &StudioConfig) -> Result<StudioConfig>,
    ) -> std::result::Result<
        (
            ConfigRuntimeSnapshot,
            ProjectionPublication,
            AgentProfilesEvidence,
        ),
        ConfigMutationFailure,
    > {
        let prepared = (|| -> ConfigRuntimeResult<_> {
            let (current, current_catalog) = self.read_with_catalog()?;
            ensure_revision(expected_revision, current.revision)?;
            let (desired, observations) = {
                let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
                if state.closing {
                    return Err(PureError::ConfigError("settings owner is closing".into()).into());
                }
                (state.desired.clone(), state.observations.clone())
            };
            let mut next_config = edit(&desired, &current.config)?;
            for account in next_config.models.accounts.values_mut() {
                account.clear_model_catalog_overlay();
            }
            let next_observations =
                model_catalog::reconcile(self.store.paths(), &next_config, &observations)?;
            let effective = effective_runtime_config(&next_config, &next_observations)?;
            effective.validate_declarations()?;
            validate_changed_selections(&desired, &effective)?;
            Ok((
                current,
                current_catalog,
                desired,
                observations,
                next_config,
                next_observations,
                effective,
            ))
        })();
        let (
            current,
            current_catalog,
            desired,
            observations,
            next_config,
            next_observations,
            effective,
        ) = prepared.map_err(ConfigMutationFailure::Preflight)?;

        // 文件和 credential IO 不持有 state lock；command lock 只负责串行化 Settings 命令。
        self.store
            .save(&next_config)
            .map_err(|error| ConfigMutationFailure::Commit(error.into()))?;

        let next = ConfigRuntimeSnapshot {
            revision: current.revision.saturating_add(1),
            updated_at: unix_seconds(),
            config: effective.clone(),
            canonical_config: next_config.clone(),
            usage_query_revisions: next_usage_query_revisions(&current, &effective),
        };
        // 目录投影必须在配置材料捕获之前取得：持久化已确定，观察与发布失败都不改动提交结论，
        // 只作为提交后的观察失败保留类型化诊断。此处不持有配置状态锁。
        let acp_directory = self.observe_settings_commit(&next);
        let catalog_changed = statuses(&next_observations) != current_catalog.catalogs
            || effective.models.accounts != current.config.models.accounts;
        let models_inputs_changed = catalog_changed
            || next_config.models != desired.models
            || next_config.web_search != desired.web_search
            || next_config.deepseek_web_search != desired.deepseek_web_search;
        let catalog = ModelCatalogRuntimeSnapshot {
            revision: current_catalog
                .revision
                .saturating_add(u64::from(catalog_changed)),
            updated_at: unix_seconds(),
            catalogs: statuses(&next_observations),
        };
        invalidate_observations(&observations, &next_observations);
        let mut state = self
            .state
            .write()
            .map_err(|_| ConfigMutationFailure::Confirmed(config_runtime_poisoned()))?;
        state.acp_directory = Some(acp_directory);
        state.desired = next_config;
        state.observations = next_observations;
        state.snapshot = next.clone();
        state.catalog = catalog;
        if models_inputs_changed {
            let observed_at = state.catalog.updated_at;
            model_projection::observe_source(&mut state.models_status, observed_at);
        }
        let publication = self.publish_projection_locked(&mut state);
        drop(state);
        // Capture the original adoption, not a later read/watch. Notify after command unlock.
        let adopted = self
            .profiles
            .adopt_scan_captured(self.store.paths(), &next.config);
        let evidence = adopted.evidence.clone();
        let mut publication = publication;
        publication.profiles = Some(adopted);
        Ok((next, publication, evidence))
    }

    /// 显式从磁盘重新加载配置；普通 read 永不调用此方法。
    pub fn reload_from_disk(
        &self,
        expected_revision: u64,
    ) -> ConfigRuntimeResult<ConfigReloadResult> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let (current, current_catalog) = self.read_with_catalog()?;
        ensure_revision(expected_revision, current.revision)?;
        if self
            .state
            .read()
            .map_err(|_| config_runtime_poisoned())?
            .closing
        {
            return Err(PureError::ConfigError("settings owner is closing".into()).into());
        }
        // Explicit reload must not adopt using a saturated, reused business watermark.
        let settings_revision = current
            .revision
            .checked_add(1)
            .ok_or_else(|| PureError::ConfigError("settings revision is exhausted".into()))?;
        let catalog_revision = current_catalog
            .revision
            .checked_add(1)
            .ok_or_else(|| PureError::ConfigError("model catalog revision is exhausted".into()))?;
        let desired = self.store.load_or_default()?;
        let observations = self
            .state
            .read()
            .map_err(|_| config_runtime_poisoned())?
            .observations
            .clone();
        let next_observations =
            model_catalog::reconcile(self.store.paths(), &desired, &observations)?;
        let config = effective_runtime_config(&desired, &next_observations)?;
        config.validate_declarations()?;
        super::AgentProfileCatalog::validate_for_startup(self.store.paths())?;
        let next = ConfigRuntimeSnapshot {
            revision: settings_revision,
            updated_at: unix_seconds(),
            config: config.clone(),
            canonical_config: desired.clone(),
            usage_query_revisions: next_usage_query_revisions(&current, &config),
        };
        // 重载同样先取得同版本的不可变 ACP 目录，再在原状态发布边界采用配置材料。
        let acp_directory = self.observe_settings_commit(&next);
        let catalog = ModelCatalogRuntimeSnapshot {
            revision: catalog_revision,
            updated_at: unix_seconds(),
            catalogs: statuses(&next_observations),
        };
        invalidate_observations(&observations, &next_observations);
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        state.acp_directory = Some(acp_directory);
        state.desired = desired;
        state.observations = next_observations;
        state.snapshot = next.clone();
        state.catalog = catalog;
        let observed_at = state.catalog.updated_at;
        model_projection::observe_source(&mut state.models_status, observed_at);
        let publication = self.publish_projection_locked(&mut state);
        let catalog = state.catalog.clone();
        drop(state);
        // 显式重扫；目录未变化时不提升 revision。
        let adopted = self
            .profiles
            .adopt_scan_captured(self.store.paths(), &next.config);
        let result = ConfigReloadResult {
            evidence: ConfigMutationEvidence {
                configuration: next.clone(),
                catalog: catalog.clone(),
                captures: publication.configuration_captures.clone(),
                profiles: adopted.evidence.clone(),
            },
            configuration: next,
            catalog,
            profiles: adopted.evidence.snapshot.clone(),
        };
        drop(_command);
        adopted.notify();
        self.notify_projection(publication);
        Ok(result)
    }

    pub(crate) fn set_system_agent_enabled(
        &self,
        expected_revision: u64,
        profile_id: &str,
        enabled: bool,
    ) -> ConfigRuntimeResult<ConfigProfileCommandResult> {
        self.set_system_agent_enabled_phased(expected_revision, profile_id, enabled)
            .map_err(ConfigRuntimeError::from)
    }
}

/// 与 `revision` 严格相符的 ACP 目录事实。
///
/// 只有同一 revision 的成功捕获才可交付（其行集可以就是空列表，即已确认空目录）；捕获值缺失、
/// 跨版本或捕获失败一律返回显式类型化失败，绝不补空列表或零连接代次。
fn acp_directory(
    revision: u64,
    capture: Option<&AcpDirectoryCapture>,
) -> std::result::Result<
    Arc<[pl_protocol::studio::AcpAccountSettings]>,
    Arc<pl_protocol::studio::StudioError>,
> {
    // 先要求匹配的同 revision 捕获并传播其错误；只有成功捕获（其中可以就是空列表）才构成该
    // 版本的目录事实。canonical 的空集合不能替代捕获，否则会把"来源未就绪/失败"伪造成已知空。
    match capture {
        Some(capture) if capture.settings_revision == revision => capture.accounts.clone(),
        Some(_) => Err(Arc::new(pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Protocol,
            "ACP directory projection does not match the committed Settings revision",
            false,
        ))),
        None => Err(Arc::new(pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Unavailable,
            "ACP directory projection is not prepared for this Settings revision",
            true,
        ))),
    }
}

fn projection_stamp(state: &RuntimeState) -> pl_protocol::studio::ConfigProjectionStamp {
    pl_protocol::studio::ConfigProjectionStamp {
        settings_revision: state.snapshot.revision,
        model_catalog_revision: state.catalog.revision,
        closing: state.closing,
    }
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
                .find(|model| model.model_id == *model_id)
                .ok_or_else(|| {
                    PureError::ConfigError(
                        "new connection override references unavailable model".into(),
                    )
                })?;
            if !model
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
    use crate::config::{ConfigPaths, ConfigStore};

    fn runtime() -> (tempfile::TempDir, ConfigRuntime) {
        let directory = tempfile::tempdir().expect("isolated config directory");
        let store = ConfigStore::new(ConfigPaths::from_config_dir(directory.path()));
        let runtime = ConfigRuntime::initialize(store).expect("default config initializes");
        (directory, runtime)
    }

    #[test]
    fn scalar_config_mutation_does_not_advance_catalog_clock() {
        let (_directory, runtime) = runtime();
        let before = runtime.read().expect("read config");
        let catalog_before = runtime.read_catalog().expect("read catalog");
        let next = runtime
            .update(before.revision, |config| {
                let mut next = config.clone();
                next.instructions.user = "independent config field".to_string();
                Ok(next)
            })
            .expect("update one field");

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
}
