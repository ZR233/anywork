//! 独立投递账本的窄存储端口：有界读、独立认领、规范合并、Intent/结算与文件 fence。
//!
//! 每个写入端口都在同一事务内核对当前 token、作用域身份、原授权（前端范围）与实体版本；
//! 消费者不得复制这些谓词。读取端口只使用已准备好的连接，绝不触发初始化、迁移或联网。

use super::super::audience::{self, DeliveryObservation};
use super::super::{BotStateStore, MessageStage, SendRecord, UploadFact, send_record_from_row};
use super::super::{statement, stored_i64, strict_text};
use super::records::{
    cursor_exists, decode_entity_row, decode_scope_row, entity_key_order, insert_cursor_row,
    insert_scope_row, order_value, read_entity, read_scope,
};
use super::{
    DELIVERY_READ_LIMIT, DeliveryContent, DeliveryCursor, DeliveryEntity, DeliveryEntityKey,
    DeliveryPendingRevision, DeliveryScope, DeliveryScopeKey, DeliveryScopeOrigin, conflict,
    derive_flags, diagnostic_of, item_platform, unreadable,
};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::send::SendIdentity;
use pl_protocol::BotAuthorizationId;
use pl_protocol::studio::BotItemLedgerSummary;
use sea_orm::ConnectionTrait;

/// 有界作用域页。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryScopePage {
    pub scopes: Vec<DeliveryScope>,
    pub next_after: Option<String>,
}

/// 有界实体页：键为 `(item_order, entity_key)` 的唯一复合位置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryEntityPage {
    pub entities: Vec<DeliveryEntity>,
    pub next_after: Option<(i64, String)>,
}

/// 有界未完成索引页。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryPendingPage {
    pub pending: Vec<DeliveryPendingRevision>,
    pub next_after: Option<(i64, String)>,
}

/// 从真实授权与创建来源建立（或逐字段核验）前端作用域。
///
/// 由原授权/绑定持有者在其**同一事务**内调用（首次 PendingStart、后续 Enable、激活）。
/// 只读取本地已证明事实：不联网、不补猜种类、不复制 phase/start。已有作用域必须完整身份
/// 等值，缺游标属于结构不一致而不是静默修补。普通只读查询不调用本入口。
pub(in crate::bots) async fn ensure_frontend_scope_in<C: ConnectionTrait>(
    db: &C,
    authorization: &super::super::audience::Authorization,
    origin: &super::super::audience::ThreadOrigin,
) -> Result<bool, FeishuError> {
    authorization.validate()?;
    let id = authorization.intent.authorization.clone();
    if id.bot_id.is_empty()
        || id.chat_id.is_empty()
        || id.generation == 0
        || authorization.app_id.is_empty()
        || authorization.project_id.is_empty()
        || authorization.creation_id.is_empty()
        || authorization.intent.binding_revision == 0
        || authorization.intent.thread_id.is_empty()
        || origin.thread_id != authorization.intent.thread_id
        || origin.chat_id != id.chat_id
        || origin.project_id != authorization.project_id
        || origin.creation_id != authorization.creation_id
        || origin.binding_revision != authorization.intent.binding_revision
        || origin.summary_version == 0
    {
        return Err(unreadable());
    }
    // 创建期证明只做本地一致性核对：不据此发送，也不从当前配置补出种类。
    match &origin.target {
        super::super::target::TargetProof::Unproven => {
            if !origin.requires_upgrade {
                return Err(unreadable());
            }
        }
        super::super::target::TargetProof::Legacy { .. } => {}
        super::super::target::TargetProof::Created { evidence } => {
            if evidence.bot_id != id.bot_id
                || evidence.app_id != authorization.app_id
                || evidence.project_id != authorization.project_id
                || evidence.chat_id != id.chat_id
                || evidence.creation_id != authorization.creation_id
                || evidence.binding_revision != authorization.intent.binding_revision
            {
                return Err(unreadable());
            }
        }
    }
    let key = DeliveryScopeKey::Frontend {
        authorization: id.clone(),
    };
    match read_scope(db, &key).await? {
        Some(scope) => {
            let origin_matches = matches!(
                &scope.origin,
                DeliveryScopeOrigin::Frontend {
                    authorization: stored
                } if *stored == id
            );
            if !scope.key.is_frontend()
                || !origin_matches
                || scope.bot_id != id.bot_id
                || scope.chat_id != id.chat_id
                || scope.thread_id != origin.thread_id
                || scope.app_id != authorization.app_id
                || scope.project_id != authorization.project_id
                || scope.creation_id != authorization.creation_id
                || scope.binding_revision != authorization.intent.binding_revision
                || scope.needs_recovery
            {
                return Err(conflict());
            }
            if !cursor_exists(db, &key).await? {
                return Err(unreadable());
            }
            Ok(false)
        }
        None => {
            insert_scope_row(
                db,
                &DeliveryScope {
                    key: key.clone(),
                    bot_id: id.bot_id.clone(),
                    chat_id: id.chat_id.clone(),
                    thread_id: origin.thread_id.clone(),
                    app_id: authorization.app_id.clone(),
                    project_id: authorization.project_id.clone(),
                    creation_id: authorization.creation_id.clone(),
                    binding_revision: authorization.intent.binding_revision,
                    origin: DeliveryScopeOrigin::Frontend { authorization: id },
                    needs_recovery: false,
                },
            )
            .await
            .map_err(|_| unreadable())?;
            insert_cursor_row(db, &key)
                .await
                .map_err(|_| unreadable())?;
            Ok(true)
        }
    }
}

impl BotStateStore {
    /// 只读：有界列出作用域（按稳定键递增）。不初始化、不迁移、不联网。
    pub(in crate::bots) async fn delivery_scopes(
        &self,
        after: Option<&str>,
        limit: usize,
    ) -> Result<DeliveryScopePage, FeishuError> {
        let limit = i64::try_from(limit.clamp(1, DELIVERY_READ_LIMIT)).map_err(|_| unreadable())?;
        let db = self.audience_db()?;
        let rows = match after {
            None => {
                db.query_all_raw(statement(
                    "SELECT * FROM bot_delivery_scopes ORDER BY scope_key LIMIT ?",
                    vec![(limit + 1).into()],
                ))
                .await
            }
            Some(after) => {
                db.query_all_raw(statement(
                    "SELECT * FROM bot_delivery_scopes WHERE scope_key>? ORDER BY scope_key LIMIT ?",
                    vec![after.to_string().into(), (limit + 1).into()],
                ))
                .await
            }
        }
        .map_err(storage)?;
        let more = rows.len() > usize::try_from(limit).unwrap_or(usize::MAX);
        let mut scopes = Vec::with_capacity(rows.len().min(DELIVERY_READ_LIMIT));
        for row in rows
            .iter()
            .take(usize::try_from(limit).map_err(|_| unreadable())?)
        {
            let decoded = decode_scope_row(row)?;
            scopes.push(read_scope(db, &decoded.key).await?.ok_or_else(unreadable)?);
        }
        let next_after = more
            .then(|| scopes.last().and_then(|scope| scope.key.storage_key().ok()))
            .flatten();
        Ok(DeliveryScopePage { scopes, next_after })
    }

    /// 只读：单个作用域；不存在返回 `None`（不是“无受众”）。
    pub(in crate::bots) async fn delivery_scope(
        &self,
        key: &DeliveryScopeKey,
    ) -> Result<Option<DeliveryScope>, FeishuError> {
        read_scope(self.audience_db()?, key).await
    }

    /// 只读：恢复位置扫描水位。
    pub(in crate::bots) async fn delivery_cursor(
        &self,
        key: &DeliveryScopeKey,
    ) -> Result<DeliveryCursor, FeishuError> {
        let db = self.audience_db()?;
        let row = db
            .query_one_raw(statement(
                "SELECT order_watermark,updated_at FROM bot_delivery_cursors WHERE scope_key=?",
                vec![key.storage_key()?.into()],
            ))
            .await
            .map_err(storage)?;
        read_scope(db, key).await?.ok_or_else(unreadable)?;
        let row = row.ok_or_else(unreadable)?;
        Ok(DeliveryCursor {
            scope: key.clone(),
            order_watermark: u64::try_from(stored_i64(&row, "order_watermark")?)
                .map_err(|_| unreadable())?,
            updated_at: stored_i64(&row, "updated_at")?,
        })
    }

    /// 只读：按规范顺序有界读取实体；键是 `(item_order, entity_key)`。
    pub(in crate::bots) async fn delivery_entities(
        &self,
        scope: &DeliveryScopeKey,
        after: Option<(i64, String)>,
        limit: usize,
    ) -> Result<DeliveryEntityPage, FeishuError> {
        let limit = i64::try_from(limit.clamp(1, DELIVERY_READ_LIMIT)).map_err(|_| unreadable())?;
        let db = self.audience_db()?;
        read_scope(db, scope).await?.ok_or_else(unreadable)?;
        let key = scope.storage_key()?;
        let rows = match after {
            None => {
                db.query_all_raw(statement(
                    "SELECT * FROM bot_delivery_items WHERE scope_key=?
                     ORDER BY item_order,entity_key LIMIT ?",
                    vec![key.into(), (limit + 1).into()],
                ))
                .await
            }
            Some((order, entity)) => {
                db.query_all_raw(statement(
                    "SELECT * FROM bot_delivery_items WHERE scope_key=?
                       AND (item_order,entity_key)>(?,?)
                     ORDER BY item_order,entity_key LIMIT ?",
                    vec![key.into(), order.into(), entity.into(), (limit + 1).into()],
                ))
                .await
            }
        }
        .map_err(storage)?;
        let take = usize::try_from(limit).unwrap_or(DELIVERY_READ_LIMIT);
        let more = rows.len() > take;
        let mut entities = Vec::with_capacity(rows.len().min(DELIVERY_READ_LIMIT));
        for row in rows.iter().take(take) {
            entities.push(decode_entity_row(scope, row)?);
        }
        let next_after = more
            .then(|| {
                entities
                    .last()
                    .map(|entity| (order_value(entity.item_order), entity_key_order(entity)))
            })
            .flatten();
        Ok(DeliveryEntityPage {
            entities,
            next_after,
        })
    }

    /// 只读：单个实体。
    pub(in crate::bots) async fn delivery_entity(
        &self,
        scope: &DeliveryScopeKey,
        entity: &DeliveryEntityKey,
    ) -> Result<Option<DeliveryEntity>, FeishuError> {
        read_entity(self.audience_db()?, scope, entity).await
    }

    /// 只读：未完成项索引（含旧项修订跟踪），键与实体页一致。
    pub(in crate::bots) async fn delivery_pending(
        &self,
        scope: &DeliveryScopeKey,
        after: Option<(i64, String)>,
        limit: usize,
    ) -> Result<DeliveryPendingPage, FeishuError> {
        let limit = i64::try_from(limit.clamp(1, DELIVERY_READ_LIMIT)).map_err(|_| unreadable())?;
        let db = self.audience_db()?;
        read_scope(db, scope).await?.ok_or_else(unreadable)?;
        let key = scope.storage_key()?;
        let rows = match after {
            None => {
                db.query_all_raw(statement(
                    "SELECT p.entity_key,p.item_order,p.item_revision,i.entity_json
                     FROM bot_delivery_pending p
                     JOIN bot_delivery_items i
                       ON i.scope_key=p.scope_key AND i.entity_key=p.entity_key
                     WHERE p.scope_key=?
                     ORDER BY p.item_order,p.entity_key LIMIT ?",
                    vec![key.into(), (limit + 1).into()],
                ))
                .await
            }
            Some((order, entity)) => {
                db.query_all_raw(statement(
                    "SELECT p.entity_key,p.item_order,p.item_revision,i.entity_json
                     FROM bot_delivery_pending p
                     JOIN bot_delivery_items i
                       ON i.scope_key=p.scope_key AND i.entity_key=p.entity_key
                     WHERE p.scope_key=? AND (p.item_order,p.entity_key)>(?,?)
                     ORDER BY p.item_order,p.entity_key LIMIT ?",
                    vec![key.into(), order.into(), entity.into(), (limit + 1).into()],
                ))
                .await
            }
        }
        .map_err(storage)?;
        let take = usize::try_from(limit).unwrap_or(DELIVERY_READ_LIMIT);
        let more = rows.len() > take;
        let mut pending = Vec::with_capacity(rows.len().min(DELIVERY_READ_LIMIT));
        for row in rows.iter().take(take) {
            // 未完成索引的稳定键只是实体身份：typed 身份解码时重算核对，不做前缀反解。
            let entity = DeliveryEntityKey::decode_stored(
                &strict_text(row, "entity_key")?,
                &strict_text(row, "entity_json")?,
            )?;
            pending.push(DeliveryPendingRevision {
                entity,
                item_order: match stored_i64(row, "item_order")? {
                    -1 => None,
                    order if order >= 0 => Some(u64::try_from(order).map_err(|_| unreadable())?),
                    _ => return Err(unreadable()),
                },
                item_revision: u64::try_from(stored_i64(row, "item_revision")?)
                    .map_err(|_| unreadable())?,
            });
        }
        let next_after = more
            .then(|| {
                pending.last().map(|entry| {
                    (
                        order_value(entry.item_order),
                        entry.entity.storage_key().unwrap_or_default(),
                    )
                })
            })
            .flatten();
        Ok(DeliveryPendingPage {
            pending,
            next_after,
        })
    }

    /// GUI 单项投影：只读当前唯一账本，authorization 与作用域身份共同核对。
    pub(in crate::bots) async fn delivery_observation(
        &self,
        auth: &BotAuthorizationId,
        item: &str,
    ) -> Result<Option<DeliveryObservation>, FeishuError> {
        let db = self.audience_db()?;
        let key = DeliveryScopeKey::Frontend {
            authorization: auth.clone(),
        };
        let Some(scope) = read_scope(db, &key).await? else {
            return Ok(None);
        };
        let stored = audience::load_auth(db, auth)
            .await?
            .ok_or_else(unreadable)?;
        if stored.intent.authorization != *auth
            || stored.intent.thread_id != scope.thread_id
            || stored.app_id != scope.app_id
            || stored.project_id != scope.project_id
            || stored.creation_id != scope.creation_id
            || stored.intent.binding_revision != scope.binding_revision
        {
            return Err(unreadable());
        }
        let row = db
            .query_one_raw(statement(
                "SELECT * FROM bot_delivery_items WHERE scope_key=? AND item_id=?",
                vec![key.storage_key()?.into(), item.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let Some(row) = row else {
            return Ok(None);
        };
        let entity = decode_entity_row(&key, &row)?;
        if !matches!(
            &entity.state.content,
            DeliveryContent::Text { .. }
                | DeliveryContent::File { .. }
                | DeliveryContent::Removed { .. }
                | DeliveryContent::Unresolved { .. }
        ) {
            return Err(unreadable());
        }
        let flags = derive_flags(entity.removed, &entity.state);
        let observed_revision = match &entity.state.content {
            DeliveryContent::Unresolved {
                unresolved:
                    super::DeliveryUnresolved {
                        observation: Some(observation),
                        ..
                    },
            } => Some(observation.observed_revision),
            _ => None,
        }
        .unwrap_or_else(|| entity.revision());
        let platform = item_platform(&entity, file_stage(db, &entity).await?);
        let ledger = match &entity.state.content {
            DeliveryContent::Unresolved { unresolved } => unresolved.observation.clone(),
            _ => None,
        }
        .unwrap_or(BotItemLedgerSummary {
            observed_revision,
            projected: entity.state.projected.clone(),
            accepted: entity.state.accepted.clone(),
            platform,
        });
        Ok(Some(DeliveryObservation {
            item_id: item.to_string(),
            thread_id: scope.thread_id,
            authorization: auth.clone(),
            ledger,
            removed: entity.removed,
            pending: flags.pending(),
            incomplete: flags.incomplete,
        }))
    }
}

pub(super) fn halted() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "delivery entity is halted by an unknown or rejected platform result",
        false,
        None,
    )
}

pub(super) fn storage(error: impl std::fmt::Display) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("bot delivery ledger failed: {error}"),
        true,
        None,
    )
}

/// 文件阶段事实只从原发送账本派生，不复制第二份可写状态。
pub(super) async fn file_stage<C: ConnectionTrait>(
    db: &C,
    entity: &DeliveryEntity,
) -> Result<Option<super::DeliveryFileStage>, FeishuError> {
    let Some(binding) = &entity.state.file_operation else {
        return Ok(None);
    };
    let operation_id = &binding.operation_id;
    let row = db
        .query_one_raw(statement(
            "SELECT operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,
                    segment_facts,send_identity,send_source
             FROM send_operations WHERE operation_id=?",
            vec![operation_id.clone().into()],
        ))
        .await
        .map_err(storage)?;
    let Some(row) = row else {
        return Err(unreadable());
    };
    let record: SendRecord = send_record_from_row(row)?;
    if record.operation_id != *operation_id
        || !record.facts_complete
        || record.segments.len() != 1
        || !matches!(record.identity, SendIdentity::File { .. })
    {
        return Err(unreadable());
    }
    let segment = record.segments.first().ok_or_else(unreadable)?;
    Ok(Some(super::DeliveryFileStage {
        operation_id: operation_id.clone(),
        upload: upload_result(segment)?,
        message: message_result(segment)?,
        local_stop: segment.stop_reason,
    }))
}

fn upload_result(
    segment: &super::super::SendSegmentFact,
) -> Result<pl_protocol::studio::BotPlatformResult, FeishuError> {
    use pl_protocol::studio::BotPlatformResult;
    Ok(match segment.upload.as_ref().ok_or_else(unreadable)? {
        UploadFact::NotStarted => BotPlatformResult::NotStarted {},
        UploadFact::InFlight => BotPlatformResult::InFlight {},
        UploadFact::Accepted { .. } => BotPlatformResult::Accepted {},
        UploadFact::Rejected => BotPlatformResult::Rejected {
            diagnostic: diagnostic_of("the platform rejected the file upload"),
        },
        UploadFact::Unknown => BotPlatformResult::Unknown {
            diagnostic: diagnostic_of("the file upload outcome is unknown"),
        },
    })
}

fn message_result(
    segment: &super::super::SendSegmentFact,
) -> Result<pl_protocol::studio::BotPlatformResult, FeishuError> {
    use pl_protocol::studio::BotPlatformResult;
    Ok(match segment.message_stage.ok_or_else(unreadable)? {
        MessageStage::NotStarted => BotPlatformResult::NotStarted {},
        MessageStage::InFlight => BotPlatformResult::InFlight {},
        MessageStage::Accepted => BotPlatformResult::Accepted {},
        MessageStage::Rejected => BotPlatformResult::Rejected {
            diagnostic: diagnostic_of("the platform rejected the file message"),
        },
        MessageStage::Unknown => BotPlatformResult::Unknown {
            diagnostic: diagnostic_of("the file message outcome is unknown"),
        },
    })
}

#[cfg(test)]
mod tests {
    //! 认领/合并/Intent/结算专项：真实 SQLite + 真实端口，只验证持久不变量。

    use super::super::records::{insert_entity_row, sync_pending};
    use super::*;
    use crate::bots::storage::audience::Authorization;
    use crate::bots::storage::publication::{
        ConfirmedDeliveryCardAttempt, DeliveryAction, DeliveryCandidate, DeliveryCandidateContent,
        DeliveryCardAdmission, DeliveryClaimOutcome, DeliveryClaimToken, DeliveryEntityKey,
        DeliveryEntityState, DeliveryHalt, DeliveryResult, DeliveryScope, DeliveryScopeKey,
        DeliveryScopeOrigin, MergeOutcome, SettlementOutcome,
    };
    use crate::bots::storage::{BotStateStore, SendRecordStatus, statement};
    use crate::studio::audience_start::{AudienceStartIntent, AudienceStartReceipt};
    use pl_protocol::BotAuthorizationId;
    use pl_protocol::studio::{
        BotAuthorizationPhase, BotItemPresentation, BotPublicTextChannel, BotTextIntegrity,
    };
    use sea_orm::TransactionTrait;

    const BOT: &str = "botfixture";
    const CHAT: &str = "chat-1";
    const THREAD: &str = "thread-1";
    const PROJECT: &str = "project";
    const APP: &str = "app";

    fn creation() -> String {
        format!("botthread:{BOT}:{CHAT}:op")
    }

    fn authorization_id() -> BotAuthorizationId {
        BotAuthorizationId {
            bot_id: BOT.to_string(),
            chat_id: CHAT.to_string(),
            generation: 1,
        }
    }

    fn active_authorization() -> Authorization {
        let intent = AudienceStartIntent {
            operation_id: "op-1".to_string(),
            thread_id: THREAD.to_string(),
            authorization: authorization_id(),
            binding_revision: 1,
        };
        Authorization {
            start: Some(AudienceStartReceipt {
                version: 1,
                intent: intent.clone(),
                extension_revision: 1,
                sequence: 1,
                excluded_turn_id: None,
            }),
            intent,
            app_id: APP.to_string(),
            project_id: PROJECT.to_string(),
            creation_id: creation(),
            revision: 1,
            phase: BotAuthorizationPhase::Active,
            closed: None,
            delivery_version: 1,
        }
    }

    /// 真实新建机器人库（当前结构），再写入一份已证明前端作用域。
    async fn store_with_frontend() -> anyhow::Result<(tempfile::TempDir, BotStateStore)> {
        let directory = tempfile::tempdir()?;
        let store = BotStateStore::new(directory.path().join("state.sqlite"));
        let db = store.db().await?;
        db.execute_raw(statement(
            "INSERT INTO bot_audience_origins
               (thread_id,chat_id,project_id,creation_id,binding_revision,requires_upgrade,
                summary_version,target_json)
             VALUES(?,?,?,?,1,1,1,?)",
            vec![
                THREAD.into(),
                CHAT.into(),
                PROJECT.into(),
                creation().into(),
                "{\"kind\":\"unproven\"}".into(),
            ],
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO bot_authorizations
               (chat_id,generation,thread_id,control_revision,phase,state_json)
             VALUES(?,1,?,1,'active',?)",
            vec![
                CHAT.into(),
                THREAD.into(),
                serde_json::to_string(&active_authorization())?.into(),
            ],
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO thread_bindings
               (chat_id,thread_id,status,creation_id,project_id,revision,created_at)
             VALUES(?,?,'bound',?,?,1,1)",
            vec![
                CHAT.into(),
                THREAD.into(),
                creation().into(),
                PROJECT.into(),
            ],
        ))
        .await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        insert_scope_row(
            db,
            &DeliveryScope {
                key: key.clone(),
                bot_id: BOT.to_string(),
                chat_id: CHAT.to_string(),
                thread_id: THREAD.to_string(),
                app_id: APP.to_string(),
                project_id: PROJECT.to_string(),
                creation_id: creation(),
                binding_revision: 1,
                origin: DeliveryScopeOrigin::Frontend {
                    authorization: authorization_id(),
                },
                needs_recovery: false,
            },
        )
        .await?;
        insert_cursor_row(db, &key).await?;
        Ok((directory, store))
    }

