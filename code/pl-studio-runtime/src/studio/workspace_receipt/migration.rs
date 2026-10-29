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
    review_target: Option<LegacyReviewTarget>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyReviewTarget {
    agent_id: String,
}

impl LegacyReviewTarget {
    fn migrate(self) -> AgentReviewTargetSnapshot {
        AgentReviewTargetSnapshot {
            agent_id: self.agent_id,
            feedback: None,
            baseline: None,
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct V2Assignment {
    mode: AgentWorkspaceMode,
    project_root: String,
    root: String,
    #[serde(default)]
    writable_paths: Option<Vec<String>>,
    #[serde(default)]
    worktree: Option<AgentWorktreeSnapshot>,
    #[serde(default)]
    review_target: Option<LegacyReviewTarget>,
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
            review_target: legacy.review_target.map(LegacyReviewTarget::migrate),
        };
        record.payload = super::to_payload(&assignment)?;
    }
    if record.payload.format() == super::FORMAT && record.payload.version() == 2 {
        let legacy: V2Assignment = serde_json::from_str(record.payload.content())?;
        record.payload = super::to_payload(&AgentWorkspaceAssignmentSnapshot {
            mode: legacy.mode,
            project_root: legacy.project_root,
            root: legacy.root,
            writable_paths: legacy.writable_paths,
            worktree: legacy.worktree,
            review_target: legacy.review_target.map(LegacyReviewTarget::migrate),
        })?;
    }
    super::from_payload(&record.payload)?;
    Ok(())
}
