mod account_catalog;
mod accounting;
mod activity;
mod agent;
mod agent_profile;
pub mod agent_session;
mod billing;
mod delegation;
mod error;
mod event;
mod id;
mod interaction;
mod labeled;
mod mcp;
mod message;
mod model_context;
mod observed_state;
mod permission;
pub mod process_worker;
pub mod remote;
pub mod session_runtime;
pub mod studio;
pub mod thread;
mod thread_item;
pub mod timeline_content;
mod tool;
mod turn;
mod turn_failure;
mod workflow;

pub use account_catalog::{
    ACCOUNT_CATALOG_SCHEMA_VERSION, AccountCatalogSnapshot, AccountServiceCapabilitiesDescriptor,
    AccountTemplateDescriptor, BillingKind, ConnectionModeDescriptor, CredentialDescriptorDto,
    ModelCapabilitiesDto, ModelCatalogDescriptor, ModelContextAdjustment, ModelContextResolution,
    ModelContextUnavailable, ModelDescriptor, ModelInputCapabilityDto, ModelInputSourceDto,
    ModelModalityDto, ModelOriginDto, ModelPriceTierDto, ModelPricingDto, ModelReasoningDescriptor,
    ModelSelectionGuideDto, ModelSelectionMeasurementDto, ModelSelectionSourceDto,
    ModelSelectionSourceKindDto, ModelTransportDescriptor, ModelType, ModelTypeExclusion,
    ModelTypeSupport, WebSearchResolutionDescriptor, WebSearchServiceCapabilitiesDescriptor,
};
pub use accounting::{
    InferenceAccounting, PricingMode, PricingOutcome, UnpricedReason, UsageReport, UsageStatus,
};
pub use activity::{
    ACTIVITY_SUMMARY_LIMIT, ThreadActivity, ThreadActivityArguments, ThreadActivityContentPart,
    ThreadActivityDetail, ThreadActivityDetailQuery, ThreadActivityKind, ThreadActivityToolDetail,
    ThreadActivityToolEntry, ThreadActivityToolState, ThreadActivityTools,
};
pub use agent::*;
pub use agent_profile::{
    AgentProfileSnapshot, AgentReviewTargetSnapshot, AgentWorkspaceAssignmentSnapshot,
    AgentWorkspaceMode, AgentWorktreeSnapshot,
};
pub use agent_session::plan::{
    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, AgentSessionPlanAvailableTransition,
    AgentSessionPlanConfirmationPurpose, AgentSessionPlanDocument,
    AgentSessionPlanMutationResponse, AgentSessionPlanOperation, AgentSessionPlanOperationReceipt,
    AgentSessionPlanPhase, AgentSessionPlanResultCode, AgentSessionPlanRuntimeSnapshot,
    AgentSessionPlanSnapshot, AgentSessionPlanState, AgentSessionPlanTransitionActor,
    AgentSessionPlanTransitionError, AgentSessionPlanTransitionRecord,
};
pub use billing::{
    InferenceBillingAppend, InferenceBillingRecord, InferenceModelObservation,
    InferenceOrchestrationMetrics, InferenceTiming, InferenceTokenUsage, ModelMatchState,
    ModelPricingSnapshot, TurnBillingRecord,
};
pub use delegation::{
    AGENT_EVALUATION_COMMENT_MAX_CHARS, AGENT_EVALUATION_WINDOW, AgentEvaluation,
    AgentEvaluationOutcome, AgentEvaluationSummary, AgentEvaluationWrite, AgentTaskCategory,
    DELEGATION_MODEL_CURSOR_VERSION, DELEGATION_MODEL_PAGE_DEFAULT, DELEGATION_MODEL_PAGE_MAX,
    DelegationMode, DelegationModelCapability, DelegationModelCursor, DelegationModelDetail,
    DelegationModelFilter, DelegationModelKey, DelegationModelList, DelegationModelListItem,
    DelegationPreference, DelegationSettings, EvaluateAgentReceipt, EvaluateAgentRequest,
    GetDelegationModelRequest, ListDelegationModelsRequest, LocalModelPerformanceSummary,
};
pub use error::{PureError, Result};
pub use event::{
    AgentRuntimeDelta, BudgetLimitKind, BudgetLimitSnapshot, BudgetUsage, ErrorSeverity,
    OutputStream, PipelineStage, RuntimeCostAmount, RuntimeUsageSnapshot, SkillActivation,
    SkillActivationCause, SkillActivationResourceBase, TodoItem, TodoListSnapshot, TodoStatus,
    TokenUsageSnapshot, UserInputAnswer, UserInputRequest, UserInputResponse, UserQuestion,
    UserQuestionOption,
};
pub use id::{AgentRoleId, ThreadId, TurnId};
pub use interaction::*;
pub use labeled::{LabeledEnum, UnknownLabelError};
pub use mcp::{McpAvailabilityDescriptor, McpHealthSnapshot, McpServerDescriptor};
pub use message::{
    AttachmentModality, ContentPart, Message, MessageContent, MessagePresentation, MessageRole,
    ToolCallCaller, ToolCallKind, ToolCallRecord, ToolResultRecord,
};
pub use model_context::{
    AgentSessionSnapshot, AgentWorkingState, ContextSectionId, ContextSectionIdError,
    ConversationExternalStatePolicy, ConversationRecoveryMode, ConversationRecoveryRecord,
    ConversationRecoveryState, ConversationRecoveryTurnRange, ModelContextItem,
    ModelContextSectionSnapshot, ModelContextSnapshot, PinnedContextSection,
    PromptPrefixChangedReason, ResponsesContextItem, ResponsesContextItemKind, SessionNote,
    ThreadPromptMetadata, ThreadPromptSnapshot, ToolDiscoveryState, ToolMediaContext,
    ToolResultReceipt,
};
pub use observed_state::{
    DegradedResource, FailedResource, LoadingResource, ObservedResource, ObservedResourceCommand,
    ObservedResourceKind, ObservedResourceTransitionDecision, ObservedResourceTransitionError,
    ReadyResource, RefreshingResource, StaleResource, StateError, StateOperation, StoppedResource,
    UninitializedResource,
};
pub use permission::PermissionLevel;
pub use timeline_content::{
    ThreadContentField, ThreadUserInputFieldPart, TimelineAnswerDescriptor, TimelineChange,
    TimelineDescriptor, TimelineDetailChunk, TimelineDetailCursor, TimelineDetailQuery,
    TimelineDetailRef, TimelineFieldChange, TimelineFieldPreview, TimelineFieldUpdate,
    TimelineItem, TimelineItemHeader, TimelineItemSource, TimelineLifecycle, TimelinePage,
    TimelinePageCursor, TimelinePageQuery, TimelinePriority, TimelineQuestionDescriptor,
    TimelineRawDescriptor, TimelineRawPayloadDescriptor, TimelineRecoveryNotice,
    TimelineResyncReason, TimelineTailBaseline, TimelineTailUpdate, TimelineTextDescriptor,
    TimelineThinkingDescriptor, TimelineToolDescriptor, TimelineToolInvocation,
    TimelineToolOutputDescriptor, TimelineToolState, TimelineUserInputDescriptor,
    TimelineUserInputState,
};
// 持久化观测契约（队列压力、逐 Thread 水位）同时由 runtime 协调器与其上层
// bridge/HTTP 适配器命名，因此在 crate 根重导出，消费方无需再拼 `studio::` 路径。
pub use studio::{
    PersistenceQueueSnapshot, ThreadPersistenceSnapshot, ThreadStorageExecution, ThreadStorageState,
};
pub use thread::mode::*;
pub use thread::{
    CacheUsageSummary, THREAD_SCHEMA_VERSION, Thread, ThreadContextDisposition,
    ThreadModelRouteSnapshot, ThreadNotification, ThreadNotificationEnvelope,
    ThreadRuntimeLiveUsage, ThreadRuntimeSnapshot, ThreadRuntimeUsage, ThreadRuntimeUsageState,
    ThreadSnapshot, ThreadStatus, ThreadSubscriptionRequest, ThreadSubscriptionUpdate,
    ThreadTurnHistory, ThreadTurnPage, ThreadWorkspaceMode, TimelineTurn,
};
mod session_entry;
pub use session_entry::SessionEntry;
pub use thread_item::*;
pub use tool::{
    HostedWebSearchDialect, HostedWebSearchOptions, ToolCallerMode, ToolFormat, ToolSpec,
    WebSearchContextSize, WebSearchFilters, WebSearchUserLocation, WebSearchUserLocationType,
};
pub use turn::{
    BudgetLimitedTurnOutcome, BudgetLimitedTurnState, CancelledTurnOutcome, CancelledTurnState,
    CompletedTurnOutcome, CompletedTurnState, FailedTurnOutcome, FailedTurnState, QueuedTurnState,
    RunningTurnState, Turn, TurnCancellationCause, TurnCommand, TurnCompletion, TurnOutcome,
    TurnPhase, TurnRolloverOutcome, TurnState, TurnTransitionDecision, TurnTransitionError,
};
pub use turn_failure::{
    ProviderFailure, ProviderFailureContext, ProviderFailureKind, ProviderFailureStage,
    ProviderRecovery, RetryDisposition, TurnFailure, TurnFailureCategory,
};
pub use workflow::{
    WorkflowDefinition, WorkflowOperationReceipt, WorkflowRun, WorkflowRunArchive,
    WorkflowRunLifecycle, WorkflowRuntimeRunSnapshot, WorkflowRuntimeSnapshot,
    WorkflowSessionState, WorkflowState, WorkflowStateKind, WorkflowTransition,
    WorkflowTransitionRecord,
};

/// Search request and configuration interchange shared by upper adapters.
pub mod search;

/// Product trace records and their typed wire projection.
pub mod trace;

/// Shared model/tool projection materials; core carries their encoded payload without decoding.
pub mod tool_projection;
