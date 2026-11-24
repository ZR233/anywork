use crate::InteractionRequest;
use anyhow::Result;

use crate::StudioPromptInput;
use crate::config::ConfigRuntime;
use crate::studio::records::ThreadRecord;
use crate::studio::{ProductEventBus, StudioActiveTurn, StudioRuntimeState, StudioStore};

pub use crate::{ThreadPreparationProgress, ThreadPreparationStage};

/// Nonblocking observation of a creation command. The observer must not reenter the runtime;
/// losing observation does not cancel creation or transfer its resource ownership.
pub type ThreadPreparationObserver =
    std::sync::Arc<dyn Fn(ThreadPreparationProgress) + Send + Sync>;

mod account_usage;
pub mod accounts;
mod acp_accounts;
pub(crate) mod acp_business;
mod acp_detection;
pub(crate) mod acp_host_mcp;
mod acp_install;
mod acp_launch;
mod acp_workspace_tools;
pub use acp_business::{AcpSessionCompletion, AcpSessionObservation, AcpSessionOpen};
mod acp_worker;
mod attachment_drafts;
mod background_task;

mod bots_api;
mod bots_recovery;
pub(crate) mod chat_item;
mod chatgpt_auth;
mod command_receipts;
mod conversation_state_feed;
mod current_reader;
pub use current_reader::{CurrentBodyWatch, CurrentReader, CurrentWatch};
mod delegation_models;
mod directory_observation;
mod file_display;
pub use file_display::{DisplayDownloadOutcome, DisplayDownloadRequest};
mod history;
pub(crate) use history::history_turn;
mod lifecycle;
pub(in crate::studio) mod lsp_state;
mod mcp_api;
mod mode_definitions;
mod model_catalog;
mod model_performance;
mod model_refresh;
mod observation_lifecycle;
mod product_subscription;
mod prompt_runner;
mod pull_observation;
pub(crate) mod rejected_tools;
mod residency;
pub(in crate::studio) mod run_export;
mod session_entry;
pub(crate) mod session_tools;
mod settings_api;
mod shutdown_progress;
mod skill_catalog;
mod ssh;
mod state_query;
mod thread_mode;
mod thread_service;
mod thread_stream;

mod tool_refresh;
pub use directory_observation::{ThreadMetadataObservation, ThreadsObservation};
pub use product_subscription::StudioProductTopicSubscription;
pub use run_export::{
    BuildInfoV3, ChatItemHeaderExportV3, CompletionCursorV3, ConfigInputEntryV3,
    EVENTS_SCHEMA_VERSION, EventBodyV3, EventSourceV3, EventV3, ExecutionErrorStage,
    ExecutionErrorV3, ExecutionLifecycleExportV3, ExecutionOutcome, ExportSchemaV3, ExportedBlobV3,
    ExportedContentV3, ExportedHistoryEventHeaderV3, ModelUsageExportV3, RESULT_SCHEMA_VERSION,
    RUN_MANIFEST_SCHEMA_VERSION, ResultOutcome, ResultV3, RunExportOptions, RunExportReport,
    RunExporter, RunInvocationV3, RunManifestV3, SealedMemberCutV3, SkillSearchManifestV3,
    ThreadUsageExportV3, TimingReportV3, TraceSummaryV3, UsageCoverage, UsageExportV3,
    UsageKnownTotalsV3, UsageMetricKey, UsageTotalsV3,
    format_utc_rfc3339 as format_export_utc_rfc3339,
    prepare_output_dir as prepare_export_output_dir, sha256_hex as export_sha256_hex,
    validate_output_dir_preflight as validate_export_output_dir_preflight,
};
pub(crate) mod thread_observation;
mod thread_title;
mod updater;

pub(crate) use account_usage::AccountUsageCacheMigrationError;
pub(crate) use account_usage::AccountUsageRuntime;
pub(crate) use model_performance::ModelPerformanceOwner;
pub(crate) use shutdown_progress::ShutdownProgressBus;
pub(crate) use skill_catalog::SkillCatalogRuntime;
pub use skill_catalog::{SkillSearchResult, SkillsStateSnapshot};
pub use ssh::{SshPasswordUpdate, SshServerRuntimeEntry};
use thread_title::ThreadTitleTasks;
pub(crate) use updater::StudioUpdateRuntime;
pub use updater::*;

