//! anywork 产品运行时。
//!
//! 本 crate 负责 Studio 配置、SQLite projection、project/thread 编排与 bridge DTO；
//! 通用模型循环、agent actor、工具和协议基础类型由 `pl-core` 提供。

// Unit tests reuse the same isolated Runtime fixtures as the integration binaries.
#[cfg(test)]
extern crate self as pl_studio_runtime;

pub(crate) use pl_core::context::content_hash as canonical_content_hash;
pub(crate) use studio::thread_projection::{ExecutionItem, ExecutionKind, ExecutionShape};
pub use studio::{AcpSessionCompletion, AcpSessionObservation, AcpSessionOpen};
// Execution/storage diagnostics may name the Core's opaque completion records.
pub use pl_core::chat::{ChatError, ChatItem, ChatKey};
pub use pl_core::model::ContentBlock;
mod hash;
mod toml_schema;

pub mod agent;
pub mod approval;
pub use approval::PermissionMode;
mod account_usage;
mod bots;
pub mod channel_output;
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
pub mod thread_assembler;
mod worker_assets;

// Data types needed to call Studio's SSH API; transport consumers do not depend on tool runtimes.
pub use pl_tool::remote::{
    RemoteDirectoryEntry, RemoteDirectoryListing, RemoteErrorCode, SshConfigEntry, SshConfigFile,
    SshConnectionSnapshot, SshConnectionState, SshServerProfile,
};

pub use pl_tool::skill::{
    SkillActivation, SkillActivationCause, SkillActivationResourceBase, SkillCatalog,
    SkillMetadata, SkillResourceBase, SkillSearchOptions, SkillSourceKind,
};

pub use config::{
    AccountId, ConfigPaths, ConfigRuntimeError, ConfigRuntimeSnapshot, ConfigStore,
    DeepSeekWebSearchConfig, McpCatalogResource, McpDocumentError, McpFileSpecV1, McpFileV1,
    ModelCatalogRuntimeSnapshot, ReasoningEffort, ResolvedThreadMcpServer,
    STUDIO_CONFIG_SCHEMA_VERSION, ScopedEffectiveMcpServer, StudioConfig, StudioUiConfig,
    UserAgentProfile, WebSearchContextSize, WebSearchLocation, WebSearchMode,
};
pub use config_editor::{AccountEdit, AccountModelEdit};
pub use error_mapping::{studio_error_from_anyhow, studio_error_from_anyhow_ref};
pub use host_mcp_assets::HostMcpSource;
pub use protocol::*;

pub use studio::{
    AttachmentRecord, CurrentBodyWatch, CurrentReader, CurrentWatch, DisplayDownloadOutcome,
    DisplayDownloadRequest, PersistenceState, PersistenceStateSnapshot, ProductEventBus,
    ProductTopicReceiver, ProductTopicRecvError, ProductTopicTryRecvError, SkillSearchResult,
    SkillsStateSnapshot, SshPasswordUpdate, SshServerRuntimeEntry, StudioDatabaseError,
    StudioHostKind, StudioInstance, StudioInstanceLease, StudioProductTopicSubscription,
    StudioReadyUpdate, StudioRecoveryImpact, StudioRecoveryIssue, StudioRecoveryIssueAction,
    StudioRecoveryIssueCategory, StudioRecoveryIssueScope, StudioRecoveryWorktreeOwner,
    StudioRuntime, StudioRuntimeLifecycleState, StudioRuntimeOptions, StudioRuntimeSnapshot,
    StudioRuntimeStateKind, StudioStartNewThreadRequest, StudioStartNewThreadResponse,
    StudioStartupError, StudioStartupErrorKind, StudioStartupPolicy, StudioStartupRecovery,
    StudioStore, StudioSubmitPromptOptions, StudioSubmitPromptRequest, StudioSubmitPromptResponse,
    StudioUpdateActivity, StudioUpdatePreparationResult, StudioUpdateStateSnapshot,
    StudioWorktreeInspection, StudioWorktreeRecoveryPreview, ThreadMetadataObservation,
    ThreadPreparationObserver, ThreadRecord, ThreadsObservation, WorkspaceRecord,
};
pub use studio::{
    BuildInfoV3, ChatItemHeaderExportV3, CompletionCursorV3, ConfigInputEntryV3,
    EVENTS_SCHEMA_VERSION, EventBodyV3, EventSourceV3, EventV3, ExecutionErrorStage,
    ExecutionErrorV3, ExecutionLifecycleExportV3, ExecutionOutcome, ExportSchemaV3, ExportedBlobV3,
    ExportedContentV3, ExportedHistoryEventHeaderV3, ModelUsageExportV3, RESULT_SCHEMA_VERSION,
    RUN_MANIFEST_SCHEMA_VERSION, ResultOutcome, ResultV3, RunExportOptions, RunExportReport,
    RunExporter, RunInvocationV3, RunManifestV3, SealedMemberCutV3, SkillSearchManifestV3,
    ThreadUsageExportV3, TimingReportV3, TraceSummaryV3, UsageCoverage, UsageExportV3,
    UsageKnownTotalsV3, UsageMetricKey, UsageTotalsV3, export_sha256_hex,
    format_export_utc_rfc3339, prepare_export_output_dir, validate_export_output_dir_preflight,
};
pub use worker_assets::RemoteHelperSource;

