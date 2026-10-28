//! 规范合并、卡片 Intent/结算与文件 fence：写入都在同一事务内核对 token、作用域与版本。
//!
//! 结算不要求认领（撤权/失租后仍保存已启动结果），但绝不覆盖后继操作；Unknown 不重放。

use super::super::{BotStateStore, statement, stored_i64, strict_text};
use super::claim::{ClaimFence, WriteFence, fence_claim, fence_write};
use super::records::{read_entity, sync_pending, write_entity};
use super::store::{halted, storage};
use super::*;
use crate::studio::unix_seconds;
use sea_orm::{ConnectionTrait, TransactionTrait};

/// 规范合并结果：旧 revision 不覆盖新 revision，同 revision 异内容拒绝。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) enum MergeOutcome {
    Applied {
        item_revision: u64,
    },
    Unchanged {
        item_revision: u64,
    },
    Stale {
        current: u64,
    },
    Conflict,
    /// 该作用域不接受规范合并（存量有限回复）。
    NotCanonical,
    /// 认领/授权/作用域不再允许该写入。
    Fenced,
}

/// 卡片结果结算：不因撤权或失租丢弃已启动结果，也不覆盖后继操作。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) enum SettlementOutcome {
    Applied,
    AlreadySettled,
    /// 原意图已不匹配、版本或认领已失效，或存在后继事实；本次零写，不覆盖它们。
    Superseded,
}

/// 仅本次新建 Intent 的事务可产生的本地退役能力，不暴露请求或启动操作。
/// 不可复制、序列化或从恢复材料重建；提交未确认时只能凭此核实原意图并本地退役。
/// 读取或保存错误不会消耗本地退役责任。
#[derive(Debug)]
pub(in crate::bots) struct DeliveryCardAttempt {
    claim: DeliveryClaimToken,
    entity: DeliveryEntityKey,
    intent: DeliveryIntent,
    expected_ledger_version: u64,
    request_started: bool,
    consumed: bool,
}

/// 仅在原事务 commit 明确成功后构造的请求启动能力；不接受未确认或恢复材料转换。
/// 原所有者须在首次 HTTP future poll 之前标记启动，且在此之前保持平台短准入。
#[derive(Debug)]
pub(in crate::bots) struct ConfirmedDeliveryCardAttempt {
    attempt: DeliveryCardAttempt,
}

impl ConfirmedDeliveryCardAttempt {
    pub(in crate::bots) fn intent(&self) -> &DeliveryIntent {
        &self.attempt.intent
    }

    /// 一旦开始就不能再记录 NotStarted；即使请求随后取消或失败也不回退。
    pub(in crate::bots) fn mark_request_started(&mut self) {
        self.attempt.request_started = true;
    }

    /// 不可逆降级：消费启动能力，之后只能凭原 cap 本地退役，不能再次取得请求或启动权。
    pub(in crate::bots) fn into_retirement(self) -> DeliveryCardAttempt {
        self.attempt
    }
}

/// 提交错误不等于没有写入。Unconfirmed 只能用原 attempt 核实本地退役，不能启动请求；
/// Existing 仅表示原意图已存在，不携带请求材料，不授予发送权或新的本次启动证明。
#[derive(Debug)]
pub(in crate::bots) enum DeliveryCardAdmission {
    Confirmed(ConfirmedDeliveryCardAttempt),
    Unconfirmed {
        attempt: DeliveryCardAttempt,
        error: FeishuError,
    },
    Existing,
}