/// Studio UI 提交 prompt 的请求。
///
/// runtime 只负责产品投影；Turn ID、FIFO、取消与 canonical Thread 全部由
/// `pl_core::thread::ThreadHandle` 对应的 owner 管理。
pub struct StudioSubmitPromptRequest {
    pub thread_id: String,
    pub input: StudioPromptInput,
    pub options: StudioSubmitPromptOptions,
}

/// Creates a root Thread with the requested mode and submits its first prompt as one product command.
pub struct StudioStartNewThreadRequest {
    pub workspace_id: String,
    pub title: Option<String>,
    pub input: StudioPromptInput,
    pub mode: crate::mode::ThreadModeId,
    pub route: crate::NewThreadModelRoute,
    pub service_tier: Option<String>,
    pub delegation_mode: Option<crate::DelegationMode>,
    pub delegation_preference: Option<crate::DelegationPreference>,
    pub workspace_mode: crate::ThreadWorkspaceMode,
    pub options: StudioSubmitPromptOptions,
    pub preparation_observer: Option<ThreadPreparationObserver>,
}

/// Studio UI 提交 prompt 的附加选项。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct StudioSubmitPromptOptions {
    pub presentation: crate::MessagePresentation,
    /// Existing-Thread user submissions carry the route revision observed by
    /// their caller. Initial submission of an explicitly routed new Thread has
    /// no prior Client mirror and remains in the same lifecycle transaction.
    pub expected_model_route_revision: Option<u64>,
    /// Tightens this input's model-step budget without changing the Thread default.
    /// Child submissions remain bounded by the existing child policy.
    pub max_model_steps: Option<std::num::NonZeroU32>,
}

/// Studio 输入受理回执；实际 Turn 关联由 Thread 事实流提供。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioSubmitPromptResponse {
    pub thread_id: String,
    pub input_id: String,
    pub cursor: u64,
}

/// Result of creating a root Thread and accepting its first Turn.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioStartNewThreadResponse {
    pub thread: ThreadRecord,
    pub submission: StudioSubmitPromptResponse,
}

