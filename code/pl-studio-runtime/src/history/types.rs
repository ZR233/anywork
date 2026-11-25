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

/// Write-side atomic history event submitted to `HistoryStore`.
///
/// The owner assigns `seq`; callers leave it at zero. `payload_schema` and `payload_json` hold
/// the open event/business document (with `<= 16 KiB` UTF-8 text inlined under `bodies[].inlineText`
/// and larger/binary payloads attached in `bodies` for `history_bodies` chunk storage).
#[derive(Debug, Clone, PartialEq)]
pub struct HistoryEvent {
    pub seq: u64,
    pub event_id: String,
    pub kind: HistoryEventKind,
    pub timeline_role: HistoryTimelineRole,
    pub occurred_at: Option<i64>,
    pub recorded_at: i64,
    pub run_id: Option<String>,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub call_id: Option<String>,
    pub entity_id: Option<String>,
    pub message_id: Option<String>,
    pub tool_name: Option<String>,
    pub source: Option<HistorySource>,
    pub original: Option<HistoryOriginalInfo>,
    pub row_scope: Option<HistoryBusinessRowScope>,
    pub row_key: Option<String>,
    pub is_anchor: bool,
    pub payload_schema: String,
    pub payload_json: String,
    pub bodies: Vec<HistoryBody>,
}

impl HistoryEvent {
    /// Builds an unaccepted event; `recorded_at` is UTC epoch milliseconds.
    pub fn new(
        event_id: impl Into<String>,
        kind: HistoryEventKind,
        timeline_role: HistoryTimelineRole,
        recorded_at: i64,
    ) -> Self {
        Self {
            seq: 0,
            event_id: event_id.into(),
            kind,
            timeline_role,
            occurred_at: None,
            recorded_at,
            run_id: None,
            turn_id: None,
            attempt_id: None,
            call_id: None,
            entity_id: None,
            message_id: None,
            tool_name: None,
            source: None,
            original: None,
            row_scope: None,
            row_key: None,
            is_anchor: false,
            payload_schema: "anywork.business/1".into(),
            payload_json: "{}".into(),
            bodies: Vec::new(),
        }
    }

    pub fn to_record(&self) -> HistoryEventRecord {
        HistoryEventRecord {
            seq: self.seq,
            event_id: self.event_id.clone(),
            kind: self.kind.clone(),
            timeline_role: self.timeline_role,
            occurred_at: self.occurred_at,
            recorded_at: self.recorded_at,
            run_id: self.run_id.clone(),
            turn_id: self.turn_id.clone(),
            attempt_id: self.attempt_id.clone(),
            call_id: self.call_id.clone(),
            entity_id: self.entity_id.clone(),
            message_id: self.message_id.clone(),
            tool_name: self.tool_name.clone(),
            source: self.source.clone(),
            original: self.original.clone(),
            row_scope: self.row_scope,
            row_key: self.row_key.clone(),
            payload_schema: self.payload_schema.clone(),
            payload_json: self.payload_json.clone(),
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
    /// Accepted events not yet committed to SQLite. These are not durable receipts.
    pub pending_events: usize,
    pub pending_bytes: usize,
    /// Charged RAM, including committed roots still borrowed by in-flight readers.
    pub retained_events: usize,
    pub retained_bytes: usize,
    pub write_error: Option<String>,
    pub accepting: bool,
}

pub(super) fn source_key(source: &HistorySource) -> Result<String> {
    Ok(serde_json::to_string(source)?)
}
