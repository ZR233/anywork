use super::runtime::{
    BridgeAgentDirectoryEntryDto, BridgeDegradedResource, BridgeFailedResource,
    BridgeLoadingResource, BridgeLspHealthDto, BridgeMcpHealthDto, BridgeReadyResource,
    BridgeRefreshingResource, BridgeStaleResource, BridgeStoppedResource,
    BridgeUninitializedResource,
};
use super::settings::{BridgeModelCatalogAccountDto, BridgeStudioSettingsDto};
use super::thread_stream::{BridgeRuntimeCostAmount, BridgeThread};
use serde::{Deserialize, Serialize};
// ── Response types ──

/// 一个根会话的作用域费用事实；`cost == null` 是显式清除，不是零费用。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeSessionCostsState {
    pub root_thread_id: String,
    pub revision: u64,
    pub updated_at: i64,
    pub statistics_pending: bool,
    pub statistics_gap: bool,
    pub read_failed: bool,
    pub cost: Option<BridgeSessionCostSnapshot>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeSessionCostSnapshot {
    pub root_thread_id: String,
    pub purpose_costs: Vec<BridgePurposeCostSnapshot>,
    pub estimated_costs: Vec<BridgeRuntimeCostAmount>,
    pub has_unpriced_usage: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgePurposeCostSnapshot {
    pub purpose: Option<String>,
    pub estimated_costs: Vec<BridgeRuntimeCostAmount>,
    pub has_unpriced_usage: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgePersistenceStateSnapshot {
    pub revision: u64,
    pub state: BridgePersistenceState,
}

/// 持久化队列的 typed 快照：发布 revision + 时间基线 + 协调器真实观测。
///
/// `updatedAt` 是本次发布的时间基线；展示"最老待保存年龄"由基线与 payload 的现有
/// age 字段共同表达，不驱动每秒事件或轮询。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgePersistenceQueueStateSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub queue: BridgePersistenceQueueSnapshot,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgePersistenceState {
    Ready {
        pending_commits: u64,
    },
    Flushing {
        pending_commits: u64,
        oldest_pending_revision: Option<u64>,
    },
    Degraded {
        pending_commits: u64,
        oldest_pending_revision: Option<u64>,
        first_failed_at: i64,
        error: super::runtime::BridgeStateError,
    },
    Recovering {
        pending_commits: u64,
        oldest_pending_revision: Option<u64>,
        first_failed_at: i64,
    },
    Blocked {
        pending_commits: u64,
        oldest_pending_revision: Option<u64>,
        first_failed_at: i64,
        error: super::runtime::BridgeStateError,
    },
}

/// 进程级持久化队列压力与逐 Thread 水位。
///
/// 与 [`BridgePersistenceStateSnapshot`] 的单条 owner 状态互补：本快照保留每个 Thread 的
/// checkpoint/history/calls 水位，并把队列字节、最老待保存年龄、在途字节与最近错误一并暴露，
/// 因此 GUI 展示的落后量、压力与错误都来自持久化协调器的真实观测而非本地推算。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgePersistenceQueueSnapshot {
    pub statistics_gap: bool,
    pub pending_operations: u64,
    pub pending_bytes: u64,
    pub in_flight_bytes: u64,
    pub oldest_pending_age_millis: Option<u64>,
    pub last_error: Option<String>,
    pub pressure_paused: bool,
    pub threads: Vec<BridgeThreadPersistenceSnapshot>,
}

/// 单个 Thread 的持久化水位与队列压力。
///
/// 水位字段为 `Some` 表示该 Thread 有正在上报的 writer，值为已观测事实（含 0）；`None`
/// 表示没有 writer 报告过该水位（例如仅通过 checkpoint 回退诊断出现），是未知而非零。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeThreadPersistenceSnapshot {
    pub thread_id: String,
    pub fault_generation: u64,
    pub fault: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state_dirty_revision: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state_saving_revision: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state_durable_revision: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_admitted_sequence: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_durable_sequence: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub calls_admitted_sequence: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub calls_durable_sequence: Option<u64>,
    pub pending_operations: u64,
    pub pending_bytes: u64,
    pub oldest_pending_age_millis: Option<u64>,
    pub in_flight_bytes: u64,
    pub last_error: Option<String>,
    pub pressure_paused: bool,
}

