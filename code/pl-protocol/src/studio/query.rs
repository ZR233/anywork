//! Studio 查询参数与健康探测响应。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadPageQuery {
    pub cursor: Option<String>,
    pub limit: Option<u32>,
}

impl ThreadPageQuery {
    pub const DEFAULT_LIMIT: u32 = 50;
    pub const MAX_LIMIT: u32 = 200;

    pub fn limit(&self) -> usize {
        self.limit
            .unwrap_or(Self::DEFAULT_LIMIT)
            .clamp(1, Self::MAX_LIMIT) as usize
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct HealthResponse {
    pub status: String,
}

/// Project-scoped directory query; filtering precedes keyset pagination.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryQuery {
    pub workspace_id: Option<String>,
    pub search: Option<String>,
    #[serde(default)]
    pub archived: bool,
    #[serde(default)]
    pub filter: ThreadDirectoryFilter,
    /// Optional fixed membership, used by the bounded pinned group.
    #[serde(default)]
    pub thread_ids: Option<Vec<String>>,
    /// Membership excluded from the independent ordinary window.
    #[serde(default)]
    pub excluded_thread_ids: Vec<String>,
}

/// Immutable keyset demand. A boundary is a saved sort key, not a moving row ID.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryWindow {
    pub before: Option<String>,
    pub limit: u32,
}

impl ThreadDirectoryWindow {
    pub const MAX_LIMIT: u32 = 100;
    pub const MAX_FRAME_BYTES: usize = 256 * 1024;

    pub fn validate(&self) -> Result<(), super::StudioError> {
        if self.limit == 0 || self.limit > Self::MAX_LIMIT {
            return Err(super::StudioError::invalid_argument(
                "Directory window limit must be between 1 and 100",
            ));
        }
        Ok(())
    }
}

/// One complete current result for precisely this query and window.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryFrame {
    pub query: ThreadDirectoryQuery,
    pub window: ThreadDirectoryWindow,
    pub stamp: super::ResourceStamp,
    pub threads: Vec<crate::Thread>,
    pub next_cursor: Option<String>,
}

/// Metadata observation independent of all list memberships.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadMetadataFrame {
    pub thread_id: String,
    pub stamp: super::ResourceStamp,
    pub thread: Option<crate::Thread>,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ThreadDirectoryFilter {
    #[default]
    All,
    Running,
    Attention,
}

impl ThreadDirectoryQuery {
    pub const MAX_ID_FILTER_ITEMS: usize = 64;

    pub fn normalized(mut self) -> Result<Self, super::StudioError> {
        fn normalize(ids: &mut Vec<String>) -> Result<(), super::StudioError> {
            if ids.len() > ThreadDirectoryQuery::MAX_ID_FILTER_ITEMS
                || ids.iter().any(|id| id.trim().is_empty())
            {
                return Err(super::StudioError::invalid_argument(
                    "Directory ID filters require at most 64 nonempty identities",
                ));
            }
            ids.sort();
            ids.dedup();
            Ok(())
        }
        if let Some(ids) = self.thread_ids.as_mut() {
            normalize(ids)?;
        }
        normalize(&mut self.excluded_thread_ids)?;
        Ok(self)
    }

    pub fn matches(&self, thread: &crate::Thread, project_matches: bool) -> bool {
        use crate::ThreadStatus;
        thread.parent_thread_id.is_none()
            && thread.archived == self.archived
            && self
                .thread_ids
                .as_ref()
                .is_none_or(|ids| ids.contains(&thread.id))
            && !self.excluded_thread_ids.contains(&thread.id)
            && self
                .workspace_id
                .as_ref()
                .is_none_or(|id| id.as_str() == thread.workspace_id)
            && (project_matches
                || self.search.as_ref().is_none_or(|text| {
                    thread
                        .title
                        .to_lowercase()
                        .contains(&text.trim().to_lowercase())
                }))
            && match self.filter {
                ThreadDirectoryFilter::All => true,
                ThreadDirectoryFilter::Running => matches!(
                    thread.status,
                    ThreadStatus::Queued
                        | ThreadStatus::Running
                        | ThreadStatus::WaitingTool
                        | ThreadStatus::Cancelling
                ),
                ThreadDirectoryFilter::Attention => matches!(
                    thread.status,
                    ThreadStatus::WaitingInteraction | ThreadStatus::Faulted
                ),
            }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RenameProjectRequest {
    pub name: String,
}
