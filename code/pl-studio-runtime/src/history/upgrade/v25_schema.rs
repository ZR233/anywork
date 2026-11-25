//! Frozen Schema 25 wire and persistence types used solely at the explicit migration boundary.

use super::super::{
    HistoryAccountingHead, HistoryBody, HistoryCostHead, HistoryDelivery, HistoryEntityKind,
    HistoryEntityState, HistoryError, HistoryOriginalInfo, HistorySingleVisibility, HistorySource,
    HistorySourceHead, HistoryTurnHead, HistoryWaitHead, Result,
    db::{number, statement},
    types::source_key,
};
use sea_orm::ConnectionTrait;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::history) enum HistoryEventKindV25 {
    RunStarted,
    RunEnded,
    TurnStarted,
    TurnChanged,
    TurnEnded,
    TurnRolledBack,
    SourceStarted,
    SourceEnded,
    InputAccepted,
    InputConsumed,
    InputDiscarded,
    EntityStarted,
    EntityStateChanged,
    EntityEnded,
    ContentBecameVisible,
    GroupOpened,
    GroupHeadChanged,
    GroupClosed,
    BoundaryObserved,
    UsageRecorded,
    UsageAdjusted,
    BackgroundDeliveryRecorded,
    BusinessChanged,
    LegacyObserved,
    Other(String),
}

impl HistoryEventKindV25 {
    pub fn as_str(&self) -> &str {
        match self {
            Self::RunStarted => "run_started",
            Self::RunEnded => "run_ended",
            Self::TurnStarted => "turn_started",
            Self::TurnChanged => "turn_changed",
            Self::TurnEnded => "turn_ended",
            Self::TurnRolledBack => "turn_rolled_back",
            Self::SourceStarted => "source_started",
            Self::SourceEnded => "source_ended",
            Self::InputAccepted => "input_accepted",
            Self::InputConsumed => "input_consumed",
            Self::InputDiscarded => "input_discarded",
            Self::EntityStarted => "entity_started",
            Self::EntityStateChanged => "entity_state_changed",
            Self::EntityEnded => "entity_ended",
            Self::ContentBecameVisible => "content_became_visible",
            Self::GroupOpened => "group_opened",
            Self::GroupHeadChanged => "group_head_changed",
            Self::GroupClosed => "group_closed",
            Self::BoundaryObserved => "boundary_observed",
            Self::UsageRecorded => "usage_recorded",
            Self::UsageAdjusted => "usage_adjusted",
            Self::BackgroundDeliveryRecorded => "background_delivery_recorded",
            Self::BusinessChanged => "business_changed",
            Self::LegacyObserved => "legacy_observed",
            Self::Other(s) => s,
        }
    }
}

