//! 纯本地呈现推进：同投影修订关联、有限回复的新证明及无网络卡片的明确终局。
//! 每次写入都在原 claim/授权围栏与实体 CAS 的同一事务，不制造 HTTP 意图或回执。

use super::claim::{WriteFence, fence_write};
use super::records::{read_entity, sync_pending, write_entity};
use super::store::storage;
use super::*;
use crate::bots::storage::BotStateStore;
use crate::studio::unix_seconds;
use sea_orm::{ConnectionTrait, TransactionTrait};

impl BotStateStore {
    /// 把当前 canonical 修订关联到已接受的相同有界文本；原 HTTP 材料与确认快照不变。
    pub(in crate::bots) async fn confirm_unchanged_delivery_text(
        &self,
        token: &DeliveryClaimToken,
        entity_key: &DeliveryEntityKey,
        expected_ledger_version: u64,
    ) -> Result<SettlementOutcome, FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let scope = match fence_write(&tx, token).await? {
            WriteFence::Permitted(scope) => scope,
            _ => return Err(fenced()),
        };
        if !scope.key.is_frontend() {
            return Err(conflict());
        }
        let entity = read_entity(&tx, &token.scope, entity_key)
            .await?
            .ok_or_else(conflict)?;
        if entity.ledger_version != expected_ledger_version {
            return Err(conflict());
        }
        let target = unchanged_text_presentation(&entity)?;
        if entity.state.projected == target && entity.state.accepted == target {
            return Ok(SettlementOutcome::AlreadySettled);
        }
        let mut state = entity.state.clone();
        state.projected = target.clone();
        state.accepted = target;
        write_local_state(&tx, &entity, state).await?;
        tx.commit().await.map_err(storage)?;
        Ok(SettlementOutcome::Applied)
    }

    /// 新的 canonical 呈现只挂在原有限回复实体；续接 Turn 不改原实体身份或 HTTP 事实。
    pub(in crate::bots) async fn merge_legacy_delivery_presentation(
        &self,
        token: &DeliveryClaimToken,
        entity_key: &DeliveryEntityKey,
        expected_ledger_version: u64,
        candidate: &DeliveryLegacyCandidate,
    ) -> Result<MergeOutcome, FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let scope = match fence_write(&tx, token).await? {
            WriteFence::Permitted(scope) => scope,
            _ => return Ok(MergeOutcome::Fenced),
        };
        if scope.key.is_frontend() {
            return Ok(MergeOutcome::NotCanonical);
        }
        let entity = read_entity(&tx, &token.scope, entity_key)
            .await?
            .ok_or_else(conflict)?;
        require_legacy_entity(&scope, &entity, expected_ledger_version)?;
        let presentation = DeliveryLegacyPresentation {
            turn_id: candidate.turn_id.clone(),
            body: candidate.body.clone(),
            integrity: candidate.integrity,
            saved: candidate.saved,
            request_bytes: candidate.request_bytes,
        };
        validate_legacy_presentation(&presentation)?;
        if super::ownership::turn_owner(
            &tx,
            &DeliveryTurnIdentity {
                thread_id: scope.thread_id.clone(),
                turn_id: candidate.turn_id.clone(),
                input_chain: candidate.input_chain.clone(),
            },
        )
        .await?
            != (DeliveryTurnOwner::LegacyFinal {
                scope: token.scope.clone(),
            })
        {
            return Ok(MergeOutcome::NotCanonical);
        }
        let mut state = entity.state.clone();
        let DeliveryContent::Legacy {
            presentation: current,
            ..
        } = &mut state.content
        else {
            return Err(conflict());
        };
        if current.as_ref() == Some(&presentation) {
            return Ok(MergeOutcome::Unchanged { item_revision: 0 });
        }
        *current = Some(presentation);
        write_local_state(&tx, &entity, state).await?;
        tx.commit().await.map_err(storage)?;
        Ok(MergeOutcome::Applied { item_revision: 0 })
    }

    /// O 已证明原义务明确结束时，只终结从未出现网络材料的有限回复，不发送空卡。
    pub(in crate::bots) async fn settle_legacy_without_card(
        &self,
        token: &DeliveryClaimToken,
        entity_key: &DeliveryEntityKey,
        expected_ledger_version: u64,
        reason: LegacyLocalCompletion,
    ) -> Result<SettlementOutcome, FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let scope = match fence_write(&tx, token).await? {
            WriteFence::Permitted(scope) => scope,
            _ => return Err(fenced()),
        };
        let entity = read_entity(&tx, &token.scope, entity_key)
            .await?
            .ok_or_else(conflict)?;
        require_legacy_entity(&scope, &entity, expected_ledger_version)?;
        if entity.state.has_legacy_network_history() || entity.state.halt.is_some() {
            return Err(conflict());
        }
        if let Some(existing) = entity.state.card.legacy_local_completion {
            return if existing == reason && entity.state.card.lifecycle == Some(reason.lifecycle())
            {
                Ok(SettlementOutcome::AlreadySettled)
            } else {
                Err(conflict())
            };
        }
        if !matches!(
            entity.state.card.lifecycle,
            None | Some(CardLifecycle::Empty | CardLifecycle::Paused)
        ) {
            return Err(conflict());
        }
        let mut state = entity.state.clone();
        state.card.lifecycle = Some(reason.lifecycle());
        state.card.legacy_local_completion = Some(reason);
        write_local_state(&tx, &entity, state).await?;
        tx.commit().await.map_err(storage)?;
        Ok(SettlementOutcome::Applied)
    }
}

