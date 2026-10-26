//! Immutable Workspace directory reads. Cursors and field/list IDs belong to the issued value.
use serde::{Deserialize, Serialize};

use super::primitives::TypedListRef;
use crate::products::identity::{ProductCollectionRef, ProductEntityRef};
use crate::products::source::SourceStateErrorRead;
use crate::studio::{ReadText, ThreadDirectoryQuery};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ThreadDirectoryScope {
    Query {
        query: ThreadDirectoryQuery,
        include_pinned: bool,
    },
    Thread {
        thread_id: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectDirectoryReadHeader {
    pub projects: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentDirectoryReadHeader {
    pub agents: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryReadHeader {
    pub threads: TypedListRef,
    pub next_cursor: Option<ReadText>,
    pub has_more: bool,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectRecordRead {
    pub id: ReadText,
    pub name: ReadText,
    pub path: ReadText,
    pub ssh_alias: Option<ReadText>,
    pub updated_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FrozenModelSelectionRead {
    pub account_id: ReadText,
    pub model_id: ReadText,
    pub effort: Option<ReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkspaceThreadRecordRead {
    pub id: ReadText,
    pub project_id: ReadText,
    pub title: ReadText,
    pub mode: ReadText,
    pub workspace_mode: crate::ThreadWorkspaceMode,
    pub delegation_mode: crate::DelegationMode,
    pub delegation_preference: crate::DelegationPreference,
    pub frozen_model: Option<FrozenModelSelectionRead>,
    pub workspace_path: ReadText,
    pub root_thread_id: ReadText,
    pub parent_thread_id: Option<ReadText>,
    pub role: ReadText,
    pub agent_path: ReadText,
    pub status: crate::ThreadStatus,
    pub created_at: i64,
    pub updated_at: i64,
    pub last_user_message_at: Option<i64>,
    pub archived: bool,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentBudgetPauseRead {
    pub turn_id: ReadText,
    pub limit: crate::BudgetLimitSnapshot,
    pub paused_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum AgentStateRead {
    Idle {
        budget_pause: Option<AgentBudgetPauseRead>,
    },
    Queued {
        turn_id: ReadText,
    },
    Running {
        turn_id: ReadText,
    },
    WaitingTool {
        turn_id: ReadText,
    },
    WaitingInteraction {
        turn_id: ReadText,
        interaction_id: ReadText,
    },
    Cancelling {
        turn_id: ReadText,
    },
    Closing {
        workspace_disposition: crate::AgentWorkspaceDisposition,
        turn_id: Option<ReadText>,
        error: Option<SourceStateErrorRead>,
    },
    Closed,
    Faulted {
        error: SourceStateErrorRead,
        turn_id: Option<ReadText>,
        classification: crate::AgentFaultClassification,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentDirectoryEntryRead {
    pub id: ReadText,
    pub thread_id: ReadText,
    pub root_thread_id: ReadText,
    pub path: ReadText,
    pub parent_path: Option<ReadText>,
    pub role: ReadText,
    pub task: ReadText,
    pub summary: Option<ReadText>,
    pub delegation_mode: crate::DelegationMode,
    pub delegation_preference: crate::DelegationPreference,
    pub frozen_model: Option<FrozenModelSelectionRead>,
    pub depth: u32,
    pub state: AgentStateRead,
    pub execution: Option<crate::AgentExecution>,
    pub can_stop: bool,
    pub awaiting_scheduling: bool,
    pub updated_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectDirectoryEntityRead {
    pub reference: ProductEntityRef,
    pub value: ProjectRecordRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryEntityRead {
    pub reference: ProductEntityRef,
    pub value: WorkspaceThreadRecordRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentDirectoryEntityRead {
    pub reference: ProductEntityRef,
    pub value: AgentDirectoryEntryRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectDirectoryEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentDirectoryEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryEntryPage {
    pub collection: ProductCollectionRef,
    pub items: Vec<ProductEntityRef>,
    pub next_cursor: Option<ReadText>,
    pub has_more: bool,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectRecordReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<ProjectRecordRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkspaceThreadRecordReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<WorkspaceThreadRecordRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentDirectoryEntryReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<AgentDirectoryEntryRead>,
    pub next_offset: Option<u64>,
}
