//! anywork 产品运行时。
//!
//! 本 crate 负责 Studio 配置、SQLite projection、project/thread 编排与 bridge DTO；
//! 通用模型循环、agent actor、工具和协议基础类型由 `pl-core` 提供。

// 共享协议错误 `StudioError` 已通过装箱 `details` 收敛体积；本 crate 内部 shutdown/close
// 失败结构刻意保留全部同时成立的事实（见 `write_behind/failure.rs`、`thread_observation/close.rs`
// 的注释），其体积超过 clippy 默认阈值，且这些结构不跨 FFI 边界。这里只针对该内部诊断形态
// 放宽误用同一阈值的告警，不覆盖协议侧错误类型。
#![allow(clippy::result_large_err)]

pub(crate) use pl_core::context::content_hash as canonical_content_hash;
pub(crate) use pl_protocol::*;
// Public Studio timeline signatures use the core content types; adapters need no direct
// dependency on the execution kernel to name them.
pub use pl_core::chat::{CHAT_ITEM_PREVIEW_BYTES, ChatError, ChatField, ChatItem, ChatLifecycle};
pub use pl_core::model::ContentBlock;
mod hash;

pub mod agent;
pub mod approval;
pub use approval::PermissionMode;
mod account_usage;
mod bots;
mod compaction;
pub mod config;
mod config_editor;
mod error_mapping;
mod first_run;
mod instruction;
mod protocol;
pub mod resource_store;
mod studio;
pub mod thread_assembler;
mod updater;
mod worker_assets;

// Data types needed to call Studio's SSH API; transport consumers do not depend on tool runtimes.
pub use pl_tool::remote::{
    SshConfigEntry, SshConfigFile, SshConnectionSnapshot, SshConnectionState, SshServerProfile,
};

pub use pl_tool::skill::{SkillCatalog, SkillMetadata, SkillResourceBase, SkillSourceKind};

pub use config::{
    AccountId, ConfigPaths, ConfigRuntimeError, ConfigRuntimeSnapshot, ConfigStore,
    DeepSeekWebSearchConfig, ModelCatalogRuntimeSnapshot, ReasoningEffort,
    STUDIO_CONFIG_SCHEMA_VERSION, StudioConfig, StudioMcpConfig, StudioUiConfig, UserAgentProfile,
    WebSearchContextSize, WebSearchLocation, WebSearchMode,
};
pub use config_editor::{AccountEdit, AccountModelEdit, account_template_kind};
pub use error_mapping::studio_error_from_anyhow;
pub(crate) use error_mapping::studio_error_from_anyhow_ref;
pub use first_run::{
    AccountTemplateKind, FirstRunAccountDraft, FirstRunConfigDraft, FirstRunModelDraft,
};
pub use protocol::{
    FlushingPersistenceProgress, LspAvailable, LspAvailableActivity, LspBusy, LspChecking,
    LspDisabled, LspIdle, LspIndexing, LspUnavailable, McpAvailable, McpChecking, McpDisabled,
    McpMissingCredential, McpUnavailable, StudioAgentDirectoryData, StudioAgentDirectoryEntry,
    StudioAgentDirectoryState, StudioLspHealth, StudioLspServer, StudioLspServerState,
    StudioLspStateSnapshot, StudioMcpHealth, StudioMcpServer, StudioMcpServerState,
    StudioMcpStateData, StudioMcpStateSnapshot, StudioModelCatalogStateSnapshot,
    StudioModelPerformanceEffortSummary, StudioModelPerformanceSample,
    StudioModelPerformanceSnapshot, StudioModelPerformanceSummary, StudioPendingPersistence,
    StudioProductBaseline, StudioProductBaselineState, StudioProductEventEnvelope,
    StudioProductEventKind, StudioProductFrame, StudioProductTopic, StudioProductTopicScopeError,
    StudioProjectDirectoryData, StudioProjectDirectoryState, StudioPurposeCostSnapshot,
    StudioRecoveryStateSnapshot, StudioSessionCostSnapshot, StudioSessionCostsState,
    StudioSettingsConfigStateSnapshot, StudioShutdownIssue, StudioShutdownOutcome,
    StudioShutdownProgress, StudioShutdownReport, StudioSkillsStateSnapshot, StudioStartupStage,
    StudioStateSnapshot, StudioThreadDirectoryData, StudioThreadDirectoryDelta,
    StudioThreadDirectoryPage, StudioThreadDirectoryPageData, StudioThreadDirectoryState,
};

