//! Git command and credential capabilities shared by independent Git tools.
//!
//! This crate does not choose a workspace, resolve accounts, authorize calls,
//! spawn processes or own product history. Hosts supply those capabilities.

use std::{collections::BTreeMap, path::PathBuf};

mod credential;
mod error;
mod execution;
mod policy;

pub use credential::*;
pub use error::*;
pub use execution::*;
pub use policy::GitPolicy;

/// Frozen repository facts, selected by the host before binding a tool.
#[derive(Debug, Clone, PartialEq)]
pub struct GitWorkspaceConfig {
    pub worktree: PathBuf,
    pub git_binary: PathBuf,
    pub policy: GitPolicy,
    pub native_credentials: bool,
    pub default_push_branch: Option<String>,
    pub remote_url: Option<String>,
    pub workspace_info: BTreeMap<String, serde_json::Value>,
}

impl GitWorkspaceConfig {
    pub fn local(worktree: impl Into<PathBuf>) -> Self {
        Self {
            worktree: worktree.into(),
            git_binary: PathBuf::from("git"),
            policy: GitPolicy::default(),
            native_credentials: false,
            default_push_branch: None,
            remote_url: None,
            workspace_info: BTreeMap::new(),
        }
    }

    pub fn with_native_credentials(mut self) -> Self {
        self.native_credentials = true;
        self
    }
}

/// Git's structured domain result, without host context or history metadata.
#[derive(Debug, Clone, PartialEq)]
pub struct GitOutput {
    payload: serde_json::Value,
}

impl GitOutput {
    pub fn new(payload: serde_json::Value) -> Self {
        Self { payload }
    }

    pub fn command(status: i32, stdout: String, stderr: String) -> Self {
        Self::new(serde_json::json!({
            "status": status,
            "stdout": stdout,
            "stderr": stderr,
        }))
    }

    pub fn payload(&self) -> &serde_json::Value {
        &self.payload
    }

    pub fn stdout(&self) -> &str {
        self.payload["stdout"].as_str().unwrap_or_default()
    }
}