/// Result of archiving a root Thread tree.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioArchiveThreadResult {
    pub archived_root_id: String,
    pub removed_thread_ids: Vec<String>,
    pub next_root: Option<crate::SessionDirectoryRow>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameThreadCommandReply {
    pub thread: crate::SessionDirectoryRow,
    pub receipt: crate::StudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveThreadCommandReply {
    pub result: StudioArchiveThreadResult,
    pub receipt: crate::StudioCommandReceipt,
}

/// Result of permanently deleting a root Thread and all its descendants.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioDeleteThreadResult {
    pub deleted_root_id: String,
    pub deleted_thread_ids: Vec<String>,
    pub next_root: Option<crate::SessionDirectoryRow>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteThreadCommandReply {
    pub result: StudioDeleteThreadResult,
    pub receipt: crate::StudioCommandReceipt,
}

/// Studio UI resolve interaction 后的核心响应。
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioResolveInteractionResponse {
    pub thread_id: String,
    pub interaction: InteractionRequest,
    pub receipt: crate::StudioCommandReceipt,
}

/// 归档前「结束会话树活动工作」的有界等待上界。
///
/// 中断当前 Turn 与丢弃未消费输入只需取消进程内取消令牌；运行中任务的收束需要等其
/// 拥有的资源（例如工具进程树）终止，因此上界留出余量；但仍必须有限：超过上界仍未
/// 收束说明现场无法安全结束，归档必须显式失败并保留会话（design/01 §1.4）。
pub(in crate::studio::runtime) const ARCHIVE_TREE_SETTLE_TIMEOUT: std::time::Duration =
    std::time::Duration::from_secs(10);

#[derive(Clone)]
pub struct StudioRuntime {
    owner_epoch: String,
    startup_recovery: Option<crate::StudioStartupRecovery>,
    observations: std::sync::Arc<observation_lifecycle::RuntimeObservationOwner>,
    thread_observations: thread_observation::ThreadObservations,
    settings_updates: tokio::sync::watch::Sender<crate::config::ConfigRuntimeSnapshot>,
    settings_refresh: background_task::BackgroundTaskSlot,
    model_catalog_tasks: model_catalog::ModelCatalogTasks,
    tool_refresh: background_task::BackgroundTaskSlot,
    rejected_tools: rejected_tools::RejectedToolOwners,
    tool_catalog_updates: std::sync::Arc<tokio::sync::Notify>,
    sessions: crate::session::SessionTable,
    #[cfg(test)]
    s2_delete_publication_failure: std::sync::Arc<std::sync::Mutex<Option<String>>>,
    thread_factory: crate::studio::thread_factory::StudioThreadFactory,
    instance_lock: super::runtime_lock::RuntimeLockOwner,
    store: StudioStore,
    bots: crate::bots::BotRuntime,
    config_runtime: ConfigRuntime,
    external_runtimes: StudioExternalRuntimes,
    agent_facility: StudioAgentFacility,
    residency: residency::ThreadResidency,
    shutdown_progress: ShutdownProgressBus,
    runtime_state: StudioRuntimeState,
    recovery: crate::studio::StudioRecoveryRegistry,
    recovery_task: background_task::BackgroundTaskSlot,
    skills: SkillCatalogRuntime,
    thread_modes: crate::mode::ThreadModeManager,
    account_usage: AccountUsageRuntime,
    /// ACP 接入与认证 owner：连接身份、操作代次、探测资源与独立 `acpAuth` topic。
    acp_accounts: acp_accounts::AcpAccountRuntime,
    chatgpt_auth: chatgpt_auth::ChatGptAuthRuntime,
    /// 官方 server 准备 owner：与认证、Settings 相互独立的共享资产 owner。
    acp_install: acp_install::AcpInstallRuntime,
    /// Short local CLI probe; owns its operation and supervised cleanup.
    acp_detection: acp_detection::AcpLocalDetectionRuntime,
    model_performance: ModelPerformanceOwner,
    updater: StudioUpdateRuntime,
    activation: ProjectActivationRuntime,
    attachment_drafts: attachment_drafts::AttachmentDraftRuntime,
    ssh_manager: std::sync::Arc<pl_tool::remote::SshManager>,
    /// 外部服务（MCP/LSP/SSH）关闭 job 的常驻槽位；跨阶段与跨重试保留，超时不丢句柄。
    service_stops: lifecycle::shutdown::ServiceStopSlots,
    /// An archive or worktree cleanup owns lifecycle admission through its real terminal commit,
    /// independent of its caller. The shared slot retains completion for retry/shutdown.
    thread_lifecycle_task: background_task::BackgroundTaskSlot,
    lifecycle_lock: std::sync::Arc<tokio::sync::Mutex<()>>,
    /// 单向关闭终止闩：commit 后拒绝迟到安装。
    shutdown_latch: lifecycle::shutdown::ShutdownLatch,
    /// 退出关闭运行的共享完成句柄；反复退出只 join 同一后台任务。
    shutdown_run: lifecycle::shutdown::ShutdownRun,
    /// native 首次 close 触发的早期退出封闭所观测到的诊断；由随后同一 `execute_shutdown`
    /// 播种为成功前置条件，不吞、不伪成功。std `Mutex`，只在无 await 的短临界区内持有。
    early_exit_issues: std::sync::Arc<std::sync::Mutex<Vec<crate::StudioShutdownIssue>>>,
    title_tasks: ThreadTitleTasks,
    /// 仅用于把 Weak 宿主租约交给 bots；bots 不持有 StudioRuntime 强引用。
    bot_host: Option<std::sync::Arc<StudioRuntime>>,
}

#[derive(Clone)]
struct StudioExternalRuntimes {
    lsp: pl_lsp::runtime::LspRuntimeRegistry,
    lsp_state: lsp_state::LspStateRuntime,
}

#[derive(Clone)]
struct StudioAgentFacility {
    worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner,
    product_events: ProductEventBus,
    /// agent framework 的 write-behind writer 句柄；framework 被 take 后关机仍能排空。
    persistence: std::sync::Arc<
        tokio::sync::Mutex<Option<crate::studio::agent_host::ThreadWriteBehindWriter>>,
    >,
    run_export: Option<std::sync::Arc<run_export::RunExportCoordinator>>,
}

#[derive(Clone, Default)]
struct ProjectActivationRuntime {
    command_lock: std::sync::Arc<tokio::sync::Mutex<()>>,
    applied: std::sync::Arc<tokio::sync::RwLock<Option<ProjectActivation>>>,
}

#[derive(Clone, PartialEq, Eq)]
struct ProjectActivation {
    workspace_id: String,
    fingerprint: String,
}

impl StudioRuntime {
    /// Opens a native latest-value statistics feed from this runtime's existing statistics owner.
    pub fn open_statistics_feed(&self) -> pl_studio_statistics::StatisticsFeed {
        self.model_performance.subscribe_statistics()
    }

    /// 归档前结束会话树活动工作的有界等待上界。
    fn archive_settle_timeout(&self) -> std::time::Duration {
        ARCHIVE_TREE_SETTLE_TIMEOUT
    }

    /// 读取配置 owner 已发布的 Agent Profiles 资源快照。
    ///
    /// 纯缓存读取（完整配置与逐文件诊断），不扫描文件；外部手改 Profile 后需显式
    /// reload 设置才会形成新事实。
    pub(crate) fn read_agent_profiles_state(
        &self,
    ) -> Result<crate::StudioAgentProfilesStateSnapshot> {
        Ok(self.config_runtime.agent_profiles_snapshot()?.into())
    }

    /// 原子创建或保存一个用户 Agent Profile TOML。
    pub fn save_user_agent_profile(
        &self,
        operation_id: String,
        expected_revision: Option<&str>,
        profile_id: &str,
        profile: &crate::config::UserAgentProfile,
    ) -> Result<crate::SettingsCommandReply> {
        Self::validate_operation_id(&operation_id)?;
        let (state, changed) =
            self.config_runtime
                .save_user_agent_profile(expected_revision, profile_id, profile)?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            operation_id,
            &state,
            changed,
            crate::CommandEffectPoint::FutureSession,
        )
    }

    /// 启用或禁用不可编辑、不可删除的系统 Agent Profile。
    pub fn set_system_agent_enabled(
        &self,
        operation_id: String,
        profile_id: &str,
        enabled: bool,
    ) -> Result<crate::SettingsCommandReply> {
        Self::validate_operation_id(&operation_id)?;
        if !crate::config::is_system_profile_id(profile_id)? {
            anyhow::bail!("`{profile_id}` is not a system Agent Profile");
        }
        let profile_id = profile_id.to_string();
        let mut changed = false;
        let state = self
            .config_runtime
            .update_with_effective(None, |config, _| {
                let mut config = config.clone();
                if enabled {
                    changed = config.disabled_system_agents.remove(&profile_id);
                } else {
                    changed = config.disabled_system_agents.insert(profile_id.clone());
                }
                Ok(config)
            })?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            operation_id,
            &state,
            changed,
            crate::CommandEffectPoint::FutureSession,
        )
    }

    /// 立即重试待落库事实；查询和停止路径不需要调用本命令。
    pub async fn retry_persistence(&self) -> Result<crate::PersistenceStateSnapshot> {
        let persistence = self.agent_facility.persistence.lock().await.clone();
        let Some(persistence) = persistence else {
            return Ok(self.agent_facility.product_events.persistence_state());
        };
        persistence.retry_now();
        self.store.thread_persistence().retry_now();
        Ok(self.agent_facility.product_events.persistence_state())
    }

    /// Does not alter the independent product-directory write-behind retry.
    pub async fn retry_thread_history(
        &self,
        thread_id: &str,
        fault_generation: u64,
    ) -> Result<crate::PersistenceQueueSnapshot> {
        self.store
            .thread_persistence()
            .retry_history(thread_id, fault_generation)
            .await?;
        // The reliable writer's backlog and a producer's failed capture/archive are two independent
        // obligations: a healthy history write never stands in for the archive that failed. The same
        // GUI "retry save" action therefore also re-runs the active owner's owed output, through the
        // one CoreHandle, before the caller verifies the fence with `resume_thread_history`. A retry
        // that is not yet durable surfaces its typed failure and leaves the Thread paused; only its
        // success lets the existing explicit resume release the latch.
        if let Some(thread) = self
            .session_of(thread_id)
            .and_then(|session| session.thread(thread_id))
        {
            thread.retry_output_storage().await?;
        }
        Ok(self.persistence_queue_snapshot())
    }

    /// 硬故障恢复后的显式继续：只有当保存故障确实按 `fault_generation` 恢复后才解除准入闩。
    ///
    /// 这是与 [`Self::retry_thread_history`] **分开**的第二个动作。重试保存只负责把积压事实写下去，
    /// 绝不自行恢复模型/工具调用；本命令把调用方核验过的代数交给驻留 owner，由 owner 重新读取
    /// 后端 typed 报告，只有在代数匹配、故障已消失且每个已发布批次都已上交时才解除闩锁，随后
    /// 才能开始下一轮推理。代数过期、仍在上报故障或仍有未上交批次都会被拒绝，所以“继续”是恢复
    /// 的事实回执，而不是只改变外观的按钮。
    ///
    /// 不驻留的 Thread 没有活跃 owner，也就没有活跃的准入闩：此时返回成功且不激活任何 Thread。
    pub async fn resume_thread_history(
        &self,
        thread_id: &str,
        fault_generation: u64,
    ) -> Result<crate::PersistenceQueueSnapshot> {
        if let Some(thread) = self
            .session_of(thread_id)
            .and_then(|session| session.thread(thread_id))
        {
            thread.resume_storage(fault_generation).await?;
        }
        Ok(self.persistence_queue_snapshot())
    }

    /// 读取已发布的持久化队列 typed 快照（含 revision 与时间基线）。
    pub fn read_persistence_queue_state(&self) -> crate::StudioPersistenceQueueStateSnapshot {
        self.agent_facility.product_events.persistence_queue_state()
    }

    /// 进程级持久化队列压力与逐 Thread 水位。
    ///
    /// 唯一事实源是持有全部 per-Thread writer 的持久化协调器；本入口只是把它已观测到的
    /// 真实值投影为协议形态，不读取、不聚合、也不编造任何 GUI 本地计数。队列字节、最老
    /// 待保存年龄、在途字节与最近错误都直接来自协调器，缺失即为未知而非零。
    pub fn persistence_queue_snapshot(&self) -> crate::PersistenceQueueSnapshot {
        self.store
            .thread_persistence()
            .report_calls(self.store.calls());
        self.store.thread_persistence().queue_snapshot()
    }

    /// 从 agent framework 派生当前所有活动 turn。
    ///
    /// 活动 turn 列表不再手工维护：canonical source 是每个 agent 的
    /// 旧 Agent 镜像字段。这里聚合整棵 agent tree 的活动 turn，
    /// 用于 idle 判断。UI 不消费此列表（它从 per-thread 流读取 busy 状态）。
    async fn derive_active_turns(&self) -> Result<Vec<StudioActiveTurn>> {
        Ok(self
            .sessions
            .observed_threads()
            .into_iter()
            .flat_map(|(thread_id, handle)| {
                handle
                    .snapshot()
                    .turns
                    .iter()
                    .filter(|turn| turn.state == pl_core::thread::TurnState::Running)
                    .map(|turn| StudioActiveTurn {
                        thread_id: thread_id.clone(),
                        turn_id: turn.turn_id.clone(),
                    })
                    .collect::<Vec<_>>()
            })
            .collect())
    }

    async fn close_project_agent_trees(&self, thread_ids: &[String]) -> Result<()> {
        let mut roots = std::collections::BTreeSet::new();
        for id in thread_ids {
            let member = self
                .agent_facility
                .product_events
                .directory_member(id)?
                .or(self.store.directory_member(id)?)
                .ok_or_else(|| anyhow::anyhow!("close directory member is missing"))?;
            roots.insert(member.root_thread_id);
        }
        for root in roots {
            let mut members = self.store.read_directory_tree(&root).await?;
            for hot in self.agent_facility.product_events.members_for_root(&root)? {
                members.retain(|member| member.agent.thread_id != hot.agent.thread_id);
                members.push(hot);
            }
            let identities = members
                .into_iter()
                .map(
                    |member| crate::studio::store::thread_preparation::PreparationIdentity {
                        thread_id: member.agent.thread_id,
                        workspace_id: member.session.workspace_id,
                        parent_id: member.parent_thread_id,
                        root_id: member.root_thread_id,
                    },
                )
                .collect::<Vec<_>>();
            self.require_session(&root)?
                .close_tree(&root, &identities)
                .await?;
        }
        Ok(())
    }
}

