//! Thread Mode 使用的扁平确定性状态图协议。

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::thread_mode_id::ThreadModeId;

/// 一个 state 在状态机中的语义种类。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub enum WorkflowStateKind {
    Atomic,
    Final,
}

/// 状态图中的一个 state。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowState {
    pub id: String,
    pub title: String,
    pub instructions: String,
    #[serde(default)]
    pub completion_criteria: Vec<String>,
    pub kind: WorkflowStateKind,
}

/// 一条有向 state transition。
///
/// `guard` 是由 Agent 判断的声明性自然语言条件；Runtime 不执行表达式。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowTransition {
    pub source_state_id: String,
    pub target_state_id: String,
    pub guard: String,
}

/// 注册进 Thread Mode Manager 的完整状态图定义。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowDefinition {
    pub title: String,
    pub goal: String,
    pub initial_state_id: String,
    #[serde(default)]
    pub states: Vec<WorkflowState>,
    #[serde(default)]
    pub transitions: Vec<WorkflowTransition>,
}

/// Result of an isolated replay using the production transition machine.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowPreviewSnapshot {
    pub accepted: bool,
    pub message: String,
    pub current_state: Option<WorkflowState>,
    pub transitions: Vec<WorkflowTransition>,
    pub path: Vec<String>,
    pub terminal: bool,
}

/// 当前 run 的主生命周期。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum WorkflowRunLifecycle {
    Active,
    Terminal,
}

/// 一次已提交的状态转换事实。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowTransitionRecord {
    pub revision: u64,
    pub source_state_id: String,
    pub target_state_id: String,
    #[serde(default)]
    pub forced: bool,
    pub reason: String,
    pub summary: String,
    #[serde(default)]
    pub evidence: Vec<String>,
    pub turn_id: String,
    pub call_id: String,
    pub transitioned_at: i64,
}

/// 与 Agent working state 一起保存的轻量 run。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRun {
    pub lineage_id: String,
    pub run_id: String,
    pub mode_id: ThreadModeId,
    pub graph_revision: u64,
    pub graph_hash: String,
    pub lifecycle: WorkflowRunLifecycle,
    pub current_state_id: String,
    pub started_at: i64,
    pub updated_at: i64,
    #[serde(default)]
    pub history_tail: Vec<WorkflowTransitionRecord>,
    #[serde(default)]
    pub archived_transition_count: u64,
    #[serde(default)]
    pub archived_transition_digest: String,
}

/// 已从热状态归档的 run 摘要。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRunArchive {
    pub lineage_id: String,
    pub run_id: String,
    pub mode_id: ThreadModeId,
    pub graph_revision: u64,
    pub graph_hash: String,
    pub final_state_id: String,
    pub outcome: String,
    pub summary: String,
    pub archived_at: i64,
}

/// 最近一次成功 mutation 的幂等凭据。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowOperationReceipt {
    pub operation_id: String,
    pub argument_hash: String,
    pub operation_revision: u64,
}

/// 与 canonical Agent session 一起保存的工作流状态。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowSessionState {
    #[serde(default)]
    pub revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_run: Option<WorkflowRun>,
    #[serde(default)]
    pub archived_runs: Vec<WorkflowRunArchive>,
    #[serde(default)]
    pub archived_run_count: u64,
    #[serde(default)]
    pub archived_run_digest: String,
    #[serde(default)]
    pub operation_receipts: Vec<WorkflowOperationReceipt>,
}

/// Summary of one valid state in the workflow graph.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowStateBrief {
    pub id: String,
    pub title: String,
    pub kind: WorkflowStateKind,
}

/// Allowed direct transition option from the current workflow state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowAllowedTransition {
    pub target_state_id: String,
    pub target_state_title: String,
    pub target_kind: WorkflowStateKind,
    pub guard: String,
}

/// Rich diagnostic payload returned when `workflow_transition` is rejected.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowTransitionError {
    pub code: String,
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_state_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_state_title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attempted_target_state_id: Option<String>,
    #[serde(default)]
    pub allowed_transitions: Vec<WorkflowAllowedTransition>,
    #[serde(default)]
    pub all_states: Vec<WorkflowStateBrief>,
    pub recovery_action: String,
}

/// Node in the deferred UI workflow graph projection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRuntimeGraphState {
    pub id: String,
    pub title: String,
    pub kind: WorkflowStateKind,
    #[serde(default)]
    pub instructions: String,
}

/// Edge in the deferred UI workflow graph projection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRuntimeGraphEdge {
    pub id: String,
    pub source_state_id: String,
    pub target_state_id: String,
    pub guard: String,
}

/// Full frozen workflow graph projected on demand for session status inspection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRuntimeGraphSnapshot {
    pub mode_id: ThreadModeId,
    #[serde(default)]
    pub mode_display_name: String,
    #[serde(default)]
    pub mode_deleted: bool,
    pub initial_state_id: String,
    #[serde(default)]
    pub states: Vec<WorkflowRuntimeGraphState>,
    #[serde(default)]
    pub edges: Vec<WorkflowRuntimeGraphEdge>,
}

/// Thread stream 向 GUI 暴露的轻量当前 run 投影。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRuntimeRunSnapshot {
    pub lineage_id: String,
    pub run_id: String,
    pub mode_id: ThreadModeId,
    pub graph_revision: u64,
    pub graph_hash: String,
    pub lifecycle: WorkflowRunLifecycle,
    #[serde(default)]
    pub current_state_title: String,
    #[serde(default)]
    pub mode_display_name: String,
    #[serde(default)]
    pub mode_deleted: bool,
    pub current_state_id: String,
    #[serde(default)]
    pub visited_state_ids: Vec<String>,
    #[serde(default)]
    pub last_transition_forced: bool,
    pub started_at: i64,
    pub updated_at: i64,
}

/// Thread stream 向 GUI 暴露的当前工作流投影。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRuntimeSnapshot {
    pub revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_run: Option<WorkflowRuntimeRunSnapshot>,
}

fn push_unique_state(visited: &mut Vec<String>, state_id: &str) {
    if !state_id.is_empty() && !visited.iter().any(|existing| existing == state_id) {
        visited.push(state_id.to_string());
    }
}

impl WorkflowRuntimeSnapshot {
    pub(crate) fn from_state(
        state: &WorkflowSessionState,
        current_state_title: &str,
        mode_display_name: &str,
        mode_deleted: bool,
    ) -> Self {
        Self {
            revision: state.revision,
            current_run: state.current_run.as_ref().map(|run| {
                let mut visited = Vec::new();
                if let Some(first) = run.history_tail.first() {
                    push_unique_state(&mut visited, &first.source_state_id);
                }
                for record in &run.history_tail {
                    push_unique_state(&mut visited, &record.target_state_id);
                }
                push_unique_state(&mut visited, &run.current_state_id);
                let last_transition_forced =
                    run.history_tail.last().is_some_and(|record| record.forced);
                WorkflowRuntimeRunSnapshot {
                    lineage_id: run.lineage_id.clone(),
                    run_id: run.run_id.clone(),
                    mode_id: run.mode_id.clone(),
                    graph_revision: run.graph_revision,
                    graph_hash: run.graph_hash.clone(),
                    lifecycle: run.lifecycle,
                    current_state_id: run.current_state_id.clone(),
                    current_state_title: current_state_title.to_string(),
                    mode_display_name: mode_display_name.to_string(),
                    mode_deleted,
                    visited_state_ids: visited,
                    last_transition_forced,
                    started_at: run.started_at,
                    updated_at: run.updated_at,
                }
            }),
        }
    }
}
