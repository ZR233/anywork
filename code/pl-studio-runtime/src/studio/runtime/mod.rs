use crate::InteractionRequest;
use anyhow::Result;

use crate::config::ConfigRuntime;
use crate::studio::records::ThreadRecord;
use crate::studio::{ProductEventBus, StudioActiveTurn, StudioRuntimeState, StudioStore};
use pl_protocol::studio::StudioPromptInput;
use pl_tool::mcp::McpRuntimeHandle;

pub use pl_protocol::studio::{ThreadPreparationProgress, ThreadPreparationStage};

/// Nonblocking observation of a creation command. The observer must not reenter the runtime;
/// losing observation does not cancel creation or transfer its resource ownership.
pub type ThreadPreparationObserver =
    std::sync::Arc<dyn Fn(ThreadPreparationProgress) + Send + Sync>;

pub mod account_usage;
pub mod acp_auth;
pub mod acp_install;
pub mod attachment_binary;
mod attachment_drafts;
mod background_task;
pub mod bots;
mod bots_api;
mod bots_recovery;
pub(crate) mod chat_item;
mod command_receipts;
pub mod configuration;
mod delegation_models;
pub mod draft_commands;
mod history;
mod lifecycle;
pub mod lsp;
mod lsp_state;
pub mod mcp;
mod mcp_health;
mod mode_definitions;
mod model_catalog;
mod model_performance;
mod model_refresh;
pub mod models;
pub mod modes;
mod observation_ids;
pub mod persistence;
mod product_subscription;
mod prompt_runner;
mod read_budget;
mod read_calls;
mod read_scopes;
pub mod recovery;
mod rejected_tools;
pub mod remote_directory;
pub mod skills;
pub mod startup;
pub mod statistics;
pub mod updates;
pub mod workspace;
pub(crate) use rejected_tools::RejectedToolsCloseFailure;
mod residency;
pub(crate) mod session_tools;
mod settings_api;
mod shutdown_progress;
mod skill_catalog;
mod ssh;
mod state_query;
pub mod thread_authoring;
pub mod thread_authoring_read;
pub mod thread_configuration;
pub mod thread_configuration_read;
pub mod thread_context;
pub mod thread_context_read;
pub mod thread_execution;
pub mod thread_execution_read;
mod thread_metrics;
mod thread_metrics_read;
mod thread_mode;
mod thread_service;
mod thread_stream;
pub(in crate::studio) mod timeline;
pub(crate) mod timeline_content;
mod tool_refresh;
pub use product_subscription::StudioProductTopicSubscription;
pub use thread_metrics::{
    StudioMetricsSample, StudioMetricsSourceEvent, StudioThreadMetricsSource,
};
pub use thread_metrics_read::StudioMetricsIdentityRead;
pub use thread_stream::StudioThreadSubscription;
pub use timeline_content::{TimelineContentReader, TimelineTailStream};
mod thread_observation;
pub(crate) use thread_observation::ObservationCloseFailure;
mod thread_reads;
mod thread_title;
mod updater;

pub(crate) use account_usage::AccountUsageRuntime;
pub use account_usage::{AccountUsageStateData, AccountUsageStateSnapshot};
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
    pub project_id: String,
    pub title: Option<String>,
    pub input: StudioPromptInput,
    pub mode: pl_protocol::ThreadModeId,
    pub route: pl_protocol::studio::NewThreadModelRoute,
    pub delegation_mode: Option<pl_protocol::DelegationMode>,
    pub delegation_preference: Option<pl_protocol::DelegationPreference>,
    pub workspace_mode: pl_protocol::ThreadWorkspaceMode,
    pub options: StudioSubmitPromptOptions,
    pub preparation_observer: Option<ThreadPreparationObserver>,
}