/// 配置级 Agent Profiles 的 canonical 资源快照；与运行期 Agent directory 互不替代。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeAgentProfilesStateSnapshot {
    pub state: BridgeAgentProfilesState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeAgentProfilesState {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeAgentProfilesData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeAgentProfilesData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeAgentProfilesData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeAgentProfilesData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

/// 完整 Profile 配置与逐文件诊断。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeAgentProfilesData {
    pub profiles: Vec<super::agent_profile::BridgeAgentProfileDto>,
    pub diagnostics: Vec<BridgeAgentProfileDiagnostic>,
}

/// 单个 Profile 文件的诊断；只排除对应 Profile，不阻断其余配置。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeAgentProfileDiagnostic {
    pub path: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeProjectDirectoryState {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeProjectDirectoryData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeProjectDirectoryData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeProjectDirectoryData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeProjectDirectoryData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeProjectDirectoryData {
    pub projects: Vec<ProjectDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeThreadDirectoryPage {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeThreadDirectoryPageData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeThreadDirectoryPageData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeThreadDirectoryPageData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeThreadDirectoryPageData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

/// Thread directory 分页窗口页数据（按 `updatedAt` 倒序、id 倒序的 keyset cursor）。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeThreadDirectoryPageData {
    pub threads: Vec<BridgeThread>,
    /// `None` 表示没有更旧的页。
    pub next_cursor: Option<String>,
}

/// `listThreadsPage` 请求；`cursor` 为 `null` 时从最新一页开始。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeListThreadsPageRequest {
    pub cursor: Option<String>,
    pub limit: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeAgentDirectoryState {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeAgentDirectoryData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeAgentDirectoryData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeAgentDirectoryData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeAgentDirectoryData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeAgentDirectoryData {
    pub agents: Vec<BridgeAgentDirectoryEntryDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeSettingsConfigStateSnapshot {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeSettingsConfigStateData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeSettingsConfigStateData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeSettingsConfigStateData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeSettingsConfigStateData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeSettingsConfigStateData {
    pub settings: BridgeStudioSettingsDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeModelCatalogStateSnapshot {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeModelCatalogStateData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeModelCatalogStateData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeModelCatalogStateData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeModelCatalogStateData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeModelCatalogStateData {
    pub accounts: Vec<BridgeModelCatalogAccountDto>,
}

/// Direct command response. The two clocks stay independent even though a
/// command returns both canonical resources for convenience.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeSettingsStateResponse {
    pub config: BridgeSettingsConfigSnapshotDto,
    pub catalog: BridgeModelCatalogSnapshotDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeSettingsConfigSnapshotDto {
    pub revision: u64,
    pub updated_at: i64,
    pub settings: BridgeStudioSettingsDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeModelCatalogSnapshotDto {
    pub revision: u64,
    pub updated_at: i64,
    pub accounts: Vec<BridgeModelCatalogAccountDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeMcpStateSnapshot {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeMcpStateData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeMcpStateData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeMcpStateData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeMcpStateData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeMcpStateData {
    pub desired_config_fingerprint: String,
    pub applied_config_fingerprint: String,
    pub health: BridgeMcpHealthDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeLspStateSnapshot {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeLspStateData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeLspStateData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeLspStateData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeLspStateData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeLspStateData {
    pub health: BridgeLspHealthDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeSkillsStateSnapshot {
    pub project_id: String,
    pub state: BridgeSkillsResourceState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeSkillsResourceState {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeSkillsStateData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeSkillsStateData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeSkillsStateData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeSkillsStateData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeSkillsStateData {
    pub config_fingerprint: String,
    pub catalog_revision: u64,
    pub skills: Vec<SkillSummaryDto>,
    pub warnings: Vec<String>,
    pub complete: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeThreadModeCatalogSnapshot {
    pub revision: u64,
    pub modes: Vec<BridgeThreadModeDescriptor>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeThreadModeDescriptor {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub order: u32,
    pub has_workflow: bool,
    pub read_only: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeAccountUsageStateSnapshot {
    Uninitialized(BridgeUninitializedResource),
    Loading(BridgeLoadingResource),
    Ready {
        resource: BridgeReadyResource,
        value: BridgeAccountUsageStateData,
    },
    Refreshing {
        resource: BridgeRefreshingResource,
        value: BridgeAccountUsageStateData,
    },
    Stale {
        resource: BridgeStaleResource,
        value: BridgeAccountUsageStateData,
    },
    Degraded {
        resource: BridgeDegradedResource,
        value: BridgeAccountUsageStateData,
    },
    Failed(BridgeFailedResource),
    Stopped(BridgeStoppedResource),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BridgeAccountUsageStateData {
    pub config_fingerprint: String,
    pub usages: Vec<AccountUsageDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectDto {
    pub id: String,
    pub name: String,
    pub path: String,
    pub ssh_alias: Option<String>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SubmitPromptResponse {
    pub thread_id: String,
    pub input_id: String,
    pub cursor: u64,
    pub request_digest: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeInputAcceptanceEvidence {
    pub accepted_sequence: u64,
    pub request_digest: Option<String>,
    pub disposition: BridgePersistedInputDisposition,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgePersistedInputDisposition {
    Consumed,
    Discarded,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct StartNewThreadResponse {
    pub thread: BridgeThread,
    pub receipt: SubmitPromptResponse,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveThreadResult {
    pub archived_root_id: String,
    pub removed_thread_ids: Vec<String>,
    pub next_root: Option<BridgeThread>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AccountUsagesResponse {
    pub usages: Vec<AccountUsageDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AccountUsageDto {
    pub account_id: String,
    pub revision: u64,
    pub updated_at: i64,
    pub state: BridgeAccountUsageState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeAccountUsageState {
    Unsupported,
    MissingCredential {
        message: String,
    },
    Ready {
        data: BridgeAccountUsageData,
    },
    Failed {
        error: super::runtime::BridgeStateError,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeAccountUsageData {
    DeepSeekBalance(DeepSeekBalanceDto),
    ZhipuCodingPlan(ZhipuCodingPlanUsageDto),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DeepSeekBalanceDto {
    pub is_available: bool,
    pub balances: Vec<DeepSeekBalanceInfoDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DeepSeekBalanceInfoDto {
    pub currency: String,
    pub total_balance: String,
    pub granted_balance: String,
    pub topped_up_balance: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ZhipuCodingPlanUsageDto {
    pub level: Option<String>,
    pub limits: Vec<ZhipuQuotaLimitDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ZhipuQuotaLimitDto {
    pub window: String,
    pub label: String,
    pub percentage: f64,
    pub current_value: Option<f64>,
    pub total: Option<f64>,
    pub remaining: Option<f64>,
    pub next_reset_at: Option<i64>,
    pub usage_details: Vec<ZhipuToolUsageDetailDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ZhipuToolUsageDetailDto {
    pub name: String,
    pub current_value: Option<f64>,
    pub total: Option<f64>,
    pub percentage: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SkillsResponse {
    pub skills: Vec<SkillSummaryDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeSkillSearchResult {
    pub project_id: String,
    pub catalog_revision: u64,
    pub matches: Vec<SkillSummaryDto>,
    pub truncated: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SkillSummaryDto {
    pub name: String,
    pub description: String,
    pub category: Option<String>,
    pub platforms: Vec<String>,
    pub source: String,
    pub provider_id: String,
    pub invocation: SkillInvocationPolicyDto,
    pub resource_base: SkillResourceBaseDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SkillInvocationPolicyDto {
    pub model_invocable: bool,
    pub user_invocable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum SkillResourceBaseDto {
    Directory { path: String },
    Url { url: String },
    Opaque { description: String },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeDirectoryQuery {
    pub project_id: Option<String>,
    pub search: Option<String>,
    pub archived: bool,
    pub filter: BridgeDirectoryFilter,
    pub cursor: Option<String>,
    pub limit: u32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeDirectoryFilter {
    All,
    Running,
    Attention,
}
