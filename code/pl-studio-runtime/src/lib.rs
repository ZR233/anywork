//! anywork 产品运行时。
//!
//! 本 crate 负责 Studio 配置、SQLite projection、project/thread 编排与 bridge DTO；
//! 通用模型循环、agent actor、工具和协议基础类型由 `pl-core` 提供。

// Unit tests reuse the same isolated Runtime fixtures as the integration binaries.
#[cfg(test)]
extern crate self as pl_studio_runtime;

pub(crate) use pl_core::context::content_hash as canonical_content_hash;
pub(crate) use studio::storage::history::schema::legacy_execution_item::LegacyTurn;
pub(crate) use studio::thread_projection::{
    ExecutionItem, ExecutionKind, ExecutionShape, ItemStamp,
};
pub use studio::{AcpSessionCompletion, AcpSessionObservation, AcpSessionOpen};
mod hash;
mod toml_schema;

mod account_usage;
pub mod agent;
pub(crate) mod approval;
mod bots;
pub(crate) mod channel_output;
mod compaction;
pub mod config;
mod config_editor;
mod error_mapping;
pub mod history;
mod instruction;
mod protocol;
pub mod resource_store;
mod studio;
pub use studio::accounts;
#[cfg(feature = "benchmarks")]
#[doc(hidden)]
pub use studio::benchmark;
mod executable_assets;
mod host_mcp_assets;
pub(crate) mod session;
pub(crate) mod thread_assembler;
mod worker_assets;

// Data types needed to call Studio's SSH API; transport consumers do not depend on tool runtimes.
pub use pl_tool::remote::{
    RemoteDirectoryListing, SshConfigFile, SshConnectionSnapshot, SshConnectionState,
    SshServerProfile,
};

pub use pl_tool::skill::{
    SkillActivation, SkillCatalog, SkillMetadata, SkillResourceBase, SkillSearchOptions,
    SkillSourceKind,
};
pub(crate) use pl_tool::skill::{SkillActivationCause, SkillActivationResourceBase};

pub use config::{
    AccountId, ConfigPaths, ConfigRuntimeError, ConfigRuntimeSnapshot, ConfigStore,
    DeepSeekWebSearchConfig, McpCatalogResource, McpDocumentError, McpFileSpecV1, McpFileV1,
    ResolvedThreadMcpServer, ScopedEffectiveMcpServer, StudioConfig, StudioUiConfig,
    UserAgentProfile, WebSearchContextSize, WebSearchMode,
};
pub(crate) use config::{
    ModelCatalogRuntimeSnapshot, STUDIO_CONFIG_SCHEMA_VERSION, WebSearchLocation,
};
pub use error_mapping::{studio_error_from_anyhow, studio_error_from_anyhow_ref};
pub use host_mcp_assets::HostMcpSource;
pub use protocol::*;

pub(crate) use studio::StudioDatabaseError;
pub use studio::{
    AttachmentRecord, CurrentBodyWatch, CurrentReader, CurrentWatch, DisplayDownloadOutcome,
    DisplayDownloadRequest, PersistenceState, PersistenceStateSnapshot, ProductEventBus,
    ProductTopicReceiver, ProductTopicRecvError, ProductTopicTryRecvError, SkillSearchResult,
    SkillsStateSnapshot, SshPasswordUpdate, SshServerRuntimeEntry, StudioHostKind, StudioInstance,
    StudioInstanceLease, StudioProductTopicSubscription, StudioReadyUpdate, StudioRecoveryImpact,
    StudioRecoveryIssue, StudioRecoveryIssueAction, StudioRecoveryIssueCategory,
    StudioRecoveryIssueScope, StudioRecoveryWorktreeOwner, StudioRuntime,
    StudioRuntimeLifecycleState, StudioRuntimeOptions, StudioRuntimeSnapshot,
    StudioRuntimeStateKind, StudioStartNewThreadRequest, StudioStartNewThreadResponse,
    StudioStartupError, StudioStartupErrorKind, StudioStartupPolicy, StudioStartupRecovery,
    StudioStore, StudioSubmitPromptOptions, StudioSubmitPromptRequest, StudioSubmitPromptResponse,
    StudioUpdateActivity, StudioUpdatePreparationResult, StudioUpdateStateSnapshot,
    StudioWorktreeInspection, StudioWorktreeRecoveryPreview, ThreadMetadataObservation,
    ThreadPreparationObserver, ThreadRecord, ThreadsObservation, WorkspaceRecord,
};
pub use studio::{
    BuildInfoV3, ChatItemHeaderExportV3, CompletionCursorV3, ConfigInputEntryV3, EventBodyV3,
    EventSourceV3, EventV3, ExecutionErrorStage, ExecutionErrorV3, ExecutionLifecycleExportV3,
    ExecutionOutcome, ExportSchemaV3, ExportedBlobV3, ExportedContentV3,
    ExportedHistoryEventHeaderV3, ModelUsageExportV3, RESULT_SCHEMA_VERSION, ResultOutcome,
    ResultV3, RunExportOptions, RunExportReport, RunExporter, RunInvocationV3, RunManifestV3,
    SealedMemberCutV3, SkillSearchManifestV3, ThreadUsageExportV3, TimingReportV3, TraceSummaryV3,
    UsageCoverage, UsageExportV3, UsageKnownTotalsV3, UsageMetricKey, UsageTotalsV3,
    export_sha256_hex, format_export_utc_rfc3339, validate_export_output_dir_preflight,
};
pub use worker_assets::RemoteHelperSource;