impl BotStateStore {
    /// 规范候选合并：只更新 canonical 身份/顺序/修订/正文与未完成索引。
    pub(in crate::bots) async fn merge_delivery_candidate(
        &self,
        token: &DeliveryClaimToken,
        candidate: &DeliveryCandidate,
    ) -> Result<MergeOutcome, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let scope = match fence_write(&tx, token).await? {
            WriteFence::Permitted(scope) => scope,
            WriteFence::LostClaim | WriteFence::Stopped => return Ok(MergeOutcome::Fenced),
        };
        if !scope.key.is_frontend() {
            return Ok(MergeOutcome::NotCanonical);
        }
        if candidate.item_order == 0
            || candidate.turn_id.is_empty()
            || candidate.content.revision() == 0
        {
            return Err(rejected(
                "canonical item needs positive order/revision and exact Turn",
            ));
        }
        let owner = super::ownership::turn_owner(
            &tx,
            &DeliveryTurnIdentity {
                thread_id: scope.thread_id.clone(),
                turn_id: candidate.turn_id.clone(),
                input_chain: candidate.input_chain.clone(),
            },
        )
        .await?;
        if owner != DeliveryTurnOwner::Frontend {
            return Ok(MergeOutcome::NotCanonical);
        }
        let revision = candidate.content.revision();
        let content = candidate_content(&candidate.content)?;
        if let DeliveryContent::File { file } = &content
            && (file.artifact.thread_id() != scope.thread_id
                || file.artifact.turn_id() != candidate.turn_id
                || file.artifact.item_order() != candidate.item_order
                || file.artifact.entity_key() != candidate.entity)
        {
            return Err(conflict());
        }
        let existing = read_entity(&tx, &token.scope, &candidate.entity).await?;
        let (state, removed, saved, expected) = match &existing {
            Some(entity) => {
                let current = entity.revision();
                if revision < current {
                    return Ok(MergeOutcome::Stale { current });
                }
                if matches!(&entity.state.content, DeliveryContent::Unresolved { unresolved } if unresolved.observation.is_some())
                {
                    return Ok(MergeOutcome::Conflict);
                }
                if entity
                    .turn_id
                    .as_deref()
                    .is_some_and(|turn| turn != candidate.turn_id)
                    || entity
                        .item_order
                        .is_some_and(|order| order != candidate.item_order)
                {
                    return Ok(MergeOutcome::Conflict);
                }
                let mut state = entity.state.clone();
                let removed = matches!(content, DeliveryContent::Removed { .. });
                let mut saved = candidate_saved(&candidate.content);
                if revision == current {
                    if entity.removed != removed || !same_candidate(entity, &content) {
                        return Ok(MergeOutcome::Conflict);
                    }
                    if entity.saved || !saved {
                        return Ok(MergeOutcome::Unchanged {
                            item_revision: current,
                        });
                    }
                    // 同修订 Saved 单调推进；保留原 accepted/confirmed/in-flight，不倒退。
                    saved = true;
                }
                // 只有后继 canonical 修订可重新准备；网络 Unknown/Rejected/LocalFailure
                // 及其原操作事实从不因 canonical 更新而清除。
                if revision > current
                    && matches!(state.halt, Some(DeliveryHalt::FilePreparation { .. }))
                {
                    state.halt = None;
                }
                state.content = content.clone();
                (state, removed, saved, Some(entity.ledger_version))
            }
            None => (
                DeliveryEntityState {
                    content,
                    projected: BotItemPresentation::None {},
                    accepted: BotItemPresentation::None {},
                    card: DeliveryCard::default(),
                    file_operation: None,
                    in_flight: None,
                    settled: None,
                    halt: None,
                },
                matches!(candidate.content, DeliveryCandidateContent::Removed { .. }),
                candidate_saved(&candidate.content),
                None,
            ),
        };
        let entity = DeliveryEntity {
            scope: token.scope.clone(),
            entity: candidate.entity.clone(),
            turn_id: Some(candidate.turn_id.clone()),
            item_order: Some(candidate.item_order),
            saved,
            removed,
            state,
            ledger_version: existing
                .as_ref()
                .map(|entity| entity.ledger_version.saturating_add(1))
                .unwrap_or(1),
            updated_at: unix_seconds(),
        };
        write_entity(&tx, &entity, expected).await?;
        sync_pending(&tx, &entity).await?;
        tx.commit().await.map_err(storage)?;
        Ok(MergeOutcome::Applied {
            item_revision: revision,
        })
    }

    /// 只进不退的规范顺序扫描水位。
    pub(in crate::bots) async fn save_delivery_watermark(
        &self,
        token: &DeliveryClaimToken,
        order_watermark: u64,
    ) -> Result<bool, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        match fence_write(&tx, token).await? {
            WriteFence::Permitted(_) => {}
            WriteFence::LostClaim | WriteFence::Stopped => return Ok(false),
        }
        let updated = tx
            .execute_raw(statement(
                "UPDATE bot_delivery_cursors SET order_watermark=?,updated_at=?
                 WHERE scope_key=? AND order_watermark<=?",
                vec![
                    i64::try_from(order_watermark)
                        .map_err(|_| unreadable())?
                        .into(),
                    unix_seconds().into(),
                    token.scope.storage_key()?.into(),
                    i64::try_from(order_watermark)
                        .map_err(|_| unreadable())?
                        .into(),
                ],
            ))
            .await
            .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        Ok(updated.rows_affected() == 1)
    }

    /// 先持久 Intent 才交付本次启动证明；Unknown 之后不再派发新操作。
    /// 事务提交前的错误正常返回 Err；提交结果不明则保留精确 attempt，禁止盲目重登。
    pub(in crate::bots) async fn register_delivery_card_intent<F>(
        &self,
        token: &DeliveryClaimToken,
        entity_key: &DeliveryEntityKey,
        expected_ledger_version: u64,
        action: DeliveryAction,
        freeze: F,
    ) -> Result<DeliveryCardAdmission, FeishuError>
    where
        F: FnOnce(
            &DeliveryOperationIdentity,
            &DeliveryAction,
        ) -> Result<FrozenDeliveryRequest, FeishuError>,
    {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let scope = match fence_write(&tx, token).await? {
            WriteFence::Permitted(scope) => scope,
            WriteFence::LostClaim | WriteFence::Stopped => return Err(fenced()),
        };
        if let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin
            && (legacy.source.is_none() || !legacy.resumable)
        {
            return Err(fenced());
        }
        let Some(entity) = read_entity(&tx, &token.scope, entity_key).await? else {
            return Err(unreadable());
        };
        if !scope.key.is_frontend() && !super::legacy::entity_matches(&scope, entity_key) {
            return Err(conflict());
        }
        if entity.ledger_version != expected_ledger_version {
            return Err(conflict());
        }
        if entity.state.card.lifecycle == Some(CardLifecycle::NeedsAttention) {
            return Err(fenced());
        }
        if let Some(in_flight) = &entity.state.in_flight {
            if in_flight.action == action
                && in_flight.owner_id == token.owner_id
                && in_flight.lease_generation == token.lease_generation
            {
                return Ok(DeliveryCardAdmission::Existing);
            }
            return Err(conflict());
        }
        if entity.state.halt.is_some() {
            return Err(halted());
        }
        if entity.removed {
            return Err(fenced());
        }
        if !scope.key.is_frontend()
            && entity
                .state
                .card
                .lifecycle
                .is_some_and(CardLifecycle::terminal)
        {
            return Err(fenced());
        }
        if action
            .text()
            .is_some_and(|text| text.chars().count() > DELIVERY_TEXT_CHARS)
        {
            return Err(rejected("new card action exceeds the text bound"));
        }
        let card = &entity.state.card;
        let (content_revision, integrity, saved) = match (action.text(), &entity.state.content) {
            (Some(body), DeliveryContent::Text { text }) if body == text.body => {
                (text.revision, text.integrity, text.saved)
            }
            (
                Some(body),
                DeliveryContent::Legacy {
                    presentation: Some(presentation),
                    ..
                },
            ) if body == presentation.body => (0, presentation.integrity, presentation.saved),
            (Some(_), DeliveryContent::Text { .. } | DeliveryContent::Legacy { .. }) => {
                return Err(conflict());
            }
            (None, DeliveryContent::Text { .. } | DeliveryContent::Legacy { .. }) => {
                let Some(BotItemPresentation::Text {
                    revision,
                    integrity,
                    saved,
                }) = &card.confirmed_presentation
                else {
                    return Err(conflict());
                };
                (*revision, *integrity, *saved)
            }
            (_, DeliveryContent::File { .. }) => {
                return Err(rejected("file delivery uses the send-operation ledger"));
            }
            (_, DeliveryContent::Unresolved { .. } | DeliveryContent::Removed { .. }) => {
                return Err(rejected("unproven delivery content cannot be sent"));
            }
        };
        let sequence = intent_sequence(card, &action)?;
        let operation_id = format!(
            "botcard:{}",
            super::typed_digest(&(
                &token.scope,
                entity_key,
                entity.ledger_version,
                sequence,
                &action
            ))?
        );
        let uuid =
            super::typed_digest(&(&operation_id, token.lease_generation, token.work_version))?;
        let uuid = uuid
            .strip_prefix("sha256:")
            .unwrap_or(&uuid)
            .chars()
            .take(32)
            .collect::<String>();
        let request = freeze(
            &DeliveryOperationIdentity {
                operation_id: operation_id.clone(),
                sequence,
                uuid: uuid.clone(),
            },
            &action,
        )?;
        request.validate_for_action(&action)?;
        let request_hash = request.hash()?;
        let intent = DeliveryIntent {
            operation_id,
            action: action.clone(),
            request_hash,
            request,
            legacy_action_hash: None,
            content_revision,
            integrity,
            saved,
            sequence,
            uuid,
            created_at: unix_seconds(),
            lease_generation: token.lease_generation,
            owner_id: token.owner_id.clone(),
        };
        let mut state = entity.state.clone();
        state.in_flight = Some(intent.clone());
        state.card.sequence = sequence;
        let mut next = entity.clone();
        next.state = state;
        next.ledger_version = entity
            .ledger_version
            .checked_add(1)
            .ok_or_else(unreadable)?;
        next.updated_at = unix_seconds();
        write_entity(&tx, &next, Some(entity.ledger_version)).await?;
        sync_pending(&tx, &next).await?;
        // 必须在 commit 之前构造：确认丢失时仍把这一次的身份与退役责任交给原 caller。
        let attempt = DeliveryCardAttempt {
            claim: token.clone(),
            entity: entity_key.clone(),
            intent,
            expected_ledger_version: next.ledger_version,
            request_started: false,
            consumed: false,
        };
        Ok(match tx.commit().await {
            Ok(()) => DeliveryCardAdmission::Confirmed(ConfirmedDeliveryCardAttempt { attempt }),
            Err(error) => DeliveryCardAdmission::Unconfirmed {
                attempt,
                error: storage(error),
            },
        })
    }

    /// 确定首次请求尚未开始的本地终态。只纠正精确原 Intent，不消费当前外写授权：
    /// Pause/Close 不阻止仍持原 live claim 的纠正；尚无本地终态时永久 stop/失租则零写 Superseded。
    /// 读取或保存失败保留 attempt 可重试；commit 确认丢失也由精确 NotStarted 读回裁决。
    /// 已有精确原 NotStarted 无后继时只读 AlreadySettled，不要求消费或失租的能力复活。
    pub(in crate::bots) async fn retire_unstarted_delivery_card(
        &self,
        attempt: &mut DeliveryCardAttempt,
    ) -> Result<SettlementOutcome, FeishuError> {
        if attempt.request_started {
            return Err(rejected(
                "a started card request cannot be retired as NotStarted",
            ));
        }
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let entity = read_entity(&tx, &attempt.claim.scope, &attempt.entity).await?;
        let Some(entity) = entity else {
            attempt.consumed = true;
            return Ok(SettlementOutcome::Superseded);
        };
        if entity.state.in_flight.is_none()
            && entity.state.settled.as_ref().is_some_and(|settled| {
                settled.intent == attempt.intent && settled.result == DeliveryResult::NotStarted
            })
        {
            // 只读核对已存在的本地终态，不是重新取得退役写权或发送能力。
            // 精确原 NotStarted 无后继时，即使本地能力已消费或后来失租也保持幂等。
            attempt.consumed = true;
            return Ok(SettlementOutcome::AlreadySettled);
        }
        if attempt.consumed
            || entity.state.in_flight.as_ref() != Some(&attempt.intent)
            || entity.ledger_version != attempt.expected_ledger_version
            || entity
                .state
                .settled
                .as_ref()
                .is_some_and(|settled| settled.intent.operation_id == attempt.intent.operation_id)
            || !matches!(fence_claim(&tx, &attempt.claim).await?, ClaimFence::Held)
        {
            attempt.consumed = true;
            return Ok(SettlementOutcome::Superseded);
        }
        let mut next = entity.clone();
        next.state.in_flight = None;
        next.state.settled = Some(DeliverySettled {
            intent: attempt.intent.clone(),
            result: DeliveryResult::NotStarted,
        });
        // 不改已接受呈现、card/confirmed sequence、UUID 或当前修订；同代待发索引照常派生。
        next.ledger_version = entity
            .ledger_version
            .checked_add(1)
            .ok_or_else(unreadable)?;
        next.updated_at = unix_seconds();
        write_entity(&tx, &next, Some(attempt.expected_ledger_version)).await?;
        sync_pending(&tx, &next).await?;
        tx.commit().await.map_err(storage)?;
        attempt.consumed = true;
        Ok(SettlementOutcome::Applied)
    }

    /// 按原 operation identity 结算真实结果：不要求认领（撤权后仍保存），不覆盖后继操作。
    pub(in crate::bots) async fn settle_delivery_card_result(
        &self,
        scope: &DeliveryScopeKey,
        entity_key: &DeliveryEntityKey,
        operation_id: &str,
        result: DeliveryResult,
    ) -> Result<SettlementOutcome, FeishuError> {
        if result == DeliveryResult::NotStarted {
            return Err(rejected(
                "NotStarted requires the original unstarted card attempt",
            ));
        }
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let Some(entity) = read_entity(&tx, scope, entity_key).await? else {
            return Err(unreadable());
        };
        let intent = match entity.state.in_flight.clone() {
            Some(intent) => intent,
            None => match &entity.state.settled {
                Some(settled) if settled.intent.operation_id == operation_id => {
                    if settled.result == result {
                        return Ok(SettlementOutcome::AlreadySettled);
                    }
                    if matches!(settled.result, DeliveryResult::Unknown { .. })
                        && !matches!(result, DeliveryResult::Unknown { .. })
                    {
                        settled.intent.clone()
                    } else {
                        return Err(conflict());
                    }
                }
                Some(_) => return Ok(SettlementOutcome::Superseded),
                None => return Err(conflict()),
            },
        };
        if intent.operation_id != operation_id {
            return Ok(SettlementOutcome::Superseded);
        }
        if !result_matches(&intent.action, intent.sequence, &result) {
            return Err(conflict());
        }
        let mut state = entity.state.clone();
        state.in_flight = None;
        state.halt = None;
        state.settled = Some(DeliverySettled {
            intent: intent.clone(),
            result: result.clone(),
        });
        match &result {
            DeliveryResult::NotStarted => {
                return Err(rejected(
                    "NotStarted requires the original unstarted card attempt",
                ));
            }
            DeliveryResult::Created { card_id } => {
                state.card.card_id = Some(card_id.clone());
                // Create 请求已声明 streaming_mode=true。
                state.card.streaming = Some(true);
                state.card.lifecycle = Some(CardLifecycle::Created);
                confirm_text(&mut state.card, &intent);
            }
            DeliveryResult::Sent {
                card_id: _,
                message_id,
            } => {
                state.card.platform_message_id = Some(message_id.clone());
                state.card.lifecycle = Some(CardLifecycle::Streaming);
                if let Some(presentation) = &state.card.confirmed_presentation {
                    state.projected = presentation.clone();
                    state.accepted = presentation.clone();
                }
            }
            DeliveryResult::ContentAccepted { .. } => {
                let presentation = text_presentation(&intent);
                state.projected = presentation.clone();
                state.accepted = presentation;
                confirm_text(&mut state.card, &intent);
            }
            DeliveryResult::SettingsAccepted { streaming, .. } => {
                state.card.streaming = Some(*streaming);
                if let DeliveryAction::UpdateSettings {
                    lifecycle,
                    recovery,
                    ..
                } = &intent.action
                {
                    state.card.lifecycle = Some(*lifecycle);
                    state.card.recovery_used |= recovery;
                }
            }
            DeliveryResult::Rejected { diagnostic } => {
                state.halt = Some(DeliveryHalt::Rejected {
                    operation_id: intent.operation_id.clone(),
                    diagnostic: diagnostic.clone(),
                });
            }
            DeliveryResult::Unknown { diagnostic } => {
                state.halt = Some(DeliveryHalt::Unknown {
                    operation_id: intent.operation_id.clone(),
                    diagnostic: diagnostic.clone(),
                });
            }
        }
        if !matches!(
            result,
            DeliveryResult::Rejected { .. } | DeliveryResult::Unknown { .. }
        ) {
            confirm_recovery(&mut state.card, &intent.action)?;
            state.card.confirmed_sequence = intent.sequence;
        }
        if entity.state.card.lifecycle == Some(CardLifecycle::NeedsAttention) {
            state.card.lifecycle = Some(CardLifecycle::NeedsAttention);
        }
        let mut next = entity.clone();
        next.state = state;
        next.ledger_version = entity.ledger_version.saturating_add(1);
        next.updated_at = unix_seconds();
        write_entity(&tx, &next, Some(entity.ledger_version)).await?;
        sync_pending(&tx, &next).await?;
        tx.commit().await.map_err(storage)?;
        Ok(SettlementOutcome::Applied)
    }

    /// 重启遗留未确认意图：不能证明未启动，只能在原租约不再持有时按 Unknown 保全。
    pub(in crate::bots) async fn retire_orphaned_delivery_intent(
        &self,
        scope: &DeliveryScopeKey,
        entity_key: &DeliveryEntityKey,
        operation_id: &str,
        diagnostic: &str,
    ) -> Result<SettlementOutcome, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let Some(entity) = read_entity(&tx, scope, entity_key).await? else {
            return Err(unreadable());
        };
        let Some(intent) = entity.state.in_flight.clone() else {
            return Ok(match &entity.state.settled {
                Some(settled) if settled.intent.operation_id == operation_id => {
                    SettlementOutcome::AlreadySettled
                }
                _ => SettlementOutcome::Superseded,
            });
        };
        if intent.operation_id != operation_id {
            return Ok(SettlementOutcome::Superseded);
        }
        let now = unix_seconds();
        let claim = tx
            .query_one_raw(statement(
                "SELECT owner_id,lease_generation,expires_at,stopped_reason
                 FROM bot_delivery_claims WHERE scope_key=?",
                vec![scope.storage_key()?.into()],
            ))
            .await
            .map_err(storage)?;
        let still_owned = claim.is_some_and(|row| {
            strict_text(&row, "owner_id").ok().as_deref() == Some(intent.owner_id.as_str())
                && strict_text(&row, "stopped_reason")
                    .ok()
                    .is_some_and(|reason| reason.is_empty())
                && stored_i64(&row, "lease_generation")
                    .ok()
                    .and_then(|value| u64::try_from(value).ok())
                    == Some(intent.lease_generation)
                && stored_i64(&row, "expires_at").unwrap_or(0) > now
        });
        if still_owned {
            // 该意图仍由活跃持有者负责：它应结算真实结果，而不是被旁观者改成 Unknown。
            return Err(conflict());
        }
        let result = DeliveryResult::Unknown {
            diagnostic: Some(diagnostic.to_string()),
        };
        let mut state = entity.state.clone();
        state.in_flight = None;
        state.settled = Some(DeliverySettled {
            intent: intent.clone(),
            result: result.clone(),
        });
        state.halt = Some(DeliveryHalt::Unknown {
            operation_id: intent.operation_id.clone(),
            diagnostic: Some(diagnostic.to_string()),
        });
        let mut next = entity.clone();
        next.state = state;
        next.ledger_version = entity.ledger_version.saturating_add(1);
        next.updated_at = now;
        write_entity(&tx, &next, Some(entity.ledger_version)).await?;
        sync_pending(&tx, &next).await?;
        tx.commit().await.map_err(storage)?;
        Ok(SettlementOutcome::Applied)
    }

    /// 首次发送登记前的单项准备失败。当前授权、认领、canonical 保存证明和版本在同一
    /// 事务内核验；既有网络材料或匹配的 send row 均拒绝，不创建操作身份或停止 scope。
    /// 幂等重报也须携带当前 ledger version；AlreadySettled 不写入、不推进观察版本。
    pub(in crate::bots) async fn block_delivery_file_preparation(
        &self,
        token: &DeliveryClaimToken,
        entity_key: &DeliveryEntityKey,
        expected_ledger_version: u64,
        artifact: &SavedArtifact,
        reason: DeliveryFilePreparationBlock,
    ) -> Result<SettlementOutcome, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let scope = match fence_write(&tx, token).await? {
            WriteFence::Permitted(scope) => scope,
            WriteFence::LostClaim | WriteFence::Stopped => return Err(fenced()),
        };
        if !scope.key.is_frontend() {
            return Err(conflict());
        }
        let entity = read_entity(&tx, &token.scope, entity_key)
            .await?
            .ok_or_else(conflict)?;
        let DeliveryContent::File { file } = &entity.state.content else {
            return Err(conflict());
        };
        if entity.ledger_version != expected_ledger_version
            || file.artifact != *artifact
            || artifact.entity_key() != *entity_key
            || artifact.thread_id() != scope.thread_id
            || entity.removed
            || !entity.saved
            || entity.state.has_network_history()
        {
            return Err(conflict());
        }
        let request_hash = delivery_file_request_hash(&scope, entity_key, artifact)?;
        if tx
            .query_one_raw(statement(
                "SELECT 1 FROM send_operations WHERE bot_id=? AND chat_id=?
               AND json_extract(send_identity,'$.kind')='file'
               AND json_extract(send_identity,'$.requestHash')=? LIMIT 1",
                vec![
                    scope.bot_id.clone().into(),
                    scope.chat_id.clone().into(),
                    request_hash.into(),
                ],
            ))
            .await
            .map_err(storage)?
            .is_some()
        {
            return Err(conflict());
        }
        let halt = DeliveryHalt::FilePreparation {
            revision: artifact.revision(),
            reason,
        };
        match &entity.state.halt {
            Some(existing) if *existing == halt => return Ok(SettlementOutcome::AlreadySettled),
            Some(_) => return Err(conflict()),
            None => {}
        }
        let mut next = entity.clone();
        next.state.halt = Some(halt);
        next.ledger_version = entity
            .ledger_version
            .checked_add(1)
            .ok_or_else(unreadable)?;
        next.updated_at = unix_seconds();
        write_entity(&tx, &next, Some(expected_ledger_version)).await?;
        sync_pending(&tx, &next).await?;
        tx.commit().await.map_err(storage)?;
        Ok(SettlementOutcome::Applied)
    }

    /// 文件绑定在原发送登记事务内逐字段核原 send row，绝不接受任意存在的 operation ID。
    pub(in crate::bots) async fn bind_delivery_file_operation<C: ConnectionTrait>(
        db: &C,
        token: &DeliveryClaimToken,
        entity_key: &DeliveryEntityKey,
        expected_ledger_version: u64,
        operation_id: &str,
        artifact: &SavedArtifact,
    ) -> Result<(), FeishuError> {
        let scope = match fence_write(db, token).await? {
            WriteFence::Permitted(scope) => scope,
            WriteFence::LostClaim | WriteFence::Stopped => return Err(fenced()),
        };
        let entity = read_entity(db, &token.scope, entity_key)
            .await?
            .ok_or_else(unreadable)?;
        if entity.ledger_version != expected_ledger_version {
            return Err(conflict());
        }
        let DeliveryContent::File { file } = &entity.state.content else {
            return Err(conflict());
        };
        if file.artifact != *artifact || entity.removed || file_block_reason(file).is_some() {
            return Err(conflict());
        }
        let binding =
            super::artifact::verify_send(db, &scope, entity_key, operation_id, artifact).await?;
        match &entity.state.file_operation {
            Some(existing) if *existing == binding => return Ok(()),
            Some(existing) => {
                // 只有原 revision 已确定送达才可登记更高修订；未知/在途材料绝不被替换。
                let old_stage = super::store::file_stage(db, &entity)
                    .await?
                    .ok_or_else(unreadable)?;
                if existing.artifact.revision() >= artifact.revision()
                    || entity.state.halt.is_some()
                    || !matches!(old_stage.message, BotPlatformResult::Accepted {})
                    || entity.state.accepted
                        != (BotItemPresentation::File {
                            revision: existing.artifact.revision(),
                        })
                {
                    return Err(conflict());
                }
            }
            None => {}
        }
        let mut next = entity.clone();
        next.state.file_operation = Some(binding);
        next.ledger_version = entity
            .ledger_version
            .checked_add(1)
            .ok_or_else(unreadable)?;
        next.updated_at = unix_seconds();
        write_entity(db, &next, Some(entity.ledger_version)).await?;
        sync_pending(db, &next).await
    }

    /// 每个 upload/message 新意图的同事务围栏；F 必须在实际 send writer 内调用。
    pub(in crate::bots) async fn fence_delivery_file_write<C: ConnectionTrait>(
        db: &C,
        token: &DeliveryClaimToken,
        entity_key: &DeliveryEntityKey,
        operation_id: &str,
    ) -> Result<(), FeishuError> {
        let scope = match fence_write(db, token).await? {
            WriteFence::Permitted(scope) => scope,
            _ => return Err(fenced()),
        };
        let entity = read_entity(db, &token.scope, entity_key)
            .await?
            .ok_or_else(unreadable)?;
        let binding = entity
            .state
            .file_operation
            .as_ref()
            .ok_or_else(unreadable)?;
        let DeliveryContent::File { .. } = &entity.state.content else {
            return Err(fenced());
        };
        if binding.operation_id != operation_id || entity.state.halt.is_some() || entity.removed {
            return Err(fenced());
        }
        if super::artifact::verify_send(db, &scope, entity_key, operation_id, &binding.artifact)
            .await?
            != *binding
        {
            return Err(conflict());
        }
        let stages = super::store::file_stage(db, &entity)
            .await?
            .ok_or_else(unreadable)?;
        if !stages.has_unstarted_stage() {
            return Err(fenced());
        }
        Ok(())
    }

    /// 原 send writer 在保存实际阶段的同一事务调用。结果与本地停止均由唯一账本派生，
    /// 不接受调用者另报结果；只确认原 binding revision，不要求当前授权/认领复活。
    /// 每次推进观察版本，使仅 upload/stop 变化也失效 GUI；AlreadySettled 仅表示派生
    /// 平台投影未改变。此写入 hook 不作轮询，也不授予下一阶段许可。
    pub(in crate::bots) async fn settle_delivery_file_result<C: ConnectionTrait>(
        db: &C,
        scope: &DeliveryScopeKey,
        entity_key: &DeliveryEntityKey,
        operation_id: &str,
    ) -> Result<SettlementOutcome, FeishuError> {
        let entity = read_entity(db, scope, entity_key)
            .await?
            .ok_or_else(unreadable)?;
        let Some(binding) = &entity.state.file_operation else {
            return Err(conflict());
        };
        if binding.operation_id != operation_id {
            return Ok(SettlementOutcome::Superseded);
        }
        let scope_row = super::records::read_scope(db, scope)
            .await?
            .ok_or_else(unreadable)?;
        if super::artifact::verify_send(db, &scope_row, entity_key, operation_id, &binding.artifact)
            .await?
            != *binding
        {
            return Err(conflict());
        }
        let stages = super::store::file_stage(db, &entity)
            .await?
            .ok_or_else(unreadable)?;
        let mut state = entity.state.clone();
        if matches!(stages.message, BotPlatformResult::Accepted {}) {
            let presentation = BotItemPresentation::File {
                revision: binding.artifact.revision(),
            };
            state.projected = presentation.clone();
            state.accepted = presentation;
        }
        state.halt = stages.halt();
        let outcome = if state == entity.state {
            SettlementOutcome::AlreadySettled
        } else {
            SettlementOutcome::Applied
        };
        let mut next = entity.clone();
        next.state = state;
        next.ledger_version = entity
            .ledger_version
            .checked_add(1)
            .ok_or_else(unreadable)?;
        next.updated_at = unix_seconds();
        write_entity(db, &next, Some(entity.ledger_version)).await?;
        sync_pending(db, &next).await?;
        Ok(outcome)
    }
}