/// Studio UI 提交 prompt 的附加选项。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct StudioSubmitPromptOptions {
    pub presentation: pl_protocol::MessagePresentation,
    /// Existing-Thread user submissions carry the route revision observed by
    /// their caller. Initial submission of an explicitly routed new Thread has
    /// no prior Client mirror and remains in the same lifecycle transaction.
    pub expected_model_route_revision: Option<u64>,
}

/// Studio 输入受理回执；实际 Turn 关联由 Thread 事实流提供。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioSubmitPromptResponse {
    pub thread_id: String,
    pub input_id: String,
    pub cursor: u64,
    pub request_digest: String,
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
    pub next_root: Option<ThreadRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameThreadCommandReply {
    pub thread: ThreadRecord,
    pub receipt: pl_protocol::studio::StudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveThreadCommandReply {
    pub result: StudioArchiveThreadResult,
    pub receipt: pl_protocol::studio::StudioCommandReceipt,
}

/// Studio UI resolve interaction 后的核心响应。
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioResolveInteractionResponse {
    pub thread_id: String,
    pub interaction: InteractionRequest,
    pub receipt: pl_protocol::studio::StudioCommandReceipt,
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
    read_calls: read_calls::ReadCalls,
    read_scopes: read_scopes::ReadScopeRegistry,
    observation_ids: observation_ids::ObservationIds,
    models_source: std::sync::Arc<crate::config::ModelCatalogSource>,
    configuration_source: std::sync::Arc<crate::config::ConfigurationSource>,
    mcp_source: std::sync::Arc<mcp::source::McpSource>,
    lsp_source: std::sync::Arc<lsp::source::LspSource>,
    skills_source: std::sync::Arc<skills::sources::SkillsSources>,
    profiles_source: std::sync::Arc<crate::config::ProfilesSource>,
    templates_source: std::sync::Arc<models::TemplatesSource>,
    bots_source: std::sync::Arc<bots::BotsSource>,
    workspace_source: std::sync::Arc<workspace::WorkspaceProductSource>,
    startup_source: std::sync::Arc<startup::StartupSource>,
    recovery_source: std::sync::Arc<recovery::RecoverySource>,
    persistence_source: std::sync::Arc<persistence::PersistenceSource>,
    persistence_queue_source: std::sync::Arc<persistence::PersistenceQueueSource>,
    remote_directory_source: std::sync::Arc<remote_directory::RemoteDirectorySource>,
    modes_source: std::sync::Arc<modes::ModesSource>,
    usage_source: std::sync::Arc<account_usage::UsageSource>,
    statistics_source: std::sync::Arc<statistics::StatisticsSource>,
    updates_source: std::sync::Arc<updates::UpdatesSource>,
    startup_recovery: Option<crate::StudioStartupRecovery>,
    persistence_observer: background_task::BackgroundTaskSlot,
    thread_observations: thread_observation::ThreadObservations,
    settings_updates: tokio::sync::watch::Sender<crate::config::ConfigRuntimeSnapshot>,
    settings_refresh: background_task::BackgroundTaskSlot,
    model_catalog_tasks: model_catalog::ModelCatalogTasks,
    tool_refresh: background_task::BackgroundTaskSlot,
    rejected_tools: rejected_tools::RejectedToolOwners,
    tool_catalog_updates: std::sync::Arc<tokio::sync::Notify>,
    threads: crate::thread_assembler::StudioThreadAssembler,
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
    acp_auth: acp_auth::AcpAuthRuntime,
    /// 官方 server 准备 owner：与认证、Settings 相互独立的共享资产 owner。
    acp_install: acp_install::AcpInstallRuntime,
    model_performance: ModelPerformanceOwner,
    /// 统计进度 follower：调用库的统计受理/落库/缺口 watch → 同一 owner 的投影发布任务。
    ///
    /// runtime 持有该任务（`BackgroundTaskSlot`）：shutdown 先广播取消、再在独立资源组以同一
    /// 首次期限有界 join；超时不丢句柄，slot 的 Drop 只 abort 不 join。
    statistics_follower: background_task::BackgroundTaskSlot,
    updater: StudioUpdateRuntime,
    activation: ProjectActivationRuntime,
    attachment_drafts: attachment_drafts::AttachmentDraftRuntime,
    draft_commands: draft_commands::DraftCommandRegistry,
    ssh_manager: std::sync::Arc<pl_tool::remote::SshManager>,
    /// Linux 本地工作区按需物化受监督 worker（本地工具执行与本地 LSP 宿主）时保留的 remote
    /// helper 来源；其他平台没有本地 worker 物化路径（Windows 本地执行走原生 Job 监督、远端
    /// helper 分发走 `ssh_manager`），因此不保留该字段。
    #[cfg(target_os = "linux")]
    helper_source: crate::worker_assets::RemoteHelperSource,
    /// An archive or worktree cleanup owns lifecycle admission through its real terminal commit,
    /// independent of its caller. The shared slot retains completion for retry/shutdown.
    thread_lifecycle_task: background_task::BackgroundTaskSlot,
    lifecycle_lock: std::sync::Arc<tokio::sync::Mutex<()>>,
    /// 单向关闭终止闩：commit 后拒绝迟到安装。
    shutdown_latch: lifecycle::shutdown::ShutdownLatch,
    /// 原关闭协调器：跨 strict/exit 持有阶段 completion、首个退出前置与最终成功许可。
    shutdown_run: lifecycle::shutdown::ShutdownRun,
    /// native 首次 close 触发的早期退出封闭所观测到的诊断；由随后同一 `execute_shutdown`
    /// 播种为成功前置条件，不吞、不伪成功。std `Mutex`，只在无 await 的短临界区内持有。
    early_exit_issues: std::sync::Arc<std::sync::Mutex<Vec<crate::StudioShutdownIssue>>>,
    title_tasks: ThreadTitleTasks,
    /// Agent Profiles 配置 watch → product bus 转发任务；runtime 持有，shutdown 先广播取消
    /// 再在独立资源组以同一首次期限有界 join——失败 / 超时经 collector 令 `Clean` 不可达并
    /// 保留 owner（常驻槽位超时不丢句柄）。
    profiles_forwarder: background_task::BackgroundTaskSlot,
    /// 仅用于把 Weak 宿主租约交给 bots；bots 不持有 StudioRuntime 强引用。
    bot_host: Option<std::sync::Arc<StudioRuntime>>,
}

#[derive(Clone)]
struct StudioExternalRuntimes {
    mcp: McpRuntimeHandle,
    mcp_state: mcp_health::McpStateRuntime,
    mcp_config_watcher: background_task::BackgroundTaskSlot,
    mcp_health_watcher: background_task::BackgroundTaskSlot,
    lsp: pl_lsp::runtime::LspRuntimeRegistry,
    lsp_state: lsp_state::LspStateRuntime,
    lsp_state_watcher: background_task::BackgroundTaskSlot,
}

#[derive(Clone)]
struct StudioAgentFacility {
    worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner,
    product_events: ProductEventBus,
    /// agent framework 的 write-behind writer 句柄；framework 被 take 后关机仍能排空。
    persistence: std::sync::Arc<
        tokio::sync::Mutex<Option<crate::studio::agent_host::ThreadWriteBehindWriter>>,
    >,
}

#[derive(Clone, Default)]
struct ProjectActivationRuntime {
    command_lock: std::sync::Arc<tokio::sync::Mutex<()>>,
    applied: std::sync::Arc<tokio::sync::RwLock<Option<ProjectActivation>>>,
}

#[derive(Clone, PartialEq, Eq)]
struct ProjectActivation {
    project_id: String,
    fingerprint: String,
}

impl StudioRuntime {
    /// 归档前结束会话树活动工作的有界等待上界。
    fn archive_settle_timeout(&self) -> std::time::Duration {
        ARCHIVE_TREE_SETTLE_TIMEOUT
    }

    /// 读取配置 owner 已发布的 Agent Profiles 资源快照。
    ///
    /// 纯缓存读取（完整配置与逐文件诊断），不扫描文件；外部手改 Profile 后需显式
    /// reload 设置才会形成新事实。
    pub fn read_agent_profiles_state(&self) -> Result<crate::StudioAgentProfilesStateSnapshot> {
        Ok(self.config_runtime.agent_profiles_snapshot()?.into())
    }

    /// 原子创建或保存一个用户 Agent Profile TOML。
    pub fn save_user_agent_profile(
        &self,
        operation_id: String,
        expected_settings_revision: u64,
        profile_id: &str,
        profile: &crate::config::UserAgentProfile,
    ) -> Result<pl_protocol::studio::SettingsCommandReply> {
        Self::validate_operation_id(&operation_id)?;
        let committed = self.config_runtime.save_user_agent_profile(
            expected_settings_revision,
            profile_id,
            profile,
        )?;
        self.publish_settings_state()?;
        let mut reply = self.settings_command_reply(
            operation_id,
            &committed.configuration,
            committed.changed,
            pl_protocol::studio::CommandEffectPoint::FutureSession,
        )?;
        reply
            .receipt
            .targets
            .push(self.resource_stamp("agent-profiles", committed.profiles.revision));
        Ok(reply)
    }

    /// 启用或禁用不可编辑、不可删除的系统 Agent Profile。
    pub fn set_system_agent_enabled(
        &self,
        operation_id: String,
        expected_settings_revision: u64,
        profile_id: &str,
        enabled: bool,
    ) -> Result<pl_protocol::studio::SettingsCommandReply> {
        Self::validate_operation_id(&operation_id)?;
        if !crate::config::is_system_profile_id(profile_id)? {
            anyhow::bail!("`{profile_id}` is not a system Agent Profile");
        }
        let committed = self.config_runtime.set_system_agent_enabled(
            expected_settings_revision,
            profile_id,
            enabled,
        )?;
        self.publish_settings_state()?;
        let mut reply = self.settings_command_reply(
            operation_id,
            &committed.configuration,
            committed.changed,
            pl_protocol::studio::CommandEffectPoint::FutureSession,
        )?;
        reply
            .receipt
            .targets
            .push(self.resource_stamp("agent-profiles", committed.profiles.revision));
        Ok(reply)
    }

    /// Does not alter the independent product-directory write-behind retry.
    pub async fn retry_thread_history(
        &self,
        thread_id: &str,
        fault_generation: u64,
    ) -> Result<pl_protocol::PersistenceQueueSnapshot> {
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
        if let Some(thread) = self.threads.thread(thread_id) {
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
    ) -> Result<pl_protocol::PersistenceQueueSnapshot> {
        if let Some(thread) = self.threads.thread(thread_id) {
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
    pub fn persistence_queue_snapshot(&self) -> pl_protocol::PersistenceQueueSnapshot {
        self.store
            .thread_persistence()
            .report_calls(self.store.calls().metrics());
        self.store.thread_persistence().queue_snapshot()
    }

    /// 从 agent framework 派生当前所有活动 turn。
    ///
    /// 活动 turn 列表不再手工维护：canonical source 是每个 agent 的
    /// 旧 Agent 镜像字段。这里聚合整棵 agent tree 的活动 turn，
    /// 用于 idle 判断。UI 不消费此列表（它从 per-thread 流读取 busy 状态）。
    async fn derive_active_turns(&self) -> Result<Vec<StudioActiveTurn>> {
        Ok(self
            .threads
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
            roots.insert(self.read_owned_thread(id).await?.root_thread_id);
        }
        for root in roots {
            self.threads.close_tree(&root).await?;
        }
        Ok(())
    }
}

// Legacy Task orchestration tests were removed with the fixed Task runtime.
