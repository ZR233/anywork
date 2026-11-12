//! Product projection of ordered patch facts. No filesystem or transport state.
use crate::{PatchChange, PatchReport};
use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PatchOutput {
    pub cwd: String,
    pub added: Vec<String>,
    pub updated: Vec<String>,
    pub deleted: Vec<String>,
    pub moved: Vec<PatchMove>,
    pub changed_files: Vec<String>,
    pub stdout: String,
    pub stderr: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub summary: String,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PatchMove {
    pub from: String,
    pub to: String,
}

impl PatchReport {
    pub fn into_output(self, cwd: String) -> PatchOutput {
        let mut added = Vec::new();
        let mut updated = Vec::new();
        let mut deleted = Vec::new();
        let mut moved = Vec::new();
        let mut changed_files = BTreeSet::new();
        let mut summary = String::from("Success. Updated the following files:\n");
        for change in self.changes {
            match change {
                PatchChange::Add { path } => {
                    summary.push_str(&format!("A {path}\n"));
                    changed_files.insert(path.clone());
                    added.push(path);
                }
                PatchChange::Update { path } => {
                    summary.push_str(&format!("M {path}\n"));
                    changed_files.insert(path.clone());
                    updated.push(path);
                }
                PatchChange::Delete { path } => {
                    summary.push_str(&format!("D {path}\n"));
                    changed_files.insert(path.clone());
                    deleted.push(path);
                }
                PatchChange::Move { source, target } => {
                    summary.push_str(&format!("M {target}\n"));
                    changed_files.insert(source.clone());
                    changed_files.insert(target.clone());
                    moved.push(PatchMove {
                        from: source,
                        to: target,
                    });
                }
            }
        }
        PatchOutput {
            cwd,
            added,
            updated,
            deleted,
            moved,
            changed_files: changed_files.into_iter().collect(),
            stdout: "apply_patch completed".into(),
            stderr: String::new(),
            summary,
        }
    }
}
