//! Admission provenance, live claim and current scope are separate predicates.

use super::*;
use crate::bots::inbound::{InboundAttachment, unsupported_only};
use crate::bots::storage::{
    ClaimedWork, FrozenInbound, WorkKeys, audience, stored_i64, work_needs_recovery,
};
use pl_protocol::studio::BotAuthorizationPhase;
use sea_orm::QueryResult;

pub(super) enum Scope {
    Active(NoticeControl),
    Paused(BotAuthorizationRef),
    Closed,
}

pub(super) struct Route {
    pub status: String,
    pub thread_id: String,
    pub project_id: String,
    pub creation_id: String,
    pub revision: u64,
}

pub(super) async fn route<C: ConnectionTrait>(
    db: &C,
    chat: &str,
) -> Result<Option<Route>, FeishuError> {
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT chat_id,thread_id,status,project_id,creation_id,revision,generation
         FROM thread_bindings WHERE chat_id=?",
            vec![chat.into()],
        ))
        .await
        .map_err(storage)?
    else {
        return Ok(None);
    };
    let status = strict_text(&row, "status")?;
    if strict_text(&row, "chat_id")? != chat
        || !matches!(status.as_str(), "creating" | "bound" | "needs_attention")
    {
        return Err(work_needs_recovery());
    }
    strict_watermark(&row, "generation")?;
    Ok(Some(Route {
        status,
        thread_id: strict_text(&row, "thread_id")?,
        project_id: strict_text(&row, "project_id")?,
        creation_id: strict_text(&row, "creation_id")?,
        revision: strict_watermark(&row, "revision")?,
    }))
}

pub(super) async fn scope<C: ConnectionTrait>(
    db: &C,
    identity: &InboundNoticeIdentity,
) -> Result<Scope, FeishuError> {
    let s = &identity.source;
    let current = route(db, &s.chat_id).await?;
    let route_matches = match (identity.binding, &current) {
        (ReplyBinding::Absent, None) => true,
        (ReplyBinding::Creating, Some(route)) => {
            route.status == "creating"
                && route.thread_id.is_empty()
                && route.project_id == s.project_id
                && route.creation_id == s.creation_id
                && route.revision == s.binding_revision
        }
        (ReplyBinding::Bound, Some(route)) => {
            route.status == "bound"
                && route.thread_id == s.thread_id
                && route.project_id == s.project_id
                && route.creation_id == s.creation_id
                && route.revision == s.binding_revision
        }
        _ => false,
    };
    if !route_matches {
        return Ok(Scope::Closed);
    }
    let head = audience::head(db, &s.chat_id).await?;
    let NoticeAuthorization::Bound { start } = &identity.authorization else {
        return Ok(if head.is_none() {
            Scope::Active(NoticeControl::NoHead)
        } else {
            Scope::Closed
        });
    };
    let Some(head) = head else {
        return Ok(Scope::Closed);
    };
    if head.intent.authorization != start.intent.authorization
        || head.start.as_ref() != Some(start.as_ref())
        || head.intent.thread_id != s.thread_id
        || head.intent.binding_revision != s.binding_revision
        || head.app_id != s.app_id
        || head.project_id != s.project_id
        || head.creation_id != s.creation_id
    {
        return Ok(Scope::Closed);
    }
    let Some(origin) = audience::proven_origin(db, &s.thread_id, &s.bot_id).await? else {
        return Ok(Scope::Closed);
    };
    if origin.requires_upgrade
        || origin.chat_id != s.chat_id
        || origin.project_id != s.project_id
        || origin.creation_id != s.creation_id
        || origin.binding_revision != s.binding_revision
    {
        return Ok(Scope::Closed);
    }
    let target = match &origin.target {
        crate::bots::storage::target::TargetProof::Created { evidence } => &evidence.target,
        crate::bots::storage::target::TargetProof::Legacy { target } => target,
        crate::bots::storage::target::TargetProof::Unproven => return Ok(Scope::Closed),
    };
    let same_target = match target {
        crate::bots::storage::target::TargetKind::Group => s.chat_kind == "group",
        crate::bots::storage::target::TargetKind::Direct { open_id } => {
            s.chat_kind == "direct" && s.open_id == *open_id
        }
    };
    if !same_target {
        return Ok(Scope::Closed);
    }
    Ok(match head.phase {
        BotAuthorizationPhase::Active => Scope::Active(NoticeControl::Bound {
            reference: head.reference(),
        }),
        BotAuthorizationPhase::Paused => Scope::Paused(head.reference()),
        BotAuthorizationPhase::PendingStart | BotAuthorizationPhase::Closed => Scope::Closed,
    })
}

pub(super) fn keys(source: &SendSource) -> WorkKeys<'_> {
    WorkKeys {
        identity: inbound_identity(&source.bot_id, &source.chat_id, &source.message_id),
        bot_id: &source.bot_id,
        chat_id: &source.chat_id,
        message_id: &source.message_id,
    }
}

