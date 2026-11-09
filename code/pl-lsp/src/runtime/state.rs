use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LspAvailabilityKind {
    Checking,
    Available,
    Unavailable,
    MissingCommand,
    Disabled,
}

/// LSP reset 的明确作用域。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LspScope {
    Server {
        workspace_root: PathBuf,
        server_id: String,
    },
    Workspace {
        workspace_root: PathBuf,
    },
    All,
}

impl LspAvailabilityKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Checking => "checking",
            Self::Available => "available",
            Self::Unavailable => "unavailable",
            Self::MissingCommand => "missingCommand",
            Self::Disabled => "disabled",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LspActivityKind {
    Idle,
    Busy,
    Indexing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LspLifecyclePhase {
    Loading,
    Probing,
    Starting,
    Initializing,
    Ready,
    Failed,
    Stopped,
    Disabled,
}

impl LspActivityKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Busy => "busy",
            Self::Indexing => "indexing",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LspServerSnapshot {
    pub id: String,
    pub configuration_path: Option<String>,
    pub phase: LspLifecyclePhase,
    pub display_name: String,
    pub extensions: Vec<String>,
    pub language_ids: Vec<String>,
    pub availability_kind: LspAvailabilityKind,
    pub availability_message: Option<String>,
    pub last_checked_at: Option<i64>,
    pub diagnostic_count: usize,
    pub activity_kind: LspActivityKind,
    pub activity_title: Option<String>,
    pub activity_message: Option<String>,
    pub activity_percentage: Option<u32>,
    pub last_error: Option<String>,
    pub last_error_at: Option<i64>,
}
