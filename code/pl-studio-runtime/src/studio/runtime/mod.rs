use crate::InteractionRequest;
use anyhow::Result;

use crate::config::ConfigRuntime;
use crate::studio::records::ThreadRecord;
use crate::studio::{ProductEventBus, StudioActiveTurn, StudioRuntimeState, StudioStore};
use pl_protocol::studio::StudioPromptInput;

pub use pl_protocol::studio::{ThreadPreparationProgress, ThreadPreparationStage};

/// Nonblocking observation of a creation command. The observer must not reenter the runtime;
/// losing observation does not cancel creation or transfer its resource ownership.
pub type ThreadPreparationObserver =
    std::sync::Arc<dyn Fn(ThreadPreparationProgress) + Send + Sync>;

mod account_usage;
pub mod accounts;
mod acp_auth;
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
mod conversation_feed;
pub(in crate::studio) mod conversation_reader;
mod conversation_state_feed;
mod delegation_models;
mod directory_observation;
mod history;
mod lifecycle;
pub(in crate::studio) mod lsp_state;
mod mcp_api;
mod mode_definitions;
mod model_catalog;
mod model_performance;
mod model_refresh;
pub(super) mod presentation_reader;
mod product_subscription;
mod prompt_runner;
pub(crate) mod rejected_tools;
mod residency;
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
pub(in crate::studio) mod timeline;

mod tool_refresh;
pub use conversation_feed::{ConversationEvent, ConversationFeed};
pub use conversation_reader::{ContentWatch, ConversationReader};
pub use conversation_state_feed::ConversationStateFeed;
pub use directory_observation::{ThreadMetadataObservation, ThreadsObservation};
mod timeline_reader;
pub use presentation_reader::DisplayMembers;
pub use product_subscription::StudioProductTopicSubscription;
pub use timeline_reader::TimelineReader;
pub(crate) mod thread_observation;
mod thread_title;
mod updater;