fn require_legacy_entity(
    scope: &DeliveryScope,
    entity: &DeliveryEntity,
    expected_ledger_version: u64,
) -> Result<(), FeishuError> {
    if entity.ledger_version != expected_ledger_version
        || entity.removed
        || !super::legacy::entity_matches(scope, &entity.entity)
        || !matches!(&scope.origin, DeliveryScopeOrigin::LegacyFinal { legacy } if legacy.resumable)
        || !matches!(entity.state.content, DeliveryContent::Legacy { .. })
    {
        return Err(conflict());
    }
    Ok(())
}

fn unchanged_text_presentation(
    entity: &DeliveryEntity,
) -> Result<BotItemPresentation, FeishuError> {
    let state = &entity.state;
    let DeliveryContent::Text { text } = &state.content else {
        return Err(conflict());
    };
    let card = &state.card;
    if entity.removed
        || state.in_flight.is_some()
        || state.halt.is_some()
        || state.file_operation.is_some()
        || card.recovery.is_some()
        || card.lifecycle == Some(CardLifecycle::NeedsAttention)
        || card.sequence != card.confirmed_sequence
        || state.projected != state.accepted
        || card.confirmed_text != text.body
        || card.confirmed_content_hash != super::super::card::hash(card.confirmed_text.as_bytes())
    {
        return Err(conflict());
    }
    let card_id = card
        .card_id
        .as_deref()
        .filter(|id| !id.is_empty())
        .ok_or_else(conflict)?;
    let message_id = card
        .platform_message_id
        .as_deref()
        .filter(|id| !id.is_empty())
        .ok_or_else(conflict)?;
    let Some(BotItemPresentation::Text {
        revision: confirmed_revision,
        integrity,
        saved: confirmed_saved,
    }) = &card.confirmed_presentation
    else {
        return Err(conflict());
    };
    let BotItemPresentation::Text {
        revision: accepted_revision,
        integrity: accepted_integrity,
        saved,
    } = &state.accepted
    else {
        return Err(conflict());
    };
    if *confirmed_revision == 0
        || text.integrity != *integrity
        || text.integrity != *accepted_integrity
        || accepted_revision < confirmed_revision
        || *accepted_revision > text.revision
    {
        return Err(conflict());
    }
    let settled = state.settled.as_ref().ok_or_else(conflict)?;
    let accepted = match &settled.result {
        DeliveryResult::Sent {
            card_id: id,
            message_id: message,
        } => id == card_id && message == message_id,
        DeliveryResult::ContentAccepted { card_id: id }
        | DeliveryResult::SettingsAccepted { card_id: id, .. } => id == card_id,
        DeliveryResult::NotStarted
        | DeliveryResult::Created { .. }
        | DeliveryResult::Rejected { .. }
        | DeliveryResult::Unknown { .. } => false,
    };
    if !accepted
        || settled.intent.sequence != card.confirmed_sequence
        || settled.intent.content_revision != *confirmed_revision
        || settled.intent.integrity != *integrity
        || settled.intent.saved != *confirmed_saved
    {
        return Err(conflict());
    }
    Ok(BotItemPresentation::Text {
        revision: text.revision,
        integrity: text.integrity,
        saved: text.saved || *accepted_revision == text.revision && *saved,
    })
}

async fn write_local_state<C: ConnectionTrait>(
    db: &C,
    entity: &DeliveryEntity,
    state: DeliveryEntityState,
) -> Result<(), FeishuError> {
    let mut next = entity.clone();
    next.state = state;
    next.ledger_version = entity
        .ledger_version
        .checked_add(1)
        .ok_or_else(unreadable)?;
    next.updated_at = unix_seconds();
    write_entity(db, &next, Some(entity.ledger_version)).await?;
    sync_pending(db, &next).await
}