pub use account_usage::{
    AccountUsageCommand, AccountUsageData, AccountUsageRecord, AccountUsageState,
    AccountUsageTransitionDecision, AccountUsageTransitionError, DeepSeekBalanceInfo,
    DeepSeekBalanceUsage, FailedAccountUsage, MissingCredentialAccountUsage, ReadyAccountUsage,
    UnsupportedAccountUsage, ZhipuCodingPlanUsage, ZhipuQuotaLimit, ZhipuQuotaWindow,
    ZhipuToolUsageDetail, zhipu_limit_by_window,
};
pub use pl_protocol::studio::{
    FeedCloseReport, InputAcceptanceEvidence, PersistedInputDisposition, StudioError, TextChunk,
};
pub use pl_protocol::thread_facets::identity::{
    FeedClosedReason, MetricsIdentityRef, ReadScopeIdentity, ThreadFacet, ThreadFacetStamp,
    ThreadFeedIdentity, ThreadObservationMode,
};
pub use pl_protocol::thread_facets::metrics::MetricsValue;
pub use pl_protocol::thread_facets::read::values::MetricsIdentityReadHeader;
pub use protocol::{
    StudioAgentProfileDiagnostic, StudioAgentProfilesData, StudioAgentProfilesStateSnapshot,
    StudioPersistenceQueueStateSnapshot, StudioSkillsStateData,
};
pub use studio::account_usage::*;
pub use studio::attachment_binary;
pub use studio::bots::{StudioBotConversationsRead, StudioBotsFeed, StudioBotsSourceStatusRead};
pub use studio::configuration;
pub use studio::draft_commands;
pub use studio::models;
pub use studio::thread_authoring;
pub use studio::thread_authoring_read;
pub use studio::thread_configuration;
pub use studio::thread_configuration_read;
pub use studio::thread_context;
pub use studio::thread_context_read;
pub use studio::thread_execution;
pub use studio::thread_execution_read;
pub use studio::workspace;
pub use studio::{acp_auth, acp_install, lsp, mcp, skills};
pub use studio::{modes, statistics, updates};
pub use studio::{
    persistence_products as persistence, recovery, remote_directory, startup_products as startup,
};
pub use tokio::sync::mpsc::Sender;

pub use studio::{
    AccountUsageStateData, AccountUsageStateSnapshot, AttachmentRecord, PersistenceState,
    PersistenceStateSnapshot, ProductEventBus, ProjectRecord, SkillSearchResult,
    SkillsStateSnapshot, SshPasswordUpdate, SshServerRuntimeEntry, StudioDatabaseError,
    StudioHostKind, StudioInstance, StudioInstanceLease, StudioMetricsIdentityRead,
    StudioMetricsSample, StudioMetricsSourceEvent, StudioProductTopicSubscription,
    StudioRecoveryIssue, StudioRecoveryIssueAction, StudioRecoveryIssueCategory,
    StudioRecoveryIssueScope, StudioRecoveryWorktreeOwner, StudioRuntime,
    StudioRuntimeLifecycleState, StudioRuntimeOptions, StudioRuntimeSnapshot,
    StudioRuntimeStateKind, StudioStartNewThreadResponse, StudioStartupError,
    StudioStartupErrorKind, StudioStartupRecovery, StudioStore, StudioThreadMetricsSource,
    StudioThreadSubscription, StudioUpdateStateSnapshot, StudioWorktreeRecoveryPreview,
    ThreadPreparationObserver, ThreadPreparationProgress, ThreadPreparationStage, ThreadRecord,
    TimelineContentReader, TimelineTailStream,
};
pub use updater::{
    PreparedStudioUpdate, StudioUpdate, StudioUpdateAsset, StudioUpdateCancellation,
    StudioUpdateCheck, StudioUpdateError, StudioUpdateErrorCode, StudioUpdateEvent,
    StudioUpdateLaunch, StudioUpdater,
};
pub use worker_assets::RemoteHelperSource;

// 公共签名（bridge DTO 字段、runtime API 返回值）使用的 pl-protocol 类型在此
// 精确重导出，消费方只依赖 pl-studio-runtime 即可命名完整签名。
pub use pl_protocol::studio::NewThreadModelRoute;
pub use pl_protocol::studio::{SetAccountBillingKindRequest, SetAccountModelEnabledRequest};
pub use pl_protocol::{
    AgentState, AgentWorkspaceMode, CancelInteraction, DelegationMode, DelegationModelDetail,
    DelegationModelList, DelegationPreference, DelegationSettings, GetDelegationModelRequest,
    InteractionCommand, InteractionContinuationInput, InteractionPurpose,
    ListDelegationModelsRequest, ReopenRecoveredInteraction, ResolveToolApproval, ResolveUserInput,
    ThreadModeId, ToolApprovalResolutionPayload, UserInputResolution,
};

mod programmatic;

pub mod plan_tool;

pub mod workflow_tool;

pub mod mode;

mod tool_review;

mod startup_timing;