impl From<String> for HistoryEventKindV25 {
    fn from(value: String) -> Self {
        match value.as_str() {
            "run_started" => Self::RunStarted,
            "run_ended" => Self::RunEnded,
            "turn_started" => Self::TurnStarted,
            "turn_changed" => Self::TurnChanged,
            "turn_ended" => Self::TurnEnded,
            "turn_rolled_back" => Self::TurnRolledBack,
            "source_started" => Self::SourceStarted,
            "source_ended" => Self::SourceEnded,
            "input_accepted" => Self::InputAccepted,
            "input_consumed" => Self::InputConsumed,
            "input_discarded" => Self::InputDiscarded,
            "entity_started" => Self::EntityStarted,
            "entity_state_changed" => Self::EntityStateChanged,
            "entity_ended" => Self::EntityEnded,
            "content_became_visible" => Self::ContentBecameVisible,
            "group_opened" => Self::GroupOpened,
            "group_head_changed" => Self::GroupHeadChanged,
            "group_closed" => Self::GroupClosed,
            "boundary_observed" => Self::BoundaryObserved,
            "usage_recorded" => Self::UsageRecorded,
            "usage_adjusted" => Self::UsageAdjusted,
            "background_delivery_recorded" => Self::BackgroundDeliveryRecorded,
            "business_changed" => Self::BusinessChanged,
            "legacy_observed" => Self::LegacyObserved,
            _ => Self::Other(value),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(in crate::history) enum HistoryObservationV25 {
    Original,
    Boundary { captured_at: Option<i64> },
    UnavailableLegacy { captured_at: Option<i64> },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::history) struct HistoryWorkHeadV25 {
    pub group_id: String,
    pub run_id: Option<String>,
    pub started_at: Option<i64>,
    pub boundary_at: Option<i64>,
    pub closed: bool,
    pub member_count: u64,
    pub unfinished_count: u64,
    pub execution_present: bool,
    pub summary: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::history) struct HistoryEntityHeadV25 {
    pub entity_id: String,
    pub run_id: Option<String>,
    pub attempt_id: Option<String>,
    pub source: HistorySource,
    pub kind: HistoryEntityKind,
    pub delivery: HistoryDelivery,
    pub state: HistoryEntityState,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub text_channel: Option<crate::ThreadTextChannel>,
    pub tool: Option<super::super::HistoryToolIdentity>,
    pub wait: Option<HistoryWaitHead>,
    pub content_present: Option<bool>,
    pub single_visibility: Option<HistorySingleVisibility>,
    pub observation: HistoryObservationV25,
    pub presentation_contract: Option<String>,
    pub detail_event_id: Option<String>,
    pub input_manifest_event_id: Option<String>,
    pub body_manifest_event_id: Option<String>,
}

impl HistoryEntityHeadV25 {
    pub fn from_atom(atom: &crate::ChatAtom, run: Option<String>) -> Result<Self> {
        let state = match &atom.lifecycle {
            crate::ChatAtomLifecycle::Active { status, .. } => {
                HistoryEntityState::KnownActive { status: *status }
            }
            crate::ChatAtomLifecycle::Terminal { outcome, .. } => {
                HistoryEntityState::KnownTerminal { outcome: *outcome }
            }
        };
        let to_ms = |secs: Option<i64>| -> Result<Option<i64>> {
            secs.map(super::super::milliseconds_from_seconds)
                .transpose()
        };
        Ok(Self {
            entity_id: atom.id.clone(),
            run_id: run,
            attempt_id: atom.attempt_id.clone(),
            source: atom.source.clone(),
            kind: atom.kind,
            delivery: atom.delivery,
            state,
            started_at: to_ms(atom.started_at)?,
            finished_at: to_ms(atom.finished_at)?,
            text_channel: atom.text_channel,
            tool: atom.tool.clone(),
            wait: atom
                .wait
                .clone()
                .map(|presentation| HistoryWaitHead::Inline { presentation }),
            content_present: atom.content_present,
            single_visibility: None,
            observation: HistoryObservationV25::Original,
            presentation_contract: None,
            detail_event_id: None,
            input_manifest_event_id: None,
            body_manifest_event_id: None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub(in crate::history) enum HistoryRowHeadV25 {
    Work(HistoryWorkHeadV25),
    Single(HistoryEntityHeadV25),
    Member(HistoryEntityHeadV25),
    Turn(HistoryTurnHead),
    Source(HistorySourceHead),
    Cost(HistoryCostHead),
    Accounting(HistoryAccountingHead),
}

impl HistoryRowHeadV25 {
    pub fn scope(&self) -> &'static str {
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

#[derive(Debug, Clone, PartialEq)]
pub(in crate::history) struct HistoryEventHeaderV25 {
    pub seq: u64,
    pub event_id: String,
    pub kind: HistoryEventKindV25,
    pub run_id: Option<String>,
    pub attempt_id: Option<String>,
    pub entity_id: Option<String>,
    pub turn_id: Option<String>,
    pub source: Option<HistorySource>,
    pub call_id: Option<String>,
    pub message_id: Option<String>,
    pub group_id: Option<String>,
    pub row_key: Option<String>,
    pub original: Option<HistoryOriginalInfo>,
    pub occurred_at: Option<i64>,
    pub recorded_at: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub(in crate::history) struct HistoryEventV25 {
    pub header: HistoryEventHeaderV25,
    pub head: Option<HistoryRowHeadV25>,
    pub is_anchor: bool,
    pub payload_body_id: Option<String>,
    pub bodies: Vec<HistoryBody>,
}

impl HistoryEventV25 {
    pub fn new(event_id: impl Into<String>, kind: HistoryEventKindV25, recorded_at: i64) -> Self {
        Self {
            header: HistoryEventHeaderV25 {
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

pub(in crate::history) async fn insert_v25_event(
    db: &impl ConnectionTrait,
    event: &HistoryEventV25,
) -> Result<()> {
    let (source_kind, source_id) = match &event.header.source {
        Some(source) => {
            let kind = match source {
                HistorySource::ForegroundTurn { .. } => "foreground_turn",
                HistorySource::Input { .. } => "input",
                HistorySource::InboxMessage { .. } => "inbox_message",
                HistorySource::BackgroundResult { .. } => "background_result",
                HistorySource::Operation { .. } => "operation",
                HistorySource::Receipt { .. } => "receipt",
            };
            let id = source_key(source)?;
            (Some(kind.to_owned()), Some(id))
        }
        None => (None, None),
    };
    let (query_class, parent_id, original_kind, tool_name) = match &event.header.original {
        Some(original) => {
            let kind = match serde_json::to_value(original.original_kind)? {
                serde_json::Value::String(text) => text,
                _ => {
                    return Err(HistoryError::InvalidEvent(
                        "original kind did not serialize as string".into(),
                    ));
                }
            };
            (
                Some(original.query_class.clone()),
                original.parent_id.clone(),
                Some(kind),
                original.tool_name.clone(),
            )
        }
        None => (None, None, None, None),
    };
    let (row_scope, head_json) = match &event.head {
        Some(head) => (
            Some(head.scope().to_owned()),
            Some(serde_json::to_string(head)?),
        ),
        None => (None, None),
    };
    db.execute_raw(statement(
        "INSERT INTO history_events(\
            seq,event_id,kind,run_id,attempt_id,entity_id,turn_id,source_kind,source_id,\
            call_id,message_id,query_class,parent_id,original_kind,tool_name,group_id,\
            row_scope,row_key,is_anchor,occurred_at,recorded_at,head_json,payload_body_id\
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        vec![
            number(event.header.seq)?.into(),
            event.header.event_id.clone().into(),
            event.header.kind.as_str().to_owned().into(),
            event.header.run_id.clone().into(),
            event.header.attempt_id.clone().into(),
            event.header.entity_id.clone().into(),
            event.header.turn_id.clone().into(),
            source_kind.into(),
            source_id.into(),
            event.header.call_id.clone().into(),
            event.header.message_id.clone().into(),
            query_class.into(),
            parent_id.into(),
            original_kind.into(),
            tool_name.into(),
            event.header.group_id.clone().into(),
            row_scope.into(),
            event.header.row_key.clone().into(),
            i64::from(event.is_anchor).into(),
            event.header.occurred_at.into(),
            event.header.recorded_at.into(),
            head_json.into(),
            event.payload_body_id.clone().into(),
        ],
    ))
    .await?;
    for (ordinal, body) in event.bodies.iter().enumerate() {
        insert_v25_body(db, &event.header.event_id, ordinal as u64, body).await?;
    }
    Ok(())
}

pub(in crate::history) async fn insert_v25_body(
    db: &impl ConnectionTrait,
    owner_event_id: &str,
    ordinal: u64,
    body: &HistoryBody,
) -> Result<()> {
    let digest = Sha256::digest(&body.bytes).to_vec();
    db.execute_raw(statement(
        "INSERT INTO history_bodies(body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest) \
         VALUES(?,?,?,?,?,?,?,?)",
        vec![
            body.body_id.clone().into(),
            owner_event_id.to_owned().into(),
            number(ordinal)?.into(),
            body.body_key.clone().into(),
            body.role.as_str().to_owned().into(),
            number(body.bytes.len() as u64)?.into(),
            body.media_type.clone().into(),
            digest.into(),
        ],
    ))
    .await?;
    for (chunk_no, chunk) in body
        .bytes
        .chunks(super::super::BODY_CHUNK_BYTES)
        .enumerate()
    {
        db.execute_raw(statement(
            "INSERT INTO history_body_chunks(body_id,chunk_no,data) VALUES(?,?,?)",
            vec![
                body.body_id.clone().into(),
                number(chunk_no as u64)?.into(),
                chunk.to_vec().into(),
            ],
        ))
        .await?;
    }
    Ok(())
}

pub(in crate::history) fn validate_v25_event(event: &HistoryEventV25) -> Result<()> {
    if event.header.event_id.is_empty() {
        return Err(HistoryError::InvalidEvent(
            "v25 import event_id must not be empty".into(),
        ));
    }
    if event.header.seq != 0 {
        return Err(HistoryError::InvalidEvent(
            "caller must not supply event sequence".into(),
        ));
    }
    if let Some(head) = &event.head
        && event.header.row_key.is_none()
    {
        let _ = head.scope();
        return Err(HistoryError::InvalidEvent(
            "v25 row head requires row_key".into(),
        ));
    }
    if event.is_anchor && event.header.row_key.is_none() {
        return Err(HistoryError::InvalidEvent(
            "v25 anchor requires row_key".into(),
        ));
    }
    Ok(())
}
