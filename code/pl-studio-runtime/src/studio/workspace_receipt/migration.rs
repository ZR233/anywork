//! Only the checkpoint-maintenance transaction decodes the retired branch-bearing receipt.
use anyhow::{Result, ensure};
use pl_protocol::{
    AgentReviewTargetSnapshot, AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode,
    AgentWorktreeSnapshot,
};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyWorktree {
    repository_root: String,
    path: String,
    branch: String,
    base_commit: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyAssignment {
    mode: AgentWorkspaceMode,
    project_root: String,
    root: String,
    #[serde(default)]
    writable_paths: Option<Vec<String>>,
    #[serde(default)]
    worktree: Option<LegacyWorktree>,
    #[serde(default)]
    review_target: Option<AgentReviewTargetSnapshot>,
}

pub(crate) fn upgrade(state: &mut pl_core::thread::ThreadSnapshot) -> Result<()> {
    let Some(record) = state.extensions.get_mut(super::EXTENSION) else {
        return Ok(());
    };
    if record.payload.format() == super::FORMAT && record.payload.version() == 1 {
        let legacy: LegacyAssignment = serde_json::from_str(record.payload.content())?;
        let worktree = legacy
            .worktree
            .map(|tree| {
                ensure!(
                    !tree.branch.trim().is_empty(),
                    "legacy worktree receipt branch is empty"
                );
                Ok::<_, anyhow::Error>(AgentWorktreeSnapshot {
                    repository_root: tree.repository_root,
                    path: tree.path,
                    base_commit: tree.base_commit,
                })
            })
            .transpose()?;
        let assignment = AgentWorkspaceAssignmentSnapshot {
            mode: legacy.mode,
            project_root: legacy.project_root,
            root: legacy.root,
            writable_paths: legacy.writable_paths,
            worktree,
            review_target: legacy.review_target,
        };
        record.payload = super::to_payload(&assignment)?;
    }
    super::from_payload(&record.payload)?;
    Ok(())
}