/// Decode original work/identity regardless of its *current* claim status; no wall-clock repair.
pub(super) async fn work<C: ConnectionTrait>(
    db: &C,
    identity: &InboundNoticeIdentity,
) -> Result<FrozenInbound, FeishuError> {
    let s = &identity.source;
    let keys = keys(s);
    let row = db
        .query_one_raw(statement(
            "SELECT * FROM inbound_work WHERE identity=?",
            vec![keys.identity.clone().into()],
        ))
        .await
        .map_err(storage)?
        .ok_or_else(work_needs_recovery)?;
    let work = decoded_work(&row)?;
    if strict_text(&row, "identity")? != keys.identity
        || !matches!(
            strict_text(&row, "status")?.as_str(),
            "pending" | "claimed" | "failed" | "completed" | "needs_attention"
        )
        || work.bot_id != s.bot_id
        || work.chat_id != s.chat_id
        || work.message_id != s.message_id
        || work.app_id != s.app_id
        || work.project_id != s.project_id
        || work.creation_id != s.creation_id
        || work.binding_revision != s.binding_revision
        || work.open_id != s.open_id
        || work.chat_kind != s.chat_kind
        || (!work.watch_input.is_empty() && work.watch_input != s.original_input_id)
        || !unsupported_only(&work.text, &work.attachments)
    {
        return Err(work_needs_recovery());
    }
    check_admission(db, &keys, &row, &work).await?;
    Ok(work)
}

pub(super) async fn original<C: ConnectionTrait>(
    db: &C,
    inbound: &FrozenInbound,
) -> Result<(), FeishuError> {
    let keys = WorkKeys {
        identity: inbound_identity(&inbound.bot_id, &inbound.chat_id, &inbound.message_id),
        bot_id: &inbound.bot_id,
        chat_id: &inbound.chat_id,
        message_id: &inbound.message_id,
    };
    let row = db
        .query_one_raw(statement(
            "SELECT * FROM inbound_work WHERE identity=?",
            vec![keys.identity.clone().into()],
        ))
        .await
        .map_err(storage)?
        .ok_or_else(work_needs_recovery)?;
    if decoded_work(&row)? != *inbound || strict_text(&row, "identity")? != keys.identity {
        return Err(work_needs_recovery());
    }
    check_admission(db, &keys, &row, inbound).await
}

async fn check_admission<C: ConnectionTrait>(
    db: &C,
    keys: &WorkKeys<'_>,
    row: &QueryResult,
    work: &FrozenInbound,
) -> Result<(), FeishuError> {
    if !matches!(
        strict_text(row, "status")?.as_str(),
        "pending" | "claimed" | "failed" | "completed" | "needs_attention"
    ) {
        return Err(work_needs_recovery());
    }
    let attempt_count = stored_i64(row, "attempt_count")?;
    if attempt_count < 0 {
        return Err(work_needs_recovery());
    }
    let admitted = ClaimedWork {
        attempt_count,
        content_hash: work.content_hash.clone(),
        project_id: work.project_id.clone(),
        creation_id: work.creation_id.clone(),
        binding_revision: work.binding_revision,
    };
    BotStateStore::admitted_at(db, keys, &admitted).await?;
    Ok(())
}

fn decoded_work(row: &QueryResult) -> Result<FrozenInbound, FeishuError> {
    Ok(FrozenInbound {
        bot_id: strict_text(row, "bot_id")?,
        chat_id: strict_text(row, "chat_id")?,
        message_id: strict_text(row, "message_id")?,
        content_hash: strict_text(row, "content_hash")?,
        text: strict_text(row, "text")?,
        attachments: serde_json::from_str::<Vec<InboundAttachment>>(&strict_text(
            row,
            "attachments",
        )?)
        .map_err(|_| work_needs_recovery())?,
        open_id: strict_text(row, "open_id")?,
        chat_kind: strict_text(row, "chat_kind")?,
        app_id: strict_text(row, "app_id")?,
        project_id: strict_text(row, "project_id")?,
        creation_id: strict_text(row, "creation_id")?,
        binding_revision: strict_watermark(row, "binding_revision")?,
        watch_input: strict_text(row, "watch_input")?,
    })
}

pub(super) async fn live<C: ConnectionTrait>(
    db: &C,
    identity: &InboundNoticeIdentity,
    worker: &str,
) -> Result<bool, FeishuError> {
    if worker.is_empty() {
        return Ok(false);
    }
    Ok(BotStateStore::claimed_work(
        db,
        &keys(&identity.source),
        worker,
        crate::studio::unix_seconds().saturating_sub(INBOUND_CLAIM_TTL_SECONDS),
    )
    .await?
    .is_some())
}