fn item_sequence_base(card: &DeliveryCard) -> i32 {
    card.sequence
}

fn confirm_text(card: &mut DeliveryCard, intent: &DeliveryIntent) {
    if let Some(text) = intent.action.text() {
        card.confirmed_text = text.to_string();
        card.confirmed_content_hash = super::super::card::hash(text.as_bytes());
        card.confirmed_presentation = Some(text_presentation(intent));
        if matches!(
            intent.action,
            DeliveryAction::UpdateContent {
                final_content: true,
                ..
            }
        ) {
            card.final_content_hash = Some(card.confirmed_content_hash.clone());
        }
    }
}

fn confirm_recovery(card: &mut DeliveryCard, action: &DeliveryAction) -> Result<(), FeishuError> {
    use super::super::card::CardRecoveryPhase;
    let Some(recovery) = card.recovery.as_mut() else {
        return Ok(());
    };
    let finished = match (recovery.phase, action) {
        (
            CardRecoveryPhase::Reopen,
            DeliveryAction::UpdateSettings {
                streaming: true,
                recovery: true,
                ..
            },
        ) => {
            recovery.phase = CardRecoveryPhase::Content;
            false
        }
        (CardRecoveryPhase::Content, DeliveryAction::UpdateContent { .. }) => {
            if matches!(
                recovery.action,
                DeliveryAction::UpdateSettings {
                    streaming: false,
                    ..
                }
            ) {
                recovery.phase = CardRecoveryPhase::Close;
                false
            } else {
                true
            }
        }
        (
            CardRecoveryPhase::Close,
            DeliveryAction::UpdateSettings {
                streaming: false, ..
            },
        ) => true,
        _ => return Err(conflict()),
    };
    if finished {
        card.recovery = None;
    }
    Ok(())
}