// Legacy Task orchestration tests were removed with the fixed Task runtime.

#[cfg(test)]
pub(crate) mod bot_archive_test_host {
    //! Test-only Studio-private fixture, registered by studio::runtime.
    use std::path::Path;
    use std::sync::Arc;

    use anyhow::Result;
    use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
    use pl_model::model::ModelDefinition;

    use super::StudioRuntime;
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use crate::{StudioHostKind, StudioRuntimeOptions};

    pub(crate) struct BotArchiveTestHost {
        pub(crate) runtime: Arc<StudioRuntime>,
        // Retained without accepting: no test is expected to submit model work.
        _endpoint: std::net::TcpListener,
    }

    impl BotArchiveTestHost {
        pub(crate) async fn new(home: &Path) -> Result<Self> {
            Self::new_with_optional_file_input(home, false).await
        }

        pub(crate) async fn new_with_file_input(home: &Path) -> Result<Self> {
            Self::new_with_optional_file_input(home, true).await
        }

        async fn new_with_optional_file_input(home: &Path, file_input: bool) -> Result<Self> {
            let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
            let account_id = AccountId::new("bot-archive-fixture")?;
            let route = ModelRouteConfig {
                account_id: account_id.clone(),
                model_id: "archive-model".into(),
                effort: None,
            };
            let mut config = StudioConfig::default_config()?;
            config.models.accounts.clear();
            let mut model = ModelDefinition::compatible(&route.model_id);
            if file_input {
                use pl_model::model::{
                    MediaRepresentation, MediaWireFormat, ModelInputCapability, ModelInputSource,
                    ModelMediaInputProfile, ModelModality,
                };
                model
                    .extra
                    .capabilities
                    .input
                    .push(ModelInputCapability::media(
                        ModelModality::File,
                        vec![ModelInputSource::Local],
                    ));
                model
                    .extra
                    .binding
                    .request
                    .media
                    .push(ModelMediaInputProfile {
                        modality: ModelModality::File,
                        wire: MediaWireFormat::ChatFileUrl,
                        first_send: vec![MediaRepresentation::DataUrl],
                        replay: vec![MediaRepresentation::DataUrl],
                    });
            }
            config.models.accounts.insert(
                account_id,
                AccountConfig::from_explicit_models(
                    pl_model::protocol::providers::openai::compatible_endpoint(
                        "Bot archive fixture",
                        format!("http://{}", endpoint.local_addr()?),
                    ),
                    vec![model],
                ),
            );
            for selected in config
                .models
                .routes
                .values_mut()
                .chain(config.mode_model_routes.values_mut())
            {
                *selected = route.clone();
            }
            ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
            let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(home.to_owned()),
                host: StudioHostKind::Test,
                skill_search: pl_tool::skill::SkillSearchOptions {
                    include_default_user_dir: false,
                    additional_dirs: Vec::new(),
                },
                ..StudioRuntimeOptions::desktop()
            })
            .await?;
            Ok(Self {
                runtime: Arc::new(runtime),
                _endpoint: endpoint,
            })
        }

        pub(crate) fn bots(&self) -> crate::bots::BotRuntime {
            self.runtime.bots.clone()
        }

        pub(crate) fn lifecycle_lock(&self) -> &tokio::sync::Mutex<()> {
            &self.runtime.lifecycle_lock
        }

        pub(crate) fn resources_dir(
            &self,
            workspace_id: &str,
            thread_id: &str,
        ) -> Result<std::path::PathBuf> {
            Ok(self
                .runtime
                .store
                .session_paths(workspace_id, thread_id)?
                .resources_dir())
        }

        pub(crate) fn drafts_dir(&self) -> std::path::PathBuf {
            self.runtime.store.attachment_drafts_dir()
        }
    }
}
