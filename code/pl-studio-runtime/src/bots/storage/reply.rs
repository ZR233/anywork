//! Ephemeral host proof for auxiliary inbound replies. No model arguments,
//! persistence schema, or alternative sender: the existing ledger owns sends.
use super::{
    BotStateStore, INBOUND_CLAIM_TTL_SECONDS, inbound_identity, statement, storage, strict_text,
    strict_watermark,
};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::send::SendSource;
use sea_orm::ConnectionTrait;

#[derive(Debug, Clone, Copy)]
pub(in crate::bots) enum ReplyBinding {
    /// An explicit no-row expectation, never a wildcard for the current binding.
    Absent,
    Creating,
    Bound,
}

#[derive(Debug, Clone)]
pub(in crate::bots) struct InboundReply {
    pub source: SendSource,
    pub worker_id: String,
    pub watch_input: String,
    pub admitted_binding_revision: u64,
    pub binding: ReplyBinding,
}

impl InboundReply {
    pub(in crate::bots) fn freeze_bytes(&self, copies: usize) -> Result<usize, FeishuError> {
        let source = serde_json::to_vec(&self.source)
            .map_err(|_| crate::bots::occupancy::freeze_budget_error())?;
        crate::bots::occupancy::counted_extra_bytes(
            0,
            [
                (source.len(), copies),
                (self.worker_id.len(), copies),
                (self.watch_input.len(), copies),
            ],
        )
    }
}

impl BotStateStore {
    /// Read-only check for an existing receipt. New send claims/stage intents
    /// call the same predicate inside their actual write transaction instead.
    pub(in crate::bots) async fn verify_reply(
        &self,
        reply: &InboundReply,
    ) -> Result<(), FeishuError> {
        check(self.db().await?, reply).await
    }
}

pub(super) async fn check<C: ConnectionTrait>(
    db: &C,
    reply: &InboundReply,
) -> Result<(), FeishuError> {
    let s = &reply.source;
    let original = format!("bot:{}:{}:{}", s.bot_id, s.chat_id, s.message_id);
    if reply.worker_id.is_empty() || reply.watch_input.is_empty() || s.original_input_id != original
    {
        return Err(denied());
    }
    let claim = db.query_one_raw(statement(
        "SELECT 1 AS held FROM inbound_work WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
         AND app_id=? AND project_id=? AND open_id=? AND chat_kind=? AND creation_id=? AND binding_revision=?
         AND status='claimed' AND claimed_by=? AND claimed_at>?
         AND (watch_input=? OR (watch_input='' AND ?=?))",
        vec![inbound_identity(&s.bot_id,&s.chat_id,&s.message_id).into(),s.bot_id.clone().into(),s.chat_id.clone().into(),s.message_id.clone().into(),
             s.app_id.clone().into(),s.project_id.clone().into(),s.open_id.clone().into(),s.chat_kind.clone().into(),s.creation_id.clone().into(),
             i64::try_from(reply.admitted_binding_revision).map_err(|_| denied())?.into(),reply.worker_id.clone().into(),
             crate::studio::unix_seconds().saturating_sub(INBOUND_CLAIM_TTL_SECONDS).into(),reply.watch_input.clone().into(),reply.watch_input.clone().into(),original.into()],
    )).await.map_err(storage)?;
    if claim.is_none() {
        return Err(denied());
    }
    let row = db.query_one_raw(statement(
        "SELECT chat_id,thread_id,status,creation_id,project_id,revision,generation FROM thread_bindings WHERE chat_id=?",
        vec![s.chat_id.clone().into()],
    )).await.map_err(storage)?;
    let Some(row) = row else {
        return if matches!(reply.binding, ReplyBinding::Absent)
            && s.creation_id.is_empty()
            && s.thread_id.is_empty()
            && s.binding_revision == 0
            && reply.admitted_binding_revision == 0
        {
            Ok(())
        } else {
            Err(denied())
        };
    };
    // Bad columns/unknown state are not absence. Decode the existing row even
    // when the caller expected no row, preserving corruption versus revocation.
    let chat = strict_text(&row, "chat_id")?;
    let thread = strict_text(&row, "thread_id")?;
    let status = strict_text(&row, "status")?;
    let creation = strict_text(&row, "creation_id")?;
    let project = strict_text(&row, "project_id")?;
    let revision = strict_watermark(&row, "revision")?;
    let _generation = strict_watermark(&row, "generation")?;
    let state_matches = match reply.binding {
        ReplyBinding::Absent => false,
        ReplyBinding::Creating => {
            status == "creating" && thread.is_empty() && s.thread_id.is_empty()
        }
        ReplyBinding::Bound => status == "bound" && !thread.is_empty() && thread == s.thread_id,
    };
    if !state_matches
        || chat != s.chat_id
        || creation.is_empty()
        || creation != s.creation_id
        || project != s.project_id
        || revision != s.binding_revision
    {
        return Err(denied());
    }
    Ok(())
}

pub(in crate::bots) fn denied() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Permission,
        "original inbound reply claim or binding is no longer valid",
        false,
        None,
    )
}
