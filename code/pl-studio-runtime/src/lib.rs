//! anywork 产品运行时。
//!
//! 本 crate 负责 Studio 配置、SQLite projection、project/thread 编排与 bridge DTO；
//! 通用模型循环、agent actor、工具和协议基础类型由 `pl-core` 提供。

// Unit tests reuse the same isolated Runtime fixtures as the integration binaries.
#[cfg(test)]
extern crate self as pl_studio_runtime;

pub(crate) use pl_core::context::content_hash as canonical_content_hash;
pub(crate) use pl_protocol::*;
// Public Studio timeline signatures use the core content types; adapters need no direct
// dependency on the execution kernel to name them.
pub use pl_core::chat::{CHAT_ITEM_PREVIEW_BYTES, ChatError, ChatField, ChatItem};
pub use pl_core::model::ContentBlock;
mod hash;
mod toml_schema;

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
pub mod statistics;
mod studio;
pub use studio::accounts;
#[cfg(feature = "benchmarks")]
#[doc(hidden)]
pub use studio::benchmark;
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
    StudioPendingPersistence, StudioProductBaseline, StudioProductBaselineState,
    StudioProductEventEnvelope, StudioProductEventKind, StudioProductFrame, StudioProductTopic,
    StudioProductTopicScopeError, StudioProjectDirectoryData, StudioProjectDirectoryState,
    StudioPurposeCostSnapshot, StudioRecoveryStateSnapshot, StudioSessionCostSnapshot,
    StudioSessionCostsState, StudioSettingsConfigStateSnapshot, StudioShutdownIssue,
    StudioShutdownOutcome, StudioShutdownProgress, StudioShutdownReport, StudioSkillsStateSnapshot,
    StudioStartupStage, StudioStateSnapshot, StudioThreadDirectoryData, StudioThreadDirectoryDelta,
    StudioThreadDirectoryPage, StudioThreadDirectoryPageData, StudioThreadDirectoryState,
};

pub use account_usage::{
    AccountUsageCommand, AccountUsageData, AccountUsageRecord, AccountUsageState,
    AccountUsageTransitionDecision, AccountUsageTransitionError, DeepSeekBalanceInfo,
    DeepSeekBalanceUsage, FailedAccountUsage, MissingCredentialAccountUsage, ReadyAccountUsage,
    UnsupportedAccountUsage, ZhipuCodingPlanUsage, ZhipuQuotaLimit, ZhipuQuotaWindow,
    ZhipuToolUsageDetail, zhipu_limit_by_window,
};
pub use protocol::{
    StudioAgentProfileDiagnostic, StudioAgentProfilesData, StudioAgentProfilesStateSnapshot,
    StudioPersistenceQueueStateSnapshot,
};
pub use studio::{
    AccountUsageStateData, AccountUsageStateSnapshot, AttachmentRecord, ConversationEvent,
    ConversationFeed, PersistenceState, PersistenceStateSnapshot, ProductEventBus,
    SkillSearchResult, SkillsStateSnapshot, SshPasswordUpdate, SshServerRuntimeEntry,
    StudioDatabaseError, StudioHostKind, StudioInstance, StudioInstanceLease,
    StudioProductTopicSubscription, StudioRecoveryImpact, StudioRecoveryIssue,
    StudioRecoveryIssueAction, StudioRecoveryIssueCategory, StudioRecoveryIssueScope,
    StudioRecoveryWorktreeOwner, StudioRuntime, StudioRuntimeLifecycleState, StudioRuntimeOptions,
    StudioRuntimeSnapshot, StudioRuntimeStateKind, StudioStartNewThreadResponse,
    StudioStartupError, StudioStartupErrorKind, StudioStartupRecovery, StudioStore,
    StudioThreadSubscription, StudioUpdateStateSnapshot, StudioWorktreeInspection,
    StudioWorktreeRecoveryPreview, ThreadPreparationObserver, ThreadPreparationProgress,
    ThreadPreparationStage, ThreadRecord, TimelineContentReader, TimelineTailStream,
    WorkspaceRecord,
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