pub(crate) use account_usage::AccountUsageCacheMigrationError;
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
    pub workspace_id: String,
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
    pub next_root: Option<pl_protocol::SessionDirectoryRow>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameThreadCommandReply {
    pub thread: pl_protocol::SessionDirectoryRow,
    pub receipt: pl_protocol::studio::StudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveThreadCommandReply {
    pub result: StudioArchiveThreadResult,
    pub receipt: pl_protocol::studio::StudioCommandReceipt,
}

/// Result of permanently deleting a root Thread and all its descendants.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioDeleteThreadResult {
    pub deleted_root_id: String,
    pub deleted_thread_ids: Vec<String>,
    pub next_root: Option<pl_protocol::SessionDirectoryRow>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteThreadCommandReply {
    pub result: StudioDeleteThreadResult,
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
    startup_recovery: Option<crate::StudioStartupRecovery>,
    persistence_observer: background_task::BackgroundTaskSlot,
    thread_observations: thread_observation::ThreadObservations,
    settings_updates: tokio::sync::watch::Sender<crate::config::ConfigRuntimeSnapshot>,
    settings_refresh: background_task::BackgroundTaskSlot,
    model_catalog_tasks: model_catalog::ModelCatalogTasks,
    tool_refresh: background_task::BackgroundTaskSlot,
    rejected_tools: rejected_tools::RejectedToolOwners,
    tool_catalog_updates: std::sync::Arc<tokio::sync::Notify>,
    sessions: crate::session::SessionTable,
    acp_workers: std::sync::Arc<pl_remote_helper::Executor>,
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
    acp_auth: acp_auth::AcpAuthRuntime,
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
    host_mcp_source: crate::host_mcp_assets::HostMcpSource,
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
    /// Agent Profiles 配置 watch → product bus 转发任务；runtime 持有，shutdown 先广播取消
    /// 再在独立资源组以同一首次期限有界 join——失败 / 超时经 collector 令 `Clean` 不可达并
    /// 保留 owner（常驻槽位超时不丢句柄）。
    profiles_forwarder: background_task::BackgroundTaskSlot,
    /// 仅用于把 Weak 宿主租约交给 bots；bots 不持有 StudioRuntime 强引用。
    bot_host: Option<std::sync::Arc<StudioRuntime>>,
}

#[derive(Clone)]
struct StudioExternalRuntimes {
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
        let (state, changed) = self.config_runtime.save_user_agent_profile(
            expected_settings_revision,
            profile_id,
            profile,
        )?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            operation_id,
            &state,
            changed,
            pl_protocol::studio::CommandEffectPoint::FutureSession,
        )
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
        let profile_id = profile_id.to_string();
        let mut changed = false;
        let state = self
            .config_runtime
            .update(expected_settings_revision, |config| {
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
            pl_protocol::studio::CommandEffectPoint::FutureSession,
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
    ) -> Result<pl_protocol::PersistenceQueueSnapshot> {
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
    pub fn persistence_queue_snapshot(&self) -> pl_protocol::PersistenceQueueSnapshot {
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
    use pl_model::model::ModelInfo;
    use pl_model::protocol::ProtocolEndpoint;

    use super::StudioRuntime;
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use crate::studio::store::thread_archive::{
        ArchivePhase, ArchiveScope, ThreadArchiveOperation,
    };
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
            let mut model = ModelInfo::compatible(&route.model_id);
            if file_input {
                use pl_model::model::{
                    MediaRepresentation, MediaWireFormat, ModelInputCapability, ModelInputSource,
                    ModelMediaInputProfile, ModelModality,
                };
                model.capabilities.input.push(ModelInputCapability::media(
                    ModelModality::File,
                    vec![ModelInputSource::Local],
                ));
                model.binding.request.media.push(ModelMediaInputProfile {
                    modality: ModelModality::File,
                    wire: MediaWireFormat::ChatFileUrl,
                    first_send: vec![MediaRepresentation::DataUrl],
                    replay: vec![MediaRepresentation::DataUrl],
                });
            }
            config.models.accounts.insert(
                account_id,
                AccountConfig::from_explicit_models(
                    ProtocolEndpoint::compatible(
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

        pub(crate) async fn restart(&self) -> Result<Self> {
            let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(self.runtime.store.paths().home().to_owned()),
                host: StudioHostKind::Test,
                ..StudioRuntimeOptions::desktop()
            })
            .await?;
            Ok(Self {
                runtime: Arc::new(runtime),
                _endpoint: self._endpoint.try_clone()?,
            })
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

        pub(crate) async fn seal_thread(&self, thread_id: &str) -> Result<()> {
            // A durable scope seal alone must reject dispatch, independently of
            // resident producers and even before member cleanup has completed.
            self.runtime
                .store
                .save_thread_archive(&ThreadArchiveOperation {
                    scope: ArchiveScope::Thread(thread_id.into()),
                    revision: 1,
                    members: Vec::new(),
                    private_members: Vec::new(),
                    worktrees: Vec::new(),
                    phase: ArchivePhase::Sealed,
                })
                .await
        }
    }
}

#[cfg(test)]
mod timeline_backlog_tests {
    //! Ordinary reliable backlog preserves immutable completions through the original writer.
    use super::*;
    use crate::runtime_test_support as support;
    use anyhow::{Context, Result, bail, ensure};
    use futures::FutureExt as _;
    use pl_core::{
        context::OpaquePayload,
        model::{
            DynModelSession, Model, ModelError, ModelFactory, ModelFailureKind, ModelMemberSender,
            ModelRequest, ModelSession, ModelStepOutput, ModelTextChannel, ObservedItemKind,
            ObservedPartIdentity, ObservedPartKind, PreparedModelCall, ProviderPartIdentity,
        },
        thread::{ModelStepLimit, ThreadHandle, TurnInput, TurnOutcome},
    };
    use pl_model::{
        completion::{
            CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
            CompletionPresentationPartKind,
        },
        runtime::{ModelMemberReceipt, ModelMemberState},
    };
    use pl_protocol::*;
    use sea_orm::{ConnectionTrait, Database, DatabaseConnection, DbBackend, Statement};
    use std::{
        panic::AssertUnwindSafe,
        sync::{Arc, Mutex},
    };
    use tokio::sync::{Semaphore, watch};
    use tokio_util::sync::CancellationToken;

    const WINDOW: usize = 128;
    const PREFIX_MEMBERS: usize = 2 * WINDOW;
    // Cross several ordinary credit windows without claiming to exercise the writer's capacity limit.
    const SUFFIX_MEMBERS: usize = 2 * WINDOW;
    const TEXT: &str = "T completed before R; 正文与附件所有权不能随普通积压中断";
    const R: &str = "a34-r";
    const T: &str = "a34-t";
    const U: &str = "a34-u";

    #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
    enum Stage {
        Initial,
        FirstWindow,
        Cut,
        SuffixReady,
    }

    /// Only a model environment: it emits canonical starts/receipts through Core's
    /// original one-slot member port. It has no projection, storage or maintenance logic.
    struct Script {
        stage: watch::Sender<Stage>,
        next: Semaphore,
        diagnostic: Mutex<ProducerDiagnostic>,
    }
    #[derive(Debug, Default)]
    struct ProducerDiagnostic {
        operation: String,
        acknowledged: u64,
        finished: Option<String>,
    }
    impl Script {
        fn new() -> Arc<Self> {
            Arc::new(Self {
                stage: watch::channel(Stage::Initial).0,
                next: Semaphore::new(0),
                diagnostic: Mutex::new(ProducerDiagnostic::default()),
            })
        }
        async fn reached(&self, target: Stage) -> Result<()> {
            let mut stage = self.stage.subscribe();
            loop {
                if *stage.borrow_and_update() >= target {
                    return Ok(());
                }
                if let Some(finished) = &self.diagnostic.lock().unwrap().finished {
                    bail!("producer ended before {target:?}: {finished}");
                }
                stage.changed().await?;
            }
        }
        fn operation(&self, operation: String) {
            self.diagnostic.lock().unwrap().operation = operation;
        }
        fn acknowledged(&self) {
            self.diagnostic.lock().unwrap().acknowledged += 1;
        }
        fn finished(&self, result: String) {
            self.diagnostic.lock().unwrap().finished = Some(result);
            // A retained sender is not proof the producer can still reach its next
            // boundary. Wake reached() on the producer's actual exit, too.
            self.stage.send_modify(|_| {});
        }
        fn release(&self) {
            self.next.add_permits(1);
        }
        async fn boundary(&self, stage: Stage, cancel: &CancellationToken) -> Result<()> {
            self.operation(format!("boundary {stage:?}"));
            self.stage.send_replace(stage);
            tokio::select! {
                biased;
                () = cancel.cancelled() => bail!("A34 model cancelled at {stage:?}"),
                permit = self.next.acquire() => permit?.forget(),
            }
            Ok(())
        }
    }

    struct ScriptModel(Arc<Script>);
    impl Model for ScriptModel {
        async fn open_session(&self) -> std::result::Result<DynModelSession, ModelError> {
            Ok(DynModelSession::new(ScriptSession(self.0.clone())))
        }
    }
    struct ScriptSession(Arc<Script>);
    impl ModelSession for ScriptSession {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> std::result::Result<PreparedModelCall, ModelError> {
            let script = self.0.clone();
            Ok(PreparedModelCall::new(async move {
                emit(&script, &request).await.map_err(|error| {
                    script.finished(format!("model emitter: {error:#}"));
                    ModelError {
                        kind: ModelFailureKind::InvalidResponse,
                        details: None,
                        usage: Box::default(),
                        source: Some(error.into_boxed_dyn_error()),
                    }
                })?;
                Ok(ModelStepOutput {
                    turn_action: Default::default(),
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    // T was independently completed through the member port already.
                    // Do not synthesize a second final message at response completion.
                    content: vec![],
                    tool_calls: vec![],
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }
        async fn close(&mut self) -> std::result::Result<(), ModelError> {
            Ok(())
        }
    }

    fn identity(id: &str, reasoning: bool) -> ObservedPartIdentity {
        ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: id.into(),
            output_index: None,
            content_index: 0,
            item_kind: if reasoning {
                ObservedItemKind::Reasoning
            } else {
                ObservedItemKind::Text(ModelTextChannel::Final)
            },
            part: if reasoning {
                ObservedPartKind::ReasoningText
            } else {
                ObservedPartKind::OutputText
            },
        })
    }
    fn receipt(id: &str, reasoning: bool, text: &str) -> Result<OpaquePayload> {
        Ok(OpaquePayload::new(
            "pl.model.completed-member",
            1,
            serde_json::to_string(&ModelMemberReceipt {
                item: CompletionPresentationItem {
                    provider_item_id: id.into(),
                    output_index: None,
                    kind: if reasoning {
                        CompletionPresentationItemKind::Reasoning
                    } else {
                        CompletionPresentationItemKind::Text(
                            pl_protocol::trace::TraceTextChannel::Final,
                        )
                    },
                    parts: vec![CompletionPresentationPart {
                        content_index: 0,
                        provider_part_id: None,
                        text: text.into(),
                        kind: if reasoning {
                            CompletionPresentationPartKind::ReasoningText
                        } else {
                            CompletionPresentationPartKind::OutputText
                        },
                    }],
                },
                state: ModelMemberState::Completed,
            })?,
        )?)
    }
    async fn complete(
        script: &Script,
        members: &ModelMemberSender,
        id: &str,
        reasoning: bool,
        text: &str,
        cancellation: &CancellationToken,
    ) -> Result<()> {
        script.operation(format!("terminal {id}"));
        members
            .submit(
                0,
                id.into(),
                receipt(id, reasoning, text)?,
                Some(cancellation),
            )
            .await
            .with_context(|| format!("canonical terminal {id}"))?;
        script.acknowledged();
        Ok(())
    }
    async fn start(
        script: &Script,
        members: &ModelMemberSender,
        id: &str,
        reasoning: bool,
        cancellation: &CancellationToken,
    ) -> Result<()> {
        script.operation(format!("start {id}"));
        members
            .start(0, identity(id, reasoning), Some(cancellation))
            .await
            .with_context(|| format!("canonical start {id}"))?;
        script.acknowledged();
        Ok(())
    }
    async fn emit(script: &Script, request: &ModelRequest) -> Result<()> {
        let members = request.members.as_ref().context("real Core member port")?;
        let cancellation = &request.cancellation;
        start(script, members, R, true, cancellation).await?;
        for index in 0..PREFIX_MEMBERS {
            ensure!(!request.cancellation.is_cancelled(), "A34 model cancelled");
            let id = format!("a34-prefix-{index:04}");
            start(script, members, &id, true, cancellation).await?;
            complete(
                script,
                members,
                &id,
                true,
                &format!("prefix body {index}"),
                cancellation,
            )
            .await?;
            if index + 1 == WINDOW {
                script
                    .boundary(Stage::FirstWindow, &request.cancellation)
                    .await?;
            }
        }
        start(script, members, T, false, cancellation).await?;
        complete(script, members, T, false, TEXT, cancellation).await?;
        start(script, members, U, true, cancellation).await?;
        script.boundary(Stage::Cut, &request.cancellation).await?;
        for index in 0..SUFFIX_MEMBERS {
            ensure!(!request.cancellation.is_cancelled(), "A34 model cancelled");
            let id = format!("a34-suffix-{index:04}");
            start(script, members, &id, true, cancellation).await?;
            complete(
                script,
                members,
                &id,
                true,
                &format!("suffix body {index}"),
                cancellation,
            )
            .await?;
        }
        complete(script, members, R, true, "R ended after T", cancellation).await?;
        script
            .boundary(Stage::SuffixReady, &request.cancellation)
            .await?;
        complete(
            script,
            members,
            U,
            true,
            "U ended after backlog",
            cancellation,
        )
        .await?;
        Ok(())
    }

    fn demand() -> ReadDemand {
        ReadDemand {
            max_items: 16,
            max_bytes: 128 * 1024,
        }
    }
    async fn chat(feed: &mut ConversationFeed, scope: &ChatScope) -> Result<ChatBatch> {
        loop {
            match feed.recv().await?.context("A34 feed ended")? {
                ConversationEvent::Chat { batch } => {
                    batch.validate_for(scope)?;
                    return Ok(*batch);
                }
                ConversationEvent::Activity { .. } => {}
            }
        }
    }

    async fn receive_while<T>(
        feed: &mut ConversationFeed,
        delivered: &mut Vec<CompletedEntry>,
        operation: impl std::future::Future<Output = Result<T>>,
    ) -> Result<T> {
        tokio::pin!(operation);
        loop {
            tokio::select! {
                result = &mut operation => return result,
                event = feed.recv() => {
                    if let ConversationEvent::Chat { batch } = event?.context("A34 original feed ended")? {
                        batch.validate_for(&ChatScope::conversation(None))?;
                        assert_eq!(batch.placement, ChatPlacement::Append);
                        assert!(batch.encoded_len()? <= demand().max_bytes as usize);
                        for entry in batch.entries {
                            if let Some(previous) = delivered.last() {
                                assert!(previous.completion_seq < entry.completion_seq);
                            }
                            delivered.push(entry);
                        }
                    }
                }
            }
        }
    }
    fn sql(text: &str, values: Vec<sea_orm::Value>) -> Statement {
        Statement::from_sql_and_values(DbBackend::Sqlite, text, values)
    }
    async fn facts(db: &DatabaseConnection, through: u64) -> Result<Vec<(String, String, String)>> {
        db.query_all_raw(sql("SELECT identity,'start' AS phase,json_array(kind,source_kind,source_identity,source_order,started_effect,started_suborder,started_at) AS fact
            FROM execution_lifecycle WHERE started_effect<=?1
            UNION ALL SELECT identity,'terminal',json_array(kind,source_kind,source_identity,ended_effect,ended_suborder,finished_at,outcome,completion_item_id)
            FROM execution_lifecycle WHERE ended_effect<=?1 ORDER BY identity,phase",vec![i64::try_from(through)?.into()])).await?.into_iter()
            .map(|row|Ok((row.try_get("","identity")?,row.try_get("","phase")?,row.try_get("","fact")?))).collect()
    }
    #[derive(Debug, Clone, PartialEq, Eq)]
    struct SavedCompletion {
        seq: u64,
        id: String,
        class: String,
        parent: Option<String>,
        payload: Vec<u8>,
        metadata: Vec<u8>,
    }
    async fn saved_items(db: &DatabaseConnection) -> Result<Vec<SavedCompletion>> {
        db.query_all_raw(sql("SELECT seq,item_id,query_class,parent_id,payload,metadata FROM conversation_items ORDER BY seq",vec![])).await?.into_iter()
            .map(|row|Ok(SavedCompletion { seq:u64::try_from(row.try_get::<i64>("","seq")?)?,id:row.try_get("","item_id")?,class:row.try_get("","query_class")?,
                parent:row.try_get("","parent_id")?,payload:row.try_get("","payload")?,metadata:row.try_get("","metadata")? })).collect()
    }
    async fn saved_chunks(db: &DatabaseConnection) -> Result<Vec<(String, String, i64, Vec<u8>)>> {
        db.query_all_raw(sql("SELECT owner_key,content_key,byte_offset,data FROM conversation_content_chunks ORDER BY owner_key,content_key,byte_offset", vec![]))
        .await?.into_iter().map(|row| Ok((row.try_get("", "owner_key")?, row.try_get("", "content_key")?, row.try_get("", "byte_offset")?, row.try_get("", "data")?))).collect()
    }

    async fn check_text(reader: &ConversationReader, item: &CompletedEntry) -> Result<()> {
        let owner = &item.record_id;
        ensure!(!item.atom.contents.is_empty(), "T lost its body references");
        let body = &item.atom.contents[0];
        let bytes = reader
            .read_content(
                &body.reference,
                ContentRange {
                    offset: 0,
                    max_bytes: 4096,
                },
            )
            .await?;
        assert_eq!(bytes.bytes, TEXT.as_bytes());
        let ContentTarget::Body {
            owner: ContentOwner::Item { item_id },
            ..
        } = &body.reference.target
        else {
            bail!("T body has no original completion owner");
        };
        assert_eq!(item_id, owner);
        Ok(())
    }

    async fn all_members(
        runtime: &StudioRuntime,
        feeds: &mut Vec<ConversationFeed>,
        id: &str,
        start: u64,
        end: u64,
        expected_bodies: &[String],
    ) -> Result<Vec<CompletedEntry>> {
        let scope = ChatScope::conversation(None);
        feeds.push(
            runtime
                .open_conversation_feed(id, scope.clone(), demand())
                .await?,
        );
        // The outer cleanup retains this feed even if its deadline cancels this
        // helper during a member/content read.
        let feed = feeds.last_mut().context("owned members feed")?;
        let result = async {
            let mut page = chat(feed, &scope).await?;
            let mut atoms = Vec::new();
            loop {
                let mut prefix = Vec::new();
                prefix.extend(page.entries);
                prefix.extend(atoms);
                atoms = prefix;
                let Some(before) = page.before else { break };
                page = feed.reader().load_older(&before, demand()).await?;
                page.validate_for(&scope)?;
            }
            let atoms = atoms
                .into_iter()
                .filter(|entry| {
                    entry.completion_seq >= start
                        && entry.completion_seq <= end
                        && entry.atom.kind == ChatAtomKind::Reasoning
                })
                .collect::<Vec<_>>();
            assert_eq!(atoms.len(), expected_bodies.len());
            for (entry, text) in atoms.iter().zip(expected_bodies) {
                let atom = &entry.atom;
                ensure!(
                    matches!(
                        atom.lifecycle,
                        ChatAtomLifecycle::Terminal {
                            outcome: ChatTerminalOutcome::Completed,
                            ..
                        }
                    ),
                    "member lost its real terminal"
                );
                let body = atom.contents.first().context("member original body")?;
                let ContentTarget::Body {
                    owner: ContentOwner::Item { item_id },
                    ..
                } = &body.reference.target
                else {
                    bail!("completed member retained a mutable content owner");
                };
                ensure!(
                    Some(item_id) == atom.completion_item_id.as_ref(),
                    "member body changed owner"
                );
                let content = feed
                    .reader()
                    .read_content(
                        &body.reference,
                        ContentRange {
                            offset: 0,
                            max_bytes: 4096,
                        },
                    )
                    .await?;
                ensure!(
                    content.bytes == text.as_bytes(),
                    "member body changed bytes"
                );
            }
            Ok(atoms)
        }
        .await;
        let close = feed.close().await;
        let reader = feed.reader().close().await;
        close?;
        reader?;
        result
    }

    #[tokio::test]
    async fn ordinary_backlog_preserves_completion_order_runs_and_original_bytes() -> Result<()> {
        let env = support::Environment::new(vec![], vec![]).await?;
        let result = run_case(&env, false).await;
        eprintln!("ordinary backlog story before environment shutdown: {result:#?}");
        env.finish(result).await
    }

    #[tokio::test]
    async fn backlog_save_failure_retains_pending_and_retries_original_completions() -> Result<()> {
        let env = support::Environment::new(vec![], vec![]).await?;
        let result = run_case(&env, true).await;
        eprintln!("failed-save backlog story before environment shutdown: {result:#?}");
        env.finish(result).await
    }

    fn diagnostic(
        env: &support::Environment,
        id: &str,
        owner: &ThreadHandle,
        script: &Script,
        phase: &str,
    ) -> String {
        let core = owner.snapshot();
        let channel = env.runtime.store.thread_persistence().history_channel(id);
        let status = channel.subscribe().borrow().clone();
        let live = env.runtime.thread_observations.live_feed(id);
        let publication = live
            .as_ref()
            .and_then(|live| live.current_conversation())
            .map(|current| {
                (
                    current.head,
                    current.session.durable_seq(),
                    current.activity.revision,
                    current.activity.entries.len(),
                    current.serial,
                )
            });
        let owner_status = live.as_ref().map(|live| {
            let registration = live.conversation();
            let progress = registration.owner_progress.borrow();
            (
                progress.is_finished(),
                progress.retained_error().map(|error| format!("{error:#}")),
            )
        });
        let writer = env
            .runtime
            .persistence_queue_snapshot()
            .threads
            .into_iter()
            .find(|thread| thread.thread_id == id);
        format!(
            "wait={phase}; producer_stage={:?}; producer={:?}; \
         core_commit={}; core_lifecycle={:?}; core_model={:?}; persistence={:?}; \
         channel={status:?}; handoff={}; channel_stopping={}; publication={publication:?}; \
         owner_finished/error={owner_status:?}; writer={writer:?}",
            *script.stage.borrow(),
            *script.diagnostic.lock().unwrap(),
            core.commit_sequence,
            core.lifecycle,
            core.model_execution,
            core.persistence,
            channel.handoff_ticket(),
            channel.is_stopping(),
        )
    }

    async fn run_case(env: &support::Environment, fail_final_save: bool) -> Result<()> {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "ordinary backlog owner")
            .await?;
        let id = thread.id.clone();
        let owner: ThreadHandle = env.runtime.ensure_thread_owner(&id).await?;
        let script = Script::new();
        owner
            .replace_model(ModelFactory::new(ScriptModel(script.clone())))
            .await?;
        let history = env.runtime.store.history(&id).await?;
        let channel = env.runtime.store.thread_persistence().history_channel(&id);
        let cancel = CancellationToken::new();
        let mut run = tokio::spawn({
            let owner = owner.clone();
            let cancel = cancel.clone();
            let script = script.clone();
            async move {
                let result = owner
                    .run_turn(TurnInput {
                        turn_id: "a34-turn".into(),
                        attempt_prefix: "a34-attempt".into(),
                        content: vec![],
                        max_model_steps: ModelStepLimit::Limited(
                            1.try_into().expect("one model step"),
                        ),
                        cancellation: cancel,
                    })
                    .await;
                script.finished(format!("Core run_turn: {result:?}"));
                result
            }
        });
        // Preserve the original typed reply once consumed. Cleanup must not poll a
        // completed JoinHandle again, including when the reply reports a failure.
        let mut producer_join = None;
        let mut feeds = Vec::new();
        let mut delivered = Vec::new();
        let mut database_connection = None;
        let mut fault_trigger_installed = false;
        let mut phase = "first-window producer ACKs";
        let story_started = std::time::Instant::now();
        let trace_phase = |phase: &str| {
            eprintln!("A34 elapsed={:?}; phase={phase}", story_started.elapsed());
        };
        trace_phase(phase);
        let story = async {
            script.reached(Stage::FirstWindow).await?;
            phase = "first-window observation/durable barrier";
            env.runtime.synchronize_thread_observation(&id).await?;
            channel
                .await_handoff_durable(&id, channel.handoff_ticket())
                .await?;
            let source = env
                .runtime
                .thread_observations
                .live_feed(&id)
                .context("original live owner")?;
            let first = source.current_conversation().context("first publication")?;
            assert_eq!(first.head, WINDOW as u64);
            assert_eq!(first.session.durable_seq(), first.head);
            assert_eq!(first.activity.entries.len(), 1, "only R is still active");
            script.release();
            phase = "second-window / R-T-U producer ACKs";
            script.reached(Stage::Cut).await?;
            phase = "R-T-U observation/durable barrier";
            env.runtime.synchronize_thread_observation(&id).await?;
            channel
                .await_handoff_durable(&id, channel.handoff_ticket())
                .await?;
            let slot = env.runtime.thread_observations.observation_slot(&id);
            let (position, _) = slot.capture();
            let installed = position.source.context("installed original owner")?;
            let live = installed
                .current_conversation()
                .context("cut publication")?;
            let cut = live.current.projection().source_effect_seq;
            let cut_head = live.head;
            assert_eq!(cut_head, (PREFIX_MEMBERS + 1) as u64);
            assert_eq!(live.session.durable_seq(), cut_head);
            assert_eq!(live.activity.completed_through, cut_head);
            assert_eq!(
                live.activity.entries.len(),
                2,
                "R and U remain active after T completed"
            );
            assert!(
                live.activity
                    .entries
                    .iter()
                    .all(|entry| matches!(entry.atom.lifecycle, ChatAtomLifecycle::Active { .. }))
            );
            let database = history
                .conversation_database_id()
                .await?
                .context("database identity")?;
            phase = "original records Set and T range";
            feeds.push(
                env.runtime
                    .open_conversation_feed(&id, ChatScope::conversation(None), demand())
                    .await?,
            );
            let initial = chat(&mut feeds[0], &ChatScope::conversation(None)).await?;
            assert_eq!(initial.placement, ChatPlacement::Set);
            assert_eq!(initial.through_seq, cut_head);
            assert_eq!(initial.entries.len(), demand().max_items as usize);
            assert!(
                initial
                    .entries
                    .iter()
                    .all(|entry| entry.atom.source_state.is_none())
            );
            let text = initial
                .entries
                .last()
                .context("latest completed T")?
                .clone();
            assert_eq!(text.completion_seq, cut_head);
            check_text(feeds[0].reader(), &text).await?;
            let mut status = channel.subscribe();
            assert_eq!(channel.handoff_ticket(), cut);
            assert_eq!(status.borrow().committed_sequence, cut);
            assert_eq!(status.borrow().queued_records, 0);
            assert!(!channel.is_stopping());
            let path = env
                .runtime
                .store
                .registered_session_paths(&id)?
                .history_database();
            let mode = if fail_final_save { "rw" } else { "ro" };
            database_connection =
                Some(Database::connect(format!("sqlite://{}?mode={mode}", path.display())).await?);
            let db = database_connection
                .as_ref()
                .context("test read connection")?;
            let prefix = facts(db, cut).await?;
            assert!(prefix.len() > PREFIX_MEMBERS * 2);
            let originals = saved_items(db).await?;
            assert_eq!(originals.len(), cut_head as usize);
            let chunks = saved_chunks(db).await?;
            assert!(!chunks.is_empty(), "fixture did not save original bodies");

            script.release();
            phase = "ordinary suffix producer ACKs";
            trace_phase(phase);
            // The original consumer keeps reading while the original publisher
            // applies backpressure; a save barrier is not a substitute for reads.
            receive_while(
                &mut feeds[0],
                &mut delivered,
                script.reached(Stage::SuffixReady),
            )
            .await?;
            let suffix_target = owner.snapshot().commit_sequence;
            phase = "ordinary suffix fixed-target observation/durable barrier";
            trace_phase(phase);
            receive_while(
                &mut feeds[0],
                &mut delivered,
                env.runtime.synchronize_thread_observation(&id),
            )
            .await?;
            channel
                .await_handoff_durable(&id, channel.handoff_ticket())
                .await?;
            let suffix_status = status.borrow_and_update().clone();
            ensure!(
                suffix_status.fault.is_none(),
                "ordinary backlog faulted: {suffix_status:?}"
            );
            ensure!(
                suffix_status.error.is_none(),
                "ordinary backlog save failed: {suffix_status:?}"
            );
            assert!(suffix_status.admitted_sequence >= suffix_target);
            assert!(suffix_status.committed_sequence >= suffix_target);
            assert_eq!(suffix_status.queued_records, 0);
            assert!(!channel.is_stopping());
            assert_eq!(
                facts(db, cut).await?,
                prefix,
                "durable prefix changed while suffix drained"
            );
            assert!(Arc::ptr_eq(
                &channel,
                &env.runtime.store.thread_persistence().history_channel(&id)
            ));
            let (after_suffix, _) = slot.capture();
            assert!(Arc::ptr_eq(
                after_suffix.source.as_ref().context("owner after suffix")?,
                &installed
            ));
            assert_eq!(
                history.conversation_database_id().await?.as_deref(),
                Some(database.as_str())
            );
            let suffix_live = installed
                .current_conversation()
                .context("suffix publication")?;
            assert_eq!(
                suffix_live.current.projection().source_effect_seq,
                suffix_target
            );
            assert!(suffix_target > cut);
            assert_eq!(
                suffix_live.head,
                (PREFIX_MEMBERS + 1 + SUFFIX_MEMBERS + 1) as u64
            );
            assert_eq!(suffix_live.session.durable_seq(), suffix_live.head);
            assert_eq!(
                suffix_live.activity.entries.len(),
                1,
                "only U remains active"
            );
            assert_eq!(
                saved_items(db)
                    .await?
                    .into_iter()
                    .filter(|row| row.seq <= cut_head)
                    .collect::<Vec<_>>(),
                originals,
                "later saves changed immutable payload/metadata/run bytes"
            );

            if fail_final_save {
                db.execute_unprepared(
                    "CREATE TRIGGER reject_backlog_completion BEFORE INSERT ON conversation_items
                 BEGIN SELECT RAISE(ABORT,'injected backlog completion failure'); END",
                )
                .await?;
                fault_trigger_installed = true;
            }
            script.release();
            phase = "same producer U terminal";
            trace_phase(phase);
            if fail_final_save {
                phase = "real writer fault and retained pending completion";
                receive_while(&mut feeds[0], &mut delivered, async {
                    while status.borrow_and_update().fault.is_none() {
                        status.changed().await?;
                    }
                    Ok(())
                })
                .await?;
                let failed = status.borrow().clone();
                assert!(failed.queued_records > 0);
                assert!(
                    failed
                        .error
                        .as_deref()
                        .is_some_and(|error| error.contains("injected backlog completion failure"))
                );
                // The failed transaction cannot confirm the newly published U.
                assert_eq!(live.session.durable_seq(), suffix_live.head);
                assert!(live.session.head_seq() > live.session.durable_seq());
                assert_eq!(
                    saved_items(db).await?.last().context("saved prefix")?.seq,
                    suffix_live.head
                );
                let pending_feed = feeds.len();
                feeds.push(
                    env.runtime
                        .open_conversation_feed(&id, ChatScope::conversation(None), demand())
                        .await?,
                );
                let set = chat(&mut feeds[pending_feed], &ChatScope::conversation(None)).await?;
                let pending = set
                    .entries
                    .iter()
                    .find(|entry| {
                        entry.atom.kind == ChatAtomKind::Reasoning && entry.record_id.contains(U)
                    })
                    .context("pending U original")?;
                assert!(pending.completion_seq > live.session.durable_seq());
                let original = feeds[pending_feed]
                    .reader()
                    .read_completed(&pending.record_id, demand())
                    .await?;
                let body = original
                    .atom
                    .contents
                    .first()
                    .context("pending original U body")?;
                let bytes = feeds[pending_feed]
                    .reader()
                    .read_content(
                        &body.reference,
                        ContentRange {
                            offset: 0,
                            max_bytes: 4096,
                        },
                    )
                    .await?;
                assert_eq!(bytes.bytes, b"U ended after backlog");
                db.execute_unprepared("DROP TRIGGER reject_backlog_completion")
                    .await?;
                fault_trigger_installed = false;
                env.runtime
                    .retry_thread_history(&id, failed.fault_generation)
                    .await?;
                env.runtime
                    .resume_thread_history(&id, failed.fault_generation)
                    .await?;
                let durable = feeds[pending_feed]
                    .reader()
                    .read_completed(&original.record_id, demand())
                    .await?;
                assert_eq!(durable.record_id, original.record_id);
                assert_eq!(durable.completion_seq, original.completion_seq);
                assert_eq!(durable.atom.payload, original.atom.payload);
                assert_eq!(durable.atom.contents, original.atom.contents);
            }
            let joined = receive_while(&mut feeds[0], &mut delivered, async {
                (&mut run)
                    .await
                    .context("ordinary backlog producer join")
                    .and_then(|joined| Ok(joined?))
            })
            .await;
            let completed = joined
                .as_ref()
                .is_ok_and(|completion| completion.outcome == TurnOutcome::Completed);
            let terminal = format!("{joined:?}");
            producer_join = Some(joined);
            ensure!(
                completed,
                "original Core producer ended unexpectedly: {terminal}; persistence={:?}",
                owner.snapshot().persistence
            );
            let target = owner.snapshot().commit_sequence;
            phase = "final observation/durable barrier";
            trace_phase(phase);
            receive_while(
                &mut feeds[0],
                &mut delivered,
                env.runtime.synchronize_thread_observation(&id),
            )
            .await?;
            channel
                .await_handoff_durable(&id, channel.handoff_ticket())
                .await?;
            assert_eq!(
                facts(db, cut).await?,
                prefix,
                "C facts changed while ordinary backlog drained"
            );
            let latest = installed
                .current_conversation()
                .context("final publication")?;
            assert_eq!(latest.current.projection().source_effect_seq, target);
            assert!(target > suffix_target);
            let final_status = status.borrow_and_update().clone();
            assert_eq!(final_status.queued_records, 0);
            assert_eq!(final_status.admitted_sequence, target);
            assert_eq!(final_status.committed_sequence, target);
            assert!(final_status.fault.is_none() && final_status.error.is_none());
            assert_eq!(latest.session.durable_seq(), latest.head);
            assert!(latest.activity.entries.is_empty());
            let (final_position, _) = slot.capture();
            assert!(Arc::ptr_eq(
                final_position
                    .source
                    .as_ref()
                    .context("final original owner")?,
                &installed
            ));
            phase = "final immutable completion inventory and raw bytes";
            let saved = saved_items(db).await?;
            assert_eq!(saved.last().context("final completion")?.seq, latest.head);
            assert_eq!(
                saved
                    .iter()
                    .filter(|row| row.seq <= cut_head)
                    .cloned()
                    .collect::<Vec<_>>(),
                originals
            );
            let final_chunks = saved_chunks(db).await?;
            for chunk in &chunks {
                assert!(
                    final_chunks.contains(chunk),
                    "a durable original body chunk changed"
                );
            }
            let visible = saved
                .iter()
                .filter(|row| row.class == "conversation")
                .collect::<Vec<_>>();
            assert_eq!(visible.len(), PREFIX_MEMBERS + SUFFIX_MEMBERS + 4);
            let suffix = visible
                .iter()
                .filter(|row| row.seq > cut_head)
                .collect::<Vec<_>>();
            while delivered.len() < suffix.len() {
                let batch = chat(&mut feeds[0], &ChatScope::conversation(None)).await?;
                assert_eq!(batch.placement, ChatPlacement::Append);
                delivered.extend(batch.entries);
            }
            assert_eq!(
                delivered
                    .iter()
                    .map(|entry| (&entry.record_id, entry.completion_seq))
                    .collect::<Vec<_>>(),
                suffix
                    .iter()
                    .map(|row| (&row.id, row.seq))
                    .collect::<Vec<_>>()
            );
            // The emitter starts R before the prefix and U before the suffix. Neither
            // may move backwards in completed history when its terminal finally arrives.
            let suffix_start = cut_head + 1;
            assert!(suffix.windows(2).all(|pair| pair[0].seq < pair[1].seq));
            phase = "real record pages and original body ranges";
            let prefix_bodies = (0..PREFIX_MEMBERS)
                .map(|index| format!("prefix body {index}"))
                .collect::<Vec<_>>();
            let mut suffix_bodies = (0..SUFFIX_MEMBERS)
                .map(|index| format!("suffix body {index}"))
                .collect::<Vec<_>>();
            suffix_bodies.extend(["R ended after T".into(), "U ended after backlog".into()]);
            for (start, expected_bodies) in [(1, prefix_bodies), (suffix_start, suffix_bodies)] {
                let actual = all_members(
                    &env.runtime,
                    &mut feeds,
                    &id,
                    start,
                    if start == 1 {
                        cut_head - 1
                    } else {
                        latest.head
                    },
                    &expected_bodies,
                )
                .await?;
                assert_eq!(actual.len(), expected_bodies.len());
                let expected = saved
                    .iter()
                    .filter(|row| {
                        row.seq >= start
                            && (start != 1 || row.seq < cut_head)
                            && serde_json::from_slice::<ChatAtom>(&row.metadata)
                                .is_ok_and(|atom| atom.kind == ChatAtomKind::Reasoning)
                    })
                    .collect::<Vec<_>>();
                for (entry, row) in actual.iter().zip(expected) {
                    assert_eq!((&entry.record_id, entry.completion_seq), (&row.id, row.seq));
                    let atom: ChatAtom = serde_json::from_slice(&row.metadata)?;
                    assert_eq!(entry.atom.id, atom.id);
                    assert_eq!(entry.atom.contents, atom.contents);
                }
            }
            phase = "final bounded records and genuine Turn receipt";
            let final_feed = feeds.len();
            feeds.push(
                env.runtime
                    .open_conversation_feed(&id, ChatScope::conversation(None), demand())
                    .await?,
            );
            let set = chat(&mut feeds[final_feed], &ChatScope::conversation(None)).await?;
            assert_eq!(set.placement, ChatPlacement::Set);
            assert_eq!(set.through_seq, latest.head);
            assert_eq!(set.entries.len(), demand().max_items as usize);
            assert!(
                set.entries
                    .windows(2)
                    .all(|pair| pair[0].completion_seq < pair[1].completion_seq)
            );
            let fresh_text = feeds[final_feed]
                .reader()
                .read_completed(&text.record_id, demand())
                .await?;
            assert_eq!(fresh_text.atom.contents, text.atom.contents);
            check_text(feeds[final_feed].reader(), &fresh_text).await?;
            let hidden = saved
                .iter()
                .find(|row| {
                    serde_json::from_slice::<ChatAtom>(&row.metadata)
                        .is_ok_and(|atom| atom.kind == ChatAtomKind::TurnReceipt)
                })
                .context("real successful Turn receipt")?;
            let scope = ChatScope::conversation(Some(
                hidden.parent.clone().context("real receipt parent")?,
            ));
            let children_feed = feeds.len();
            feeds.push(
                env.runtime
                    .open_conversation_feed(&id, scope.clone(), demand())
                    .await?,
            );
            let mut page = chat(&mut feeds[children_feed], &scope).await?;
            let mut found = false;
            loop {
                for entry in page.entries {
                    if entry.record_id == hidden.id {
                        assert_eq!(entry.completion_seq, hidden.seq);
                        found = true;
                    }
                }
                let Some(before) = page.before else {
                    break;
                };
                page = feeds[children_feed]
                    .reader()
                    .load_older(&before, demand())
                    .await?;
                page.validate_for(&scope)?;
            }
            assert!(found, "Children suppressed its real successful receipt");
            Ok::<_, anyhow::Error>(())
        };
        // Assertion failures must also reach the owned resource cleanup below.
        let deadline = support::integration_test_deadline()?;
        let result =
            match tokio::time::timeout(deadline, AssertUnwindSafe(story).catch_unwind()).await {
                Ok(Ok(result)) => result,
                Ok(Err(panic)) => Err(anyhow::anyhow!(
                    "A34 assertion: {}",
                    panic
                        .downcast_ref::<String>()
                        .map(String::as_str)
                        .or_else(|| panic.downcast_ref::<&str>().copied())
                        .unwrap_or("non-string panic")
                )),
                Err(error) => Err(anyhow::Error::new(error).context("A34 owner/queue deadline")),
            }
            .with_context(|| diagnostic(env, &id, &owner, &script, phase));
        // End all environment waits before runtime close/join, including a failed
        // assertion path. A test-owned JoinHandle is always observed, never detached.
        trace_phase("cleanup begins");
        let mut cleanup_errors = Vec::new();
        if fault_trigger_installed {
            if let Some(db) = &database_connection
                && let Err(error) = db
                    .execute_unprepared("DROP TRIGGER IF EXISTS reject_backlog_completion")
                    .await
            {
                cleanup_errors.push(format!("fault trigger cleanup: {error:#}"));
            }
            if let Err(error) = env.runtime.retry_persistence().await {
                cleanup_errors.push(format!("fault retry cleanup: {error:#}"));
            }
        }
        cancel.cancel();
        script.next.add_permits(3);
        let joined = if let Some(joined) = producer_join {
            joined
        } else {
            match tokio::time::timeout(deadline, &mut run).await {
                Ok(joined) => joined
                    .context("A34 producer join")
                    .and_then(|joined| Ok(joined?)),
                Err(error) => {
                    run.abort();
                    let cancelled = run.await;
                    Err(anyhow::Error::new(error).context(format!(
                        "A34 producer join deadline; abort receipt={cancelled:?}"
                    )))
                }
            }
        };
        for feed in &mut feeds {
            if let Err(error) = feed.close().await {
                cleanup_errors.push(format!("feed close: {error:#}"));
            }
            if let Err(error) = feed.reader().close().await {
                cleanup_errors.push(format!("reader close: {error:#}"));
            }
        }
        if let Some(db) = database_connection
            && let Err(error) = db.close().await
        {
            cleanup_errors.push(format!("readonly database close: {error:#}"));
        }
        let cleanup_context = format!(
            "A34 cleanup: producer_join={joined:?}; resource_errors={cleanup_errors:?}; after={}",
            diagnostic(env, &id, &owner, &script, phase),
        );
        trace_phase("owned producer/feed/reader/database cleanup complete");
        let result = result.and_then(|()| {
            let completion = joined?;
            ensure!(
                completion.outcome == TurnOutcome::Completed,
                "A34 producer failed"
            );
            ensure!(cleanup_errors.is_empty(), "A34 resource cleanup failed");
            Ok(())
        });
        result.context(cleanup_context)
    }
}
