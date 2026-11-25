//! Canonical History event bodies for the facts owned by one prepared effect.

use anyhow::Result;

use crate::history::{
    HistoryBodyRole, HistoryBusinessRowScope, HistoryEvent, HistoryEventKind, HistoryTimelineRole,
    HistoryTurnHead, PendingBody,
    body::{BusinessEnvelope, BusinessFactEnvelope},
    pack_bodies,
};

pub(super) fn millis(at: i64) -> Result<i64> {
    crate::history::milliseconds_from_seconds(at)
        .map_err(|error| anyhow::anyhow!(error.to_string()))
}

pub(super) fn turn_event(
    event_id: String,
    turn: &HistoryTurnHead,
    detail: Option<&crate::Turn>,
    recorded_at: i64,
    anchor: bool,
    database_id: &str,
) -> Result<HistoryEvent> {
    let terminal = matches!(
        turn.state,
        crate::history::HistoryTurnState::Completed
            | crate::history::HistoryTurnState::Cancelled
            | crate::history::HistoryTurnState::Failed
            | crate::history::HistoryTurnState::BudgetLimited
    );
    let mut event = HistoryEvent::new(
        event_id,
        if terminal {
            HistoryEventKind::TurnEnded
        } else if anchor && turn.started_at.is_some() {
            HistoryEventKind::TurnStarted
        } else {
            HistoryEventKind::TurnChanged
        },
        HistoryTimelineRole::Hidden,
        recorded_at,
    );
    event.run_id = turn.run_id.clone();
    event.turn_id = Some(turn.turn_id.clone());
    event.row_scope = Some(HistoryBusinessRowScope::Turn);
    event.row_key = Some(format!("turn:{}", turn.turn_id));
    event.occurred_at = if terminal {
        turn.finished_at
    } else {
        turn.started_at
    };
    let mut head = turn.clone();
    let mut manifest = Vec::new();
    if let Some(detail) = detail {
        head.detail_event_id = Some(event.event_id.clone());
        manifest = pack_bodies(
            &mut event,
            vec![PendingBody::new(
                "turn_detail",
                HistoryBodyRole::CanonicalPayload,
                Some("application/json".into()),
                serde_json::to_vec(detail)?,
            )],
            database_id,
        )?;
    }
    event.payload_schema = "anywork.turn/1".into();
    event.payload_json = serde_json::to_string(&BusinessEnvelope {
        head,
        bodies: manifest,
    })?;
    event.is_anchor = anchor;
    Ok(event)
}

#[derive(Clone, Copy)]
pub(super) struct BatchWriteContext<'a> {
    pub(super) recorded_at: i64,
    pub(super) anchor: bool,
    pub(super) database_id: &'a str,
}

pub(super) fn source_event(
    source: &crate::history::HistorySourceHead,
    continuation_payload: Option<Vec<u8>>,
    entity_override: Option<&str>,
    run_override: Option<String>,
    turn_override: Option<String>,
    context: BatchWriteContext<'_>,
) -> Result<HistoryEvent> {
    let BatchWriteContext {
        recorded_at,
        anchor,
        database_id,
    } = context;
    let identity = serde_json::to_string(&source.source)?;
    let ended = matches!(&source.lifecycle, crate::ChatSourceLifecycle::Ended { .. });
    let mut event = HistoryEvent::new(
        format!("source:{identity}:{ended}:{recorded_at}"),
        if ended {
            HistoryEventKind::SourceEnded
        } else {
            HistoryEventKind::SourceStarted
        },
        HistoryTimelineRole::Hidden,
        recorded_at,
    );
    event.source = Some(source.source.clone());
    event.row_scope = Some(HistoryBusinessRowScope::Source);
    event.row_key = Some(format!("source:{identity}"));
    event.occurred_at = source.started_at.or(source.ended_at);
    event.entity_id = entity_override.map(str::to_owned);
    event.run_id = run_override;
    event.turn_id = turn_override;
    let manifest = if let Some(bytes) = continuation_payload {
        pack_bodies(
            &mut event,
            vec![PendingBody::new(
                "payload",
                HistoryBodyRole::CanonicalPayload,
                Some("application/json".into()),
                bytes,
            )],
            database_id,
        )?
    } else {
        Vec::new()
    };
    event.payload_schema = "anywork.source/1".into();
    event.payload_json = serde_json::to_string(&BusinessEnvelope {
        head: source.clone(),
        bodies: manifest,
    })?;
    event.is_anchor = anchor;
    Ok(event)
}

pub(super) fn run_event(run: &str, recorded_at: i64) -> Result<HistoryEvent> {
    let mut event = HistoryEvent::new(
        format!("run:{run}:started"),
        HistoryEventKind::RunStarted,
        HistoryTimelineRole::Hidden,
        recorded_at,
    );
    event.run_id = Some(run.to_owned());
    event.payload_schema = "anywork.business/1".into();
    event.payload_json = serde_json::to_string(&BusinessFactEnvelope {
        fact_type: "run_started".into(),
        data: None,
        bodies: Vec::new(),
    })?;
    Ok(event)
}

pub(super) fn delivery_event(
    thread_id: &str,
    prefix: &str,
    message_id: &str,
    payload: String,
    run: pl_core::thread::current::RuntimeEpoch,
    context: BatchWriteContext<'_>,
) -> Result<HistoryEvent> {
    let BatchWriteContext {
        recorded_at,
        anchor,
        database_id,
    } = context;
    let kind = match prefix {
        "parent_report" => HistoryEventKind::ParentReportRecorded,
        _ => HistoryEventKind::ReviewDeliveryRecorded,
    };
    let mut event = HistoryEvent::new(
        format!("{prefix}:{message_id}"),
        kind,
        HistoryTimelineRole::Hidden,
        recorded_at,
    );
    event.run_id = Some(run.to_string());
    event.message_id = Some(message_id.to_owned());
    event.source = Some(crate::studio::history_delivery::source(thread_id, prefix));
    let payload = pl_core::context::OpaquePayload::new(
        match prefix {
            "parent_report" => "pl.studio.parent-report",
            _ => "pl.studio.review-delivery",
        },
        1,
        payload,
    )?;
    let manifest = pack_bodies(
        &mut event,
        vec![PendingBody::new(
            "business_fact",
            HistoryBodyRole::CanonicalPayload,
            Some("application/json".into()),
            serde_json::to_vec(&payload)?,
        )],
        database_id,
    )?;
    event.payload_schema = "anywork.business/1".into();
    event.payload_json = serde_json::to_string(&BusinessFactEnvelope {
        fact_type: prefix.to_owned(),
        data: None,
        bodies: manifest,
    })?;
    event.is_anchor = anchor;
    Ok(event)
}