fn intent_sequence(card: &DeliveryCard, action: &DeliveryAction) -> Result<i32, FeishuError> {
    if matches!(
        action,
        DeliveryAction::UpdateSettings { recovery: true, .. }
    ) && card.recovery_used
    {
        return Err(rejected("card recovery was already used"));
    }
    let card_id = card.card_id.as_deref();
    let message = card.platform_message_id.as_deref();
    match action {
        DeliveryAction::CreateCard { .. } => {
            if card_id.is_some() || message.is_some() || item_sequence_base(card) != 0 {
                return Err(rejected("the card entity already exists"));
            }
            Ok(0)
        }
        DeliveryAction::SendCard { card_id: expected } => {
            if card_id != Some(expected.as_str()) || message.is_some() {
                return Err(rejected("the card must be created once before it is sent"));
            }
            if item_sequence_base(card) != 0 {
                return Err(rejected("a sent card cannot be sent again"));
            }
            Ok(0)
        }
        DeliveryAction::UpdateContent {
            card_id: expected, ..
        } => {
            if card_id != Some(expected.as_str()) || message.is_none() {
                return Err(rejected("content updates need a sent card"));
            }
            if card.streaming != Some(true) {
                return Err(rejected("content updates need an open streaming card"));
            }
            card.sequence
                .checked_add(1)
                .ok_or_else(|| rejected("card sequence exhausted"))
        }
        DeliveryAction::UpdateSettings {
            card_id: expected,
            streaming,
            ..
        } => {
            if card_id != Some(expected.as_str()) || message.is_none() {
                return Err(rejected("card settings need a sent card"));
            }
            if card.streaming == Some(*streaming) {
                return Err(rejected("card settings already carry that streaming state"));
            }
            card.sequence
                .checked_add(1)
                .ok_or_else(|| rejected("card sequence exhausted"))
        }
    }
}

