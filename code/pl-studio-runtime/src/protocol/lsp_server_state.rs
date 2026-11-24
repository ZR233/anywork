//! LSP server 可用性与 Available 内活动状态。

use serde::{Deserialize, Serialize};

use crate::StateError;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum StudioLspServerState {
    Checking(LspChecking),
    Available(LspAvailable),
    Unavailable(LspUnavailable),
    Disabled(LspDisabled),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspAvailable {
    checked_at: i64,
    diagnostic_count: u64,
    activity: LspAvailableActivity,
}

impl LspAvailable {
    pub fn new(checked_at: i64, diagnostic_count: u64, activity: LspAvailableActivity) -> Self {
        Self {
            checked_at,
            diagnostic_count,
            activity,
        }
    }

    pub fn checked_at(&self) -> i64 {
        self.checked_at
    }

    pub fn diagnostic_count(&self) -> u64 {
        self.diagnostic_count
    }

    pub fn activity(&self) -> &LspAvailableActivity {
        &self.activity
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum LspAvailableActivity {
    Idle(LspIdle),
    Busy(LspBusy),
    Indexing(LspIndexing),
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct LspIdle;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LspActivityProgress {
    title: Option<String>,
    message: Option<String>,
    percentage: Option<u32>,
}

impl LspActivityProgress {
    fn new(title: Option<String>, message: Option<String>, percentage: Option<u32>) -> Self {
        Self {
            title,
            message,
            percentage,
        }
    }

    fn title(&self) -> Option<&str> {
        self.title.as_deref()
    }

    fn message(&self) -> Option<&str> {
        self.message.as_deref()
    }

    fn percentage(&self) -> Option<u32> {
        self.percentage
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(transparent)]
pub struct LspBusy(LspActivityProgress);

impl LspBusy {
    pub fn new(title: Option<String>, message: Option<String>, percentage: Option<u32>) -> Self {
        Self(LspActivityProgress::new(title, message, percentage))
    }

    pub fn title(&self) -> Option<&str> {
        self.0.title()
    }

    pub fn message(&self) -> Option<&str> {
        self.0.message()
    }

    pub fn percentage(&self) -> Option<u32> {
        self.0.percentage()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(transparent)]
pub struct LspIndexing(LspActivityProgress);

impl LspIndexing {
    pub fn new(title: Option<String>, message: Option<String>, percentage: Option<u32>) -> Self {
        Self(LspActivityProgress::new(title, message, percentage))
    }

    pub fn title(&self) -> Option<&str> {
        self.0.title()
    }

    pub fn message(&self) -> Option<&str> {
        self.0.message()
    }

    pub fn percentage(&self) -> Option<u32> {
        self.0.percentage()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspChecking {
    message: String,
}

impl LspChecking {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspDisabled {
    message: String,
}

impl LspDisabled {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspUnavailable {
    checked_at: i64,
    error: StateError,
}

impl LspUnavailable {
    pub fn new(checked_at: i64, error: StateError) -> Self {
        Self { checked_at, error }
    }

    pub fn checked_at(&self) -> i64 {
        self.checked_at
    }

    pub fn error(&self) -> &StateError {
        &self.error
    }
}