// 公共签名（bridge DTO 字段、HTTP/CLI API 返回值）使用的下层 crate 类型在此精确重导出，
// 消费方只依赖 pl-studio-runtime 即可命名完整签名。
pub use pl_model::completion::{
    AttachmentModality, ContentPart, HostedWebSearchOptions, InferenceBillingRecord,
    InferenceModelObservation, InferenceOrchestrationMetrics, InferenceTiming, InferenceTokenUsage,
    Message, MessageContent, MessagePresentation, MessageRole, ModelContextItem,
    ResponsesContextItem, ResponsesContextItemKind, ThreadAttachment, ToolCallCaller, ToolCallKind,
    ToolCallRecord, ToolCallerMode, ToolFormat, ToolMediaContext, ToolResultReceipt,
    ToolResultRecord, ToolSpec, WebSearchFilters, WebSearchUserLocation, WebSearchUserLocationType,
};
pub use pl_model::config::{
    ACCOUNT_CATALOG_SCHEMA_VERSION, AccountAuthenticationMethod, AccountCatalogSnapshot,
    AccountServiceCapabilitiesDescriptor, AccountTemplateDescriptor, AgentRoleId, BillingKind,
    ConnectionModeDescriptor, CredentialDescriptorDto, ModelCapabilitiesDto,
    ModelCatalogDescriptor, ModelDescriptor, ModelInputCapabilityDto, ModelInputSourceDto,
    ModelModalityDto, ModelOriginDto, ModelReasoningDescriptor, ModelSelectionGuideDto,
    ModelSelectionMeasurementDto, ModelSelectionSourceDto, ModelSelectionSourceKindDto,
    ModelTransportDescriptor, WebSearchServiceCapabilitiesDescriptor,
};
pub use pl_model::model::{
    AgentTaskCategory, InferenceAccounting, ModelContextAdjustment, ModelContextResolution,
    ModelContextUnavailable, ModelPriceTierDto, ModelPricingDto, ModelPricingSnapshot, ModelType,
    ModelTypeExclusion, ModelTypeSupport, PricingMode, PricingOutcome, RuntimeCostAmount,
    UnpricedReason, UsageReport,
};
pub use pl_model::protocol::HostedWebSearchDialect;
pub use pl_model::runtime::{
    PromptPrefixChangedReason, ThreadPromptMetadata, ThreadPromptSnapshot,
};
pub use pl_model_auth::chatgpt::{ChatGptAccountInfo, CodexAccountInfo};
pub use pl_protocol::{
    AgentBackendKind, AgentId, AgentReviewBaseline, AgentReviewFeedback, AgentReviewTargetSnapshot,
    AgentThreadIdentity, AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode,
    AgentWorktreeSnapshot, DelegationMode, DelegationPreference, DelegationSettings,
    FirstOutputSource, LabeledEnum, NewThreadModelRoute, ProviderFailure, ProviderFailureContext,
    ProviderFailureKind, ProviderFailureStage, ProviderRecovery, PureError, Result,
    RetryDisposition, SessionId, StateError, ThreadId, UnknownLabelError,
};
pub use pl_studio_statistics::{MetricAvailability, ModelMatchState, UsageReportStatus};
pub use pl_tool::ask_user::{
    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, UserQuestion, UserQuestionOption,
};
pub use pl_tool::mcp::{McpAvailabilityDescriptor, McpHealthSnapshot, McpServerDescriptor};
pub use pl_tool::session_note::SessionNote;
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