    fn text_candidate(body: &str, revision: u64) -> DeliveryCandidate {
        DeliveryCandidate {
            entity: DeliveryEntityKey::TextItem {
                item_id: "item-1".to_string(),
            },
            turn_id: "turn-1".to_string(),
            item_order: 1,
            input_chain: super::super::DeliveryInputChain::Proven {
                input_id: "gui-input".into(),
                continuation_ancestors: vec![],
            },
            content: DeliveryCandidateContent::Text {
                channel: BotPublicTextChannel::Final,
                revision,
                integrity: BotTextIntegrity::Full,
                saved: true,
                body: body.to_string(),
                request_bytes: 300,
            },
        }
    }

    fn legacy_candidate(body: &str) -> super::super::DeliveryLegacyCandidate {
        super::super::DeliveryLegacyCandidate {
            turn_id: "turn-1".into(),
            input_chain: super::super::DeliveryInputChain::Proven {
                input_id: format!("bot:{BOT}:{CHAT}:old-message"),
                continuation_ancestors: vec![],
            },
            body: body.into(),
            integrity: BotTextIntegrity::Full,
            saved: false,
            request_bytes: 300,
        }
    }

    impl BotStateStore {
        async fn register_test_card_admission(
            &self,
            token: &DeliveryClaimToken,
            key: &DeliveryEntityKey,
            action: DeliveryAction,
        ) -> Result<DeliveryCardAdmission, FeishuError> {
            let version = self
                .delivery_entity(&token.scope, key)
                .await?
                .ok_or_else(unreadable)?
                .ledger_version;
            self.register_delivery_card_intent(token, key, version, action, |identity, action| {
                let frozen = super::super::migrate::freeze_legacy_request(
                    CHAT,
                    action,
                    identity.sequence,
                    &identity.uuid,
                )?;
                super::super::FrozenDeliveryRequest::new(frozen.target(), frozen.body().to_string())
            })
            .await
        }

        async fn register_test_card_attempt(
            &self,
            token: &DeliveryClaimToken,
            key: &DeliveryEntityKey,
            action: DeliveryAction,
        ) -> Result<ConfirmedDeliveryCardAttempt, FeishuError> {
            match self
                .register_test_card_admission(token, key, action)
                .await?
            {
                DeliveryCardAdmission::Confirmed(attempt) => Ok(attempt),
                DeliveryCardAdmission::Unconfirmed { error, .. } => Err(error),
                DeliveryCardAdmission::Existing => Err(conflict()),
            }
        }

        /// 原有真实结果保存专项只需已启动请求的身份事实，不从 Existing 取得启动权。
        async fn register_test_card_intent(
            &self,
            token: &DeliveryClaimToken,
            key: &DeliveryEntityKey,
            action: DeliveryAction,
        ) -> Result<super::super::DeliveryIntent, FeishuError> {
            let mut attempt = self.register_test_card_attempt(token, key, action).await?;
            attempt.mark_request_started();
            Ok(attempt.intent().clone())
        }
    }

    fn entity_key() -> DeliveryEntityKey {
        DeliveryEntityKey::TextItem {
            item_id: "item-1".to_string(),
        }
    }

    async fn claimed(store: &BotStateStore, key: &DeliveryScopeKey) -> DeliveryClaimToken {
        match store.claim_delivery_scope(key, "owner-a").await.unwrap() {
            DeliveryClaimOutcome::Acquired(token) => token,
            other => panic!("claim must be acquired, got {other:?}"),
        }
    }

    async fn summary_version(store: &BotStateStore) -> anyhow::Result<i64> {
        let row = store
            .db()
            .await?
            .query_one_raw(statement(
                "SELECT summary_version FROM bot_audience_origins WHERE thread_id=?",
                vec![THREAD.into()],
            ))
            .await?
            .expect("summary origin");
        Ok(stored_i64(&row, "summary_version")?)
    }

    async fn card_state_raw(
        store: &BotStateStore,
        key: &DeliveryScopeKey,
    ) -> anyhow::Result<String> {
        let row = store
            .db()
            .await?
            .query_one_raw(statement(
                "SELECT state_json FROM bot_delivery_items WHERE scope_key=? AND entity_key=?",
                vec![
                    key.storage_key()?.into(),
                    entity_key().storage_key()?.into(),
                ],
            ))
            .await?
            .expect("card entity");
        Ok(strict_text(&row, "state_json")?)
    }

    async fn inject_card_state(
        store: &BotStateStore,
        key: &DeliveryScopeKey,
        raw: &str,
    ) -> anyhow::Result<()> {
        store
            .db()
            .await?
            .execute_raw(statement(
                "UPDATE bot_delivery_items SET state_json=? WHERE scope_key=? AND entity_key=?",
                vec![
                    raw.into(),
                    key.storage_key()?.into(),
                    entity_key().storage_key()?.into(),
                ],
            ))
            .await?;
        Ok(())
    }

    async fn rejected_card_result_is_zero_write(
        store: &BotStateStore,
        key: &DeliveryScopeKey,
        operation: &str,
        result: DeliveryResult,
    ) -> anyhow::Result<()> {
        let before = store.delivery_entity(key, &entity_key()).await?.unwrap();
        let raw = card_state_raw(store, key).await?;
        let pending = store.delivery_pending(key, None, 100).await?;
        let cursor = store.delivery_cursor(key).await?;
        let version = summary_version(store).await?;
        assert!(
            store
                .settle_delivery_card_result(key, &entity_key(), operation, result)
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(key, &entity_key()).await?,
            Some(before)
        );
        assert_eq!(card_state_raw(store, key).await?, raw);
        assert_eq!(store.delivery_pending(key, None, 100).await?, pending);
        assert_eq!(store.delivery_cursor(key).await?, cursor);
        assert_eq!(summary_version(store).await?, version);
        Ok(())
    }

    /// 真实 Intent 事务之后只故障注入 action 的平台身份，保 state.card 的合法身份。
    /// 普通读取必须仍成功，才能证明结果矩阵本身拒绝“空白且相等”的 Accepted 身份。
    async fn blank_accepted_ids_preserve_inflight(
        store: &BotStateStore,
        key: &DeliveryScopeKey,
        intent: &super::super::DeliveryIntent,
    ) -> anyhow::Result<()> {
        let before = store.delivery_entity(key, &entity_key()).await?.unwrap();
        assert_eq!(before.state.in_flight.as_ref(), Some(intent));
        let original_raw = card_state_raw(store, key).await?;
        for blank in ["", " \t\r\n\u{2003}"] {
            let mut state = before.state.clone();
            let action = &mut state.in_flight.as_mut().unwrap().action;
            let result = match action {
                DeliveryAction::CreateCard { .. } => DeliveryResult::Created {
                    card_id: blank.into(),
                },
                DeliveryAction::SendCard { card_id } => {
                    *card_id = blank.into();
                    DeliveryResult::Sent {
                        card_id: blank.into(),
                        message_id: "om-valid".into(),
                    }
                }
                DeliveryAction::UpdateContent { card_id, .. } => {
                    *card_id = blank.into();
                    DeliveryResult::ContentAccepted {
                        card_id: blank.into(),
                    }
                }
                DeliveryAction::UpdateSettings {
                    card_id, streaming, ..
                } => {
                    *card_id = blank.into();
                    DeliveryResult::SettingsAccepted {
                        card_id: blank.into(),
                        streaming: *streaming,
                    }
                }
            };
            inject_card_state(store, key, &serde_json::to_string(&state)?).await?;
            rejected_card_result_is_zero_write(store, key, &intent.operation_id, result).await?;
            inject_card_state(store, key, &original_raw).await?;
            if let DeliveryAction::SendCard { card_id } = &intent.action {
                rejected_card_result_is_zero_write(
                    store,
                    key,
                    &intent.operation_id,
                    DeliveryResult::Sent {
                        card_id: card_id.clone(),
                        message_id: blank.into(),
                    },
                )
                .await?;
            }
        }
        assert_eq!(
            store.delivery_entity(key, &entity_key()).await?,
            Some(before)
        );
        assert_eq!(card_state_raw(store, key).await?, original_raw);
        Ok(())
    }

    async fn blank_stored_card_ids_refuse_cold_read(
        store: &BotStateStore,
        key: &DeliveryScopeKey,
        path: &std::path::Path,
    ) -> anyhow::Result<()> {
        let before = store.delivery_entity(key, &entity_key()).await?.unwrap();
        assert!(matches!(
            before.state.settled.as_ref().unwrap().result,
            DeliveryResult::ContentAccepted { .. } | DeliveryResult::SettingsAccepted { .. }
        ));
        let original_raw = card_state_raw(store, key).await?;
        let version = summary_version(store).await?;
        BotStateStore::new(path.to_path_buf()).db().await?;
        for message in [false, true] {
            let mut state = before.state.clone();
            let id = if message {
                &mut state.card.platform_message_id
            } else {
                &mut state.card.card_id
            };
            *id = Some(" \t\r\n\u{2003}".into());
            let damaged_raw = serde_json::to_string(&state)?;
            inject_card_state(store, key, &damaged_raw).await?;
            assert!(store.delivery_entity(key, &entity_key()).await.is_err());
            assert!(BotStateStore::new(path.to_path_buf()).db().await.is_err());
            assert_eq!(card_state_raw(store, key).await?, damaged_raw);
            assert_eq!(summary_version(store).await?, version);
            // 仅测试恢复故障注入的原字节；生产端口不得清空或修复这些身份。
            inject_card_state(store, key, &original_raw).await?;
            assert_eq!(
                store.delivery_entity(key, &entity_key()).await?,
                Some(before.clone())
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn unstarted_card_attempt_retires_without_halting_or_reusing_sequence()
    -> anyhow::Result<()> {
        let (directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let action = DeliveryAction::CreateCard {
            text: "hello".into(),
        };
        let attempt = store
            .register_test_card_attempt(&token, &entity_key(), action.clone())
            .await?;
        let original = attempt.intent().clone();
        let before = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert_eq!(before.state.in_flight.as_ref(), Some(&original));
        let version = summary_version(&store).await?;
        assert!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &original.operation_id,
                    DeliveryResult::NotStarted,
                )
                .await
                .is_err()
        );
        let existing = store
            .register_delivery_card_intent(
                &token,
                &entity_key(),
                before.ledger_version,
                action.clone(),
                |_, _| panic!("existing facts cannot freeze another request"),
            )
            .await?;
        assert!(matches!(existing, DeliveryCardAdmission::Existing));
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(before.clone())
        );
        assert_eq!(summary_version(&store).await?, version);
        let mut attempt = attempt.into_retirement();
        assert_eq!(
            store.retire_unstarted_delivery_card(&mut attempt).await?,
            SettlementOutcome::Applied
        );
        let retired = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert!(retired.state.in_flight.is_none());
        assert!(retired.state.halt.is_none());
        assert_eq!(retired.state.card, before.state.card);
        assert_eq!(retired.state.accepted, before.state.accepted);
        assert_eq!(retired.state.projected, before.state.projected);
        assert_eq!(
            retired.state.settled,
            Some(super::super::DeliverySettled {
                intent: original.clone(),
                result: DeliveryResult::NotStarted,
            })
        );
        assert!(derive_flags(retired.removed, &retired.state).pending());
        assert_eq!(
            store.delivery_pending(&key, None, 100).await?.pending.len(),
            1
        );
        assert!(matches!(
            item_platform(&retired, None),
            pl_protocol::studio::BotItemPlatform::Card { latest_operation }
                if latest_operation.result == pl_protocol::studio::BotPlatformResult::NotStarted {}
        ));
        let cold = BotStateStore::new(directory.path().join("state.sqlite"));
        cold.db().await?;
        assert_eq!(
            cold.delivery_entity(&key, &entity_key()).await?,
            Some(retired.clone())
        );
        let version = summary_version(&store).await?;
        assert_eq!(
            store.retire_unstarted_delivery_card(&mut attempt).await?,
            SettlementOutcome::AlreadySettled
        );
        assert_eq!(summary_version(&store).await?, version);
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(retired.clone())
        );
        // 本地 NotStarted 不是可由普通迟到路径澄清的 Unknown。
        assert!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &original.operation_id,
                    DeliveryResult::Created {
                        card_id: "impossible-late-card".into()
                    },
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(retired.clone())
        );
        assert_eq!(summary_version(&store).await?, version);

