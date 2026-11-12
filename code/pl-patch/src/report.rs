//! Serializable, ordered facts; file contents never cross the execution boundary.
use crate::{PatchFileChange, PatchOutcome, PatchPathDisplay};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PatchChange {
    Add { path: String },
    Update { path: String },
    Delete { path: String },
    Move { source: String, target: String },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PatchReport {
    pub changes: Vec<PatchChange>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[error("{diagnostic}")]
pub struct PatchFailure {
    pub diagnostic: String,
    pub applied_changes: Vec<PatchChange>,
    pub changes_may_be_incomplete: bool,
}

impl PatchOutcome {
    pub fn report(&self, display: &impl PatchPathDisplay) -> PatchReport {
        PatchReport {
            changes: self
                .file_changes()
                .into_iter()
                .map(|change| match change {
                    PatchFileChange::Add { path } => PatchChange::Add {
                        path: display.display_path(&path),
                    },
                    PatchFileChange::Update { path } => PatchChange::Update {
                        path: display.display_path(&path),
                    },
                    PatchFileChange::Delete { path } => PatchChange::Delete {
                        path: display.display_path(&path),
                    },
                    PatchFileChange::Move { source, target } => PatchChange::Move {
                        source: display.display_path(&source),
                        target: display.display_path(&target),
                    },
                })
                .collect(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PatchPathRole {
    Add,
    Delete,
    Update,
    MoveSource,
    MoveTarget,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AffectedPath {
    pub path: String,
    pub role: PatchPathRole,
}

/// Uses the same parser as execution. Does not resolve, read or modify any file.
pub fn affected_paths(patch: &str) -> crate::PatchResult<Vec<AffectedPath>> {
    use crate::parse::Hunk;
    let mut paths = Vec::new();
    for hunk in crate::parse::parse_patch(patch)? {
        match hunk {
            Hunk::Add { path, .. } => paths.push(AffectedPath {
                path,
                role: PatchPathRole::Add,
            }),
            Hunk::Delete { path } => paths.push(AffectedPath {
                path,
                role: PatchPathRole::Delete,
            }),
            Hunk::Update {
                path, move_path, ..
            } => {
                paths.push(AffectedPath {
                    path,
                    role: if move_path.is_some() {
                        PatchPathRole::MoveSource
                    } else {
                        PatchPathRole::Update
                    },
                });
                if let Some(path) = move_path {
                    paths.push(AffectedPath {
                        path,
                        role: PatchPathRole::MoveTarget,
                    });
                }
            }
        }
    }
    Ok(paths)
}