fn text_presentation(intent: &DeliveryIntent) -> BotItemPresentation {
    BotItemPresentation::Text {
        revision: intent.content_revision,
        integrity: intent.integrity,
        saved: intent.saved,
    }
}

fn candidate_saved(content: &DeliveryCandidateContent) -> bool {
    match content {
        DeliveryCandidateContent::Text { saved, .. } => *saved,
        DeliveryCandidateContent::File { .. } | DeliveryCandidateContent::Removed { .. } => true,
    }
}

fn candidate_content(content: &DeliveryCandidateContent) -> Result<DeliveryContent, FeishuError> {
    Ok(match content {
        DeliveryCandidateContent::Text {
            channel,
            revision,
            integrity,
            saved,
            body,
            request_bytes,
        } => {
            let text = DeliveryText {
                channel: *channel,
                revision: *revision,
                integrity: *integrity,
                saved: *saved,
                body: body.clone(),
                body_chars: u64::try_from(body.chars().count()).map_err(|_| unreadable())?,
                request_bytes: *request_bytes,
            };
            validate_text(&text)?;
            DeliveryContent::Text { text }
        }
        DeliveryCandidateContent::File { artifact } => {
            artifact.validate()?;
            DeliveryContent::File {
                file: DeliveryFile {
                    artifact: artifact.clone(),
                },
            }
        }
        DeliveryCandidateContent::Removed { revision } => {
            if *revision == 0 {
                return Err(rejected("removed item revision must be positive"));
            }
            DeliveryContent::Removed {
                revision: *revision,
            }
        }
    })
}

fn same_candidate(entity: &DeliveryEntity, applied: &DeliveryContent) -> bool {
    match (applied, &entity.state.content) {
        (DeliveryContent::Text { text }, DeliveryContent::Text { text: current }) => {
            let mut current = current.clone();
            current.saved = text.saved;
            current == *text
        }
        _ => applied == &entity.state.content,
    }
}
