use std::sync::Arc;

use serde::Serialize;
use sha2::{Digest, Sha256};

pub use crate::protocol::history::*;

pub const BODY_CHUNK_BYTES: usize = 64 * 1024;
pub const HEAD_MAX_BYTES: usize = 16 * 1024;

pub(crate) fn milliseconds_from_seconds(seconds: i64) -> Result<i64> {
    seconds.checked_mul(1000).ok_or_else(|| {
        HistoryError::InvalidEvent("native timestamp exceeds the history millisecond range".into())
    })
}

#[derive(Debug, thiserror::Error)]
pub enum HistoryError {
    #[error("invalid history event: {0}")]
    InvalidEvent(String),
    #[error("invalid history demand: {0}")]
    InvalidDemand(String),
    #[error("invalid or stale history cursor")]
    InvalidCursor,
    #[error("history identity conflicts: {0}")]
    Conflict(String),
    #[error("history integrity error: {0}")]
    Integrity(String),
    #[error("history object not found: {0}")]
    NotFound(String),
    #[error("history pending capacity reached")]
    Capacity,
    #[error("history owner is closed")]
    Closed,
    #[error(transparent)]
    Database(#[from] sea_orm::DbErr),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Storage(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, HistoryError>;

pub(super) trait HistoryDemandValidation {
    fn validate(self) -> Result<()>;
    fn fits(&self, value: &impl Serialize) -> Result<bool>;
}
impl HistoryDemandValidation for HistoryDemand {
    fn validate(self) -> Result<()> {
        if !(1..=512).contains(&self.max_rows) || !(1..=1024 * 1024).contains(&self.max_bytes) {
            return Err(HistoryError::InvalidDemand(
                "rows must be 1..512 and bytes 1..1048576".into(),
            ));
        }
        Ok(())
    }
    fn fits(&self, value: &impl Serialize) -> Result<bool> {
        Ok(serde_json::to_vec(value)?.len() <= self.max_bytes as usize)
    }
}
/// Immutable bytes supplied by the producer. Reuse this object when retrying an event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryBody {
    pub body_id: String,
    pub body_key: String,
    pub role: HistoryBodyRole,
    pub media_type: Option<String>,
    pub bytes: Arc<[u8]>,
}
impl HistoryBody {
    pub fn new(key: impl Into<String>, role: HistoryBodyRole, bytes: impl Into<Arc<[u8]>>) -> Self {
        Self {
            body_id: uuid::Uuid::new_v4().to_string(),
            body_key: key.into(),
            role,
            media_type: None,
            bytes: bytes.into(),
        }
    }
    pub(super) fn digest(&self) -> Vec<u8> {
        Sha256::digest(&self.bytes).to_vec()
    }
}

/// The owner assigns `header.seq`; callers submit zero. The full semantic batch becomes visible
/// together. Bodies and header references are validated before acceptance.
#[derive(Debug, Clone, PartialEq)]
pub struct HistoryEvent {
    pub header: HistoryEventHeader,
    pub head: Option<HistoryRowHead>,
    pub is_anchor: bool,
    pub payload_body_id: Option<String>,
    pub bodies: Vec<HistoryBody>,
}
impl HistoryEvent {
    /// Builds an unaccepted event; `recorded_at` is UTC epoch milliseconds.
    pub fn new(event_id: impl Into<String>, kind: HistoryEventKind, recorded_at: i64) -> Self {
        Self {
            header: HistoryEventHeader {
                seq: 0,
                event_id: event_id.into(),
                kind,
                run_id: None,
                attempt_id: None,
                entity_id: None,
                turn_id: None,
                source: None,
                call_id: None,
                message_id: None,
                group_id: None,
                row_key: None,
                original: None,
                occurred_at: None,
                recorded_at,
            },
            head: None,
            is_anchor: false,
            payload_body_id: None,
            bodies: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct HistoryLimits {
    pub pending_events: u32,
    pub pending_bytes: u32,
}
impl Default for HistoryLimits {
    fn default() -> Self {
        Self {
            pending_events: 4096,
            pending_bytes: 64 * 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryStatus {
    pub pending_events: usize,
    pub pending_bytes: usize,
    pub write_error: Option<String>,
    pub accepting: bool,
}

pub(super) fn source_key(source: &HistorySource) -> Result<(String, String)> {
    let kind = match source {
        HistorySource::ForegroundTurn { .. } => "foreground_turn",
        HistorySource::Input { .. } => "input",
        HistorySource::InboxMessage { .. } => "inbox_message",
        HistorySource::BackgroundResult { .. } => "background_result",
        HistorySource::Operation { .. } => "operation",
        HistorySource::Receipt { .. } => "receipt",
    };
    Ok((kind.into(), serde_json::to_string(source)?))
}

pub(super) trait HistoryHeadScope {
    fn scope(&self) -> &'static str;
}
impl HistoryHeadScope for HistoryRowHead {
    fn scope(&self) -> &'static str {
        match self {
            Self::Work(_) => "work",
            Self::Single(_) => "single",
            Self::Member(_) => "member",
            Self::Turn(_) => "turn",
            Self::Source(_) => "source",
            Self::Cost(_) => "cost",
            Self::Accounting(_) => "accounting",
        }
    }
}
