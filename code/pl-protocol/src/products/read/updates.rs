//! Native update state and retained task completion, independent from installer handoff.
use crate::products::source::SourceStateErrorRead;
use crate::studio::{FeedCloseOutcome, ReadText};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateTaskIdentity {
    pub runtime_epoch: String,
    pub task_id: String,
    pub operation_id: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateTaskCloseReport {
    pub identity: UpdateTaskIdentity,
    pub outcome: FeedCloseOutcome,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateSummaryRead {
    pub version: ReadText,
    pub published_at: i64,
    pub notes_url: ReadText,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateAssetRead {
    pub url: ReadText,
    pub size: u64,
    pub sha256: ReadText,
    pub signature: ReadText,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateDetailsRead {
    pub summary: UpdateSummaryRead,
    pub installer: UpdateAssetRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateOperationReadHeader {
    pub operation_id: ReadText,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum UpdatesReadHeader {
    Disabled {
        revision: u64,
        updated_at: i64,
    },
    Idle {
        revision: u64,
        updated_at: i64,
    },
    Checking {
        revision: u64,
        operation_id: ReadText,
        started_at: i64,
    },
    UpToDate {
        revision: u64,
        checked_at: i64,
    },
    Available {
        revision: u64,
        checked_at: i64,
        update: UpdateDetailsRead,
    },
    Downloading {
        revision: u64,
        updated_at: i64,
        update: UpdateDetailsRead,
        downloaded: u64,
        total: u64,
    },
    Verifying {
        revision: u64,
        updated_at: i64,
        update: UpdateDetailsRead,
        downloaded: u64,
        total: u64,
    },
    Ready {
        revision: u64,
        ready_at: i64,
        update: UpdateDetailsRead,
    },
    InstallerLaunched {
        revision: u64,
        launched_at: i64,
        update: UpdateDetailsRead,
    },
    CheckFailed {
        revision: u64,
        failed_at: i64,
        error: SourceStateErrorRead,
    },
    InstallFailed {
        revision: u64,
        failed_at: i64,
        update: UpdateDetailsRead,
        error: SourceStateErrorRead,
    },
}
