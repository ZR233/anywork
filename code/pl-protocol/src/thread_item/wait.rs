//! Shared typed wait/sleep presentation for activity rows and Timeline tool items.
//!
//! Product hosts derive this from canonical wait/sleep parameters, resident task facts and the
//! wait result payload. Missing optional fields stay missing; consumers never invent a countdown,
//! a percentage or a target the parameters did not name.

use serde::{Deserialize, Serialize};

/// Human-readable wait/sleep presentation attached to the original tool call.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadWaitPresentation {
    intent: ThreadWaitIntent,
    state: ThreadWaitState,
    /// Set only when an event wait became ready; never implies every selected task finished.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    messages_ready: Option<bool>,
}

impl ThreadWaitPresentation {
    pub fn new(
        intent: ThreadWaitIntent,
        state: ThreadWaitState,
        messages_ready: Option<bool>,
    ) -> Self {
        Self {
            intent,
            state,
            messages_ready: match (state, messages_ready) {
                (ThreadWaitState::Ready, Some(ready)) => Some(ready),
                _ => None,
            },
        }
    }

    pub fn intent(&self) -> &ThreadWaitIntent {
        &self.intent
    }

    pub fn state(&self) -> ThreadWaitState {
        self.state
    }

    pub fn messages_ready(&self) -> Option<bool> {
        self.messages_ready
    }
}

/// Why this call is waiting: selected tasks plus a timeout, or a timer duration.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ThreadWaitIntent {
    Events {
        targets: Vec<ThreadWaitTarget>,
        timeout_ms: u64,
    },
    Timer {
        duration_ms: u64,
    },
}

/// One selected wait target. Unknown names, summaries and statuses stay absent.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadWaitTarget {
    task_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    tool_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    summary: Option<String>,
    /// True when [`Self::summary`] was cut to [`crate::ACTIVITY_SUMMARY_LIMIT`].
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    summary_truncated: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    status: Option<ThreadWaitTargetStatus>,
}

impl ThreadWaitTarget {
    pub fn new(
        task_id: String,
        tool_name: Option<String>,
        summary: Option<(String, bool)>,
        status: Option<ThreadWaitTargetStatus>,
    ) -> Self {
        let (summary, summary_truncated) = match summary {
            Some((text, truncated)) if !text.is_empty() => (Some(text), truncated),
            _ => (None, false),
        };
        Self {
            task_id,
            tool_name: tool_name.filter(|name| !name.is_empty()),
            summary,
            summary_truncated,
            status,
        }
    }

    pub fn task_id(&self) -> &str {
        &self.task_id
    }

    pub fn tool_name(&self) -> Option<&str> {
        self.tool_name.as_deref()
    }

    pub fn summary(&self) -> Option<&str> {
        self.summary.as_deref()
    }

    pub fn summary_truncated(&self) -> bool {
        self.summary_truncated
    }

    pub fn status(&self) -> Option<ThreadWaitTargetStatus> {
        self.status
    }
}

/// Real scheduler status of a selected task; absence means the fact was not available.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ThreadWaitTargetStatus {
    Running,
    Succeeded,
    Failed,
    Cancelled,
    Interrupted,
}

/// Result of this wait/sleep call. `timedOut` is not a tool failure.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ThreadWaitState {
    Waiting,
    Ready,
    TimedOut,
    Elapsed,
    Cancelled,
    Failed,
    Interrupted,
}
