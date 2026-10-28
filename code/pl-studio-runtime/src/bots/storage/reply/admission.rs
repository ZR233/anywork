//! Fresh-only freezing participates in the caller's original inbound transaction.

use super::*;
use crate::bots::occupancy::{OccupancyBudget, counted_extra_bytes};
use crate::bots::send::{inbound_notice_freeze_bytes, plan_inbound_notice};
use crate::bots::storage::{
    FrozenInbound, MessageStage, audience, corrupt_send, encode_segment_facts,
    encode_send_identity, encode_send_source, inbound_identity_bytes,
};

pub(in crate::bots::storage) enum FreshNotice {
    NotApplicable,
    Frozen(SendRecord),
    NeedsAttention(InboundNoticeUnavailable),
}

pub(in crate::bots::storage) async fn freeze_admission_in<C: ConnectionTrait>(
    db: &C,
    inbound: &FrozenInbound,
    budget: &mut OccupancyBudget,
) -> Result<FreshNotice, FeishuError> {
    if !crate::bots::inbound::unsupported_only(&inbound.text, &inbound.attachments) {
        return Ok(FreshNotice::NotApplicable);
    }
    let unavailable = || FreshNotice::NeedsAttention(InboundNoticeUnavailable::OriginalScopeClosed);
    let original = format!(
        "bot:{}:{}:{}",
        inbound.bot_id, inbound.chat_id, inbound.message_id
    );
    if (!inbound.watch_input.is_empty() && inbound.watch_input != original)
        || inbound.app_id.is_empty()
        || inbound.project_id.is_empty()
        || !matches!(inbound.chat_kind.as_str(), "group" | "direct")
        || (inbound.chat_kind == "direct" && inbound.open_id.is_empty())
    {
        return Ok(unavailable());
    }
    let route = authority::route(db, &inbound.chat_id).await?;
    let binding = match &route {
        None if inbound.creation_id.is_empty() && inbound.binding_revision == 0 => {
            ReplyBinding::Absent
        }
        Some(route)
            if route.project_id == inbound.project_id
                && route.creation_id == inbound.creation_id
                && !route.creation_id.is_empty()
                && route.revision == inbound.binding_revision
                && route.revision > 0 =>
        {
            match route.status.as_str() {
                "creating" if route.thread_id.is_empty() => ReplyBinding::Creating,
                "bound" if !route.thread_id.is_empty() => ReplyBinding::Bound,
                _ => return Ok(unavailable()),
            }
        }
        _ => return Ok(unavailable()),
    };
    let head = audience::head(db, &inbound.chat_id).await?;
    let authorization = match (binding, head) {
        (ReplyBinding::Absent | ReplyBinding::Creating, None) => NoticeAuthorization::NoHead {},
        (ReplyBinding::Bound, Some(head)) => {
            let Some(start) = head.start else {
                return Ok(unavailable());
            };
            NoticeAuthorization::Bound {
                start: Box::new(start),
            }
        }
        _ => return Ok(unavailable()),
    };
    let identity = InboundNoticeIdentity {
        version: 1,
        source: SendSource {
            bot_id: inbound.bot_id.clone(),
            chat_id: inbound.chat_id.clone(),
            message_id: inbound.message_id.clone(),
            app_id: inbound.app_id.clone(),
            project_id: inbound.project_id.clone(),
            thread_id: route.map(|route| route.thread_id).unwrap_or_default(),
            input_id: original.clone(),
            original_input_id: original,
            open_id: inbound.open_id.clone(),
            chat_kind: inbound.chat_kind.clone(),
            creation_id: inbound.creation_id.clone(),
            binding_revision: inbound.binding_revision,
        },
        binding,
        authorization,
    };
    if matches!(
        authority::scope(db, &identity).await?,
        authority::Scope::Closed
    ) {
        return Ok(unavailable());
    }
    let operation = crate::bots::send::inbound_notice_operation_id(
        &inbound.bot_id,
        &inbound.chat_id,
        &inbound.message_id,
    )?;
    let plan = plan_inbound_notice(&identity)?;
    let record = crate::bots::send_service::into_record(
        operation,
        inbound.bot_id.clone(),
        inbound.chat_id.clone(),
        plan,
    );
    // The send owner's checked peak includes owned records, Saved identities and SQL copies.
    // These additional original-input/key/hash strings are local to the admission/work boundary.
    let bytes = counted_extra_bytes(
        inbound_notice_freeze_bytes(&record)?,
        [
            (
                inbound_identity_bytes(&inbound.bot_id, &inbound.chat_id, &inbound.message_id)?,
                2,
            ),
            (identity.source.input_id.len(), 1),
            (inbound.content_hash.len(), 1),
        ],
    )?;
    budget.reserve_more(bytes)?;
    Ok(FreshNotice::Frozen(record))
}

pub(in crate::bots::storage) async fn insert_frozen_notice_in<C: ConnectionTrait>(
    db: &C,
    record: &SendRecord,
) -> Result<(), FeishuError> {
    operation::identity(record)?;
    if operation::counter(record)? != 0 || operation::stage(record)? != MessageStage::NotStarted {
        return Err(corrupt_send());
    }
    db.execute_raw(statement(
        "INSERT INTO send_operations(operation_id,bot_id,chat_id,content_hash,status,
         platform_message_ids,segment_facts,updated_at,send_identity,send_source)
         VALUES(?,?,?,?,?,?,?,?,?,?)",
        vec![
            record.operation_id.clone().into(),
            record.bot_id.clone().into(),
            record.chat_id.clone().into(),
            record.content_hash.clone().into(),
            record.status.as_str().into(),
            record.platform_message_ids.join(",").into(),
            encode_segment_facts(&record.segments)?.into(),
            crate::studio::unix_seconds().into(),
            encode_send_identity(&record.identity)?.into(),
            encode_send_source(&record.source)?.into(),
        ],
    ))
    .await
    .map_err(storage)?;
    Ok(())
}