        // 原 cap 已成功消费，随后再失租：精确原 NotStarted 无后继仍只读幂等，
        // 不因回执重新授予写权或发送权，也不推进任何投递事实。
        assert!(store.release_delivery_claim(&token).await?);
        assert_eq!(
            store.renew_delivery_claim(&token).await?,
            DeliveryClaimOutcome::LostClaim
        );
        let pending = store.delivery_pending(&key, None, 100).await?;
        let cursor = store.delivery_cursor(&key).await?;
        let version = summary_version(&store).await?;
        assert_eq!(
            store.retire_unstarted_delivery_card(&mut attempt).await?,
            SettlementOutcome::AlreadySettled
        );
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(retired)
        );
        assert_eq!(store.delivery_pending(&key, None, 100).await?, pending);
        assert_eq!(store.delivery_cursor(&key).await?, cursor);
        assert_eq!(summary_version(&store).await?, version);

        let token = claimed(&store, &key).await;
        let mut successor = store
            .register_test_card_attempt(&token, &entity_key(), action)
            .await?;
        assert_ne!(successor.intent().operation_id, original.operation_id);
        assert_ne!(successor.intent().uuid, original.uuid);
        let before = store.delivery_entity(&key, &entity_key()).await?;
        let pending = store.delivery_pending(&key, None, 100).await?;
        let cursor = store.delivery_cursor(&key).await?;
        let version = summary_version(&store).await?;
        assert_eq!(
            store.retire_unstarted_delivery_card(&mut attempt).await?,
            SettlementOutcome::Superseded
        );
        assert_eq!(store.delivery_entity(&key, &entity_key()).await?, before);
        assert_eq!(store.delivery_pending(&key, None, 100).await?, pending);
        assert_eq!(store.delivery_cursor(&key).await?, cursor);
        assert_eq!(summary_version(&store).await?, version);
        successor.mark_request_started();
        let successor_intent = successor.intent().clone();
        let mut successor = successor.into_retirement();
        assert!(
            store
                .retire_unstarted_delivery_card(&mut successor)
                .await
                .is_err()
        );
        assert_eq!(store.delivery_entity(&key, &entity_key()).await?, before);
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &successor_intent.operation_id,
                DeliveryResult::Created {
                    card_id: "card-1".into(),
                },
            )
            .await?;
        let send = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::SendCard {
                    card_id: "card-1".into(),
                },
            )
            .await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &send.operation_id,
                DeliveryResult::Sent {
                    card_id: "card-1".into(),
                    message_id: "om_1".into(),
                },
            )
            .await?;
        store
            .merge_delivery_candidate(&token, &text_candidate("later", 2))
            .await?;
        let update = DeliveryAction::UpdateContent {
            card_id: "card-1".into(),
            text: "later".into(),
            final_content: true,
        };
        let unstarted = store
            .register_test_card_attempt(&token, &entity_key(), update.clone())
            .await?;
        let first_sequence = unstarted.intent().sequence;
        let card_before = store
            .delivery_entity(&key, &entity_key())
            .await?
            .unwrap()
            .state
            .card;
        let mut unstarted = unstarted.into_retirement();
        store.retire_unstarted_delivery_card(&mut unstarted).await?;
        assert_eq!(
            store
                .delivery_entity(&key, &entity_key())
                .await?
                .unwrap()
                .state
                .card,
            card_before
        );
        let mut accepted = store
            .register_test_card_attempt(&token, &entity_key(), update)
            .await?;
        assert_eq!(accepted.intent().sequence, first_sequence + 1);
        accepted.mark_request_started();
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &accepted.intent().operation_id,
                DeliveryResult::ContentAccepted {
                    card_id: "card-1".into(),
                },
            )
            .await?;
        let mut accepted = accepted.into_retirement();
        let final_entity = store.delivery_entity(&key, &entity_key()).await?;
        let final_pending = store.delivery_pending(&key, None, 100).await?;
        let final_cursor = store.delivery_cursor(&key).await?;
        let version = summary_version(&store).await?;
        for old in [&mut attempt, &mut unstarted] {
            assert_eq!(
                store.retire_unstarted_delivery_card(old).await?,
                SettlementOutcome::Superseded
            );
        }
        assert!(
            store
                .retire_unstarted_delivery_card(&mut accepted)
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            final_entity
        );
        assert_eq!(
            store.delivery_pending(&key, None, 100).await?,
            final_pending
        );
        assert_eq!(store.delivery_cursor(&key).await?, final_cursor);
        assert_eq!(summary_version(&store).await?, version);
        assert_eq!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &original.operation_id,
                    DeliveryResult::Created {
                        card_id: "old-card".into()
                    },
                )
                .await?,
            SettlementOutcome::Superseded
        );
        Ok(())
    }

    #[tokio::test]
    async fn unstarted_card_retirement_uses_live_claim_not_current_control_permission()
    -> anyhow::Result<()> {
        for phase in [BotAuthorizationPhase::Paused, BotAuthorizationPhase::Closed] {
            let (_directory, store) = store_with_frontend().await?;
            let key = DeliveryScopeKey::Frontend {
                authorization: authorization_id(),
            };
            let token = claimed(&store, &key).await;
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 1))
                .await?;
            let action = DeliveryAction::CreateCard {
                text: "hello".into(),
            };
            let attempt = store
                .register_test_card_attempt(&token, &entity_key(), action.clone())
                .await?;
            if phase == BotAuthorizationPhase::Closed {
                store
                    .close_sync_generation(
                        &authorization_id(),
                        pl_protocol::BotAudienceCloseReason::LocalClose,
                    )
                    .await?;
            } else {
                let mut auth = active_authorization();
                auth.phase = phase;
                auth.revision = 2;
                store.db().await?.execute_raw(statement(
                    "UPDATE bot_authorizations SET phase='paused',control_revision=2,state_json=?",
                    vec![serde_json::to_string(&auth)?.into()],
                )).await?;
            }
            assert!(matches!(
                store.renew_delivery_claim(&token).await?,
                DeliveryClaimOutcome::Stopped { .. }
            ));
            assert!(
                store
                    .register_test_card_admission(&token, &entity_key(), action)
                    .await
                    .is_err()
            );
            let mut attempt = attempt.into_retirement();
            assert_eq!(
                store.retire_unstarted_delivery_card(&mut attempt).await?,
                SettlementOutcome::Applied
            );
            let entity = store.delivery_entity(&key, &entity_key()).await?.unwrap();
            assert!(entity.state.halt.is_none());
            assert_eq!(
                entity.state.settled.as_ref().map(|settled| &settled.result),
                Some(&DeliveryResult::NotStarted)
            );
            assert_eq!(
                store.delivery_pending(&key, None, 100).await?.pending.len(),
                1
            );
            assert!(store.release_delivery_claim(&token).await?);
            assert!(matches!(
                store.claim_delivery_scope(&key, "owner-b").await?,
                DeliveryClaimOutcome::Stopped { .. }
            ));
        }
        Ok(())
    }

    #[tokio::test]
    async fn stale_card_attempt_cannot_change_unknown_or_accepted_facts() -> anyhow::Result<()> {
        for loss in ["released", "expired", "stopped", "revision", "request"] {
            let (_directory, store) = store_with_frontend().await?;
            let key = DeliveryScopeKey::Frontend {
                authorization: authorization_id(),
            };
            let token = claimed(&store, &key).await;
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 1))
                .await?;
            let attempt = store
                .register_test_card_attempt(
                    &token,
                    &entity_key(),
                    DeliveryAction::CreateCard {
                        text: "hello".into(),
                    },
                )
                .await?;
            let original = attempt.intent().clone();
            let mut attempt = attempt.into_retirement();
            match loss {
                "released" => {
                    store.release_delivery_claim(&token).await?;
                    let successor = claimed(&store, &key).await;
                    assert_ne!(successor.lease_generation, token.lease_generation);
                }
                "expired" => {
                    store
                        .db()
                        .await?
                        .execute_unprepared("UPDATE bot_delivery_claims SET expires_at=0")
                        .await?;
                }
                "stopped" => {
                    store
                        .stop_delivery_scope(&key, "permanent local stop")
                        .await?;
                }
                "revision" => {
                    store
                        .merge_delivery_candidate(&token, &text_candidate("later", 2))
                        .await?;
                }
                "request" => {
                    // 即使 owner、代次、operation、UUID、动作与版本均相同，也不能拿另一份
                    // 冻结材料替代原 cap。合法 typed 材料用于注入这一精确身份冲突。
                    let mut entity = store.delivery_entity(&key, &entity_key()).await?.unwrap();
                    let intent = entity.state.in_flight.as_mut().unwrap();
                    intent.request = super::super::FrozenDeliveryRequest::new(
                        intent.request.target(),
                        "{\"different\":true}".into(),
                    )?;
                    intent.request_hash = intent.request.hash()?;
                    store.db().await?.execute_raw(statement(
                        "UPDATE bot_delivery_items SET state_json=? WHERE scope_key=? AND entity_key=?",
                        vec![serde_json::to_string(&entity.state)?.into(), key.storage_key()?.into(), entity_key().storage_key()?.into()],
                    )).await?;
                }
                _ => unreachable!(),
            }
            let before = store.delivery_entity(&key, &entity_key()).await?;
            let pending = store.delivery_pending(&key, None, 100).await?;
            let version = summary_version(&store).await?;
            assert_eq!(
                store.retire_unstarted_delivery_card(&mut attempt).await?,
                SettlementOutcome::Superseded
            );
            assert_eq!(
                store.retire_unstarted_delivery_card(&mut attempt).await?,
                SettlementOutcome::Superseded
            );
            assert_eq!(store.delivery_entity(&key, &entity_key()).await?, before);
            assert_eq!(store.delivery_pending(&key, None, 100).await?, pending);
            assert_eq!(summary_version(&store).await?, version);
            // 恢复仍走保守 Unknown，不从旧 cap 或当前同 owner 的 Intent 推断未启动。
            store.release_delivery_claim(&token).await?;
            store
                .retire_orphaned_delivery_intent(
                    &key,
                    &entity_key(),
                    &original.operation_id,
                    "lost original attempt ownership",
                )
                .await?;
            let unknown = store.delivery_entity(&key, &entity_key()).await?;
            assert!(
                store
                    .settle_delivery_card_result(
                        &key,
                        &entity_key(),
                        &original.operation_id,
                        DeliveryResult::NotStarted
                    )
                    .await
                    .is_err()
            );
            assert_eq!(
                store.retire_unstarted_delivery_card(&mut attempt).await?,
                SettlementOutcome::Superseded
            );
            assert_eq!(store.delivery_entity(&key, &entity_key()).await?, unknown);
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &original.operation_id,
                    DeliveryResult::Created {
                        card_id: "late-card".into(),
                    },
                )
                .await?;
            let accepted = store.delivery_entity(&key, &entity_key()).await?;
            assert_eq!(
                store.retire_unstarted_delivery_card(&mut attempt).await?,
                SettlementOutcome::Superseded
            );
            assert_eq!(store.delivery_entity(&key, &entity_key()).await?, accepted);
        }
        Ok(())
    }

    #[tokio::test]
    async fn unconfirmed_card_attempt_keeps_exact_identity_and_retry_responsibility()
    -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let action = DeliveryAction::CreateCard {
            text: "hello".into(),
        };
        // 真实事务成功，仅在测试的返回值边界丢失确认；不伪造 cap、DB 或 Migrator。
        let (admission, original) = match store
            .register_test_card_admission(&token, &entity_key(), action.clone())
            .await?
        {
            DeliveryCardAdmission::Confirmed(attempt) => {
                let original = attempt.intent().clone();
                let unconfirmed = DeliveryCardAdmission::Unconfirmed {
                    attempt: attempt.into_retirement(),
                    error: FeishuError::new(
                        FeishuErrorKind::Unavailable,
                        "controlled lost commit acknowledgement",
                        true,
                        None,
                    ),
                };
                (unconfirmed, original)
            }
            other => panic!("new intent was not committed: {other:?}"),
        };
        let DeliveryCardAdmission::Unconfirmed { mut attempt, .. } = admission else {
            unreachable!()
        };
        let before = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        let version = summary_version(&store).await?;
        store
            .db()
            .await?
            .execute_unprepared("ALTER TABLE bot_delivery_items RENAME TO unavailable_card_items")
            .await?;
        assert!(
            store
                .retire_unstarted_delivery_card(&mut attempt)
                .await
                .is_err()
        );
        store
            .db()
            .await?
            .execute_unprepared("ALTER TABLE unavailable_card_items RENAME TO bot_delivery_items")
            .await?;
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(before.clone())
        );
        assert_eq!(summary_version(&store).await?, version);
        store.db().await?.execute_unprepared("CREATE TRIGGER fail_unstarted_retirement BEFORE UPDATE OF summary_version ON bot_audience_origins BEGIN SELECT RAISE(ABORT,'controlled unstarted retirement fault'); END").await?;
        assert!(
            store
                .retire_unstarted_delivery_card(&mut attempt)
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(before)
        );
        assert_eq!(summary_version(&store).await?, version);
        store
            .db()
            .await?
            .execute_unprepared("DROP TRIGGER fail_unstarted_retirement")
            .await?;
        assert_eq!(
            store.retire_unstarted_delivery_card(&mut attempt).await?,
            SettlementOutcome::Applied
        );
        let retired = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert_eq!(
            retired
                .state
                .settled
                .as_ref()
                .map(|settled| &settled.intent),
            Some(&original)
        );
        let successor = store
            .register_test_card_attempt(&token, &entity_key(), action)
            .await?;
        let mut successor = successor.into_retirement();
        let successor_before = store.delivery_entity(&key, &entity_key()).await?;
        assert_eq!(
            store.retire_unstarted_delivery_card(&mut attempt).await?,
            SettlementOutcome::Superseded
        );
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            successor_before
        );
        assert_eq!(
            store.retire_unstarted_delivery_card(&mut successor).await?,
            SettlementOutcome::Applied
        );
        Ok(())
    }

    #[tokio::test]
    async fn failed_card_intent_commit_returns_original_unconfirmed_attempt_without_writes()
    -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let before = store.delivery_entity(&key, &entity_key()).await?;
        let version = summary_version(&store).await?;
        // 延迟 FK 直到 COMMIT 才报错，覆盖正式 register 的 Unconfirmed 分支。
        // 两个探针表和 trigger 仅由测试建立，不进入 schema 或生产端口。
        store.db().await?.execute_unprepared(
            "CREATE TABLE card_attempt_commit_parent(id INTEGER PRIMARY KEY);
             CREATE TABLE card_attempt_commit_probe(parent_id INTEGER REFERENCES card_attempt_commit_parent(id) DEFERRABLE INITIALLY DEFERRED);
             CREATE TRIGGER fail_card_attempt_commit AFTER UPDATE OF state_json ON bot_delivery_items
             BEGIN INSERT INTO card_attempt_commit_probe(parent_id) VALUES(1); END;"
        ).await?;
        let admission = store
            .register_test_card_admission(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        let DeliveryCardAdmission::Unconfirmed { mut attempt, error } = admission else {
            panic!("a commit-time failure must retain the original attempt");
        };
        assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
        assert!(
            error
                .to_string()
                .to_ascii_lowercase()
                .contains("foreign key")
        );
        assert_eq!(store.delivery_entity(&key, &entity_key()).await?, before);
        assert_eq!(summary_version(&store).await?, version);
        assert_eq!(
            store.retire_unstarted_delivery_card(&mut attempt).await?,
            SettlementOutcome::Superseded
        );
        assert_eq!(store.delivery_entity(&key, &entity_key()).await?, before);
        assert_eq!(summary_version(&store).await?, version);
        store.db().await?.execute_unprepared(
            "DROP TRIGGER fail_card_attempt_commit; DROP TABLE card_attempt_commit_probe; DROP TABLE card_attempt_commit_parent;"
        ).await?;
        Ok(())
    }

    #[tokio::test]
    async fn claim_is_independent_and_fences_stale_writers() -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        assert_eq!(
            store.claim_delivery_scope(&key, "owner-b").await?,
            DeliveryClaimOutcome::Busy {
                expires_at: token.expires_at
            }
        );
        assert!(matches!(
            store.renew_delivery_claim(&token).await?,
            DeliveryClaimOutcome::Acquired(renewed) if renewed.expires_at >= token.expires_at
        ));
        assert!(store.release_delivery_claim(&token).await?);
        let next = claimed(&store, &key).await;
        assert!(next.lease_generation > token.lease_generation);
        // 旧代次的持有者不能写入，也不能自认续约。
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 1))
                .await?,
            MergeOutcome::Fenced
        );
        assert_eq!(
            store.renew_delivery_claim(&token).await?,
            DeliveryClaimOutcome::LostClaim
        );
        assert_eq!(
            store
                .merge_delivery_candidate(&next, &text_candidate("hello", 1))
                .await?,
            MergeOutcome::Applied { item_revision: 1 }
        );
        Ok(())
    }

    #[tokio::test]
    async fn merge_only_updates_canonical_fields() -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 1))
                .await?,
            MergeOutcome::Applied { item_revision: 1 }
        );
        // 同一修订同一内容幂等；同一修订不同内容拒绝；旧修订不覆盖。
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 1))
                .await?,
            MergeOutcome::Unchanged { item_revision: 1 }
        );
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("other", 1))
                .await?,
            MergeOutcome::Conflict
        );
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 2))
                .await?,
            MergeOutcome::Applied { item_revision: 2 }
        );
        // 规范顺序必须为正，不能把“未知顺序”写成 0。
        let mut zero_order = text_candidate("hello", 3);
        zero_order.item_order = 0;
        assert!(
            store
                .merge_delivery_candidate(&token, &zero_order)
                .await
                .is_err()
        );
        // 实体仍是 canonical 状态，平台事实尚未产生。
        let entity = store
            .delivery_entity(&key, &entity_key())
            .await?
            .expect("entity");
        assert_eq!(entity.revision(), 2);
        assert_eq!(entity.item_order, Some(1));
        assert_eq!(entity.state.accepted, BotItemPresentation::None {});
        assert!(entity.state.in_flight.is_none());
        Ok(())
    }

    #[tokio::test]
    async fn card_intent_waits_for_a_matching_result() -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;

        let create = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        assert_eq!(create.sequence, 0);
        assert_eq!(create.uuid.len(), 32);
        // 同一动作只读回原意图，不产生第二个 UUID，也不再发放本次启动证明。
        let again = store
            .register_test_card_admission(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        let DeliveryCardAdmission::Existing = again else {
            panic!("an existing intent must not mint another attempt");
        };
        let again = store
            .delivery_entity(&key, &entity_key())
            .await?
            .expect("existing entity")
            .state
            .in_flight
            .expect("original in-flight intent");
        assert_eq!(again, create);
        blank_accepted_ids_preserve_inflight(&store, &key, &create).await?;
        // 结果必须匹配动作种类：Create 的 Sent 不是合法结算。
        assert!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &create.operation_id,
                    DeliveryResult::Sent {
                        card_id: "card-1".to_string(),
                        message_id: "om_1".to_string(),
                    },
                )
                .await
                .is_err()
        );
        assert_eq!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &create.operation_id,
                    DeliveryResult::Created {
                        card_id: "card-1".to_string(),
                    },
                )
                .await?,
            SettlementOutcome::Applied
        );
        // 迟到重复结算幂等，不同结果固定冲突。
        assert_eq!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &create.operation_id,
                    DeliveryResult::Created {
                        card_id: "card-1".to_string(),
                    },
                )
                .await?,
            SettlementOutcome::AlreadySettled
        );
        assert!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &create.operation_id,
                    DeliveryResult::Created {
                        card_id: "card-2".to_string(),
                    },
                )
                .await
                .is_err()
        );

        let send = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::SendCard {
                    card_id: "card-1".to_string(),
                },
            )
            .await?;
        blank_accepted_ids_preserve_inflight(&store, &key, &send).await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &send.operation_id,
                DeliveryResult::Sent {
                    card_id: "card-1".to_string(),
                    message_id: "om_1".to_string(),
                },
            )
            .await?;
        let content = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::UpdateContent {
                    card_id: "card-1".to_string(),
                    text: "hello".into(),
                    final_content: true,
                },
            )
            .await?;
        assert!(content.sequence > send.sequence);
        blank_accepted_ids_preserve_inflight(&store, &key, &content).await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &content.operation_id,
                DeliveryResult::ContentAccepted {
                    card_id: "card-1".to_string(),
                },
            )
            .await?;
        blank_stored_card_ids_refuse_cold_read(
            &store,
            &key,
            &_directory.path().join("state.sqlite"),
        )
        .await?;
        let entity = store
            .delivery_entity(&key, &entity_key())
            .await?
            .expect("entity");
        assert_eq!(
            entity.state.accepted,
            BotItemPresentation::Text {
                revision: 1,
                integrity: BotTextIntegrity::Full,
                saved: true,
            }
        );
        // 已结算的当前修订不再属于未完成索引。
        assert!(
            store
                .delivery_pending(&key, None, 100)
                .await?
                .pending
                .is_empty()
        );
        let original_card = entity.state.card.clone();
        let original_http = entity.state.settled.clone();
        for revision in [2, 3] {
            let mut candidate = text_candidate("hello", revision);
            if let DeliveryCandidateContent::Text { saved, .. } = &mut candidate.content {
                *saved = false;
            }
            store.merge_delivery_candidate(&token, &candidate).await?;
            let before = store.delivery_entity(&key, &entity_key()).await?.unwrap();
            assert!(derive_flags(before.removed, &before.state).pending());
            assert!(
                store
                    .confirm_unchanged_delivery_text(
                        &token,
                        &entity_key(),
                        before.ledger_version - 1
                    )
                    .await
                    .is_err()
            );
            let mut stale = token.clone();
            stale.lease_generation += 1;
            assert!(
                store
                    .confirm_unchanged_delivery_text(&stale, &entity_key(), before.ledger_version)
                    .await
                    .is_err()
            );
            if revision == 2 {
                store.db().await?.execute_unprepared("CREATE TRIGGER fail_text_association BEFORE UPDATE OF summary_version ON bot_audience_origins BEGIN SELECT RAISE(ABORT,'controlled association fault'); END").await?;
                assert!(
                    store
                        .confirm_unchanged_delivery_text(
                            &token,
                            &entity_key(),
                            before.ledger_version
                        )
                        .await
                        .is_err()
                );
                assert_eq!(
                    store.delivery_entity(&key, &entity_key()).await?,
                    Some(before.clone())
                );
                store
                    .db()
                    .await?
                    .execute_unprepared("DROP TRIGGER fail_text_association")
                    .await?;
            }
            assert_eq!(
                store
                    .confirm_unchanged_delivery_text(&token, &entity_key(), before.ledger_version)
                    .await?,
                SettlementOutcome::Applied
            );
            let associated = store.delivery_entity(&key, &entity_key()).await?.unwrap();
            assert_eq!(
                associated.state.accepted,
                BotItemPresentation::Text {
                    revision,
                    integrity: BotTextIntegrity::Full,
                    saved: false
                }
            );
            assert_eq!(associated.state.card, original_card);
            assert_eq!(associated.state.settled, original_http);
            assert!(associated.state.in_flight.is_none());
            assert!(
                store
                    .delivery_pending(&key, None, 100)
                    .await?
                    .pending
                    .is_empty()
            );
            assert_eq!(
                store
                    .confirm_unchanged_delivery_text(
                        &token,
                        &entity_key(),
                        associated.ledger_version
                    )
                    .await?,
                SettlementOutcome::AlreadySettled
            );
            assert_eq!(
                store.delivery_entity(&key, &entity_key()).await?,
                Some(associated)
            );
        }
        // 同 revision 的 Saved 推进只改本地关联，不伪造新的 HTTP Saved/完整性事实。
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 3))
            .await?;
        let saved = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        store
            .confirm_unchanged_delivery_text(&token, &entity_key(), saved.ledger_version)
            .await?;
        let saved = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert_eq!(
            saved.state.accepted,
            BotItemPresentation::Text {
                revision: 3,
                integrity: BotTextIntegrity::Full,
                saved: true
            }
        );
        assert_eq!(saved.state.card, original_card);
        assert_eq!(saved.state.settled, original_http);
        let mut stale_saved = text_candidate("hello", 3);
        if let DeliveryCandidateContent::Text { saved, .. } = &mut stale_saved.content {
            *saved = false;
        }
        assert_eq!(
            store.merge_delivery_candidate(&token, &stale_saved).await?,
            MergeOutcome::Unchanged { item_revision: 3 }
        );
        assert_eq!(
            store
                .confirm_unchanged_delivery_text(&token, &entity_key(), saved.ledger_version)
                .await?,
            SettlementOutcome::AlreadySettled
        );
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(saved)
        );
        let pending = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::UpdateContent {
                    card_id: "card-1".into(),
                    text: "hello".into(),
                    final_content: true,
                },
            )
            .await?;
        let waiting = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert!(
            store
                .confirm_unchanged_delivery_text(&token, &entity_key(), waiting.ledger_version)
                .await
                .is_err()
        );
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &pending.operation_id,
                DeliveryResult::Unknown {
                    diagnostic: Some("late confirmation pending".into()),
                },
            )
            .await?;
        let unknown = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert!(
            store
                .confirm_unchanged_delivery_text(&token, &entity_key(), unknown.ledger_version)
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(unknown)
        );
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 4))
            .await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &pending.operation_id,
                DeliveryResult::ContentAccepted {
                    card_id: "card-1".into(),
                },
            )
            .await?;
        let late = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert_eq!(late.state.settled.as_ref().unwrap().intent, pending);
        assert_eq!(
            late.state.accepted,
            BotItemPresentation::Text {
                revision: 3,
                integrity: BotTextIntegrity::Full,
                saved: true
            }
        );
        store
            .confirm_unchanged_delivery_text(&token, &entity_key(), late.ledger_version)
            .await?;
        let mut truncated = text_candidate("hello", 5);
        if let DeliveryCandidateContent::Text { integrity, .. } = &mut truncated.content {
            *integrity = BotTextIntegrity::Truncated;
        }
        for candidate in [truncated, text_candidate("different body", 6)] {
            store.merge_delivery_candidate(&token, &candidate).await?;
            let changed = store.delivery_entity(&key, &entity_key()).await?.unwrap();
            assert!(
                store
                    .confirm_unchanged_delivery_text(&token, &entity_key(), changed.ledger_version)
                    .await
                    .is_err()
            );
            assert_eq!(
                store.delivery_entity(&key, &entity_key()).await?,
                Some(changed)
            );
        }
        store
            .merge_delivery_candidate(&token, &text_candidate("", 7))
            .await?;
        let empty = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        let clear = DeliveryAction::UpdateContent {
            card_id: "card-1".into(),
            text: String::new(),
            final_content: true,
        };
        for body in [String::new(), "x".repeat(30_001)] {
            assert!(
                store
                    .register_delivery_card_intent(
                        &token,
                        &entity_key(),
                        empty.ledger_version,
                        clear.clone(),
                        |_, _| super::super::FrozenDeliveryRequest::new(
                            super::super::DeliveryRequestTarget::ElementContent,
                            body
                        )
                    )
                    .await
                    .is_err()
            );
            assert_eq!(
                store.delivery_entity(&key, &entity_key()).await?,
                Some(empty.clone())
            );
        }
        let clear = store
            .register_test_card_intent(&token, &entity_key(), clear)
            .await?;
        assert_eq!(clear.action.text(), Some(""));
        assert!(!clear.request.body().is_empty());
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &clear.operation_id,
                DeliveryResult::ContentAccepted {
                    card_id: "card-1".into(),
                },
            )
            .await?;
        let reject = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::UpdateContent {
                    card_id: "card-1".into(),
                    text: String::new(),
                    final_content: true,
                },
            )
            .await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &reject.operation_id,
                DeliveryResult::Rejected {
                    diagnostic: "explicit rejection".into(),
                },
            )
            .await?;
        let rejected = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert!(
            store
                .confirm_unchanged_delivery_text(&token, &entity_key(), rejected.ledger_version)
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &entity_key()).await?,
            Some(rejected)
        );
        let mut second = text_candidate("", 1);
        second.entity = DeliveryEntityKey::TextItem {
            item_id: "empty-host-item".into(),
        };
        second.item_order = 2;
        store.merge_delivery_candidate(&token, &second).await?;
        let create = store
            .register_test_card_intent(
                &token,
                &second.entity,
                DeliveryAction::CreateCard {
                    text: String::new(),
                },
            )
            .await?;
        assert_eq!(create.action.text(), Some(""));
        assert!(!create.request.body().is_empty());
        store
            .settle_delivery_card_result(
                &key,
                &second.entity,
                &create.operation_id,
                DeliveryResult::Created {
                    card_id: "empty-card".into(),
                },
            )
            .await?;
        let send = store
            .register_test_card_intent(
                &token,
                &second.entity,
                DeliveryAction::SendCard {
                    card_id: "empty-card".into(),
                },
            )
            .await?;
        store
            .settle_delivery_card_result(
                &key,
                &second.entity,
                &send.operation_id,
                DeliveryResult::Sent {
                    card_id: "empty-card".into(),
                    message_id: "empty-message".into(),
                },
            )
            .await?;
        // 独立注入需处理状态，不能靠相同正文/已接受关系绕过它。
        let mut attention = store.delivery_entity(&key, &second.entity).await?.unwrap();
        let previous = attention.ledger_version;
        attention.state.card.lifecycle =
            Some(crate::bots::storage::card::CardLifecycle::NeedsAttention);
        attention.ledger_version += 1;
        let tx = store.db().await?.begin().await?;
        super::super::records::write_entity(&tx, &attention, Some(previous)).await?;
        sync_pending(&tx, &attention).await?;
        tx.commit().await?;
        assert!(
            store
                .confirm_unchanged_delivery_text(&token, &second.entity, attention.ledger_version)
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &second.entity).await?,
            Some(attention)
        );
        // 新 Accepted 身份同样原值保存，不修剪合法首尾空白，也不新增 message 长度上限。
        let (directory, store) = store_with_frontend().await?;
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let card_id = " \tcard-original\u{2003}".to_string();
        let message_id = format!("\t{}\u{2003}", "om".repeat(160));
        let create = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &create.operation_id,
                DeliveryResult::Created {
                    card_id: card_id.clone(),
                },
            )
            .await?;
        let send = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::SendCard {
                    card_id: card_id.clone(),
                },
            )
            .await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &send.operation_id,
                DeliveryResult::Sent {
                    card_id: card_id.clone(),
                    message_id: message_id.clone(),
                },
            )
            .await?;
        let settings = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::UpdateSettings {
                    card_id: card_id.clone(),
                    streaming: false,
                    lifecycle: crate::bots::storage::card::CardLifecycle::Cancelled,
                    recovery: false,
                },
            )
            .await?;
        blank_accepted_ids_preserve_inflight(&store, &key, &settings).await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &settings.operation_id,
                DeliveryResult::SettingsAccepted {
                    card_id: card_id.clone(),
                    streaming: false,
                },
            )
            .await?;
        blank_stored_card_ids_refuse_cold_read(
            &store,
            &key,
            &directory.path().join("state.sqlite"),
        )
        .await?;
        let preserved = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert_eq!(preserved.state.card.card_id, Some(card_id));
        assert_eq!(preserved.state.card.platform_message_id, Some(message_id));
        Ok(())
    }

    #[tokio::test]
    async fn unknown_halts_new_actions_but_keeps_started_results() -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let create = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        // 撤权/停止后仍保存已启动请求的真实结果。
        assert!(
            store
                .stop_delivery_scope(&key, "authorization closed")
                .await?
        );
        assert!(matches!(
            store.renew_delivery_claim(&token).await?,
            DeliveryClaimOutcome::Stopped { .. }
        ));
        assert_eq!(
            store.claim_delivery_scope(&key, "owner-b").await?,
            DeliveryClaimOutcome::Stopped {
                reason: "authorization closed".to_string()
            }
        );
        assert!(
            store
                .register_test_card_intent(
                    &token,
                    &entity_key(),
                    DeliveryAction::CreateCard {
                        text: "hello".into()
                    }
                )
                .await
                .is_err()
        );
        assert_eq!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &create.operation_id,
                    DeliveryResult::Unknown {
                        diagnostic: Some("timeout".to_string()),
                    },
                )
                .await?,
            SettlementOutcome::Applied
        );
        let entity = store
            .delivery_entity(&key, &entity_key())
            .await?
            .expect("entity");
        assert!(matches!(
            entity.state.halt,
            Some(DeliveryHalt::Unknown { .. })
        ));
        // Unknown 之后不得再派发新动作，也不能换成新 UUID 重试。
        assert!(
            store
                .register_test_card_intent(
                    &token,
                    &entity_key(),
                    DeliveryAction::CreateCard {
                        text: "hello".into()
                    }
                )
                .await
                .is_err()
        );
        Ok(())
    }

    #[tokio::test]
    async fn orphaned_intent_becomes_unknown_only_after_the_lease_is_gone() -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let attempt = store
            .register_test_card_attempt(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        let create = attempt.intent().clone();
        // 本次证明丢失后，冷开也不能根据 Intent 重新得出“未启动”。
        drop(attempt);
        // 冷开只能读回事实，即使仍有同 owner 的有效租约也不能从 Intent mint 新 cap。
        let cold = BotStateStore::new(_directory.path().join("state.sqlite"));
        cold.db().await?;
        let entity = cold.delivery_entity(&key, &entity_key()).await?.unwrap();
        let admission = cold
            .register_delivery_card_intent(
                &token,
                &entity_key(),
                entity.ledger_version,
                create.action.clone(),
                |_, _| panic!("cold in-flight facts do not grant another request"),
            )
            .await?;
        assert!(matches!(admission, DeliveryCardAdmission::Existing));
        assert_eq!(
            cold.delivery_entity(&key, &entity_key())
                .await?
                .unwrap()
                .state
                .in_flight,
            Some(create.clone())
        );
        // 原租约仍活跃：旁观者不能把它改成 Unknown。
        assert!(
            store
                .retire_orphaned_delivery_intent(
                    &key,
                    &entity_key(),
                    &create.operation_id,
                    "runtime restart"
                )
                .await
                .is_err()
        );
        store.release_delivery_claim(&token).await?;
        let _next = claimed(&store, &key).await;
        assert_eq!(
            store
                .retire_orphaned_delivery_intent(
                    &key,
                    &entity_key(),
                    &create.operation_id,
                    "runtime restart left an unconfirmed intent"
                )
                .await?,
            SettlementOutcome::Applied
        );
        let entity = store
            .delivery_entity(&key, &entity_key())
            .await?
            .expect("entity");
        assert!(matches!(
            entity.state.halt,
            Some(DeliveryHalt::Unknown { .. })
        ));
        // 不是新操作：原操作身份仍留在已结算事实里。
        assert_eq!(
            entity
                .state
                .settled
                .as_ref()
                .map(|settled| settled.intent.operation_id.as_str()),
            Some(create.operation_id.as_str())
        );
        Ok(())
    }

    #[tokio::test]
    async fn controlled_binding_creates_a_scope_only_claimable_after_activation()
    -> anyhow::Result<()> {
        use crate::bots::storage::target::{TargetClaim, TargetKind};
        use crate::bots::storage::{BindingOperation, FirstStart};

        let directory = tempfile::tempdir()?;
        let store = BotStateStore::new(directory.path().join("state.sqlite"));
        store.binding_for_chat(CHAT, BOT, PROJECT).await?;
        let claim = TargetClaim::from_operation(
            BOT,
            APP,
            PROJECT,
            CHAT,
            &creation(),
            "op1",
            TargetKind::Group,
        );
        let operation = BindingOperation {
            operation_id: "op1".to_string(),
            bot_id: BOT.to_string(),
            chat_id: CHAT.to_string(),
            content_hash: "hash".to_string(),
            expected_revision: 0,
            creation_id: creation(),
            thread_id: None,
            target: claim.freeze(1),
        };
        store
            .begin_binding_operation(CHAT, 0, PROJECT, &operation)
            .await?;
        let first = FirstStart {
            bot_id: BOT.to_string(),
            app_id: APP.to_string(),
            operation_id: "op1".to_string(),
        };
        store
            .bind_thread(CHAT, THREAD, &creation(), PROJECT, Some(&first))
            .await?;

        // 真实受控入口已建立同事务作用域，冷读取即可见。
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let scope = store
            .delivery_scope(&key)
            .await?
            .expect("the controlled binding created its scope");
        assert_eq!(scope.thread_id, THREAD);
        assert!(!scope.needs_recovery);
        assert!(matches!(
            &scope.origin,
            DeliveryScopeOrigin::Frontend { authorization } if *authorization == authorization_id()
        ));
        // PendingStart：范围存在但没有任何可认领资格，也不产生新平台写入。
        assert!(matches!(
            store.claim_delivery_scope(&key, "owner-a").await?,
            DeliveryClaimOutcome::Stopped { .. }
        ));
        // 激活从原授权读取已保存起点后，同一代才可认领。
        let head = store
            .audience_scope(THREAD, BOT)
            .await?
            .expect("audience scope")
            .head
            .expect("pending head");
        assert_eq!(head.phase, BotAuthorizationPhase::PendingStart);
        let receipt = AudienceStartReceipt {
            version: 1,
            intent: head.intent.clone(),
            extension_revision: 1,
            sequence: 1,
            excluded_turn_id: None,
        };
        let activated = store.activate_sync(&receipt).await?;
        assert!(activated.changed);
        assert_eq!(activated.authorization.phase, BotAuthorizationPhase::Active);
        let reopened_scope = store.delivery_scope(&key).await?.expect("scope retained");
        assert_eq!(reopened_scope.binding_revision, scope.binding_revision);
        let token = claimed(&store, &key).await;
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 1))
                .await?,
            MergeOutcome::Applied { item_revision: 1 }
        );
        // 关闭不删除作用域或未知义务，只封闭新写。
        store.stop_delivery_scope(&key, "local close").await?;
        assert!(store.delivery_scope(&key).await?.is_some());
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 2))
                .await?,
            MergeOutcome::Fenced
        );
        Ok(())
    }

    async fn store_with_inbound_target(
        target: crate::bots::storage::target::TargetKind,
    ) -> anyhow::Result<(
        tempfile::TempDir,
        BotStateStore,
        crate::bots::storage::card::CardBinding,
    )> {
        use crate::bots::storage::FrozenInbound;
        use crate::bots::storage::card::CardBinding;
        use crate::bots::storage::target::{TargetKind, TargetProof};
        let (directory, store) = store_with_frontend().await?;
        let (chat_kind, open_id) = match &target {
            TargetKind::Group => ("group", String::new()),
            TargetKind::Direct { open_id } => ("direct", open_id.clone()),
        };
        let db = store.db().await?;
        db.execute_raw(statement(
            "UPDATE bot_audience_origins SET target_json=?",
            vec![TargetProof::Legacy { target }.encode()?.into()],
        ))
        .await?;
        let admit_tasks = crate::bots::occupancy::OccupancyTasks::new();
        let mut admit_budget = admit_tasks.text_budget(0)?;
        store
            .admit_inbound(
                FrozenInbound {
                    bot_id: BOT.into(),
                    chat_id: CHAT.into(),
                    message_id: "old-message".into(),
                    content_hash: "original-hash".into(),
                    text: "input".into(),
                    attachments: vec![],
                    open_id,
                    chat_kind: chat_kind.into(),
                    app_id: APP.into(),
                    project_id: PROJECT.into(),
                    creation_id: creation(),
                    binding_revision: 1,
                    watch_input: String::new(),
                },
                &mut admit_budget,
            )
            .await?;
        let inbound_identity = format!("{BOT}:{CHAT}:old-message");
        let binding = CardBinding {
            bot_id: BOT.into(),
            chat_id: CHAT.into(),
            message_id: "old-message".into(),
            thread_id: THREAD.into(),
            original_input: format!("bot:{inbound_identity}"),
        };
        Ok((directory, store, binding))
    }

    async fn store_with_legacy_fixture(
        target: crate::bots::storage::target::TargetKind,
    ) -> anyhow::Result<(
        tempfile::TempDir,
        BotStateStore,
        DeliveryScope,
        DeliveryEntityKey,
    )> {
        use super::super::DeliveryCard;
        let (directory, store, binding) = store_with_inbound_target(target).await?;
        let db = store.db().await?;
        let inbound_identity = format!("{BOT}:{CHAT}:old-message");
        let facts = super::super::legacy::facts(
            db,
            &inbound_identity,
            &binding,
            &binding.original_input,
            Some("turn-1"),
        )
        .await?;
        assert!(facts.origin.needs_recovery.is_none());
        let scope = DeliveryScope {
            key: DeliveryScopeKey::LegacyFinal { inbound_identity },
            bot_id: BOT.into(),
            chat_id: CHAT.into(),
            thread_id: THREAD.into(),
            app_id: APP.into(),
            project_id: PROJECT.into(),
            creation_id: creation(),
            binding_revision: 1,
            origin: DeliveryScopeOrigin::LegacyFinal {
                legacy: Box::new(facts.origin),
            },
            needs_recovery: false,
        };
        let entity = DeliveryEntity {
            scope: scope.key.clone(),
            entity: DeliveryEntityKey::LegacyFinal {
                entity_id: binding.reply_operation(),
            },
            turn_id: Some("turn-1".into()),
            item_order: None,
            saved: false,
            removed: false,
            state: DeliveryEntityState {
                content: DeliveryContent::Legacy {
                    final_only: true,
                    presentation: None,
                },
                projected: BotItemPresentation::None {},
                accepted: BotItemPresentation::None {},
                card: DeliveryCard::default(),
                file_operation: None,
                in_flight: None,
                settled: None,
                halt: None,
            },
            ledger_version: 1,
            updated_at: 1,
        };
        let tx = db.begin().await?;
        insert_scope_row(&tx, &scope).await?;
        insert_cursor_row(&tx, &scope.key).await?;
        insert_entity_row(&tx, &entity).await?;
        sync_pending(&tx, &entity).await?;
        tx.commit().await?;
        Ok((directory, store, scope, entity.entity))
    }

    async fn remove_frontend_head(store: &BotStateStore) -> anyhow::Result<()> {
        let db = store.db().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        }
        .storage_key()?;
        for table in [
            "bot_delivery_pending",
            "bot_delivery_claims",
            "bot_delivery_items",
            "bot_delivery_cursors",
            "bot_delivery_scopes",
        ] {
            db.execute_raw(statement(
                &format!("DELETE FROM {table} WHERE scope_key=?"),
                vec![key.clone().into()],
            ))
            .await?;
        }
        db.execute_unprepared("DELETE FROM bot_sync_operations")
            .await?;
        db.execute_unprepared("DELETE FROM bot_authorizations")
            .await?;
        Ok(())
    }

    /// 模拟迁移保留的来源不足材料；仍有原范围身份和 cursor，不伪造可认领资格。
    async fn insert_recovery_legacy(
        store: &BotStateStore,
        mut scope: DeliveryScope,
        identity: &str,
    ) -> anyhow::Result<DeliveryScope> {
        scope.key = DeliveryScopeKey::LegacyFinal {
            inbound_identity: identity.into(),
        };
        let DeliveryScopeOrigin::LegacyFinal { legacy } = &mut scope.origin else {
            unreachable!()
        };
        legacy.inbound_identity = identity.into();
        legacy.original_input_id = format!("bot:{identity}");
        legacy.watch_input = legacy.original_input_id.clone();
        legacy.source = None;
        legacy.admission = None;
        legacy.resumable = false;
        legacy.needs_recovery = Some("original legacy admission needs recovery".into());
        scope.needs_recovery = true;
        let tx = store.db().await?.begin().await?;
        if audience::read_origin(&tx, &scope.thread_id)
            .await?
            .is_none()
        {
            tx.execute_raw(statement("INSERT INTO bot_audience_origins(thread_id,chat_id,project_id,creation_id,binding_revision,requires_upgrade,summary_version,target_json) VALUES(?,?,?,?,?,1,1,?)", vec![scope.thread_id.clone().into(),scope.chat_id.clone().into(),scope.project_id.clone().into(),scope.creation_id.clone().into(),i64::try_from(scope.binding_revision)?.into(),legacy.target.encode()?.into()])).await?;
        }
        insert_scope_row(&tx, &scope).await?;
        insert_cursor_row(&tx, &scope.key).await?;
        tx.commit().await?;
        Ok(scope)
    }

    async fn legacy_stop(
        store: &BotStateStore,
        key: &DeliveryScopeKey,
    ) -> anyhow::Result<Option<String>> {
        store
            .db()
            .await?
            .query_one_raw(statement(
                "SELECT stopped_reason FROM bot_delivery_claims WHERE scope_key=?",
                vec![key.storage_key()?.into()],
            ))
            .await?
            .map(|row| strict_text(&row, "stopped_reason").map_err(Into::into))
            .transpose()
    }

    async fn prune_all_legacy(
        store: &BotStateStore,
        config: &crate::bots::config::BotConfigFile,
    ) -> anyhow::Result<(bool, usize)> {
        let mut after = None;
        let mut changed = false;
        let mut pages = 0;
        loop {
            let (updated, next) = store
                .prune_legacy_delivery_page(config, after.as_deref())
                .await?;
            changed |= updated;
            pages += 1;
            if let Some(next) = next {
                assert!(after.as_ref().is_none_or(|previous| &next > previous));
                assert!(
                    pages < 8,
                    "bounded fixture must finish rather than repeat stopped pages"
                );
                after = Some(next);
            } else {
                return Ok((changed, pages));
            }
        }
    }

    #[tokio::test]
    async fn legacy_claim_is_live_but_its_turn_cannot_also_be_frontend() -> anyhow::Result<()> {
        use super::super::DeliveryInputChain;
        use crate::bots::config::BotConfigFile;
        use crate::bots::storage::BoundThreadExpectation;
        use crate::bots::storage::target::TargetKind;
        use pl_protocol::studio::{BotThreadSyncAction, ChangeBotThreadSyncRequest};
        use pl_protocol::{BotAudienceCloseReason, BotAuthorizationHead, BotSyncCas};
        let (_directory, store, scope, entity_key) =
            store_with_legacy_fixture(crate::bots::storage::target::TargetKind::Group).await?;
        let db = store.db().await?;
        let legacy = claimed(&store, &scope.key).await;
        let empty = store
            .delivery_entity(&scope.key, &entity_key)
            .await?
            .unwrap();
        assert!(
            store
                .register_test_card_intent(
                    &legacy,
                    &entity_key,
                    DeliveryAction::CreateCard {
                        text: "legacy final".into()
                    }
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&scope.key, &entity_key).await?,
            Some(empty.clone())
        );
        store
            .merge_legacy_delivery_presentation(
                &legacy,
                &entity_key,
                empty.ledger_version,
                &legacy_candidate("legacy final"),
            )
            .await?;
        let frontend_key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let frontend = claimed(&store, &frontend_key).await;
        let mut candidate = text_candidate("hello", 1);
        candidate.input_chain = DeliveryInputChain::Unavailable;
        assert_eq!(
            store
                .merge_delivery_candidate(&frontend, &candidate)
                .await?,
            MergeOutcome::NotCanonical
        );
        candidate.turn_id = "independent-turn".into();
        candidate.input_chain = DeliveryInputChain::Proven {
            input_id: "independent-input".into(),
            continuation_ancestors: vec![],
        };
        assert_eq!(
            store
                .merge_delivery_candidate(&frontend, &candidate)
                .await?,
            MergeOutcome::Applied { item_revision: 1 }
        );
        let intent = store
            .register_test_card_intent(
                &legacy,
                &entity_key,
                DeliveryAction::CreateCard {
                    text: "legacy final".into(),
                },
            )
            .await?;
        store
            .settle_delivery_card_result(
                &scope.key,
                &entity_key,
                &intent.operation_id,
                DeliveryResult::Unknown {
                    diagnostic: Some("started before close".into()),
                },
            )
            .await?;
        let material = store.delivery_entity(&scope.key, &entity_key).await?;
        let mut successor = scope.clone();
        successor.thread_id = "successor-thread".into();
        successor.creation_id = "successor-creation".into();
        successor.binding_revision = 2;
        let successor = insert_recovery_legacy(&store, successor, "successor-legacy").await?;
        let mut other_chat = scope.clone();
        other_chat.chat_id = "other-chat".into();
        other_chat.thread_id = "other-thread".into();
        other_chat.creation_id = "other-creation".into();
        let other_chat = insert_recovery_legacy(&store, other_chat, "other-chat-legacy").await?;
        let config = BotConfigFile::new(BOT.into(), "fixture".into(), PROJECT.into(), APP.into())?;
        let request = |id: &str, action, auth: &Authorization| ChangeBotThreadSyncRequest {
            operation_id: id.into(),
            thread_id: auth.intent.thread_id.clone(),
            action,
            expected: BotSyncCas {
                binding_revision: auth.intent.binding_revision,
                authorization_head: BotAuthorizationHead::Present {
                    authorization: auth.reference(),
                },
            },
        };
        let auth = audience::load_auth(db, &authorization_id()).await?.unwrap();
        let paused = store
            .change_sync(
                &request("legacy-pause", BotThreadSyncAction::Pause, &auth),
                &config,
            )
            .await?;
        assert!(
            legacy_stop(&store, &scope.key)
                .await?
                .unwrap_or_default()
                .is_empty()
        );
        let resumed = store
            .change_sync(
                &request(
                    "legacy-resume",
                    BotThreadSyncAction::Resume,
                    &paused.authorization,
                ),
                &config,
            )
            .await?;
        assert!(
            legacy_stop(&store, &scope.key)
                .await?
                .unwrap_or_default()
                .is_empty()
        );
        // 摘要失效失败必须回滚永久 stop 与授权控制，不能吞掉观察源损坏。
        db.execute_unprepared("CREATE TRIGGER fail_legacy_summary BEFORE UPDATE OF summary_version ON bot_audience_origins WHEN OLD.thread_id='thread-1' BEGIN SELECT RAISE(ABORT,'controlled legacy summary fault'); END").await?;
        assert!(
            store
                .close_sync_generation(&authorization_id(), BotAudienceCloseReason::TrustRevoked)
                .await
                .is_err()
        );
        assert_eq!(
            audience::load_auth(db, &authorization_id()).await?,
            Some(resumed.authorization.clone())
        );
        assert!(
            legacy_stop(&store, &scope.key)
                .await?
                .unwrap_or_default()
                .is_empty()
        );
        assert_eq!(
            store.delivery_entity(&scope.key, &entity_key).await?,
            material
        );
        db.execute_unprepared("DROP TRIGGER fail_legacy_summary")
            .await?;
        let close = request(
            "legacy-close",
            BotThreadSyncAction::Close,
            &resumed.authorization,
        );
        let closed = store.change_sync(&close, &config).await?;
        assert_eq!(closed.authorization.phase, BotAuthorizationPhase::Closed);
        let reason = legacy_stop(&store, &scope.key).await?.unwrap();
        assert!(!reason.is_empty());
        assert_eq!(
            store.delivery_entity(&scope.key, &entity_key).await?,
            material
        );
        assert!(legacy_stop(&store, &successor.key).await?.is_none());
        assert!(legacy_stop(&store, &other_chat.key).await?.is_none());
        let summary = audience::read_origin(db, THREAD)
            .await?
            .unwrap()
            .summary_version;
        assert!(!store.change_sync(&close, &config).await?.changed);
        assert!(
            !store
                .close_sync_generation(&authorization_id(), BotAudienceCloseReason::BotDisabled)
                .await?
        );
        assert_eq!(
            audience::read_origin(db, THREAD)
                .await?
                .unwrap()
                .summary_version,
            summary
        );
        // 旧 generation 的补充关闭只命中原绑定，不能封后继绑定或其它 chat。
        let old_material =
            insert_recovery_legacy(&store, scope.clone(), "late-old-material").await?;
        assert!(
            store
                .close_sync_generation(&authorization_id(), BotAudienceCloseReason::BotDisabled)
                .await?
        );
        assert!(
            legacy_stop(&store, &old_material.key)
                .await?
                .is_some_and(|reason| !reason.is_empty())
        );
        assert_eq!(legacy_stop(&store, &scope.key).await?, Some(reason));
        assert!(legacy_stop(&store, &successor.key).await?.is_none());
        assert!(legacy_stop(&store, &other_chat.key).await?.is_none());
        assert!(matches!(
            store
                .claim_delivery_scope(&scope.key, "after-close")
                .await?,
            DeliveryClaimOutcome::Stopped { .. }
        ));
        db.execute_unprepared("UPDATE thread_bindings SET thread_id='replacement',revision=2")
            .await?;
        assert!(
            store
                .register_test_card_intent(
                    &legacy,
                    &entity_key,
                    DeliveryAction::CreateCard {
                        text: "legacy final".into()
                    }
                )
                .await
                .is_err()
        );
        store
            .settle_delivery_card_result(
                &scope.key,
                &entity_key,
                &intent.operation_id,
                DeliveryResult::Created {
                    card_id: "legacy-card".into(),
                },
            )
            .await?;
        assert_eq!(
            store
                .delivery_entity(&scope.key, &entity_key)
                .await?
                .unwrap()
                .state
                .card
                .card_id
                .as_deref(),
            Some("legacy-card")
        );
        assert!(matches!(
            store
                .claim_delivery_scope(&scope.key, "after-late-result")
                .await?,
            DeliveryClaimOutcome::Stopped { .. }
        ));
        super::super::schema::validate(db).await?;

        // 没有 head/claim 的真实绑定不可用与替换路径，同事务关闭全部匹配范围（超过一页）。
        let (_directory, store, scope, entity_key) =
            store_with_legacy_fixture(TargetKind::Group).await?;
        remove_frontend_head(&store).await?;
        let db = store.db().await?;
        let original = store.delivery_entity(&scope.key, &entity_key).await?;
        let mut lost_origin = scope.clone();
        lost_origin.thread_id = "lost-origin-thread".into();
        lost_origin.creation_id = "lost-origin-creation".into();
        let lost_origin =
            insert_recovery_legacy(&store, lost_origin, "missing-origin-material").await?;
        let origin = audience::read_origin(db, &lost_origin.thread_id)
            .await?
            .unwrap();
        db.execute_raw(statement(
            "DELETE FROM bot_audience_origins WHERE thread_id=?",
            vec![lost_origin.thread_id.clone().into()],
        ))
        .await?;
        assert!(
            store
                .stop_delivery_scope(&lost_origin.key, "local close with missing origin")
                .await
                .is_err()
        );
        assert!(
            legacy_stop(&store, &lost_origin.key).await?.is_none(),
            "missing observer origin must roll back the stop, not be silently ignored"
        );
        db.execute_raw(statement("INSERT INTO bot_audience_origins(thread_id,chat_id,project_id,creation_id,binding_revision,requires_upgrade,summary_version,target_json) VALUES(?,?,?,?,?,?,?,?)", vec![origin.thread_id.into(),origin.chat_id.into(),origin.project_id.into(),origin.creation_id.into(),i64::try_from(origin.binding_revision)?.into(),i64::from(origin.requires_upgrade).into(),i64::try_from(origin.summary_version)?.into(),origin.target.encode()?.into()])).await?;
        let mut same_binding = vec![scope.clone()];
        for index in 0..34 {
            same_binding.push(
                insert_recovery_legacy(&store, scope.clone(), &format!("unavailable-{index}"))
                    .await?,
            );
        }
        let mut successor = scope.clone();
        successor.thread_id = "successor-thread".into();
        successor.creation_id = "successor-creation".into();
        successor.binding_revision = 2;
        let successor = insert_recovery_legacy(&store, successor, "unavailable-successor").await?;
        let mut other_chat = scope.clone();
        other_chat.chat_id = "other-chat".into();
        other_chat.thread_id = "other-thread".into();
        other_chat.creation_id = "other-creation".into();
        let other_chat =
            insert_recovery_legacy(&store, other_chat, "unavailable-other-chat").await?;
        let expected = BoundThreadExpectation {
            chat_id: CHAT.into(),
            thread_id: THREAD.into(),
            creation_id: creation(),
            project_id: PROJECT.into(),
            revision: 1,
        };
        db.execute_unprepared("CREATE TRIGGER fail_legacy_summary BEFORE UPDATE OF summary_version ON bot_audience_origins WHEN OLD.thread_id='thread-1' BEGIN SELECT RAISE(ABORT,'controlled unavailable summary fault'); END").await?;
        assert!(
            store
                .mark_binding_attention(&expected, "lookup unavailable")
                .await
                .is_err()
        );
        let route = db
            .query_one_raw(statement(
                "SELECT status,revision FROM thread_bindings WHERE chat_id=?",
                vec![CHAT.into()],
            ))
            .await?
            .unwrap();
        assert_eq!(strict_text(&route, "status")?, "bound");
        assert_eq!(stored_i64(&route, "revision")?, 1);
        assert!(legacy_stop(&store, &scope.key).await?.is_none());
        db.execute_unprepared("DROP TRIGGER fail_legacy_summary")
            .await?;
        assert!(
            store
                .mark_binding_attention(&expected, "lookup unavailable")
                .await?
        );
        for item in &same_binding {
            assert!(
                legacy_stop(&store, &item.key)
                    .await?
                    .is_some_and(|reason| !reason.is_empty())
            );
        }
        assert_eq!(
            store.delivery_entity(&scope.key, &entity_key).await?,
            original
        );
        assert!(legacy_stop(&store, &successor.key).await?.is_none());
        assert!(legacy_stop(&store, &other_chat.key).await?.is_none());
        let reason = legacy_stop(&store, &scope.key).await?;
        let tx = db.begin().await?;
        assert!(audience::close_chat(&tx, CHAT, BotAudienceCloseReason::BindingReplaced).await?);
        tx.commit().await?;
        assert!(
            legacy_stop(&store, &successor.key)
                .await?
                .is_some_and(|reason| !reason.is_empty())
        );
        assert!(legacy_stop(&store, &other_chat.key).await?.is_none());
        assert_eq!(legacy_stop(&store, &scope.key).await?, reason);
        let summary = audience::read_origin(db, THREAD)
            .await?
            .unwrap()
            .summary_version;
        let tx = db.begin().await?;
        assert!(!audience::close_chat(&tx, CHAT, BotAudienceCloseReason::BindingReplaced).await?);
        assert!(
            !audience::close_chat(&tx, "unrelated-chat", BotAudienceCloseReason::LocalClose)
                .await?
        );
        tx.commit().await?;
        assert_eq!(
            audience::read_origin(db, THREAD)
                .await?
                .unwrap()
                .summary_version,
            summary
        );
        assert!(legacy_stop(&store, &other_chat.key).await?.is_none());
        super::super::schema::validate(db).await?;
        Ok(())
    }

    #[tokio::test]
    async fn legacy_live_admission_preserves_handoff_and_results_without_reopening_attention()
    -> anyhow::Result<()> {
        use super::super::records::write_entity;
        use crate::bots::storage::card::CardLifecycle;
        let (_directory, store, scope, entity_key) =
            store_with_legacy_fixture(crate::bots::storage::target::TargetKind::Group).await?;
        let db = store.db().await?;
        let token = claimed(&store, &scope.key).await;
        let version = store
            .delivery_entity(&scope.key, &entity_key)
            .await?
            .unwrap()
            .ledger_version;
        store
            .merge_legacy_delivery_presentation(
                &token,
                &entity_key,
                version,
                &legacy_candidate("legacy final"),
            )
            .await?;
        // 迁移时 pending 的有限义务，可靠 handoff 后 completed 仍独立接续。
        db.execute_unprepared("UPDATE inbound_work SET status='completed'")
            .await?;
        assert!(matches!(
            store.renew_delivery_claim(&token).await?,
            DeliveryClaimOutcome::Acquired(_)
        ));
        let create = store
            .register_test_card_intent(
                &token,
                &entity_key,
                DeliveryAction::CreateCard {
                    text: "legacy final".into(),
                },
            )
            .await?;
        for status in ["needs_attention", "future_status"] {
            db.execute_raw(statement(
                "UPDATE inbound_work SET status=?",
                vec![status.into()],
            ))
            .await?;
            assert!(
                matches!(
                    store.claim_delivery_scope(&scope.key, "owner-b").await?,
                    DeliveryClaimOutcome::Stopped { .. }
                ),
                "{status} must fence a new claim"
            );
            assert!(
                store
                    .register_test_card_intent(
                        &token,
                        &entity_key,
                        DeliveryAction::CreateCard {
                            text: "legacy final".into()
                        }
                    )
                    .await
                    .is_err()
            );
            assert_eq!(
                store
                    .delivery_entity(&scope.key, &entity_key)
                    .await?
                    .unwrap()
                    .state
                    .in_flight,
                Some(create.clone())
            );
            super::super::schema::validate(db).await?;
        }
        store
            .settle_delivery_card_result(
                &scope.key,
                &entity_key,
                &create.operation_id,
                DeliveryResult::Created {
                    card_id: "legacy-card".into(),
                },
            )
            .await?;
        db.execute_unprepared("UPDATE inbound_work SET status='completed'")
            .await?;
        store.release_delivery_claim(&token).await?;
        let current = claimed(&store, &scope.key).await;
        // 最后操作是 Confirmed；需处理不是 Unknown，也不允许从此创建新请求。
        let mut entity = store
            .delivery_entity(&scope.key, &entity_key)
            .await?
            .unwrap();
        let previous = entity.ledger_version;
        entity.state.card.lifecycle = Some(CardLifecycle::NeedsAttention);
        entity.ledger_version += 1;
        let tx = db.begin().await?;
        write_entity(&tx, &entity, Some(previous)).await?;
        sync_pending(&tx, &entity).await?;
        tx.commit().await?;
        let flags = derive_flags(false, &entity.state);
        assert!(flags.attention && !flags.pending());
        assert!(matches!(
            store.claim_delivery_scope(&scope.key, "owner-b").await?,
            DeliveryClaimOutcome::Stopped { .. }
        ));
        assert!(
            store
                .register_test_card_intent(
                    &current,
                    &entity_key,
                    DeliveryAction::SendCard {
                        card_id: "legacy-card".into()
                    }
                )
                .await
                .is_err()
        );
        assert!(
            store
                .delivery_pending(&scope.key, None, 100)
                .await?
                .pending
                .is_empty()
        );
        assert!(store.audience_counts(THREAD, 1).await?.1.needs_attention);
        // 模拟保存故障后人工恢复再发起请求，随后本地注意状态先于在途响应保存。
        let previous = entity.ledger_version;
        entity.state.card.lifecycle = Some(CardLifecycle::Created);
        entity.ledger_version += 1;
        let tx = db.begin().await?;
        write_entity(&tx, &entity, Some(previous)).await?;
        sync_pending(&tx, &entity).await?;
        tx.commit().await?;
        let send = store
            .register_test_card_intent(
                &current,
                &entity_key,
                DeliveryAction::SendCard {
                    card_id: "legacy-card".into(),
                },
            )
            .await?;
        let mut entity = store
            .delivery_entity(&scope.key, &entity_key)
            .await?
            .unwrap();
        let previous = entity.ledger_version;
        entity.state.card.lifecycle = Some(CardLifecycle::NeedsAttention);
        entity.ledger_version += 1;
        let tx = db.begin().await?;
        write_entity(&tx, &entity, Some(previous)).await?;
        sync_pending(&tx, &entity).await?;
        tx.commit().await?;
        db.execute_unprepared("DELETE FROM inbound_work").await?;
        assert!(matches!(
            store.claim_delivery_scope(&scope.key, "owner-b").await?,
            DeliveryClaimOutcome::Stopped { .. }
        ));
        store
            .settle_delivery_card_result(
                &scope.key,
                &entity_key,
                &send.operation_id,
                DeliveryResult::Sent {
                    card_id: "legacy-card".into(),
                    message_id: "om_legacy".into(),
                },
            )
            .await?;
        let retained = store
            .delivery_entity(&scope.key, &entity_key)
            .await?
            .unwrap();
        assert_eq!(
            retained.state.card.lifecycle,
            Some(CardLifecycle::NeedsAttention)
        );
        assert_eq!(
            retained.state.card.platform_message_id.as_deref(),
            Some("om_legacy")
        );
        super::super::schema::validate(db).await?;

        // 原有限资格没有 auth head/claim 时也必须受持久关闭约束，恢复配置不能复活。
        use crate::bots::config::BotConfigFile;
        use crate::bots::storage::target::TargetKind;
        let peer = format!("ou_{}", "a".repeat(32));
        for (target, policy) in [
            (TargetKind::Group, "disabled"),
            (TargetKind::Group, "group-trust"),
            (
                TargetKind::Direct {
                    open_id: peer.clone(),
                },
                "direct-trust",
            ),
            (TargetKind::Group, "app"),
            (TargetKind::Group, "project"),
        ] {
            let (directory, store, scope, entity_key) = store_with_legacy_fixture(target).await?;
            remove_frontend_head(&store).await?;
            let db = store.db().await?;
            assert!(legacy_stop(&store, &scope.key).await?.is_none());
            let original = store.delivery_entity(&scope.key, &entity_key).await?;
            let mut scopes = vec![scope.clone()];
            if policy == "disabled" {
                for index in 0..35 {
                    scopes.push(
                        insert_recovery_legacy(
                            &store,
                            scope.clone(),
                            &format!("{BOT}:{CHAT}:archived-{index}"),
                        )
                        .await?,
                    );
                }
            }
            let pages = if scopes.len() > 32 { 2 } else { 1 };
            let mut config =
                BotConfigFile::new(BOT.into(), "fixture".into(), PROJECT.into(), APP.into())?;
            config.feishu_mut().trusted_chat_ids.insert(CHAT.into());
            config.feishu_mut().trusted_open_ids.insert(peer.clone());
            assert_eq!(prune_all_legacy(&store, &config).await?, (false, pages));
            let permitted = config.clone();
            match policy {
                "disabled" => config.enabled = false,
                "group-trust" => {
                    config.feishu_mut().trusted_chat_ids.remove(CHAT);
                }
                "direct-trust" => {
                    config.feishu_mut().trusted_open_ids.remove(&peer);
                }
                "app" => config.feishu_mut().app_id = "other-app".into(),
                "project" => config.project_id = "other-project".into(),
                _ => unreachable!(),
            }
            let version = audience::read_origin(db, THREAD)
                .await?
                .unwrap()
                .summary_version;
            assert_eq!(
                prune_all_legacy(&store, &config).await?,
                (true, pages),
                "{policy}"
            );
            let reason = legacy_stop(&store, &scope.key).await?.unwrap();
            assert!(!reason.is_empty());
            for item in &scopes {
                assert!(
                    legacy_stop(&store, &item.key)
                        .await?
                        .is_some_and(|reason| !reason.is_empty())
                );
            }
            assert_eq!(
                store.delivery_entity(&scope.key, &entity_key).await?,
                original
            );
            let stopped_version = audience::read_origin(db, THREAD)
                .await?
                .unwrap()
                .summary_version;
            assert!(stopped_version > version);
            assert_eq!(prune_all_legacy(&store, &config).await?, (false, pages));
            assert_eq!(prune_all_legacy(&store, &permitted).await?, (false, pages));
            assert_eq!(
                audience::read_origin(db, THREAD)
                    .await?
                    .unwrap()
                    .summary_version,
                stopped_version
            );
            assert_eq!(legacy_stop(&store, &scope.key).await?, Some(reason));
            let count = db
                .query_one_raw(statement(
                    "SELECT count(*) AS n FROM bot_authorizations",
                    vec![],
                ))
                .await?
                .unwrap();
            assert_eq!(
                stored_i64(&count, "n")?,
                0,
                "pruning must not invent an authorization head"
            );
            let cold = BotStateStore::new(directory.path().join("state.sqlite"));
            cold.db().await?;
            assert!(matches!(
                cold.claim_delivery_scope(&scope.key, "after-regrant")
                    .await?,
                DeliveryClaimOutcome::Stopped { .. }
            ));
            assert_eq!(
                cold.delivery_entity(&scope.key, &entity_key).await?,
                original
            );
            if policy == "disabled" {
                // 即使同 chat 在信任名单中，也不能从名单为 Unproven 材料推断 Group。
                let mut unknown = scope.clone();
                let DeliveryScopeOrigin::LegacyFinal { legacy } = &mut unknown.origin else {
                    unreachable!()
                };
                legacy.target = crate::bots::storage::target::TargetProof::Unproven;
                let unknown = insert_recovery_legacy(&store, unknown, "unproven-target").await?;
                assert_eq!(prune_all_legacy(&store, &permitted).await?, (true, 2));
                assert!(
                    legacy_stop(&store, &unknown.key)
                        .await?
                        .is_some_and(|reason| !reason.is_empty())
                );
                let mut wrong_bot = permitted.clone();
                wrong_bot.id = "another-bot".into();
                assert!(
                    store
                        .prune_legacy_delivery_page(&wrong_bot, None)
                        .await
                        .is_err()
                );
                // 新的权威授权仍建立自己的 Frontend scope，不能继承旧 Legacy 的 stop。
                let mut fresh = active_authorization();
                fresh.intent.authorization.generation = 2;
                fresh.intent.operation_id = "explicit-new-authorization".into();
                fresh.start.as_mut().unwrap().intent = fresh.intent.clone();
                let tx = db.begin().await?;
                tx.execute_raw(statement("INSERT INTO bot_authorizations(chat_id,generation,thread_id,control_revision,phase,state_json) VALUES(?,2,?,1,'active',?)", vec![CHAT.into(),THREAD.into(),serde_json::to_string(&fresh)?.into()])).await?;
                let origin = audience::read_origin(&tx, THREAD).await?.unwrap();
                ensure_frontend_scope_in(&tx, &fresh, &origin).await?;
                tx.commit().await?;
                let fresh_key = DeliveryScopeKey::Frontend {
                    authorization: fresh.intent.authorization.clone(),
                };
                let fresh_token = claimed(&store, &fresh_key).await;
                let mut independent = text_candidate("new authorization output", 1);
                independent.turn_id = "post-close-turn".into();
                independent.input_chain = super::super::DeliveryInputChain::Proven {
                    input_id: "post-close-input".into(),
                    continuation_ancestors: vec![],
                };
                assert_eq!(
                    store
                        .merge_delivery_candidate(&fresh_token, &independent)
                        .await?,
                    MergeOutcome::Applied { item_revision: 1 }
                );
                assert_eq!(prune_all_legacy(&store, &permitted).await?, (false, 2));
                assert!(
                    legacy_stop(&store, &scope.key)
                        .await?
                        .is_some_and(|reason| !reason.is_empty())
                );
            }
            super::super::schema::validate(db).await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn migrated_direct_reply_claims_only_its_recorded_domain_target() -> anyhow::Result<()> {
        use crate::bots::storage::card::{
            CardAction, CardLifecycle, CardOperation, CardOperationStatus, CardStream, hash,
        };
        use crate::bots::storage::target::{TargetKind, TargetProof};
        let peer = format!("ou_{}", "a".repeat(32));
        let other_peer = format!("ou_{}", "b".repeat(32));
        let mut failures = Vec::new();
        for scenario in [
            "direct",
            "wrong-open-id",
            "wrong-target",
            "p2p",
            "unproven-unknown",
        ] {
            let (_directory, store, binding) = store_with_inbound_target(TargetKind::Direct {
                open_id: peer.clone(),
            })
            .await?;
            let db = store.db().await?;
            match scenario {
                "wrong-open-id" => {
                    db.execute_raw(statement(
                        "UPDATE inbound_work SET open_id=?",
                        vec![other_peer.clone().into()],
                    ))
                    .await?;
                }
                "wrong-target" => {
                    db.execute_raw(statement(
                        "UPDATE bot_audience_origins SET target_json=?",
                        vec![
                            TargetProof::Legacy {
                                target: TargetKind::Direct {
                                    open_id: other_peer.clone(),
                                },
                            }
                            .encode()?
                            .into(),
                        ],
                    ))
                    .await?;
                }
                "p2p" => {
                    db.execute_unprepared("UPDATE inbound_work SET chat_kind='p2p'")
                        .await?;
                }
                "unproven-unknown" => {
                    db.execute_raw(statement(
                        "UPDATE bot_audience_origins SET target_json=?",
                        vec![TargetProof::Unproven.encode()?.into()],
                    ))
                    .await?;
                }
                _ => {}
            }
            let action = CardAction::Content {
                text: "saved direct final".into(),
                final_content: false,
            };
            let stream = CardStream {
                binding: binding.clone(),
                watch_input: binding.original_input.clone(),
                turn_id: Some("direct-turn".into()),
                version: 1,
                lifecycle: CardLifecycle::Streaming,
                card_id: Some("direct-card".into()),
                platform_message_id: Some("om_direct".into()),
                sequence: 1,
                confirmed_sequence: 1,
                confirmed_text: "saved direct final".into(),
                confirmed_content_hash: hash(b"saved direct final"),
                final_content_hash: None,
                last_operation: Some(CardOperation {
                    content_hash: hash(&serde_json::to_vec(&action)?),
                    action,
                    sequence: 1,
                    uuid: "0123456789abcdef0123456789abcdef".into(),
                    status: if scenario == "unproven-unknown" {
                        CardOperationStatus::Unknown
                    } else {
                        CardOperationStatus::Confirmed
                    },
                    diagnostic: None,
                }),
                recovery_used: false,
                recovery: None,
                diagnostic: None,
            };
            // 完整真实机器人库保留原入站/来源，仅将本模块恢复结构还原成九号来源后正式迁移。
            let tx = db.begin().await?;
            for table in [
                "bot_delivery_pending",
                "bot_delivery_claims",
                "bot_delivery_cursors",
                "bot_delivery_items",
                "bot_delivery_scopes",
            ] {
                tx.execute_unprepared(&format!("DROP TABLE {table}"))
                    .await?;
            }
            tx.execute_unprepared(audience::legacy_items_declaration())
                .await?;
            tx.execute_raw(statement("INSERT INTO bot_card_streams(identity,bot_id,chat_id,message_id,thread_id,original_input,watch_input,turn_id,version,state_json,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,1)",vec![format!("{BOT}:{CHAT}:old-message").into(),BOT.into(),CHAT.into(),"old-message".into(),THREAD.into(),binding.original_input.clone().into(),stream.watch_input.clone().into(),"direct-turn".into(),1_i64.into(),serde_json::to_string(&stream)?.into()])).await?;
            // This fixture owns a genuine pre-official schema-nine source, not a schema-ten
            // database with completed official records left behind after a manual downgrade.
            tx.execute_unprepared("DROP TABLE seaql_migrations").await?;
            tx.execute_unprepared(
                "CREATE INDEX bot_delivery_thread ON bot_delivery_items(thread_id,item_id)",
            )
            .await?;
            audience::prepare_count_indexes(&tx).await?;
            tx.execute_unprepared("UPDATE bot_meta SET schema_version=9 WHERE id=1")
                .await?;
            tx.commit().await?;
            crate::bots::storage::schema::initialize(
                db,
                crate::bots::storage::DatabaseOrigin::Existing,
            )
            .await?;
            let key = DeliveryScopeKey::LegacyFinal {
                inbound_identity: format!("{BOT}:{CHAT}:old-message"),
            };
            let scope = store.delivery_scope(&key).await?.unwrap();
            let entity_key = DeliveryEntityKey::LegacyFinal {
                entity_id: binding.reply_operation(),
            };
            let entity = store.delivery_entity(&key, &entity_key).await?.unwrap();
            assert_eq!(entity.state.card.confirmed_text, stream.confirmed_text);
            assert!(
                !entity.saved,
                "old confirmed text is not a canonical Saved proof"
            );
            let claim = store.claim_delivery_scope(&key, "direct-owner").await?;
            if scenario == "direct" {
                if scope.needs_recovery || !matches!(claim, DeliveryClaimOutcome::Acquired(_)) {
                    failures.push(format!("direct qualification lost: {claim:?}"));
                }
                if let DeliveryClaimOutcome::Acquired(token) = claim {
                    let close = DeliveryAction::UpdateSettings {
                        card_id: "direct-card".into(),
                        streaming: false,
                        lifecycle: CardLifecycle::Completed,
                        recovery: false,
                    };
                    assert!(
                        store
                            .register_test_card_intent(&token, &entity_key, close.clone())
                            .await
                            .is_err()
                    );
                    let mut proof = legacy_candidate("next direct final");
                    proof.turn_id = "direct-turn".into();
                    store
                        .merge_legacy_delivery_presentation(
                            &token,
                            &entity_key,
                            entity.ledger_version,
                            &proof,
                        )
                        .await?;
                    assert!(
                        store
                            .register_test_card_intent(&token, &entity_key, close)
                            .await
                            .is_err(),
                        "new canonical proof cannot replace the old HTTP confirmation"
                    );
                    let next = store
                        .register_test_card_intent(
                            &token,
                            &entity_key,
                            DeliveryAction::UpdateContent {
                                card_id: "direct-card".into(),
                                text: "next direct final".into(),
                                final_content: true,
                            },
                        )
                        .await?;
                    assert_eq!(
                        (next.content_revision, next.integrity, next.saved),
                        (0, BotTextIntegrity::Full, false)
                    );
                }
            } else if !scope.needs_recovery
                || !matches!(claim, DeliveryClaimOutcome::Stopped { .. })
            {
                failures.push(format!("{scenario} was granted: {claim:?}"));
            }
            if scenario == "unproven-unknown" {
                // 缺少外写资格不等于缺少已开始的操作：冷恢复仍须展示并只计数一次，
                // 不从恢复状态制造 pending 或新的 UUID。原操作迟到的确定结果仍可结算。
                let cold = BotStateStore::new(_directory.path().join("state.sqlite"));
                cold.db().await?;
                let recovered = cold.delivery_entity(&key, &entity_key).await?.unwrap();
                assert_eq!(recovered, entity);
                assert!(matches!(
                    recovered.state.content,
                    DeliveryContent::Unresolved { .. }
                ));
                assert!(matches!(
                    super::super::item_platform(&recovered, None),
                    pl_protocol::studio::BotItemPlatform::Card { latest_operation }
                        if matches!(latest_operation.result, pl_protocol::studio::BotPlatformResult::Unknown { .. })
                ));
                let (_, summary) = cold.audience_counts(THREAD, 1).await?;
                assert_eq!(summary.unknown_operations, 1);
                assert!(summary.needs_attention);
                assert!(
                    cold.delivery_pending(&key, None, 100)
                        .await?
                        .pending
                        .is_empty()
                );
                assert!(matches!(
                    cold.claim_delivery_scope(&key, "recovery-owner").await?,
                    DeliveryClaimOutcome::Stopped { .. }
                ));
                let original = recovered.state.settled.as_ref().unwrap();
                assert_eq!(
                    cold.settle_delivery_card_result(
                        &key,
                        &entity_key,
                        &original.intent.operation_id,
                        DeliveryResult::ContentAccepted {
                            card_id: "direct-card".into(),
                        },
                    )
                    .await?,
                    SettlementOutcome::Applied
                );
                let settled = cold.delivery_entity(&key, &entity_key).await?.unwrap();
                assert_eq!(
                    settled.state.settled.as_ref().unwrap().intent,
                    original.intent
                );
                assert_eq!(settled.state.card.card_id, stream.card_id);
                assert_eq!(
                    settled.state.card.platform_message_id,
                    stream.platform_message_id
                );
                assert_eq!(
                    cold.audience_counts(THREAD, 1).await?.1.unknown_operations,
                    0
                );
                assert!(matches!(
                    cold.claim_delivery_scope(&key, "after-result-owner")
                        .await?,
                    DeliveryClaimOutcome::Stopped { .. }
                ));
            }
        }
        assert!(failures.is_empty(), "{failures:#?}");
        Ok(())
    }

    #[tokio::test]
    async fn unresolved_observation_keeps_cold_projection_and_distinct_unknown_stages()
    -> anyhow::Result<()> {
        use super::super::{DeliveryCard, DeliveryRecoveryReason, DeliveryUnresolved};
        use pl_protocol::studio::{BotFileOutcome, BotItemPlatform, BotPlatformResult};
        let (directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let unknown = BotPlatformResult::Unknown {
            diagnostic: diagnostic_of("historical unknown"),
        };
        let ledger = BotItemLedgerSummary {
            observed_revision: 4,
            projected: BotItemPresentation::File { revision: 3 },
            accepted: BotItemPresentation::File { revision: 2 },
            platform: BotItemPlatform::File {
                operation_id: "old-file".into(),
                content_revision: 3,
                upload: unknown.clone(),
                message: unknown,
                outcome: BotFileOutcome::Unknown,
                local_stop: None,
            },
        };
        let entity = DeliveryEntity {
            scope: key.clone(),
            entity: DeliveryEntityKey::TextItem {
                item_id: "old-item".into(),
            },
            turn_id: None,
            item_order: None,
            saved: false,
            removed: false,
            state: DeliveryEntityState {
                content: DeliveryContent::Unresolved {
                    unresolved: DeliveryUnresolved {
                        reason: DeliveryRecoveryReason::LegacyObservation,
                        observation: Some(ledger.clone()),
                        removed: false,
                        pending: true,
                        incomplete: false,
                        detail: "migrated observation".into(),
                    },
                },
                projected: BotItemPresentation::None {},
                accepted: BotItemPresentation::None {},
                card: DeliveryCard::default(),
                file_operation: None,
                in_flight: None,
                settled: None,
                halt: None,
            },
            ledger_version: 1,
            updated_at: 1,
        };
        let tx = store.db().await?.begin().await?;
        insert_entity_row(&tx, &entity).await?;
        sync_pending(&tx, &entity).await?;
        tx.commit().await?;
        let reopened = BotStateStore::new(directory.path().join("state.sqlite"));
        reopened.db().await?;
        let observation = reopened
            .delivery_observation(&authorization_id(), "old-item")
            .await?
            .unwrap();
        assert_eq!(observation.ledger, ledger);
        let (summary, _) = reopened.audience_counts(THREAD, 1).await?;
        assert_eq!(summary.unknown_operations, 2);
        assert_eq!(summary.pending_items, 0);
        assert_eq!(summary.incomplete_items, 1);
        assert!(
            reopened
                .delivery_pending(&key, None, 100)
                .await?
                .pending
                .is_empty()
        );
        Ok(())
    }

    #[tokio::test]
    async fn frozen_targets_match_actions_and_survive_revisions_and_reopen() -> anyhow::Result<()> {
        use super::super::{DeliveryRequestTarget as Target, FrozenDeliveryRequest};
        #[derive(serde::Serialize)]
        struct ContentBody<'a> {
            content: &'a str,
            sequence: i32,
            uuid: &'a str,
        }
        #[derive(serde::Serialize)]
        struct CardBody<'a> {
            r#type: &'a str,
            data: &'a str,
        }
        #[derive(serde::Serialize)]
        struct WholeBody<'a> {
            card: CardBody<'a>,
            uuid: &'a str,
            sequence: i32,
        }
        for target in [Target::ElementContent, Target::WholeCard] {
            let (_directory, store) = store_with_frontend().await?;
            let key = DeliveryScopeKey::Frontend {
                authorization: authorization_id(),
            };
            let token = claimed(&store, &key).await;
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 1))
                .await?;
            let create = store
                .register_test_card_intent(
                    &token,
                    &entity_key(),
                    DeliveryAction::CreateCard {
                        text: "hello".into(),
                    },
                )
                .await?;
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &create.operation_id,
                    DeliveryResult::Created {
                        card_id: "card-1".into(),
                    },
                )
                .await?;
            let send = store
                .register_test_card_intent(
                    &token,
                    &entity_key(),
                    DeliveryAction::SendCard {
                        card_id: "card-1".into(),
                    },
                )
                .await?;
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &send.operation_id,
                    DeliveryResult::Sent {
                        card_id: "card-1".into(),
                        message_id: "om_card".into(),
                    },
                )
                .await?;
            let action = DeliveryAction::UpdateContent {
                card_id: "card-1".into(),
                text: "hello".into(),
                final_content: true,
            };
            let before = store.delivery_entity(&key, &entity_key()).await?.unwrap();
            for wrong in [Target::CreateCard, Target::SendCard, Target::Settings] {
                assert!(
                    store
                        .register_delivery_card_intent(
                            &token,
                            &entity_key(),
                            before.ledger_version,
                            action.clone(),
                            |_, _| FrozenDeliveryRequest::new(wrong, "{}".into())
                        )
                        .await
                        .is_err()
                );
                assert_eq!(
                    store.delivery_entity(&key, &entity_key()).await?.unwrap(),
                    before
                );
            }
            let admission=store.register_delivery_card_intent(&token,&entity_key(),before.ledger_version,action.clone(),|id,_| {
                let body=if target==Target::ElementContent {
                    serde_json::to_string(&ContentBody { content:"hello",sequence:id.sequence,uuid:&id.uuid })
                } else {
                    // 测试只核冻结材料；真实官方 serializer 与网络由 O 接线。
                    serde_json::to_string(&WholeBody { card:CardBody { r#type:"card_json",data:r#"{"schema":"2.0","config":{"update_multi":true},"body":{"elements":[{"tag":"markdown","element_id":"answer","content":"hello"},{"tag":"markdown","element_id":"host_state","content":"Completed"}]}}"# },uuid:&id.uuid,sequence:id.sequence })
                }.map_err(|_|unreadable())?;
                FrozenDeliveryRequest::new(target,body)
            }).await?;
            let DeliveryCardAdmission::Confirmed(mut attempt) = admission else {
                panic!("a newly committed intent must return its unique attempt");
            };
            attempt.mark_request_started();
            let intent = attempt.intent();
            assert_eq!(intent.request.target(), target);
            assert_eq!(
                intent.request_hash,
                super::super::typed_digest(&(target, intent.request.body()))?
            );
            let other = if target == Target::ElementContent {
                Target::WholeCard
            } else {
                Target::ElementContent
            };
            assert_ne!(
                intent.request_hash,
                FrozenDeliveryRequest::new(other, intent.request.body().into())?.hash()?
            );
            store
                .merge_delivery_candidate(&token, &text_candidate("new body", 2))
                .await?;
            let current = store.delivery_entity(&key, &entity_key()).await?.unwrap();
            let again = store
                .register_delivery_card_intent(
                    &token,
                    &entity_key(),
                    current.ledger_version,
                    action,
                    |_, _| FrozenDeliveryRequest::new(other, "{}".into()),
                )
                .await?;
            let DeliveryCardAdmission::Existing = again else {
                panic!("a persisted intent must not mint a new attempt");
            };
            let again = store
                .delivery_entity(&key, &entity_key())
                .await?
                .expect("existing entity")
                .state
                .in_flight
                .expect("original frozen intent");
            assert_eq!(&again, intent);
            let cold = BotStateStore::new(_directory.path().join("state.sqlite"));
            cold.db().await?;
            assert_eq!(
                cold.delivery_entity(&key, &entity_key())
                    .await?
                    .unwrap()
                    .state
                    .in_flight,
                Some(intent.clone())
            );
            let mut invalid = current.state.clone();
            let corrupted = invalid.in_flight.as_mut().unwrap();
            corrupted.request =
                FrozenDeliveryRequest::new(Target::Settings, intent.request.body().into())?;
            corrupted.request_hash = corrupted.request.hash()?;
            let tx = store.db().await?.begin().await?;
            tx.execute_raw(statement(
                "UPDATE bot_delivery_items SET state_json=? WHERE scope_key=? AND entity_key=?",
                vec![
                    serde_json::to_string(&invalid)?.into(),
                    key.storage_key()?.into(),
                    entity_key().storage_key()?.into(),
                ],
            ))
            .await?;
            assert!(
                super::super::schema::validate(&tx).await.is_err(),
                "reopen must reject a target/action mismatch even with a matching hash"
            );
            tx.rollback().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn frozen_request_survives_revisions_and_late_confirmation() -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let create = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        store
            .merge_delivery_candidate(&token, &text_candidate("new revision", 2))
            .await?;
        let stored = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert_eq!(stored.state.in_flight, Some(create.clone()));
        assert_eq!(create.request_hash, create.request.hash()?);
        assert!(create.request.body().contains("hello"));
        assert!(!create.request.body().contains("new revision"));
        store.release_delivery_claim(&token).await?;
        store
            .retire_orphaned_delivery_intent(
                &key,
                &entity_key(),
                &create.operation_id,
                "owner exited",
            )
            .await?;
        let next = claimed(&store, &key).await;
        assert!(
            store
                .register_test_card_intent(
                    &next,
                    &entity_key(),
                    DeliveryAction::CreateCard {
                        text: "new revision".into()
                    }
                )
                .await
                .is_err()
        );
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &create.operation_id,
                DeliveryResult::Created {
                    card_id: "card-1".into(),
                },
            )
            .await?;
        let entity = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert_eq!(entity.state.card.confirmed_text, "hello");
        assert_eq!(entity.state.settled.unwrap().intent, create);
        assert_eq!(
            entity.state.card.confirmed_presentation,
            Some(BotItemPresentation::Text {
                revision: 1,
                integrity: BotTextIntegrity::Full,
                saved: true
            })
        );
        use super::super::{CardLifecycle, LegacyLocalCompletion};
        use crate::bots::storage::target::TargetKind;
        let (_directory, store, scope, key) = store_with_legacy_fixture(TargetKind::Group).await?;
        let token = claimed(&store, &scope.key).await;
        let original = store.delivery_entity(&scope.key, &key).await?.unwrap();
        let mut proof = legacy_candidate("truncated preview");
        proof.integrity = BotTextIntegrity::Truncated;
        let mut unrelated = proof.clone();
        unrelated.turn_id = "unrelated-turn".into();
        unrelated.input_chain = super::super::DeliveryInputChain::Proven {
            input_id: "unrelated-input".into(),
            continuation_ancestors: vec![],
        };
        assert_eq!(
            store
                .merge_legacy_delivery_presentation(
                    &token,
                    &key,
                    original.ledger_version,
                    &unrelated
                )
                .await?,
            MergeOutcome::NotCanonical
        );
        assert!(
            store
                .merge_legacy_delivery_presentation(
                    &token,
                    &key,
                    original.ledger_version + 1,
                    &proof
                )
                .await
                .is_err()
        );
        let mut stale = token.clone();
        stale.lease_generation += 1;
        assert_eq!(
            store
                .merge_legacy_delivery_presentation(&stale, &key, original.ledger_version, &proof)
                .await?,
            MergeOutcome::Fenced
        );
        let mut oversized = proof.clone();
        oversized.request_bytes = 30_001;
        assert!(
            store
                .merge_legacy_delivery_presentation(
                    &token,
                    &key,
                    original.ledger_version,
                    &oversized
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&scope.key, &key).await?,
            Some(original.clone())
        );
        store.db().await?.execute_unprepared("CREATE TRIGGER fail_legacy_presentation BEFORE UPDATE OF summary_version ON bot_audience_origins BEGIN SELECT RAISE(ABORT,'controlled legacy presentation fault'); END").await?;
        assert!(
            store
                .merge_legacy_delivery_presentation(&token, &key, original.ledger_version, &proof)
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&scope.key, &key).await?,
            Some(original.clone())
        );
        store
            .db()
            .await?
            .execute_unprepared("DROP TRIGGER fail_legacy_presentation")
            .await?;
        assert_eq!(
            store
                .merge_legacy_delivery_presentation(&token, &key, original.ledger_version, &proof)
                .await?,
            MergeOutcome::Applied { item_revision: 0 }
        );
        let preview = store.delivery_entity(&scope.key, &key).await?.unwrap();
        assert_eq!(
            store
                .merge_legacy_delivery_presentation(&token, &key, preview.ledger_version, &proof)
                .await?,
            MergeOutcome::Unchanged { item_revision: 0 }
        );
        assert_eq!(
            store.delivery_entity(&scope.key, &key).await?,
            Some(preview)
        );
        let create = store
            .register_test_card_intent(
                &token,
                &key,
                DeliveryAction::CreateCard {
                    text: proof.body.clone(),
                },
            )
            .await?;
        assert_eq!(
            (create.content_revision, create.integrity, create.saved),
            (0, BotTextIntegrity::Truncated, false)
        );
        let mut continuation = legacy_candidate("authoritative final");
        continuation.turn_id = "continuation-turn".into();
        continuation.input_chain = super::super::DeliveryInputChain::Proven {
            input_id: "canonical-continuation".into(),
            continuation_ancestors: vec![format!("bot:{BOT}:{CHAT}:old-message")],
        };
        continuation.saved = true;
        let pending = store.delivery_entity(&scope.key, &key).await?.unwrap();
        store
            .merge_legacy_delivery_presentation(&token, &key, pending.ledger_version, &continuation)
            .await?;
        let current = store.delivery_entity(&scope.key, &key).await?.unwrap();
        assert_eq!(current.turn_id, original.turn_id);
        assert_eq!(current.item_order, original.item_order);
        assert_eq!(current.entity, original.entity);
        assert_eq!(current.revision(), 0);
        assert_eq!(current.state.in_flight, Some(create.clone()));
        assert!(
            store
                .settle_legacy_without_card(
                    &token,
                    &key,
                    current.ledger_version,
                    LegacyLocalCompletion::NoFinal
                )
                .await
                .is_err()
        );
        store
            .settle_delivery_card_result(
                &scope.key,
                &key,
                &create.operation_id,
                DeliveryResult::Unknown {
                    diagnostic: Some("create outcome unknown without a card id".into()),
                },
            )
            .await?;
        let no_card_unknown = store.delivery_entity(&scope.key, &key).await?.unwrap();
        assert!(no_card_unknown.state.card.card_id.is_none());
        assert!(
            store
                .settle_legacy_without_card(
                    &token,
                    &key,
                    no_card_unknown.ledger_version,
                    LegacyLocalCompletion::Failed
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&scope.key, &key).await?,
            Some(no_card_unknown)
        );
        store
            .settle_delivery_card_result(
                &scope.key,
                &key,
                &create.operation_id,
                DeliveryResult::Created {
                    card_id: "legacy-card".into(),
                },
            )
            .await?;
        let send = store
            .register_test_card_intent(
                &token,
                &key,
                DeliveryAction::SendCard {
                    card_id: "legacy-card".into(),
                },
            )
            .await?;
        assert_eq!(
            (send.content_revision, send.integrity, send.saved),
            (0, BotTextIntegrity::Truncated, false)
        );
        store
            .settle_delivery_card_result(
                &scope.key,
                &key,
                &send.operation_id,
                DeliveryResult::Sent {
                    card_id: "legacy-card".into(),
                    message_id: "om_legacy".into(),
                },
            )
            .await?;
        let sent = store.delivery_entity(&scope.key, &key).await?.unwrap();
        assert!(
            store
                .settle_legacy_without_card(
                    &token,
                    &key,
                    sent.ledger_version,
                    LegacyLocalCompletion::NoFinal
                )
                .await
                .is_err()
        );
        let update = store
            .register_test_card_intent(
                &token,
                &key,
                DeliveryAction::UpdateContent {
                    card_id: "legacy-card".into(),
                    text: continuation.body.clone(),
                    final_content: true,
                },
            )
            .await?;
        assert_eq!(
            (update.content_revision, update.integrity, update.saved),
            (0, BotTextIntegrity::Full, true)
        );
        store
            .settle_delivery_card_result(
                &scope.key,
                &key,
                &update.operation_id,
                DeliveryResult::Unknown {
                    diagnostic: Some("original update pending".into()),
                },
            )
            .await?;
        let unknown = store.delivery_entity(&scope.key, &key).await?.unwrap();
        assert!(
            store
                .settle_legacy_without_card(
                    &token,
                    &key,
                    unknown.ledger_version,
                    LegacyLocalCompletion::Failed
                )
                .await
                .is_err()
        );
        let mut newer = continuation.clone();
        newer.body = "newer preview".into();
        newer.saved = false;
        newer.integrity = BotTextIntegrity::Truncated;
        store
            .merge_legacy_delivery_presentation(&token, &key, unknown.ledger_version, &newer)
            .await?;
        let newer_state = store.delivery_entity(&scope.key, &key).await?.unwrap();
        assert_eq!(newer_state.state.halt, unknown.state.halt);
        assert_eq!(newer_state.state.settled, unknown.state.settled);
        store
            .settle_delivery_card_result(
                &scope.key,
                &key,
                &update.operation_id,
                DeliveryResult::ContentAccepted {
                    card_id: "legacy-card".into(),
                },
            )
            .await?;
        let cold = BotStateStore::new(_directory.path().join("state.sqlite"));
        cold.db().await?;
        let late = cold.delivery_entity(&scope.key, &key).await?.unwrap();
        assert_eq!(late.turn_id, original.turn_id);
        assert_eq!(late.state.card.confirmed_text, "authoritative final");
        assert_eq!(
            late.state.card.confirmed_presentation,
            Some(BotItemPresentation::Text {
                revision: 0,
                integrity: BotTextIntegrity::Full,
                saved: true
            })
        );
        assert!(
            matches!(&late.state.content, DeliveryContent::Legacy { presentation: Some(p), .. } if p.body == newer.body && !p.saved && p.integrity == BotTextIntegrity::Truncated)
        );

        let local_completions = [
            (LegacyLocalCompletion::NoFinal, CardLifecycle::NoFinalReply),
            (LegacyLocalCompletion::Discarded, CardLifecycle::Cancelled),
            (
                LegacyLocalCompletion::InteractionEnded,
                CardLifecycle::InteractionEnded,
            ),
            (LegacyLocalCompletion::Cancelled, CardLifecycle::Cancelled),
            (LegacyLocalCompletion::Failed, CardLifecycle::Failed),
            (
                LegacyLocalCompletion::BudgetLimited,
                CardLifecycle::BudgetLimited,
            ),
        ];
        for (reason, lifecycle) in local_completions {
            let (directory, store, scope, key) =
                store_with_legacy_fixture(TargetKind::Group).await?;
            let token = claimed(&store, &scope.key).await;
            // 当前开发版10缺少新Option时，只能保守读作None，不造呈现或终局资格。
            store.db().await?.execute_raw(statement("UPDATE bot_delivery_items SET state_json=json_remove(state_json,'$.content.presentation','$.card.legacyLocalCompletion') WHERE scope_key=?", vec![scope.key.storage_key()?.into()])).await?;
            let initial = store.delivery_entity(&scope.key, &key).await?.unwrap();
            assert!(matches!(
                &initial.state.content,
                DeliveryContent::Legacy {
                    presentation: None,
                    ..
                }
            ));
            assert_eq!(initial.state.card.legacy_local_completion, None);
            assert!(
                store
                    .settle_legacy_without_card(&token, &key, initial.ledger_version + 1, reason)
                    .await
                    .is_err()
            );
            let mut stale = token.clone();
            stale.lease_generation += 1;
            assert!(
                store
                    .settle_legacy_without_card(&stale, &key, initial.ledger_version, reason)
                    .await
                    .is_err()
            );
            if reason == LegacyLocalCompletion::NoFinal {
                store.db().await?.execute_unprepared("CREATE TRIGGER fail_legacy_completion BEFORE UPDATE OF summary_version ON bot_audience_origins BEGIN SELECT RAISE(ABORT,'controlled local completion fault'); END").await?;
                assert!(
                    store
                        .settle_legacy_without_card(&token, &key, initial.ledger_version, reason)
                        .await
                        .is_err()
                );
                assert_eq!(
                    store.delivery_entity(&scope.key, &key).await?,
                    Some(initial.clone())
                );
                store
                    .db()
                    .await?
                    .execute_unprepared("DROP TRIGGER fail_legacy_completion")
                    .await?;
            }
            assert_eq!(
                store
                    .settle_legacy_without_card(&token, &key, initial.ledger_version, reason)
                    .await?,
                SettlementOutcome::Applied
            );
            let cold = BotStateStore::new(directory.path().join("state.sqlite"));
            cold.db().await?;
            let ended = cold.delivery_entity(&scope.key, &key).await?.unwrap();
            assert_eq!(ended.state.card.lifecycle, Some(lifecycle));
            assert_eq!(ended.state.card.legacy_local_completion, Some(reason));
            assert!(!ended.state.has_legacy_network_history());
            assert!(
                ended.state.settled.is_none()
                    && ended.state.in_flight.is_none()
                    && ended.state.halt.is_none()
            );
            assert_eq!(ended.state.accepted, BotItemPresentation::None {});
            assert!(
                cold.delivery_pending(&scope.key, None, 100)
                    .await?
                    .pending
                    .is_empty()
            );
            assert_eq!(
                cold.settle_legacy_without_card(&token, &key, ended.ledger_version, reason)
                    .await?,
                SettlementOutcome::AlreadySettled
            );
            for (different, _) in local_completions {
                if different == reason {
                    continue;
                }
                assert!(
                    cold.settle_legacy_without_card(&token, &key, ended.ledger_version, different)
                        .await
                        .is_err()
                );
            }
            assert_eq!(cold.delivery_entity(&scope.key, &key).await?, Some(ended));
        }
        Ok(())
    }

    fn artifact_metadata(
        revision: u64,
        saved: bool,
        byte_len: u64,
    ) -> crate::studio::TimelineItemMetadata {
        crate::studio::TimelineItemMetadata {
            shell: pl_protocol::ThreadItem::new(
                "artifact-item".into(),
                THREAD.into(),
                "turn-file".into(),
                2,
                revision,
                1,
                1,
                pl_protocol::ThreadItemState::PublicArtifact(
                    pl_protocol::ThreadPublicArtifactItem {
                        publication_id: "publication".into(),
                        tool_call_id: "producer-call".into(),
                        display_name: "original.txt".into(),
                        published_at: 1,
                        resource: pl_protocol::ThreadArtifactResource {
                            id: "original-resource".into(),
                            content_digest: format!("sha256:{}", "a".repeat(64)),
                            byte_len,
                            media_type: "text/plain".into(),
                        },
                    },
                ),
            ),
            fields: vec![],
            saved,
            lifecycle: pl_protocol::TimelineLifecycle::Terminal,
        }
    }

    fn artifact_candidate(artifact: super::super::SavedArtifact) -> DeliveryCandidate {
        DeliveryCandidate {
            entity: artifact.entity_key(),
            turn_id: artifact.turn_id().into(),
            item_order: artifact.item_order(),
            input_chain: super::super::DeliveryInputChain::Proven {
                input_id: "gui-file".into(),
                continuation_ancestors: vec![],
            },
            content: DeliveryCandidateContent::File { artifact },
        }
    }

    async fn persist_file_stages(
        store: &BotStateStore,
        scope: &DeliveryScopeKey,
        entity: &DeliveryEntityKey,
        record: &SendRecord,
    ) -> anyhow::Result<SettlementOutcome> {
        let tx = store.db().await?.begin().await?;
        tx.execute_raw(statement("UPDATE send_operations SET status=?,platform_message_ids=?,segment_facts=? WHERE operation_id=?",vec![record.status.as_str().into(),record.platform_message_ids.join(",").into(),serde_json::to_string(&record.segments)?.into(),record.operation_id.clone().into()])).await?;
        let outcome =
            BotStateStore::settle_delivery_file_result(&tx, scope, entity, &record.operation_id)
                .await?;
        tx.commit().await?;
        Ok(outcome)
    }

    #[tokio::test]
    async fn blocked_artifact_remains_saved_without_pending_or_send_rows() -> anyhow::Result<()> {
        use super::super::{DeliveryFilePreparationBlock as PreparationBlock, SavedArtifact};
        use pl_protocol::studio::{BotFileBlockReason, BotItemPlatform};
        for length in [0, 30_000_001, 50 * 1024 * 1024] {
            let (directory, store) = store_with_frontend().await?;
            let key = DeliveryScopeKey::Frontend {
                authorization: authorization_id(),
            };
            let token = claimed(&store, &key).await;
            let proof = SavedArtifact::from_metadata(&artifact_metadata(1, true, length))?;
            let candidate = artifact_candidate(proof.clone());
            store.merge_delivery_candidate(&token, &candidate).await?;
            let cold = BotStateStore::new(directory.path().join("state.sqlite"));
            cold.db().await?;
            let item = cold
                .delivery_entity(&key, &candidate.entity)
                .await?
                .unwrap();
            assert!(item.saved);
            assert!(
                matches!(&item.state.content,DeliveryContent::File { file } if file.artifact==proof)
            );
            let flags = derive_flags(item.removed, &item.state);
            assert!(flags.attention && !flags.pending() && !flags.delivered && !flags.unknown);
            let gui = cold
                .delivery_observation(&authorization_id(), proof.item_id())
                .await?
                .unwrap();
            assert!(
                matches!(gui.ledger.platform,BotItemPlatform::Blocked { reason } if reason==if length==0 { BotFileBlockReason::EmptyFile } else { BotFileBlockReason::PlatformSizeLimit })
            );
            assert!(
                cold.delivery_pending(&key, None, 100)
                    .await?
                    .pending
                    .is_empty()
            );
            let summary = cold.audience_counts(THREAD, 1).await?.0;
            assert_eq!(
                (
                    summary.pending_items,
                    summary.unknown_operations,
                    summary.incomplete_items
                ),
                (0, 0, 0)
            );
            let count = cold
                .db()
                .await?
                .query_one_raw(statement(
                    "SELECT count(*) AS n FROM send_operations",
                    vec![],
                ))
                .await?
                .unwrap();
            assert_eq!(stored_i64(&count, "n")?, 0);
        }

        let (directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let mut token = claimed(&store, &key).await;
        let artifact = SavedArtifact::from_metadata(&artifact_metadata(1, true, 12))?;
        let candidate = artifact_candidate(artifact.clone());
        store.merge_delivery_candidate(&token, &candidate).await?;
        let initial = store
            .delivery_entity(&key, &candidate.entity)
            .await?
            .unwrap();
        store.release_delivery_claim(&token).await?;
        assert!(
            store
                .block_delivery_file_preparation(
                    &token,
                    &candidate.entity,
                    initial.ledger_version,
                    &artifact,
                    PreparationBlock::SourceUnavailable
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &candidate.entity).await?,
            Some(initial.clone())
        );
        token = claimed(&store, &key).await;
        let different = SavedArtifact::from_metadata(&artifact_metadata(1, true, 13))?;
        let db = store.db().await?;
        let version = audience::load_auth(db, &authorization_id())
            .await?
            .unwrap()
            .delivery_version;
        for (expected, proof) in [
            (initial.ledger_version + 1, &artifact),
            (initial.ledger_version, &different),
        ] {
            assert!(
                store
                    .block_delivery_file_preparation(
                        &token,
                        &candidate.entity,
                        expected,
                        proof,
                        PreparationBlock::SourceUnavailable
                    )
                    .await
                    .is_err()
            );
            assert_eq!(
                store.delivery_entity(&key, &candidate.entity).await?,
                Some(initial.clone())
            );
            assert_eq!(
                audience::load_auth(db, &authorization_id())
                    .await?
                    .unwrap()
                    .delivery_version,
                version
            );
        }
        let other = text_candidate("unrelated item remains live", 1);
        for (revision, reason, platform_reason) in [
            (
                1,
                PreparationBlock::SourceUnavailable,
                BotFileBlockReason::SourceUnavailable,
            ),
            (
                2,
                PreparationBlock::BudgetUnavailable,
                BotFileBlockReason::BudgetUnavailable,
            ),
        ] {
            let proof = SavedArtifact::from_metadata(&artifact_metadata(revision, true, 12))?;
            let current = artifact_candidate(proof.clone());
            store.merge_delivery_candidate(&token, &current).await?;
            let ready = store.delivery_entity(&key, &current.entity).await?.unwrap();
            assert!(ready.state.halt.is_none());
            assert!(derive_flags(ready.removed, &ready.state).pending());
            assert_eq!(
                store
                    .block_delivery_file_preparation(
                        &token,
                        &current.entity,
                        ready.ledger_version,
                        &proof,
                        reason
                    )
                    .await?,
                SettlementOutcome::Applied
            );
            // 当前文件已被阻止后，另一个规范条目仍能在同 scope 合并并进入 pending。
            store.merge_delivery_candidate(&token, &other).await?;
            let cold = BotStateStore::new(directory.path().join("state.sqlite"));
            cold.db().await?;
            let blocked = cold.delivery_entity(&key, &current.entity).await?.unwrap();
            assert!(blocked.saved);
            assert!(
                matches!(&blocked.state.content, DeliveryContent::File { file } if file.artifact == proof)
            );
            assert_eq!(
                blocked.state.halt,
                Some(DeliveryHalt::FilePreparation { revision, reason })
            );
            assert!(!blocked.state.has_network_history());
            let flags = derive_flags(blocked.removed, &blocked.state);
            assert!(flags.attention && !flags.pending() && !flags.delivered && !flags.unknown);
            let gui = cold
                .delivery_observation(&authorization_id(), proof.item_id())
                .await?
                .unwrap();
            assert_eq!(
                gui.ledger.platform,
                BotItemPlatform::Blocked {
                    reason: platform_reason
                }
            );
            assert_eq!(gui.ledger.observed_revision, revision);
            assert_eq!(gui.ledger.accepted, BotItemPresentation::None {});
            assert_eq!(gui.ledger.projected, BotItemPresentation::None {});
            assert!(!gui.pending);
            let pending = cold.delivery_pending(&key, None, 100).await?.pending;
            assert_eq!(pending.len(), 1);
            assert_eq!(pending[0].entity, other.entity);
            let summary = cold.audience_counts(THREAD, 1).await?.0;
            assert_eq!((summary.pending_items, summary.unknown_operations), (1, 0));
            // 同修订观察与同原因重报不复活，也不推进 ledger/观察版本。
            let version = audience::load_auth(db, &authorization_id())
                .await?
                .unwrap()
                .delivery_version;
            assert_eq!(
                store.merge_delivery_candidate(&token, &current).await?,
                MergeOutcome::Unchanged {
                    item_revision: revision
                }
            );
            assert_eq!(
                store
                    .block_delivery_file_preparation(
                        &token,
                        &current.entity,
                        blocked.ledger_version,
                        &proof,
                        reason
                    )
                    .await?,
                SettlementOutcome::AlreadySettled
            );
            let different_reason = match reason {
                PreparationBlock::SourceUnavailable => PreparationBlock::BudgetUnavailable,
                PreparationBlock::BudgetUnavailable => PreparationBlock::SourceUnavailable,
            };
            assert!(
                store
                    .block_delivery_file_preparation(
                        &token,
                        &current.entity,
                        blocked.ledger_version,
                        &proof,
                        different_reason
                    )
                    .await
                    .is_err()
            );
            assert!(
                store
                    .block_delivery_file_preparation(
                        &token,
                        &current.entity,
                        ready.ledger_version,
                        &proof,
                        reason
                    )
                    .await
                    .is_err()
            );
            assert_eq!(
                store.delivery_entity(&key, &current.entity).await?,
                Some(blocked)
            );
            assert_eq!(
                audience::load_auth(db, &authorization_id())
                    .await?
                    .unwrap()
                    .delivery_version,
                version
            );
        }
        // 正常重开与即时写入使用同一严格校验；不能用任意渠道原因或其它内容承载准备失败。
        for expression in [
            "json_set(state_json,'$.halt.revision',0)",
            "json_set(state_json,'$.halt.revision',99)",
            "json_set(state_json,'$.halt.reason','emptyFile')",
        ] {
            let tx = db.begin().await?;
            tx.execute_raw(statement(&format!("UPDATE bot_delivery_items SET state_json={expression} WHERE scope_key=? AND entity_key=?"), vec![key.storage_key()?.into(),candidate.entity.storage_key()?.into()])).await?;
            assert!(super::super::schema::validate(&tx).await.is_err());
            tx.rollback().await?;
        }
        let blocked = store
            .delivery_entity(&key, &candidate.entity)
            .await?
            .unwrap();
        let mut invalid_text = store.delivery_entity(&key, &other.entity).await?.unwrap();
        invalid_text.state.halt = blocked.state.halt.clone();
        let mut invalid_legacy = blocked.clone();
        invalid_legacy.scope = DeliveryScopeKey::LegacyFinal {
            inbound_identity: "original-inbound".into(),
        };
        invalid_legacy.entity = DeliveryEntityKey::LegacyFinal {
            entity_id: "legacy-card".into(),
        };
        invalid_legacy.item_order = None;
        invalid_legacy.state.content = DeliveryContent::Legacy {
            final_only: true,
            presentation: None,
        };
        let mut invalid_unresolved = blocked.clone();
        invalid_unresolved.state.content = DeliveryContent::Unresolved {
            unresolved: super::super::DeliveryUnresolved {
                reason: super::super::DeliveryRecoveryReason::CanonicalUnavailable,
                observation: None,
                removed: false,
                pending: false,
                incomplete: true,
                detail: "unavailable".into(),
            },
        };
        let mut invalid_result = blocked.clone();
        invalid_result.state.accepted = BotItemPresentation::File { revision: 2 };
        for invalid in [
            invalid_text,
            invalid_legacy,
            invalid_unresolved,
            invalid_result,
        ] {
            assert!(super::super::records::validate_entity(&invalid).is_err());
        }
        let next = SavedArtifact::from_metadata(&artifact_metadata(3, true, 12))?;
        store
            .merge_delivery_candidate(&token, &artifact_candidate(next))
            .await?;
        let ready = store
            .delivery_entity(&key, &candidate.entity)
            .await?
            .unwrap();
        assert!(ready.state.halt.is_none());
        assert!(derive_flags(ready.removed, &ready.state).pending());
        assert!(
            store
                .block_delivery_file_preparation(
                    &token,
                    &candidate.entity,
                    ready.ledger_version,
                    &artifact,
                    PreparationBlock::SourceUnavailable
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &candidate.entity).await?,
            Some(ready)
        );
        let empty = SavedArtifact::from_metadata(&artifact_metadata(4, true, 0))?;
        store
            .merge_delivery_candidate(&token, &artifact_candidate(empty.clone()))
            .await?;
        let limited = store
            .delivery_entity(&key, &candidate.entity)
            .await?
            .unwrap();
        assert!(limited.state.halt.is_none());
        assert_eq!(
            store
                .delivery_observation(&authorization_id(), empty.item_id())
                .await?
                .unwrap()
                .ledger
                .platform,
            BotItemPlatform::Blocked {
                reason: BotFileBlockReason::EmptyFile
            }
        );
        assert!(matches!(
            store.renew_delivery_claim(&token).await?,
            DeliveryClaimOutcome::Acquired(_)
        ));
        let mut closed = audience::load_auth(db, &authorization_id()).await?.unwrap();
        closed.phase = BotAuthorizationPhase::Closed;
        closed.closed = Some((pl_protocol::BotAudienceCloseReason::LocalClose, 1));
        closed.revision += 1;
        db.execute_raw(statement("UPDATE bot_authorizations SET phase='closed',control_revision=?,state_json=? WHERE chat_id=? AND generation=1", vec![i64::try_from(closed.revision)?.into(),serde_json::to_string(&closed)?.into(),CHAT.into()])).await?;
        assert!(
            store
                .block_delivery_file_preparation(
                    &token,
                    &candidate.entity,
                    limited.ledger_version,
                    &empty,
                    PreparationBlock::BudgetUnavailable
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&key, &candidate.entity).await?,
            Some(limited)
        );
        let count = db
            .query_one_raw(statement(
                "SELECT count(*) AS n FROM send_operations",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(stored_i64(&count, "n")?, 0);
        super::super::schema::validate(db).await?;
        Ok(())
    }

    #[tokio::test]
    async fn file_binding_requires_saved_producer_and_exact_send_material() -> anyhow::Result<()> {
        use super::super::{SavedArtifact, delivery_file_plan_hash, delivery_file_request_hash};
        use crate::bots::send::{SendContent, SendIdentity};
        use crate::bots::storage::SendSegmentFact;
        for len in [0, 30_000_000, 50 * 1024 * 1024] {
            let local = SavedArtifact::from_metadata(&artifact_metadata(1, true, len))?;
            assert_eq!(
                super::super::file_block_reason(&super::super::DeliveryFile { artifact: local })
                    .is_some(),
                len != 30_000_000
            );
        }
        assert!(SavedArtifact::from_metadata(&artifact_metadata(1, false, 12)).is_err());
        assert!(SavedArtifact::from_metadata(&artifact_metadata(0, true, 12)).is_err());
        let mut streaming = artifact_metadata(1, true, 12);
        streaming.lifecycle = pl_protocol::TimelineLifecycle::Streaming;
        assert!(SavedArtifact::from_metadata(&streaming).is_err());
        let (_directory, store) = store_with_frontend().await?;
        let scope_key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let mut token = claimed(&store, &scope_key).await;
        let scope = store.delivery_scope(&scope_key).await?.unwrap();
        let artifact = SavedArtifact::from_metadata(&artifact_metadata(1, true, 12))?;
        let candidate = artifact_candidate(artifact.clone());
        store.merge_delivery_candidate(&token, &candidate).await?;
        let segments = vec![SendContent::File {
            filename: artifact.display_name().into(),
            upload_filename: artifact.display_name().into(),
            resource: pl_core::context::ResourceReference::new(
                "frozen-copy".into(),
                artifact.resource().content_digest.clone(),
                12,
                "text/plain".into(),
            )?,
        }];
        let operation_id = "file-operation";
        let uuid =
            super::super::typed_digest(&(operation_id, BOT, CHAT, 0_usize))?[7..39].to_string();
        let mut record = SendRecord {
            operation_id: operation_id.into(),
            bot_id: BOT.into(),
            chat_id: CHAT.into(),
            content_hash: delivery_file_plan_hash(
                &scope,
                &candidate.entity,
                &artifact,
                operation_id,
                &segments,
            )?,
            status: SendRecordStatus::Unknown,
            platform_message_ids: vec![],
            segments: vec![SendSegmentFact {
                index: 0,
                uuid,
                status: SendRecordStatus::Unknown,
                platform_message_id: None,
                diagnostic: None,
                content: Some(segments[0].clone()),
                upload: Some(UploadFact::NotStarted),
                message_stage: Some(MessageStage::NotStarted),
                notice_attempt: None,
                platform_diagnostic: None,
                stop_reason: None,
            }],
            facts_complete: true,
            identity: SendIdentity::File {
                request_hash: delivery_file_request_hash(&scope, &candidate.entity, &artifact)?,
            },
            source: None,
        };
        store.claim_send(&record).await?;
        let entity = store
            .delivery_entity(&scope_key, &candidate.entity)
            .await?
            .unwrap();
        // 已有真实 send row 即使尚未绑定，也不能降格为前置准备失败。
        assert!(
            store
                .block_delivery_file_preparation(
                    &token,
                    &candidate.entity,
                    entity.ledger_version,
                    &artifact,
                    super::super::DeliveryFilePreparationBlock::SourceUnavailable
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.delivery_entity(&scope_key, &candidate.entity).await?,
            Some(entity.clone())
        );
        let db = store.db().await?;
        for mutation in [
            "UPDATE send_operations SET bot_id='other-bot'",
            "UPDATE send_operations SET chat_id='other-chat'",
            "UPDATE send_operations SET content_hash='different-plan'",
            "UPDATE send_operations SET send_identity='{\"kind\":\"file\",\"requestHash\":\"wrong\"}'",
            "UPDATE send_operations SET segment_facts=json_set(segment_facts,'$[0].index',1)",
            "UPDATE send_operations SET segment_facts=json_set(segment_facts,'$[0].uuid','wrong')",
            "UPDATE send_operations SET segment_facts=json_set(segment_facts,'$[0].content.filename','other.txt')",
            "UPDATE send_operations SET segment_facts=json_set(segment_facts,'$[0].content.uploadFilename','other.bin')",
            "UPDATE send_operations SET segment_facts=json_set(segment_facts,'$[0].content.resource.byteLen',13)",
            "UPDATE send_operations SET segment_facts=json_set(segment_facts,'$[0].content.resource.contentDigest',?)",
            "UPDATE send_operations SET segment_facts=json_set(segment_facts,'$[0].content.resource.mediaType','application/pdf')",
            "UPDATE send_operations SET segment_facts=json_remove(segment_facts,'$[0].upload')",
            "UPDATE send_operations SET segment_facts=json_remove(segment_facts,'$[0].messageStage')",
        ] {
            let tx = db.begin().await?;
            let values = if mutation.contains('?') {
                vec![format!("sha256:{}", "b".repeat(64)).into()]
            } else {
                vec![]
            };
            tx.execute_raw(statement(mutation, values)).await?;
            assert!(
                BotStateStore::bind_delivery_file_operation(
                    &tx,
                    &token,
                    &candidate.entity,
                    entity.ledger_version,
                    operation_id,
                    &artifact
                )
                .await
                .is_err(),
                "{mutation}"
            );
            tx.rollback().await?;
        }
        let tx = db.begin().await?;
        let tool_source = crate::bots::send::SendSource {
            bot_id: BOT.into(),
            chat_id: CHAT.into(),
            app_id: APP.into(),
            project_id: PROJECT.into(),
            thread_id: THREAD.into(),
            input_id: "tool-input".into(),
            original_input_id: "tool-input".into(),
            message_id: "tool-source-message".into(),
            open_id: String::new(),
            chat_kind: "group".into(),
            creation_id: creation(),
            binding_revision: 1,
        };
        tx.execute_raw(statement(
            "UPDATE send_operations SET send_source=?",
            vec![serde_json::to_string(&tool_source)?.into()],
        ))
        .await?;
        assert!(
            BotStateStore::bind_delivery_file_operation(
                &tx,
                &token,
                &candidate.entity,
                entity.ledger_version,
                operation_id,
                &artifact,
            )
            .await
            .is_err()
        );
        tx.rollback().await?;
        assert_eq!(
            store.delivery_entity(&scope_key, &candidate.entity).await?,
            Some(entity.clone())
        );
        let tx = db.begin().await?;
        BotStateStore::bind_delivery_file_operation(
            &tx,
            &token,
            &candidate.entity,
            entity.ledger_version,
            operation_id,
            &artifact,
        )
        .await?;
        tx.commit().await?;
        use pl_protocol::studio::{
            BotFileBlockReason, BotFileOutcome, BotItemPlatform, BotPlatformResult,
            BotSendStopReason,
        };
        let original_binding = store
            .delivery_entity(&scope_key, &candidate.entity)
            .await?
            .unwrap()
            .state
            .file_operation
            .unwrap();
        let bound = store
            .delivery_entity(&scope_key, &candidate.entity)
            .await?
            .unwrap();
        assert!(
            store
                .block_delivery_file_preparation(
                    &token,
                    &candidate.entity,
                    bound.ledger_version,
                    &artifact,
                    super::super::DeliveryFilePreparationBlock::BudgetUnavailable
                )
                .await
                .is_err()
        );
        let mut invalid = bound.clone();
        invalid.state.halt = Some(DeliveryHalt::FilePreparation {
            revision: artifact.revision(),
            reason: super::super::DeliveryFilePreparationBlock::SourceUnavailable,
        });
        assert!(super::super::records::validate_entity(&invalid).is_err());
        assert_eq!(
            store.delivery_entity(&scope_key, &candidate.entity).await?,
            Some(bound)
        );
        // 场景输入由唯一原账本提供；同步不能把本地失败伪造成平台拒绝。
        record.segments[0].stop_reason = Some(BotSendStopReason::LocalFailure);
        persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?;
        let failed = store
            .delivery_entity(&scope_key, &candidate.entity)
            .await?
            .unwrap();
        assert!(matches!(
            failed.state.halt,
            Some(DeliveryHalt::LocalFailure { .. })
        ));
        assert!(
            store
                .delivery_pending(&scope_key, None, 100)
                .await?
                .pending
                .is_empty()
        );
        let cold = BotStateStore::new(_directory.path().join("state.sqlite"));
        cold.db().await?;
        let gui = cold
            .delivery_observation(&authorization_id(), artifact.item_id())
            .await?
            .unwrap();
        assert!(matches!(
            gui.ledger.platform,
            BotItemPlatform::File {
                upload: BotPlatformResult::NotStarted {},
                message: BotPlatformResult::NotStarted {},
                outcome: BotFileOutcome::Stopped,
                local_stop: Some(BotSendStopReason::LocalFailure),
                ..
            }
        ));
        assert_eq!(
            store.audience_counts(THREAD, 1).await?.0.unknown_operations,
            0
        );
        assert!(matches!(
            store.renew_delivery_claim(&token).await?,
            DeliveryClaimOutcome::Acquired(_)
        ));
        let tx = db.begin().await?;
        assert!(
            BotStateStore::fence_delivery_file_write(&tx, &token, &candidate.entity, operation_id)
                .await
                .is_err()
        );
        tx.rollback().await?;
        // 确定未启动的 Cancelled 保同代义务、UUID 与冻结资源；Pause 仍封新写。
        record.segments[0].stop_reason = Some(BotSendStopReason::Cancelled);
        persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?;
        assert_eq!(
            store
                .delivery_pending(&scope_key, None, 100)
                .await?
                .pending
                .len(),
            1
        );
        let mut auth = audience::load_auth(db, &authorization_id()).await?.unwrap();
        for phase in [BotAuthorizationPhase::Paused, BotAuthorizationPhase::Active] {
            auth.phase = phase;
            auth.revision += 1;
            db.execute_raw(statement("UPDATE bot_authorizations SET phase=?,control_revision=?,state_json=? WHERE chat_id=? AND generation=1",vec![if phase==BotAuthorizationPhase::Paused { "paused".into() } else { "active".into() },i64::try_from(auth.revision)?.into(),serde_json::to_string(&auth)?.into(),CHAT.into()])).await?;
            let tx = db.begin().await?;
            assert!(
                BotStateStore::fence_delivery_file_write(
                    &tx,
                    &token,
                    &candidate.entity,
                    operation_id
                )
                .await
                .is_err()
            );
            tx.rollback().await?;
        }
        store.release_delivery_claim(&token).await?;
        token = claimed(&store, &scope_key).await;
        let tx = db.begin().await?;
        BotStateStore::fence_delivery_file_write(&tx, &token, &candidate.entity, operation_id)
            .await?;
        tx.rollback().await?;
        record.segments[0].upload = Some(UploadFact::Accepted {
            file_key: "upload-key".into(),
        });
        record.segments[0].stop_reason = None;
        let version_before_upload = audience::load_auth(db, &authorization_id())
            .await?
            .unwrap()
            .delivery_version;
        persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?;
        assert!(
            audience::load_auth(db, &authorization_id())
                .await?
                .unwrap()
                .delivery_version
                > version_before_upload,
            "upload-only changes must invalidate GUI observations"
        );
        assert_eq!(
            store
                .delivery_pending(&scope_key, None, 100)
                .await?
                .pending
                .len(),
            1
        );
        assert!(matches!(
            store
                .delivery_observation(&authorization_id(), artifact.item_id())
                .await?
                .unwrap()
                .ledger
                .platform,
            BotItemPlatform::File {
                upload: BotPlatformResult::Accepted {},
                message: BotPlatformResult::NotStarted {},
                outcome: BotFileOutcome::Pending,
                ..
            }
        ));
        assert_eq!(
            store
                .delivery_entity(&scope_key, &candidate.entity)
                .await?
                .unwrap()
                .state
                .accepted,
            BotItemPresentation::None {}
        );
        record.segments[0].stop_reason = Some(BotSendStopReason::Cancelled);
        persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?;
        let tx = db.begin().await?;
        BotStateStore::fence_delivery_file_write(&tx, &token, &candidate.entity, operation_id)
            .await?;
        tx.rollback().await?;
        assert_eq!(
            store
                .delivery_entity(&scope_key, &candidate.entity)
                .await?
                .unwrap()
                .state
                .file_operation,
            Some(original_binding.clone())
        );
        for (upload, message, stop, outcome) in [
            (
                UploadFact::InFlight,
                MessageStage::NotStarted,
                BotSendStopReason::Cancelled,
                BotFileOutcome::Unknown,
            ),
            (
                UploadFact::Rejected,
                MessageStage::NotStarted,
                BotSendStopReason::Cancelled,
                BotFileOutcome::Rejected,
            ),
            (
                UploadFact::Accepted {
                    file_key: "upload-key".into(),
                },
                MessageStage::Rejected,
                BotSendStopReason::LocalFailure,
                BotFileOutcome::Partial,
            ),
        ] {
            record.segments[0].upload = Some(upload);
            record.segments[0].message_stage = Some(message);
            record.segments[0].stop_reason = Some(stop);
            persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?;
            assert!(
                store
                    .delivery_pending(&scope_key, None, 100)
                    .await?
                    .pending
                    .is_empty()
            );
            assert!(
                matches!(store.delivery_observation(&authorization_id(),artifact.item_id()).await?.unwrap().ledger.platform,BotItemPlatform::File { outcome:observed,.. } if observed==outcome)
            );
            let tx = db.begin().await?;
            assert!(
                BotStateStore::fence_delivery_file_write(
                    &tx,
                    &token,
                    &candidate.entity,
                    operation_id
                )
                .await
                .is_err()
            );
            tx.rollback().await?;
        }
        record.segments[0].stop_reason = Some(BotSendStopReason::LocalFailure);
        record.segments[0].upload = Some(UploadFact::Accepted {
            file_key: "upload-key".into(),
        });
        record.segments[0].message_stage = Some(MessageStage::Unknown);
        persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?;
        assert_eq!(
            store.audience_counts(THREAD, 1).await?.0.unknown_operations,
            1
        );
        record.segments[0].upload = Some(UploadFact::Unknown);
        persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?;
        assert_eq!(
            store.audience_counts(THREAD, 1).await?.0.unknown_operations,
            2
        );
        let original_stages = file_stage(
            db,
            &store
                .delivery_entity(&scope_key, &candidate.entity)
                .await?
                .unwrap(),
        )
        .await?;
        // 当前修订被渠道阻止不隐藏为旧操作，也不删除旧操作的真实阶段或保存证明。
        for (revision, length, reason) in [
            (2, 0, BotFileBlockReason::EmptyFile),
            (3, 30_000_001, BotFileBlockReason::PlatformSizeLimit),
        ] {
            let newer = SavedArtifact::from_metadata(&artifact_metadata(revision, true, length))?;
            assert_eq!(
                store
                    .merge_delivery_candidate(&token, &artifact_candidate(newer.clone()))
                    .await?,
                MergeOutcome::Applied {
                    item_revision: revision
                }
            );
            assert_eq!(
                persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?,
                SettlementOutcome::AlreadySettled
            );
            let cold = BotStateStore::new(_directory.path().join("state.sqlite"));
            cold.db().await?;
            let item = cold
                .delivery_entity(&scope_key, &candidate.entity)
                .await?
                .unwrap();
            assert!(item.saved);
            assert!(
                matches!(&item.state.content, DeliveryContent::File { file } if file.artifact == newer)
            );
            assert_eq!(item.state.file_operation, Some(original_binding.clone()));
            assert_eq!(file_stage(cold.db().await?, &item).await?, original_stages);
            let flags = derive_flags(item.removed, &item.state);
            assert!(flags.attention && flags.unknown && !flags.pending() && !flags.delivered);
            let gui = cold
                .delivery_observation(&authorization_id(), artifact.item_id())
                .await?
                .unwrap();
            assert_eq!(gui.ledger.platform, BotItemPlatform::Blocked { reason });
            assert_eq!(gui.ledger.observed_revision, revision);
            assert!(!gui.pending);
            assert!(
                cold.delivery_pending(&scope_key, None, 100)
                    .await?
                    .pending
                    .is_empty()
            );
            let summary = cold.audience_counts(THREAD, 1).await?.0;
            assert_eq!((summary.pending_items, summary.unknown_operations), (0, 2));
            let original = cold.load_send(operation_id).await?.unwrap();
            assert_eq!(original.segments, record.segments);
            assert_eq!(original.content_hash, record.content_hash);
            assert_eq!(original.identity, record.identity);
            let count = cold
                .db()
                .await?
                .query_one_raw(statement(
                    "SELECT count(*) AS n FROM send_operations",
                    vec![],
                ))
                .await?
                .unwrap();
            assert_eq!(stored_i64(&count, "n")?, 1);
        }
        let blocked_content = store
            .delivery_entity(&scope_key, &candidate.entity)
            .await?
            .unwrap()
            .state
            .content;
        record.segments[0].upload = Some(UploadFact::Accepted {
            file_key: "upload-key".into(),
        });
        record.segments[0].message_stage = Some(MessageStage::Accepted);
        record.segments[0].status = SendRecordStatus::Succeeded;
        record.segments[0].platform_message_id = Some("om_file".into());
        record.status = SendRecordStatus::Succeeded;
        record.platform_message_ids = vec!["om_file".into()];
        let mut closed = audience::load_auth(db, &authorization_id()).await?.unwrap();
        closed.phase = BotAuthorizationPhase::Closed;
        closed.closed = Some((pl_protocol::BotAudienceCloseReason::LocalClose, 1));
        closed.revision += 1;
        db.execute_raw(statement("UPDATE bot_authorizations SET phase='closed',control_revision=?,state_json=? WHERE chat_id=? AND generation=1",vec![i64::try_from(closed.revision)?.into(),serde_json::to_string(&closed)?.into(),CHAT.into()])).await?;
        db.execute_unprepared("UPDATE thread_bindings SET status='needs_attention'")
            .await?;
        let tx = db.begin().await?;
        assert!(
            BotStateStore::fence_delivery_file_write(&tx, &token, &candidate.entity, operation_id)
                .await
                .is_err()
        );
        tx.execute_raw(statement("UPDATE send_operations SET status=?,platform_message_ids=?,segment_facts=? WHERE operation_id=?",vec![record.status.as_str().into(),record.platform_message_ids.join(",").into(),serde_json::to_string(&record.segments)?.into(),operation_id.into()])).await?;
        BotStateStore::settle_delivery_file_result(
            &tx,
            &scope_key,
            &candidate.entity,
            operation_id,
        )
        .await?;
        tx.commit().await?;
        let cold = BotStateStore::new(_directory.path().join("state.sqlite"));
        cold.db().await?;
        let observed = cold
            .delivery_observation(&authorization_id(), artifact.item_id())
            .await?
            .unwrap();
        assert_eq!(
            observed.ledger.accepted,
            BotItemPresentation::File { revision: 1 }
        );
        assert_eq!(observed.ledger.observed_revision, 3);
        assert_eq!(
            observed.ledger.platform,
            BotItemPlatform::Blocked {
                reason: BotFileBlockReason::PlatformSizeLimit
            }
        );
        assert!(!observed.pending);
        let current = cold
            .delivery_entity(&scope_key, &candidate.entity)
            .await?
            .unwrap();
        assert!(current.saved);
        assert_eq!(current.state.content, blocked_content);
        assert_eq!(current.state.file_operation, Some(original_binding));
        assert!(current.state.halt.is_none());
        let flags = derive_flags(current.removed, &current.state);
        assert!(flags.attention && !flags.unknown && !flags.pending() && !flags.delivered);
        let original = cold.load_send(operation_id).await?.unwrap();
        assert_eq!(original.segments, record.segments);
        assert_eq!(original.content_hash, record.content_hash);
        assert_eq!(original.identity, record.identity);
        let count = cold
            .db()
            .await?
            .query_one_raw(statement(
                "SELECT count(*) AS n FROM send_operations",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(stored_i64(&count, "n")?, 1);
        assert_eq!(
            audience::load_auth(db, &authorization_id())
                .await?
                .unwrap()
                .phase,
            BotAuthorizationPhase::Closed
        );
        assert_eq!(
            store.audience_counts(THREAD, 1).await?.0.unknown_operations,
            0
        );
        assert_eq!(
            persist_file_stages(&store, &scope_key, &candidate.entity, &record).await?,
            SettlementOutcome::AlreadySettled
        );
        assert!(
            !file_stage(
                db,
                &store
                    .delivery_entity(&scope_key, &candidate.entity)
                    .await?
                    .unwrap()
            )
            .await?
            .unwrap()
            .has_unstarted_stage()
        );
        super::super::schema::validate(db).await?;
        Ok(())
    }

    #[tokio::test]
    async fn route_replacement_fences_writes_but_not_started_results() -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let intent = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        store
            .db()
            .await?
            .execute_unprepared("UPDATE thread_bindings SET thread_id='successor',revision=2")
            .await?;
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("later", 2))
                .await?,
            MergeOutcome::Fenced
        );
        assert_eq!(
            store
                .settle_delivery_card_result(
                    &key,
                    &entity_key(),
                    &intent.operation_id,
                    DeliveryResult::Created {
                        card_id: "card-1".into()
                    }
                )
                .await?,
            SettlementOutcome::Applied
        );
        super::super::schema::validate(store.db().await?).await?;
        Ok(())
    }

    #[tokio::test]
    async fn canonical_revision_checks_all_facts_and_advances_saved_monotonically()
    -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        let mut candidate = text_candidate("hello", 1);
        store.merge_delivery_candidate(&token, &candidate).await?;
        candidate.item_order = 2;
        assert_eq!(
            store.merge_delivery_candidate(&token, &candidate).await?,
            MergeOutcome::Conflict
        );
        candidate.item_order = 1;
        if let DeliveryCandidateContent::Text { channel, .. } = &mut candidate.content {
            *channel = BotPublicTextChannel::Commentary;
        }
        assert_eq!(
            store.merge_delivery_candidate(&token, &candidate).await?,
            MergeOutcome::Conflict
        );
        let mut unsaved = text_candidate("later", 2);
        if let DeliveryCandidateContent::Text { saved, .. } = &mut unsaved.content {
            *saved = false;
        }
        store.merge_delivery_candidate(&token, &unsaved).await?;
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("later", 2))
                .await?,
            MergeOutcome::Applied { item_revision: 2 }
        );
        assert_eq!(
            store.merge_delivery_candidate(&token, &unsaved).await?,
            MergeOutcome::Unchanged { item_revision: 2 }
        );
        let mut different_budget = text_candidate("later", 2);
        if let DeliveryCandidateContent::Text { request_bytes, .. } = &mut different_budget.content
        {
            *request_bytes = 301;
        }
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &different_budget)
                .await?,
            MergeOutcome::Conflict
        );
        let mut different_turn = text_candidate("later", 2);
        different_turn.turn_id = "other-turn".into();
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &different_turn)
                .await?,
            MergeOutcome::Conflict
        );
        let mut removed = text_candidate("", 0);
        removed.content = DeliveryCandidateContent::Removed { revision: 0 };
        assert!(
            store
                .merge_delivery_candidate(&token, &removed)
                .await
                .is_err()
        );
        let mut empty = text_candidate("", 3);
        store.merge_delivery_candidate(&token, &empty).await?;
        let mut over_budget = text_candidate("", 4);
        if let DeliveryCandidateContent::Text { request_bytes, .. } = &mut over_budget.content {
            *request_bytes = 30_001;
        }
        assert!(
            store
                .merge_delivery_candidate(&token, &over_budget)
                .await
                .is_err()
        );
        let mut nonempty_without_budget = text_candidate("not empty", 4);
        if let DeliveryCandidateContent::Text { request_bytes, .. } =
            &mut nonempty_without_budget.content
        {
            *request_bytes = 0;
        }
        assert!(
            store
                .merge_delivery_candidate(&token, &nonempty_without_budget)
                .await
                .is_err()
        );
        empty.content = DeliveryCandidateContent::Text {
            channel: BotPublicTextChannel::Final,
            revision: 4,
            integrity: BotTextIntegrity::Full,
            saved: true,
            body: String::new(),
            request_bytes: 0,
        };
        store.merge_delivery_candidate(&token, &empty).await?;
        assert!(
            !store
                .delivery_entity(&key, &entity_key())
                .await?
                .unwrap()
                .removed
        );
        removed.content = DeliveryCandidateContent::Removed { revision: 4 };
        assert_eq!(
            store.merge_delivery_candidate(&token, &removed).await?,
            MergeOutcome::Conflict
        );
        removed.content = DeliveryCandidateContent::Removed { revision: 5 };
        assert_eq!(
            store.merge_delivery_candidate(&token, &removed).await?,
            MergeOutcome::Applied { item_revision: 5 }
        );
        assert!(
            store
                .delivery_entity(&key, &entity_key())
                .await?
                .unwrap()
                .removed
        );
        assert!(
            store
                .delivery_pending(&key, None, 100)
                .await?
                .pending
                .is_empty()
        );
        Ok(())
    }

    #[tokio::test]
    async fn pause_is_not_a_persistent_stop_and_control_revision_fences_old_claims()
    -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let db = store.db().await?;
        let mut auth = active_authorization();
        auth.phase = BotAuthorizationPhase::Paused;
        auth.revision = 2;
        db.execute_raw(statement(
            "UPDATE bot_authorizations SET phase='paused',control_revision=2,state_json=?",
            vec![serde_json::to_string(&auth)?.into()],
        ))
        .await?;
        assert!(matches!(
            store.claim_delivery_scope(&key, "owner-b").await?,
            DeliveryClaimOutcome::Stopped { .. }
        ));
        auth.phase = BotAuthorizationPhase::Active;
        auth.revision = 3;
        db.execute_raw(statement(
            "UPDATE bot_authorizations SET phase='active',control_revision=3,state_json=?",
            vec![serde_json::to_string(&auth)?.into()],
        ))
        .await?;
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("later", 2))
                .await?,
            MergeOutcome::Fenced
        );
        store.release_delivery_claim(&token).await?;
        let fresh = claimed(&store, &key).await;
        assert_eq!(fresh.authorization_revision, 3);
        assert_eq!(
            store.delivery_pending(&key, None, 100).await?.pending.len(),
            1
        );
        assert_eq!(
            store
                .merge_delivery_candidate(&fresh, &text_candidate("later", 2))
                .await?,
            MergeOutcome::Applied { item_revision: 2 }
        );
        Ok(())
    }

    #[tokio::test]
    async fn recovery_indexes_reject_missing_cursor_and_pending() -> anyhow::Result<()> {
        let (directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let db = store.db().await?;
        let before = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        for corruption in [
            "DELETE FROM bot_delivery_cursors",
            "DELETE FROM bot_delivery_pending",
            "UPDATE bot_delivery_pending SET item_revision=item_revision+1",
            "UPDATE bot_delivery_pending SET item_order=item_order+1",
            "INSERT INTO bot_delivery_pending(scope_key,entity_key,item_order,item_revision,updated_at)
             SELECT scope_key,'orphan-entity',1,1,1 FROM bot_delivery_scopes",
        ] {
            let tx = db.begin().await?;
            // 故障注入允许构造暂时孤儿；正常 writer 不关闭外键，也没有补索引接口。
            tx.execute_unprepared("PRAGMA defer_foreign_keys=ON").await?;
            tx.execute_unprepared(corruption).await?;
            assert!(super::super::schema::validate(&tx).await.is_err(), "{corruption}");
            assert!(read_scope(&tx, &key).await.is_err(), "{corruption}");
            tx.rollback().await?;
            assert_eq!(store.delivery_entity(&key, &entity_key()).await?, Some(before.clone()));
        }
        let tx = db.begin().await?;
        tx.execute_unprepared("PRAGMA defer_foreign_keys=ON")
            .await?;
        tx.execute_unprepared("INSERT INTO bot_delivery_cursors(scope_key,order_watermark,updated_at) VALUES('orphan-scope',0,1)").await?;
        assert!(super::super::schema::validate(&tx).await.is_err());
        tx.rollback().await?;

        let intent = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &intent.operation_id,
                DeliveryResult::Unknown { diagnostic: None },
            )
            .await?;
        let unknown = store.delivery_entity(&key, &entity_key()).await?.unwrap();
        assert!(
            store
                .delivery_pending(&key, None, 100)
                .await?
                .pending
                .is_empty()
        );
        // Unknown 不能因 delivered=0 被额外索引成可重发。冷打开和正常写都须拒绝，
        // 不删除损坏索引来制造“恢复成功”，也不推进实体或 GUI 版本。
        db.execute_unprepared("INSERT INTO bot_delivery_pending(scope_key,entity_key,item_order,item_revision,updated_at)
             SELECT scope_key,entity_key,item_order,item_revision,updated_at FROM bot_delivery_items").await?;
        let version = summary_version(&store).await?;
        assert!(super::super::schema::validate(db).await.is_err());
        assert!(store.delivery_pending(&key, None, 100).await.is_err());
        assert!(store.delivery_cursor(&key).await.is_err());
        assert!(
            store
                .merge_delivery_candidate(&token, &text_candidate("later", 2))
                .await
                .is_err()
        );
        assert!(
            store
                .claim_delivery_scope(&key, "replacement-owner")
                .await
                .is_err()
        );
        let row = db
            .query_one_raw(statement(
                "SELECT * FROM bot_delivery_items WHERE scope_key=? AND entity_key=?",
                vec![
                    key.storage_key()?.into(),
                    entity_key().storage_key()?.into(),
                ],
            ))
            .await?
            .unwrap();
        assert_eq!(decode_entity_row(&key, &row)?, unknown);
        assert_eq!(summary_version(&store).await?, version);
        let cold = BotStateStore::new(directory.path().join("state.sqlite"));
        assert!(cold.db().await.is_err());
        let row = db
            .query_one_raw(statement(
                "SELECT count(*) AS n FROM bot_delivery_pending",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(stored_i64(&row, "n")?, 1);
        Ok(())
    }

    #[tokio::test]
    async fn authorization_close_fences_new_writes() -> anyhow::Result<()> {
        let (_directory, store) = store_with_frontend().await?;
        let key = DeliveryScopeKey::Frontend {
            authorization: authorization_id(),
        };
        let token = claimed(&store, &key).await;
        store
            .merge_delivery_candidate(&token, &text_candidate("hello", 1))
            .await?;
        let intent = store
            .register_test_card_intent(
                &token,
                &entity_key(),
                DeliveryAction::CreateCard {
                    text: "hello".into(),
                },
            )
            .await?;
        let db = store.db().await?;
        let mut closed = audience::load_auth(db, &authorization_id()).await?.unwrap();
        let delivery_version = closed.delivery_version;
        closed.revision = 2;
        closed.phase = BotAuthorizationPhase::Closed;
        closed.start = None;
        closed.closed = Some((pl_protocol::BotAudienceCloseReason::LocalClose, 1));
        db.execute_raw(statement(
            "UPDATE bot_authorizations SET phase='closed',control_revision=2,state_json=? WHERE chat_id=? AND generation=1",
            vec![
                serde_json::to_string(&closed)?.into(),
                CHAT.into(),
            ],
        ))
        .await?;
        assert_eq!(
            store.renew_delivery_claim(&token).await?,
            DeliveryClaimOutcome::Stopped {
                reason: "delivery scope is stopped".to_string()
            }
        );
        assert!(matches!(
            store.claim_delivery_scope(&key, "owner-b").await?,
            DeliveryClaimOutcome::Stopped { .. }
        ));
        assert_eq!(
            store
                .merge_delivery_candidate(&token, &text_candidate("hello", 1))
                .await?,
            MergeOutcome::Fenced
        );
        // 冷读取仍然可用并如实反映关闭的授权，不初始化、不重迁。
        let scope = store
            .delivery_scope(&key)
            .await?
            .expect("scope remains readable");
        assert!(!scope.needs_recovery);
        store
            .settle_delivery_card_result(
                &key,
                &entity_key(),
                &intent.operation_id,
                DeliveryResult::Created {
                    card_id: "late-card".into(),
                },
            )
            .await?;
        let after = audience::load_auth(db, &authorization_id()).await?.unwrap();
        assert_eq!(after.phase, BotAuthorizationPhase::Closed);
        assert_eq!(after.revision, 2);
        assert!(after.delivery_version > delivery_version);
        Ok(())
    }
}
