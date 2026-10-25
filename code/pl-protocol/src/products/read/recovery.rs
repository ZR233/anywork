//! Complete Recovery material. Text/list handles are local to their original read scope.
use super::super::identity::{ProductCollectionRef, ProductEntityRef};
use super::primitives::TypedListRef;
use crate::studio::ReadText;
use serde::{Deserialize, Serialize};
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub enum RecoveryScope {
    Application,
    Project,
    Thread,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub enum RecoveryCategory {
    ProcessLease,
    ToolCatalog,
    Repository,
    Storage,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub enum RecoveryAction {
    None,
    Retry,
    CleanupThread,
    RemoveProject,
    CleanupWorktree,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub enum WorktreeOwner {
    Session,
    Child,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecoveryReadHeader {
    pub issues: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorktreeRecoveryPreviewRead {
    pub owner_kind: WorktreeOwner,
    pub owner_thread_id: ReadText,
    pub lease_revision: u64,
    pub state: ReadText,
    pub repository_root: ReadText,
    pub path: ReadText,
    pub branch: ReadText,
    pub base_commit: ReadText,
    pub head_commit: Option<ReadText>,
    pub dirty: bool,
    pub changed_files: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecoveryIssueRead {
    pub id: ReadText,
    pub scope: RecoveryScope,
    pub category: RecoveryCategory,
    pub action: RecoveryAction,
    pub project_id: Option<ReadText>,
    pub thread_id: Option<ReadText>,
    pub message: ReadText,
    pub worktree: Option<WorktreeRecoveryPreviewRead>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecoveryEntityRead {
    pub reference: ProductEntityRef,
    pub value: RecoveryIssueRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecoveryEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecoveryIssueReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<RecoveryIssueRead>,
    pub next_offset: Option<u64>,
}