// 公开签名或外部 crate 直接命名的下层类型在此精确重导出。
// 只被 crate 根路径内部使用、且不出现在公开签名中的别名收为 pub(crate)。
pub(crate) use pl_model::completion::{
    AttachmentModality, InferenceModelObservation, InferenceTiming, MessageContent, MessageRole,
    ToolSpec,
};
pub use pl_model::completion::{
    InferenceBillingRecord, Message, MessagePresentation, ModelContextItem, ThreadAttachment,
    ToolResultRecord,
};
pub(crate) use pl_model::config::AgentRoleId;
pub use pl_model::config::{
    AccountAuthenticationMethod, AccountCatalogSnapshot, BillingKind, ModelCapabilitiesDto,
    ModelDescriptor, ModelInputCapabilityDto, ModelInputSourceDto, ModelModalityDto,
    ModelOriginDto, ModelSelectionGuideDto, ModelSelectionSourceKindDto,
};
pub use pl_model::model::{
    AgentTaskCategory, InferenceAccounting, ModelContextAdjustment, ModelContextUnavailable,
    ModelPricingDto, ModelType, ModelTypeExclusion, PricingOutcome, RuntimeCostAmount, UsageReport,
};
pub(crate) use pl_model::model::{PricingMode, UnpricedReason};
pub use pl_model::runtime::PromptPrefixChangedReason;
pub use pl_model_auth::chatgpt::ChatGptAccountInfo;
pub(crate) use pl_model_auth::chatgpt::CodexAccountInfo;
pub use pl_protocol::{
    AgentBackendKind, AgentId, AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode,
    DelegationMode, DelegationPreference, DelegationSettings, FirstOutputSource,
    NewThreadModelRoute, ProviderFailureKind, PureError, Result, RetryDisposition, StateError,
    UnknownLabelError,
};
pub(crate) use pl_protocol::{
    AgentReviewBaseline, AgentReviewFeedback, AgentReviewTargetSnapshot, AgentThreadIdentity,
    AgentWorktreeSnapshot, LabeledEnum, SessionId, ThreadId,
};
pub use pl_studio_statistics::{MetricAvailability, ModelMatchState, UsageReportStatus};
pub(crate) use pl_tool::ask_user::UserQuestionOption;
pub use pl_tool::ask_user::{AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, UserQuestion};
pub use pl_tool::mcp::{McpAvailabilityDescriptor, McpHealthSnapshot, McpServerDescriptor};
pub use pl_tool::todo::{TodoItem, TodoListSnapshot, TodoStatus};

mod programmatic;

pub mod plan_tool;

pub mod workflow_tool;

pub mod mode;

mod tool_review;

mod startup_timing;

#[cfg(all(test, target_os = "linux"))]
#[path = "../tests/support/acp_transport_fixture.rs"]
mod acp_transport_fixture;

#[cfg(test)]
#[expect(
    dead_code,
    reason = "the shared fixture also serves standalone integration test binaries"
)]
#[path = "../tests/support/mod.rs"]
pub(crate) mod runtime_test_support;

#[cfg(test)]
#[path = "../../pl-tool/tests/support/binding_host.rs"]
mod test_fixture_binding_host;

#[cfg(test)]
#[expect(dead_code, reason = "shared real stdio protocol fixture")]
#[path = "../../pl-tool/tests/support/mcp_stdio.rs"]
mod test_fixture_mcp_stdio;
